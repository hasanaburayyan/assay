use sim::tuning::GEAR_MIN_HARDNESS;
use sim::{
    Event, Grade, Input, Item, ItemKind, PlayerCommand, PlayerId, Property, RecipeId, RejectReason,
    SpeciesId, StopReason, SystemCommand, World, WorldConfig, step,
};

const X: SpeciesId = SpeciesId(0);

fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    // Species 0 is hard enough for gears at every grade.
    world.species_mut(X).sheet.hardness = 100;
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

fn craft(recipe: RecipeId, item: Item, count: u32) -> PlayerCommand {
    PlayerCommand::Craft {
        recipe,
        item,
        count,
    }
}

fn ore(grade: Grade) -> Item {
    Item::new(ItemKind::Ore, X, grade)
}

fn refined(grade: Grade) -> Item {
    Item::new(ItemKind::Refined, X, grade)
}

#[test]
fn recipes_are_named_after_their_output_and_keep_species_and_grade() {
    assert_eq!(RecipeId::parse("smelter"), Some(RecipeId::Smelter));
    assert_eq!(RecipeId::parse("gear"), Some(RecipeId::Gear));
    assert_eq!(RecipeId::parse("refined"), Some(RecipeId::Refine));
    assert_eq!(RecipeId::parse("ore"), None, "ore is mined, not made");
    let smelter = RecipeId::Smelter.recipe();
    assert_eq!(smelter.input, (ItemKind::Ore, 5));
    assert_eq!(
        smelter.output_for(ore(Grade::B)),
        Some(Item::new(ItemKind::Smelter, X, Grade::B))
    );
    assert_eq!(RecipeId::parse("sort"), Some(RecipeId::Sort));
    assert_eq!(RecipeId::parse("resmelt"), Some(RecipeId::Resmelt));
    assert!(RecipeId::Smelter.is_hand_craftable());
    assert!(!RecipeId::Refine.is_hand_craftable());
}

#[test]
fn crafting_a_smelter_takes_ore_then_time() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(Grade::C), 7);
    let ticks = RecipeId::Smelter.recipe().ticks;

    let events = run(
        &mut world,
        &[Input::player(
            me,
            craft(RecipeId::Smelter, ore(Grade::C), 1),
        )],
        1,
    );
    assert_eq!(
        events,
        vec![Event::CraftStarted {
            player: me,
            recipe: RecipeId::Smelter,
            item: ore(Grade::C),
            count: 1
        }]
    );
    let inv = &world.player(me).unwrap().inventory;
    assert_eq!(inv.count(ore(Grade::C)), 2);

    let events = run(&mut world, &[], ticks - 1);
    let made = Item::new(ItemKind::Smelter, X, Grade::C);
    assert_eq!(
        events,
        vec![Event::ItemCrafted {
            player: me,
            recipe: RecipeId::Smelter,
            item: made,
            count: 1,
            remaining: 0
        }]
    );
    let p = world.player(me).unwrap();
    assert_eq!(p.inventory.count(made), 1);
    assert!(p.crafting.is_none());
}

#[test]
fn a_batch_of_several_runs_until_inputs_run_out() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(refined(Grade::A), 5);
    let ticks = RecipeId::Gear.recipe().ticks;

    let events = run(
        &mut world,
        &[Input::player(
            me,
            craft(RecipeId::Gear, refined(Grade::A), 3),
        )],
        ticks * 3,
    );
    let crafted = events
        .iter()
        .filter(|e| matches!(e, Event::ItemCrafted { .. }))
        .count();
    assert_eq!(crafted, 2, "5 refined make 2 gears, not 3");
    assert_eq!(
        events.last(),
        Some(&Event::CraftingStopped {
            player: me,
            recipe: RecipeId::Gear,
            reason: StopReason::OutOfInputs
        })
    );
    let inv = &world.player(me).unwrap().inventory;
    assert_eq!(inv.count(Item::new(ItemKind::Gear, X, Grade::A)), 2);
    assert_eq!(inv.count(refined(Grade::A)), 1);
}

#[test]
fn gears_need_hard_enough_material_at_their_grade() {
    // Property threshold, scaled by grade: C may fail where A passes.
    let (mut world, me) = world_with_player();
    world.species_mut(X).sheet.hardness = GEAR_MIN_HARDNESS as u8 + 2;
    assert!(world.species(X).effective(Property::Hardness, Grade::C) < GEAR_MIN_HARDNESS);
    assert!(world.species(X).effective(Property::Hardness, Grade::A) >= GEAR_MIN_HARDNESS);
    let inv = &mut world.player_mut(me).unwrap().inventory;
    inv.add(refined(Grade::C), 2);
    inv.add(refined(Grade::A), 2);

    let bad = craft(RecipeId::Gear, refined(Grade::C), 1);
    let events = run(&mut world, &[Input::player(me, bad.clone())], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: bad,
            reason: RejectReason::RequirementNotMet(Property::Hardness, GEAR_MIN_HARDNESS)
        }]
    );
    let events = run(
        &mut world,
        &[Input::player(
            me,
            craft(RecipeId::Gear, refined(Grade::A), 1),
        )],
        1,
    );
    assert!(matches!(events[..], [Event::CraftStarted { .. }]));
}

#[test]
fn stop_cancels_crafting_and_refunds_the_current_batch() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(Grade::B), 5);
    run(
        &mut world,
        &[Input::player(
            me,
            craft(RecipeId::Smelter, ore(Grade::B), 1),
        )],
        3,
    );
    let events = run(&mut world, &[Input::player(me, PlayerCommand::Stop)], 1);
    assert_eq!(
        events,
        vec![Event::CraftingStopped {
            player: me,
            recipe: RecipeId::Smelter,
            reason: StopReason::Stopped
        }]
    );
    let p = world.player(me).unwrap();
    assert_eq!(p.inventory.count(ore(Grade::B)), 5);
    assert!(p.crafting.is_none());
}

