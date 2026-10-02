//! Mining with a tool and mining with a machine: decisions 6-9 and 12 of the
//! minimal-demo-loop note.
//!
//! `tests/assembly.rs` tests the model, `tests/assemble.rs` tests the commands
//! that build a machine, and this file tests what a built machine DOES. The
//! thing it is really guarding is that a pick and a drill are the same code:
//! every rate here comes from one catalogue row read through one curve.

use sim::assembly::Assembly;
use sim::tuning::{
    HAND_MINE_MAX_HARDNESS, HAND_MINE_TICKS, HAND_WORK_PER_TICK, HEAD_SPEED_PER_HARDNESS,
    HOPPER_CAPACITY, PICK_DURABILITY_PER_STRENGTH, PICK_WEAR_PER_SWING, PLANTED_FRAME_BUFFER,
    WORK_PER_UNIT, YIELD_BY_GRADE,
};
use sim::{
    BuildingId, DepositId, Event, Grade, Input, Item, ItemKind, Mount, Part, PartKind,
    PlayerCommand, PlayerId, Property, RejectReason, Sheet, SpeciesId, SystemCommand, TilePos,
    World, WorldConfig, step,
};

/// The species every test here digs and builds from, so a rate can be
/// reasoned about rather than discovered.
const ROCK: SpeciesId = SpeciesId(0);

const HELD: PartKind = PartKind::Frame(Mount::Held);
const PLANTED: PartKind = PartKind::Frame(Mount::Planted);

/// A world with one player, every species hand-mineable, and `ROCK`'s sheet
/// set on purpose. Strength 50 so the pool is the ADR's anchor; hardness 30 so
/// it is under the hand gate with room either side.
fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    for s in &mut world.species {
        s.sheet.hardness = s.sheet.hardness.min(HAND_MINE_MAX_HARDNESS as u8);
        s.assayed = true;
    }
    world.species_mut(ROCK).sheet = Sheet {
        density: 10,
        strength: 50,
        hardness: 30,
        heat_tolerance: 50,
        reactivity: 50,
        conductivity: 50,
    };
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

/// A deposit of `ROCK` at grade `grade`, with the player standing on it.
fn deposit_under_player(world: &mut World, me: PlayerId, grade: Grade) -> (DepositId, TilePos) {
    let id = DepositId(0);
    let center = world.deposit(id).unwrap().center;
    {
        let d = world.deposit_mut(id).unwrap();
        d.species = ROCK;
        d.purity = match grade {
            Grade::C => 20,
            Grade::B => 50,
            Grade::A => 80,
        };
        d.amount = 10_000;
    }
    world.player_mut(me).unwrap().pos = center;
    (id, center)
}

fn refined(species: SpeciesId, grade: Grade) -> Item {
    Item::new(ItemKind::Refined, species, grade)
}

fn pick(head_grade: Grade) -> Assembly {
    Assembly::new(
        Part::of(HELD, refined(ROCK, Grade::B)),
        vec![Part::of(PartKind::Head, refined(ROCK, head_grade))],
    )
}

fn drill(head_grade: Grade, hoppers: u32) -> Assembly {
    let mut mounted = vec![Part::of(PartKind::Head, refined(ROCK, head_grade))];
    for _ in 0..hoppers {
        mounted.push(Part::of(PartKind::Hopper, refined(ROCK, Grade::C)));
    }
    Assembly::new(Part::of(PLANTED, refined(ROCK, Grade::B)), mounted)
}

fn send(world: &mut World, me: PlayerId, command: PlayerCommand) -> Vec<Event> {
    let mut events = Vec::new();
    step(world, &[Input::player(me, command)], &mut events);
    events
}

fn run(world: &mut World, ticks: u32) -> Vec<Event> {
    let mut events = Vec::new();
    for _ in 0..ticks {
        step(world, &[], &mut events);
    }
    events
}

fn rejection(events: &[Event]) -> Option<RejectReason> {
    events.iter().find_map(|e| match e {
        Event::CommandRejected { reason, .. } => Some(*reason),
        _ => None,
    })
}

