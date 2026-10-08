//! Headless r2ts host.
//!
//!     cargo run -p sim-relay                  # host world 42 on port 7777
//!     cargo run -p sim-relay -- 7 --port 8000 --tps 20
//!     cargo run -p sim-relay -- 42 --fresh    # ignore the existing save
//!
//! The relay owns the clock. Every tick it gathers the commands clients sent,
//! puts them in one order, runs the sim itself, and broadcasts that tick's
//! inputs so every client can run the identical step. It also welcomes
//! joiners with a snapshot, compares clients' state hashes, and autosaves.

mod auth;

use std::collections::{BTreeMap, VecDeque};
use std::io::{BufReader, BufWriter, Write};
use std::net::{IpAddr, Ipv4Addr, Shutdown, TcpListener};
use std::path::{Path, PathBuf};
use std::process::exit;
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;
use std::time::{Duration, Instant};

use auth::{AccountId, Authenticator, DevAuthenticator};
use sim::{Event, Input, PlayerCommand, PlayerId, SystemCommand, World, step};
use sim_net::{
    ClientMsg, DEFAULT_PORT, Greeting, HASH_EVERY, PROTOCOL_VERSION, ServerMsg, TickBundle,
    read_frame, saves_dir, write_msg,
};

/// THE FIRST THING THIS PROCESS PRINTS, and a contract exactly like `LISTENING`
/// is: a client keys on this prefix, never on the words after it.
///
/// **IT EXISTS SO A DEAD CHILD CAN BE TOLD FROM A REFUSED ONE** (ASSA-120).
/// Limpet measured that a client which spawns this binary cannot learn whether
/// the exec happened: `OS.execute_with_pipe` hands back a live pid for a file
/// that is not executable and for a path that does not exist alike, Godot's own
/// complaint reached the child's stderr 3 times in 10 and then 0 in 9, and
/// `/bin/sh -c "exit 1"` — a process that really ran — leaves exactly as much
/// behind as a failed exec. So "macOS would not run it" was a reading, not a
/// fact, and a confident wrong diagnosis is worse than a vague true one.
///
/// This line makes it a fact: a child that died without it never reached this
/// crate's code. **Which is why it is printed before argument parsing, before
/// the save is opened and before the socket is bound** (Maren's one constraint,
/// ASSA-120). A marker printed after anything that can fail turns "ran but
/// could not bind" into "the system would not run it" — the same wrong
/// diagnosis one layer down. It therefore says nothing a running world knows:
/// the protocol and rules id are compile-time constants of this build, and
/// resumed-versus-created is knowable only after the save opens, so Maren ruled
/// it belongs beside `LISTENING` instead.
const RELAY_STARTED: &str = "RELAY STARTED";

const AUTOSAVE_EVERY: u64 = 20;
const DEFAULT_TPS: u32 = 10;
/// How many recent hashes to keep for checking client reports.
const HASH_HISTORY: usize = 64;

type ConnId = u64;

/// Everything the network threads tell the main loop.
enum NetEvent {
    Connected(ConnId, Sender<ServerMsg>, String),
    Message(ConnId, ClientMsg),
    /// A frame this build cannot read as a [`ClientMsg`], plus whatever the
    /// greeting gave up. **A connection we cannot understand is still a person
    /// waiting** (ASSA-77), so it is refused in words instead of dropped.
    Unreadable(ConnId, Greeting),
    Disconnected(ConnId),
}

struct Conn {
    out: Sender<ServerMsg>,
    addr: String,
    joined: Option<Joined>,
}

struct Joined {
    account: AccountId,
    player: PlayerId,
    name: String,
}

/// A connection waiting for `AddPlayer` to run before it can be welcomed.
struct PendingJoin {
    conn: ConnId,
    account: AccountId,
    name: String,
}

