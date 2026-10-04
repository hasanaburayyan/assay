//! Plain-text views of the world for terminals, logs and tests.
//! Debugging aids only; real rendering lives outside the sim.

use std::fmt::Write;

use crate::assembly::{
    Assembly, AssemblyError, BreakVerdict, Built, Mount, PART_SPECS, PartKind, Source,
};
use crate::building::{
    Building, BuildingKind, BuildingState, Machine, MachineIdle, MachineStall, MachineState, Slot,
    SmelterStall, SmelterState,
};
use crate::command::{Event, PlayerCommand, RejectReason, StopReason};
use crate::item::{Item, ItemKind, ItemStack};
use crate::ladder::Lighting;
use crate::mineral::{Grade, MineralSpecies, NameError, Property, Sheet, SpeciesId};
use crate::ore::OreDeposit;
use crate::recipe::{RECIPES, Station};
// `YIELD_BY_GRADE` was here until ASSA-94: this file used it to work out for
// itself whether a drill's buffer had room. It decides nothing now, so it
// needs no rate.
use crate::tuning::{HAND_MINE_MAX_HARDNESS, HAND_WORK_PER_TICK, PICK_WEAR_PER_SWING};
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
            // NO SLOT NUMBER IN SCROLLBACK (ASSA-130, the Game Director's
            // correction to her own box). This used to read `assembled
            // #{assembly}`, and `assembly` is a Vec index: `Equip` does
            // `assemblies.remove(i)` (`step.rs`), so every later design
            // shifts down one. An entry that stays on screen would then name
            // a different design than the one it was written about. The sheet
            // is on this very line, so the sheet is the identification.
            //
            // The noun is read off the frame, not fixed: `Assembled` fires
            // for a planted drill as well as a held pick, and `debug.rs`
            // already words the difference as "a handle for a tool, a frame
            // to plant" in `assembly_error_phrase`.
            let noun = match world
                .player(*player)
                .and_then(|p| p.assemblies.get(*assembly as usize))
                .and_then(|b| b.assembly.mount())
            {
                Some(Mount::Held) => "a tool",
                _ => "a machine",
            };
            match readout {
                Some(r) => format!("{} assembled {noun}: {r}", who(player)),
                None => format!("{} assembled {noun}", who(player)),
            }
        }
        Event::Equipped { player } => {
            // THE VERDICT ONLY, ONE ROW (ASSA-130). The sheet is not news
            // here: `Assembled` printed it one tick earlier -- the normal
            // flow, not an edge, as `sim-cli/tests/first_pick.rs` shows -- and
            // the designs panel holds it standing. Four wrapped rows repeated
            // were a third of the readable log in the window shot that filed
            // this. The verdict stays because it is the part that bears on the
            // act: am I about to swing something that will break.
            let verdict = world
                .player(*player)
                .and_then(|p| p.tool.as_ref())
                .map(|b| b.assembly.stat_range(&world.species).verdict().label());
            match verdict {
                Some(v) => format!("{} equipped a tool: {v}", who(player)),
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
                RejectReason::AlreadyBestGrade => best_grade_note().to_string(),
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
                RejectReason::BadAssembly(e) => assembly_error_phrase(*e),
                // **THE SUBJECT IS THE KIND, NOT THE ITEM.** This refusal is
                // categorical — no ore of any species or grade is a machine
                // part — so naming "Korvite ore (B)" would imply some other
                // ore might work, and `item.code()` (what this said until
                // ASSA-102's QA found it) shows a player `ore#3(B)`, an id
                // that exists for save files. It is also the only subject a
                // host asking *before* the press can have: it holds a pack
                // row's kind, not a rejected `Item`. One sentence, one noun.
                RejectReason::NotAPart(item) => not_a_part_phrase(item.kind.name()),
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

/// WHETHER A PLAYER MUST SEE THIS EVENT EVEN WITH THE EVENT LOG HIDDEN
/// (ASSA-89). Says nothing about wording: the sentence is still
/// [`event_line`]'s, and a host shows the same string in a louder place.
///
/// THE PROPERTY, WHICH IS A PROPERTY AND NOT A LIST: an event needs attention
/// when it reports that something **did not happen, stopped happening, or was
/// lost**. Never a success. Successes are the story, and the story is what the
/// log is for; a surface that holds one line at a time can only carry the
/// problem.
///
/// IT LIVES HERE, BESIDE `event_line`, FOR THE REASON `recipe_dead_end` DOES
/// (ASSA-84). The alternative is a host matching the TEXT of a sentence to
/// decide how loudly to say it — and `event_line`'s wording moved thirteen
/// times in one afternoon on ASSA-67. A host that classified by text would
/// have gone quiet that afternoon without one test going red.
///
/// THE MATCH IS EXHAUSTIVE AND THE `false` ARMS ARE WRITTEN OUT, which is most
/// of the point. A new `Event` variant fails to compile here, so its author
/// decides whether a player must be told; a `_ => false` would make silence
/// the default for every event nobody thought about, which is the shape of
/// defect ASSA-51 and ASSA-53 both were.
///
/// MINE AND NOT EVERYONE'S, for anything carrying a player: another player's
/// refusal is their notice, and in a co-op world of two the alternative is
/// each of us reading the other's mistakes over our own. Machines have no
/// player and belong to the world, so a stall is everybody's.
pub fn event_needs_attention(me: Option<PlayerId>, event: &Event) -> bool {
    let mine = |p: &PlayerId| me.is_some() && me == Some(*p);
    match event {
        // THE WORLD REFUSED WHAT YOU ASKED FOR (ASSA-43, ASSA-70). The reason
        // this function exists at all: this is the only sentence in the game
        // that says why the button you pressed did nothing.
        Event::CommandRejected { player, .. } => mine(player),

        // A MACHINE STOPPED AND WANTS A HAND (decision 9, ASSA-80). Emitted
        // once on the edge into the stall, so a notice cannot repeat every
        // tick -- that property is the event's, not this function's.
        Event::MachineStalled { .. } | Event::SmelterStalled { .. } => true,

        // YOU LOST SOMETHING (decision 11, decision 12). The most dramatic
        // moment in the game is a poor one to find out by scrolling.
        Event::MachineBroke { player, .. } | Event::ToolWornOut { player, .. } => mine(player),

        // SOMETHING OF YOURS STOPPED WITHOUT YOU ASKING. A stop you asked for
        // is not news; a depleted deposit, a missing input or walking off the
        // rock is the reason your next press will do nothing.
        Event::MiningStopped { player, reason, .. }
        | Event::AssayStopped { player, reason, .. }
        | Event::CraftingStopped { player, reason, .. } => {
            mine(player) && *reason != StopReason::Stopped
        }

        // PART OF WHAT YOU ASKED FOR DID NOT FIT (ASSA-48). `left` is the
        // actionable half by that variant's own doc comment: "put 50 in" tells
        // a player nothing about why they still have 167.
        Event::ItemsInserted { player, left, .. } => mine(player) && *left > 0,

        // EVERY SUCCESS, WRITTEN OUT RATHER THAN DEFAULTED.
        //
        // `DepositDepleted` is here deliberately and it is the one I would
        // argue about: it is a thing that stopped. But it lands on the same
        // tick as the miner's own `MiningStopped { Depleted }`, so taking both
        // means two notices for one fact on a surface that holds one line, and
        // the second would overwrite the sentence that names the player.
        Event::PlayerJoined { .. }
        | Event::MiningStarted { .. }
        | Event::OreMined { .. }
        | Event::DepositDepleted { .. }
        | Event::SpeciesDiscovered { .. }
        | Event::AssayStarted { .. }
        | Event::SpeciesAssayed { .. }
        | Event::SpeciesRenamed { .. }
        | Event::RenameGranted { .. }
        | Event::CraftStarted { .. }
        | Event::ItemCrafted { .. }
        | Event::BuildingPlaced { .. }
        | Event::ItemsTaken { .. }
        | Event::BuildingRemoved { .. }
        | Event::ItemSmelted { .. }
        | Event::PartsMade { .. }
        | Event::Assembled { .. }
        | Event::Equipped { .. }
        | Event::Unequipped { .. }
        | Event::MachinePlaced { .. }
        | Event::MachineMined { .. }
        | Event::MoveStarted { .. }
        | Event::PlayerArrived { .. }
        | Event::PlayerStopped { .. } => false,
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
    (!crate::ladder::hand_minable(species)).then(|| too_hard_sentence(species))
}

/// The hardness gate in words, for a caller that has already established the
/// gate applies.
///
/// **ONE SENTENCE FOR ONE GATE** — the rock's own line reaches it through
/// `deposit_reach_note`, a drill standing on that rock reaches it through
/// `machine_state_line`, and a player who reads both is told the same thing
/// twice rather than two things once. Separated out on ASSA-94 only because
/// `MachineIdle::DepositTooHard` has already decided the gate applies, so it
/// needs the sentence and not the `Option`.
fn too_hard_sentence(species: &MineralSpecies) -> String {
    format!(
        "{} is too hard for anything you can build: hardness is over \
         {HAND_MINE_MAX_HARDNESS}, and a drill mines faster, not harder",
        species.name()
    )
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

/// What the GROUND of a tile is, when no deposit is doing the talking.
/// Empty when there is nothing for it to say.
///
/// **"empty ground" CARRIED TWO MEANINGS AND THE READER GOT THE WRONG ONE**
/// (Game Director, ASSA-146). Every host words a tile the same way — the
/// deposit, else spawn, else the ground — and then appends the building
/// standing there as a separate line, written by a separate block. The deposit
/// case composes ("deposit 11 · Remdornite · 712 ore left" over a smelter reads
/// correctly); the bare case did not:
///
/// ```text
/// (76, 38) · chunk (4, 2) · 1 from spawn
/// empty ground
/// Minyte smelter (B) 0 · walls 29 · in empty · fuel 9 Minyte ore (B) …
/// ```
///
/// One line says the tile is empty, the next names what is standing on it. The
/// phrase meant *this tile has no deposit* and was read as *nothing is here*,
/// and a tile with a building is by far the most interesting tile with no
/// deposit. So the ground line now names its own fact and only its own fact:
/// **it is about rock, not about occupancy**, and then it cannot contradict a
/// line it does not know about. Deleting it instead would have paid for that
/// with the no-deposit fact, on the line the Game Director ruled (ASSA-138) to
/// be where a player reads a machine's exact capacity.
///
/// **IT LIVES HERE BECAUSE THERE WERE THREE OF IT**: the literal was spelled
/// out in `sim-cli`'s `at`, in the inspector's tile panel and in the Godot
/// client's cursor section, which is how `building_name` and `fuel_tag` ended
/// up here too. Hosts render this verbatim; none of them may word the ground.
///
/// Empty in the two cases where this function has no business speaking: a tile
/// off the map (the host says *that* instead, with the bounds), and a tile with
/// a deposit, whose own line is the ground line there — including on spawn,
/// which is unchanged, deposit first.
pub fn ground_note(world: &World, at: TilePos) -> &'static str {
    if !world.in_bounds(at) || world.deposit_at(at).is_some() {
        return "";
    }
    if at == world.spawn_tile() {
        // UNCHANGED, AND NOT AN OVERSIGHT: "spawn" says what the tile IS and
        // claims nothing about being bare, so it was never the contradiction —
        // and it composed over a building before this function existed.
        return "spawn";
    }
    "no deposit here"
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

/// WHAT A RECIPE'S ROW SAYS WHEN NOTHING IN THE GAME CONSUMES ITS OUTPUT, or
/// "" when something does. The one place that sentence is written.
///
/// DERIVED, NEVER LISTED (ASSA-59). It asks `recipe::is_consumed`, so the day
/// anything takes this kind as an input the clause disappears on its own and
/// nobody has to remember to delete it. Nothing here names a gear; the gear is
/// merely the only kind that answers false today, which `reach.rs` pins.
///
/// IT LIVES HERE BECAUSE TWO HOSTS NEED IT. `recipe_table` prints it for the
/// terminal, and `AssaySim::recipes` carries it to the window, where a BUTTON
/// is a stronger invitation than a table row and a gear costs 2 refined
/// (ASSA-84, Maren's ruling 2: one describer, not a second sentence written in
/// GDScript).
///
/// **NO "YET"**: no accepted decision backs a future use for a gear, and
/// `reach.rs::no_reach_sentence_promises_a_later_unlock` reads these rows.
pub fn recipe_dead_end(recipe: &crate::recipe::Recipe) -> String {
    if crate::recipe::is_consumed(recipe.output.0) {
        String::new()
    } else {
        format!("nothing uses a {}", recipe.output.0.name())
    }
}

/// THE WALLS A SMELTER MADE FROM THIS STACK WOULD HAVE, or "" for every other
/// row. One clause, appended like [`recipe_dead_end`], never composed by a
/// host.
///
/// **THE FIGURE, NOT THE RULE** (Game Director, ASSA-88 → ASSA-125). The
/// recipe table already says what walls ARE and what they DO, once, and two
/// wordings for one condition is how hosts drift. What a player cannot get
/// from that rule is the number for THIS rock at the moment they spend five
/// ore on it. Her measurement is why it is worth a clause at all: a pair that
/// refines your nearest diggable rock exists in 86.8% of worlds, but rough
/// sheets prove one works in only 49.4% — so in half of worlds the first
/// smelter cannot be chosen, only tried.
///
/// **THE COMPARISON STAYS THE PLAYER'S.** This says what the walls would be
/// and not whether they are enough: ranking the rocks for them is the game,
/// and `ladder::starter_pair` — the one answer the sim could give — is right
/// 75.2% of the time and wrong exactly where a player cannot tell (her
/// measurement again; a hint right three times in four is worse than none).
///
/// **IT IS THE PLAYER'S READING, NOT THE GROUND'S.** [`reading`] gives the
/// 25-wide band until that species is assayed, which is honest about what they
/// know and is a third reason to assay, on a decision taken in the first two
/// minutes of play.
///
/// Keyed on the recipe's OUTPUT KIND, like the recipe table's own sentence:
/// every building's material sets its `max_temperature`, but only a smelter
/// melts anything with it, so a later placeable recipe gets its own clause
/// rather than inheriting this one.
pub fn walls_clause(world: &World, recipe: &crate::recipe::Recipe, input: Item) -> String {
    if recipe.output.0 != ItemKind::Smelter {
        return String::new();
    }
    // GRADE IS DELIBERATELY NOT READ. Heat tolerance is one of the two
    // properties grade never scales (`Sheet::effective`), so the same species
    // at grade C and grade A builds walls of exactly the same height. A clause
    // that quietly took the stack's grade would be a second opinion about a
    // rule that lives in one place, and `make_offers.rs` pins it.
    format!(
        "walls {}",
        reading(world.species(input.species), Property::HeatTolerance)
    )
}

/// HOW FAR A SPECIES GETS IF YOU GO AND SWING AT IT: the three states a
/// player plans from, as one answer instead of two bools a host must combine.
///
/// **WHY THIS ENUM IS HERE AND NOT IN `ladder`** (ASSA-135). The two
/// decisions are already `ladder`'s and stay there — `hand_minable` is a
/// hardness comparison and `usable_from_bare_hands` walks rung zero. Nothing
/// in the rules branches on the three-way; only the wording does, and
/// `RULES_ID` is a hash of every `sim/src` file except this one. So a type
/// that exists to be *said* belongs on the side of that line where a new
/// variant cannot make two peers refuse each other. Prose cannot desync.
///
/// What this DOES buy is the thing the bools could not: a fourth state fails
/// to compile in [`mining_note`], and no host can collapse three states into
/// two by accident. That is exactly how it was lost — the window appended
/// "hand-minable" on a bool and appended nothing when it was false, so the
/// half of the roster nothing can mine, and the 13.6% whose ore dead-ends,
/// both rendered as the absence of a word.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Mining {
    /// Hardness is past anything a player can swing.
    TooHard,
    /// A pick gets the ore out, and the ore is where it ends.
    ByHandNotSmeltable,
    /// A pick gets the ore out and the ore goes somewhere.
    ByHand,
}

/// Which of the three [`Mining`] states a species is in, for a roster.
///
/// The roster is needed and not just the sheet: "can this ore be smelted"
/// is a question about which fires THIS WORLD can build, which is rung zero
/// and therefore every species at once — the same reason
/// [`crate::ladder::lighting`] takes the slice.
pub fn mining(species: &[MineralSpecies], id: SpeciesId) -> Mining {
    let s = &species[usize::from(id.0)];
    if !crate::ladder::hand_minable(s) {
        Mining::TooHard
    } else if !crate::ladder::usable_from_bare_hands(species, id) {
        Mining::ByHandNotSmeltable
    } else {
        Mining::ByHand
    }
}

/// The three states in words, and **THE ONLY WORDING OF THEM ANYWHERE**
/// (ASSA-135, Game Director).
///
/// One wording and not a `tag`/`clause` pair like [`lighting_tag`] and
/// [`lighting_clause`], because the Game Director asked for the window's
/// sentence to be byte-identical to the table's: the species panel and the
/// `species` table are the same surface at two widths, and a player who read
/// one and then the other must not have to work out whether two phrasings
/// mean one thing. `species_table_says_what_the_panel_says` pins it.
///
/// - **`TooHard`**: the absence of a note used to be the only cue, and
///   absence is not a cue. This is the half of the roster nothing can mine.
/// - **`ByHandNotSmeltable`**: **BARE "hand-minable" READ AS A PROMISE**
///   (Game Director, ASSA-52). It is the truth about the swing and says
///   nothing about the ore, and for 13.6% of deposits the ore is where it
///   ends. The row still BEGINS "hand-minable" because that part is true and
///   a player comparing rows is comparing swings. Terse on purpose: a row is
///   read against five others, and the full explanation belongs on the
///   deposit line, where a player is standing on the thing.
pub fn mining_note(m: Mining) -> &'static str {
    match m {
        Mining::TooHard => "too hard for anything you can build",
        Mining::ByHandNotSmeltable => "hand-minable, but not smeltable",
        Mining::ByHand => "hand-minable",
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
        // THE THREE MINING STATES AND THEIR WORDS BOTH LIVE IN `mining` AND
        // `mining_note` NOW (ASSA-135). They were an if/else chain here, which
        // made this table the only surface that could say the middle state at
        // all: the species panel was handed `hand_minable` and composed its own
        // word from it, so three states arrived as two. The note the window
        // shows is this same string, byte for byte.
        let minable = crate::ladder::hand_minable(s);
        notes.push(mining_note(mining(&world.species, s.id)).to_string());
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
        if let Some(grade) = crate::ladder::fuel_grade(s) {
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
            // THE GRADE AND THE CONDITIONAL ARE WORDED BY `fuel_tag` AND NOT
            // HERE (ASSA-143). They used to be two `format!`s inside this
            // loop, so this table was the only surface in the game that could
            // say at which grade a rock burns — the window was handed
            // `fuel_grade(..).is_some()` and dropped the threshold on the
            // line that computed it. What is left here is the one part that
            // is genuinely the table's: a prose row binds the lighting clause
            // onto the fuel claim, and a column of tags cannot.
            let clause = if minable {
                format!(
                    "{}{}",
                    fuel_tag(grade, minable),
                    lighting_clause(crate::ladder::lighting(&world.species, s.id))
                )
            } else {
                fuel_tag(grade, minable)
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

/// WHAT LABELS A PERMANENT DEAD END IN THE CATALOGUE, so the sentence is not
/// read as one more thing to go and satisfy.
///
/// **UNDER `needs`, EVERY ENTRY MUST BE A CONDITION THAT CAN BECOME TRUE**
/// (Game Director, ASSA-122). "hardness ≥ 20" is something a player makes true
/// by finding better rock; "nothing uses a gear" can never become true by
/// anything they do. Both were in one cell under one header, so the second read
/// as a second requirement — exactly the wasted trip ASSA-107's precedence rule
/// exists to prevent. The menu got that right and the catalogue did not.
///
/// **WHY ITS OWN LINE AND NOT ANOTHER COLUMN.** `needs` is last precisely
/// because it is unbounded: the smelter row's cell alone is ~80 characters, so
/// there is no room for a column after it, and a marked suffix *inside* the
/// cell is the defect. The line sits under `makes` because that is what the
/// fact is about — the output nothing consumes, not the input.
///
/// The label carries the KIND and the sentence stays verbatim out of
/// [`recipe_dead_end`], so the clause is still derived from
/// `recipe::is_consumed` and still disappears on its own the day something
/// takes a gear. Public because `reach.rs` asserts against the shipped string
/// rather than a copy of it.
pub const DEAD_END_LABEL: &str = "dead end: ";

/// Table of every recipe.
pub fn recipe_table() -> String {
    // `makes` is 18 and not 16 because `1 refined +1 grade` is exactly 18: at
    // 16 the resmelt row overflowed its cell and shoved the last four columns
    // two places right, on that row alone (ASSA-122, found while moving the
    // dead end). A header that promises a shape its cells break is the same
    // defect as a header that promises a kind its cells break.
    // `every_recipe_row_lines_up_with_the_header` is what keeps this honest;
    // an exact fit is one character from breaking again and the guard, not the
    // width, is the fix.
    let mut out = format!(
        "{:<8} {:<18} {:<12} {:>5}  {:<16} needs\n",
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
            // **CONSEQUENCE FIRST, DEFINITION SECOND** (Game Director,
            // ASSA-76). What shipped on ASSA-61 defined `walls` and never said
            // what walls DO -- and "walls" is jargon introduced in this very
            // cell, so a player read a definition with no consequence and had
            // no reason to care which rock they spent. The same defect ASSA-52
            // fixed one slot over: "hand-minable" was true and stopped.
            //
            // Until this, the consequence only reached them through the
            // `TooHotForWalls` refusal, which fires after five ore are already
            // spent on the wrong rock. The point of the clause is to speak at
            // the moment of choice.
            needs.push(
                "melts ore up to its walls; walls = the heat tolerance of the ore you build \
                 it from"
                    .into(),
            );
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
        // scanning for their row never reaches a footer.
        //
        // **BUT NOT IN `needs`, WHICH IS WHERE IT SHIPPED** — see
        // [`DEAD_END_LABEL`]. It gets its own labelled line under the row, so
        // the row keeps only conditions a player can make true.
        //
        // **NO "YET"**: no accepted decision backs a future use for a gear,
        // and `reach.rs::no_reach_sentence_promises_a_later_unlock` now reads
        // these rows too, so the word cannot creep back in quietly.
        let _ = writeln!(
            out,
            "{:<8} {makes:<18} {from:<12} {:>5}  {station:<16} {}",
            r.name,
            r.ticks,
            if needs.is_empty() {
                "nothing".to_string()
            } else {
                needs.join(", ")
            }
        );
        let dead_end = recipe_dead_end(r);
        if !dead_end.is_empty() {
            // Indented to the `makes` column by the same width as the name, so
            // the line is plainly subordinate to the row above it. The recipe
            // is still listed and still craftable: absence is never a cue.
            let _ = writeln!(out, "{:<8} {DEAD_END_LABEL}{dead_end}", "");
        }
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

/// The small print under a design's verdict: the sim's own sentence, or
/// nothing when the verdict is settled and good.
///
/// **ONE SENTENCE, TWO HOSTS** (Game Director's ruling on ASSA-90). The window
/// used to compose its own, out of the raw `unassayed` list, and appended it
/// **whenever that list was non-empty** — so a WILL BREAK design was offered an
/// assay instead of being told it would break, and a SAFE one was handed a
/// to-do. The two hosts said opposite things about one design.
///
/// **WHY THE ASSAY OFFER IS DEAD ON A SETTLED VERDICT, by construction and not
/// by bench:** SAFE means the highest mass is under the lowest budget, and WILL
/// BREAK means the lowest mass is over the highest budget — the two spans are
/// **disjoint**. An assay collapses a band to a point *inside* itself, so it
/// cannot cross a gap that is already open. Offering it there names an action
/// that cannot move the thing it is named for.
///
/// Takes the roster rather than a `World`, so both hosts and a synthetic test
/// ask the same question.
pub fn verdict_note(species: &[MineralSpecies], a: &Assembly) -> Option<String> {
    match a.stat_range(species).verdict() {
        // A settled design is not a to-do.
        BreakVerdict::Safe => None,
        BreakVerdict::WillBreak => {
            Some("this is over budget: it will break when planted or first used".to_string())
        }
        BreakVerdict::Uncertain => {
            let mut rough: Vec<&str> = Vec::new();
            for part in a.parts() {
                let s = &species[usize::from(part.material.species.0)];
                if !s.assayed && !rough.contains(&s.name()) {
                    rough.push(s.name());
                }
            }
            // **THE WINDOW'S WORDING WON** (her ruling): it names the material,
            // and this is the only advertisement assaying gets. The reference
            // client used to say "assay every species in it to know whether it
            // will hold" — true, and it tells you nothing to do next.
            //
            // UNCERTAIN implies a rough species, because an all-exact design has
            // low == high on both spans and they cannot overlap. This says what
            // it can rather than panicking on a state it has not proved
            // impossible; `assembly.rs` measures that the list is never empty.
            if rough.is_empty() {
                Some("assay the materials in it to know".to_string())
            } else {
                Some(format!("assay {} to know", rough.join(" and ")))
            }
        }
    }
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
    let state = machine_state_line(world, world.machine_state(b, m));
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

/// How a fuel can be lit, as the clause that follows the grade in a species
/// row — **binding the fuel claim when it disqualifies it** (Game Director,
/// ASSA-93).
///
/// The disqualifier used to trail after a comma, so `fuel at C or better,
/// nothing here burns hot enough to light it` looked exactly like the positive
/// `, lights from cold` after a grade-bearing claim that had already invited
/// the player in. The board loaded 50 units of a fuel nothing in their world
/// could light and the row read like an offer. `species_table` already binds
/// correctly one clause over — `fuel at C or better if you could mine it` —
/// and this is the same shape for the same reason.
///
/// `FromAHotterFire` keeps its comma on purpose: it is a real conditional a
/// player can satisfy, not a disqualifier.
pub fn lighting_clause(l: Lighting) -> &'static str {
    match l {
        Lighting::FromCold => ", lights from cold",
        Lighting::FromAHotterFire => ", needs a hotter fire to light",
        Lighting::NothingBurnsHotEnough => " if anything here could light it",
    }
}

/// The same three states as a short label, for a host that shows tags rather
/// than sentences (ASSA-93).
///
/// **TWO RENDERINGS OF ONE ENUM, BOTH HERE.** A window row is a column of tags
/// and a table row is prose; a clause reading " if anything here could light
/// it" is not a tag, and "nothing here can light it" does not bind a sentence.
/// What must not happen is a HOST choosing either — so both matches live in
/// this file and a fourth `Lighting` state fails to compile in both at once.
/// If the Game Director would rather have one wording on both surfaces, it is
/// this function and the one above that merge, and no host changes.
pub fn lighting_tag(l: Lighting) -> &'static str {
    match l {
        Lighting::FromCold => "lights from cold",
        Lighting::FromAHotterFire => "needs a hotter fire",
        Lighting::NothingBurnsHotEnough => "nothing here can light it",
    }
}

/// THE FUEL CLAIM, CARRYING THE GRADE IT IS CONDITIONAL ON — the one place in
/// the game that words "this rock is fuel" (ASSA-143).
///
/// **A CONDITIONAL CLAIM MUST CARRY ITS CONDITION** (Game Director, ASSA-143,
/// on ASSA-52's rule). `fuel_grade` holds the cheapest grade that burns, and
/// 18.8% of the rows the window tags as fuel name a grade other than C: a
/// player reading a bare "fuel" walks to the nearest deposit, mines a stack,
/// feeds the smelter and the fire does not light, with no surface having said
/// purity was the variable. The threshold is computed to decide whether to say
/// anything at all, so saying "fuel" without it throws away the more useful
/// half of the answer.
///
/// **ONE FUNCTION, BOTH SURFACES, UNLIKE THE LIGHTING PAIR ABOVE.** The
/// lighting axis needs two renderings because a prose clause binds a sentence
/// (", lights from cold") and a tag cannot. The fuel claim does not: "fuel at
/// B or better" reads as both, and `species_table` composes its prose row by
/// appending [`lighting_clause`] to this. So a window tag is byte-identical to
/// the head of the table's clause by construction rather than by agreement —
/// `the_species_panels_fuel_tag_is_the_tables_own_words` holds that.
///
/// `minable` is NOT a second thought about the fuel claim: it is the
/// difference between fuel and a rock whose fuel rating the player can never
/// collect, and ASSA-68 is why the clause says so here rather than letting the
/// lighting slot answer it. No comma before the "if" — the conditional binds
/// the whole claim, which is its status, not a trailing remark.
pub fn fuel_tag(grade: Grade, minable: bool) -> String {
    if minable {
        format!("fuel at {} or better", grade.letter())
    } else {
        format!("fuel at {} or better if you could mine it", grade.letter())
    }
}

/// Why a design was refused, in the words it has always used.
///
/// **THE SENTENCES WERE REAL AND UNREACHABLE** (ASSA-102). They lived inside
/// `event_line`'s `BadAssembly` arm, so the only way for a host to obtain one
/// was to *actually be rejected* — which is exactly what the Game Director's
/// ASSA-86 ruling 2 forbids, since a client must say why it will not confirm a
/// press *before* submitting anything. Same sentences, same arms, now callable:
/// the `stall_reason` shape.
pub fn assembly_error_phrase(e: AssemblyError) -> String {
    match e {
        AssemblyError::FrameIsNotAFrame => {
            "the first part must be a frame: a handle for a tool, a frame to plant".to_string()
        }
        AssemblyError::FrameMounted => "a frame cannot be mounted on another frame".to_string(),
        AssemblyError::NoSuchSlot(kind) => {
            format!("that frame has no {} slot at all", kind.name())
        }
        AssemblyError::TooFew { kind, have, min } => {
            format!("it needs at least {min} {} and has {have}", kind.name())
        }
        AssemblyError::TooMany { kind, have, max } => {
            format!(
                "it takes at most {max} {} and was given {have}",
                kind.name()
            )
        }
    }
}

/// What a player offered that is not a part, and what the parts are.
///
/// Extracted alongside [`assembly_error_phrase`] and for the same reason: a
/// host that is handed an item kind it cannot place has to say so in the sim's
/// words rather than compose its own. The list comes from the catalogue, so a
/// new part kind names itself here without anyone editing this sentence.
pub fn not_a_part_phrase(what: &str) -> String {
    format!(
        "{what} is not a machine part; parts are {}",
        PartKind::ALL
            .iter()
            .map(|k| k.name())
            .collect::<Vec<_>>()
            .join(", ")
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

/// What a smelter is doing, in words. **THE DECISION IS
/// `World::smelter_state`'S AND THE WORDS ARE MINE** (ASSA-80): the chain used
/// to live here, which left `step` no way to know a smelter had stalled except
/// by re-deriving it, and a second copy of a decision is how ASSA-43 and
/// ASSA-52 happened.
pub fn smelter_state_line(state: SmelterState) -> String {
    match state {
        SmelterState::Idle => "idle: nothing to refine".to_string(),
        SmelterState::Stalled(why) => format!("stalled: {}", stall_reason(why)),
        SmelterState::Working { at } => format!("working at {at}"),
    }
}

/// What a planted machine is doing, in words.
///
/// **EVERY WAY A DRILL CAN BE DOING NOTHING HAS TO SAY SO HERE**, because the
/// alternative is a player watching a machine they paid eight refined for and
/// guessing. A5's rule — the bad case must be visible — is not only about mass.
///
/// The arms are the sentences this function has always printed; what changed on
/// ASSA-94 is that it no longer decides which one applies.
///
/// **REACH, NOT `deposit_dead_end_note`, AND THAT IS DELIBERATE** (ASSA-52). A
/// drill on a rock that can be mined but never smelted works perfectly: it
/// fills its hopper. Calling it "idle" there would be false, and the rock's own
/// line already says the ore is a dead end. A machine reports what the machine
/// is doing.
pub fn machine_state_line(world: &World, state: MachineState) -> String {
    match state {
        MachineState::Idle(MachineIdle::NoDeposit) => "idle: no deposit underneath".to_string(),
        MachineState::Idle(MachineIdle::DepositMinedOut) => {
            "idle: deposit is mined out".to_string()
        }
        // Decision 7: a drill is a throughput upgrade, never a hardness
        // unlock, so it refuses exactly what hands refuse. Without this line
        // that refusal is invisible and reads as a bug.
        MachineState::Idle(MachineIdle::DepositTooHard { species }) => {
            format!("idle: {}", too_hard_sentence(world.species(species)))
        }
        MachineState::Stalled(MachineStall::BufferFull { .. }) => {
            "stalled: full, take the ore out".to_string()
        }
        MachineState::Working { species, .. } => {
            format!("mining {}", world.species(species).name())
        }
    }
}

/// What any building is doing, in words, whichever kind it is.
///
/// The one wording for a standing condition: `building_status` puts it after
/// the contents, `halted_table` puts it after the address, and neither writes
/// its own.
pub fn building_state_line(world: &World, b: &Building) -> String {
    match world.building_state(b) {
        BuildingState::Smelter(s) => smelter_state_line(s),
        BuildingState::Machine(m) => machine_state_line(world, m),
    }
}

/// One line describing what a building holds and whether it is working.
/// **A COUNT AND ITS NOUN, AGREEING** — one place, so the next counted noun
/// inherits it (ASSA-145, Maren's filing).
///
/// `1 players` has been the second line of every screenshot of Assay that
/// exists, including the ones the board has looked at, because solo is `Play
/// solo` and that is how a stranger opens the game. It is not one typo: the
/// rule was already being applied deliberately in [`halted_table`] ("The 1
/// building you have placed is working") and at `crafting_readout`, and missed
/// in four other places. A number whose noun is wrong for some of its values is
/// the same defect as `5 of your 3 Tonore ore` (ASSA-129, `assay-rulings` §2):
/// A SENTENCE THAT ONLY READS IN THE GOOD CASE IS A DEFECT.
///
/// TWO FORMS AND NOT A SUFFIX RULE. English plurals are not `+ "s"`
/// (`1 species`), and a caller that has to think about it writes the pair
/// rather than trusting a guess this function cannot make.
///
/// IT TAKES THE COUNT AND RETURNS THE COUNT, so a call site reads as the whole
/// phrase and there is no way to print the noun without the number it agrees
/// with. ZERO IS PLURAL, which is English and not an accident: "0 players".
pub fn counted(n: u64, one: &str, many: &str) -> String {
    if n == 1 {
        format!("1 {one}")
    } else {
        format!("{n} {many}")
    }
}

pub fn building_status(world: &World, b: &Building) -> String {
    let s = match &b.kind {
        BuildingKind::Smelter(s) => s,
        BuildingKind::Machine(m) => return machine_status(world, b, m),
    };
    let walls = world.max_temperature(b);
    let state = smelter_state_line(world.smelter_state(b));
    format!(
        "walls {walls} · in {} · fuel {} ({} burning at {}) · out {} · {state}",
        slot(world, s.input),
        slot(world, s.fuel),
        counted(u64::from(s.burn_left), "tick", "ticks"),
        s.burn_temperature,
        slot(world, s.output)
    )
}

/// What a building IS, named the way every other object in this game is
/// named: species, kind, grade.
///
/// **A BUILDING WAS THE ONE OBJECT THAT LOST ITS NAME WHEN YOU PUT IT DOWN**
/// (Game Director, ASSA-136). A stack is a `Tonore ore (A)`, a part is a
/// `Tonore frame (A)`, a deposit's line names its species — and the moment a
/// smelter is standing on the ground every surface called it `smelter 0`. Its
/// material is not decoration: it is the species whose heat tolerance caps the
/// fire (`World::max_temperature`), and it is the exact `Item` that comes back
/// in your pack when you pick the thing up (`step::Pickup`).
///
/// **THE KIND IS THE BUILDING'S, NOT THE ITEM'S, AND THAT IS NOT A DETAIL.**
/// `Building::material` is whatever was placed: a `Smelter` item for a
/// smelter, but `assembly.frame.refined()` for a machine. Reading
/// `World::item_name` straight off it would name a planted drill
/// `Tonore refined (A)`. So the species and grade come from the material and
/// the noun comes from `BuildingKind::name`.
///
/// Grade is carried because it is the grade you get back, NOT because it
/// changes what the building does — it cannot: heat tolerance is one of the
/// two properties `Property::scales_with_grade` excludes, so an A smelter caps
/// the fire exactly where a C one does. That is also why this name sits beside
/// `walls N` rather than inside it; see `walls_clause`, which deliberately
/// does not read grade at all.
pub fn building_name(world: &World, b: &Building) -> String {
    format!(
        "{} {} ({})",
        world.species(b.material.species).name(),
        b.kind.name(),
        b.material.grade.letter()
    )
}

/// Where a building is, as a player would say it.
///
/// **ONE PLACE DECIDES HOW A BUILDING IS ADDRESSED.** This used to be private
/// and `halt_lines` was its only caller, so `sim-cli`'s tile line, the TUI's
/// tile panel and the Godot client each hand-rolled `kind + id + pos` of their
/// own. Four copies of one decision is how ASSA-43, ASSA-52 and ASSA-128
/// happened; the surfaces call this now.
pub fn building_address(world: &World, b: &Building) -> String {
    format!(
        "{} {} at ({}, {})",
        building_name(world, b),
        b.id.0,
        b.pos.x,
        b.pos.y
    )
}

/// Every building that has stopped, one line each, worst-placed first in
/// placement order.
///
/// **THE SURFACE A SCROLLING LOG CANNOT BE** (Game Director, ASSA-94: "a
/// refusal is a MOMENT; a stall is a CONDITION"). The board's own session is
/// the case this exists for: `SmelterStalled` fired correctly, once, on the
/// edge into the stall — and was gone from a fourteen-line log in about a
/// second. Ninety thousand ticks later the smelter was still cold and nothing
/// anywhere said so unless they hovered its two tiles on a 96×64 map.
///
/// Empty when nothing has stopped, so a caller can render nothing at all
/// rather than a reassuring line nobody asked for.
pub fn halt_lines(world: &World) -> Vec<String> {
    world
        .halted()
        .map(|b| {
            format!(
                "{} · {}",
                building_address(world, b),
                building_state_line(world, b)
            )
        })
        .collect()
}

/// [`halt_lines`] as a block, for the terminal.
pub fn halted_table(world: &World) -> String {
    let lines = halt_lines(world);
    if lines.is_empty() {
        // Says what was checked, because "nothing has stopped" and "you have
        // built nothing" look identical to a player and are not the same news.
        return match world.buildings.len() {
            0 => "Nothing built yet. Craft a smelter from 5 ore and `place smelter`.\n".into(),
            1 => "Nothing has stopped. The 1 building you have placed is working.\n".into(),
            n => format!("Nothing has stopped. All {n} buildings you have placed are working.\n"),
        };
    }
    let mut out = format!(
        "{} of {} buildings stopped:\n",
        lines.len(),
        world.buildings.len()
    );
    for line in lines {
        let _ = writeln!(out, "  {line}");
    }
    out
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
            // WAS `world.item_name(b.material)`, AND THAT IS THE BUG THIS
            // FUNCTION WAS CARRYING (ASSA-136). It happens to read correctly
            // for a smelter, whose material IS a smelter item, and names a
            // planted drill `Tonore refined (A)` — the material it was built
            // from rather than the thing standing there.
            building_name(world, b),
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
    // ONE SENTENCE, TWO HOSTS (ASSA-90). This used to be an inline match that
    // the Godot window had no access to, so the window wrote its own and got
    // it wrong on two verdicts out of three.
    if let Some(note) = verdict_note(&world.species, a) {
        let _ = write!(out, "\n      {note}");
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
    let left = counted(u64::from(left), "tick", "ticks");
    Some(if crafting.remaining > 1 {
        format!(
            "making {making}: {left} left on this one, {} to go after it",
            crafting.remaining - 1
        )
    } else {
        format!("making {making}: {left} left")
    })
}

/// EVERY ACTIVITY THIS PLAYER HAS RUNNING, one sentence each, in the order
/// `step` runs the systems: hand mining, assaying, hand crafting (ASSA-95,
/// Maren's ruling).
///
/// **PLURAL BY CONSTRUCTION, AND THAT IS A MEASUREMENT, NOT A STYLE.** `step`
/// never clears `mining` when an assay starts, nor the reverse — independent
/// fields, independent systems — so a player standing on a deposit mines
/// through their own assay and gets seven ore out of it
/// (`shared/assay/maren_assay_while_mining_2026-10-03.rs`, seed 14247). A
/// readout built for "whichever activity is running" would therefore say the
/// mining had stopped. **A list that silently omits a kind teaches that it is
/// complete when it is not**, which is the defect ASSA-94 exists to fix.
///
/// **NEVER RANKED.** The order is `step`'s own, so the day a fourth self-running
/// activity is added it has one obvious place and no host gets an opinion.
///
/// **A COUNTDOWN ONLY WHERE THERE IS AN END.** An assay finishes, so it counts
/// down; a craft finishes, so `crafting_readout` says so in its own words. Hand
/// mining repeats until you stop or the deposit runs dry, so it carries NO
/// NUMBER AT ALL — the 4-tick cycle restarting forever is not a countdown, and
/// a number there would promise an end that does not come. The absence is the
/// fact.
///
/// Ticks, never seconds and never a bar: the tick is what the sim counts in and
/// a clock rate belongs to a host. A host may label this list; it may not
/// reword a number, rank the lines, or drop one.
pub fn activity_lines(world: &World, player: PlayerId) -> Vec<String> {
    let Some(p) = world.player(player) else {
        return Vec::new();
    };
    let mut lines = Vec::new();
    // THE DEPOSIT IS LOOKED UP, NEVER ASSUMED. A player keeps mining a deposit
    // the world can still hand back; if it ever could not, a line naming a
    // species nobody can read is worse than one line fewer.
    if let Some(mining) = p.mining
        && let Some(deposit) = world.deposit(mining.deposit)
    {
        lines.push(format!("mining {}", world.species(deposit.species).name()));
    }
    if let Some(assaying) = p.assaying
        && let Some(deposit) = world.deposit(assaying.deposit)
    {
        lines.push(format!(
            "assaying {}: {} ticks left",
            world.species(deposit.species).name(),
            crate::tuning::ASSAY_TICKS.saturating_sub(assaying.progress)
        ));
    }
    if let Some(line) = crafting_readout(world, player) {
        lines.push(line);
    }
    lines
}

/// WHAT ONE PRESS WOULD MAKE, as the words a menu row or a terminal line
/// shows, plus the identity a host needs to send the command.
///
/// **A host must not compose this sentence.** It names the OUTPUT item, and
/// the output's grade is not always the input's: a recipe with `raises_grade`
/// makes one grade better, and `Recipe::output_for` makes nothing at all out
/// of grade A. A client that wrote "Souktulore ore (A)" on a `sort` row would
/// be guessing a rule, and would be wrong on the one recipe in the table that
/// moves a grade (ASSA-88, Maren's wording ruling).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MakeOffer {
    /// Which catalogue row this is, so a host can name it in a command.
    pub what: MakeWhat,
    /// The stack a batch is spent from.
    pub input: Item,
    /// How many of `input` one batch costs.
    pub cost: u32,
    /// How many of `input` the player holds right now.
    pub have: u32,
    /// What one batch makes, or `None` when this input makes nothing.
    pub makes: Option<Item>,
    /// The row's sentence: what it makes, then what it costs.
    pub line: String,
    /// [`recipe_dead_end`], empty unless nothing in the game uses the output.
    pub dead_end: String,
    /// [`walls_clause`], empty on every row but the smelter's.
    pub walls: String,
}

/// The two catalogues a player can make something out of by hand. Not a
/// string: a host sends `Craft` for one and `MakePart` for the other, and
/// telling them apart by reading a label is how a client invents a rule.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MakeWhat {
    Recipe(crate::recipe::RecipeId),
    Part(PartKind),
}

/// EVERYTHING A PLAYER COULD MAKE BY HAND RIGHT NOW: one offer per catalogue
/// row per stack it could be made from, in the sim's own order.
///
/// **One offer per RECIPE × MATERIAL, not per stack** (Maren's ruling on
/// ASSA-88). A make-verb belongs to a recipe, so a pack holding two species of
/// ore used to grow two buttons both labelled `Craft smelter` which build
/// smelters with different walls — identical labels, different machines, told
/// apart only by which row you were standing on.
///
/// **ORDER IS THIS TABLE'S, THEN THE PACK'S.** `RecipeId::ALL`, then
/// `PartKind::ALL`, and inside each the player's own stack order, which
/// `Inventory` already sorts. A host that sorted again would be a second
/// opinion that drifts from the terminal's.
///
/// **A ROW WITH NO OUTPUT IS STILL AN OFFER.** `sort` on grade A makes
/// nothing, and the answer to that is a sentence saying so, not a missing row:
/// absence is never a cue (Maren, ASSA-37) and the player holding grade A ore
/// is exactly the person wondering why they cannot refine it. The clause is
/// [`best_grade_note`], the same words the refusal uses.
///
/// Hand work only. `Refine` and `Resmelt` happen inside a smelter, so they are
/// nobody's button; `recipes()` has told the client that much since ASSA-37.
pub fn make_offers(world: &World, player: PlayerId) -> Vec<MakeOffer> {
    let Some(p) = world.player(player) else {
        return Vec::new();
    };
    let mut offers = Vec::new();
    for id in crate::recipe::RecipeId::ALL {
        if !id.is_hand_craftable() {
            continue;
        }
        let recipe = id.recipe();
        for stack in p.inventory.stacks() {
            if stack.item.kind != recipe.input.0 {
                continue;
            }
            let makes = recipe.output_for(stack.item);
            // **ONE CLAUSE PER ROW, FIRST MATCH WINS, DEAD END OUTRANKING THE
            // MATERIAL'S SHORTFALL** (Maren's ruling on ASSA-88, copied from
            // `deposit_dead_end_note`'s `reach.or_else(unsmeltable)`). Her
            // reason is the whole of it: told its hardness is short, a player
            // goes and finds harder rock and spends 2 refined, only to learn
            // nothing consumes the thing. So when a recipe is a dead end, the
            // shortfall is not shown AT ALL -- not shown second, not shown in
            // smaller print.
            //
            // **AND TODAY THAT MAKES THE SHORTFALL CLAUSE UNREACHABLE.** `Gear`
            // is the only recipe with a `requires` and the only one whose
            // output nothing consumes, so the two sets coincide exactly and the
            // dead end always wins. I am building the ruled behaviour rather
            // than the reachable half of it, and saying so: it starts being
            // read the day a recipe gains a requirement or anything consumes a
            // gear, and `unmet_requirement_clause` is unit-tested directly
            // because `make_offers` cannot currently reach it.
            let dead_end = recipe_dead_end(recipe);
            let blocker = if dead_end.is_empty() {
                match makes {
                    None => Some(no_better_grade_clause(world, stack.item)),
                    Some(item) => recipe
                        .unmet_requirement(world.species(stack.item.species), stack.item)
                        .map(|(property, min)| {
                            shortfall_clause(&world.item_name(item), property, min)
                        }),
                }
            } else {
                // A DEAD END STILL HAS TO SAY WHAT IT MAKES, or the row claims
                // nothing and warns about nothing. The positive claim is right
                // here: the batch WILL produce the item, and that it is useless
                // is exactly what the slot says.
                match makes {
                    None => Some(no_better_grade_clause(world, stack.item)),
                    Some(_) => None,
                }
            };
            offers.push(MakeOffer {
                what: MakeWhat::Recipe(id),
                input: stack.item,
                cost: recipe.input.1,
                have: stack.count,
                makes,
                line: offer_line(
                    world,
                    makes.map(|item| (item, recipe.output.1)),
                    blocker.as_deref(),
                    recipe.input.1,
                    stack,
                ),
                dead_end,
                walls: walls_clause(world, recipe, stack.item),
            });
        }
    }
    for kind in PartKind::ALL {
        for stack in p.inventory.stacks() {
            if stack.item.kind != ItemKind::Refined {
                continue;
            }
            let cost = crate::assembly::spec(kind).size;
            let makes = crate::assembly::Part::of(kind, stack.item).as_item();
            offers.push(MakeOffer {
                what: MakeWhat::Part(kind),
                input: stack.item,
                cost,
                have: stack.count,
                makes: Some(makes),
                // NO BLOCKER ON A PART, AND IT IS THE CATALOGUE SAYING SO
                // RATHER THAN ME: a part has no property threshold to miss
                // (`PartSpec` carries size and contributions, no `requires`)
                // and no grade to raise, so neither clause has anything to
                // report. A `requires` added to `PartSpec` one day lands here
                // as a missing arm rather than as silence.
                line: offer_line(world, Some((makes, 1)), None, cost, stack),
                dead_end: String::new(),
                // A PART IS NEVER A BUILDING, so there are no walls to name.
                // Spelled out rather than defaulted for the same reason the
                // blocker is: the day a part can be planted, this is a line
                // somebody has to decide about.
                walls: String::new(),
            });
        }
    }
    offers
}

/// CONSEQUENCE FIRST, FIGURES AFTER (the ASSA-76 shape): what the press makes,
/// by species and grade, then what it spends out of what you hold.
///
/// The count of a batch's output is only spelled when it is more than one, so
/// today's table reads as a name and a cost; a recipe that one day yields two
/// says so without this sentence being rewritten.
fn offer_line(
    world: &World,
    makes: Option<(Item, u32)>,
    blocker: Option<&str>,
    cost: u32,
    from: &ItemStack,
) -> String {
    // **ONE SHAPE WHETHER YOU CAN AFFORD IT OR NOT** (Maren's ruling, ASSA-129).
    // `{cost} of your {have} {item}` is a PARTITIVE: it asserts you hold at
    // least `have` and are taking `cost` of them. Both numbers are correct and
    // the sentence is false the moment you cannot afford the thing -- "5 of
    // your 3 Tonore ore (A)", which is what the game says to a player holding
    // their first ore, about the first thing they can build. The state where a
    // cost line has work to do is the state it garbled.
    //
    // NO BRANCH ON `from.count >= cost`, and that is the half of the ruling
    // that matters. Affordability changes tick to tick and `step` answers it at
    // the press; a sentence that picked its words by comparing them would be a
    // second opinion about affordability living in the describer. The trailing
    // clause is a FIGURE and not a limit, so ASSA-88 ("the limit binds the verb,
    // never trailing after a comma") is untouched: every blocker still binds
    // its verb ahead of the dash.
    let spend = format!(
        "{cost} {}, you have {}",
        world.item_name(from.item),
        from.count
    );
    // **THE LIMIT BINDS THE CLAIM IT KILLS, WITH NO COMMA BEFORE THE "IF"**
    // (Maren's ruling on ASSA-88, the shape `species_table` already uses for
    // "fuel at B or better if you could mine it"). What shipped first was
    // "nothing from X: grade A is already the best", which names no verb at all
    // and leaves the reason trailing after a colon -- the defect her ruling
    // describes, in my own code.
    match (makes, blocker) {
        (_, Some(why)) => format!("{why} — {spend}"),
        (Some((item, 1)), None) => format!("{} — {spend}", world.item_name(item)),
        (Some((item, n)), None) => format!("{n} × {} — {spend}", world.item_name(item)),
        // UNREACHABLE BY CONSTRUCTION rather than by luck: every caller that can
        // produce `None` for `makes` produces a blocker in the same step,
        // because a row with no output has a reason and `make_offers` is the
        // only place that knows it. Written out so that the next arm added here
        // has to decide, rather than inheriting a silent empty claim.
        (None, None) => format!("nothing from {} — {spend}", world.item_name(from.item)),
    }
}

/// WHY A GRADE-A STACK CANNOT BE REFINED. One sentence, two callers: the
/// refusal a player reads after pressing, and the offer row they read before.
/// It was written out inside `event_line`'s match and nowhere else, so the
/// menu either repeated it in different words or said nothing.
pub fn best_grade_note() -> &'static str {
    "grade A is already the best; refining can't improve it"
}

/// WHY A GRADE-RAISING RECIPE MAKES NOTHING OUT OF THIS STACK, bound to the
/// claim it kills: "a better grade of X ore if it were not already grade A".
///
/// THE SAME FACT AS `best_grade_note` IN A DIFFERENT MOOD, and they sit next to
/// each other on purpose. The refusal is read AFTER a press and states what
/// happened; an offer row is read BEFORE one and has to be a conditional on the
/// thing it would have made (Maren, ASSA-88: the disqualifier inside the claim,
/// never trailing after a comma). Neither can be derived from the other because
/// English will not have it -- but the only part that could DRIFT is the grade,
/// and both say A for the same reason: `Grade::better` returns `None` there and
/// nowhere else.
fn no_better_grade_clause(world: &World, input: Item) -> String {
    format!(
        "a better grade of {} {} if it were not already grade {}",
        world.species(input.species).name(),
        input.kind.name(),
        input.grade.letter()
    )
}

/// WHY THIS MATERIAL CANNOT FEED THIS RECIPE, bound to the claim it kills:
/// "Minyte gear (B) if its hardness reached 20 at that grade".
///
/// **THE NUMBER HAS ONE SOURCE.** The property and the threshold both arrive
/// from `Recipe::unmet_requirement`, which is the same call `step` makes before
/// refusing, so the figure in the offer and the figure in the refusal cannot
/// disagree. The refusal's own indicative wording stays where it is, for the
/// reason given on `no_better_grade_clause`.
pub fn shortfall_clause(made: &str, property: Property, min: u32) -> String {
    format!(
        "{made} if its {} reached {min} at that grade",
        property.name()
    )
}

impl MakeOffer {
    /// THE COMMAND THIS OFFER SENDS, so the catalogue a row came from decides
    /// which command it is rather than a host reading the label back. `Craft`
    /// and `MakePart` are different commands with differently shaped payloads,
    /// and a host that chose between them by inspecting a sentence would be
    /// the one place that breaks when a third catalogue appears.
    pub fn command(&self, count: u32) -> PlayerCommand {
        match self.what {
            MakeWhat::Recipe(recipe) => PlayerCommand::Craft {
                recipe,
                item: self.input,
                count,
            },
            MakeWhat::Part(kind) => PlayerCommand::MakePart {
                kind,
                material: self.input,
                count,
            },
        }
    }
}

/// THE SAME MENU, FOR A TERMINAL: what you could make by hand right now, with
/// the line to type beside each row.
///
/// The game is playable headless by rule, so the menu the window grew for
/// ASSA-88 is a block here first. Both halves are existing describers —
/// [`command_line`] spells what to type, [`make_offers`] words what it makes —
/// so there is nothing in this function for the two hosts to disagree about.
pub fn make_offer_table(world: &World, player: PlayerId) -> String {
    let offers = make_offers(world, player);
    if offers.is_empty() {
        return "you are carrying nothing a pair of hands can work with\n".to_string();
    }
    let mut out = String::from("what you could make by hand, from what you are carrying:\n");
    for offer in &offers {
        // EVERY CLAUSE THE ROW CARRIES, IN ONE ORDER, AND THE TERMINAL GETS
        // THEM TOO. A menu only the window has is a feature that only works
        // with graphics, which this repo does not allow; the window appends
        // the same two fields as their own lines. They are disjoint today — a
        // smelter is consumed, so its row has no dead end — and the order is
        // fixed anyway, because a disqualifier outranks a figure (Maren's
        // precedence ruling on ASSA-88).
        let clauses: String = [&offer.dead_end, &offer.walls]
            .iter()
            .filter(|c| !c.is_empty())
            .map(|c| format!(" — {c}"))
            .collect();
        let _ = writeln!(
            out,
            "  {:<34} {}{}",
            command_line(&offer.command(1), world),
            offer.line,
            clauses
        );
    }
    out
}
