use sim::{
    DepositId, Input, PlayerCommand, PlayerId, SAVE_VERSION, SaveError, SystemCommand, World,
    WorldConfig, step,
};

/// A world with one player already joined.
fn world(seed: u64) -> World {
    let mut w = World::new(WorldConfig {
        seed,
        ..WorldConfig::default()
    });
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut w, &[join], &mut Vec::new());
    w
}

/// A world with one player standing on deposit `deposit`, ready to mine.
fn world_on_deposit(seed: u64, deposit: u32) -> World {
    let mut w = world(seed);
    for s in &mut w.species {
        s.sheet.hardness = s
            .sheet
            .hardness
            .min(sim::tuning::HAND_MINE_MAX_HARDNESS as u8);
    }
    let center = w.deposit(DepositId(deposit)).unwrap().center;
    w.player_mut(PlayerId(0)).unwrap().pos = center;
    w
}

fn mine() -> Input {
    Input::player(PlayerId(0), PlayerCommand::Mine)
}

#[test]
fn json_round_trip_is_exact() {
    let original = world(42);
    let loaded = World::from_json(&original.to_json().unwrap()).unwrap();
    assert_eq!(loaded, original);
    assert_eq!(loaded.state_hash(), original.state_hash());
}

#[test]
fn round_trip_keeps_changes_made_by_ticks() {
    let mut w = world_on_deposit(42, 0);
    let mut events = Vec::new();
    for _ in 0..10 {
        step(&mut w, &[mine()], &mut events);
    }
    assert!(w.players[0].inventory.total() > 0);
    let loaded = World::from_json(&w.to_json().unwrap()).unwrap();
    assert_eq!(loaded.tick, 11);
    assert_eq!(loaded, w);
}

/// Loading a save and continuing must give the same result as never stopping.
#[test]
fn a_loaded_world_continues_identically() {
    let cmd = [mine()];
    let mut events = Vec::new();

    let mut straight = world_on_deposit(7, 1);
    for _ in 0..50 {
        step(&mut straight, &cmd, &mut events);
    }

    let mut resumed = world_on_deposit(7, 1);
    for _ in 0..20 {
        step(&mut resumed, &cmd, &mut events);
    }
    let mut resumed = World::from_json(&resumed.to_json().unwrap()).unwrap();
    for _ in 20..50 {
        step(&mut resumed, &cmd, &mut events);
    }

    assert_eq!(resumed.state_hash(), straight.state_hash());
}

#[test]
fn save_is_readable_json() {
    let json = world(42).to_json().unwrap();
    assert!(json.contains(&format!("\"version\": {SAVE_VERSION}")));
    assert!(json.contains("\"seed\": 42"));
    assert!(json.contains("\"generated_name\""));
    assert!(json.contains("\"heat_tolerance\""));
}

#[test]
fn unknown_version_is_rejected() {
    let json = world(1).to_json().unwrap().replacen(
        &format!("\"version\": {SAVE_VERSION}"),
        "\"version\": 999",
        1,
    );
    assert!(matches!(
        World::from_json(&json),
        Err(SaveError::UnsupportedVersion { found: 999 })
    ));
}

#[test]
fn save_and_load_from_disk() {
    let dir = std::env::temp_dir().join(format!("r2ts-sim-test-{}", std::process::id()));
    let path = dir.join("nested/world.json");
    let original = world(5);

    original.save_json(&path).unwrap();
    let loaded = World::load_json(&path).unwrap();
    std::fs::remove_dir_all(&dir).unwrap();

    assert_eq!(loaded, original);
}

/// Decision 12: the named-ore saves are gone for good, not migrated.
#[test]
fn named_ore_era_saves_are_refused() {
    let json = world(1).to_json().unwrap().replacen(
        &format!("\"version\": {SAVE_VERSION}"),
        "\"version\": 8",
        1,
    );
    assert!(matches!(
        World::from_json(&json),
        Err(SaveError::UnsupportedVersion { found: 8 })
    ));
}

/// A v10 save has no `assemblies` and no `tool` on its players, because
/// nothing could be built then. It must still load, and load as the world it
/// described: the founders' ongoing test world is a v10 file.
#[test]
fn a_v10_save_without_assemblies_still_loads() {
    let original = world(5);
    let v10 = original
        .to_json()
        .unwrap()
        .replacen(
            &format!("\"version\": {SAVE_VERSION}"),
            "\"version\": 10",
            1,
        )
        // Strip the fields v11 added; a v10 writer never emitted them. Taken
        // out with their punctuation, so the fixture is valid JSON and the
        // test is really exercising serde's defaults.
        .replace("\"assemblies\": [],\n        ", "")
        .replace(",\n        \"tool\": null", "");
    assert!(
        !v10.contains("assemblies") && !v10.contains("\"tool\""),
        "the fixture must really be missing the v11 fields"
    );

    let loaded = World::from_json(&v10).expect("a v10 save must still load");
    let player = loaded.player(PlayerId(0)).expect("its player survived");
    assert!(player.assemblies.is_empty(), "nothing was built in v10");
    assert!(player.tool.is_none(), "nothing was in hand in v10");
    assert_eq!(loaded, original, "the rest of the world is unchanged");
}

