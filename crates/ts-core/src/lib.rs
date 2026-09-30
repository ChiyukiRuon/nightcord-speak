//! # ts-core
//!
//! The facade every front-end drives, and the top of the Rust client.
//!
//! ```text
//! Flutter ──┐
//! CLI    ───┼──▶ ts-core ──▶ ts-session ──▶ ts-protocol ──▶ backend
//! Web    ───┘                  │
//!                              └──▶ ts-events ──▶ front-ends
//! ```
//!
//! This is where a protocol name becomes a concrete backend, and the only crate
//! that depends on both `ts-protocol-ts3` and (later) `ts-protocol-ts6`. Keeping
//! the choice here means the session layer never has to know which protocols
//! exist (§79).

mod client;
mod request;

pub use client::Client;
pub use request::{ConnectRequest, DEFAULT_PROFILE};
