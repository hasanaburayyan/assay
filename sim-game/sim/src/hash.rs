//! State hashing for determinism checks (replays, tests, multiplayer desync
//! detection).
//!
//! We use FNV-1a instead of std's `DefaultHasher`, whose algorithm is not
//! guaranteed to stay the same across Rust versions. Note that std's `Hash`
//! impls write integers in native byte order and `usize` lengths at native
//! width, so hashes match across our 64-bit little-endian targets
//! (x86-64 and ARM64), not across every platform.

use std::hash::{Hash, Hasher};

pub struct Fnv64(u64);

impl Default for Fnv64 {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Hasher for Fnv64 {
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 ^= u64::from(b);
            self.0 = self.0.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }

    fn finish(&self) -> u64 {
        self.0
    }
}

/// Hash any value with FNV-1a.
pub fn fnv64<T: Hash>(value: &T) -> u64 {
    let mut h = Fnv64::default();
    value.hash(&mut h);
    h.finish()
}
