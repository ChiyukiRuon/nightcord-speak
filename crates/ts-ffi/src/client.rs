//! The worker task that owns the Rust core.
//!
//! Two properties of `ts_core::Client` make a direct C ABI impossible:
//!
//! 1. Every action takes `&mut self` and is `async`. A synchronous C call
//!    would have to `block_on`, and `connect` takes seconds — blocking Dart's
//!    UI thread for that long is not an option.
//! 2. It has no interior mutability, so it cannot simply be locked and shared.
//!
//! So it is moved into one task and reached through a command channel, the same
//! shape `ts-protocol-ts3` uses for `tsclientlib`. Commands return immediately;
//! outcomes arrive on the event queue.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use tokio::sync::broadcast::error::RecvError;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use ts_audio::{FRAME_MS, VoiceEngine};
use ts_core::Client as CoreClient;
use ts_model::{ClientError, NetworkError, SessionId, VoiceActivationSettings, VoiceState};

use crate::command::Command;
use crate::event::FfiEvent;

/// How long a clean shutdown may take before the task is abandoned.
const SHUTDOWN_GRACE: Duration = Duration::from_secs(3);

/// How many events may queue before the oldest are dropped.
///
/// The front-end polls on a timer, so in normal use this is never approached.
/// It exists so a front-end that stops polling — or never starts — cannot grow
/// the core's memory without bound.
const MAX_QUEUED_EVENTS: usize = 4096;

/// What the queue holds, plus a count of anything it had to discard.
#[derive(Debug, Default)]
struct QueueState {
    events: VecDeque<FfiEvent>,
    /// Dropped since the last drain, reported once on the next poll rather than
    /// one marker per discarded event.
    dropped: u64,
}

/// The queue the worker fills and [`NightcordClient::poll_events`] drains.
///
/// A plain mutex is right here: pushes are short and rare next to the audio
/// callback, and the only other contender is the thread calling `poll`.
#[derive(Debug, Clone, Default)]
pub(crate) struct EventQueue {
    inner: Arc<Mutex<QueueState>>,
}

impl EventQueue {
    fn lock(&self) -> MutexGuard<'_, QueueState> {
        // A poisoned lock means a previous holder panicked mid-push; the queue
        // itself is still consistent, and losing it would silently stop all
        // events, so recover rather than propagate.
        self.inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub(crate) fn push(&self, event: FfiEvent) {
        let mut state = self.lock();
        if state.events.len() >= MAX_QUEUED_EVENTS {
            state.events.pop_front();
            state.dropped += 1;
        }
        state.events.push_back(event);
    }

    /// Drains everything queued, as a JSON array.
    ///
    /// Anything discarded for lack of room is reported first, as a `lagged`
    /// envelope, so the front-end can resynchronise rather than quietly
    /// rendering a stale tree.
    pub(crate) fn drain_json(&self) -> String {
        let (drained, dropped) = {
            let mut state = self.lock();
            let dropped = std::mem::take(&mut state.dropped);
            (state.events.drain(..).collect::<Vec<FfiEvent>>(), dropped)
        };

        let batch = if dropped > 0 {
            // Rebuilt rather than pushed: the queue was emptied above, and
            // mutating it again would race a concurrent push.
            let mut batch = Vec::with_capacity(drained.len() + 1);
            batch.push(FfiEvent::Lagged { missed: dropped });
            batch.extend(drained);
            batch
        } else {
            drained
        };

        // Serialising `FfiEvent` cannot fail: every field is plain data.
        serde_json::to_string(&batch).unwrap_or_else(|error| {
            tracing::error!(%error, "could not serialise the event batch");
            "[]".to_string()
        })
    }

    /// How many events are waiting, for tests and diagnostics.
    #[must_use]
    pub(crate) fn len(&self) -> usize {
        self.lock().events.len()
    }
}

/// The voice engine and the session it feeds.
struct Voice {
    session: SessionId,
    engine: VoiceEngine,
    /// Set after the first send failure, so a persistent refusal (deafened
    /// clients cannot transmit) does not emit an event every 20 ms.
    reported_failure: bool,
}

/// One `NightcordClient` per Flutter app.
pub struct NightcordClient {
    /// Kept alive for the object's lifetime; dropping it stops every task.
    runtime: tokio::runtime::Runtime,
    commands: mpsc::UnboundedSender<Command>,
    events: EventQueue,
    worker: Mutex<Option<JoinHandle<()>>>,
}

