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

use sim::tuning::{FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, HAND_SPARK_TEMPERATURE};
use sim::{
    DepositId, Event, Grade, Input, PlayerCommand, PlayerId, Property, RejectReason, SystemCommand,
    World, WorldConfig, step,
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

    let line = sim::debug::event_line(&world, Some(me), &events[0], sim::debug::Audience::Typed);
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
    // ASSA-58 AND ASSA-59 PUT THREE MORE IN THE FAMILY. The fuel rows say what
    // a player cannot light today and the gear row says what nothing consumes
    // today, which is the same kind of sentence and the same temptation: "needs
    // a hotter fire" is one word away from promising one, and "nothing uses a
    // gear" is one word away from promising a use the alloys note only
    // discusses. The whole recipe table goes in, not the gear row alone — a
    // guard that watched one row would miss the next sentence like it.
    let w = host_world(14247);
    for row in sim::debug::species_table(&w).lines() {
        if light_sentences().iter().any(|t| row.contains(t)) {
            sentences.push(row.to_string());
        }
    }
    sentences.extend(sim::debug::recipe_table().lines().map(str::to_string));

    for sentence in &sentences {
        for promise in PROMISES_OF_A_LATER_DRILL {
            assert!(
                !sentence.to_lowercase().contains(promise),
                "found {promise:?}, which reads as a later unlock, in: {sentence}"
            );
        }
    }
}

/// **A RECIPE WHOSE OUTPUT NOTHING CONSUMES SAYS SO** (ASSA-59). A gear costs
/// 2 refined — a whole handle, two thirds of a pick, 40 ticks of the demo's
/// scarcest resource — and the table advertised it with a hardness gate that
/// read like a gated reward.
///
/// **PINNED AS A DERIVATION, NOT AS A ROW.** The clause has to appear exactly
/// where `recipe::is_consumed` is false, so that the day something consumes a
/// gear the sentence disappears on its own; a test that only checked the gear
/// row would be green for a lie.
#[test]
fn a_recipe_output_nothing_consumes_says_so() {
    let table = sim::debug::recipe_table();
    let mut unconsumed = 0;
    for r in &sim::RECIPES {
        let lines = catalogue_entry(&table, r.name);
        let row = lines[0];
        let said = lines.join("\n");
        let clause = format!("nothing uses a {}", r.output.0.name());
        if sim::recipe::is_consumed(r.output.0) {
            assert!(
                !said.contains("nothing uses"),
                "something does consume a {}, so its entry must not say otherwise: {said}",
                r.output.0.name()
            );
        } else {
            unconsumed += 1;
            assert!(
                said.contains(&clause),
                "nothing consumes a {}, and the entry has to say it: {said}",
                r.output.0.name()
            );
            // **ON ITS OWN LABELLED LINE, NEVER ON THE ROW** (ASSA-122). The
            // row's last column is `needs`, and a permanent dead end is not a
            // need. These two assertions are the pair: the sentence has to be
            // somewhere (above) and it may not be there (here).
            assert!(
                !row.contains("nothing uses"),
                "the dead end may not sit in the row's needs cell: {row}"
            );
            assert!(
                lines[1..]
                    .iter()
                    .any(|l| l.trim_start().starts_with(sim::debug::DEAD_END_LABEL)),
                "the dead end gets a line naming its kind, not a bare sentence: {said}"
            );
        }
    }
    // Non-vacuity, and the shape of the claim: exactly one output in the game
    // is a dead end today, and it is the gear.
    assert_eq!(
        unconsumed, 1,
        "one recipe output is consumed by nothing; if that changed, say which in the commit"
    );
    assert!(
        table.contains("nothing uses a gear"),
        "and it is the gear:\n{table}"
    );
}

/// A recipe's WHOLE ENTRY in the catalogue: its row, plus any lines indented
/// under it.
///
/// ASSA-122 moved the dead end off the row, so "what this recipe says" stopped
/// being one line. A guard that kept reading only the row would have gone green
/// the day the sentence vanished entirely, which is the failure the ASSA-59
/// derivation was written to prevent.
fn catalogue_entry<'a>(table: &'a str, name: &str) -> Vec<&'a str> {
    let mut lines = table.lines().skip_while(|l| !l.starts_with(name));
    let row = lines
        .next()
        .unwrap_or_else(|| panic!("no row for {name}\n{table}"));
    let mut entry = vec![row];
    entry.extend(lines.take_while(|l| l.starts_with(' ')));
    entry
}

