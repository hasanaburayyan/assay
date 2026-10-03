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

/// **A RE-PRESS ON THE BATCH ALREADY RUNNING COSTS NOTHING** (ASSA-109), the
/// way pressing Mine on the deposit you are already mining costs nothing.
///
/// Asserted against a CONTROL TICK rather than against the two fields I
/// thought to check: the same world is stepped once with the re-press and once
/// with nothing at all, and the two must be indistinguishable. That is what
/// "no-op" means, it needs no knowledge of the tick rate, and it would catch a
/// guard that returned early after already having spent something.
#[test]
fn pressing_craft_again_on_the_running_batch_is_the_same_as_doing_nothing() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(Grade::B), 50);
    let press = Input::player(me, craft(RecipeId::Smelter, ore(Grade::B), 1));
    run(&mut world, std::slice::from_ref(&press), 9);

    // There must be real elapsed ticks to lose, or this test proves nothing.
    let running = world.player(me).unwrap().crafting.expect("a batch runs");
    assert!(
        running.progress > 0,
        "nothing is at stake in this test unless the batch has progressed: {running:?}"
    );

    let mut idle = world.clone();
    let mut idle_events = Vec::new();
    step(&mut idle, &[], &mut idle_events);

    let mut again_events = Vec::new();
    step(&mut world, std::slice::from_ref(&press), &mut again_events);

    assert_eq!(
        world.player(me).unwrap().crafting,
        idle.player(me).unwrap().crafting,
        "the re-press moved the batch: {running:?} before it"
    );
    assert_eq!(
        world.state_hash(),
        idle.state_hash(),
        "a re-press changed something in the world that an idle tick did not"
    );
    assert_eq!(
        again_events, idle_events,
        "a re-press said something an idle tick did not"
    );
}

/// The other half of the ruling: changing your mind IS a change, and still
/// refunds what it abandons. Two ways to change it — the recipe and the stack
/// the batches come from — because the guard compares both and a test naming
/// one would let the other through.
#[test]
fn craft_naming_a_different_recipe_or_stack_still_replaces_the_batch() {
    for (what, recipe, item) in [
        ("another recipe", RecipeId::Sort, ore(Grade::B)),
        ("another stack", RecipeId::Smelter, ore(Grade::C)),
    ] {
        const STOCKED: u32 = 5;
        let switch = craft(recipe, item, 1);
        let (mut world, me) = world_with_player();
        let inventory = &mut world.player_mut(me).unwrap().inventory;
        inventory.add(ore(Grade::B), STOCKED);
        inventory.add(ore(Grade::C), STOCKED);
        run(
            &mut world,
            &[Input::player(
                me,
                craft(RecipeId::Smelter, ore(Grade::B), 1),
            )],
            3,
        );
        assert_eq!(
            world.player(me).unwrap().inventory.count(ore(Grade::B)),
            0,
            "{what}: the first batch must really have taken the ore"
        );
        let abandoned = world.player(me).unwrap().crafting.expect("a batch runs");

        let events = run(&mut world, &[Input::player(me, switch)], 1);
        assert!(
            events.iter().any(|e| matches!(
                e,
                Event::CraftingStopped {
                    reason: StopReason::Stopped,
                    ..
                }
            )),
            "{what}: a real change of intent still stops the old batch: {events:?}"
        );
        let p = world.player(me).unwrap();
        let replacement = p.crafting.expect("the new batch runs");
        assert_ne!(
            replacement, abandoned,
            "{what}: the batch was supposed to be replaced"
        );
        // Not `== 0`: the same tick that applied the command also advanced the
        // new batch. Below the abandoned one, so the clock really restarted.
        assert!(
            replacement.progress < abandoned.progress,
            "{what}: the replacement kept the old batch's clock: {replacement:?} after {abandoned:?}"
        );
        // THE REFUND, counted off the recipes rather than off numbers I typed:
        // Sort takes 3 ore and Smelter 5, so one expected total for both arms
        // would be asserting that Sort costs what Smelter costs.
        let came_back = abandoned.recipe.recipe().input.1;
        let went_out = recipe.recipe().input.1;
        assert!(came_back > 0, "a refund of nothing proves nothing");
        assert_eq!(
            p.inventory.count(ore(Grade::B)) + p.inventory.count(ore(Grade::C)),
            2 * STOCKED - went_out,
            "{what}: the abandoned batch's {came_back} must come back (without \
             it this is short by exactly that) and the replacement's \
             {went_out} go out"
        );
    }
}

/// **THE TWO ARMS ANSWER THE SAME GESTURE THE SAME WAY**, which is the whole
/// of ASSA-109: it goes red if somebody deletes `Mine`'s `// already at it`
/// instead of `Craft`'s.
///
/// The quantity is the control tick again, and that is a correction I owe the
/// test. I first wrote this arm as "neither reports a stop", because that is
/// the quantity the Game Director measured the asymmetry on — and deleting
/// `Mine`'s guard left it GREEN, since an unguarded `Mine` re-press emits
/// `MiningStarted` and silently resets progress rather than reporting a stop.
/// The harm is the reset, not the word, so the assertion has to be the reset.
#[test]
fn neither_mining_nor_crafting_loses_progress_when_you_repeat_yourself() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(Grade::B), 50);
    // Stand on a deposit soft enough to dig, so `Mine` really starts.
    let (center, species) = {
        let d = world.deposits.first().expect("a world has deposits");
        (d.center, d.species)
    };
    world.player_mut(me).unwrap().pos = center;
    world.species_mut(species).sheet.hardness = 1;

    for (what, command) in [
        ("craft", craft(RecipeId::Smelter, ore(Grade::B), 1)),
        ("mine", PlayerCommand::Mine),
    ] {
        let press = Input::player(me, command);
        let first = run(&mut world, std::slice::from_ref(&press), 3);
        assert!(
            !first.is_empty(),
            "{what}: the first press must do something, or the second proves nothing: {first:?}"
        );
        let started = world.player(me).unwrap();
        assert!(
            started.crafting.is_some() || started.mining.is_some(),
            "{what}: something must be under way to be lost"
        );

        let mut idle = world.clone();
        let mut idle_events = Vec::new();
        step(&mut idle, &[], &mut idle_events);
        let mut again_events = Vec::new();
        step(&mut world, std::slice::from_ref(&press), &mut again_events);

        assert_eq!(
            world.state_hash(),
            idle.state_hash(),
            "{what}: repeating yourself changed the world; an idle tick left \
             {:?}/{:?} and the re-press left {:?}/{:?}",
            idle.player(me).unwrap().crafting,
            idle.player(me).unwrap().mining,
            world.player(me).unwrap().crafting,
            world.player(me).unwrap().mining,
        );
        assert_eq!(
            again_events, idle_events,
            "{what}: repeating yourself said something an idle tick did not"
        );

        world.player_mut(me).unwrap().crafting = None;
        world.player_mut(me).unwrap().mining = None;
    }
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
