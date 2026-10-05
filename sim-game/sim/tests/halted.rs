//! **A STALL IS A CONDITION, NOT A LINE** (Game Director, ASSA-94).
//!
//! The stall *events* are edges: each fires once, on the tick it happens, and
//! is gone. `World::halted` is the question a host may ask on any tick
//! afterwards, which is what a surface that outlives a scrolling log needs.
//!
//! The case this file exists for is the board's own co-op session. Their
//! `SmelterStalled` fired correctly, once — into a fourteen-line log, where it
//! survived about a second. Ninety thousand ticks later the smelter was still
//! cold and two people sat beside it not knowing why.
//!
//! `tests/smelter.rs` pins the rules that get a smelter into each stall and
//! `tests/tools.rs` pins what a drill does; this file pins only that a
//! stopped machine stays *askable*, and in one vocabulary.

use sim::tuning::{HAND_MINE_MAX_HARDNESS, YIELD_BY_GRADE};
use sim::{
    Assembly, BuildingId, BuildingKind, DepositId, Event, Grade, Input, Item, ItemKind,
    MachineIdle, MachineStall, MachineState, Mount, PART_SPECS, Part, PartKind, PlayerCommand,
    PlayerId, Sheet, Slot, SmelterStall, SmelterState, Source, SpeciesId, Stat, SystemCommand,
    TilePos, World, WorldConfig, step,
};

const WALLS: SpeciesId = SpeciesId(0); // smelter material, and the ore it can take
const HOT_FUEL: SpeciesId = SpeciesId(3); // burns, and nothing here lights it: the board's Zuxite
const ROCK: SpeciesId = SpeciesId(4); // what a drill digs

const PLANTED: PartKind = PartKind::Frame(Mount::Planted);

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

fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    for s in &mut world.species {
        s.assayed = true;
    }
    world.species_mut(WALLS).sheet = sheet(30, 60, 1);
    // Reactivity 100 clears the fuel gate; heat tolerance 90 is far over the
    // hand spark, so it IS fuel and nothing in this world can light it. That
    // is the shape of the rock the board loaded fifty units of.
    world.species_mut(HOT_FUEL).sheet = sheet(30, 90, 100);
    world.species_mut(ROCK).sheet = sheet(30, 60, 1);
    // **ASKED OF THE SIM, NOT OF THE LITERALS ABOVE.** The fixture is only
    // the board's case if `ladder` agrees this is real fuel that nothing in
    // this world can light; comparing the numbers I just typed to the tuning
    // constants would restate the sheet rather than test it, and would still
    // pass if the fuel gate moved under it.
    assert!(
        sim::ladder::fuel_grade(world.species(HOT_FUEL)).is_some(),
        "the fixture's fuel must actually be fuel"
    );
    assert_eq!(
        sim::ladder::lighting(&world.species, HOT_FUEL),
        sim::ladder::Lighting::NothingBurnsHotEnough,
        "nothing in this world may be able to light it, or the central case \
         here is not the board's case"
    );
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

fn run(world: &mut World, inputs: &[Input], ticks: u32) -> Vec<Event> {
    let mut events = Vec::new();
    step(world, inputs, &mut events);
    for _ in 1..ticks {
        step(world, &[], &mut events);
    }
    events
}

fn ore(species: SpeciesId) -> Item {
    Item::new(ItemKind::Ore, species, Grade::A)
}

fn refined(species: SpeciesId) -> Item {
    Item::new(ItemKind::Refined, species, Grade::B)
}

