//! A browser credential selects one isolated core and persistent store.

use std::collections::{HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::{broadcast, mpsc};
use tokio::task::JoinHandle;
use tokio::time::Instant;
use ts_core::Client as CoreClient;
use ts_identity::IdentityStore;
use ts_settings::{BookmarkStore, SettingsStore};

use crate::worker::{GatewayCommand, Worker};
use crate::{OUTBOUND_CAPACITY, Outbound, generate_token};

/// A refresh may restore sessions; abandoned devices must eventually disconnect.
pub(crate) const RESTORE_WINDOW: Duration = Duration::from_secs(30);
const MAX_ACTIVE_DEVICES: usize = 64;

pub(crate) struct DeviceContext {
    pub(crate) outbound: broadcast::Sender<Outbound>,
    pub(crate) commands: mpsc::UnboundedSender<GatewayCommand>,
}

struct Device {
    context: Arc<DeviceContext>,
    worker: JoinHandle<()>,
    connections: usize,
    idle_since: Instant,
}

struct State {
    devices: HashMap<String, Device>,
    stopped: bool,
    retiring: HashSet<String>,
}

pub(crate) struct Devices {
    root: PathBuf,
    profile: String,
    state: Mutex<State>,
}

/// Drop is synchronous so socket cancellation cannot leak its device reference.
pub(crate) struct DeviceLease {
    registry: Arc<Devices>,
    id: String,
    pub(crate) credential: String,
    pub(crate) context: Arc<DeviceContext>,
}

impl Drop for DeviceLease {
    fn drop(&mut self) {
        if let Ok(mut state) = self.registry.state.lock()
            && let Some(device) = state.devices.get_mut(&self.id)
        {
            device.connections = device.connections.saturating_sub(1);
            if device.connections == 0 {
                device.idle_since = Instant::now();
                let _ = device.context.commands.send(GatewayCommand::Idle);
            }
        }
    }
}

impl Devices {
    pub(crate) fn new(root: PathBuf, profile: String) -> io::Result<Self> {
        fs::create_dir_all(&root)?;
        Ok(Self {
            root,
            profile,
            state: Mutex::new(State {
                devices: HashMap::new(),
                stopped: false,
                retiring: HashSet::new(),
            }),
        })
    }

    pub(crate) async fn attach(
        self: &Arc<Self>,
        requested: Option<&str>,
    ) -> Result<DeviceLease, &'static str> {
        loop {
            match self.attach_now(requested) {
                Err("device is closing") => tokio::time::sleep(Duration::from_millis(20)).await,
                result => return result,
            }
        }
    }

    fn attach_now(self: &Arc<Self>, requested: Option<&str>) -> Result<DeviceLease, &'static str> {
        let credential = requested.map_or_else(
            || format!("{}.{}", generate_token(), generate_token()),
            str::to_owned,
        );
        let (id, secret) = credential
            .split_once('.')
            .ok_or("invalid device credential")?;
        if !valid_part(id) || !valid_part(secret) {
            return Err("invalid device credential");
        }
        let mut state = self
            .state
            .lock()
            .map_err(|_| "device registry unavailable")?;
        if state.stopped {
            return Err("gateway stopped");
        }
        if state.retiring.contains(id) {
            return Err("device is closing");
        }
        if !state.devices.contains_key(id) && state.devices.len() >= MAX_ACTIVE_DEVICES {
            return Err("gateway device capacity reached");
        }
        // Only the public random id becomes a path. The secret never reaches
        // identity filenames, errors, Debug output or logs.
        let directory = self.root.join(id);
        fs::create_dir_all(&directory).map_err(|_| "could not create device storage")?;
        let grant = directory.join("access.key");
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        match options.open(&grant) {
            Ok(mut file) => {
                file.write_all(secret.as_bytes())
                    .map_err(|_| "could not save device credential")?;
                file.sync_all()
                    .map_err(|_| "could not save device credential")?;
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                let saved = fs::read(&grant).map_err(|_| "could not read device credential")?;
                if saved.len() != secret.len()
                    || saved
                        .iter()
                        .zip(secret.bytes())
                        .fold(0u8, |diff, (a, b)| diff | (a ^ b))
                        != 0
                {
                    return Err("invalid device credential");
                }
            }
            Err(_) => return Err("could not save device credential"),
        }
        let device = state.devices.entry(id.to_owned()).or_insert_with(|| {
            let core = CoreClient::new(
                IdentityStore::new(&directory),
                SettingsStore::new(&directory),
                BookmarkStore::new(&directory),
            );
            let (outbound, _) = broadcast::channel(OUTBOUND_CAPACITY);
            let (commands, input) = mpsc::unbounded_channel();
            let worker = tokio::spawn(
                Worker::new(core, self.profile.clone(), outbound.clone(), input).run(),
            );
            Device {
                context: Arc::new(DeviceContext { outbound, commands }),
                worker,
                connections: 0,
                idle_since: Instant::now(),
            }
        });
        device.connections += 1;
        Ok(DeviceLease {
            registry: self.clone(),
            id: id.to_owned(),
            context: device.context.clone(),
            credential,
        })
    }

    pub(crate) async fn reap(&self, age: Duration) {
        let (ids, expired) = if let Ok(mut state) = self.state.lock() {
            let ids: Vec<_> = state
                .devices
                .iter()
                .filter(|(_, device)| device.connections == 0 && device.idle_since.elapsed() >= age)
                .map(|(id, _)| id.clone())
                .collect();
            state.retiring.extend(ids.iter().cloned());
            let expired = ids
                .iter()
                .filter_map(|id| state.devices.remove(id))
                .collect::<Vec<_>>();
            (ids, expired)
        } else {
            (Vec::new(), Vec::new())
        };
        stop(expired).await;
        if let Ok(mut state) = self.state.lock() {
            for id in ids {
                state.retiring.remove(&id);
            }
        }
    }

    pub(crate) async fn shutdown(&self) {
        let devices = if let Ok(mut state) = self.state.lock() {
            state.stopped = true;
            state.devices.drain().map(|(_, device)| device).collect()
        } else {
            Vec::new()
        };
        stop(devices).await;
    }
}

