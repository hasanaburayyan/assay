//! Reach is stated, not left to silence (ASSA-43).
//!
//! The Game Director measured that **40.7% of deposits are of a species
//! nothing in the game can mine**, 97.9% of worlds hold one and 27.9% hold one
//! in the spawn chunk. The deposits are right — an unreachable rock is a
//! promise — but an unexplained one is a bug, and until this item the only
//! thing the game said about reach was a rejection sentence that promised
//! "drills come later", which decision 7 makes false.
//!
//! These tests are about what a player is TOLD. The gate's behaviour is
//! already pinned elsewhere and deliberately not duplicated here:
//! `mining.rs::hand_mining_refuses_ore_that_is_too_hard`,
//! `tools.rs::a_drill_on_ore_too_hard_for_hands_does_nothing` and
//! `tools.rs::a_pick_does_not_unlock_ore_too_hard_for_hands`. Those three are
//! also the reason the old sentence was wrong: it promised a machine two
//! green tests say cannot exist.

use sim::tuning::HAND_MINE_MAX_HARDNESS;
use sim::{
    DepositId, Event, Input, PlayerCommand, PlayerId, RejectReason, SystemCommand, World,
    WorldConfig, step,
};

fn world(seed: u64) -> World {
    World::new(WorldConfig {
        seed,
        ..WorldConfig::default()
    })
}

/// A world with "ada" joined, standing on deposit 0, whose species is one
/// point outside the gate.
fn on_a_rock_nothing_can_mine(seed: u64) -> (World, PlayerId) {
    let mut world = world(seed);
    let me = PlayerId(0);
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    let d = world.deposit(DepositId(0)).unwrap();
    let (center, species) = (d.center, d.species);
    world.player_mut(me).unwrap().pos = center;
    world.species_mut(species).sheet.hardness = HAND_MINE_MAX_HARDNESS as u8 + 1;
    (world, me)
}

/// The decision, both directions, over every deposit of 200 worlds.
///
/// **BOTH DIRECTIONS ON PURPOSE.** A note that fired on everything would pass
/// a test that only checked the unreachable ones, and would also put "nothing
/// can mine this" on the starter deposit the ladder guarantees.
#[test]
fn a_deposit_has_a_reach_note_exactly_when_nothing_can_mine_it() {
    let (mut noted, mut quiet) = (0, 0);
    for seed in 1..200 {
        let w = world(seed);
        for d in &w.deposits {
            let minable = sim::ladder::hand_minable(w.species(d.species));
            match sim::debug::deposit_reach_note(&w, d) {
                Some(why) => {
                    assert!(!minable, "seed {seed} deposit {} is minable", d.id.0);
                    assert!(
                        why.contains(w.species(d.species).name()),
                        "a player must be told WHICH rock: {why}"
                    );
                    noted += 1;
                }
                None => {
                    assert!(minable, "seed {seed} deposit {} says nothing", d.id.0);
                    quiet += 1;
                }
            }
        }
    }
    // NON-VACUITY: this file is worthless if the sweep never meets either
    // case. The Game Director's figure is ~40% unreachable, so both counts
    // must be large.
    assert!(noted > 500, "too few unreachable deposits seen: {noted}");
    assert!(quiet > 500, "too few reachable deposits seen: {quiet}");
}

/// The listing is where a player compares rocks, so it is the worst place for
/// reach to be missing — and the control half matters as much: the rows that
/// yield must stay exactly as they were.
#[test]
fn the_deposit_listing_names_reach_on_the_dead_rows_and_only_those() {
    let w = world(9);
    let table = sim::debug::deposit_table(&w);
    let mut checked = 0;
    for d in &w.deposits {
        let row = table
            .lines()
            .find(|l| l.split_whitespace().next() == Some(&d.id.0.to_string()))
            .unwrap_or_else(|| panic!("deposit {} has no row", d.id.0));
        let says_reach = row.contains("too hard for anything you can build");
        assert_eq!(
            says_reach,
            !sim::ladder::hand_minable(w.species(d.species)),
            "row disagrees with the gate: {row}"
        );
        checked += 1;
    }
    assert!(checked > 10, "only {checked} rows in the listing");
}

