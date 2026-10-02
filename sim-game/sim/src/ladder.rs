//! The starter ladder (ADR 0001, decision 10): given a roster, which species
//! can a fresh player use, and which become usable once those are in hand?
//!
//! Worldgen rerolls a roster until this check passes, so every world starts
//! climbable. The model is deliberately simple and only reads the rules
//! that exist today plus the next one (drill heads):
//!
//! - **Mine** a species if its hardness is within what you can mine: bare
//!   hands at first, later the best drill head you could make, which is
//!   *modelled* here as mining up to its own effective hardness.
//!   **THE SIM DOES NOT IMPLEMENT THAT YET** — `HAND_MINE_MAX_HARDNESS`
//!   gates machine mining as well as hand mining (`step.rs`), so nothing in
//!   the game mines hardness above 40 whatever it is made of. Harmless only
//!   because `MIN_STARTER_RUNGS` is 1, so no rung above zero is ever
//!   required. When reach is built, gate it on the head's **effective
//!   hardness** and not on `HEAD_SPEED_PER_HARDNESS`: reach is not speed.
//! - **Build a smelter** from any minable species; its walls take that
//!   species' heat tolerance.
//! - **Fuel** is any minable species reactive enough. It lights by hand if
//!   its heat tolerance is within the hand spark, or from a fire already
//!   burning at least that hot.
//! - A species is **usable** once it is minable and a fire you can build
//!   and feed reaches its heat tolerance. Each rung is the set of species
//!   that become usable together.
//!
//! Capabilities are judged at grade B, a margin below the best roll, so the
//! guarantee holds with average ore.

use crate::assembly::{Assembly, Mount, Part, PartKind};
use crate::item::{Item, ItemKind};
use crate::mineral::{Grade, MineralSpecies, Property, SpeciesId};
use crate::tuning::{
    FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, HAND_SPARK_TEMPERATURE, HAND_WORK_PER_TICK,
    MIN_HAND_MINABLE_SPECIES, MIN_STARTER_RUNGS,
};

/// The grade capabilities are judged at.
pub const JUDGED_AT: Grade = Grade::B;

pub fn hand_minable(s: &MineralSpecies) -> bool {
    u32::from(s.sheet.hardness) <= HAND_MINE_MAX_HARDNESS
}

/// How hot this species burns at the judged grade, if it counts as fuel.
pub fn burn_temperature(s: &MineralSpecies) -> Option<u32> {
    let t = s.effective(Property::Reactivity, JUDGED_AT);
    (t >= FUEL_MIN_REACTIVITY).then_some(t)
}

/// Fuel a player can mine and light with no machine at all.
pub fn hand_lit_fuel(s: &MineralSpecies) -> bool {
    hand_minable(s)
        && burn_temperature(s).is_some()
        && u32::from(s.sheet.heat_tolerance) <= HAND_SPARK_TEMPERATURE
}

/// The hottest fire you can keep going with these minable species: light
/// what the hand spark lights, then anything that fire lights, and so on.
fn best_fire(minable: &[&MineralSpecies]) -> u32 {
    let mut fire = 0;
    let mut spark = HAND_SPARK_TEMPERATURE;
    loop {
        let reachable = minable
            .iter()
            .filter(|s| u32::from(s.sheet.heat_tolerance) <= spark)
            .filter_map(|s| burn_temperature(s))
            .max()
            .unwrap_or(0);
        if reachable <= fire {
            return fire;
        }
        fire = reachable;
        spark = spark.max(fire);
    }
}

/// Which species become usable at each rung, starting from bare hands.
/// Empty if nothing at all can be smelted by hand.
pub fn rungs(species: &[MineralSpecies]) -> Vec<Vec<SpeciesId>> {
    let mut usable = vec![false; species.len()];
    let mut rungs = Vec::new();
    let mut mine = HAND_MINE_MAX_HARDNESS;
    loop {
        let minable: Vec<&MineralSpecies> = species
            .iter()
            .filter(|s| u32::from(s.sheet.hardness) <= mine)
            .collect();
        let walls = minable
            .iter()
            .map(|s| u32::from(s.sheet.heat_tolerance))
            .max()
            .unwrap_or(0);
        let fire = best_fire(&minable);
        let newly: Vec<SpeciesId> = minable
            .iter()
            .filter(|s| !usable[usize::from(s.id.0)])
            .filter(|s| u32::from(s.sheet.heat_tolerance) <= walls.min(fire))
            .map(|s| s.id)
            .collect();
        if newly.is_empty() {
            return rungs;
        }
        for id in &newly {
            usable[usize::from(id.0)] = true;
        }
        rungs.push(newly);
        // The model's climb: drill heads made from what's usable mine up to
        // their own hardness. See the module doc — `step.rs` does not do this
        // yet, and no rung above zero is required while `MIN_STARTER_RUNGS`
        // is 1.
        mine = species
            .iter()
            .filter(|s| usable[usize::from(s.id.0)])
            .map(|s| s.effective(Property::Hardness, JUDGED_AT))
            .fold(mine, u32::max);
    }
}

