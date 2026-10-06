//! **"WHAT IS NEARBY THAT'S VIABLE AS FUEL"** — the board's own question
//! (Rainy, 10-05), and the one thing no surface in the game could answer
//! (ASSA-248).
//!
//! **THESE TESTS ASK THE SIM FOR THE ANSWER, NOT FOR A SENTENCE.** Box 10 of
//! the item says so and it is the difference between this file and a snapshot
//! of some strings: `nearest_answering` returns a `DepositId`, a tile, a tick
//! count and a heading, so a test can go and *check* each one against the
//! thing it describes. The two tests that do read the headline read it for the
//! one property a string is the right home for — that an unassayed species
//! stays a band — and even those compare against `debug::reading`'s output
//! rather than a literal.
//!
//! The headline's wording is judged by the Game Director at 1x on ASSA-241;
//! none of it is pinned here, on purpose. A test that froze the sentence would
//! turn their next ruling into a red suite.

use sim::debug;
use sim::ladder;
use sim::mineral::Property;
use sim::proximity::{Heading, Question, walking_ticks};
use sim::tuning::GRADE_B_MIN_PURITY;
use sim::{
    Grade, Input, PlayerCommand, PlayerId, SpeciesId, SystemCommand, TilePos, World, WorldConfig,
    step,
};

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
        &[Input::System(SystemCommand::AddPlayer {
            name: "ada".into(),
        })],
        &mut Vec::new(),
    );
    (w, PlayerId(0))
}

/// Walk one tick, having submitted `MoveTo` on the first of them.
///
/// `step` applies commands and then runs `move_players` in the SAME tick
/// (`step.rs`), so the tick that carries the command is already a step: a trip
/// of `distance` takes `distance` calls, not `distance + 1`. Getting that wrong
/// would make every assertion below pass one tile early.
fn walk(w: &mut World, me: PlayerId, target: Option<TilePos>) {
    let inputs: Vec<Input> = target
        .map(|t| Input::player(me, PlayerCommand::MoveTo { target: t }))
        .into_iter()
        .collect();
    step(w, &inputs, &mut Vec::new());
}

/// **THE BOX THAT A FORMATTED STRING CAN FAKE** (ASSA-249's wording of it, kept
/// because it is the sharper one: *"distance and direction to a real deposit,
/// and a player who walks it arrives at that deposit"*).
///
/// A headline can carry a plausible number and a plausible compass word and
/// point at nothing, and every assertion about its shape would stay green. So
/// this one walks: it submits the sim's own `MoveTo` to the tile the answer
/// names, steps exactly as many ticks as the answer claimed, and then asks the
/// *ground* what is underfoot.
///
/// **THE TICK SHORT OF IT IS THE HALF THAT MAKES THIS A MEASUREMENT.** Without
/// it, `distance` only has to be *at least* far enough, and a query returning
/// Euclidean distance (always ≥ Chebyshev) would pass — which is exactly the
/// metric a reader would reach for first.
#[test]
fn the_distance_is_the_walk_and_the_walk_ends_on_that_deposit() {
    // A seed whose nearest answer is at least two tiles off, so "one tick
    // short" is a real assertion and not the standing tile.
    let seed = (0..200)
        .find(|s| {
            let (w, me) = joined(*s);
            let at = w.player(me).unwrap().pos;
            w.nearest_answering(Question::Burns, at)
                .is_some_and(|n| n.distance >= 2)
        })
        .expect("some seed in 0..200 answers `Burns` from two or more tiles away");

    let (mut w, me) = joined(seed);
    let from = w.player(me).unwrap().pos;
    let near = w
        .nearest_answering(Question::Burns, from)
        .expect("the seed was chosen for having an answer");

    assert_eq!(
        near.distance,
        walking_ticks(from, near.tile),
        "seed {seed}: the reported distance is not the walk to the tile it names"
    );

    walk(&mut w, me, Some(near.tile));
    for _ in 1..near.distance {
        assert_ne!(
            w.player(me).unwrap().pos,
            near.tile,
            "seed {seed}: arrived early, so `distance` ({}) overstates the walk — \
             a Euclidean or Manhattan metric would do exactly this",
            near.distance
        );
        walk(&mut w, me, None);
    }

    let landed = w.player(me).unwrap().pos;
    assert_eq!(
        landed, near.tile,
        "seed {seed}: {} ticks of walking did not reach the tile the answer named",
        near.distance
    );
    let under = w
        .deposit_at(landed)
        .expect("the answer named a deposit tile, so something is underfoot");
    assert_eq!(
        under.id, near.deposit,
        "seed {seed}: the player arrived on deposit {:?}, not the {:?} the answer named",
        under.id, near.deposit
    );
    // AND IT IS GENUINELY AN ANSWER TO THE QUESTION ASKED, not merely a deposit.
    assert!(
        Question::Burns.answered_by(&w.species, under),
        "seed {seed}: walked to a patch that does not answer `Burns`"
    );
}

