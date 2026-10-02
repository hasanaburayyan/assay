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
///
/// **THIS IS NOT THE RULES.** It answers "can we understand each other's
/// messages", and two builds can understand each other perfectly while
/// playing different games — see [`sim::RULES_ID`] and [`check_join`].
pub const PROTOCOL_VERSION: u32 = 8;

/// The rules this build runs, re-exported so a host has one place to look.
pub const RULES_ID: &str = sim::RULES_ID;

/// The size of a session's world, in chunks.
///
/// **ONE COPY, BECAUSE THERE WERE TWO** (ASSA-53). `sim-relay` built its world
/// with these numbers written out, and `sim-godot::fresh_welcome_text` wrote
/// them out again so the client's headless suite could have a real world. The
/// Systems engineer flagged the consequence before it bit us: if the two drift,
/// *every client test passes against a world no relay would ever send*, and
/// nothing goes red — the drift's author would be whoever next edits the relay,
/// who has no reason to look in the binding.
///
/// That is the same shape as the bug that hung six CI runs on 2026-10-02: two
/// spellings of one thing, one of them exercised only where it happens to work.
pub const SESSION_CHUNKS: (i32, i32) = (6, 4);

/// The world a relay starts a fresh session with, and the only place its shape
/// is decided.
///
/// It lives here rather than in a host because **both hosts already depend on
/// this crate** and neither may depend on the other: the Godot binding must not
/// pull in the relay, and the relay must not pull in the engine. `sim` itself is
/// the wrong home — a world's size is a session convention, not a rule, and
/// `sim` may not hold conventions it does not enforce.
pub fn fresh_world(seed: u64) -> World {
    let (width_chunks, height_chunks) = SESSION_CHUNKS;
    World::new(sim::WorldConfig {
        seed,
        width_chunks,
        height_chunks,
    })
}

/// Default port for `sim-relay` and `sim-cli --connect`.
pub const DEFAULT_PORT: u16 = 7777;

/// Clients report their state hash whenever the tick is a multiple of this.
pub const HASH_EVERY: u64 = 20;

/// Refuse to read any message bigger than this (guards against garbage).
const MAX_MESSAGE_BYTES: u32 = 64 * 1024 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum ClientMsg {
    /// First message on every connection. `rules` is the sender's
    /// [`sim::RULES_ID`]; see [`check_join`] for why both numbers are here.
    Hello {
        name: String,
        protocol: u32,
        rules: String,
    },
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

/// Whether a peer saying [`ClientMsg::Hello`] may join, and if not, the
/// sentence to refuse it with (ASSA-40).
///
/// **TWO QUESTIONS, ASKED IN THIS ORDER.** Can we understand each other's
/// messages (`protocol`), and are we playing the same game (`rules`)? The
/// second is the one that bit us: #47 changed a single tuning constant, so
/// every derived stat changed, and the relay running since before it spoke
/// protocol 6 exactly like its clients. Nothing diverges while a player only
/// walks and reads; the first mined unit is worth different work, the hash
/// check fires twenty ticks later, and the client says the session is
/// unrecoverable. One rebuild, an hour and a half, and a held playtest.
///
/// **THE WORDING LIVES HERE AND NOWHERE ELSE** so the relay, `sim-cli` and
/// the Godot client cannot each invent their own. It names both identities,
/// because "your build is wrong" without saying which build is useless, and
/// it ends in the only action that fixes it. A stranger reading it should not
/// need to know what a lockstep peer is.
pub fn check_join(protocol: u32, rules: &str) -> Result<(), String> {
    if protocol != PROTOCOL_VERSION {
        // **THE SAME THREE THINGS THE RULES SENTENCE SAYS** (Game Director,
        // ASSA-77): which build the host is, which build to fetch, and that
        // nothing is wrong with the player's machine. A stranger meeting this
        // across a protocol bump has no terminal and no way to tell "the host
        // is newer" from "the host is down" or "my wifi is broken", and the
        // build identity is the one thing they can act on.
        return Err(format!(
            "This host speaks protocol v{PROTOCOL_VERSION} and your client speaks \
             v{protocol}, so the two builds cannot talk to each other at all. \
             Nothing is wrong with your machine or your network. Download the \
             build that matches this host: {RULES_ID}"
        ));
    }
    if rules != RULES_ID {
        return Err(format!(
            "This host runs game rules {RULES_ID} but your client was built from \
             rules {rules}. You would both play a different game and desync \
             within a few seconds. Download the build that matches this host: \
             {RULES_ID}"
        ));
    }
    Ok(())
}

/// What can be read out of a connection's first frame **without knowing which
/// protocol wrote it**.
///
/// **THIS SHAPE IS FROZEN AND MUST STAY PARSEABLE FOR EVERY BUILD THAT EVER
/// SHIPPED** (ASSA-77). The Game Director pointed the board's own downloaded
/// build at the host the decision record names and got
/// `failed to fill whole buffer`: a protocol-6 `Hello` carries no `rules`
/// field, so today's relay could not deserialise it into [`ClientMsg`], the
/// reader thread ended, and the socket closed **with nothing sent**. The
/// sentence we are proud of only worked between builds that could already
/// talk.
///
/// Every field is optional and nothing is required, which is the whole point:
/// a frame from the future may carry fields this struct has never heard of and
/// a frame from the past may be missing all of them. The only contract is the
/// one every build has kept since protocol 1 — *the first frame is a
/// length-prefixed JSON object with a `Hello` member* — and
/// `a_protocol_6_hello_is_still_readable` pins it against a hand-written
/// historical frame rather than against anything today's code can produce.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Greeting {
    pub protocol: Option<u32>,
    pub rules: Option<String>,
    pub name: Option<String>,
}

