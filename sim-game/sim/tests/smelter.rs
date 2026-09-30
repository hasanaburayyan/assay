use sim::tuning::{COAL_BURN_TICKS, REACH, SMELTER_INPUT_CAP, SMELTER_OUTPUT_CAP};
use sim::{
    BuildingId, BuildingKind, Event, Input, Item, PlayerCommand, PlayerId, RecipeId, RejectReason,
    SystemCommand, TilePos, World, WorldConfig, step,
};

fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

fn run(world: &mut World, inputs: &[Input], ticks: u32) -> Vec<Event> {
    let mut events = Vec::new();
    step(world, inputs, &mut events);
    for _ in 1..ticks {
        step(world, &[], &mut events);
    }
    events
}

fn give(world: &mut World, me: PlayerId, item: Item, n: u32) {
    world.player_mut(me).unwrap().inventory.add(item, n);
}

fn count(world: &World, me: PlayerId, item: Item) -> u32 {
    world.player(me).unwrap().inventory.count(item)
}

/// Player at spawn with a smelter placed just east of them (id 0).
fn world_with_smelter() -> (World, PlayerId, BuildingId, TilePos) {
    let (mut world, me) = world_with_player();
    give(&mut world, me, Item::Smelter, 1);
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 1, spawn.y);
    let events = run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place {
                item: Item::Smelter,
                pos,
            },
        )],
        1,
    );
    let id = BuildingId(0);
    assert_eq!(
        events,
        vec![Event::BuildingPlaced {
            player: me,
            building: id,
            item: Item::Smelter,
            pos
        }]
    );
    (world, me, id, pos)
}

fn insert(b: BuildingId, item: Item, count: u32) -> PlayerCommand {
    PlayerCommand::Insert {
        building: b,
        item,
        count,
    }
}

#[test]
fn placing_a_smelter_uses_the_item_and_covers_two_by_two() {
    let (world, me, id, pos) = world_with_smelter();
    assert_eq!(count(&world, me, Item::Smelter), 0);
    let b = world.building(id).unwrap();
    assert_eq!(b.kind.footprint(), (2, 2));
    for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        let t = TilePos::new(pos.x + dx, pos.y + dy);
        assert_eq!(world.building_at(t).map(|b| b.id), Some(id));
    }
    assert!(world.building_at(TilePos::new(pos.x + 2, pos.y)).is_none());
    assert!(world.building_at(TilePos::new(pos.x, pos.y - 1)).is_none());
}

#[test]
fn placement_is_validated() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let near = TilePos::new(spawn.x + 1, spawn.y);
    let place = |item, pos| PlayerCommand::Place { item, pos };

    // No smelter in hand.
    let events = run(
        &mut world,
        &[Input::player(me, place(Item::Smelter, near))],
        1,
    );
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::MissingItems(Item::Smelter),
            ..
        }]
    ));

    give(&mut world, me, Item::Smelter, 3);
    give(&mut world, me, Item::Stone, 1);
    let cases = [
        (place(Item::Stone, near), RejectReason::NotPlaceable),
        (
            place(Item::Smelter, TilePos::new(spawn.x + REACH + 1, spawn.y)),
            RejectReason::OutOfReach,
        ),
        (
            place(Item::Smelter, TilePos::new(-1, 0)),
            RejectReason::OutOfBounds,
        ),
        (
            place(Item::Smelter, TilePos::new(world.width() - 1, 0)),
            RejectReason::OutOfBounds,
        ),
    ];
    for (command, reason) in cases {
        let events = run(&mut world, &[Input::player(me, command.clone())], 1);
        assert_eq!(
            events,
            vec![Event::CommandRejected {
                player: me,
                command,
                reason
            }],
        );
    }

    // Reach is measured to the nearest footprint tile, so the far edge of a
    // 2×2 can be REACH + 1 away.
    let edge = TilePos::new(spawn.x + REACH, spawn.y);
    let events = run(
        &mut world,
        &[Input::player(me, place(Item::Smelter, edge))],
        1,
    );
    assert!(matches!(events[..], [Event::BuildingPlaced { .. }]));

    // Overlapping an existing building, even by one tile, is refused.
    let overlap = TilePos::new(edge.x - 1, edge.y - 1);
    let events = run(
        &mut world,
        &[Input::player(me, place(Item::Smelter, overlap))],
        1,
    );
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::TileOccupied,
            ..
        }]
    ));
}

