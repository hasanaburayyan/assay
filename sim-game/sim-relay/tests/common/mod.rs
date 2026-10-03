//! Starting a real `sim-relay` for a test, without guessing a port (ASSA-110).
//!
//! **NO HARNESS MAY PICK A PORT.** The old shape was: bind `127.0.0.1:0`, read
//! the number, **close the socket**, then spawn a relay on it. Between the
//! close and the relay's bind anything on the machine can take that port —
//! including another test binary in the same `cargo test` run, which is why it
//! only failed under load. `the_relay_prints_the_rules_it_is_hosting` failed
//! that way with `ConnectionReset` on a branch that touched no relay file, and
//! passed 6/6 alone.
//!
//! So the relay is given `--port 0` and asked what it got (ASSA-108). There is
//! no gap to lose, and it is the same `LISTENING` line the Godot client reads
//! when it starts a solo relay (ASSA-106) — so these tests exercise the
//! contract the product depends on rather than one invented for testing.

use std::io::{BufRead, BufReader};
use std::net::SocketAddr;
use std::process::{Child, ChildStdout, Command, Stdio};

// **EACH TEST BINARY COMPILES THIS MODULE SEPARATELY**, so anything one of
// them does not call is dead code *there* and fails `-D warnings` even though
// the other file uses it. That is a property of `tests/common/mod.rs`, not a
// sign the helper is unused.
#[allow(dead_code)]
pub struct Relay {
    pub child: Child,
    /// The address the relay said it was listening on.
    pub bound: SocketAddr,
    /// Everything it printed before it went quiet and started ticking.
    pub startup: String,
    /// **HELD OPEN ON PURPOSE, AND NOT DECORATION.** Dropping the read end of
    /// the pipe makes the relay's next `println!` fail, and a relay logs every
    /// join — so the first version of this helper let three tests connect to a
    /// relay that then died mid-handshake, and they failed with "failed to
    /// fill whole buffer". Keeping the reader alive keeps the pipe alive.
    _stdout: BufReader<ChildStdout>,
}

#[allow(dead_code)]
impl Relay {
    pub fn port(&self) -> u16 {
        self.bound.port()
    }
}

impl Drop for Relay {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Start a relay on a free port and wait until it says where it is.
///
/// `extra` goes after the fixed arguments, so a caller can add `--bind` or a
/// different seed. The saves directory is per process and per thread, because
/// `cargo test` runs these concurrently and two relays sharing a world file
/// would be a different flake.
pub fn spawn_relay(seed: &str, extra: &[&str]) -> Relay {
    let saves = std::env::temp_dir().join(format!(
        "assay-relay-test-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    std::fs::create_dir_all(&saves).expect("a temp saves dir");
    let mut child = Command::new(env!("CARGO_BIN_EXE_sim-relay"))
        .args([seed, "--port", "0", "--fresh"])
        .args(extra)
        .env("R2TS_SAVES_DIR", &saves)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("sim-relay starts");
    let mut stdout = BufReader::new(child.stdout.take().expect("piped stdout"));
    let mut bound = None;
    let mut startup = String::new();
    // **READ TO A TERMINATOR, NEVER KILL AND DRAIN.** A harness that kills the
    // relay and reads whatever was flushed sees a different amount of output
    // every run: one assertion passes by luck and the next fails on two lines.
    // The relay prints its whole startup block and then goes quiet, so the
    // block's last line is the signal that nothing more is coming — `nobody
    // else` on a local-only bind, `over the internet` otherwise.
    //
    // `LISTENING` comes before the end of the block, so by the time we return
    // the socket is already accepting and no caller has to poll for it.
    for _ in 0..40 {
        let mut line = String::new();
        if stdout.read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }
        startup.push_str(&line);
        if let Some(addr) = line.trim().strip_prefix("LISTENING ") {
            bound =
                Some(addr.parse::<SocketAddr>().unwrap_or_else(|e| {
                    panic!("LISTENING did not carry an address: {line:?} ({e})")
                }));
        }
        if line.contains("nobody else") || line.contains("over the internet") {
            break;
        }
    }
    let bound = bound
        .unwrap_or_else(|| panic!("the relay never said it was listening. It printed:\n{startup}"));
    // A POSITIVE ANCHOR, so absence assertions in callers cannot pass by
    // having read too little: if a line is ever added after the terminator,
    // this still proves the join block itself was captured.
    assert!(
        startup.contains("Players join with"),
        "the startup block was not read to the end: {startup}"
    );
    Relay {
        child,
        bound,
        startup,
        _stdout: stdout,
    }
}