/// Can bare hands actually *use* this species — mine it **and** smelt it?
///
/// **RUNG ZERO IS THE AUTHORITY AND THIS RE-DERIVES NOTHING** (Game Director's
/// ruling on ASSA-52). [`hand_minable`] answers a smaller question than it
/// looks: a species can pass the hardness gate and still never become a part,
/// because smelting needs a fire hot enough for its heat tolerance **and** a
/// smelter whose walls survive that fire. Over 2000 worlds 13.6% of deposits
/// are exactly that, 59.3% of worlds hold one, and 13.9% put one under spawn.
///
/// Asking [`rungs`] rather than comparing temperatures here is the whole point:
/// the fire you can build, what it can light, and what those walls survive are
/// already decided in one place, and a second copy would drift from it the
/// first time the chain changed.
pub fn usable_from_bare_hands(species: &[MineralSpecies], id: SpeciesId) -> bool {
    rungs(species)
        .first()
        .is_some_and(|rung_zero| rung_zero.contains(&id))
}

/// Rung zero's two guaranteed deposits: a species to mine, smelt and build
/// with, and a fuel the player can light by hand. May be the same species.
///
/// **THE MATERIAL IS THE HARDEST SPECIES IN RUNG ZERO**, at the judged grade,
/// ties by lowest id (Game Director's ruling on ASSA-6; ASSA-35). It used to
/// be `rung0.first()` — roster order, so effectively at random among the
/// hand-minable species — and over 2000 seeds the pick built from it was
/// *slower than the bare hands that built it* in 40% of worlds. Hardness is
/// the only property a head reads, so selecting on anything else here is
/// selecting on nothing. This alone leaves 23.9%, which is why
/// [`starter_roster_ok`] also rerolls; see
/// `docs/design-notes/2026-10-01-hardness-gears-and-alloys.md`.
///
/// Ties must break deterministically or two peers disagree about the world.
pub fn starter_species(species: &[MineralSpecies]) -> Option<(SpeciesId, SpeciesId)> {
    let rung0 = rungs(species).into_iter().next()?;
    let material = *rung0.iter().min_by_key(|id| {
        let s = &species[usize::from(id.0)];
        (
            std::cmp::Reverse(s.effective(Property::Hardness, JUDGED_AT)),
            id.0,
        )
    })?;
    let fuel = species.iter().find(|s| hand_lit_fuel(s))?.id;
    Some((material, fuel))
}

/// How fast the demo's first pick mines: a handle and a head, both of
/// `material` at the judged grade.
///
/// **This is the number `step` reads for a held tool**, not a re-derivation
/// of it — it goes through the real `PART_SPECS` row and the real
/// [`Assembly::stats`], so a handle that started contributing speed, or a
/// head row that stopped reading hardness, changes this too. Compare it
/// against [`HAND_WORK_PER_TICK`], which is what `mine_by_hand` uses when a
/// player holds nothing.
pub fn starter_pick_speed(species: &[MineralSpecies], material: SpeciesId) -> u32 {
    let refined = Item::new(ItemKind::Refined, material, JUDGED_AT);
    Assembly::new(
        Part::of(PartKind::Frame(Mount::Held), refined),
        vec![Part::of(PartKind::Head, refined)],
    )
    .stats(species)
    .speed
}

/// Every condition worldgen rerolls a roster until it meets. One place, so
/// the reroll loop and the tests that measure its cost read the same list.
///
/// 1. At least [`MIN_STARTER_RUNGS`] rungs, with a hand-lit fuel — a world
///    nobody can mine or smelt is not a world.
/// 2. **The first pick beats bare hands.** The demo's first build is a pick
///    of the starter species; if it is slower than hands, the loop's first
///    lesson is "do not build". A rate factor cannot fix this, because it is
///    a tail and not a mean: a starter of hardness 5 makes a useless head at
///    any factor.
/// 3. **At least [`MIN_HAND_MINABLE_SPECIES`] species are hand-minable.**
///    With one, assaying is decoration — five property sheets and nothing to
///    compare them against, so no material decision anywhere.
///
/// Together these accept 70.9% of rosters that already pass (1), measured
/// over 2000 seeds, and the guarantee is the **starter species only**: every
/// other species stays a gamble you have to assay to read.
pub fn starter_roster_ok(species: &[MineralSpecies]) -> bool {
    let Some((material, _fuel)) = starter_species(species) else {
        return false;
    };
    rungs(species).len() >= MIN_STARTER_RUNGS
        && starter_pick_speed(species, material) > HAND_WORK_PER_TICK
        && species.iter().filter(|s| hand_minable(s)).count() >= MIN_HAND_MINABLE_SPECIES
}
