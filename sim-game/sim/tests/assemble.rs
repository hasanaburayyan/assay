//! The assembly commands: making parts, building a machine, taking it in hand
//! or planting it, and the break that decision 11 puts at placement.
//!
//! `tests/assembly.rs` tests the model in isolation. This file tests the
//! *wiring*: that the rules run inside `step`, that nothing validates mass
//! early, and that what the player gets back is what the ADR says.

use sim::assembly::{BreakVerdict, spec};
use sim::debug;
use sim::tuning::{
    BREAK_RETURN_PERCENT, HAND_WORK_PER_TICK, PICK_DURABILITY_PER_STRENGTH, PICK_WEAR_PER_SWING,
    PLANTED_FRAME_BUFFER, REACH,
};
use sim::{
    Assembly, AssemblyError, Event, Grade, Input, Item, ItemKind, MachineStats, Mount, Part,
    PartKind, PlayerCommand, PlayerId, RejectReason, Rng, Sheet, SpeciesId, SystemCommand, TilePos,
    World, WorldConfig, step,
};

/// Middling in everything: a design of this species fits its own budget.
const LIGHT: SpeciesId = SpeciesId(0);
/// Dense enough to overload a weak frame.
const HEAVY: SpeciesId = SpeciesId(1);
/// Light, but so weak that its frame carries almost nothing: the species the
/// overweight tests build their frames from.
const FRAIL: SpeciesId = SpeciesId(2);

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

/// A world with one player at spawn and sheets set on purpose. Every species
/// is assayed, so the sim's exact numbers are what the tests reason about.
fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    world.species_mut(LIGHT).sheet = sheet(20, 60);
    world.species_mut(HEAVY).sheet = sheet(100, 1);
    world.species_mut(FRAIL).sheet = sheet(20, 10);
    for id in 0..world.species.len() {
        world.species[id].assayed = true;
    }
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

fn refined(species: SpeciesId) -> Item {
    Item::new(ItemKind::Refined, species, Grade::B)
}

fn part_item(kind: PartKind, species: SpeciesId) -> Item {
    Item::new(ItemKind::Part(kind), species, Grade::B)
}

fn give(world: &mut World, me: PlayerId, item: Item, n: u32) {
    world.player_mut(me).unwrap().inventory.add(item, n);
}

fn send(world: &mut World, me: PlayerId, command: PlayerCommand) -> Vec<Event> {
    let mut events = Vec::new();
    step(world, &[Input::player(me, command)], &mut events);
    events
}

/// The reason a command was rejected, or `None` if it was accepted.
fn rejection(events: &[Event]) -> Option<RejectReason> {
    events.iter().find_map(|e| match e {
        Event::CommandRejected { reason, .. } => Some(*reason),
        _ => None,
    })
}

/// Hand the player every part of `assembly`, so `Assemble` can take them.
fn give_parts(world: &mut World, me: PlayerId, assembly: &Assembly) {
    for item in assembly.part_items() {
        give(world, me, item, 1);
    }
}

fn pick(species: SpeciesId, head: SpeciesId) -> Assembly {
    Assembly::new(
        Part::of(HELD, refined(species)),
        vec![Part::of(PartKind::Head, refined(head))],
    )
}

fn drill(species: SpeciesId, hoppers: u32) -> Assembly {
    let mut mounted = vec![Part::of(PartKind::Head, refined(species))];
    for _ in 0..hoppers {
        mounted.push(Part::of(PartKind::Hopper, refined(species)));
    }
    Assembly::new(Part::of(PLANTED, refined(species)), mounted)
}

