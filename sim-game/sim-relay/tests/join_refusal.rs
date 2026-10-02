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

use std::io::Read;
use std::net::{TcpListener, TcpStream};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use sim_net::{ClientMsg, RULES_ID, ServerMsg, read_msg, write_msg};

const OTHER_RULES: &str = "0123456789abcdef";

struct Relay(Child);

impl Drop for Relay {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .expect("a free port")
        .local_addr()
        .expect("its address")
        .port()
}

fn spawn_relay(port: u16) -> Relay {
    let saves = std::env::temp_dir().join(format!("assay-assa40-{}", std::process::id()));
    std::fs::create_dir_all(&saves).expect("a temp saves dir");
    let child = Command::new(env!("CARGO_BIN_EXE_sim-relay"))
        .args(["7", "--port", &port.to_string(), "--fresh"])
        .env("R2TS_SAVES_DIR", &saves)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("sim-relay starts");

    let deadline = Instant::now() + Duration::from_secs(20);
    while TcpStream::connect(("127.0.0.1", port)).is_err() {
        assert!(Instant::now() < deadline, "the relay never listened");
        std::thread::sleep(Duration::from_millis(50));
    }
    Relay(child)
}

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
    let port = free_port();
    let relay = spawn_relay(port);

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
    let port = free_port();
    let mut relay = spawn_relay(port);
    let mut stdout = relay.0.stdout.take().expect("piped");

    // Read what it has printed by the time it is listening, then stop it so
    // the pipe closes rather than blocking on a relay that runs for ever.
    let _ = greet(port, "reader", RULES_ID);
    let _ = relay.0.kill();
    let mut banner = String::new();
    let _ = stdout.read_to_string(&mut banner);

    assert!(
        banner.contains(RULES_ID),
        "the startup banner must name the rules identity, got:\n{banner}"
    );
}
