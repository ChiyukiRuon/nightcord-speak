use serde::{Deserialize, Serialize};
use ts_model::ProtocolKind;
use ts_protocol::Dialect;

/// Everything a front-end supplies to open a connection.
///
/// This is the shape that crosses the FFI boundary as JSON, so it is the one
/// struct in the core that is deliberately dumb: strings and options only, no
/// parsed types. Credentials live here because the user types them, but the
/// *identity* does not — the core owns that and never hands it out (§31, §44).
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectRequest {
    /// `host`, `host:port`, `ts3://host`, `[::1]:9987` — see
    /// [`ts_model::ConnectionTarget::parse`].
    pub address: String,

    /// Nickname to appear under on the server.
    pub nickname: String,

    /// Profile name the stored identity is filed under.
    ///
    /// Two servers with the same profile present the same client identity,
    /// which is what a user expects: one identity per person, not per server.
    #[serde(default = "default_profile")]
    pub profile: String,

    /// Password for the server itself.
    #[serde(default)]
    pub server_password: Option<String>,

    /// Password for the channel being joined.
    #[serde(default)]
    pub channel_password: Option<String>,

    /// Privilege key to redeem on connect.
    #[serde(default)]
    pub privilege_key: Option<String>,

    /// Channel to join instead of the server's default, by name or path.
    #[serde(default)]
    pub default_channel: Option<String>,

    /// Which backend to use.
    #[serde(default = "default_protocol")]
    pub protocol: ProtocolKind,

    /// Which server flavour to expect, or how to detect it.
    #[serde(default)]
    pub dialect: Dialect,
}

impl ConnectRequest {
    /// A request for `address` as `nickname`, using everything else's default.
    #[must_use]
    pub fn new(address: impl Into<String>, nickname: impl Into<String>) -> Self {
        Self {
            address: address.into(),
            nickname: nickname.into(),
            profile: default_profile(),
            server_password: None,
            channel_password: None,
            privilege_key: None,
            default_channel: None,
            protocol: default_protocol(),
            dialect: Dialect::default(),
        }
    }

    /// The identity profile this request resolves to.
    #[must_use]
    pub fn profile(&self) -> &str {
        if self.profile.trim().is_empty() {
            DEFAULT_PROFILE
        } else {
            &self.profile
        }
    }
}

impl std::fmt::Debug for ConnectRequest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Secrets are reported as set or unset, never by value (§44).
        f.debug_struct("ConnectRequest")
            .field("address", &self.address)
            .field("nickname", &self.nickname)
            .field("profile", &self.profile)
            .field(
                "server_password",
                &if self.server_password.is_some() {
                    "<set>"
                } else {
                    "<unset>"
                },
            )
            .field(
                "channel_password",
                &if self.channel_password.is_some() {
                    "<set>"
                } else {
                    "<unset>"
                },
            )
            .field(
                "privilege_key",
                &if self.privilege_key.is_some() {
                    "<set>"
                } else {
                    "<unset>"
                },
            )
            .field("default_channel", &self.default_channel)
            .field("protocol", &self.protocol)
            .field("dialect", &self.dialect)
            .finish()
    }
}

/// The profile used when a request names none.
pub const DEFAULT_PROFILE: &str = "default";

fn default_profile() -> String {
    DEFAULT_PROFILE.to_string()
}

fn default_protocol() -> ProtocolKind {
    // One definition, in the type itself: a request, a saved server and a
    // hand-written file all mean the same thing by "no protocol given".
    ProtocolKind::default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_minimal_request_gets_the_defaults() {
        let request = ConnectRequest::new("example.com", "Tester");
        assert_eq!(request.profile(), DEFAULT_PROFILE);
        assert_eq!(request.protocol, ProtocolKind::Ts3);
        assert_eq!(request.dialect, Dialect::Auto);
        assert!(request.server_password.is_none());
    }

    #[test]
    fn a_blank_profile_falls_back_rather_than_reaching_the_filesystem() {
        // The identity store rejects empty names, so resolve it here instead of
        // turning a blank field into a hard error.
        let mut request = ConnectRequest::new("example.com", "Tester");
        request.profile = "   ".into();
        assert_eq!(request.profile(), DEFAULT_PROFILE);
    }

    #[test]
    fn missing_fields_deserialize_to_defaults() {
        // Dart may send only the fields the user filled in.
        let request: ConnectRequest =
            serde_json::from_str(r#"{"address":"example.com","nickname":"Tester"}"#).unwrap();
        assert_eq!(request.address, "example.com");
        assert_eq!(request.protocol, ProtocolKind::Ts3);
        assert!(request.server_password.is_none());
    }

    #[test]
    fn requests_round_trip_through_json() {
        let mut request = ConnectRequest::new("ts3://example.com:9988/", "Tester");
        request.protocol = ProtocolKind::Ts6;
        request.dialect = Dialect::TeaSpeak;
        request.default_channel = Some("Lobby".into());

        let json = serde_json::to_string(&request).unwrap();
        let back: ConnectRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(back, request);
    }

    #[test]
    fn debug_never_prints_credentials() {
        let mut request = ConnectRequest::new("example.com", "Tester");
        request.server_password = Some("hunter2".into());
        request.channel_password = Some("s3cret".into());
        request.privilege_key = Some("token-material".into());

        let rendered = format!("{request:?}");
        for secret in ["hunter2", "s3cret", "token-material"] {
            assert!(
                !rendered.contains(secret),
                "debug leaked `{secret}`: {rendered}"
            );
        }
        assert!(
            rendered.contains("<set>"),
            "secrets should show as set: {rendered}"
        );
    }
}