impl NightcordClient {
    /// Starts the runtime and the worker task.
    ///
    /// # Errors
    ///
    /// Returns [`ClientError::Identity`] when the platform gives no application
    /// data directory for identities — Android and iOS, which must supply their
    /// sandbox path — or a network error if the runtime cannot be built.
    pub fn new() -> Result<Self, ClientError> {
        let core = CoreClient::with_platform_store()?;

        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            // The audio callback lives on a cpal thread, not here, so two is
            // plenty: one for the worker loop, one for network tasks.
            .thread_name("nightcord")
            .enable_all()
            .build()
            .map_err(|error| ClientError::Network(NetworkError::new(error.to_string())))?;

        let events = EventQueue::default();
        let (commands, receiver) = mpsc::unbounded_channel();

        let worker = runtime.spawn(run(core, receiver, events.clone()));

        tracing::info!("nightcord core started");
        Ok(Self {
            runtime,
            commands,
            events,
            worker: Mutex::new(Some(worker)),
        })
    }

    /// Queues a command.
    ///
    /// Returns `false` when the worker is gone, which means the client was
    /// already destroyed; the caller should not treat that as a normal failure.
    pub(crate) fn send(&self, command: Command) -> bool {
        match self.commands.send(command) {
            Ok(()) => true,
            Err(error) => {
                tracing::warn!(
                    command = error.0.name(),
                    "the worker is gone; command dropped"
                );
                false
            }
        }
    }

    /// Queues a failure that never reached the worker.
    ///
    /// A malformed argument is rejected in the entry point, but the UI must see
    /// the same `CommandResult` shape it would for any other failure — an error
    /// that vanishes because it was caught early is the worst kind.
    pub fn report_failure(&self, command: &str, error: ts_model::ClientError) {
        self.events.push(FfiEvent::failed(command, None, error));
    }

    /// Drains queued events as a JSON array.
    #[must_use]
    pub fn poll_events(&self) -> String {
        self.events.drain_json()
    }

    /// Number of events waiting, for tests.
    #[must_use]
    pub fn pending_events(&self) -> usize {
        self.events.len()
    }

    /// Stops the worker and waits briefly for it to finish.
    ///
    /// Sessions are disconnected on the way out, so the server does not hold a
    /// stale client — TS3 refuses a second connection from the same identity
    /// until it times out.
    pub fn shutdown(&mut self) {
        let _ = self.commands.send(Command::Shutdown);

        let worker = self
            .worker
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();

        if let Some(worker) = worker {
            let finished = self
                .runtime
                .block_on(async { tokio::time::timeout(SHUTDOWN_GRACE, worker).await.is_ok() });
            if !finished {
                tracing::warn!("the worker did not stop in time; abandoning it");
            }
        }

        tracing::info!("nightcord core stopped");
    }
}

impl Drop for NightcordClient {
    fn drop(&mut self) {
        self.shutdown();
    }
}

impl std::fmt::Debug for NightcordClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NightcordClient")
            .field("pending_events", &self.pending_events())
            .finish_non_exhaustive()
    }
}

/// The worker loop.
async fn run(
    mut core: CoreClient,
    mut commands: mpsc::UnboundedReceiver<Command>,
    events: EventQueue,
) {
    // Subscribed before anything can be commanded, so the handshake burst is
    // never missed.
    let mut subscription = core.subscribe();
    let mut voice: Option<Voice> = None;
    // What the user has asked for, held outside `voice` because it has to
    // outlive the engine not existing yet — see `set_muted`.
    let mut voice_intent = VoiceState::default();

    let mut ticker = tokio::time::interval(Duration::from_millis(u64::from(FRAME_MS)));
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    // `interval` fires immediately; consume it so the first transmitted frame is
    // a frame's duration away rather than instantaneous.
    ticker.tick().await;

    loop {
        tokio::select! {
            command = commands.recv() => match command {
                Some(command) if command.is_shutdown() => break,
                Some(command) => {
                    handle(command, &mut core, &mut voice, &mut voice_intent, &events).await;
                }
                // Every sender was dropped, which happens only on teardown.
                None => break,
            },

            received = subscription.recv() => match received {
                Ok(event) => events.push(FfiEvent::client(event.session, event.event)),
                // Reported, not swallowed: a UI that silently misses
                // `ChannelRemoved` keeps drawing a channel that is gone.
                Err(RecvError::Lagged(missed)) => events.push(FfiEvent::Lagged { missed }),
                Err(RecvError::Closed) => {}
            },

            _ = ticker.tick(), if voice.is_some() => {
                pump_voice(&mut core, &mut voice, &events).await;
            }
        }
    }

    // Leaving sessions open would have the server hold a client for this
    // identity until it times out.
    if let Err(error) = core.disconnect_all().await {
        tracing::warn!(%error, "a session did not close cleanly during shutdown");
    }
    tracing::debug!("nightcord worker stopped");
}

