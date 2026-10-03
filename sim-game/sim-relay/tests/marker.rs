//! The relay's FIRST word, and the three ways it could stop being first
//! (ASSA-120).
//!
//! **WHAT THE MARKER BUYS.** A Godot client that spawns this relay gets a live
//! PID from `OS.execute_with_pipe` whether the file was executed or not — the
//! same answer for a missing path, a non-executable file and a healthy start.
//! So "macOS would not run it" and "it ran and could not bind" are the same
//! observation, and a client that names either one is guessing at a cause.
//! Measured on that side: the dead child leaves Godot's `Could not create child
//! process` on stderr 3 of 10 attempts and 0 of the next 9, from a mono build
//! CI does not ship, and `/bin/sh -c "exit 1"` — a process that really ran —
//! leaves exactly as much behind.
//!
//! One line printed before anything that can fail makes the absence of the line
//! mean something. Which is why these tests are not about the line's text so
//! much as about its POSITION: a marker printed after the first fallible step
//! turns "ran but could not bind" into "the system would not run it", the same
//! wrong diagnosis one layer down (Maren's ruling on ASSA-120).
//!
//! Through the real binary, because the claim is about a process, not a string.

use std::process::{Command, Stdio};

mod common;
use common::spawn_relay;

/// The prefix a parent process keys on. Spelled out here rather than imported:
/// a test that reads the same constant as the code moves with it, and this one
/// must not. If someone renames the marker, this file is the thing that notices.
const MARKER: &str = "RELAY v";

/// Run the relay with these arguments and give back (stdout, stderr, exit ok).
///
/// `R2TS_SAVES_DIR` on a temp path, because a test that opens the founders'
/// world would be a different kind of bug.
fn run(args: &[&str]) -> (String, String, bool) {
    run_in(args, &format!("assay-marker-test-{}", std::process::id()))
}

/// The same, in a named saves directory, so one test can plant a file in it.
fn run_in(args: &[&str], dir: &str) -> (String, String, bool) {
    let saves = std::env::temp_dir().join(dir);
    std::fs::create_dir_all(&saves).expect("a temp saves dir");
    let out = Command::new(env!("CARGO_BIN_EXE_sim-relay"))
        .args(args)
        .env("R2TS_SAVES_DIR", &saves)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .expect("sim-relay runs");
    (
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
        out.status.success(),
    )
}

// ---------------------------------------------------------------------------

/// **FIRST LINE, NOT MERELY PRESENT.** A marker that appears somewhere in the
/// startup block is a marker that something ran before it, and the something is
/// what the client needed ruled out.
#[test]
fn the_marker_is_the_first_line_a_healthy_relay_prints() {
    let relay = spawn_relay("4242", &["--bind", "127.0.0.1"]);
    let first = relay
        .startup
        .lines()
        .next()
        .expect("the relay printed nothing at all");
    assert!(
        first.starts_with(MARKER),
        "the relay's first line is {first:?}, not the {MARKER:?} marker. Its whole startup:\n{}",
        relay.startup
    );
}

/// **A BAD FLAG STILL PRINTS IT, AND THIS IS THE CASE THE FEATURE EXISTS FOR.**
/// Argument parsing exits 1 on anything it does not understand. If the marker
/// came after it, a client passing a flag this build does not have would see a
/// silent dead child — exactly the picture of a file the system refused to run,
/// and it would say so.
#[test]
fn a_usage_error_is_not_mistaken_for_a_file_the_system_would_not_run() {
    let (stdout, stderr, ok) = run(&["--no-such-flag"]);
    assert!(!ok, "a bad flag should exit non-zero. stderr:\n{stderr}");
    assert!(
        stderr.contains("Didn't understand"),
        "a bad flag should still be explained to the person: {stderr:?}"
    );
    assert!(
        stdout.starts_with(MARKER),
        "the relay died on a bad flag without saying it had started: stdout {stdout:?}"
    );
}