/// Build `assembly` through the real command and return its index.
fn assemble(world: &mut World, me: PlayerId, assembly: &Assembly) -> u32 {
    give_parts(world, me, assembly);
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

// ---------------------------------------------------------------------------
// Making parts
// ---------------------------------------------------------------------------

/// A part costs its catalogue `size` in refined material and nothing else.
/// Looped over `PartKind::ALL` and naming no kind, so a row added later is
/// covered without editing this test.
#[test]
fn every_part_costs_its_catalogue_size_in_refined() {
    for kind in PartKind::ALL {
        let (mut world, me) = world_with_player();
        let size = spec(kind).size;
        give(&mut world, me, refined(LIGHT), size);

        let events = send(
            &mut world,
            me,
            PlayerCommand::MakePart {
                kind,
                material: refined(LIGHT),
                count: 1,
            },
        );

        assert_eq!(rejection(&events), None, "{} was refused", kind.name());
        let inv = &world.player(me).unwrap().inventory;
        assert_eq!(
            inv.count(refined(LIGHT)),
            0,
            "{} should have spent all {size} refined",
            kind.name()
        );
        assert_eq!(
            inv.count(part_item(kind, LIGHT)),
            1,
            "{} should be in the inventory",
            kind.name()
        );
    }
}

/// One refined short is no part at all, and nothing is taken.
#[test]
fn a_part_one_refined_short_takes_nothing() {
    for kind in PartKind::ALL {
        let size = spec(kind).size;
        if size < 2 {
            continue; // a size-1 part cannot be one short of itself
        }
        let (mut world, me) = world_with_player();
        give(&mut world, me, refined(LIGHT), size - 1);

        let events = send(
            &mut world,
            me,
            PlayerCommand::MakePart {
                kind,
                material: refined(LIGHT),
                count: 1,
            },
        );

        assert_eq!(
            rejection(&events),
            Some(RejectReason::MissingItems(refined(LIGHT))),
            "{}",
            kind.name()
        );
        assert_eq!(
            world.player(me).unwrap().inventory.count(refined(LIGHT)),
            size - 1,
            "{} must not spend anything when it fails",
            kind.name()
        );
    }
}

/// Parts are made of refined material. Ore is refused rather than coerced.
#[test]
fn a_part_cannot_be_made_from_ore() {
    let (mut world, me) = world_with_player();
    let ore = Item::new(ItemKind::Ore, LIGHT, Grade::B);
    give(&mut world, me, ore, 50);

    let events = send(
        &mut world,
        me,
        PlayerCommand::MakePart {
            kind: PartKind::Head,
            material: ore,
            count: 1,
        },
    );

    assert_eq!(rejection(&events), Some(RejectReason::WrongItem));
    assert_eq!(world.player(me).unwrap().inventory.count(ore), 50);
}

// ---------------------------------------------------------------------------
// Decision 11: nothing refuses a design for its mass
// ---------------------------------------------------------------------------

/// The acceptance check in its own test: there is no early mass validation on
/// the assemble path. The design here is far over budget and still builds.
#[test]
fn assemble_never_refuses_an_overweight_design() {
    let (mut world, me) = world_with_player();
    let design = pick(FRAIL, HEAVY);
    assert!(
        design.stats(&world.species).is_overweight(),
        "test needs an overweight design to be meaningful"
    );

    let index = assemble(&mut world, me, &design);

    let built = &world.player(me).unwrap().assemblies[index as usize];
    assert_eq!(built.assembly, design, "the overweight design was built");
}

/// Decision 11's test, first half: an overweight design planted gives no
/// building, a break event, and fewer parts back than went in.
#[test]
fn an_overweight_design_breaks_on_placement() {
    let (mut world, me) = world_with_player();
    let design = Assembly::new(
        Part::of(PLANTED, refined(FRAIL)),
        vec![
            Part::of(PartKind::Head, refined(HEAVY)),
            Part::of(PartKind::Hopper, refined(HEAVY)),
        ],
    );
    let stats = design.stats(&world.species);
    assert!(stats.is_overweight(), "test needs an overweight design");
    let went_in = design.part_count();

    let index = assemble(&mut world, me, &design);
    let pos = TilePos::new(
        world.player(me).unwrap().pos.x + 1,
        world.player(me).unwrap().pos.y,
    );
    let events = send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos,
        },
    );

    assert_eq!(rejection(&events), None, "a break is not a rejection");
    assert!(world.buildings.is_empty(), "no building may be placed");
    assert!(
        world.player(me).unwrap().assemblies.is_empty(),
        "the broken design is gone from the built list"
    );

    let Some(Event::MachineBroke {
        mass,
        budget,
        lost,
        returned,
        pos: broke_at,
        ..
    }) = events
        .iter()
        .find(|e| matches!(e, Event::MachineBroke { .. }))
    else {
        panic!("expected a MachineBroke event, got {events:?}")
    };
    assert_eq!((*mass, *budget), (stats.mass, stats.budget));
    assert_eq!(*broke_at, Some(pos));
    assert!(!lost.is_empty(), "a break must lose something");
    assert!(
        returned.len() < went_in,
        "fewer parts back ({}) than went in ({went_in})",
        returned.len()
    );
    assert_eq!(
        lost.len() + returned.len(),
        went_in,
        "every part is accounted for"
    );

    // What came back is in the inventory, and nothing else is.
    let inv = &world.player(me).unwrap().inventory;
    for item in returned {
        assert!(inv.count(*item) >= 1, "{} should be back", item.code());
    }
    assert_eq!(inv.total(), returned.len() as u32);
}

/// Decision 11's test, second half: a design within budget places and runs.
#[test]
fn a_design_within_budget_places_and_runs() {
    let (mut world, me) = world_with_player();
    let design = drill(LIGHT, 1);
    assert!(!design.stats(&world.species).is_overweight());

    let index = assemble(&mut world, me, &design);
    let pos = TilePos::new(
        world.player(me).unwrap().pos.x + 1,
        world.player(me).unwrap().pos.y,
    );
    let events = send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos,
        },
    );

    assert_eq!(rejection(&events), None);
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::MachinePlaced { .. })),
        "expected MachinePlaced, got {events:?}"
    );
    assert_eq!(world.buildings.len(), 1);
    let machine = world.buildings[0]
        .kind
        .machine()
        .expect("a planted assembly is a machine");
    assert_eq!(machine.assembly, design);
    assert!(machine.held.is_none(), "it starts empty");

    // It keeps running: nothing breaks it on a later tick.
    for _ in 0..20 {
        step(&mut world, &[], &mut Vec::new());
    }
    assert_eq!(world.buildings.len(), 1, "it is still there");
}

/// The break roll walks the rng at the same rate whatever the outcome, so two
/// peers cannot drift. Checked by advancing the same rng through designs whose
/// always-lost part differs and asserting the state is identical.
#[test]
fn the_break_roll_takes_one_rng_call_per_part_on_every_path() {
    let (world, _) = world_with_player();
    // Same part count, but the heaviest non-frame part is a different index.
    let head_heaviest = Assembly::new(
        Part::of(PLANTED, refined(LIGHT)),
        vec![
            Part::of(PartKind::Head, refined(HEAVY)),
            Part::of(PartKind::Hopper, refined(LIGHT)),
        ],
    );
    let hopper_heaviest = Assembly::new(
        Part::of(PLANTED, refined(LIGHT)),
        vec![
            Part::of(PartKind::Head, refined(LIGHT)),
            Part::of(PartKind::Hopper, refined(HEAVY)),
        ],
    );
    assert_ne!(
        head_heaviest.part_always_lost(&world.species),
        hopper_heaviest.part_always_lost(&world.species),
        "the two designs must lose different parts for this test to mean anything"
    );

    let mut a = Rng::new(1234);
    let mut b = Rng::new(1234);
    head_heaviest.break_apart(&world.species, &mut a);
    hopper_heaviest.break_apart(&world.species, &mut b);
    assert_eq!(a, b, "the rng advanced by a different number of draws");

    // And that number is exactly one per part, not zero and not two.
    let mut counting = Rng::new(1234);
    for _ in 0..head_heaviest.part_count() {
        counting.range(0, 100);
    }
    assert_eq!(counting, a, "expected exactly one draw per part");
}

