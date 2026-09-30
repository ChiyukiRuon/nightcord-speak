//! # ts-session
//!
//! The session layer: one [`Session`] per server, all of them collected in a
//! [`SessionManager`].
//!
//! This is the layer that makes "several servers connected at once" a property
//! of the design rather than a feature bolted on later (§16). It knows about
//! [`ts_protocol`] and [`ts_model`] and nothing else — in particular it has no
//! idea whether a session is backed by TS3 or TS6.

mod manager;
mod session;

pub use manager::SessionManager;
pub use session::Session;