struct Options {
    seed: u64,
    port: u16,
    tps: u32,
    fresh: bool,
    /// **IS THE STALL THE MACHINE OR `run_tick`?** (ASSA-208) Print a timing
    /// summary every N ticks; 0 is off, which is every run nobody asked. The
    /// client measures bundle ARRIVALS and cannot tell a host that woke late
    /// from a host that worked long -- both read as a gap -- so the two numbers
    /// have to come from inside this loop.
    tick_stats: u32,
    /// Which interfaces to listen on. `0.0.0.0` is every one of them, which is
    /// what a relay people join over a network wants and what this has always
    /// done.
    ///
    /// **A SOLO RELAY MUST NOT BE REACHABLE FROM THE NETWORK** (Wren's ruling
    /// 2 on ASSA-106). `DevAuthenticator` trusts any well-formed name, so a
    /// single-player world started by a button on the join screen would
    /// otherwise sit open on the player's LAN under whatever name a stranger
    /// typed. Solo passes `127.0.0.1`.
    bind: IpAddr,
}

struct Relay {
    seed: u64,
    world: World,
    /// Which world slot each account plays. Saved next to the world so
    /// reconnecting gets you your character back.
    accounts: BTreeMap<AccountId, PlayerId>,
    conns: BTreeMap<ConnId, Conn>,
    auth: Box<dyn Authenticator>,
    /// Our own (tick, hash) pairs, to compare with what clients report.
    hashes: VecDeque<(u64, u64)>,
}

fn main() {
    // BEFORE EVERYTHING, INCLUDING THE ARGUMENTS. See `RELAY_STARTED`. The
    // flush is belt and braces — Rust line-buffers stdout, so the newline
    // already pushes it — but the whole value of this line is that it has left
    // the process before anything that could fail or hang, and that is worth a
    // syscall that costs nothing once per run.
    println!(
        "{RELAY_STARTED} protocol {PROTOCOL_VERSION} rules {}",
        sim_net::RULES_ID
    );
    let _ = std::io::stdout().flush();
    let opts = parse_args();
    let (world, accounts) = open_world(&opts);

    let listener = TcpListener::bind((opts.bind, opts.port)).unwrap_or_else(|e| {
        eprintln!("Could not listen on {}:{}: {e}", opts.bind, opts.port);
        exit(1);
    });
    // **THE ADDRESS WE ACTUALLY GOT, NOT THE ONE WE ASKED FOR.** `--port 0`
    // means "any free port", which is the only race-free way to get one: a
    // caller that picks a number, closes it and hands it over can lose the
    // port in between (`tests/join_refusal.rs` does exactly that and it
    // flakes). Printing `opts.port` would announce "port 0" and nobody could
    // join, so every line below reads this instead.
    let bound = listener.local_addr().unwrap_or_else(|e| {
        eprintln!("Listening, but could not read our own address: {e}");
        exit(1);
    });
    let local_only = bound.ip().is_loopback();
    let (events_tx, events_rx) = mpsc::channel();
    spawn_listener(listener, events_tx);

    println!(
        "Hosting world {} at tick {} on port {} ({} ticks/s)",
        opts.seed,
        world.tick,
        bound.port(),
        opts.tps
    );
    // ONE STABLE LINE A PARENT PROCESS CAN MATCH (ASSA-108, for ASSA-106's
    // "Play solo"). A client that spawns this relay has to know two things —
    // that it is up, and on which port — and the alternative is scraping the
    // prose above, which is written for a person and will be reworded. This
    // line is the contract: `LISTENING <addr>:<port>`, printed once, after the
    // socket is accepting and before the first tick.
    println!("LISTENING {bound}");
    // ASSA-40: so pairing a downloaded zip to a running host is reading, not
    // guessing. A peer on a different rules id is refused at join, with both
    // numbers named.
    println!(
        "Rules {} · protocol v{}",
        sim_net::RULES_ID,
        PROTOCOL_VERSION
    );
    println!("Saves: {}", saves_dir().display());
    println!("Players join with:");
    println!(
        "  this computer:  sim-cli --connect localhost:{} --name <name>",
        bound.port()
    );
    // **THE INSTRUCTIONS FOLLOW THE BIND.** A relay listening only on loopback
    // refuses every one of these routes, and telling somebody to forward a
    // port to a socket that will not answer is worse than saying nothing: it
    // sends them to their router. So on a local-only bind we say so instead of
    // printing two addresses that cannot work.
    if local_only {
        println!(
            "  nobody else:    this relay is listening on {} only",
            bound.ip()
        );
    } else {
        if let Some(ip) = lan_ip() {
            println!(
                "  same network:   sim-cli --connect {ip}:{} --name <name>",
                bound.port()
            );
        }
        println!(
            "  over the internet: use Tailscale or forward TCP port {} on your router",
            bound.port()
        );
    }

    let mut relay = Relay {
        seed: opts.seed,
        world,
        accounts,
        conns: BTreeMap::new(),
        auth: Box::new(DevAuthenticator),
        hashes: VecDeque::new(),
    };

    // Fixed-rate clock. If we fall far behind (machine slept), skip ahead
    // instead of running a burst of catch-up ticks.
    let interval = Duration::from_secs_f64(1.0 / f64::from(opts.tps));
    let mut stats = TickStats::new(opts.tick_stats);
    let mut next = Instant::now();
    let mut began = next;
    loop {
        next += interval;
        let now = Instant::now();
        if next > now {
            thread::sleep(next - now);
        } else if now - next > interval * 20 {
            next = now;
        }
        // THE TWO NUMBERS THE CLIENT CANNOT TELL APART, taken on either side of
        // the work: how late this tick STARTED against the time it was due, and
        // how long its own work took. A bundle arriving 250 ms after the last
        // one is the sum of these, and only one of them is ours to fix.
        let woke = Instant::now();
        let late = woke.saturating_duration_since(next);
        // AND THE GAP A PEER ACTUALLY SEES: start to start. Lateness alone
        // cannot say whether a late tick is followed by a normal one or by an
        // immediate catch-up, and that difference is the client's whole
        // problem -- a 200 ms gap and then two bundles at once is a dry frame
        // and then a full buffer, which is what ASSA-197's probe is fighting.
        let gap = woke.saturating_duration_since(began);
        began = woke;
        relay.run_tick(&events_rx);
        stats.record(
            late,
            gap,
            woke.elapsed(),
            relay.world.tick,
            relay.conns.len(),
        );
    }
}

