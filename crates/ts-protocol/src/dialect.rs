use serde::{Deserialize, Serialize};

/// Which flavour of TeamSpeak server we are talking to.
///
/// Servers cannot be told apart by port (§34) — a TeaSpeak server answers on the
/// same ports as a stock one — so the difference has to be resolved during the
/// handshake. This value controls how that happens.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Dialect {
    /// Ask the server and adapt. The right default for a client, where the user
    /// should not have to know what software the server runs.
    #[default]
    Auto,
    /// Behave as a stock TeamSpeak server: skip the TeaSpeak handshake.
    TeamSpeak,
    /// Always perform the TeaSpeak handshake.
    TeaSpeak,
}

impl Dialect {
    /// Whether detection should run during the handshake.
    #[must_use]
    pub const fn is_auto(self) -> bool {
        matches!(self, Self::Auto)
    }

    /// The flavour this resolves to when detection is off.
    #[must_use]
    pub const fn forced(self) -> Option<Self> {
        match self {
            Self::Auto => None,
            forced => Some(forced),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_is_the_default() {
        assert_eq!(Dialect::default(), Dialect::Auto);
        assert!(Dialect::default().is_auto());
    }

    #[test]
    fn only_auto_defers_detection() {
        assert_eq!(Dialect::TeamSpeak.forced(), Some(Dialect::TeamSpeak));
        assert_eq!(Dialect::TeaSpeak.forced(), Some(Dialect::TeaSpeak));
        assert_eq!(Dialect::Auto.forced(), None);
    }
}
