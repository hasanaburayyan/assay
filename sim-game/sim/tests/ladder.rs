//! ADR 0001 decisions 10 and 11: every world has a climbable starter ladder
//! and abundant rung zero next to spawn.

use sim::ladder::{
    JUDGED_AT, hand_lit_fuel, hand_minable, rungs, starter_pick_speed, starter_species,
};
use sim::mineral::Property;
use sim::tuning::{
    HAND_WORK_PER_TICK, MIN_HAND_MINABLE_SPECIES, MIN_STARTER_RUNGS, STARTER_MIN_PURITY,
    WORK_PER_UNIT,
};
use sim::worldgen::{STARTER_CHUNKS, species_roster, species_roster_attempts};
use sim::{ChunkPos, Grade, World, WorldConfig};

/// How many seeds the sweeps below cover. A roster roll is pure arithmetic on
/// six species, so this costs tenths of a second; the figures in
/// `docs/design-notes/2026-10-01-hardness-gears-and-alloys.md` were measured
/// over 2000 and re-measured over 4000.
const SEEDS: u64 = 1000;

fn world(seed: u64) -> World {
    World::new(WorldConfig {
        seed,
        width_chunks: 6,
        height_chunks: 4,
    })
}

#[test]
fn a_hundred_seeds_all_have_a_climbable_ladder() {
    for seed in 0..100 {
        let w = world(seed);
        let r = rungs(&w.species);
        assert!(
            r.len() >= MIN_STARTER_RUNGS,
            "seed {seed}: only {} rungs\n{}",
            r.len(),
            sim::debug::species_table(&w)
        );
        let (material, fuel) = starter_species(&w.species).expect("starter species");
        assert!(hand_minable(w.species(material)));
        assert!(hand_lit_fuel(w.species(fuel)));
        // Each rung needs something new: it is non-empty and disjoint.
        let mut seen = Vec::new();
        for rung in &r {
            assert!(!rung.is_empty());
            for id in rung {
                assert!(!seen.contains(id), "seed {seed}: {id:?} in two rungs");
                seen.push(*id);
            }
        }
    }
}

#[test]
fn rung_zero_sits_next_to_spawn_at_a_useful_purity() {
    for seed in 0..100 {
        let w = world(seed);
        let (material, fuel) = starter_species(&w.species).unwrap();
        for (i, (dx, dy)) in STARTER_CHUNKS.iter().enumerate() {
            let chunk = ChunkPos::new(w.spawn.x + dx, w.spawn.y + dy);
            let d = w
                .deposits
                .iter()
                .find(|d| d.center.chunk() == chunk)
                .unwrap_or_else(|| panic!("seed {seed}: no starter deposit in {chunk:?}"));
            assert_eq!(d.species, [material, fuel][i], "seed {seed}");
            assert!(u32::from(d.purity) >= STARTER_MIN_PURITY);
            assert!(d.grade() >= Grade::B);
            // Decision 11: finite but far more than a smelter needs.
            assert!(d.amount >= 400);
        }
    }
}

#[test]
fn a_roster_nobody_can_mine_has_no_rungs() {
    let mut w = world(1);
    for s in &mut w.species {
        s.sheet.hardness = 100;
    }
    assert!(rungs(&w.species).is_empty());
    assert!(starter_species(&w.species).is_none());
}

#[test]
fn rung_zero_needs_a_fire_hot_enough_for_the_ore() {
    let mut w = world(1);
    let soft = |hardness, heat, reactivity| sim::Sheet {
        density: 50,
        strength: 50,
        hardness,
        heat_tolerance: heat,
        reactivity,
        conductivity: 50,
    };
    for s in &mut w.species {
        s.sheet = soft(100, 50, 1); // unreachable unless set below
    }
    w.species[0].sheet = soft(30, 25, 60); // hand-lit fuel: burns at 48 (grade B)
    w.species[1].sheet = soft(30, 45, 1); // smeltable: heat 45 ≤ fire 48
    w.species[2].sheet = soft(30, 49, 1); // too hot for that fire
    let r = rungs(&w.species);
    assert_eq!(r.len(), 1, "{r:?}");
    assert_eq!(r[0], vec![w.species[0].id, w.species[1].id]);

    // A hotter fuel that only lights from the first fire extends the fire
    // to 72, which brings species 2 within reach (still rung zero: no new
    // tool was needed, just a hotter fire).
    w.species[3].sheet = soft(30, 48, 90);
    let r = rungs(&w.species);
    assert_eq!(r.len(), 1, "{r:?}");
    assert!(r[0].contains(&w.species[2].id));
}

// ---------------------------------------------------------------------------
// ASSA-35: the first tool is worth building, and two species are minable
// ---------------------------------------------------------------------------

