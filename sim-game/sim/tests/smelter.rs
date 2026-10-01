use sim::tuning::{
    BURN_TICKS_PER_REACTIVITY, FUEL_MIN_REACTIVITY, HAND_SPARK_TEMPERATURE, REACH,
    SMELTER_INPUT_CAP, SMELTER_OUTPUT_CAP,
};
use sim::{
    BuildingId, BuildingKind, Event, Grade, Input, Item, ItemKind, PlayerCommand, PlayerId,
    RecipeId, RejectReason, Sheet, Slot, SpeciesId, SystemCommand, TilePos, World, WorldConfig,
    step,
};

/// Species used by these tests, with sheets set explicitly so the rules are
/// exercised on purpose rather than by luck of the roll.
const WALLS: SpeciesId = SpeciesId(0); // smelter material and the ore it can take
const FUEL: SpeciesId = SpeciesId(1); // burns, lights by hand
const HOT: SpeciesId = SpeciesId(2); // too hot for WALLS
const HOT_FUEL: SpeciesId = SpeciesId(3); // burns hotter, but won't light from cold
const INERT: SpeciesId = SpeciesId(4); // not fuel

fn sheet(hardness: u8, heat: u8, reactivity: u8) -> Sheet {
    Sheet {
        density: 50,
        strength: 50,
        hardness,
        heat_tolerance: heat,
        reactivity,
        conductivity: 50,
    }
}

fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    world.species_mut(WALLS).sheet = sheet(30, 60, 1);
    world.species_mut(FUEL).sheet = sheet(30, HAND_SPARK_TEMPERATURE as u8, 60);
    world.species_mut(HOT).sheet = sheet(30, 61, 1);
    world.species_mut(HOT_FUEL).sheet = sheet(30, 90, 100);
    world.species_mut(INERT).sheet = sheet(30, 20, FUEL_MIN_REACTIVITY as u8 - 1);
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

fn ore(species: SpeciesId) -> Item {
    Item::new(ItemKind::Ore, species, Grade::A)
}

fn give(world: &mut World, me: PlayerId, item: Item, n: u32) {
    world.player_mut(me).unwrap().inventory.add(item, n);
}

fn count(world: &World, me: PlayerId, item: Item) -> u32 {
    world.player(me).unwrap().inventory.count(item)
}

fn smelter_of(world: &World, id: BuildingId) -> &sim::Smelter {
    let BuildingKind::Smelter(s) = &world.building(id).unwrap().kind else {
        panic!("building {} is not a smelter", id.0)
    };
    s
}

/// Player at spawn with a WALLS smelter placed just east of them (id 0).
fn world_with_smelter() -> (World, PlayerId, BuildingId, TilePos) {
    let (mut world, me) = world_with_player();
    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
    give(&mut world, me, smelter, 1);
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 1, spawn.y);
    let events = run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place { item: smelter, pos },
        )],
        1,
    );
    let id = BuildingId(0);
    assert_eq!(
        events,
        vec![Event::BuildingPlaced {
            player: me,
            building: id,
            item: smelter,
            pos
        }]
    );
    (world, me, id, pos)
}

fn insert(b: BuildingId, slot: Slot, item: Item, count: u32) -> PlayerCommand {
    PlayerCommand::Insert {
        building: b,
        slot,
        item,
        count,
    }
}

#[test]
fn placing_a_smelter_uses_the_item_and_covers_two_by_two() {
    let (world, me, id, pos) = world_with_smelter();
    assert_eq!(
        count(&world, me, Item::new(ItemKind::Smelter, WALLS, Grade::C)),
        0
    );
    let b = world.building(id).unwrap();
    assert_eq!(b.kind.footprint(), (2, 2));
    assert_eq!(
        world.max_temperature(b),
        60,
        "walls are the material's heat tolerance"
    );
    for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        let t = TilePos::new(pos.x + dx, pos.y + dy);
        assert_eq!(world.building_at(t).map(|b| b.id), Some(id));
    }
    assert!(world.building_at(TilePos::new(pos.x + 2, pos.y)).is_none());
}

