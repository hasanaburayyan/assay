//! Ore kinds and deposits.

use crate::types::{DepositId, TilePos};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum OreKind {
    Iron,
    Copper,
    Coal,
    Stone,
}

impl OreKind {
    pub const ALL: [OreKind; 4] = [
        OreKind::Iron,
        OreKind::Copper,
        OreKind::Coal,
        OreKind::Stone,
    ];

    /// One-character symbol for debug maps.
    pub const fn symbol(self) -> char {
        match self {
            OreKind::Iron => 'I',
            OreKind::Copper => 'C',
            OreKind::Coal => 'K',
            OreKind::Stone => 'S',
        }
    }
}

/// A circular patch of ore on the map.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct OreDeposit {
    pub id: DepositId,
    pub kind: OreKind,
    pub center: TilePos,
    /// Patch radius in tiles.
    pub radius: u8,
    /// Units of ore left to extract.
    pub amount: u32,
    /// Ore quality, 1–100. Higher purity will mean better parts later.
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
}
