//! Human-readable JSON saves.
//!
//! A save wraps the world with a format version:
//!
//! ```json
//! { "version": 4, "world": { "tick": 0, "seed": 42, ... } }
//! ```
//!
//! When the layout of `World` changes, bump [`SAVE_VERSION`] and add a step
//! to `migrate` so older saves still load.
//!
//! History:
//! - v1: world, ore deposits
//! - v2: players
//! - v3: player names
//! - v4: player inventories (loads from v3 with empty inventories)

use std::path::Path;
use std::{fmt, fs, io};

use serde::{Deserialize, Serialize};

use crate::player::Player;
use crate::types::PlayerId;
use crate::world::World;

/// Current save format version.
pub const SAVE_VERSION: u32 = 4;

/// Oldest version `from_json` can still load and migrate forward.
pub const OLDEST_SAVE_VERSION: u32 = 1;

#[derive(Serialize)]
struct SaveOut<'a> {
    version: u32,
    world: &'a World,
}

#[derive(Deserialize)]
struct SaveIn {
    world: World,
}

/// Read only the version first, so a file with a newer or older layout gets
/// a clear error instead of a confusing field mismatch.
#[derive(Deserialize)]
struct VersionOnly {
    version: u32,
}

#[derive(Debug)]
pub enum SaveError {
    Io(io::Error),
    Json(serde_json::Error),
    UnsupportedVersion { found: u32 },
}

impl fmt::Display for SaveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SaveError::Io(e) => write!(f, "file error: {e}"),
            SaveError::Json(e) => write!(f, "invalid save JSON: {e}"),
            SaveError::UnsupportedVersion { found } => {
                write!(
                    f,
                    "save format version {found} is not supported (this build loads versions {OLDEST_SAVE_VERSION} to {SAVE_VERSION})"
                )
            }
        }
    }
}

impl std::error::Error for SaveError {}

impl From<io::Error> for SaveError {
    fn from(e: io::Error) -> Self {
        SaveError::Io(e)
    }
}

impl From<serde_json::Error> for SaveError {
    fn from(e: serde_json::Error) -> Self {
        SaveError::Json(e)
    }
}

impl World {
    /// The world as pretty-printed JSON.
    pub fn to_json(&self) -> Result<String, SaveError> {
        Ok(serde_json::to_string_pretty(&SaveOut {
            version: SAVE_VERSION,
            world: self,
        })?)
    }

    pub fn from_json(json: &str) -> Result<World, SaveError> {
        let VersionOnly { version } = serde_json::from_str(json)?;
        if !(OLDEST_SAVE_VERSION..=SAVE_VERSION).contains(&version) {
            return Err(SaveError::UnsupportedVersion { found: version });
        }
        let SaveIn { mut world } = serde_json::from_str(json)?;
        migrate(&mut world, version);
        Ok(world)
    }

    /// Write the world to `path`, creating parent folders if needed.
    pub fn save_json(&self, path: impl AsRef<Path>) -> Result<(), SaveError> {
        let path = path.as_ref();
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        fs::write(path, self.to_json()? + "\n")?;
        Ok(())
    }

    pub fn load_json(path: impl AsRef<Path>) -> Result<World, SaveError> {
        World::from_json(&fs::read_to_string(path)?)
    }
}

/// Bring a world loaded from an older save up to the current layout.
fn migrate(world: &mut World, from_version: u32) {
    if from_version < 2 && world.players.is_empty() {
        // v1 had no players, but was always played by one. Start them at spawn.
        world
            .players
            .push(Player::new(PlayerId(0), "", world.spawn_tile()));
    }
    if from_version < 3 {
        // v3 added names.
        for p in world.players.iter_mut().filter(|p| p.name.is_empty()) {
            p.name = format!("player {}", p.id.0);
        }
    }
}
