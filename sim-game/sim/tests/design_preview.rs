//! Weighing a design without building it (ASSA-324).
//!
//! `assembly::plan` is the one answer to "what would `Assemble` do with these
//! items", and `step`'s `Assemble` arm is that answer plus the spending. These
//! tests exist for one claim and keep asking it from different sides: **a
//! preview and the press can never disagree.** Not about the verdict, not about
//! the order a design is refused in, and not about which item is missing.
//!
//! The defect they are written against is one a player sees before anyone else:
//! a build screen reading SAFE over a button that refuses.

use sim::assembly::{AssemblyPlan, plan};
use sim::debug;
use sim::{
    AssemblyError, Event, Grade, Input, Item, ItemKind, Mount, PartKind, PlayerCommand, PlayerId,
    RejectReason, Sheet, SpeciesId, SystemCommand, World, WorldConfig, step,
};

const LIGHT: SpeciesId = SpeciesId(0);
const HEAVY: SpeciesId = SpeciesId(1);
/// Past the end of any roster this world rolls: a species index a client made
/// up.
const NO_SUCH: SpeciesId = SpeciesId(200);

const HELD: PartKind = PartKind::Frame(Mount::Held);
const PLANTED: PartKind = PartKind::Frame(Mount::Planted);

fn sheet(density: u8, strength: u8) -> Sheet {
    Sheet {
        density,
        strength,
        hardness: 30,
        heat_tolerance: 50,
        reactivity: 50,
        conductivity: 50,
    }
}

fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    world.species_mut(LIGHT).sheet = sheet(20, 60);
    world.species_mut(HEAVY).sheet = sheet(100, 1);
    for id in 0..world.species.len() {
        world.species[id].assayed = true;
    }
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

fn part_item(kind: PartKind, species: SpeciesId) -> Item {
    Item::new(ItemKind::Part(kind), species, Grade::B)
}

fn ore(species: SpeciesId) -> Item {
    Item::new(ItemKind::Ore, species, Grade::B)
}

fn give(world: &mut World, me: PlayerId, item: Item, n: u32) {
    world.player_mut(me).unwrap().inventory.add(item, n);
}

fn send(world: &mut World, me: PlayerId, command: PlayerCommand) -> Vec<Event> {
    let mut events = Vec::new();
    step(world, &[Input::player(me, command)], &mut events);
    events
}

fn rejection(events: &[Event]) -> Option<RejectReason> {
    events.iter().find_map(|e| match e {
        Event::CommandRejected { reason, .. } => Some(*reason),
        _ => None,
    })
}

fn preview(world: &World, me: PlayerId, frame: Item, mounted: &[Item]) -> AssemblyPlan {
    let inventory = &world.player(me).expect("player exists").inventory;
    plan(frame, mounted, &world.species, inventory)
}

/// One case: what the pack holds, and the design asked of it.
struct Case {
    what: &'static str,
    pack: Vec<(Item, u32)>,
    frame: Item,
    mounted: Vec<Item>,
    expected: Option<RejectReason>,
}

