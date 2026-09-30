//! Every rate, duration and limit the rules use, in one place so the game
//! can be retuned without hunting through systems.
//!
//! Durations are in ticks. The terminal clock runs at 10 ticks/s by default
//! and the game is planned to run at 60, so expect these to be rescaled.

/// Ticks of standing on a deposit per unit of ore mined by hand.
pub const HAND_MINE_TICKS: u32 = 4;