/// A break loses the always-lost part no matter how the rolls fall, and never
/// returns it. Run over many seeds so one lucky roll cannot pass this.
#[test]
fn the_always_lost_part_never_comes_back() {
    let (world, _) = world_with_player();
    let design = drill(HEAVY, 2);
    let lost_index = design.part_always_lost(&world.species);
    let lost_kind = design.parts().nth(lost_index).unwrap().kind;
    let mut returned_any = false;

    for seed in 0..200 {
        let mut rng = Rng::new(seed);
        let outcome = design.break_apart(&world.species, &mut rng);
        assert_eq!(
            outcome.lost.len() + outcome.returned.len(),
            design.part_count()
        );
        // Resolve the index to the part and ask what KIND it is, rather than
        // trusting that a position in the list means a particular part.
        let lost_kinds: Vec<PartKind> = outcome.lost.iter().filter_map(|i| i.kind.part()).collect();
        assert!(
            lost_kinds.contains(&lost_kind),
            "seed {seed}: {} was not lost",
            lost_kind.name()
        );
        returned_any |= !outcome.returned.is_empty();
    }
    assert!(
        returned_any,
        "at {BREAK_RETURN_PERCENT}% some part should have come back"
    );
}

// ---------------------------------------------------------------------------
// Slots: the only thing Assemble refuses
// ---------------------------------------------------------------------------

#[test]
fn assemble_refuses_only_what_does_not_fit_the_frames_slots() {
    let cases: Vec<(&str, Item, Vec<Item>, AssemblyError)> = vec![
        (
            "a head in the frame position",
            part_item(PartKind::Head, LIGHT),
            vec![part_item(PartKind::Head, LIGHT)],
            AssemblyError::FrameIsNotAFrame,
        ),
        (
            "a frame mounted on a frame",
            part_item(PLANTED, LIGHT),
            vec![part_item(PartKind::Head, LIGHT), part_item(HELD, LIGHT)],
            AssemblyError::FrameMounted,
        ),
        (
            "a hopper on a handle",
            part_item(HELD, LIGHT),
            vec![
                part_item(PartKind::Head, LIGHT),
                part_item(PartKind::Hopper, LIGHT),
            ],
            AssemblyError::NoSuchSlot(PartKind::Hopper),
        ),
        (
            "no head at all",
            part_item(HELD, LIGHT),
            vec![],
            AssemblyError::TooFew {
                kind: PartKind::Head,
                have: 0,
                min: 1,
            },
        ),
        (
            "two heads",
            part_item(HELD, LIGHT),
            vec![
                part_item(PartKind::Head, LIGHT),
                part_item(PartKind::Head, LIGHT),
            ],
            AssemblyError::TooMany {
                kind: PartKind::Head,
                have: 2,
                max: 1,
            },
        ),
    ];

    for (what, frame, mounted, expected) in cases {
        let (mut world, me) = world_with_player();
        give(&mut world, me, frame, 4);
        for item in &mounted {
            give(&mut world, me, *item, 4);
        }
        let before = world.player(me).unwrap().inventory.total();

        let events = send(
            &mut world,
            me,
            PlayerCommand::Assemble {
                frame,
                mounted: mounted.clone(),
            },
        );

        assert_eq!(
            rejection(&events),
            Some(RejectReason::BadAssembly(expected)),
            "{what}"
        );
        assert_eq!(
            world.player(me).unwrap().inventory.total(),
            before,
            "{what}: a refused assembly must not consume parts"
        );
        assert!(world.player(me).unwrap().assemblies.is_empty(), "{what}");
    }
}

/// An item that is not a part is named as such, rather than being read as one.
#[test]
fn assemble_refuses_an_item_that_is_not_a_part() {
    let (mut world, me) = world_with_player();
    let ore = Item::new(ItemKind::Ore, LIGHT, Grade::B);
    give(&mut world, me, ore, 10);
    give(&mut world, me, part_item(PartKind::Head, LIGHT), 1);

    let frame_is_ore = send(
        &mut world,
        me,
        PlayerCommand::Assemble {
            frame: ore,
            mounted: vec![part_item(PartKind::Head, LIGHT)],
        },
    );
    assert_eq!(
        rejection(&frame_is_ore),
        Some(RejectReason::NotAPart(ore)),
        "a non-part frame"
    );

    give(&mut world, me, part_item(HELD, LIGHT), 1);
    let mount_is_ore = send(
        &mut world,
        me,
        PlayerCommand::Assemble {
            frame: part_item(HELD, LIGHT),
            mounted: vec![ore],
        },
    );
    assert_eq!(
        rejection(&mount_is_ore),
        Some(RejectReason::NotAPart(ore)),
        "a non-part mounted"
    );
}

