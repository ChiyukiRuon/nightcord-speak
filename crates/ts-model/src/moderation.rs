//! Acting on other people: how far a kick reaches, and how long a ban lasts.
//!
//! These are domain types rather than protocol ones because they are choices a
//! *user* makes — a menu item says "kick from channel", and the wire spelling of
//! that (`reasonid=4`) is a detail no front-end should have to know.

use serde::{Deserialize, Serialize};

/// How far a kick reaches.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KickScope {
    /// Out of the channel they are in, remaining on the server.
    ///
    /// The gentler of the two and the one a moderator usually means.
    #[default]
    Channel,
    /// Off the server entirely.
    Server,
}

/// How long a ban lasts.
///
/// Modelled as a choice rather than a number of seconds because "permanent" is
/// not a duration, and a UI that has to spell it as some very large integer will
/// eventually spell it as a much smaller one by accident.
///
/// The wire convention this hides is worth knowing anyway, because getting it
/// backwards is invisible until somebody is banned forever by mistake: on the
/// wire, **zero seconds means permanent**, and TeamSpeak's own messages carry it
/// as an absent field rather than a zero.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BanDuration {
    /// Until someone lifts it.
    #[default]
    Permanent,
    /// For a fixed number of seconds.
    Seconds(u32),
}

impl BanDuration {
    /// Whether this ban ever expires on its own.
    #[must_use]
    pub const fn is_permanent(self) -> bool {
        matches!(self, Self::Permanent)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permanent_is_the_only_permanent_one() {
        assert!(BanDuration::Permanent.is_permanent());
        // Including zero seconds, which is the wire's spelling of permanent but
        // must never be read back as one: a caller that means "forever" has to
        // say so.
        assert!(!BanDuration::Seconds(0).is_permanent());
        assert!(!BanDuration::Seconds(1).is_permanent());
    }

    #[test]
    fn defaults_are_the_gentler_choice() {
        // A menu opened and confirmed without reading must not ban anyone, and
        // if it does kick it should be to the channel rather than the server.
        assert_eq!(KickScope::default(), KickScope::Channel);
        assert_eq!(BanDuration::default(), BanDuration::Permanent);
    }

    #[test]
    fn the_wire_names_are_stable() {
        assert_eq!(
            serde_json::to_string(&KickScope::Channel).unwrap(),
            "\"channel\""
        );
        assert_eq!(
            serde_json::to_string(&KickScope::Server).unwrap(),
            "\"server\""
        );
        assert_eq!(
            serde_json::to_string(&BanDuration::Permanent).unwrap(),
            "\"permanent\""
        );
        assert_eq!(
            serde_json::to_string(&BanDuration::Seconds(600)).unwrap(),
            r#"{"seconds":600}"#
        );
    }
}
