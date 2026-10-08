//! Talking to a relay: join handshake, then one thread sending commands and
//! one thread receiving tick bundles.

use std::io::BufReader;
use std::net::TcpStream;
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};
use std::thread;

use sim::{PlayerId, World};
use sim_net::{ClientMsg, DEFAULT_PORT, PROTOCOL_VERSION, ServerMsg, read_msg, write_msg};

use crate::host::Host;

/// Connect, say hello, and wait to be welcomed.
pub fn join(addr: &str, name: &str) -> Result<(TcpStream, String, PlayerId, World), String> {
    let addr = if addr.contains(':') {
        addr.to_string()
    } else {
        format!("{addr}:{DEFAULT_PORT}")
    };
    let mut stream =
        TcpStream::connect(&addr).map_err(|e| format!("Could not reach {addr}: {e}"))?;
    let _ = stream.set_nodelay(true);

    let hello = ClientMsg::Hello {
        name: name.to_string(),
        protocol: PROTOCOL_VERSION,
        rules: sim_net::RULES_ID.to_string(),
    };
    write_msg(&mut stream, &hello).map_err(|e| format!("Could not talk to {addr}: {e}"))?;

    // Read unbuffered here so no bytes after the Welcome get swallowed.
    match read_msg(&mut stream) {
        Ok(ServerMsg::Welcome { player, world }) => Ok((stream, addr, player, world)),
        Ok(ServerMsg::Refused { reason }) => {
            Err(format!("{addr} refused the connection: {reason}"))
        }
        Ok(other) => Err(format!("{addr} sent {other:?} before welcoming us.")),
        Err(e) => Err(format!("Lost the connection to {addr} while joining: {e}")),
    }
}

/// Everything sent to `returned sender` goes out over the socket, in order.
pub fn spawn_sender(stream: TcpStream) -> Sender<ClientMsg> {
    let (tx, rx) = mpsc::channel::<ClientMsg>();
    thread::spawn(move || {
        let mut stream = stream;
        for msg in rx {
            if write_msg(&mut stream, &msg).is_err() {
                break;
            }
        }
    });
    tx
}

/// Apply every tick bundle the relay sends, printing what happened.
pub fn spawn_receiver(stream: TcpStream, host: Arc<Mutex<Host>>, print: Sender<String>) {
    thread::spawn(move || {
        let mut r = BufReader::new(stream);
        loop {
            match read_msg(&mut r) {
                Ok(ServerMsg::Tick(bundle)) => {
                    let lines = host.lock().unwrap().apply_bundle(&bundle);
                    for line in lines {
                        let _ = print.send(format!("  {line}"));
                    }
                }
                Ok(ServerMsg::Desync {
                    tick,
                    reported,
                    expected,
                }) => {
                    // **THE EVIDENCE, AND THE HONEST STATEMENT THAT THIS
                    // CLIENT HAS NO WAY BACK** (ASSA-190 box 6). The Godot
                    // client closes its socket on a desync and offers Join;
                    // `sim-cli` has no reconnect and this item does not give
                    // it one, so the sentence says restart and means it. The
                    // two hashes are here because a drop with no evidence is
                    // the shape that lets a determinism bug pass as a bad
                    // connection.
                    let _ = print.send(format!(
                        "  WARNING: desync at tick {tick}: we hashed {reported}, the host has \
                         {expected}. Your world no longer matches the host's and this client \
                         cannot rejoin without restarting."
                    ));
                }
                Ok(ServerMsg::Welcome { .. } | ServerMsg::Refused { .. }) => {}
                Err(e) => {
                    host.lock().unwrap().disconnected();
                    let _ = print.send(format!("  Disconnected from the host: {e}"));
                    return;
                }
            }
        }
    });
}
