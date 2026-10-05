//! What a gateway needs to be told before it can serve.

use std::net::SocketAddr;
use std::path::PathBuf;

/// Everything the caller decides: where to listen, who may speak, and where
/// the client's stores live.
#[derive(Clone)]
pub struct GatewayConfig {
    /// The addresses to listen on.
    ///
    /// Two by default — `127.0.0.1` and `[::1]` — because `localhost` resolves
    /// to `::1` first on some setups (this machine's included: its IPv6
    /// prefix policy gives `::1/128` precedence 50 over `::/0` at 40), and a
    /// gateway bound to only one of them gets `ECONNREFUSED` from half the
    /// URLs a user might type.
    pub bind: Vec<SocketAddr>,

    /// Optional shared secret. Empty disables token authentication; Origin
    /// restrictions still apply before the socket upgrade.
    pub token: String,

    /// Origins the browser may connect from, matched exactly (`scheme://host`
    /// with any port).
    ///
    /// Empty means the default policy: localhost origins, any port — which is
    /// what the embedded debug page and local development use. A connection
    /// without an `Origin` header at all (a test client, a native app) is
    /// always allowed; it is not a browser being borrowed by a page.
    pub allowed_origins: Vec<String>,

    /// Profile name within each device's isolated identity store.
    pub profile: String,

    /// Where the client's stores live. `None` uses the platform default — the
    /// same `%APPDATA%` directory the desktop app and CLI use; tests point it
    /// at a temporary directory.
    ///
    /// Each device's identity, settings, bookmarks and credential live under
    /// `devices/<public-id>/` within this directory.
    pub data_dir: Option<PathBuf>,

    /// A directory to serve the page from. `None` serves the embedded copy of
    /// `web/index.html`. This is a diagnostic page; Pages hosts Flutter's build.
    pub web_root: Option<PathBuf>,
}

impl std::fmt::Debug for GatewayConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Configuration may be inspected during diagnosis; never expose a key.
        f.debug_struct("GatewayConfig")
            .field("bind", &self.bind)
            .field(
                "token",
                &if self.token.is_empty() {
                    "<unset>"
                } else {
                    "<set>"
                },
            )
            .field("allowed_origins", &self.allowed_origins)
            .field("profile", &self.profile)
            .field("data_dir", &self.data_dir)
            .field("web_root", &self.web_root)
            .finish()
    }
}

impl GatewayConfig {
    /// A configuration for `bind` with token authentication disabled.
    #[must_use]
    pub fn new(bind: Vec<SocketAddr>) -> Self {
        Self {
            bind,
            token: String::new(),
            allowed_origins: Vec::new(),
            profile: "web".to_string(),
            data_dir: None,
            web_root: None,
        }
    }

    /// Whether a browser origin may connect.
    ///
    /// `None` (no `Origin` header) is allowed: only browsers send one, and the
    /// configured token authentication still applies.
    #[must_use]
    pub fn origin_allowed(&self, origin: Option<&str>) -> bool {
        let Some(origin) = origin else { return true };

        if !self.allowed_origins.is_empty() {
            return self
                .allowed_origins
                .iter()
                .any(|allowed| origin_matches(allowed, origin));
        }

        // The default policy: pages served from this machine. Ports are
        // whatever the page happens to be on, so they are not compared.
        let Some(host) = host_of(origin) else {
            return false;
        };
        let host = host.trim_start_matches('[').trim_end_matches(']');
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

/// Whether `pattern` (`scheme://host`, port optional) matches `origin`.
fn origin_matches(pattern: &str, origin: &str) -> bool {
    let (Some(pattern_scheme), Some(origin_scheme)) = (scheme_of(pattern), scheme_of(origin))
    else {
        return false;
    };
    if !pattern_scheme.eq_ignore_ascii_case(origin_scheme) {
        return false;
    }
    match (host_of(pattern), host_of(origin)) {
        (Some(pattern_host), Some(origin_host)) => pattern_host.eq_ignore_ascii_case(origin_host),
        _ => false,
    }
}

/// The scheme half of an origin or pattern, if it has one.
fn scheme_of(value: &str) -> Option<&str> {
    value.split_once("://").map(|(scheme, _)| scheme)
}

/// The host half, with the port and any brackets stripped.
fn host_of(value: &str) -> Option<&str> {
    let (_, rest) = value.split_once("://")?;
    let host = rest.split('/').next()?;
    // An IPv6 host is bracketed (`http://[::1]:8080`); a bare host is not.
    if let Some(end) = host.find(']') {
        return host.get(1..end);
    }
    Some(host.split(':').next().unwrap_or(host))
}

/// A fresh token: 32 hex characters from the operating system's entropy.
///
/// Hex rather than base64 so it survives being read out of a terminal, pasted
/// into a URL query string, or copied by eye — it is a shared secret people
/// have to move around by hand.
#[must_use]
pub fn generate_token() -> String {
    let mut bytes = [0u8; 16];
    // The OS generator is infallible on every platform this ships on; a
    // fallback would be a weaker token pretending to be a strong one.
    getrandom::getrandom(&mut bytes).expect("the operating system entropy source");
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_never_exposes_token() {
        // Diagnostic formatting previously included the entire shared secret.
        let mut config = GatewayConfig::new(Vec::new());
        config.token = "private-gateway-credential".into();
        let debug = format!("{config:?}");
        assert!(!debug.contains(&config.token));
        assert!(debug.contains("<set>"));
        config.token.clear();
        assert!(format!("{config:?}").contains("<unset>"));
    }

    fn config() -> GatewayConfig {
        let mut config = GatewayConfig::new(Vec::new());
        config.token = "test-token".into();
        config
    }

    #[test]
    fn a_non_browser_client_needs_no_origin() {
        // The integration tests and `wscat` send no Origin header; they are not
        // a page being borrowed.
        assert!(config().origin_allowed(None));
    }

    #[test]
    fn the_default_policy_allows_loopback_pages_and_nothing_else() {
        let config = config();
        for origin in [
            "http://localhost:8080",
            "http://127.0.0.1:1234",
            "https://localhost",
            "http://[::1]:9000",
        ] {
            assert!(config.origin_allowed(Some(origin)), "{origin}");
        }
        for origin in [
            "https://evil.example",
            "http://localhost.evil.example",
            "https://pages.dev",
            "not-an-origin",
        ] {
            assert!(!config.origin_allowed(Some(origin)), "{origin}");
        }
    }

    #[test]
    fn an_explicit_allowlist_replaces_the_default_and_ignores_ports() {
        // The deployed page's origin is what someone would paste; the port is
        // assigned per deployment and would be wrong by the time it is copied.
        let mut config = config();
        config.allowed_origins = vec!["https://nightcord.pages.dev".into()];

        assert!(config.origin_allowed(Some("https://nightcord.pages.dev")));
        assert!(config.origin_allowed(Some("https://nightcord.pages.dev:8443")));
        assert!(
            !config.origin_allowed(Some("http://localhost:9999")),
            "the allowlist replaces the default rather than adding to it"
        );
        assert!(!config.origin_allowed(Some("https://nightcord.pages.dev.evil.example")));
    }

    #[test]
    fn tokens_are_long_and_not_repeated() {
        let first = generate_token();
        let second = generate_token();
        assert_eq!(first.len(), 32);
        assert!(first.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(first, second, "two tokens in a row must not collide");
    }
}
