//! Plain-text views of the world for terminals, logs and tests.
//! Debugging aids only; real rendering lives outside the sim.

use std::fmt::Write;

use crate::assembly::{
    Assembly, AssemblyError, BreakVerdict, Built, Mount, PART_SPECS, PartKind, Source,
};
use crate::building::{Building, BuildingKind, Machine, Slot};
use crate::command::{Event, PlayerCommand, RejectReason, StopReason};
use crate::item::{Item, ItemStack};
use crate::mineral::{Grade, MineralSpecies, NameError, Property, Sheet};
use crate::ore::OreDeposit;
use crate::recipe::{RECIPES, Station};
use crate::tuning::{
    FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, HAND_WORK_PER_TICK, PICK_WEAR_PER_SWING,
    SMELTER_OUTPUT_CAP, YIELD_BY_GRADE,
};
use crate::types::{PlayerId, TilePos};
use crate::world::World;

/// An item as `kind:species:grade`, the form a player types and `inv` prints.
pub fn item_spec(world: &World, item: Item) -> String {
    format!(
        "{}:{}:{}",
        item.kind.name(),
        world.species(item.species).name().to_ascii_lowercase(),
        item.grade.letter().to_ascii_lowercase()
    )
}

/// ONE COMMAND AS A PHRASE, for naming what a rejection refused.
///
/// MOVED HERE WITH `event_line` RATHER THAN DUPLICATED, and it carries a wart
/// worth stating: this spells a command the way a player TYPES it in `sim-cli`
/// (`goto 12 5`), which is not how a player who clicked a tile in the Godot
/// client did it. Both hosts saying the same thing is still better than two
/// describers drifting, which is what this move fixes. If a graphical host wants
/// its own phrasing, the answer is a second function beside this one -- never a
/// second copy of the event match.
pub fn command_line(cmd: &PlayerCommand, world: &World) -> String {
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
            // `None` reader: nobody is "you" in a phrase describing somebody
            // else's command. The CLI passed an impossible PlayerId for this,
            // which worked and said nothing about why.
            player_name(world, None, *to)
        ),
        PlayerCommand::MakePart {
            kind,
            material,
            count,
        } => format!("make {} {} {count}", kind.name(), spec(material)),
        PlayerCommand::Assemble { frame, mounted } => format!(
            "assemble {}{}",
            spec(frame),
            mounted
                .iter()
                .map(|m| format!(" {}", spec(m)))
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

/// A slot by the name a player types, not by its variant.
fn slot_name(slot: Slot) -> &'static str {
    match slot {
        Slot::Input => "ore",
        Slot::Fuel => "fuel",
    }
}

/// Says the bounds as well as the mistake: "off the map" alone leaves a player
/// guessing which edge they fell off.
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

/// "your" for the reader, "<name>'s" for anybody else.
///
/// THIS EXISTS BECAUSE THE POSSESSIVE WAS BUILT FROM THE NAME, so the reader's
/// own events read "you's design broke" -- in the terminal client, today, on the
/// one event a player is most likely to read twice. It passed every check for
/// "does this line say you", which is how it survived: a guard can only catch
/// what it measures.
fn player_possessive(world: &World, me: Option<PlayerId>, player: PlayerId) -> String {
    if me == Some(player) {
        return "your".into();
    }
    format!("{}'s", player_name(world, me, player))
}

/// A player's name, or "you" for the reader. `None` reader means nobody is "you".
fn player_name(world: &World, me: Option<PlayerId>, player: PlayerId) -> String {
    if me == Some(player) {
        return "you".into();
    }
    world
        .player(player)
        .map_or_else(|| format!("player {}", player.0), |p| p.name.clone())
}