#[test]
fn smelter_turns_ore_into_plates_using_coal() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, Item::IronOre, 3);
    give(&mut world, me, Item::Coal, 1);
    let ticks = RecipeId::IronPlate.recipe().ticks;

    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Item::IronOre, 3)),
            Input::player(me, insert(id, Item::Coal, 1)),
        ],
        1,
    );
    assert_eq!(
        events,
        vec![
            Event::ItemsInserted {
                player: me,
                building: id,
                item: Item::IronOre,
                count: 3
            },
            Event::ItemsInserted {
                player: me,
                building: id,
                item: Item::Coal,
                count: 1
            },
        ]
    );
    assert_eq!(count(&world, me, Item::IronOre), 0);
    assert_eq!(count(&world, me, Item::Coal), 0);

    // The insert tick already ran one tick of smelting.
    let events = run(&mut world, &[], ticks - 1);
    assert_eq!(
        events,
        vec![Event::ItemSmelted {
            building: id,
            item: Item::IronPlate,
            count: 1
        }]
    );
    let BuildingKind::Smelter(s) = &world.building(id).unwrap().kind;
    assert_eq!(s.input.map(|i| i.count), Some(2));
    assert_eq!(
        s.output.map(|o| (o.item, o.count)),
        Some((Item::IronPlate, 1))
    );
    assert_eq!(s.fuel, 0);
    assert_eq!(s.burn_left, COAL_BURN_TICKS - ticks);

    // Finish the rest, then take the plates out.
    run(&mut world, &[], ticks * 2);
    let events = run(
        &mut world,
        &[Input::player(me, PlayerCommand::Take { building: id })],
        1,
    );
    assert_eq!(
        events,
        vec![Event::ItemsTaken {
            player: me,
            building: id,
            item: Item::IronPlate,
            count: 3
        }]
    );
    assert_eq!(count(&world, me, Item::IronPlate), 3);
    let BuildingKind::Smelter(s) = &world.building(id).unwrap().kind;
    assert!(s.input.is_none() && s.output.is_none());
}

#[test]
fn smelter_stalls_without_fuel_and_resumes_when_fed() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, Item::CopperOre, 1);
    give(&mut world, me, Item::Coal, 1);
    let ticks = RecipeId::CopperPlate.recipe().ticks;

    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Item::CopperOre, 1))],
        ticks * 2,
    );
    assert!(
        events
            .iter()
            .all(|e| !matches!(e, Event::ItemSmelted { .. }))
    );
    let BuildingKind::Smelter(s) = &world.building(id).unwrap().kind;
    assert_eq!(s.progress, 0);

    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Item::Coal, 1))],
        ticks,
    );
    assert!(events.contains(&Event::ItemSmelted {
        building: id,
        item: Item::CopperPlate,
        count: 1
    }));
}

#[test]
fn coal_only_burns_while_smelting() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, Item::Coal, 1);
    run(
        &mut world,
        &[Input::player(me, insert(id, Item::Coal, 1))],
        50,
    );
    let BuildingKind::Smelter(s) = &world.building(id).unwrap().kind;
    assert_eq!((s.fuel, s.burn_left), (1, 0), "no ore, so nothing burned");
}

#[test]
fn smelter_stops_when_its_output_is_full() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, Item::IronOre, SMELTER_INPUT_CAP);
    give(&mut world, me, Item::Coal, 50);
    let ticks = RecipeId::IronPlate.recipe().ticks;
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Item::IronOre, SMELTER_INPUT_CAP)),
            Input::player(me, insert(id, Item::Coal, 50)),
        ],
        ticks * (SMELTER_OUTPUT_CAP + 5),
    );
    let BuildingKind::Smelter(s) = &world.building(id).unwrap().kind;
    assert_eq!(s.output.map(|o| o.count), Some(SMELTER_OUTPUT_CAP));

    // More ore goes in, but nothing more comes out until someone empties it.
    give(&mut world, me, Item::IronOre, 10);
    run(
        &mut world,
        &[Input::player(me, insert(id, Item::IronOre, 10))],
        ticks * 5,
    );
    let BuildingKind::Smelter(s) = &world.building(id).unwrap().kind;
    assert_eq!(s.output.map(|o| o.count), Some(SMELTER_OUTPUT_CAP));
    assert_eq!(s.input.map(|i| i.count), Some(10));
    assert_eq!(s.progress, 0);

    let events = run(
        &mut world,
        &[Input::player(me, PlayerCommand::Take { building: id })],
        ticks,
    );
    assert_eq!(count(&world, me, Item::IronPlate), SMELTER_OUTPUT_CAP);
    assert!(events.contains(&Event::ItemSmelted {
        building: id,
        item: Item::IronPlate,
        count: 1
    }));
}

