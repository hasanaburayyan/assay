//! Multiplayer depends on every peer computing the exact same world from the
//! same inputs. These tests hammer that property with random input streams.

use sim::{Input, PlayerCommand, PlayerId, Rng, SystemCommand, TilePos, World, WorldConfig, step};

fn new_world() -> World {
    World::new(WorldConfig {
        seed: 42,
        width_chunks: 6,
        height_chunks: 4,
    })
}

/// A random mix of joins and player commands, including invalid ones
/// (unknown players, unknown deposits, off-map targets) so rejections are
/// exercised too.
fn random_inputs(rng: &mut Rng, world: &World) -> Vec<Input> {
    let mut inputs = Vec::new();
    if world.players.len() < 8 && rng.range(0, 100) < 2 {
        let name = format!("p{}", world.players.len());
        inputs.push(Input::System(SystemCommand::AddPlayer { name }));
    }
    for _ in 0..rng.range(0, 4) {
        let player = PlayerId(rng.range(0, world.players.len() as u32 + 1));
        let command = match rng.range(0, 3) {
            0 => PlayerCommand::Mine,
            1 => PlayerCommand::MoveTo {
                target: TilePos::new(
                    rng.range(0, world.width() as u32 + 4) as i32 - 2,
                    rng.range(0, world.height() as u32 + 4) as i32 - 2,
                ),
            },
            _ => PlayerCommand::Stop,
        };
        inputs.push(Input::player(player, command));
    }
    inputs
}

/// Two peers fed the same inputs must agree on every tick, and emit the
/// same events.
#[test]
fn peers_given_the_same_inputs_stay_identical() {
    let mut script = Rng::new(7);
    let (mut a, mut b) = (new_world(), new_world());
    let (mut ea, mut eb) = (Vec::new(), Vec::new());

    for _ in 0..5_000 {
        let inputs = random_inputs(&mut script, &a);
        step(&mut a, &inputs, &mut ea);
        step(&mut b, &inputs, &mut eb);
        assert_eq!(a.state_hash(), b.state_hash(), "desync at tick {}", a.tick);
    }
    assert_eq!(ea, eb);
    assert!(a.players.len() > 1, "script should have added players");
}

/// A peer that joins late gets a save and must then keep up exactly.
#[test]
fn a_peer_joining_from_a_save_stays_in_sync() {
    let mut script = Rng::new(99);
    let mut host = new_world();
    let mut events = Vec::new();

    for _ in 0..2_000 {
        let inputs = random_inputs(&mut script, &host);
        step(&mut host, &inputs, &mut events);
    }

    let mut joiner = World::from_json(&host.to_json().unwrap()).unwrap();
    for _ in 0..3_000 {
        let inputs = random_inputs(&mut script, &host);
        step(&mut host, &inputs, &mut events);
        step(&mut joiner, &inputs, &mut events);
        assert_eq!(
            host.state_hash(),
            joiner.state_hash(),
            "desync at tick {}",
            host.tick
        );
    }
}

/// A fixed script must always produce this exact hash, on every machine and
/// every build. If this fails after an intentional rule change, update the
/// constant. If it fails without one (or only on one OS), something
/// nondeterministic slipped into the sim.
#[test]
fn golden_hash_is_stable_across_machines() {
    let mut script = Rng::new(2026);
    let mut world = new_world();
    let mut events = Vec::new();
    for _ in 0..2_000 {
        let inputs = random_inputs(&mut script, &world);
        step(&mut world, &inputs, &mut events);
    }
    assert_eq!(
        format!("{:016x}", world.state_hash()),
        "323d2fe20d915817",
        "world hash changed; see the comment on this test"
    );
}
