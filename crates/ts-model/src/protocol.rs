use serde::{Deserialize, Serialize};

/// Which TeamSpeak dialect a server speaks.
///
/// Deliberately kept to two variants for now. TeaSpeak and GreenTeaSpeak are
/// planned, but adding them before the TS3 and TS6 backends are stable would
/// make this enum a lie about what the client can actually talk to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProtocolKind {
    /// TeamSpeak 3.
    Ts3,
    /// TeamSpeak 6, which is still in beta upstream.
    Ts6,
}

impl ProtocolKind {
    /// A short label suitable for a server tab.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Ts3 => "TS3",
            Self::Ts6 => "TS6",
        }
    }
}

impl std::fmt::Display for ProtocolKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.label())
    }
}
