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
        Item::new(ItemKind::Smelter, X, Grade::B)
    );
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
