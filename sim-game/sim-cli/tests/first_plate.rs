//! The reference play-through: a fresh world to the first gear, driven
//! through the plain prompt exactly as a script or a tester would, against
//! whatever minerals the seed rolled. If this breaks, the loop is not
//! playable headless.

use std::io::Write;
use std::process::{Command, Stdio};

use sim::ladder::starter_species;
use sim::tuning::GEAR_MIN_HARDNESS;
use sim::worldgen::STARTER_CHUNKS;
use sim::{ChunkPos, OreDeposit, Property, TilePos, World, WorldConfig};

/// Chebyshev distance: ticks it takes to walk between two tiles.
fn walk(from: TilePos, to: TilePos) -> i32 {
    (to.x - from.x).abs().max((to.y - from.y).abs())
}

/// The starter deposits of this seed's world, as the CLI will build it.
fn starters(seed: u64) -> (World, OreDeposit, OreDeposit) {
    let world = World::new(WorldConfig {
        seed,
        width_chunks: 6,
        height_chunks: 4,
    });
    let at = |i: usize| {
        let (dx, dy) = STARTER_CHUNKS[i];
        let chunk = ChunkPos::new(world.spawn.x + dx, world.spawn.y + dy);
        world
            .deposits
            .iter()
            .find(|d| d.center.chunk() == chunk)
            .cloned()
            .expect("starter deposit")
    };
    let (material, fuel) = (at(0), at(1));
    (world, material, fuel)
}

#[test]
fn fresh_world_to_first_gear_through_the_plain_prompt() {
    // Any seed starts climbable, but gears also need the starter material to
    // be hard enough at its rolled grade, and the fuel to burn hot enough
    // for it. Pick the first seed where that holds; most do.
    let (seed, world, material, fuel) = (1..200)
        .map(|seed| {
            let (w, m, f) = starters(seed);
            (seed, w, m, f)
        })
        .find(|(_, w, m, f)| {
            let (ms, fs) = (w.species(m.species), w.species(f.species));
            ms.effective(Property::Hardness, m.grade()) >= GEAR_MIN_HARDNESS
                && fs.effective(Property::Reactivity, f.grade())
                    >= u32::from(ms.sheet.heat_tolerance)
                && m.species != f.species
        })
        .expect("some seed supports the full loop");
    let (ms, fs) = (world.species(material.species), world.species(fuel.species));
    assert_eq!(
        starter_species(&world.species),
        Some((material.species, fuel.species))
    );
    let spawn = world.spawn_tile();
    let mat_ore = format!(
        "ore:{}:{}",
        ms.name().to_ascii_lowercase(),
        material.grade().letter().to_ascii_lowercase()
    );
    let fuel_ore = format!(
        "ore:{}:{}",
        fs.name().to_ascii_lowercase(),
        fuel.grade().letter().to_ascii_lowercase()
    );
    let refined = mat_ore.replacen("ore:", "refined:", 1);

    let script = format!(
        "new {seed}
pause
species
goto {} {}
tick {}
assay
tick 30
mine
tick 40
craft smelter {mat_ore}
goto {} {}
tick {}
mine
tick 20
place smelter
insert 0 fuel {fuel_ore} 5
insert 0 ore {mat_ore} 10
tick 200
take 0
tick 1
craft gear {refined} 2
tick 10
buildings
inv
quit
",
        material.center.x,
        material.center.y,
        walk(spawn, material.center),
        fuel.center.x,
        fuel.center.y,
        walk(material.center, fuel.center).max(20), // craft finishes on the way
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
    let transcript = format!("--- script\n{script}\n--- stdout\n{stdout}\n--- stderr\n{stderr}");

    assert!(out.status.success(), "{transcript}");
    assert!(!stdout.contains("rejected"), "{transcript}");
    let (m, g) = (ms.name(), material.grade().letter());
    for expected in [
        format!("you started assaying {m}"),
        format!("you assayed {m}: density {}", ms.sheet.density),
        format!("you discovered {m}!"),
        format!("you started mining {m}"),
        format!("you crafted 1 {m} smelter ({g})"),
        format!("you placed {m} smelter ({g}) as building 0"),
        format!("building 0 smelted 1 {m} refined ({g})"),
        format!("you took 10 {m} refined ({g}) from building 0"),
        format!("you crafted 1 {m} gear ({g})"),
    ] {
        assert!(
            stdout.contains(&expected),
            "missing {expected:?}\n{transcript}"
        );
    }
    let carrying = stdout
        .lines()
        .rfind(|l| l.starts_with("Carrying "))
        .unwrap_or_else(|| panic!("no inventory line\n{transcript}"));
    assert!(
        carrying.contains(&format!("6 {m} refined ({g})")),
        "{carrying}\n{transcript}"
    );
    assert!(
        carrying.contains(&format!("2 {m} gear ({g})")),
        "{carrying}\n{transcript}"
    );
    assert!(
        stdout.contains("   0  smelter"),
        "buildings table should list the smelter\n{transcript}"
    );
    assert!(
        stdout.contains("conductivity") || stdout.contains("cond"),
        "{transcript}"
    );
}
