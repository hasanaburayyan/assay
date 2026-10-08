//! **THE AXIS A READING SITS ON IS VISIBLE WITHOUT A WINDOW** (ASSA-279),
//! driven through the REAL `sim-cli --plain` binary.
//!
//! `debug::reading_scale` was published so the Godot client could draw a
//! property bar without typing `100` of its own. A fact that only a renderer
//! can see is the repo's "no feature is done if it only works with graphics"
//! failure, so the terminal states the same scale under the same six columns.
//!
//! **DRIVEN THROUGH THE BINARY, not asserted on `reading_scale()`.** A unit
//! test on the function is already in `sim/tests/assay.rs` and would stay
//! green if no command ever printed the thing — which is exactly the gap this
//! file exists to close, and the same reason `ground_note.rs` spawns a child.

use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn the_species_command_states_the_scale_its_columns_sit_on() {
    let script = "new 14247\nspecies\n";
    let saves = std::env::temp_dir().join(format!("assay-reading-scale-{}", std::process::id()));
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

    // THE PREMISE: the table the line is about actually printed. Without this,
    // a `species` command that failed outright would leave the assertion below
    // the only thing on screen and it would still be true.
    assert!(
        stdout.contains("notes"),
        "the species table did not print, so there is nothing for a scale to be about\n\
         {transcript}"
    );

    let (lo, hi) = sim::debug::reading_scale();
    let expected = format!("(every reading above is on the {lo}-{hi} scale)");
    assert!(
        stdout.contains(&expected),
        "the terminal never stated the scale its readings sit on; expected {expected:?}\n\
         {transcript}"
    );

    // AND THE NUMBERS IN THAT SENTENCE COME FROM THE SIM. A literal here would
    // pass the assertion above for as long as it happened to match, which is
    // the whole defect ASSA-279 is about — one copy of the axis per surface.
    let src = include_str!("../src/host.rs");
    assert!(
        src.contains("debug::reading_scale"),
        "host.rs must ask the sim for the scale rather than spell it"
    );
    assert!(
        !src.contains(&format!("{lo}-{hi} scale")),
        "host.rs spells the scale's ends itself, so the sentence and the constant are free \
         to disagree"
    );
}