/// A drill with one hopper, planted on `pos`, built through the real commands.
fn plant_drill(world: &mut World, me: PlayerId, pos: TilePos) -> BuildingId {
    let assembly = Assembly::new(
        Part::of(PLANTED, refined(ROCK)),
        vec![
            Part::of(PartKind::Head, refined(ROCK)),
            Part::of(PartKind::Hopper, refined(ROCK)),
        ],
    );
    for item in assembly.part_items() {
        world.player_mut(me).unwrap().inventory.add(item, 1);
    }
    world.player_mut(me).unwrap().pos = pos;
    let before = world.buildings.len();
    let events = run(
        world,
        &[Input::player(
            me,
            PlayerCommand::Assemble {
                frame: assembly.frame.as_item(),
                mounted: assembly.mounted.iter().map(Part::as_item).collect(),
            },
        )],
        1,
    );
    let index = events
        .iter()
        .find_map(|e| match e {
            Event::Assembled { assembly, .. } => Some(*assembly),
            _ => None,
        })
        .expect("the assemble must have produced a design");
    run(
        world,
        &[Input::player(
            me,
            PlayerCommand::PlaceAssembly {
                assembly: index,
                pos,
            },
        )],
        1,
    );
    assert_eq!(
        world.buildings.len(),
        before + 1,
        "the drill must plant, or every state below is about nothing"
    );
    world.buildings.last().expect("just planted").id
}

/// Move deposit 0 under `pos` and make it `ROCK` at grade B.
fn deposit_under(world: &mut World, pos: TilePos) -> DepositId {
    let id = DepositId(0);
    let d = world.deposit_mut(id).unwrap();
    d.species = ROCK;
    d.purity = 50;
    d.amount = 10_000;
    // `contains` is a radius around the centre, so moving the centre moves the
    // whole deposit.
    d.center = pos;
    assert!(
        world.deposit(id).unwrap().contains(pos),
        "the deposit must actually cover the tile it was moved to"
    );
    id
}

/// Move every deposit off `pos`, so `deposit_at` finds nothing there.
///
/// Needed because the starter ladder guarantees deposits in the chunks beside
/// spawn: moving the one deposit a test placed is not enough, and the first
/// version of this file read a *different* deposit's hardness and called it
/// "no deposit underneath".
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
        "the tile must really be bare, or 'no deposit' is untested"
    );
}

fn state_of(world: &World, id: BuildingId) -> MachineState {
    let b = world.building(id).unwrap();
    let BuildingKind::Machine(m) = &b.kind else {
        panic!("building {} is not a machine", id.0)
    };
    world.machine_state(b, m)
}

/// The reason portion of a halt line.
///
/// **IT TAKES THE FIRST FIELD NOW, NOT THE LAST** (ASSA-94). This read
/// "everything after the address" and returned `.1`, because the line used to be
/// `address · reason`. The Game Director reversed it on the 1x shot — *"a
/// stopped-machine line exists to say what to do, and 'no fuel' is that; the
/// identity is how you find it afterwards"* — so the reason is the leading
/// field. Two tests failed on this one helper, and both were right to.
///
/// The address half still contains a ` · `-free name, so a single split is
/// enough: `splitn` from the left takes the reason whole.
fn reason_in(line: &str) -> &str {
    line.split_once(" · ")
        .expect("a halt line is a reason and an address")
        .0
}

// ---------------------------------------------------------------------------
// The property the item is about
// ---------------------------------------------------------------------------

