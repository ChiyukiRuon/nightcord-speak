//! Headless Nightcord Speak client — Milestone 0.1.
//!
//! Connects to a real TeamSpeak server, prints what it finds, and then streams
//! events until interrupted. It exists to prove the core works before any UI
//! depends on it (§81, §82): if this cannot hold a connection and render the
//! channel tree, no amount of Flutter will help.

mod audio;
mod view;

use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use clap::Parser;
use tokio::sync::broadcast::Receiver;
use tokio::sync::broadcast::error::RecvError;
use ts_core::{Client, ConnectRequest};
use ts_events::{ClientEvent, SessionEvent};
use ts_identity::IdentityStore;
use ts_model::{ChannelId, MessageTarget, ProtocolKind, SessionId, VoiceActivationSettings};
use ts_protocol::AudioSink;
use ts_settings::{BookmarkStore, SettingsStore};

use crate::audio::AudioReport;
use crate::view::View;

/// How long the server must stay quiet before the first snapshot is complete.
///
/// The first render has to wait for the whole handshake burst; waiting for a
/// gap is more robust than guessing a fixed delay.
const SETTLE: Duration = Duration::from_millis(400);

#[derive(Parser, Debug)]
#[command(
    name = "nightcord-cli",
    about = "Headless Nightcord Speak client",
    version
)]
struct Args {
    /// Server address: `host`, `host:port`, `ts3://host` or `[::1]:9987`.
    #[arg(short, long)]
    address: String,

    /// Nickname to appear under.
    #[arg(short, long, default_value = "Nightcord CLI")]
    nickname: String,

    /// Identity profile. The same profile presents the same client to every
    /// server, which is what a user expects of "their" identity.
    #[arg(long, default_value = "default")]
    profile: String,

    /// Password for the server itself.
    #[arg(long, env = "TS_SERVER_PASSWORD", hide_env_values = true)]
    server_password: Option<String>,

    /// Channel to join on connect, by name or path.
    #[arg(long)]
    channel: Option<String>,

    /// Protocol to speak.
    #[arg(long, value_parser = ["ts3", "ts6"], default_value = "ts3")]
    protocol: String,

    /// Where to store identities. Defaults to the platform application data
    /// directory.
    #[arg(long)]
    identity_dir: Option<PathBuf>,

    /// Join this channel once connected, to exercise the round trip.
    #[arg(long)]
    join: Option<u64>,

    /// Send this to the server once connected.
    #[arg(long)]
    say: Option<String>,

    /// Disconnect and exit after this many seconds instead of streaming until
    /// interrupted.
    ///
    /// Exists so a script can exercise the shutdown path: killing the process
    /// leaves the server holding a session, and TS3 refuses a second connection
    /// from the same identity until it times out.
    #[arg(long)]
    duration: Option<u64>,

    /// Open audio devices and send and receive voice.
    #[arg(long)]
    voice: bool,

    /// Transmit a sine tone at this frequency instead of using a microphone.
    ///
    /// Needs no input device and produces a known signal, which is what makes
    /// it possible to verify the voice path with two headless runs and no
    /// second person: one transmits, the other reports what it decoded.
    #[arg(long, value_name = "HZ")]
    tone: Option<f32>,

    /// Microphone to capture from. Defaults to the system default.
    #[arg(long)]
    input_device: Option<String>,

    /// Speakers to play through. Defaults to the system default.
    #[arg(long)]
    output_device: Option<String>,
}

/// A generated tone, for exercising the transmit path without a microphone.
struct Tone {
    hz: f32,
    encoder: ts_audio::OpusEncoder,
    /// Carried between frames so the wave is continuous rather than restarting
    /// every 20 ms, which would encode as a rattle.
    phase: f32,
}

/// Voice plumbing for a run.
struct Voice {
    /// Absent in tone mode, where neither capture nor playback is opened.
    engine: Option<ts_audio::VoiceEngine>,
    tone: Option<Tone>,
    /// Frames actually handed to the network, for the periodic report.
    sent: u64,
}

impl Voice {
    /// Prepares voice, opening devices unless a tone was requested.
    fn start(args: &Args) -> Result<Self> {
        if let Some(hz) = args.tone {
            return Ok(Self {
                engine: None,
                tone: Some(Tone {
                    hz,
                    encoder: ts_audio::OpusEncoder::new(ts_audio::VOICE_CHANNELS)
                        .context("could not start Opus")?,
                    phase: 0.0,
                }),
                sent: 0,
            });
        }

        // The CLI has no settings file, so it plays at unity — and, like every
        // other front-end, encodes at the top of the range with nothing to
        // configure.
        let mut engine = ts_audio::VoiceEngine::new(VoiceActivationSettings::default(), 1.0)
            .context("could not start the audio engine")?;
        engine
            .open_devices(args.input_device.as_deref(), args.output_device.as_deref())
            .context("could not open audio devices")?;

        println!(
            "Audio: input {}, output {}",
            if engine.input_available() {
                "open"
            } else {
                "unavailable"
            },
            if engine.output_available() {
                "open"
            } else {
                "unavailable"
            },
        );

        Ok(Self {
            engine: Some(engine),
            tone: None,
            sent: 0,
        })
    }

