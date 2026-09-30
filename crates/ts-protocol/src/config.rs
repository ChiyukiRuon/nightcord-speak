use std::fmt;

use ts_identity::Identity;
use ts_model::{ConnectionTarget, ReconnectPolicy};

use crate::Dialect;

/// Everything needed to open one connection.
///
/// This carries secrets — a server password, a channel password, a privilege
/// key, and a private identity — so its [`fmt::Debug`] output is redacted.
/// Nothing else in the codebase may print a `ConnectionConfig` with `{:?}` and
/// expect to see the credentials (§44).
#[derive(Clone, PartialEq, Eq)]
pub struct ConnectionConfig {
    /// Where to connect. Parsed from user input before it gets here.
    pub target: ConnectionTarget,

    /// Nickname to appear under on the server.
    pub nickname: String,

    /// The identity to present. Loaded from [`ts_identity::IdentityStore`], never
    /// generated per connection (§36).
    pub identity: Identity,

    /// Password for the server itself, if it has one.
    pub server_password: Option<String>,

    /// Password for the channel we want to join, if it has one.
    pub channel_password: Option<String>,

    /// Privilege key to redeem on connect.
    pub privilege_key: Option<String>,

    /// Channel to join instead of the server's default, given by name or path.
    pub default_channel: Option<String>,

    /// Which server flavour to expect, or how to find out.
    pub dialect: Dialect,

    /// How hard to try to keep this connection alive.
    ///
    /// Carried here rather than read from the settings by the backend, because
    /// this struct is already everything a rebuild needs: the reconnect is
    /// driven inside the backend that owns the connection, and it must not
    /// grow a second source of configuration to do it.
    pub reconnect: ReconnectPolicy,
}

impl ConnectionConfig {
    /// A config for `target` as `nickname`, with `identity` and no secrets.
    #[must_use]
    pub fn new(target: ConnectionTarget, nickname: impl Into<String>, identity: Identity) -> Self {
        Self {
            target,
            nickname: nickname.into(),
            identity,
            server_password: None,
            channel_password: None,
            privilege_key: None,
            default_channel: None,
            dialect: Dialect::default(),
            reconnect: ReconnectPolicy::default(),
        }
    }

    /// Whether any credential is set, so callers can avoid touching the secret
    /// fields when there is nothing to protect.
    #[must_use]
    pub fn has_secrets(&self) -> bool {
        self.server_password.is_some()
            || self.channel_password.is_some()
            || self.privilege_key.is_some()
    }

    /// The `host:port` this config points at.
    #[must_use]
    pub fn endpoint(&self) -> String {
        self.target.to_string()
    }
}

impl fmt::Debug for ConnectionConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // Secrets are reported as present-or-absent, never by value. The
        // identity's own `Debug` already redacts the key material.
        f.debug_struct("ConnectionConfig")
            .field("target", &self.target)
            .field("nickname", &self.nickname)
            .field("identity", &self.identity)
            .field("server_password", &Redacted(self.server_password.is_some()))
            .field(
                "channel_password",
                &Redacted(self.channel_password.is_some()),
            )
            .field("privilege_key", &Redacted(self.privilege_key.is_some()))
            .field("default_channel", &self.default_channel)
            .field("dialect", &self.dialect)
            .field("reconnect", &self.reconnect)
            .finish()
    }
}

/// Renders a secret as set/unset rather than by value.
struct Redacted(bool);

impl fmt::Debug for Redacted {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(if self.0 { "<set>" } else { "<unset>" })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::DEFAULT_PORT;

    fn config() -> ConnectionConfig {
        ConnectionConfig::new(
            ConnectionTarget::new("example.com", DEFAULT_PORT),
            "Tester",
            Identity::new("uid=", vec![1, 2, 3]),
        )
    }

    #[test]
    fn debug_never_prints_secrets() {
        let mut cfg = config();
        cfg.server_password = Some("hunter2".into());
        cfg.channel_password = Some("s3cret".into());
        cfg.privilege_key = Some("key-material".into());

        let rendered = format!("{cfg:?}");

        for secret in ["hunter2", "s3cret", "key-material"] {
            assert!(
                !rendered.contains(secret),
                "debug leaked `{secret}`: {rendered}"
            );
        }
        // The blob must not appear either.
        assert!(
            !rendered.contains("[1, 2, 3"),
            "debug leaked the identity: {rendered}"
        );
        assert!(
            rendered.contains("<set>"),
            "secrets should be reported as set: {rendered}"
        );
    }

    #[test]
    fn has_secrets_tracks_the_optional_fields() {
        let mut cfg = config();
        assert!(!cfg.has_secrets());
        cfg.server_password = Some("x".into());
        assert!(cfg.has_secrets());
    }

    #[test]
    fn endpoint_is_rendered_with_the_port() {
        assert_eq!(config().endpoint(), "example.com:9987");
    }
}
