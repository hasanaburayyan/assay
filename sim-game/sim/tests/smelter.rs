use sim::tuning::{
    BURN_TICKS_PER_REACTIVITY, FUEL_MIN_REACTIVITY, HAND_SPARK_TEMPERATURE, REACH,
    SMELTER_INPUT_CAP, SMELTER_OUTPUT_CAP,
};
use sim::{
    BuildingId, BuildingKind, Event, Grade, Input, Item, ItemKind, PlayerCommand, PlayerId,
    RecipeId, RejectReason, Sheet, Slot, SmelterIdle, SmelterStall, SmelterState, SpeciesId,
    SystemCommand, TilePos, World, WorldConfig, step,
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

// ---------------------------------------------------------------------------
// ASSA-321: the batch a smelter is part-way through, which nothing could read
// ---------------------------------------------------------------------------

fn work_of(world: &World, id: BuildingId) -> Option<sim::WorkReading> {
    world.building_work(world.building(id).unwrap())
}

/// The clause a player reads, or `""` when there is no batch to report.
fn work_words(world: &World, id: BuildingId) -> String {
    sim::debug::work_clause(world, world.building(id).unwrap()).unwrap_or_default()
}

/// **AN EMPTY SMELTER MUST NOT OFFER A NUMBER.** `0 of 20` on a cold empty
/// smelter is an invitation to wait for something nobody has fed it (ASSA-43's
/// rule), which is why the reading is `Option` rather than a zeroed pair.
#[test]
fn a_smelter_with_nothing_in_it_has_no_batch_to_report() {
    let (world, _, id, _) = world_with_smelter();
    assert_eq!(work_of(&world, id), None);
    assert_eq!(work_words(&world, id), "");
    let status = sim::debug::building_status(&world, world.building(id).unwrap());
    assert!(
        !status.contains(" of 20 "),
        "an idle smelter's status must carry no batch numbers: {status}"
    );
}

/// The reading exists while the smelter is STOPPED, and says the batch has not
/// started — a different sentence from the stall on its own.
#[test]
fn ore_with_no_fuel_reads_as_a_batch_that_has_not_started() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 3);
    run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, ore(WALLS), 3))],
        5,
    );
    assert_eq!(
        world.smelter_state(world.building(id).unwrap()),
        SmelterState::Stalled(SmelterStall::NoFuel)
    );
    assert_eq!(
        work_of(&world, id),
        Some(sim::WorkReading { done: 0, total: 20 }),
        "a stall does not remove the batch in front of it"
    );
    assert_eq!(work_words(&world, id), "0 of 20 ticks into this batch");
}

/// The number moves with the ticks, and `building_status` carries it — the
/// whole of what ASSA-321 found missing.
#[test]
fn a_smelters_batch_progress_is_readable_as_it_refines() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 3);
    give(&mut world, me, ore(FUEL), 1);
    let total = RecipeId::Refine.recipe().ticks;
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 3)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1)),
        ],
        7,
    );
    assert_eq!(
        work_of(&world, id),
        Some(sim::WorkReading { done: 7, total }),
        "seven ticks of refining is seven ticks of progress"
    );
    let status = sim::debug::building_status(&world, world.building(id).unwrap());
    assert!(
        status.contains("7 of 20 ticks into this batch"),
        "the status line is where a headless player reads it: {status}"
    );

    // Finishing resets it, and the next unit of the same stack starts over.
    run(&mut world, &[], total - 7);
    assert_eq!(
        work_of(&world, id),
        Some(sim::WorkReading { done: 0, total }),
        "two ore are left, so a new batch is in front of it at zero"
    );
}

