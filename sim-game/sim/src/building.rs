//! Buildings: things placed on the map that work on their own each tick.
//! The smelter is the first; drills, belts and inserters follow.

use serde::{Deserialize, Serialize};

use crate::item::{Item, ItemKind, ItemStack};
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
    /// The item it was placed from. Its species is the building's material:
    /// a smelter's walls can only take that species' heat tolerance.
    pub material: Item,
    pub kind: BuildingKind,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum BuildingKind {
    Smelter(Smelter),
}

/// Which slot of a building an `Insert` aims at.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Slot {
    Input,
    Fuel,
}

/// Burns reactive material to turn ore into refined material. Fixed 2×2.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Smelter {
    /// Ore waiting to be smelted. One item at a time.
    pub input: Option<ItemStack>,
    /// Fuel not yet burning. One item at a time.
    pub fuel: Option<ItemStack>,
    /// Ticks of burn left from the unit currently in the fire. Only counts
    /// down while smelting.
    pub burn_left: u32,
    /// How hot the fire is while `burn_left > 0`: the burning fuel's
    /// effective reactivity. Zero when cold.
    pub burn_temperature: u32,
    /// Refined material waiting to be taken out.
    pub output: Option<ItemStack>,
    /// Ticks spent on the current unit.
    pub progress: u32,
}

impl BuildingKind {
    /// The building an item kind turns into when placed, if any.
    pub fn for_item(kind: ItemKind) -> Option<BuildingKind> {
        match kind {
            ItemKind::Smelter => Some(BuildingKind::Smelter(Smelter::default())),
            _ => None,
        }
    }

    /// (width, height) in tiles.
    pub const fn footprint(&self) -> (i32, i32) {
        match self {
            BuildingKind::Smelter(_) => (2, 2),
        }
    }

    pub const fn name(&self) -> &'static str {
        match self {
            BuildingKind::Smelter(_) => "smelter",
        }
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
