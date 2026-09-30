//! The gateway process: one core, one WebSocket, browser front-ends.
//!
//! Everything interesting lives in `ts-gateway`; this file is argument
//! parsing, logging, the shutdown signal, and an exit code — the same shape
//! as `nightcord-cli`'s.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context as _, Result};
use clap::Parser;
use ts_gateway::{Gateway, GatewayConfig};

/// Runs a Nightcord Speak core behind a WebSocket for browser front-ends.
#[derive(Debug, Parser)]
#[command(name = "nightcord-gateway", version, about)]
struct Args {
    /// Addresses to listen on, e.g. `127.0.0.1:8787`.
    ///
    /// Defaults to both loopback addresses — `localhost` resolves to `::1`
    /// first on some systems, and a browser that tries one and fails is a
    /// confusing first experience.
    ///
    /// Binding anything else exposes the client to the network: a holder of
    /// the token can drive it, and Windows will ask about the firewall the
    /// first time a remote host connects. Prefer a tunnel (`cloudflared`,
    /// a reverse proxy) over exposing the port directly — `docs/gateway.md`.
    #[arg(long = "bind", value_name = "ADDR")]
    bind: Vec<SocketAddr>,

    /// The shared secret browsers must present. Generated and printed when
    /// absent; `NIGHTCORD_GATEWAY_TOKEN` is also read, so a service manager
    /// can keep it out of the command line.
    #[arg(long, env = "NIGHTCORD_GATEWAY_TOKEN")]
    token: Option<String>,

    /// A browser origin allowed to connect, e.g. `https://x.pages.dev`.
    ///
    /// May be repeated. Anything non-empty replaces the default (loopback
    /// origins, any port) — the deployed page's origin must be listed here.
    #[arg(long = "allow-origin", value_name = "ORIGIN")]
    allow_origin: Vec<String>,

    /// The identity profile the gateway's client presents.
    ///
    /// Deliberately not `default`: TS3 refuses a second connection from the
    /// same identity while the desktop app holds one.
    #[arg(long, default_value = "web")]
    profile: String,

    /// Where the client's stores live, instead of the platform default.
    ///
    /// Keeps a run's identity, settings and bookmarks out of the real
    /// profile — the same flag the CLI has.
    #[arg(long, value_name = "DIR")]
    data_dir: Option<PathBuf>,

    /// A directory holding `index.html` and `pcm-worklet.js`, instead of the
    /// embedded copies.
    #[arg(long, value_name = "DIR")]
    web_root: Option<PathBuf>,
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("failed: {error:#}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<()> {
    let args = Args::parse();
    init_logging();

    let bind = if args.bind.is_empty() {
        vec![
            "127.0.0.1:8787".parse().expect("a literal address"),
            "[::1]:8787".parse().expect("a literal address"),
        ]
    } else {
        args.bind.clone()
    };

    let generated = args.token.is_none();
    let mut config = GatewayConfig::new(bind);
    if let Some(token) = &args.token {
        config.token = token.clone();
    }
    config.allowed_origins = args.allow_origin;
    config.profile = args.profile;
    config.data_dir = args.data_dir;
    config.web_root = args.web_root;

    // Read back out of the config rather than out of `args`: with no `--token`
    // the config is the only place the generated one exists, and the line
    // printed below is the only place it is ever shown. Taking it from `args`
    // meant a run that let the gateway generate a token announced `…` — the
    // operator was handed a placeholder for the one secret they have to carry
    // to the browser.
    let token = config.token.clone();

    let runtime = tokio::runtime::Runtime::new().context("could not start the runtime")?;
    runtime.block_on(async move {
        let bound = Gateway::new(config).bind().await?;
        let addrs = bound.local_addrs().context("local addresses")?;
        for addr in &addrs {
            tracing::info!(%addr, "listening");
        }

        // Printed to stdout as well as logged: the token is the one thing the
        // person starting the gateway has to carry to the browser, and a log
        // file is not where they are looking.
        println!("nightcord-gateway listening on {addrs:?}");
        if generated {
            println!("token: {token}");
        }
        println!(
            "open http://{}/ for the debug page",
            first_http_addr(&addrs)
        );

        let (shutdown, shutdown_rx) = tokio::sync::oneshot::channel();
        tokio::spawn(async move {
            let _ = tokio::signal::ctrl_c().await;
            let _ = shutdown.send(());
        });

        bound
            .serve(async move {
                let _ = shutdown_rx.await;
            })
            .await?;
        Ok::<(), anyhow::Error>(())
    })
}

/// The address to print a URL for: prefer the v4 loopback so the URL is one
/// people can click without bracket surgery.
fn first_http_addr(addrs: &[SocketAddr]) -> String {
    addrs
        .iter()
        .find(|addr| addr.is_ipv4())
        .unwrap_or(&addrs[0])
        .to_string()
}

/// logging: file when the platform has an application directory, stderr
/// always — a gateway is usually started by a service manager or a terminal
/// that keeps the output.
fn init_logging() {
    let dir = ts_identity::app_data_root().map(|root| root.join("logs"));
    let _sink = ts_logging::init(dir.as_deref());
    tracing::info!("nightcord-gateway starting");
}