/// **THE DENOMINATOR IS NOT A CONSTANT**, which is the reason this reading is
/// a sim function at all. A client that divided by one number would be wrong
/// about every resmelt a player runs; this test is what goes red if anyone
/// writes `20` into a host.
#[test]
fn the_total_comes_from_the_recipe_in_the_slot_and_not_from_one_constant() {
    let (mut world, me, id, _) = world_with_smelter();
    let refined_b = Item::new(ItemKind::Refined, WALLS, Grade::B);
    give(&mut world, me, refined_b, 3);
    give(&mut world, me, ore(FUEL), 1);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, refined_b, 3)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1)),
        ],
        3,
    );
    let resmelt = RecipeId::Resmelt.recipe().ticks;
    assert_ne!(
        resmelt,
        RecipeId::Refine.recipe().ticks,
        "if the two recipes ever take the same time this test proves nothing"
    );
    assert_eq!(
        work_of(&world, id),
        Some(sim::WorkReading {
            done: 3,
            total: resmelt
        })
    );
    assert_eq!(work_words(&world, id), "3 of 40 ticks into this batch");
}

/// **A SLOT HOLDING LESS THAN A BATCH IS NOT A BATCH**, and since ASSA-322 the
/// state line knows it.
///
/// `run_smelters` skips a smelter whose input is short of `recipe.input.1`
/// (resmelt eats 3), and `World::smelter_state` used not to check the count: it
/// reported `Working` for a smelter that would sit there forever, so the status
/// line of a smelter holding 2 refined said `working at 60` while nothing
/// happened — the "honest status" defect ASSA-80 and ASSA-94 exist to kill, one
/// slot over.
///
/// **WHAT CHANGED, NAMED RATHER THAN QUIETLY EDITED.** This test pinned the
/// disagreement for a day and asserted `Working { at: 60 }` as *wrong on
/// purpose*. The Game Director ruled it an idle with a reason, not a stall and
/// not a fifth state, so the assertion below is now
/// `Idle(ShortBatch { recipe: Resmelt, holding: 2 })` and the wording test
/// beside it owns the sentence.
///
/// **AND THE PROTOCOL CLAIM IN MY OWN OLD DOC COMMENT WAS WRONG.** It said the
/// fix "needs a `PROTOCOL_VERSION` bump because `SmelterStall` rides on an
/// event". It does ride on one — but a short batch is not a stall, and
/// `SmelterState` derives no `Serialize` at all (`building.rs`), so it is on no
/// wire and in no save. Protocol stayed 10 and `SAVE_VERSION` stayed 12.
///
/// The reading stays `None`: the sim's own precondition says there is no batch,
/// so there is no batch to report progress on.
#[test]
fn a_part_batch_makes_no_progress_and_the_state_line_says_so() {
    let (mut world, me, id, _) = world_with_smelter();
    let refined_b = Item::new(ItemKind::Refined, WALLS, Grade::B);
    let needs = RecipeId::Resmelt.recipe().input.1;
    assert!(
        needs > 2,
        "the fixture needs a recipe that eats more than 2"
    );
    give(&mut world, me, refined_b, 2);
    give(&mut world, me, ore(FUEL), 1);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, refined_b, 2)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 1)),
        ],
        RecipeId::Resmelt.recipe().ticks * 3,
    );
    let s = smelter_of(&world, id);
    assert_eq!(s.input.map(|i| i.count), Some(2), "nothing was consumed");
    assert_eq!(s.output, None, "and nothing was produced");
    assert_eq!(s.progress, 0, "because the step loop never reached it");
    assert_eq!(
        work_of(&world, id),
        None,
        "no batch is in front of it, so there is no batch to report"
    );
    // The half that used to be wrong. `holding` is this smelter's own fact and
    // `recipe` is the table's, which is what lets the sentence carry a batch
    // size without a second copy of the number.
    assert_eq!(
        world.smelter_state(world.building(id).unwrap()),
        SmelterState::Idle(SmelterIdle::ShortBatch {
            recipe: RecipeId::Resmelt,
            holding: 2
        }),
        "a smelter holding 2 of a 3-refined batch is idle with a reason"
    );
    assert_eq!(
        sim::debug::building_state_line(&world, world.building(id).unwrap()),
        "idle: needs 3 to resmelt, holding 2",
        "the Game Director's sentence, on the surface a player reads"
    );
    // **AND IT IS NOT SOMETHING TO FIX.** The whole reason this is an idle and
    // not a stall is that it is where every bulk load ends, so it must not
    // reach the halt surface or announce an event.
    assert!(
        !world.building_state(world.building(id).unwrap()).halted(),
        "a short batch is the rules' own remainder, not a player's mistake"
    );
    assert_eq!(
        sim::debug::halt_lines(&world, sim::debug::Audience::Typed),
        Vec::<String>::new(),
        "a surface listing this would cry wolf after every bulk resmelt"
    );
}

