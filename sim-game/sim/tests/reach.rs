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

    // ASSA-52 PUT TWO MORE SENTENCES IN THIS FAMILY, so they are held to the
    // same bar. "a hotter fire would smelt it" is exactly the kind of true
    // statement that becomes a promise in the reading, and rung one — which
    // would be that fire — is not in the demo.
    let mut dead_ends = 0;
    for seed in 1..60 {
        let w = host_world(seed);
        let table = sim::debug::species_table(&w);
        for dep in &w.deposits {
            let s = w.species(dep.species);
            if sim::ladder::hand_minable(s)
                && !sim::ladder::usable_from_bare_hands(&w.species, dep.species)
            {
                sentences.push(
                    sim::debug::deposit_dead_end_note(&w, dep).expect("an unsmeltable dead end"),
                );
                if let Some(row) = table.lines().find(|l| l.contains(s.name())) {
                    sentences.push(row.to_string());
                }
                dead_ends += 1;
            }
        }
    }
    assert!(
        dead_ends > 20,
        "the ASSA-52 half of this guard saw only {dead_ends} dead ends"
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

// ---------------------------------------------------------------------------
// ASSA-52: the quieter dead end — minable, and impossible to smelt.
// ---------------------------------------------------------------------------

/// The world shape the hosts and CI actually build. `world()` above uses
/// `WorldConfig::default()`, which is 8x8 — fine for sweeping a property, but
/// a different world for the same seed, and seed 10027 below is cited by the
/// Game Director at 6x4. I measured that difference rather than assuming the
/// default was the shipped shape.
fn host_world(seed: u64) -> World {
    World::new(WorldConfig {
        seed,
        width_chunks: 6,
        height_chunks: 4,
    })
}

/// **EXHAUSTIVE AND THREE-WAY.** Every deposit is in exactly one of three
/// states, and the sentence has to match the state: too hard to break, minable
/// but impossible to smelt, or usable. A test that only checked the middle case
/// would pass while the note appeared on rock that yields.
#[test]
fn a_deposit_says_when_it_can_be_mined_but_never_smelted() {
    let (mut too_hard, mut unsmeltable, mut usable) = (0, 0, 0);
    for seed in 1..200 {
        let w = host_world(seed);
        for d in &w.deposits {
            let s = w.species(d.species);
            let note = sim::debug::deposit_dead_end_note(&w, d);
            if !sim::ladder::hand_minable(s) {
                let note = note.unwrap_or_else(|| panic!("seed {seed}: silent unbreakable rock"));
                assert!(note.contains("too hard"), "{note}");
                too_hard += 1;
            } else if !sim::ladder::usable_from_bare_hands(&w.species, d.species) {
                let note = note.unwrap_or_else(|| panic!("seed {seed}: silent unsmeltable rock"));
                assert!(
                    note.contains("can be mined but not smelted"),
                    "a minable rock must not be described as unbreakable: {note}"
                );
                assert!(
                    note.contains(s.name()),
                    "a player must be told WHICH rock: {note}"
                );
                unsmeltable += 1;
            } else {
                assert_eq!(
                    note, None,
                    "seed {seed}: a rock that yields must say nothing at all"
                );
                usable += 1;
            }
        }
    }
    // NON-VACUITY ON ALL THREE ARMS. The Game Director measured ~13.6% of
    // deposits unsmeltable over 2000 worlds; I measure about 14% over these
    // 199, which is the same figure inside sampling noise.
    assert!(too_hard > 200, "too few unbreakable: {too_hard}");
    assert!(unsmeltable > 200, "too few unsmeltable: {unsmeltable}");
    assert!(usable > 200, "too few usable: {usable}");
}

/// **HARDNESS WINS, AND BOTH ARMS ARE REACHABLE** (Game Director's precedence
/// ruling). One world, one variable: the same species is made unsmeltable and
/// then its hardness is moved across the gate, so the test cannot pass by
/// having only one sentence implemented.
///
/// **THE PRECEDENCE ITSELF IS NOT WHAT THIS PROVES, AND I MEASURED THAT.**
/// Reversing the two arms in `deposit_dead_end_note` reddens nothing, because
/// they are mutually exclusive by construction: "unsmeltable" is only defined
/// for rock you can mine, so a rock over the hardness gate never matches the
/// second arm whatever order they are tried in. The ordering reads as the
/// ruling and costs nothing, but it is belt-and-braces rather than
/// load-bearing — and a player can therefore never be handed both sentences,
/// which is the thing the ruling was actually protecting. What this test does
/// prove is that each arm fires on its own case and neither leaks into the
/// other's.
#[test]
fn hardness_wins_when_a_rock_is_both_too_hard_and_unsmeltable() {
    let mut world = host_world(9);
    let d = world.deposit(DepositId(0)).unwrap();
    let (id, species) = (d.id, d.species);
    // Hotter than anything can reach, so it can never be smelted.
    world.species_mut(species).sheet.heat_tolerance = 100;
    world.species_mut(species).sheet.hardness = HAND_MINE_MAX_HARDNESS as u8 + 1;
    assert!(
        !sim::ladder::usable_from_bare_hands(&world.species, species),
        "the test's own premise: this rock must be unsmeltable either way"
    );

    let note =
        sim::debug::deposit_dead_end_note(&world, world.deposit(id).unwrap()).expect("a dead end");
    assert!(note.contains("too hard"), "hardness comes first: {note}");
    assert!(
        !note.contains("not smelted"),
        "two problems where the player has one, and the one they have is the \
         swing that will not land: {note}"
    );

    // Now it can be broken, and only the heat is left.
    world.species_mut(species).sheet.hardness = 10;
    let note = sim::debug::deposit_dead_end_note(&world, world.deposit(id).unwrap())
        .expect("still a dead end");
    assert!(
        note.contains("can be mined but not smelted"),
        "the second arm must exist: {note}"
    );
}

/// Bare "hand-minable" read as a promise about the ore when it is only a fact
/// about the swing.
#[test]
fn the_species_row_never_says_bare_hand_minable_for_a_dead_end() {
    let mut checked = 0;
    for seed in 1..60 {
        let w = host_world(seed);
        let table = sim::debug::species_table(&w);
        for s in &w.species {
            if !sim::ladder::hand_minable(s) {
                continue;
            }
            let row = table
                .lines()
                .find(|l| l.contains(s.name()))
                .unwrap_or_else(|| panic!("{} has no row", s.name()));
            if sim::ladder::usable_from_bare_hands(&w.species, s.id) {
                assert!(row.contains("hand-minable"), "{row}");
                assert!(!row.contains("not smeltable"), "{row}");
            } else {
                assert!(
                    row.contains("not smeltable"),
                    "a dead end must say so: {row}"
                );
                checked += 1;
            }
        }
    }
    assert!(checked > 20, "only {checked} dead-end rows seen");
}

/// **A DRILL ON AN UNSMELTABLE ROCK IS WORKING, NOT IDLE**, and that is a
/// deliberate choice rather than an oversight: `machine_status` reads
/// `deposit_reach_note` and not the dead-end note. The hopper fills; the ore
/// is a dead end; the rock's own line says so. A machine reports what the
/// machine is doing.
///
/// **THIS PINS THE MECHANISM, NOT THE PANEL.** It asserts what
/// `machine_status` is handed, which is not the same as asserting what it
/// prints — a caller could stop asking and this would stay green. The panel's
/// own text is asserted in `tools.rs::the_panel_names_every_reason_a_drill_is_
/// not_mining`, which has a real planted drill to read it from.
#[test]
fn a_drill_on_an_unsmeltable_rock_does_not_claim_to_be_idle() {
    let mut world = host_world(9);
    let species = world.deposit(DepositId(0)).unwrap().species;
    world.species_mut(species).sheet.hardness = 10;
    world.species_mut(species).sheet.heat_tolerance = 100;
    assert!(
        !sim::ladder::usable_from_bare_hands(&world.species, species),
        "premise: unsmeltable"
    );
    let d = world.deposit(DepositId(0)).unwrap();
    assert!(
        sim::debug::deposit_dead_end_note(&world, d).is_some(),
        "the rock still says it is a dead end"
    );
    assert_eq!(
        sim::debug::deposit_reach_note(&world, d),
        None,
        "and reach has nothing to say, which is what keeps a working drill out \
         of the idle branch"
    );
}