/// The error for addressing a session that has gone away.
fn no_such_session() -> ClientError {
    ClientError::Network(NetworkError::new("no such session"))
}

/// Runs an action against one session, or fails if it is gone.
///
/// A macro rather than a helper taking an async closure: an async block that
/// borrows its argument cannot satisfy `FnOnce(&mut Session) -> Fut`, because
/// that needs a higher-ranked lifetime no closure can express. Written out, each
/// call site would be a five-line match.
macro_rules! with_session {
    ($core:expr, $session:expr, $session_ref:ident => $body:expr) => {
        match $core.sessions_mut().get_mut($session) {
            Some($session_ref) => $body.await,
            None => Err(no_such_session()),
        }
    };
}

/// Runs one command and reports its outcome.
async fn handle(
    command: Command,
    core: &mut CoreClient,
    voice: &mut Option<Voice>,
    voice_intent: &mut VoiceState,
    events: &EventQueue,
) {
    let name = command.name();

    match command {
        Command::Connect(request) => match core.connect(&request).await {
            // The session handle is the result, which is how the UI learns the
            // id it will address everything else by.
            Ok(session) => events.push(FfiEvent::ok(name, Some(session))),
            Err(error) => events.push(FfiEvent::failed(name, None, error)),
        },

        Command::Disconnect { session } => {
            report(events, name, Some(session), core.disconnect(session).await);
        }

        Command::JoinChannel {
            session,
            channel_id,
        } => {
            let outcome = with_session!(core, session, s => s.join_channel(channel_id));
            report(events, name, Some(session), outcome);
        }

        Command::LeaveChannel { session } => {
            let outcome = with_session!(core, session, s => s.leave_channel());
            report(events, name, Some(session), outcome);
        }

        Command::SendMessage {
            session,
            target,
            text,
        } => {
            let outcome = with_session!(core, session, s => s.send_text(target, &text));
            report(events, name, Some(session), outcome);
        }

        Command::MoveClient {
            session,
            client_id,
            channel_id,
        } => {
            let outcome = with_session!(core, session, s => s.move_client(client_id, channel_id));
            report(events, name, Some(session), outcome);
        }

        Command::ListDevices { direction } => match crate::audio::list(direction) {
            Ok(devices) => {
                // The direction goes back with the list so the UI can tell which
                // request it is answering.
                let data = serde_json::json!({
                    "direction": direction.as_str(),
                    "devices": devices,
                });
                events.push(FfiEvent::with_data(name, None, data));
            }
            Err(error) => {
                events.push(FfiEvent::failed(name, None, ClientError::Audio(error)));
            }
        },

        Command::VoiceStart {
            session,
            input,
            output,
        } => {
            start_voice(core, voice, voice_intent, session, input, output, events).await;
        }

        Command::VoiceStop => {
            // Dropping the engine stops the streams and releases the devices.
            let was_bound = voice.take().map(|active| active.session);
            events.push(FfiEvent::ok(name, was_bound));
        }

        Command::VoiceSetMode { mode } => {
            // Recorded even with no engine, so the choice survives until voice
            // starts — same reasoning as `set_muted`.
            voice_intent.mode = mode;
            if let Some(active) = voice.as_mut() {
                active.engine.set_mode(mode);
                // Tell the server too, so other clients can see the change
                // rather than inferring it from silence.
                let state = active.engine.state();
                let session = active.session;
                let outcome = with_session!(core, session, s => s.set_voice_state(state));
                if let Err(error) = outcome {
                    tracing::debug!(%error, "could not tell the server about the voice mode");
                }
            }
            events.push(FfiEvent::ok(
                name,
                voice.as_ref().map(|active| active.session),
            ));
        }

        Command::VoiceSetInputMuted { muted } => {
            set_muted(core, voice, voice_intent, events, name, muted, true).await;
        }

        Command::VoiceSetOutputMuted { muted } => {
            set_muted(core, voice, voice_intent, events, name, muted, false).await;
        }

        Command::VoicePushToTalk { held } => {
            if let Some(active) = voice.as_mut() {
                active.engine.set_push_to_talk(held);
            }
            // Too frequent to report: this fires on every key press (§30).
        }

        Command::Shutdown => unreachable!("filtered by the caller"),
    }
}