/// **THE BOARD'S OWN INCIDENT, AND THE ONE THAT MATTERS.**
///
/// Insert ore and a fuel nothing can light, then run far past the moment the
/// event fired. The event is correct and gone; the condition is still true, so
/// the standing surface must still say it — in `stall_reason`'s words.
#[test]
fn a_cold_smelter_is_still_reported_long_after_its_event_has_scrolled_away() {
    let (mut world, me) = world_with_player();
    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
    world.player_mut(me).unwrap().inventory.add(smelter, 1);
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 1, spawn.y);
    run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place { item: smelter, pos },
        )],
        1,
    );
    let id = BuildingId(0);
    world.player_mut(me).unwrap().inventory.add(ore(WALLS), 5);
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(HOT_FUEL), 50);

    let events = run(
        &mut world,
        &[
            Input::player(
                me,
                PlayerCommand::Insert {
                    building: id,
                    slot: Slot::Input,
                    item: ore(WALLS),
                    count: 5,
                },
            ),
            Input::player(
                me,
                PlayerCommand::Insert {
                    building: id,
                    slot: Slot::Fuel,
                    item: ore(HOT_FUEL),
                    count: 50,
                },
            ),
        ],
        20,
    );
    let announced: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, Event::SmelterStalled { .. }))
        .collect();
    assert_eq!(
        announced.len(),
        1,
        "ASSA-80's edge must still fire exactly once, or this test is \
         measuring a different bug: {events:?}"
    );
    assert_eq!(
        world.smelter_state(world.building(id).unwrap()),
        SmelterState::Stalled(SmelterStall::FuelWontLight),
        "the fixture must reproduce the board's stall and not some other one"
    );

    // Now the part that was missing. Run on, far past anything a log holds.
    let later = run(&mut world, &[], 5_000);
    assert!(
        !later
            .iter()
            .any(|e| matches!(e, Event::SmelterStalled { .. })),
        "a smelter that sits stalled must not shout (ASSA-80 rule 2)"
    );
    let lines = sim::debug::halt_lines(&world, sim::debug::Audience::Typed);
    assert_eq!(
        lines.len(),
        1,
        "the standing condition must survive the event: {lines:?}"
    );
    assert_eq!(
        reason_in(&lines[0]),
        format!(
            "stalled: {}",
            sim::debug::stall_reason(SmelterStall::FuelWontLight)
        ),
        "the reason is stall_reason's own words, never a second wording"
    );
    assert!(
        lines[0].contains(&format!("at ({}, {})", pos.x, pos.y)),
        "a player has to be able to walk to it: {}",
        lines[0]
    );
}

/// **`idle: nothing to refine` MUST NEVER APPEAR HERE** (Game Director,
/// ASSA-94): it follows every finished batch, so a surface that listed it
/// would cry wolf after every successful smelt.
#[test]
fn a_smelter_with_nothing_in_it_is_not_something_to_fix() {
    let (mut world, me) = world_with_player();
    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
    world.player_mut(me).unwrap().inventory.add(smelter, 1);
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 1, spawn.y);
    run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place { item: smelter, pos },
        )],
        1,
    );
    let b = world.building(BuildingId(0)).unwrap();
    assert_eq!(
        world.smelter_state(b),
        SmelterState::Idle,
        "a smelter is placed empty, so the fixture must be the idle case"
    );
    assert!(!world.building_state(b).halted());
    assert_eq!(
        sim::debug::halt_lines(&world, sim::debug::Audience::Typed),
        Vec::<String>::new(),
        "an empty smelter is not a problem"
    );
    // And the sentence itself is nowhere near this surface.
    let table = sim::debug::halted_table(&world);
    assert!(
        !table.contains("nothing to refine"),
        "the idle sentence must not reach the halt surface: {table}"
    );
}

/// The deliberate opposite of the test above, asserted so the two can never be
/// quietly "reconciled".
///
/// A smelter's idle resolves itself the moment somebody inserts. A machine's
/// idle means it was *planted where it cannot work*, which never resolves on
/// its own — and the player has already paid for it.
#[test]
fn a_drill_that_is_merely_idle_is_something_to_fix_and_a_smelter_is_not() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let nowhere = TilePos::new(spawn.x + 4, spawn.y + 4);
    clear_deposits_from(&mut world, nowhere);
    let id = plant_drill(&mut world, me, nowhere);
    assert_eq!(
        state_of(&world, id),
        MachineState::Idle(MachineIdle::NoDeposit)
    );
    assert!(
        world.building_state(world.building(id).unwrap()).halted(),
        "a drill on nothing is eight refined doing nothing: it must be reported"
    );
    assert_eq!(
        sim::debug::halt_lines(&world, sim::debug::Audience::Typed).len(),
        1,
        "the idle drill is the one thing reported"
    );
    assert_ne!(
        SmelterState::Idle.halted(),
        MachineState::Idle(MachineIdle::NoDeposit).halted(),
        "the asymmetry is the ruling, not an oversight: a smelter's idle is \
         normal and a machine's idle is a misplacement"
    );
}