/// Build `assembly` through the real commands and return its index.
fn assemble(world: &mut World, me: PlayerId, assembly: &Assembly) -> u32 {
    for item in assembly.part_items() {
        world.player_mut(me).unwrap().inventory.add(item, 1);
    }
    let events = send(
        world,
        me,
        PlayerCommand::Assemble {
            frame: assembly.frame.as_item(),
            mounted: assembly.mounted.iter().map(Part::as_item).collect(),
        },
    );
    assert_eq!(rejection(&events), None, "assemble was rejected");
    events
        .iter()
        .find_map(|e| match e {
            Event::Assembled { assembly, .. } => Some(*assembly),
            _ => None,
        })
        .expect("Assemble emits Assembled")
}

/// Equip `assembly` and start mining. Returns the tool's starting pool.
fn equip_and_mine(world: &mut World, me: PlayerId, assembly: &Assembly) -> u32 {
    let index = assemble(world, me, assembly);
    let events = send(world, me, PlayerCommand::Equip { assembly: index });
    assert_eq!(rejection(&events), None, "equip was rejected");
    let events = send(world, me, PlayerCommand::Mine);
    assert_eq!(rejection(&events), None, "mine was rejected");
    world.player(me).unwrap().tool.as_ref().unwrap().durability
}

/// Units of ore the player holds of `ROCK` at `grade`.
fn ore_held(world: &World, me: PlayerId, grade: Grade) -> u32 {
    world
        .player(me)
        .unwrap()
        .inventory
        .count(Item::new(ItemKind::Ore, ROCK, grade))
}

// ---------------------------------------------------------------------------
// The curve (ADR 0003 amendment A3)
// ---------------------------------------------------------------------------

/// Hand mining is EXACTLY what it was before the curve existed. The whole
/// reason `HAND_WORK_PER_TICK` is 25 against a `WORK_PER_UNIT` of 100 is that
/// four ticks still make one unit, so every rule, test and save that assumed
/// `HAND_MINE_TICKS` still holds.
#[test]
fn the_hand_rate_is_unchanged_by_the_curve() {
    assert_eq!(
        HAND_WORK_PER_TICK * HAND_MINE_TICKS,
        WORK_PER_UNIT,
        "hands must still take exactly HAND_MINE_TICKS per unit"
    );

    let (mut world, me) = world_with_player();
    deposit_under_player(&mut world, me, Grade::B);
    // `send` is itself a tick, and the mining system runs on the tick the
    // command lands, so this leaves the player one tick short of a unit.
    send(&mut world, me, PlayerCommand::Mine);
    run(&mut world, HAND_MINE_TICKS - 2);
    assert_eq!(ore_held(&world, me, Grade::B), 0, "not yet");
    run(&mut world, 1);
    assert_eq!(
        ore_held(&world, me, Grade::B),
        YIELD_BY_GRADE[Grade::B as usize],
        "the HAND_MINE_TICKS-th tick yields"
    );
}

/// THE REMAINDER CARRIES, which is the whole point of accumulating work
/// instead of counting ticks: the long-run rate is exactly
/// `WORK_PER_UNIT / speed`, not its ceiling.
///
/// A grade-A head of hardness 30 gives speed 30, so a unit costs 100/30 =
/// 3.33 ticks. Over 30 ticks that is exactly 9 units — a ceiling rule would
/// give 7 (one unit per 4 ticks), and resetting progress to zero would give 7
/// too. The exact count is what tells those three apart.
#[test]
fn the_remainder_carries_so_the_rate_is_not_a_ceiling() {
    let (mut world, me) = world_with_player();
    deposit_under_player(&mut world, me, Grade::C);
    let design = pick(Grade::A);
    assert_eq!(
        design.stats(&world.species).speed,
        30 * HEAD_SPEED_PER_HARDNESS,
        "the anchor this test reasons about: effective hardness 30 at grade A, \
         times the factor"
    );
    equip_and_mine(&mut world, me, &design);

    run(&mut world, 30);
    assert_eq!(
        ore_held(&world, me, Grade::C),
        18 * YIELD_BY_GRADE[Grade::C as usize],
        "30 ticks at 60 work/tick is 1800 work = 18 units; a ceiling (2 ticks \
         a unit) or a reset would both give 15. These numbers are the factor's \
         to move: at `HEAD_SPEED_PER_HARDNESS` 1 it was 9 against a ceiling's 7"
    );
}