/// Applies a mute change and tells the server.
///
/// The change is recorded as *intent* first, so muting before voice is started
/// works. It used to report [`AudioError::NoInputDevice`] in that case, which
/// was both wrong — there is nothing the matter with the device — and useless,
/// since the user had simply clicked the button before opening one.
async fn set_muted(
    core: &mut CoreClient,
    voice: &mut Option<Voice>,
    voice_intent: &mut VoiceState,
    events: &EventQueue,
    name: &str,
    muted: bool,
    is_input: bool,
) {
    if is_input {
        voice_intent.input_muted = muted;
    } else {
        voice_intent.output_muted = muted;
    }

    let Some(active) = voice.as_mut() else {
        // No engine yet. The preference is remembered and applied by
        // `start_voice`; nothing failed, so nothing is reported as failing.
        events.push(FfiEvent::ok(name, None));
        return;
    };

    if is_input {
        active.engine.set_input_muted(muted);
    } else {
        active.engine.set_output_muted(muted);
    }

    // The server is told as well, so other clients can grey out the speaker
    // rather than receiving silence.
    let state = active.engine.state();
    let session = active.session;
    let outcome = with_session!(core, session, s => s.set_voice_state(state));
    if let Err(error) = outcome {
        tracing::debug!(%error, "could not tell the server about the mute change");
    }

    events.push(FfiEvent::ok(name, Some(session)));
}

/// Builds a voice engine, wires it to `session`, and starts it.
#[allow(clippy::too_many_arguments)]
async fn start_voice(
    core: &mut CoreClient,
    voice: &mut Option<Voice>,
    intent: &VoiceState,
    session: SessionId,
    input: Option<String>,
    output: Option<String>,
    events: &EventQueue,
) {
    const NAME: &str = "voice_start";

    // An engine already bound elsewhere is stopped first: two capture streams
    // on one microphone is not something the OS will allow anyway, and holding
    // the old one would keep the device busy.
    *voice = None;

    let Some(session_ref) = core.sessions_mut().get_mut(session) else {
        events.push(FfiEvent::failed(
            NAME,
            Some(session),
            ClientError::Network(NetworkError::new("no such session")),
        ));
        return;
    };

    let mut engine = match VoiceEngine::new(VoiceActivationSettings::default()) {
        Ok(engine) => engine,
        Err(error) => {
            events.push(FfiEvent::failed(
                NAME,
                Some(session),
                ClientError::Audio(error),
            ));
            return;
        }
    };

    if let Err(error) = engine.open_devices(input.as_deref(), output.as_deref()) {
        // Only reported when *both* sides failed; a single missing device is
        // survivable and `input_available`/`output_available` describe it.
        events.push(FfiEvent::failed(
            NAME,
            Some(session),
            ClientError::Audio(error),
        ));
        return;
    }

    // Adopt what the user asked for before there was an engine, so a mute or a
    // transmission mode chosen earlier is not silently forgotten.
    engine.set_input_muted(intent.input_muted);
    engine.set_output_muted(intent.output_muted);
    engine.set_mode(intent.mode);

    // The speakers are wired straight to the session, so decoded audio never
    // crosses the ABI.
    if let Some(sink) = engine.sink() {
        session_ref.set_audio_sink(sink);
    }

    let data = serde_json::json!({
        "input": engine.input_available(),
        "output": engine.output_available(),
    });

    *voice = Some(Voice {
        session,
        engine,
        reported_failure: false,
    });
    events.push(FfiEvent::with_data(NAME, Some(session), data));
}

