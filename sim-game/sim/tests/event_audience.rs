//! **ONE DESCRIBER, TWO READERS, AND THE DIFFERENCE IS A BUILDING REFERENCE**
//! (ASSA-222, Game Director's ruling: *"the audience is a PARAMETER of the one
//! describer, never a second describer"*).
//!
//! The defect was one sentence doing two incompatible jobs. `sim-cli` prints
//! `you took 10 Minyte refined (A) from building 0` and the `0` is **the handle
//! you type next** — `Take`/`Pickup` take a `BuildingId`, so printing it is
//! principle 2 of the repo's `CLAUDE.md` working as designed. The Godot client
//! renders the same string into a window with no command line, where the `0` is
//! an index a player can do nothing with (Nerite, at 1x: *"'building 0' (an id,
//! not a building name)"*).
//!
//! **WHAT THESE TESTS GUARD IS THE NARROWNESS OF THE PARAMETER**, because that
//! is the thing that could rot. An audience argument is one short step from two
//! lists of which events are worth saying, which is the host-side drift the
//! consolidation into `event_line` removed and which the Game Director said she
//! would refuse. So: both readers hear about every event, the attention set is
//! identical for both, and any sentence that does not mention a building is
//! **byte-identical** between them.
//!
//! THE CORPUS IS A REAL PLAY-THROUGH, not a list of hand-built `Event`s, and
//! that is deliberate: a fixture that synthesises events can keep passing while
//! the sim emits a shape it has never seen. The one exception is labelled where
//! it appears.

use sim::tuning::{FUEL_MIN_REACTIVITY, HAND_SPARK_TEMPERATURE, SMELTER_INPUT_CAP};
use sim::{
    BuildingId, Event, Grade, Input, Item, ItemKind, PlayerCommand, PlayerId, Sheet, Slot,
    SpeciesId, SystemCommand, TilePos, World, WorldConfig, debug, step,
};

const WALLS: SpeciesId = SpeciesId(0);
const FUEL: SpeciesId = SpeciesId(1);

fn sheet(hardness: u8, heat: u8, reactivity: u8) -> Sheet {
    Sheet {
        density: 50,
        strength: 50,
        hardness,
        heat_tolerance: heat,
        reactivity,
        conductivity: 50,
    }
}

fn ore(species: SpeciesId) -> Item {
    Item::new(ItemKind::Ore, species, Grade::A)
}

/// **A WHOLE SMELTER LIFE, THROUGH THE REAL COMMANDS**: place it, fuel it, feed
/// it, let it smelt, take the output, pick the building back up. That sequence
/// is chosen because it is the only one that emits all five events carrying a
/// `BuildingId` — `BuildingPlaced`, `ItemsInserted`, `ItemSmelted`,
/// `ItemsTaken`, `BuildingRemoved` — so the corpus covers every arm this item
/// changed without naming them.
///
/// **TWO WORLDS COME BACK AND THAT IS THE POINT.** `live` is cloned while the
/// building is still standing; `world` is the end state, after it has been
/// picked up. A describer is handed one or the other on purpose: the naming path
/// only exists in `live`, and `building_ref`'s fallback only in `world`. Testing
/// both against the end state is the mistake this split exists to stop — it
/// would have made the naming assertion pass on the fallback.
struct Life {
    live: World,
    world: World,
    me: PlayerId,
    id: BuildingId,
    events: Vec<Event>,
}