    /// The frames to transmit now, if any.
    fn frames(&mut self) -> Result<Vec<ts_protocol::VoicePacket>> {
        if let Some(tone) = &mut self.tone {
            let pcm = audio::tone_frame(tone.hz, 0.3, &mut tone.phase);
            return Ok(vec![
                tone.encoder
                    .encode(&pcm)
                    .context("encoding the tone failed")?,
            ]);
        }

        match &mut self.engine {
            Some(engine) => engine.poll().context("capturing a frame failed"),
            None => Ok(Vec::new()),
        }
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    // The same filter the Flutter client writes its file with, from one
    // definition: our own crates at info, the protocol library only when
    // something is wrong, because its per-packet logging is far too loud for
    // output meant to be read by a person. `NIGHTCORD_LOG` overrides it, and
    // `RUST_LOG` still works for anyone who reaches for that first.
    //
    // A terminal is the right destination here, unlike the GUI: this program's
    // whole output is the terminal, and a developer running it is watching one.
    tracing_subscriber::fmt()
        .with_env_filter(ts_logging::env_filter())
        .init();

    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            // `{:#}` prints the whole anyhow chain, which is what makes a failed
            // handshake diagnosable.
            eprintln!("\nfailed: {error:#}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<()> {
    let args = Args::parse();

    let identities = match &args.identity_dir {
        Some(dir) => IdentityStore::new(dir),
        None => IdentityStore::platform_default()
            .context("could not find a place to store identities; pass --identity-dir")?,
    };

    // `--identity-dir` exists to keep a run's state out of the real profile, so
    // the settings follow it there rather than being written to `%APPDATA%`
    // anyway — a flag that only half-relocates the state is a trap.
    let settings = match &args.identity_dir {
        Some(dir) => SettingsStore::new(dir),
        None => SettingsStore::platform_default()
            .context("could not find a place to store settings; pass --identity-dir")?,
    };
    let bookmarks = match &args.identity_dir {
        Some(dir) => BookmarkStore::new(dir),
        None => BookmarkStore::platform_default()
            .context("could not find a place to store saved servers; pass --identity-dir")?,
    };

    let mut client = Client::new(identities, settings, bookmarks);

    // Always installed, even without `--voice`: it costs nothing and makes the
    // "did any audio arrive" question answerable on any run.
    let report = AudioReport::new();

    // Subscribe before connecting: the handshake publishes the whole channel
    // and client list, and a subscriber that attaches afterwards misses it.
    let mut events = client.subscribe();

    let mut request = ConnectRequest::new(&args.address, &args.nickname);
    request.profile = args.profile.clone();
    request.server_password = args.server_password.clone();
    request.default_channel = args.channel.clone();
    request.protocol = match args.protocol.as_str() {
        "ts6" => ProtocolKind::Ts6,
        _ => ProtocolKind::Ts3,
    };

    println!("Connecting to {} as \"{}\"...", args.address, args.nickname);
    let session = client
        .connect(&request)
        .await
        .context("could not connect")?;
    println!("Connected.\n");

    let mut view = View::default();
    settle(&mut events, &mut view).await;
    print_state(&view);
    print_capabilities(&client, session);

    if let Some(channel_id) = args.join {
        println!("\nJoining channel {channel_id}...");
        let target = ChannelId::new(channel_id);
        session_mut(&mut client, session)?
            .join_channel(target)
            .await
            .context("join failed")?;
        // Give the server a moment to reflect the move back.
        settle(&mut events, &mut view).await;
        println!("Joined.");
    }

    if let Some(text) = &args.say {
        // Prefer our own channel: server-wide messages are privilege-gated on
        // many servers (verified against the test server, which refuses them),
        // whereas talking in the channel you are in is what the flag means to a
        // user.
        let (target, where_to) = match view.own_channel_id() {
            Some(channel_id) => (
                MessageTarget::Channel(channel_id),
                format!("channel {channel_id}"),
            ),
            None => (MessageTarget::Server, "the server".to_string()),
        };

        println!("\nSending to {where_to}: {text}");
        session_mut(&mut client, session)?
            .send_text(target, text)
            .await
            .context("send failed")?;
        println!("Sent.");
    }

    // Set up voice after connecting, so device errors are reported against a
    // session the user can see exists.
    let mut voice = if args.voice || args.tone.is_some() {
        let voice = Voice::start(&args)?;
        let sink: Arc<dyn AudioSink> = Arc::clone(&report) as Arc<dyn AudioSink>;
        session_mut(&mut client, session)?.set_audio_sink(sink);
        Some(voice)
    } else {
        None
    };

    match args.duration {
        Some(seconds) => println!("\nStreaming events for {seconds}s...\n"),
        None => println!("\nStreaming events — press Ctrl-C to disconnect.\n"),
    }
    stream_events(
        &mut events,
        &mut view,
        args.duration,
        voice.as_mut(),
        &mut client,
        session,
    )
    .await;

    if let Some(voice) = &voice {
        println!("Sent {} voice frame(s).", voice.sent);
    }
    if report.frames() > 0 {
        println!(
            "Received {} voice frame(s), {:.1}s of audio, peak {:.3}.",
            report.frames(),
            report.seconds(),
            report.peak()
        );
    }

    println!("Disconnecting...");
    if let Err(error) = client.disconnect(session).await {
        eprintln!("disconnect reported: {error}");
    } else {
        println!("Disconnected.");
    }
    Ok(())
}

/// Borrows a session, or explains why it is gone.
fn session_mut(
    client: &mut Client,
    session: ts_model::SessionId,
) -> Result<&mut ts_session::Session> {
    client
        .sessions_mut()
        .get_mut(session)
        .context("the session disappeared while the client was running")
}

/// Drains events until the server goes quiet.
///
/// A quiet gap means the initial burst has finished, so the first render shows
/// the whole tree rather than a fraction of it.
async fn settle(events: &mut Receiver<SessionEvent>, view: &mut View) {
    loop {
        match tokio::time::timeout(SETTLE, events.recv()).await {
            Ok(Ok(event)) => view.apply(&event.event),
            // Quiet, or the channel closed; either way there is nothing to wait for.
            Ok(Err(_)) | Err(_) => return,
        }
    }
}

/// Streams events until interrupted, the deadline passes, or the session ends.
async fn stream_events(
    events: &mut Receiver<SessionEvent>,
    view: &mut View,
    duration: Option<u64>,
    mut voice: Option<&mut Voice>,
    client: &mut Client,
    session: SessionId,
) {
    let deadline =
        duration.map(|seconds| tokio::time::Instant::now() + Duration::from_secs(seconds));

    // Ticks at the codec's frame rate, so transmitted audio leaves in real time
    // rather than as fast as the encoder can produce it.
    let mut ticker = tokio::time::interval(audio::frame_interval());
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    // The first tick is immediate; consume it so the loop starts in step.
    ticker.tick().await;

    loop {
        tokio::select! {
            // The guard makes the branch inert when voice is off, so the timer
            // does not wake the loop for nothing.
            _ = ticker.tick(), if voice.is_some() => {
                if let Some(voice) = voice.as_deref_mut() {
                    match voice.frames() {
                        Ok(frames) => {
                            for packet in frames {
                                let Some(session_ref) = client.sessions_mut().get_mut(session)
                                else {
                                    tracing::warn!("the session disappeared; stopping voice");
                                    return;
                                };
                                match session_ref.send_voice(packet).await {
                                    Ok(()) => voice.sent += 1,
                                    Err(error) => {
                                        tracing::debug!(%error, "could not send a voice frame");
                                    }
                                }
                            }
                        }
                        Err(error) => tracing::warn!(%error, "voice capture failed"),
                    }
                }
            }
            received = events.recv() => match received {
                Ok(event) => {
                    view.apply(&event.event);
                    render(&event);
                    if event.is_terminal() {
                        return;
                    }
                }
                Err(RecvError::Lagged(missed)) => {
                    // The core never blocks on a slow consumer, so this is
                    // expected on a busy server and worth saying out loud.
                    println!("(fell behind; {missed} events were dropped)");
                }
                Err(RecvError::Closed) => return,
            },
            _ = tokio::signal::ctrl_c() => {
                println!("\nInterrupted.");
                return;
            }
            // Terminating without a disconnect leaves the server holding a
            // session, and TS3 limits connections per identity — so the next
            // run would be refused with `ClientTooManyClonesConnected` until
            // the server times the stale one out.
            _ = termination_signal() => {
                println!("\nTerminated.");
                return;
            }
            _ = wait_until(deadline) => {
                println!();
                return;
            }
        }
    }
}

/// Resolves at `deadline`, or never when there is none.
async fn wait_until(deadline: Option<tokio::time::Instant>) {
    match deadline {
        Some(at) => tokio::time::sleep_until(at).await,
        None => std::future::pending().await,
    }
}

/// Resolves when the process is asked to terminate.
///
/// `SIGTERM` has no portable equivalent, so on Windows this never resolves and
/// Ctrl-C is the only supported way out.
#[cfg(unix)]
async fn termination_signal() {
    match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
        Ok(mut signal) => {
            signal.recv().await;
        }
        // If the handler cannot be installed, never resolve: losing SIGTERM
        // handling is better than exiting on startup.
        Err(error) => {
            eprintln!("could not install a SIGTERM handler: {error}");
            std::future::pending::<()>().await;
        }
    }
}

/// See the Unix definition above.
#[cfg(not(unix))]
async fn termination_signal() {
    std::future::pending::<()>().await;
}

/// Prints one event, if it is worth a line.
fn render(event: &SessionEvent) {
    let session = event.session;
    match &event.event {
        ClientEvent::Screen(_) => {}
        ClientEvent::ConnectionStateChanged(state) => {
            println!("[{session}] connection: {state:?}");
        }
        ClientEvent::MessageReceived(message) => {
            println!("[{session}] <{}> {}", message.sender_name, message.content);
        }
        ClientEvent::Poked {
            sender_name,
            message,
            ..
        } => {
            println!("[{session}] {sender_name} poked you: {message}");
        }
        ClientEvent::ClientJoined(client) => {
            println!("[{session}] + {} joined", client.name);
        }
        ClientEvent::ClientLeft(id) => println!("[{session}] - client {id} left"),
        ClientEvent::ClientMoved {
            client_id,
            channel_id,
        } => {
            println!("[{session}] client {client_id} moved to channel {channel_id}");
        }
        ClientEvent::ChannelCreated(channel) => {
            println!("[{session}] + channel \"{}\"", channel.name);
        }
        ClientEvent::ChannelRemoved(id) => println!("[{session}] - channel {id} removed"),
        ClientEvent::ReconnectScheduled { attempt, delay_ms } => {
            println!("[{session}] reconnecting: attempt {attempt} in {delay_ms}ms");
        }
        ClientEvent::ServerInfoChanged(info) => {
            println!(
                "[{session}] now {} client(s), {} channel(s)",
                info.clients_online, info.channels_online
            );
        }
        ClientEvent::Error(error) => println!("[{session}] error: {error}"),
        ClientEvent::Disconnected => println!("[{session}] disconnected"),

        // The rest would be noise in a terminal: these arrive in a burst on
        // connect and the tree printout covers them.
        ClientEvent::Connected { .. }
        | ClientEvent::OwnClientIdentified { .. }
        | ClientEvent::ChannelUpdated(_)
        | ClientEvent::ClientUpdated(_)
        | ClientEvent::PermissionsChanged(_)
        | ClientEvent::CapabilitiesChanged(_)
        | ClientEvent::Speaking(_)
        | ClientEvent::VoiceStateChanged(_) => {}
    }
}

/// Prints what the server can do.
///
/// Worth surfacing from a diagnostic client: the UI branches on these rather
/// than on the protocol, so this is what decides which controls appear (§15).
fn print_capabilities(client: &Client, session: SessionId) {
    let Some(session) = client.sessions().get(session) else {
        return;
    };
    let capabilities = session.capabilities();

    let mut supported = Vec::new();
    for (name, present) in [
        ("chat", capabilities.text_chat),
        ("private", capabilities.private_chat),
        ("voice", capabilities.voice),
        ("whisper", capabilities.whisper),
        ("files", capabilities.file_transfer),
        ("stream", capabilities.screen_stream),
        ("poke", capabilities.poke),
    ] {
        if present {
            supported.push(name);
        }
    }

    println!(
        "\nCapabilities ({:?}): {}",
        session.protocol(),
        if supported.is_empty() {
            "none".to_string()
        } else {
            supported.join(", ")
        }
    );
}

/// Renders the accumulated view.
fn print_state(view: &View) {
    match &view.info {
        Some(info) => {
            println!("Server: {}", info.name);
            if let Some(welcome) = &info.welcome_message {
                for line in welcome.lines() {
                    println!("  {line}");
                }
            }
            println!(
                "  {} client(s), {} channel(s), {} slot(s)",
                info.clients_online, info.channels_online, info.max_clients
            );
            if let (Some(platform), Some(version)) = (&info.platform, &info.version) {
                println!("  running {platform} {version}");
            }
        }
        None => println!("(the server has not described itself yet)"),
    }

    println!("\nChannels:");
    for (depth, channel) in view.tree() {
        println!("{}{}", "  ".repeat(depth + 1), channel.name);
        for client in view.clients_in(channel.id) {
            let suffix = if Some(client.id) == view.own_client_id {
                "  (you)"
            } else {
                ""
            };
            println!("{}- {}{}", "  ".repeat(depth + 2), client.name, suffix);
        }
    }

    println!("\n{} client(s) visible.", view.clients.len());
}
