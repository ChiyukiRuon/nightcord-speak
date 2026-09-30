//! The one error vocabulary used above the protocol backends.
//!
//! Both backends and (later) the audio engine normalise into [`ClientError`]
//! before an error crosses the FFI boundary, so a front-end matches on a single
//! enum and never sees a `tsclientlib` or `cpal` error (§37).
//!
//! Every type here is `Serialize`, because errors travel to Dart as JSON.

use serde::{Deserialize, Serialize};

/// Everything that can go wrong, in one place.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(tag = "kind", content = "detail", rename_all = "snake_case")]
pub enum ClientError {
    /// The transport failed — DNS, TCP, UDP or TLS. Never a protocol violation.
    #[error("network error: {0}")]
    Network(NetworkError),

    /// The peer sent something unparseable, or violated the protocol.
    #[error("protocol error: {0}")]
    Protocol(ProtocolError),

    /// The server rejected the connection, the identity or the credentials.
    #[error("authentication error: {0}")]
    Authentication(AuthError),

    /// Sending or receiving voice failed.
    #[error("voice error: {0}")]
    Voice(VoiceError),

    /// A local audio device failed.
    #[error("audio error: {0}")]
    Audio(AudioError),

    /// The client identity could not be loaded, generated or stored.
    #[error("identity error: {0}")]
    Identity(IdentityError),

    /// The user's settings could not be read or written.
    #[error("settings error: {0}")]
    Settings(SettingsError),

    /// The server refused an operation for permission reasons.
    #[error("permission error: {0}")]
    Permission(PermissionError),

    /// A server address could not be parsed.
    ///
    /// The reason is left to the source error: repeating it here would make an
    /// anyhow error chain print it twice.
    #[error("invalid server address")]
    InvalidAddress(#[from] AddressError),

    /// An operation did not complete in time.
    #[error("operation timed out")]
    Timeout,

    /// The server or protocol cannot do this.
    #[error("unsupported: {0}")]
    Unsupported(String),
}

impl ClientError {
    /// Whether running the same operation again could plausibly succeed.
    ///
    /// Drives the reconnect decision: a dropped socket is worth retrying, a
    /// rejected password is not.
    #[must_use]
    pub const fn is_retryable(&self) -> bool {
        matches!(self, Self::Network(_) | Self::Timeout)
    }

    /// Whether this failure means the credentials or identity are wrong.
    #[must_use]
    pub const fn is_auth_failure(&self) -> bool {
        matches!(self, Self::Authentication(_))
    }
}

/// The transport failed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[error("{message}")]
pub struct NetworkError {
    /// Human-readable description, for logs and for the UI.
    pub message: String,
    /// Host being contacted, when known.
    pub host: Option<String>,
    /// Port being contacted, when known.
    pub port: Option<u16>,
}

impl NetworkError {
    /// An error with no target attached.
    #[must_use]
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            host: None,
            port: None,
        }
    }

    /// Attaches the address that was being contacted.
    #[must_use]
    pub fn with_target(mut self, host: impl Into<String>, port: u16) -> Self {
        self.host = Some(host.into());
        self.port = Some(port);
        self
    }

    /// A connection attempt exceeded its deadline.
    #[must_use]
    pub fn timeout(host: impl Into<String>, port: u16) -> Self {
        Self::new("connection attempt timed out").with_target(host, port)
    }

    /// The host name could not be resolved.
    #[must_use]
    pub fn resolve_failed(host: impl Into<String>, port: u16) -> Self {
        Self::new("could not resolve host").with_target(host, port)
    }
}

/// The peer said something we could not handle.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[error("{message}")]
pub struct ProtocolError {
    /// Human-readable description.
    pub message: String,
    /// Server-reported error id, when the failure came from a response.
    pub server_code: Option<u32>,
}

impl ProtocolError {
    /// An error with no server code.
    #[must_use]
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            server_code: None,
        }
    }

    /// An error carrying a server-reported code.
    #[must_use]
    pub fn from_server(code: u32, message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            server_code: Some(code),
        }
    }
}

/// The server refused us.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum AuthError {
    /// The server needs a password before it will let us in.
    #[error("the server requires a password")]
    ServerPasswordRequired,
    /// The target channel needs a password.
    #[error("the channel requires a password")]
    ChannelPasswordRequired,
    /// The identity was malformed or rejected.
    #[error("the server rejected this identity")]
    InvalidIdentity,
    /// A privilege key was supplied and refused.
    #[error("the privilege key was rejected")]
    InvalidPrivilegeKey,
    /// The requested nickname is taken.
    #[error("that nickname is already in use")]
    NicknameInUse,
}

/// Voice failed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum VoiceError {
    /// Voice was attempted with no live session.
    #[error("not connected")]
    NotConnected,
    /// The negotiated codec is not one we implement.
    #[error("the server selected an unsupported codec")]
    UnsupportedCodec,
    /// A received voice packet could not be decoded.
    #[error("could not decode a voice packet")]
    DecodeFailed,
    /// A captured frame could not be encoded.
    #[error("could not encode a voice packet")]
    EncodeFailed,
    /// Voice encryption failed.
    #[error("voice encryption failed")]
    EncryptionFailed,
}