/// **THE ONE THING THE DEMO PROMISES ABOUT ITS FIRST BUILD.** A player's
/// first pick must mine faster than the hands that built it; a loop whose
/// first tool is a downgrade teaches "do not build".
///
/// Over 2000 seeds the old `rung0.first()` starter lost that race in 40% of
/// worlds. The last assertion here is the one that keeps this test honest:
/// it proves the guarantee is still doing work, by showing that the species
/// the old rule would have picked still loses in some of these very worlds.
/// If worldgen ever became generous enough that any starter would do, this
/// fails and says so rather than passing for free.
#[test]
fn every_worlds_first_pick_beats_the_hands_that_built_it() {
    let hands = HAND_WORK_PER_TICK;
    let mut worst = u32::MAX;
    let mut old_rule_would_have_lost = 0;
    for seed in 0..SEEDS {
        let roster = species_roster(seed);
        let (material, _) = starter_species(&roster).expect("every world has a starter");
        let speed = starter_pick_speed(&roster, material);
        assert!(
            speed > hands,
            "seed {seed}: the first pick mines at {speed} against bare hands at \
             {hands} — the first thing the player builds is a downgrade\n{}",
            sim::debug::species_table(&World::new(WorldConfig {
                seed,
                width_chunks: 6,
                height_chunks: 4
            }))
        );
        worst = worst.min(speed);
        let first = rungs(&roster)[0][0];
        if starter_pick_speed(&roster, first) <= hands {
            old_rule_would_have_lost += 1;
        }
    }
    // Ticks per unit, the way the readout says it: lower is faster, and bare
    // hands are 4.00. Reported rather than pinned, because the exact worst
    // case is a property of the seed space and not a rule.
    println!(
        "worst accepted pick: {:.2} ticks/unit against the hands' {:.2}",
        f64::from(WORK_PER_UNIT) / f64::from(worst),
        f64::from(WORK_PER_UNIT) / f64::from(hands)
    );
    assert!(
        old_rule_would_have_lost > 0,
        "NOTHING IS BEING GUARANTEED ANY MORE: in all {SEEDS} worlds the \
         first species in rung zero would also have beaten hands, so this \
         test can no longer fail for the reason it exists. Check that \
         `starter_species` still selects on hardness."
    );
}

/// The starter material is the **hardest** species in rung zero, because
/// hardness is the only property a head reads — picking on anything else is
/// picking at random for the purpose the species is chosen for.
///
/// Built by hand rather than hunted for in the seed space: three minable
/// species in roster order soft, hardest, middling, so `rung0.first()` and
/// "hardest" are different answers and the old rule fails this.
#[test]
fn the_starter_material_is_the_hardest_species_in_rung_zero() {
    let mut w = world(1);
    let sheet = |hardness| sim::Sheet {
        density: 50,
        strength: 50,
        hardness,
        heat_tolerance: 25,
        reactivity: 60,
        conductivity: 50,
    };
    for s in &mut w.species {
        s.sheet = sheet(100); // unminable unless set below
    }
    w.species[0].sheet = sheet(10);
    w.species[1].sheet = sheet(40);
    w.species[2].sheet = sheet(25);
    let rung0 = rungs(&w.species).into_iter().next().expect("a rung zero");
    assert_eq!(rung0.len(), 3, "all three must be in rung zero: {rung0:?}");

    let (material, _) = starter_species(&w.species).expect("a starter");
    assert_eq!(
        material, w.species[1].id,
        "the starter must be the hardest in rung zero, not the first"
    );
    // Resolved to the property rather than trusted by index: this is what
    // "hardest" means, read at the grade the ladder judges at.
    let hardest = w
        .species
        .iter()
        .filter(|s| rung0.contains(&s.id))
        .map(|s| s.effective(Property::Hardness, JUDGED_AT))
        .max()
        .unwrap();
    assert_eq!(
        w.species(material).effective(Property::Hardness, JUDGED_AT),
        hardest
    );
}