/// Drains the engine and sends whatever it produced.
async fn pump_voice(core: &mut CoreClient, voice: &mut Option<Voice>, events: &EventQueue) {
    let Some(active) = voice.as_mut() else {
        return;
    };

    let frames = match active.engine.poll() {
        Ok(frames) => frames,
        Err(error) => {
            // One frame failed to encode; the rest of the batch is still in
            // `frames`, but a broken encoder is worth surfacing once.
            tracing::warn!(%error, "a voice frame could not be encoded");
            return;
        }
    };
    if frames.is_empty() {
        return;
    }

    let session_id = active.session;
    let Some(session) = core.sessions_mut().get_mut(session_id) else {
        // The session is gone, so voice has nothing to feed. Stopping beats
        // logging this every 20 ms.
        tracing::info!(session = %session_id, "the voice session ended; stopping voice");
        *voice = None;
        return;
    };

    for packet in frames {
        match session.send_voice(packet).await {
            Ok(()) => active.reported_failure = false,
            Err(error) => {
                // Deafened clients cannot transmit, so this repeats every frame
                // while that lasts. Report it once per run of failures.
                if !active.reported_failure {
                    active.reported_failure = true;
                    tracing::info!(%error, "the server refused a voice frame");
                    events.push(FfiEvent::failed("voice_send", Some(session_id), error));
                }
                break;
            }
        }
    }
}

