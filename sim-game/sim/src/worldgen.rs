//! Procedural world generation.
//!
//! Every chunk's contents are a pure function of `(seed, chunk)`. Chunks can
//! be generated in any order, or lazily when a player first explores them,
//! and always come out identical. Later we only need to save the chunks
//! players have changed.

use crate::ore::{OreDeposit, OreKind};
use crate::rng::{Rng, hash_coords};
use crate::types::{ChunkPos, DepositId, TilePos};
use crate::world::CHUNK_SIZE;

/// Salt so ore placement is independent of other generated features.
const SALT_ORE: u64 = 0x0DE5_0DE5_0DE5_0DE5;

/// Chance, out of 100, that a chunk holds a deposit.
const DEPOSIT_CHANCE: u32 = 55;

/// Generate the ore deposit for one chunk, if it has one.
///
/// A deposit always fits entirely inside its own chunk, so deposits never
/// overlap. Purity and size grow with distance from `spawn`: the further out
/// you build, the better the ore.
pub fn deposit_in_chunk(
    seed: u64,
    chunk: ChunkPos,
    spawn: ChunkPos,
    id: DepositId,
) -> Option<OreDeposit> {
    let mut rng = Rng::new(hash_coords(seed, chunk.x, chunk.y, SALT_ORE));

    if rng.range(0, 100) >= DEPOSIT_CHANCE {
        return None;
    }

    let kind = match rng.range(0, 100) {
        0..40 => OreKind::Iron,
        40..70 => OreKind::Copper,
        70..90 => OreKind::Coal,
        _ => OreKind::Stone,
    };

    let radius = rng.range(2, 5) as i32; // 2..=4 tiles
    let span = (CHUNK_SIZE - 2 * radius) as u32; // room for the center so the patch stays in-chunk
    let center = TilePos::new(
        chunk.x * CHUNK_SIZE + radius + rng.range(0, span) as i32,
        chunk.y * CHUNK_SIZE + radius + rng.range(0, span) as i32,
    );

    let distance = chunk.distance(spawn) as u32;
    let purity = (15 + distance * 8 + rng.range(0, 15)).min(100) as u8;
    let amount = 400 + distance * 150 + rng.range(0, 600);

    Some(OreDeposit {
        id,
        kind,
        center,
        radius: radius as u8,
        amount,
        purity,
    })
}
