//! The JSON vocabulary every front-end speaks.
//!
//! Two front-ends ask the core for things — the Flutter app through the C ABI,
//! the web through the gateway (`docs/gateway.md`) — and this crate is the one
//! spelling of what they may ask for ([`Command`]) and of what comes back
//! ([`FfiEvent`]). Sharing it is what keeps "the web can do what the desktop
//! can" a property of the code rather than a promise (§52).
//!
//! What lives here is vocabulary only: no queue, no transport, no entry
//! points. `ts-ffi` keeps the C ABI and its polling queue; `ts-gateway` keeps
//! the WebSocket and its fan-out.
//!
//! # Two wire shapes, one vocabulary
//!
//! - `ts-ffi` takes **one JSON argument per C entry point** and builds a
//!   [`Command`] by hand (the Dart side is built against exactly that).
//! - The gateway takes a **tagged envelope** — `{"command": …, "payload": …}` —
//!   deserialised with the derives below. That envelope is new surface defined
//!   for the web; the ABI never uses it.

mod command;
mod event;

pub use command::{AudioDirection, Command};
pub use event::{CommandOutcome, FfiEvent};