/// ONE EVENT AS ONE SENTENCE, FOR EVERY HOST. `me` is written "you"; everyone
/// else is named. `None` means the caller has no player yet -- a client before
/// its welcome -- so nobody is "you".
///
/// THIS LIVES HERE BECAUSE THERE WERE TWO OF IT. `sim-cli` had this match and
/// `sim-godot` had another, which meant the terminal and the Godot client could
/// word the same event differently -- and did: the Godot one had no arm for any
/// of the eight events the assembly model added, so it showed players raw Rust
/// `Debug` at the most dramatic moment in the game ("MachineBroke { player:
/// PlayerId(0), ... }"). Same reason `durability_readout` lives here: a rule
/// about what a player may know, said once.
///
/// AND THE EXHAUSTIVE MATCH BELONGS IN THIS CRATE, NOT IN A HOST. In `sim-godot`
/// it was a brake: adding an `Event` variant failed to compile the client, so
/// the sim could not grow without the renderer's permission. Here, adding a
/// variant fails to compile the crate that added it, which is the author who
/// knows what it should say.
pub fn event_line(world: &World, me: Option<PlayerId>, event: &Event) -> String {
    let who = |p: &PlayerId| player_name(world, me, *p);
    let name = |item: &Item| world.item_name(*item);
    match event {
        Event::PlayerJoined { player, name } if me == Some(*player) => {
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
                StopReason::Stopped => "stopped",
                StopReason::LeftDeposit => "walked off it",
                StopReason::Depleted => "mined it out",
                StopReason::OutOfInputs => "ran out",
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
            crate::tuning::ASSAY_TICKS
        ),
        Event::AssayStopped {
            player,
            deposit,
            reason,
        } => {
            let why = match reason {
                StopReason::LeftDeposit => "walked off it",
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
                StopReason::OutOfInputs => "ran out of inputs",
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
                .map(|b| match &b.kind {
                    BuildingKind::Smelter(s) => s.output.map_or(0, |o| o.count),
                    BuildingKind::Machine(_) => 0,
                })
                .unwrap_or(0);
            format!(
                "building {} smelted {count} {} ({waiting} waiting; `take {}`)",
                building.0,
                name(item),
                building.0
            )
        }
        Event::PartsMade {
            player,
            part,
            count,
        } => format!("{} made {count} x {}", who(player), name(part)),
        Event::Assembled { player, assembly } => {
            // Read the design out of the world, not out of the event: what the
            // player may see of it is banded until they assay (amendment A5).
            let readout = world
                .player(*player)
                .and_then(|p| p.assemblies.get(*assembly as usize))
                .map(|b| assembly_readout(world, b));
            match readout {
                Some(r) => format!("{} assembled #{assembly}: {r}", who(player)),
                None => format!("{} assembled #{assembly}", who(player)),
            }
        }
        Event::Equipped { player } => {
            let readout = world
                .player(*player)
                .and_then(|p| p.tool.as_ref())
                .map(|b| assembly_readout(world, b));
            match readout {
                Some(r) => format!("{} equipped a tool: {r}", who(player)),
                None => format!("{} equipped a tool", who(player)),
            }
        }
        Event::Unequipped { player } => format!("{} put their tool away", who(player)),
        Event::MachinePlaced {
            player,
            building,
            pos,
        } => format!(
            "{} planted machine {} at ({}, {})",
            who(player),
            building.0,
            pos.x,
            pos.y
        ),
        Event::MachineBroke {
            player,
            pos,
            mass,
            budget,
            lost,
            returned,
        } => {
            let items = |v: &[Item]| {
                if v.is_empty() {
                    "nothing".to_string()
                } else {
                    v.iter().map(name).collect::<Vec<_>>().join(", ")
                }
            };
            format!(
                "{} design broke{}: {mass} mass against a {budget} budget. Lost {}; got back {}",
                player_possessive(world, me, *player),
                pos.map_or(String::new(), |p| format!(" at ({}, {})", p.x, p.y)),
                items(lost),
                items(returned)
            )
        }
        // Names what was kept, not just what was lost: the player needs to
        // know the handle came back, because re-heading it costs a third of a
        // new pick and there is no command that would tell them so.
        Event::ToolWornOut {
            player,
            head,
            handle,
        } => format!(
            "{} {} wore out. The {} is gone; the {} is back in {} inventory — assemble it with a new head to repair it",
            player_possessive(world, me, *player),
            name(handle),
            name(head),
            name(handle),
            // "back in YOUR inventory" about somebody else's tool tells the
            // reader to go looking in their own pack for a part they never had.
            if me == Some(*player) { "your" } else { "their" }
        ),
        Event::MachineMined {
            building,
            item,
            amount,
            held,
            ..
        } => format!(
            "machine {} mined {amount} {} ({held} waiting inside)",
            building.0,
            name(item)
        ),
        Event::MachineStalled {
            building,
            held,
            capacity,
        } => format!(
            "machine {} is full at {held} of {capacity} and has stopped: take the ore out, or give it a hopper",
            building.0
        ),
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
                // "DRILLS COME LATER" WAS FALSE (ASSA-43). Decision 7 holds
                // `mine_by_machine` to the same gate, so this ore is out of
                // reach of everything the game can build — and this sentence
                // was the only thing the game said about reach at all, which
                // made our one explanation a promise we break.
                RejectReason::TooHardForHands => format!(
                    "that ore is too hard to mine (hardness over {}); a drill lifts throughput, \
                     not hardness, so nothing reaches it yet",
                    crate::tuning::HAND_MINE_MAX_HARDNESS
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
                    NameError::Empty => "the name is empty".to_string(),
                    NameError::TooLong => format!(
                        "names are at most {} characters",
                        crate::tuning::SPECIES_NAME_MAX
                    ),
                    NameError::BadCharacter => {
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
                    crate::tuning::REACH
                ),
                RejectReason::TileOccupied => "another building is in the way".to_string(),
                RejectReason::NotPlaceable => "that item is not a building".to_string(),
                RejectReason::TooHotForWalls => {
                    "that ore needs more heat than this smelter's walls survive; build one from a more heat-tolerant species".to_string()
                }
                RejectReason::NotFuel => format!(
                    "that doesn't burn well enough to be fuel (reactivity below {} at that grade)",
                    crate::tuning::FUEL_MIN_REACTIVITY
                ),
                RejectReason::SlotFull => {
                    "that slot is full or holds a different item; `buildings` shows what's inside"
                        .to_string()
                }
                RejectReason::NothingToTake => "it has nothing waiting to be taken".to_string(),
                RejectReason::BadAssembly(e) => match e {
                    AssemblyError::FrameIsNotAFrame => {
                        "the first part must be a frame: a handle for a tool, a frame to plant"
                            .to_string()
                    }
                    AssemblyError::FrameMounted => {
                        "a frame cannot be mounted on another frame".to_string()
                    }
                    AssemblyError::NoSuchSlot(kind) => {
                        format!("that frame has no {} slot at all", kind.name())
                    }
                    AssemblyError::TooFew { kind, have, min } => {
                        format!("it needs at least {min} {} and has {have}", kind.name())
                    }
                    AssemblyError::TooMany { kind, have, max } => {
                        format!("it takes at most {max} {} and was given {have}", kind.name())
                    }
                },
                RejectReason::NotAPart(item) => {
                    format!("{} is not a machine part; `parts` lists them", item.code())
                }
                RejectReason::NoSuchAssembly => {
                    "you have not built that; `built` lists what you have".to_string()
                }
                RejectReason::WrongMount => {
                    "a handle is held (`equip`) and a frame is planted (`plant`); you asked for the other one"
                        .to_string()
                }
                RejectReason::NothingEquipped => "you have nothing in hand".to_string(),
                RejectReason::NotInsertable => {
                    "that machine takes nothing in; `take` empties it".to_string()
                }
            };
            let whose = if me == Some(*player) {
                String::new()
            } else {
                format!("{}'s ", who(player))
            };
            format!(
                "{whose}`{}` was rejected: {why}",
                command_line(command, world)
            )
        }
    }
}

