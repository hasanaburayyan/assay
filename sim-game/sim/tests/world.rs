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
fn world_has_deposits_of_every_kind() {
    let world = World::new(WorldConfig {
        seed: 7,
        width_chunks: 16,
        height_chunks: 16,
    });
    for kind in sim::OreKind::ALL {
        assert!(
            world.deposits.iter().any(|d| d.kind == kind),
            "no {kind:?} deposits"
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

#[test]
fn far_ore_is_purer_than_ore_near_spawn() {
    let world = World::new(WorldConfig {
        seed: 11,
        width_chunks: 16,
        height_chunks: 16,
    });
    let dist = |c: TilePos| c.chunk().distance(world.spawn);
    let near_max = world
        .deposits
        .iter()
        .filter(|d| dist(d.center) <= 1)
        .map(|d| d.purity)
        .max();
    let far_min = world
        .deposits
        .iter()
        .filter(|d| dist(d.center) >= 3)
        .map(|d| d.purity)
        .min();
    let (Some(near_max), Some(far_min)) = (near_max, far_min) else {
        panic!("world too small to compare near and far deposits");
    };
    assert!(
        far_min > near_max,
        "far min {far_min} should beat near max {near_max}"
    );
}

#[test]
fn chunks_generate_the_same_in_any_order() {
    let world = World::new(config(5));
    for d in &world.deposits {
        let regenerated =
            sim::worldgen::deposit_in_chunk(world.seed, d.center.chunk(), world.spawn, d.id);
        assert_eq!(regenerated.as_ref(), Some(d));
    }
    // A chunk outside the map can still be generated on demand.
    let _ = sim::worldgen::deposit_in_chunk(
        world.seed,
        ChunkPos::new(-50, 900),
        world.spawn,
        DepositId(0),
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

fn extract(deposit: DepositId, amount: u32) -> PlayerCommand {
    PlayerCommand::Extract { deposit, amount }
}

#[test]
fn extract_takes_ore_and_reports_it() {
    let (mut world, me) = world_with_player(9);
    let id = world.deposits[0].id;
    let before = world.deposits[0].amount;
    let mut events = Vec::new();

    step(
        &mut world,
        &[Input::player(me, extract(id, 10))],
        &mut events,
    );

    assert_eq!(world.deposit(id).unwrap().amount, before - 10);
    let kind = world.deposits[0].kind;
    assert_eq!(world.player(me).unwrap().inventory.count(kind.into()), 10);
    assert_eq!(world.player(me).unwrap().inventory.total(), 10);
    assert_eq!(
        events,
        vec![Event::OreExtracted {
            player: me,
            deposit: id,
            kind: world.deposits[0].kind,
            amount: 10
        }]
    );
}

#[test]
fn over_extracting_depletes_then_rejects() {
    let (mut world, me) = world_with_player(9);
    let id = world.deposits[0].id;
    let all = world.deposits[0].amount;
    let mut events = Vec::new();

    step(
        &mut world,
        &[Input::player(me, extract(id, all + 500))],
        &mut events,
    );
    assert!(world.deposit(id).unwrap().is_depleted());
    assert!(events.contains(&Event::DepositDepleted { deposit: id }));

    events.clear();
    step(
        &mut world,
        &[Input::player(me, extract(id, 1))],
        &mut events,
    );
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: extract(id, 1),
            reason: RejectReason::DepositDepleted
        }]
    );
}

#[test]
fn unknown_deposit_is_rejected() {
    let (mut world, me) = world_with_player(9);
    let bad = extract(DepositId(u32::MAX), 1);
    let mut events = Vec::new();
    step(&mut world, &[Input::player(me, bad.clone())], &mut events);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: bad,
            reason: RejectReason::UnknownDeposit
        }]
    );
}

#[test]
fn commands_from_unknown_players_are_rejected() {
    let (mut world, _) = world_with_player(9);
    let before = world.clone();
    let mut events = Vec::new();
    step(
        &mut world,
        &[Input::player(PlayerId(5), extract(DepositId(0), 10))],
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
            let cmd = extract(DepositId((t % 5) as u32), 37);
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