/// The heading is the first step the mover actually takes, which is why
/// `Heading::of_gap` signums the gap the same way `move_players` does.
///
/// Across a gap that is neither straight nor diagonal the walk changes heading
/// partway, so this asserts about the FIRST tick only — and the doc on
/// `Heading::of_gap` says so rather than letting a reader believe the compass
/// word is a bearing to the target.
#[test]
fn the_heading_is_the_first_step_the_mover_takes() {
    let mut checked = 0;
    for seed in 0..60 {
        let (mut w, me) = joined(seed);
        let from = w.player(me).unwrap().pos;
        let Some(near) = w.nearest_answering(Question::Burns, from) else {
            continue;
        };
        let Some(heading) = near.heading else {
            continue; // standing on it; there is no step to take
        };
        walk(&mut w, me, Some(near.tile));
        let after = w.player(me).unwrap().pos;
        assert_eq!(
            Heading::of_gap(after.x - from.x, after.y - from.y),
            Some(heading),
            "seed {seed}: the answer said {heading:?} and the first step went \
             ({}, {})",
            after.x - from.x,
            after.y - from.y
        );
        checked += 1;
    }
    assert!(
        checked >= 40,
        "only {checked} of 60 seeds exercised a heading, so this test is mostly \
         skipping; it is supposed to be measuring"
    );
}

/// **NORTH IS UP ON THE MAP THE PLAYER IS LOOKING AT.** `debug::ascii_map`
/// emits one row per `y` ascending, so `y` grows downward and north must be
/// `-y`. Flip the two and every direction the game ever says is backwards —
/// a defect no amount of green elsewhere would catch, because nothing else in
/// the sim had a compass before this module.
#[test]
fn the_compass_agrees_with_the_drawn_map() {
    assert_eq!(Heading::of_gap(0, -1), Some(Heading::North));
    assert_eq!(Heading::of_gap(0, 1), Some(Heading::South));
    assert_eq!(Heading::of_gap(1, 0), Some(Heading::East));
    assert_eq!(Heading::of_gap(-1, 0), Some(Heading::West));
    assert_eq!(Heading::of_gap(5, -9), Some(Heading::NorthEast));
    assert_eq!(Heading::of_gap(-5, 9), Some(Heading::SouthWest));
    assert_eq!(Heading::of_gap(-2, -2), Some(Heading::NorthWest));
    assert_eq!(Heading::of_gap(7, 1), Some(Heading::SouthEast));
    assert_eq!(Heading::of_gap(0, 0), None);

    // The map itself, read rather than assumed: the row a tile is drawn on is
    // its `y`, so a larger `y` is further down the printed block.
    let w = world(14247);
    let map = debug::ascii_map(&w);
    let rows: Vec<&str> = map.lines().collect();
    assert_eq!(rows.len() as i32, w.height(), "one row per y");
    let spawn = w.spawn_tile();
    assert_eq!(
        rows[spawn.y as usize].chars().nth(spawn.x as usize),
        Some('@'),
        "the spawn glyph sits at row y, column x; if this moved, the compass \
         above needs re-deriving, not patching"
    );
}

/// A mined-out patch is still a deposit, still drawn (in lower case), and never
/// the answer to a question a player asks with their feet.
///
/// **THE MUTATION THIS EXISTS FOR:** drop `is_depleted` from
/// `Question::answered_by` and the headline sends the player to an empty hole.
/// Nothing else in the suite would notice, because the patch is of the right
/// species and at the right grade.
#[test]
fn a_mined_out_patch_is_never_the_answer() {
    let (mut w, me) = joined(14247);
    let at = w.player(me).unwrap().pos;
    let first = w
        .nearest_answering(Question::Burns, at)
        .expect("seed 14247 has something to burn");

    let i = w
        .deposits
        .iter()
        .position(|d| d.id == first.deposit)
        .expect("the answer names a deposit of this world");
    w.deposits[i].amount = 0;

    let next = w.nearest_answering(Question::Burns, at);
    assert_ne!(
        next.map(|n| n.deposit),
        Some(first.deposit),
        "a patch with no ore left was still offered as the nearest answer"
    );
    if let Some(next) = next {
        assert!(
            next.distance >= first.distance,
            "the replacement is nearer than the patch it replaced, which cannot be"
        );
    }
    // And the same for the plain species query, which is a different code path
    // for callers who already know what they want.
    let species = w.deposits[i].species;
    assert!(
        w.nearest_ore_of(species, at)
            .is_none_or(|n| n.deposit != first.deposit),
        "`nearest_ore_of` offered a mined-out patch"
    );
}

