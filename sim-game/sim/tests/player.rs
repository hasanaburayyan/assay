use sim::{
    Event, Input, PlayerCommand, PlayerId, RejectReason, SystemCommand, TilePos, World,
    WorldConfig, step,
};

fn world() -> World {
    World::new(WorldConfig {
        seed: 42,
        ..WorldConfig::default()
    })
}

fn join(name: &str) -> Input {
    Input::System(SystemCommand::AddPlayer { name: name.into() })
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
fn new_worlds_have_no_players() {
    assert!(world().players.is_empty());
}

#[test]
fn players_join_at_spawn_with_the_next_id() {
    let mut w = world();
    let events = run(&mut w, &[join("ada"), join("grace")], 1);
    assert_eq!(
        events,
        vec![
            Event::PlayerJoined {
                player: PlayerId(0),
                name: "ada".into()
            },
            Event::PlayerJoined {
                player: PlayerId(1),
                name: "grace".into()
            },
        ]
    );
    for p in &w.players {
        assert_eq!(p.pos, w.spawn_tile());
    }
    assert_eq!(w.player(PlayerId(1)).unwrap().name, "grace");
}

#[test]
fn player_walks_one_tile_per_tick_and_arrives() {
    let mut w = world();
    run(&mut w, &[join("ada")], 1);
    let me = PlayerId(0);
    let start = w.spawn_tile();
    let target = TilePos::new(start.x + 3, start.y - 5);

    let events = run(
        &mut w,
        &[Input::player(me, PlayerCommand::MoveTo { target })],
        1,
    );
    assert_eq!(
        events[0],
        Event::MoveStarted {
            player: me,
            from: start,
            to: target
        }
    );
    assert_eq!(
        w.player(me).unwrap().pos,
        TilePos::new(start.x + 1, start.y - 1)
    );

    // Diagonal steps count as one tile, so the trip takes max(3, 5) = 5 ticks.
    let events = run(&mut w, &[], 4);
    assert_eq!(w.player(me).unwrap().pos, target);
    assert_eq!(w.player(me).unwrap().target, None);
    assert_eq!(
        events,
        vec![Event::PlayerArrived {
            player: me,
            pos: target
        }]
    );
}

#[test]
fn players_only_move_themselves() {
    let mut w = world();
    run(&mut w, &[join("ada"), join("grace")], 1);
    let start = w.spawn_tile();
    let target = TilePos::new(start.x + 4, start.y);

    run(
        &mut w,
        &[Input::player(PlayerId(1), PlayerCommand::MoveTo { target })],
        4,
    );
    assert_eq!(w.player(PlayerId(0)).unwrap().pos, start);
    assert_eq!(w.player(PlayerId(1)).unwrap().pos, target);
}

#[test]
fn stop_halts_the_player() {
    let mut w = world();
    run(&mut w, &[join("ada")], 1);
    let me = PlayerId(0);
    let start = w.spawn_tile();
    let far = TilePos::new(start.x + 10, start.y);
    run(
        &mut w,
        &[Input::player(me, PlayerCommand::MoveTo { target: far })],
        3,
    );

    let events = run(&mut w, &[Input::player(me, PlayerCommand::Stop)], 5);
    let here = TilePos::new(start.x + 3, start.y);
    assert_eq!(
        events,
        vec![Event::PlayerStopped {
            player: me,
            pos: here
        }]
    );
    assert_eq!(w.player(me).unwrap().pos, here);
}

#[test]
fn moving_off_the_map_is_rejected() {
    let mut w = world();
    run(&mut w, &[join("ada")], 1);
    let me = PlayerId(0);
    let cmd = PlayerCommand::MoveTo {
        target: TilePos::new(-1, 0),
    };
    let events = run(&mut w, &[Input::player(me, cmd.clone())], 1);
    assert_eq!(
        events,
        vec![Event::CommandRejected {
            player: me,
            command: cmd,
            reason: RejectReason::OutOfBounds
        }]
    );
    assert_eq!(w.player(me).unwrap().pos, w.spawn_tile());
}

#[test]
fn version_1_saves_migrate_to_one_named_player() {
    // Build a v1-shaped save: no "players" field.
    let w = world();
    let mut json: serde_json::Value = serde_json::from_str(&w.to_json().unwrap()).unwrap();
    json["version"] = 1.into();
    json["world"].as_object_mut().unwrap().remove("players");

    let loaded = World::from_json(&json.to_string()).unwrap();
    assert_eq!(loaded.players.len(), 1);
    assert_eq!(loaded.players[0].pos, loaded.spawn_tile());
    assert_eq!(loaded.players[0].name, "player 0");
}

#[test]
fn version_2_saves_migrate_to_named_players() {
    let mut w = world();
    run(&mut w, &[join("ada")], 1);
    let mut json: serde_json::Value = serde_json::from_str(&w.to_json().unwrap()).unwrap();
    json["version"] = 2.into();
    json["world"]["players"][0]
        .as_object_mut()
        .unwrap()
        .remove("name");

    let loaded = World::from_json(&json.to_string()).unwrap();
    assert_eq!(loaded.players[0].name, "player 0");
}
