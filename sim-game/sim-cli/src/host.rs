//! Host state and the typed commands. Everything here runs with the host lock
//! held, so a tick never lands halfway through a command.

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;

use sim::{
    Event, Grade, Input, Item, ItemKind, PlayerCommand, PlayerId, RejectReason, Slot, SpeciesId,
    SystemCommand, TilePos, World, WorldConfig, debug, step,
};
use sim_net::{ClientMsg, HASH_EVERY, TickBundle};

use crate::output::out;

/// How many recent tick bundles with inputs the inspector can show.
const RECENT_INPUTS: usize = 30;

/// Autosave whenever a local world reaches a multiple of this many ticks.
const AUTOSAVE_EVERY: u64 = 20;

/// Default local clock speed. The game will run at 60; 10 keeps a terminal
/// readable.
const DEFAULT_TPS: u32 = 10;

/// How many recent events `events` can show.
const EVENT_LOG_SIZE: usize = 200;

const HELP: &str = "\
World (single-player)
  new <seed> [width height]   create a world (size in chunks, default 6 4)
  load <seed or path>         continue a save, e.g. load 42
  save                        save now

Time (single-player; online, the host runs the clock)
  pause / resume              stop or restart the clock
  speed <ticks per second>    clock speed, 1-60 (default 10)
  tick [n]                    advance n ticks right away, handy while paused

Player
  goto <x> <y>                walk to a tile, one tile per tick
  move <dir> [n]              walk n tiles (default 1); dir: n s e w ne nw se sw
  mine                        mine the deposit you stand on, by hand, until you
                              stop or walk off it (ore hardness 40 or less)
  craft <recipe> [item] [n]   hand-craft n (default 1) from an item stack:
                              smelter, gear, or sort (3 ore -> 1 ore a grade up)
  place [item] [x y]          put a smelter down (default: just east of you)
  insert <id> ore|fuel <item> [n]   feed a building, e.g. insert 0 fuel ore:kel 5
                              (the ore slot also takes refined: 3 -> 1 a grade up)
  take <id>                   empty a building's output into your inventory
  pickup <id>                 take a building and its contents back
  assay                       study the deposit you stand on (30 ticks): its
                              species then shows exact numbers, not bands
  rename <species> <name>     name a species you discovered (letters, digits, -)
  grant <species> <player>    let another player rename it too
  stop                        stop walking, mining, crafting and assaying
  where                       your position
  inv                         what you're carrying, with the names to type

Items are written kind[:species[:grade]], e.g. ore, ore:kel, ore:kelvite:b.
Species is a name prefix or its id. Leave parts off when only one of your
stacks matches; `inv` shows the exact name for each stack.

Look
  map                         draw the map (P marks players)
  players                     everyone in this world
  species                     this world's minerals and their property sheets
  deposits                    list every deposit
  recipes                     what can be made, from what
  buildings                   every placed building and what it's doing
  at <x> <y>                  what's on a tile
  events [n]                  the last n events (default 20)
  status                      tick, clock or connection, hash, save file

  help                        show this
  quit                        exit (single-player saves first; Ctrl-D works too)

Multiplayer: start a host with `cargo run -p sim-relay`, then run
`cargo run -p sim-cli -- --connect localhost:7777 --name <name>` in each
player's terminal.";

pub enum Flow {
    Continue,
    Quit,
}

enum Link {
    /// Single-player: we own the clock, the queue and the save file.
    Local {
        path: PathBuf,
        /// Inputs waiting for the next tick.
        queue: Vec<Input>,
        /// Tick of the last save, if this world has been saved.
        saved_at: Option<u64>,
    },
    /// Multiplayer: the relay owns the clock and the save; we send commands
    /// and apply its tick bundles.
    Online {
        addr: String,
        out: Sender<ClientMsg>,
        connected: bool,
    },
}

struct Session {
    world: World,
    /// The player this terminal controls.
    me: PlayerId,
    link: Link,
}

impl Session {
    fn save(&mut self) -> Result<(), String> {
        let Link::Local { path, saved_at, .. } = &mut self.link else {
            return Err(ONLINE_CLOCK.into());
        };
        self.world
            .save_json(&*path)
            .map_err(|e| format!("Could not save {}: {e}", path.display()))?;
        *saved_at = Some(self.world.tick);
        Ok(())
    }

    fn me(&self) -> Result<&sim::Player, String> {
        self.world
            .player(self.me)
            .ok_or_else(|| "You don't have a player in this world yet.".to_string())
    }

    fn is_online(&self) -> bool {
        matches!(self.link, Link::Online { .. })
    }
}

const ONLINE_CLOCK: &str = "You're playing online: the host runs the clock and saves the world.";

pub struct Host {
    session: Option<Session>,
    /// Name for your player in single-player worlds.
    name: String,
    pub tps: u32,
    paused: bool,
    pub quitting: bool,
    /// Recent event lines, oldest first.
    log: VecDeque<String>,
    /// Recent ticks that carried inputs, oldest first.
    recent_inputs: VecDeque<(u64, Vec<Input>)>,
}

impl Host {
    pub fn new(name: String) -> Self {
        Self {
            session: None,
            name,
            tps: DEFAULT_TPS,
            paused: false,
            quitting: false,
            log: VecDeque::new(),
            recent_inputs: VecDeque::new(),
        }
    }

    // --- read access for the inspector ---

    pub fn world(&self) -> Option<&World> {
        self.session.as_ref().map(|s| &s.world)
    }

    pub fn me_id(&self) -> Option<PlayerId> {
        self.session.as_ref().map(|s| s.me)
    }

    pub fn recent_inputs(&self) -> &VecDeque<(u64, Vec<Input>)> {
        &self.recent_inputs
    }

