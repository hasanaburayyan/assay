use sim::{
    ChunkPos, DepositId, Event, Grade, Input, PlayerCommand, PlayerId, RejectReason, SystemCommand,
    TilePos, World, WorldConfig, step,
};

fn config(seed: u64) -> WorldConfig {
    WorldConfig {
        seed,
        ..WorldConfig::default()
    }
}

#[test]
fn same_seed_builds_the_same_world() {
    let a = World::new(config(42));
    let b = World::new(config(42));
    assert_eq!(a, b);
    assert_eq!(a.state_hash(), b.state_hash());
}

#[test]
fn different_seeds_build_different_worlds() {
    assert_ne!(
        World::new(config(1)).state_hash(),
        World::new(config(2)).state_hash()
    );
}

#[test]
fn a_big_world_has_deposits_of_every_species() {
    let world = World::new(WorldConfig {
        seed: 7,
        width_chunks: 16,
        height_chunks: 16,
    });
    for s in &world.species {
        assert!(
            world.deposits.iter().any(|d| d.species == s.id),
            "no deposits of {}",
            s.name()
        );
    }
}

#[test]
fn deposits_stay_in_bounds_and_never_overlap() {
    for seed in 0..20 {
        let world = World::new(config(seed));
        for y in 0..world.height() {
            for x in 0..world.width() {
                let pos = TilePos::new(x, y);
                let covering = world.deposits.iter().filter(|d| d.contains(pos)).count();
                assert!(
                    covering <= 1,
                    "seed {seed}: {covering} deposits overlap at {pos:?}"
                );
            }
        }
        for d in &world.deposits {
            let r = i32::from(d.radius);
            for (dx, dy) in [(-r, 0), (r, 0), (0, -r), (0, r)] {
                let edge = TilePos::new(d.center.x + dx, d.center.y + dy);
                assert!(
                    world.in_bounds(edge),
                    "seed {seed}: {:?} leaves the map",
                    d.id
                );
            }
        }
    }
}

#[test]
fn deposit_ids_match_their_index() {
    let world = World::new(config(3));
    for (i, d) in world.deposits.iter().enumerate() {
        assert_eq!(d.id, DepositId(i as u32));
        assert_eq!(world.deposit(d.id), Some(d));
    }
}

/// ADR 0001 withdrew "purity rises with distance from spawn" and ADR 0002
/// answers the question it left open: purity is core quality plus a seeded
/// spread. Still no positive trend with distance, and a world still spans a
/// wide range of purities.
///
/// The range this asserts (10 and below, 75 and above) is no longer the
/// whole 1–100: at the default core quality the roll spans 2–82 (ASSA-13
/// retuned that down from 5–95), so these bounds say "wide", not
/// "saturated". `raising_core_quality_*` below owns the part of decision 13
/// that this test cannot see.
#[test]
fn purity_has_no_distance_trend_and_spans_the_range() {
    let (mut near, mut far) = ((0u64, 0u64), (0u64, 0u64));
    let (mut lowest, mut highest) = (u8::MAX, u8::MIN);
    for seed in 0..40 {
        let world = World::new(WorldConfig {
            seed,
            width_chunks: 16,
            height_chunks: 16,
        });
        for d in &world.deposits {
            lowest = lowest.min(d.purity);
            highest = highest.max(d.purity);
            let bucket = match d.center.chunk().distance(world.spawn) {
                0..=1 => &mut near,
                2..=3 => continue,
                _ => &mut far,
            };
            bucket.0 += u64::from(d.purity);
            bucket.1 += 1;
        }
    }
    let (near_avg, far_avg) = (near.0 / near.1, far.0 / far.1);
    assert!(
        far_avg <= near_avg + 5,
        "far ore ({far_avg}) is still purer on average than near ore ({near_avg})"
    );
    assert!(
        lowest <= 10 && highest >= 75,
        "purity range {lowest}..{highest}"
    );
}

/// Every deposit a fixed seed would generate at a given core quality, in
/// `World::new`'s own row-major chunk order.
///
/// It walks `deposit_in_chunk` rather than building a `World` on purpose:
/// `World::new` passes `tuning::CORE_QUALITY`, so a test that went through
/// it could only ever see one value of the knob this test exists to vary.
fn purities_at(seed: u64, core_quality: u32) -> Vec<u8> {
    let (width, height) = (16, 16);
    let spawn = ChunkPos::new(width / 2, height / 2);
    let species = sim::worldgen::species_roster(seed);
    let mut purities = Vec::new();
    for cy in 0..height {
        for cx in 0..width {
            let id = DepositId(purities.len() as u32);
            if let Some(d) = sim::worldgen::deposit_in_chunk(
                seed,
                ChunkPos::new(cx, cy),
                spawn,
                id,
                &species,
                core_quality,
            ) {
                purities.push(d.purity);
            }
        }
    }
    purities
}