/// Two hoppers of one material are two of one stack: the parts must be taken
/// all or nothing, not one at a time until the stack runs out.
#[test]
fn assemble_is_all_or_nothing_when_a_part_repeats() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, part_item(PLANTED, LIGHT), 1);
    give(&mut world, me, part_item(PartKind::Head, LIGHT), 1);
    give(&mut world, me, part_item(PartKind::Hopper, LIGHT), 1); // one short

    let events = send(
        &mut world,
        me,
        PlayerCommand::Assemble {
            frame: part_item(PLANTED, LIGHT),
            mounted: vec![
                part_item(PartKind::Head, LIGHT),
                part_item(PartKind::Hopper, LIGHT),
                part_item(PartKind::Hopper, LIGHT),
            ],
        },
    );

    assert_eq!(
        rejection(&events),
        Some(RejectReason::MissingItems(part_item(
            PartKind::Hopper,
            LIGHT
        )))
    );
    assert_eq!(
        world.player(me).unwrap().inventory.total(),
        3,
        "every part must still be in the inventory"
    );
}

// ---------------------------------------------------------------------------
// Decision 6: one command path, and the mount is the only difference
// ---------------------------------------------------------------------------

/// A pick and a drill are built by the same command, and differ only in which
/// of `Equip` and `PlaceAssembly` will take them.
#[test]
fn a_pick_and_a_drill_are_built_by_the_same_command() {
    let (mut world, me) = world_with_player();
    let pick = pick(LIGHT, LIGHT);
    let drill = drill(LIGHT, 1);

    let pick_index = assemble(&mut world, me, &pick);
    let drill_index = assemble(&mut world, me, &drill);

    assert_eq!(world.player(me).unwrap().assemblies.len(), 2);
    assert_eq!(pick.mount(), Some(Mount::Held));
    assert_eq!(drill.mount(), Some(Mount::Planted));

    // The held one cannot be planted...
    let here = world.player(me).unwrap().pos;
    let planted_a_pick = send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: pick_index,
            pos: here,
        },
    );
    assert_eq!(
        rejection(&planted_a_pick),
        Some(RejectReason::WrongMount),
        "a handle cannot be planted"
    );
    // ...and the planted one cannot be held.
    let equipped_a_drill = send(
        &mut world,
        me,
        PlayerCommand::Equip {
            assembly: drill_index,
        },
    );
    assert_eq!(
        rejection(&equipped_a_drill),
        Some(RejectReason::WrongMount),
        "a planted frame cannot be equipped"
    );
    assert_eq!(
        world.player(me).unwrap().assemblies.len(),
        2,
        "a refused mount leaves the built list alone"
    );
}

/// Equipping takes the tool out of the built list and puts its stats in the
/// event; the pool starts full.
#[test]
fn equipping_takes_the_tool_in_hand_with_a_full_pool() {
    let (mut world, me) = world_with_player();
    let design = pick(LIGHT, LIGHT);
    let expected = design.stats(&world.species);
    let index = assemble(&mut world, me, &design);

    let events = send(&mut world, me, PlayerCommand::Equip { assembly: index });

    assert_eq!(rejection(&events), None);
    let p = world.player(me).unwrap();
    assert!(p.assemblies.is_empty(), "it left the built list");
    let tool = p.tool.as_ref().expect("something is in hand");
    assert_eq!(tool.assembly, design);
    assert_eq!(tool.durability, expected.durability);
    assert!(tool.durability > 0, "a pick must have a pool");
    assert!(events.iter().any(|e| matches!(e, Event::Equipped { .. })));
    // The event deliberately carries no stats: an unassayed sheet must stay
    // banded, so a host reads the design out of the world instead.
    assert_eq!(
        world
            .player(me)
            .unwrap()
            .tool
            .as_ref()
            .unwrap()
            .assembly
            .stats(&world.species),
        expected
    );
}

/// The exploit this guards: putting a worn tool down and taking it up again
/// must not refill its durability. Wear is set here by hand because ASSA-6
/// owns the swing that causes it.
#[test]
fn putting_a_tool_down_and_taking_it_up_again_keeps_its_wear() {
    let (mut world, me) = world_with_player();
    let index = assemble(&mut world, me, &pick(LIGHT, LIGHT));
    send(&mut world, me, PlayerCommand::Equip { assembly: index });

    let worn = world.player(me).unwrap().tool.as_ref().unwrap().durability / 3;
    world
        .player_mut(me)
        .unwrap()
        .tool
        .as_mut()
        .unwrap()
        .durability = worn;

    let put_down = send(&mut world, me, PlayerCommand::Unequip);
    assert_eq!(rejection(&put_down), None);
    assert!(world.player(me).unwrap().tool.is_none());
    assert_eq!(
        world.player(me).unwrap().assemblies[0].durability,
        worn,
        "wear must survive going back on the built list"
    );

    let take_up = send(&mut world, me, PlayerCommand::Equip { assembly: 0 });
    assert_eq!(rejection(&take_up), None);
    assert_eq!(
        world.player(me).unwrap().tool.as_ref().unwrap().durability,
        worn,
        "re-equipping must not refill the pool"
    );
}

/// Equipping with a tool already in hand swaps them, and the old one keeps its
/// wear on the way back to the list.
#[test]
fn equipping_with_a_tool_in_hand_swaps_them() {
    let (mut world, me) = world_with_player();
    let first = pick(LIGHT, LIGHT);
    let second = pick(LIGHT, HEAVY);
    let a = assemble(&mut world, me, &first);
    send(&mut world, me, PlayerCommand::Equip { assembly: a });
    world
        .player_mut(me)
        .unwrap()
        .tool
        .as_mut()
        .unwrap()
        .durability = 7;
    let b = assemble(&mut world, me, &second);

    send(&mut world, me, PlayerCommand::Equip { assembly: b });

    let p = world.player(me).unwrap();
    assert_eq!(p.tool.as_ref().unwrap().assembly, second, "the new one");
    assert_eq!(p.assemblies.len(), 1);
    assert_eq!(p.assemblies[0].assembly, first, "the old one went back");
    assert_eq!(p.assemblies[0].durability, 7, "with its wear");
}