    /// Short lines about the clock, connection and save for the inspector.
    pub fn link_lines(&self) -> Vec<String> {
        let Some(s) = &self.session else {
            return vec!["no world".into()];
        };
        match &s.link {
            Link::Online {
                addr, connected, ..
            } => vec![format!(
                "host {addr} ({})",
                if *connected {
                    "connected"
                } else {
                    "DISCONNECTED"
                }
            )],
            Link::Local {
                path,
                queue,
                saved_at,
            } => {
                let file = path.file_name().map_or_else(
                    || path.display().to_string(),
                    |f| f.to_string_lossy().into(),
                );
                vec![
                    if self.paused {
                        "clock paused".to_string()
                    } else {
                        format!("clock {} tps (local)", self.tps)
                    },
                    match saved_at {
                        Some(t) => format!("save {file} @ tick {t}"),
                        None => format!("save {file} (unsaved)"),
                    },
                    format!("queued {}", queue.len()),
                ]
            }
        }
    }

    /// Send a player command (used by the inspector's keys and mouse).
    pub fn act(&mut self, command: PlayerCommand) -> Result<(), String> {
        let paused = self.paused;
        let s = self.session.as_mut().ok_or("No world yet.")?;
        submit(s, paused, command)
    }

    pub fn go_online(&mut self, addr: String, world: World, me: PlayerId, out: Sender<ClientMsg>) {
        let name = world.player(me).map_or("?", |p| p.name.as_str());
        out!(
            "Joined {addr} as {name} (player {}) at tick {}. Try `players`, `map` or `goto 10 10`.",
            me.0,
            world.tick
        );
        self.session = Some(Session {
            world,
            me,
            link: Link::Online {
                addr,
                out,
                connected: true,
            },
        });
    }

    pub fn disconnected(&mut self) {
        if let Some(Session {
            link: Link::Online { connected, .. },
            ..
        }) = &mut self.session
        {
            *connected = false;
        }
    }

    pub fn prompt(&self) -> String {
        let Some(s) = &self.session else {
            return "> ".into();
        };
        let name = s.me().map_or("?", |p| p.name.as_str());
        match &s.link {
            Link::Online {
                connected: false, ..
            } => "[disconnected] > ".into(),
            Link::Online { addr, .. } => format!("[{name} @ {addr}] > "),
            Link::Local { .. } if self.paused => format!("[seed {} · paused] > ", s.world.seed),
            Link::Local { .. } => format!("[seed {}] > ", s.world.seed),
        }
    }

    /// Whether the local clock should tick.
    pub fn is_running(&self) -> bool {
        !self.paused && self.session.as_ref().is_some_and(|s| !s.is_online())
    }

    /// Single-player: advance one tick, autosave on schedule, return event lines.
    pub fn tick_once(&mut self) -> Vec<String> {
        let Some(s) = self.session.as_mut() else {
            return Vec::new();
        };
        let Link::Local { queue, .. } = &mut s.link else {
            return Vec::new();
        };
        let inputs = std::mem::take(queue);
        let tick = s.world.tick;
        let mut lines = run_step(&mut s.world, s.me, &inputs);
        if s.world.tick.is_multiple_of(AUTOSAVE_EVERY)
            && let Err(msg) = s.save()
        {
            lines.push(msg);
        }
        self.remember(&lines);
        self.remember_inputs(tick, inputs);
        lines
    }

    /// Online: apply one tick bundle from the relay, return event lines.
    pub fn apply_bundle(&mut self, bundle: &TickBundle) -> Vec<String> {
        let Some(s) = self.session.as_mut() else {
            return Vec::new();
        };
        if bundle.tick != s.world.tick {
            return vec![format!(
                "The host sent tick {} but we're at tick {}. Restart the client to rejoin.",
                bundle.tick, s.world.tick
            )];
        }
        let lines = run_step(&mut s.world, s.me, &bundle.inputs);
        if let Link::Online { out, .. } = &s.link
            && s.world.tick.is_multiple_of(HASH_EVERY)
        {
            let _ = out.send(ClientMsg::Hash {
                tick: s.world.tick,
                hash: s.world.state_hash(),
            });
        }
        self.remember(&lines);
        self.remember_inputs(bundle.tick, bundle.inputs.clone());
        lines
    }

    fn remember_inputs(&mut self, tick: u64, inputs: Vec<Input>) {
        if inputs.is_empty() {
            return;
        }
        if self.recent_inputs.len() == RECENT_INPUTS {
            self.recent_inputs.pop_front();
        }
        self.recent_inputs.push_back((tick, inputs));
    }

    fn remember(&mut self, lines: &[String]) {
        for line in lines {
            if self.log.len() == EVENT_LOG_SIZE {
                self.log.pop_front();
            }
            self.log.push_back(line.clone());
        }
    }

    pub fn save_on_exit(&mut self) {
        if let Some(s) = self.session.as_mut()
            && let Link::Local { saved_at, path, .. } = &s.link
            && *saved_at != Some(s.world.tick)
        {
            let path = path.clone();
            match s.save() {
                Ok(()) => out!("Saved tick {} to {}", s.world.tick, path.display()),
                Err(msg) => eprintln!("{msg}"),
            }
        }
    }

    pub fn run(&mut self, args: &[&str]) -> Result<Flow, String> {
        let online = self.session.as_ref().is_some_and(Session::is_online);
        match args[0] {
            "help" | "?" => out!("{HELP}"),
            "quit" | "exit" | "q" => return Ok(Flow::Quit),
            "new" | "load" | "speed" if online => return Err(ONLINE_CLOCK.into()),
            "new" => {
                let session = new_world(args, &self.name)?;
                self.start(session);
            }
            "load" => {
                let session = load_world(args, &self.name)?;
                self.start(session);
            }
            "speed" => self.speed(args)?,
            cmd => self.run_in_world(cmd, args)?,
        }
        Ok(Flow::Continue)
    }

