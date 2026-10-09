use std::path::PathBuf;

use ts_model::{OwnAvatar, SettingsError};

/// Kept outside settings.json so preference commands remain small.
#[derive(Debug, Clone)]
pub struct AvatarStore {
    path: PathBuf,
}

impl AvatarStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub fn load(&self) -> Result<OwnAvatar, SettingsError> {
        if let Ok(meta) = std::fs::metadata(&self.path)
            && meta.len() > 14 * 1024 * 1024
        {
            return Err(SettingsError::Malformed {
                message: "avatar file exceeds size limit".into(),
            });
        }
        Ok(crate::store::read_json(&self.path)?.unwrap_or_default())
    }

    pub fn save(&self, avatar: &OwnAvatar) -> Result<(), SettingsError> {
        crate::store::write_json(&self.path, avatar)
    }
}