impl Relay {
    fn log(&self, msg: impl AsRef<str>) {
        println!("[tick {}] {}", self.world.tick, msg.as_ref());
    }

    fn run_tick(&mut self, events: &Receiver<NetEvent>) {
        let mut commands = Vec::new();
        let mut pending = Vec::new();
        while let Ok(event) = events.try_recv() {
            match event {
                NetEvent::Connected(id, out, addr) => {
                    self.conns.insert(
                        id,
                        Conn {
                            out,
                            addr,
                            joined: None,
                        },
                    );
                }
                NetEvent::Disconnected(id) => {
                    if let Some(Conn {
                        joined: Some(j), ..
                    }) = self.conns.remove(&id)
                    {
                        self.log(format!("{} left", j.name));
                    }
                }
                NetEvent::Message(id, msg) => self.handle(id, msg, &mut commands, &mut pending),
                NetEvent::Unreadable(id, greeting) => {
                    // The wording is sim-net's, not the relay's: this host,
                    // sim-cli and the Godot client must not each invent their
                    // own sentence for one condition (ASSA-40's law).
                    self.refuse(id, sim_net::refuse_unreadable(&greeting));
                }
            }
        }

        // This tick's inputs: joins first, then commands in arrival order.
        let mut inputs: Vec<Input> = pending
            .iter()
            .map(|p| {
                Input::System(SystemCommand::AddPlayer {
                    name: p.name.clone(),
                })
            })
            .collect();
        inputs.extend(commands);
        let bundle = TickBundle {
            tick: self.world.tick,
            inputs,
        };

        let mut events = Vec::new();
        step(&mut self.world, &bundle.inputs, &mut events);

        // Everyone already in the game gets the bundle. People who just
        // joined get a snapshot taken after it instead (below).
        for conn in self.conns.values().filter(|c| c.joined.is_some()) {
            let _ = conn.out.send(ServerMsg::Tick(bundle.clone()));
        }

        let new_ids = events.iter().filter_map(|e| match e {
            Event::PlayerJoined { player, .. } => Some(*player),
            _ => None,
        });
        for (join, player) in pending.into_iter().zip(new_ids.collect::<Vec<_>>()) {
            self.accounts.insert(join.account.clone(), player);
            self.welcome(join.conn, join.account, join.name, player);
        }

        if self.world.tick.is_multiple_of(HASH_EVERY) {
            if self.hashes.len() == HASH_HISTORY {
                self.hashes.pop_front();
            }
            self.hashes
                .push_back((self.world.tick, self.world.state_hash()));
        }
        if self.world.tick.is_multiple_of(AUTOSAVE_EVERY) {
            self.save();
        }
    }