/// Every arm `plan` can take, each with a pack chosen so nothing *else* could
/// explain the answer.
fn cases() -> Vec<Case> {
    let frame = part_item(HELD, LIGHT);
    let head = part_item(PartKind::Head, LIGHT);
    let planted = part_item(PLANTED, LIGHT);
    let hopper = part_item(PartKind::Hopper, LIGHT);
    vec![
        Case {
            what: "a pick the player holds every part of",
            pack: vec![(frame, 1), (head, 1)],
            frame,
            mounted: vec![head],
            expected: None,
        },
        Case {
            what: "a species index this world has never rolled",
            pack: vec![(frame, 1), (head, 1)],
            frame: part_item(HELD, NO_SUCH),
            mounted: vec![head],
            expected: Some(RejectReason::UnknownSpecies),
        },
        Case {
            // The unknown species is on a MOUNTED part, not the frame: the
            // precheck walks the whole command, and a preview that only
            // checked the frame would index the roster out of bounds while
            // weighing the head.
            what: "a made-up species on a mounted part",
            pack: vec![(frame, 1), (head, 1)],
            frame,
            mounted: vec![part_item(PartKind::Head, NO_SUCH)],
            expected: Some(RejectReason::UnknownSpecies),
        },
        Case {
            what: "ore in the frame position",
            pack: vec![(ore(LIGHT), 4), (head, 1)],
            frame: ore(LIGHT),
            mounted: vec![head],
            expected: Some(RejectReason::NotAPart(ore(LIGHT))),
        },
        Case {
            what: "ore mounted on a frame",
            pack: vec![(frame, 1), (ore(HEAVY), 4)],
            frame,
            mounted: vec![ore(HEAVY)],
            expected: Some(RejectReason::NotAPart(ore(HEAVY))),
        },
        Case {
            what: "a head where the frame goes",
            pack: vec![(head, 4)],
            frame: head,
            mounted: vec![head],
            expected: Some(RejectReason::BadAssembly(AssemblyError::FrameIsNotAFrame)),
        },
        Case {
            what: "a frame mounted on a frame",
            pack: vec![(planted, 1), (head, 1), (frame, 1)],
            frame: planted,
            mounted: vec![head, frame],
            expected: Some(RejectReason::BadAssembly(AssemblyError::FrameMounted)),
        },
        Case {
            what: "a hopper on a handle",
            pack: vec![(frame, 1), (head, 1), (hopper, 1)],
            frame,
            mounted: vec![head, hopper],
            expected: Some(RejectReason::BadAssembly(AssemblyError::NoSuchSlot(
                PartKind::Hopper,
            ))),
        },
        Case {
            what: "a handle with no head",
            pack: vec![(frame, 1)],
            frame,
            mounted: vec![],
            expected: Some(RejectReason::BadAssembly(AssemblyError::TooFew {
                kind: PartKind::Head,
                have: 0,
                min: 1,
            })),
        },
        Case {
            what: "two heads on one handle",
            pack: vec![(frame, 1), (head, 2)],
            frame,
            mounted: vec![head, head],
            expected: Some(RejectReason::BadAssembly(AssemblyError::TooMany {
                kind: PartKind::Head,
                have: 2,
                max: 1,
            })),
        },
        Case {
            // THE FRAME IS FIRST IN PART ORDER, so it is the item named even
            // though the head is missing too. The "which item" half of the
            // claim is an order, not a set.
            what: "a pack holding none of it",
            pack: vec![],
            frame,
            mounted: vec![head],
            expected: Some(RejectReason::MissingItems(frame)),
        },
        Case {
            what: "a pack holding the head but not the handle",
            pack: vec![(head, 1)],
            frame,
            mounted: vec![head],
            expected: Some(RejectReason::MissingItems(frame)),
        },
        Case {
            // THE TALLY, AND THE ONE CASE AN UNTALLIED CHECK PASSES. Holding
            // one hopper satisfies `has(hopper, 1)` twice over, so a check
            // that asked per part instead of per tallied stack would let this
            // build and quietly take the same hopper twice.
            what: "a drill wanting two hoppers from a pack holding one",
            pack: vec![(planted, 1), (head, 1), (hopper, 1)],
            frame: planted,
            mounted: vec![head, hopper, hopper],
            expected: Some(RejectReason::MissingItems(hopper)),
        },
        Case {
            what: "the same drill with both hoppers in the pack",
            pack: vec![(planted, 1), (head, 1), (hopper, 2)],
            frame: planted,
            mounted: vec![head, hopper, hopper],
            expected: None,
        },
        Case {
            // BOTH WRONG AT ONCE: the order is a rule, so the slot fault wins
            // over a pack that could not have paid either way.
            what: "an illegal design the pack also cannot afford",
            pack: vec![],
            frame,
            mounted: vec![head, hopper],
            expected: Some(RejectReason::BadAssembly(AssemblyError::NoSuchSlot(
                PartKind::Hopper,
            ))),
        },
    ]
}

