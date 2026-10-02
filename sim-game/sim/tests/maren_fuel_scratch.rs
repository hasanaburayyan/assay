//! SCRATCH (Maren, design measurement, not for merge as-is).
//! How often does the species table's "fuel at X or better" note send a
//! player to a smelter that will not light from cold?
use sim::ladder;
use sim::mineral::Property;
use sim::{Grade, World, WorldConfig};
use sim::tuning::FUEL_MIN_REACTIVITY;

fn world(seed: u64) -> World {
    World::new(WorldConfig { seed, ..WorldConfig::default() })
}

/// Does the species table print a "fuel at X or better" note for this one?
fn labelled_fuel(s: &sim::mineral::MineralSpecies) -> bool {
    Grade::ALL.into_iter().rev().any(|g| s.effective(Property::Reactivity, g) >= FUEL_MIN_REACTIVITY)
}

/// The only row that can mislead: the table already says "too hard for
/// anything you can build", so a fuel label on unminable rock is not what
/// sends a player anywhere. The misleading row is HAND-MINABLE + labelled
/// fuel + will not spark.
#[test]
fn how_often_does_the_fuel_note_mislead() {
    const N: u64 = 5000;
    let (mut labelled, mut labelled_unlit) = (0u64, 0u64);
    let (mut worlds_first_fails, mut worlds_any_unlit) = (0u64, 0u64);
    let mut tries_hist = [0u64; 8];
    for seed in 0..N {
        let w = world(seed);
        let fuels: Vec<_> = w
            .species
            .iter()
            .filter(|s| labelled_fuel(s) && ladder::hand_minable(s))
            .collect();
        labelled += fuels.len() as u64;
        let unlit = fuels.iter().filter(|s| !ladder::hand_lit_fuel(s)).count();
        labelled_unlit += unlit as u64;
        if unlit > 0 { worlds_any_unlit += 1; }
        // Reading order = species id order, which is the table's order.
        match fuels.iter().position(|s| ladder::hand_lit_fuel(s)) {
            Some(0) => tries_hist[0] += 1,
            Some(n) => { worlds_first_fails += 1; tries_hist[n.min(7)] += 1; }
            None => tries_hist[7] += 1,
        }
    }
    println!("worlds {N}");
    println!("HAND-MINABLE species labelled 'fuel at X or better': {labelled} ({:.2} per world)", labelled as f64 / N as f64);
    println!("  of those, CANNOT be lit from cold: {labelled_unlit} ({:.1}%)", 100.0 * labelled_unlit as f64 / labelled as f64);
    println!("worlds with >=1 misleading fuel label: {worlds_any_unlit} ({:.1}%)", 100.0 * worlds_any_unlit as f64 / N as f64);
    println!("worlds where the FIRST fuel-labelled row does not light: {worlds_first_fails} ({:.1}%)", 100.0 * worlds_first_fails as f64 / N as f64);
    println!("tries needed to find a lighting fuel, reading top-down: {tries_hist:?}");
}

/// If the row is going to say "needs a fire already burning", that fire has
/// to exist in this world, or it is the ASSA-43 trap again: a promise the
/// world does not keep. Replicates `ladder::best_fire`, which is private.
fn best_fire(w: &World) -> u32 {
    let minable: Vec<_> = w.species.iter().filter(|s| ladder::hand_minable(s)).collect();
    let mut fire = 0u32;
    loop {
        let spark = sim::tuning::HAND_SPARK_TEMPERATURE.max(fire);
        let reachable = minable
            .iter()
            .filter(|s| u32::from(s.sheet.heat_tolerance) <= spark)
            .filter_map(|s| ladder::burn_temperature(s))
            .max()
            .unwrap_or(0);
        if reachable <= fire { return fire; }
        fire = reachable;
    }
}

#[test]
fn is_the_hotter_fire_actually_reachable() {
    const N: u64 = 5000;
    let (mut unlit, mut unlit_but_reachable, mut unlit_forever) = (0u64, 0u64, 0u64);
    for seed in 0..N {
        let w = world(seed);
        let fire = best_fire(&w);
        for s in w.species.iter().filter(|s| labelled_fuel(s) && ladder::hand_minable(s)) {
            if ladder::hand_lit_fuel(s) { continue; }
            unlit += 1;
            if u32::from(s.sheet.heat_tolerance) <= fire { unlit_but_reachable += 1 } else { unlit_forever += 1 }
        }
    }
    println!("hand-minable fuel labels that will not spark: {unlit}");
    println!("  lightable off a fire this world can build: {unlit_but_reachable} ({:.1}%)", 100.0 * unlit_but_reachable as f64 / unlit as f64);
    println!("  NEVER lightable in this world:              {unlit_forever} ({:.1}%)", 100.0 * unlit_forever as f64 / unlit as f64);
}

#[test]
fn name_the_three_states_on_real_seeds() {
    for seed in [14247u64, 777042] {
        let w = world(seed);
        let fire = best_fire(&w);
        println!("--- seed {seed} (best fire this world can build: {fire}) ---");
        for s in &w.species {
            if !labelled_fuel(s) || !ladder::hand_minable(s) { continue; }
            let heat = u32::from(s.sheet.heat_tolerance);
            let state = if ladder::hand_lit_fuel(s) { "1 LIGHTS FROM COLD" }
                else if heat <= fire { "2 needs a hotter fire (reachable)" }
                else { "3 NOTHING HERE CAN EVER LIGHT IT" };
            println!("  {:<12} heat {:>3} burn {:>3?}  {state}", s.name(), heat, ladder::burn_temperature(s));
        }
    }
}