/// **ASSA-143'S HOLE, CLOSED BY KNOWING WHICH PATCH.** `fuel_tag` says "fuel at
/// B or better" about a *species*; a player who read that, walked to the
/// nearest patch and mined it could come back with grade-C ore that will not
/// light, with no surface having said purity was the variable.
///
/// Here the question is asked of `deposit.grade()`, so a patch too poor to
/// burn is not offered at all. Built by lowering one patch's purity rather than
/// by hunting a seed, so the test states the rule instead of a coincidence.
#[test]
fn the_question_is_asked_of_the_grade_the_patch_yields() {
    // A species that needs better than grade C to burn, and a patch of it.
    let found = (0..300).find_map(|seed| {
        let w = world(seed);
        let s = w
            .species
            .iter()
            .find(|s| ladder::fuel_grade(s).is_some_and(|g| g > Grade::C))?;
        let i = w.deposits.iter().position(|d| d.species == s.id)?;
        Some((seed, i))
    });
    let (seed, i) = found.expect(
        "no seed in 0..300 rolled a species that burns only above grade C; \
         18.8% of fuel rows name a grade above C (ASSA-143), so this is a \
         broken search, not a world without one",
    );

    let mut w = world(seed);
    let at = w.deposits[i].center;
    let id = w.deposits[i].id;
    let species = w.deposits[i].species;

    // At a grade that burns, standing on it, it is the answer.
    w.deposits[i].purity = GRADE_B_MIN_PURITY;
    assert_eq!(w.deposits[i].grade(), Grade::B);
    let rich = w.nearest_answering(Question::Burns, at);
    assert_eq!(
        rich.map(|n| n.deposit),
        Some(id),
        "seed {seed}: a burnable patch underfoot was not the nearest answer"
    );

    // The same patch, too poor to light anything: not an answer, even though
    // the species' own fuel row still reads "fuel at B or better".
    w.deposits[i].purity = 1;
    assert_eq!(w.deposits[i].grade(), Grade::C);
    assert!(
        !Question::Burns.answered_by(&w.species, &w.deposits[i]),
        "seed {seed}: a grade-C patch of a species that only burns at B or \
         better was offered as something that burns"
    );
    assert!(
        ladder::fuel_grade(w.species(species)).is_some(),
        "the species is still fuel at SOME grade — that is the whole point: the \
         species-level claim is true and the patch-level one is not"
    );
}

/// **ROUGH STAYS ROUGH, and the headline is the surface most likely to leak.**
/// It is the one place that prints a property outside the table's own column,
/// so it goes through `debug::reading` and cannot format a sheet value itself.
///
/// Compared against `reading`'s output rather than a literal band, so this
/// cannot drift from the function it is asserting about.
#[test]
fn rough_stays_rough_in_the_headline() {
    let (mut w, me) = joined(14247);
    let at = w.player(me).unwrap().pos;
    let near = w
        .nearest_answering(Question::Burns, at)
        .expect("seed 14247 has something to burn");
    let species = w.deposit(near.deposit).unwrap().species;

    assert!(
        !w.species(species).assayed,
        "nothing is assayed in a fresh world, so the band is the state under test"
    );
    let rough = debug::proximity_headline(&w, me, Question::Burns);
    let band = debug::reading(w.species(species), Property::Reactivity);
    assert!(
        band.contains('-'),
        "an unassayed reading is a band like 51-75, got {band:?}"
    );
    assert!(
        rough.contains(&band),
        "the headline dropped the rough band {band:?}:\n{rough}"
    );
    let exact = w
        .species(species)
        .sheet
        .get(Property::Reactivity)
        .to_string();
    assert!(
        !rough.contains(&format!("reactivity {exact}")),
        "the headline printed the exact reactivity {exact} for an unassayed \
         species:\n{rough}"
    );

    // And it sharpens, because the gate is the assay and nothing else.
    w.species_mut(species).assayed = true;
    let sharp = debug::proximity_headline(&w, me, Question::Burns);
    assert!(
        sharp.contains(&format!("reactivity {exact}")),
        "after assaying, the headline still will not say the number:\n{sharp}"
    );
}

/// When the world has no answer the line says so in words, because **silence
/// where an answer goes reads as a bug** (Game Director, ASSA-241) and this is
/// a common state rather than an edge: of worlds whose fuel label cannot be
/// lit, 56.3% can never light it at all (ASSA-58).
///
/// Built by emptying every patch, which is the honest way to reach "nothing
/// here burns" without hunting for a world that happens to be bleak.
#[test]
fn nothing_qualifies_says_so_in_words() {
    let (mut w, me) = joined(14247);
    for d in &mut w.deposits {
        d.amount = 0;
    }
    let at = w.player(me).unwrap().pos;
    assert!(
        w.nearest_answering(Question::Burns, at).is_none(),
        "every patch is empty, so nothing can answer"
    );

    for q in Question::ALL {
        let line = debug::proximity_headline(&w, me, q);
        assert!(
            line.starts_with(debug::question_asked(q)),
            "the line must still lead with the question it is answering:\n{line}"
        );
        assert!(
            line.contains(debug::nothing_answers(q)),
            "{q:?}: the empty answer is not the one sentence written for it:\n{line}"
        );
        assert!(
            !line.chars().any(|c| c.is_ascii_digit()),
            "{q:?}: a no-answer line carries a number, so something was \
             formatted from a deposit that does not exist:\n{line}"
        );
    }
}

