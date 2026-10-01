use sim::{
    ChunkPos, DepositId, Event, Input, PlayerCommand, PlayerId, RejectReason, SystemCommand,
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
/// The range this asserts (10 and below, 90 and above) is no longer the
/// whole 1–100: at the default core quality the roll spans 5–95, so these
/// bounds say "wide", not "saturated". `raising_core_quality_*` below owns
/// the part of decision 13 that this test cannot see.
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
        lowest <= 10 && highest >= 90,
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
