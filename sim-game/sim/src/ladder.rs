//! The starter ladder (ADR 0001, decision 10): given a roster, which species
//! can a fresh player use, and which become usable once those are in hand?
//!
//! Worldgen rerolls a roster until this check passes, so every world starts
//! climbable. The model is deliberately simple and only reads the rules
//! that exist today plus the next one (drill heads):
//!
//! - **Mine** a species if its hardness is within what you can mine: bare
//!   hands at first, later the best drill head you could make, which mines
//!   up to its own effective hardness.
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

use crate::mineral::{Grade, MineralSpecies, Property, SpeciesId};
use crate::tuning::{FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, HAND_SPARK_TEMPERATURE};

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
        // Drill heads made from what's usable mine up to their hardness.
        mine = species
            .iter()
            .filter(|s| usable[usize::from(s.id.0)])
            .map(|s| s.effective(Property::Hardness, JUDGED_AT))
            .fold(mine, u32::max);
    }
}

/// Rung zero's two guaranteed deposits: a species to mine, smelt and build
/// with, and a fuel the player can light by hand. May be the same species.
pub fn starter_species(species: &[MineralSpecies]) -> Option<(SpeciesId, SpeciesId)> {
    let rung0 = rungs(species).into_iter().next()?;
    let material = *rung0.first()?;
    let fuel = species.iter().find(|s| hand_lit_fuel(s))?.id;
    Some((material, fuel))
}
