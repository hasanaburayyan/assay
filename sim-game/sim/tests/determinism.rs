//! Multiplayer depends on every peer computing the exact same world from the
//! same inputs. These tests hammer that property with random input streams.

use sim::{
    BuildingId, Input, Item, PlayerCommand, PlayerId, RecipeId, Rng, SystemCommand, TilePos, World,
    WorldConfig, step,
};

fn new_world() -> World {
    World::new(WorldConfig {
        seed: 42,
        width_chunks: 6,
        height_chunks: 4,
    })
}

/// A random mix of joins and player commands, including invalid ones
/// (unknown players, unknown deposits, off-map targets) so rejections are
/// exercised too. It is nudged toward the real loop (walk to deposits, mine,
/// craft a smelter once there is stone, place and feed it) so buildings and
/// smelting happen from inputs alone, without any test-only shortcuts.
fn random_inputs(rng: &mut Rng, world: &World) -> Vec<Input> {
    let mut inputs = Vec::new();
    if world.players.len() < 8 && rng.range(0, 100) < 2 {
        let name = format!("p{}", world.players.len());
        inputs.push(Input::System(SystemCommand::AddPlayer { name }));
    }
    for _ in 0..rng.range(0, 4) {
        let player = PlayerId(rng.range(0, world.players.len() as u32 + 1));
        let p = world.player(player);
        let inv = p.map(|p| &p.inventory);
        let has = |item, n| inv.is_some_and(|i| i.has(item, n));
        let near = p.map_or(world.spawn_tile(), |p| p.pos);
        let random_item = |rng: &mut Rng| Item::ALL[rng.range(0, Item::ALL.len() as u32) as usize];
        let random_building = |rng: &mut Rng| BuildingId(rng.range(0, world.next_building_id + 2));
        let command = match rng.range(0, 12) {
            0 | 1 => PlayerCommand::Mine,
            2 => PlayerCommand::Craft {
                recipe: if has(Item::Stone, 5) && rng.range(0, 4) > 0 {
                    RecipeId::Smelter
                } else {
                    RecipeId::ALL[rng.range(0, RecipeId::ALL.len() as u32) as usize]
                },
                count: rng.range(0, 4),
            },
            3 => PlayerCommand::Place {
                item: if has(Item::Smelter, 1) && rng.range(0, 4) > 0 {
                    Item::Smelter
                } else {
                    random_item(rng)
                },
                pos: TilePos::new(
                    near.x + rng.range(0, 7) as i32 - 3,
                    near.y + rng.range(0, 7) as i32 - 3,
                ),
            },
            4 => {
                // Mostly feed the nearest smelter with fuel or ore in hand.
                let nearest = world
                    .buildings
                    .iter()
                    .min_by_key(|b| b.distance_from(near))
                    .map(|b| b.id);
                let item = match rng.range(0, 4) {
                    0 if has(Item::Coal, 1) => Item::Coal,
                    1 if has(Item::IronOre, 1) => Item::IronOre,
                    2 if has(Item::CopperOre, 1) => Item::CopperOre,
                    _ => random_item(rng),
                };
                PlayerCommand::Insert {
                    building: nearest
                        .filter(|_| rng.range(0, 4) > 0)
                        .unwrap_or_else(|| random_building(rng)),
                    item,
                    count: rng.range(0, 5),
                }
            }
            5 => PlayerCommand::Take {
                building: random_building(rng),
            },
            6 => PlayerCommand::Pickup {
                building: random_building(rng),
            },
            7 | 8 => {
                // Head for a deposit, so mining actually happens: stone
                // first until there is enough for a smelter.
                let wanted: Vec<&sim::OreDeposit> = world
                    .deposits
                    .iter()
                    .filter(|d| !d.is_depleted())
                    .filter(|d| has(Item::Stone, 5) || d.kind == sim::OreKind::Stone)
                    .collect();
                let target = if wanted.is_empty() {
                    world.spawn_tile()
                } else {
                    wanted[rng.range(0, wanted.len() as u32) as usize].center
                };
                PlayerCommand::MoveTo { target }
            }
            9 | 10 => PlayerCommand::MoveTo {
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
    assert!(
        a.next_building_id > 0,
        "script should have placed at least one building"
    );
    assert!(
        ea.iter()
            .any(|e| matches!(e, sim::Event::ItemSmelted { .. })),
        "script should have smelted something"
    );
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
        "9d0e359cc2cc17b7",
        "world hash changed; see the comment on this test"
    );
}