    fn start(&mut self, session: Session) {
        self.session = Some(session);
        self.paused = false;
        self.log.clear();
        out!(
            "The clock is running at {} ticks/s. Try `goto 10 10`, `map`, or `pause`.",
            self.tps
        );
    }

    fn speed(&mut self, args: &[&str]) -> Result<(), String> {
        let tps: u32 = parse_arg(args, 1, "speed")
            .map_err(|e| format!("{e}\nUsage: speed <ticks per second>, e.g. speed 20"))?;
        if !(1..=60).contains(&tps) {
            return Err("Speed must be between 1 and 60 ticks per second.".into());
        }
        self.tps = tps;
        out!("Clock speed set to {tps} ticks/s.");
        Ok(())
    }

    fn run_in_world(&mut self, cmd: &str, args: &[&str]) -> Result<(), String> {
        let paused = self.paused;
        let s = self
            .session
            .as_mut()
            .ok_or("No world yet. Start one with `new <seed>` or `load <seed>`. To join a host, restart with: sim-cli --connect <address> --name <name>")?;

        if s.is_online() && matches!(cmd, "save" | "pause" | "resume" | "play" | "tick" | "t") {
            return Err(ONLINE_CLOCK.into());
        }

        match cmd {
            "save" => {
                s.save()?;
                if let Link::Local { path, .. } = &s.link {
                    out!("Saved tick {} to {}", s.world.tick, path.display());
                }
            }
            "pause" => {
                self.paused = true;
                out!(
                    "Paused at tick {}. `tick` steps, `resume` restarts the clock.",
                    s.world.tick
                );
            }
            "resume" | "play" => {
                self.paused = false;
                out!("Running at {} ticks/s.", self.tps);
            }
            "tick" | "t" => {
                let n: u64 = optional_arg(args, 1, "tick count", 1)?;
                if n == 0 {
                    return Err("Tick count must be at least 1.".into());
                }
                for _ in 0..n {
                    for line in self.tick_once() {
                        out!("  {line}");
                    }
                }
                let s = self.session.as_ref().expect("session checked above");
                out!(
                    "Now at tick {} · hash {:016x}",
                    s.world.tick,
                    s.world.state_hash()
                );
            }
            "map" => {
                out!("{}", debug::ascii_map(&s.world));
                out!("{}", debug::MAP_LEGEND);
            }
            "players" | "who" => {
                for p in &s.world.players {
                    let you = if p.id == s.me { " (you)" } else { "" };
                    let walking = p
                        .target
                        .map(|t| format!(", walking to ({}, {})", t.x, t.y))
                        .unwrap_or_default();
                    let mining = p
                        .mining
                        .map(|m| format!(", mining deposit {}", m.deposit.0))
                        .unwrap_or_default();
                    let crafting = p
                        .crafting
                        .map(|c| format!(", crafting {} ({} to go)", c.recipe.name(), c.remaining))
                        .unwrap_or_default();
                    let assaying = p
                        .assaying
                        .map(|a| format!(", assaying deposit {}", a.deposit.0))
                        .unwrap_or_default();
                    out!(
                        "  {} · {}{you} at ({}, {}){walking}{mining}{crafting}{assaying} · carrying {}",
                        p.id.0,
                        p.name,
                        p.pos.x,
                        p.pos.y,
                        describe_inventory(&s.world, &p.inventory)
                    );
                }
            }
            "deposits" | "ls" => out!("{}", debug::deposit_table(&s.world)),
            "recipes" => out!("{}", debug::recipe_table()),
            "species" | "minerals" => out!("{}", debug::species_table(&s.world)),
            "buildings" => out!("{}", debug::building_table(&s.world)),
            "at" => at(s, args)?,
            "where" => where_am_i(s)?,
            "inv" | "inventory" => {
                let me = s.me()?;
                out!("Carrying {}", describe_inventory(&s.world, &me.inventory));
                for st in me.inventory.stacks() {
                    out!(
                        "  {:>4} {:<28} type: {}",
                        st.count,
                        s.world.item_name(st.item),
                        item_spec(&s.world, st.item)
                    );
                }
            }
            "events" | "log" => {
                let n: usize = optional_arg(args, 1, "count", 20)?;
                if self.log.is_empty() {
                    out!("No events yet. Try `goto 10 10`, or walk onto a deposit and `mine`.");
                }
                for line in self.log.iter().skip(self.log.len().saturating_sub(n)) {
                    out!("  {line}");
                }
            }
            "status" => status(s, paused, self.tps),
            "goto" => {
                let usage = "Usage: goto <x> <y>, e.g. goto 10 10";
                let x: i32 = parse_arg(args, 1, "x").map_err(|e| format!("{e}\n{usage}"))?;
                let y: i32 = parse_arg(args, 2, "y").map_err(|e| format!("{e}\n{usage}"))?;
                let target = TilePos::new(x, y);
                submit(s, paused, PlayerCommand::MoveTo { target })?;
            }
            "move" | "m" => {
                let usage = "Usage: move <dir> [tiles], dir is one of n s e w ne nw se sw";
                let dir = args.get(1).ok_or(format!("Missing direction.\n{usage}"))?;
                let (dx, dy) =
                    direction(dir).ok_or(format!("`{dir}` is not a direction.\n{usage}"))?;
                let n: i32 = optional_arg(args, 2, "tile count", 1)?;
                if !(1..=1000).contains(&n) {
                    return Err("Tile count must be between 1 and 1000.".into());
                }
                let from = s.me()?.pos;
                // Stop at the map edge instead of rejecting the whole move.
                let target = TilePos::new(
                    (from.x + dx * n).clamp(0, s.world.width() - 1),
                    (from.y + dy * n).clamp(0, s.world.height() - 1),
                );
                submit(s, paused, PlayerCommand::MoveTo { target })?;
            }
            "stop" => submit(s, paused, PlayerCommand::Stop)?,
            "mine" => submit(s, paused, PlayerCommand::Mine)?,
            "assay" => submit(s, paused, PlayerCommand::Assay)?,
            "rename" => {
                let usage = "Usage: rename <species> <name>, e.g. rename kel Kelvite";
                let species = resolve_species(s, args.get(1).copied())
                    .map_err(|e| format!("{e}\n{usage}"))?;
                let name = args.get(2).ok_or(format!("Missing name.\n{usage}"))?;
                submit(
                    s,
                    paused,
                    PlayerCommand::Rename {
                        species,
                        name: (*name).to_string(),
                    },
                )?;
            }
            "grant" => {
                let usage = "Usage: grant <species> <player name or id>, e.g. grant kel grace";
                let species = resolve_species(s, args.get(1).copied())
                    .map_err(|e| format!("{e}\n{usage}"))?;
                let who = args.get(2).ok_or(format!("Missing player.\n{usage}"))?;
                let to = s
                    .world
                    .players
                    .iter()
                    .find(|p| p.name.eq_ignore_ascii_case(who) || who.parse() == Ok(p.id.0))
                    .map(|p| p.id)
                    .ok_or(format!(
                        "No player called `{who}`. `players` lists them.\n{usage}"
                    ))?;
                submit(s, paused, PlayerCommand::GrantRename { species, to })?;
            }
            "place" => {
                let usage =
                    "Usage: place [item] [x y], e.g. place smelter, or place smelter:kel 10 12";
                let (spec, next) = match args.get(1) {
                    Some(a) if a.parse::<i32>().is_err() => (Some(*a), 2),
                    _ => (None, 1),
                };
                let item = resolve_item(s, spec, Some(ItemKind::Smelter))?;
                let me = s.me()?.pos;
                let x: i32 =
                    optional_arg(args, next, "x", me.x + 1).map_err(|e| format!("{e}\n{usage}"))?;
                let y: i32 =
                    optional_arg(args, next + 1, "y", me.y).map_err(|e| format!("{e}\n{usage}"))?;
                let pos = TilePos::new(x, y);
                submit(s, paused, PlayerCommand::Place { item, pos })?;
            }
            "insert" | "put" => {
                let usage = "Usage: insert <building id> ore|fuel <item> [count], e.g. insert 0 fuel ore:kel 5";
                let id: u32 =
                    parse_arg(args, 1, "building id").map_err(|e| format!("{e}\n{usage}"))?;
                let slot = match args.get(2).copied() {
                    Some("ore" | "in" | "input") => Slot::Input,
                    Some("fuel" | "burn") => Slot::Fuel,
                    Some(other) => return Err(format!("`{other}` is not a slot.\n{usage}")),
                    None => return Err(format!("Missing slot.\n{usage}")),
                };
                let item = resolve_item(s, args.get(3).copied(), None)?;
                let count: u32 = optional_arg(args, 4, "count", 1)?;
                let building = sim::BuildingId(id);
                submit(
                    s,
                    paused,
                    PlayerCommand::Insert {
                        building,
                        slot,
                        item,
                        count,
                    },
                )?;
            }
            "take" => {
                let id: u32 = parse_arg(args, 1, "building id")
                    .map_err(|e| format!("{e}\nUsage: take <building id>, e.g. take 0"))?;
                let building = sim::BuildingId(id);
                submit(s, paused, PlayerCommand::Take { building })?;
            }
            "pickup" => {
                let id: u32 = parse_arg(args, 1, "building id")
                    .map_err(|e| format!("{e}\nUsage: pickup <building id>, e.g. pickup 0"))?;
                let building = sim::BuildingId(id);
                submit(s, paused, PlayerCommand::Pickup { building })?;
            }
            "craft" => {
                let usage = "Usage: craft <smelter|gear|sort> [item] [count], e.g. craft smelter, or craft sort ore:kel:c 2. `recipes` lists them.";
                let name = args.get(1).ok_or(format!("Missing recipe.\n{usage}"))?;
                let recipe = sim::RecipeId::parse(name)
                    .ok_or(format!("No recipe makes `{name}`.\n{usage}"))?;
                let (spec, next) = match args.get(2) {
                    Some(a) if a.parse::<u32>().is_err() => (Some(*a), 3),
                    _ => (None, 2),
                };
                let item = resolve_item(s, spec, Some(recipe.recipe().input.0))?;
                let count: u32 = optional_arg(args, next, "count", 1)?;
                submit(
                    s,
                    paused,
                    PlayerCommand::Craft {
                        recipe,
                        item,
                        count,
                    },
                )?;
            }
            other => {
                return Err(format!(
                    "Unknown command `{other}`. Type `help` to see commands."
                ));
            }
        }
        Ok(())
    }
}

