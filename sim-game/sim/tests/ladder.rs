//! ADR 0001 decisions 10 and 11: every world has a climbable starter ladder
//! and abundant rung zero next to spawn.

use sim::ladder::{
    JUDGED_AT, burn_temperature_at, carries_first_machine, hand_lit_fuel, hand_minable,
    pair_smelts, rungs, starter_pick_speed, starter_roster_ok, starter_species,
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

// =====================================================================
// ASSA-139: the pair the ladder hands out must actually smelt.
// =====================================================================

/// **THE GUARANTEE, AND IT IS THE WHOLE POINT OF THE LADDER.** Rung-zero
/// membership is judged against the best walls and the hottest chained fire
/// in the roster; the starter pair gets one hand-lit fuel and a smelter built
/// out of the material. Over 2000 worlds the pair could not light at all in
/// 1.8% of them and the player's only guaranteed path ended at a smelter
/// stalled forever.
///
/// Judged twice, and the second is the one that matters: at [`JUDGED_AT`],
/// which is the grade `starter_roster_ok` rerolls on, and then at the grade
/// the deposit worldgen actually puts beside spawn holds — because a
/// guarantee stated at a grade nobody can reach is not one. They agree today
/// only because `STARTER_MIN_PURITY` grades at or above `JUDGED_AT`, which is
/// its own test below.
#[test]
fn the_starter_pair_smelts_in_every_world() {
    const PAIR_SEEDS: u64 = 2000;
    for seed in 0..PAIR_SEEDS {
        let w = world(seed);
        let (material, fuel) = starter_species(&w.species).expect("a starter pair");
        let (ms, fs) = (w.species(material), w.species(fuel));
        assert!(
            pair_smelts(ms, fs, JUDGED_AT),
            "seed {seed}: {} needs {} and {} burns at {:?} at grade {}",
            ms.name(),
            ms.sheet.heat_tolerance,
            fs.name(),
            burn_temperature_at(fs, JUDGED_AT),
            JUDGED_AT.letter(),
        );
        // ...and at the grade the guaranteed deposit really holds.
        let (dx, dy) = STARTER_CHUNKS[1];
        let chunk = ChunkPos::new(w.spawn.x + dx, w.spawn.y + dy);
        let fuel_deposit = w
            .deposits
            .iter()
            .find(|d| d.center.chunk() == chunk)
            .unwrap_or_else(|| panic!("seed {seed}: no guaranteed fuel deposit"));
        assert_eq!(fuel_deposit.species, fuel, "seed {seed}");
        assert!(
            pair_smelts(ms, fs, fuel_deposit.grade()),
            "seed {seed}: the GUARANTEED fuel deposit is grade {} and will not \
             melt {} (needs {})",
            fuel_deposit.grade().letter(),
            ms.name(),
            ms.sheet.heat_tolerance,
        );
    }
}

/// **THE TWO CONSTANTS THE GUARANTEE RESTS ON, AND NOTHING ELSE TIED THEM.**
/// `starter_roster_ok` rerolls until the pair smelts at [`JUDGED_AT`];
/// `worldgen::deposit_in_chunk` floors the two starter deposits at
/// `STARTER_MIN_PURITY`. The promise is true only while the second grades at
/// least as high as the first.
///
/// MEASURED, and it corrects what I first wrote here: at
/// `STARTER_MIN_PURITY = 39` the existing
/// `rung_zero_sits_next_to_spawn_at_a_useful_purity` **stays green** — it
/// asserts the grade of the deposits a few seeds actually rolled, and a floor
/// of 39 still rolls above 40 most of the time. What does catch it is
/// `the_starter_pair_smelts_in_every_world`, because its second assertion
/// judges at the deposit's real grade. So this test is not the only lever,
/// but it is the only one that names the *reason*, and it fails on the
/// constant rather than on 1 seed in 2000.
///
/// This is the answer to "which grade is the guarantee stated at": the one
/// worldgen can deliver next to spawn, which is a LOCATED promise and not an
/// idealised one. Demanding the pair smelt at grade C instead — so that *any*
/// deposit of those species would do — costs 22.4% of rosters, measured on
/// ASSA-139, and buys a different guarantee than ADR 0001 decided on.
#[test]
fn the_judged_grade_is_one_worldgen_can_deliver_beside_spawn() {
    let floored = Grade::from_purity(STARTER_MIN_PURITY as u8);
    assert!(
        floored >= JUDGED_AT,
        "STARTER_MIN_PURITY {STARTER_MIN_PURITY} grades {} but the ladder \
         judges at {}, so the pair is cleared at a grade the guaranteed \
         deposit does not hold",
        floored.letter(),
        JUDGED_AT.letter(),
    );
}

/// **THE FUEL IS PICKED ON THE ONE PROPERTY ITS JOB READS.** It was
/// `species.iter().find(hand_lit_fuel)` — roster order — which is the exact
/// defect the doc comment above `starter_species` describes for the material's
/// own history, left on the fuel line.
///
/// The premise is asserted too, and it is not decoration: if the hottest
/// hand-lit fuel were always also the first one in roster order, this test
/// would pass against the code it is here to reject.
#[test]
fn the_starter_fuel_is_the_hottest_hand_lit_species() {
    let mut roster_order_would_differ = 0u32;
    for seed in 0..SEEDS {
        let w = world(seed);
        let (_, fuel) = starter_species(&w.species).expect("a starter pair");
        let hottest = w
            .species
            .iter()
            .filter(|s| hand_lit_fuel(s))
            .filter_map(|s| burn_temperature_at(s, JUDGED_AT))
            .max()
            .expect("a hand-lit fuel");
        assert_eq!(
            burn_temperature_at(w.species(fuel), JUDGED_AT),
            Some(hottest),
            "seed {seed}: the starter fuel is not the hottest hand-lit species"
        );
        let first = w
            .species
            .iter()
            .find(|s| hand_lit_fuel(s))
            .expect("a hand-lit fuel")
            .id;
        if first != fuel {
            roster_order_would_differ += 1;
        }
    }
    assert!(
        roster_order_would_differ > SEEDS as u32 / 10,
        "only {roster_order_would_differ} of {SEEDS} worlds have a hottest \
         hand-lit fuel that is not simply the first one in roster order, so \
         this test cannot tell the two picks apart"
    );
    println!("the pick differs from roster order in {roster_order_would_differ} of {SEEDS} worlds");
}

/// Ties break by lowest id on the fuel line as they do on the material's, or
/// two peers roll different worlds from one seed.
#[test]
fn a_tie_for_hottest_fuel_breaks_by_lowest_species_id() {
    let mut w = world(7);
    let fuel_sheet = |hardness, reactivity| sim::Sheet {
        density: 50,
        strength: 50,
        hardness,
        heat_tolerance: 10, // lights from cold
        reactivity,
        conductivity: 50,
    };
    // Everything unminable, then three hand-lit fuels: two tied hottest and
    // one cooler, with the tie NOT first in roster order.
    for s in &mut w.species {
        s.sheet = fuel_sheet(100, 60);
    }
    w.species[0].sheet = fuel_sheet(10, 50);
    w.species[1].sheet = fuel_sheet(10, 90);
    w.species[2].sheet = fuel_sheet(10, 90);
    let (_, fuel) = starter_species(&w.species).expect("a starter pair");
    assert_eq!(
        fuel, w.species[1].id,
        "the hottest fuel must win and a tie must break by lowest id, not by \
         whichever `max_by_key` saw last"
    );
}

/// **THE HARDEST RUNG-ZERO SPECIES THAT CARRIES A FIRST PLANTED MACHINE**, not
/// simply the hardest (ASSA-170, out of Maren's ASSA-155 ruling).
///
/// A frame reads STRENGTH and sets the whole mass budget; a head reads
/// hardness. Picking on hardness alone and then building the frame out of the
/// answer is `assay-rulings` §5's "one species, selected on one property, then
/// used for three jobs" — and over 2000 worlds it cost a first machine in
/// 15.2% of them where ANOTHER rung-zero species would have carried one.
///
/// Built by hand for the same reason as the test above: the hardest species is
/// heavy and weak, a softer one is light and strong, so "hardest" and "hardest
/// that stands" are different answers and the old rule fails this.
#[test]
fn the_starter_material_is_the_hardest_rung_zero_species_that_carries_a_machine() {
    let mut w = world(1);
    let sheet = |density, strength, hardness| sim::Sheet {
        density,
        strength,
        hardness,
        heat_tolerance: 25, // hand-lit, so a starter pair exists at all
        reactivity: 60,
        conductivity: 50,
    };
    for s in &mut w.species {
        s.sheet = sheet(50, 50, 100); // unminable unless set below
    }
    w.species[0].sheet = sheet(100, 1, 40); // hardest, and far too heavy for its own frame
    w.species[1].sheet = sheet(1, 100, 25); // softer, and carries easily
    let rung0 = rungs(&w.species).into_iter().next().expect("a rung zero");
    assert_eq!(rung0.len(), 2, "both must be in rung zero: {rung0:?}");

    // THE PREMISE, ASSERTED RATHER THAN ASSUMED. Without this the test passes
    // whenever the two species happen to agree, which is most of the seed
    // space — the shape of a green test that is decoration.
    assert!(
        !carries_first_machine(&w.species, w.species[0].id, JUDGED_AT),
        "the hardest species must NOT carry a machine or there is nothing to choose between"
    );
    assert!(
        carries_first_machine(&w.species, w.species[1].id, JUDGED_AT),
        "the softer species must carry one or this roster has no right answer"
    );

    let (material, _) = starter_species(&w.species).expect("a starter");
    assert_eq!(
        material, w.species[1].id,
        "the starter must be the hardest species that CARRIES a first machine, not the \
         hardest species"
    );
}

/// And where nothing in rung zero carries a machine, **the old answer survives
/// untouched**: every candidate ties on the leading term, so the key reduces to
/// hardness exactly as before. This is why ASSA-170 step 1 rejects no roster —
/// it changes the pick only where a better pick exists.
#[test]
fn where_no_rung_zero_species_carries_a_machine_the_hardest_still_wins() {
    let mut w = world(1);
    let sheet = |hardness| sim::Sheet {
        density: 100, // heavy and weak: nothing here carries its own frame
        strength: 1,
        hardness,
        heat_tolerance: 25,
        reactivity: 60,
        conductivity: 50,
    };
    for s in &mut w.species {
        s.sheet = sheet(100);
    }
    w.species[0].sheet = sheet(10);
    w.species[1].sheet = sheet(40);
    w.species[2].sheet = sheet(25);
    let rung0 = rungs(&w.species).into_iter().next().expect("a rung zero");
    assert!(
        rung0
            .iter()
            .all(|id| !carries_first_machine(&w.species, *id, JUDGED_AT)),
        "the premise is that NOTHING in rung zero carries a machine"
    );

    let (material, _) = starter_species(&w.species).expect("a starter");
    assert_eq!(
        material, w.species[1].id,
        "with no carrier to prefer, the hardest must still win"
    );
}

/// **EVERY WORLD'S STARTER CARRIES A FIRST PLANTED MACHINE** (ASSA-170 step 2;
/// Maren's ASSA-155 ruling: rung zero promises a first planted machine, not
/// only "you can mine this and smelt it").
///
/// This is the guard the step-2 clause exists for, and it is a sweep rather
/// than a fixture because the thing being promised is a property of the seed
/// space. Step 1 alone leaves 9.6% of worlds with no carrier anywhere in rung
/// zero; removing the clause from `starter_roster_ok` turns this red.
#[test]
fn every_worlds_starter_carries_a_first_planted_machine() {
    for seed in 0..SEEDS {
        let roster = species_roster(seed);
        let (material, _) = starter_species(&roster).expect("every world has a starter");
        assert!(
            carries_first_machine(&roster, material, JUDGED_AT),
            "seed {seed}: the starter species cannot carry a frame and a head, so the world \
             cannot deliver the first planted machine rung zero promises"
        );
    }
}

/// And the clause is what does it: a roster that passes every OTHER condition
/// and holds no carrier is refused.
///
/// **EACH OF THE OTHER FOUR CONDITIONS IS ASSERTED FIRST**, because a test that
/// only checks the final `false` passes whenever the roster fails for some
/// unrelated reason — which is a test that cannot tell this clause from any of
/// the others, and would stay green if the clause were deleted tomorrow.
#[test]
fn a_roster_with_no_first_machine_in_rung_zero_is_refused() {
    let mut w = world(1);
    let sheet = |hardness| sim::Sheet {
        density: 100, // heavy and weak: nothing here carries its own frame
        strength: 1,
        hardness,
        heat_tolerance: 25, // hand-lit, and walls the fire can reach
        reactivity: 60,
        conductivity: 50,
    };
    for s in &mut w.species {
        s.sheet = sheet(100);
    }
    w.species[0].sheet = sheet(10);
    w.species[1].sheet = sheet(40);
    w.species[2].sheet = sheet(25);
    let roster = w.species.clone();
    let (material, fuel) = starter_species(&roster).expect("a starter pair");

    // THE PREMISE: every other clause in `starter_roster_ok` passes.
    assert!(rungs(&roster).len() >= MIN_STARTER_RUNGS, "rungs");
    assert!(
        starter_pick_speed(&roster, material) > HAND_WORK_PER_TICK,
        "the first pick must beat bare hands or this roster fails for that reason instead"
    );
    assert!(
        roster.iter().filter(|s| hand_minable(s)).count() >= MIN_HAND_MINABLE_SPECIES,
        "hand-minable count"
    );
    assert!(
        pair_smelts(
            &roster[usize::from(material.0)],
            &roster[usize::from(fuel.0)],
            JUDGED_AT
        ),
        "the pair must smelt or this roster fails for that reason instead"
    );
    assert!(
        !carries_first_machine(&roster, material, JUDGED_AT),
        "the premise is that the starter cannot carry a machine"
    );

    assert!(
        !starter_roster_ok(&roster),
        "a roster that passes everything else and holds no first planted machine must be \
         rerolled, which is the whole of ASSA-170 step 2"
    );
}
