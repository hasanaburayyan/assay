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
pub mod recipe;
pub mod rng;
pub mod save;
pub mod step;
pub mod tuning;
pub mod types;
pub mod world;
pub mod worldgen;

pub use building::{Building, BuildingId, BuildingKind, Slot, Smelter};
pub use command::{Event, Input, PlayerCommand, RejectReason, StopReason, SystemCommand};
pub use inventory::Inventory;
pub use item::{Item, ItemKind, ItemStack};
pub use mineral::{Grade, MineralSpecies, NameError, Property, Sheet, SpeciesId};
pub use ore::OreDeposit;
pub use player::{Assaying, Crafting, Mining, Player};
pub use recipe::{RECIPES, Recipe, RecipeId, Station};
pub use rng::Rng;
pub use save::{OLDEST_SAVE_VERSION, SAVE_VERSION, SaveError};
pub use step::step;
pub use types::{ChunkPos, DepositId, PlayerId, TilePos};
pub use world::{CHUNK_SIZE, World, WorldConfig};
