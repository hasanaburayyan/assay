//! **A BUILDING IS NAMED THE WAY EVERY OTHER OBJECT IS** (Game Director,
//! ASSA-136): species, kind, grade.
//!
//! A stack is a `Tonore ore (A)`, a part is a `Tonore frame (A)`, a deposit's
//! line names its species — and until this file a building standing on the
//! ground was `smelter 0` on every surface in the game. Its material is not
//! decoration: it is the species whose heat tolerance caps the fire
//! (`World::max_temperature`) and the exact `Item` that comes back in your pack
//! when you pick it up (`step::Pickup`). After ASSA-131 draws buildings it is
//! also the species the sprite's tint claims, and a tint whose key is written
//! down nowhere is a mark a player cannot read.
//!
//! The trap this file exists to hold shut is in `Building::material`: it is
//! whatever was PLACED, so a smelter carries a `Smelter` item and a machine
//! carries `assembly.frame.refined()`. Name a building with `World::item_name`
//! and a planted drill becomes `Tonore refined (A)`.

use sim::{
    Assembly, BuildingId, Grade, Input, Item, ItemKind, Mount, Part, PartKind, PlayerCommand,
    PlayerId, Sheet, SpeciesId, SystemCommand, TilePos, World, WorldConfig, step,
};

const WALLS: SpeciesId = SpeciesId(0);
const CHASSIS: SpeciesId = SpeciesId(4);

const PLANTED: PartKind = PartKind::Frame(Mount::Planted);

fn sheet() -> Sheet {
    Sheet {
        density: 50,
        strength: 50,
        hardness: 30,
        heat_tolerance: 60,
        reactivity: 1,
        conductivity: 50,
    }
}

/// Two species with names nothing else in the world shares, so an assertion
/// cannot pass by naming the wrong one.
fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    for s in &mut world.species {
        s.sheet = sheet();
        s.assayed = true;
    }
    world.species_mut(WALLS).generated_name = "Wallstone".into();
    world.species_mut(CHASSIS).generated_name = "Chassium".into();
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

fn run(world: &mut World, inputs: &[Input]) {
    step(world, inputs, &mut Vec::new());
}

/// Move every deposit off `pos`, the way `tests/halted.rs` does: the starter
/// ladder guarantees deposits in the chunks beside spawn, so a drill planted
/// near spawn is usually WORKING and never reaches the halted surface.
fn clear_deposits_from(world: &mut World, pos: TilePos) {
    let corner = TilePos::new(1, 1);
    assert!(!(pos.x < 8 && pos.y < 8), "the corner must be far from pos");
    for i in 0..world.deposits.len() {
        if world.deposits[i].contains(pos) {
            world.deposits[i].center = corner;
        }
    }
    assert!(
        world.deposit_at(pos).is_none(),
        "the tile must really be bare"
    );
}

fn place_smelter(world: &mut World, me: PlayerId, grade: Grade, pos: TilePos) -> BuildingId {
    let item = Item::new(ItemKind::Smelter, WALLS, grade);
    world.player_mut(me).unwrap().inventory.add(item, 1);
    world.player_mut(me).unwrap().pos = TilePos::new(pos.x - 1, pos.y);
    let before = world.buildings.len();
    run(
        world,
        &[Input::player(me, PlayerCommand::Place { item, pos })],
    );
    assert_eq!(
        world.buildings.len(),
        before + 1,
        "the fixture must actually place a smelter"
    );
    world.buildings.last().unwrap().id
}

fn plant_drill(world: &mut World, me: PlayerId, grade: Grade, pos: TilePos) -> BuildingId {
    let refined = Item::new(ItemKind::Refined, CHASSIS, grade);
    let assembly = Assembly::new(
        Part::of(PLANTED, refined),
        vec![
            Part::of(PartKind::Head, refined),
            Part::of(PartKind::Hopper, refined),
        ],
    );
    for item in assembly.part_items() {
        world.player_mut(me).unwrap().inventory.add(item, 1);
    }
    world.player_mut(me).unwrap().pos = TilePos::new(pos.x - 1, pos.y);
    run(
        world,
        &[Input::player(
            me,
            PlayerCommand::Assemble {
                frame: assembly.frame.as_item(),
                mounted: assembly.mounted.iter().map(Part::as_item).collect(),
            },
        )],
    );
    let index = (world.player(me).unwrap().assemblies.len() - 1) as u32;
    let before = world.buildings.len();
    run(
        world,
        &[Input::player(
            me,
            PlayerCommand::PlaceAssembly {
                assembly: index,
                pos,
            },
        )],
    );
    assert_eq!(
        world.buildings.len(),
        before + 1,
        "the fixture must actually plant a drill"
    );
    world.buildings.last().unwrap().id
}

#[test]
fn a_standing_smelter_is_named_by_the_species_and_grade_it_was_built_from() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let id = place_smelter(&mut world, me, Grade::C, TilePos::new(spawn.x + 1, spawn.y));
    let b = world.building(id).unwrap();
    assert_eq!(
        sim::debug::building_name(&world, b),
        "Wallstone smelter (C)"
    );
}

