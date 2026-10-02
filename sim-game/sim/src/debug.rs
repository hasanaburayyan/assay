//! Plain-text views of the world for terminals, logs and tests.
//! Debugging aids only; real rendering lives outside the sim.

use std::fmt::Write;

use crate::assembly::{
    Assembly, AssemblyError, BreakVerdict, Built, Mount, PART_SPECS, PartKind, Source,
};
use crate::building::{Building, BuildingKind, Machine, Slot, SmelterStall, SmelterState};
use crate::command::{Event, PlayerCommand, RejectReason, StopReason};
use crate::item::{Item, ItemKind, ItemStack};
use crate::ladder::Lighting;
use crate::mineral::{Grade, MineralSpecies, NameError, Property, Sheet, SpeciesId};
use crate::ore::OreDeposit;
use crate::recipe::{RECIPES, Station};
use crate::tuning::{
    FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, HAND_WORK_PER_TICK, PICK_WEAR_PER_SWING,
    YIELD_BY_GRADE,
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

/// ONE COMMAND AS AN ACTION, in words that belong to no host.
///
/// **THE SECOND FUNCTION [`command_line`]'s OWN COMMENT PREDICTED** (Game
/// Director, ASSA-70). `event_line` is rendered verbatim by the Godot client, so
/// a player who pressed **Fuel** was reading `` `insert 0 fuel ore:minyte:b 10`
/// was rejected `` — a command line, in a window that has none. ASSA-67 took
/// that syntax out of thirteen literal sentences and could not touch this one:
/// here the command is a runtime *value*, so no scan of the source ever saw it.
///
/// The split, and which half is shared: **the prose one is.** `event_line` calls
/// this; `sim-cli` keeps [`command_line`] for its own voice — the queue echo and
/// its usage messages — where syntax is exactly right because the reader has a
/// prompt. One describer each, neither duplicating the other's match.
///
/// **EVERY PHRASE IS A GERUND, AND THAT IS LOAD-BEARING**, not taste. The
/// sentence it goes into keeps the possessive prefix co-op needs ("" for you,
/// "Ada's " for anyone else), and a possessive can only take a noun phrase:
/// "Ada's moving to (12, 5) was refused" works where "Ada's move to (12, 5)"
/// and "Ada's your move" do not. Each phrase reuses the nouns of the event that
/// *would* have happened, so a refusal reads as the mirror of its success
/// ("you put 10 Tonore ore (B) into building 0's fuel slot" against "putting 10
/// Tonore ore (B) into building 0's fuel slot was refused: ...").
pub fn command_phrase(cmd: &PlayerCommand, world: &World) -> String {
    let name = |item: &Item| world.item_name(*item);
    let species = |s: &SpeciesId| world.species(*s).name().to_string();
    match cmd {
        PlayerCommand::Mine => "mining".into(),
        PlayerCommand::Craft {
            recipe,
            item,
            count,
        } => format!("crafting {count} {} from {}", recipe.name(), name(item)),
        PlayerCommand::Place { item, pos } => {
            format!("placing {} at ({}, {})", name(item), pos.x, pos.y)
        }
        PlayerCommand::Insert {
            building,
            slot,
            item,
            count,
        } => format!(
            "putting {count} {} into building {}'s {} slot",
            name(item),
            building.0,
            slot_name(*slot)
        ),
        PlayerCommand::Take { building } => format!("taking from building {}", building.0),
        PlayerCommand::Pickup { building } => format!("picking up building {}", building.0),
        PlayerCommand::Assay => "assaying".into(),
        PlayerCommand::Rename { species: s, name } => {
            format!("naming {} \"{name}\"", species(s))
        }
        PlayerCommand::GrantRename { species: s, to } => format!(
            "letting {} name {}",
            // `None` reader, for [`command_line`]'s reason: nobody is "you" in a
            // phrase describing somebody else's command.
            player_name(world, None, *to),
            species(s)
        ),
        PlayerCommand::MakePart {
            kind,
            material,
            count,
        } => format!("making {count} x {} from {}", kind.name(), name(material)),
        PlayerCommand::Assemble { frame, mounted } => format!(
            "assembling {} with {}",
            name(frame),
            if mounted.is_empty() {
                "nothing mounted on it".to_string()
            } else {
                mounted.iter().map(name).collect::<Vec<_>>().join(", ")
            }
        ),
        PlayerCommand::Equip { assembly } => format!("taking #{assembly} in hand"),
        // "putting the tool away", not "your tool": the possessive belongs to
        // the prefix, and "Ada's putting your tool away" is what the other
        // reading produces. Read in `--plain` before it was worded this way.
        PlayerCommand::Unequip => "putting the tool away".into(),
        PlayerCommand::PlaceAssembly { assembly, pos } => {
            format!("planting #{assembly} at ({}, {})", pos.x, pos.y)
        }
        PlayerCommand::MoveTo { target } => {
            format!("moving to ({}, {})", target.x, target.y)
        }
        PlayerCommand::Stop => "stopping".into(),
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

/// The possessive a sentence uses when the owner is already its subject:
/// "**your** tool" to the reader, "**their** tool" about anybody else.
///
/// **THE SAME BUG AS [`player_possessive`]'s, ONE PRONOUN FURTHER ALONG**
/// (ASSA-74). `Unequipped` said "{} put **their** tool away" for every reader,
/// so your own log told you that you had put somebody else's tool away — on an
/// action with a button in the client. `PickWornOut` had the conditional right
/// and inline, which is how one arm of the pair drifted from the other.
///
/// It is a function and not two literals so that **no "your" or "their" survives
/// in [`event_line`]**, which turns the rule into a guard a test can read off the
/// source instead of a list of today's sentences. `None` reader means nobody is
/// the reader, so everything is "their" — the same convention as the two
/// functions above it.
fn reader_possessive(me: Option<PlayerId>, player: PlayerId) -> &'static str {
    if me == Some(player) { "your" } else { "their" }
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
            // The syntax went and the exclamation STAYED: `first_plate.rs`
            // uses this line as a waypoint in the reference play-through, and
            // trimming a character off someone else's pin to suit my rewording
            // is the wrong way round. `who` twice so it is true for both
            // readers - only the discoverer may name it.
            "{} discovered {}! {} may name it",
            who(player),
            world.species(*species).name(),
            who(player),
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
            "{} placed {} as building {} at ({}, {}){}",
            who(player),
            name(item),
            building.0,
            pos.x,
            pos.y,
            // ONLY WHERE IT IS TRUE: a machine takes nothing in
            // (`NotInsertable` is its own rejection), so it gets the bare
            // placement sentence rather than a hint I would be inventing.
            //
            // **CORRECTION, MINE, ON THE GAME DIRECTOR'S READING OF #94.** This
            // comment used to say "this event fires for a planted machine too".
            // It does not: `Place` accepts only a smelter (`for_item` is `Some`
            // for `ItemKind::Smelter` alone, else `NotPlaceable`) and a planted
            // machine emits `MachinePlaced`, so `BuildingPlaced` has one emitter
            // and the `else` arm is unreachable today. The `if` stays as
            // future-proofing; the false fact about the event model does not.
            if item.kind == ItemKind::Smelter {
                "; it needs fuel and ore before it will run"
            } else {
                ""
            }
        ),
        // A CLAMP THAT DOES NOT SAY WHAT IT REFUSED IS A SILENT PARTIAL
        // SUCCESS (ASSA-48). The leftover is the half a player can act on: it
        // is the difference between "the slot took what it could" and "I still
        // have 167 of these and I do not know why".
        Event::ItemsInserted {
            player,
            building,
            slot,
            item,
            count,
            left,
        } => format!(
            "{} put {count} {} into building {}'s {} slot{}",
            who(player),
            name(item),
            building.0,
            slot_name(*slot),
            if *left > 0 {
                format!("; {left} would not fit, still in hand")
            } else {
                String::new()
            }
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
                "building {} smelted {count} {} ({waiting} waiting to be taken)",
                building.0,
                name(item)
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
        Event::Unequipped { player } => format!(
            "{} put {} tool away",
            who(player),
            reader_possessive(me, *player)
        ),
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
            // The conditional used to be here, inline; it is `reader_possessive`
            // now because `Unequipped` got the same choice wrong while this arm
            // got it right (ASSA-74).
            reader_possessive(me, *player)
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
        Event::SmelterStalled { building, why } => {
            format!("smelter {} stopped: {}", building.0, stall_reason(*why))
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
                // "DRILLS COME LATER" WAS FALSE (ASSA-43). Decision 7 holds
                // `mine_by_machine` to the same gate, so this ore is out of
                // reach of everything the game can build — and this sentence
                // was the only thing the game said about reach at all, which
                // made our one explanation a promise we break.
                //
                // AND IT MUST NOT SAY "YET" EITHER (Game Director's wording
                // ruling). The first fix read "so nothing reaches it yet",
                // which is the same promise in one word: "yet" says a later
                // thing arrives, and decision 7 says none does. The guard in
                // `tests/reach.rs` now refuses a set of future-tense words
                // rather than the one phrase we had already deleted.
                //
                // THIS IS THE STRONGEST OF THE THREE REACH SENTENCES ON
                // PURPOSE: it is the only one a player reads at the moment
                // they acted, so it carries the whole fact rather than the
                // short form.
                RejectReason::TooHardForHands => format!(
                    "nothing can mine that: hardness is over {}, and a drill mines faster, \
                     not harder",
                    crate::tuning::HAND_MINE_MAX_HARDNESS
                ),
                RejectReason::UnknownPlayer => "no such player".to_string(),
                RejectReason::ZeroCount => "the count must be at least 1".to_string(),
                RejectReason::NotHandCraftable => {
                    "that needs a machine to make, not bare hands".to_string()
                }
                RejectReason::UnknownSpecies => "no such mineral in this world".to_string(),
                RejectReason::AlreadyAssayed => {
                    "that species is already assayed, so its sheet already reads exact"
                        .to_string()
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
                RejectReason::NoSuchPlayer => "nobody in this world has that name".to_string(),
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
                    "its {} is below {min} at that grade",
                    property.name()
                ),
                RejectReason::OutOfBounds => match command {
                    PlayerCommand::MoveTo { target } => off_map(world, *target),
                    _ => "that's off the map".to_string(),
                },
                RejectReason::UnknownBuilding => {
                    "nothing is built with that id".to_string()
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
                    "that slot is full or holds a different item".to_string()
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
                    format!(
                        "{} is not a machine part; parts are {}",
                        item.code(),
                        // From the catalogue, so a new part kind names itself
                        // here without anyone editing this sentence.
                        PartKind::ALL
                            .iter()
                            .map(|k| k.name())
                            .collect::<Vec<_>>()
                            .join(", ")
                    )
                }
                RejectReason::NoSuchAssembly => {
                    "you have not built that design".to_string()
                }
                RejectReason::WrongMount => {
                    "a handle is held and a frame is planted; you asked for the other one"
                        .to_string()
                }
                RejectReason::NothingEquipped => "you have nothing in hand".to_string(),
                RejectReason::NotInsertable => {
                    "that machine takes nothing in; it only gives out what it has mined"
                        .to_string()
                }
            };
            let whose = if me == Some(*player) {
                String::new()
            } else {
                format!("{}'s ", who(player))
            };
            // **THE REFUSAL NAMES THE ACTION, LIKE EVERY OTHER SENTENCE HERE**
            // (ASSA-70). It used to spell the command as `sim-cli` syntax, so a
            // player who pressed Fuel read `insert 0 fuel ore:minyte:b 10` back.
            // The `why` half is untouched and still said once, for every host.
            format!(
                "{whose}{} was refused: {why}",
                command_phrase(command, world)
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
            "{} is too hard for anything you can build: hardness is over \
             {HAND_MINE_MAX_HARDNESS}, and a drill mines faster, not harder",
            species.name()
        )
    })
}

