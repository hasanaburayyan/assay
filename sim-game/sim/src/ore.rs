//! Ore deposits: a patch of one mineral species at one purity.

use crate::mineral::{Grade, SpeciesId};
use crate::types::{DepositId, TilePos};
use serde::{Deserialize, Serialize};

/// A circular patch of ore on the map.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct OreDeposit {
    pub id: DepositId,
    pub species: SpeciesId,
    pub center: TilePos,
    /// Patch radius in tiles.
    pub radius: u8,
    /// Units of ore left to extract.
    pub amount: u32,
    /// Ore quality, 1–100. Rounds into a `Grade`, which is what items carry.
    pub purity: u8,
}

impl OreDeposit {
    /// Whether `pos` lies inside this deposit's patch.
    pub fn contains(&self, pos: TilePos) -> bool {
        let dx = pos.x - self.center.x;
        let dy = pos.y - self.center.y;
        let r = i32::from(self.radius);
        dx * dx + dy * dy <= r * r
    }

    pub fn is_depleted(&self) -> bool {
        self.amount == 0
    }

    pub fn grade(&self) -> Grade {
        Grade::from_purity(self.purity)
    }
}
