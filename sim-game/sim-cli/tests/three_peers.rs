//! THE THREE-PEER RELAY SESSION (ASSA-8): one relay, three `sim-cli` peers,
//! and the demo loop played **once between them**.
//!
//! `first_plate.rs` proves one player can play the loop. This proves the game
//! is the same game when three people share a world — which is a different
//! claim, and the only one that can catch a rule that is deterministic in one
//! process and not across three.
//!
//! **The co-op split is the point.** Nothing here is three solos run in
//! parallel (Game Director's ruling on this item): ada assays the species and
//! mines the ore, bo builds and fires the smelter, cy takes the refined out of
//! bo's smelter and builds the pick and the drill, and **ada empties the drill
//! cy planted**. Every hand-off goes through the world, because the world is
//! the only thing the three of them share.
//!
//! **What it proves, and how:**
//!
//! - Every peer's `(tick, hash)` is compared **against the other peers**, not
//!   against the relay's silence. The relay only speaks up on a mismatch, so a
//!   session where the hash check never ran looks exactly like a clean one.
//! - The **relay's own world** gets a vote too, read out of its autosave, so
//!   "the host agrees" is a measurement rather than an absence.
//! - The three transcripts must carry the same event at the **same tick**, for
//!   the two moments with no rng in them at all (the stall, the wear-out) and
//!   for the placement.
//!
//! **What it does not prove:** a placement that BREAKS. The seed is chosen so
//! the drill fits its budget, so `break_apart` — the one rng draw in the loop —
//! never runs here. Limpet's Godot probe covers that case across three peers
//! (PR #36); this one covers the case where the machine survives and produces.

mod common;

use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use sim::assembly::{Assembly, Mount, Part, PartKind};
use sim::item::{Item, ItemKind};
use sim::tuning::{PICK_WEAR_PER_SWING, YIELD_BY_GRADE};
use sim::{OreDeposit, TilePos, World};

const ADA: usize = 0;
const BO: usize = 1;
const CY: usize = 2;
const NAMES: [&str; 3] = ["ada", "bo", "cy"];

/// The relay's clock, at its ceiling: the loop is roughly 700 ticks and this
/// test is a wall-clock test whether it likes it or not.
const TPS: u32 = 60;
/// How long one stage may take before the session is called broken. Generous:
/// a slow CI box running three sims and a relay is not a failure.
const STAGE_TIMEOUT: Duration = Duration::from_secs(120);
/// Ore ada mines for the smelter, and refined the party needs: a pick is 3
/// (handle 2 + head 1) and a drill is 8 (frame 5 + head 1 + hopper 2).
const ADA_ORE: u32 = 14;
const REFINED_NEEDED: u32 = 11;
/// Ore bo mines for the smelter's body (5) and to burn (20).
const SMELTER_ORE: u32 = 5;
const FUEL_ORE: u32 = 20;
/// A pick with a weaker head wears out sooner, and this session runs one to
/// destruction. 25 swings is about 2 seconds of mining; a 200-swing pick would
/// be a minute of nothing happening.
const MAX_SWINGS: u32 = 25;

// ---------------------------------------------------------------------------
// The session
// ---------------------------------------------------------------------------