/// Read a first frame for whatever it will give up. Never fails: a frame this
/// cannot read at all becomes an empty [`Greeting`], which still earns the
/// player a sentence.
pub fn greeting(frame: &[u8]) -> Greeting {
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(frame) else {
        return Greeting::default();
    };
    // Externally tagged: `{"Hello": {...}}`. A future build could rename the
    // variant, so fall back to the object itself rather than giving up.
    let body = value.get("Hello").unwrap_or(&value);
    Greeting {
        protocol: body
            .get("protocol")
            .and_then(serde_json::Value::as_u64)
            .and_then(|n| u32::try_from(n).ok()),
        rules: body
            .get("rules")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
        name: body
            .get("name")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
    }
}

/// The sentence for a first frame this build cannot read as a [`ClientMsg`].
///
/// **ALWAYS A SENTENCE, NEVER A DROPPED SOCKET.** Where the greeting explains
/// itself — a protocol we do not speak, rules we do not share — the wording is
/// [`check_join`]'s, because two wordings for one condition is how hosts
/// drift. Where it does not, the player still gets the three things they need.
///
/// A greeting with no `rules` is NOT accused of a rules mismatch: an old build
/// that never had the field would otherwise be told its rules are wrong when
/// the real answer is its protocol. Passing this host's own id keeps the
/// rules clause silent so only the true complaint is made.
pub fn refuse_unreadable(g: &Greeting) -> String {
    if let Some(protocol) = g.protocol {
        if let Err(why) = check_join(protocol, g.rules.as_deref().unwrap_or(RULES_ID)) {
            return why;
        }
    }
    format!(
        "This host could not read your client's first message. Nothing is wrong \
         with your machine or your network: the two builds disagree about how to \
         talk to each other. Download the build that matches this host: {RULES_ID}"
    )
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

/// Read one length-prefixed frame as bytes, without deciding what it means.
///
/// Separate from [`read_msg`] so a host can answer a frame it cannot parse
/// (ASSA-77): the framing is the one part of this protocol that has never
/// changed, so bytes are readable across any version gap even when their
/// contents are not.
pub fn read_frame<R: Read>(r: &mut R) -> io::Result<Vec<u8>> {
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
    Ok(body)
}

/// Read one length-prefixed JSON message. Blocks until it arrives.
pub fn read_msg<R: Read, T: DeserializeOwned>(r: &mut R) -> io::Result<T> {
    let body = read_frame(r)?;
    serde_json::from_slice(&body).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use sim::{SystemCommand, TilePos};

    /// **A FRAME FROM A BUILD THAT SHIPPED, WRITTEN BY HAND.** This is a
    /// protocol-6 `Hello` exactly as `sim-net` serialised it before ASSA-40
    /// added `rules` — copied out of the source at `2ff1466^`, not generated by
    /// anything in this tree, because a frame today's code can produce is not
    /// evidence about a build that is already on someone's disk.
    ///
    /// It is the frame the Game Director actually sent at the #38 bench, and
    /// the one today's `ClientMsg` cannot deserialise.
    const PROTOCOL_6_HELLO: &str = r#"{"Hello":{"name":"ada","protocol":6}}"#;

    #[test]
    fn a_protocol_6_hello_is_still_readable_as_a_greeting() {
        // The premise, so this test says why it exists: today's ClientMsg
        // genuinely cannot read it. If that ever stops being true, the bug is
        // gone and this test should be read again rather than kept green.
        assert!(
            serde_json::from_str::<ClientMsg>(PROTOCOL_6_HELLO).is_err(),
            "a protocol-6 hello is supposed to be unparseable as a ClientMsg; \
             that is the whole reason `greeting` exists"
        );

        let g = greeting(PROTOCOL_6_HELLO.as_bytes());
        assert_eq!(g.protocol, Some(6), "the protocol is the actionable field");
        assert_eq!(g.name.as_deref(), Some("ada"));
        assert_eq!(g.rules, None, "protocol 6 had no rules field; that is the point");
    }

    #[test]
    fn an_unreadable_frame_still_earns_a_sentence() {
        // 1. The real case: an old protocol, no rules field.
        let old = refuse_unreadable(&greeting(PROTOCOL_6_HELLO.as_bytes()));
        assert!(old.contains("v6") && old.contains(&PROTOCOL_VERSION.to_string()), "{old}");
        assert!(
            old.contains(RULES_ID),
            "it must name the build to download, like the rules sentence does: {old}"
        );
        assert!(
            old.contains("Nothing is wrong with your machine"),
            "a stranger cannot tell this from a dead host or bad wifi: {old}"
        );
        // AND IT MUST NOT ACCUSE THEM OF A RULES MISMATCH. A build that never
        // had the field would otherwise be told its rules are wrong when the
        // real answer is its protocol.
        assert!(
            !old.contains("runs game rules"),
            "the complaint must be the true one: {old}"
        );

        // 2. Nothing readable at all: still three things, never a dropped
        //    socket. This is the arm a greeting-shaped test would miss.
        for junk in [b"not json at all".as_slice(), b"{}".as_slice(), b"".as_slice()] {
            let said = refuse_unreadable(&greeting(junk));
            assert!(said.contains(RULES_ID), "{said}");
            assert!(said.contains("Nothing is wrong with your machine"), "{said}");
        }

        // 3. **OUR PROTOCOL, NO RULES FIELD.** This arm exists because a
        //    mutation found it: swapping `unwrap_or(RULES_ID)` for
        //    `unwrap_or("")` reddened NOTHING, since `check_join` answers the
        //    protocol question first and never reads the rules argument when
        //    the protocol already disagrees. The two arms were mutually
        //    exclusive by construction and my tests only reached one of them.
        //    Reachable for real: a build on this protocol that renames a field,
        //    or a frame damaged after its protocol number. It must be told the
        //    truth -- "I could not read it" -- not that its rules are wrong.
        let ours_no_rules = refuse_unreadable(&Greeting {
            protocol: Some(PROTOCOL_VERSION),
            rules: None,
            name: Some("ada".into()),
        });
        assert!(
            !ours_no_rules.contains("runs game rules"),
            "a missing rules field is not a rules mismatch: {ours_no_rules}"
        );
        assert!(
            ours_no_rules.contains("could not read your client's first message"),
            "{ours_no_rules}"
        );

        // 4. NON-VACUITY: a greeting that agrees about everything reaches the
        //    fallback rather than borrowing check_join's complaint, so this
        //    function cannot be passing arm 1 by accident.
        let same = refuse_unreadable(&Greeting {
            protocol: Some(PROTOCOL_VERSION),
            rules: Some(RULES_ID.to_string()),
            name: Some("ada".into()),
        });
        assert!(
            same.contains("could not read your client's first message"),
            "{same}"
        );
    }

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
