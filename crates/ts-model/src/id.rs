//! Opaque identifiers.
//!
//! Each id is a newtype over its wire representation, so a [`ChannelId`] can
//! never be passed where a [`ClientId`] is expected and the underlying integer
//! can change without touching call sites.

use std::fmt;

use serde::{Deserialize, Serialize};

macro_rules! numeric_id {
    ($(#[$doc:meta])* $name:ident, $inner:ty) => {
        $(#[$doc])*
        #[derive(
            Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize,
        )]
        #[serde(transparent)]
        pub struct $name($inner);

        impl $name {
            /// Wraps a raw value.
            #[must_use]
            pub const fn new(value: $inner) -> Self {
                Self(value)
            }

            /// Returns the raw value.
            #[must_use]
            pub const fn get(self) -> $inner {
                self.0
            }
        }

        impl From<$inner> for $name {
            fn from(value: $inner) -> Self {
                Self(value)
            }
        }

        impl From<$name> for $inner {
            fn from(value: $name) -> Self {
                value.0
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                fmt::Display::fmt(&self.0, f)
            }
        }
    };
}

numeric_id!(
    /// Identifies a server in the local address book.
    ///
    /// Assigned locally and never travels over the wire: it is not a TS3/TS6
    /// concept, it just lets the UI refer to a saved server.
    ServerId,
    u64
);

numeric_id!(
    /// Identifies one live connection.
    ///
    /// The UI only ever holds this handle; the core resolves it against its own
    /// session table, so no Rust object is exposed across the FFI boundary.
    SessionId,
    u32
);

numeric_id!(
    /// Server-assigned channel id, stable for the lifetime of the channel.
    ChannelId,
    u64
);

numeric_id!(
    /// Server-assigned client id.
    ///
    /// Only stable while the client stays connected — reconnecting yields a new
    /// id even for the same user, so it must never be persisted.
    ClientId,
    u16
);

numeric_id!(
    /// Identifies a chat message within one session.
    MessageId,
    u64
);
