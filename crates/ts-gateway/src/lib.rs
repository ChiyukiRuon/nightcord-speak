//! The WebSocket front-end: one isolated core per browser device.
//! Protocol implementations and command vocabulary are reused unchanged.

mod config;
mod devices;
mod http;
mod snapshot;
mod voice;
mod worker;
mod ws;

use std::net::SocketAddr;
use std::sync::Arc;
use std::sync::atomic::AtomicU64;

use tokio::net::TcpListener;

pub use config::{GatewayConfig, generate_token};
use devices::{Devices, RESTORE_WINDOW};
use http::Route;
use ws::ConnectionContext;

/// How many outbound messages may queue before a connection counts as lagged.
///
/// The same order of magnitude as the FFI's event queue: a connection that
/// stopped reading has stopped caring, and dropping its oldest messages with a
/// `lagged` marker beats unbounded memory per visitor.
const OUTBOUND_CAPACITY: usize = 1024;

/// One message on its way to every connection.
#[derive(Debug, Clone)]
pub(crate) enum Outbound {
    /// A JSON envelope: an event, a command result, or a control frame.
    Text(String),
    /// A binary audio frame, already in its wire layout.
    Binary(Vec<u8>),
}

/// What can go wrong before the gateway is serving.
#[derive(Debug, thiserror::Error)]
pub enum GatewayError {
    /// A listener could not be bound.
    #[error("could not listen on {address}: {source}")]
    Bind {
        /// Which address.
        address: SocketAddr,
        /// Why not.
        source: std::io::Error,
    },

    /// The client's stores could not be found or built.
    #[error("could not start the client core: {0}")]
    Core(#[from] ts_model::ClientError),

    /// Device storage could not be prepared.
    #[error("could not prepare gateway device storage")]
    Storage(#[source] std::io::Error),
}

/// A gateway that has not bound its sockets yet.
pub struct Gateway {
    config: GatewayConfig,
}

impl Gateway {
    /// Prepares a gateway from `config`.
    #[must_use]
    pub fn new(config: GatewayConfig) -> Self {
        Self { config }
    }

    /// Binds every address in the configuration.
    ///
    /// # Errors
    ///
    /// [`GatewayError::Bind`] — any address failing to bind fails the whole
    /// gateway, because "it started but only half the URLs work" is the kind
    /// of state nobody diagnoses quickly.
    pub async fn bind(self) -> Result<BoundGateway, GatewayError> {
        let mut listeners = Vec::with_capacity(self.config.bind.len());
        for address in &self.config.bind {
            let listener =
                TcpListener::bind(address)
                    .await
                    .map_err(|source| GatewayError::Bind {
                        address: *address,
                        source,
                    })?;
            listeners.push(listener);
        }
        Ok(BoundGateway {
            config: Arc::new(self.config),
            listeners,
        })
    }
}

/// A gateway with sockets open and nothing served yet.
pub struct BoundGateway {
    config: Arc<GatewayConfig>,
    listeners: Vec<TcpListener>,
}

impl BoundGateway {
    /// The addresses actually bound — the answer to "which port did the
    /// kernel pick" when the configuration asked for port 0.
    ///
    /// # Errors
    ///
    /// Whatever [`TcpListener::local_addr`] returns; in practice never.
    pub fn local_addrs(&self) -> Result<Vec<SocketAddr>, std::io::Error> {
        self.listeners.iter().map(TcpListener::local_addr).collect()
    }

    /// Serves until `shutdown` resolves, then stops the worker.
    ///
    /// # Errors
    ///
    /// [`GatewayError::Core`] when the client's stores cannot be built — the
    /// only failure left by the time sockets exist.
    pub async fn serve(
        self,
        shutdown: impl Future<Output = ()> + Send + 'static,
    ) -> Result<(), GatewayError> {
        let root = self
            .config
            .data_dir
            .clone()
            .or_else(ts_identity::app_data_root)
            .ok_or(ts_model::ClientError::Identity(
                ts_model::IdentityError::NoStorageRoot,
            ))?
            .join("devices");
        let devices = Arc::new(
            Devices::new(root, self.config.profile.clone()).map_err(GatewayError::Storage)?,
        );
        let context = Arc::new(ConnectionContext {
            config: self.config.clone(),
            devices: devices.clone(),
            next_connection: AtomicU64::new(1),
        });
        let cleanup_devices = devices.clone();
        let (stop_cleanup, mut cleanup_stopped) = tokio::sync::oneshot::channel();
        let cleanup = tokio::spawn(async move {
            let mut timer = tokio::time::interval(std::time::Duration::from_secs(5));
            loop {
                tokio::select! {
                    _ = &mut cleanup_stopped => break,
                    _ = timer.tick() => cleanup_devices.reap(RESTORE_WINDOW).await,
                }
            }
        });

        let mut accepts = Vec::with_capacity(self.listeners.len());
        for listener in self.listeners {
            accepts.push(tokio::spawn(accept_loop(listener, context.clone())));
        }

        shutdown.await;

        for accept in accepts {
            accept.abort();
        }
        let _ = stop_cleanup.send(());
        let _ = cleanup.await;
        devices.shutdown().await;
        tracing::info!("the gateway stopped");
        Ok(())
    }
}

/// Accepts connections until the task is aborted.
async fn accept_loop(listener: TcpListener, context: Arc<ConnectionContext>) {
    loop {
        let Ok((stream, peer)) = listener.accept().await else {
            // Out of handles or the listener is in a bad state; spinning on it
            // would burn a core, so stop this listener entirely.
            tracing::error!("the listener stopped accepting");
            return;
        };
        let context = context.clone();
        tokio::spawn(async move {
            if let Err(error) = handle_connection(stream, context).await {
                tracing::debug!(%peer, %error, "a connection ended with an error");
            }
        });
    }
}

/// Routes one accepted stream: WebSocket, page, or nothing.
async fn handle_connection(
    mut stream: tokio::net::TcpStream,
    context: Arc<ConnectionContext>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let request_line = match http::peek_request_line(&stream).await {
        Ok(line) => line,
        Err(_) => return Ok(()),
    };

    match http::route(&request_line) {
        Route::WebSocket => {
            let socket = ws::upgrade(stream, &context).await?;
            ws::serve(socket, context).await;
        }
        Route::Page => {
            let path = request_line
                .split_whitespace()
                .nth(1)
                .unwrap_or("/")
                .split('?')
                .next()
                .unwrap_or("/")
                .to_string();
            http::serve_page(&mut stream, &path, context.config.web_root.as_deref()).await?;
        }
        Route::NotFound => http::serve_error(&mut stream, "404 Not Found").await?,
    }
    Ok(())
}
