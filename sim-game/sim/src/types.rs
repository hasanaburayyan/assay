//! Small shared types. Entities refer to each other by ID, never by pointer,
//! so references survive save/load and network transfer.

use crate::world::CHUNK_SIZE;
use serde::{Deserialize, Serialize};

/// A tile coordinate in the world grid.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct TilePos {
    pub x: i32,
    pub y: i32,
}

impl TilePos {
    pub const fn new(x: i32, y: i32) -> Self {
        Self { x, y }
    }

    /// The chunk this tile belongs to.
    pub const fn chunk(self) -> ChunkPos {
        ChunkPos {
            x: self.x.div_euclid(CHUNK_SIZE),
            y: self.y.div_euclid(CHUNK_SIZE),
        }
    }
}

/// A chunk coordinate. World generation works one chunk at a time.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct ChunkPos {
    pub x: i32,
    pub y: i32,
}

impl ChunkPos {
    pub const fn new(x: i32, y: i32) -> Self {
        Self { x, y }
    }

    /// Distance in chunks, counting diagonal steps as one (Chebyshev distance).
    pub fn distance(self, other: ChunkPos) -> i32 {
        (self.x - other.x).abs().max((self.y - other.y).abs())
    }
}

/// Stable ID for a player.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct PlayerId(pub u32);

/// Stable ID for an ore deposit. Equal to its index in `World::deposits`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct DepositId(pub u32);