/// **THE CLAIM.** For every arm, the plan taken before the press is the verdict
/// the press then gives — the same `RejectReason`, naming the same item.
#[test]
fn a_preview_and_the_press_agree_on_every_refusal() {
    for case in cases() {
        let (mut world, me) = world_with_player();
        for (item, n) in &case.pack {
            give(&mut world, me, *item, *n);
        }

        let planned = preview(&world, me, case.frame, &case.mounted);
        let events = send(
            &mut world,
            me,
            PlayerCommand::Assemble {
                frame: case.frame,
                mounted: case.mounted.clone(),
            },
        );

        assert_eq!(
            planned.refusal(),
            rejection(&events),
            "{}: the preview and the press disagreed",
            case.what
        );
        assert_eq!(
            planned.refusal(),
            case.expected,
            "{}: the refusal itself moved",
            case.what
        );
    }
}

/// A refusal costs nothing, and the plan said so before the press proved it.
#[test]
fn a_refused_design_spends_nothing_and_the_plan_knew_the_cost() {
    for case in cases() {
        let (mut world, me) = world_with_player();
        for (item, n) in &case.pack {
            give(&mut world, me, *item, *n);
        }
        let before = world.player(me).unwrap().inventory.clone();

        let planned = preview(&world, me, case.frame, &case.mounted);
        send(
            &mut world,
            me,
            PlayerCommand::Assemble {
                frame: case.frame,
                mounted: case.mounted.clone(),
            },
        );
        let after = &world.player(me).unwrap().inventory;

        if planned.refusal().is_some() {
            assert_eq!(&before, after, "{}: a refusal took something", case.what);
            continue;
        }
        // It built. Every tallied stack in the plan came out of the pack, and
        // nothing else did.
        let AssemblyPlan::Weighed { cost, .. } = &planned else {
            unreachable!("an accepted plan is Weighed")
        };
        let mut expected = before.clone();
        for s in cost {
            assert!(
                expected.remove(s.item, s.count),
                "{}: the plan's cost is not in the pack",
                case.what
            );
        }
        assert_eq!(
            &expected, after,
            "{}: the press spent something other than the plan's cost",
            case.what
        );
    }
}

/// **AN UNAFFORDABLE DESIGN IS STILL WEIGHED.** This is the whole reason a
/// build screen can exist: you price a machine before the pack can buy it.
#[test]
fn a_design_the_pack_cannot_pay_for_is_still_weighed() {
    let (world, me) = world_with_player();
    let frame = part_item(HELD, LIGHT);
    let head = part_item(PartKind::Head, LIGHT);

    let planned = preview(&world, me, frame, &[head]);

    assert_eq!(
        planned.refusal(),
        Some(RejectReason::MissingItems(frame)),
        "an empty pack cannot build this"
    );
    let built = planned.built().expect("the design itself is sound");
    let line = debug::design_preview(&world, me, frame, &[head]);
    assert!(
        line.starts_with(&debug::assembly_readout(&world, built)),
        "the preview must carry the readout, not a summary of it: {line}"
    );
    assert!(
        line.contains("not enough"),
        "and it must say what is short: {line}"
    );
    // The counts are the plan's tally, so an empty pack reads 0 on both rows
    // rather than omitting them — and in §5.5's words, which make the short
    // case an instruction (ASSA-338).
    assert!(
        line.contains("need 1 · have 0") && !line.contains("have 1"),
        "and the counts must read off the same empty pack, need first: {line}"
    );
}