#[test]
fn unequipping_with_empty_hands_is_refused() {
    let (mut world, me) = world_with_player();
    let events = send(&mut world, me, PlayerCommand::Unequip);
    assert_eq!(rejection(&events), Some(RejectReason::NothingEquipped));
}

#[test]
fn equipping_or_planting_something_unbuilt_is_refused() {
    let (mut world, me) = world_with_player();
    let equip = send(&mut world, me, PlayerCommand::Equip { assembly: 3 });
    assert_eq!(rejection(&equip), Some(RejectReason::NoSuchAssembly));
    let here = world.player(me).unwrap().pos;
    let plant = send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: 3,
            pos: here,
        },
    );
    assert_eq!(rejection(&plant), Some(RejectReason::NoSuchAssembly));
}

// ---------------------------------------------------------------------------
// Decision 5 and 9: capacity is a sum, through the real commands
// ---------------------------------------------------------------------------

/// A planted drill's capacity is its frame's buffer plus its hoppers, and each
/// extra hopper raises it with no new code. Driven through the commands, so
/// this is the wiring and not the model.
#[test]
fn each_extra_hopper_raises_a_planted_machines_capacity() {
    let max = sim::tuning::MAX_HOPPER_SLOTS;
    let mut capacities = Vec::new();
    for hoppers in 0..=max {
        let (mut world, me) = world_with_player();
        let design = drill(LIGHT, hoppers);
        let index = assemble(&mut world, me, &design);
        let pos = TilePos::new(
            world.player(me).unwrap().pos.x + 1,
            world.player(me).unwrap().pos.y,
        );
        let events = send(
            &mut world,
            me,
            PlayerCommand::PlaceAssembly {
                assembly: index,
                pos,
            },
        );
        assert_eq!(rejection(&events), None, "{hoppers} hoppers");
        let machine = world.buildings[0].kind.machine().unwrap();
        capacities.push(machine.assembly.stats(&world.species).capacity);
    }

    assert_eq!(
        capacities[0], PLANTED_FRAME_BUFFER,
        "no hoppers is the frame's own buffer (decision 9)"
    );
    for pair in capacities.windows(2) {
        assert!(
            pair[1] > pair[0],
            "each hopper must raise capacity: {capacities:?}"
        );
    }
}

/// A machine was never an item, so picking it up gives back its parts.
#[test]
fn picking_up_a_machine_returns_its_parts() {
    let (mut world, me) = world_with_player();
    let design = drill(LIGHT, 2);
    let index = assemble(&mut world, me, &design);
    let pos = TilePos::new(
        world.player(me).unwrap().pos.x + 1,
        world.player(me).unwrap().pos.y,
    );
    send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos,
        },
    );
    let id = world.buildings[0].id;
    assert_eq!(world.player(me).unwrap().inventory.total(), 0);

    let events = send(&mut world, me, PlayerCommand::Pickup { building: id });

    assert_eq!(rejection(&events), None);
    assert!(world.buildings.is_empty());
    let inv = &world.player(me).unwrap().inventory;
    assert_eq!(
        inv.total(),
        design.part_count() as u32,
        "every part comes back"
    );
    for item in design.part_items() {
        assert!(inv.count(item) >= 1, "{} should be back", item.code());
    }
}

/// A machine has no slot to insert into: `Slot` names the smelter's two.
#[test]
fn a_machine_takes_nothing_in() {
    let (mut world, me) = world_with_player();
    let index = assemble(&mut world, me, &drill(LIGHT, 0));
    let pos = TilePos::new(
        world.player(me).unwrap().pos.x + 1,
        world.player(me).unwrap().pos.y,
    );
    send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos,
        },
    );
    let id = world.buildings[0].id;
    let ore = Item::new(ItemKind::Ore, LIGHT, Grade::B);
    give(&mut world, me, ore, 5);

    let events = send(
        &mut world,
        me,
        PlayerCommand::Insert {
            building: id,
            slot: sim::Slot::Input,
            item: ore,
            count: 1,
        },
    );

    assert_eq!(rejection(&events), Some(RejectReason::NotInsertable));
    assert_eq!(world.player(me).unwrap().inventory.count(ore), 5);
}

/// Placement is checked before survival: an illegal position is a rejection,
/// not a broken machine. Otherwise a misclick would destroy a design.
#[test]
fn an_out_of_reach_placement_is_refused_rather_than_broken() {
    let (mut world, me) = world_with_player();
    let design = Assembly::new(
        Part::of(PLANTED, refined(FRAIL)),
        vec![Part::of(PartKind::Head, refined(HEAVY))],
    );
    assert!(design.stats(&world.species).is_overweight());
    let index = assemble(&mut world, me, &design);
    let far = TilePos::new(
        world.player(me).unwrap().pos.x + REACH + 2,
        world.player(me).unwrap().pos.y,
    );

    let events = send(
        &mut world,
        me,
        PlayerCommand::PlaceAssembly {
            assembly: index,
            pos: far,
        },
    );

    assert_eq!(rejection(&events), Some(RejectReason::OutOfReach));
    assert!(
        !events
            .iter()
            .any(|e| matches!(e, Event::MachineBroke { .. })),
        "an overweight design must not break on a refused placement"
    );
    assert_eq!(
        world.player(me).unwrap().assemblies.len(),
        1,
        "it is still on the built list"
    );
}

// ---------------------------------------------------------------------------
// Amendment A5 and the verdict ruling: the bad case must be visible
// ---------------------------------------------------------------------------