fn a_smelters_life() -> Life {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    world.species_mut(WALLS).sheet = sheet(30, 60, FUEL_MIN_REACTIVITY as u8 - 1);
    world.species_mut(FUEL).sheet = sheet(30, HAND_SPARK_TEMPERATURE as u8, 60);
    let mut events = Vec::new();
    // **TWO PLAYERS, AND THE SECOND ONE IS NOT DECORATION.** With only a reader
    // in the world, `PlayerJoined` takes the `me ==` arm and the other arm is
    // unreachable — so the corpus held exactly ONE building-free sentence and my
    // first mutation of `a_sentence_without_a_building_is_byte_identical` patched
    // a branch nothing visited and stayed green. A joiner who is not the reader
    // covers both arms, and with them the pronoun split this describer has got
    // wrong twice (ASSA-74).
    step(
        &mut world,
        &[
            Input::System(SystemCommand::AddPlayer { name: "ada".into() }),
            Input::System(SystemCommand::AddPlayer { name: "bex".into() }),
        ],
        &mut events,
    );
    let me = PlayerId(0);

    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
    let inv = |world: &mut World, item: Item, n: u32| {
        world.player_mut(me).expect("joined").inventory.add(item, n);
    };
    inv(&mut world, smelter, 1);
    // Three to smelt, then more than a full slot's worth to get clamped. See
    // the over-cap `Insert` below for why that matters.
    inv(&mut world, ore(WALLS), 3 + SMELTER_INPUT_CAP + 2);
    inv(&mut world, ore(FUEL), 1);

    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 1, spawn.y);
    let id = BuildingId(0);

    step(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place { item: smelter, pos },
        )],
        &mut events,
    );
    assert!(
        world.building(id).is_some(),
        "the smelter was not placed, so this corpus proves nothing: {events:?}"
    );
    step(
        &mut world,
        &[
            Input::player(
                me,
                PlayerCommand::Insert {
                    building: id,
                    slot: Slot::Input,
                    item: ore(WALLS),
                    count: 3,
                },
            ),
            Input::player(
                me,
                PlayerCommand::Insert {
                    building: id,
                    slot: Slot::Fuel,
                    item: ore(FUEL),
                    count: 1,
                },
            ),
        ],
        &mut events,
    );
    // Long enough for the fire to reach temperature and one unit to refine.
    for _ in 0..400 {
        step(&mut world, &[], &mut events);
    }
    step(
        &mut world,
        &[Input::player(me, PlayerCommand::Take { building: id })],
        &mut events,
    );
    // **ONE LOUD EVENT, AND IT TOOK ME TWO WRONG GUESSES TO GET HERE.** The
    // corpus needs something `event_needs_attention` calls loud, and I twice
    // asserted it already had one by reasoning about the smelter: first "the
    // fire starts cold", then "feed a smelter whose fuel is spent". Both were
    // false -- fuel and ore go in on the same tick, and there was burn left --
    // and both times the loud count came back 0.
    //
    // So I read the function instead of reasoning about it. A clamped insert is
    // loud (`ItemsInserted { left > 0 }`, ASSA-48: the leftover is the half a
    // player can act on) and it is the CHEAPEST loud event that also carries a
    // `BuildingId`, which is what this file is about. A stall would have worked
    // too and cost thermodynamics I kept getting wrong.
    step(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Insert {
                building: id,
                slot: Slot::Input,
                item: ore(WALLS),
                count: SMELTER_INPUT_CAP + 2,
            },
        )],
        &mut events,
    );
    // **AND A REAL `SmelterStalled`, BECAUSE A SOURCE SCAN IS NOT A READING.**
    // `host_neutral.rs` now forbids a bare `building.0` outside a typed arm, and
    // that is the guard that would have caught the four arms I missed. But a
    // scan proves the id is gone, not that the sentence reads — so the corpus
    // takes the stall too, and it is the cheapest way to get one: the fire burns
    // out, then ore goes into a cold smelter with no fuel left.
    //
    // This is the arm that matters most of the four. `SmelterStalled` is LOUD,
    // so it lands on the always-visible status line — the surface ASSA-89 built
    // precisely because the log gets missed — and it was carrying `smelter 0`.
    for _ in 0..600 {
        step(&mut world, &[], &mut events);
    }
    step(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Insert {
                building: id,
                slot: Slot::Input,
                item: ore(WALLS),
                count: 1,
            },
        )],
        &mut events,
    );
    for _ in 0..40 {
        step(&mut world, &[], &mut events);
    }
    let live = world.clone();
    assert!(
        live.building(id).is_some(),
        "`live` is supposed to still have the building in it"
    );
    step(
        &mut world,
        &[Input::player(me, PlayerCommand::Pickup { building: id })],
        &mut events,
    );
    Life {
        live,
        world,
        me,
        id,
        events,
    }
}

/// Every event in the corpus, both ways, as `(typed, pointed)`.
fn both_ways(world: &World, me: PlayerId, events: &[Event]) -> Vec<(String, String)> {
    events
        .iter()
        .map(|e| {
            (
                debug::event_line(world, Some(me), e, debug::Audience::Typed),
                debug::event_line(world, Some(me), e, debug::Audience::Pointed),
            )
        })
        .collect()
}