/// What v11 writes, it reads back: a worn tool in hand, a design on the built
/// list, and a planted machine all survive a round trip.
#[test]
fn assemblies_and_machines_survive_a_round_trip() {
    use sim::assembly::Built;
    use sim::{
        Building, BuildingId, BuildingKind, Grade, Item, ItemKind, Machine, Mount, Part, PartKind,
        SpeciesId,
    };

    let mut original = world(6);
    let material = Item::new(ItemKind::Refined, SpeciesId(0), Grade::B);
    let pick = sim::Assembly::new(
        Part::of(PartKind::Frame(Mount::Held), material),
        vec![Part::of(PartKind::Head, material)],
    );
    let drill = sim::Assembly::new(
        Part::of(PartKind::Frame(Mount::Planted), material),
        vec![Part::of(PartKind::Head, material)],
    );
    let spawn = original.spawn_tile();
    let p = original.player_mut(PlayerId(0)).unwrap();
    p.tool = Some(Built {
        assembly: pick.clone(),
        durability: 42,
    });
    p.assemblies.push(Built {
        assembly: drill.clone(),
        durability: 0,
    });
    original.buildings.push(Building {
        id: BuildingId(0),
        pos: spawn,
        material,
        kind: BuildingKind::Machine(Machine::new(drill.clone())),
    });

    let loaded = World::from_json(&original.to_json().unwrap()).unwrap();

    let player = loaded.player(PlayerId(0)).unwrap();
    assert_eq!(player.tool.as_ref().unwrap().assembly, pick);
    assert_eq!(
        player.tool.as_ref().unwrap().durability,
        42,
        "wear is saved, not recomputed"
    );
    assert_eq!(player.assemblies[0].assembly, drill);
    assert_eq!(
        loaded.buildings[0].kind.machine().unwrap().assembly,
        drill,
        "a planted machine survives"
    );
    assert_eq!(loaded, original);
    assert_eq!(loaded.state_hash(), original.state_hash());
}

/// **A MIGRATION THAT NO LAYOUT CHANGE WOULD HAVE ASKED FOR.**
/// `Mining::progress` counted ticks in v11 and accumulates work in v12 — same
/// field, same type, different unit. A v11 save therefore loads without a
/// single serde complaint and quietly tells a player mid-swing that they have
/// barely started. Nothing but this test notices.
///
/// Builds the fixture by ticking a real world into a mid-mine state and then
/// writing the progress back down to the tick count a v11 writer would have
/// emitted, so the numbers are the ones the old rule actually produced.
#[test]
fn a_v11_save_rescales_mining_progress_from_ticks_to_work() {
    use sim::tuning::{HAND_WORK_PER_TICK, WORK_PER_UNIT};

    let mut w = world_on_deposit(7, 0);
    let me = PlayerId(0);
    step(
        &mut w,
        &[Input::player(me, PlayerCommand::Mine)],
        &mut Vec::new(),
    );
    step(&mut w, &[], &mut Vec::new());
    let work = w.player(me).unwrap().mining.expect("mid-mine").progress;
    assert_eq!(
        work,
        2 * HAND_WORK_PER_TICK,
        "two ticks of hand work, so the fixture is really mid-swing"
    );
    assert!(work < WORK_PER_UNIT, "and has not yet yielded");

    // What a v11 writer would have put on disk for this same moment: 2.
    let v11 = w
        .to_json()
        .unwrap()
        .replacen(
            &format!("\"version\": {SAVE_VERSION}"),
            "\"version\": 11",
            1,
        )
        .replace(
            &format!("\"progress\": {work}"),
            &format!("\"progress\": {}", work / HAND_WORK_PER_TICK),
        );
    assert!(
        v11.contains("\"progress\": 2"),
        "the fixture must carry the v11 tick count, not the v12 work count"
    );

    let loaded = World::from_json(&v11).expect("a v11 save must still load");
    assert_eq!(
        loaded.player(me).unwrap().mining.unwrap().progress,
        work,
        "the migration must put the player back where they were, not where \
         the number happened to read"
    );

    // And it is version-gated: a current save is not rescaled a second time.
    let current = World::from_json(&w.to_json().unwrap()).expect("v12 loads");
    assert_eq!(
        current.player(me).unwrap().mining.unwrap().progress,
        work,
        "a v12 save must pass through the migration untouched"
    );
}