pub const MAP_LEGEND: &str =
    "P player   @ spawn   M smelter   letters = ore by species initial (lowercase = depleted)";

/// One-line summary: seed, tick, size, deposit count and state hash.
pub fn summary(world: &World) -> String {
    format!(
        "seed {} · tick {} · {}x{} tiles · {} species · {} deposits · hash {:016x}",
        world.seed,
        world.tick,
        world.width(),
        world.height(),
        world.species.len(),
        world.deposits.len(),
        world.state_hash()
    )
}

/// The map letter for a species: its generated name's initial, which is
/// unique per world (player names need not be).
pub fn species_symbol(species: &MineralSpecies) -> char {
    species
        .generated_name
        .chars()
        .next()
        .map_or('?', |c| c.to_ascii_uppercase())
}

/// ASCII map, one character per tile.
pub fn ascii_map(world: &World) -> String {
    let spawn = world.spawn_tile();
    let mut out = String::new();
    for y in 0..world.height() {
        for x in 0..world.width() {
            let pos = TilePos::new(x, y);
            let c = if world.players.iter().any(|p| p.pos == pos) {
                'P'
            } else if world.building_at(pos).is_some() {
                'M'
            } else if pos == spawn {
                '@'
            } else if let Some(d) = world.deposit_at(pos) {
                let s = species_symbol(world.species(d.species));
                if d.is_depleted() {
                    s.to_ascii_lowercase()
                } else {
                    s
                }
            } else {
                '.'
            };
            out.push(c);
        }
        out.push('\n');
    }
    out
}

