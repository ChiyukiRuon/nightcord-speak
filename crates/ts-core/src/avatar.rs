use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use tokio::sync::{Notify, broadcast};
use ts_events::{ClientEvent, EventBus, SessionEvent};
use ts_model::{AvatarEdit, ClientError, ConnectionState, OwnAvatar, ProtocolError, SessionId};
use ts_protocol::Avatars;
use ts_settings::AvatarStore;

struct State {
    avatar: OwnAvatar,
    bytes: Option<Vec<u8>>,
}

/// One saved preference with independent, coalescing workers per server.
/// A slow or rejecting server cannot prevent the others from updating.
pub struct GlobalAvatar {
    store: AvatarStore,
    state: Mutex<State>,
    changes: tokio::sync::Mutex<()>,
    targets: Mutex<HashMap<SessionId, Arc<Notify>>>,
    events: EventBus,
}

fn invalid() -> ClientError {
    ClientError::Protocol(ProtocolError::new("invalid global avatar image"))
}

fn validate(bytes: &[u8]) -> Result<(), ClientError> {
    if bytes.is_empty()
        || bytes.len() > 200 * 1024
        || !(bytes.starts_with(b"\x89PNG\r\n\x1a\n") || bytes.starts_with(&[0xff, 0xd8, 0xff]))
    {
        return Err(invalid());
    }
    Ok(())
}

impl GlobalAvatar {
    pub(crate) fn new(store: AvatarStore, events: EventBus) -> Arc<Self> {
        let mut loaded = store
            .load()
            .and_then(|avatar| {
                let bytes = avatar
                    .image
                    .as_ref()
                    .map(|image| STANDARD.decode(image))
                    .transpose()
                    .map_err(|_| ts_model::SettingsError::Malformed {
                        message: "invalid saved avatar encoding".into(),
                    })?;
                if bytes.as_ref().is_some_and(|bytes| validate(bytes).is_err()) {
                    return Err(ts_model::SettingsError::Malformed {
                        message: "invalid saved avatar image".into(),
                    });
                }
                Ok((avatar, bytes))
            })
            .unwrap_or_else(|error| {
                tracing::warn!(%error, "ignoring unreadable global avatar");
                (OwnAvatar::default(), None)
            });
        if loaded.0.configured && loaded.0.revision == 0 {
            loaded.0.revision = 1;
        }
        Arc::new(Self {
            store,
            state: Mutex::new(State {
                avatar: loaded.0,
                bytes: loaded.1,
            }),
            changes: tokio::sync::Mutex::new(()),
            targets: Mutex::new(HashMap::new()),
            events,
        })
    }

    pub fn snapshot(&self) -> OwnAvatar {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .avatar
            .clone()
    }

    pub async fn set(&self, origin: SessionId, bytes: Option<Vec<u8>>) -> Result<(), ClientError> {
        self.change(origin, bytes, None, false).await
    }

    pub async fn set_with_edit(
        &self,
        origin: SessionId,
        bytes: Option<Vec<u8>>,
        edit: Option<AvatarEdit>,
    ) -> Result<(), ClientError> {
        self.change(origin, bytes, edit, false).await
    }

    async fn change(
        &self,
        origin: SessionId,
        bytes: Option<Vec<u8>>,
        edit: Option<AvatarEdit>,
        import: bool,
    ) -> Result<(), ClientError> {
        if let Some(bytes) = &bytes {
            validate(bytes)?;
        }
        if let Some(edit) = &edit {
            if edit.source.len() > 13981016 {
                return Err(invalid());
            }
            let source = STANDARD.decode(&edit.source).map_err(|_| invalid())?;
            if bytes.is_none()
                || source.is_empty()
                || source.len() > 10 * 1024 * 1024
                || edit.turns > 3
                || !(1.0..=4.0).contains(&edit.zoom)
                || !(0.0..=1.0).contains(&edit.x)
                || !(0.0..=1.0).contains(&edit.y)
            {
                return Err(invalid());
            }
        }
        let _guard = self.changes.lock().await;
        if import && self.snapshot().configured {
            return Ok(());
        }
        let avatar = OwnAvatar {
            revision: self
                .snapshot()
                .revision
                .checked_add(1)
                .ok_or_else(invalid)?,
            edit,
            configured: true,
            image: bytes.as_ref().map(|b| STANDARD.encode(b)),
        };
        let saved = avatar.clone();
        let store = self.store.clone();
        tokio::task::spawn_blocking(move || store.save(&saved))
            .await
            .map_err(|_| ClientError::CoreGone)?
            .map_err(ClientError::Settings)?;
        {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.avatar = avatar.clone();
            state.bytes = bytes;
        }
        self.events.publish(SessionEvent {
            session: origin,
            event: ClientEvent::OwnAvatarChanged(avatar),
        });
        for notify in self
            .targets
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
        {
            notify.notify_one();
        }
        Ok(())
    }

