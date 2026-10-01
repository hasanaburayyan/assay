//! ADR 0001 decisions 8 and 13: rough sheets that sharpen on assay, and
//! species named by their discoverer.

use sim::tuning::ASSAY_TICKS;
use sim::{
    DepositId, Event, Input, NameError, PlayerCommand, PlayerId, Property, RejectReason, Sheet,
    SpeciesId, StopReason, SystemCommand, World, WorldConfig, debug, step,
};

fn world_with_players() -> (World, PlayerId, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    for s in &mut world.species {
        s.sheet.hardness = s
            .sheet
            .hardness
            .min(sim::tuning::HAND_MINE_MAX_HARDNESS as u8);
    }
    let joins = [
        Input::System(SystemCommand::AddPlayer { name: "ada".into() }),
        Input::System(SystemCommand::AddPlayer {
            name: "grace".into(),
        }),
    ];
    step(&mut world, &joins, &mut Vec::new());
    (world, PlayerId(0), PlayerId(1))
}

fn run(world: &mut World, inputs: &[Input], ticks: u32) -> Vec<Event> {
    let mut events = Vec::new();
    step(world, inputs, &mut events);
    for _ in 1..ticks {
        step(world, &[], &mut events);
    }
    events
}

fn stand_on(world: &mut World, who: PlayerId, id: DepositId) -> SpeciesId {
    let d = world.deposit(id).unwrap().clone();
    world.player_mut(who).unwrap().pos = d.center;
    d.species
}

#[test]
fn bands_are_rough_and_cover_the_value() {
    assert_eq!(Sheet::band(1), (1, 25));
    assert_eq!(Sheet::band(25), (1, 25));
    assert_eq!(Sheet::band(26), (26, 50));
    assert_eq!(Sheet::band(100), (76, 100));
}

#[test]
fn a_fresh_species_reads_as_bands_until_assayed() {
    let (mut world, me, _) = world_with_players();
    let species = stand_on(&mut world, me, DepositId(0));
    let s = world.species(species);
    let exact = s.sheet.hardness;
    assert!(!s.assayed);
    let rough = debug::reading(s, Property::Hardness);
    assert!(rough.contains('-'), "{rough}");
    assert_ne!(rough, exact.to_string());

    let events = run(&mut world, &[Input::player(me, PlayerCommand::Assay)], 1);
    assert_eq!(
        events,
        vec![Event::AssayStarted {
            player: me,
            deposit: DepositId(0),
            species
        }]
    );
    let events = run(&mut world, &[], ASSAY_TICKS - 1);
    assert_eq!(
        events,
        vec![
            Event::SpeciesAssayed {
                player: me,
                species
            },
            Event::SpeciesDiscovered {
                player: me,
                species
            },
        ]
    );
    let s = world.species(species);
    assert!(s.assayed);
    assert_eq!(debug::reading(s, Property::Hardness), exact.to_string());
    assert!(world.player(me).unwrap().assaying.is_none());

    let events = run(&mut world, &[Input::player(me, PlayerCommand::Assay)], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::AlreadyAssayed,
            ..
        }]
    ));
}

#[test]
fn assay_needs_a_deposit_and_stops_when_you_leave_or_stop() {
    let (mut world, me, _) = world_with_players();
    let bare = (0..world.width())
        .map(|x| sim::TilePos::new(x, 0))
        .find(|&t| world.deposit_at(t).is_none())
        .unwrap();
    world.player_mut(me).unwrap().pos = bare;
    let events = run(&mut world, &[Input::player(me, PlayerCommand::Assay)], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::NotOnDeposit,
            ..
        }]
    ));

    let species = stand_on(&mut world, me, DepositId(0));
    run(&mut world, &[Input::player(me, PlayerCommand::Assay)], 3);
    let events = run(&mut world, &[Input::player(me, PlayerCommand::Stop)], 1);
    assert_eq!(
        events,
        vec![Event::AssayStopped {
            player: me,
            deposit: DepositId(0),
            reason: StopReason::Stopped
        }]
    );
    assert!(!world.species(species).assayed);

    let center = world.deposit(DepositId(0)).unwrap().center;
    let r = i32::from(world.deposit(DepositId(0)).unwrap().radius);
    let away = sim::TilePos::new(center.x + r + 2, center.y);
    let events = run(
        &mut world,
        &[
            Input::player(me, PlayerCommand::Assay),
            Input::player(me, PlayerCommand::MoveTo { target: away }),
        ],
        (r + 2) as u32,
    );
    assert!(events.contains(&Event::AssayStopped {
        player: me,
        deposit: DepositId(0),
        reason: StopReason::LeftDeposit
    }));
}

