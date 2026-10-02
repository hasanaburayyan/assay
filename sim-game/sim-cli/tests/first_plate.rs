//! The reference play-through: a fresh world through the WHOLE demo loop,
//! driven through the plain prompt exactly as a script or a tester would,
//! against whatever minerals the seed rolled. If this breaks, the loop is not
//! playable headless.
//!
//! **WHERE IT ENDS** (Game Director's ruling 9 on ASSA-8, which named the one
//! thing "a full demo loop" had never been defined to mean): hand-mine ore,
//! assay, refine, assemble a pick, mine with it, assemble a drill, place it
//! inside the frame's budget, it produces into its hopper, and the player
//! takes that ore back out. The first gear is kept as a waypoint on the way.
//!
//! There is no victory state anywhere in this, deliberately. "Completion" is
//! a test condition; the world keeps running.

use std::io::Write;
use std::process::{Command, Stdio};

use sim::ladder::starter_species;
use sim::tuning::{
    FRAME_BUDGET_PER_STRENGTH, GEAR_MIN_HARDNESS, HEAD_SIZE, HOPPER_SIZE, PLANTED_FRAME_SIZE,
};
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
fn fresh_world_through_the_whole_demo_loop_on_the_plain_prompt() {
    // Any seed starts climbable, but gears also need the starter material to
    // be hard enough at its rolled grade, and the fuel to burn hot enough
    // for it. Pick the first seed where that holds; most do.
    //
    // ASSA-6 adds one more condition, and it is a REAL one rather than a
    // convenience: the loop now ends in a planted drill, and decision 11 says
    // placement is the test, so the seed's material must make a drill that
    // fits its own frame's budget. Same species throughout, that is
    // `8 x density <= 15 x effective strength` (sizes 5 + 1 + 2 against
    // `PLANTED_FRAME_SIZE x FRAME_BUDGET_PER_STRENGTH`). On a seed where it
    // fails, the honest outcome is a drill that breaks when planted — which
    // is a correct sim and a useless play-through.
    let (seed, world, material, fuel) = (1..400)
        .map(|seed| {
            let (w, m, f) = starters(seed);
            (seed, w, m, f)
        })
        .find(|(_, w, m, f)| {
            let (ms, fs) = (w.species(m.species), w.species(f.species));
            let drill_mass =
                (PLANTED_FRAME_SIZE + HEAD_SIZE + HOPPER_SIZE) * u32::from(ms.sheet.density);
            let frame_budget = PLANTED_FRAME_SIZE
                * FRAME_BUDGET_PER_STRENGTH
                * ms.effective(Property::Strength, m.grade());
            ms.effective(Property::Hardness, m.grade()) >= GEAR_MIN_HARDNESS
                && fs.effective(Property::Reactivity, f.grade())
                    >= u32::from(ms.sheet.heat_tolerance)
                && m.species != f.species
                && drill_mass <= frame_budget
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
    // Part specs the CLI resolves against the inventory: `<part>:<species>:<grade>`.
    let sp = format!(
        "{}:{}",
        ms.name().to_ascii_lowercase(),
        material.grade().letter().to_ascii_lowercase()
    );

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
goto {} {}
tick {}
mine
tick 120
goto {} {}
tick {}
insert 0 fuel {fuel_ore} 40
insert 0 ore {mat_ore} 14
tick 400
take 0
tick 1
make handle {refined}
make head {refined}
tick 60
assemble handle:{sp} head:{sp}
tick 1
built
equip 0
goto {} {}
tick {}
mine
tick 60
built
make frame {refined}
make head {refined}
make hopper {refined}
tick 200
assemble frame:{sp} head:{sp} hopper:{sp}
tick 1
built
plant 0 {} {}
tick 200
buildings
take 1
tick 1
inv
quit
",
        material.center.x,
        material.center.y,
        walk(spawn, material.center),
        fuel.center.x,
        fuel.center.y,
        walk(material.center, fuel.center).max(20), // craft finishes on the way
        // Back for the ore the pick and the drill are made of: 3 refined for
        // a pick, 8 for a drill, and smelting is one unit at a time.
        material.center.x,
        material.center.y,
        walk(fuel.center, material.center),
        fuel.center.x,
        fuel.center.y,
        walk(material.center, fuel.center),
        // Mine again, this time with the pick in hand.
        material.center.x,
        material.center.y,
        walk(fuel.center, material.center),
        // The drill goes on the deposit tile it works: a machine is 1x1 and
        // mines what is underneath it.
        material.center.x,
        material.center.y,
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
    // Two waypoints, two inventory lines. The gear is kept exactly as it was
    // (Game Director's ruling 9: "keep the gear waypoint the test already
    // proves; do not delete it"), and the drill cycle closing is the new end.
    let inventories: Vec<&str> = stdout
        .lines()
        .filter(|l| l.starts_with("Carrying "))
        .collect();
    assert_eq!(
        inventories.len(),
        2,
        "one inventory at the gear, one at the end\n{transcript}"
    );
    let (at_gear, at_end) = (inventories[0], inventories[1]);
    assert!(
        at_gear.contains(&format!("6 {m} refined ({g})")),
        "{at_gear}\n{transcript}"
    );
    assert!(
        at_gear.contains(&format!("2 {m} gear ({g})")),
        "{at_gear}\n{transcript}"
    );
    assert!(
        stdout.contains("   0  smelter"),
        "buildings table should list the smelter\n{transcript}"
    );
    assert!(
        stdout.contains("conductivity") || stdout.contains("cond"),
        "{transcript}"
    );

    // ---------------------------------------------------------------------
    // THE REST OF THE DEMO LOOP, clause by clause from ruling 9. Each of
    // these is a decision in the note, and the point of asserting them from
    // the TRANSCRIPT rather than from the world is that a player typing the
    // same words gets the same game.
    // ---------------------------------------------------------------------
    for expected in [
        // Parts, from refined material, with no new recipe system.
        format!("you made 1 x {m} handle ({g})"),
        format!("you made 1 x {m} head ({g})"),
        format!("you made 1 x {m} frame ({g})"),
        format!("you made 1 x {m} hopper ({g})"),
        // A pick: the held frame plus a head, assembled and taken in hand.
        //
        // Matches the part NAMES and their order, not the whole summary
        // string: what each part is made of and what it weighs belong to the
        // readout, which is the Systems engineer's to format, and this test
        // should not break when they add a column. What it is really
        // asserting is decision 6 — one command path, parts in part order.
        format!("handle({m} {g}"),
        format!("+ head({m} {g}"),
        "you equipped a tool".to_string(),
        // A drill: a planted frame plus a head plus a hopper, from the SAME
        // command.
        format!("frame({m} {g}"),
        format!("+ hopper({m} {g}"),
        "you planted machine 1".to_string(),
        // It produces into its buffer, and the ore comes back out.
        format!("machine 1 mined 2 {m} ore ({g})"),
        "from building 1".to_string(),
    ] {
        assert!(
            stdout.contains(&expected),
            "missing {expected:?}\n{transcript}"
        );
    }

    // The pick WORE while it was in hand: the readout's SWINGS USED is higher
    // the second time it is printed. This is the only part of decision 12 the
    // play-through can show without running 120 swings, and asserting the
    // direction rather than a value keeps it true across a retune.
    //
    // A10's readout counts up now rather than down (swings used, not a pool),
    // so this reads `last > first`. A test that had kept the old direction
    // would have gone on passing on an empty list.
    let used: Vec<u32> = stdout
        .lines()
        .filter_map(|l| l.split("durability ").nth(1))
        .filter_map(|rest| rest.split(' ').next()?.parse().ok())
        .collect();
    assert!(
        used.len() >= 2,
        "the readout should be printed at least twice: {used:?}\n{transcript}"
    );
    assert!(
        used.last() > used.first(),
        "the pick's swings used must rise as it is used, got {used:?}\n{transcript}"
    );

    // And the drill is still standing at the end, which is decision 12's
    // other half: placed machines do not wear out.
    assert!(
        stdout.contains("   1  machine"),
        "the buildings table should list the planted drill\n{transcript}"
    );
    assert!(
        !stdout.contains("wore out"),
        "nothing in this script runs a pool to zero; if it does, the \
         assertions above are measuring the wrong thing\n{transcript}"
    );
    assert!(
        at_end.contains(&format!("{m} ore ({g})")),
        "the loop closes with the drill's ore in the player's hands: \
         {at_end}\n{transcript}"
    );
}