/// Step the world with `inputs` and describe what happened.
fn run_step(world: &mut World, me: PlayerId, inputs: &[Input]) -> Vec<String> {
    let tick = world.tick;
    let mut events = Vec::new();
    step(world, inputs, &mut events);
    events
        .iter()
        .map(|e| format!("tick {tick} · {}", describe_event(e, world, me)))
        .collect()
}

/// Send a command toward the next tick. The sim validates it and answers with
/// an event, so no checks here. While time is running, that event is the
/// feedback.
fn submit(s: &mut Session, paused: bool, command: PlayerCommand) -> Result<(), String> {
    let what = describe_command(&command, &s.world);
    match &mut s.link {
        Link::Local { queue, .. } => {
            if paused {
                out!(
                    "Queued `{what}` for tick {}. Paused: `tick` or `resume` to apply it.",
                    s.world.tick
                );
            }
            queue.push(Input::player(s.me, command));
            Ok(())
        }
        Link::Online {
            connected: false, ..
        } => Err("You're disconnected from the host. Restart the client to rejoin.".into()),
        Link::Online { out, .. } => out
            .send(ClientMsg::Submit { command })
            .map_err(|_| "The connection to the host is closed.".to_string()),
    }
}

pub use sim_net::saves_dir;

fn save_path(seed: u64) -> PathBuf {
    saves_dir().join(format!("world-{seed}.json"))
}