/// **THE SENTENCE'S TWO NUMBERS AND ITS VERB COME OFF `RECIPES`, AND THIS IS
/// THE CHECK ON IT** (Game Director, ASSA-322).
///
/// The end-to-end test above can only ever reach `Resmelt`: it is the one
/// smelter recipe that eats more than one, so it is also the only one a real
/// slot can be short of. That makes it blind to a hardcoded `3` or
/// `"resmelt"` — the exact literal the ruling forbids, and ASSA-59's shape.
///
/// So this drives the wording function directly over four recipes carrying
/// three different batch sizes (3, 2 and 5). A literal anywhere in the format
/// string reddens it.
#[test]
fn the_short_batch_sentence_reads_the_recipe_table_and_not_a_literal() {
    // **THE WORLD IS A SPELLING TABLE THIS ARM NEVER OPENS.**
    // `smelter_state_line` grew its `&World` on ASSA-350, for the one stall
    // whose reason names an item (`output still holds <name>`). The
    // `ShortBatch` arm under test reads `recipe` and `holding` only, so any
    // world does — but it has to be a real one, because a sentence that
    // started naming a species would be the literal this test forbids and the
    // table is what would catch it.
    let (world, _) = world_with_player();
    let line = |recipe, holding| {
        sim::debug::smelter_state_line(
            &world,
            SmelterState::Idle(SmelterIdle::ShortBatch { recipe, holding }),
        )
    };
    assert_eq!(
        line(RecipeId::Resmelt, 2),
        "idle: needs 3 to resmelt, holding 2"
    );
    // Not reachable through a slot, and that is the point: these pin the
    // function to the table rather than to the one row the world can show us.
    assert_eq!(line(RecipeId::Sort, 1), "idle: needs 3 to sort, holding 1");
    assert_eq!(line(RecipeId::Gear, 1), "idle: needs 2 to gear, holding 1");
    assert_eq!(
        line(RecipeId::Smelter, 4),
        "idle: needs 5 to smelter, holding 4"
    );
    // Non-vacuity: the three above must not all be the same string.
    assert_ne!(line(RecipeId::Gear, 1), line(RecipeId::Sort, 1));
    // And the batch size really is the table's, not a constant that happens to
    // match today.
    for recipe in [RecipeId::Resmelt, RecipeId::Sort, RecipeId::Gear] {
        assert!(
            line(recipe, 0).contains(&format!(
                "needs {} to {}",
                recipe.recipe().input.1,
                recipe.name()
            )),
            "{recipe:?} sentence drifted from the table: {}",
            line(recipe, 0)
        );
    }
}

/// **AN EMPTY SLOT STAYS WORDLESS** (Game Director, ASSA-322): her standing
/// ruling is that an absent part gives an absent number, never a 0, so the
/// empty arm keeps `nothing to refine` and never becomes `holding 0`.
#[test]
fn an_empty_smelter_says_nothing_about_counts() {
    let (world, _, id, _) = world_with_smelter();
    let b = world.building(id).unwrap();
    assert_eq!(
        world.smelter_state(b),
        SmelterState::Idle(SmelterIdle::Empty)
    );
    let line = sim::debug::building_state_line(&world, b);
    assert_eq!(line, "idle: nothing to refine");
    assert!(
        !line.contains("holding") && !line.contains('0'),
        "the empty arm must not print a count: {line}"
    );
}