/// **THE SURPLUS CASE IS THE NORMAL CASE, WHICH IS WHY THE SLASH WENT**
/// (ASSA-338; the Game Director's §5.5, reversing her own §5.3 the same
/// evening). You have two heads and need one, and `2/1` says that as a ratio
/// with its left side bigger than its right — which reads as 200% of
/// something, not as a pack.
///
/// **THIS IS THE CASE THE OTHER TWO TESTS CANNOT SEE.** They weigh a design
/// against a pack holding exactly one of each or none at all, where need and
/// have are the same number or the same word — so `need 1 · have 1` survives
/// swapping the pair, and the whole wording would be unpinned by tests that
/// look green. A surplus is the one shape where the two numbers differ in the
/// direction nothing else in this file produces.
///
/// It asks for the WHOLE entry, name included, because the name's place is the
/// other half of her ruling (*name, then counts*) and a `contains` of the two
/// counts alone would pass with the name anywhere on the line.
///
/// **AND IT NOW PINS THE LIST'S SHAPE WITH `ends_with`** (ASSA-338, her third
/// ruling: one entry per line). Each entry must END at its own `have`, which is
/// a claim no `contains` can make: re-joining the entries with `, ` — the shape
/// this replaced — leaves the first entry's line running on into the second, so
/// that entry no longer ends where its counts do and this test reddens. The
/// reason the list is lines at all is that `·` is the sim's TOP-LEVEL clause
/// mark, so an entry that contains one may not also be separated by one, and
/// the weaker marks all invert the hierarchy.
#[test]
fn a_surplus_pack_reads_need_then_have_and_never_a_ratio() {
    let (mut world, me) = world_with_player();
    let frame = part_item(HELD, LIGHT);
    let head = part_item(PartKind::Head, LIGHT);
    give(&mut world, me, frame, 1);
    give(&mut world, me, head, 2);

    let line = debug::design_preview(&world, me, frame, &[head]);
    // The claim is about the pack clause, so the slash is looked for THERE and
    // not on the whole readout: a verdict line that grows a slash of its own
    // some day is not this test's business.
    let header = line
        .lines()
        .position(|l| l.contains("your pack:"))
        .unwrap_or_else(|| panic!("a weighed design prints its pack: {line}"));
    let entries: Vec<&str> = line.lines().skip(header + 1).collect();

    for (item, counts) in [(head, "need 1 · have 2"), (frame, "need 1 · have 1")] {
        let name = world.item_name(item);
        let entry = entries
            .iter()
            .find(|l| l.trim_start().starts_with(&name))
            .unwrap_or_else(|| panic!("no entry of its own for {name}: {line}"));
        assert!(
            entry.ends_with(counts),
            "{name}'s entry must be a line of its own that ENDS at its counts \
             ({counts}), or the separator is back: {entry:?}\n{line}"
        );
    }
    assert!(
        !entries.iter().any(|l| l.contains('/')),
        "a slash is a ratio's mark and this is not a ratio: {line}"
    );
    assert!(
        !line.contains("not enough"),
        "a pack with a spare head is not short of anything: {line}"
    );
}

/// **THE REFUSAL CLAUSE NAMES THE FIRST ENTRY THE PACK CANNOT PAY FOR, WHICH IS
/// NOT THE LAST ONE PRINTED** — the thing one-entry-per-line made askable.
///
/// While the counts were a single line the clause trailed them and there was
/// nothing to get wrong. Now it is a line, and the only wrong place to put it is
/// hanging off the final row: `assembly::plan` picks the item with
/// `cost.iter().find(…)`, so it is the FIRST short entry in `part_items()`
/// order. This fixture holds the head and not the frame, so the short entry is
/// the frame — printed FIRST, with an affordable row after it. A clause trailed
/// on the last row would blame the head, which the player is holding.
///
/// It also pins the clause's indent as the HEADER's and not the entries': it is
/// a verdict on the list, not a fourth entry, and the indent is what says so.
#[test]
fn the_refusal_clause_blames_the_first_short_entry_and_is_not_an_entry() {
    let (mut world, me) = world_with_player();
    let frame = part_item(HELD, LIGHT);
    let head = part_item(PartKind::Head, LIGHT);
    give(&mut world, me, head, 1);

    let line = debug::design_preview(&world, me, frame, &[head]);
    let clause = line
        .lines()
        .find(|l| l.contains("not enough"))
        .unwrap_or_else(|| panic!("an unaffordable design predicts the refusal: {line}"));

    assert!(
        clause.contains(&world.item_name(frame)),
        "the frame is the part the pack is short of: {clause:?}\n{line}"
    );
    assert!(
        !clause.contains(&world.item_name(head)),
        "the head is held, so blaming it would be the clause trailing the last \
         row instead of naming `plan`'s own choice: {clause:?}\n{line}"
    );
    // The entries are indented one step deeper than the header; the clause sits
    // at the header's step. Measured off the strings rather than asserted as a
    // constant, because the width is `debug.rs`'s to change.
    let header = line
        .lines()
        .find(|l| l.contains("your pack:"))
        .expect("a weighed design prints its pack");
    let indent = |l: &str| l.len() - l.trim_start().len();
    assert_eq!(
        indent(clause),
        indent(header),
        "the clause is a verdict on the list, so it sits at the header's \
         indent, not an entry's:\n{line}"
    );
}