    fn handle(
        &mut self,
        id: ConnId,
        msg: ClientMsg,
        commands: &mut Vec<Input>,
        pending: &mut Vec<PendingJoin>,
    ) {
        let Some(conn) = self.conns.get(&id) else {
            return;
        };
        match msg {
            ClientMsg::Hello {
                name,
                protocol,
                rules,
            } => {
                if conn.joined.is_some() || pending.iter().any(|p| p.conn == id) {
                    return;
                }
                // Both the wire and the rules, worded in one place
                // (ASSA-40). A peer that disagrees about either is refused
                // here rather than discovering it as a desync.
                if let Err(reason) = sim_net::check_join(protocol, &rules) {
                    return self.refuse(id, reason);
                }
                let account = match self.auth.authenticate(&name) {
                    Ok(a) => a,
                    Err(reason) => return self.refuse(id, reason),
                };
                let online = self
                    .conns
                    .values()
                    .filter_map(|c| c.joined.as_ref())
                    .any(|j| j.account == account)
                    || pending.iter().any(|p| p.account == account);
                if online {
                    return self.refuse(id, format!("{account} is already connected."));
                }

                // Returning account, or a player slot nobody owns yet (for
                // example the player from a single-player save): welcome now.
                // Otherwise add a new player this tick and welcome after.
                let known = self.accounts.get(&account).copied();
                match known.or_else(|| self.unclaimed_player()) {
                    Some(player) => {
                        self.accounts.insert(account.clone(), player);
                        let name = self.world.player(player).map_or(name, |p| p.name.clone());
                        self.welcome(id, account, name, player);
                    }
                    None => pending.push(PendingJoin {
                        conn: id,
                        account,
                        name,
                    }),
                }
            }
            ClientMsg::Submit { command } => {
                if let Some(j) = &conn.joined {
                    self.log(format!("{}: {}", j.name, describe(&command)));
                    commands.push(Input::player(j.player, command));
                }
            }
            ClientMsg::Hash { tick, hash } => {
                let Some(j) = &conn.joined else { return };
                let ours = self.hashes.iter().find(|(t, _)| *t == tick);
                if let Some(&(_, expected)) = ours
                    && expected != hash
                {
                    // THE SAME TWO STRINGS GO TO THE LOG AND DOWN THE WIRE
                    // (ASSA-190). The host has always known both hashes and
                    // sent neither, so a peer could say only "we diverged" and
                    // never show the evidence. Formatted once by
                    // `sim_net::hash_hex` so the log a host reads and the band
                    // a player reads cannot spell one hash two ways.
                    let reported = sim_net::hash_hex(hash);
                    let expected = sim_net::hash_hex(expected);
                    self.log(format!(
                        "DESYNC: {} reported {reported} for tick {tick}, host has {expected}",
                        j.name
                    ));
                    let _ = conn.out.send(ServerMsg::Desync {
                        tick,
                        reported,
                        expected,
                    });
                }
            }
        }
    }

    fn unclaimed_player(&self) -> Option<PlayerId> {
        self.world
            .players
            .iter()
            .map(|p| p.id)
            .find(|id| !self.accounts.values().any(|owned| owned == id))
    }