/// **THE BOUNDARY, ADDED BECAUSE A MUTATION FOUND THIS CRATE NOT GUARDING IT.**
///
/// Turning ASSA-322's `<` into `<=` — a smelter holding exactly one batch reads
/// short and nothing ever smelts again — left `sim`'s whole suite green. Every
/// resmelt fixture in this file loads more than one batch, so nothing here
/// pinned `input.count == recipe.input.1`. Only `sim-godot`'s tests caught it,
/// and the rule is this crate's: an off-by-one in a rule should not need a host
/// to notice.
///
/// Exactly one batch is a batch. It works, and it finishes — the second half
/// matters because a state label that said `Working` while `run_smelters` still
/// skipped it would be the same lie in the other direction.
#[test]
fn a_smelter_holding_exactly_one_batch_is_working_and_not_short() {
    let (mut world, me, id, _) = world_with_smelter();
    let refined_b = Item::new(ItemKind::Refined, WALLS, Grade::B);
    let batch = RecipeId::Resmelt.recipe().input.1;
    give(&mut world, me, refined_b, batch);
    give(&mut world, me, ore(FUEL), 4);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, refined_b, batch)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 4)),
        ],
        2,
    );
    let state = world.smelter_state(world.building(id).unwrap());
    assert!(
        matches!(state, SmelterState::Working { .. }),
        "exactly one batch is a batch, not a short one: {state:?}"
    );
    run(&mut world, &[], RecipeId::Resmelt.recipe().ticks + 2);
    let s = smelter_of(&world, id);
    assert_eq!(s.input, None, "the whole batch was consumed");
    let bar = s.output.expect("and one grade-A bar came out");
    assert_eq!(bar.item.grade, Grade::A, "a resmelt raises the grade");
}

