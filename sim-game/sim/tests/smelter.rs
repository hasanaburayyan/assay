use sim::tuning::{
    BURN_TICKS_PER_REACTIVITY, FUEL_MIN_REACTIVITY, HAND_SPARK_TEMPERATURE, REACH,
    SMELTER_INPUT_CAP, SMELTER_OUTPUT_CAP,
};
use sim::{
    BuildingId, BuildingKind, Event, Grade, Input, Item, ItemKind, PlayerCommand, PlayerId,
    RecipeId, RejectReason, Sheet, Slot, SmelterStall, SpeciesId, SystemCommand, TilePos, World,
    WorldConfig, step,
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
                count: 3,
                left: 0,
            },
            Event::ItemsInserted {
                player: me,
                building: id,
                slot: Slot::Fuel,
                item: ore(FUEL),
                count: 1,
                left: 0,
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
    // The ore went in; this smelter has no fuel, so ASSA-80's stall follows in
    // the same tick. What this test is about is that nothing was REFUSED, so
    // it asks that rather than pinning the exact list.
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::ItemsInserted { .. })),
        "{events:?}"
    );
    assert!(
        !events
            .iter()
            .any(|e| matches!(e, Event::CommandRejected { .. })),
        "nothing was refused: {events:?}"
    );
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
        // OFFERING MORE THAN FITS IS NO LONGER A REJECTION (ASSA-48): it was
        // `(..., ore(WALLS), 41) => SlotFull` and `(..., ore(FUEL), 51) =>
        // SlotFull` here, and the Game Director ruled that Insert takes what
        // fits. Both cases moved to
        // `inserting_takes_what_fits_and_says_what_stayed_behind`, which
        // asserts the clamp AND that a slot with no room at all still refuses.
        // The one SlotFull a clamp cannot absorb stays right here:
        (
            insert(id, Slot::Input, ore(INERT), 1),
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

/// **INSERT TAKES WHAT FITS AND SAYS WHAT STAYED BEHIND** (ASSA-48, Game
/// Director's ruling off ASSA-37).
///
/// The measured failure: a player mined 222 ore on the pinned friend seed,
/// pressed the client's one Smelt button, and was told *"that slot is full or
/// holds a different item"* about an **empty** slot. One press is the whole
/// interface, and a client that offered a smaller number would be deciding how
/// much fuel a fire wants — a sheet reading it does not have. So the sim owns
/// the clamp, because the sim owns the cap.
///
/// Three things, and the third is why this is not just a clamp: a partial
/// success that does not say what it refused leaves the player holding 167 of
/// something for no stated reason, which is the same silence the item was
/// filed about.
#[test]
fn inserting_takes_what_fits_and_says_what_stayed_behind() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), SMELTER_INPUT_CAP + 7);

    // 1. MORE THAN FITS: the slot fills to the cap, the rest stays in hand,
    //    and the event names both halves.
    let events = run(
        &mut world,
        &[Input::player(
            me,
            insert(id, Slot::Input, ore(WALLS), SMELTER_INPUT_CAP + 7),
        )],
        1,
    );
    // THE SECOND EVENT IS ASSA-80 AND IT IS KEPT EXACT ON PURPOSE. Ore went
    // into a smelter with no fuel, so it entered a stall on this very tick and
    // now says so. Asserting the pair rather than filtering the new one keeps
    // this test pinning something it did not before: the stall arrives in the
    // same tick as the insert that caused it, which is the whole point of
    // taking the "before" state at the top of `step`.
    assert_eq!(
        events,
        vec![
            Event::ItemsInserted {
                player: me,
                building: id,
                slot: Slot::Input,
                item: ore(WALLS),
                count: SMELTER_INPUT_CAP,
                left: 7,
            },
            Event::SmelterStalled {
                building: id,
                why: sim::SmelterStall::NoFuel,
            }
        ],
        "the offer is clamped to the room, and the leftover is reported"
    );
    assert_eq!(
        smelter_of(&world, id).input.unwrap().count,
        SMELTER_INPUT_CAP
    );
    assert_eq!(
        count(&world, me, ore(WALLS)),
        7,
        "what would not fit is still the player's, not destroyed"
    );

    // 2. NO ROOM AT ALL still refuses. "Nothing happened" is true here, and
    //    the player's move is to empty the slot rather than offer less — so a
    //    clamp to zero would be a silent no-op, which is worse.
    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, ore(WALLS), 7))],
        1,
    );
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: insert(id, Slot::Input, ore(WALLS), 7),
            reason: RejectReason::SlotFull,
        }]
    );
    assert_eq!(count(&world, me, ore(WALLS)), 7, "a refusal takes nothing");

    // 3. THE CONTROL. An offer that fits exactly reports no leftover, so the
    //    extra clause can never appear on a clean insert. Without this a
    //    `left` that was always non-zero would pass the test above.
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(FUEL), 4);
    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 4))],
        1,
    );
    assert_eq!(
        events,
        vec![Event::ItemsInserted {
            player: me,
            building: id,
            slot: Slot::Fuel,
            item: ore(FUEL),
            count: 4,
            left: 0,
        }]
    );
    assert_eq!(count(&world, me, ore(FUEL)), 0);
}