// ---------------------------------------------------------------------------
// Decision 6: a pick and a drill are the same code
// ---------------------------------------------------------------------------

/// The claim this whole item rests on. A pick and a drill with the SAME head
/// mine at the same rate, because the rate is one catalogue row read through
/// one curve — not two features that happen to agree.
///
/// Names no stat and no kind: it compares the two designs' `Speed` and then
/// compares what they actually produce over the same ticks.
#[test]
fn a_pick_and_a_drill_with_the_same_head_mine_at_the_same_rate() {
    let (mut world, me) = world_with_player();
    let (_, center) = deposit_under_player(&mut world, me, Grade::C);

    let by_hand = pick(Grade::B);
    let planted = drill(Grade::B, 1);
    assert_eq!(
        by_hand.stats(&world.species).speed,
        planted.stats(&world.species).speed,
        "the head is the only source of Speed, so the frame cannot change it"
    );

    equip_and_mine(&mut world, me, &by_hand);
    run(&mut world, 20);
    let with_pick = ore_held(&world, me, Grade::C);
    assert!(with_pick > 0, "the pick must have produced something");

    // Same world, same deposit, same head: now plant one instead.
    let (mut world, me) = world_with_player();
    let (_, center2) = deposit_under_player(&mut world, me, Grade::C);
    assert_eq!(center, center2, "same fixture, same tile");
    let index = assemble(&mut world, me, &planted);
    let events = send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos: center,
        },
    );
    assert_eq!(rejection(&events), None, "the drill must plant");
    run(&mut world, 20);
    let machine_held = match &world.buildings[0].kind {
        sim::BuildingKind::Machine(m) => m.held.map_or(0, |s| s.count),
        other => panic!("expected a machine, got {other:?}"),
    };
    assert_eq!(
        machine_held, with_pick,
        "20 ticks of the same head produces the same ore whether it is held \
         or planted"
    );
}

// ---------------------------------------------------------------------------
// Decision 7: throughput, not a hardness unlock
// ---------------------------------------------------------------------------

/// A drill on ore too hard for hands does NOTHING. The hardness ladder above
/// rung zero stays parked, so a machine is a throughput upgrade and never a
/// key to a new tier.
///
/// Asserts the drill is otherwise working first, so a silent failure to place
/// or a zero-speed design cannot pass this test by accident.
#[test]
fn a_drill_on_ore_too_hard_for_hands_does_nothing() {
    let (mut world, me) = world_with_player();
    let (_, center) = deposit_under_player(&mut world, me, Grade::C);
    let design = drill(Grade::B, 1);
    let index = assemble(&mut world, me, &design);
    send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos: center,
        },
    );

    run(&mut world, 20);
    let working = match &world.buildings[0].kind {
        sim::BuildingKind::Machine(m) => m.held.map_or(0, |s| s.count),
        other => panic!("expected a machine, got {other:?}"),
    };
    assert!(
        working > 0,
        "the fixture must be a drill that mines, or the next assertion is vacuous"
    );

    // Now harden the species past the hand gate and run again.
    world.species_mut(ROCK).sheet.hardness = HAND_MINE_MAX_HARDNESS as u8 + 1;
    let events = run(&mut world, 100);
    let after = match &world.buildings[0].kind {
        sim::BuildingKind::Machine(m) => m.held.map_or(0, |s| s.count),
        other => panic!("expected a machine, got {other:?}"),
    };
    assert_eq!(
        after, working,
        "100 ticks on ore too hard must produce nothing"
    );
    assert!(
        !events
            .iter()
            .any(|e| matches!(e, Event::MachineMined { .. })),
        "and must not even claim to have mined"
    );
}

/// The same gate, from the other side: a pick does not let a player mine
/// what their hands cannot. The gate lives on the `Mine` command and the
/// tool never revisits it.
#[test]
fn a_pick_does_not_unlock_ore_too_hard_for_hands() {
    let (mut world, me) = world_with_player();
    deposit_under_player(&mut world, me, Grade::C);
    let index = assemble(&mut world, me, &pick(Grade::A));
    send(&mut world, me, PlayerCommand::Equip { assembly: index });

    world.species_mut(ROCK).sheet.hardness = HAND_MINE_MAX_HARDNESS as u8 + 1;
    let events = send(&mut world, me, PlayerCommand::Mine);
    assert_eq!(
        rejection(&events),
        Some(RejectReason::TooHardForHands),
        "a pick buys throughput, never a tier"
    );
}