/// **A SMELTER WHOSE OUTPUT HOLDS A DIFFERENT MATERIAL REPORTS `working`
/// FOREVER** — the third silent skip in `run_smelters`, and the only one of the
/// three that is reachable (ASSA-350).
///
/// `run_smelters` has three `continue`s before the fuel block. Two are shut at
/// the door by `Insert` into `Slot::Input`: an input kind with no smelter recipe
/// is `RejectReason::WrongItem` and a grade-A input is
/// `RejectReason::AlreadyBestGrade`. **The third has no gate anywhere.**
/// Insert-input validates kind, grade, walls and reach and **never looks at the
/// output slot**, so a smelter can legally be handed ore of species Y while its
/// output still holds refined species X. `out_item` is then refined Y,
/// `s.output` is refined X, and the loop takes `Some(_) => continue, // holds
/// something else; wait to be emptied` on every tick from then on.
///
/// `World::smelter_state` knows nothing about it — its only output arm is the
/// cap, and one bar is not a full slot. So the status line says `working at 60`
/// and `sim-godot`'s `lit` (`matches!(state, Working { .. })`) draws a burning
/// fire on it. Exactly ASSA-322's defect, one slot further on, sprite included.
///
/// **IT TAKES NO MISTAKE AND NO `Take`.** Refine everything you loaded — the
/// input empties and one bar sits in the output — then load the next rock. That
/// is tidying, and it is what anyone smelting two species in one smelter does.
///
/// **THIS TEST WAS WRITTEN AS A PIN AND IS NOW THE ASSERTION** (PR #460 → this
/// one). It passed on main 0d17524 asserting `Working` and `halted() == false`,
/// and its passing was the finding. Both of those lines are inverted below and
/// nothing else about the fixture moved, so the diff on this function *is* the
/// behaviour change.
///
/// **RULED A STALL** by the Game Director, on a criterion she sharpened in order
/// to split it from ASSA-322: *an idle is waiting for SUPPLY; a stall is blocked
/// by a CONFLICT no supply resolves.* Pour more ore into a short batch and it
/// runs — the remainder is the rules' own doing. Pour more ore into this and
/// nothing happens, ever; the only thing that clears it is a hand in the output
/// slot. So `halted()` must be true here and must not be on 322.
///
/// That cost `PROTOCOL_VERSION` 10 → 11, because `Event::SmelterStalled`
/// changed shape and the code rulebook counts an event. Her words: *"the
/// protocol bump is the price of telling the truth, not an argument against
/// it."* **Not because it crosses the wire — it never has.** `SmelterStall`
/// derives `Serialize`, which is what I first gave as the reason, but no
/// message carries an `Event`: lockstep ships inputs and each peer computes
/// its own events. See `sim_net::PROTOCOL_VERSION` for the correction.
#[test]
fn a_smelter_whose_output_holds_another_material_says_so_and_counts_as_halted() {
    let (mut world, me, id, _) = world_with_smelter();
    // WALLS (heat 60) and INERT (heat 20) both smelt inside WALLS' walls, so the
    // skip under test cannot be confused with TooHotForWalls.
    let first = ore(WALLS);
    let second = ore(INERT);
    give(&mut world, me, first, 1);
    give(&mut world, me, second, 1);
    give(&mut world, me, ore(FUEL), 4);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, first, 1)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 4)),
        ],
        RecipeId::Refine.recipe().ticks * 2,
    );
    // The premise, asserted before the finding: the first rock really did
    // refine, and nobody emptied the output.
    let s = smelter_of(&world, id);
    assert_eq!(s.input, None, "everything loaded was refined");
    let bar = s.output.expect("one bar came out");
    assert_eq!(bar.item.species, WALLS);

    // Now load the next rock. The rules accept it without a word.
    run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, second, 1))],
        RecipeId::Refine.recipe().ticks * 4,
    );
    let s = smelter_of(&world, id);
    assert_eq!(
        s.input.map(|i| i.count),
        Some(1),
        "nothing was consumed: run_smelters skipped it on the output slot"
    );
    assert_eq!(s.output, Some(bar), "and nothing was produced");
    assert_eq!(s.progress, 0, "because the step loop never reached it");

    // **THE TWO LINES THAT WERE INVERTED.** They asserted `Working` and
    // `!halted()` and passed, which was the whole finding.
    let state = world.smelter_state(world.building(id).unwrap());
    assert_eq!(
        state,
        SmelterState::Stalled(SmelterStall::OutputHoldsAnother(bar.item)),
        "the state names the material in the way, not a temperature"
    );
    assert!(
        world.building_state(world.building(id).unwrap()).halted(),
        "a conflict no supply resolves is something to fix, so it joins halt_lines"
    );

    // **AND THE SENTENCE, WHICH IS THE GAME DIRECTOR'S, WITH THE SIM'S OWN
    // SPELLING OF THE ITEM.** Built from `item_name` rather than typed here: a
    // literal would pass while the menu's `held` line said something else,
    // which is the two-spellings defect (ASSA-43/52) this wording exists to
    // avoid. One clause, no `·`, and no instruction to press anything.
    let said = sim::debug::stall_reason(&world, SmelterStall::OutputHoldsAnother(bar.item));
    assert_eq!(
        said,
        format!("output still holds {}", world.item_name(bar.item))
    );
    assert!(
        !said.contains('·') && !said.contains("take"),
        "one clause, no top-level mark, and the sim does not name a button: {said:?}"
    );
    assert_eq!(
        sim::debug::smelter_state_line(&world, state),
        format!("stalled: {said}"),
        "the status line is the `stalled:` prefix and this reason, nothing else"
    );

    // **THE PROGRESS CLAUSE IS PRESENT AND READS `0 of 20`, AND I HAD THIS
    // BACKWARDS.** I first asserted `None` here, from `building_status`'s rule
    // that the clause is *"absent, not zero, when no batch is in front of it:
    // an empty smelter saying `0 of 20` would be inviting a wait"* — and
    // measuring said `Some(0 of 20)`.
    //
    // **The code is right and my assertion was wrong.** A batch IS in front of
    // this smelter: a recipe's worth of ore is sitting in the input slot. What
    // is absent is not the batch but any progress on it, and that is exactly
    // what `0 of 20` says. The same docstring gives the reason it belongs here:
    // *"a stall is read as 'what do I do about it' and the progress is what
    // says whether fixing it resumes or restarts."* Take the bar out and this
    // batch starts from 0 — the number is the honest answer to that question,
    // and the stall sentence beside it is what stops it reading as a wait.
    assert_eq!(
        world
            .building_work(world.building(id).unwrap())
            .map(|w| (w.done, w.total)),
        Some((0, RecipeId::Refine.recipe().ticks)),
        "a loaded batch that cannot start is `0 of 20`, not absent"
    );
}