/// The sentence a player actually reads, for both halves of the clamp. The
/// event carrying `left` is useless if nothing says it out loud, and
/// `event_line` is what both hosts render.
#[test]
fn the_insert_line_names_the_leftover_only_when_there_is_one() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), SMELTER_INPUT_CAP + 7);
    let events = run(
        &mut world,
        &[Input::player(
            me,
            insert(id, Slot::Input, ore(WALLS), SMELTER_INPUT_CAP + 7),
        )],
        1,
    );
    let line = sim::debug::event_line(&world, Some(me), &events[0], sim::debug::Audience::Typed);
    assert!(
        line.contains(&format!("put {SMELTER_INPUT_CAP} ")),
        "{line}"
    );
    assert!(line.contains("7 would not fit"), "{line}");

    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(FUEL), 4);
    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 4))],
        1,
    );
    let line = sim::debug::event_line(&world, Some(me), &events[0], sim::debug::Audience::Typed);
    assert!(line.contains("put 4 "), "{line}");
    assert!(
        !line.contains("would not fit"),
        "a clean insert must not mention a leftover: {line}"
    );
}

// ---------------------------------------------------------------------------
// ASSA-80: the machine that is half the demo's clock says when it stops.
// ---------------------------------------------------------------------------

/// Every `SmelterStalled` in `events`, as its reason.
fn stalls(events: &[Event]) -> Vec<SmelterStall> {
    events
        .iter()
        .filter_map(|e| match e {
            Event::SmelterStalled { why, .. } => Some(*why),
            _ => None,
        })
        .collect()
}

/// **THE GAME DIRECTOR'S REPRODUCTION, AS A TEST.** She inserted fuel and ore
/// on the pinned seed and watched 120 ticks with zero events while
/// `buildings` said `stalled: fuel won't light from cold` the whole time. The
/// player had done everything the buttons offer and the log was empty.
///
/// **THE EDGE IS ENTERING A STALL, NOT WORKING -> STALLED**, and that
/// difference is the test: here the smelter goes from `idle: nothing to
/// refine` straight into a stall without ever working, so a guard written to
/// the ruling's letter would have stayed green through exactly the silence she
/// measured. Her rule 2 is the load-bearing half and it holds below: once
/// stalled, it says nothing more.
#[test]
fn a_smelter_entering_a_stall_says_so_once_and_then_stops_talking() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 10);

    // Ore in, no fuel: idle -> stalled on this tick.
    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, ore(WALLS), 5))],
        1,
    );
    assert_eq!(
        stalls(&events),
        vec![SmelterStall::NoFuel],
        "entering a stall is announced once: {events:?}"
    );

    // **AND THEN SILENCE.** This is the arm a per-tick emitter fails: fifty
    // ticks of a smelter sitting in the same stall must add nothing to a log
    // the player is supposed to keep reading.
    let later = run(&mut world, &[], 50);
    assert_eq!(
        stalls(&later),
        vec![],
        "a smelter that sits stalled must not shout: {later:?}"
    );

    // The status line agrees with what the event said, because both read
    // `World::smelter_state`.
    let status = sim::debug::building_status(&world, world.building(id).unwrap());
    assert!(status.contains("stalled: no fuel"), "{status}");
}