/// ADR 0002 / decision 13: "Raising the constant shifts the whole world
/// toward higher purity without removing variance." Test, verbatim: raising
/// the constant raises the mean deposit purity of a fixed seed while
/// deposits still vary.
///
/// BOTH HALVES MATTER AND THEY PULL AGAINST EACH OTHER. A roll that ignored
/// the constant would keep the variance and fail the mean; a roll that
/// returned the constant would move the mean and kill the variance. Only a
/// baseline-plus-spread passes both, which is why the two assertions live in
/// one test.
#[test]
fn raising_core_quality_raises_mean_purity_without_flattening_it() {
    let seed = 7;
    let mut previous_mean = 0.0;
    for core_quality in [20, 35, 50, 65, 80] {
        let purities = purities_at(seed, core_quality);

        // The case is reached: a seed with no deposits would pass every
        // assertion below without measuring anything.
        assert!(
            purities.len() >= 50,
            "core quality {core_quality}: only {} deposits to average",
            purities.len()
        );

        let mean = purities.iter().map(|&p| f64::from(p)).sum::<f64>() / purities.len() as f64;
        assert!(
            mean > previous_mean,
            "core quality {core_quality}: mean purity {mean:.1} did not rise above {previous_mean:.1}"
        );

        // Still varied: the spread survives the shift. Anything that
        // collapsed toward the constant would show up here.
        let (lowest, highest) = (
            *purities.iter().min().expect("deposits"),
            *purities.iter().max().expect("deposits"),
        );
        assert!(
            highest - lowest >= 40,
            "core quality {core_quality}: purity only spans {lowest}..{highest}"
        );

        previous_mean = mean;
    }
}

/// ASSA-13: grade A has to be rare enough that the refining ladder has a
/// job. `sort` and `resmelt` are built, tested and in the golden hash, and
/// their only purpose is climbing to A — so if A is easy to find, walking one
/// chunk over dominates refining and both recipes ship as dead content.
///
/// THIS GUARDS THE DESIGN RULE, NOT ONE NUMBER. The band holds the ruled
/// 42/40 (A ~16%) and the named fallback 40/35 (A ~8.5%), and fails the
/// 50/45 that shipped on ASSA-3 (A 28.6%). Retuning the two constants inside
/// the rule is free; retuning past it has to be argued.
///
/// Run with `--nocapture` for the printed distribution.
#[test]
fn grade_a_is_rare_enough_that_refining_has_a_job() {
    let (mut c, mut b, mut a) = (0usize, 0usize, 0usize);
    for seed in 0..40 {
        let purities = purities_at(seed, sim::tuning::CORE_QUALITY);

        // The case is reached: a seed with no deposits would pass every
        // share assertion below without measuring anything.
        assert!(
            purities.len() >= 50,
            "seed {seed}: only {} deposits to count",
            purities.len()
        );

        let mut seen = [0usize; 3];
        for p in purities {
            match Grade::from_purity(p) {
                Grade::C => seen[0] += 1,
                Grade::B => seen[1] += 1,
                Grade::A => seen[2] += 1,
            }
        }
        assert!(
            seen.iter().all(|&n| n > 0),
            "seed {seed}: a world must still hold all three grades, got C/B/A {seen:?}"
        );
        c += seen[0];
        b += seen[1];
        a += seen[2];
    }

    let total = c + b + a;
    let share = |n: usize| 100.0 * n as f64 / total as f64;
    assert!(
        total > 5_000,
        "only {total} deposits: too few to call a distribution"
    );
    println!(
        "purity grades over {total} deposits at core quality {} spread {}: \
         C {:.1}% / B {:.1}% / A {:.1}%",
        sim::tuning::CORE_QUALITY,
        sim::tuning::PURITY_SPREAD,
        share(c),
        share(b),
        share(a)
    );
    assert!(
        (5.0..=22.0).contains(&share(a)),
        "grade A is {:.1}% of deposits: outside the 5-22% the refining ladder needs \
         (C {:.1}% / B {:.1}%)",
        share(a),
        share(c),
        share(b)
    );
}