/// Why nothing can mine this deposit, if nothing can; `None` when the ore is
/// within reach and there is nothing to say.
///
/// **AN UNREACHABLE ROCK IS A PROMISE; AN UNEXPLAINED ONE IS A BUG** (Game
/// Director, ASSA-43). Over 2000 worlds, 40.7% of deposits are of a species the
/// gate refuses and 27.9% of worlds hold one in the spawn chunk, so this is the
/// common case and not the corner — a player meets one before they meet a
/// smelter.
///
/// It asks [`crate::ladder::hand_minable`], the function `step` itself asks, so
/// a deposit cannot read as minable and then refuse the swing.
///
/// **IT DOES NOT SAY "DRILLS COME LATER".** They do not: decision 7 holds
/// `mine_by_machine` to the same gate, so a deposit too hard for hands is too
/// hard for every machine in the game. The old rejection sentence promised the
/// opposite and that was the only thing the game said about reach at all.
pub fn deposit_reach_note(world: &World, deposit: &OreDeposit) -> Option<String> {
    let species = world.species(deposit.species);
    (!crate::ladder::hand_minable(species)).then(|| {
        format!(
            "{} is too hard for anything we can build: hardness is over \
             {HAND_MINE_MAX_HARDNESS}, and a drill lifts throughput, not hardness",
            species.name()
        )
    })
}

/// Table of every deposit.
pub fn deposit_table(world: &World) -> String {
    let mut out = format!(
        "{:>4}  {:<12} {:>10}  {:>6}  {:>6}  {:>6}  {:>5}  notes\n",
        "id", "species", "center", "radius", "amount", "purity", "grade"
    );
    for d in &world.deposits {
        let center = format!("({}, {})", d.center.x, d.center.y);
        // The listing is where a player compares deposits, so it is the worst
        // place to leave reach out: four of ten rows here are rock nothing can
        // break, and before this they looked exactly like the six that yield.
        let mut notes = Vec::new();
        if d.is_depleted() {
            notes.push("mined out".to_string());
        }
        if let Some(why) = deposit_reach_note(world, d) {
            notes.push(why);
        }
        let _ = writeln!(
            out,
            "{:>4}  {:<12} {:>10}  {:>6}  {:>6}  {:>6}  {:>5}  {}",
            d.id.0,
            world.species(d.species).name(),
            center,
            d.radius,
            d.amount,
            d.purity,
            d.grade().letter(),
            notes.join(" · ")
        );
    }
    out
}

/// One property as a player sees it: exact once assayed, else its band.
pub fn reading(species: &MineralSpecies, property: Property) -> String {
    let v = species.sheet.get(property);
    if species.assayed {
        v.to_string()
    } else {
        let (lo, hi) = Sheet::band(v);
        format!("{lo}-{hi}")
    }
}