#[test]
fn three_peers_on_one_relay_close_the_demo_loop_once_between_them() {
    let starter = common::demo_seed(short_enough_to_run_to_destruction);
    let c = starter.codes();
    let (m, f) = (starter.material.center, starter.fuel.center);
    let ms = starter.world.species(starter.material.species);
    let species = ms.name().to_string();

    let mut party = Party::start(starter.seed);

    // Everyone is in, and everyone's world holds all three players. Note what
    // this does NOT wait for: a "joined" event. Three peers that connect
    // within the same tick are all welcomed with a snapshot taken AFTER their
    // own joins were stepped, so nobody is ever told about anybody — the
    // players are simply already there. A peer that never sees the other two
    // is not in this session, whatever its hash says.
    for (i, name) in NAMES.iter().enumerate() {
        party.until(i, "joined", |l| says(l, &format!("as {name} (player")));
    }
    for i in 0..3 {
        party.until(i, "has all three players", |l| {
            says(l, "Players in world: 3")
        });
    }

    // --- ada and bo walk to the ore; cy goes to wait where the smelter will be
    party.send(ADA, &format!("goto {} {}", m.x, m.y));
    party.send(BO, &format!("goto {} {}", m.x, m.y));
    party.send(CY, &format!("goto {} {}", f.x, f.y));
    // Every walk waits on where the peer IS, never on an "arrived" line:
    // ada and cy each visit the ore twice, so a transcript that has said
    // "arrived at (73, 42)" once will say it before the second walk starts.
    party.until(ADA, "arrived at the ore", |l| standing_at(l, m));
    party.until(BO, "arrived at the ore", |l| standing_at(l, m));
    party.until(CY, "arrived at the fuel", |l| standing_at(l, f));

    // --- ada assays, which makes the sheet exact FOR EVERYONE.
    party.send(ADA, "assay");
    party.until(ADA, "assayed the species", |l| says(l, "you assayed"));
    party.until(CY, "saw ada's assay", |l| {
        says(l, &format!("ada assayed {species}"))
    });

    // --- bo mines the smelter's body while ada mines the ore to smelt.
    party.send(BO, "mine");
    party.until(BO, "mined the smelter's ore", |l| {
        carrying(l, &species) >= SMELTER_ORE
    });
    party.send(BO, "stop");
    party.send(BO, &format!("craft smelter {}", c.ore));
    party.until(BO, "crafted the smelter", |l| says(l, "you crafted 1"));

    party.send(ADA, "mine");
    party.until(ADA, "mined the ore to smelt", |l| {
        carrying(l, &species) >= ADA_ORE
    });
    party.send(ADA, "stop");

    // --- bo plants the smelter beside the fuel and fires it.
    party.send(BO, &format!("goto {} {}", f.x, f.y));
    party.until(BO, "arrived at the fuel", |l| standing_at(l, f));
    party.send(BO, "place smelter");
    party.until(BO, "placed the smelter", |l| says(l, "as building 0"));
    party.send(BO, "mine");
    party.until(BO, "mined the fuel", |l| {
        carrying(l, &fuel_species(&starter)) >= FUEL_ORE
    });
    party.send(BO, "stop");
    party.send(BO, &format!("insert 0 fuel {} {FUEL_ORE}", c.fuel_ore));

    // --- ada carries her ore to bo's smelter. This is the hand-off: she
    // cannot give it to him, so the building is where the two of them meet.
    party.send(ADA, &format!("goto {} {}", f.x, f.y));
    party.until(ADA, "reached the smelter", |l| standing_at(l, f));
    party.send(ADA, &format!("insert 0 ore {} {ADA_ORE}", c.ore));
    party.until(CY, "saw the smelter running", |l| {
        count(l, "building 0 smelted") >= REFINED_NEEDED as usize
    });

    // --- cy takes somebody else's refined out of somebody else's smelter.
    party.send(CY, "take 0");
    party.until(CY, "took the refined", |l| {
        took(l, "building 0") >= REFINED_NEEDED
    });

    // --- cy builds the pick: one `assemble`, a held frame plus a head.
    party.send(CY, &format!("make handle {}", c.refined));
    party.send(CY, &format!("make head {}", c.refined));
    party.until(CY, "made the pick's parts", |l| {
        says(l, &format!("you made 1 x {species} handle"))
            && says(l, &format!("you made 1 x {species} head"))
    });
    party.send(CY, &format!("assemble handle:{} head:{}", c.part, c.part));
    party.until(CY, "assembled the pick", |l| says(l, "handle("));
    party.send(CY, "equip 0");
    party.until(CY, "equipped the pick", |l| says(l, "you equipped a tool"));

    // --- and runs it to destruction. No rng on this path at all: wear is
    // certain, so every peer must see it at the same tick.
    party.send(CY, &format!("goto {} {}", m.x, m.y));
    party.until(CY, "got back to the ore", |l| standing_at(l, m));
    party.send(CY, "mine");
    party.until(CY, "wore the pick out", |l| says(l, "wore out"));
    party.send(CY, "stop");

    // --- the drill: the SAME command, with a planted frame and a hopper.
    party.send(CY, &format!("make frame {}", c.refined));
    party.send(CY, &format!("make head {}", c.refined));
    party.send(CY, &format!("make hopper {}", c.refined));
    party.until(CY, "made the drill's parts", |l| {
        says(l, &format!("you made 1 x {species} frame"))
            && says(l, &format!("you made 1 x {species} hopper"))
            && count(l, &format!("you made 1 x {species} head")) >= 2
    });
    party.send(
        CY,
        &format!(
            "assemble frame:{} head:{} hopper:{}",
            c.part, c.part, c.part
        ),
    );
    party.until(CY, "assembled the drill", |l| says(l, "frame("));
    party.send(CY, &format!("plant 0 {} {}", m.x, m.y));
    party.until(CY, "planted the drill", |l| says(l, "planted machine 1"));

    // --- it fills its hopper and stops, which is the only thing that tells
    // the player to come and empty it.
    party.until(ADA, "saw the drill fill up", |l| says(l, "is full at"));

    // --- ada closes the loop cy opened. Once, by the party.
    party.send(ADA, &format!("goto {} {}", m.x, m.y));
    party.until(ADA, "walked to the drill", |l| standing_at(l, m));
    party.send(ADA, "take 1");
    party.until(ADA, "emptied the drill", |l| took(l, "building 1") > 0);
    party.send(ADA, "inv");
    party.until(ADA, "listed its inventory", |l| says(l, "Carrying "));

    // One last pump burst, so the hash samples cover the end of the session
    // and not only up to the last thing anybody waited for.
    for _ in 0..12 {
        party.pump();
    }

    // -----------------------------------------------------------------------
    // What the session proved
    // -----------------------------------------------------------------------
    let diagnostics = party.diagnostics();
    let ada = party.lines(ADA);
    let bo = party.lines(BO);
    let cy = party.lines(CY);
    let relay = party.relay_log();

    // Nothing was refused. A rejected command would leave a later stage
    // waiting, but it can also pass silently (a `stop` nobody needed), and a
    // session with a refusal in it is not the session this test describes.
    //
    // **BOTH WORDINGS, SO THIS CANNOT GO BLIND THE NEXT TIME THE SENTENCE IS
    // REWORDED.** ASSA-70 moved it from "`insert ...` was rejected" to "putting
    // ... was refused", and a check for the old phrase alone would have gone on
    // passing while covering nothing.
    for (i, lines) in [&ada, &bo, &cy].iter().enumerate() {
        for phrase in ["was refused", "was rejected"] {
            assert!(
                !says(lines, phrase),
                "{} had a command refused ({phrase})\n{diagnostics}",
                NAMES[i]
            );
        }
    }

    // --- LOCKSTEP, peer against peer.
    let mut samples: BTreeMap<u64, Vec<(&str, u64)>> = BTreeMap::new();
    for (i, lines) in [&ada, &bo, &cy].iter().enumerate() {
        for (tick, hash) in hashes(lines) {
            samples.entry(tick).or_default().push((NAMES[i], hash));
        }
    }
    let shared: Vec<_> = samples.iter().filter(|(_, v)| v.len() >= 2).collect();
    let all_three = shared.iter().filter(|(_, v)| v.len() == 3).count();
    for (tick, reports) in &shared {
        let (_, first) = reports[0];
        assert!(
            reports.iter().all(|(_, h)| *h == first),
            "peers disagree at tick {tick}: {reports:?}\n{diagnostics}"
        );
    }
    assert!(
        shared.len() >= 25 && all_three >= 8,
        "not enough overlapping samples to call this lockstep: {} ticks with \
         two or more peers, {all_three} with all three\n{diagnostics}",
        shared.len()
    );
    // The agreement has to reach the END of the session. Three peers that
    // match for the first 50 ticks and are never compared again would satisfy
    // every assertion above.
    let last_event_tick = [&ada, &bo, &cy]
        .iter()
        .filter_map(|l| tick_of(l, "is full at"))
        .max()
        .expect("the stall is asserted above");
    let last_agreed = shared.last().map(|(t, _)| **t).unwrap_or(0);
    assert!(
        last_agreed > last_event_tick,
        "the peers stopped being compared at tick {last_agreed}, before the \
         drill filled at tick {last_event_tick}\n{diagnostics}"
    );

    // --- THE HOST agrees too, in its own words: its autosave, hashed.
    let host = party.host_hashes.clone();
    let mut checked = 0;
    for (tick, hash) in &host {
        if let Some(reports) = samples.get(tick) {
            for (name, peer_hash) in reports {
                assert_eq!(
                    peer_hash, hash,
                    "{name} and the relay's own world disagree at tick {tick}\n{diagnostics}"
                );
                checked += 1;
            }
        }
    }
    assert!(
        checked >= 3,
        "the relay's own world was never compared against a peer at the same \
         tick ({} host samples, {} peer ticks)\n{diagnostics}",
        host.len(),
        samples.len()
    );
    assert!(
        !says(&relay, "DESYNC"),
        "the relay called a desync\n{diagnostics}"
    );

    // --- THE SAME EVENT AT THE SAME TICK. Hashes agreeing says the worlds
    // match; this says the three players were told the same story about it.
    for needle in ["planted machine 1", "is full at", "wore out"] {
        let ticks: Vec<Option<u64>> = [&ada, &bo, &cy]
            .iter()
            .map(|l| tick_of(l, needle))
            .collect();
        assert!(
            ticks.iter().all(|t| t.is_some()) && ticks.iter().all(|t| *t == ticks[0]),
            "{needle:?} did not reach all three peers on one tick: {ticks:?}\n{diagnostics}"
        );
    }

    // --- THE LOOP CLOSED, AND NOT BY ONE PLAYER. Each clause of ruling 9,
    // read from the transcript of somebody who did not do it.
    for (lines, who, expected) in [
        (&cy, "cy", format!("ada assayed {species}")),
        (&cy, "cy", "ada mined".to_string()),
        (&cy, "cy", "bo placed".to_string()),
        (&ada, "ada", "bo placed".to_string()),
        (&ada, "ada", "cy equipped a tool".to_string()),
        (&ada, "ada", "cy's".to_string()), // cy's pick wore out, in ada's words
        (&ada, "ada", "cy planted machine 1".to_string()),
        (&bo, "bo", "machine 1 mined".to_string()),
    ] {
        assert!(
            says(lines, &expected),
            "{who} never saw {expected:?} — then this was not one shared \
             world\n{diagnostics}"
        );
    }
    // ada took the drill's ore, and it is hers at the end. The drill was
    // planted by cy out of refined that came from bo's smelter out of ore ada
    // mined: four hands, one loop, closed once.
    let carried = ada
        .iter()
        .rev()
        .find(|l| l.starts_with("Carrying "))
        .expect("asserted above")
        .clone();
    assert!(
        carried.contains(&format!("{species} ore")),
        "the loop closes with the drill's ore in ada's hands: {carried}\n{diagnostics}"
    );
    // And the possessive reads like English for both of them, which is the
    // bug this session found in my own ASSA-6 wording.
    assert!(
        says(&cy, "your") && !says(&cy, "you's"),
        "cy's own tool should wear out in the second person\n{diagnostics}"
    );

    // The relay saw all three play: it logs every command it ordered.
    for name in NAMES {
        assert!(
            says(&relay, &format!("{name}: ")),
            "the relay never ordered a command from {name}\n{diagnostics}"
        );
    }

    println!(
        "three peers, seed {} ({species}), {} ticks of overlap ({all_three} with all three), \
         {checked} host comparisons, {} relay lines",
        starter.seed,
        shared.len(),
        relay.len()
    );
}

