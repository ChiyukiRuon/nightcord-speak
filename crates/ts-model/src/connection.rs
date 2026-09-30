use serde::{Deserialize, Serialize};

/// Where a session is in its lifecycle.
///
/// Every transition is published as an event, so the UI never has to poll.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionState {
    /// No transport, no session.
    Disconnected,
    /// A transport is being established for the first time.
    Connecting,
    /// Handshake finished, state synchronised, ready to use.
    Connected,
    /// The transport dropped and a retry is in flight. The session and its
    /// identity survive this state — see [`ReconnectPolicy`].
    Reconnecting,
    /// A clean shutdown is in progress.
    Disconnecting,
    /// The last attempt failed and no retry is scheduled.
    Failed,
}

impl ConnectionState {
    /// Whether the session is usable right now.
    #[must_use]
    pub const fn is_usable(self) -> bool {
        matches!(self, Self::Connected)
    }

    /// Whether the session is between states and neither usable nor dead.
    #[must_use]
    pub const fn is_transitional(self) -> bool {
        matches!(
            self,
            Self::Connecting | Self::Reconnecting | Self::Disconnecting
        )
    }

    /// Whether the session has stopped and needs an explicit retry.
    #[must_use]
    pub const fn is_terminal(self) -> bool {
        matches!(self, Self::Disconnected | Self::Failed)
    }
}

/// Backoff schedule used while reconnecting.
///
/// Mirrors the doubling-with-a-ceiling schedule in DEVELOPMENT.md §35. Keeping
/// it as data (rather than a hard-coded loop) makes it testable and lets later
/// phases make it user-configurable.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReconnectPolicy {
    /// Delay before the first retry, in milliseconds.
    pub initial_delay_ms: u64,
    /// Upper bound for a single delay, in milliseconds.
    pub max_delay_ms: u64,
    /// Factor applied to the delay after each failure.
    pub multiplier: u32,
    /// How many retries to attempt before giving up. `None` retries forever.
    pub max_attempts: Option<u32>,
}

impl ReconnectPolicy {
    /// The schedule from the design doc: 1s, 2s, 4s, 8s, 16s, capped at 30s.
    #[must_use]
    pub const fn exponential() -> Self {
        Self {
            initial_delay_ms: 1_000,
            max_delay_ms: 30_000,
            multiplier: 2,
            max_attempts: None,
        }
    }

    /// Delay to wait before retry number `attempt`, where the first retry is
    /// attempt `0`. Saturates at [`Self::max_delay_ms`].
    #[must_use]
    pub const fn delay_for_attempt(&self, attempt: u32) -> u64 {
        let mut delay = self.initial_delay_ms;
        let mut i = 0;
        while i < attempt {
            delay = delay.saturating_mul(self.multiplier as u64);
            if delay >= self.max_delay_ms {
                return self.max_delay_ms;
            }
            i += 1;
        }
        if delay > self.max_delay_ms {
            self.max_delay_ms
        } else {
            delay
        }
    }

    /// Whether another retry is allowed after `attempts` failures.
    #[must_use]
    pub const fn should_retry(&self, attempts: u32) -> bool {
        match self.max_attempts {
            Some(max) => attempts < max,
            None => true,
        }
    }
}

impl Default for ReconnectPolicy {
    fn default() -> Self {
        Self::exponential()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_doubles_and_saturates() {
        let policy = ReconnectPolicy::exponential();
        let delays: Vec<u64> = (0..6).map(|a| policy.delay_for_attempt(a)).collect();
        assert_eq!(delays, vec![1_000, 2_000, 4_000, 8_000, 16_000, 30_000]);
    }

    #[test]
    fn backoff_stays_at_ceiling() {
        let policy = ReconnectPolicy::exponential();
        assert_eq!(policy.delay_for_attempt(50), 30_000);
    }

    #[test]
    fn retry_budget_is_respected() {
        let mut policy = ReconnectPolicy::exponential();
        assert!(policy.should_retry(1_000));
        policy.max_attempts = Some(3);
        assert!(policy.should_retry(2));
        assert!(!policy.should_retry(3));
    }

    #[test]
    fn state_classification() {
        assert!(ConnectionState::Connected.is_usable());
        assert!(ConnectionState::Reconnecting.is_transitional());
        assert!(ConnectionState::Failed.is_terminal());
        assert!(!ConnectionState::Failed.is_usable());
    }
}