/// A species you can mine and can never smelt, said without quoting its sheet.
///
/// **THE QUIETER HALF OF ASSA-43** (Game Director, ASSA-52). The hardness gate
/// *refuses*, so a player learns in one press. This one accepts: you mine it,
/// `amount` pays out generously, and the first thing that mentions a problem is
/// `that ore needs more heat than this smelter's walls survive` — which blames
/// the smelter, after the smelter has been paid for. 13.6% of deposits.
///
/// **IT NAMES NO NUMBER ON PURPOSE.** The reach sentence can quote
/// `HAND_MINE_MAX_HARDNESS` because that is a rule, the same in every world. A
/// species' heat tolerance is its *sheet*, which reads as a 25-wide band until
/// somebody assays it — printing it here would hand over a reading the player
/// has not earned and make the assay pointless for the one rock it matters on.
///
/// **AND IT DOES NOT SAY WHICH HALF FAILED.** The blocker may be the fire or
/// the walls that must survive it ([`crate::ladder::rungs`] weighs both), so a
/// sentence blaming the fire would be wrong in some worlds. "nothing you can
/// build and light" is true in all of them.
fn unsmeltable_note(world: &World, species: SpeciesId) -> Option<String> {
    let s = world.species(species);
    (crate::ladder::hand_minable(s)
        && !crate::ladder::usable_from_bare_hands(&world.species, species))
    .then(|| {
        format!(
            "{} can be mined but not smelted: no smelter you can build and light will refine it",
            s.name()
        )
    })
}