/// **ALL FOUR STALLS, EACH BY ITS OWN SENTENCE, AND THE TWO SURFACES HELD
/// EQUAL.** A state-to-words mapping test: the slots are set directly rather
/// than driven, because what is under test is that one decision reaches both
/// the log and the status line saying the same thing — not the rules that get
/// a smelter into each state, which the tests above already pin.
#[test]
fn every_stall_reason_says_the_same_thing_in_the_log_and_on_the_status_line() {
    let cases: [(SmelterStall, &str); 4] = [
        (SmelterStall::OutputFull, "output full"),
        (SmelterStall::NoFuel, "no fuel"),
        (SmelterStall::FuelWontLight, "fuel won't light from cold"),
        (
            SmelterStall::FireTooCool {
                fire: 60,
                needs: 90,
            },
            "fire 60 too cool for ore needing 90",
        ),
    ];
    for (why, sentence) in cases {
        let (mut world, me, id, _) = world_with_smelter();
        // Walls hot enough that the fire, not the walls, is the limit in the
        // FireTooCool case; harmless for the others.
        world.species_mut(WALLS).sheet.heat_tolerance = 100;
        let ore_for = match why {
            SmelterStall::FireTooCool { .. } => ore(HOT_FUEL),
            _ => ore(WALLS),
        };
        {
            let b = world.building_mut(id).unwrap();
            let BuildingKind::Smelter(s) = &mut b.kind else {
                panic!("the fixture places a smelter")
            };
            s.input = Some(sim::ItemStack::new(ore_for, 5));
            match why {
                SmelterStall::OutputFull => {
                    s.output = Some(sim::ItemStack::new(
                        Item::new(ItemKind::Refined, WALLS, Grade::A),
                        SMELTER_OUTPUT_CAP,
                    ));
                    s.burn_left = 10;
                    s.burn_temperature = 60;
                }
                SmelterStall::NoFuel => {
                    s.fuel = None;
                    s.burn_left = 0;
                }
                SmelterStall::FuelWontLight => {
                    s.fuel = Some(sim::ItemStack::new(ore(HOT_FUEL), 1));
                    s.burn_left = 0;
                }
                SmelterStall::FireTooCool { .. } => {
                    s.burn_left = 10;
                    s.burn_temperature = 60;
                }
            }
        }
        let b = world.building(id).unwrap();
        assert_eq!(
            world.smelter_state(b).stall(),
            Some(why),
            "the state this test set up is not the one it is about"
        );

        let status = sim::debug::building_status(&world, b);
        assert!(
            status.contains(&format!("stalled: {sentence}")),
            "the status line's own words: {status}"
        );
        let line = sim::debug::event_line(
            &world,
            Some(me),
            &Event::SmelterStalled { building: id, why },
            sim::debug::Audience::Typed,
        );
        assert!(
            line.contains(sentence),
            "and the log must say the same thing, not a second wording: {line}"
        );
    }
}

/// **IDLE IS NOT A STALL AND IS NEVER ANNOUNCED** (Game Director's rule 2). A
/// finished batch empties the input slot, and announcing that would fire after
/// every batch -- noise that teaches a player to stop reading the log.
#[test]
fn a_smelter_that_runs_dry_is_silent_because_idle_is_not_a_stall() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 60);
    give(&mut world, me, ore(FUEL), 60);
    // One unit of ore and plenty of fuel: it smelts, finishes, and goes idle.
    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 10)),
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 1)),
        ],
        60,
    );
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::ItemSmelted { .. })),
        "premise: it has to actually smelt something: {events:?}"
    );
    let smelter = smelter_of(&world, id);
    assert!(smelter.input.is_none(), "premise: the input ran out");
    assert_eq!(
        stalls(&events),
        vec![],
        "running dry is idle, not a stall: {events:?}"
    );
    let status = sim::debug::building_status(&world, world.building(id).unwrap());
    assert!(status.contains("idle: nothing to refine"), "{status}");
}

