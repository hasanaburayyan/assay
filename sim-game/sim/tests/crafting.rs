use sim::{
    Event, Input, Item, PlayerCommand, PlayerId, RecipeId, RejectReason, StopReason, SystemCommand,
    World, WorldConfig, step,
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

fn craft(recipe: RecipeId, count: u32) -> PlayerCommand {
    PlayerCommand::Craft { recipe, count }
}

#[test]
fn recipe_names_parse_and_smelter_needs_five_stone() {
    assert_eq!(RecipeId::parse("smelter"), Some(RecipeId::Smelter));
    assert_eq!(RecipeId::parse("gear"), Some(RecipeId::IronGear));
    assert_eq!(RecipeId::parse("iron-plate"), Some(RecipeId::IronPlate));
    assert_eq!(RecipeId::parse("coal"), None, "coal is mined, not made");
    let smelter = RecipeId::Smelter.recipe();
    assert_eq!(smelter.inputs, &[(Item::Stone, 5)]);
    assert_eq!(smelter.output, (Item::Smelter, 1));
    assert!(RecipeId::Smelter.is_hand_craftable());
    assert!(!RecipeId::IronPlate.is_hand_craftable());
    assert_eq!(
        sim::recipe::smelting_recipe_for(Item::IronOre),
        Some(RecipeId::IronPlate)
    );
    assert_eq!(sim::recipe::smelting_recipe_for(Item::Stone), None);
}

#[test]
fn crafting_a_smelter_takes_stone_then_time() {
    let (mut world, me) = world_with_player();
    world.player_mut(me).unwrap().inventory.add(Item::Stone, 7);
    let ticks = RecipeId::Smelter.recipe().ticks;

    let events = run(
        &mut world,
        &[Input::player(me, craft(RecipeId::Smelter, 1))],
        1,
    );
    assert_eq!(
        events,
        vec![Event::CraftStarted {
            player: me,
            recipe: RecipeId::Smelter,
            count: 1
        }]
    );
    // Inputs go in at the start; the output is not there yet.
    let inv = &world.player(me).unwrap().inventory;
    assert_eq!(inv.count(Item::Stone), 2);
    assert_eq!(inv.count(Item::Smelter), 0);

    let events = run(&mut world, &[], ticks - 1);
    assert_eq!(
        events,
        vec![Event::ItemCrafted {
            player: me,
            recipe: RecipeId::Smelter,
            item: Item::Smelter,
            count: 1,
            remaining: 0
        }]
    );
    let p = world.player(me).unwrap();
    assert_eq!(p.inventory.count(Item::Smelter), 1);
    assert!(p.crafting.is_none());
}

#[test]
fn a_batch_of_several_runs_until_inputs_run_out() {
    let (mut world, me) = world_with_player();
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(Item::IronPlate, 5);
    let ticks = RecipeId::IronGear.recipe().ticks;

    let events = run(
        &mut world,
        &[Input::player(me, craft(RecipeId::IronGear, 3))],
        ticks * 3,
    );
    let crafted = events
        .iter()
        .filter(|e| matches!(e, Event::ItemCrafted { .. }))
        .count();
    assert_eq!(crafted, 2, "5 plates make 2 gears, not 3");
    assert_eq!(
        events.last(),
        Some(&Event::CraftingStopped {
            player: me,
            recipe: RecipeId::IronGear,
            reason: StopReason::OutOfInputs
        })
    );
    let inv = &world.player(me).unwrap().inventory;
    assert_eq!(inv.count(Item::IronGear), 2);
    assert_eq!(inv.count(Item::IronPlate), 1);
}

#[test]
fn stop_cancels_crafting_and_refunds_the_current_batch() {
    let (mut world, me) = world_with_player();
    world.player_mut(me).unwrap().inventory.add(Item::Stone, 5);
    run(
        &mut world,
        &[Input::player(me, craft(RecipeId::Smelter, 1))],
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
    assert_eq!(p.inventory.count(Item::Stone), 5);
    assert!(p.crafting.is_none());
}

#[test]
fn crafting_is_rejected_without_inputs_or_for_machine_recipes() {
    let (mut world, me) = world_with_player();
    let cases = [
        (
            craft(RecipeId::Smelter, 1),
            RejectReason::MissingItems(Item::Stone),
        ),
        (
            craft(RecipeId::IronPlate, 1),
            RejectReason::NotHandCraftable,
        ),
        (craft(RecipeId::Smelter, 0), RejectReason::ZeroCount),
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
    world.player_mut(me).unwrap().inventory.add(Item::Stone, 5);
    let start = world.spawn_tile();
    let target = sim::TilePos::new(start.x + 10, start.y);
    run(
        &mut world,
        &[
            Input::player(me, craft(RecipeId::Smelter, 1)),
            Input::player(me, PlayerCommand::MoveTo { target }),
        ],
        RecipeId::Smelter.recipe().ticks,
    );
    let p = world.player(me).unwrap();
    assert_eq!(p.inventory.count(Item::Smelter), 1);
    assert_eq!(p.pos, target);
}
