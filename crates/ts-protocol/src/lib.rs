//! # ts-protocol
//!
//! The abstraction every TeamSpeak backend implements, and the only thing
//! `ts-session` and `ts-core` are allowed to know about a protocol.
//!
//! ```text
//! ts-session ──▶ ts-protocol ◀── ts-protocol-ts3
//!                          ◀── ts-protocol-ts6
//! ```
//!
//! Nothing here mentions TS3 or TS6. A backend translates its wire format into
//! [`ts_model`] values on the way out and accepts [`ts_model`] values on the way
//! in, so adding TS6 — or replacing `tsclientlib` entirely — cannot change the
//! session layer or the UI (§9, §77).
//!
//! Capabilities are split into narrow traits rather than one wide interface, so
//! a backend can implement chat without pretending to implement voice (§10).

mod config;
mod dialect;
mod traits;
mod voice;

#[cfg(any(test, feature = "testing"))]
pub mod testing;

pub use config::ConnectionConfig;
pub use dialect::Dialect;
pub use traits::{
    AudioSink, Backend, ChannelOperations, ClientOperations, Connection, Messaging, NoVoice,
    PermissionsReport, Presence, ScreenSharing, Voice,
};
pub use voice::{Codec, VoicePacket};