/// **THE SELECTOR IS A SHAPE ONLY IF A SECOND QUESTION USES IT**, so this asks
/// the second one and then proves the two are not the same question wearing two
/// names.
///
/// The non-vacuity half matters: if every world answered both questions with
/// the same patch, `Question` would be decoration and a single hardcoded fuel
/// search would pass this file.
#[test]
fn the_selector_answers_a_second_question_and_a_different_one() {
    let mut differed = 0;
    let mut both_answered = 0;
    for seed in 0..80 {
        let (w, me) = joined(seed);
        let at = w.player(me).unwrap().pos;
        let burns = w.nearest_answering(Question::Burns, at);
        let hard = w.nearest_answering(Question::HardEnough, at);
        if burns.is_some() && hard.is_some() {
            both_answered += 1;
            if burns.map(|n| n.deposit) != hard.map(|n| n.deposit) {
                differed += 1;
            }
        }
        // Whatever each one answered, it answered its OWN question.
        for (q, got) in [(Question::Burns, burns), (Question::HardEnough, hard)] {
            if let Some(n) = got {
                let d = w.deposit(n.deposit).unwrap();
                assert!(
                    q.answered_by(&w.species, d),
                    "seed {seed}: {q:?} returned a patch that does not answer it"
                );
            }
        }
        // And each names the property it turns on, so the headline cannot
        // print hardness for a question about burning.
        assert_eq!(Question::Burns.property(), Property::Reactivity);
        assert_eq!(Question::HardEnough.property(), Property::Hardness);
    }
    assert!(
        both_answered >= 20,
        "only {both_answered} of 80 seeds answered both questions; this test is \
         not exercising the selector"
    );
    assert!(
        differed > 0,
        "in {both_answered} seeds answering both, the two questions never once \
         picked different patches — so `Question` is decoration and a hardcoded \
         fuel search would pass this file"
    );
}

/// **NO PER-PLAYER KNOWLEDGE IS INTRODUCED** (Wren's ruling on ASSA-241:
/// knowledge is per WORLD, `command.rs:157`).
///
/// Two proofs, because the structural one alone is too easy: the query takes a
/// TILE and no `PlayerId`, so it cannot gate on a reader; and one player's
/// assay sharpens the other player's headline, which is the co-op behaviour the
/// ruling chose.
#[test]
fn knowledge_is_per_world_and_proximity_is_only_about_where_you_stand() {
    let (mut w, me) = joined(14247);
    step(
        &mut w,
        &[Input::System(SystemCommand::AddPlayer {
            name: "grace".into(),
        })],
        &mut Vec::new(),
    );
    let you = PlayerId(1);
    let far = TilePos::new(w.width() - 2, w.height() - 2);
    w.player_mut(you).unwrap().pos = far;

    let mine = w.player(me).unwrap().pos;
    // THE STRUCTURAL HALF IS THE SIGNATURE AND NOT AN ASSERTION. `nearest_
    // answering` takes a `TilePos` and no `PlayerId`, so there is no reader for
    // a fog to be keyed on; my first draft "asserted" that by comparing the
    // answer with itself mapped through an `unwrap`, which is a vacuous
    // assertion of exactly the kind I keep finding in my own merged tests.
    // What CAN be measured is below: distance follows the tile, and an assay by
    // one player is readable by the other.
    let near_me = w.nearest_answering(Question::Burns, mine);
    let near_you = w.nearest_answering(Question::Burns, far);
    let (near_me, near_you) = (
        near_me.expect("spawn has something to burn"),
        near_you.expect("the far corner has something to burn"),
    );
    // **THE CLAIM IS DIFFERENT PATCHES, NOT DIFFERENT DISTANCES, and my first
    // version got that wrong and went red for it.** I asserted the two
    // distances differ; both came back 3. That is not a defect — a 128x128 map
    // carries one deposit per 16x16 chunk, so two players 170 ticks apart can
    // easily each have a burnable patch three tiles away. The coincidence was
    // in my assertion, not in the sim.
    assert_ne!(
        near_me.deposit, near_you.deposit,
        "two players at opposite corners were sent to the SAME patch, so the \
         answer is not being measured from the asking tile"
    );
    // And each distance is the walk from the tile that asked, which is the
    // thing the distances were standing in for.
    assert_eq!(near_me.distance, walking_ticks(mine, near_me.tile));
    assert_eq!(near_you.distance, walking_ticks(far, near_you.tile));
    // **AND THE TWO TILES ARE GENUINELY FAR APART, measured off the map rather
    // than guessed.** My first threshold was a hand-typed `> 100` and it failed
    // at 62 — because spawn is the CENTRE of the middle chunk, not a corner, so
    // the furthest any corner can be is about half the map. Everything above
    // this line passed; the only wrong number was the one I reasoned my way to,
    // which is the mistake my notes already had me down for.
    let apart = walking_ticks(mine, far);
    let quarter = w.width().min(w.height()) / 4;
    assert!(
        apart >= quarter as u32,
        "the two asking tiles are {apart} ticks apart, under a quarter of the \
         map ({quarter}); a shared nearest patch would prove nothing"
    );

    // ONE PLAYER ASSAYS, BOTH SEE THE NUMBER. The gate is the species, not the
    // reader — so there is nowhere for a per-player fog to have been added.
    let species = w.deposit(near_you.deposit).unwrap().species;
    w.species_mut(species).assayed = true;
    let exact = w
        .species(species)
        .sheet
        .get(Property::Reactivity)
        .to_string();
    let theirs = debug::proximity_headline(&w, you, Question::Burns);
    assert!(
        theirs.contains(&format!("reactivity {exact}")),
        "the assaying player's own headline does not show the number:\n{theirs}"
    );
    // `me` is somewhere else, so their nearest patch may be another species;
    // what must hold is that the SPECIES is exact for them too.
    assert!(
        debug::reading(w.species(species), Property::Reactivity) == exact,
        "an assay is known to everyone in the world (command.rs:157)"
    );
}

