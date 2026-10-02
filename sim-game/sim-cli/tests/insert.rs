//! One press puts what fits into a smelter, on the seed the friend test will
//! use (ASSA-48), driven through the REAL `sim-cli --plain` binary.
//!
//! **THIS IS THE GAME DIRECTOR'S OWN REPRODUCTION, KEPT.** She mined 222 ore at
//! spawn on seed 10027, pressed the client's one Smelt button, and was told
//! *"that slot is full or holds a different item"* about an **empty** slot,
//! because `Insert` rejected any offer larger than the cap instead of taking
//! what fits. A unit test on the clamp proves the rule; it does not prove that
//! a person pressing one button gets ore into a smelter. This does, through the
//! binary, with the species and grade read from the world rather than typed.

mod common;

use std::io::Write;
use std::process::{Command, Stdio};

use sim::tuning::SMELTER_INPUT_CAP;

/// The seed the bug was found on, which is why it is a literal here.
///
/// **IT IS NO LONGER THE FRIEND-TEST PIN** and must not be read as one: the
/// Game Director pinned 10027 at 12:11 on 2026-10-02 and withdrew it at 13:27
/// because spawn there stands on ore no hand-lit fire can smelt. The pin is
/// 14247 (ASSA-45), guarded by `demo_seed.rs`. This test keeps 10027 because a
/// reproduction belongs on the world it was reproduced on; everything else
/// below is derived from the world, so the number is all that would change.
const REPRO_SEED: u64 = 10027;

#[test]
fn one_press_fills_the_slot_and_says_what_stayed_in_hand() {
    let world = sim_net::fresh_world(REPRO_SEED);
    let spawn = world.spawn_tile();
    let under_foot = world
        .deposit_at(spawn)
        .expect("the pinned seed puts a deposit under the player's feet");
    let species = world.species(under_foot.species);
    let ore = format!(
        "ore:{}:{}",
        species.name().to_ascii_lowercase(),
        under_foot.grade().letter().to_ascii_lowercase()
    );

    // Mine well past the cap, build a smelter out of some of it, then offer
    // the whole pile in one go, exactly as the client's single button does.
    let offer = SMELTER_INPUT_CAP * 4;
    let script = format!(
        "new {REPRO_SEED}
pause
mine
tick 300
stop
craft smelter {ore}
tick 30
place smelter
tick 1
insert 0 ore {ore} {offer}
tick 1
buildings
inv
quit
"
    );

    let saves = std::env::temp_dir().join(format!("assay-insert-{}", std::process::id()));
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

    // THE LINE A PLAYER READS, pinned to the insert's own line so it cannot
    // pass on some other command's output.
    let put = stdout
        .lines()
        .find(|l| l.contains("into building 0's ore slot"))
        .unwrap_or_else(|| panic!("nothing went into the smelter\n{transcript}"));
    assert!(
        put.contains(&format!("put {SMELTER_INPUT_CAP} ")),
        "one press must fill the slot to its cap: {put}\n{transcript}"
    );
    assert!(
        put.contains("would not fit, still in hand"),
        "the leftover is the actionable half: {put}\n{transcript}"
    );
    assert!(
        !stdout.contains("that slot is full"),
        "THE BUG: an empty slot reported as full\n{transcript}"
    );

    // And the world agrees with the sentence: the slot holds a cap's worth and
    // the player still has the rest.
    let inside = stdout
        .lines()
        .find(|l| l.contains("smelter") && l.contains("in "))
        .unwrap_or_else(|| panic!("no smelter row\n{transcript}"));
    assert!(
        inside.contains(&format!("in {SMELTER_INPUT_CAP} ")),
        "{inside}\n{transcript}"
    );
    let carrying = stdout
        .lines()
        .rfind(|l| l.starts_with("Carrying "))
        .unwrap_or_else(|| panic!("no inventory line\n{transcript}"));
    assert!(
        !carrying.contains(&format!("{offer} ")),
        "the player cannot still be holding the whole offer: {carrying}\n{transcript}"
    );
    let _ = common::walk(spawn, spawn);
}
