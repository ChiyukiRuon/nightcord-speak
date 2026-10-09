use serde::{Deserialize, Serialize};

/// A client-wide preference, distinct from each server's public avatar state.
#[derive(Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct OwnAvatar {
    #[serde(default)]
    pub revision: u64,
    pub configured: bool,
    pub image: Option<String>,
    #[serde(default)]
    pub edit: Option<AvatarEdit>,
}

/// Original input and normalized crop, kept locally and never uploaded to a server.
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct AvatarEdit {
    pub source: String,
    pub turns: u8,
    pub zoom: f64,
    pub x: f64,
    pub y: f64,
}

impl std::fmt::Debug for AvatarEdit {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AvatarEdit").finish_non_exhaustive()
    }
}

impl std::fmt::Debug for OwnAvatar {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OwnAvatar")
            .field("configured", &self.configured)
            .field("has_image", &self.image.is_some())
            .finish()
    }
}