/// Turn what was typed after `load` into a file: a bare seed (`42`), a file
/// in the saves folder (`world-42.json` or `saves/world-42.json`), or any
/// other path.
fn resolve_save(arg: &str) -> PathBuf {
    if let Ok(seed) = arg.parse::<u64>() {
        return save_path(seed);
    }
    let typed = Path::new(arg);
    let in_saves = saves_dir().join(typed.strip_prefix("saves").unwrap_or(typed));
    if !typed.exists() && in_saves.exists() {
        in_saves
    } else {
        typed.to_path_buf()
    }
}

/// Make sure the local player exists: player 0, added through the sim like
/// any join so the world stays consistent.
fn local_session(mut world: World, path: PathBuf, saved_at: Option<u64>, name: &str) -> Session {
    if world.players.is_empty() {
        let join = Input::System(SystemCommand::AddPlayer { name: name.into() });
        step(&mut world, &[join], &mut Vec::new());
    }
    Session {
        world,
        me: PlayerId(0),
        link: Link::Local {
            path,
            queue: Vec::new(),
            saved_at,
        },
    }
}

fn new_world(args: &[&str], name: &str) -> Result<Session, String> {
    let usage = "Usage: new <seed> [width height], e.g. new 42 or new 42 8 8";
    let seed: u64 = parse_arg(args, 1, "seed").map_err(|e| format!("{e}\n{usage}"))?;
    let width = optional_arg(args, 2, "width", 6)?;
    let height = optional_arg(args, 3, "height", 4)?;
    if !(1..=64).contains(&width) || !(1..=64).contains(&height) {
        return Err("Width and height are in chunks and must be between 1 and 64.".into());
    }

    let world = World::new(WorldConfig {
        seed,
        width_chunks: width,
        height_chunks: height,
    });
    let path = save_path(seed);
    if path.exists() {
        out!(
            "Note: {} already exists and will be overwritten at the next save. Use `load {seed}` to continue it instead.",
            path.display()
        );
    }
    let session = local_session(world, path, None, name);
    out!("Created {}", debug::summary(&session.world));
    Ok(session)
}

fn load_world(args: &[&str], name: &str) -> Result<Session, String> {
    let arg = args
        .get(1)
        .ok_or("Usage: load <seed or path>, e.g. load 42 or load saves/world-42.json")?;
    let path = resolve_save(arg);
    let world =
        World::load_json(&path).map_err(|e| format!("Could not load {}: {e}", path.display()))?;
    out!("Loaded {} from {}", debug::summary(&world), path.display());
    let saved_at = Some(world.tick);
    Ok(local_session(world, path, saved_at, name))
}

fn at(s: &Session, args: &[&str]) -> Result<(), String> {
    let x: i32 = parse_arg(args, 1, "x")?;
    let y: i32 = parse_arg(args, 2, "y")?;
    let pos = TilePos::new(x, y);
    if !s.world.in_bounds(pos) {
        return Err(off_map(&s.world, pos));
    }
    let chunk = pos.chunk();
    let distance = chunk.distance(s.world.spawn);
    let place = format!(
        "chunk ({}, {}), {distance} chunks from spawn",
        chunk.x, chunk.y
    );
    if let Some(b) = s.world.building_at(pos) {
        out!(
            "({x}, {y}): {} {} at ({}, {}) · {}",
            b.kind.name(),
            b.id.0,
            b.pos.x,
            b.pos.y,
            debug::building_status(&s.world, b)
        );
    }
    match s.world.deposit_at(pos) {
        Some(d) => out!(
            "({x}, {y}): deposit {} · {} · {} left · purity {} (grade {}) · {place}",
            d.id.0,
            s.world.species(d.species).name(),
            d.amount,
            d.purity,
            d.grade().letter()
        ),
        None if pos == s.world.spawn_tile() => out!("({x}, {y}): spawn · {place}"),
        None => out!("({x}, {y}): empty ground · {place}"),
    }
    Ok(())
}

fn where_am_i(s: &Session) -> Result<(), String> {
    let me = s.me()?;
    let (x, y) = (me.pos.x, me.pos.y);
    match me.target {
        Some(t) => {
            let tiles = (t.x - x).abs().max((t.y - y).abs());
            out!(
                "You are at ({x}, {y}), walking to ({}, {}), {tiles} tiles to go.",
                t.x,
                t.y
            );
        }
        None => out!("You are standing at ({x}, {y})."),
    }
    if let Some(d) = s.world.deposit_at(me.pos) {
        let mining = if me.mining.is_some() {
            " You're mining it."
        } else {
            " `mine` to start mining it."
        };
        out!(
            "You're on deposit {} ({}, grade {}, {} left).{mining}",
            d.id.0,
            s.world.species(d.species).name(),
            d.grade().letter(),
            d.amount
        );
    }
    Ok(())
}