/// Pushes the outcome of a plain `Result<(), _>` action.
fn report(
    events: &EventQueue,
    name: &str,
    session: Option<SessionId>,
    outcome: Result<(), ClientError>,
) {
    match outcome {
        Ok(()) => events.push(FfiEvent::ok(name, session)),
        Err(error) => events.push(FfiEvent::failed(name, session, error)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_queue_drains_to_an_empty_array() {
        let queue = EventQueue::default();
        assert_eq!(queue.drain_json(), "[]");
    }

    #[test]
    fn draining_takes_everything_queued_exactly_once() {
        let queue = EventQueue::default();
        queue.push(FfiEvent::ok("connect", Some(SessionId::new(1))));
        queue.push(FfiEvent::Lagged { missed: 3 });

        let first: serde_json::Value =
            serde_json::from_str(&queue.drain_json()).expect("valid JSON");
        assert_eq!(first.as_array().map(Vec::len), Some(2));
        assert_eq!(queue.len(), 0, "the queue must be empty after draining");

        assert_eq!(queue.drain_json(), "[]", "a second drain yields nothing");
    }

    #[test]
    fn the_queue_is_bounded_and_reports_what_it_dropped() {
        // A front-end that stops polling must not grow the core without bound,
        // and must be told it missed something rather than shown a stale tree.
        let queue = EventQueue::default();
        for i in 0..(MAX_QUEUED_EVENTS + 10) {
            queue.push(FfiEvent::Lagged { missed: i as u64 });
        }
        assert_eq!(
            queue.len(),
            MAX_QUEUED_EVENTS,
            "the queue grew past its cap"
        );

        let batch: Vec<serde_json::Value> =
            serde_json::from_str(&queue.drain_json()).expect("valid JSON");
        assert_eq!(
            batch.len(),
            MAX_QUEUED_EVENTS + 1,
            "expected the drop marker too"
        );
        assert_eq!(batch[0]["kind"], "lagged");
        assert_eq!(batch[0]["missed"], 10, "ten were discarded");
    }

    #[test]
    fn the_drop_marker_is_reported_once_not_per_event() {
        let queue = EventQueue::default();
        for _ in 0..(MAX_QUEUED_EVENTS + 5) {
            queue.push(FfiEvent::ok("x", None));
        }

        let first: Vec<serde_json::Value> = serde_json::from_str(&queue.drain_json()).unwrap();
        assert_eq!(first.iter().filter(|e| e["kind"] == "lagged").count(), 1);

        // And the count does not carry over into the next batch.
        queue.push(FfiEvent::ok("y", None));
        let second: Vec<serde_json::Value> = serde_json::from_str(&queue.drain_json()).unwrap();
        assert_eq!(
            second.len(),
            1,
            "the drop marker leaked into the next batch"
        );
    }

    #[test]
    fn the_batch_is_an_array_so_dart_can_iterate_without_a_special_case() {
        let queue = EventQueue::default();
        queue.push(FfiEvent::ok("x", None));
        let parsed: serde_json::Value = serde_json::from_str(&queue.drain_json()).unwrap();
        assert!(parsed.is_array());
    }

    #[test]
    fn a_client_reports_no_events_before_anything_happens() {
        let client = NightcordClient::new().expect("start the core");
        assert_eq!(client.pending_events(), 0);
        assert_eq!(client.poll_events(), "[]");
    }

    #[test]
    fn shutting_down_twice_is_harmless() {
        // `Drop` calls `shutdown`, so any explicit call must leave it idempotent.
        let mut client = NightcordClient::new().expect("start the core");
        client.shutdown();
        client.shutdown();
    }

    #[test]
    fn a_command_sent_after_shutdown_is_refused_rather_than_panicking() {
        let mut client = NightcordClient::new().expect("start the core");
        client.shutdown();
        assert!(!client.send(Command::VoiceStop));
    }

    /// Polls until a command reports back, returning the batch that carried it.
    ///
    /// The batch comes back rather than a `bool` because draining happens here:
    /// a second `poll_events` would find nothing.
    fn wait_for_batch(client: &NightcordClient, command: &str, within: Duration) -> Option<String> {
        let deadline = std::time::Instant::now() + within;
        while std::time::Instant::now() < deadline {
            let batch = client.poll_events();
            if batch.contains(command) {
                return Some(batch);
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        None
    }

    /// Whether a command reported back in time.
    fn wait_for(client: &NightcordClient, command: &str, within: Duration) -> bool {
        wait_for_batch(client, command, within).is_some()
    }

    #[test]
    fn muting_before_voice_starts_succeeds() {
        // Clicking mute or deafen before 「start voice」 used to answer with
        // `NoInputDevice`: a wrong explanation for a button the user was
        // entitled to press, and it showed up as a red error banner.
        let client = NightcordClient::new().expect("start the core");

        for command in ["voice_set_input_muted", "voice_set_output_muted"] {
            match command {
                "voice_set_input_muted" => client.send(Command::VoiceSetInputMuted { muted: true }),
                _ => client.send(Command::VoiceSetOutputMuted { muted: true }),
            };

            let batch = wait_for_batch(&client, command, Duration::from_secs(5))
                .unwrap_or_else(|| panic!("`{command}` went unanswered"));

            assert!(
                batch.contains("\"status\":\"ok\""),
                "muting without an engine must succeed, got {batch}"
            );
            assert!(
                !batch.contains("no_input_device"),
                "the failure should not claim a device problem: {batch}"
            );
        }
    }

    #[test]
    fn choosing_a_mode_before_voice_starts_succeeds() {
        // Same reasoning: the choice is a preference and is applied when the
        // engine starts.
        let client = NightcordClient::new().expect("start the core");
        client.send(Command::VoiceSetMode {
            mode: ts_model::VoiceActivationMode::PushToTalk,
        });

        let batch = wait_for_batch(&client, "voice_set_mode", Duration::from_secs(5))
            .expect("voice_set_mode went unanswered");

        assert!(batch.contains("\"status\":\"ok\""), "got {batch}");
    }

    #[test]
    fn the_worker_answers_a_device_query() {
        // Reproduces the Dart path exactly: the command goes through the
        // channel and the answer comes back on the event queue. Enumeration
        // touches real hardware, so the window is generous.
        let client = NightcordClient::new().expect("start the core");
        client.send(Command::ListDevices {
            direction: crate::audio::AudioDirection::Output,
        });

        let answered = wait_for(&client, "audio_devices", Duration::from_secs(15));
        let batch = client.poll_events();
        assert!(
            answered,
            "the worker never answered; last batch was {batch:?}"
        );
    }

    #[test]
    fn the_worker_survives_a_device_query() {
        // If enumeration panicked the task, later commands would go unanswered
        // and every subsequent result would vanish silently.
        let client = NightcordClient::new().expect("start the core");

        client.send(Command::ListDevices {
            direction: crate::audio::AudioDirection::Input,
        });
        assert!(
            wait_for(&client, "audio_devices", Duration::from_secs(15)),
            "the first query went unanswered"
        );

        // A second, cheap command proves the worker is still looping.
        client.send(Command::VoiceStop);
        assert!(
            wait_for(&client, "voice_stop", Duration::from_secs(5)),
            "the worker stopped answering after a device query"
        );
    }
}
