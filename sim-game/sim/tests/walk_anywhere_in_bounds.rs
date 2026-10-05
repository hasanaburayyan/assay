//! **IN ASSAY YOU WALK ANYWHERE IN BOUNDS.** A design call the Game Director
//! owns (ASSA-215, 10-05), pinned here because a renderer now rests on it.
//!
//! The close-up draws the tile you clicked in the frame you clicked it, from
//! your own local click, before any bundle comes back (ASSA-215). That mark is
//! a promise: *you are going there*. It is honest only while `MoveTo` is
//! refused for being off the map and for nothing else — `step.rs` rejects it
//! with `RejectReason::OutOfBounds` alone, and the client bounds-checks the
//! tile before submitting, so today a refused walk is not a state a click can
//! reach.
//!
//! **THAT IS WHY THIS FILE IS A TRIPWIRE AND NOT A DUPLICATE.** Maren refused
//! to tick the clause by unreachability, and she was right: add impassable
//! terrain, a reach limit on walking, or a rule that you cannot stand where a
//! machine stands, and `MoveTo` gains a second reject reason. The mark would
//! then promise a walk the sim refuses, and nothing would go red. These tests
//! go red instead, and whoever adds that rule has to answer the mark.
//!
//! Not duplicated here, deliberately: `player.rs::moving_off_the_map_is_
//! rejected` (the one-tile negative) and `player.rs::stop_halts_the_player`
//! (what a walk does once accepted). This file is about the *set* of
//! acceptable targets, which no other test states.

use sim::{
    Building, BuildingId, BuildingKind, Event, Grade, Input, Item, ItemKind, Machine, Mount, Part,
    PartKind, PlayerCommand, PlayerId, RejectReason, SpeciesId, TilePos, World, WorldConfig, step,
};
use std::collections::BTreeSet;

fn world(seed: u64) -> World {
    World::new(WorldConfig {
        seed,
        ..WorldConfig::default()
    })
}

fn joined(seed: u64) -> (World, PlayerId) {
    let mut w = world(seed);
    step(
        &mut w,
        &[Input::System(sim::SystemCommand::AddPlayer {
            name: "ada".into(),
        })],
        &mut Vec::new(),
    );
    (w, PlayerId(0))
}

/// Walk to `targets` in one tick and report what the sim said about each.
///
/// One tick per batch, and every command in it is applied before
/// `move_players` runs (`step.rs:41-54`), so the body cannot move out from
/// under the batch: the tile the player stands on is the same for all of them.
/// Returns `(accepted, rejected)` — accepted being the `to` of every
/// `MoveStarted`, plus the standing tile, which is accepted *silently*
/// (`step.rs` sets `target = None` and emits nothing: you are already there).
fn walk_to_each(
    w: &mut World,
    me: PlayerId,
    targets: &[TilePos],
) -> (BTreeSet<(i32, i32)>, Vec<(TilePos, RejectReason)>) {
    let standing = w.player(me).unwrap().pos;
    let inputs: Vec<Input> = targets
        .iter()
        .map(|t| Input::player(me, PlayerCommand::MoveTo { target: *t }))
        .collect();
    let mut events = Vec::new();
    step(w, &inputs, &mut events);

    let mut accepted = BTreeSet::new();
    let mut rejected = Vec::new();
    for e in &events {
        match e {
            Event::MoveStarted { to, .. } => {
                accepted.insert((to.x, to.y));
            }
            Event::CommandRejected {
                command: PlayerCommand::MoveTo { target },
                reason,
                ..
            } => rejected.push((*target, reason.clone())),
            _ => {}
        }
    }
    if targets.contains(&standing) {
        accepted.insert((standing.x, standing.y));
    }
    (accepted, rejected)
}

/// **THE WHOLE MAP, TILE BY TILE.** Not a sample: all 16384 in-bounds tiles of
/// the demo seed, each one named as a `MoveTo` target and each one accepted.
///
/// Exhaustive because the rule this guards is about *which* tiles, and a
/// sample is chosen by the person who already believes the answer. The demo
/// seed carries 13 deposits, a spawn pad and species nothing can mine; a rule
/// that made any of those unwalkable would have to walk over this test.
#[test]
fn every_in_bounds_tile_of_the_demo_seed_is_an_acceptable_walk_target() {
    let (mut w, me) = joined(14247);
    let (width, height) = (w.width(), w.height());
    assert_eq!(
        (width, height),
        (128, 128),
        "the default world is 8x8 chunks"
    );

    let mut swept = 0;
    for y in 0..height {
        let row: Vec<TilePos> = (0..width).map(|x| TilePos::new(x, y)).collect();
        let (accepted, rejected) = walk_to_each(&mut w, me, &row);
        assert!(
            rejected.is_empty(),
            "row {y}: the sim refused {} in-bounds tiles, first {:?}. \
             If a walk now has a second reject reason, the close-up's \
             destination mark (ASSA-215) promises a walk that will not \
             happen: answer that before changing this test.",
            rejected.len(),
            rejected.first()
        );
        let expected: BTreeSet<(i32, i32)> = row.iter().map(|t| (t.x, t.y)).collect();
        assert_eq!(
            accepted, expected,
            "row {y}: every tile in the row must be accepted, loudly or silently"
        );
        swept += row.len();
    }
    assert_eq!(swept, 16384, "the sweep covered the whole map");
}

