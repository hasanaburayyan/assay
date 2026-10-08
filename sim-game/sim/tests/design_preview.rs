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
    // The have/need column is the plan's tally, so an empty pack reads 0 on
    // both rows rather than omitting them.
    assert!(
        line.contains("0/1") && !line.contains("1/1"),
        "and the have/need column must read off the same empty pack: {line}"
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
        before.contains("1/1") && !before.contains("not enough"),
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