/// Beyond [`common::supports_the_loop`]: this session runs the pick to
/// destruction and fills the drill's hopper, so the seed has to make both
/// happen inside a bounded wall-clock, and the deposit has to survive all of
/// it — the party's ore, the pick's whole life, and the drill's hopper.
fn short_enough_to_run_to_destruction(w: &World, m: &OreDeposit, _f: &OreDeposit) -> bool {
    let grade = m.grade();
    let refined = Item::new(ItemKind::Refined, m.species, grade);
    let part = |kind| Part {
        kind,
        material: refined,
    };
    let head = part(PartKind::Head);
    let pick = Assembly::new(part(PartKind::Frame(Mount::Held)), vec![head]);
    let drill = Assembly::new(
        part(PartKind::Frame(Mount::Planted)),
        vec![head, part(PartKind::Hopper)],
    );
    let swings = pick
        .stats(&w.species)
        .durability
        .div_ceil(PICK_WEAR_PER_SWING);
    let per_swing = YIELD_BY_GRADE[grade as usize];
    let ore_needed =
        ADA_ORE + SMELTER_ORE + (swings + drill.stats(&w.species).capacity) * per_swing;
    swings <= MAX_SWINGS && m.amount >= ore_needed
}

fn fuel_species(s: &common::Starter) -> String {
    s.world.species(s.fuel.species).name().to_string()
}