/// A drill and the rock under it must not tell two different stories. Before
/// this item they already agreed by accident; they agree by construction now,
/// because both read `deposit_reach_note`.
#[test]
fn a_drill_and_the_rock_under_it_give_the_same_reason() {
    let (world, _me) = on_a_rock_nothing_can_mine(9);
    let d = world.deposit(DepositId(0)).unwrap();
    let why = sim::debug::deposit_reach_note(&world, d).expect("out of reach");
    assert!(
        why.contains(world.species(d.species).name()),
        "names the rock: {why}"
    );
    assert!(
        why.contains(&HAND_MINE_MAX_HARDNESS.to_string()),
        "names the gate: {why}"
    );
}

/// **THE SENTENCE THE GAME ALREADY HAD, AND THE PROMISE IT BROKE.**
///
/// A refused mine has always produced a worded event — `event_line` is what
/// both hosts render, so this reaches the Godot log and the terminal alike. It
/// said "drills come later". Decision 7 holds `mine_by_machine` to the same
/// gate, so no drill ever comes, and two green tests in `tools.rs` prove it.
/// The one explanation the game gave was the one thing it got wrong.
#[test]
fn a_refused_mine_says_why_and_promises_no_drill() {
    let (mut world, me) = on_a_rock_nothing_can_mine(9);
    let mut events = Vec::new();
    step(
        &mut world,
        &[Input::player(me, PlayerCommand::Mine)],
        &mut events,
    );
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: PlayerCommand::Mine,
            reason: RejectReason::TooHardForHands,
        }],
        "the swing must be refused, or this test is about nothing"
    );

    let line = sim::debug::event_line(&world, Some(me), &events[0]);
    assert!(
        line.contains(&HAND_MINE_MAX_HARDNESS.to_string()),
        "the player is told the gate: {line}"
    );
    // THE GUARD WATCHES THE CLASS, NOT THE PHRASE WE ALREADY DELETED (Game
    // Director's wording ruling on ASSA-43). The first fix for "drills come
    // later" read "so nothing reaches it yet", and a test pinned to the old
    // five words was green about it: "yet" is the same promise, one word long.
    // So refuse the whole family. Any of these turns a statement of fact into
    // a thing to wait for, and decision 7 says nothing arrives.
    for promise in PROMISES_OF_A_LATER_DRILL {
        assert!(
            !line.to_lowercase().contains(promise),
            "decision 7: no drill ever reaches this, so the sentence may not \
             hint that one is coming -- found {promise:?} in: {line}"
        );
    }
    assert!(
        line.contains("drill"),
        "say what a drill does change, or 'too hard' reads as 'build a drill': {line}"
    );
}

/// Words that make a flat refusal sound like a wait. Checked case-insensitively
/// against every reach sentence, because the one thing this family of strings
/// must never do is imply a later unlock.
const PROMISES_OF_A_LATER_DRILL: &[&str] = &[
    "later",
    "yet",
    "soon",
    "eventually",
    "for now",
    "until",
    "once you",
    "come back",
];

/// Every reach sentence, not only the rejection, held to the same bar: the
/// deposit note and the species row are read more often than the refusal is.
#[test]
fn no_reach_sentence_promises_a_later_unlock() {
    let (world, _me) = on_a_rock_nothing_can_mine(9);
    let d = world.deposit(DepositId(0)).unwrap();
    let mut sentences = vec![sim::debug::deposit_reach_note(&world, d).expect("out of reach")];
    for s in &world.species {
        if !sim::ladder::hand_minable(s) {
            let table = sim::debug::species_table(&world);
            if let Some(row) = table.lines().find(|l| l.contains(s.name())) {
                sentences.push(row.to_string());
            }
        }
    }
    assert!(
        sentences.len() > 1,
        "this test is about nothing without an unmineable species"
    );
    for sentence in &sentences {
        for promise in PROMISES_OF_A_LATER_DRILL {
            assert!(
                !sentence.to_lowercase().contains(promise),
                "found {promise:?}, which reads as a later unlock, in: {sentence}"
            );
        }
    }
}

/// The species table's only cue used to be the PRESENCE of "hand-minable" on
/// the rows that are, and absence is not a cue — half the roster said nothing
/// at all about whether it could be used.
#[test]
fn every_species_row_says_whether_it_can_be_mined() {
    let w = world(9);
    let table = sim::debug::species_table(&w);
    for s in &w.species {
        let row = table
            .lines()
            .find(|l| l.contains(s.name()))
            .unwrap_or_else(|| panic!("{} has no row", s.name()));
        if sim::ladder::hand_minable(s) {
            assert!(row.contains("hand-minable"), "{row}");
        } else {
            assert!(row.contains("too hard"), "{row}");
        }
    }
}