/// The headline's fuel clause is the species table's own words, byte for byte,
/// so a player who reads the line and then the row it points at cannot find
/// two phrasings of one fact.
///
/// This is `mining_note`'s argument from ASSA-135 applied to a new surface, and
/// it is asserted by composing the same two functions the table composes rather
/// than by copying their output.
#[test]
fn the_headline_speaks_the_tables_own_words() {
    let (w, me) = joined(14247);
    let at = w.player(me).unwrap().pos;
    let near = w
        .nearest_answering(Question::Burns, at)
        .expect("seed 14247 has something to burn");
    let s = w.species(w.deposit(near.deposit).unwrap().species);

    let grade = ladder::fuel_grade(s).expect("a patch that burns is of a species that is fuel");
    let clause = format!(
        "{}{}",
        debug::fuel_tag(grade, ladder::hand_minable(s)),
        debug::lighting_clause(ladder::lighting(&w.species, s.id))
    );
    let line = debug::proximity_headline(&w, me, Question::Burns);
    assert!(
        line.contains(&clause),
        "the headline does not carry the table's fuel clause.\nwanted: \
         {clause}\nline:   {line}"
    );
    // The table says it too, on that species' row, which is what makes it "the
    // table's own words" rather than two places agreeing by luck.
    let table = debug::species_table(&w);
    let row = table
        .lines()
        .find(|l| l.contains(s.name()))
        .expect("every species has a row");
    assert!(
        row.contains(&clause),
        "the clause is not on the row either, so the headline invented it.\n{row}"
    );
}

/// **DISCOVERY IS VISIBLE, AND SO IS WHAT IT WON YOU** (box 7). "found by X"
/// named the finder and never said that finding it is what lets them name the
/// species — the one piece of authorship co-op hands a player, invisible unless
/// they read `help`.
///
/// The right is stated, never the history: `MineralSpecies` records who found
/// it and who may rename it, and NOT who did the renaming, so a note crediting
/// a name to the discoverer could be crediting the wrong player.
#[test]
fn discovery_and_the_naming_right_are_both_in_the_output() {
    let (mut w, me) = joined(14247);
    let species = SpeciesId(0);
    let table_before = debug::species_table(&w);
    assert!(
        !table_before.contains("found by"),
        "nothing is discovered in a fresh world"
    );

    w.species_mut(species).discoverer = Some(me);
    let row = |w: &World| {
        debug::species_table(w)
            .lines()
            .find(|l| l.contains(w.species(species).name()))
            .expect("a row for species 0")
            .to_string()
    };
    let found = row(&w);
    assert!(
        found.contains("found by ada"),
        "the finder is not named:\n{found}"
    );
    // **ONE VERB IN BOTH STATES (Game Director, ruling 1).** This asserted
    // `may name it` here and `may rename it` after a player name was set — my
    // switch, and the ruling is that the switch had the words the right way
    // round for a fact the game does not have: every species is generated with
    // a name, so nothing is ever unnamed.
    assert!(
        found.contains("found by ada, who may rename it"),
        "finding it is what lets you rename it, and the row does not say so:\n{found}"
    );

    // Setting a player name must NOT change the clause: it was the thing the
    // old switch turned on, so this is the lever that would catch it coming
    // back. The row still credits only the finding, because that is all the
    // world knows.
    w.species_mut(species).player_name = Some("Kelvite".into());
    let named = row(&w);
    assert_eq!(
        named.contains("found by ada, who may rename it"),
        found.contains("found by ada, who may rename it"),
        "the naming right changed wording when the species gained a player \
         name; one verb covers both states:\n{found}\n{named}"
    );
    assert!(
        !named.contains("named by"),
        "the sim does not record WHO typed the name — a grantee may have — so \
         the row must not claim it:\n{named}"
    );

    // A grant is news: someone else may name it too.
    w.species_mut(species).rename_grants.push(PlayerId(7));
    let shared = row(&w);
    assert!(
        shared.contains("1 others may too"),
        "a granted rename right is invisible:\n{shared}"
    );
}

/// **"HARD ENOUGH" NEVER NAMES A ROCK WHOSE ORE GOES NOWHERE**, and this test
/// exists because my first version did.
///
/// I asked only `hand_minable`, which is exactly the filter the Game Director
/// withdrew on ASSA-52: a part needs refined material, so the gate is rung
/// zero. `sim-cli/tests/unsmeltable.rs` went red and caught it — on seed 10027
/// the player spawns on a grade-A patch with the best yield on the map and a
/// heat tolerance no fire a player can light will reach. It is scenery, and my
/// headline sent them to mine it.
///
/// **THE DEAD-END SPECIES IS FOUND BY ASKING THE SIM, NOT BY NAMING A SEED'S
/// ROCK.** A sweep looks for any world holding a hand-minable species that rung
/// zero cannot use, asserts it found one, and then asserts no `HardEnough`
/// answer anywhere in that world is of that species. `Burns` is deliberately
/// NOT held to this: you burn ore, you do not smelt it, so a patch that can
/// never become a part is still honest fuel.
#[test]
fn hard_enough_never_points_at_a_rock_that_can_never_become_a_part() {
    let mut worlds_with_a_dead_end = 0;
    for seed in 0..120 {
        let (w, me) = joined(seed);
        let at = w.player(me).unwrap().pos;
        let dead: Vec<SpeciesId> = w
            .species
            .iter()
            .filter(|s| ladder::hand_minable(s))
            .filter(|s| !ladder::usable_from_bare_hands(&w.species, s.id))
            .map(|s| s.id)
            .collect();
        if dead.is_empty() {
            continue;
        }
        worlds_with_a_dead_end += 1;
        // Not just the nearest answer: every tile a player could ask from, so a
        // dead end cannot hide behind a luckier patch being closer.
        for tile in [at, TilePos::new(0, 0), TilePos::new(w.width() - 1, 0)] {
            if let Some(n) = w.nearest_answering(Question::HardEnough, tile) {
                let named = w.deposit(n.deposit).unwrap().species;
                assert!(
                    !dead.contains(&named),
                    "seed {seed}: `hard enough` sent the player from {tile:?} to \
                     {}, whose ore rung zero can never use — the ASSA-52 \
                     promise, rebuilt",
                    w.species(named).name()
                );
            }
        }
    }
    assert!(
        worlds_with_a_dead_end >= 20,
        "only {worlds_with_a_dead_end} of 120 seeds held a hand-minable rock \
         rung zero cannot use, so this test is barely asking its question; \
         13.6% of deposits are that (ASSA-52)"
    );
}