    fn welcome(&mut self, id: ConnId, account: AccountId, name: String, player: PlayerId) {
        let world = self.world.clone();
        let Some(conn) = self.conns.get_mut(&id) else {
            return; // they left while joining
        };
        let _ = conn.out.send(ServerMsg::Welcome { player, world });
        let line = format!(
            "{name} ({account}) joined as player {} from {}",
            player.0, conn.addr
        );
        conn.joined = Some(Joined {
            account,
            player,
            name,
        });
        self.log(line);
    }

    fn refuse(&mut self, id: ConnId, reason: String) {
        if let Some(conn) = self.conns.remove(&id) {
            self.log(format!("Refused {}: {reason}", conn.addr));
            let _ = conn.out.send(ServerMsg::Refused { reason });
            // Dropping `conn.out` lets the writer finish and close the socket.
        }
    }

    fn save(&self) {
        let (world_path, accounts_path) = save_paths(self.seed);
        if let Err(e) = self.world.save_json(&world_path) {
            eprintln!("Could not save {}: {e}", world_path.display());
        }
        let accounts: BTreeMap<&str, u32> = self
            .accounts
            .iter()
            .map(|(a, p)| (a.0.as_str(), p.0))
            .collect();
        let json = serde_json::to_string_pretty(&accounts).expect("plain map serializes");
        if let Err(e) = std::fs::write(&accounts_path, json + "\n") {
            eprintln!("Could not save {}: {e}", accounts_path.display());
        }
    }
}

/// Accept connections. Each gets a reader thread (messages in) and a writer
/// thread (messages out), both talking to the main loop through channels.
fn spawn_listener(listener: TcpListener, events: Sender<NetEvent>) {
    thread::spawn(move || {
        for (id, stream) in (1..).zip(listener.incoming()) {
            let Ok(stream) = stream else { continue };
            let _ = stream.set_nodelay(true);
            let Ok(write_half) = stream.try_clone() else {
                continue;
            };
            let addr = stream
                .peer_addr()
                .map_or_else(|_| "unknown".into(), |a| a.to_string());

            let (out_tx, out_rx) = mpsc::channel::<ServerMsg>();
            thread::spawn(move || {
                {
                    let mut w = BufWriter::new(&write_half);
                    for msg in out_rx {
                        if write_msg(&mut w, &msg).is_err() {
                            break;
                        }
                    }
                }
                let _ = write_half.shutdown(Shutdown::Both);
            });

            if events.send(NetEvent::Connected(id, out_tx, addr)).is_err() {
                return;
            }
            let events = events.clone();
            thread::spawn(move || {
                let mut r = BufReader::new(stream);
                // FRAMES FIRST, MEANING SECOND (ASSA-77). The framing is the
                // one part of this protocol that has never changed, so a frame
                // from any build arrives readable even when its contents are
                // not. Parsing used to happen inside the read, and a `Hello`
                // from an older protocol therefore ended this loop silently:
                // the player saw `failed to fill whole buffer` where the
                // refusal should have been.
                while let Ok(frame) = read_frame(&mut r) {
                    match serde_json::from_slice::<ClientMsg>(&frame) {
                        Ok(msg) => {
                            if events.send(NetEvent::Message(id, msg)).is_err() {
                                return;
                            }
                        }
                        Err(_) => {
                            let g = sim_net::greeting(&frame);
                            let _ = events.send(NetEvent::Unreadable(id, g));
                            // Refused: stop reading rather than spin on a
                            // stream we cannot interpret.
                            break;
                        }
                    }
                }
                let _ = events.send(NetEvent::Disconnected(id));
            });
        }
    });
}