/// **THE ARM MUST NOT FIRE ON A SMELTER THAT IS SIMPLY RUNNING** — the cry-wolf
/// half, and the reason ASSA-322 had to be an idle. A smelter refining a second
/// batch of the SAME material has a loaded output slot and is working perfectly;
/// if this stall reached that, every bulk resmelt would end in a false alarm and
/// `SmelterState::Idle`'s own docstring rule would be broken from the other side.
#[test]
fn an_output_holding_more_of_the_same_material_is_not_a_stall() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), 6);
    give(&mut world, me, ore(FUEL), 8);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), 1)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 8)),
        ],
        RecipeId::Refine.recipe().ticks * 2,
    );
    let bar = smelter_of(&world, id).output.expect("one bar came out");

    // Load MORE of the same rock over that bar: same output item, so no conflict.
    run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, ore(WALLS), 1))],
        1,
    );
    let state = world.smelter_state(world.building(id).unwrap());
    assert!(
        !matches!(
            state,
            SmelterState::Stalled(SmelterStall::OutputHoldsAnother(_))
        ),
        "the output holds {} and the batch makes the same thing: {state:?}",
        world.item_name(bar.item)
    );
    assert!(
        matches!(state, SmelterState::Working { .. }),
        "it is refining, so it says so: {state:?}"
    );

    // AND THE CONFLICT GATE ITSELF AGREES, asked directly rather than through
    // the state chain, so a reordering of those arms cannot hide this.
    assert_eq!(
        world.smelter_output_conflict(smelter_of(&world, id)),
        None,
        "same item in the slot is not a conflict"
    );
}

