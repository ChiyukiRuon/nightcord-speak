//! Server address parsing (§33).

use std::fmt;

use serde::{Deserialize, Serialize};

use crate::error::AddressError;

/// Port a TeamSpeak client connects to when the address names none.
pub const DEFAULT_PORT: u16 = 9987;

/// A server address, parsed and validated.
///
/// Users type addresses in several shapes — `example.com`, `example.com:9987`,
/// `ts3://example.com`, `[::1]:9987` — and all of them should work. Parsing
/// happens once, here, rather than at each call site.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ConnectionTarget {
    /// Hostname or IP literal, with IPv6 brackets already stripped.
    pub host: String,
    /// TCP/UDP port. Always populated; defaults to [`DEFAULT_PORT`].
    pub port: u16,
}

impl ConnectionTarget {
    /// Builds a target from an explicit host and port.
    #[must_use]
    pub fn new(host: impl Into<String>, port: u16) -> Self {
        Self {
            host: host.into(),
            port,
        }
    }

    /// Parses a user-supplied address.
    ///
    /// # Errors
    ///
    /// Returns [`AddressError`] when the input is empty, names an unknown
    /// scheme, carries an unparseable port, or is a bare IPv6 literal without
    /// the brackets needed to disambiguate it from `host:port`.
    pub fn parse(input: &str) -> Result<Self, AddressError> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return Err(AddressError::new(input, "address is empty"));
        }

        // Accept (and validate) an optional scheme so pasted URLs work.
        let rest = match trimmed.split_once("://") {
            Some((scheme, rest)) => match scheme.to_ascii_lowercase().as_str() {
                "ts3" | "ts6" | "teamspeak" => rest,
                other => {
                    return Err(AddressError::new(
                        input,
                        format!("unknown scheme `{other}`, expected ts3:// or ts6://"),
                    ));
                }
            },
            None => trimmed,
        };

        // A trailing slash or path is meaningless for a client address; drop it
        // rather than failing, since users paste `ts3://host/` out of habit.
        let rest = rest.split(['/', '?', '#']).next().unwrap_or(rest);

        if rest.is_empty() {
            return Err(AddressError::new(input, "address has a scheme but no host"));
        }

        if let Some(after_bracket) = rest.strip_prefix('[') {
            // Bracketed IPv6, optionally followed by `:port`.
            let Some((host, tail)) = after_bracket.split_once(']') else {
                return Err(AddressError::new(input, "unclosed `[` in IPv6 address"));
            };
            if host.is_empty() {
                return Err(AddressError::new(input, "IPv6 address is empty"));
            }
            let port = match tail.strip_prefix(':') {
                Some(port) => parse_port(input, port)?,
                None if tail.is_empty() => DEFAULT_PORT,
                None => return Err(AddressError::new(input, "unexpected text after `]`")),
            };
            return Ok(Self {
                host: host.to_string(),
                port,
            });
        }

        match rest.match_indices(':').count() {
            0 => Ok(Self {
                host: rest.to_string(),
                port: DEFAULT_PORT,
            }),
            1 => {
                let (host, _, port) = split_once_char(rest, ':');
                if host.is_empty() {
                    return Err(AddressError::new(input, "host is empty"));
                }
                Ok(Self {
                    host: host.to_string(),
                    port: parse_port(input, port)?,
                })
            }
            // `::1`, `2001:db8::1` and friends: the port is genuinely ambiguous,
            // so require brackets instead of guessing.
            _ => Err(AddressError::new(
                input,
                "bare IPv6 addresses are ambiguous, write them as [::1]:9987",
            )),
        }
    }
}

fn split_once_char(s: &str, sep: char) -> (&str, char, &str) {
    let idx = s.find(sep).expect("caller checked the separator exists");
    (&s[..idx], sep, &s[idx + sep.len_utf8()..])
}

fn parse_port(input: &str, port: &str) -> Result<u16, AddressError> {
    port.parse::<u16>()
        .map_err(|_| AddressError::new(input, format!("`{port}` is not a valid port")))
}

impl fmt::Display for ConnectionTarget {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // Re-bracket IPv6 so the output parses back into an equal value.
        if self.host.contains(':') {
            write!(f, "[{}]:{}", self.host, self.port)
        } else {
            write!(f, "{}:{}", self.host, self.port)
        }
    }
}

impl std::str::FromStr for ConnectionTarget {
    type Err = AddressError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_host_gets_the_default_port() {
        let target = ConnectionTarget::parse("example.com").unwrap();
        assert_eq!(target.host, "example.com");
        assert_eq!(target.port, DEFAULT_PORT);
    }

    #[test]
    fn explicit_port_wins() {
        assert_eq!(
            ConnectionTarget::parse("example.com:9999").unwrap().port,
            9999
        );
    }

    #[test]
    fn scheme_is_accepted_and_checked() {
        assert_eq!(
            ConnectionTarget::parse("ts3://example.com").unwrap().host,
            "example.com"
        );
        assert_eq!(
            ConnectionTarget::parse("TS6://example.com:1").unwrap().port,
            1
        );
        assert!(ConnectionTarget::parse("http://example.com").is_err());
    }

    #[test]
    fn trailing_path_is_ignored() {
        let target = ConnectionTarget::parse("ts3://example.com:9988/").unwrap();
        assert_eq!(target, ConnectionTarget::new("example.com", 9988));
    }

    #[test]
    fn bracketed_ipv6_round_trips() {
        let target = ConnectionTarget::parse("[::1]:9987").unwrap();
        assert_eq!(target.host, "::1");
        assert_eq!(target.port, 9987);
        assert_eq!(
            ConnectionTarget::parse(&target.to_string()).unwrap(),
            target
        );
    }

    #[test]
    fn bare_ipv6_is_rejected_with_guidance() {
        let err = ConnectionTarget::parse("2001:db8::1").unwrap_err();
        assert!(
            err.message.contains("[::1]:9987"),
            "unhelpful message: {}",
            err.message
        );
    }

    #[test]
    fn whitespace_is_trimmed() {
        assert_eq!(
            ConnectionTarget::parse("  example.com  ").unwrap().host,
            "example.com"
        );
    }

    #[test]
    fn rejects_bad_input() {
        assert!(ConnectionTarget::parse("").is_err());
        assert!(ConnectionTarget::parse("   ").is_err());
        assert!(ConnectionTarget::parse("example.com:notaport").is_err());
        assert!(ConnectionTarget::parse("example.com:70000").is_err());
        assert!(ConnectionTarget::parse("ts3://").is_err());
        assert!(ConnectionTarget::parse("[::1").is_err());
    }
}