/// **TIES MUST BREAK THE SAME WAY ON EVERY MACHINE** or two peers generate
/// different worlds from one seed, which lockstep cannot survive. Lowest id
/// wins; `effective` rounds, so ties are not rare — two species of base
/// hardness 35 and 36 both read 28 at grade B.
///
/// My first draft of this used 40 and 41, which tie at grade B and taught me
/// something instead: `hand_minable` reads BASE hardness against the gate, so
/// 41 never reaches rung zero at all and there was no tie to break. Both
/// sides of a tie have to be minable for the tie to exist.
#[test]
fn a_tie_for_hardest_breaks_by_lowest_species_id() {
    let mut w = world(1);
    let sheet = |hardness| sim::Sheet {
        density: 50,
        strength: 50,
        hardness,
        heat_tolerance: 25,
        reactivity: 60,
        conductivity: 50,
    };
    for s in &mut w.species {
        s.sheet = sheet(100);
    }
    // 35 and 36 both read 28 at grade B, so this is a tie on the number the
    // selection actually compares, not on base hardness, and both are inside
    // the hand gate so both are really in rung zero.
    w.species[0].sheet = sheet(10);
    w.species[1].sheet = sheet(36);
    w.species[2].sheet = sheet(35);
    let at_b = |i: usize| w.species[i].effective(Property::Hardness, JUDGED_AT);
    assert_eq!(at_b(1), at_b(2), "the premise: these must tie at grade B");
    assert!(
        hand_minable(&w.species[1]) && hand_minable(&w.species[2]),
        "and both sides of the tie must be in rung zero for a tie to exist"
    );

    let (material, _) = starter_species(&w.species).expect("a starter");
    assert_eq!(material, w.species[1].id, "the lower id must win the tie");

    // And the same roster with the tie in the other order still answers with
    // the lower id, which a `max_by_key` keeping the last match would not.
    w.species[1].sheet = sheet(35);
    w.species[2].sheet = sheet(36);
    let (material, _) = starter_species(&w.species).expect("a starter");
    assert_eq!(material, w.species[1].id, "still the lower id");
}

/// With one hand-minable species the assay action is decoration: five
/// property sheets and nothing to compare them against, so no material
/// decision anywhere in the demo. 9.2% of rosters that pass the rung check
/// hold exactly one.
#[test]
fn every_world_has_at_least_two_hand_minable_species() {
    for seed in 0..SEEDS {
        let roster = species_roster(seed);
        let minable = roster.iter().filter(|s| hand_minable(s)).count();
        assert!(
            minable >= MIN_HAND_MINABLE_SPECIES,
            "seed {seed}: only {minable} hand-minable species"
        );
    }
}

/// **THE GUARANTEE IS THE STARTER SPECIES ONLY** (the Game Director's words
/// and I agree): every other species stays a gamble you have to assay to
/// read, and choosing badly is the spine of the game. If this ever fails,
/// worldgen has started handing out worlds where nothing can go wrong.
#[test]
fn only_the_starter_species_is_guaranteed_to_be_worth_mining() {
    let mut worlds_with_an_unminable_species = 0;
    let mut worlds_with_a_minable_dud = 0;
    for seed in 0..SEEDS {
        let roster = species_roster(seed);
        let (material, _) = starter_species(&roster).unwrap();
        for s in &roster {
            if !hand_minable(s) {
                worlds_with_an_unminable_species += 1;
                break;
            }
        }
        // A species you CAN mine whose head would still lose to bare hands:
        // the trap the starter is protected from and nothing else is.
        if roster.iter().any(|s| {
            s.id != material
                && hand_minable(s)
                && starter_pick_speed(&roster, s.id) <= HAND_WORK_PER_TICK
        }) {
            worlds_with_a_minable_dud += 1;
        }
    }
    assert!(
        worlds_with_an_unminable_species > SEEDS / 2,
        "only {worlds_with_an_unminable_species} of {SEEDS} worlds hold a \
         species too hard for hands — the hardness gamble has gone soft"
    );
    assert!(
        worlds_with_a_minable_dud > SEEDS / 4,
        "only {worlds_with_a_minable_dud} of {SEEDS} worlds hold a minable \
         species that makes a worse-than-hands head — picking the wrong \
         material no longer costs anything"
    );
}

/// **A REROLL IS CHEAP BUT NOT FREE, AND EVERY CONDITION MULTIPLIES IT.**
/// Measured when ASSA-35 landed: the loop went from 2.47 attempts per world
/// to 3.44 (2000 and 4000 seeds agree to within 0.04), worst seed 17 rolls
/// to 30. The 1.41 figure in the design note is the MULTIPLIER on the
/// existing loop — 2.47 x 1.41 = 3.48 — not the total.
///
/// The bound is loose on purpose: this is here to catch a condition that
/// makes worldgen cost ten rolls a world, not to pin a measurement that
/// moves with the sample.
#[test]
fn the_roster_reroll_stays_cheap() {
    let mut total = 0u64;
    let mut worst = 0u64;
    for seed in 0..SEEDS {
        let (_, attempts) = species_roster_attempts(seed);
        total += attempts;
        worst = worst.max(attempts);
    }
    let mean = total as f64 / SEEDS as f64;
    println!("roster reroll: mean {mean:.3} attempts, worst {worst}");
    assert!(
        mean > 1.0,
        "the reroll is not rerolling at all ({mean:.3} attempts), so the \
         conditions in `starter_roster_ok` are not being applied"
    );
    assert!(
        mean < 6.0,
        "WORLDGEN HAS GOT EXPENSIVE: {mean:.3} rolls per world, was 3.44 \
         when ASSA-35 landed. A condition added to `starter_roster_ok` \
         multiplies this; if it is wanted, measure it and move the bound."
    );
}