/// Table of every species with its sheet as the players know it (rough
/// bands until assayed), plus what the sheet means for the rules that
/// exist today. Notes use the exact values: the ground knows what it is.
pub fn species_table(world: &World) -> String {
    let mut out = format!(
        "{:>2}  {:<12} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6}  notes\n",
        "id", "name", "dens", "str", "hard", "heat", "reac", "cond"
    );
    for s in &world.species {
        let sh = &s.sheet;
        let mut notes = Vec::new();
        // REACH FIRST, AND NO ASSAY INVITATION ON A SPECIES NOTHING CAN MINE
        // (ASSA-43). `Assay` is not hardness-gated, so a player invited here
        // can spend the ticks, succeed, and learn a sheet they can never
        // spend: you cannot build with ore you cannot mine. The Game
        // Director's rule for the Godot tile line is that reach comes before
        // the invitation and replaces it — the headless game must not be the
        // one with less information, so it holds here too.
        if crate::ladder::hand_minable(s) {
            notes.push("hand-minable".to_string());
            if !s.assayed {
                notes.push("rough: stand on it and `assay`".to_string());
            }
        } else {
            notes.push("too hard for anything we can build".to_string());
        }
        if let Some(d) = s.discoverer {
            let who = world
                .player(d)
                .map_or(format!("player {}", d.0), |p| p.name.clone());
            notes.push(format!("found by {who}"));
        }
        for grade in Grade::ALL.into_iter().rev() {
            if s.effective(Property::Reactivity, grade) >= FUEL_MIN_REACTIVITY {
                notes.push(format!("fuel at {} or better", grade.letter()));
                break;
            }
        }
        let _ = sh;
        let _ = writeln!(
            out,
            "{:>2}  {:<12} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6}  {}",
            s.id.0,
            s.name(),
            reading(s, Property::Density),
            reading(s, Property::Strength),
            reading(s, Property::Hardness),
            reading(s, Property::HeatTolerance),
            reading(s, Property::Reactivity),
            reading(s, Property::Conductivity),
            notes.join(", ")
        );
    }
    out
}

/// Table of every recipe.
pub fn recipe_table() -> String {
    let mut out = format!(
        "{:<8} {:<16} {:<12} {:>5}  {:<16} needs\n",
        "name", "makes", "from", "ticks", "where"
    );
    for r in &RECIPES {
        let from = format!("{} {}", r.input.1, r.input.0.name());
        let makes = format!(
            "{} {}{}",
            r.output.1,
            r.output.0.name(),
            if r.raises_grade { " +1 grade" } else { "" }
        );
        let station = match r.station {
            Station::Hand => "by hand (craft)",
            Station::Smelter => "in a smelter",
        };
        let mut needs: Vec<String> = r
            .requires
            .iter()
            .map(|(p, min)| format!("{} ≥ {min}", p.name()))
            .collect();
        if r.station == Station::Smelter {
            needs.push("fire ≥ the ore's heat tolerance".into());
        }
        let _ = writeln!(
            out,
            "{:<8} {makes:<16} {from:<12} {:>5}  {station:<16} {}",
            r.name,
            r.ticks,
            if needs.is_empty() {
                "nothing".to_string()
            } else {
                needs.join(", ")
            }
        );
    }
    out.push_str(
        "Every recipe keeps the input's species. sort and resmelt raise its grade by one\n(C->B->A) and lose two thirds of the material; by hand: craft sort <ore> [n].\n",
    );
    out
}

fn slot(world: &World, stack: Option<ItemStack>) -> String {
    stack.map_or("empty".to_string(), |st| {
        format!("{} {}", st.count, world.item_name(st.item))
    })
}

/// The parts a design is made of, as `handle(Korvite B 150) + head(Adaite A
/// 26-50)`.
///
/// **The mass is per part and banded like every other sheet reading**, because
/// a player looking at an over-budget design picks which part to change out of
/// this line, and the heaviest non-frame part is also the one a break always
/// loses. Last on the line on purpose: the inspector's side panel truncates it
/// and the kinds and species must survive that.
pub fn parts_summary(world: &World, assembly: &Assembly) -> String {
    assembly
        .parts()
        .map(|p| {
            let species = world.species(p.material.species);
            let (low, high) = Assembly::part_mass_range(p, species);
            format!(
                "{}({} {} {})",
                p.kind.name(),
                species.name(),
                p.material.grade.letter(),
                if low == high {
                    low.to_string()
                } else {
                    format!("{low}-{high}")
                }
            )
        })
        .collect::<Vec<_>>()
        .join(" + ")
}

