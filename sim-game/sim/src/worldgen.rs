//! Procedural world generation.
//!
//! Every chunk's contents are a pure function of `(seed, chunk)`. Chunks can
//! be generated in any order, or lazily when a player first explores them,
//! and always come out identical. Later we only need to save the chunks
//! players have changed.
//!
//! The mineral roster is a pure function of the seed too (ADR 0001): there
//! is no fixed list of ores.

use crate::ladder;
use crate::mineral::{MineralSpecies, Sheet, SpeciesId};
use crate::ore::OreDeposit;
use crate::rng::{Rng, hash_coords, mix};
use crate::tuning::{MIN_STARTER_RUNGS, SPECIES_PER_WORLD, STARTER_MIN_PURITY};
use crate::types::{ChunkPos, DepositId, TilePos};
use crate::world::CHUNK_SIZE;

/// Salt so ore placement is independent of other generated features.
const SALT_ORE: u64 = 0x0DE5_0DE5_0DE5_0DE5;
/// Salt for the species roster.
const SALT_SPECIES: u64 = 0x5BEC_1E5A_7B1E_0001;

/// Chance, out of 100, that a chunk holds a deposit.
const DEPOSIT_CHANCE: u32 = 55;

/// Chunks next to spawn that always hold rung zero: the first one gets the
/// starter material, the second the hand-lit fuel.
pub const STARTER_CHUNKS: [(i32, i32); 2] = [(1, 0), (0, 1)];

/// Generate the ore deposit for one chunk, if it has one.
///
/// A deposit always fits entirely inside its own chunk, so deposits never
/// overlap. Size grows with distance from `spawn`. Purity is a plain seeded
/// roll with no spatial trend: the "purer further out" rule was withdrawn
/// (ADR 0001) until purity's source is decided. The two `STARTER_CHUNKS`
/// are the exception: they always hold rung zero at a purity from
/// `STARTER_MIN_PURITY` up.
pub fn deposit_in_chunk(
    seed: u64,
    chunk: ChunkPos,
    spawn: ChunkPos,
    id: DepositId,
    roster: &[MineralSpecies],
) -> Option<OreDeposit> {
    let mut rng = Rng::new(hash_coords(seed, chunk.x, chunk.y, SALT_ORE));

    let starter = STARTER_CHUNKS
        .iter()
        .position(|&(dx, dy)| chunk == ChunkPos::new(spawn.x + dx, spawn.y + dy))
        .and_then(|i| {
            let (material, fuel) = ladder::starter_species(roster)?;
            Some([material, fuel][i])
        });

    if rng.range(0, 100) >= DEPOSIT_CHANCE && starter.is_none() {
        return None;
    }

    let species = starter.unwrap_or(SpeciesId(rng.range(0, roster.len() as u32) as u8));

    let radius = rng.range(2, 5) as i32; // 2..=4 tiles
    let span = (CHUNK_SIZE - 2 * radius) as u32; // room for the center so the patch stays in-chunk
    let center = TilePos::new(
        chunk.x * CHUNK_SIZE + radius + rng.range(0, span) as i32,
        chunk.y * CHUNK_SIZE + radius + rng.range(0, span) as i32,
    );

    let distance = chunk.distance(spawn) as u32;
    let purity = if starter.is_some() {
        rng.range(STARTER_MIN_PURITY, 101) as u8
    } else {
        rng.range(1, 101) as u8
    };
    let amount = 400 + distance * 150 + rng.range(0, 600);

    Some(OreDeposit {
        id,
        species,
        center,
        radius: radius as u8,
        amount,
        purity,
    })
}

/// The world's mineral species: `SPECIES_PER_WORLD` of them, each with a
/// rolled property sheet and a rolled name. Names start with distinct
/// letters so the ASCII map can show one letter per species.
///
/// Rosters are rerolled (deterministically) until the starter ladder is
/// climbable: at least `MIN_STARTER_RUNGS` rungs and a hand-lit fuel.
pub fn species_roster(seed: u64) -> Vec<MineralSpecies> {
    (0u64..)
        .map(|attempt| roll_roster(seed, attempt))
        .find(|roster| {
            ladder::rungs(roster).len() >= MIN_STARTER_RUNGS
                && ladder::starter_species(roster).is_some()
        })
        .expect("some roster passes the ladder check")
}

fn roll_roster(seed: u64, attempt: u64) -> Vec<MineralSpecies> {
    let mut rng = Rng::new(mix(seed ^ SALT_SPECIES ^ mix(attempt)));
    let mut initials: Vec<u8> = Vec::new();
    (0..SPECIES_PER_WORLD)
        .map(|i| {
            let sheet = Sheet {
                density: roll(&mut rng),
                strength: roll(&mut rng),
                hardness: roll(&mut rng),
                heat_tolerance: roll(&mut rng),
                reactivity: roll(&mut rng),
                conductivity: roll(&mut rng),
            };
            let generated_name = generate_name(&mut rng, &mut initials);
            MineralSpecies {
                id: SpeciesId(i as u8),
                generated_name,
                player_name: None,
                discoverer: None,
                rename_grants: Vec::new(),
                sheet,
            }
        })
        .collect()
}

fn roll(rng: &mut Rng) -> u8 {
    rng.range(1, 101) as u8
}

const ONSETS: [&str; 20] = [
    "b", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z", "th", "kr", "br",
    "gl", "st",
];
const VOWELS: [&str; 8] = ["a", "e", "i", "o", "u", "ae", "io", "ou"];
const CODAS: [&str; 8] = ["n", "r", "l", "s", "m", "k", "x", "rn"];
const SUFFIXES: [&str; 6] = ["ite", "ium", "ine", "ore", "ase", "yte"];

/// A mineral-sounding name, with a first letter no other species uses.
fn generate_name(rng: &mut Rng, initials: &mut Vec<u8>) -> String {
    loop {
        let onset = ONSETS[rng.range(0, ONSETS.len() as u32) as usize];
        let first = onset.as_bytes()[0];
        if initials.contains(&first) {
            continue;
        }
        initials.push(first);
        let mut name = String::new();
        name.push_str(onset);
        name.push_str(VOWELS[rng.range(0, VOWELS.len() as u32) as usize]);
        if rng.range(0, 2) == 0 {
            name.push_str(CODAS[rng.range(0, CODAS.len() as u32) as usize]);
            name.push_str(ONSETS[rng.range(0, 15) as usize]);
            name.push_str(VOWELS[rng.range(0, 5) as usize]);
        }
        name.push_str(CODAS[rng.range(0, CODAS.len() as u32) as usize]);
        name.push_str(SUFFIXES[rng.range(0, SUFFIXES.len() as u32) as usize]);
        let mut chars = name.chars();
        let first = chars.next().expect("non-empty").to_ascii_uppercase();
        return format!("{first}{}", chars.as_str());
    }
}