// ---------------------------------------------------------------------------
// Decision 8: head hardness, grade-scaled, sets the rate
// ---------------------------------------------------------------------------

/// Same species, better grade head, more ore in the same ticks — for a pick
/// and for a drill, because decision 8 says "picks and drills alike".
///
/// This is the test the continuous curve exists for: at hardness 30 the three
/// grades give effective hardness 18, 24 and 30 — so 36, 48 and 60 work per
/// tick at `HEAD_SPEED_PER_HARDNESS` 2 — which under a tick-counting rule
/// would all have landed on the same integer tick count.
#[test]
fn a_better_grade_head_mines_more_of_the_same_species() {
    let mut ore_by_grade = Vec::new();
    for head in [Grade::C, Grade::B, Grade::A] {
        let (mut world, me) = world_with_player();
        deposit_under_player(&mut world, me, Grade::C);
        equip_and_mine(&mut world, me, &pick(head));
        run(&mut world, 60);
        ore_by_grade.push(ore_held(&world, me, Grade::C));
    }
    assert!(
        ore_by_grade[0] < ore_by_grade[1] && ore_by_grade[1] < ore_by_grade[2],
        "a pick's rate must be strictly monotone in head grade, got {ore_by_grade:?}"
    );

    let mut machine_by_grade = Vec::new();
    for head in [Grade::C, Grade::B, Grade::A] {
        let (mut world, me) = world_with_player();
        let (_, center) = deposit_under_player(&mut world, me, Grade::C);
        let index = assemble(&mut world, me, &drill(head, 4));
        send(
            &mut world,
            me,
            PlayerCommand::PlaceAssembly {
                assembly: index,
                pos: center,
            },
        );
        run(&mut world, 60);
        machine_by_grade.push(match &world.buildings[0].kind {
            sim::BuildingKind::Machine(m) => m.held.map_or(0, |s| s.count),
            other => panic!("expected a machine, got {other:?}"),
        });
    }
    assert!(
        machine_by_grade[0] < machine_by_grade[1] && machine_by_grade[1] < machine_by_grade[2],
        "and so must a drill's, from the same row: {machine_by_grade:?}"
    );
}

// ---------------------------------------------------------------------------
// The guard the Game Director asked for, and what it is guarding
// ---------------------------------------------------------------------------