/// One line describing a planted machine.
///
/// **No durability here, on purpose** (Game Director's ruling on ASSA-5):
/// the head contributes a durability pool whatever frame it sits on, but
/// decision 12 parks drill wear, so on a planted machine that number would
/// never move — and a number that never moves teaches a mechanic that does not
/// exist. The catalogue row is untouched; this is a display rule.
pub fn machine_status(world: &World, b: &Building, m: &Machine) -> String {
    let range = m.assembly.stat_range(&world.species);
    let show = |low: u32, high: u32| {
        if low == high {
            low.to_string()
        } else {
            format!("{low}-{high}")
        }
    };
    // Capacity is flat from the kind, so it is exact whether or not anyone has
    // assayed anything; mass and speed are read off sheets and are not.
    let capacity = range.low.capacity;
    // EVERY WAY A DRILL CAN BE DOING NOTHING HAS TO SAY SO HERE, because the
    // alternative is a player watching a machine they paid eight refined for
    // and guessing. A5's rule — the bad case must be visible — is not only
    // about mass.
    let state = match world.deposit_at(b.pos) {
        None => "idle: no deposit underneath".to_string(),
        Some(d) if d.is_depleted() => "idle: deposit is mined out".to_string(),
        // Decision 7: a drill is a throughput upgrade, never a hardness
        // unlock, so it refuses exactly what hands refuse. Without this line
        // that refusal is invisible and reads as a bug. The sentence is
        // `deposit_reach_note`'s now, so a drill and the rock it sits on can
        // never give a player two different stories about the same gate.
        Some(d) => {
            if let Some(why) = deposit_reach_note(world, d) {
                format!("idle: {why}")
            // The sim stops a machine that has no room for a WHOLE unit, so
            // the readout has to use the same test or it will call a stopped
            // drill "mining" for the last few units of its buffer.
            } else if m.held.map_or(0, |h| h.count) + YIELD_BY_GRADE[d.grade() as usize] > capacity
            {
                "stalled: full, take the ore out".to_string()
            } else {
                format!("mining {}", world.species(d.species).name())
            }
        }
    };
    // Same reason as `assembly_readout`: what it is holding and what it is
    // doing come before the design it was built from, because the table line
    // is truncated in the inspector's side panel.
    format!(
        "holding {} of {} · {state} · mass {} of {} budget · speed {} · {}",
        m.held.map_or(0, |h| h.count),
        capacity,
        show(range.low.mass, range.high.mass),
        show(range.low.budget, range.high.budget),
        show(range.low.speed, range.high.speed),
        parts_summary(world, &m.assembly),
    )
}

/// One line describing what a building holds and whether it is working.
pub fn building_status(world: &World, b: &Building) -> String {
    let s = match &b.kind {
        BuildingKind::Smelter(s) => s,
        BuildingKind::Machine(m) => return machine_status(world, b, m),
    };
    let walls = world.max_temperature(b);
    let needs = s
        .input
        .map(|i| u32::from(world.species(i.item.species).sheet.heat_tolerance));
    let state = if s.input.is_none() {
        "idle: nothing to refine".to_string()
    } else if s.output.is_some_and(|o| o.count >= SMELTER_OUTPUT_CAP) {
        "stalled: output full".to_string()
    } else if s.burn_left == 0 && s.fuel.is_none() {
        "stalled: no fuel".to_string()
    } else if s.burn_left == 0 {
        "stalled: fuel won't light from cold".to_string()
    } else if needs.is_some_and(|n| s.burn_temperature.min(walls) < n) {
        format!(
            "stalled: fire {} too cool for ore needing {}",
            s.burn_temperature.min(walls),
            needs.unwrap_or(0)
        )
    } else {
        format!("working at {}", s.burn_temperature.min(walls))
    };
    format!(
        "walls {walls} · in {} · fuel {} ({} ticks burning at {}) · out {} · {state}",
        slot(world, s.input),
        slot(world, s.fuel),
        s.burn_left,
        s.burn_temperature,
        slot(world, s.output)
    )
}

/// Table of every building.
pub fn building_table(world: &World) -> String {
    if world.buildings.is_empty() {
        return "No buildings yet. Craft a smelter from 5 ore and `place smelter`.\n".into();
    }
    let mut out = format!("{:>4}  {:<8} {:>9}  status\n", "id", "kind", "at");
    for b in &world.buildings {
        let _ = writeln!(
            out,
            "{:>4}  {:<8} {:>9}  {} · {}",
            b.id.0,
            b.kind.name(),
            format!("({}, {})", b.pos.x, b.pos.y),
            world.item_name(b.material),
            building_status(world, b)
        );
    }
    out
}