/// Each question's trailing clause is about the question asked.
///
/// **MY FIRST VERSION APPENDED THE FUEL CLAIM TO BOTH**, so a line about making
/// a part carried a fuel grade and an ignition state. Nothing in it was false,
/// which is why thirteen green tests did not see it — on a one-line answer the
/// wrong fact costs what a false one costs, and one look at the real output
/// found it.
#[test]
fn each_headline_carries_the_clause_its_own_question_turns_on() {
    let (w, me) = joined(14247);
    let burns = debug::proximity_headline(&w, me, Question::Burns);
    let hard = debug::proximity_headline(&w, me, Question::HardEnough);
    assert!(
        burns.contains("fuel at"),
        "the fuel question must carry the fuel claim:\n{burns}"
    );
    assert!(
        !hard.contains("fuel at"),
        "the hardness question must not carry a fuel grade or an ignition \
         state:\n{hard}"
    );
    assert!(
        hard.contains(Property::Hardness.name()) && burns.contains(Property::Reactivity.name()),
        "each line names the property it turns on:\n{burns}\n{hard}"
    );
}

/// The query is a pure function of the world: same seed, same answers, and
/// asking changes nothing.
///
/// **THE GOLDEN HASH IN `determinism.rs` CANNOT COVER THIS AND I WOULD RATHER
/// SAY SO THAN LET IT READ AS COVER.** That hash is over `World` state after a
/// scripted run; a query adds no state, so it would not move if this module
/// returned a different answer every call. The determinism that matters here is
/// that two peers asking the same question of the same world get the same
/// answer, and that is what this asserts.
#[test]
fn the_query_is_deterministic_and_changes_nothing() {
    for seed in [14247, 777042, 2191] {
        let (a, me) = joined(seed);
        let (b, _) = joined(seed);
        let at = a.player(me).unwrap().pos;
        for q in Question::ALL {
            assert_eq!(
                a.nearest_answering(q, at),
                b.nearest_answering(q, at),
                "seed {seed} {q:?}: two worlds built from one seed disagree"
            );
        }
        for s in &a.species {
            assert_eq!(
                a.nearest_ore_of(s.id, at),
                b.nearest_ore_of(s.id, at),
                "seed {seed}: `nearest_ore_of` disagrees for {}",
                s.name()
            );
        }
        // Asking is not a mutation: the state hash is untouched by every
        // question asked above.
        let before = a.state_hash();
        for q in Question::ALL {
            let _ = a.nearest_answering(q, at);
            let _ = debug::proximity_headline(&a, me, q);
        }
        assert_eq!(
            before,
            a.state_hash(),
            "seed {seed}: asking the ground a question changed the world"
        );
    }
}

/// Every tile the answer names is a tile of that deposit and on the map, and
/// the one it names is the nearest such tile.
///
/// **THE NEAREST TILE AND NOT THE CENTRE.** A radius-4 patch is eight tiles
/// across, so centre-distance overstates the walk by up to the radius — and
/// `distance` is what the headline promises. Checked by brute force against
/// every tile of the chosen patch.
#[test]
fn the_tile_named_is_the_nearest_tile_of_that_patch_and_is_on_the_map() {
    for seed in 0..40 {
        let (w, me) = joined(seed);
        let at = w.player(me).unwrap().pos;
        let Some(near) = w.nearest_answering(Question::Burns, at) else {
            continue;
        };
        let d = w.deposit(near.deposit).unwrap();
        assert!(
            d.contains(near.tile) && w.in_bounds(near.tile),
            "seed {seed}: {:?} is not an on-map tile of the patch",
            near.tile
        );
        let r = i32::from(d.radius);
        let best = ((d.center.y - r)..=(d.center.y + r))
            .flat_map(|y| ((d.center.x - r)..=(d.center.x + r)).map(move |x| TilePos::new(x, y)))
            .filter(|t| d.contains(*t) && w.in_bounds(*t))
            .map(|t| walking_ticks(at, t))
            .min()
            .expect("the patch has at least its centre");
        assert_eq!(
            near.distance, best,
            "seed {seed}: the answer named a tile {} ticks away when {best} was \
             reachable in the same patch — centre-distance overstates a walk by \
             up to the radius",
            near.distance
        );
    }
}