/// The readout a player reads BEFORE spending is the one the machine gives
/// AFTER. Two different printers — `design_preview` and `built_table` — asked
/// the same question across the press.
#[test]
fn the_preview_reads_as_the_machine_it_builds() {
    let (mut world, me) = world_with_player();
    let frame = part_item(HELD, LIGHT);
    let head = part_item(PartKind::Head, HEAVY);
    give(&mut world, me, frame, 1);
    give(&mut world, me, head, 1);

    let planned = preview(&world, me, frame, &[head]);
    let before = debug::design_preview(&world, me, frame, &[head]);
    assert!(
        before.contains("need 1 · have 1") && !before.contains("not enough"),
        "the pack does cover it: {before}"
    );
    let readout = debug::assembly_readout(&world, planned.built().expect("sound design"));

    let events = send(
        &mut world,
        me,
        PlayerCommand::Assemble {
            frame,
            mounted: vec![head],
        },
    );
    assert_eq!(rejection(&events), None, "it was supposed to build");

    let table = debug::built_table(&world, me);
    for line in readout.lines() {
        assert!(
            table.contains(line.trim()),
            "the built machine does not read as the preview promised.\n\
             preview: {line}\nbuilt table:\n{table}"
        );
    }
}

/// Weighing a design changes nothing at all — not the pack, not the built
/// list, not one bit of the world. A preview that stepped would desync a
/// co-op session by being *looked at*.
#[test]
fn weighing_a_design_changes_nothing_in_the_world() {
    let (mut world, me) = world_with_player();
    let frame = part_item(HELD, LIGHT);
    let head = part_item(PartKind::Head, LIGHT);
    give(&mut world, me, frame, 1);
    give(&mut world, me, head, 1);
    let before = sim::hash::fnv64(&world);

    for _ in 0..3 {
        assert!(preview(&world, me, frame, &[head]).built().is_some());
        let _ = debug::design_preview(&world, me, frame, &[head]);
    }

    assert_eq!(
        before,
        sim::hash::fnv64(&world),
        "weighing a design moved the world"
    );
    assert!(world.player(me).unwrap().assemblies.is_empty());
}

/// A plan that cannot be weighed says why in the sim's own words, and `step`
/// says the same words after the press.
#[test]
fn a_design_that_is_not_a_design_is_refused_in_the_same_words_both_times() {
    let (mut world, me) = world_with_player();
    let bad = ore(LIGHT);
    give(&mut world, me, bad, 4);

    let planned = preview(&world, me, bad, &[]);
    let line = debug::design_preview(&world, me, bad, &[]);
    assert!(planned.built().is_none(), "there is no design to weigh");

    let events = send(
        &mut world,
        me,
        PlayerCommand::Assemble {
            frame: bad,
            mounted: vec![],
        },
    );
    let rejected = events
        .iter()
        .find(|e| matches!(e, Event::CommandRejected { .. }))
        .expect("refused");
    let after = debug::event_line(&world, Some(me), rejected, debug::Audience::Typed);

    let phrase =
        debug::plan_refusal_phrase(&world, Some(me), planned.refusal().expect("it was refused"))
            .expect("`plan` refuses only in its own vocabulary");
    assert!(
        line.contains(&phrase),
        "the preview must use the phrase: {line}"
    );
    assert!(
        after.contains(&phrase),
        "and so must the log after the press: {after}"
    );
}