/// **AND A FLAG MISSING ITS VALUE**, which exits from inside the closure rather
/// than from the match — a different early exit, and the one I would have
/// missed by testing only the branch I wrote the first test against.
#[test]
fn a_flag_with_no_value_still_prints_the_marker() {
    let (stdout, _stderr, ok) = run(&["--port"]);
    assert!(!ok, "a flag with no value should exit non-zero");
    assert!(
        stdout.starts_with(MARKER),
        "stdout was {stdout:?}, so the marker is not before argument parsing"
    );
}

/// **`--help` IS AN EARLY EXIT TOO**, and the only one that succeeds. A client
/// never passes it, but it is the third way out of `parse_args` and leaving it
/// unchecked would mean "the marker is first" rests on two of three paths.
#[test]
fn even_help_is_preceded_by_the_marker() {
    let (stdout, _stderr, ok) = run(&["--help"]);
    assert!(ok, "--help should exit 0");
    assert!(
        stdout.starts_with(MARKER),
        "stdout was {stdout:?}, so --help prints usage before the marker"
    );
}

/// **BEFORE ANY FILE WORK, AND THIS IS THE ONLY TEST THAT CAN SAY SO.** Every
/// other case here fails inside argument parsing, which happens before the save
/// is touched either way — so with the marker moved just one step later, after
/// `open_world`, all of them still fire and none of them is about the file.
/// A save the relay cannot read exits 1 from inside `open_world`, which is the
/// one place a marker printed "after the file" would be lost.
#[test]
fn a_save_this_build_cannot_read_is_still_preceded_by_the_marker() {
    let dir = format!("assay-marker-badsave-{}", std::process::id());
    let saves = std::env::temp_dir().join(&dir);
    std::fs::create_dir_all(&saves).expect("a temp saves dir");
    // The relay's own naming, not a guess: `world-<seed>.json` beside the
    // accounts file. Deliberately not JSON at all, so the failure is the load
    // and not a migration.
    std::fs::write(saves.join("world-4244.json"), "{ this is not a world").expect("plant a save");
    // NO `--fresh`: that is the flag that skips the load entirely, and skipping
    // the load is skipping the test.
    let (stdout, stderr, ok) = run_in(&["4244", "--port", "0", "--bind", "127.0.0.1"], &dir);
    assert!(
        !ok,
        "an unreadable save should exit non-zero. stdout:\n{stdout}"
    );
    assert!(
        stderr.contains("Could not load"),
        "the person should be told which file: {stderr:?}"
    );
    assert!(
        stdout.starts_with(MARKER),
        "the relay died opening a save without saying it had started: stdout {stdout:?}. \
         A client cannot tell that from a file the system refused to execute."
    );
}

/// **THE MARKER CARRIES THE PROTOCOL, AND IT IS THE REAL ONE.** Compared
/// against `sim_net::PROTOCOL_VERSION` rather than a number typed here, so a
/// bump cannot leave this file asserting last week's wire. The point is a peer
/// learning the number before the socket instead of through a torn read.
#[test]
fn the_marker_names_the_protocol_this_build_speaks() {
    let (stdout, _stderr, _ok) = run(&["--help"]);
    let first = stdout.lines().next().expect("no output");
    assert_eq!(
        first,
        format!("{MARKER}{}", sim_net::PROTOCOL_VERSION),
        "the marker should be `RELAY v<protocol>` with this build's number"
    );
}

/// **THE OTHER CONTRACT IS UNTOUCHED.** `LISTENING` is what every test harness
/// and the Godot client wait for; a change to the first line that broke the last
/// one would be a worse bug than the one being fixed.
#[test]
fn the_listening_line_still_comes_after_it_and_still_carries_the_address() {
    let relay = spawn_relay("4243", &["--bind", "127.0.0.1"]);
    let marker_at = relay
        .startup
        .lines()
        .position(|l| l.starts_with(MARKER))
        .expect("no marker");
    let listening_at = relay
        .startup
        .lines()
        .position(|l| l.starts_with("LISTENING "))
        .expect("no LISTENING line");
    assert!(
        marker_at < listening_at,
        "the marker must precede LISTENING; got {marker_at} and {listening_at} in:\n{}",
        relay.startup
    );
    assert_eq!(
        relay.bound.port(),
        relay.port(),
        "the address the harness parsed out of LISTENING should be the relay's"
    );
}
