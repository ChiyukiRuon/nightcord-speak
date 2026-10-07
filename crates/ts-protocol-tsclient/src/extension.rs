//! Wire extension hooks implemented by the protocol-specific backend.

use std::collections::BTreeMap;
use ts_model::{ClientError, ScreenCommand, ScreenEvent};

/// An adapter-local representation, never exposed to the core or frontend.
pub struct ExtensionCommand {
    pub name: &'static str,
    pub arguments: BTreeMap<String, String>,
}

/// Keeps extension vocabulary out of the shared connection actor.
pub trait ScreenExtension: Send + Sync {
    fn encode(&self, command: ScreenCommand) -> Result<ExtensionCommand, ClientError>;
    fn decode(&self, name: &str, arguments: &BTreeMap<String, String>) -> Option<ScreenEvent>;

    /// Only retry explicit server refusals; uncertain delivery is never replayed.
    fn retry_delay(&self, _attempt: u32, _error: &ClientError) -> Option<std::time::Duration> {
        None
    }
}