fn status(s: &Session, paused: bool, tps: u32) {
    out!("{}", debug::summary(&s.world));
    if let Ok(me) = s.me() {
        out!(
            "You: {} (player {}) at ({}, {})",
            me.name,
            s.me.0,
            me.pos.x,
            me.pos.y
        );
    }
    out!("Players in world: {}", s.world.players.len());
    let depleted = s.world.deposits.iter().filter(|d| d.is_depleted()).count();
    out!(
        "Depleted deposits: {depleted} of {}",
        s.world.deposits.len()
    );
    match &s.link {
        Link::Online {
            addr, connected, ..
        } => {
            let state = if *connected {
                "connected"
            } else {
                "disconnected"
            };
            out!("Host: {addr} ({state}); the host runs the clock and saves");
        }
        Link::Local {
            path,
            queue,
            saved_at,
        } => {
            if paused {
                out!("Clock: paused");
            } else {
                out!("Clock: running at {tps} ticks/s");
            }
            match saved_at {
                Some(t) => out!("Save file: {} (last saved at tick {t})", path.display()),
                None => out!("Save file: {} (not saved yet)", path.display()),
            }
            let next = (s.world.tick / AUTOSAVE_EVERY + 1) * AUTOSAVE_EVERY;
            out!("Next autosave: tick {next}");
            out!(
                "Queued for tick {}: {} command(s)",
                s.world.tick,
                queue.len()
            );
        }
    }
}

pub fn describe_inventory(world: &World, inv: &sim::Inventory) -> String {
    if inv.is_empty() {
        return "nothing".into();
    }
    inv.stacks()
        .iter()
        .map(|st| format!("{} {}", st.count, world.item_name(st.item)))
        .collect::<Vec<_>>()
        .join(", ")
}

/// The exact `kind:species:grade` text that names this item in a command.
pub fn item_spec(world: &World, item: Item) -> String {
    format!(
        "{}:{}:{}",
        item.kind.name(),
        world.species(item.species).name().to_ascii_lowercase(),
        item.grade.letter().to_ascii_lowercase()
    )
}

/// A species by name prefix (player or generated name) or by id.
fn resolve_species(s: &Session, text: Option<&str>) -> Result<SpeciesId, String> {
    let text = text.ok_or("Missing species. `species` lists them.")?;
    let lower = text.to_ascii_lowercase();
    let hits: Vec<&sim::MineralSpecies> = s
        .world
        .species
        .iter()
        .filter(|sp| {
            text.parse::<u8>().ok() == Some(sp.id.0)
                || sp.name().to_ascii_lowercase().starts_with(&lower)
                || sp.generated_name.to_ascii_lowercase().starts_with(&lower)
        })
        .collect();
    match hits.as_slice() {
        [one] => Ok(one.id),
        [] => Err(format!(
            "No species matches `{text}`. `species` lists them."
        )),
        many => Err(format!(
            "`{text}` could be: {}",
            many.iter()
                .map(|sp| sp.name())
                .collect::<Vec<_>>()
                .join(", ")
        )),
    }
}

/// Find the one stack in your inventory that `spec` means. `spec` is
/// `kind[:species[:grade]]`; the kind may be left off when the command
/// already says which kind it needs (`want`).
fn resolve_item(s: &Session, spec: Option<&str>, want: Option<ItemKind>) -> Result<Item, String> {
    let me = s.me()?;
    let parts: Vec<&str> = spec.map_or_else(Vec::new, |t| t.split(':').collect());
    let (kind, rest) = match parts.first().and_then(|p| ItemKind::parse(p)) {
        Some(k) => (Some(k), &parts[1..]),
        None => (want, &parts[..]),
    };
    let kind = match (kind, want) {
        (Some(k), Some(w)) if k != w => {
            return Err(format!("That needs {} items, not {}.", w.name(), k.name()));
        }
        (Some(k), _) | (None, Some(k)) => k,
        (None, None) => {
            return Err(
                "Say which item: kind[:species[:grade]], e.g. ore:kel:b. `inv` lists yours.".into(),
            );
        }
    };
    if rest.len() > 2 {
        return Err("Too many parts: items are kind[:species[:grade]].".into());
    }
    let species = rest.first().copied().filter(|t| !t.is_empty());
    let grade = match rest.get(1) {
        Some(g) => Some(Grade::parse(g).ok_or(format!("`{g}` is not a grade (A, B or C)."))?),
        None => None,
    };
    let species_matches = |item: &Item| {
        species.is_none_or(|t| {
            let name = s.world.species(item.species).name().to_ascii_lowercase();
            t.parse::<u8>().ok() == Some(item.species.0)
                || name.starts_with(&t.to_ascii_lowercase())
        })
    };
    let candidates: Vec<Item> = me
        .inventory
        .stacks()
        .iter()
        .map(|st| st.item)
        .filter(|i| i.kind == kind && species_matches(i) && grade.is_none_or(|g| i.grade == g))
        .collect();
    match candidates.as_slice() {
        [one] => Ok(*one),
        [] => Err(format!(
            "You have no {} matching `{}`. `inv` lists what you carry.",
            kind.name(),
            spec.unwrap_or(kind.name())
        )),
        many => Err(format!(
            "Be more specific. You carry: {}",
            many.iter()
                .map(|i| item_spec(&s.world, *i))
                .collect::<Vec<_>>()
                .join(", ")
        )),
    }
}

fn off_map(world: &World, pos: TilePos) -> String {
    format!(
        "({}, {}) is off the map. The map is {}x{} tiles, from (0, 0) to ({}, {}).",
        pos.x,
        pos.y,
        world.width(),
        world.height(),
        world.width() - 1,
        world.height() - 1
    )
}

fn direction(s: &str) -> Option<(i32, i32)> {
    Some(match s {
        "n" | "north" | "up" => (0, -1),
        "s" | "south" | "down" => (0, 1),
        "e" | "east" | "right" => (1, 0),
        "w" | "west" | "left" => (-1, 0),
        "ne" => (1, -1),
        "nw" => (-1, -1),
        "se" => (1, 1),
        "sw" => (-1, 1),
        _ => return None,
    })
}

fn who(world: &World, me: PlayerId, player: PlayerId) -> String {
    if player == me {
        return "you".into();
    }
    world
        .player(player)
        .map_or_else(|| format!("player {}", player.0), |p| p.name.clone())
}

