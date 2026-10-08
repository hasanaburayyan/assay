//! The reference play-through for ASSA-5: a fresh world to a pick in hand and
//! a drill on the ground, driven through the plain prompt exactly as a tester
//! would. `first_plate.rs` gets to the first refined material; this carries on
//! from there into parts and machines.
//!
//! If this breaks, the assembly loop is not playable headless, which the repo's
//! second principle says means it is not done.

use std::io::Write;
use std::process::{Command, Stdio};

use sim::tuning::{FRAME_BUDGET_PER_STRENGTH, HEAD_SIZE, HELD_FRAME_SIZE, PLANTED_FRAME_SIZE};
use sim::worldgen::STARTER_CHUNKS;
use sim::{ChunkPos, OreDeposit, Property, TilePos, World};

fn walk(from: TilePos, to: TilePos) -> i32 {
    (to.x - from.x).abs().max((to.y - from.y).abs())
}

/// The starter deposits of this seed's world, as the CLI will build it.
fn starters(seed: u64) -> (World, OreDeposit, OreDeposit) {
    // `sim_net::fresh_world` and not a `WorldConfig` written out here: the
    // same seed at `WorldConfig::default()`'s 8x8 is a DIFFERENT world, and
    // the doc comment above only stays true while one place decides the shape
    // (ASSA-53).
    let world = sim_net::fresh_world(seed);
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
fn fresh_world_to_a_pick_in_hand_and_a_drill_on_the_ground() {
    // Both designs must fit their frame's budget at the grade this seed rolls,
    // or the play-through would be testing the break instead of the build.
    // A pick is `HELD_FRAME_SIZE` + `HEAD_SIZE` of mass against
    // `HELD_FRAME_SIZE * strength * FRAME_BUDGET_PER_STRENGTH`.
    let fits = |w: &World, d: &OreDeposit| {
        let s = w.species(d.species);
        let density = u32::from(s.sheet.density);
        let strength = s.effective(Property::Strength, d.grade());
        let pick_mass = (HELD_FRAME_SIZE + HEAD_SIZE) * density;
        let drill_mass = (PLANTED_FRAME_SIZE + HEAD_SIZE) * density;
        pick_mass <= HELD_FRAME_SIZE * strength * FRAME_BUDGET_PER_STRENGTH
            && drill_mass <= PLANTED_FRAME_SIZE * strength * FRAME_BUDGET_PER_STRENGTH
    };
    let (seed, world, material, fuel) = (1..400)
        .map(|seed| {
            let (w, m, f) = starters(seed);
            (seed, w, m, f)
        })
        .find(|(_, w, m, f)| {
            let (ms, fs) = (w.species(m.species), w.species(f.species));
            // The fuel has to melt the material, and both designs must hold.
            fs.effective(Property::Reactivity, f.grade()) >= u32::from(ms.sheet.heat_tolerance)
                && m.species != f.species
                && m.amount >= 30
                && f.amount >= 10
                && fits(w, m)
        })
        .expect("some seed supports a pick and a drill from its starter material");

    let (ms, fs) = (world.species(material.species), world.species(fuel.species));
    let spawn = world.spawn_tile();
    let grade = material.grade().letter().to_ascii_lowercase();
    let name = ms.name().to_ascii_lowercase();
    let mat_ore = format!("ore:{name}:{grade}");
    let fuel_ore = format!(
        "ore:{}:{}",
        fs.name().to_ascii_lowercase(),
        fuel.grade().letter().to_ascii_lowercase()
    );
    let refined = format!("refined:{name}:{grade}");
    // A pick is a handle and a head; a drill is a frame and a head.
    let handle = format!("handle:{name}:{grade}");
    let head = format!("head:{name}:{grade}");
    let frame = format!("frame:{name}:{grade}");
    let needed = HELD_FRAME_SIZE + PLANTED_FRAME_SIZE + 2 * HEAD_SIZE;

    let script = format!(
        "new {seed}
pause
goto {mx} {my}
tick {to_material}
mine
tick 80
goto {fx} {fy}
tick {to_fuel}
mine
tick 30
craft smelter {mat_ore}
tick 25
place smelter
insert 0 fuel {fuel_ore} 6
insert 0 ore {mat_ore} {ore_in}
tick {smelting}
take 0
tick 1
parts
make {handle_kind} {refined} 1
tick 1
make head {refined} 2
tick 1
make {frame_kind} {refined} 1
tick 1
inv
design {handle} {head}
design {frame} {head}
assemble {handle} {head}
tick 1
built
equip 0
tick 1
built
assemble {frame} {head}
tick 1
built
plant 0 {px} {py}
tick 1
buildings
built
goto {mx} {my}
tick {back}
assay
tick 31
built
inv
quit
",
        mx = material.center.x,
        my = material.center.y,
        to_material = walk(spawn, material.center),
        fx = fuel.center.x,
        fy = fuel.center.y,
        to_fuel = walk(material.center, fuel.center).max(25),
        ore_in = needed + 2,
        smelting = (needed + 2) * 25 + 50,
        handle_kind = "handle",
        frame_kind = "frame",
        // West of the player: `place smelter` already took the tiles to the east.
        px = fuel.center.x - 1,
        py = fuel.center.y,
        back = walk(fuel.center, material.center),
    );

    let saves = std::env::temp_dir().join(format!("assay-first-pick-{}", std::process::id()));
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

    let m = ms.name();
    let g = material.grade().letter();
    for expected in [
        // The catalogue reads in text.
        "head     mounted".to_string(),
        "handle   held".to_string(),
        // Parts are made from refined material and nothing else.
        format!("you made 1 x {m} handle ({g})"),
        format!("you made 2 x {m} head ({g})"),
        format!("you made 1 x {m} frame ({g})"),
        // One command builds a pick and a drill alike, and the entry says
        // which it built rather than which slot it went into (ASSA-130).
        "you assembled a tool".to_string(),
        "you assembled a machine".to_string(),
        "you equipped a tool".to_string(),
        // And a planted design becomes a building.
        "you planted machine 1".to_string(),
    ] {
        assert!(
            stdout.contains(&expected),
            "missing {expected:?}\n{transcript}"
        );
    }

    // ASSA-130, IN THE PLAY-THROUGH THAT HAS THE PAIR. `assemble` then
    // `equip` one tick apart is the normal flow, and both entries printed the
    // same sheet: four wrapped rows each, eight of the twenty-four readable
    // rows in the window shot that filed the item. The sheet belongs to the
    // entry where it is news.
    let assembled = stdout
        .lines()
        .find(|l| l.contains("you assembled a tool"))
        .unwrap_or_else(|| panic!("no assemble entry in the transcript\n{transcript}"));
    let equipped = stdout
        .lines()
        .find(|l| l.contains("you equipped a tool"))
        .unwrap_or_else(|| panic!("no equip entry in the transcript\n{transcript}"));
    for marker in ["mass ", "budget", "durability", "speed ", "handle("] {
        // The present half first: without it, a readout that stopped saying
        // "mass" would make the absence below true for the wrong reason.
        assert!(
            assembled.contains(marker),
            "premise: the assemble entry is supposed to carry the whole sheet, \
             and is missing {marker:?}: {assembled}\n{transcript}"
        );
        assert!(
            !equipped.contains(marker),
            "the equip entry reprints the sheet's {marker:?} one tick after the \
             assemble entry already said it: {equipped}\n{transcript}"
        );
    }
    assert!(
        equipped.contains("SAFE"),
        "the verdict bears on the act and stays on the equip entry: \
         {equipped}\n{transcript}"
    );

    // Amendment A5, end to end: mass against budget, **banded before the assay
    // and exact after it**. Both readings of the same pick are in this one
    // transcript, which is the claim the ruling actually makes.
    let in_hand: Vec<&str> = stdout
        .lines()
        .filter(|l| l.starts_with("in hand  ") && l.contains("handle("))
        .collect();
    assert!(
        in_hand.len() >= 2,
        "expected the pick read out before and after the assay\n{transcript}"
    );
    let banded = in_hand.first().expect("a first reading");
    let exact = in_hand.last().expect("a last reading");
    let density = u32::from(ms.sheet.density);
    let strength = ms.effective(Property::Strength, material.grade());
    assert!(
        banded.contains('-') && banded.contains("budget"),
        "before assaying, mass and budget should read as bands: {banded}\n{transcript}"
    );
    assert!(
        exact.contains(&format!(
            "mass {} of {} budget",
            (HELD_FRAME_SIZE + HEAD_SIZE) * density,
            HELD_FRAME_SIZE * strength * FRAME_BUDGET_PER_STRENGTH
        )),
        "after assaying, mass and budget should be exact: {exact}\n{transcript}"
    );
    assert!(
        exact.contains("durability "),
        "a held tool shows its pool: {exact}\n{transcript}"
    );
    assert!(
        in_hand.iter().all(|l| l.contains("SAFE")),
        "this seed's pick fits its budget, so the verdict should say so\n{transcript}"
    );
    // The planted machine is in the buildings table, and shows no durability
    // there (the Game Director's ruling: drill wear is parked, so a number
    // that never moves must not be displayed).
    let machine_line = stdout
        .lines()
        .rfind(|l| l.contains("machine") && l.contains("mass"))
        .unwrap_or_else(|| panic!("no machine line in the buildings table\n{transcript}"));
    assert!(
        !machine_line.contains("durability"),
        "a planted machine must not show durability: {machine_line}\n{transcript}"
    );
    assert!(
        machine_line.contains("holding 0 of"),
        "a fresh drill holds nothing: {machine_line}\n{transcript}"
    );

    // Every part was spent: the pick is in hand, the drill is on the map.
    let carrying = stdout
        .lines()
        .rfind(|l| l.starts_with("Carrying "))
        .unwrap_or_else(|| panic!("no inventory line\n{transcript}"));
    assert!(
        !carrying.contains("handle") && !carrying.contains("frame"),
        "both frames should have been consumed: {carrying}\n{transcript}"
    );

    // ASSA-323: THE DESIGN READ BEFORE THE PRESS, IN THE PLAY-THROUGH A TESTER
    // DRIVES. `design` takes the same words as `assemble` and spends nothing —
    // which this transcript proves twice over, because the two `assemble`
    // commands come after the two `design` commands and neither was rejected
    // (asserted above), and the final inventory is empty of frames.
    //
    // The claim worth a test is the harder one: the sentence you read before
    // you commit is the sentence you read afterwards. So the previews are not
    // matched against text written here — they are matched against the readout
    // the BUILT designs got later in the same run.
    let readouts: Vec<&str> = stdout.lines().filter(|l| l.contains("· mass ")).collect();
    assert!(
        readouts.len() > 2,
        "expected two previews and then the built designs' own readouts, \
         got {}:\n{transcript}",
        readouts.len()
    );
    let (previews, after) = readouts.split_at(2);
    for preview in previews {
        let line = preview.trim_start();
        assert!(
            after.iter().any(|l| l.contains(line)),
            "a preview that nothing later repeats is a second opinion, not a \
             preview: {line:?}\n{transcript}"
        );
    }
    // And the pack counts the Game Director's §5.3 asks for: have on the left.
    assert!(
        stdout.contains("your pack: 1/1 "),
        "the preview should count the parts the press will spend\n{transcript}"
    );
}