/// **THE FIXTURE'S OWN PREMISE, FIRST.** Every assertion in this file is about a
/// corpus, so a corpus that quietly stopped containing the interesting events
/// would make all of them vacuous — the shape that has cost me three separate
/// findings this week.
#[test]
fn the_corpus_contains_every_event_that_carries_a_building() {
    let life = a_smelters_life();
    let kinds: Vec<&str> = life
        .events
        .iter()
        .map(|e| match e {
            Event::BuildingPlaced { .. } => "placed",
            Event::ItemsInserted { .. } => "inserted",
            Event::ItemSmelted { .. } => "smelted",
            Event::ItemsTaken { .. } => "taken",
            Event::BuildingRemoved { .. } => "removed",
            Event::SmelterStalled { .. } => "stalled",
            _ => "other",
        })
        .collect();
    // `stalled` IS IN THIS LIST BECAUSE IT WAS NOT, AND THAT IS HOW FOUR ARMS
    // KEPT A BARE ID THROUGH SLICE 2 (ASSA-244). It is also the one I am least
    // willing to assert by reasoning: twice on this file I claimed the corpus
    // held a loud event because of how I thought the smelter worked, and twice
    // the count was 0.
    for want in [
        "placed", "inserted", "smelted", "taken", "removed", "stalled",
    ] {
        assert!(
            kinds.contains(&want),
            "the corpus has no {want} event, so every test in this file is \
             vacuous for that arm. Got: {kinds:?}"
        );
    }
    assert!(
        kinds.contains(&"other"),
        "the corpus has no building-free event either, and \
         `a_sentence_without_a_building_is_byte_identical` needs one to mean \
         anything. Got: {kinds:?}"
    );
}

/// **NEITHER READER IS EVER TOLD LESS THAN THE OTHER** — the condition the Game
/// Director put on her ruling, and the one thing an audience parameter must
/// never grow into. If an arm ever returns nothing for one reader, the parameter
/// has started deciding *whether* to speak instead of *how*.
#[test]
fn no_audience_arm_decides_whether_to_speak() {
    let life = a_smelters_life();
    for (typed, pointed) in both_ways(&life.live, life.me, &life.events) {
        assert!(
            !typed.trim().is_empty() && !pointed.trim().is_empty(),
            "one reader got silence:\ntyped:   {typed:?}\npointed: {pointed:?}"
        );
    }
}

/// **LOUDNESS TAKES A READER BUT NOT AN AUDIENCE, AND THE DIFFERENCE IS THE
/// WHOLE RULING.** `event_needs_attention(me, event)` is per-*player* — your own
/// refusal is loud to you and quiet to everyone else — and that is a fact about
/// the world, so the sim owns it. What it must never take is an *audience*,
/// because that would let one host's reader be told about things another's is
/// not, and the Godot client's `attention_lines` is advertised as a filtered
/// `event_lines`, word for word.
///
/// The no-audience half is structural (the signature cannot see one), so what is
/// left to measure is the consequence that would actually hurt: **every event
/// the sim calls loud must be sayable to both readers.** An audience arm that
/// returned nothing for a loud event would put a blank notice on the one surface
/// a player cannot miss — the always-visible status line, with the log hidden.
#[test]
fn every_loud_event_is_sayable_to_both_readers() {
    let life = a_smelters_life();
    let mut loud_count = 0;
    for event in &life.events {
        if !debug::event_needs_attention(Some(life.me), event) {
            continue;
        }
        loud_count += 1;
        for audience in [debug::Audience::Typed, debug::Audience::Pointed] {
            let line = debug::event_line(&life.live, Some(life.me), event, audience);
            assert!(
                !line.trim().is_empty(),
                "a loud event is silent for {audience:?}, so the status line \
                 would carry a blank: {event:?}"
            );
        }
    }
    // **NON-VACUITY IS THE POINT HERE, AND IT EARNED ITS KEEP TWICE.** A corpus
    // with nothing loud in it passes this test by skipping every iteration. I
    // claimed the corpus already had a loud event in it twice, both times by
    // reasoning about the smelter rather than measuring, and both times this
    // line came back with a loud count of 0. The fixture now causes one on
    // purpose, picked by reading `event_needs_attention`.
    assert!(
        loud_count > 0,
        "nothing in the corpus needed attention, so this guard measured \
         nothing. Events: {:?}",
        life.events
    );
}

