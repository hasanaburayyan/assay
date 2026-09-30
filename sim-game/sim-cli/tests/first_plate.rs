//! The reference play-through: a fresh world to the first iron gear, driven
//! through the plain prompt exactly as a script or a tester would. If this
//! breaks, the loop is not playable headless.

use std::io::Write;
use std::process::{Command, Stdio};

use sim::{OreKind, TilePos, World, WorldConfig};

/// Chebyshev distance: ticks it takes to walk between two tiles.
fn walk(from: TilePos, to: TilePos) -> i32 {
    (to.x - from.x).abs().max((to.y - from.y).abs())
}

#[test]
fn fresh_world_to_first_gear_through_the_plain_prompt() {
    let seed = 9;
    // Same world the CLI builds for `new 9`, so we can find deposits.
    let world = World::new(WorldConfig {
        seed,
        width_chunks: 6,
        height_chunks: 4,
    });
    let find = |kind: OreKind| {
        world
            .deposits
            .iter()
            .find(|d| d.kind == kind)
            .unwrap_or_else(|| panic!("seed {seed} has no {kind:?} deposit"))
    };
    let (stone, iron, coal) = (
        find(OreKind::Stone),
        find(OreKind::Iron),
        find(OreKind::Coal),
    );
    let spawn = world.spawn_tile();

    let script = format!(
        "new {seed}
pause
goto {} {}
tick {}
mine
tick 20
craft smelter
goto {} {}
tick {}
mine
tick 40
goto {} {}
tick {}
mine
tick 20
place smelter
insert 0 iron-ore 10
insert 0 coal 5
tick 200
take 0
craft gear 2
tick 10
buildings
inv
quit
",
        stone.center.x,
        stone.center.y,
        walk(spawn, stone.center),
        iron.center.x,
        iron.center.y,
        walk(stone.center, iron.center).max(20), // craft finishes on the way
        coal.center.x,
        coal.center.y,
        walk(iron.center, coal.center),
    );

    let saves = std::env::temp_dir().join(format!("assay-first-plate-{}", std::process::id()));
    let mut child = Command::new(env!("CARGO_BIN_EXE_sim-cli"))
        .arg("--plain")
        .arg("--name")
        .arg("ada")
        .env("R2TS_SAVES_DIR", &saves)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("sim-cli starts");
    child
        .stdin
        .take()
        .unwrap()
        .write_all(script.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let _ = std::fs::remove_dir_all(&saves);
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let transcript = format!("--- stdout\n{stdout}\n--- stderr\n{stderr}");

    assert!(out.status.success(), "{transcript}");
    assert!(!stdout.contains("rejected"), "{transcript}");
    for expected in [
        "you started mining Stone",
        "you crafted 1 smelter",
        "you placed smelter 0",
        "building 0 smelted 1 iron-plate",
        "you took 10 iron-plate from building 0",
        "you crafted 1 iron-gear",
    ] {
        assert!(
            stdout.contains(expected),
            "missing {expected:?}\n{transcript}"
        );
    }
    let carrying = stdout
        .lines()
        .rfind(|l| l.starts_with("Carrying "))
        .unwrap_or_else(|| panic!("no inventory line\n{transcript}"));
    assert!(
        carrying.contains("6 iron-plate"),
        "{carrying}\n{transcript}"
    );
    assert!(carrying.contains("2 iron-gear"), "{carrying}\n{transcript}");
    assert!(
        stdout.contains("   0  smelter"),
        "buildings table should list the smelter\n{transcript}"
    );
}
