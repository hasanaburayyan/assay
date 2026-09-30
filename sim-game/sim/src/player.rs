//! Players: an entity with a name and a position that walks toward a target.

use serde::{Deserialize, Serialize};

use crate::inventory::Inventory;
use crate::types::{PlayerId, TilePos};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Player {
    pub id: PlayerId,
    /// Display name. Saves from before v3 load with an empty name and are
    /// migrated (see `save.rs`).
    #[serde(default)]
    pub name: String,
    pub pos: TilePos,
    /// Where the player is walking to. The movement system moves them one
    /// tile per tick, diagonals included, until they arrive.
    pub target: Option<TilePos>,
    /// Ore carried. Saves from before v4 load with an empty inventory.
    #[serde(default)]
    pub inventory: Inventory,
}

impl Player {
    pub fn new(id: PlayerId, name: impl Into<String>, pos: TilePos) -> Self {
        Self {
            id,
            name: name.into(),
            pos,
            target: None,
            inventory: Inventory::default(),
        }
    }
}