#[test]
fn placement_is_validated() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let near = TilePos::new(spawn.x + 1, spawn.y);
    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
    let place = |item, pos| PlayerCommand::Place { item, pos };

    let events = run(&mut world, &[Input::player(me, place(smelter, near))], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::MissingItems(_),
            ..
        }]
    ));

    give(&mut world, me, smelter, 3);
    give(&mut world, me, ore(WALLS), 1);
    let cases = [
        (place(ore(WALLS), near), RejectReason::NotPlaceable),
        (
            place(smelter, TilePos::new(spawn.x + REACH + 1, spawn.y)),
            RejectReason::OutOfReach,
        ),
        (
            place(smelter, TilePos::new(-1, 0)),
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

    let edge = TilePos::new(spawn.x + REACH, spawn.y);
    let events = run(&mut world, &[Input::player(me, place(smelter, edge))], 1);
    assert!(matches!(events[..], [Event::BuildingPlaced { .. }]));
    let overlap = TilePos::new(edge.x - 1, edge.y - 1);
    let events = run(&mut world, &[Input::player(me, place(smelter, overlap))], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::TileOccupied,
            ..
        }]
    ));
}

#[test]
fn smelter_refines_ore_using_hand_lit_fuel() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 3);
    give(&mut world, me, ore(FUEL), 1);
    let ticks = RecipeId::Refine.recipe().ticks;

    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 3)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1)),
        ],
        1,
    );
    assert_eq!(
        events,
        vec![
            Event::ItemsInserted {
                player: me,
                building: id,
                slot: Slot::Input,
                item: ore(WALLS),
                count: 3
            },
            Event::ItemsInserted {
                player: me,
                building: id,
                slot: Slot::Fuel,
                item: ore(FUEL),
                count: 1
            },
        ]
    );
    assert_eq!(count(&world, me, ore(WALLS)), 0);
    assert_eq!(count(&world, me, ore(FUEL)), 0);

    let refined = Item::new(ItemKind::Refined, WALLS, Grade::A);
    let events = run(&mut world, &[], ticks - 1);
    assert_eq!(
        events,
        vec![Event::ItemSmelted {
            building: id,
            item: refined,
            count: 1
        }]
    );
    let s = smelter_of(&world, id);
    assert_eq!(s.input.map(|i| i.count), Some(2));
    assert_eq!(s.output.map(|o| (o.item, o.count)), Some((refined, 1)));
    assert!(s.fuel.is_none());
    assert_eq!(s.burn_temperature, 60);
    assert_eq!(s.burn_left, 60 * BURN_TICKS_PER_REACTIVITY - ticks);

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
            item: refined,
            count: 3
        }]
    );
    assert_eq!(count(&world, me, refined), 3);
}

#[test]
fn refined_output_keeps_the_ores_grade() {
    let (mut world, me, id, _) = world_with_smelter();
    let c_ore = Item::new(ItemKind::Ore, WALLS, Grade::C);
    give(&mut world, me, c_ore, 1);
    give(&mut world, me, ore(FUEL), 1);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, c_ore, 1)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1)),
        ],
        RecipeId::Refine.recipe().ticks,
    );
    let s = smelter_of(&world, id);
    assert_eq!(
        s.output.map(|o| o.item),
        Some(Item::new(ItemKind::Refined, WALLS, Grade::C))
    );
}

#[test]
fn walls_cap_which_ore_a_smelter_accepts() {
    // Decision 9.
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(HOT), 1);
    let bad = insert(id, Slot::Input, ore(HOT), 1);
    let events = run(&mut world, &[Input::player(me, bad.clone())], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: bad,
            reason: RejectReason::TooHotForWalls
        }]
    );

    // A smelter built from the hot species takes it.
    let hot_smelter = Item::new(ItemKind::Smelter, HOT, Grade::C);
    give(&mut world, me, hot_smelter, 1);
    let spawn = world.spawn_tile();
    run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place {
                item: hot_smelter,
                pos: TilePos::new(spawn.x - 2, spawn.y),
            },
        )],
        1,
    );
    let events = run(
        &mut world,
        &[Input::player(
            me,
            insert(BuildingId(1), Slot::Input, ore(HOT), 1),
        )],
        1,
    );
    assert!(matches!(events[..], [Event::ItemsInserted { .. }]));
}

#[test]
fn fuel_must_be_reactive_and_the_fire_hot_enough_for_the_ore() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(INERT), 1);
    let bad = insert(id, Slot::Fuel, ore(INERT), 1);
    let events = run(&mut world, &[Input::player(me, bad.clone())], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: bad,
            reason: RejectReason::NotFuel
        }]
    );

    // C-grade fuel burns at 60% reactivity: 36, too cool for ore needing 60.
    let weak = Item::new(ItemKind::Ore, FUEL, Grade::C);
    give(&mut world, me, weak, 1);
    give(&mut world, me, ore(WALLS), 1);
    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 1)),
            Input::player(me, insert(id, Slot::Fuel, weak, 1)),
        ],
        RecipeId::Refine.recipe().ticks * 2,
    );
    assert!(
        events
            .iter()
            .all(|e| !matches!(e, Event::ItemSmelted { .. }))
    );
    let s = smelter_of(&world, id);
    assert_eq!(s.burn_temperature, 36, "the fire is lit");
    assert_eq!(s.progress, 0, "but nothing smelts");
}

