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

/// ADR 0001 withdrew "purity rises with distance from spawn". Purity is a
/// seeded roll: no positive trend with distance, and the full range shows up.
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
