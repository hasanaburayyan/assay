//! The headless game says when a rock can be mined and never smelted
//! (ASSA-52), on the seed that proves why it matters, through the REAL binary.
//!
//! **SEED 10027 IS HERE FOR ITS DEFECT, NOT AS A PIN.** The Game Director
//! pinned it for the friend test in the morning and withdrew it the same day:
//! she had filtered on *hand-minable*, and a part needs refined material, so
//! the gate is rung zero. Spawn on 10027 stands on Meline — grade A, purity
//! 80, the best ore yield in the game — with a heat tolerance no fire a player
//! can light will reach. A friend would have mined two hundred ore of the most
//! promising rock on the map and found out much later that it was scenery.
//! That is the exact world this sentence exists for, so it is the world the
//! test plays. The friend test itself is seed 14247 now (ASSA-45).
//!
//! The world comes from `sim_net::fresh_world`, the one place a session's
//! shape is decided (ASSA-53): `WorldConfig::default()` is 8x8, which is a
//! *different world* for the same seed, and the hosts and CI build 6x4.

use std::io::Write;
use std::process::{Command, Stdio};

use sim::World;

const UNSMELTABLE_SEED: u64 = 10027;

fn host_world(seed: u64) -> World {
    sim_net::fresh_world(seed)
}

#[test]
fn the_plain_prompt_says_a_rock_can_be_mined_and_never_smelted() {
    let world = host_world(UNSMELTABLE_SEED);
    let spawn = world.spawn_tile();
    let under_foot = world
        .deposit_at(spawn)
        .expect("10027 at 6x4 puts a deposit under the player's feet");
    let dead = world.species(under_foot.species);
    assert!(
        sim::ladder::hand_minable(dead),
        "the point of this seed is that the rock CAN be mined: {}",
        dead.name()
    );
    assert!(
        !sim::ladder::usable_from_bare_hands(&world.species, under_foot.species),
        "and that it can never be smelted: {}",
        dead.name()
    );
    // A rock in the same world that IS usable, for the control half.
    let good = world
        .deposits
        .iter()
        .find(|d| sim::ladder::usable_from_bare_hands(&world.species, d.species))
        .expect("the ladder guarantees a usable species");
    let good_name = world.species(good.species).name().to_string();
    assert_ne!(good_name, dead.name(), "control must be different rock");

    let script = format!(
        "new {UNSMELTABLE_SEED}
pause
where
at {} {}
deposits
species
quit
",
        good.center.x, good.center.y,
    );

    let saves = std::env::temp_dir().join(format!("assay-unsmeltable-{}", std::process::id()));
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
    let transcript = format!(
        "--- script\n{script}\n--- stdout\n{stdout}\n--- stderr\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.status.success(), "{transcript}");

    let says_dead_end = |line: &str| line.contains("can be mined but not smelted");

    // `where`: standing on it. This is the line a friend meets first, before
    // they have mined anything, and it used to say "`mine` to start mining it"
    // with no hint that the ore would never become a part.
    let standing = stdout
        .lines()
        .find(|l| l.starts_with("You're on deposit"))
        .unwrap_or_else(|| panic!("no `where` report\n{transcript}"));
    assert!(
        says_dead_end(standing),
        "standing on a dead end must say so: {standing}\n{transcript}"
    );

    // `at`, pinned to its own line: the control rock, which must stay silent.
    let at_line = stdout
        .lines()
        .find(|l| l.starts_with(&format!("({}, {}): deposit", good.center.x, good.center.y)))
        .unwrap_or_else(|| panic!("`at` printed no deposit line\n{transcript}"));
    assert!(
        !says_dead_end(at_line),
        "THE CONTROL: a rock that yields must say nothing: {at_line}\n{transcript}"
    );

    // `deposits`: the listing, where a player compares rocks. Every row of the
    // dead species says so and no row of the usable one does.
    let rows: Vec<&str> = stdout
        .lines()
        .filter(|l| l.contains(dead.name()) && l.contains('('))
        .collect();
    assert!(!rows.is_empty(), "no listing rows\n{transcript}");
    for row in &rows {
        assert!(says_dead_end(row), "listing row stays silent: {row}");
    }

    // `species`: the roster, where bare "hand-minable" read as a promise.
    let species_row = stdout
        .lines()
        .find(|l| l.contains(dead.name()) && l.contains("hand-minable"))
        .unwrap_or_else(|| panic!("no species row for {}\n{transcript}", dead.name()));
    assert!(
        species_row.contains("not smeltable"),
        "the roster must not promise a dead end: {species_row}\n{transcript}"
    );
    let good_row = stdout
        .lines()
        .find(|l| l.contains(&good_name) && l.contains("hand-minable"))
        .unwrap_or_else(|| panic!("no species row for {good_name}\n{transcript}"));
    assert!(
        !good_row.contains("not smeltable"),
        "THE CONTROL: a usable species keeps its row: {good_row}\n{transcript}"
    );
}