/// **IF MINING'S REACH EVER RISES, THIS FAILS INSTEAD OF THE RATE CURVE GOING
/// QUIETLY FLAT.** `mine_by_hand` takes at most one unit per tick, so work
/// above `WORK_PER_UNIT` is thrown away and the rate stops being monotone in
/// hardness — which is the entire reason A3 carries the remainder. Nothing
/// detects that; the game simply stops rewarding a better head.
///
/// At `HEAD_SPEED_PER_HARDNESS` 2 the best head anybody can reach makes 80 of
/// 100, so there is headroom. At 3 it would be 120 and the top of the ladder
/// would flatten; the day somebody lifts the hardness gate, the same thing
/// happens at 2.
///
/// **THE REACHABLE MAXIMUM IS MINED FOR, NOT TYPED.** A guard whose bound came
/// from me reading `HAND_MINE_MAX_HARDNESS` would guard my reading. So this
/// tries every base hardness through the real mining rule and asks what came
/// out, which also keeps it honest if hand mining and machine mining ever stop
/// sharing a gate.
#[test]
fn the_rate_curve_cannot_flatten_without_ci_saying_so() {
    let mut hardest_minable = 0u32;
    let mut refused_something = false;
    for base in 1..=100u8 {
        let (mut world, me) = world_with_player();
        world.species_mut(ROCK).sheet.hardness = base;
        deposit_under_player(&mut world, me, Grade::A);
        send(&mut world, me, PlayerCommand::Mine);
        run(&mut world, HAND_MINE_TICKS * 2);
        if ore_held(&world, me, Grade::A) > 0 {
            // Grade A scales hardness by 100%, so A is this species' best head
            // and `effective` is the number a head would actually contribute.
            hardest_minable =
                hardest_minable.max(world.species(ROCK).effective(Property::Hardness, Grade::A));
        } else {
            refused_something = true;
        }
    }
    // The loop must have found the boundary, not just run. A world where
    // nothing was minable would pass the real assertion below vacuously.
    assert!(
        hardest_minable > 0 && refused_something,
        "this must span the gate: hardest minable {hardest_minable}, and \
         something must have been refused"
    );
    assert_eq!(
        hardest_minable, HAND_MINE_MAX_HARDNESS,
        "the gate the sim applies is no longer the constant this test's \
         message talks about; read `mine_by_hand` and `mine_by_machine` again"
    );
    assert!(
        hardest_minable * HEAD_SPEED_PER_HARDNESS <= WORK_PER_UNIT,
        "THE RATE CURVE HAS FLATTENED AT THE TOP. The best reachable head now \
         contributes {} work per tick against a {WORK_PER_UNIT} unit, so work \
         is discarded and a harder head stops mining faster. Two ways out: put \
         `HEAD_SPEED_PER_HARDNESS` back to 1, or raise `WORK_PER_UNIT` to 200 \
         with `HAND_WORK_PER_TICK` 50 — that identity keeps hand mining at \
         exactly {HAND_MINE_TICKS} ticks per unit.",
        hardest_minable * HEAD_SPEED_PER_HARDNESS
    );
}

/// **THE FACTOR CANNOT CHANGE HOW GRADE FEELS**, and that is worth a test
/// because it is the thing people will expect it to do. A head's `Speed` is
/// `effective hardness x HEAD_SPEED_PER_HARDNESS`, so the within-species C:A
/// ratio is `floor(0.6 x base) / base` and the factor cancels out of it. All 2
/// moved was the whole ladder, relative to bare hands.
///
/// Cross-multiplied rather than divided, so it is exact, and read off the real
/// `PART_SPECS` row rather than recomputed here: a flat bonus on the speed row,
/// or a row that started reading strength, breaks this even though both would
/// leave `a_better_grade_head_mines_more_of_the_same_species` green.
#[test]
fn grade_scales_the_rate_by_a_ratio_the_factor_cannot_move() {
    for base in [7u8, 20, 30, HAND_MINE_MAX_HARDNESS as u8] {
        let (mut world, me) = world_with_player();
        world.species_mut(ROCK).sheet.hardness = base;
        let _ = me;
        let speed = |grade| pick(grade).stats(&world.species).speed;
        let eff = |grade| world.species(ROCK).effective(Property::Hardness, grade);
        assert_eq!(
            speed(Grade::A) * eff(Grade::C),
            speed(Grade::C) * eff(Grade::A),
            "at base hardness {base} the C:A rate ratio must be the C:A \
             effective-hardness ratio, with no factor left in it: speeds {}/{} \
             against effective {}/{}",
            speed(Grade::C),
            speed(Grade::A),
            eff(Grade::C),
            eff(Grade::A)
        );
    }
}

// ---------------------------------------------------------------------------
// Decision 9: the buffer, the stall, and what a hopper buys
// ---------------------------------------------------------------------------

