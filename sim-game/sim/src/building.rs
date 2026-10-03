//! Buildings: things placed on the map that work on their own each tick.
//! The smelter is the first; drills, belts and inserters follow.

use serde::{Deserialize, Serialize};

use crate::assembly::Assembly;
use crate::item::{Item, ItemKind, ItemStack};
use crate::mineral::{Grade, SpeciesId};
use crate::types::{DepositId, TilePos};

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

    /// Whether a player has to do something about this.
    ///
    /// **`Idle` IS NOT A PROBLEM AND MUST NEVER BE REPORTED AS ONE** (Game
    /// Director, ASSA-80, restated on ASSA-94): an empty smelter follows every
    /// finished batch, so a surface that listed it would cry wolf after every
    /// successful smelt. The asymmetry with [`MachineState::halted`] — where
    /// idle *is* reported — is explained there.
    pub const fn halted(self) -> bool {
        self.stall().is_some()
    }
}

/// Why a planted machine has stopped with work still in front of it.
///
/// One variant, because decision 9 gives a drill exactly one way to stop: it
/// never starts a unit it has no room for. Structured rather than a string for
/// [`SmelterStall`]'s reason — the rule says *which*, `debug` says it in
/// words, and the two cannot drift apart.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum MachineStall {
    /// The buffer has no room for a whole unit of what is underneath.
    /// `held`/`capacity` are carried so a host can draw the fill without
    /// re-reading the world, as [`crate::command::Event::MachineStalled`]
    /// already does.
    BufferFull { held: u32, capacity: u32 },
}

/// Why a planted machine is doing nothing, when nothing is broken about it.
///
/// **EVERY ONE OF THESE IS WORTH A PLAYER'S ATTENTION**, which is what makes
/// a machine's idle different from a smelter's — see [`MachineState::halted`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum MachineIdle {
    /// Planted where there is no deposit at all.
    NoDeposit,
    /// Its deposit is mined out. It will never produce again.
    DepositMinedOut,
    /// Decision 7: a drill is a throughput upgrade, never a hardness unlock,
    /// so it refuses exactly what hands refuse. The species is carried because
    /// the sentence names the rock, and it saves `debug` a fallible re-read of
    /// a deposit this state has already proved exists.
    DepositTooHard { species: SpeciesId },
}

/// What a planted machine is doing. **DECIDED IN ONE PLACE**
/// (`World::machine_state`), for the reason the smelter got the same treatment
/// on ASSA-80.
///
/// Before ASSA-94 this chain existed three times: `step` refusing to mine,
/// `step` announcing the stall edge, and `debug::machine_status` writing the
/// prose. Two read `stats().capacity` and the third read
/// `stat_range().low.capacity`. Nothing had gone wrong yet — capacity is flat
/// from the part kind, so those two agree — but the only standing answer about
/// a drill that existed anywhere was a *sentence*, so a host could not ask
/// whether a machine had stopped without parsing prose.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MachineState {
    Idle(MachineIdle),
    Stalled(MachineStall),
    /// Mining this deposit. **The work system acts on exactly this arm, and
    /// on nothing it looked up itself** — the deposit and grade ride along so
    /// `step` re-reads nothing after asking, which is what makes "one place
    /// decides" true rather than merely intended.
    Working {
        deposit: DepositId,
        species: SpeciesId,
        grade: Grade,
    },
}

impl MachineState {
    /// The stall, if this is one.
    pub const fn stall(self) -> Option<MachineStall> {
        match self {
            MachineState::Stalled(why) => Some(why),
            _ => None,
        }
    }

    /// Whether a player has to do something about this.
    ///
    /// **TRUE FOR IDLE TOO, AND THAT IS THE OPPOSITE OF THE SMELTER**
    /// (Game Director, ASSA-94: "every standing not-working state", naming
    /// mined out and unreachable). The two are not inconsistent, because the
    /// two idles are not the same thing. A smelter is idle when nobody has
    /// fed it yet, which is the normal end of every batch and resolves itself
    /// the moment a player inserts. A machine is idle only because it was
    /// *planted somewhere it cannot work* — no deposit, a mined-out deposit,
    /// or rock too hard for anything that can be built. None of those three
    /// will ever resolve on their own, and the player has already paid eight
    /// refined for the thing not working.
    pub const fn halted(self) -> bool {
        match self {
            MachineState::Idle(_) | MachineState::Stalled(_) => true,
            MachineState::Working { .. } => false,
        }
    }
}

/// What any building is doing, so one question answers for every kind.
///
/// A host asking "has this stopped?" should not have to match the kind first
/// and then learn two different vocabularies — that is the shape that let the
/// drill go three days with no askable state at all.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BuildingState {
    Smelter(SmelterState),
    Machine(MachineState),
}

impl BuildingState {
    /// Whether a player has to do something about this building.
    ///
    /// Exhaustive on purpose: a new `BuildingKind` fails to compile here
    /// rather than quietly reporting itself as fine (ASSA-51/53's shape).
    pub const fn halted(self) -> bool {
        match self {
            BuildingState::Smelter(s) => s.halted(),
            BuildingState::Machine(m) => m.halted(),
        }
    }
}

impl Machine {
    /// Whether a whole `amount` more fits in the buffer.
    ///
    /// **DECISION 9 LIVES HERE AND NOWHERE ELSE.** It stops AT the cap, so it
    /// never starts a unit it has no room for: nothing is mined and thrown
    /// away, and `progress` keeps whatever it had, so emptying the buffer
    /// resumes mid-unit. `step` asks this before mining and again after, and
    /// `World::machine_state` asks it to report the stall; before ASSA-94
    /// those were three separate `>` comparisons.
    pub fn has_room_for(&self, amount: u32, capacity: u32) -> bool {
        self.held.map_or(0, |h| h.count) + amount <= capacity
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
