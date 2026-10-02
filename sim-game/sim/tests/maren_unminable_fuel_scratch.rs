//! SCRATCH (Game Director, ASSA-58 follow-up). Not a guard: this measures
//! what an UNMINABLE fuel row says, to price Marlow's three options.
//!
//! The question: 45.6% of fuel rows sit on rock nobody can mine, and they now
//! carry a lighting state computed from physics the player can never touch.
//! Two things I want numbers for, because "it is still true" is Marlow's
//! option 1 and the cost of leaving it is the only argument against it:
//!   (a) how often the moot row carries the SELL, "lights from cold";
//!   (b) how often reading the table top-down, the FIRST "lights from cold"
//!       you meet is on rock you can never hold.
//! (b) is the harm: the ASSA-58 work taught the player to scan for that
//! phrase, and the table is read in order.

use sim::{Grade, Property, World, WorldConfig};

fn host_world(seed: u64) -> World {
    World::new(WorldConfig {
        seed,
        width_chunks: 6,
        height_chunks: 4,
    })
}

fn is_fuel(s: &sim::MineralSpecies) -> bool {
    Grade::ALL
        .into_iter()
        .any(|g| s.effective(Property::Reactivity, g) >= sim::tuning::FUEL_MIN_REACTIVITY)
}

#[test]
fn what_an_unminable_fuel_row_says() {
    const SEEDS: u32 = 2000;
    let (mut rows, mut unminable_fuel) = (0u32, 0u32);
    let (mut cold, mut hotter, mut never) = (0u32, 0u32, 0u32);
    // Reading order: is the first "lights from cold" row in the table one you
    // can never mine?
    let (mut worlds_with_cold, mut first_cold_is_moot) = (0u32, 0u32);
    // And the weaker version: does the moot row merely appear ABOVE a real one?
    let mut moot_above_real = 0u32;
    for seed in 1..=u64::from(SEEDS) {
        let w = host_world(seed);
        let mut first_cold: Option<bool> = None; // Some(moot?)
        let (mut saw_moot_cold, mut saw_real_cold) = (false, false);
        for s in &w.species {
            if !is_fuel(s) {
                continue;
            }
            rows += 1;
            let minable = sim::ladder::hand_minable(s);
            if minable {
                if matches!(sim::ladder::lighting(&w.species, s.id), sim::ladder::Lighting::FromCold)
                {
                    saw_real_cold = true;
                    if first_cold.is_none() {
                        first_cold = Some(false);
                    }
                }
                continue;
            }
            unminable_fuel += 1;
            match sim::ladder::lighting(&w.species, s.id) {
                sim::ladder::Lighting::FromCold => {
                    cold += 1;
                    if !saw_real_cold {
                        saw_moot_cold = true;
                    }
                    if first_cold.is_none() {
                        first_cold = Some(true);
                    }
                }
                sim::ladder::Lighting::FromAHotterFire => hotter += 1,
                sim::ladder::Lighting::NothingBurnsHotEnough => never += 1,
            }
        }
        if let Some(moot) = first_cold {
            worlds_with_cold += 1;
            if moot {
                first_cold_is_moot += 1;
            }
        }
        if saw_moot_cold && saw_real_cold {
            moot_above_real += 1;
        }
    }
    let pc = |n: u32, d: u32| 100.0 * f64::from(n) / f64::from(d.max(1));
    println!("{SEEDS} worlds, {rows} fuel rows");
    println!(
        "unminable fuel rows: {unminable_fuel} ({:.1}% of fuel rows)",
        pc(unminable_fuel, rows)
    );
    println!(
        "  of those: lights from cold {cold} ({:.1}%), needs a hotter fire {hotter} ({:.1}%), \
         nothing burns hot enough {never} ({:.1}%)",
        pc(cold, unminable_fuel),
        pc(hotter, unminable_fuel),
        pc(never, unminable_fuel)
    );
    println!(
        "worlds whose table shows any 'lights from cold': {worlds_with_cold}; \
         the FIRST such row is unminable in {first_cold_is_moot} ({:.1}%)",
        pc(first_cold_is_moot, worlds_with_cold)
    );
    println!(
        "worlds where a moot 'lights from cold' sits above a real one: {moot_above_real} \
         ({:.1}% of worlds)",
        pc(moot_above_real, SEEDS)
    );
}

/// The two worlds humans actually read: the #38 bench and the pinned friend
/// seed. Priority turns on whether the defect is in front of them.
#[test]
fn the_two_human_worlds() {
    for seed in [777042u64, 14247] {
        let w = host_world(seed);
        println!("--- seed {seed}");
        for line in sim::debug::species_table(&w).lines() {
            if line.contains("fuel at") || line.starts_with("id") {
                println!("{line}");
            }
        }
    }
}
