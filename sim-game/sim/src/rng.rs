//! Deterministic randomness. Never use a global or thread RNG inside the sim.

use serde::{Deserialize, Serialize};

/// SplitMix64: tiny, fast and good enough for gameplay.
/// Its state is part of the world, so it is saved, loaded and hashed.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Rng {
    state: u64,
}

impl Rng {
    pub const fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        mix(self.state)
    }

    /// Integer in `lo..hi`. Modulo bias is negligible for game-sized ranges.
    pub fn range(&mut self, lo: u32, hi: u32) -> u32 {
        debug_assert!(lo < hi, "empty range {lo}..{hi}");
        lo + (self.next_u64() % u64::from(hi - lo)) as u32
    }
}

/// SplitMix64 finalizer: scrambles a 64-bit value.
pub const fn mix(mut z: u64) -> u64 {
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// Stateless hash of (seed, x, y, salt). The same inputs give the same output
/// no matter when or in what order they are asked for, which is what lets us
/// generate any chunk on demand. Use a different `salt` per feature so ore
/// placement and, say, terrain don't correlate.
pub const fn hash_coords(seed: u64, x: i32, y: i32, salt: u64) -> u64 {
    let xy = (x as u32 as u64) | ((y as u32 as u64) << 32);
    mix(seed ^ mix(salt ^ mix(xy)))
}