/// A drill with no hopper fills its frame's buffer, says so once, and stops.
/// A hopper raises the cap with no new code — the capacity is a sum over
/// parts, which is the model doing the work.
#[test]
fn a_drill_stalls_at_its_buffer_and_a_hopper_raises_the_cap() {
    let (mut world, me) = world_with_player();
    let (_, center) = deposit_under_player(&mut world, me, Grade::C);
    let bare = drill(Grade::A, 0);
    assert_eq!(
        bare.stats(&world.species).capacity,
        PLANTED_FRAME_BUFFER,
        "a bare planted frame holds only its own buffer"
    );
    let index = assemble(&mut world, me, &bare);
    send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos: center,
        },
    );

    let events = run(&mut world, 500);
    let stalls: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, Event::MachineStalled { .. }))
        .collect();
    assert_eq!(
        stalls.len(),
        1,
        "a stall is announced once, on the tick it fills, not every tick it \
         sits full: {stalls:?}"
    );
    assert_eq!(
        stalls[0],
        &Event::MachineStalled {
            building: BuildingId(0),
            held: PLANTED_FRAME_BUFFER,
            capacity: PLANTED_FRAME_BUFFER,
        },
        "it stops AT the cap, never over it"
    );

    // One hopper, same everything else.
    let (mut world, me) = world_with_player();
    let (_, center) = deposit_under_player(&mut world, me, Grade::C);
    let with_hopper = drill(Grade::A, 1);
    assert_eq!(
        with_hopper.stats(&world.species).capacity,
        PLANTED_FRAME_BUFFER + HOPPER_CAPACITY,
        "capacity is a sum over parts"
    );
    let index = assemble(&mut world, me, &with_hopper);
    send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos: center,
        },
    );
    run(&mut world, 500);
    let held = match &world.buildings[0].kind {
        sim::BuildingKind::Machine(m) => m.held.map_or(0, |s| s.count),
        other => panic!("expected a machine, got {other:?}"),
    };
    assert!(
        held > PLANTED_FRAME_BUFFER,
        "one hopper must let it past the bare frame's cap, got {held}"
    );
}

/// Emptying a stalled drill starts it again, and the work it had in progress
/// when it stalled is still there. Never lose work in progress.
#[test]
fn taking_the_ore_out_restarts_a_stalled_drill() {
    let (mut world, me) = world_with_player();
    let (_, center) = deposit_under_player(&mut world, me, Grade::C);
    let index = assemble(&mut world, me, &drill(Grade::A, 0));
    send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos: center,
        },
    );
    run(&mut world, 500);

    let events = send(
        &mut world,
        me,
        PlayerCommand::Take {
            building: BuildingId(0),
        },
    );
    assert_eq!(rejection(&events), None, "the ore must come out");
    assert_eq!(
        ore_held(&world, me, Grade::C),
        PLANTED_FRAME_BUFFER,
        "a full buffer's worth lands in the inventory"
    );

    let events = run(&mut world, 20);
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::MachineMined { .. })),
        "and it goes back to work"
    );
}

// ---------------------------------------------------------------------------
// Decision 12: hand tools wear out, placed machines do not
// ---------------------------------------------------------------------------

/// A pick's pool drops by exactly one swing's wear per unit mined, and the
/// pool it starts with is the ADR's anchor.
#[test]
fn a_picks_pool_drops_one_swing_per_unit_mined() {
    let (mut world, me) = world_with_player();
    deposit_under_player(&mut world, me, Grade::C);
    let full = equip_and_mine(&mut world, me, &pick(Grade::B));
    // Head strength 50 at grade B is effective 40; size 1.
    assert_eq!(
        full,
        40 * PICK_DURABILITY_PER_STRENGTH,
        "the pool anchor: head size x effective strength x per-strength"
    );

    // Speed 48 at grade B (effective hardness 24 x the factor), so 100 work
    // lands on the third tick: 48, 96, 144. The window is one unit wide on
    // purpose — run it longer and a second unit hides what this is about.
    run(&mut world, 3);
    assert_eq!(ore_held(&world, me, Grade::C), 1, "exactly one unit so far");
    assert_eq!(
        world.player(me).unwrap().tool.as_ref().unwrap().durability,
        full - PICK_WEAR_PER_SWING,
        "one unit mined is one swing's wear, not one tick's"
    );
}

