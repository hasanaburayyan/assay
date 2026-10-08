//! Assay simulation core.
//!
//! The rules of the game as plain data plus a `step` function. Nothing in
//! this crate knows about rendering, input devices, or wall-clock time, so it
//! runs the same in Godot, in tests, and on a headless server.
//!
//! Determinism rules for everything in here:
//! - randomness only from a seeded [`Rng`] or [`rng::hash_coords`]
//! - no clock reads; [`World::tick`] is the only notion of time
//! - iterate in a stable order (`Vec`, not `HashMap`)
//! - integers for anything that affects the rules

/// **WHICH RULES THIS BINARY WAS BUILT FROM** (ASSA-40): a fingerprint of
/// this crate's source, computed by `build.rs` and baked in. Sixteen hex
/// digits, like a world hash.
///
/// It exists because `PROTOCOL_VERSION` answers a different question. That
/// tracks the shape of the wire; this tracks the rules, and the rules change
/// without the wire changing — #47 moved one constant, every stat derived
/// from it moved, and a relay built an hour earlier spoke the same protocol
/// while playing a different game. Hosts compare this at join time
/// (`sim_net::check_join`) so the first symptom is a sentence a stranger can
/// act on, instead of a desync twenty ticks in.
///
/// **NOTHING IN THE RULES MAY READ THIS.** It is not world state, it is not
/// in the state hash, and a `step` that branched on it would make two builds
/// disagree on purpose. It is for hosts deciding whether to talk to each
/// other, and for a log line.
pub const RULES_ID: &str = env!("SIM_RULES_ID");

pub mod assembly;
pub mod building;
pub mod command;
pub mod debug;
pub mod hash;
pub mod inventory;
pub mod item;
pub mod ladder;
pub mod mineral;
pub mod ore;
pub mod player;
pub mod proximity;
pub mod recipe;
pub mod rng;
pub mod rules_fingerprint;
pub mod save;
pub mod step;
pub mod tuning;
pub mod types;
pub mod world;
pub mod worldgen;

pub use assembly::{
    Assembly, AssemblyError, BreakOutcome, BreakVerdict, Built, Contribution, MachineStats, Mount,
    PART_SPECS, Part, PartKind, PartSpec, SlotLimit, Source, Stat, StatRange,
};
pub use building::{
    Building, BuildingId, BuildingKind, BuildingState, Machine, MachineIdle, MachineStall,
    MachineState, Slot, SlotRole, Smelter, SmelterStall, SmelterState, WorkReading,
};
pub use command::{Event, Input, PlayerCommand, RejectReason, StopReason, SystemCommand};
pub use inventory::Inventory;
pub use item::{Item, ItemKind, ItemStack};
pub use mineral::{Grade, MineralSpecies, NameError, Property, Sheet, SpeciesId};
pub use ore::OreDeposit;
pub use player::{Assaying, Crafting, Mining, Player};
pub use proximity::{Heading, NearestDeposit, Question, walking_ticks};
pub use recipe::{RECIPES, Recipe, RecipeId, Station};
pub use rng::Rng;
pub use save::{OLDEST_SAVE_VERSION, SAVE_VERSION, SaveError};
pub use step::step;
pub use types::{ChunkPos, DepositId, PlayerId, TilePos};
pub use world::{CHUNK_SIZE, World, WorldConfig};