    pub(crate) fn attach(
        self: &Arc<Self>,
        session: SessionId,
        handle: Arc<dyn Avatars>,
        mut events: broadcast::Receiver<SessionEvent>,
    ) -> tokio::task::JoinHandle<()> {
        let notify = Arc::new(Notify::new());
        self.targets
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(session, notify.clone());
        let global = self.clone();
        tokio::spawn(async move {
            let mut connected = false;
            let mut applied = 0;
            loop {
                tokio::select! {
                    _ = notify.notified(), if connected => {
                        let (revision, bytes, configured) = {
                            let state = global.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
                            (state.avatar.revision, state.bytes.clone(), state.avatar.configured)
                        };
                        if configured && applied != revision {
                            match handle.set_avatar(bytes).await {
                                Ok(()) => applied = revision,
                                Err(error) => { tracing::warn!(%session, %error, "global avatar synchronization failed");
                                    global.events.publish(SessionEvent { session,
                                    event: ClientEvent::Error(error) }); },
                            }
                        }
                    }
                    event = events.recv() => {
                        match event {
                            Ok(event) if event.session == session => match event.event {
                                ClientEvent::ConnectionStateChanged(ConnectionState::Connected) => {
                                    connected = true;
                                    applied = 0;
                                    notify.notify_one();
                                }
                                ClientEvent::ConnectionStateChanged(_) => connected = false,
                                ClientEvent::Disconnected => break,
                                ClientEvent::ClientJoined(client) | ClientEvent::ClientUpdated(client)
                                    if client.is_self && client.avatar_version.is_some() && !global.snapshot().configured => {
                                    // Migrate the first existing self avatar once. Recheck under
                                    // the change lock so a simultaneous user choice always wins.
                                    if let Ok(image) = handle.get_avatar(client.id).await
                                        && let Ok(bytes) = STANDARD.decode(image.image) {
                                        if let Err(error) = global.change(session, Some(bytes), None, true).await {
                                            global.events.publish(SessionEvent { session, event: ClientEvent::Error(error) });
                                        }
                                    }
                                }
                                _ => {}
                            },
                            Ok(_) => {},
                            Err(broadcast::error::RecvError::Lagged(_)) => { applied = 0; notify.notify_one(); },
                            Err(broadcast::error::RecvError::Closed) => break,
                        }
                    }
                }
            }
        })
    }