/// The part catalogue: every row, what it costs, and what it contributes.
///
/// Generated from `PART_SPECS` and naming no kind, so a row added to the
/// catalogue appears here without this function being touched.
pub fn part_table() -> String {
    let mut out = format!("{:<8} {:<9} {:>5}  contributes\n", "name", "mount", "size");
    for s in &PART_SPECS {
        let mount = match s.kind {
            PartKind::Frame(Mount::Held) => "held",
            PartKind::Frame(Mount::Planted) => "planted",
            _ => "mounted",
        };
        let gives = s
            .contributions
            .iter()
            .map(|c| match c.source {
                Source::Property(p) => format!("{:?} from {}", c.stat, p.name()),
                Source::Flat(n) => format!("{:?} {n}", c.stat),
            })
            .collect::<Vec<_>>()
            .join(", ");
        let _ = writeln!(out, "{:<8} {mount:<9} {:>5}  {gives}", s.name, s.size);
    }
    let _ = write!(
        out,
        "\nsize is both the refined cost and how much stuff the part is made of for\n\
         mass. A frame carries mass = size x strength x {}; over that, the design\n\
         breaks when it is planted or first used. `make <part> <refined>` then\n\
         `assemble <frame> <part>...`.\n",
        crate::tuning::FRAME_BUDGET_PER_STRENGTH
    );
    out
}

/// THE PICK'S LIFE AS A PLAYER MAY READ IT: **swings used, out of the swings
/// its class affords.** `20 of 120-180 swings used` while any species in it is
/// rough, `20 of 144 swings used` once they are all known.
///
/// **Public and shared on purpose.** The Godot part menu shows this same
/// number (`sim-godot`'s `designs_of`), and A10 is a rule about what a player
/// is allowed to know, not a formatting preference — two hosts spelling it
/// two ways is how the leak comes back in one of them. One wording, one place.
///
/// **Why not a percentage, which is what A10 first said** (the Game Director
/// reversed it on ASSA-5 after Limpet measured the hole): a pool is always a
/// multiple of `PICK_WEAR_PER_SWING`, so only 21 values fit the 2400-3600
/// band, and an integer percent plus the player's own swing count narrows it
/// to exactly one — after **6 swings** for a 2400 pool, 16 for 3600, worst
/// case 61 out of a 120-180 life. A leak is measured in *when*, not whether:
/// the pick's death gives the pool away too, but at swing 120-180, long after
/// the design decision is dead.
///
/// This form leaks nothing by construction. `used` is the player's own count —
/// they took those swings — and the band ends are the rough sheet's own. It
/// also retires `1800/2400` points, a unit nothing else in the game uses.
///
/// **One narrowing of the ruling's letter, with its reason.** The ruling said
/// `div_ceil` throughout, and that was right for the percentage, where its
/// purpose was that a pick with a swing left must never read 0%. Pointed at
/// `used`, ceiling rounds the *other* way: a pool of 1 point would read
/// `144 of 144 swings used`, which is a working pick reading as a spent one —
/// the same defect, inverted. So **capacity ceils and consumption floors**:
/// `used` is swings completed, the band ends and the max are what a pool of
/// that size affords (the last swing drains a part-full pool and still
/// yields). For every state a player can actually reach the two agree, because
/// wear subtracts exactly `PICK_WEAR_PER_SWING` at a time.
pub fn durability_readout(world: &World, built: &Built) -> String {
    let range = built.assembly.stat_range(&world.species);
    let max = built.assembly.stats(&world.species).durability;
    let affords = |pool: u32| pool.div_ceil(PICK_WEAR_PER_SWING);
    let used = max.saturating_sub(built.durability) / PICK_WEAR_PER_SWING;
    if range.low.durability == range.high.durability {
        format!("{used} of {} swings used", affords(max))
    } else {
        format!(
            "{used} of {}-{} swings used",
            affords(range.low.durability),
            affords(range.high.durability)
        )
    }
}