/// The same sweep on the other two seeds the studio pins, one row of tiles at
/// a time but over every row: worldgen cannot roll a tile you may not walk to.
///
/// 777042 is the 13-disc world the art checks use and 2191 is the worst-case
/// bench. Three seeds rather than one because the tiles worldgen *places*
/// differ per seed, and the rule is about the map, not about one map.
#[test]
fn the_other_pinned_seeds_hold_the_same_rule() {
    for seed in [777042, 2191] {
        let (mut w, me) = joined(seed);
        for y in 0..w.height() {
            let row: Vec<TilePos> = (0..w.width()).map(|x| TilePos::new(x, y)).collect();
            let (accepted, rejected) = walk_to_each(&mut w, me, &row);
            assert!(
                rejected.is_empty(),
                "seed {seed} row {y}: refused {:?}",
                rejected.first()
            );
            assert_eq!(accepted.len(), row.len(), "seed {seed} row {y}");
        }
    }
}

/// **A TILE WITH SOMETHING ON IT IS STILL A TILE YOU MAY WALK TO.** The three
/// occupants worldgen never produces, so the sweep above cannot see them: a
/// planted machine, another player, and yourself.
///
/// This is the case a future rule is most likely to take away ("you cannot
/// stand where a smelter stands"), and the one the mark would then lie about
/// most often, because a machine is exactly what you click near.
#[test]
fn a_machine_another_player_or_your_own_tile_are_all_walkable() {
    let (mut w, me) = joined(14247);
    step(
        &mut w,
        &[Input::System(sim::SystemCommand::AddPlayer {
            name: "grace".into(),
        })],
        &mut Vec::new(),
    );
    let you = PlayerId(1);

    let spawn = w.spawn_tile();
    let machine_tile = TilePos::new(spawn.x + 4, spawn.y + 4);
    let material = Item::new(ItemKind::Refined, SpeciesId(0), Grade::B);
    let drill = sim::Assembly::new(
        Part::of(PartKind::Frame(Mount::Planted), material),
        vec![Part::of(PartKind::Head, material)],
    );
    w.buildings.push(Building {
        id: BuildingId(0),
        pos: machine_tile,
        material,
        kind: BuildingKind::Machine(Machine::new(drill)),
    });

    let other_tile = TilePos::new(spawn.x - 3, spawn.y + 2);
    w.player_mut(you).unwrap().pos = other_tile;
    let standing = w.player(me).unwrap().pos;

    let targets = [machine_tile, other_tile, standing];
    let (accepted, rejected) = walk_to_each(&mut w, me, &targets);
    assert!(
        rejected.is_empty(),
        "an occupied in-bounds tile is still walkable; refused {:?}",
        rejected
    );
    for t in targets {
        assert!(
            accepted.contains(&(t.x, t.y)),
            "{t:?} was neither started nor already-there"
        );
    }
    assert_eq!(
        w.player(me).unwrap().target,
        None,
        "the last of the three was the tile under the player, which clears the target"
    );
}

/// **THE OTHER DIRECTION, WHICH IS WHAT MAKES THE SWEEP A MEASUREMENT.** Off
/// the map is refused, with `OutOfBounds` and no other reason, on all four
/// sides and at a corner. Without this half, a sim that accepted *everything*
/// — including the tiles the client's own bounds check exists to catch — would
/// pass the sweep.
#[test]
fn off_the_map_is_refused_and_out_of_bounds_is_the_only_reason() {
    let (mut w, me) = joined(14247);
    let (width, height) = (w.width(), w.height());
    let outside = [
        TilePos::new(-1, 0),
        TilePos::new(0, -1),
        TilePos::new(width, 0),
        TilePos::new(0, height),
        TilePos::new(width, height),
        TilePos::new(i32::MIN, i32::MAX),
    ];
    let (accepted, rejected) = walk_to_each(&mut w, me, &outside);
    assert!(
        accepted.is_empty(),
        "no tile off the map may start a walk, got {accepted:?}"
    );
    assert_eq!(rejected.len(), outside.len(), "each one is refused once");
    let reasons: BTreeSet<String> = rejected.iter().map(|(_, r)| format!("{r:?}")).collect();
    assert_eq!(
        reasons,
        BTreeSet::from(["OutOfBounds".to_string()]),
        "OutOfBounds is the only reason a walk is ever refused; a second one \
         means the destination mark needs an answer first (ASSA-215 box 4)"
    );
    assert_eq!(
        w.player(me).unwrap().pos,
        w.spawn_tile(),
        "a refused walk moves nobody"
    );
}
