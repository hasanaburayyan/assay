//! Every rate, duration and limit the rules use, in one place so the game
//! can be retuned without hunting through systems.
//!
//! Durations are in ticks. The terminal clock runs at 10 ticks/s by default
//! and the game is planned to run at 60, so expect these to be rescaled.

/// Ticks of standing on a deposit per unit of ore mined by hand.
pub const HAND_MINE_TICKS: u32 = 4;

/// How far (in tiles, diagonals counting as one) a player can reach to
/// place, fill, empty or pick up a building.
pub const REACH: i32 = 3;

/// Ticks of smelting one unit of coal keeps a smelter going.
pub const COAL_BURN_TICKS: u32 = 80;

/// Most ore a smelter's input slot holds.
pub const SMELTER_INPUT_CAP: u32 = 50;
/// Most coal a smelter holds in reserve.
pub const SMELTER_FUEL_CAP: u32 = 50;
/// Most plates a smelter holds before it stops until someone empties it.
pub const SMELTER_OUTPUT_CAP: u32 = 50;