/// The invariant my own doc comment leant on, pinned because I first wrote the
/// opposite: for a smelter, `progress > 0` means it refined on the last tick.
/// Every stall is tested before `progress += 1` and one unit of legal fuel
/// outlasts the longest batch, so there is no stalled smelter part-way through
/// a unit. A fuel rule that makes this false should arrive as a red test here.
#[test]
fn a_smelters_progress_is_zero_unless_it_refined_last_tick() {
    let (mut world, me, id, _) = world_with_smelter();
    give(&mut world, me, ore(WALLS), SMELTER_INPUT_CAP);
    give(&mut world, me, ore(FUEL), 2);
    run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, ore(WALLS), SMELTER_INPUT_CAP)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 2)),
        ],
        1,
    );
    let mut seen_working_mid_unit = 0;
    for _ in 0..600 {
        let before = smelter_of(&world, id).progress;
        step(&mut world, &[], &mut Vec::new());
        let s = smelter_of(&world, id);
        let state = world.smelter_state(world.building(id).unwrap());
        if s.progress > 0 {
            assert!(
                matches!(state, SmelterState::Working { .. }),
                "progress {} while {state:?}",
                s.progress
            );
            seen_working_mid_unit += 1;
        }
        assert!(
            s.progress <= before + 1,
            "a tick advances a batch by at most one tick"
        );
    }
    assert!(
        seen_working_mid_unit > 50,
        "the run has to spend real time mid-unit or this proves nothing: \
         {seen_working_mid_unit}"
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

/// **ALL FIVE STALLS, EACH BY ITS OWN SENTENCE, AND THE TWO SURFACES HELD
/// EQUAL.** A state-to-words mapping test: the slots are set directly rather
/// than driven, because what is under test is that one decision reaches both
/// the log and the status line saying the same thing — not the rules that get
/// a smelter into each state, which the tests above already pin.
///
/// **IT WAS FOUR UNTIL ASSA-350.** A new `SmelterStall` variant that skipped
/// this test would be a stall whose two surfaces are free to disagree, which is
/// the defect this function exists to prevent — so the count is in the heading
/// and asserted at the bottom against the list, not left as prose.
#[test]
fn every_stall_reason_says_the_same_thing_in_the_log_and_on_the_status_line() {
    // The material the `OutputHoldsAnother` case leaves in the output slot:
    // refined INERT, while the input is WALLS ore, so the batch would make
    // refined WALLS and cannot add to it.
    let in_the_way = Item::new(ItemKind::Refined, INERT, Grade::A);
    let cases: [(SmelterStall, &str); 5] = [
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
        // The sentence is built from the world inside the loop, because it
        // names an item and a literal here would pass while the machine menu's
        // own `held` line said something else (ASSA-43/52).
        (SmelterStall::OutputHoldsAnother(in_the_way), ""),
    ];
    let mut covered = 0;
    for (why, sentence) in cases {
        covered += 1;
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
                // A burning fire and one bar of the WRONG material: the stall
                // has to come from the output slot and not from the fuel.
                SmelterStall::OutputHoldsAnother(item) => {
                    s.output = Some(sim::ItemStack::new(item, 1));
                    s.burn_left = 10;
                    s.burn_temperature = 100;
                }
            }
        }
        let b = world.building(id).unwrap();
        assert_eq!(
            world.smelter_state(b).stall(),
            Some(why),
            "the state this test set up is not the one it is about"
        );

        // The one reason whose words come from the world rather than the table.
        let sentence = match why {
            SmelterStall::OutputHoldsAnother(item) => {
                format!("output still holds {}", world.item_name(item))
            }
            _ => sentence.to_string(),
        };
        assert!(
            !sentence.is_empty(),
            "every case has to arrive here with a sentence to compare: {why:?}"
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
            line.contains(&sentence),
            "and the log must say the same thing, not a second wording: {line}"
        );
    }
    // **THE SELF-CHECK ON THIS TEST'S OWN AIM.** The table is a hand-written
    // list and a new `SmelterStall` variant does not force its way in, so the
    // one thing that catches a sixth reason shipping unheld is this count read
    // against the heading. If it fails, add the case — do not raise the number.
    assert_eq!(
        covered, 5,
        "five stall reasons exist and this test holds all of them equal"
    );
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

