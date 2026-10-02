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
    // ASSA-58 AND ASSA-59 PUT THREE MORE IN THE FAMILY. The fuel rows say what
    // a player cannot light today and the gear row says what nothing consumes
    // today, which is the same kind of sentence and the same temptation: "needs
    // a hotter fire" is one word away from promising one, and "nothing uses a
    // gear" is one word away from promising a use the alloys note only
    // discusses. The whole recipe table goes in, not the gear row alone — a
    // guard that watched one row would miss the next sentence like it.
    let w = host_world(14247);
    for row in sim::debug::species_table(&w).lines() {
        if LIGHT_SENTENCES.iter().any(|t| row.contains(t)) {
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
        let row = table
            .lines()
            .find(|l| l.starts_with(r.name))
            .unwrap_or_else(|| panic!("no row for {}\n{table}", r.name));
        let clause = format!("nothing uses a {}", r.output.0.name());
        if sim::recipe::is_consumed(r.output.0) {
            assert!(
                !row.contains("nothing uses"),
                "something does consume a {}, so the row must not say otherwise: {row}",
                r.output.0.name()
            );
        } else {
            unconsumed += 1;
            assert!(
                row.contains(&clause),
                "nothing consumes a {}, and the row has to say it: {row}",
                r.output.0.name()
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

const LIGHT_SENTENCES: [&str; 3] = [
    "lights from cold",
    "needs a hotter fire to light",
    "nothing here burns hot enough to light it",
];

/// **EXHAUSTIVE AND THREE-WAY**, the same shape as the dead-end test above:
/// every fuel row is in exactly one lighting state, and the row has to say
/// which — and must not say either of the other two. A test that only checked
/// the cold case would pass while "fuel" promised a fire 35.8% of the time
/// there is none (measured below over these same worlds).
///
/// **STATES 2 AND 3 CANNOT BE COLLAPSED PAST THIS.** They are different
/// sentences on rows this sweep reaches in the hundreds, so a `lighting` that
/// returned one for both reddens, in either direction.
#[test]
fn every_fuel_row_says_how_that_fuel_could_be_lit() {
    let (mut cold, mut hotter, mut never, mut not_fuel) = (0, 0, 0, 0);
    for seed in 1..200 {
        let w = host_world(seed);
        let table = sim::debug::species_table(&w);
        let fire = hottest_fire(&w.species);
        for s in &w.species {
            let row = species_row(&table, s);
            let Some(grade) = cheapest_fuel_grade(s) else {
                not_fuel += 1;
                assert!(
                    !row.contains("fuel") && LIGHT_SENTENCES.iter().all(|t| !row.contains(t)),
                    "a species nothing would burn must not be offered as fuel: {row}"
                );
                continue;
            };
            assert!(
                row.contains(&format!("fuel at {} or better", grade.letter())),
                "the burn clause must name the CHEAPEST grade that burns ({}): {row}",
                grade.letter()
            );

            let heat = u32::from(s.sheet.heat_tolerance);
            let (want, i) = if heat <= HAND_SPARK_TEMPERATURE {
                cold += 1;
                (LIGHT_SENTENCES[0], 0)
            } else if heat <= fire {
                hotter += 1;
                (LIGHT_SENTENCES[1], 1)
            } else {
                never += 1;
                (LIGHT_SENTENCES[2], 2)
            };
            assert!(
                row.contains(want),
                "seed {seed}: heat {heat} against this world's best fire {fire} means \
                 \"{want}\": {row}"
            );
            for (j, other) in LIGHT_SENTENCES.iter().enumerate() {
                assert!(
                    j == i || !row.contains(other),
                    "seed {seed}: one state per row, and this one claims two: {row}"
                );
            }
        }
    }
    // Non-vacuity, every arm: the sweep is only exhaustive if it met all
    // three. Measured over 2000 worlds: cold 41.6%, hotter fire 22.7%,
    // never 35.8% of 9418 fuel rows.
    assert!(cold > 50, "only {cold} cold-lighting rows");
    assert!(hotter > 50, "only {hotter} needs-a-hotter-fire rows");
    assert!(never > 50, "only {never} nothing-can-light-it rows");
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
        row.contains("nothing here burns hot enough to light it"),
        "one degree short must read as a dead end, not as a promise: {row}"
    );
}

/// The other two states, on the seed the friend playtest is pinned to
/// (ASSA-45). Both appear in 14247's roster, which is why it is the seed a
/// stranger meets: the lesson is readable from the rocks beside spawn.
#[test]
fn seed_14247_shows_both_a_cold_light_and_a_hotter_fire() {
    let w = host_world(14247);
    let table = sim::debug::species_table(&w);
    let said: Vec<&str> = LIGHT_SENTENCES
        .into_iter()
        .filter(|t| table.contains(t))
        .collect();
    assert!(
        said.contains(&LIGHT_SENTENCES[0]) && said.contains(&LIGHT_SENTENCES[1]),
        "the pinned world must show a fuel that lights from cold AND one that needs a \
         hotter fire: got {said:?}\n{table}"
    );
}