#[test]
fn mining_discovers_a_species_once() {
    let (mut world, me, other) = world_with_players();
    let species = stand_on(&mut world, me, DepositId(0));
    let events = run(
        &mut world,
        &[Input::player(me, PlayerCommand::Mine)],
        sim::tuning::HAND_MINE_TICKS * 2,
    );
    assert_eq!(
        events
            .iter()
            .filter(|e| matches!(e, Event::SpeciesDiscovered { .. }))
            .count(),
        1
    );
    assert_eq!(world.species(species).discoverer, Some(me));

    stand_on(&mut world, other, DepositId(0));
    let events = run(
        &mut world,
        &[Input::player(other, PlayerCommand::Mine)],
        sim::tuning::HAND_MINE_TICKS,
    );
    assert!(
        !events
            .iter()
            .any(|e| matches!(e, Event::SpeciesDiscovered { .. }))
    );
    assert_eq!(world.species(species).discoverer, Some(me));
}

#[test]
fn only_the_discoverer_or_a_grantee_may_rename() {
    // Decision 13.
    let (mut world, me, other) = world_with_players();
    let species = stand_on(&mut world, me, DepositId(0));
    let rename = |who, name: &str| {
        Input::player(
            who,
            PlayerCommand::Rename {
                species,
                name: name.into(),
            },
        )
    };

    // Undiscovered: nobody may name it.
    let events = run(&mut world, &[rename(me, "Adaite")], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::NotDiscovered,
            ..
        }]
    ));

    run(
        &mut world,
        &[Input::player(me, PlayerCommand::Mine)],
        sim::tuning::HAND_MINE_TICKS,
    );
    assert_eq!(world.species(species).discoverer, Some(me));
    run(&mut world, &[Input::player(me, PlayerCommand::Stop)], 1);

    let events = run(&mut world, &[rename(other, "Graceite")], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::NotDiscoverer,
            ..
        }]
    ));

    let events = run(&mut world, &[rename(me, "Adaite")], 1);
    assert_eq!(
        events,
        vec![Event::SpeciesRenamed {
            player: me,
            species,
            name: "Adaite".into()
        }]
    );
    assert_eq!(world.species(species).name(), "Adaite");
    assert!(
        world
            .item_name(sim::Item::new(sim::ItemKind::Ore, species, sim::Grade::C))
            .starts_with("Adaite")
    );

    // The map glyph stays the generated initial, which is unique.
    let glyph = debug::species_symbol(world.species(species));
    assert_eq!(
        Some(glyph),
        world.species(species).generated_name.chars().next()
    );

    // Bad names.
    for (name, err) in [
        ("", NameError::Empty),
        ("a-name-that-is-far-too-long", NameError::TooLong),
        ("no spaces", NameError::BadCharacter),
    ] {
        let events = run(&mut world, &[rename(me, name)], 1);
        assert!(
            matches!(
                events[..],
                [Event::CommandRejected {
                    reason: RejectReason::BadName(e),
                    ..
                }] if e == err
            ),
            "{name:?}: {events:?}"
        );
    }

    // Grants: only the discoverer grants; then the grantee may rename.
    let grant = |who, to| Input::player(who, PlayerCommand::GrantRename { species, to });
    let events = run(&mut world, &[grant(other, me)], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::NotDiscoverer,
            ..
        }]
    ));
    let events = run(&mut world, &[grant(me, PlayerId(9))], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::NoSuchPlayer,
            ..
        }]
    ));
    let events = run(&mut world, &[grant(me, other)], 1);
    assert_eq!(
        events,
        vec![Event::RenameGranted {
            species,
            from: me,
            to: other
        }]
    );
    let events = run(&mut world, &[grant(me, other)], 1);
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::AlreadyGranted,
            ..
        }]
    ));
    let events = run(&mut world, &[rename(other, "Graceite")], 1);
    assert!(matches!(events[..], [Event::SpeciesRenamed { .. }]));
    assert_eq!(world.species(species).name(), "Graceite");

    // Everything above went through the tick, so a peer replaying the same
    // inputs would hash identically; the save round-trips the new state.
    let loaded = World::from_json(&world.to_json().unwrap()).unwrap();
    assert_eq!(loaded, world);
}

#[test]
fn renaming_an_unknown_species_is_rejected() {
    let (mut world, me, _) = world_with_players();
    let events = run(
        &mut world,
        &[Input::player(
            me,
            PlayerCommand::Rename {
                species: SpeciesId(200),
                name: "X".into(),
            },
        )],
        1,
    );
    assert!(matches!(
        events[..],
        [Event::CommandRejected {
            reason: RejectReason::UnknownSpecies,
            ..
        }]
    ));
}
