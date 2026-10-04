//! **THE GROUND LINE IS ABOUT ROCK, AND A BUILDING CANNOT MAKE IT FALSE**
//! (Game Director, ASSA-146).
//!
//! Every host words a tile the same way — the deposit, else the ground — and
//! then appends the building standing there from a separate block. "empty
//! ground" was one phrase carrying two facts, *no deposit* and *nothing here*,
//! so the cursor section read:
//!
//! ```text
//! (76, 38) · chunk (4, 2) · 1 from spawn
//! empty ground
//! Minyte smelter (B) 0 · walls 29 · in empty · fuel 9 Minyte ore (B) …
//! ```
//!
//! `debug::ground_note` says only what it can know, so the sentence is true
//! whatever else is standing on the tile. **That invariance is the test**: the
//! note is taken before and after a smelter is placed on the very same tile,
//! and the two must be the same string. A fix that instead hid the line when a
//! building was present would satisfy the complaint and lose the no-deposit
//! fact on the line ASSA-138 ruled to be where a player reads a machine's
//! capacity — so `the_note_still_names_the_deposit_fact` holds that door shut.
//!
//! The wording being the sim's is the other half, and no unit test in this
//! crate can see it: `sim-cli/tests/ground_note.rs` drives the real binary and
//! reads the host's own output.

use sim::{
    Grade, Input, Item, ItemKind, PlayerCommand, PlayerId, SpeciesId, SystemCommand, TilePos,
    World, WorldConfig, debug, step,
};

const WALLS: SpeciesId = SpeciesId(0);

/// A tile far from spawn and from every deposit, so nothing in the world has a
/// claim on it but the sentence under test.
const BARE: TilePos = TilePos { x: 60, y: 40 };

fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

/// Move every deposit off `pos`, the way `tests/building_name.rs` does: one
/// deposit per chunk means a hard-coded tile is sometimes covered, and a test
/// that silently measured the deposit branch would prove nothing.
fn clear_deposits_from(world: &mut World, pos: TilePos) {
    let corner = TilePos::new(1, 1);
    assert!(!(pos.x < 8 && pos.y < 8), "the corner must be far from pos");
    for i in 0..world.deposits.len() {
        if world.deposits[i].contains(pos) {
            world.deposits[i].center = corner;
        }
    }
    assert!(
        world.deposit_at(pos).is_none(),
        "the tile must really be bare"
    );
}

fn place_smelter(world: &mut World, me: PlayerId, pos: TilePos) {
    let item = Item::new(ItemKind::Smelter, WALLS, Grade::B);
    world.player_mut(me).unwrap().inventory.add(item, 1);
    world.player_mut(me).unwrap().pos = TilePos::new(pos.x - 1, pos.y);
    let before = world.buildings.len();
    step(
        world,
        &[Input::player(me, PlayerCommand::Place { item, pos })],
        &mut Vec::new(),
    );
    assert_eq!(
        world.buildings.len(),
        before + 1,
        "the fixture must actually place a smelter"
    );
    assert!(
        world.building_at(pos).is_some(),
        "and it must stand on the tile under test, not beside it"
    );
}

/// THE BUG, AS ONE ASSERTION. The ground line a player reads above a building
/// is the ground line they read without one.
#[test]
fn a_building_cannot_make_the_ground_line_false() {
    let (mut world, me) = world_with_player();
    clear_deposits_from(&mut world, BARE);
    let bare = debug::ground_note(&world, BARE);
    assert!(!bare.is_empty(), "a tile on the map must say something");

    place_smelter(&mut world, me, BARE);
    assert_eq!(
        debug::ground_note(&world, BARE),
        bare,
        "the note is about rock; a smelter standing here changes none of it"
    );
}

/// BOX 2 OF ASSA-146: the no-deposit fact survives the fix. The cheap way to
/// stop the contradiction was to drop the line on an occupied tile, which
/// spends this fact to buy that silence.
#[test]
fn the_note_still_names_the_deposit_fact() {
    let (mut world, _me) = world_with_player();
    clear_deposits_from(&mut world, BARE);
    let note = debug::ground_note(&world, BARE);
    assert!(
        note.contains("deposit"),
        "a player must still learn there is no deposit here, got {note:?}"
    );
    assert!(
        !note.contains("empty"),
        "and it must not claim the tile is empty of anything else, got {note:?}"
    );
}

/// WHERE THE DEPOSIT SPEAKS, THIS DOES NOT. Hosts print one ground line, so a
/// sentence here would be a second one — and it would be a lie, because the
/// tile it is about has a deposit on it.
#[test]
fn a_deposit_tile_gets_no_ground_note() {
    let (world, _me) = world_with_player();
    let covered = world
        .deposits
        .first()
        .expect("every world has deposits")
        .center;
    assert!(world.deposit_at(covered).is_some(), "fixture check");
    assert_eq!(debug::ground_note(&world, covered), "");
}

/// Spawn is unchanged, and deposit-first is unchanged with it: the word says
/// what the tile IS and never claimed to be bare, which is why it was not the
/// bug and is not part of the fix.
///
/// **TWO SEEDS, BECAUSE ONE OF THEM ONLY EVER PROVES HALF OF THIS.** Written
/// as `if deposit { "" } else { "spawn" }` against the fixture seed, this test
/// passed without the word `spawn` ever being produced — seed 9 drops a
/// deposit on its own spawn tile, so the branch the test is named after was
/// dead. The seeds are pinned to the two cases rather than searched for, and
/// each is asserted to still *be* its case.
#[test]
fn spawn_says_spawn_and_a_deposit_on_it_still_wins() {
    let bare = World::new(WorldConfig {
        seed: 2,
        ..WorldConfig::default()
    });
    let spawn = bare.spawn_tile();
    assert!(
        bare.deposit_at(spawn).is_none(),
        "seed 2 must still be the bare-spawn case"
    );
    assert_eq!(debug::ground_note(&bare, spawn), "spawn");

    let covered = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    let spawn = covered.spawn_tile();
    assert!(
        covered.deposit_at(spawn).is_some(),
        "seed 9 must still be the deposit-on-spawn case"
    );
    assert_eq!(
        debug::ground_note(&covered, spawn),
        "",
        "the deposit line is the ground line there"
    );
}

/// OFF THE MAP IT SAYS NOTHING, because the host says that instead and says it
/// with the bounds. A note here would be a claim about rock that is not there.
#[test]
fn off_the_map_has_no_ground_note() {
    let (world, _me) = world_with_player();
    let (w, h) = (world.width(), world.height());
    for off in [
        TilePos::new(-1, 0),
        TilePos::new(0, -1),
        TilePos::new(w, 0),
        TilePos::new(0, h),
    ] {
        assert!(!world.in_bounds(off), "fixture check on {off:?}");
        assert_eq!(debug::ground_note(&world, off), "", "{off:?}");
    }
}