// ---------------------------------------------------------------------------
// Reading a transcript
// ---------------------------------------------------------------------------

fn says(lines: &[String], needle: &str) -> bool {
    lines.iter().any(|l| l.contains(needle))
}

fn count(lines: &[String], needle: &str) -> usize {
    lines.iter().filter(|l| l.contains(needle)).count()
}

/// Every `(tick, hash)` this peer has reported, from its `status` lines.
fn hashes(lines: &[String]) -> Vec<(u64, u64)> {
    lines
        .iter()
        .filter_map(|l| {
            let tick = field(l, "tick ")?.parse().ok()?;
            let hash = u64::from_str_radix(field(l, "hash ")?, 16).ok()?;
            Some((tick, hash))
        })
        .collect()
}

/// One ` · `-separated field of a summary line, without its label.
fn field<'a>(line: &'a str, label: &str) -> Option<&'a str> {
    line.split(" · ")
        .find_map(|part| part.strip_prefix(label))
        .map(str::trim)
}

/// How much of `species` this peer last said it was carrying, out of its own
/// mining lines: "you mined 2 Kiomase ore (B) (carrying 14, 538 left ...)".
fn carrying(lines: &[String], species: &str) -> u32 {
    lines
        .iter()
        .filter(|l| l.contains("you mined") && l.contains(species))
        .filter_map(|l| {
            l.split("(carrying ")
                .nth(1)?
                .split(',')
                .next()?
                .parse()
                .ok()
        })
        .max()
        .unwrap_or(0)
}

