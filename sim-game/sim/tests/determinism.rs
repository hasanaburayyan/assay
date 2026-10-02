//! Multiplayer depends on every peer computing the exact same world from the
//! same inputs. These tests hammer that property with random input streams.

use sim::{
    BuildingId, Grade, Input, Item, ItemKind, ItemStack, PartKind, PlayerCommand, PlayerId,
    RecipeId, Rng, Slot, SpeciesId, SystemCommand, TilePos, World, WorldConfig, step,
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
        let n_built = p.map_or(0, |p| p.assemblies.len() as u32);
        let random_part = |rng: &mut Rng| -> Item {
            let kind = PartKind::ALL[rng.range(0, PartKind::ALL.len() as u32) as usize];
            // Mostly a part the player holds, sometimes one they do not.
            held(ItemKind::Part(kind), rng)
                .filter(|_| rng.range(0, 4) > 0)
                .unwrap_or_else(|| {
                    Item::new(
                        ItemKind::Part(kind),
                        SpeciesId(rng.range(0, n_species + 1) as u8),
                        Grade::ALL[rng.range(0, 3) as usize],
                    )
                })
        };
        let command = match rng.range(0, 24) {
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
            // The assembly commands (ASSA-5). Deliberately fed junk as often
            // as sense, so every rejection path is walked on both peers.
            15 | 16 => PlayerCommand::MakePart {
                kind: PartKind::ALL[rng.range(0, PartKind::ALL.len() as u32) as usize],
                material: held(ItemKind::Refined, rng)
                    .filter(|_| rng.range(0, 4) > 0)
                    .unwrap_or_else(|| random_item(rng)),
                count: rng.range(0, 3),
            },
            17..=19 => {
                // A frame plus 0..3 mounted parts, which is sometimes a legal
                // pick or drill and sometimes nonsense.
                let frame = random_part(rng);
                let mounted = (0..rng.range(0, 4)).map(|_| random_part(rng)).collect();
                PlayerCommand::Assemble { frame, mounted }
            }
            20 => PlayerCommand::Equip {
                assembly: rng.range(0, n_built + 2),
            },
            21 => PlayerCommand::Unequip,
            22 => PlayerCommand::PlaceAssembly {
                assembly: rng.range(0, n_built + 2),
                pos: TilePos::new(
                    near.x + rng.range(0, 7) as i32 - 3,
                    near.y + rng.range(0, 7) as i32 - 3,
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
        "6f2062de05c2d6f7",
        "world hash changed; see the comment on this test"
    );
}

/// The assembly commands need refined material, and the random script above
/// almost never gets a smelter running long enough to make any — so on that
/// script every `MakePart` is rejected and none of ASSA-5's rules are reached.
///
/// This is the same random script against a fixture that hands every player a
/// pile of refined material to start with. Seeding an inventory is a starting
/// state, not a rule shortcut: every part, assembly, placement and break below
/// still happens only through `step` and the real commands.
#[test]
fn peers_agree_on_the_assembly_commands() {
    let mut script = Rng::new(31);
    let (mut a, mut b) = (stocked_world(), stocked_world());
    let (mut ea, mut eb) = (Vec::new(), Vec::new());

    for _ in 0..8_000 {
        let inputs = random_inputs(&mut script, &a);
        step(&mut a, &inputs, &mut ea);
        step(&mut b, &inputs, &mut eb);
        assert_eq!(a.state_hash(), b.state_hash(), "desync at tick {}", a.tick);
    }
    assert_eq!(ea, eb);

    // A green run proves agreement, not coverage: assert the script really
    // walked each new path, or this test could pass while testing nothing.
    let reached = |name: &str, f: &dyn Fn(&sim::Event) -> bool| {
        let n = ea.iter().filter(|e| f(e)).count();
        assert!(n > 0, "the script never reached {name}");
        n
    };
    reached("PartsMade", &|e| matches!(e, sim::Event::PartsMade { .. }));
    reached("Assembled", &|e| matches!(e, sim::Event::Assembled { .. }));
    reached("Equipped", &|e| matches!(e, sim::Event::Equipped { .. }));
    reached("MachinePlaced", &|e| {
        matches!(e, sim::Event::MachinePlaced { .. })
    });
    let breaks = reached("MachineBroke", &|e| {
        matches!(e, sim::Event::MachineBroke { .. })
    });
    // Every break is a roll per part off `world.rng`, so the breaks are what
    // make this test say anything about determinism that the others do not.
    assert!(
        breaks > 2,
        "only {breaks} breaks; the roll is barely exercised"
    );
}

/// The test world, plus a stock of refined material of every species and grade
/// in every player's inventory, so parts can actually be made.
fn stocked_world() -> World {
    let mut world = new_world();
    let joins: Vec<Input> = (0..4)
        .map(|i| {
            Input::System(SystemCommand::AddPlayer {
                name: format!("p{i}"),
            })
        })
        .collect();
    step(&mut world, &joins, &mut Vec::new());
    let species: Vec<SpeciesId> = world.species.iter().map(|s| s.id).collect();
    for player in &mut world.players {
        for &id in &species {
            for grade in Grade::ALL {
                player
                    .inventory
                    .add(Item::new(ItemKind::Refined, id, grade), 60);
            }
        }
    }
    world
}

/// **A SECOND GOLDEN ANCHOR, BECAUSE THE FIRST ONE IS BLIND TO TOOLS.**
///
/// `golden_hash_is_stable_across_machines` hashes only the FINAL world after
/// 2000 random ticks, and I probed that world: every player ends with
/// `mining: None` and nothing in hand. So a change to how a held tool or a
/// planted machine mines cannot move that hash, and its passing says nothing
/// about this code. It did not move when ASSA-6 landed, and that was luck.
///
/// This one is scripted rather than random, so it ends in exactly the state
/// the random script never reaches: a worn pick in hand, mid-swing, beside a
/// drill that has mined into its hopper. Update the constant only for an
/// intentional rule change, and say so in the commit.
#[test]
fn golden_hash_covers_a_held_tool_and_a_planted_machine() {
    use sim::{Mount, Part, PartKind, Sheet};

    let mut world = new_world();
    let mut events = Vec::new();
    // Every sheet set on purpose, not clamped from the seed: strength 90 so
    // the pool outlasts the swinging below (it must have WORN, not run out),
    // hardness 30 so the ore is hand-mineable, density 10 so the drill is well
    // inside its frame's budget. A seed-dependent anchor would be an anchor to
    // nothing.
    //
    // THE MARGIN, WRITTEN DOWN BECAUSE IT HAS ALREADY BEEN SPENT ONCE. At
    // grade B this head is effective hardness 24 and effective strength 72, so
    // the pool is 72 × 60 = 4320 = 216 swings, and the rate is
    // 24 × HEAD_SPEED_PER_HARDNESS work per tick. The original 500 ticks left
    // 96 swings spare at factor 1 and overran by 24 at factor 2 — the pick
    // wore out and the reach assertion below caught it, which is the whole
    // reason that assertion exists. 300 ticks is 144 swings of 216 at factor
    // 2. If the factor rises again, check this arithmetic before the hash.
    for s in &mut world.species {
        s.sheet = Sheet {
            density: 10,
            strength: 90,
            hardness: 30,
            heat_tolerance: 50,
            reactivity: 50,
            conductivity: 50,
        };
    }
    step(
        &mut world,
        &[Input::System(SystemCommand::AddPlayer {
            name: "ada".into(),
        })],
        &mut events,
    );
    let me = PlayerId(0);

    // Stand on a deposit, and make the species one a design can be built from
    // without the test having to mine and smelt its way there.
    let d = world.deposits[0].clone();
    world.player_mut(me).unwrap().pos = d.center;
    let refined = Item::new(ItemKind::Refined, d.species, Grade::B);
    let pick = (
        Part::of(PartKind::Frame(Mount::Held), refined),
        Part::of(PartKind::Head, refined),
    );
    let drill = (
        Part::of(PartKind::Frame(Mount::Planted), refined),
        Part::of(PartKind::Head, refined),
        Part::of(PartKind::Hopper, refined),
    );
    for item in [
        pick.0.as_item(),
        pick.1.as_item(),
        drill.0.as_item(),
        drill.1.as_item(),
        drill.2.as_item(),
    ] {
        world.player_mut(me).unwrap().inventory.add(item, 1);
    }

    let script = [
        PlayerCommand::Assemble {
            frame: pick.0.as_item(),
            mounted: vec![pick.1.as_item()],
        },
        PlayerCommand::Equip { assembly: 0 },
        PlayerCommand::Mine,
        PlayerCommand::Assemble {
            frame: drill.0.as_item(),
            mounted: vec![drill.1.as_item(), drill.2.as_item()],
        },
        PlayerCommand::PlaceAssembly {
            assembly: 0,
            pos: TilePos::new(d.center.x + 1, d.center.y),
        },
    ];
    for command in script {
        step(&mut world, &[Input::player(me, command)], &mut events);
    }
    for _ in 0..300 {
        step(&mut world, &[], &mut events);
    }

    // The scenario must still REACH the state it exists to hash. A green
    // golden assertion over a world where nothing was built would be the
    // first test all over again.
    let p = world.player(me).unwrap();
    assert!(p.tool.is_some(), "a tool must be in hand");
    assert!(p.mining.is_some(), "mid-swing");
    let worn = p.tool.as_ref().unwrap();
    assert!(
        worn.durability < worn.assembly.stats(&world.species).durability,
        "and it must have worn, or the pool is not in the hash in any useful way"
    );
    let held = world.buildings.iter().any(|b| match &b.kind {
        sim::BuildingKind::Machine(m) => m.held.is_some_and(|s| s.count > 0),
        _ => false,
    });
    assert!(held, "and the drill must have mined into its buffer");

    assert_eq!(
        format!("{:016x}", world.state_hash()),
        "9afde5135ca07119",
        "world hash changed; see the comment on this test"
    );
}
