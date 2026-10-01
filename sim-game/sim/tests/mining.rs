use sim::tuning::{HAND_MINE_MAX_HARDNESS, HAND_MINE_TICKS, YIELD_BY_GRADE};
use sim::{
    DepositId, Event, Grade, Input, Item, ItemKind, PlayerCommand, PlayerId, RejectReason,
    StopReason, SystemCommand, TilePos, World, WorldConfig, step,
};

/// A world with one player, "ada", already joined, where every species is
/// soft enough to mine by hand unless a test says otherwise.
fn world_with_player(seed: u64) -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed,
        ..WorldConfig::default()
    });
    for s in &mut world.species {
        s.sheet.hardness = s.sheet.hardness.min(HAND_MINE_MAX_HARDNESS as u8);
    }
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

/// Put the player on the centre of deposit `id` without walking, as a test
/// shortcut. Real play walks there with `MoveTo`.
fn teleport_onto(world: &mut World, me: PlayerId, id: DepositId) -> TilePos {
    let center = world.deposit(id).unwrap().center;
    world.player_mut(me).unwrap().pos = center;
    center
}

fn run(world: &mut World, inputs: &[Input], ticks: u32) -> Vec<Event> {
    let mut events = Vec::new();
    step(world, inputs, &mut events);
    for _ in 1..ticks {
        step(world, &[], &mut events);
    }
    events
}

#[test]
fn mining_yields_the_grades_share_every_hand_mine_ticks() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    teleport_onto(&mut world, me, id);
    world.deposit_mut(id).unwrap().purity = 50; // grade B
    let (species, before) = {
        let d = world.deposit(id).unwrap();
        (d.species, d.amount)
    };
    let item = Item::new(ItemKind::Ore, species, Grade::B);
    let per_cycle = YIELD_BY_GRADE[Grade::B as usize];

    let events = run(&mut world, &[Input::player(me, PlayerCommand::Mine)], 1);
    assert_eq!(
        events,
        vec![Event::MiningStarted {
            player: me,
            deposit: id,
            species
        }]
    );

    let events = run(&mut world, &[], HAND_MINE_TICKS * 3 - 1);
    let mined: Vec<_> = events
        .iter()
        .filter(|e| matches!(e, Event::OreMined { .. }))
        .collect();
    assert_eq!(mined.len(), 3);
    assert_eq!(
        mined[0],
        &Event::OreMined {
            player: me,
            deposit: id,
            item,
            amount: per_cycle
        }
    );
    assert_eq!(
        world.player(me).unwrap().inventory.count(item),
        3 * per_cycle
    );
    assert_eq!(world.deposit(id).unwrap().amount, before - 3);
    assert!(world.player(me).unwrap().mining.is_some());
}

#[test]
fn purer_deposits_yield_more_per_unit_mined() {
    // Decision 1: purity raises yield.
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    teleport_onto(&mut world, me, id);
    let mut got = Vec::new();
    for purity in [10, 50, 90] {
        world.deposit_mut(id).unwrap().purity = purity;
        world.player_mut(me).unwrap().inventory = Default::default();
        run(
            &mut world,
            &[
                Input::player(me, PlayerCommand::Stop),
                Input::player(me, PlayerCommand::Mine),
            ],
            HAND_MINE_TICKS,
        );
        got.push(world.player(me).unwrap().inventory.total());
    }
    assert!(got[0] < got[1] && got[1] < got[2], "{got:?}");
}

#[test]
fn hand_mining_refuses_ore_that_is_too_hard() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    teleport_onto(&mut world, me, id);
    let species = world.deposit(id).unwrap().species;
    world.species_mut(species).sheet.hardness = HAND_MINE_MAX_HARDNESS as u8 + 1;
    let events = run(&mut world, &[Input::player(me, PlayerCommand::Mine)], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: PlayerCommand::Mine,
            reason: RejectReason::TooHardForHands
        }]
    );
}

#[test]
fn mine_requires_standing_on_a_deposit() {
    let (mut world, me) = world_with_player(9);
    let bare = (0..world.width())
        .map(|x| TilePos::new(x, 0))
        .find(|&t| world.deposit_at(t).is_none())
        .expect("some tile has no deposit");
    world.player_mut(me).unwrap().pos = bare;
    let events = run(&mut world, &[Input::player(me, PlayerCommand::Mine)], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: PlayerCommand::Mine,
            reason: RejectReason::NotOnDeposit
        }]
    );
    assert!(world.player(me).unwrap().mining.is_none());
}

#[test]
fn stop_ends_mining() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    teleport_onto(&mut world, me, id);
    run(&mut world, &[Input::player(me, PlayerCommand::Mine)], 2);
    let events = run(&mut world, &[Input::player(me, PlayerCommand::Stop)], 1);
    assert_eq!(
        events,
        vec![Event::MiningStopped {
            player: me,
            deposit: id,
            reason: StopReason::Stopped
        }]
    );
    assert!(world.player(me).unwrap().mining.is_none());
}

#[test]
fn walking_off_the_deposit_ends_mining() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    let center = teleport_onto(&mut world, me, id);
    let radius = i32::from(world.deposit(id).unwrap().radius);
    run(&mut world, &[Input::player(me, PlayerCommand::Mine)], 1);

    let outside = TilePos::new(center.x + radius + 2, center.y);
    let events = run(
        &mut world,
        &[Input::player(me, PlayerCommand::MoveTo { target: outside })],
        (radius + 2) as u32,
    );
    assert!(events.contains(&Event::MiningStopped {
        player: me,
        deposit: id,
        reason: StopReason::LeftDeposit
    }));
    assert!(world.player(me).unwrap().mining.is_none());
    assert!(world.player(me).unwrap().inventory.total() >= 1);
}

#[test]
fn mining_out_a_deposit_depletes_it_and_stops() {
    let (mut world, me) = world_with_player(9);
    let id = DepositId(0);
    teleport_onto(&mut world, me, id);
    world.deposit_mut(id).unwrap().amount = 2;

    let events = run(
        &mut world,
        &[Input::player(me, PlayerCommand::Mine)],
        HAND_MINE_TICKS * 2 + 5,
    );
    assert!(world.deposit(id).unwrap().is_depleted());
    let tail: Vec<_> = events.iter().rev().take(2).rev().collect();
    assert_eq!(
        tail,
        vec![
            &Event::DepositDepleted { deposit: id },
            &Event::MiningStopped {
                player: me,
                deposit: id,
                reason: StopReason::Depleted
            }
        ]
    );

    let events = run(&mut world, &[Input::player(me, PlayerCommand::Mine)], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: PlayerCommand::Mine,
            reason: RejectReason::DepositDepleted
        }]
    );
}

#[test]
fn mining_survives_a_save_and_load() {
    let (mut world, me) = world_with_player(9);
    teleport_onto(&mut world, me, DepositId(0));
    run(&mut world, &[Input::player(me, PlayerCommand::Mine)], 3);
    let mut loaded = World::from_json(&world.to_json().unwrap()).unwrap();
    assert_eq!(loaded, world);
    run(&mut loaded, &[], HAND_MINE_TICKS);
    run(&mut world, &[], HAND_MINE_TICKS);
    assert_eq!(loaded.state_hash(), world.state_hash());
}