/// **THE SURFACE THAT ALREADY NAMED BUILDINGS, AND NAMED THEM WRONG.**
/// `building_table` — sim-cli's `buildings` — has always printed
/// `world.item_name(b.material)`, which reads correctly for a smelter by
/// accident and calls a planted drill `Tonore refined (A)`. I filed ASSA-136
/// saying no surface named a building at all; one did, in the one construction
/// that cannot survive a machine.
#[test]
fn the_buildings_table_names_a_machine_as_a_machine() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 2, spawn.y + 2);
    clear_deposits_from(&mut world, pos);
    plant_drill(&mut world, me, Grade::B, pos);
    let table = sim::debug::building_table(&world);
    assert!(
        table.contains("Chassium machine (B)"),
        "the table names what is standing there: {table}"
    );
    assert!(
        !table.contains("refined"),
        "never the material it was built from: {table}"
    );
}

/// **THE GRADE IS THE ONE YOU GET BACK, NOT A CLAIM ABOUT THE FIRE.**
/// `Property::scales_with_grade` excludes heat tolerance, so an A smelter caps
/// the fire exactly where a C one does — the name changes and `walls` does not.
fn walls_of(world: &World, id: BuildingId) -> u32 {
    world.max_temperature(world.building(id).unwrap())
}

#[test]
fn grade_is_in_the_name_and_not_in_the_walls() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let c = place_smelter(&mut world, me, Grade::C, TilePos::new(spawn.x + 1, spawn.y));
    let a = place_smelter(&mut world, me, Grade::A, TilePos::new(spawn.x + 4, spawn.y));
    assert_eq!(
        sim::debug::building_name(&world, world.building(c).unwrap()),
        "Wallstone smelter (C)"
    );
    assert_eq!(
        sim::debug::building_name(&world, world.building(a).unwrap()),
        "Wallstone smelter (A)"
    );
    assert_eq!(
        walls_of(&world, c),
        walls_of(&world, a),
        "a grade in the name must not become a claim about the fire"
    );
}

/// The trap. A machine's `material` is `assembly.frame.refined()`, so the noun
/// has to come from `BuildingKind`, never from the item.
#[test]
fn a_planted_machine_is_a_machine_and_never_refined() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let id = plant_drill(
        &mut world,
        me,
        Grade::B,
        TilePos::new(spawn.x + 2, spawn.y + 2),
    );
    let b = world.building(id).unwrap();
    let name = sim::debug::building_name(&world, b);
    assert_eq!(name, "Chassium machine (B)");
    assert!(
        !name.contains("refined"),
        "the noun comes from the building, not from the item it was placed \
         from: {name}"
    );
    assert_eq!(
        world.item_name(b.material),
        "Chassium refined (B)",
        "and this is the shape that would have been wrong"
    );
}

/// A building standing on the ground names the species the player chose. Two
/// species in one world, each building wearing its own.
#[test]
fn two_buildings_of_different_species_do_not_share_a_name() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let smelter = place_smelter(&mut world, me, Grade::C, TilePos::new(spawn.x + 1, spawn.y));
    let drill = plant_drill(
        &mut world,
        me,
        Grade::B,
        TilePos::new(spawn.x + 2, spawn.y + 3),
    );
    assert_eq!(
        sim::debug::building_name(&world, world.building(smelter).unwrap()),
        "Wallstone smelter (C)"
    );
    assert_eq!(
        sim::debug::building_name(&world, world.building(drill).unwrap()),
        "Chassium machine (B)"
    );
}

/// A renamed species keeps the mark already drawn: the name is read now, not
/// snapshotted when the thing was placed.
#[test]
fn renaming_the_species_renames_what_is_already_standing() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let id = place_smelter(&mut world, me, Grade::C, TilePos::new(spawn.x + 1, spawn.y));
    world.species_mut(WALLS).player_name = Some("Hearthrock".into());
    assert_eq!(
        sim::debug::building_name(&world, world.building(id).unwrap()),
        "Hearthrock smelter (C)"
    );
}

/// **ONE PLACE DECIDES HOW A BUILDING IS ADDRESSED.** `halt_lines` is the
/// surface a player reads when something has stopped; it must carry the same
/// name, and still carry the walk-to-it coordinates.
#[test]
fn the_halted_surface_names_the_building_and_still_says_where_it_is() {
    let (mut world, me) = world_with_player();
    let spawn = world.spawn_tile();
    let pos = TilePos::new(spawn.x + 2, spawn.y + 2);
    clear_deposits_from(&mut world, pos);
    let id = plant_drill(&mut world, me, Grade::B, pos);
    step(&mut world, &[], &mut Vec::new());
    let lines = sim::debug::halt_lines(&world);
    assert_eq!(
        lines.len(),
        1,
        "a drill on no deposit is idle and must be listed: {lines:?}"
    );
    assert!(
        lines[0].starts_with(&format!("Chassium machine (B) {}", id.0)),
        "the halted line is addressed by the sim's own name: {}",
        lines[0]
    );
    assert!(
        lines[0].contains(&format!("at ({}, {})", pos.x, pos.y)),
        "a player still has to be able to walk to it: {}",
        lines[0]
    );
    assert_eq!(
        lines[0],
        format!(
            "{} · {}",
            sim::debug::building_address(&world, world.building(id).unwrap()),
            sim::debug::building_state_line(&world, world.building(id).unwrap())
        ),
        "address and state are each written in exactly one place"
    );
}
