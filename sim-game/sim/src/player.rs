//! Players: an entity with a name and a position that walks toward a target,
//! carries items, and can mine and craft by hand.

use serde::{Deserialize, Serialize};

use crate::inventory::Inventory;
use crate::item::Item;
use crate::recipe::RecipeId;
use crate::types::{DepositId, PlayerId, TilePos};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Player {
    pub id: PlayerId,
    pub name: String,
    pub pos: TilePos,
    /// Where the player is walking to. The movement system moves them one
    /// tile per tick, diagonals included, until they arrive.
    pub target: Option<TilePos>,
    pub inventory: Inventory,
    /// Hand mining in progress. Continues while the player stays on the
    /// deposit; walking off it or `Stop` ends it.
    pub mining: Option<Mining>,
    /// Hand crafting in progress. Continues while walking or mining; `Stop`
    /// cancels it and refunds the unit being worked on.
    pub crafting: Option<Crafting>,
    /// Assaying the deposit underfoot. Ends like mining: walking off it or
    /// `Stop` cancels, finishing reveals the species' exact sheet.
    pub assaying: Option<Assaying>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Assaying {
    pub deposit: DepositId,
    pub progress: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Mining {
    pub deposit: DepositId,
    /// Ticks spent on the current cycle.
    pub progress: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Crafting {
    pub recipe: RecipeId,
    /// Which stack the batches are made from.
    pub input: Item,
    /// Ticks spent on the current batch. Its inputs are already consumed.
    pub progress: u32,
    /// Batches still to make, counting the current one.
    pub remaining: u32,
}

impl Player {
    pub fn new(id: PlayerId, name: impl Into<String>, pos: TilePos) -> Self {
        Self {
            id,
            name: name.into(),
            pos,
            target: None,
            inventory: Inventory::default(),
            mining: None,
            crafting: None,
            assaying: None,
        }
    }
}
