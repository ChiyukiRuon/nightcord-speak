//! The WebSocket front-end: one core, N browser connections.
//!
//! The shape mirrors `ts-ffi`'s, with a socket where the C ABI was: a worker
//! owns the `ts_core::Client`, connections send commands and receive a
//! broadcast of events and results. What is shared with the desktop is the
//! vocabulary ([`ts_wire`]) and the core, not a translation of either.
//!
//! Two things this crate deliberately is not:
//!
//! - **Not a hosted service.** One gateway is one TS identity on one machine,
//!   the browser is a remote control for it. Multi-user hosting would be a
//!   different product with different problems (identity per visitor,
//!   server-side audio mixing, accounts); `docs/gateway.md` records the
//!   boundary.
//! - **Not a static file server.** It answers four URLs — the page, its
//!   worklet, `/ws`, and 404 — because the embedded debug page has to come
//!   from *somewhere* on the same origin. Deployments serve the page from
//!   Cloudflare Pages and use the gateway for `/ws` only.

mod config;
mod http;
mod voice;
mod worker;
mod ws;

use std::net::SocketAddr;
use std::sync::Arc;
use std::sync::atomic::AtomicU64;

use tokio::net::TcpListener;
use tokio::sync::{broadcast, mpsc};
use ts_core::Client as CoreClient;
use ts_identity::IdentityStore;
use ts_settings::{BookmarkStore, SettingsStore};

pub use config::{GatewayConfig, generate_token};
use http::Route;
use worker::{GatewayCommand, Worker};
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
        let core = self.build_core()?;

        let (outbound, _) = broadcast::channel(OUTBOUND_CAPACITY);
        let (commands, command_rx) = mpsc::unbounded_channel();
        let worker = tokio::spawn(
            Worker::new(
                core,
                self.config.profile.clone(),
                outbound.clone(),
                command_rx,
            )
            .run(),
        );

        let context = Arc::new(ConnectionContext {
            config: self.config.clone(),
            outbound,
            commands: commands.clone(),
            next_connection: AtomicU64::new(1),
        });

        let mut accepts = Vec::with_capacity(self.listeners.len());
        for listener in self.listeners {
            accepts.push(tokio::spawn(accept_loop(listener, context.clone())));
        }

        shutdown.await;

        let _ = commands.send(GatewayCommand::Shutdown);
        // The worker disconnects every session on its way out, which is what
        // keeps the server from holding a stale client for this identity.
        let _ = worker.await;
        for accept in accepts {
            accept.abort();
        }
        tracing::info!("the gateway stopped");
        Ok(())
    }

    /// Builds the client with the configured profile and stores.
    fn build_core(&self) -> Result<CoreClient, GatewayError> {
        let (identities, settings, bookmarks) = match &self.config.data_dir {
            Some(dir) => (
                IdentityStore::new(dir),
                SettingsStore::new(dir),
                BookmarkStore::new(dir),
            ),
            None => (
                IdentityStore::platform_default().map_err(|_| {
                    ts_model::ClientError::Identity(ts_model::IdentityError::NoStorageRoot)
                })?,
                SettingsStore::platform_default().map_err(|_| {
                    ts_model::ClientError::Settings(ts_model::SettingsError::NoStorageRoot)
                })?,
                BookmarkStore::platform_default().map_err(|_| {
                    ts_model::ClientError::Settings(ts_model::SettingsError::NoStorageRoot)
                })?,
            ),
        };
        Ok(CoreClient::new(identities, settings, bookmarks))
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