fn valid_part(value: &str) -> bool {
    value.len() == 32
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

async fn stop(devices: Vec<Device>) {
    for device in &devices {
        let _ = device.context.commands.send(GatewayCommand::Shutdown);
    }
    for device in devices {
        let _ = device.worker.await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn credentials_isolate_cores_and_reject_impersonation() {
        let root = std::env::temp_dir().join(format!("nightcord-devices-{}", generate_token()));
        let registry = Arc::new(Devices::new(root.clone(), "web".into()).unwrap());
        let first = registry.attach(None).await.unwrap();
        let second = registry.attach(None).await.unwrap();
        assert!(!Arc::ptr_eq(&first.context, &second.context));
        let resumed = registry.attach(Some(&first.credential)).await.unwrap();
        assert!(Arc::ptr_eq(&first.context, &resumed.context));
        // Audio from one device must never reach a different device's browser.
        let mut own_audio = resumed.context.outbound.subscribe();
        let mut other_audio = second.context.outbound.subscribe();
        first
            .context
            .outbound
            .send(Outbound::Binary(vec![1, 2, 3]))
            .unwrap();
        assert!(
            matches!(own_audio.recv().await.unwrap(), Outbound::Binary(bytes) if bytes == [1, 2, 3])
        );
        assert!(matches!(
            other_audio.try_recv(),
            Err(broadcast::error::TryRecvError::Empty)
        ));
        let wrong = format!("{}.{}", first.id, generate_token());
        assert!(registry.attach(Some(&wrong)).await.is_err());
        assert!(registry.attach(Some("../../escape.secret")).await.is_err());
        let credential = first.credential.clone();
        let original = first.context.clone();
        drop(first);
        drop(resumed);
        drop(second);
        registry.reap(Duration::ZERO).await;
        let restored = registry.attach(Some(&credential)).await.unwrap();
        assert!(!Arc::ptr_eq(&original, &restored.context));
        drop(restored);
        registry.shutdown().await;
        fs::remove_dir_all(root).unwrap();
    }
}
