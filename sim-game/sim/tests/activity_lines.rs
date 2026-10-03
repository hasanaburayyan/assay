//! What a player has running, as the sim words it (ASSA-95).
//!
//! Three self-running activities live on `Player` — `mining`, `assaying`,
//! `crafting` — and until this only the craft had a sentence. The item is
//! Maren's, and so is the shape: every live activity named, never ranked, in
//! `step`'s own system order, with a countdown only where there is an end.
//!
//! **THE TESTS ARE ABOUT PLURALITY MORE THAN WORDING.** Her correction to her
//! own filing is the whole reason this is a list: an assay costs nothing in the
//! common case because you mine straight through it, so a readout that showed
//! "whichever activity is running" would report that the mining had stopped.

use sim::debug;
use sim::tuning::{ASSAY_TICKS, HAND_MINE_MAX_HARDNESS};
use sim::{
    DepositId, Grade, Input, Item, ItemKind, PlayerCommand, PlayerId, RecipeId, SystemCommand,
    TilePos, World, WorldConfig, step,
};

fn world_with_player(seed: u64) -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed,
        ..WorldConfig::default()
    });
    for s in &mut world.species {
        s.sheet.hardness = s.sheet.hardness.min(HAND_MINE_MAX_HARDNESS as u8);
    }
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

fn stand_on(world: &mut World, me: PlayerId, id: DepositId) -> TilePos {
    let center = world.deposit(id).unwrap().center;
    world.player_mut(me).unwrap().pos = center;
    center
}

/// NOTHING RUNNING IS AN EMPTY LIST, not a sentence saying so. Whether idleness
/// deserves words is a host's question about a panel; the sim reports what is.
#[test]
fn a_player_doing_nothing_has_no_lines() {
    let (world, me) = world_with_player(9);
    assert!(debug::activity_lines(&world, me).is_empty());
    // And a player this world does not have is not a panic.
    assert!(debug::activity_lines(&world, PlayerId(7)).is_empty());
}

/// **THE MEASUREMENT THIS ITEM TURNS ON.** Mining and assaying run on the same
/// tile at the same time, because `step` keeps them in independent fields. Both
/// lines, in `step`'s order, or the readout lies about one of them.
#[test]
fn mining_and_assaying_at_once_are_both_named_in_the_systems_order() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    stand_on(&mut world, me, id);
    let species = world
        .species(world.deposit(id).unwrap().species)
        .name()
        .to_string();

    step(
        &mut world,
        &[
            Input::player(me, PlayerCommand::Mine),
            Input::player(me, PlayerCommand::Assay),
        ],
        &mut Vec::new(),
    );
    assert!(
        world.player(me).unwrap().mining.is_some() && world.player(me).unwrap().assaying.is_some(),
        "the premise: both activities are live, or this test proves nothing"
    );

    let lines = debug::activity_lines(&world, me);
    assert_eq!(lines.len(), 2, "{lines:?}");
    assert!(lines[0].starts_with("mining"), "{lines:?}");
    assert!(lines[1].starts_with("assaying"), "{lines:?}");
    assert!(lines.iter().all(|l| l.contains(&species)), "{lines:?}");
}

/// A COUNTDOWN ONLY WHERE THERE IS AN END. The assay's number is the sim's own
/// `ASSAY_TICKS` minus what it has spent, read back as it falls.
#[test]
fn the_assay_counts_down_from_the_sims_own_constant() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    stand_on(&mut world, me, id);
    step(
        &mut world,
        &[Input::player(me, PlayerCommand::Assay)],
        &mut Vec::new(),
    );
    let first = assay_line(&world, me);
    for _ in 0..5 {
        step(&mut world, &[], &mut Vec::new());
    }
    let later = assay_line(&world, me);

    let spent = world.player(me).unwrap().assaying.unwrap().progress;
    assert!(
        later.contains(&format!("{} ticks left", ASSAY_TICKS - spent)),
        "the figure is the sim's arithmetic, not a count of calls: {later}"
    );
    assert_ne!(first, later, "it did not move in five ticks");
}

/// **HAND MINING CARRIES NO NUMBER, AND THE ABSENCE IS THE FACT** (Maren's
/// ruling). It repeats until you stop or the deposit runs dry, so a countdown
/// would promise an end that never comes — and the 4-tick cycle restarting is
/// not progress towards anything a player cares about.
#[test]
fn the_mining_line_promises_no_end() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    stand_on(&mut world, me, id);
    step(
        &mut world,
        &[Input::player(me, PlayerCommand::Mine)],
        &mut Vec::new(),
    );
    for _ in 0..3 {
        step(&mut world, &[], &mut Vec::new());
    }

    let lines = debug::activity_lines(&world, me);
    assert_eq!(lines.len(), 1, "{lines:?}");
    assert!(
        !lines[0].chars().any(|c| c.is_ascii_digit()),
        "a mining line with a number in it is a countdown to nothing: {}",
        lines[0]
    );
    assert!(lines[0].starts_with("mining "), "{}", lines[0]);
}

/// THE CRAFT LINE IS `crafting_readout`'S OWN SENTENCE, byte for byte. Two
/// wordings for one fact is the disagreement nobody notices — the reason that
/// function was pulled into `debug` in the first place (ASSA-49).
#[test]
fn the_craft_line_is_the_readout_that_already_existed() {
    let (mut world, me) = world_with_player(9);
    let ore = Item::new(
        ItemKind::Ore,
        world.deposit(DepositId(0)).unwrap().species,
        Grade::B,
    );
    world.player_mut(me).unwrap().inventory.add(ore, 9);
    step(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Craft {
                recipe: RecipeId::Sort,
                item: ore,
                count: 2,
            },
        )],
        &mut Vec::new(),
    );

    let readout = debug::crafting_readout(&world, me).expect("a craft is running");
    assert_eq!(debug::activity_lines(&world, me), vec![readout]);
}

/// ALL THREE AT ONCE, which is the state the surface has to survive: the demo's
/// own player stands on a deposit, mines it, assays it and sorts what they
/// already hold. Order is `step`'s, and nothing is dropped for being third.
#[test]
fn three_live_activities_give_three_lines_and_none_is_ranked_away() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    stand_on(&mut world, me, id);
    let ore = Item::new(ItemKind::Ore, world.deposit(id).unwrap().species, Grade::B);
    world.player_mut(me).unwrap().inventory.add(ore, 9);
    step(
        &mut world,
        &[
            Input::player(me, PlayerCommand::Mine),
            Input::player(me, PlayerCommand::Assay),
            Input::player(
                me,
                PlayerCommand::Craft {
                    recipe: RecipeId::Sort,
                    item: ore,
                    count: 1,
                },
            ),
        ],
        &mut Vec::new(),
    );

    let lines = debug::activity_lines(&world, me);
    assert_eq!(lines.len(), 3, "{lines:?}");
    assert!(lines[0].starts_with("mining"), "{lines:?}");
    assert!(lines[1].starts_with("assaying"), "{lines:?}");
    assert!(lines[2].starts_with("making"), "{lines:?}");
}

fn assay_line(world: &World, me: PlayerId) -> String {
    debug::activity_lines(world, me)
        .into_iter()
        .find(|l| l.starts_with("assaying"))
        .expect("an assay is running")
}
