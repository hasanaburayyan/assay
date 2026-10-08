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
use crate::tuning::{PURITY_SPREAD, SHEET_SCALE, SPECIES_PER_WORLD, STARTER_MIN_PURITY};
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

/// One deposit's purity: `core_quality` plus a seeded spread, clamped to
/// 1–100 (ADR 0002, decision 13 of the 2026-10-01 demo-loop note).
///
/// THE SPREAD IS SYMMETRIC, which is what makes `core_quality` the world's
/// mean purity rather than merely its floor. An asymmetric `core + roll(0,
/// spread)` would read as "plus" too, but then raising the constant would
/// raise the floor and the mean by different amounts and the knob would be
/// harder to reason about from one number.
///
/// EXACTLY ONE `rng.range` CALL, whatever the arguments. Worldgen is a pure
/// function of `(seed, chunk)` and every peer must walk the same stream, so
/// a branch that consumed a different number of rolls would desync two
/// clients that disagreed only about a tuning constant.
///
/// Clamping does compress the spread once `core_quality` nears either end:
/// at 95 a deposit can only be 50–100. That is intended — a rich world has
/// no poor ore — and it is why the test asserts a *strictly rising mean*
/// rather than a shifted distribution.
///
/// **THE `1, 100` HERE IS NOT [`SHEET_SCALE`] AND MUST NOT BECOME IT**
/// (ASSA-279). Purity and a sheet property share two numbers and nothing
/// else: purity rounds into a `Grade`, a sheet value feeds property
/// thresholds, and a reading's scale is now published to hosts as a bar's
/// denominator. One constant for both would mean the day either range moved
/// the other moved with it, silently, and a purity bar would start claiming
/// a sheet's axis.
pub fn roll_purity(rng: &mut Rng, core_quality: u32) -> u8 {
    let offset = i64::from(rng.range(0, 2 * PURITY_SPREAD + 1)) - i64::from(PURITY_SPREAD);
    (i64::from(core_quality) + offset).clamp(1, 100) as u8
}

/// Generate the ore deposit for one chunk, if it has one.
///
/// A deposit always fits entirely inside its own chunk, so deposits never
/// overlap. Size grows with distance from `spawn`. Purity is `core_quality`
/// plus a seeded spread with no spatial trend: the "purer further out" rule
/// was withdrawn (ADR 0001) and ADR 0002 answers the question it left open.
/// The two `STARTER_CHUNKS` are the exception: they always hold rung zero,
/// floored at `STARTER_MIN_PURITY`.
///
/// `core_quality` is an argument and not a read of `tuning::CORE_QUALITY`
/// because the galaxy layer will set it per planet; until then every caller
/// passes the one constant.
pub fn deposit_in_chunk(
    seed: u64,
    chunk: ChunkPos,
    spawn: ChunkPos,
    id: DepositId,
    roster: &[MineralSpecies],
    core_quality: u32,
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
    let rolled = roll_purity(&mut rng, core_quality);
    let purity = if starter.is_some() {
        rolled.max(STARTER_MIN_PURITY as u8)
    } else {
        rolled
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
/// climbable and the first pick is worth building — the whole list is
/// [`ladder::starter_roster_ok`].
pub fn species_roster(seed: u64) -> Vec<MineralSpecies> {
    species_roster_attempts(seed).0
}

/// The roster, and how many rolls it took to find it.
///
/// **The count is for tests and nothing in the game reads it.** A reroll is
/// cheap but not free, and every condition added to
/// [`ladder::starter_roster_ok`] multiplies the attempts; `tests/ladder.rs`
/// measures the mean so a future condition cannot make worldgen expensive
/// without CI saying so.
pub fn species_roster_attempts(seed: u64) -> (Vec<MineralSpecies>, u64) {
    (0u64..)
        .map(|attempt| (roll_roster(seed, attempt), attempt + 1))
        .find(|(roster, _)| ladder::starter_roster_ok(roster))
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
                assayed: false,
                sheet,
            }
        })
        .collect()
}

/// One sheet property, rolled flat across [`SHEET_SCALE`].
///
/// The ends come from the constant rather than from `1` and `101` here
/// (ASSA-279), because a reading's scale is now published to hosts
/// (`debug::reading_scale`) and a bar drawn against it would be wrong the
/// moment these two literals and that constant disagreed.
///
/// `SHEET_SCALE.1 + 1` because `Rng::range` excludes its top and the scale is
/// inclusive at both ends.
fn roll(rng: &mut Rng) -> u8 {
    rng.range(u32::from(SHEET_SCALE.0), u32::from(SHEET_SCALE.1) + 1) as u8
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
