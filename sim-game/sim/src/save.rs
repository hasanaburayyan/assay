//! Human-readable JSON saves.
//!
//! A save wraps the world with a format version:
//!
//! ```json
//! { "version": 10, "world": { "tick": 0, "seed": 42, ... } }
//! ```
//!
//! When the layout of `World` changes, bump [`SAVE_VERSION`] and add a step
//! to `migrate` so older saves still load.
//!
//! History:
//! - v1–v8: the named-ore era (iron, copper, coal, stone). Dropped in one
//!   cut-over (ADR 0001); those saves no longer load.
//! - v9: generated mineral species, items keyed by species and grade
//!   (never shipped: superseded on the same branch).
//! - v10: species carry assayed/discoverer/name state; players may be
//!   assaying.
//! - v11: players carry built assemblies and a held tool, and a building may
//!   be a planted machine (ADR 0003).

use std::path::Path;
use std::{fmt, fs, io};

use serde::{Deserialize, Serialize};

use crate::world::World;

/// Current save format version.
pub const SAVE_VERSION: u32 = 11;

/// Oldest version `from_json` can still load and migrate forward.
pub const OLDEST_SAVE_VERSION: u32 = 10;

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
///
/// **v10 → v11 needs no fixing up, and that is deliberate rather than
/// forgotten.** Everything v11 added is new state nobody had in a v10 world:
/// `Player::assemblies`, `Player::tool` and the `Machine` variant of
/// `BuildingKind`. The player fields carry `#[serde(default)]`, so a v10 save
/// loads with an empty built list and nothing in hand, which is exactly the
/// world it described. The founders' v10 test world therefore keeps loading;
/// `tests/save.rs` pins that.
fn migrate(_world: &mut World, _from_version: u32) {}
