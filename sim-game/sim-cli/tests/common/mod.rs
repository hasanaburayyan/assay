//! Scaffolding shared by the two play-through tests: `first_plate.rs` plays
//! the demo loop alone in one process, `three_peers.rs` plays it once between
//! three clients on a relay. Both need the same thing first — a seed whose
//! starter minerals can actually support the loop — and that choice belongs
//! in one place so the two tests cannot drift into proving different games.
//!
//! Nothing here is a rule. These are a test's own arithmetic over the rules
//! in `sim`, which is why it lives in `tests/` and not in the crate.
//!
//! Each test binary links its own copy and uses a different part of it: the
//! single-process play-through counts ticks to walk, the relay session waits
//! for the world to say it arrived.
#![allow(dead_code)]

use sim::tuning::{
    FRAME_BUDGET_PER_STRENGTH, GEAR_MIN_HARDNESS, HEAD_SIZE, HOPPER_SIZE, PLANTED_FRAME_SIZE,
};
use sim::worldgen::STARTER_CHUNKS;
use sim::{ChunkPos, OreDeposit, Property, TilePos, World};

/// Chebyshev distance: ticks it takes to walk between two tiles.
pub fn walk(from: TilePos, to: TilePos) -> i32 {
    (to.x - from.x).abs().max((to.y - from.y).abs())
}

/// A seed and the two deposits the starter ladder guarantees beside spawn.
pub struct Starter {
    pub seed: u64,
    pub world: World,
    pub material: OreDeposit,
    pub fuel: OreDeposit,
}

impl Starter {
    /// The item specs the CLI resolves against an inventory, for this world's
    /// generated species: `ore:<species>:<grade>` and friends.
    pub fn codes(&self) -> Codes {
        let ms = self.world.species(self.material.species);
        let fs = self.world.species(self.fuel.species);
        let species = ms.name().to_ascii_lowercase();
        let grade = self.material.grade().letter().to_ascii_lowercase();
        Codes {
            ore: format!("ore:{species}:{grade}"),
            refined: format!("refined:{species}:{grade}"),
            part: format!("{species}:{grade}"),
            fuel_ore: format!(
                "ore:{}:{}",
                fs.name().to_ascii_lowercase(),
                self.fuel.grade().letter().to_ascii_lowercase()
            ),
        }
    }
}

pub struct Codes {
    pub ore: String,
    pub refined: String,
    /// `<species>:<grade>`, which is how `make` and `assemble` name a part.
    pub part: String,
    pub fuel_ore: String,
}

/// The starter deposits of this seed's world, as a host will build it.
pub fn starters(seed: u64) -> (World, OreDeposit, OreDeposit) {
    // `sim_net::fresh_world` and not a `WorldConfig` written out here: the
    // same seed at `WorldConfig::default()`'s 8x8 is a DIFFERENT world, and
    // the doc comment above only stays true while one place decides the shape
    // (ASSA-53).
    let world = sim_net::fresh_world(seed);
    let at = |i: usize| {
        let (dx, dy) = STARTER_CHUNKS[i];
        let chunk = ChunkPos::new(world.spawn.x + dx, world.spawn.y + dy);
        world
            .deposits
            .iter()
            .find(|d| d.center.chunk() == chunk)
            .cloned()
            .expect("starter deposit")
    };
    let (material, fuel) = (at(0), at(1));
    (world, material, fuel)
}

/// Can the whole demo loop be played on this world's starter minerals?
///
/// Any seed starts climbable, but the loop needs more than the ladder:
///
/// - gears need the starter material hard enough at its rolled grade,
/// - the fuel must burn hot enough to melt that material,
/// - two deposits, so the party is not fighting over one tile,
/// - and (decision 11) the drill must fit its own frame's budget. Same
///   species throughout, that is `8 x density <= 15 x effective strength`
///   (sizes 5 + 1 + 2 against `PLANTED_FRAME_SIZE x FRAME_BUDGET_PER_STRENGTH`).
///   On a seed where it fails, the honest outcome is a drill that breaks when
///   planted — a correct sim and a useless play-through.
pub fn supports_the_loop(w: &World, m: &OreDeposit, f: &OreDeposit) -> bool {
    let (ms, fs) = (w.species(m.species), w.species(f.species));
    let drill_mass = (PLANTED_FRAME_SIZE + HEAD_SIZE + HOPPER_SIZE) * u32::from(ms.sheet.density);
    let frame_budget = PLANTED_FRAME_SIZE
        * FRAME_BUDGET_PER_STRENGTH
        * ms.effective(Property::Strength, m.grade());
    ms.effective(Property::Hardness, m.grade()) >= GEAR_MIN_HARDNESS
        // ASKS THE SIM, not a fifth copy of the comparison. This line used to
        // re-derive "the fuel melts the material" and it was the fourth copy
        // of it in the tree (ASSA-139); it also omitted the fuel-threshold
        // half, so it counted a rock with reactivity 20 as fuel when the sim
        // would not light it at all.
        && sim::ladder::pair_smelts(ms, fs, f.grade())
        && m.species != f.species
        && drill_mass <= frame_budget
}

/// The first seed that supports the loop and whatever else the caller needs.
/// Most seeds pass; searching beats hard-coding one, because a seed-dependent
/// play-through is a play-through of one world rather than of the game.
pub fn demo_seed(extra: impl Fn(&World, &OreDeposit, &OreDeposit) -> bool) -> Starter {
    (1..400)
        .map(starters)
        .find(|(w, m, f)| supports_the_loop(w, m, f) && extra(w, m, f))
        .map(|(world, material, fuel)| Starter {
            seed: world.seed,
            world,
            material,
            fuel,
        })
        .expect("some seed supports the full loop")
}
