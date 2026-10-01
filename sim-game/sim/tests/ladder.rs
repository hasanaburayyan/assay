//! ADR 0001 decisions 10 and 11: every world has a climbable starter ladder
//! and abundant rung zero next to spawn.

use sim::ladder::{hand_lit_fuel, hand_minable, rungs, starter_species};
use sim::tuning::{MIN_STARTER_RUNGS, STARTER_MIN_PURITY};
use sim::worldgen::STARTER_CHUNKS;
use sim::{ChunkPos, Grade, World, WorldConfig};

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