/// **ASSA-350 BOX 5's CRY-WOLF HALF, ON THE NEW ARM, THROUGH THE REAL
/// COMMANDS.** The Game Director's standing test of a new stall is *a check we
/// have only ever seen fire when it is false is worse than no check* — so this
/// drives a smelter into `OutputHoldsAnother` the way a player reaches it
/// (refine a rock, leave the bar, load another species) and pins both halves of
/// her ASSA-80 rule 2: announced once on the edge in, then nothing while it
/// sits.
///
/// **THE LAST BLOCK IS A MEASUREMENT I EXPECTED TO GO THE OTHER WAY**, and it
/// is why box 5 can be ticked rather than left open on ASSA-364. Maren's
/// ASSA-364 is real — `announce_new_stalls` keys on a `bool`, so a stall that
/// becomes a *different* stall emits nothing and the old sentence cannot be
/// retired. I assumed this arm fed that edge: `Take` the bar and a smelter with
/// no fuel would fall from `OutputHoldsAnother` straight into `NoFuel`,
/// silently. **It does not, and `burn_left`'s own docstring says why** —
/// *"only counts down while smelting"* — so a fire lit to refine the first rock
/// is still lit, and the act that clears this conflict leaves the smelter
/// WORKING. Asserted below rather than argued, because the whole point of the
/// block is that the reasoning was wrong.
#[test]
fn a_smelter_blocked_on_its_output_announces_itself_once_and_then_goes_quiet() {
    let (mut world, me, id, _) = world_with_smelter();
    let first = ore(WALLS);
    let second = ore(INERT);
    give(&mut world, me, first, 1);
    give(&mut world, me, second, 1);
    give(&mut world, me, ore(FUEL), 4);

    // Refine the first rock and leave the bar where it lands.
    let setup = run(
        &mut world,
        &[
            Input::player(me, insert(id, Slot::Input, first, 1)),
            Input::player(me, insert(id, Slot::Fuel, ore(FUEL), 4)),
        ],
        RecipeId::Refine.recipe().ticks * 2,
    );
    let bar = smelter_of(&world, id).output.expect("one bar came out");

    // **THE PREMISE, ASSERTED AS A FAILURE.** If anything were stalled already
    // the line below would not be an edge and this test would prove nothing:
    // an emptied input is `idle: nothing to refine`, which is never announced.
    assert_eq!(
        stalls(&setup),
        vec![],
        "nothing stalls during setup: {setup:?}"
    );
    assert!(
        world
            .smelter_state(world.building(id).unwrap())
            .stall()
            .is_none(),
        "the smelter is idle, not stalled, before the edge"
    );

    // **THE EDGE IN, ON ONE TICK.** Loading a second species over the bar is
    // the whole defect, and it is announced naming the material in the way.
    let events = run(
        &mut world,
        &[Input::player(me, insert(id, Slot::Input, second, 1))],
        1,
    );
    assert_eq!(
        stalls(&events),
        vec![SmelterStall::OutputHoldsAnother(bar.item)],
        "entering this stall is said once, with the item that is blocking it: {events:?}"
    );

    // **AND THEN SILENCE** — the arm a per-tick emitter fails, and the reason
    // the log stays readable.
    let later = run(&mut world, &[], 80);
    assert_eq!(
        stalls(&later),
        vec![],
        "a smelter sitting in this stall must not shout: {later:?}"
    );
    // Silence because it is still stuck, not because it quietly recovered.
    // Without this the assertion above passes on a smelter that got better.
    assert_eq!(
        world.smelter_state(world.building(id).unwrap()),
        SmelterState::Stalled(SmelterStall::OutputHoldsAnother(bar.item)),
        "80 silent ticks and the condition is unchanged"
    );

    // **CLEARING IT: WHERE THIS ARM MEETS ASSA-364, MEASURED.** `Take` empties
    // the output, which is the one act that resolves this conflict.
    let cleared = run(
        &mut world,
        &[Input::player(me, PlayerCommand::Take { building: id })],
        1,
    );
    assert_eq!(
        smelter_of(&world, id).output,
        None,
        "premise: the bar really left the slot"
    );
    let after = world.smelter_state(world.building(id).unwrap());
    assert!(
        after.stall().is_none(),
        "the act that clears this conflict does not land in another stall, so this \
         arm never reaches ASSA-364's silent stall-to-stall edge; it is {after:?}"
    );
    // And the stronger claim the docstring actually makes, because "not
    // stalled" would also be true of an idle smelter and would leave the
    // mechanism unproven: the fire lit for the first rock is still burning, so
    // the second species starts refining the moment the slot is free.
    assert!(
        matches!(after, SmelterState::Working { .. }),
        "the fire never went out while it sat blocked, so clearing the slot resumes \
         work rather than exposing a fuel stall; it is {after:?}"
    );
    assert_eq!(
        stalls(&cleared),
        vec![],
        "and nothing is announced on the way out, because leaving a stall is not entering one"
    );
}