/// **THE COUNT IS THE SIM'S SENTENCE AND IT IS WORDED EXACTLY ONCE** (ASSA-94).
///
/// The Game Director ruled the count the floor of this surface: *"a player who
/// reads '3 machines stopped' and can see one reason knows there are two more to
/// find."* The window declined one, on the correct objection that a count would
/// be a second claim about the world — and the sim was already making it, inside
/// `halted_table`'s first line, where no host could reach it.
///
/// **AND THE LAST ASSERTION IS HERE BECAUSE A MUTATION PASSED WITHOUT IT.** I
/// wrote the two below first and said in the pull request that they required the
/// table's first line to *be* the summary rather than to resemble it. They do
/// not. I put `halted_table`'s own `format!("{} of {} buildings stopped:\n", …)`
/// back, which is precisely the duplication this split removes, and all nine
/// tests in this file stayed green — because a faithful copy produces identical
/// TEXT, and text is all an equality over output can see. The drift it is meant
/// to catch is a FUTURE edit to one wording that the other does not follow, and
/// no comparison of today's two strings can observe that.
///
/// So the call itself is asserted, in the source, the same weaker-but-real trick
/// the client tests use for a disc nothing headless can read. It is brittle to
/// reformatting on purpose: re-duplicating the sentence must cost somebody a red
/// test, and nothing else here can make it.
#[test]
fn the_stopped_count_is_one_sentence_the_table_and_a_window_both_read() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let nowhere = TilePos::new(spawn.x + 4, spawn.y + 4);
    clear_deposits_from(&mut world, nowhere);
    plant_drill(&mut world, me, nowhere);
    let stopped = sim::debug::halt_lines(&world, sim::debug::Audience::Typed).len();
    assert_eq!(
        stopped, 1,
        "the fixture must stop exactly one of the buildings"
    );
    assert_eq!(
        sim::debug::halt_summary(&world),
        format!("1 of {} buildings stopped", world.buildings.len())
    );
    let table = sim::debug::halted_table(&world);
    assert_eq!(
        table.lines().next().unwrap(),
        format!("{}:", sim::debug::halt_summary(&world)),
        "the terminal's first line and the summary disagree: {table}"
    );
    // THE ONLY ASSERTION HERE A RE-DUPLICATION CANNOT SURVIVE. See the note above:
    // the equality on the line before passes on a faithful copy.
    let source = include_str!("../src/debug.rs");
    assert!(
        source.contains(r#"format!("{}:\n", halt_summary(world))"#),
        "`halted_table` no longer builds its first line out of `halt_summary`, \
         so the count is worded in two places again and they are free to drift"
    );
}

/// **A COUNT OF ZERO IS NOT DRAWN** (Game Director, ASSA-94): a surface saying
/// "0 stopped" in the healthy case is the cry-wolf failure one step removed.
///
/// The summary is empty rather than `"0 of 2 buildings stopped"`, so a host
/// cannot render one by accident — the emptiness is the instruction. The
/// terminal keeps its own fuller sentence, because a reply to a typed `halted`
/// has to say something, and the two are deliberately not the same string.
#[test]
fn nothing_stopped_is_an_empty_summary_and_a_spoken_table() {
    let (mut world, me) = world_with_player();
    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
    world.player_mut(me).unwrap().inventory.add(smelter, 1);
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 1, spawn.y);
    run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place { item: smelter, pos },
        )],
        1,
    );
    assert!(
        sim::debug::halt_lines(&world, sim::debug::Audience::Typed).is_empty(),
        "the fixture must have nothing stopped, or this test is about nothing"
    );
    assert_eq!(sim::debug::halt_summary(&world), "");
    assert!(
        sim::debug::halted_table(&world).contains("Nothing has stopped"),
        "the terminal still answers a typed `halted`"
    );
}