/// The verdict never lies. Over every (density, strength) pair a world can
/// roll, SAFE never breaks and WILL BREAK always does — which is what makes a
/// three-state readout worth trusting instead of a percentage.
#[test]
fn the_verdict_is_never_wrong_about_a_design_that_breaks() {
    let (mut world, _) = world_with_player();
    let mut seen = [0_u32; 3];

    for density in 1..=100_u8 {
        for strength in 1..=100_u8 {
            world.species_mut(LIGHT).sheet = sheet(density, strength);
            world.species_mut(LIGHT).assayed = false;
            let design = pick(LIGHT, LIGHT);
            let verdict = design.stat_range(&world.species).verdict();
            let breaks = design.stats(&world.species).is_overweight();
            match verdict {
                BreakVerdict::Safe => {
                    assert!(!breaks, "SAFE but breaks at d{density} s{strength}");
                    seen[0] += 1;
                }
                BreakVerdict::Uncertain => seen[1] += 1,
                BreakVerdict::WillBreak => {
                    assert!(breaks, "WILL BREAK but holds at d{density} s{strength}");
                    seen[2] += 1;
                }
            }
        }
    }

    assert!(seen.iter().all(|&n| n > 0), "every verdict should occur");
    // The Game Director's measured claim: UNCERTAIN is a real coin flip, so a
    // third or so of unassayed designs are worth 30 ticks of assay.
    let uncertain = f64::from(seen[1]) / 10_000.0;
    assert!(
        (0.2..0.5).contains(&uncertain),
        "UNCERTAIN was {uncertain:.3} of designs, expected roughly a third"
    );
}

/// Assaying resolves the question: an exact sheet is never UNCERTAIN.
#[test]
fn an_assayed_species_is_never_uncertain() {
    let (mut world, _) = world_with_player();
    for density in 1..=100_u8 {
        for strength in (1..=100_u8).step_by(7) {
            world.species_mut(LIGHT).sheet = sheet(density, strength);
            world.species_mut(LIGHT).assayed = true;
            let range = pick(LIGHT, LIGHT).stat_range(&world.species);
            assert_eq!(range.low, range.high, "exact sheets give one reading");
            assert_ne!(
                range.verdict(),
                BreakVerdict::Uncertain,
                "d{density} s{strength} was uncertain after an assay"
            );
        }
    }
}

/// The exact numbers always lie inside the banded ones, which is what makes
/// reading each band end through `effective()` sound.
#[test]
fn exact_stats_lie_within_the_banded_range() {
    let (mut world, _) = world_with_player();
    for density in 1..=100_u8 {
        for strength in (1..=100_u8).step_by(3) {
            world.species_mut(LIGHT).sheet = sheet(density, strength);
            world.species_mut(LIGHT).assayed = false;
            let design = drill(LIGHT, 2);
            let exact = design.stats(&world.species);
            let range = design.stat_range(&world.species);
            for stat in sim::Stat::ALL {
                let (lo, hi) = (range.low.get(stat), range.high.get(stat));
                let v = exact.get(stat);
                assert!(
                    lo <= v && v <= hi,
                    "{stat:?} {v} outside {lo}..={hi} at d{density} s{strength}"
                );
            }
        }
    }
}

/// A5's bad case, through the commands: a frame whose own mass exceeds its own
/// budget breaks whatever head is fitted, and the verdict says so in advance.
#[test]
fn a_frame_that_cannot_carry_itself_reads_as_will_break() {
    let (mut world, me) = world_with_player();
    // density > 2.4 x strength at grade B is the frame that cannot carry
    // itself (ADR 0003 amendment A5).
    world.species_mut(LIGHT).sheet = sheet(100, 10);
    let design = pick(LIGHT, LIGHT);

    world.species_mut(LIGHT).assayed = false;
    assert_eq!(
        design.stat_range(&world.species).verdict(),
        BreakVerdict::WillBreak,
        "the player should be able to see this before spending anything"
    );

    let index = assemble(&mut world, me, &design);
    let equipped = send(&mut world, me, PlayerCommand::Equip { assembly: index });
    assert_eq!(
        rejection(&equipped),
        None,
        "the sim still does not refuse the design (decision 11)"
    );
    let tool = world.player(me).unwrap().tool.as_ref().unwrap();
    assert!(
        tool.assembly.stats(&world.species).is_overweight(),
        "it is carried, and ASSA-6's first swing is what breaks it"
    );
}

// ---------------------------------------------------------------------------
// The catalogue stays one table
// ---------------------------------------------------------------------------

/// Every part kind is an item kind, built from `PartKind::ALL` rather than
/// listed, so adding a catalogue row needs no edit here or in `ItemKind`.
#[test]
fn every_part_kind_is_an_item_kind() {
    for kind in PartKind::ALL {
        assert!(
            ItemKind::ALL.contains(&ItemKind::Part(kind)),
            "{} is missing from ItemKind::ALL",
            kind.name()
        );
    }
    assert_eq!(
        ItemKind::ALL.len(),
        ItemKind::ALL
            .iter()
            .collect::<std::collections::HashSet<_>>()
            .len(),
        "no duplicates"
    );
}

/// A part round-trips to an item and back, so the two representations cannot
/// drift apart.
#[test]
fn a_part_round_trips_through_an_item() {
    for kind in PartKind::ALL {
        for grade in Grade::ALL {
            let part = Part::of(kind, Item::new(ItemKind::Refined, LIGHT, grade));
            let item = part.as_item();
            assert_eq!(item.kind, ItemKind::Part(kind));
            assert!(item.is_part());
            assert_eq!(Part::from_item(item), Some(part), "{}", kind.name());
            assert_eq!(ItemKind::parse(kind.name()), Some(ItemKind::Part(kind)));
            assert_eq!(
                ItemKind::parse(&format!("part:{}", kind.name())),
                Some(ItemKind::Part(kind)),
                "the prefixed form code() writes must parse back"
            );
        }
    }
}