/// How much this peer took out of `building`, at most, in one go.
fn took(lines: &[String], building: &str) -> u32 {
    lines
        .iter()
        .filter(|l| l.contains("you took") && l.contains(building))
        .filter_map(|l| l.split("you took ").nth(1)?.split(' ').next()?.parse().ok())
        .max()
        .unwrap_or(0)
}

/// Where this peer's `status` last said it was: "You: ada (player 1) at (57, 51)".
/// A position is STATE, which is why the walks wait on it instead of on the
/// arrival event — an event is history and history repeats.
fn position(lines: &[String]) -> Option<(i32, i32)> {
    lines.iter().rev().find_map(|l| {
        let (x, y) = l
            .strip_prefix("You: ")?
            .split(" at (")
            .nth(1)?
            .trim_end_matches(')')
            .split_once(", ")?;
        Some((x.trim().parse().ok()?, y.trim().parse().ok()?))
    })
}

fn standing_at(lines: &[String], pos: TilePos) -> bool {
    position(lines) == Some((pos.x, pos.y))
}

/// The tick of the first line matching `needle`, from its `tick N · ` prefix.
fn tick_of(lines: &[String], needle: &str) -> Option<u64> {
    lines.iter().find(|l| l.contains(needle)).and_then(|l| {
        l.trim()
            .strip_prefix("tick ")?
            .split(' ')
            .next()?
            .parse()
            .ok()
    })
}