/// Where a column starts, counted in CHARACTERS and not bytes: `≥` is three
/// bytes and the cells are padded by character, so a byte index would judge an
/// aligned table misaligned the moment one appeared to the left.
fn column_of(header: &str, title: &str) -> usize {
    let at = header
        .find(title)
        .unwrap_or_else(|| panic!("no {title} column in: {header}"));
    header[..at].chars().count()
}

/// **UNDER `needs`, EVERY ENTRY IS SOMETHING THAT MUST BECOME TRUE FOR THE
/// RECIPE TO WORK** (Game Director, ASSA-122). "hardness ≥ 20" is a condition
/// a player makes true by finding better rock; "nothing uses a gear" can never
/// become true by anything they do, and under one header the second read as a
/// second requirement — the wasted trip ASSA-107's precedence rule exists to
/// prevent.
///
/// **PINNED AS A DERIVATION, like the sentence itself.** The clauses are asked
/// of the recipe roster rather than written down here, so this covers whatever
/// the catalogue can say and not just today's gear.
#[test]
fn no_needs_cell_states_a_permanent_dead_end() {
    let table = sim::debug::recipe_table();
    let needs_col = column_of(table.lines().next().expect("a header"), "needs");
    let clauses: Vec<String> = sim::RECIPES
        .iter()
        .map(sim::debug::recipe_dead_end)
        .filter(|c| !c.is_empty())
        .collect();
    // Non-vacuity: with nothing to misplace this test proves nothing. The day
    // every output is consumed it should be deleted, not left reading green.
    assert!(
        !clauses.is_empty(),
        "no recipe output is a dead end any more, so this guard is vacuous:\n{table}"
    );
    for r in &sim::RECIPES {
        let row = catalogue_entry(&table, r.name)[0];
        let cell: String = row.chars().skip(needs_col).collect();
        for clause in &clauses {
            assert!(
                !cell.contains(clause.as_str()),
                "{:?} is not a condition that can become true, so it may not sit under \
                 `needs`: {row}",
                clause
            );
        }
    }
}

/// **A HEADER THAT PROMISES A SHAPE ITS CELLS BREAK** (ASSA-122, found while
/// moving the dead end and not reported by anyone).
///
/// `makes` was `{:<16}` and `1 refined +1 grade` is 18 characters, so the
/// resmelt row overflowed and shoved `from`, `ticks`, `where` and `needs` two
/// places right — on that one row, under a header claiming a grid. The width is
/// now an exact fit, which is one character from breaking again; this guard and
/// not the number is the fix.
#[test]
fn every_recipe_row_lines_up_with_the_header() {
    let table = sim::debug::recipe_table();
    let needs_col = column_of(table.lines().next().expect("a header"), "needs");
    for r in &sim::RECIPES {
        let row = catalogue_entry(&table, r.name)[0];
        let chars: Vec<char> = row.chars().collect();
        assert!(
            chars.len() > needs_col,
            "the {} row stops before its needs cell: {row}",
            r.name
        );
        assert_eq!(
            chars[needs_col - 1],
            ' ',
            "a cell ran into the needs column on the {} row: {row}",
            r.name
        );
        assert_ne!(
            chars[needs_col], ' ',
            "the {} row overflowed a cell and shoved `needs` right of the header: {row}",
            r.name
        );
    }
}

