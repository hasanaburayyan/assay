//! Every rate, duration and limit the rules use, in one place so the game
//! can be retuned without hunting through systems.
//!
//! Durations are in ticks. The terminal clock runs at 10 ticks/s by default
//! and the game is planned to run at 60, so expect these to be rescaled.
//! Property values are whole numbers from 1 to 100 (see `mineral.rs`).

/// Mineral species generated per world.
pub const SPECIES_PER_WORLD: usize = 6;

/// Rosters are rerolled until at least this many ladder rungs are reachable
/// from bare hands (see `ladder.rs`). Only rung zero can exist until drills
/// (and a decision on the step factor) let hardness progress, so this is 1.
pub const MIN_STARTER_RUNGS: usize = 1;

/// Starter deposits (next to spawn) roll their purity from here up, so the
/// first fuel burns hot enough and the first ore is worth mining.
pub const STARTER_MIN_PURITY: u32 = 50;

/// Purity at or above which a deposit is grade B / grade A. Below B is C.
pub const GRADE_B_MIN_PURITY: u8 = 40;
pub const GRADE_A_MIN_PURITY: u8 = 70;

/// How much of a species' strength, hardness, reactivity and conductivity
/// an item keeps at grade C, B and A, in percent. Density and heat
/// tolerance never scale.
pub const GRADE_MULTIPLIER_PERCENT: [u32; 3] = [60, 80, 100];

/// Units of ore a player gets per hand-mining cycle at grade C, B and A.
/// The deposit loses one unit per cycle either way: purer ore wastes less.
pub const YIELD_BY_GRADE: [u32; 3] = [1, 2, 3];

/// Ticks of standing on a deposit per hand-mining cycle.
pub const HAND_MINE_TICKS: u32 = 4;

/// Hardest ore (species hardness) a player can mine with bare hands.
/// Anything harder waits for drills.
pub const HAND_MINE_MAX_HARDNESS: u32 = 40;

/// The hottest fire a player can start by hand. A fuel whose species heat
/// tolerance is at most this lights in a cold smelter; hotter fuels need a
/// smelter that is already burning at least that hot.
pub const HAND_SPARK_TEMPERATURE: u32 = 30;

/// Effective reactivity an item needs to count as fuel at all.
pub const FUEL_MIN_REACTIVITY: u32 = 25;

/// Ticks one unit of fuel burns per point of effective reactivity.
pub const BURN_TICKS_PER_REACTIVITY: u32 = 2;

/// Effective hardness refined material needs to be made into a gear.
pub const GEAR_MIN_HARDNESS: u32 = 20;

/// How far (in tiles, diagonals counting as one) a player can reach to
/// place, fill, empty or pick up a building.
pub const REACH: i32 = 3;

/// Most ore a smelter's input slot holds.
pub const SMELTER_INPUT_CAP: u32 = 50;
/// Most fuel units a smelter holds in reserve.
pub const SMELTER_FUEL_CAP: u32 = 50;
/// Most output a smelter holds before it stops until someone empties it.
pub const SMELTER_OUTPUT_CAP: u32 = 50;