// ---------------------------------------------------------------------------
// The processes
// ---------------------------------------------------------------------------

struct Peer {
    child: Child,
    stdin: ChildStdin,
    out: Arc<Mutex<Vec<String>>>,
}

struct Party {
    peers: Vec<Peer>,
    relay: Child,
    log: Arc<Mutex<Vec<String>>>,
    saves: PathBuf,
    save: PathBuf,
    /// The relay's own world, read out of its autosave: tick -> hash.
    host_hashes: BTreeMap<u64, u64>,
    pumps: u64,
}

impl Party {
    fn start(seed: u64) -> Party {
        let port = free_port();
        let saves =
            std::env::temp_dir().join(format!("assay-three-peers-{}-{seed}", std::process::id()));
        std::fs::create_dir_all(&saves).expect("a temp saves dir");
        let (relay, log) = spawn_relay(seed, port, &saves);
        let peers = NAMES.iter().map(|n| spawn_peer(n, port, &saves)).collect();
        Party {
            peers,
            relay,
            log,
            save: saves.join(format!("world-{seed}.json")),
            saves,
            host_hashes: BTreeMap::new(),
            pumps: 0,
        }
    }

    fn send(&mut self, who: usize, line: &str) {
        let peer = &mut self.peers[who];
        writeln!(peer.stdin, "{line}").expect("the peer is still listening");
        peer.stdin.flush().expect("the peer is still listening");
    }

    /// Ask every peer where it is, and read the relay's own world. This is the
    /// only clock in this test: everything waits by pumping.
    fn pump(&mut self) {
        for i in 0..self.peers.len() {
            self.send(i, "status");
        }
        thread::sleep(Duration::from_millis(50));
        self.pumps += 1;
        // The autosave is rewritten every 20 ticks; a read that lands mid-write
        // just fails to parse, and the next one will not.
        if self.pumps.is_multiple_of(4)
            && let Ok(w) = World::load_json(&self.save)
        {
            self.host_hashes.insert(w.tick, w.state_hash());
        }
    }

    fn until(&mut self, who: usize, what: &str, done: impl Fn(&[String]) -> bool) {
        let deadline = Instant::now() + STAGE_TIMEOUT;
        loop {
            if done(&self.lines(who)) {
                return;
            }
            assert!(
                Instant::now() < deadline,
                "{} never {what} ({STAGE_TIMEOUT:?})\n{}",
                NAMES[who],
                self.diagnostics()
            );
            self.pump();
        }
    }

    fn lines(&self, who: usize) -> Vec<String> {
        self.peers[who].out.lock().unwrap().clone()
    }

    fn relay_log(&self) -> Vec<String> {
        self.log.lock().unwrap().clone()
    }

    /// Everything a reader needs when this test fails, with the `status` spam
    /// taken out: what each peer was told, and what the relay did.
    fn diagnostics(&self) -> String {
        let mut s = String::from("\n=== relay ===\n");
        s.push_str(&tail(&self.relay_log(), 60).join("\n"));
        for (i, name) in NAMES.iter().enumerate() {
            s.push_str(&format!("\n=== {name} ===\n"));
            let lines = self.lines(i);
            let events: Vec<String> = lines.iter().filter(|l| !is_status(l)).cloned().collect();
            s.push_str(&tail(&events, 60).join("\n"));
        }
        s
    }
}

/// The six lines `status` prints. They are the hash samples, and they would
/// bury everything else in a failure message.
fn is_status(line: &str) -> bool {
    [
        "seed ",
        "You: ",
        "Players in world",
        "Depleted deposits",
        "Host: ",
    ]
    .iter()
    .any(|p| line.starts_with(p))
}