/// **THE NARROWNESS, STATED AS AN EQUALITY.** This is the assertion I would keep
/// if I could keep only one: a sentence with no building in it is the *same
/// bytes* for both readers. It is what makes "the audience changes how a
/// building is referred to and nothing else" a fact rather than a comment, and
/// it fails the moment somebody reaches for this parameter to reword something
/// else — a grade, a tick, a pronoun, a count.
#[test]
fn a_sentence_without_a_building_is_byte_identical() {
    let life = a_smelters_life();
    let mut compared = 0;
    for (event, (typed, pointed)) in
        life.events
            .iter()
            .zip(both_ways(&life.live, life.me, &life.events))
    {
        // **READ OFF THE EVENT, NOT OFF A LIST I TYPED — AND THIS IS A FIX, NOT
        // A TIDY-UP.** This was a `matches!` over five variants, and I wrote
        // those five from the arms I had just edited. So when it turned out I
        // had MISSED four arms that print the id (`MachinePlaced`,
        // `MachineMined`, `MachineStalled`, `SmelterStalled` — they spell it
        // `machine {}` and `smelter {}`, which my grep never saw), this test
        // classified all four as "no building in it" and asserted the two
        // audiences were byte-identical — which they were, because I had never
        // given those arms an audience. **The test agreed with my blind spot.**
        //
        // The derivation cannot: an event carries a building iff its own `Debug`
        // says so. A variant added tomorrow is classified by its fields rather
        // than by my memory of them.
        if format!("{event:?}").contains("building: BuildingId(") {
            continue;
        }
        compared += 1;
        assert_eq!(
            typed, pointed,
            "the audience reworded a sentence that has no building in it, which \
             is outside the ruling it exists for: {event:?}"
        );
    }
    // **MORE THAN ONE, AND THE NUMBER IS THE LESSON.** `> 0` was the original
    // bar and it was too weak: the corpus had exactly one building-free sentence
    // (`PlayerJoined` taking the `me ==` arm), so a mutation of the OTHER arm
    // left this test green. Two players make both arms reachable, and this bar
    // now fails if the corpus ever shrinks back to the version that fooled me.
    assert!(
        compared > 1,
        "only {compared} building-free sentence(s) compared. One is enough to \
         be non-vacuous and not enough to be a guard: a sentence the corpus \
         never reaches cannot be caught."
    );
}

/// **WHAT EACH READER ACTUALLY GETS**, on the one event where both readers have
/// a live building to refer to. Asserted on the real species name out of the
/// world rather than a literal, because no rule or recipe may name a species.
#[test]
fn the_typed_reader_keeps_the_handle_and_the_pointer_gets_a_noun() {
    let life = a_smelters_life();
    let taken = life
        .events
        .iter()
        .find(|e| matches!(e, Event::ItemsTaken { .. }))
        .expect("the corpus takes the output");

    // Against `live`, so the pointing reader's line comes from the NAMING path
    // and not from the fallback that also contains an id.
    let building = life.live.building(life.id).expect("`live` still has it");
    let noun = debug::building_name(&life.live, building);

    let typed = debug::event_line(&life.live, Some(life.me), taken, debug::Audience::Typed);
    let pointed = debug::event_line(&life.live, Some(life.me), taken, debug::Audience::Pointed);

    assert!(
        typed.contains(&format!("building {}", life.id.0)),
        "the typed reader lost the handle they pass to `take`, which is \
         principle 2 regressing: {typed}"
    );
    assert!(
        pointed.contains(&noun),
        "the pointing reader was not told WHICH building, which is the whole \
         defect Nerite reported at 1x.\nwanted: {noun}\ngot:    {pointed}"
    );
    assert!(
        !pointed.contains("building "),
        "the pointing reader still carries a handle with nothing to type it \
         into: {pointed}"
    );
    // THE GRADE STAYS, and it stays because the Game Director ruled it does:
    // it is a real property of a real thing, and the place it gets explained is
    // the map key (ASSA-230), not a longer log line. `building_name` carries it,
    // so this is an assertion about her ruling and not about the helper.
    assert!(
        noun.contains('(') && pointed.contains(&noun),
        "the grade left the building's name: {noun}"
    );
}

/// **THE FALLBACK, AND THE ONE SYNTHESISED EVENT IN THIS FILE, LABELLED.**
///
/// No real play reaches it: `ItemsTaken` fires while the building stands, and
/// `BuildingRemoved`'s arm drops the reference for a pointing reader rather than
/// naming a building that is already gone. So the only way to exercise
/// `building_ref`'s `None` branch is to describe a building-carrying event
/// against a world that no longer has the building — which is exactly what a
/// client does when it renders a log line a few ticks after the event, and is
/// therefore worth pinning rather than leaving to chance.
///
/// The id is the only true thing left at that point, and both readers get it.
#[test]
fn a_vanished_building_leaves_the_id_as_the_only_true_thing() {
    let life = a_smelters_life();
    assert!(
        life.world.building(life.id).is_none(),
        "this test needs the building gone, which is how the corpus ends"
    );
    let taken = life
        .events
        .iter()
        .find(|e| matches!(e, Event::ItemsTaken { .. }))
        .expect("the corpus takes the output");
    let pointed = debug::event_line(&life.world, Some(life.me), taken, debug::Audience::Pointed);
    assert!(
        pointed.contains(&format!("building {}", life.id.0)),
        "with nothing left to name, the pointing reader should still get the \
         id rather than an empty phrase or a panic: {pointed}"
    );
}