/// One line for a design the player has built: what it is, what it weighs
/// against its budget, and the verdict.
///
/// The verdict and the numbers come from `sim` (the Game Director's ruling on
/// ASSA-5): two clients computing this would eventually disagree, and a
/// renderer does not own rules. Banded while any part's species is unassayed,
/// exact once they are all known.
///
/// **Durability only for a held frame** (same ruling): the head contributes a
/// pool whatever frame it sits on, but drill wear is parked, so showing it on a
/// planted design would teach a mechanic that does not exist.
///
/// **The pool itself is banded like everything else** (amendment A10): exact
/// against its true max once the sheet is known, a percentage of the pool's
/// *class* while it is not. See the held branch for why a number there was a
/// leak.
pub fn assembly_readout(world: &World, built: &Built) -> String {
    let a = &built.assembly;
    let range = a.stat_range(&world.species);
    let show = |low: u32, high: u32| {
        if low == high {
            low.to_string()
        } else {
            format!("{low}-{high}")
        }
    };
    // Verdict first, then the numbers, then the parts. Deliberate: a side
    // panel is narrow and the line gets truncated, so the thing the player
    // needs before spending parts must not be the thing that is cut.
    let mut out = format!(
        "{} · mass {} of {} budget",
        range.verdict().label(),
        show(range.low.mass, range.high.mass),
        show(range.low.budget, range.high.budget),
    );
    match a.mount() {
        Some(Mount::Held) => {
            // THE POOL IS NEVER PRINTED AS A NUMBER WHILE THE SHEET IS BANDED
            // (ADR 0003 amendment A10). `pool_max = HEAD_SIZE x eff strength x
            // PICK_DURABILITY_PER_STRENGTH`, and both constants are published,
            // so an exact pool divided by 60 *is* the head's effective
            // strength -- and `(pool + 20 x swings) / 60` recovers it at any
            // moment, not only at full. It was the one `Source::Property` stat
            // read exactly while mass and budget were banded, which made a
            // pick a free assay of strength.
            //
            // It is now said in SWINGS rather than as a percentage of the
            // band, which closed the rest of the same hole: see
            // `durability_readout`.
            // The label stays, and so does the Godot menu's own: a host may
            // name the field, but the NUMBER is worded once, here. A label is
            // not a thing a leak can come back through.
            let _ = write!(out, " · durability {}", durability_readout(world, built));
        }
        _ => {
            let _ = write!(
                out,
                " · holds {}",
                show(range.low.capacity, range.high.capacity)
            );
        }
    }
    // THE HANDS' RATE, BESIDE THE DESIGN'S (the Game Director's ruling 5 on
    // ASSA-6). `speed` is work per tick, the same unit bare hands are measured
    // in, so the comparison needs no arithmetic from the player — but without
    // the baseline printed, `speed 23` looks like a tool and is in fact slower
    // than the hands that built it, and nothing in the game said so before
    // three refined were spent. Measured: at the old factor a grade-C pick
    // lost to bare hands for EVERY minable species.
    //
    // Shown for planted designs too, deliberately. It is not the mirror of
    // ruling 1 (durability on a drill is a number that never moves): a drill's
    // rate against your own hands is the live question "is planting this
    // better than swinging myself", and it moves with the head. One
    // conditional to narrow it to held designs if that reads wrong on a drill.
    let _ = write!(
        out,
        " · speed {} (bare hands {HAND_WORK_PER_TICK}) · {}",
        show(range.low.speed, range.high.speed),
        parts_summary(world, a)
    );
    if range.verdict() != BreakVerdict::Safe {
        let _ = write!(
            out,
            "\n      {}",
            match range.verdict() {
                BreakVerdict::WillBreak =>
                    "this is over budget: it will break when planted or first used",
                _ => "assay every species in it to know whether it will hold",
            }
        );
    }
    out
}

/// What the player has built but not placed, and what is in their hand.
pub fn built_table(world: &World, player: PlayerId) -> String {
    let Some(p) = world.player(player) else {
        return "No such player.\n".into();
    };
    let mut out = String::new();
    match &p.tool {
        Some(t) => {
            let _ = writeln!(out, "in hand  {}", assembly_readout(world, t));
        }
        None => out.push_str("in hand  nothing (bare hands)\n"),
    }
    if p.assemblies.is_empty() {
        out.push_str(
            "built    nothing. `parts` lists the catalogue; `make <part> <refined>`\n\
             \x20        then `assemble <frame> <part>...`.\n",
        );
        return out;
    }
    for (i, built) in p.assemblies.iter().enumerate() {
        let _ = writeln!(out, "{i:>5}    {}", assembly_readout(world, built));
    }
    let _ = write!(
        out,
        "\n`equip <n>` takes a held design in hand; `plant <n> [x y]` puts a planted\n\
         one on the map.\n"
    );
    out
}
