//! Buildings: things placed on the map that work on their own each tick.
//! The smelter is the first; drills, belts and inserters follow.

use serde::{Deserialize, Serialize};

use crate::assembly::Assembly;
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
    /// A planted assembly: the drill of the demo, and whatever else a planted
    /// frame is given. Its behaviour comes entirely from its parts' stats, so
    /// there is one variant here however many machines exist.
    Machine(Machine),
}

/// A placed assembly. Where the smelter has fixed slots, a machine has only
/// what its parts give it: `Capacity` from the frame's buffer and its hoppers
/// bounds `held`.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Machine {
    pub assembly: Assembly,
    /// Ore mined and not yet taken. One item at a time; the machine stalls
    /// when it reaches the `Capacity` stat (decision 9). ASSA-6 fills it.
    pub held: Option<ItemStack>,
    /// Work accumulated toward the next unit (ADR 0003 amendment A3).
    pub progress: u32,
}

impl Machine {
    pub const fn new(assembly: Assembly) -> Self {
        Self {
            assembly,
            held: None,
            progress: 0,
        }
    }
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

/// Why a smelter has stopped. **One of these per `stalled:` line
/// `building_status` already printed**, and the reason an event can carry.
///
/// Structured and not a string, because `sim` holds rules and `debug` holds
/// prose: the event says *which* stall, and one wording function turns that
/// into the sentence both the status line and the log read (ASSA-80).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SmelterStall {
    /// Refined material is waiting and there is no room for more.
    OutputFull,
    /// Ore to smelt, nothing to burn.
    NoFuel,
    /// Fuel in the slot, and no fire a player can start from cold.
    FuelWontLight,
    /// Burning, and not hot enough for this ore. `fire` is already capped by
    /// the walls, which is what makes the smelter's own material matter.
    FireTooCool { fire: u32, needs: u32 },
}

/// What a smelter is doing. **DECIDED IN ONE PLACE** (`World::smelter_state`):
/// the status line, the stall event and any future host all read the same
/// answer, so none of them can invent a fifth state or disagree about which
/// of the four this is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SmelterState {
    /// Nothing to refine. **Not a stall**: it is something the player has not
    /// fed yet, not something they must fix (Game Director, ASSA-80), and it
    /// happens after every finished batch.
    Idle,
    Stalled(SmelterStall),
    /// Making progress, at this temperature.
    Working {
        at: u32,
    },
}

impl SmelterState {
    /// The stall, if this is one. The event edge asks this and nothing else.
    pub const fn stall(self) -> Option<SmelterStall> {
        match self {
            SmelterState::Stalled(why) => Some(why),
            _ => None,
        }
    }
}

impl BuildingKind {
    /// The building an item kind turns into when placed, if any. A machine is
    /// never here: it is placed from an assembly, not from an item.
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
            // One tile, so a drill sits on the deposit tile it works.
            BuildingKind::Machine(_) => (1, 1),
        }
    }

    pub const fn name(&self) -> &'static str {
        match self {
            BuildingKind::Smelter(_) => "smelter",
            BuildingKind::Machine(_) => "machine",
        }
    }

    pub const fn machine(&self) -> Option<&Machine> {
        match self {
            BuildingKind::Machine(m) => Some(m),
            _ => None,
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