/// **A NEARER PATCH YOU CANNOT LIGHT LOSES TO A FURTHER ONE YOU CAN** (Game
/// Director, ASSA-248 ruling 4).
///
/// **THE DISAGREEING WORLD IS SEARCHED FOR, NOT NAMED.** Pinning a seed where
/// the tiers differ would make this test a photograph of worldgen; the sweep
/// looks for any world where tier 1 and a flat search return different
/// deposits, asserts it found some, and then checks the property in each. The
/// non-vacuity bar is the point: if ranking stopped changing any answer this
/// test must fail rather than quietly agree.
#[test]
fn burns_prefers_a_patch_that_lights_from_cold_over_a_nearer_one_that_does_not() {
    let mut worlds_where_it_matters = 0;
    for seed in 0..160 {
        let (w, me) = joined(seed);
        let at = w.player(me).unwrap().pos;
        let Some(answer) = w.nearest_answering(Question::Burns, at) else {
            continue;
        };
        let chosen = w.deposit(answer.deposit).unwrap();
        let chosen_lights =
            ladder::lighting(&w.species, chosen.species) == ladder::Lighting::FromCold;

        // Is there ANY nearer patch that burns but does not light from cold?
        // That is the patch a flat search would have handed back.
        let nearer_cold_fire = w.deposits.iter().any(|d| {
            d.id != chosen.id
                && Question::Burns.answered_by(&w.species, d)
                && ladder::lighting(&w.species, d.species) != ladder::Lighting::FromCold
                && w.nearest_ore_of(d.species, at)
                    .is_some_and(|n| n.distance < answer.distance)
        });
        if !nearer_cold_fire {
            continue;
        }
        worlds_where_it_matters += 1;
        assert!(
            chosen_lights,
            "seed {seed}: a patch that needs a hotter fire sits nearer than the \
             answer, so ranking had something to do, and it still handed back \
             {} which does not light from cold",
            w.species(chosen.species).name()
        );
    }
    assert!(
        worlds_where_it_matters >= 5,
        "ranking changed the answer in only {worlds_where_it_matters} of 160 \
         seeds, so this test is barely asking its question"
    );
}

/// **THE TWO EMPTY ANSWERS ARE DIFFERENT NEWS** (ruling 3): "nothing in this
/// world burns" ends a search, "no patch is rich enough" explains it.
///
/// Asserted as a property of the sim rather than of a sentence: when
/// `nearest_answering` is empty, `too_poor_for` must agree with the real
/// predicate about which case it is — and the two cases must be exclusive.
#[test]
fn an_empty_answer_says_which_kind_of_empty_it_is() {
    let mut empty = 0;
    let mut too_poor = 0;
    for seed in 0..200 {
        let (w, me) = joined(seed);
        let at = w.player(me).unwrap().pos;
        for q in Question::ALL {
            if w.nearest_answering(q, at).is_some() {
                // The states are exclusive: an answerable question is never
                // also "too poor".
                continue;
            }
            empty += 1;
            match w.too_poor_for(q) {
                Some(s) => {
                    too_poor += 1;
                    // The claim the sentence makes has to be true of the world:
                    // this species really would answer from a richer patch.
                    assert!(
                        w.deposits
                            .iter()
                            .any(|d| d.species == s && q.could_answer_at_best_grade(&w.species, d)),
                        "seed {seed} {q:?}: named {} as merely too poor, and no \
                         patch of it could answer at any grade",
                        w.species(s).name()
                    );
                }
                None => {
                    // The stronger claim: nothing anywhere, at any grade.
                    assert!(
                        !w.deposits
                            .iter()
                            .any(|d| q.could_answer_at_best_grade(&w.species, d)),
                        "seed {seed} {q:?}: said nothing in this world answers, \
                         while a patch would answer at a better grade"
                    );
                }
            }
        }
    }
    assert!(
        empty >= 10 && too_poor >= 1,
        "{empty} empty answers and {too_poor} of the too-poor kind over 200 \
         seeds; this test needs both states to be exercising anything"
    );
}

/// **ONE VERB, AND IT IS "rename"** (ruling 1). Every species carries a
/// generated name from worldgen, so "may name it" is true in no state.
///
/// The scan is over the real table for a world where a species has been
/// discovered, not over a fixture, and it asserts the premise (that the clause
/// is present at all) before asserting the absence.
#[test]
fn the_naming_right_is_one_verb_and_never_implies_who_chose_the_name() {
    let (mut w, me) = joined(14247);
    let at = w.player(me).unwrap().pos;
    let Some(near) = w.nearest_answering(Question::Burns, at) else {
        panic!("seed 14247 should hold something that burns");
    };
    let species = w.deposit(near.deposit).unwrap().species;
    // Discovery through the real command, so `discoverer` is set the way the
    // game sets it.
    //
    // **THE WALK NEEDS ITS TICKS AND MY FIRST VERSION DID NOT GIVE THEM.**
    // `walk` submits the `MoveTo` and steps ONE tick; the body then moves a
    // tile per tick, so I asked for an `Assay` while the player was still
    // `near.distance` tiles short of the rock. My own premise guard below
    // caught it — "the assay did not record a discoverer" — rather than the
    // test passing on a species discovered some other way.
    walk(&mut w, me, Some(near.tile));
    for _ in 0..near.distance {
        step(&mut w, &[], &mut Vec::new());
    }
    assert_eq!(
        w.player(me).unwrap().pos,
        near.tile,
        "the walk did not arrive, so the assay below would be asked from the \
         wrong tile"
    );
    step(
        &mut w,
        &[Input::player(me, PlayerCommand::Assay)],
        &mut Vec::new(),
    );
    for _ in 0..sim::tuning::ASSAY_TICKS + 2 {
        step(&mut w, &[], &mut Vec::new());
    }
    let table = debug::species_table(&w);
    assert!(
        w.species(species).discoverer.is_some(),
        "the assay did not record a discoverer, so this test proves nothing"
    );
    assert!(
        table.contains("who may rename it"),
        "the discovery clause is missing its right:\n{table}"
    );
    assert!(
        !table.contains("who may name it"),
        "`may name it` is true in no state: every species is generated with a \
         name, so the verb is always `rename`:\n{table}"
    );
}