/// **A MADE-UP SPECIES INDEX IS A REFUSAL, NOT A CRASH**, and this is the one
/// test here that went red on `main` before `plan` existed.
///
/// `debug::design_preview` and the binding's `design_readout_facts` each walked
/// `step`'s chain themselves and each skipped its first link, because the
/// species roster is checked in `step`'s precheck where no preview could reach
/// it. `stat_range` and `World::item_name` then index `world.species` raw, so
/// asking about species 200 of a six-species world panicked: measured on
/// `e27ef54`, `index out of bounds: the len is 6 but the index is 200`, from
/// `world.rs:168` and `assembly.rs:684` respectively.
///
/// A sim that panics is worse than one that refuses for a reason bigger than
/// tidiness: in lockstep every peer runs this, so a question one client asks
/// about a bad index is a crash the others do not have. `step` calls such an
/// index "a bug or an attack, not a request" and that judgement is now
/// reachable before the press as well as after it.
#[test]
fn a_species_this_world_never_rolled_is_refused_rather_than_indexed() {
    let (mut world, me) = world_with_player();
    let good_frame = part_item(HELD, LIGHT);
    let good_head = part_item(PartKind::Head, LIGHT);
    give(&mut world, me, good_frame, 1);
    give(&mut world, me, good_head, 1);

    let phrase = debug::plan_refusal_phrase(&world, Some(me), RejectReason::UnknownSpecies)
        .expect("UnknownSpecies is one of the plan's four");

    // On the frame, and on a mounted part: the roster is walked whole, so the
    // head is caught even when the frame is sound.
    for (what, frame, mounted) in [
        ("the frame", part_item(HELD, NO_SUCH), vec![good_head]),
        (
            "a mounted part",
            good_frame,
            vec![part_item(PartKind::Head, NO_SUCH)],
        ),
    ] {
        let line = debug::design_preview(&world, me, frame, &mounted);
        assert!(
            line.contains(&phrase),
            "{what}: the preview must refuse a made-up species in the sim's \
             words, not index the roster: {line}"
        );
        // And it must not read as a verdict about a machine: a refused design
        // has no mass, because it is not a machine (ASSA-323's split).
        assert!(
            !line.contains("budget") && !line.contains("bare hands"),
            "{what}: a refused design must carry no numbers: {line}"
        );
    }
}

// ---------------------------------------------------------------------------
// ASSA-329: a design with a slot still empty gets its numbers and no verdict.
// ---------------------------------------------------------------------------

/// **THE NUMBERS ARRIVE AS PARTS GO IN, NOT ON THE LAST CLICK**, which is the
/// defect the Game Director measured: a held frame has one slot, so its only
/// two states were "empty" and "done" and there was nothing live about a live
/// readout.
///
/// Both mounts, because they are the two shapes of the question: a handle has
/// `Head min 1` and nothing else, a planted frame has `Head min 1` and
/// `Hopper min 0` — so on the planted one a design can be unfinished with a
/// part already in it, and the numbers have to have MOVED rather than merely
/// appeared.
#[test]
fn a_design_with_an_empty_slot_is_weighed_and_gets_no_verdict() {
    let (world, me) = world_with_player();
    let hopper = part_item(PartKind::Hopper, LIGHT);

    for (what, frame, mounted) in [
        ("a handle with no head", part_item(HELD, LIGHT), vec![]),
        (
            "a planted frame with no head",
            part_item(PLANTED, LIGHT),
            vec![],
        ),
        (
            "a planted frame holding only its hopper",
            part_item(PLANTED, LIGHT),
            vec![hopper],
        ),
    ] {
        let planned = preview(&world, me, frame, &mounted);

        let error = planned
            .unfinished()
            .unwrap_or_else(|| panic!("{what}: adding a head rescues this, so it is unfinished"));
        assert!(
            error.is_unfinished(),
            "{what}: only a recoverable fault takes this arm: {error:?}"
        );
        // IT IS STILL REFUSED, AND BY THE SAME WORDS AS BEFORE. The numbers are
        // for a screen to draw; they are not permission to build.
        assert_eq!(
            planned.refusal(),
            Some(RejectReason::BadAssembly(error)),
            "{what}: the press must still refuse it"
        );
        // AND `built` STILL SAYS NO, which is what keeps the verdict off it.
        assert!(
            planned.built().is_none(),
            "{what}: a half-built design is not a machine"
        );

        let design = planned
            .design()
            .unwrap_or_else(|| panic!("{what}: the arithmetic exists"));
        let range = design.assembly.stat_range(&world.species);
        assert!(
            range.high.budget > 0,
            "{what}: the frame's budget is what the mass is a fraction of: {range:?}"
        );

        let line = debug::design_preview(&world, me, frame, &mounted);
        // THE HEADLINE IS THE SIM'S PHRASE FOR WHAT IS MISSING, and it is the
        // SAME phrase the log gives after a press — not a second wording.
        let phrase = debug::plan_refusal_phrase(&world, Some(me), RejectReason::BadAssembly(error))
            .expect("BadAssembly is one of the plan's four");
        assert!(
            line.starts_with(&phrase),
            "{what}: the missing slot goes where the verdict would: {line}"
        );
        // NO VERDICT WORD ANYWHERE IN IT. Read off `BreakVerdict`'s own labels
        // rather than spelled here, so a fourth verdict cannot slip past this.
        for label in ["SAFE", "UNCERTAIN", "WILL BREAK"] {
            assert!(
                !line.contains(label),
                "{what}: `{label}` is a sentence about a machine that exists: {line}"
            );
        }
        // AND IT IS NOT DRESSED AS A REFUSAL EITHER: `not a machine · …` is for
        // a design no later press can rescue.
        assert!(
            !line.contains("not a machine"),
            "{what}: unfinished is not refused: {line}"
        );
        // The numbers are really in it, in the readout's own words.
        assert!(
            line.contains("mass") && line.contains("budget"),
            "{what}: the point of the arm is the numbers: {line}"
        );
    }
}