    pub(crate) fn detach(&self, session: SessionId) {
        self.targets
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(&session);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::{Semaphore, mpsc};

    #[tokio::test]
    async fn original_and_crop_survive_restart_and_removal_clears_them() {
        // Editing used to reopen the exported square and permanently lose the
        // excluded pixels. The full original must survive core recreation.
        let dir = Temp::new();
        let bus = EventBus::default();
        let global = GlobalAvatar::new(dir.store(), bus.clone());
        let edit = AvatarEdit {
            source: STANDARD.encode(vec![9; 400 * 1024]),
            turns: 1,
            zoom: 2.0,
            x: 0.3,
            y: 0.6,
        };
        let id = SessionId::new(1);
        global
            .set_with_edit(id, Some(image(1)), Some(edit.clone()))
            .await
            .unwrap();
        let reloaded = GlobalAvatar::new(dir.store(), bus);
        assert_eq!(reloaded.snapshot().edit, Some(edit));
        assert_eq!(reloaded.snapshot().image, Some(STANDARD.encode(image(1))));
        reloaded.set(id, None).await.unwrap();
        assert!(
            GlobalAvatar::new(dir.store(), EventBus::default())
                .snapshot()
                .edit
                .is_none()
        );
    }

    #[tokio::test]
    async fn invalid_edit_keeps_the_previous_avatar() {
        let dir = Temp::new();
        let global = GlobalAvatar::new(dir.store(), EventBus::default());
        let id = SessionId::new(1);
        global.set(id, Some(image(1))).await.unwrap();
        let before = global.snapshot();
        for edit in [
            AvatarEdit {
                source: "bad encoding".into(),
                turns: 0,
                zoom: 1.0,
                x: 0.5,
                y: 0.5,
            },
            AvatarEdit {
                source: STANDARD.encode(image(1)),
                turns: 0,
                zoom: f64::NAN,
                x: 0.5,
                y: 0.5,
            },
            AvatarEdit {
                source: STANDARD.encode(image(1)),
                turns: 4,
                zoom: 1.0,
                x: 0.5,
                y: 0.5,
            },
        ] {
            assert!(
                global
                    .set_with_edit(id, Some(image(2)), Some(edit))
                    .await
                    .is_err()
            );
            assert_eq!(global.snapshot(), before);
        }
    }

    struct Temp(std::path::PathBuf);
    impl Temp {
        fn new() -> Self {
            static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
            let path = std::env::temp_dir().join(format!(
                "nightcord-avatar-{}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos(),
                NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
            ));
            std::fs::create_dir_all(&path).unwrap();
            Self(path)
        }
        fn store(&self) -> AvatarStore {
            AvatarStore::new(self.0.join("avatar.json"))
        }
    }
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    struct Fake {
        sent: mpsc::UnboundedSender<Option<Vec<u8>>>,
        gate: Option<Arc<Semaphore>>,
        fail: bool,
    }
    #[async_trait::async_trait]
    impl Avatars for Fake {
        async fn get_avatar(
            &self,
            _: ts_model::ClientId,
        ) -> Result<ts_model::AvatarImage, ClientError> {
            Err(ClientError::Timeout)
        }
        async fn set_avatar(&self, bytes: Option<Vec<u8>>) -> Result<(), ClientError> {
            self.sent.send(bytes).unwrap();
            if let Some(gate) = &self.gate {
                gate.acquire().await.unwrap().forget();
            }
            if self.fail {
                Err(ClientError::Timeout)
            } else {
                Ok(())
            }
        }
    }
    fn image(value: u8) -> Vec<u8> {
        [b"\x89PNG\r\n\x1a\n".as_slice(), &[value]].concat()
    }
    fn connected(bus: &EventBus, id: SessionId) {
        bus.publish(SessionEvent {
            session: id,
            event: ClientEvent::ConnectionStateChanged(ConnectionState::Connected),
        });
    }
    async fn next(rx: &mut mpsc::UnboundedReceiver<Option<Vec<u8>>>) -> Option<Vec<u8>> {
        tokio::time::timeout(std::time::Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .unwrap()
    }

    #[tokio::test]
    async fn one_choice_fans_out_and_a_slow_server_finishes_on_the_latest_revision() {
        // Previously each upload changed only the selected server.
        let dir = Temp::new();
        let bus = EventBus::with_default_capacity();
        let global = GlobalAvatar::new(dir.store(), bus.clone());
        let gate = Arc::new(Semaphore::new(0));
        let (tx1, mut rx1) = mpsc::unbounded_channel();
        let (tx2, mut rx2) = mpsc::unbounded_channel();
        let one = SessionId::new(1);
        let two = SessionId::new(2);
        let task1 = global.attach(
            one,
            Arc::new(Fake {
                sent: tx1,
                gate: Some(gate.clone()),
                fail: false,
            }),
            bus.subscribe(),
        );
        let task2 = global.attach(
            two,
            Arc::new(Fake {
                sent: tx2,
                gate: None,
                fail: false,
            }),
            bus.subscribe(),
        );
        connected(&bus, one);
        connected(&bus, two);
        global.set(one, Some(image(1))).await.unwrap();
        assert_eq!(next(&mut rx1).await, Some(image(1)));
        assert_eq!(next(&mut rx2).await, Some(image(1)));
        global.set(two, Some(image(2))).await.unwrap();
        assert_eq!(next(&mut rx2).await, Some(image(2)));
        gate.add_permits(1);
        assert_eq!(next(&mut rx1).await, Some(image(2)));
        gate.add_permits(1);
        global.set(one, None).await.unwrap();
        assert_eq!(next(&mut rx2).await, None);
        assert_eq!(next(&mut rx1).await, None);
        gate.add_permits(1);
        assert_eq!(
            global.snapshot(),
            OwnAvatar {
                revision: 3,
                configured: true,
                image: None,
                edit: None
            }
        );
        task1.abort();
        task2.abort();
    }

    #[tokio::test]
    async fn persisted_image_and_removal_apply_on_new_connections_and_reconnections() {
        let dir = Temp::new();
        let bus = EventBus::with_default_capacity();
        GlobalAvatar::new(dir.store(), bus.clone())
            .set(SessionId::new(1), Some(image(7)))
            .await
            .unwrap();
        let global = GlobalAvatar::new(dir.store(), bus.clone());
        assert_eq!(global.snapshot().image, Some(STANDARD.encode(image(7))));
        let (tx, mut rx) = mpsc::unbounded_channel();
        let id = SessionId::new(3);
        let task = global.attach(
            id,
            Arc::new(Fake {
                sent: tx,
                gate: None,
                fail: false,
            }),
            bus.subscribe(),
        );
        connected(&bus, id);
        assert_eq!(next(&mut rx).await, Some(image(7)));
        bus.publish(SessionEvent {
            session: id,
            event: ClientEvent::ConnectionStateChanged(ConnectionState::Reconnecting),
        });
        connected(&bus, id);
        assert_eq!(next(&mut rx).await, Some(image(7)));
        global.set(id, None).await.unwrap();
        assert_eq!(next(&mut rx).await, None);
        task.abort();
        let reloaded = GlobalAvatar::new(dir.store(), bus.clone());
        reloaded
            .change(id, Some(image(8)), None, true)
            .await
            .unwrap();
        assert_eq!(
            reloaded.snapshot(),
            OwnAvatar {
                revision: 2,
                configured: true,
                image: None,
                edit: None
            }
        );
        let (tx, mut rx) = mpsc::unbounded_channel();
        let task = reloaded.attach(
            id,
            Arc::new(Fake {
                sent: tx,
                gate: None,
                fail: false,
            }),
            bus.subscribe(),
        );
        connected(&bus, id);
        assert_eq!(next(&mut rx).await, None);
        task.abort();
    }

    #[tokio::test]
    async fn a_rejecting_server_reports_its_own_error_without_blocking_others() {
        let dir = Temp::new();
        let bus = EventBus::with_default_capacity();
        let global = GlobalAvatar::new(dir.store(), bus.clone());
        let mut events = bus.subscribe();
        let (tx1, mut rx1) = mpsc::unbounded_channel();
        let (tx2, mut rx2) = mpsc::unbounded_channel();
        let bad = SessionId::new(1);
        let good = SessionId::new(2);
        let t1 = global.attach(
            bad,
            Arc::new(Fake {
                sent: tx1,
                gate: None,
                fail: true,
            }),
            bus.subscribe(),
        );
        let t2 = global.attach(
            good,
            Arc::new(Fake {
                sent: tx2,
                gate: None,
                fail: false,
            }),
            bus.subscribe(),
        );
        connected(&bus, bad);
        connected(&bus, good);
        global.set(good, Some(image(3))).await.unwrap();
        assert_eq!(next(&mut rx1).await, Some(image(3)));
        assert_eq!(next(&mut rx2).await, Some(image(3)));
        tokio::time::timeout(std::time::Duration::from_secs(2), async {
            loop {
                let event = events.recv().await.unwrap();
                if event.event.is_error() {
                    assert_eq!(event.session, bad);
                    break;
                }
            }
        })
        .await
        .unwrap();
        t1.abort();
        t2.abort();
    }

    #[tokio::test]
    async fn failed_persistence_and_invalid_images_do_not_replace_the_saved_choice() {
        let dir = Temp::new();
        let bus = EventBus::with_default_capacity();
        let global = GlobalAvatar::new(AvatarStore::new(&dir.0), bus);
        assert!(global.set(SessionId::new(1), Some(image(1))).await.is_err());
        assert!(!global.snapshot().configured);
        assert!(
            global
                .set(SessionId::new(1), Some(vec![1, 2, 3]))
                .await
                .is_err()
        );
        assert!(!global.snapshot().configured);
        assert!(
            !format!(
                "{:?}",
                OwnAvatar {
                    revision: 1,
                    configured: true,
                    edit: None,
                    image: Some("secret-image".into())
                }
            )
            .contains("secret-image")
        );
    }
}