#[test]
fn hot_fuel_needs_an_already_burning_fire() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 5);
    give(&mut world, me, ore(HOT_FUEL), 1);
    let ticks = RecipeId::Refine.recipe().ticks;

    // From cold: heat tolerance 90 is above the hand spark, so it never lights.
    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 5)),
            Input::player(me, insert(id, Slot::Fuel, ore(HOT_FUEL), 1)),
        ],
        ticks * 2,
    );
    assert!(
        events
            .iter()
            .all(|e| !matches!(e, Event::ItemSmelted { .. }))
    );
    assert_eq!(smelter_of(&world, id).burn_temperature, 0);

    // Swap in hand-lit fuel: pick up the smelter and refill it so the fire
    // runs on FUEL (burns at 60, which is below 90, so HOT_FUEL still won't
    // light from it). That is the rule: a hotter fire is needed.
    run(
        &mut world,
        &[Input::player(me, PlayerCommand::Pickup { building: id })],
        1,
    );
    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
    let spawn = world.spawn_tile();
    give(&mut world, me, ore(FUEL), 1);
    let id = BuildingId(1);
    run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place {
                item: smelter,
                pos: TilePos::new(spawn.x + 1, spawn.y),
            },
        )],
        1,
    );
    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 5)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1)),
        ],
        ticks,
    );
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::ItemSmelted { .. }))
    );
}

#[test]
fn coal_only_burns_while_smelting() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(FUEL), 1);
    run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1))],
        50,
    );
    let s = smelter_of(&world, id);
    assert_eq!(s.fuel.map(|f| f.count), Some(1));
    assert_eq!(s.burn_left, 0, "no ore, so nothing burned");
}

#[test]
fn smelter_stops_when_its_output_is_full() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), SMELTER_INPUT_CAP + 10);
    give(&mut world, me, ore(FUEL), 50);
    let ticks = RecipeId::Refine.recipe().ticks;
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), SMELTER_INPUT_CAP)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 50)),
        ],
        ticks * (SMELTER_OUTPUT_CAP + 5),
    );
    assert_eq!(
        smelter_of(&world, id).output.map(|o| o.count),
        Some(SMELTER_OUTPUT_CAP)
    );

    run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, ore(WALLS), 10))],
        ticks * 5,
    );
    let s = smelter_of(&world, id);
    assert_eq!(s.output.map(|o| o.count), Some(SMELTER_OUTPUT_CAP));
    assert_eq!(s.input.map(|i| i.count), Some(10));
    assert_eq!(s.progress, 0);

    let refined = Item::new(ItemKind::Refined, WALLS, Grade::A);
    let events = run(
        &mut world,
        &[Input::player(me, PlayerCommand::Take { building: id })],
        ticks,
    );
    assert_eq!(count(&world, me, refined), SMELTER_OUTPUT_CAP);
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::ItemSmelted { .. }))
    );
}