/// A local audio device failed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum AudioError {
    /// The named device is gone.
    #[error("no such audio device: {name}")]
    DeviceNotFound {
        /// The name that was requested.
        name: String,
    },
    /// The host has no capture device.
    #[error("no input device is available")]
    NoInputDevice,
    /// The host has no playback device.
    #[error("no output device is available")]
    NoOutputDevice,
    /// The audio host itself reported a failure.
    #[error("audio backend failure: {message}")]
    Backend {
        /// Description from the underlying library.
        message: String,
    },
    /// The device cannot provide the stream layout we need.
    #[error("the requested stream configuration is not supported")]
    UnsupportedConfig,
}

/// The persistent client identity could not be read, written or parsed.
///
/// Worth distinguishing from a generic I/O failure because the consequences
/// differ: a server treats a regenerated identity as an entirely new client, so
/// silently recovering from these would lose the user's permissions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum IdentityError {
    /// Reading or writing the identity file failed.
    #[error("identity storage failed: {message}")]
    Io {
        /// Description from the filesystem.
        message: String,
    },
    /// The stored identity could not be parsed.
    #[error("stored identity is malformed: {message}")]
    Malformed {
        /// Why it could not be parsed.
        message: String,
    },
    /// A profile name was not usable as a file name.
    #[error("invalid identity name `{name}`")]
    InvalidName {
        /// The rejected name.
        name: String,
    },
    /// No platform data directory could be determined.
    #[error("could not determine the application data directory")]
    NoStorageRoot,
}

/// The user's settings could not be read or written.
///
/// Deliberately *not* sharing [`IdentityError`]'s severity. A settings file that
/// cannot be read is worth a warning and a fall back to defaults; a client that
/// refuses to start because a preference file is malformed has turned a cosmetic
/// problem into a fatal one. This type carries the reason so the caller can make
/// that call, rather than making it here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum SettingsError {
    /// Reading or writing the settings file failed.
    #[error("settings storage failed: {message}")]
    Io {
        /// Description from the filesystem.
        message: String,
    },
    /// The file exists but could not be parsed.
    ///
    /// The message carries the file it was wrong *in*: this error is returned
    /// for both of the files this crate's stores own, and a message that named
    /// one of them would be actively misleading about the other.
    #[error("{message}")]
    Malformed {
        /// What was wrong, and in which file.
        message: String,
    },
    /// No platform data directory could be determined.
    #[error("could not determine the application data directory")]
    NoStorageRoot,
}

/// The server refused an operation for permission reasons.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum PermissionError {
    /// Permission denied, with no further detail from the server.
    #[error("permission denied")]
    Denied,
    /// Permission denied for a named action, so the UI can say which.
    #[error("permission denied: cannot {action}")]
    DeniedFor {
        /// The action that was refused.
        action: String,
    },
    /// The server refused because one specific permission was missing.
    ///
    /// Separate from [`PermissionError::DeniedFor`] because a numeric
    /// permission id is not an action: rendering it as "cannot #218" reads as
    /// nonsense. A front-end can map the id to a name if it has the table.
    #[error("missing permission #{permission}")]
    MissingPermission {
        /// The TS3/TS6 permission id that was required.
        permission: u32,
    },
}

/// A server address could not be parsed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[error("{message}")]
pub struct AddressError {
    /// Human-readable description.
    pub message: String,
    /// The input that failed to parse.
    pub input: String,
}

impl AddressError {
    /// Builds an error for `input` with an explanation.
    #[must_use]
    pub fn new(input: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            input: input.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retryability_classification() {
        assert!(ClientError::Timeout.is_retryable());
        assert!(ClientError::Network(NetworkError::new("boom")).is_retryable());
        assert!(!ClientError::Authentication(AuthError::InvalidIdentity).is_retryable());
        assert!(!ClientError::Permission(PermissionError::Denied).is_retryable());
    }

    #[test]
    fn errors_survive_a_json_round_trip() {
        // The FFI layer sends errors to Dart as JSON, so this must not regress.
        let cases = vec![
            ClientError::Timeout,
            ClientError::Unsupported("whisper".into()),
            ClientError::Network(NetworkError::timeout("example.com", 9987)),
            ClientError::Protocol(ProtocolError::from_server(2568, "invalid channel")),
            ClientError::Authentication(AuthError::ServerPasswordRequired),
            ClientError::Audio(AudioError::DeviceNotFound {
                name: "Speakers".into(),
            }),
            ClientError::Permission(PermissionError::DeniedFor {
                action: "kick".into(),
            }),
            ClientError::Identity(IdentityError::NoStorageRoot),
            ClientError::Identity(IdentityError::Malformed {
                message: "bad base64".into(),
            }),
        ];

        for case in cases {
            let json = serde_json::to_string(&case).expect("serialize");
            let back: ClientError = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(case, back, "round trip changed {json}");
        }
    }

    #[test]
    fn network_error_serializes_its_target() {
        let json = serde_json::to_value(NetworkError::timeout("example.com", 9987)).unwrap();
        assert_eq!(json["host"], "example.com");
        assert_eq!(json["port"], 9987);
    }
}
