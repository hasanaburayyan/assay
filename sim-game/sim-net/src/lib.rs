//! Wire protocol shared by the relay and clients.
//!
//! Deterministic lockstep: every client runs the full sim. The relay owns the
//! clock and, each tick, broadcasts a [`TickBundle`] listing that tick's
//! inputs in order. A client may only run tick T after receiving bundle T, so
//! everyone applies the same inputs in the same order and computes the same
//! world. Clients report state hashes so the relay can spot desyncs.
//!
//! Framing: each message is a 4-byte big-endian length followed by that many
//! bytes of JSON. JSON keeps it readable while we build; switch to a binary
//! format when bandwidth or join size starts to matter.

use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use sim::{Input, PlayerCommand, PlayerId, World};

/// Bump whenever a message changes shape. Mismatched clients are refused.
pub const PROTOCOL_VERSION: u32 = 2;

/// Default port for `sim-relay` and `sim-cli --connect`.
pub const DEFAULT_PORT: u16 = 7777;

/// Clients report their state hash whenever the tick is a multiple of this.
pub const HASH_EVERY: u64 = 20;

/// Refuse to read any message bigger than this (guards against garbage).
const MAX_MESSAGE_BYTES: u32 = 64 * 1024 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum ClientMsg {
    /// First message on every connection.
    Hello { name: String, protocol: u32 },
    /// Ask for a command to be scheduled. There is deliberately no way to
    /// send a `SystemCommand`, and no player field: the relay stamps who
    /// sent it.
    Submit { command: PlayerCommand },
    /// "After running up to `tick`, my world hashes to `hash`."
    Hash { tick: u64, hash: u64 },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum ServerMsg {
    /// Accepted. `world` is the state to start from; the next bundle you
    /// receive is for `world.tick`.
    Welcome { player: PlayerId, world: World },
    /// Not accepted; the connection closes after this.
    Refused { reason: String },
    /// The inputs for one tick, in the order everyone must apply them.
    Tick(TickBundle),
    /// Your hash for `tick` doesn't match the host's. Your world has drifted.
    Desync { tick: u64 },
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TickBundle {
    pub tick: u64,
    pub inputs: Vec<Input>,
}

/// Where host programs (relay and client) keep world saves.
///
/// 1. `R2TS_SAVES_DIR`, if set.
/// 2. Under `cargo run`: `sim-game/saves/`, whichever folder you run from.
/// 3. A shipped binary: a `saves` folder next to the executable.
pub fn saves_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("R2TS_SAVES_DIR") {
        return dir.into();
    }
    // Cargo sets this for `cargo run`; it points at the running crate
    // (e.g. sim-game/sim-cli), whose parent is the workspace.
    if let Some(workspace) = std::env::var_os("CARGO_MANIFEST_DIR")
        .as_deref()
        .map(Path::new)
        .and_then(Path::parent)
    {
        return workspace.join("saves");
    }
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("saves")))
        .unwrap_or_else(|| PathBuf::from("saves"))
}

/// Write one length-prefixed JSON message and flush.
pub fn write_msg<W: Write, T: Serialize>(w: &mut W, msg: &T) -> io::Result<()> {
    let body = serde_json::to_vec(msg).map_err(io::Error::other)?;
    let len = u32::try_from(body.len())
        .ok()
        .filter(|&n| n <= MAX_MESSAGE_BYTES)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "message too large"))?;
    w.write_all(&len.to_be_bytes())?;
    w.write_all(&body)?;
    w.flush()
}

/// Read one length-prefixed JSON message. Blocks until it arrives.
pub fn read_msg<R: Read, T: DeserializeOwned>(r: &mut R) -> io::Result<T> {
    let mut len = [0u8; 4];
    r.read_exact(&mut len)?;
    let len = u32::from_be_bytes(len);
    if len > MAX_MESSAGE_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "message too large",
        ));
    }
    let mut body = vec![0u8; len as usize];
    r.read_exact(&mut body)?;
    serde_json::from_slice(&body).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use sim::{SystemCommand, TilePos};

    #[test]
    fn messages_round_trip_through_the_framing() {
        let bundle = ServerMsg::Tick(TickBundle {
            tick: 7,
            inputs: vec![
                Input::System(SystemCommand::AddPlayer { name: "ada".into() }),
                Input::player(
                    PlayerId(0),
                    PlayerCommand::MoveTo {
                        target: TilePos::new(3, 4),
                    },
                ),
            ],
        });
        let mut buf = Vec::new();
        write_msg(&mut buf, &bundle).unwrap();
        write_msg(
            &mut buf,
            &ClientMsg::Hash {
                tick: 20,
                hash: u64::MAX,
            },
        )
        .unwrap();

        let mut r = &buf[..];
        let ServerMsg::Tick(got) = read_msg(&mut r).unwrap() else {
            panic!("expected a tick bundle");
        };
        assert_eq!(got.tick, 7);
        assert_eq!(got.inputs.len(), 2);
        let ClientMsg::Hash { hash, .. } = read_msg(&mut r).unwrap() else {
            panic!("expected a hash");
        };
        assert_eq!(hash, u64::MAX);
    }

    #[test]
    fn oversized_length_is_rejected() {
        let mut buf = (MAX_MESSAGE_BYTES + 1).to_be_bytes().to_vec();
        buf.extend_from_slice(b"{}");
        let err = read_msg::<_, ClientMsg>(&mut &buf[..]).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
    }
}
