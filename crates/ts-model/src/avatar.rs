use serde::{Deserialize, Serialize};

/// A bounded image carried identically by embedded and remote transports.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AvatarImage {
    pub client_id: crate::ClientId,
    pub version: String,
    pub image: String,
}

impl std::fmt::Debug for AvatarImage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AvatarImage")
            .field("client_id", &self.client_id)
            .finish_non_exhaustive()
    }
}