/// The ruling on this item: at zero the HEAD is consumed and the HANDLE comes
/// back as a part. Not the whole pick, and not refined material.
///
/// Asserts the run actually reached the wear-out (the event fired) rather than
/// passing because nothing happened.
#[test]
fn a_worn_out_pick_consumes_its_head_and_returns_its_handle() {
    let (mut world, me) = world_with_player();
    deposit_under_player(&mut world, me, Grade::C);
    let design = pick(Grade::B);
    let full = equip_and_mine(&mut world, me, &design);
    let swings = full / PICK_WEAR_PER_SWING;
    let head = design.mounted[0].as_item();
    let handle = design.frame.as_item();

    // Enough ticks for every swing the pool can pay for, at speed 24.
    let events = run(&mut world, swings * WORK_PER_UNIT / 24 + 10);
    let worn: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, Event::ToolWornOut { .. }))
        .collect();
    assert_eq!(
        worn.len(),
        1,
        "the pool must have run out exactly once in {swings} swings: {worn:?}"
    );
    assert_eq!(
        worn[0],
        &Event::ToolWornOut {
            player: me,
            head,
            handle,
        },
        "the event names both halves so the player can see which they kept"
    );

    let p = world.player(me).unwrap();
    assert!(p.tool.is_none(), "back to bare hands");
    assert_eq!(
        p.inventory.count(handle),
        1,
        "the handle is in the inventory, intact and re-headable"
    );
    assert_eq!(p.inventory.count(head), 0, "the head is gone");
    assert_eq!(
        p.inventory.count(refined(ROCK, Grade::B)),
        0,
        "and nothing was refunded as material"
    );
}

/// The off-by-one, pinned: the swing that empties the pool still yields its
/// ore. Work in progress is never lost, and the tool goes afterwards.
#[test]
fn the_swing_that_empties_the_pool_still_yields_its_ore() {
    let (mut world, me) = world_with_player();
    deposit_under_player(&mut world, me, Grade::C);
    let design = pick(Grade::B);
    equip_and_mine(&mut world, me, &design);
    // One swing left, mid-unit on the next.
    world
        .player_mut(me)
        .unwrap()
        .tool
        .as_mut()
        .unwrap()
        .durability = PICK_WEAR_PER_SWING;
    let before = ore_held(&world, me, Grade::C);

    // Speed 48, so 100 work lands on the third tick and not before. The
    // window is exactly one unit wide on purpose: run it longer and the
    // player's bare hands mine a second unit, which is correct behaviour but
    // would hide the thing this test is about.
    let events = run(&mut world, 3);
    assert!(
        events.iter().any(|e| matches!(e, Event::OreMined { .. })),
        "the last swing yields"
    );
    assert_eq!(
        ore_held(&world, me, Grade::C),
        before + YIELD_BY_GRADE[Grade::C as usize],
        "exactly one more unit: the pool paid for one swing and no more"
    );
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::ToolWornOut { .. })),
        "and then the pick goes"
    );
}

/// A pick breaking does not cancel the mining session: the player keeps
/// digging with their hands, at the hand rate, and the work in progress is
/// still there.
///
/// Found by one of this file's own tests failing for the right reason — I had
/// written a ten-tick window expecting one unit and got two. Calm, never
/// punishing: nothing is lost and nothing has to be restarted.
#[test]
fn a_pick_breaking_does_not_stop_the_player_mining() {
    let (mut world, me) = world_with_player();
    deposit_under_player(&mut world, me, Grade::C);
    equip_and_mine(&mut world, me, &pick(Grade::B));
    world
        .player_mut(me)
        .unwrap()
        .tool
        .as_mut()
        .unwrap()
        .durability = PICK_WEAR_PER_SWING;

    let events = run(&mut world, 5);
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::ToolWornOut { .. })),
        "the pick must actually have broken, or the rest is vacuous"
    );
    let after_break = ore_held(&world, me, Grade::C);
    assert!(
        world.player(me).unwrap().mining.is_some(),
        "the session survives the tool"
    );

    run(&mut world, 4);
    assert!(
        ore_held(&world, me, Grade::C) > after_break,
        "and bare hands keep producing at HAND_WORK_PER_TICK"
    );
}