fn describe(command: &PlayerCommand) -> String {
    match command {
        PlayerCommand::Mine => "mine".into(),
        PlayerCommand::Craft {
            recipe,
            item,
            count,
        } => format!("craft {} {} {count}", recipe.name(), item.code()),
        PlayerCommand::Place { item, pos } => format!("place {} {} {}", item.code(), pos.x, pos.y),
        PlayerCommand::Insert {
            building,
            slot,
            item,
            count,
        } => format!("insert {} {slot:?} {} {count}", building.0, item.code()),
        PlayerCommand::Take { building } => format!("take {}", building.0),
        PlayerCommand::Pickup { building } => format!("pickup {}", building.0),
        PlayerCommand::Assay => "assay".into(),
        PlayerCommand::Rename { species, name } => format!("rename #{} {name}", species.0),
        PlayerCommand::GrantRename { species, to } => format!("grant #{} p{}", species.0, to.0),
        PlayerCommand::MakePart {
            kind,
            material,
            count,
        } => format!("make {} {} {count}", kind.name(), material.code()),
        PlayerCommand::Assemble { frame, mounted } => format!(
            "assemble {}{}",
            frame.code(),
            mounted
                .iter()
                .map(|m| format!(" {}", m.code()))
                .collect::<String>()
        ),
        PlayerCommand::Equip { assembly } => format!("equip {assembly}"),
        PlayerCommand::Unequip => "unequip".into(),
        PlayerCommand::PlaceAssembly { assembly, pos } => {
            format!("plant {assembly} {} {}", pos.x, pos.y)
        }
        PlayerCommand::MoveTo { target } => format!("goto {} {}", target.x, target.y),
        PlayerCommand::Stop => "stop".into(),
    }
}

/// This machine's address on the local network, if it has one. Connecting a
/// UDP socket sends nothing; it just makes the OS pick the outgoing interface.
fn lan_ip() -> Option<std::net::IpAddr> {
    let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let ip = socket.local_addr().ok()?.ip();
    (!ip.is_loopback() && !ip.is_unspecified()).then_some(ip)
}

/// Load the save for this seed if there is one, otherwise start fresh.
fn open_world(opts: &Options) -> (World, BTreeMap<AccountId, PlayerId>) {
    let (world_path, accounts_path) = save_paths(opts.seed);
    if !opts.fresh && world_path.exists() {
        let world = World::load_json(&world_path).unwrap_or_else(|e| {
            eprintln!("Could not load {}: {e}", world_path.display());
            exit(1);
        });
        println!("Loaded {}", world_path.display());
        return (world, load_accounts(&accounts_path));
    }
    // ONE PLACE DECIDES A SESSION'S WORLD (ASSA-53). This used to write the
    // chunk counts out here, and `sim-godot` wrote them out again for the
    // client's headless suite; two copies of a number that must match.
    (sim_net::fresh_world(opts.seed), BTreeMap::new())
}

fn load_accounts(path: &Path) -> BTreeMap<AccountId, PlayerId> {
    let Ok(json) = std::fs::read_to_string(path) else {
        return BTreeMap::new();
    };
    let map: BTreeMap<String, u32> = serde_json::from_str(&json).unwrap_or_else(|e| {
        eprintln!("Ignoring unreadable {}: {e}", path.display());
        BTreeMap::new()
    });
    map.into_iter()
        .map(|(a, p)| (AccountId(a), PlayerId(p)))
        .collect()
}

fn save_paths(seed: u64) -> (PathBuf, PathBuf) {
    let dir = saves_dir();
    (
        dir.join(format!("world-{seed}.json")),
        dir.join(format!("world-{seed}.accounts.json")),
    )
}