#[test]
fn inserting_is_validated() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, Item::Stone, 5);
    give(&mut world, me, Item::IronOre, 60);
    give(&mut world, me, Item::CopperOre, 1);
    run(
        &mut world,
        &[Input::player(me, insert(id, Item::IronOre, 10))],
        1,
    );

    let cases = [
        (insert(id, Item::Stone, 1), RejectReason::WrongItem),
        (
            insert(id, Item::Coal, 1),
            RejectReason::MissingItems(Item::Coal),
        ),
        (insert(id, Item::IronOre, 0), RejectReason::ZeroCount),
        (insert(id, Item::IronOre, 41), RejectReason::SlotFull),
        (insert(id, Item::CopperOre, 1), RejectReason::SlotFull),
        (
            insert(BuildingId(99), Item::IronOre, 1),
            RejectReason::UnknownBuilding,
        ),
        (
            PlayerCommand::Take { building: id },
            RejectReason::NothingToTake,
        ),
    ];
    for (command, reason) in cases {
        let events = run(&mut world, &[Input::player(me, command.clone())], 1);
        assert_eq!(
            events,
            vec![Event::CommandRejected {
                player: me,
                command,
                reason
            }],
        );
    }

    // Walk away and it is out of reach.
    let spawn = world.spawn_tile();
    let far = TilePos::new(spawn.x - REACH - 1, spawn.y);
    run(
        &mut world,
        &[Input::player(me, PlayerCommand::MoveTo { target: far })],
        (REACH + 1) as u32,
    );
    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Item::IronOre, 1))],
        1,
    );
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::OutOfReach,
            ..
        }]
    ));
}

#[test]
fn pickup_returns_the_building_and_everything_in_it() {
    let (mut world, me, id, pos) = world_with_smelter();
    give(&mut world, me, Item::IronOre, 2);
    give(&mut world, me, Item::Coal, 3);
    let ticks = RecipeId::IronPlate.recipe().ticks;
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Item::IronOre, 2)),
            Input::player(me, insert(id, Item::Coal, 3)),
        ],
        ticks,
    );
    let events = run(
        &mut world,
        &[Input::player(me, PlayerCommand::Pickup { building: id })],
        1,
    );
    assert_eq!(
        events,
        vec![Event::BuildingRemoved {
            player: me,
            building: id,
            item: Item::Smelter,
            pos
        }]
    );
    assert!(world.buildings.is_empty());
    assert_eq!(count(&world, me, Item::Smelter), 1);
    assert_eq!(count(&world, me, Item::IronOre), 1);
    assert_eq!(count(&world, me, Item::IronPlate), 1);
    assert_eq!(
        count(&world, me, Item::Coal),
        2,
        "the coal in the fire is spent"
    );

    // IDs are never reused.
    give(&mut world, me, Item::Smelter, 0);
    let events = run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place {
                item: Item::Smelter,
                pos,
            },
        )],
        1,
    );
    assert!(matches!(
        events[..],
        [Event::BuildingPlaced {
            building: BuildingId(1),
            ..
        }]
    ));
}

#[test]
fn a_working_smelter_survives_save_and_load() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, Item::IronOre, 5);
    give(&mut world, me, Item::Coal, 1);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Item::IronOre, 5)),
            Input::player(me, insert(id, Item::Coal, 1)),
        ],
        7,
    );
    let mut loaded = World::from_json(&world.to_json().unwrap()).unwrap();
    assert_eq!(loaded, world);
    run(&mut loaded, &[], 100);
    run(&mut world, &[], 100);
    assert_eq!(loaded.state_hash(), world.state_hash());
    let BuildingKind::Smelter(s) = &loaded.building(id).unwrap().kind;
    assert!(s.output.is_some());
}