/// After a wear-out, `Assemble` with the returned handle and a new head IS
/// the repair. There is no repair command, and this test is what says so:
/// if one were added, it would be dead the day it landed.
#[test]
fn re_heading_the_returned_handle_is_an_ordinary_assemble() {
    let (mut world, me) = world_with_player();
    deposit_under_player(&mut world, me, Grade::C);
    let design = pick(Grade::B);
    equip_and_mine(&mut world, me, &design);
    world
        .player_mut(me)
        .unwrap()
        .tool
        .as_mut()
        .unwrap()
        .durability = PICK_WEAR_PER_SWING;
    run(&mut world, 10);
    assert!(world.player(me).unwrap().tool.is_none(), "worn out first");

    // The handle is already in hand from the wear-out; buy one new head.
    let head = design.mounted[0].as_item();
    world.player_mut(me).unwrap().inventory.add(head, 1);
    let events = send(
        &mut world,
        me,
        PlayerCommand::Assemble {
            frame: design.frame.as_item(),
            mounted: vec![head],
        },
    );
    assert_eq!(
        rejection(&events),
        None,
        "re-heading is the command that already exists"
    );
    let index = events
        .iter()
        .find_map(|e| match e {
            Event::Assembled { assembly, .. } => Some(*assembly),
            _ => None,
        })
        .expect("Assembled");
    // Read the pool at ASSEMBLE time, which is when it is established. By the
    // time `Equip` has run a tick the player — still mining — has already
    // spent a swing of it, which is correct and is what
    // `putting_a_tool_down_and_taking_it_up_again_keeps_its_wear` protects.
    assert_eq!(
        world.player(me).unwrap().assemblies[index as usize].durability,
        40 * PICK_DURABILITY_PER_STRENGTH,
        "a re-headed pick has a full pool: the pool is the head's, and the \
         handle brought none of its history with it"
    );
    let events = send(&mut world, me, PlayerCommand::Equip { assembly: index });
    assert_eq!(rejection(&events), None, "and it equips");
}

/// A placed machine never wears. Decision 12 parks drill wear, and this is
/// the assertion that keeps it parked — it runs long past any pool a head
/// could give it and the durability on its state does not move.
#[test]
fn a_placed_machine_never_wears() {
    let (mut world, me) = world_with_player();
    let (_, center) = deposit_under_player(&mut world, me, Grade::C);
    let design = drill(Grade::A, 4);
    let pool = design.stats(&world.species).durability;
    assert!(
        pool > 0,
        "the head contributes a pool whatever frame it sits on: that is the \
         model, and the parking is a rule on top of it"
    );
    let index = assemble(&mut world, me, &design);
    send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos: center,
        },
    );

    // Long enough to have spent the pool many times over if anything drained.
    let events = run(&mut world, pool / PICK_WEAR_PER_SWING + 500);
    assert!(
        !events
            .iter()
            .any(|e| matches!(e, Event::ToolWornOut { .. })),
        "a planted machine cannot wear out"
    );
    assert!(
        world.buildings.iter().any(|b| b.id == BuildingId(0)),
        "and it is still standing"
    );
}

// ---------------------------------------------------------------------------
// What the inspector says about a planted machine
// ---------------------------------------------------------------------------

/// Every way a drill can be doing nothing has to SAY so. A player who paid
/// eight refined for a machine and sees it sit there needs the reason in the
/// one place they look, not a guess — decision 7's refusal especially, which
/// is invisible otherwise and reads as a bug.
#[test]
fn the_panel_names_every_reason_a_drill_is_not_mining() {
    let (mut world, me) = world_with_player();
    let (_, center) = deposit_under_player(&mut world, me, Grade::C);
    let index = assemble(&mut world, me, &drill(Grade::A, 0));
    send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos: center,
        },
    );
    let status = |w: &World| {
        let b = &w.buildings[0];
        match &b.kind {
            sim::BuildingKind::Machine(m) => sim::debug::machine_status(w, b, m),
            other => panic!("expected a machine, got {other:?}"),
        }
    };

    run(&mut world, 10);
    assert!(
        status(&world).contains("mining "),
        "working: {}",
        status(&world)
    );

    run(&mut world, 500);
    assert!(
        status(&world).contains("stalled: full"),
        "a full buffer must not still read as mining: {}",
        status(&world)
    );

    // Decision 7, made visible.
    world.species_mut(ROCK).sheet.hardness = HAND_MINE_MAX_HARDNESS as u8 + 1;
    assert!(
        status(&world).contains("too hard"),
        "a drill on ore it cannot touch must say why: {}",
        status(&world)
    );

    world.species_mut(ROCK).sheet.hardness = 30;
    world.deposit_mut(DepositId(0)).unwrap().amount = 0;
    assert!(
        status(&world).contains("mined out"),
        "a dead deposit is its own reason: {}",
        status(&world)
    );
}
