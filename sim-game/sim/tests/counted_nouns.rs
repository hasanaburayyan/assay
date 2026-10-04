//! **A COUNT AND ITS NOUN AGREE, EVERYWHERE A PLAYER CAN SEE ONE** (ASSA-145).
//!
//! `1 players` was the second line of every screenshot of Assay that exists,
//! including the ones the board has looked at: solo is `Play solo`, which is how
//! every window shot was made and how a stranger opens the game. The Game
//! Director filed it as the same defect as `5 of your 3 Tonore ore` — A SENTENCE
//! THAT ONLY READS IN THE GOOD CASE IS A DEFECT (`assay-rulings` §2) — and the
//! codebase already held the rule in two places and missed it in four.
//!
//! THE POINT OF THIS FILE IS THE VALUE 1. Every assertion below drives a count
//! to exactly one, because every one of these sentences was already correct at
//! 0 and at 2 and had been printing for weeks.

use sim::debug::counted;
use sim::{Grade, Item, ItemKind, PlayerCommand, RecipeId, SpeciesId};

const X: SpeciesId = SpeciesId(0);

/// A player at spawn with a placed smelter beside them. The smaller twin of
/// `tests/smelter.rs::world_with_smelter`, inline because that one is private
/// and making it `pub` to borrow it would edit a file this change has no
/// business in. Nothing here decides a rule: the smelter is placed by the real
/// `Place` command and the status sentence comes from `sim::debug`.
fn world_with_smelter() -> (sim::World, sim::PlayerId, sim::BuildingId) {
    let mut world = sim::World::new(sim::WorldConfig {
        seed: 9,
        ..sim::WorldConfig::default()
    });
    let mut events = Vec::new();
    sim::step::step(
        &mut world,
        &[sim::Input::System(sim::SystemCommand::AddPlayer {
            name: "marlow".into(),
        })],
        &mut events,
    );
    let me = sim::PlayerId(0);
    let smelter = Item::new(ItemKind::Smelter, X, Grade::C);
    world
        .player_mut(me)
        .expect("the player joined")
        .inventory
        .add(smelter, 1);
    let spawn = world.spawn_tile();
    let pos = sim::TilePos::new(spawn.x + 1, spawn.y);
    sim::step::step(
        &mut world,
        &[sim::Input::player(
            me,
            PlayerCommand::Place { item: smelter, pos },
        )],
        &mut events,
    );
    let id = sim::BuildingId(0);
    assert!(
        world.building(id).is_some(),
        "the smelter was not placed: {events:?}"
    );
    (world, me, id)
}

/// THE HELPER ITSELF, at the three values that matter. Zero is PLURAL, which is
/// English and not an oversight.
#[test]
fn one_is_singular_and_zero_is_not() {
    assert_eq!(counted(1, "player", "players"), "1 player");
    assert_eq!(counted(0, "player", "players"), "0 players");
    assert_eq!(counted(2, "player", "players"), "2 players");
    // TWO FORMS AND NOT A SUFFIX RULE: `species` is why. A helper that appended
    // an "s" would be wrong here and nowhere a test would notice.
    assert_eq!(counted(1, "species", "species"), "1 species");
    assert_eq!(counted(6, "species", "species"), "6 species");
    // Large counts are not special-cased into a word.
    assert_eq!(counted(210, "ore", "ore"), "210 ore");
}

/// **`1 ticks burning` WAS REAL AND WAS PRINTED**, not hypothetical: the Game
/// Director's run of `maren_lit_probe.gd` on seed 14247 printed, at tick 471,
/// `fuel 8 Remdornite ore (B) (1 ticks burning at 45)`.
///
/// Driven through the REAL `building_status` on a real placed smelter, walking
/// `burn_left` down through 2, 1 and 0, because the defect is a clause inside
/// that sentence and a helper asserted on its own would not prove the sentence
/// calls it.
#[test]
fn a_smelter_with_one_tick_of_fuel_left_says_one_tick() {
    let (mut world, _me, id) = world_with_smelter();
    let mut said = Vec::new();
    for burn in [5u32, 2, 1, 0] {
        {
            let b = world.building_mut(id).expect("the smelter is there");
            let sim::BuildingKind::Smelter(s) = &mut b.kind else {
                panic!("the fixture places a smelter")
            };
            s.burn_left = burn;
            s.burn_temperature = 60;
        }
        let b = world.building(id).expect("the smelter is there");
        said.push((burn, sim::debug::building_status(&world, b)));
    }
    for (burn, line) in &said {
        let want = if *burn == 1 {
            "(1 tick burning at 60)".to_string()
        } else {
            format!("({burn} ticks burning at 60)")
        };
        assert!(
            line.contains(&want),
            "burn_left {burn}: wanted {want:?} in {line:?}"
        );
    }
    // THE PREMISE: the four states must really have produced four sentences, or
    // a fixture that silently failed to set `burn_left` would pass every
    // assertion above by printing the same line four times.
    let distinct: std::collections::BTreeSet<&String> = said.iter().map(|(_, l)| l).collect();
    assert_eq!(distinct.len(), 4, "the fixture printed one line: {said:?}");
}

/// **`1 ticks left` ARRIVES ON THE LAST TICK OF EVERY CRAFT**, so this is the
/// most frequently seen of the four.
///
/// Stepped to that tick through the real recipe rather than asserted against a
/// number I chose: `crafting_readout` is the only place that composes it, and a
/// craft that ends a tick earlier or later would make a hand-picked count pass
/// while the player still read `1 ticks left`.
#[test]
fn the_last_tick_of_a_craft_says_one_tick_left() {
    let (mut w, me, _id) = world_with_smelter();
    let ore = Item::new(ItemKind::Ore, X, Grade::C);
    w.player_mut(me).expect("player").inventory.add(ore, 20);
    let ticks = RecipeId::Smelter.recipe().ticks;
    let mut events = Vec::new();
    sim::step::step(
        &mut w,
        &[sim::Input::player(
            me,
            PlayerCommand::Craft {
                recipe: RecipeId::Smelter,
                item: ore,
                count: 1,
            },
        )],
        &mut events,
    );
    // One tick short of done: `ticks` total, and the readout says what is LEFT.
    let mut lines = Vec::new();
    for _ in 0..ticks {
        lines.push(sim::debug::crafting_readout(&w, me));
        sim::step::step(&mut w, &[], &mut events);
    }
    let said: Vec<String> = lines.into_iter().flatten().collect();
    assert!(
        said.iter().any(|l| l.ends_with("1 tick left")),
        "no tick of this craft said `1 tick left`: {said:?}"
    );
    // ENDS WITH, NOT CONTAINS, and the difference bit me: "11 ticks left" and
    // "21 ticks left" both CONTAIN "1 ticks left", so a `contains` version of
    // this reddened against correct output on its first run.
    assert!(
        !said.iter().any(|l| l.ends_with(": 1 ticks left")),
        "a tick of this craft said `1 ticks left`: {said:?}"
    );
    // THE PREMISE: if the craft were one tick long, the plural case would never
    // appear and the negative assertion above would be free.
    assert!(
        said.iter().any(|l| l.contains(" ticks left")),
        "this craft never had a plural tick count, so it proves nothing: {said:?}"
    );
}