fn parse_args() -> Options {
    let usage = "Usage: sim-relay [seed] [--port N] [--tps N] [--fresh] [--bind ADDR]\n\
         \x20            [--tick-stats N]\n\
         \n\
         --port 0     listen on any free port, and print the one you got\n\
         --bind ADDR  which interfaces to accept on (default 0.0.0.0, every one).\n\
         \x20            127.0.0.1 makes the relay reachable from this computer only.\n\
         --tick-stats N  every N ticks, print how late the clock woke and how\n\
         \x20            long the tick's own work took (ASSA-208).";
    let mut opts = Options {
        seed: 42,
        port: DEFAULT_PORT,
        tps: DEFAULT_TPS,
        fresh: false,
        tick_stats: 0,
        bind: IpAddr::V4(Ipv4Addr::UNSPECIFIED),
    };
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        let mut value = |name: &str| {
            args.next().unwrap_or_else(|| {
                eprintln!("{name} needs a value.\n{usage}");
                exit(1);
            })
        };
        let parsed = match arg.as_str() {
            "--port" => value("--port").parse().map(|p| opts.port = p).is_ok(),
            // A name is not accepted on purpose: "localhost" resolves to more
            // than one address on some machines and the point of this flag is
            // to be exact about which one we are open on.
            "--bind" => value("--bind").parse().map(|a| opts.bind = a).is_ok(),
            "--tps" => value("--tps")
                .parse()
                .ok()
                .filter(|t| (1..=60).contains(t))
                .map(|t| opts.tps = t)
                .is_some(),
            "--fresh" => {
                opts.fresh = true;
                true
            }
            "--tick-stats" => value("--tick-stats")
                .parse()
                .map(|n| opts.tick_stats = n)
                .is_ok(),
            "-h" | "--help" => {
                println!("{usage}");
                exit(0);
            }
            seed => seed.parse().map(|s| opts.seed = s).is_ok(),
        };
        if !parsed {
            eprintln!("Didn't understand `{arg}`.\n{usage}");
            exit(1);
        }
    }
    opts
}

/// **WAS IT THE MACHINE OR `run_tick`?** (ASSA-208.) The client measures bundle
/// ARRIVALS, so a late wake-up and a long tick reach it as the same gap -- and
/// on the studio Mac, which runs six agents and this relay at once, 16-20 gaps
/// over 150 ms in a nine-second run were being read as a host that cannot hold
/// 10 ticks a second. One of those two causes is ours and the other is the
/// machine, and nothing outside this loop can separate them.
///
/// `late` is the scheduler's: `thread::sleep` returning after the tick was due.
/// `work` is this process's own: inputs drained, `step`, bundles sent to every
/// peer, the hash check and the autosave, all of it.
///
/// WHOLE SAMPLES AND NOT A RUNNING MEAN, because the thing being hunted is the
/// TAIL. A mean of a hundred ticks hides one 250 ms stall completely; p95 and
/// the count over the threshold are the whole report. A hundred ticks is ten
/// seconds at the default rate, so the vector is never more than a few hundred
/// `f64` long.
struct TickStats {
    every: u32,
    late: Vec<f64>,
    gap: Vec<f64>,
    work: Vec<f64>,
}

/// The bar the client's own probe charges a frame at (`motion_probe.gd`), so
/// the two reports can be read against each other.
const STALL_MS: f64 = 150.0;

impl TickStats {
    fn new(every: u32) -> Self {
        TickStats {
            every,
            late: Vec::new(),
            gap: Vec::new(),
            work: Vec::new(),
        }
    }

    fn record(&mut self, late: Duration, gap: Duration, work: Duration, tick: u64, peers: usize) {
        if self.every == 0 {
            return;
        }
        self.late.push(late.as_secs_f64() * 1000.0);
        self.gap.push(gap.as_secs_f64() * 1000.0);
        self.work.push(work.as_secs_f64() * 1000.0);
        if self.late.len() < self.every as usize {
            return;
        }
        println!(
            "[tick {tick}] stats over {} ticks, {peers} peer(s) | late {} | gap {} | work {}",
            self.late.len(),
            Self::line(&mut self.late),
            Self::line(&mut self.gap),
            Self::line(&mut self.work)
        );
        let _ = std::io::stdout().flush();
        self.late.clear();
        self.gap.clear();
        self.work.clear();
    }

    /// p50 / p95 / max in ms, and how many of the sample cleared `STALL_MS`.
    /// Sorts in place: the caller's vector is cleared straight after.
    fn line(ms: &mut [f64]) -> String {
        let over = ms.iter().filter(|v| **v > STALL_MS).count();
        ms.sort_by(|a, b| a.partial_cmp(b).expect("no NaN in a duration"));
        let at = |q: f64| ms[((ms.len() - 1) as f64 * q).round() as usize];
        format!(
            "p50 {:.1} p95 {:.1} max {:.1} ms (>{:.0}ms: {over})",
            at(0.5),
            at(0.95),
            ms[ms.len() - 1],
            STALL_MS
        )
    }
}
