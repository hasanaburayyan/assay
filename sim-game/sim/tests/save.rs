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