/// **THE DEMO'S OWN LOG, AS A TEST** (ASSA-128). On seed 14247 the scripted
/// session printed `smelter 0 stopped: fuel won't light from cold` five times
/// while that smelter turned 19 ore into 19 refined. One false line per fuel
/// unit burned: the tick that spends the last of a unit ends with
/// `burn_left == 0`, and the relight is the next tick's first act, so
/// `announce_new_stalls` saw a dead fire in between.
///
/// **WHY NO TEST HERE CAUGHT IT: every other smelter test burns one unit.**
/// `BURN_TICKS_PER_REACTIVITY * 60` is 120 ticks of fire, and the longest run
/// above is 60 ticks. The bug lives in the seam between two units, so the
/// run has to be long enough to have a seam.
#[test]
fn a_batch_burning_three_fuel_units_never_claims_the_fuel_will_not_light() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 15);
    give(&mut world, me, ore(FUEL), 3);
    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 3)),
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 15)),
        ],
        400,
    );

    // **THE PREMISE FIRST, OR THE ASSERTION IS OVER AN EMPTY RUN.** A smelter
    // that never lit would also announce nothing once this is fixed, and it
    // has to have crossed a seam: 15 ore at 20 ticks each is 300 ticks of
    // fire, which no single unit of this fuel can pay for.
    let smelted = events
        .iter()
        .filter(|e| matches!(e, Event::ItemSmelted { .. }))
        .count();
    assert_eq!(
        smelted, 15,
        "premise: the whole batch has to run: {events:?}"
    );
    let smelter = smelter_of(&world, id);
    assert!(smelter.input.is_none(), "premise: all the ore went in");
    assert_eq!(
        smelter.output.map(|o| o.count),
        Some(15),
        "premise: all the refined came out"
    );
    assert!(
        smelter.fuel.is_none(),
        "premise: every unit of fuel was consumed, so every seam was crossed"
    );

    assert_eq!(
        stalls(&events),
        vec![],
        "a working smelter says nothing: {:?}",
        stalls(&events)
    );
}

/// **A STALL IS A CONDITION, NOT A MOMENT** (Game Director's ruling 2 on
/// ASSA-128): *a fire that relights unaided on the next tick is not a stop. A
/// stall is only a stall when nothing clears it but the player.*
///
/// That is a property of every stall and not a fact about fuel, so it is
/// asserted over every tick of a batch rather than at the two ticks we know
/// about. If any future state can un-stall itself with no input, this fails
/// without being rewritten.
///
/// It is also the lever: it is red on the state of the code before this
/// commit (tick 120 reports `FuelWontLight`, tick 121 is `Working`) and stays
/// red for any fix that only silences the *event* while `smelter_state` keeps
/// lying — which `halt_lines()` and the status line read directly.
#[test]
fn no_smelter_stall_clears_itself_without_the_player() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 15);
    give(&mut world, me, ore(FUEL), 3);
    let mut events = Vec::new();
    step(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 3)),
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 15)),
        ],
        &mut events,
    );

    let mut seen_working = false;
    for _ in 0..400 {
        let before = world.smelter_state(world.building(id).unwrap());
        let tick = world.tick;
        step(&mut world, &[], &mut events);
        let after = world.smelter_state(world.building(id).unwrap());
        seen_working |= matches!(after, sim::SmelterState::Working { .. });
        if let Some(why) = before.stall() {
            assert!(
                after.stall().is_some(),
                "tick {tick} reported stalled: {why:?}, and tick {} is {after:?} \
                 with nothing done about it, so it was never a stall",
                tick + 1
            );
        }
    }
    assert!(seen_working, "premise: the smelter has to have worked");
}

/// **AND THE TRUE CASE STILL ANNOUNCES**, which is half of what the Game
/// Director asked for: *a check we have only ever seen fire when it is false
/// is worse than no check.* Driven through the commands, not hand-set, so it
/// is the same path the false ones came down.
#[test]
fn fuel_that_cannot_light_from_cold_still_says_so_once() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 15);
    give(&mut world, me, ore(HOT_FUEL), 3);
    let events = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Fuel, ore(HOT_FUEL), 3)),
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 15)),
        ],
        400,
    );
    assert_eq!(
        stalls(&events),
        vec![SmelterStall::FuelWontLight],
        "it is said once and only once: {events:?}"
    );
    let smelter = smelter_of(&world, id);
    assert_eq!(
        smelter.input.map(|i| i.count),
        Some(15),
        "nothing was smelted, which is why the sentence is true"
    );
    assert!(smelter.output.is_none());
    let status = sim::debug::building_status(&world, world.building(id).unwrap());
    assert!(
        status.contains("stalled: fuel won't light from cold"),
        "{status}"
    );
}