#[test]
fn crafting_is_rejected_for_bad_inputs() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(refined(Grade::A), 1);
    let cases = [
        (
            craft(RecipeId::Smelter, ore(Grade::C), 1),
            RejectReason::MissingItems(ore(Grade::C)),
        ),
        (
            craft(RecipeId::Refine, ore(Grade::C), 1),
            RejectReason::NotHandCraftable,
        ),
        (
            craft(RecipeId::Smelter, ore(Grade::C), 0),
            RejectReason::ZeroCount,
        ),
        (
            craft(RecipeId::Smelter, refined(Grade::A), 1),
            RejectReason::WrongItem,
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
            }]
        );
    }
}

#[test]
fn crafting_continues_while_walking() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(Grade::A), 5);
    let start = world.spawn_tile();
    let target = sim::TilePos::new(start.x + 10, start.y);
    run(
        &mut world,
        &[
            Input::player(me, craft(RecipeId::Smelter, ore(Grade::A), 1)),
            Input::player(me, PlayerCommand::MoveTo { target }),
        ],
        RecipeId::Smelter.recipe().ticks,
    );
    let p = world.player(me).unwrap();
    assert_eq!(
        p.inventory.count(Item::new(ItemKind::Smelter, X, Grade::A)),
        1
    );
    assert_eq!(p.pos, target);
}

#[test]
fn sorting_ore_by_hand_raises_its_grade_at_a_loss() {
    // Decision 6, rung one: time plus mass loss.
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(Grade::C), 7);
    let ticks = RecipeId::Sort.recipe().ticks;
    let events = run(
        &mut world,
        &[Input::player(me, craft(RecipeId::Sort, ore(Grade::C), 2))],
        ticks * 2,
    );
    let made = events
        .iter()
        .filter(|e| matches!(e, Event::ItemCrafted { item, .. } if *item == ore(Grade::B)))
        .count();
    assert_eq!(made, 2);
    let inv = &world.player(me).unwrap().inventory;
    assert_eq!(inv.count(ore(Grade::B)), 2);
    assert_eq!(inv.count(ore(Grade::C)), 1, "6 in, 2 out");
}

#[test]
fn grade_a_cannot_be_sorted_further() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(Grade::A), 3);
    let bad = craft(RecipeId::Sort, ore(Grade::A), 1);
    let events = run(&mut world, &[Input::player(me, bad.clone())], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: bad,
            reason: RejectReason::AlreadyBestGrade
        }]
    );
    assert_eq!(world.player(me).unwrap().inventory.count(ore(Grade::A)), 3);
}

/// ASSA-49: a running craft has to be describable, because eight seconds of a
/// button saying nothing is read as a broken button.
///
/// The sentence is asserted whole rather than by substring: it is the thing
/// both hosts print, so if it changes shape that is a decision and not an
/// accident.
#[test]
fn a_running_craft_says_what_it_is_making_and_how_long_is_left() {
    let (mut world, me) = world_with_player();
    assert_eq!(
        sim::debug::crafting_readout(&world, me),
        None,
        "an idle player is making nothing, and None is how the host knows not to print a line"
    );

    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(Grade::C), 15);
    let ticks = RecipeId::Smelter.recipe().ticks;

    // THREE BATCHES, because the batch is the part that makes this worth saying.
    // One smelter is 20 ticks; three is 60, and nothing on screen said so.
    run(
        &mut world,
        &[Input::player(
            me,
            craft(RecipeId::Smelter, ore(Grade::C), 3),
        )],
        1,
    );
    let name = world.item_name(Item::new(ItemKind::Smelter, X, Grade::C));
    assert_eq!(
        sim::debug::crafting_readout(&world, me).unwrap(),
        format!(
            "making {name}: {} ticks left on this one, 2 to go after it",
            ticks - 1
        )
    );

    // Partway through the first batch the ticks come down and the count does not.
    run(&mut world, &[], 5);
    assert_eq!(
        sim::debug::crafting_readout(&world, me).unwrap(),
        format!(
            "making {name}: {} ticks left on this one, 2 to go after it",
            ticks - 6
        )
    );

    // The last batch drops the "to go" clause rather than saying "0 to go".
    run(&mut world, &[], ticks * 2);
    let line = sim::debug::crafting_readout(&world, me).unwrap();
    assert!(
        !line.contains("to go"),
        "the final batch should not advertise an empty queue: {line}"
    );
    assert!(line.starts_with(&format!("making {name}: ")), "{line}");

    // And when it finishes there is nothing to say again.
    run(&mut world, &[], ticks);
    assert_eq!(sim::debug::crafting_readout(&world, me), None);
}

/// AND `MakePart` IS INSTANT, which matters because ASSA-49 was filed believing
/// a part took ~79 ticks. It takes none: `MakePart` removes the material and
/// adds the part inside the same tick and never touches `Player::crafting`, so
/// there is no progress for any host to show. Pinned here so the next person to
/// go looking for a part's progress finds the answer instead of the question.
#[test]
fn making_a_part_finishes_in_the_tick_it_is_asked_for() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(Item::new(ItemKind::Refined, X, Grade::B), 60);
    run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::MakePart {
                kind: sim::assembly::PartKind::Head,
                material: Item::new(ItemKind::Refined, X, Grade::B),
                count: 1,
            },
        )],
        1,
    );
    assert!(
        world.player(me).unwrap().crafting.is_none(),
        "MakePart must not start a timed craft"
    );
    assert_eq!(sim::debug::crafting_readout(&world, me), None);
}