/// Every state a machine can be in is reachable, and each has its own
/// sentence.
///
/// **NON-VACUITY IS AN EQUALITY, NOT A FLOOR**: the set of states observed is
/// compared to the whole set, so a case that stops being reachable fails here
/// instead of quietly shrinking the test.
#[test]
fn all_five_machine_states_are_reachable_and_each_says_its_own_thing() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 3, spawn.y);
    let deposit = deposit_under(&mut world, pos);
    let id = plant_drill(&mut world, me, pos);

    let mut seen: Vec<(MachineState, String)> = Vec::new();
    let mut observe = |world: &World| {
        let state = state_of(world, id);
        seen.push((state, sim::debug::machine_state_line(world, state)));
    };

    // 1. Working, on a good deposit.
    observe(&world);
    // 2. Buffer full: let it mine until it stops.
    run(&mut world, &[], 4_000);
    observe(&world);
    // 3. Too hard: harden the rock past the hand gate.
    world.species_mut(ROCK).sheet.hardness = HAND_MINE_MAX_HARDNESS as u8 + 1;
    observe(&world);
    world.species_mut(ROCK).sheet.hardness = 30;
    // 4. Mined out.
    world.deposit_mut(deposit).unwrap().amount = 0;
    observe(&world);
    // 5. No deposit at all: clear every deposit off the drill's tile.
    clear_deposits_from(&mut world, pos);
    observe(&world);

    let kinds: Vec<&str> = seen
        .iter()
        .map(|(s, _)| match s {
            MachineState::Working { .. } => "working",
            MachineState::Stalled(MachineStall::BufferFull { .. }) => "full",
            MachineState::Idle(MachineIdle::DepositTooHard { .. }) => "too hard",
            MachineState::Idle(MachineIdle::DepositMinedOut) => "mined out",
            MachineState::Idle(MachineIdle::NoDeposit) => "no deposit",
        })
        .collect();
    assert_eq!(
        kinds,
        vec!["working", "full", "too hard", "mined out", "no deposit"],
        "every state must be reached in order, or a sentence below is untested: \
         {seen:#?}"
    );

    let sentences: Vec<&str> = seen.iter().map(|(_, line)| line.as_str()).collect();
    assert_eq!(
        sentences[0],
        format!("mining {}", world.species(ROCK).name())
    );
    assert_eq!(sentences[1], "stalled: full, take the ore out");
    assert!(
        sentences[2].starts_with("idle: ") && sentences[2].contains("too hard"),
        "the hardness sentence is deposit_reach_note's: {}",
        sentences[2]
    );
    assert_eq!(sentences[3], "idle: deposit is mined out");
    assert_eq!(sentences[4], "idle: no deposit underneath");
    assert_eq!(
        sentences
            .iter()
            .collect::<std::collections::HashSet<_>>()
            .len(),
        5,
        "five states, five sentences: {sentences:#?}"
    );

    // Only the working one is not a problem.
    assert_eq!(
        seen.iter().filter(|(s, _)| s.halted()).count(),
        4,
        "everything except working is something a player must fix"
    );
}

/// **ONE VOCABULARY.** For every halted building, the reason on the halt
/// surface is character-for-character the state the status line prints.
///
/// Read out of the sim rather than restated here, so this test follows the
/// Game Director's wording wherever she moves it instead of pinning a copy
/// that can disagree with her.
#[test]
fn the_halt_surface_and_the_status_line_cannot_word_a_condition_differently() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();

    // A stalled smelter and a misplaced drill, so both kinds are covered.
    let smelter = Item::new(ItemKind::Smelter, WALLS, Grade::C);
    world.player_mut(me).unwrap().inventory.add(smelter, 1);
    let spos = TilePos::new(spawn.x + 1, spawn.y);
    run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Place {
                item: smelter,
                pos: spos,
            },
        )],
        1,
    );
    world.player_mut(me).unwrap().inventory.add(ore(WALLS), 5);
    world
        .player_mut(me)
        .unwrap()
        .inventory
        .add(ore(HOT_FUEL), 5);
    run(
        &mut world,
        &[
            Input::player(
                me,
                PlayerCommand::Insert {
                    building: BuildingId(0),
                    slot: Slot::Input,
                    item: ore(WALLS),
                    count: 5,
                },
            ),
            Input::player(
                me,
                PlayerCommand::Insert {
                    building: BuildingId(0),
                    slot: Slot::Fuel,
                    item: ore(HOT_FUEL),
                    count: 5,
                },
            ),
        ],
        5,
    );
    let dpos = TilePos::new(spawn.x + 5, spawn.y + 5);
    clear_deposits_from(&mut world, dpos);
    plant_drill(&mut world, me, dpos);

    let halted: Vec<_> = world.halted().map(|b| b.id).collect();
    assert_eq!(
        halted.len(),
        2,
        "one of each kind must be halted: {halted:?}"
    );

    let lines = sim::debug::halt_lines(&world, sim::debug::Audience::Typed);
    for (id, line) in halted.iter().zip(&lines) {
        let status = sim::debug::building_status(&world, world.building(*id).unwrap());
        let reason = reason_in(line);
        // A whole field of the status line, not a substring of one: the
        // smelter puts its state last and a machine puts it third, so
        // position is not the invariant — being the same sentence is.
        assert!(
            status.split(" · ").any(|field| field == reason),
            "the halt line's reason must be one of the status line's own \
             fields, character for character.\n\
             halt:   {reason}\n\
             status: {status}"
        );
    }
}

