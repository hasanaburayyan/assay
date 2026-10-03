//! Which interfaces a relay accepts on, and whether it tells the truth about
//! the address it got (ASSA-108, for ASSA-106's "Play solo").
//!
//! **THE DEFAULT MUST NOT MOVE.** Every relay anyone has ever started binds
//! `0.0.0.0`, and the board's own host on 7777 and the 7803 bench are both
//! running right now. A flag that quietly narrowed the default would take them
//! off the network, so the first test here is that nothing changed.
//!
//! **AND A SOLO RELAY MUST NOT BE REACHABLE.** `DevAuthenticator` trusts any
//! well-formed name, so a single-player world on `0.0.0.0` is an open world on
//! the player's LAN under whatever name a stranger types.
//!
//! Through the real binary and real sockets, for `join_refusal.rs`'s reason: a
//! unit test on an options struct proves the flag parses and says nothing
//! about what the socket does.

use std::net::{IpAddr, SocketAddr, TcpStream, UdpSocket};
use std::process::Command;
use std::time::Duration;

mod common;
use common::spawn_relay;

/// A local address that is not loopback, if this machine has one.
///
/// Same trick the relay's own `lan_ip` uses: a UDP socket needs no reachable
/// peer to tell you which local address would be used to reach one.
fn non_loopback_address() -> Option<IpAddr> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let ip = socket.local_addr().ok()?.ip();
    (!ip.is_loopback()).then_some(ip)
}

fn can_connect(addr: SocketAddr) -> bool {
    TcpStream::connect_timeout(&addr, Duration::from_secs(2)).is_ok()
}

// ---------------------------------------------------------------------------

/// **THE DEFAULT IS STILL EVERY INTERFACE.** The one test here whose failure
/// would mean a live host had been taken off the network.
#[test]
fn a_relay_given_no_bind_still_listens_on_every_interface() {
    let relay = spawn_relay("7", &[]);
    assert!(
        relay.bound.ip().is_unspecified(),
        "the default bind changed: {}",
        relay.bound
    );
    assert!(
        can_connect(SocketAddr::new(
            "127.0.0.1".parse().unwrap(),
            relay.bound.port()
        )),
        "a relay on every interface must answer on loopback too"
    );
    if let Some(ip) = non_loopback_address() {
        assert!(
            can_connect(SocketAddr::new(ip, relay.bound.port())),
            "a relay on 0.0.0.0 must answer on {ip}, or co-op is broken"
        );
    }
    // And it still tells people how to reach it from elsewhere.
    let output = relay.startup.clone();
    assert!(
        output.contains("over the internet"),
        "a network relay must still say how to be reached: {output}"
    );
}

/// **A SOLO RELAY IS REACHABLE FROM THIS COMPUTER AND NOWHERE ELSE** (Wren's
/// ruling 2 on ASSA-106).
///
/// The loopback half is asserted everywhere. The refusal from another address
/// needs this machine to *have* another address, so it is conditional — but it
/// is not a silent skip: when there is no second address the test says so in a
/// message and still proves the relay bound loopback and answers there, which
/// is the half that can regress from a code change. CI runners have a network,
/// so the strong half runs there.
#[test]
fn a_loopback_relay_answers_here_and_refuses_every_other_address() {
    let relay = spawn_relay("7", &["--bind", "127.0.0.1"]);
    assert!(
        relay.bound.ip().is_loopback(),
        "asked for loopback and got {}",
        relay.bound
    );
    assert!(
        can_connect(SocketAddr::new(
            "127.0.0.1".parse().unwrap(),
            relay.bound.port()
        )),
        "solo must be able to join its own relay"
    );
    match non_loopback_address() {
        Some(ip) => assert!(
            !can_connect(SocketAddr::new(ip, relay.bound.port())),
            "a solo relay answered on {ip}: a single-player world is open on \
             the network, and the authenticator trusts any name"
        ),
        None => println!(
            "no non-loopback address on this machine, so the refusal itself \
             was not exercised; the loopback half above still was"
        ),
    }
}

/// **NO INSTRUCTION THAT IS FALSE FOR THIS RELAY.** A loopback relay refuses
/// every route the LAN and internet lines describe, and sending a player to
/// their router to forward a port to a socket that will not answer is worse
/// than saying nothing.
#[test]
fn a_loopback_relay_does_not_print_routes_it_will_refuse() {
    let local = spawn_relay("7", &["--bind", "127.0.0.1"]);
    let port = local.bound.port();
    let output = local.startup.clone();
    assert!(
        !output.contains("over the internet"),
        "a local-only relay told somebody to forward a port: {output}"
    );
    assert!(
        !output.contains("same network"),
        "a local-only relay advertised a LAN address: {output}"
    );
    assert!(
        output.contains("this relay is listening on 127.0.0.1 only"),
        "it must say why nobody else can join: {output}"
    );
    // The route that DOES work is still printed, with the real port in it.
    assert!(
        output.contains(&format!("localhost:{port}")),
        "the one route that works must name the port it is on: {output}"
    );
}

/// **EVERY PRINTED PORT IS THE ONE WE GOT, NOT THE ONE WE ASKED FOR.**
///
/// With `--port 0` the number asked for is zero, so a readout that echoed the
/// request would say "port 0" and nobody could join. This is the assertion
/// that the relay reports reality.
#[test]
fn the_port_in_the_readout_is_the_port_actually_bound() {
    let relay = spawn_relay("7", &["--bind", "127.0.0.1"]);
    let port = relay.bound.port();
    assert_ne!(port, 0, "an OS-assigned port is never 0 once bound");
    let output = relay.startup.clone();
    assert!(
        !output.contains("port 0"),
        "the readout echoed the request instead of the result: {output}"
    );
    assert!(
        output.contains(&port.to_string()),
        "the readout never names the port it is on: {output}"
    );
}

/// A bad address is refused with a sentence, not a panic or a silent default.
///
/// **THE SILENT DEFAULT IS THE DANGEROUS FAILURE**, not the crash: a typo that
/// fell back to `0.0.0.0` would put a world the player thinks is private on
/// their network.
#[test]
fn an_address_that_is_not_an_address_is_refused_in_words() {
    let output = Command::new(env!("CARGO_BIN_EXE_sim-relay"))
        .args(["7", "--bind", "localhost"])
        .env(
            "R2TS_SAVES_DIR",
            std::env::temp_dir().join("assay-assa108-bad"),
        )
        .output()
        .expect("sim-relay runs");
    assert!(
        !output.status.success(),
        "a bad --bind must not start a relay"
    );
    let said = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        said.contains("--bind") || said.contains("localhost"),
        "it must name what it did not understand: {said}"
    );
    assert!(
        said.contains("Usage"),
        "and say what it would have accepted: {said}"
    );
}