fn describe_command(cmd: &PlayerCommand, world: &World) -> String {
    let spec = |item: &Item| item_spec(world, *item);
    match cmd {
        PlayerCommand::Mine => "mine".into(),
        PlayerCommand::Craft {
            recipe,
            item,
            count,
        } => format!("craft {} {} {count}", recipe.name(), spec(item)),
        PlayerCommand::Place { item, pos } => format!("place {} {} {}", spec(item), pos.x, pos.y),
        PlayerCommand::Insert {
            building,
            slot,
            item,
            count,
        } => format!(
            "insert {} {} {} {count}",
            building.0,
            slot_name(*slot),
            spec(item)
        ),
        PlayerCommand::Take { building } => format!("take {}", building.0),
        PlayerCommand::Pickup { building } => format!("pickup {}", building.0),
        PlayerCommand::Assay => "assay".into(),
        PlayerCommand::Rename { species, name } => {
            format!("rename {} {name}", world.species(*species).name())
        }
        PlayerCommand::GrantRename { species, to } => format!(
            "grant {} {}",
            world.species(*species).name(),
            who(world, PlayerId(u32::MAX), *to)
        ),
        PlayerCommand::MoveTo { target } => format!("goto {} {}", target.x, target.y),
        PlayerCommand::Stop => "stop".into(),
    }
}

fn slot_name(slot: Slot) -> &'static str {
    match slot {
        Slot::Input => "ore",
        Slot::Fuel => "fuel",
    }
}