fn tail(lines: &[String], n: usize) -> &[String] {
    &lines[lines.len().saturating_sub(n)..]
}

impl Drop for Party {
    fn drop(&mut self) {
        for peer in &mut self.peers {
            let _ = peer.child.kill();
            let _ = peer.child.wait();
        }
        let _ = self.relay.kill();
        let _ = self.relay.wait();
        let _ = std::fs::remove_dir_all(&self.saves);
    }
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .expect("a free port")
        .local_addr()
        .expect("its address")
        .port()
}

/// `sim-relay` lives beside `sim-cli` in the target directory, and this builds
/// it EVERY time rather than only when it is missing.
///
/// That is not caution, it is a bug I hit: `CARGO_BIN_EXE_` only names
/// binaries of this package, so `cargo test -p sim-cli` never rebuilds the
/// relay. I proved the host comparison below by breaking the relay's own
/// world — and the test passed, because it had spawned the previous relay
/// binary. It failed the moment I rebuilt by hand. A test that runs last
/// week's host is not testing this week's host, and it says nothing while it
/// does it. The rebuild costs a fraction of a second when nothing changed.
fn relay_bin() -> PathBuf {
    let status = Command::new(env!("CARGO"))
        .args(["build", "--quiet", "-p", "sim-relay"])
        .current_dir(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .expect("sim-game"),
        )
        .status()
        .expect("cargo runs");
    assert!(status.success(), "could not build sim-relay");
    Path::new(env!("CARGO_BIN_EXE_sim-cli"))
        .with_file_name(format!("sim-relay{}", std::env::consts::EXE_SUFFIX))
}

fn spawn_relay(seed: u64, port: u16, saves: &Path) -> (Child, Arc<Mutex<Vec<String>>>) {
    let mut child = Command::new(relay_bin())
        .args([
            &seed.to_string(),
            "--port",
            &port.to_string(),
            "--tps",
            &TPS.to_string(),
            "--fresh",
        ])
        .env("R2TS_SAVES_DIR", saves)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("sim-relay starts");
    let log = collect(child.stdout.take().expect("piped"));
    let _ = collect(child.stderr.take().expect("piped"));

    // Wait for the port rather than sleeping on faith.
    let deadline = Instant::now() + Duration::from_secs(20);
    while TcpStream::connect(("127.0.0.1", port)).is_err() {
        assert!(
            Instant::now() < deadline,
            "the relay never listened on {port}: {:?}",
            log.lock().unwrap()
        );
        thread::sleep(Duration::from_millis(50));
    }
    (child, log)
}

fn spawn_peer(name: &str, port: u16, saves: &Path) -> Peer {
    let mut child = Command::new(env!("CARGO_BIN_EXE_sim-cli"))
        .args([
            "--connect",
            &format!("127.0.0.1:{port}"),
            "--name",
            name,
            "--plain",
        ])
        .env("R2TS_SAVES_DIR", saves)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| panic!("sim-cli starts for {name}: {e}"));
    let out = collect(child.stdout.take().expect("piped"));
    let stdin = child.stdin.take().expect("piped");
    // Errors belong in the same transcript as everything else: a peer that
    // died says so on stderr, and the assertion that times out should show it.
    let errors = collect(child.stderr.take().expect("piped"));
    let merged = Arc::clone(&out);
    thread::spawn(move || {
        loop {
            thread::sleep(Duration::from_millis(200));
            let mut taken = errors.lock().unwrap();
            if !taken.is_empty() {
                merged.lock().unwrap().extend(taken.drain(..));
            }
        }
    });
    Peer { child, stdin, out }
}

/// Read a child's stream into a shared list of lines, forever.
fn collect(stream: impl std::io::Read + Send + 'static) -> Arc<Mutex<Vec<String>>> {
    let lines = Arc::new(Mutex::new(Vec::new()));
    let sink = Arc::clone(&lines);
    thread::spawn(move || {
        for line in BufReader::new(stream).lines().map_while(Result::ok) {
            sink.lock().unwrap().push(line);
        }
    });
    lines
}