/// Why this rock is a dead end, if it is: the ONE slot every host reads.
///
/// **HARDNESS WINS WHEN BOTH APPLY** (Game Director's ruling on ASSA-52).
/// Telling a player that a rock they cannot even break also cannot be smelted
/// is two problems where they have one, and the one they have is the swing that
/// will not land.
///
/// Precedence lives here rather than at five call sites, because a rule that
/// has to be remembered by each caller is a rule that one caller will get
/// wrong.
pub fn deposit_dead_end_note(world: &World, deposit: &OreDeposit) -> Option<String> {
    deposit_reach_note(world, deposit).or_else(|| unsmeltable_note(world, deposit.species))
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
        if let Some(why) = deposit_dead_end_note(world, d) {
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
        if !s.assayed {
            notes.push("rough: stand on it and `assay`".to_string());
        }
        if let Some(d) = s.discoverer {
            let who = world
                .player(d)
                .map_or(format!("player {}", d.0), |p| p.name.clone());
            notes.push(format!("found by {who}"));
        }
        let minable = crate::ladder::hand_minable(s);
        if !minable {
            // The absence of a note used to be the only cue, and absence is not
            // a cue: this is the half of the roster nothing can mine.
            notes.push("too hard for anything you can build".to_string());
        } else if !crate::ladder::usable_from_bare_hands(&world.species, s.id) {
            // **BARE "hand-minable" READ AS A PROMISE** (Game Director,
            // ASSA-52). It is the truth about the swing and says nothing about
            // the ore, and for 13.6% of deposits the ore is where it ends. The
            // row still begins "hand-minable" because that part is true and a
            // player comparing rows is comparing swings.
            // Terse here on purpose: a table row is read against five other
            // rows, and the full explanation belongs on the deposit line where
            // a player is standing on the thing. "hand-minable" still leads,
            // because that half is true and is what a player comparing swings
            // is comparing.
            notes.push("hand-minable, but not smeltable".to_string());
        } else {
            notes.push("hand-minable".to_string());
        }
        // **"FUEL" USED TO BE A PURE REACTIVITY TEST AND NEVER ASKED WHETHER
        // THE PLAYER COULD SET THE THING ALIGHT** (Game Director, ASSA-58).
        // Over 5000 worlds half of these labels would not light a cold
        // smelter, and of those, 56.3% can never be lit in that world at all:
        // a label naming a use the world does not have. The light state is
        // therefore on every fuel row a player could ever mine — absence is not
        // a cue, the same argument the hand-minable clause above makes. (It
        // used to be every fuel row full stop; ASSA-68 below amended that, and
        // the slot is still occupied on the rows it took it from.)
        //
        // The grade stays on the burn half and is missing from the light half
        // because reactivity scales with grade and heat tolerance does not.
        // `ladder` decides both; this only words them.
        //
        // Grades ascend (`Grade::ALL` is C, B, A) so the clause names the
        // CHEAPEST grade that burns. It used to iterate `.rev()` and break on
        // the first pass, which tested A first — so every fuel row in the game
        // said "fuel at A or better" even when C would burn, and the clause
        // sorted nothing. Found while building this; flagged on ASSA-58.
        if let Some(grade) = Grade::ALL
            .into_iter()
            .find(|g| s.effective(Property::Reactivity, *g) >= FUEL_MIN_REACTIVITY)
        {
            //
            // **ON A ROW NOTHING CAN MINE, THE LIGHT SLOT ANSWERS THE PRIOR
            // QUESTION INSTEAD** (Game Director, ASSA-68). The lighting state of
            // a rock that can never enter an inventory is physics about
            // something the player cannot touch, and ASSA-58 is what taught them
            // to scan for "lights from cold": in 24.6% of worlds the first such
            // row read top-down is rock nothing can mine (2000 worlds). On the
            // board's own #38 bench, seed 777042, it is row 0.
            //
            // The clause is a conditional on the fuel claim itself and not a
            // fourth `Lighting` state, because the enum answers an ignition
            // question nobody is asking here. No comma before the "if": the
            // conditional binds the whole fuel claim, which is its status.
            // ASSA-58's "every fuel row says which lighting state it is" is
            // amended, not broken — the slot is still occupied, so a missing
            // clause still cannot become the cue for "won't light".
            let clause = if minable {
                let light = match crate::ladder::lighting(&world.species, s.id) {
                    Lighting::FromCold => "lights from cold",
                    Lighting::FromAHotterFire => "needs a hotter fire to light",
                    Lighting::NothingBurnsHotEnough => "nothing here burns hot enough to light it",
                };
                format!("fuel at {} or better, {light}", grade.letter())
            } else {
                format!("fuel at {} or better if you could mine it", grade.letter())
            };
            notes.push(clause);
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
        // **WHICH ROCK YOU SPEND ON THE SMELTER BODY IS A REAL DECISION AND
        // NOTHING SAID SO** (Game Director, ASSA-61). The walls are their
        // material's heat tolerance (`World::max_temperature`) and the fire
        // runs at `burn_temperature.min(walls)`, so the obvious choice - the
        // starter rock you are already carrying - gives worse walls than the
        // best rock you can mine in 86% of worlds, and in 42% that quietly
        // costs the player a species of their rung zero. It never costs them
        // the demo, which is why this is P2: the starter rock always smelts
        // itself, measured over 20000 worlds with no exception.
        //
        // **THE RULE HERE, THE NUMBERS ELSEWHERE.** The species table already
        // prints heat tolerance and `building_status` prints the realised
        // `walls N`; two wordings for one condition is how hosts drift. This
        // states a relationship, which is why it escapes the no-figures rule
        // ASSA-52 and ASSA-58 wrote their sentences under. And because heat
        // tolerance reads as a band until the species is assayed, a player can
        // only predict their walls to within a band - a third reason to assay,
        // on a decision taken in the first two minutes of play.
        //
        // Keyed on the smelter and NOT derived from `BuildingKind::for_item`,
        // on purpose: every building's material sets its `max_temperature`,
        // but only a smelter melts anything with it, so a future placeable
        // recipe output wants its own sentence rather than inheriting this
        // one. What keeps this sentence true is behavioural - `reach.rs`
        // builds a smelter and reads its walls back off the world.
        if r.output.0 == ItemKind::Smelter {
            needs.push("walls = the heat tolerance of the ore you build it from".into());
        }
        // **THE MOST EXPENSIVE DEAD END IN THE GAME WAS ADVERTISED UNMARKED**
        // (Game Director, ASSA-59). A gear costs 2 refined — a whole handle,
        // two thirds of a pick, 40 ticks of smelter time, and smelting is 49%
        // of the demo's clock — and nothing consumes one. The recipe stays,
        // because the alloys note still wants gears and deleting it would move
        // the golden hash for nothing; what stops is the silence.
        //
        // On the row and not in the footer, per her ruling: the footer states
        // things true of several recipes, this is true of one, and a reader
        // scanning for their row never reaches a footer. In `needs` because it
        // is the last column and has free width — `makes` is `{:<16}` with six
        // characters used and would push every column right.
        //
        // **NO "YET"**: no accepted decision backs a future use for a gear,
        // and `reach.rs::no_reach_sentence_promises_a_later_unlock` now reads
        // these rows too, so the word cannot creep back in quietly.
        if !crate::recipe::is_consumed(r.output.0) {
            needs.push(format!("nothing uses a {}", r.output.0.name()));
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
        //
        // **REACH, NOT `deposit_dead_end_note`, AND THAT IS DELIBERATE**
        // (ASSA-52). A drill on a rock that can be mined but never smelted
        // works perfectly: it fills its hopper. Calling it "idle" there would
        // be false, and the rock's own line already says the ore is a dead
        // end. A machine reports what the machine is doing.
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

/// Why a smelter stopped, in the words it has always used.
///
/// **ONE VOCABULARY PER CONDITION** (Game Director, ASSA-80, and the rule she
/// has now applied on ASSA-58, ASSA-61 and ASSA-70). The status line and the
/// event log are two surfaces and this is one sentence, so a player who reads
/// the log and then hovers the building is told the same thing twice rather
/// than two things once.
pub fn stall_reason(why: SmelterStall) -> String {
    match why {
        SmelterStall::OutputFull => "output full".to_string(),
        SmelterStall::NoFuel => "no fuel".to_string(),
        SmelterStall::FuelWontLight => "fuel won't light from cold".to_string(),
        SmelterStall::FireTooCool { fire, needs } => {
            format!("fire {fire} too cool for ore needing {needs}")
        }
    }
}

/// One line describing what a building holds and whether it is working.
pub fn building_status(world: &World, b: &Building) -> String {
    let s = match &b.kind {
        BuildingKind::Smelter(s) => s,
        BuildingKind::Machine(m) => return machine_status(world, b, m),
    };
    let walls = world.max_temperature(b);
    // **THE DECISION IS `World::smelter_state`'S AND THE WORDS ARE MINE**
    // (ASSA-80). This chain used to live here, which left `step` no way to
    // know a smelter had stalled except by re-deriving it -- and a second copy
    // of a decision is how ASSA-43 and ASSA-52 happened. Same sentences,
    // same order, decided once.
    let state = match world.smelter_state(b) {
        SmelterState::Idle => "idle: nothing to refine".to_string(),
        SmelterState::Stalled(why) => format!("stalled: {}", stall_reason(why)),
        SmelterState::Working { at } => format!("working at {at}"),
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

/// A HAND CRAFT IN PROGRESS, IN ONE SENTENCE, or `None` when nothing is being
/// made (ASSA-49, Maren's ruling).
///
/// Pressing Craft again while one is running refunds the current unit and
/// starts over — the same "latest command wins" as `MoveTo` and `Mine`, and
/// the rule is right. What was wrong is that nothing said a craft was
/// running, so a person who presses a button and sees nothing presses again
/// and throws the work away. The sentence is the whole fix; the rule does not
/// move.
///
/// **It lives here so both hosts say it once.** `sim-cli` and the Godot client
/// each had their own idea of how to word a number before `event_line` and
/// `durability_readout` were pulled in here, and two wordings for one fact is
/// the disagreement nobody notices.
///
/// **The batch is the part worth naming.** One `sort` is 20 ticks, which is
/// two seconds; ten of them is 200 ticks and twenty seconds of a button that
/// looks broken. So the count of batches still to go is in the sentence
/// whenever it is more than one, and the ticks are for the batch actually
/// being worked — `progress` only ever describes the current unit, because the
/// inputs for the later ones have not been consumed yet.
///
/// Ticks, never a bar and never seconds: the tick is what the sim counts in,
/// and a clock rate belongs to a host. A renderer that wants a bar can divide,
/// but then the scaling is its own claim and not the sim's.
pub fn crafting_readout(world: &World, player: PlayerId) -> Option<String> {
    let crafting = world.player(player)?.crafting?;
    let recipe = crafting.recipe.recipe();
    let left = recipe.ticks.saturating_sub(crafting.progress);
    let making = world.item_name(recipe.output_for(crafting.input)?);
    Some(if crafting.remaining > 1 {
        format!(
            "making {making}: {left} ticks left on this one, {} to go after it",
            crafting.remaining - 1
        )
    } else {
        format!("making {making}: {left} ticks left")
    })
}