fn describe_event(event: &Event, world: &World, me: PlayerId) -> String {
    let who = |p: &PlayerId| who(world, me, *p);
    let name = |item: &Item| world.item_name(*item);
    match event {
        Event::PlayerJoined { player, name } if *player == me => {
            format!("you joined as {name}")
        }
        Event::PlayerJoined { name, .. } => format!("{name} joined"),
        Event::MiningStarted {
            player,
            deposit,
            species,
        } => format!(
            "{} started mining {} at deposit {}",
            who(player),
            world.species(*species).name(),
            deposit.0
        ),
        Event::OreMined {
            player,
            deposit,
            item,
            amount,
        } => {
            let (left, carrying) = (
                world.deposit(*deposit).map_or(0, |d| d.amount),
                world
                    .player(*player)
                    .map_or(0, |p| p.inventory.count(*item)),
            );
            format!(
                "{} mined {amount} {} (carrying {carrying}, {left} left in deposit {})",
                who(player),
                name(item),
                deposit.0
            )
        }
        Event::MiningStopped {
            player,
            deposit,
            reason,
        } => {
            let why = match reason {
                sim::StopReason::Stopped => "stopped",
                sim::StopReason::LeftDeposit => "walked off it",
                sim::StopReason::Depleted => "mined it out",
                sim::StopReason::OutOfInputs => "ran out",
            };
            format!(
                "{} stopped mining deposit {}: {why}",
                who(player),
                deposit.0
            )
        }
        Event::DepositDepleted { deposit } => format!("deposit {} is now depleted", deposit.0),
        Event::SpeciesDiscovered { player, species } => format!(
            "{} discovered {}! `rename {} <name>` to name it",
            who(player),
            world.species(*species).name(),
            world.species(*species).name().to_ascii_lowercase()
        ),
        Event::AssayStarted {
            player,
            deposit,
            species,
        } => format!(
            "{} started assaying {} at deposit {} ({} ticks)",
            who(player),
            world.species(*species).name(),
            deposit.0,
            sim::tuning::ASSAY_TICKS
        ),
        Event::AssayStopped {
            player,
            deposit,
            reason,
        } => {
            let why = match reason {
                sim::StopReason::LeftDeposit => "walked off it",
                _ => "stopped",
            };
            format!(
                "{} stopped assaying deposit {}: {why}",
                who(player),
                deposit.0
            )
        }
        Event::SpeciesAssayed { player, species } => {
            let sp = world.species(*species);
            format!(
                "{} assayed {}: density {} · strength {} · hardness {} · heat tolerance {} · reactivity {} · conductivity {}",
                who(player),
                sp.name(),
                sp.sheet.density,
                sp.sheet.strength,
                sp.sheet.hardness,
                sp.sheet.heat_tolerance,
                sp.sheet.reactivity,
                sp.sheet.conductivity
            )
        }
        Event::SpeciesRenamed {
            player,
            species,
            name,
        } => format!(
            "{} named species {} \"{name}\" (was {})",
            who(player),
            species.0,
            world.species(*species).generated_name
        ),
        Event::RenameGranted { species, from, to } => format!(
            "{} let {} rename {}",
            who(from),
            who(to),
            world.species(*species).name()
        ),
        Event::CraftStarted {
            player,
            recipe,
            item,
            count,
        } => format!(
            "{} started crafting {count} {} from {} ({} ticks each)",
            who(player),
            recipe.name(),
            name(item),
            recipe.recipe().ticks
        ),
        Event::ItemCrafted {
            player,
            item,
            count,
            remaining,
            ..
        } => {
            let carrying = world
                .player(*player)
                .map_or(0, |p| p.inventory.count(*item));
            let more = match remaining {
                0 => String::new(),
                n => format!(", {n} more to go"),
            };
            format!(
                "{} crafted {count} {} (carrying {carrying}{more})",
                who(player),
                name(item)
            )
        }
        Event::CraftingStopped {
            player,
            recipe,
            reason,
        } => {
            let why = match reason {
                sim::StopReason::OutOfInputs => "ran out of inputs",
                _ => "cancelled, inputs refunded",
            };
            format!("{} stopped crafting {}: {why}", who(player), recipe.name())
        }
        Event::BuildingPlaced {
            player,
            building,
            item,
            pos,
        } => format!(
            "{} placed {} as building {} at ({}, {}); `insert {} fuel <item>` and `insert {} ore <item>` to run it",
            who(player),
            name(item),
            building.0,
            pos.x,
            pos.y,
            building.0,
            building.0
        ),
        Event::ItemsInserted {
            player,
            building,
            slot,
            item,
            count,
        } => format!(
            "{} put {count} {} into building {}'s {} slot",
            who(player),
            name(item),
            building.0,
            slot_name(*slot)
        ),
        Event::ItemsTaken {
            player,
            building,
            item,
            count,
        } => format!(
            "{} took {count} {} from building {}",
            who(player),
            name(item),
            building.0
        ),
        Event::BuildingRemoved {
            player,
            building,
            item,
            pos,
        } => format!(
            "{} picked up {} (building {}) from ({}, {})",
            who(player),
            name(item),
            building.0,
            pos.x,
            pos.y
        ),
        Event::ItemSmelted {
            building,
            item,
            count,
        } => {
            let waiting = world
                .building(*building)
                .map(|b| {
                    let sim::BuildingKind::Smelter(s) = &b.kind;
                    s.output.map_or(0, |o| o.count)
                })
                .unwrap_or(0);
            format!(
                "building {} smelted {count} {} ({waiting} waiting; `take {}`)",
                building.0,
                name(item),
                building.0
            )
        }
        Event::MoveStarted { player, from, to } => format!(
            "{} started walking from ({}, {}) to ({}, {})",
            who(player),
            from.x,
            from.y,
            to.x,
            to.y
        ),
        Event::PlayerArrived { player, pos } => {
            format!("{} arrived at ({}, {})", who(player), pos.x, pos.y)
        }
        Event::PlayerStopped { player, pos } => {
            format!("{} stopped at ({}, {})", who(player), pos.x, pos.y)
        }
        Event::CommandRejected {
            player,
            command,
            reason,
        } => {
            let why = match reason {
                RejectReason::NotOnDeposit => {
                    "you're not standing on a deposit; walk onto one first".to_string()
                }
                RejectReason::DepositDepleted => "that deposit is already depleted".to_string(),
                RejectReason::TooHardForHands => format!(
                    "that ore is too hard to mine by hand (hardness over {}); drills come later",
                    sim::tuning::HAND_MINE_MAX_HARDNESS
                ),
                RejectReason::UnknownPlayer => "no such player".to_string(),
                RejectReason::ZeroCount => "the count must be at least 1".to_string(),
                RejectReason::NotHandCraftable => {
                    "that needs a machine; `recipes` shows where each is made".to_string()
                }
                RejectReason::UnknownSpecies => "no such mineral in this world".to_string(),
                RejectReason::AlreadyAssayed => {
                    "that species is already assayed; `species` shows its sheet".to_string()
                }
                RejectReason::NotDiscovered => {
                    "nobody has mined or assayed that species yet, so nobody may name it"
                        .to_string()
                }
                RejectReason::NotDiscoverer => {
                    "only its discoverer (or someone they granted) may do that".to_string()
                }
                RejectReason::BadName(e) => match e {
                    sim::NameError::Empty => "the name is empty".to_string(),
                    sim::NameError::TooLong => format!(
                        "names are at most {} characters",
                        sim::tuning::SPECIES_NAME_MAX
                    ),
                    sim::NameError::BadCharacter => {
                        "names use letters, digits and hyphens only".to_string()
                    }
                },
                RejectReason::NoSuchPlayer => "no such player; `players` lists them".to_string(),
                RejectReason::AlreadyGranted => "they can already rename it".to_string(),
                RejectReason::MissingItems(item) => {
                    let have = world
                        .player(*player)
                        .map_or(0, |p| p.inventory.count(*item));
                    format!("not enough {} (you have {have})", name(item))
                }
                RejectReason::WrongItem => "that's the wrong kind of item for this".to_string(),
                RejectReason::AlreadyBestGrade => {
                    "grade A is already the best; refining can't improve it".to_string()
                }
                RejectReason::RequirementNotMet(property, min) => format!(
                    "its {} is below {min} at that grade; `species` shows the sheets",
                    property.name()
                ),
                RejectReason::OutOfBounds => match command {
                    PlayerCommand::MoveTo { target } => off_map(world, *target),
                    _ => "that's off the map".to_string(),
                },
                RejectReason::UnknownBuilding => {
                    "no building with that id; `buildings` lists them".to_string()
                }
                RejectReason::OutOfReach => format!(
                    "too far away; get within {} tiles of it",
                    sim::tuning::REACH
                ),
                RejectReason::TileOccupied => "another building is in the way".to_string(),
                RejectReason::NotPlaceable => "that item is not a building".to_string(),
                RejectReason::TooHotForWalls => {
                    "that ore needs more heat than this smelter's walls survive; build one from a more heat-tolerant species".to_string()
                }
                RejectReason::NotFuel => format!(
                    "that doesn't burn well enough to be fuel (reactivity below {} at that grade)",
                    sim::tuning::FUEL_MIN_REACTIVITY
                ),
                RejectReason::SlotFull => {
                    "that slot is full or holds a different item; `buildings` shows what's inside"
                        .to_string()
                }
                RejectReason::NothingToTake => "its output slot is empty".to_string(),
            };
            let whose = if *player == me {
                String::new()
            } else {
                format!("{}'s ", who(player))
            };
            format!(
                "{whose}`{}` was rejected: {why}",
                describe_command(command, world)
            )
        }
    }
}

fn parse_arg<T: std::str::FromStr>(args: &[&str], i: usize, name: &str) -> Result<T, String> {
    let raw = args.get(i).ok_or(format!("Missing {name}."))?;
    raw.parse()
        .map_err(|_| format!("`{raw}` is not a valid {name}."))
}

fn optional_arg<T: std::str::FromStr>(
    args: &[&str],
    i: usize,
    name: &str,
    default: T,
) -> Result<T, String> {
    match args.get(i) {
        Some(_) => parse_arg(args, i, name),
        None => Ok(default),
    }
}