/// Stats of an empty-handed player are nothing: `MachineStats::default` is the
/// zero every sum starts from.
#[test]
fn a_player_starts_with_nothing_built_and_nothing_in_hand() {
    let (world, me) = world_with_player();
    let p = world.player(me).unwrap();
    assert!(p.assemblies.is_empty());
    assert!(p.tool.is_none());
    assert_eq!(MachineStats::default().mass, 0);
}

// ---------------------------------------------------------------------------
// What a design READS as: `debug::assembly_readout`, which is the inspector
// panel's one line and the only place the Game Director's rulings on this item
// (A5, A10, and durability held-only) are visible to a player.
//
// The readout lives in `sim` on purpose. Two clients computing a verdict would
// eventually disagree, and the first time they did the player would see a
// number the game does not believe.
// ---------------------------------------------------------------------------

/// The `durability ...` field of a readout, or `None` when there is none.
///
/// Resolves the field by its NAME rather than by position: a test that counted
/// " · " separators would keep passing if the fields were reordered and would
/// be asserting on a convention instead of on the thing.
fn durability_field(readout: &str) -> Option<&str> {
    readout
        .lines()
        .next()?
        .split(" · ")
        .find(|field| field.starts_with("durability"))
}

/// A10 as the Game Director re-ruled it: while the head's sheet is banded, the
/// pick's life is **swings used out of what its class affords**, and no
/// percentage appears anywhere. A percentage was the leak with extra steps —
/// a pool is always a multiple of `PICK_WEAR_PER_SWING`, so an integer percent
/// plus the player's own swing count identifies it after six swings.
///
/// The numbers pin that nothing here is computed from the TRUE max, which is
/// the whole point. LIGHT is strength 60, so at grade B the true max is
/// `1 x 48 x 60 = 2880` = 144 swings, and the band ends are 2400 and 3600 =
/// 120 and 180 swings. A half-drained pool therefore reads `72 of 120-180`:
/// 72 is the player's own count, and 144 — the one number that would hand back
/// the head's strength — is nowhere in the string.
#[test]
fn a_banded_pool_reads_as_swings_used_out_of_its_class() {
    let (mut world, me) = world_with_player();
    let design = pick(LIGHT, LIGHT);
    let index = assemble(&mut world, me, &design);

    let built = &mut world.player_mut(me).unwrap().assemblies[index as usize];
    assert_eq!(
        built.durability, 2880,
        "the anchor this test reasons about: 1 x (60 x 80%) x 60"
    );
    built.durability = 1440;
    world.species_mut(LIGHT).assayed = false;

    let built = &world.player(me).unwrap().assemblies[index as usize];
    let readout = debug::assembly_readout(&world, built);
    let field = durability_field(&readout);
    assert_eq!(
        field,
        Some("durability 72 of 120-180 swings used"),
        "swings used against the band the rough sheet already published"
    );
    assert!(
        !field.unwrap().contains("144") && !field.unwrap().contains('%'),
        "neither the true max nor a percentage of it may appear: {field:?}"
    );
}

/// Same amendment, the other half: once the sheet is known there is nothing
/// left to protect, so the pool reads exactly against its true max.
#[test]
fn an_assayed_pool_reads_exactly() {
    let (mut world, me) = world_with_player();
    let design = pick(LIGHT, LIGHT);
    let index = assemble(&mut world, me, &design);
    world.player_mut(me).unwrap().assemblies[index as usize].durability = 1440;

    let built = &world.player(me).unwrap().assemblies[index as usize];
    assert_eq!(
        durability_field(&debug::assembly_readout(&world, built)),
        Some("durability 72 of 144 swings used"),
        "assayed: there is nothing left to protect, so the max is exact — and \
         it is still said in swings, because points are a unit nothing else \
         in the game uses"
    );
}

/// CAPACITY CEILS, CONSUMPTION FLOORS, and this is the case that decides it.
///
/// The ruling said `div_ceil` throughout, which was right for the percentage:
/// there, its purpose was that a pick with a swing left must never read 0%,
/// because 0% is what a spent tool reads and the player would throw a working
/// one away. Pointed at *swings used*, ceiling rounds the other way — a pool
/// of 1 point would read `144 of 144 swings used`, a working pick reading as a
/// spent one. Same defect, inverted. So `used` is swings COMPLETED (floor) and
/// the band ends are what a pool AFFORDS (ceil, because the last swing drains
/// a part-full pool and still yields its ore).
///
/// A pool of 1 is not reachable by swinging — wear subtracts exactly 20 — so
/// for every real state the two agree, which is why only a test can tell them
/// apart, and why one should.
#[test]
fn a_pick_with_a_swing_left_does_not_read_as_a_spent_one() {
    let (mut world, me) = world_with_player();
    let design = pick(LIGHT, LIGHT);
    let index = assemble(&mut world, me, &design);
    world.player_mut(me).unwrap().assemblies[index as usize].durability = 1;
    world.species_mut(LIGHT).assayed = false;

    let built = &world.player(me).unwrap().assemblies[index as usize];
    assert_eq!(
        durability_field(&debug::assembly_readout(&world, built)),
        Some("durability 143 of 120-180 swings used"),
        "143 swings are done and one is not; `144 of ...` would say the pick \
         is finished while it can still mine"
    );
}

