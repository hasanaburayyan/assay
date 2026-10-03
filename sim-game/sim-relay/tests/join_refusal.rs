//! A relay refuses a peer built from different rules (ASSA-40), through the
//! real binary and a real socket.
//!
//! **THE UNIT TEST IN `sim-net` IS NOT ENOUGH ON ITS OWN.** It proves
//! `check_join` decides correctly; it says nothing about whether the relay
//! calls it. Deleting the call would leave it green. So this test speaks the
//! wire to a spawned `sim-relay` and watches what comes back.
//!
//! `CARGO_BIN_EXE_sim-relay` is the binary cargo built for *this* test run,
//! which is the point: a harness that found the relay by path once handed me
//! a passing mutation against the previous build.

use std::io::Write;
use std::net::TcpStream;
use std::time::Duration;

mod common;
use common::spawn_relay;

use sim_net::{ClientMsg, RULES_ID, ServerMsg, read_msg, write_msg};

const OTHER_RULES: &str = "0123456789abcdef";

/// Say hello with these identities and return what the relay says back.
fn greet(port: u16, name: &str, rules: &str) -> ServerMsg {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    stream.set_read_timeout(Some(Duration::from_secs(20))).ok();
    write_msg(
        &mut stream,
        &ClientMsg::Hello {
            name: name.to_string(),
            protocol: sim_net::PROTOCOL_VERSION,
            rules: rules.to_string(),
        },
    )
    .expect("write hello");
    read_msg(&mut stream).expect("the relay answers a hello")
}

#[test]
fn a_peer_from_different_rules_is_refused_and_one_from_the_same_rules_joins() {
    let relay = spawn_relay("7", &[]);
    let port = relay.port();

    // 1. The failure this feature exists for: same wire, different game.
    match greet(port, "stale", OTHER_RULES) {
        ServerMsg::Refused { reason } => {
            assert!(
                reason.contains(RULES_ID) && reason.contains(OTHER_RULES),
                "the refusal must name both builds: {reason}"
            );
            assert!(
                reason.contains("Download the build that matches this host"),
                "and what to do about it: {reason}"
            );
        }
        other => panic!("a peer on different rules was not refused: {other:?}"),
    }

    // 2. NON-VACUITY, and the half that would catch a relay refusing
    //    everyone: the matching build must still get in. A test that only
    //    checked the refusal would pass against `return self.refuse(..)`.
    match greet(port, "current", RULES_ID) {
        ServerMsg::Welcome { .. } => {}
        other => panic!("a peer on the host's own rules was not welcomed: {other:?}"),
    }

    drop(relay);
}

/// The relay says which rules it is hosting on startup, so pairing a
/// downloaded zip to a running host is reading rather than guessing — Nerite
/// has been doing it with `lsof` and a binary mtime.
#[test]
fn the_relay_prints_the_rules_it_is_hosting() {
    let relay = spawn_relay("7", &[]);

    // **THE BANNER IS CAPTURED AS IT IS PRINTED, NOT RECOVERED AFTERWARDS.**
    // This test used to greet the relay, kill it, and read its pipe to EOF —
    // so what it asserted against was whatever had been flushed by the time
    // the kill landed. That is the same race as the port it used to guess, in
    // the same test, and it is why this one went red under load while passing
    // alone. `spawn_relay` reads the startup block to its terminator before
    // returning.
    assert!(
        relay.startup.contains(RULES_ID),
        "the startup banner must name the rules identity, got:\n{}",
        relay.startup
    );

    // NON-VACUITY: a harness that captured nothing would pass an assertion
    // about a string that only has to *contain* something if it is empty by
    // accident — it would not, but a future change to the reader could make it
    // so, and this is the line that would notice.
    assert!(
        relay.startup.lines().count() >= 4,
        "the banner is suspiciously short, so the assertion above proves \
         little: {:?}",
        relay.startup
    );
}

/// **THE FRAME THE GAME DIRECTOR ACTUALLY SENT AT THE #38 BENCH**, written by
/// hand from the protocol-6 source at `2ff1466^` rather than produced by
/// anything in this tree — a frame today's code can build is not evidence
/// about a build already on someone's disk.
const PROTOCOL_6_HELLO: &str = r#"{"Hello":{"name":"ada","protocol":6}}"#;

/// Write a raw length-prefixed frame, bypassing `write_msg`, because the whole
/// point is to send something this build's types cannot express.
fn send_raw(stream: &mut TcpStream, body: &str) {
    let len = u32::try_from(body.len()).expect("small");
    stream.write_all(&len.to_be_bytes()).expect("length");
    stream.write_all(body.as_bytes()).expect("body");
    stream.flush().expect("flush");
}

/// **A CLIENT TWO PROTOCOL VERSIONS BEHIND GETS A SENTENCE, NOT A TORN SOCKET
/// (ASSA-77).** This is the failure the Game Director reproduced with the
/// board's own downloaded build: a protocol-6 `Hello` carries no `rules`
/// field, so the relay could not deserialise it, the reader thread ended, and
/// the player saw `failed to fill whole buffer`.
///
/// The unit tests in `sim-net` prove the greeting parses and the sentence is
/// right; neither says the relay *answers*. Before this fix the relay dropped
/// the connection without writing a byte, and that is exactly what a test of
/// `refuse_unreadable` alone would have stayed green through.
#[test]
fn a_client_two_protocols_behind_is_refused_in_words() {
    let relay = spawn_relay("7", &[]);
    let port = relay.port();

    let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    stream.set_read_timeout(Some(Duration::from_secs(20))).ok();
    send_raw(&mut stream, PROTOCOL_6_HELLO);

    let answer: ServerMsg = read_msg(&mut stream)
        .expect("the relay must answer a hello it cannot parse, not close the socket");
    match answer {
        ServerMsg::Refused { reason } => {
            assert!(
                reason.contains("v6") && reason.contains(&sim_net::PROTOCOL_VERSION.to_string()),
                "name both protocols so they know which way the gap runs: {reason}"
            );
            assert!(
                reason.contains(RULES_ID),
                "and the build to download, as the rules refusal does: {reason}"
            );
            assert!(
                reason.contains("Nothing is wrong with your machine"),
                "a stranger cannot tell this from a dead host or bad wifi: {reason}"
            );
        }
        other => panic!("an old client was not refused in words: {other:?}"),
    }

    // NON-VACUITY: the same relay still welcomes a matching build, so this
    // cannot be passing against a relay that refuses everyone.
    match greet(port, "current", RULES_ID) {
        ServerMsg::Welcome { .. } => {}
        other => panic!("the matching build was not welcomed: {other:?}"),
    }

    drop(relay);
}

/// A first frame that is not JSON at all is the same promise: the player is
/// told something they can act on. Kept separate from the protocol case
/// because it reaches the other arm of `refuse_unreadable`, and an assertion
/// over one transcript can pass from the other command's output.
#[test]
fn a_first_frame_that_is_not_json_is_also_refused_in_words() {
    let relay = spawn_relay("7", &[]);
    let port = relay.port();

    let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    stream.set_read_timeout(Some(Duration::from_secs(20))).ok();
    send_raw(&mut stream, "hello?");

    match read_msg(&mut stream).expect("the relay answers garbage too") {
        ServerMsg::Refused { reason } => {
            assert!(
                reason.contains("could not read your client's first message"),
                "{reason}"
            );
            assert!(reason.contains(RULES_ID), "{reason}");
        }
        other => panic!("garbage was not refused in words: {other:?}"),
    }
    drop(relay);
}
