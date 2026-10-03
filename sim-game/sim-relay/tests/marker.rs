//! The relay's first line, which exists so a client that spawned it can tell
//! "the system would not run this file" from "it ran and then died" (ASSA-120).
//!
//! **EVERY TEST HERE GOES THROUGH THE REAL BINARY**, because the claim is about
//! what a parent process reads off a pipe, and nothing about a function. A unit
//! test on a constant would prove the string exists and say nothing about
//! whether it leaves the process before the thing that kills it.
//!
//! THE TWO FAILURES IT HAS TO TELL APART, and they are the whole point:
//! a usage error and a bind that cannot happen are both a relay that RAN. If
//! the marker came after either of them, a client would report "macOS refused
//! to run it" at a player whose port was busy — Maren's constraint on this
//! item, and the same wrong-diagnosis-one-layer-down she withdrew her own
//! clause over.

use std::process::Command;

mod common;
use common::spawn_relay;

const MARKER: &str = "RELAY STARTED";

/// Run the relay with these arguments and give back (stdout, stderr, ok).
///
/// No `--port 0` and no saves dir: every caller here is a relay that is
/// supposed to die before it reaches either.
fn run(args: &[&str]) -> (String, String, bool) {
    let saves = std::env::temp_dir().join(format!("assay-marker-test-{}", std::process::id()));
    std::fs::create_dir_all(&saves).expect("a temp saves dir");
    let out = Command::new(env!("CARGO_BIN_EXE_sim-relay"))
        .args(args)
        .env("R2TS_SAVES_DIR", &saves)
        .output()
        .expect("sim-relay runs");
    (
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
        out.status.success(),
    )
}

#[test]
fn the_marker_is_the_very_first_line_of_a_healthy_start() {
    let relay = spawn_relay("14247", &["--bind", "127.0.0.1"]);
    let first = relay
        .startup
        .lines()
        .next()
        .expect("the relay printed something");
    assert!(
        first.starts_with(MARKER),
        "the first line a relay prints must be the marker, not {first:?}"
    );
    // IT CARRIES ONLY WHAT THIS BUILD KNOWS BEFORE IT OPENS ANYTHING: two
    // compile-time constants. Nothing read off a save or a socket may join
    // them, or the line stops being free and stops meaning "the exec happened".
    assert!(
        first.contains(&format!("protocol {}", sim_net::PROTOCOL_VERSION))
            && first.contains(sim_net::RULES_ID),
        "the marker should name this build's protocol and rules id: {first:?}"
    );
    // AND IT PRECEDES THE LINE THAT HAS ALWAYS BEEN THE CONTRACT, which is the
    // ordering the diagnosis rests on: marker without LISTENING means it ran
    // and could not get to the socket.
    let marker_at = relay.startup.find(MARKER).expect("the marker");
    let listening_at = relay
        .startup
        .find("LISTENING ")
        .expect("the LISTENING line");
    assert!(marker_at < listening_at, "{}", relay.startup);
}

#[test]
fn a_flag_it_cannot_read_still_says_it_ran() {
    let (stdout, stderr, ok) = run(&["--nonsense"]);
    assert!(!ok, "a bad flag should still be an error");
    assert!(
        stdout.starts_with(MARKER),
        "a usage error must not look like a file the system refused to run: {stdout:?}"
    );
    assert!(stderr.contains("Didn't understand"), "{stderr:?}");
}

#[test]
fn a_socket_it_cannot_have_still_says_it_ran() {
    // A TEST-NET-3 ADDRESS (RFC 5737), which no machine has, so the bind fails
    // the way a busy port or a taken interface fails: the relay's own sentence
    // and exit 1. This is the case Limpet measured by hand on macOS —
    // "Can't assign requested address (os error 49)" — and the one a client
    // must never report as a refused exec.
    let (stdout, stderr, ok) = run(&["14247", "--bind", "203.0.113.9", "--port", "0"]);
    assert!(
        !ok,
        "binding an address this machine does not have must fail"
    );
    assert!(
        stdout.starts_with(MARKER),
        "a relay that ran and could not bind must still have said it ran: {stdout:?}"
    );
    assert!(
        !stdout.contains("LISTENING "),
        "it never listened, so it must not have said so: {stdout:?}"
    );
    assert!(stderr.contains("Could not listen on"), "{stderr:?}");
}