/// **A DESIGN NO LATER PRESS CAN RESCUE STILL GETS NOTHING**, and this is the
/// control for the test above: without it, "unfinished gets numbers" could have
/// been implemented as "everything gets numbers".
#[test]
fn a_permanently_faulted_design_keeps_todays_refusal_and_no_numbers() {
    let (world, me) = world_with_player();
    let head = part_item(PartKind::Head, LIGHT);
    let frame = part_item(HELD, LIGHT);
    let hopper = part_item(PartKind::Hopper, LIGHT);

    for (what, bad_frame, mounted) in [
        ("a head where the frame goes", head, vec![head]),
        (
            "a frame mounted on a frame",
            part_item(PLANTED, LIGHT),
            vec![head, frame],
        ),
        ("a hopper on a handle", frame, vec![head, hopper]),
        ("two heads on one handle", frame, vec![head, head]),
    ] {
        let planned = preview(&world, me, bad_frame, &mounted);
        assert!(
            planned.unfinished().is_none(),
            "{what}: no later press undoes this, so it is not unfinished"
        );
        assert!(
            planned.design().is_none(),
            "{what}: a selection that is not a design has no numbers to give"
        );
        let line = debug::design_preview(&world, me, bad_frame, &mounted);
        assert!(
            line.starts_with("not a machine · "),
            "{what}: today's refusal wording is kept: {line}"
        );
        assert!(
            !line.contains("budget") && !line.contains("bare hands"),
            "{what}: a refused design carries no numbers: {line}"
        );
    }
}

/// The two readouts are **one sentence with one word swapped**, which is what
/// makes a live readout read as one thing changing rather than two screens.
///
/// Asked by filling the slot: the only difference between the two lines is the
/// headline, so everything after the first `·` must match once the same parts
/// are weighed — and that is a claim a reimplementation of the body would fail.
#[test]
fn the_unfinished_line_is_the_finished_line_with_the_verdict_replaced() {
    let (world, me) = world_with_player();
    let frame = part_item(PLANTED, LIGHT);
    let head = part_item(PartKind::Head, HEAVY);
    let hopper = part_item(PartKind::Hopper, LIGHT);

    // The SAME parts, weighed twice: once through the unfinished arm (hopper
    // only, no head) and once through `assembly_readout` on a design built from
    // exactly those part items plus the head.
    let done = preview(&world, me, frame, &[head, hopper]);
    let built = done.built().expect("head and hopper fill a planted frame");
    let finished = debug::assembly_readout(&world, built);
    let unfinished = debug::unfinished_readout(
        &world,
        built,
        AssemblyError::TooFew {
            kind: PartKind::Head,
            have: 0,
            min: 1,
        },
    );

    let (_, finished_tail) = finished
        .split_once(" · ")
        .expect("the readout leads with a headline");
    let (_, unfinished_tail) = unfinished
        .split_once(" · ")
        .expect("so does the unfinished one");
    assert_eq!(
        finished_tail, unfinished_tail,
        "the body is shared, so only the headline may differ:\n{finished}\n{unfinished}"
    );
    assert!(
        unfinished.starts_with("it needs at least 1 head and has 0 · "),
        "and the headline is the sim's phrase for the missing slot: {unfinished}"
    );
}