#[test]
fn inserting_is_validated() {
    let (mut world, me, id, _) = world_with_smelter();
    let refined = Item::new(ItemKind::Refined, WALLS, Grade::A);
    give(&mut world, me, refined, 5);
    give(&mut world, me, ore(WALLS), 60);
    give(&mut world, me, ore(FUEL), 60);
    give(&mut world, me, ore(INERT), 1);
    run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, ore(WALLS), 10))],
        1,
    );

    let gear = Item::new(ItemKind::Gear, WALLS, Grade::A);
    give(&mut world, me, gear, 1);
    let cases = [
        (insert(id, Slot::Input, gear, 1), RejectReason::WrongItem),
        (insert(id, Slot::Fuel, gear, 1), RejectReason::WrongItem),
        (
            insert(id, Slot::Input, refined, 1),
            RejectReason::AlreadyBestGrade,
        ),
        (
            insert(id, Slot::Fuel, ore(HOT_FUEL), 1),
            RejectReason::MissingItems(ore(HOT_FUEL)),
        ),
        (
            insert(id, Slot::Input, ore(WALLS), 0),
            RejectReason::ZeroCount,
        ),
        (
            insert(id, Slot::Input, ore(WALLS), 41),
            RejectReason::SlotFull,
        ),
        (
            insert(id, Slot::Input, ore(INERT), 1),
            RejectReason::SlotFull,
        ),
        (
            insert(id, Slot::Fuel, ore(FUEL), 51),
            RejectReason::SlotFull,
        ),
        (
            insert(BuildingId(99), Slot::Input, ore(WALLS), 1),
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

    let spawn = world.spawn_tile();
    let far = TilePos::new(spawn.x - REACH - 1, spawn.y);
    run(
        &mut world,
        &[Input::player(me, PlayerCommand::MoveTo { target: far })],
        (REACH + 1) as u32,
    );
    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, ore(WALLS), 1))],
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
    give(&mut world, me, ore(WALLS), 2);
    give(&mut world, me, ore(FUEL), 3);
    let ticks = RecipeId::Refine.recipe().ticks;
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 2)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 3)),
        ],
        ticks,
    );
    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
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
            item: smelter,
            pos
        }]
    );
    assert!(world.buildings.is_empty());
    assert_eq!(count(&world, me, smelter), 1);
    assert_eq!(count(&world, me, ore(WALLS)), 1);
    assert_eq!(
        count(&world, me, Item::new(ItemKind::Refined, WALLS, Grade::A)),
        1
    );
    assert_eq!(
        count(&world, me, ore(FUEL)),
        2,
        "the fuel in the fire is spent"
    );

    let events = run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place { item: smelter, pos },
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
    give(&mut world, me, ore(WALLS), 5);
    give(&mut world, me, ore(FUEL), 1);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 5)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1)),
        ],
        7,
    );
    let mut loaded = World::from_json(&world.to_json().unwrap()).unwrap();
    assert_eq!(loaded, world);
    run(&mut loaded, &[], 100);
    run(&mut world, &[], 100);
    assert_eq!(loaded.state_hash(), world.state_hash());
    assert!(smelter_of(&loaded, id).output.is_some());
}

#[test]
fn resmelting_refined_material_raises_its_grade_at_a_loss() {
    // Decision 6, rung two: heat and fuel.
    let (mut world, me, id, _) = world_with_smelter();
    let c = Item::new(ItemKind::Refined, WALLS, Grade::C);
    give(&mut world, me, c, 7);
    give(&mut world, me, ore(FUEL), 3);
    let ticks = RecipeId::Resmelt.recipe().ticks;
    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, c, 7)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 3)),
        ],
        ticks * 2 + 5,
    );
    let b = Item::new(ItemKind::Refined, WALLS, Grade::B);
    assert_eq!(
        events
            .iter()
            .filter(|e| matches!(e, Event::ItemSmelted { item, .. } if *item == b))
            .count(),
        2
    );
    let s = smelter_of(&world, id);
    assert_eq!(
        s.input.map(|i| i.count),
        Some(1),
        "6 in, 2 out, 1 short of a batch"
    );
    assert_eq!(s.output.map(|o| (o.item, o.count)), Some((b, 2)));

    // Grade A refined has nowhere to go.
    let a = Item::new(ItemKind::Refined, WALLS, Grade::A);
    give(&mut world, me, a, 3);
    let bad = insert(id, Slot::Input, a, 3);
    let events = run(&mut world, &[Input::player(me, bad.clone())], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: bad,
            reason: RejectReason::AlreadyBestGrade
        }]
    );
}

#[test]
fn c_grade_ore_becomes_b_grade_material_through_the_chain() {
    // Decision 6 end to end: sort by hand, then refine. 3 C ore -> 1 B refined.
    let (mut world, me, id, _) = world_with_smelter();
    let c_ore = Item::new(ItemKind::Ore, WALLS, Grade::C);
    give(&mut world, me, c_ore, 3);
    give(&mut world, me, ore(FUEL), 1);
    run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Craft {
                recipe: RecipeId::Sort,
                item: c_ore,
                count: 1,
            },
        )],
        RecipeId::Sort.recipe().ticks,
    );
    let b_ore = Item::new(ItemKind::Ore, WALLS, Grade::B);
    assert_eq!(count(&world, me, b_ore), 1);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, b_ore, 1)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1)),
        ],
        RecipeId::Refine.recipe().ticks,
    );
    run(
        &mut world,
        &[Input::player(me, PlayerCommand::Take { building: id })],
        1,
    );
    assert_eq!(
        count(&world, me, Item::new(ItemKind::Refined, WALLS, Grade::B)),
        1
    );
    assert_eq!(
        world.player(me).unwrap().inventory.total(),
        1,
        "3 units in, 1 out"
    );
}