/// The other half of that decision — capacity CEILS — is invisible today, and
/// this is a guard against the retune that would reveal it rather than a test
/// of behaviour, which is a difference worth being honest about.
///
/// Every pool and every band end is `size x eff strength x
/// PICK_DURABILITY_PER_STRENGTH`, and 60 is a multiple of 20, so floor and
/// ceiling agree on all of them: there is no world, species or grade that can
/// tell the two apart through the readout. The day somebody retunes either
/// constant so that stops holding, the rounding starts showing — and this test
/// says which way it must go, instead of a comment nobody reads.
///
/// I first wrote this as `assert_eq!(2410u32.div_ceil(30), 81)`, which asserts
/// a fact about `div_ceil` and would have passed with the readout rounding
/// either way. A test that cannot fail for the reason it exists is not a test.
#[test]
fn todays_constants_hide_the_rounding_and_a_retune_would_not() {
    assert_eq!(
        PICK_DURABILITY_PER_STRENGTH % PICK_WEAR_PER_SWING,
        0,
        "pools and band ends are no longer all multiples of the wear per \
         swing, so `durability_readout`'s rounding is now visible to players: \
         capacity must CEIL (a part-full pool still buys a swing, and that \
         swing still yields its ore) and consumption must FLOOR (a pick with a \
         swing left must never read as a spent one). Check both branches of \
         the readout against this before changing these constants."
    );
}

/// THE HANDS' RATE IS IN THE READOUT, and it is the real constant rather than
/// a number somebody typed (the Game Director's ruling 5 on ASSA-6).
///
/// `speed` is work per tick, the unit bare hands are measured in, so printing
/// the baseline costs the player no arithmetic. Without it, `speed 23` looks
/// like a tool and is slower than the hands that built it — and nothing says
/// so until three refined are spent.
///
/// WHAT IT CANNOT SEE, said plainly: while `HAND_WORK_PER_TICK` is 25, a typed
/// `25` in the readout is the same program as the constant, and no test can
/// tell them apart. What this does catch is the moment that stops being true —
/// verified, not assumed: with a literal in the readout and the constant moved
/// to 50, this test fails and names the stale number.
#[test]
fn a_designs_speed_is_shown_against_bare_hands() {
    let (mut world, me) = world_with_player();
    let design = pick(LIGHT, LIGHT);
    let index = assemble(&mut world, me, &design);
    let built = &world.player(me).unwrap().assemblies[index as usize];
    let readout = debug::assembly_readout(&world, built);
    let speed = readout
        .lines()
        .next()
        .unwrap()
        .split(" · ")
        .find(|f| f.starts_with("speed "))
        .expect("a speed field");
    assert!(
        speed.contains(&format!("bare hands {HAND_WORK_PER_TICK}")),
        "the baseline must come from the constant, so a retune moves both: \
         {speed}"
    );

    // And it is there for a planted design too: "is planting this better than
    // swinging myself" is a live question that moves with the head. Narrow to
    // held if the Game Director rules the other way.
    let drill = drill(LIGHT, 1);
    let index = assemble(&mut world, me, &drill);
    let built = &world.player(me).unwrap().assemblies[index as usize];
    assert!(
        debug::assembly_readout(&world, built).contains("bare hands"),
        "a drill's rate against your own hands is a real decision"
    );
}

/// The Game Director's ruling 1 on this item, which had no test: a planted
/// design shows no durability at all. The head contributes a pool whatever
/// frame it sits on, but decision 12 parks drill wear, so the number would
/// never move — and a number that never moves teaches a mechanic that does
/// not exist.
///
/// Asserts the capacity field IS there, so the test still proves it is reading
/// a real planted readout rather than an empty string.
#[test]
fn a_planted_design_shows_no_durability_and_shows_what_it_holds() {
    let (mut world, me) = world_with_player();
    let design = drill(LIGHT, 1);
    let index = assemble(&mut world, me, &design);

    let built = &world.player(me).unwrap().assemblies[index as usize];
    let readout = debug::assembly_readout(&world, built);
    assert_eq!(
        durability_field(&readout),
        None,
        "drill wear is parked (decision 12), so the pool must not be shown"
    );
    assert!(
        readout.contains(" · holds "),
        "a planted design shows capacity instead: {readout}"
    );

    // The pool still EXISTS on the model — the ruling is a display rule, not a
    // change to the catalogue, which ADR 0003 point 6 forbids.
    assert!(
        built.durability > 0,
        "the head's contribution is unchanged; only the readout hides it"
    );
}

/// A MIXED design: one part's species assayed, the other's not. ASSA-17 asks
/// for a defined reading and this is it — every stat is banded per the species
/// it actually comes from, so the assayed half of a sum stays exact.
///
/// Head is LIGHT (assayed, density 20, size 1) and frame is HEAVY (unassayed,
/// density 100 -> band 76-100, size 2), so mass reads 172-220. If the code
/// banded every species whenever any one of them was unknown it would read
/// 153-225 instead, which is the wider, wronger answer.
#[test]
fn a_mixed_design_bands_each_part_by_its_own_species() {
    let (mut world, me) = world_with_player();
    let design = pick(HEAVY, LIGHT);
    let index = assemble(&mut world, me, &design);
    world.species_mut(HEAVY).assayed = false;

    let built = &world.player(me).unwrap().assemblies[index as usize];
    let readout = debug::assembly_readout(&world, built);
    let first = readout.lines().next().unwrap();
    assert!(
        first.starts_with("WILL BREAK · mass 172-220 of 6-120 budget"),
        "mass keeps the assayed head exact (20) and bands only the frame \
         (152-200); 153-225 would mean the band swallowed the known part: \
         {first}"
    );
    assert_eq!(
        durability_field(&readout),
        Some("durability 0 of 144 swings used"),
        "the pool comes from the head alone, and the head's species is \
         assayed, so this half of the readout is exact (one number, not a \
         band) while mass is not"
    );
}