// ---------------------------------------------------------------------------
// The two assumptions the refactor rests on
// ---------------------------------------------------------------------------

/// `World::machine_state` decides on `stats().capacity`, while a menu shows
/// `stat_range()`'s banded reading. They can never disagree, and this is why:
/// **every `Capacity` contribution in the catalogue is flat from the part
/// kind**, so no reading of a material is involved at either end of the band.
///
/// Derived from the spec table rather than by calling both functions and
/// comparing, which would only prove it for whatever designs this test
/// happened to build.
#[test]
fn capacity_is_flat_so_a_banded_reading_cannot_disagree_with_the_rules() {
    let contributions: Vec<_> = PART_SPECS
        .iter()
        .flat_map(|spec| spec.contributions.iter())
        .filter(|c| c.stat == Stat::Capacity)
        .collect();
    assert!(
        !contributions.is_empty(),
        "no part contributes capacity, so this test proves nothing"
    );
    for c in contributions {
        assert!(
            matches!(c.source, Source::Flat(_)),
            "a capacity read off a material's sheet would make the banded \
             reading disagree with what the rules mine by: {c:?}"
        );
    }
}

/// The drill's stall event fires on the tick the buffer fills **even when the
/// last unit also empties the deposit**.
///
/// This is why `step` asks decision 9's predicate directly instead of
/// re-reading `machine_state` the way `announce_new_stalls` does: the deposit
/// arm comes first, so a re-read would answer `Idle(DepositMinedOut)` on this
/// exact tick and the stall would go silent.
#[test]
fn the_buffer_stall_is_announced_even_on_the_tick_the_deposit_runs_out() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 3, spawn.y);
    let deposit = deposit_under(&mut world, pos);
    let id = plant_drill(&mut world, me, pos);

    // Fill the buffer to one unit short of the stall, and leave the deposit
    // with exactly that one unit in it.
    let (capacity, amount) = {
        let b = world.building(id).unwrap();
        let BuildingKind::Machine(m) = &b.kind else {
            panic!("not a machine")
        };
        let grade = world.deposit(deposit).unwrap().grade();
        (
            m.assembly.stats(&world.species).capacity,
            YIELD_BY_GRADE[grade as usize],
        )
    };
    let target = capacity.saturating_sub(amount);
    {
        let b = world.building_mut(id).unwrap();
        let BuildingKind::Machine(m) = &mut b.kind else {
            panic!("not a machine")
        };
        m.held = Some(sim::ItemStack::new(ore(ROCK), target));
        m.progress = 0;
    }
    world.deposit_mut(deposit).unwrap().amount = 1;
    assert_eq!(
        state_of(&world, id),
        MachineState::Working {
            deposit,
            species: ROCK,
            grade: world.deposit(deposit).unwrap().grade()
        },
        "the fixture must be able to mine exactly one more unit"
    );

    let events = run(&mut world, &[], 400);
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::DepositDepleted { .. })),
        "the fixture must empty the deposit, or the collision under test \
         never happens: {events:?}"
    );
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::MachineStalled { .. })),
        "the buffer filled on the same tick the deposit emptied, and the \
         stall must still be announced: {events:?}"
    );
    // Afterwards the standing answer is the deposit, which is the truth: the
    // buffer no longer matters because there is nothing left to mine.
    assert_eq!(
        state_of(&world, id),
        MachineState::Idle(MachineIdle::DepositMinedOut)
    );
}
