use sim::{
    DepositId, Input, Item, PlayerCommand, PlayerId, SAVE_VERSION, SaveError, SystemCommand, World,
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
    assert!(json.contains("\"kind\": \"Iron\""));
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

#[test]
fn version_4_saves_migrate_ore_counters_to_stacks() {
    let mut w = world(42);
    let mut json: serde_json::Value = serde_json::from_str(&w.to_json().unwrap()).unwrap();
    json["version"] = 4.into();
    json["world"]["players"][0]["inventory"] =
        serde_json::json!({ "iron": 12, "copper": 0, "coal": 3, "stone": 0 });

    let loaded = World::from_json(&json.to_string()).unwrap();
    let inv = &loaded.players[0].inventory;
    assert_eq!(inv.count(Item::IronOre), 12);
    assert_eq!(inv.count(Item::Coal), 3);
    assert_eq!(inv.stacks().len(), 2);

    // The migrated world must save and reload as today's format.
    w.players[0].inventory.add(Item::IronOre, 12);
    w.players[0].inventory.add(Item::Coal, 3);
    assert_eq!(loaded, w);
}