/// **`LADDER_TOP` IS THE LADDER'S TOP, DERIVED AND NOT TYPED** (ASSA-257).
///
/// The too-poor sentence points at sorting, and the only thing making that
/// honest is that the grade the condition is asked at is the best grade sorting
/// can reach. **So this test does not assert `LADDER_TOP == Grade::A`** — that
/// would just restate the constant. It walks `Grade::better` from the bottom,
/// the way `Sort` does, and asserts the walk ends where `LADDER_TOP` is. Add a
/// rung to the ladder and this reddens instead of the sentence quietly pointing
/// at a grade nothing can reach.
#[test]
fn the_grade_the_condition_asks_at_is_where_the_refining_ladder_tops_out() {
    assert!(
        sim::recipe::RecipeId::Sort.recipe().raises_grade,
        "`Sort` no longer raises a grade, so there is no ladder for the \
         too-poor sentence to point at"
    );
    // Climb from the worst grade exactly as repeated sorting would.
    let mut top = Grade::C;
    let mut rungs = 0;
    while let Some(next) = top.better() {
        top = next;
        rungs += 1;
        assert!(rungs < 16, "Grade::better does not terminate");
    }
    assert!(rungs > 0, "nothing can be lifted, so the clause is a lie");
    assert_eq!(
        top,
        sim::proximity::LADDER_TOP,
        "the ladder tops out at {top:?} and the condition is asked at {:?}; the \
         sentence would point at a grade sorting cannot reach",
        sim::proximity::LADDER_TOP
    );
}

/// **THE SENTENCE NEVER POINTS AT A LADDER THAT CANNOT ARRIVE** (ASSA-257,
/// Maren's condition).
///
/// For every species `too_poor_for` ever names, over a sweep: some patch of it
/// answers at the ladder's top, and that patch is **below** the top — so a sort
/// path genuinely exists. If either half failed, the clause would be "walk
/// further" relocated: spend ore and end in the same dead end.
///
/// Non-vacuity is asserted, because the too-poor state is the rarer of the two
/// empty answers and a sweep that never reached it would pass by doing nothing.
#[test]
fn every_species_the_too_poor_answer_names_can_be_lifted_to_one_that_answers() {
    let mut named = 0;
    for seed in 0..200 {
        let (w, me) = joined(seed);
        let at = w.player(me).unwrap().pos;
        for q in Question::ALL {
            if w.nearest_answering(q, at).is_some() {
                continue;
            }
            let Some(s) = w.too_poor_for(q) else {
                continue;
            };
            named += 1;
            let liftable = w.deposits.iter().any(|d| {
                d.species == s
                    && q.could_answer_at_best_grade(&w.species, d)
                    && d.grade() != sim::proximity::LADDER_TOP
            });
            assert!(
                liftable,
                "seed {seed} {q:?}: the sentence names {} as merely too poor, \
                 so it tells the player sorting lifts a grade - and no patch of \
                 it both answers at the ladder's top and sits below it",
                w.species(s).name()
            );
        }
    }
    assert!(
        named > 0,
        "the too-poor answer never fired over 200 seeds, so this test asserted \
         nothing about the clause it guards"
    );
}

/// The OTHER empty answer gets no ladder clause, because no ladder helps there.
///
/// `nothing_answers` is the case where no species in the world could answer at
/// any grade; pointing at sorting would be exactly the lie Maren's condition
/// exists to prevent. Asserted on the sim's own two sentences rather than on a
/// rendered line.
#[test]
fn the_plain_empty_answer_offers_no_ladder() {
    for q in Question::ALL {
        let plain = debug::nothing_answers(q);
        assert!(
            !plain.contains("sorting"),
            "the no-species-at-all sentence offers the ladder, which cannot \
             help when nothing in the world answers at any grade: {plain}"
        );
        let too_poor = debug::too_poor_answer(q, "Xite");
        assert!(
            too_poor.contains("sorting lifts a grade"),
            "the too-poor sentence lost the ladder clause: {too_poor}"
        );
        assert!(
            !too_poor.to_lowercase().contains("go and")
                && !too_poor.to_lowercase().contains("you should"),
            "the clause states a fact about the rock, never an instruction \
             (Maren, ASSA-257): {too_poor}"
        );
    }
}
