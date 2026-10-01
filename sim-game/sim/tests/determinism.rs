//! Multiplayer depends on every peer computing the exact same world from the
//! same inputs. These tests hammer that property with random input streams.

use sim::{
    BuildingId, Grade, Input, Item, ItemKind, ItemStack, PlayerCommand, PlayerId, RecipeId, Rng,
    Slot, SpeciesId, SystemCommand, TilePos, World, WorldConfig, step,
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
    let n_species = world.species.len() as u32;
    for _ in 0..rng.range(0, 4) {
        let player = PlayerId(rng.range(0, world.players.len() as u32 + 1));
        let p = world.player(player);
        let near = p.map_or(world.spawn_tile(), |p| p.pos);
        let stacks: &[ItemStack] = p.map_or(&[], |p| p.inventory.stacks());
        // Mostly something the player actually holds; sometimes nonsense.
        let random_item = |rng: &mut Rng| -> Item {
            if !stacks.is_empty() && rng.range(0, 4) > 0 {
                stacks[rng.range(0, stacks.len() as u32) as usize].item
            } else {
                Item::new(
                    ItemKind::ALL[rng.range(0, ItemKind::ALL.len() as u32) as usize],
                    SpeciesId(rng.range(0, n_species + 1) as u8),
                    Grade::ALL[rng.range(0, 3) as usize],
                )
            }
        };
        // A stack of `kind` the player holds: usually the biggest one.
        let held = |kind: ItemKind, rng: &mut Rng| -> Option<Item> {
            let matching: Vec<&ItemStack> = stacks.iter().filter(|s| s.item.kind == kind).collect();
            if matching.is_empty() {
                None
            } else if rng.range(0, 4) > 0 {
                matching.iter().max_by_key(|s| s.count).map(|s| s.item)
            } else {
                Some(matching[rng.range(0, matching.len() as u32) as usize].item)
            }
        };
        let random_building = |rng: &mut Rng| BuildingId(rng.range(0, world.next_building_id + 2));
        let command = match rng.range(0, 15) {
            0 | 1 => PlayerCommand::Mine,
            12 => PlayerCommand::Assay,
            13 => PlayerCommand::Rename {
                species: SpeciesId(rng.range(0, n_species + 1) as u8),
                name: ["Adaite", "", "Bad name", "Kel-2"][rng.range(0, 4) as usize].into(),
            },
            14 => PlayerCommand::GrantRename {
                species: SpeciesId(rng.range(0, n_species + 1) as u8),
                to: PlayerId(rng.range(0, world.players.len() as u32 + 1)),
            },
            2 => {
                let recipe = RecipeId::ALL[rng.range(0, RecipeId::ALL.len() as u32) as usize];
                let item = held(recipe.recipe().input.0, rng)
                    .filter(|_| rng.range(0, 4) > 0)
                    .unwrap_or_else(|| random_item(rng));
                PlayerCommand::Craft {
                    recipe,
                    item,
                    count: rng.range(0, 4),
                }
            }
            3 => PlayerCommand::Place {
                item: held(ItemKind::Smelter, rng)
                    .filter(|_| rng.range(0, 4) > 0)
                    .unwrap_or_else(|| random_item(rng)),
                pos: TilePos::new(
                    near.x + rng.range(0, 7) as i32 - 3,
                    near.y + rng.range(0, 7) as i32 - 3,
                ),
            },
            4 => {
                // Mostly feed the nearest smelter with something in hand.
                let nearest = world
                    .buildings
                    .iter()
                    .min_by_key(|b| b.distance_from(near))
                    .map(|b| b.id);
                let slot = if rng.range(0, 2) == 0 {
                    Slot::Input
                } else {
                    Slot::Fuel
                };
                PlayerCommand::Insert {
                    building: nearest
                        .filter(|_| rng.range(0, 4) > 0)
                        .unwrap_or_else(|| random_building(rng)),
                    slot,
                    item: held(ItemKind::Ore, rng)
                        .filter(|_| rng.range(0, 4) > 0)
                        .unwrap_or_else(|| random_item(rng)),
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
                // Head for a live deposit soft enough to mine by hand.
                let live: Vec<&sim::OreDeposit> = world
                    .deposits
                    .iter()
                    .filter(|d| !d.is_depleted())
                    .filter(|d| {
                        u32::from(world.species(d.species).sheet.hardness)
                            <= sim::tuning::HAND_MINE_MAX_HARDNESS
                    })
                    .collect();
                let target = if live.is_empty() {
                    world.spawn_tile()
                } else {
                    live[rng.range(0, live.len() as u32) as usize].center
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
        "bb0c61da64d0f008",
        "world hash changed; see the comment on this test"
    );
}