/// ADR 0002 points 1 and 4 claim the spread is symmetric about core quality
/// and that the shipped constants do not reach the 1–100 clamp. Both claims
/// were prose until now, and the clamp one is load-bearing: clamping is what
/// would make the knob non-linear in the mean, so a tuning pair that silently
/// clamped would quietly break the argument the ADR rests on.
///
/// Observed min and max must equal `CORE_QUALITY ∓ PURITY_SPREAD` exactly.
/// That is one assertion for three properties: symmetry, no clamping, and the
/// whole span actually being reachable. It is deterministic — fixed seeds, so
/// it can never flake, only be true or false.
#[test]
fn the_purity_roll_is_symmetric_and_never_clamps() {
    let (mut lowest, mut highest) = (u8::MAX, u8::MIN);
    let mut counted = 0usize;
    for seed in 0..40 {
        // Starter chunks are floored at STARTER_MIN_PURITY, so they can only
        // raise the minimum; every other deposit is a bare roll.
        for p in purities_at(seed, sim::tuning::CORE_QUALITY) {
            lowest = lowest.min(p);
            highest = highest.max(p);
            counted += 1;
        }
    }
    assert!(counted > 5_000, "only {counted} deposits rolled");

    // Signed on purpose: a spread wider than core quality must report the
    // band it wanted (a negative floor) rather than underflow.
    let (cq, spread) = (
        i64::from(sim::tuning::CORE_QUALITY),
        i64::from(sim::tuning::PURITY_SPREAD),
    );
    assert_eq!(
        (i64::from(lowest), i64::from(highest)),
        (cq - spread, cq + spread),
        "purity spans {lowest}..{highest}, not {}..{} — the roll is clamping, or no \
         longer symmetric about core quality {cq}",
        cq - spread,
        cq + spread
    );
}

/// The starter chunks' floor is a guarantee, not a distribution (ADR 0002):
/// it holds even when core quality is set low enough that an ordinary
/// deposit could never reach it.
#[test]
fn starter_deposits_keep_their_floor_at_any_core_quality() {
    let species = sim::worldgen::species_roster(3);
    let spawn = ChunkPos::new(8, 8);
    for (i, &(dx, dy)) in sim::worldgen::STARTER_CHUNKS.iter().enumerate() {
        let deposit = sim::worldgen::deposit_in_chunk(
            3,
            ChunkPos::new(spawn.x + dx, spawn.y + dy),
            spawn,
            DepositId(i as u32),
            &species,
            1,
        )
        .expect("a starter chunk always holds a deposit");
        assert!(
            u32::from(deposit.purity) >= sim::tuning::STARTER_MIN_PURITY,
            "starter deposit purity {} fell below the floor",
            deposit.purity
        );
    }
}

#[test]
fn chunks_generate_the_same_in_any_order() {
    let world = World::new(config(5));
    for d in &world.deposits {
        let regenerated = sim::worldgen::deposit_in_chunk(
            world.seed,
            d.center.chunk(),
            world.spawn,
            d.id,
            &world.species,
            sim::tuning::CORE_QUALITY,
        );
        assert_eq!(regenerated.as_ref(), Some(d));
    }
    // A chunk outside the map can still be generated on demand.
    let _ = sim::worldgen::deposit_in_chunk(
        world.seed,
        ChunkPos::new(-50, 900),
        world.spawn,
        DepositId(0),
        &world.species,
        sim::tuning::CORE_QUALITY,
    );
}

/// A world with one player, "ada", already joined.
fn world_with_player(seed: u64) -> (World, PlayerId) {
    let mut world = World::new(config(seed));
    let mut events = Vec::new();
    step(
        &mut world,
        &[Input::System(SystemCommand::AddPlayer {
            name: "ada".into(),
        })],
        &mut events,
    );
    (world, PlayerId(0))
}

#[test]
fn commands_from_unknown_players_are_rejected() {
    let (mut world, _) = world_with_player(9);
    let before = world.clone();
    let mut events = Vec::new();
    step(
        &mut world,
        &[Input::player(PlayerId(5), PlayerCommand::Mine)],
        &mut events,
    );
    assert_eq!(world.deposits, before.deposits);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::UnknownPlayer,
            ..
        }]
    ));
}

/// The replay property: same seed + same input log = same world, bit for bit.
#[test]
fn replaying_an_input_log_reproduces_the_world() {
    let log: Vec<(u64, Input)> = (1..200)
        .filter(|t| t % 7 == 0)
        .map(|t| {
            let cmd = if t % 3 == 0 {
                PlayerCommand::Mine
            } else {
                PlayerCommand::MoveTo {
                    target: TilePos::new((t % 90) as i32, (t % 60) as i32),
                }
            };
            (t, Input::player(PlayerId(0), cmd))
        })
        .collect();

    let run = || {
        let (mut world, _) = world_with_player(123);
        let mut events = Vec::new();
        for tick in 1..200 {
            let inputs: Vec<Input> = log
                .iter()
                .filter(|(t, _)| *t == tick)
                .map(|(_, i)| i.clone())
                .collect();
            step(&mut world, &inputs, &mut events);
        }
        (world.state_hash(), events)
    };

    assert_eq!(run(), run());
}