/// `is_consumed` is a claim about the whole item roster, so it is checked
/// against the whole roster rather than against the one kind the sentence is
/// about. Parts are covered by kind, because `Part::of` makes every part's
/// material `Refined` whatever item it is handed.
#[test]
fn the_gear_is_the_only_item_kind_nothing_consumes() {
    let kinds = [
        sim::ItemKind::Ore,
        sim::ItemKind::Refined,
        sim::ItemKind::Smelter,
        sim::ItemKind::Gear,
        sim::ItemKind::Part(sim::PartKind::Head),
        sim::ItemKind::Part(sim::PartKind::Hopper),
        sim::ItemKind::Part(sim::PartKind::Frame(sim::Mount::Held)),
        sim::ItemKind::Part(sim::PartKind::Frame(sim::Mount::Planted)),
    ];
    for kind in kinds {
        assert_eq!(
            sim::recipe::is_consumed(kind),
            kind != sim::ItemKind::Gear,
            "{kind:?}"
        );
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

// ---------------------------------------------------------------------------
// ASSA-58: "fuel" is a reactivity test; lighting the thing is another question
// ---------------------------------------------------------------------------

/// The hottest fire a roster can keep going, **re-derived here on purpose and
/// in a different shape from `ladder`'s**.
///
/// A test that asked `ladder::lighting` what it expected would follow the code
/// it is checking: swap two arms and it stays green. So the expectation is
/// built from the primitives instead — the hand spark, heat tolerance, and
/// `burn_temperature`, which is not what is under test. `ladder` grows one
/// temperature; this grows the SET of species actually alight and reads the
/// temperature off it at the end. Same answer by a different route, which is
/// the only kind of duplication worth having.
fn hottest_fire(species: &[sim::MineralSpecies]) -> u32 {
    let mut lit: Vec<&sim::MineralSpecies> = Vec::new();
    loop {
        let fire = lit
            .iter()
            .filter_map(|s| sim::ladder::burn_temperature(s))
            .max()
            .unwrap_or(0);
        let reach = HAND_SPARK_TEMPERATURE.max(fire);
        let next: Vec<&sim::MineralSpecies> = species
            .iter()
            .filter(|s| sim::ladder::hand_minable(s))
            .filter(|s| sim::ladder::burn_temperature(s).is_some())
            .filter(|s| u32::from(s.sheet.heat_tolerance) <= reach)
            .collect();
        if next.len() == lit.len() {
            return fire;
        }
        lit = next;
    }
}

/// The cheapest grade at which a species counts as fuel at all, or `None` if
/// none does. Independent of the table's own loop, which iterated the grades
/// the wrong way round until this item.
fn cheapest_fuel_grade(s: &sim::MineralSpecies) -> Option<Grade> {
    Grade::ALL
        .into_iter()
        .find(|g| s.effective(Property::Reactivity, *g) >= FUEL_MIN_REACTIVITY)
}

/// The row of `species_table` for one species, found by its id column so a
/// generated name that happens to contain another cannot match the wrong row.
fn species_row(table: &str, s: &sim::MineralSpecies) -> String {
    let prefix = format!("{:>2}  {:<12}", s.id.0, s.name());
    table
        .lines()
        .find(|l| l.starts_with(&prefix))
        .unwrap_or_else(|| panic!("no row for {} in\n{table}", s.name()))
        .to_string()
}

/// The three lighting clauses, **read from the sim rather than copied** —
/// their wording moved on ASSA-93, when the Game Director ruled that the
/// disqualifier must BIND the fuel claim instead of trailing it after a comma
/// where it read like another positive tag. Three tests in this file held the
/// old strings and went red, which is the pin doing its job; they follow the
/// ruling now instead of restating it.
///
/// Index order is FromCold, FromAHotterFire, NothingBurnsHotEnough. The sweep
/// below still decides WHICH state applies from the primitives — that is the
/// half that must not come from the function under test.
fn light_sentences() -> [&'static str; 3] {
    use sim::ladder::Lighting;
    [
        sim::debug::lighting_clause(Lighting::FromCold),
        sim::debug::lighting_clause(Lighting::FromAHotterFire),
        sim::debug::lighting_clause(Lighting::NothingBurnsHotEnough),
    ]
}

/// **EXHAUSTIVE AND FOUR-WAY**, the same shape as the dead-end test above:
/// every fuel row is in exactly one state, and the row has to say which — and
/// must not say any of the other three. A test that only checked the cold case
/// would pass while "fuel" promised a fire 35.8% of the time there is none
/// (measured below over these same worlds).
///
/// **STATES 2 AND 3 CANNOT BE COLLAPSED PAST THIS.** They are different
/// sentences on rows this sweep reaches in the hundreds, so a `lighting` that
/// returned one for both reddens, in either direction.
///
/// **THE FOURTH STATE CAME LATER AND SITS BEFORE THE OTHER THREE** (ASSA-68):
/// on a rock nothing can mine, the light slot answers the prior question
/// instead, because a lighting state is a promise about a fire the player can
/// never build out of that rock. It is not a fourth `Lighting` variant — the
/// enum answers an ignition question, and this row's answer is about mining —
/// so the branch under test lives in the table, and the expectation here is
/// re-derived from the sheet rather than from `ladder::hand_minable`, which is
/// the function the table asks.
#[test]
fn every_fuel_row_says_how_that_fuel_could_be_lit() {
    let (mut cold, mut hotter, mut never, mut moot, mut not_fuel) = (0, 0, 0, 0, 0);
    for seed in 1..200 {
        let w = host_world(seed);
        let table = sim::debug::species_table(&w);
        let fire = hottest_fire(&w.species);
        for s in &w.species {
            let row = species_row(&table, s);
            let Some(grade) = cheapest_fuel_grade(s) else {
                not_fuel += 1;
                assert!(
                    !row.contains("fuel") && light_sentences().iter().all(|t| !row.contains(t)),
                    "a species nothing would burn must not be offered as fuel: {row}"
                );
                continue;
            };
            assert!(
                row.contains(&format!("fuel at {} or better", grade.letter())),
                "the burn clause must name the CHEAPEST grade that burns ({}): {row}",
                grade.letter()
            );

            // State four, and it is decided before the lighting question is
            // asked at all.
            let conditional = format!("fuel at {} or better if you could mine it", grade.letter());
            if u32::from(s.sheet.hardness) > HAND_MINE_MAX_HARDNESS {
                moot += 1;
                assert!(
                    row.contains(&conditional),
                    "seed {seed}: hardness {} is past anything that mines, so the fuel claim \
                     must be conditional: {row}",
                    s.sheet.hardness
                );
                for sentence in light_sentences() {
                    assert!(
                        !row.contains(sentence),
                        "seed {seed}: a rock nothing can mine must not be told how it lights: \
                         {row}"
                    );
                }
                continue;
            }
            assert!(
                !row.contains(&conditional),
                "seed {seed}: hardness {} is minable, so nothing may hedge its fuel claim: {row}",
                s.sheet.hardness
            );

            let heat = u32::from(s.sheet.heat_tolerance);
            let (want, i) = if heat <= HAND_SPARK_TEMPERATURE {
                cold += 1;
                (light_sentences()[0], 0)
            } else if heat <= fire {
                hotter += 1;
                (light_sentences()[1], 1)
            } else {
                never += 1;
                (light_sentences()[2], 2)
            };
            assert!(
                row.contains(want),
                "seed {seed}: heat {heat} against this world's best fire {fire} means \
                 \"{want}\": {row}"
            );
            for (j, other) in light_sentences().iter().enumerate() {
                assert!(
                    j == i || !row.contains(other),
                    "seed {seed}: one state per row, and this one claims two: {row}"
                );
            }
        }
    }
    // Non-vacuity, every arm: the sweep is only exhaustive if it met all four.
    // Measured over 2000 worlds, 9418 fuel rows: **45.6% are moot** (rock
    // nothing can mine — the arm added last and the largest of the four), and
    // the remaining 5127 split cold 52.0%, hotter fire 19.6%, never 28.5%.
    // Seeds 1..200 here reach 943 fuel rows, 423 of them moot.
    assert!(cold > 50, "only {cold} cold-lighting rows");
    assert!(hotter > 50, "only {hotter} needs-a-hotter-fire rows");
    assert!(never > 50, "only {never} nothing-can-light-it rows");
    assert!(moot > 50, "only {moot} rows whose fuel claim is moot");
    assert!(not_fuel > 50, "only {not_fuel} non-fuel rows");
}

/// **THE GAME DIRECTOR'S LIVE EXAMPLE, AND IT IS OFF BY ONE.** Seed 777042 is
/// the world on the board's own #38 bench. Naersernium there is hand-minable,
/// reactive enough to be called fuel, and has a heat tolerance of 77 — one
/// degree above the hottest fire that world can build. The old table said
/// "fuel" and sent you hauling.
///
/// Pinned by the numbers and not by the name, so this still means something if
/// the generated roster is renamed; the name is here for whoever reads a
/// failure.
#[test]
fn seed_777042_has_a_fuel_no_fire_in_that_world_can_light() {
    let w = host_world(777042);
    let fire = hottest_fire(&w.species);
    assert_eq!(
        fire, 76,
        "the example is an off-by-one and stops being one if the chain moves"
    );
    let table = sim::debug::species_table(&w);
    let naersernium = w
        .species
        .iter()
        .find(|s| u32::from(s.sheet.heat_tolerance) == 77)
        .expect("seed 777042 holds a species of heat tolerance 77 (Naersernium)");
    assert!(
        cheapest_fuel_grade(naersernium).is_some(),
        "and it is reactive enough to be called fuel, which is the whole trap"
    );
    assert!(
        sim::ladder::hand_minable(naersernium),
        "and you can mine it, so the label is reachable in the fiction"
    );
    let row = species_row(&table, naersernium);
    assert!(
        row.contains(light_sentences()[2]),
        "one degree short must read as a dead end, not as a promise: {row}"
    );
}

/// **THE SAME WORLD, THE OTHER HALF OF THE TRAP, AND IT IS THE FIRST FUEL ROW
/// A PLAYER READS** (ASSA-68). On the board's #38 bench the top row of the
/// table is Koumdarnine: hardness 42, two past anything that mines, and heat
/// tolerance 11 — so a hand spark genuinely would light it, and the ASSA-58
/// wording therefore put the table's strongest buy signal on the one rock in
/// that world a player can never hold. The fuel that actually lights is three
/// fuel rows below it.
///
/// Pinned by the numbers and by position in the table, not by the generated
/// names; the names are here for whoever reads a failure.
#[test]
fn seed_777042_stops_selling_a_cold_light_in_its_first_fuel_row() {
    let w = host_world(777042);
    let table = sim::debug::species_table(&w);
    let fuel_rows: Vec<&str> = table
        .lines()
        .skip(1)
        .filter(|l| l.contains("fuel at"))
        .collect();
    assert_eq!(
        fuel_rows.len(),
        5,
        "777042 offers five of its six rocks as fuel:\n{table}"
    );

    // Which species owns the top fuel row, asked of the table rather than
    // assumed to be id 0.
    let top = w
        .species
        .iter()
        .find(|s| species_row(&table, s) == fuel_rows[0])
        .expect("the top fuel row belongs to some species");
    assert_eq!(
        u32::from(top.sheet.hardness),
        42,
        "the trap is an off-by-two over HAND_MINE_MAX_HARDNESS ({HAND_MINE_MAX_HARDNESS}) and \
         stops being this example if the roster moves: {} is hardness {}",
        top.name(),
        top.sheet.hardness
    );
    assert!(
        u32::from(top.sheet.heat_tolerance) <= HAND_SPARK_TEMPERATURE,
        "a hand spark really would light {}, which is why the old row sold it",
        top.name()
    );
    assert!(
        fuel_rows[0].contains("fuel at C or better if you could mine it"),
        "the fuel claim on unminable rock is conditional: {}",
        fuel_rows[0]
    );
    for sentence in light_sentences() {
        assert!(
            !fuel_rows[0].contains(sentence),
            "and it keeps none of the lighting sentences: {}",
            fuel_rows[0]
        );
    }

    // And the promise the player was scanning for is real, further down.
    let hand_lit: Vec<&sim::MineralSpecies> = w
        .species
        .iter()
        .filter(|s| sim::ladder::hand_lit_fuel(s))
        .collect();
    assert_eq!(
        hand_lit.len(),
        1,
        "exactly one rock here is fuel you can both mine and light: {:?}",
        hand_lit.iter().map(|s| s.name()).collect::<Vec<_>>()
    );
    let real = species_row(&table, hand_lit[0]);
    assert_eq!(
        fuel_rows.iter().position(|l| *l == real.as_str()),
        Some(3),
        "{} is the fourth fuel row, so three fuel rows are read before it:\n{table}",
        hand_lit[0].name()
    );
    assert!(
        real.contains("lights from cold"),
        "and that one still says so: {real}"
    );
}

/// The other two states, on the seed the friend playtest is pinned to
/// (ASSA-45). Both appear in 14247's roster, which is why it is the seed a
/// stranger meets: the lesson is readable from the rocks beside spawn.
#[test]
fn seed_14247_shows_both_a_cold_light_and_a_hotter_fire() {
    let w = host_world(14247);
    let table = sim::debug::species_table(&w);
    let said: Vec<&str> = light_sentences()
        .into_iter()
        .filter(|t| table.contains(t))
        .collect();
    assert!(
        said.contains(&light_sentences()[0]) && said.contains(&light_sentences()[1]),
        "the pinned world must show a fuel that lights from cold AND one that needs a \
         hotter fire: got {said:?}\n{table}"
    );
}

/// **THE SMELTER ROW SAYS WHERE ITS WALLS COME FROM** (ASSA-61), because it is
/// the only surface a player reads *before* spending five ore on a body. The
/// obvious choice — the starter rock you are already standing on — gives worse
/// walls than the best rock you can mine in 86% of worlds, and in 42% that
/// costs a species of the player's rung zero without anything saying so.
///
/// **THE SENTENCE IS PINNED TO THE BEHAVIOUR, NOT ONLY TO THE STRING.** The
/// row claims a relationship, so the test checks the relationship holds for
/// every species in a real roster, at two grades. If walls ever stop coming
/// from the material, this reddens and the sentence has to be rewritten rather
/// than quietly becoming false.
#[test]
fn the_smelter_row_says_its_walls_come_from_its_material_and_that_is_true() {
    let table = sim::debug::recipe_table();
    // THE CONSEQUENCE IS ITS OWN ASSERTION (ASSA-76), not a substring of the
    // whole clause: dropping "melts ore up to its walls" would otherwise leave
    // a definition with nothing to care about, which is what shipped on
    // ASSA-61 and what the Game Director filed ASSA-76 to fix.
    let consequence = "melts ore up to its walls";
    let clause = "walls = the heat tolerance of the ore you build it from";
    let smelter_row = table
        .lines()
        .find(|l| l.starts_with("smelter"))
        .expect("a smelter row");
    assert!(
        smelter_row.contains(consequence),
        "the row must say what walls DO before what they are made of: {smelter_row}"
    );
    assert!(
        smelter_row.find(consequence) < smelter_row.find(clause),
        "consequence first, definition second: {smelter_row}"
    );
    // From the clause to the end of the row, so the count and tick columns are
    // not mistaken for figures inside the sentence.
    let from_clause = &smelter_row[smelter_row.find(consequence).expect("just asserted")..];
    assert!(
        !from_clause.chars().any(|c| c.is_ascii_digit()),
        "no figures in this clause: the species table and building_status \
         carry them (ASSA-61): {from_clause}"
    );
    for r in &sim::RECIPES {
        let row = table
            .lines()
            .find(|l| l.starts_with(r.name))
            .unwrap_or_else(|| panic!("no row for {}\n{table}", r.name));
        assert_eq!(
            row.contains(clause),
            r.output.0 == sim::ItemKind::Smelter,
            "only the thing with walls talks about walls: {row}"
        );
    }

    let w = host_world(14247);
    for s in &w.species {
        let heat = u32::from(s.sheet.heat_tolerance);
        // Both grades, because heat tolerance is the one property grade never
        // scales — the same asymmetry ASSA-58's light clause rests on. A grade
        // in this sentence would be a lie, and this is what makes that true.
        for grade in [Grade::C, Grade::A] {
            let b = sim::Building {
                id: sim::BuildingId(0),
                pos: w.spawn_tile(),
                material: sim::Item::new(sim::ItemKind::Smelter, s.id, grade),
                kind: sim::BuildingKind::for_item(sim::ItemKind::Smelter)
                    .expect("a smelter item places a smelter"),
            };
            assert_eq!(
                w.max_temperature(&b),
                heat,
                "a smelter of {} grade {} must have that rock's walls",
                s.name(),
                grade.letter()
            );
        }
    }
}

/// **THE DISQUALIFIER BINDS THE FUEL CLAIM; THE CONDITIONAL DOES NOT**
/// (ASSA-93). Read off seed 42 — the board's own world, where they loaded 50
/// units of a fuel nothing there can light into a smelter that then sat cold.
/// Worldgen is a pure function of the seed, so this is their exact roster.
///
/// Three rows, three shapes, and the point is that they are **visibly
/// different**: before this, "fuel at C or better, nothing here burns hot
/// enough to light it" trailed the disqualifier after a comma, where it looked
/// exactly like the positive ", lights from cold" and followed a grade-bearing
/// claim that had already invited the player in.
#[test]
fn a_fuel_nothing_can_light_reads_differently_from_one_that_lights() {
    let w = host_world(42);
    let table = sim::debug::species_table(&w);
    let row = |name: &str| {
        table
            .lines()
            .find(|l| l.contains(name))
            .unwrap_or_else(|| panic!("seed 42 has no {name} row:\n{table}"))
            .to_string()
    };

    // 1. Fuel nothing in this world can light: the claim is BOUND, so there is
    //    no comma to read it as a separate positive tag.
    let dead = row("Zuxite");
    assert!(
        dead.contains("fuel at C or better if anything here could light it"),
        "the disqualifier must bind the fuel claim: {dead}"
    );
    assert!(
        !dead.contains("or better, "),
        "a bound claim must not also trail a clause after a comma: {dead}"
    );

    // 2. Fuel that lights: positive, and a comma is right here.
    let live = row("Souktulore");
    assert!(
        live.contains("fuel at C or better, lights from cold"),
        "{live}"
    );

    // 3. Not fuel at all: silent about lighting. This is the row that used to
    //    be indistinguishable from the first one at the window.
    let not_fuel = row("Viomnunine");
    assert!(
        !not_fuel.contains("fuel") && !not_fuel.contains("light"),
        "a rock the sim does not call fuel must say nothing about lighting: {not_fuel}"
    );
    assert_ne!(dead, not_fuel, "the two rows the window collapsed");
}

/// Both renderings of `Lighting` are total and distinct, so neither surface
/// can quietly lose a state (ASSA-93). The clause goes in a sentence and the
/// tag goes in a column; what must not happen is a HOST picking either.
#[test]
fn every_lighting_state_has_a_clause_and_a_tag_and_they_are_not_the_same_word() {
    use sim::debug::{lighting_clause, lighting_tag};
    use sim::ladder::Lighting;

    let all = [
        Lighting::FromCold,
        Lighting::FromAHotterFire,
        Lighting::NothingBurnsHotEnough,
    ];
    let mut clauses = Vec::new();
    let mut tags = Vec::new();
    for state in all {
        let (clause, tag) = (lighting_clause(state), lighting_tag(state));
        assert!(
            !clause.trim().is_empty() && !tag.trim().is_empty(),
            "{state:?}"
        );
        // A TAG IS NOT A CLAUSE. The clause has to join a sentence, so it
        // carries its own separator; a tag never does.
        assert!(
            !tag.starts_with(',') && !tag.starts_with(' '),
            "a tag must stand alone: {tag:?}"
        );
        clauses.push(clause);
        tags.push(tag);
    }
    clauses.sort_unstable();
    clauses.dedup();
    tags.sort_unstable();
    tags.dedup();
    assert_eq!(clauses.len(), 3, "two states share a clause: {clauses:?}");
    assert_eq!(tags.len(), 3, "two states share a tag: {tags:?}");
}

/// **THE THREE MINING STATES ARE TOTAL AND DISTINCT** (ASSA-135). One wording
/// and not a clause/tag pair like `Lighting` above: the Game Director asked
/// for the window's sentence to be byte-identical to the table's, because the
/// species panel and the `species` table are one surface at two widths.
#[test]
fn every_mining_state_has_its_own_words() {
    use sim::debug::{Mining, mining_note};

    let all = [Mining::TooHard, Mining::ByHandNotSmeltable, Mining::ByHand];
    let mut notes = Vec::new();
    for state in all {
        let note = mining_note(state);
        assert!(!note.trim().is_empty(), "{state:?} has no words");
        // A TAG STANDS ALONE. This string goes in a table cell and in a `[...]`
        // tag on a panel row, so it carries no separator of its own -- the
        // mistake `lighting_clause` exists to keep out of `lighting_tag`.
        assert!(
            !note.starts_with(',') && !note.starts_with(' '),
            "a tag must stand alone: {note:?}"
        );
        notes.push(note);
    }
    notes.sort_unstable();
    notes.dedup();
    assert_eq!(notes.len(), 3, "two states share their words: {notes:?}");
}

/// **THE TABLE'S MINING NOTE COMES OUT OF `mining_note` AND NOWHERE ELSE**,
/// over every species of 60 worlds, with all three states exercised.
///
/// This is what reddens if the words are ever re-inlined here. They WERE
/// inlined -- an if/else chain inside `species_table` -- which is how the
/// species panel came to compose its own from a bool and arrive at two states
/// (ASSA-135).
///
/// THE COUNTS ARE THE PREMISE AND ARE ASSERTED, not assumed: a run where some
/// state never came up would pass every assertion over it and prove nothing
/// about that state's row.
#[test]
fn a_species_row_says_which_of_the_three_mining_states_it_is_in() {
    use sim::debug::{Mining, mining, mining_note, species_table};

    let (mut too_hard, mut unsmeltable, mut usable) = (0, 0, 0);
    for seed in 1..60 {
        let w = host_world(seed);
        let table = species_table(&w);
        for s in &w.species {
            let state = mining(&w.species, s.id);
            match state {
                Mining::TooHard => too_hard += 1,
                Mining::ByHandNotSmeltable => unsmeltable += 1,
                Mining::ByHand => usable += 1,
            }
            let row = table
                .lines()
                .find(|l| l.contains(s.name()))
                .unwrap_or_else(|| panic!("seed {seed}: no row for {}", s.name()));
            let note = mining_note(state);
            assert!(
                row.contains(note),
                "seed {seed} {}: state {state:?} wants {note:?} and the row reads {row}",
                s.name()
            );
            // AND A ROCK NOTHING CAN MINE MAY NOT ALSO SAY IT IS MINABLE.
            // `contains` above is satisfied by a row carrying extra claims, so
            // the one state that could contradict itself is checked for what
            // it may not say as well as for what it must.
            //
            // THE MIDDLE STATE NEEDS NO SUCH GUARD AND I WROTE ONE FIRST:
            // "hand-minable, but not smeltable" has the bare promise as its
            // own prefix, so a `!contains("hand-minable")` can never hold, and
            // the version of this that tried reddened on seed 1. It does not
            // need it — if that row ever degraded to the bare promise, the
            // `contains(note)` above fails, because the longer string is the
            // one being looked for. The prefix relation does the work.
            if state == Mining::TooHard {
                assert!(
                    !row.contains(mining_note(Mining::ByHand)),
                    "seed {seed} {}: nothing can mine this and the row reads {row}",
                    s.name()
                );
            }
        }
    }
    assert!(
        too_hard > 10 && unsmeltable > 5 && usable > 10,
        "a state never came up, so its row was never checked: \
         too_hard {too_hard}, unsmeltable {unsmeltable}, usable {usable}"
    );
}

/// THE BOARD'S OWN DEMO SEED, which is where the Game Director found this:
/// two of the six rocks on 14247 can never be mined by anything and they are
/// the first two rows of the panel. The window said so by leaving a word out.
#[test]
fn the_demo_seeds_first_two_rocks_say_nothing_can_mine_them() {
    use sim::debug::{Mining, mining, mining_note, species_table};

    let w = host_world(14247);
    let table = species_table(&w);
    let dead: Vec<&str> = w
        .species
        .iter()
        .filter(|s| mining(&w.species, s.id) == Mining::TooHard)
        .map(|s| s.name())
        .collect();
    assert_eq!(
        dead.len(),
        2,
        "14247 is the demo seed and its roster moved: {dead:?}"
    );
    for name in dead {
        let row = table
            .lines()
            .find(|l| l.contains(name))
            .expect("a row per species");
        assert!(
            row.contains(mining_note(Mining::TooHard)),
            "{name} is unmineable and its row reads {row}"
        );
    }
}

/// **THE CLASSIFIER, AGAINST THE TWO LADDER FACTS, BOTH DIRECTIONS** — the
/// shape `a_deposit_has_a_reach_note_exactly_when_nothing_can_mine_it` uses
/// one surface over, and for the same reason.
///
/// THIS TEST EXISTS BECAUSE A MUTATION PROVED THE OTHERS COULD NOT SEE IT
/// (ASSA-135). Collapsing `ByHandNotSmeltable` into `ByHand` inside `mining`
/// — which is the bug this item is about, rebuilt one layer down — leaves the
/// table and the species panel AGREEING ON THE WRONG ANSWER, so every
/// byte-identity assertion between them stays green. The only thing that
/// caught it was the premise count, which is a weaker signal than it looks:
/// it reddens with "a state never came up" rather than naming the species it
/// got wrong, and it would go quiet the day someone widened the counts.
///
/// So the mapping is pinned to `ladder`, which is where the two decisions
/// actually live, and `debug` only words them.
#[test]
fn the_mining_state_is_exactly_what_the_ladder_says_it_is() {
    use sim::debug::{Mining, mining};

    let (mut too_hard, mut unsmeltable, mut usable) = (0, 0, 0);
    for seed in 1..60 {
        let w = host_world(seed);
        for s in &w.species {
            let minable = sim::ladder::hand_minable(s);
            let smeltable = sim::ladder::usable_from_bare_hands(&w.species, s.id);
            let state = mining(&w.species, s.id);
            let expected = match (minable, smeltable) {
                (false, _) => Mining::TooHard,
                (true, false) => Mining::ByHandNotSmeltable,
                (true, true) => Mining::ByHand,
            };
            assert_eq!(
                state,
                expected,
                "seed {seed} {}: hand_minable={minable} usable_from_bare_hands={smeltable}",
                s.name()
            );
            match state {
                Mining::TooHard => too_hard += 1,
                Mining::ByHandNotSmeltable => unsmeltable += 1,
                Mining::ByHand => usable += 1,
            }
        }
    }
    assert!(
        too_hard > 10 && unsmeltable > 5 && usable > 10,
        "a state never came up: too_hard {too_hard}, unsmeltable {unsmeltable}, usable {usable}"
    );
}
