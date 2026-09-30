//! Buildings: things placed on the map that work on their own each tick.
//! The smelter is the first; drills, belts and inserters follow.

use serde::{Deserialize, Serialize};

use crate::item::{Item, ItemStack};
use crate::types::TilePos;

/// Stable ID for a building. Unlike deposits, buildings come and go, so IDs
/// are handed out from a counter and are not indexes into `World::buildings`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct BuildingId(pub u32);

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Building {
    pub id: BuildingId,
    /// Top-left tile of the footprint.
    pub pos: TilePos,
    pub kind: BuildingKind,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum BuildingKind {
    Smelter(Smelter),
}

/// Burns coal to turn ore into plates. Fixed 2×2 footprint.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Smelter {
    /// Ore waiting to be smelted. One kind at a time.
    pub input: Option<ItemStack>,
    /// Coal not yet burning.
    pub fuel: u32,
    /// Ticks of burn left from the coal currently in the fire. Only counts
    /// down while smelting.
    pub burn_left: u32,
    /// Plates waiting to be taken out.
    pub output: Option<ItemStack>,
    /// Ticks spent on the current plate.
    pub progress: u32,
}

impl BuildingKind {
    /// The building an item turns into when placed, if it is a building.
    pub fn from_item(item: Item) -> Option<BuildingKind> {
        match item {
            Item::Smelter => Some(BuildingKind::Smelter(Smelter::default())),
            _ => None,
        }
    }

    /// The item you get back when picking the building up.
    pub const fn item(&self) -> Item {
        match self {
            BuildingKind::Smelter(_) => Item::Smelter,
        }
    }

    /// (width, height) in tiles.
    pub const fn footprint(&self) -> (i32, i32) {
        match self {
            BuildingKind::Smelter(_) => (2, 2),
        }
    }

    pub const fn name(&self) -> &'static str {
        self.item().name()
    }
}

impl Building {
    /// Every tile the footprint covers, row-major from `pos`.
    pub fn tiles(&self) -> impl Iterator<Item = TilePos> {
        footprint_tiles(self.pos, self.kind.footprint())
    }

    pub fn covers(&self, tile: TilePos) -> bool {
        let (w, h) = self.kind.footprint();
        (self.pos.x..self.pos.x + w).contains(&tile.x)
            && (self.pos.y..self.pos.y + h).contains(&tile.y)
    }

    /// Chebyshev distance from `from` to the nearest tile of the footprint.
    pub fn distance_from(&self, from: TilePos) -> i32 {
        let (w, h) = self.kind.footprint();
        let dx = (self.pos.x - from.x)
            .max(from.x - (self.pos.x + w - 1))
            .max(0);
        let dy = (self.pos.y - from.y)
            .max(from.y - (self.pos.y + h - 1))
            .max(0);
        dx.max(dy)
    }
}

pub fn footprint_tiles(pos: TilePos, (w, h): (i32, i32)) -> impl Iterator<Item = TilePos> {
    (0..h).flat_map(move |dy| (0..w).map(move |dx| TilePos::new(pos.x + dx, pos.y + dy)))
}
