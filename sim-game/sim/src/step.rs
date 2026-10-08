//! Advancing the world one tick.

use crate::assembly::{self, AssemblyPlan, Mount, Part, PartKind, spec};
use crate::building::{
    Building, BuildingId, BuildingKind, Machine, MachineState, Slot, footprint_tiles,
};
use crate::command::{Event, Input, PlayerCommand, RejectReason, StopReason, SystemCommand};
use crate::inventory::Inventory;
use crate::item::{Item, ItemKind, ItemStack};
use crate::mineral::{SpeciesId, validate_name};
use crate::player::{Assaying, Crafting, Mining, Player};
use crate::recipe::{Recipe, smelter_recipe_for};
use crate::tuning::{
    ASSAY_TICKS, BURN_TICKS_PER_REACTIVITY, HAND_WORK_PER_TICK, PICK_WEAR_PER_SWING, REACH,
    SMELTER_FUEL_CAP, SMELTER_INPUT_CAP, SMELTER_OUTPUT_CAP, WORK_PER_UNIT, YIELD_BY_GRADE,
};
use crate::types::{PlayerId, TilePos};
use crate::world::World;

/// Advance the world by exactly one tick.
///
/// `inputs` are everything scheduled for this tick, in the order every peer
/// agreed on. Anything that happened is appended to `events`.
pub fn step(world: &mut World, inputs: &[Input], events: &mut Vec<Event>) {
    // **THE STATE A PLAYER LAST SAW**, captured before this tick's commands
    // are applied, so the edge compared below is the one they would notice
    // (ASSA-80). Taken here rather than inside `run_smelters` because the
    // insert that causes a stall lands in the command phase of the same tick:
    // by the time the smelter system runs, a stall that began this tick looks
    // exactly like one that began an hour ago.
    //
    // A `Vec` in `world.buildings` order, which is stable, because every peer
    // must compute the same events in the same order.
    let before: Vec<(BuildingId, bool)> = world
        .buildings
        .iter()
        .filter(|b| matches!(b.kind, BuildingKind::Smelter(_)))
        .map(|b| (b.id, world.smelter_state(b).stall().is_some()))
        .collect();

    for input in inputs {
        match input {
            Input::System(command) => apply_system(world, command, events),
            Input::Player { player, command } => apply_player(world, *player, command, events),
        }
    }

    // Systems run here in a fixed order. Later: belts, inserters, drones.
    //
    // `mine_by_machine` sits immediately after `mine_by_hand` because all
    // mining belongs together, and because the position is part of the state
    // hash: moving it changes what every peer computes, so it moves once,
    // deliberately, or not at all.
    move_players(world, events);
    mine_by_hand(world, events);
    mine_by_machine(world, events);
    assay(world, events);
    craft_by_hand(world, events);
    run_smelters(world, events);
    announce_new_stalls(world, &before, events);

    world.tick += 1;
}

fn apply_system(world: &mut World, command: &SystemCommand, events: &mut Vec<Event>) {
    match command {
        SystemCommand::AddPlayer { name } => {
            let id = PlayerId(world.players.len() as u32);
            world
                .players
                .push(Player::new(id, name.clone(), world.spawn_tile()));
            events.push(Event::PlayerJoined {
                player: id,
                name: name.clone(),
            });
        }
    }
}

/// Validate and apply one player command. Validation lives in the sim, not
/// the UI or the relay: every peer runs it, so a modified client that sends
/// an illegal command gets it rejected everywhere.
fn apply_player(
    world: &mut World,
    player: PlayerId,
    command: &PlayerCommand,
    events: &mut Vec<Event>,
) {
    let reject = |reason, events: &mut Vec<Event>| {
        events.push(Event::CommandRejected {
            player,
            command: command.clone(),
            reason,
        });
    };

    if world.player(player).is_none() {
        return reject(RejectReason::UnknownPlayer, events);
    }
    // Items name a species by index; never trust a client's index. Every
    // command carrying one is listed here, because the stats and recipe code
    // downstream indexes `world.species` directly.
    let unknown = |s: &SpeciesId| !crate::mineral::known_species(&world.species, *s);
    let names_unknown_species = match command {
        PlayerCommand::Craft { item, .. }
        | PlayerCommand::Place { item, .. }
        | PlayerCommand::Insert { item, .. }
        | PlayerCommand::MakePart { material: item, .. } => unknown(&item.species),
        PlayerCommand::Rename { species, .. } | PlayerCommand::GrantRename { species, .. } => {
            unknown(species)
        }
        PlayerCommand::Assemble { frame, mounted } => std::iter::once(frame)
            .chain(mounted)
            .any(|i| unknown(&i.species)),
        _ => false,
    };
    if names_unknown_species {
        return reject(RejectReason::UnknownSpecies, events);
    }

    match command.clone() {
        PlayerCommand::Mine => {
            let pos = world.player(player).expect("checked above").pos;
            let Some(d) = world.deposit_at(pos) else {
                return reject(RejectReason::NotOnDeposit, events);
            };
            if d.is_depleted() {
                return reject(RejectReason::DepositDepleted, events);
            }
            let (deposit, species) = (d.id, d.species);
            // ONE GATE, NAMED ONCE (ASSA-43). This used to compare against
            // `HAND_MINE_MAX_HARDNESS` here, which made `ladder::hand_minable`
            // a second copy of the rule that merely happened to agree. Every
            // reader of reach — this, `mine_by_machine`, `building_status`, the
            // deposit line, the Godot facts — now asks the same function.
            if !crate::ladder::hand_minable(world.species(species)) {
                return reject(RejectReason::TooHardForHands, events);
            }
            let p = world.player_mut(player).expect("checked above");
            if p.mining.is_some_and(|m| m.deposit == deposit) {
                return; // already at it
            }
            p.mining = Some(Mining {
                deposit,
                progress: 0,
            });
            events.push(Event::MiningStarted {
                player,
                deposit,
                species,
            });
        }
        PlayerCommand::Craft {
            recipe,
            item,
            count,
        } => {
            if count == 0 {
                return reject(RejectReason::ZeroCount, events);
            }
            if !recipe.is_hand_craftable() {
                return reject(RejectReason::NotHandCraftable, events);
            }
            let r: &Recipe = recipe.recipe();
            if item.kind != r.input.0 {
                return reject(RejectReason::WrongItem, events);
            }
            if let Some((property, min)) = r.unmet_requirement(world.species(item.species), item) {
                return reject(RejectReason::RequirementNotMet(property, min), events);
            }
            if r.output_for(item).is_none() {
                return reject(RejectReason::AlreadyBestGrade, events);
            }
            let p = world.player_mut(player).expect("checked above");
            // SAME GESTURE, SAME ANSWER AS `Mine` (ASSA-109). Pressing Make
            // again on the batch already running used to refund it and start
            // over at progress 0 — materials back, elapsed ticks gone, and
            // the one sentence that said so goes to a log folded away by
            // default. `count` is deliberately NOT part of this identity:
            // the Game Director put topping up a batch out of scope, and the
            // client only ever sends 1.
            if p.crafting
                .is_some_and(|c| c.recipe == recipe && c.input == item)
            {
                return; // already at it
            }
            if let Some(c) = p.crafting {
                // Finish what's in progress first; refund it like Stop does.
                refund(&mut p.inventory, c.recipe.recipe(), c.input);
                events.push(Event::CraftingStopped {
                    player,
                    recipe: c.recipe,
                    reason: StopReason::Stopped,
                });
            }
            p.crafting = None;
            if !consume(&mut p.inventory, r, item) {
                return reject(RejectReason::MissingItems(item), events);
            }
            p.crafting = Some(Crafting {
                recipe,
                input: item,
                progress: 0,
                remaining: count,
            });
            events.push(Event::CraftStarted {
                player,
                recipe,
                item,
                count,
            });
        }
        PlayerCommand::Place { item, pos } => {
            let Some(kind) = BuildingKind::for_item(item.kind) else {
                return reject(RejectReason::NotPlaceable, events);
            };
            let me = world.player(player).expect("checked above");
            if !me.inventory.has(item, 1) {
                return reject(RejectReason::MissingItems(item), events);
            }
            let tiles: Vec<TilePos> = footprint_tiles(pos, kind.footprint()).collect();
            if tiles.iter().any(|&t| !world.in_bounds(t)) {
                return reject(RejectReason::OutOfBounds, events);
            }
            if tiles.iter().any(|&t| world.building_at(t).is_some()) {
                return reject(RejectReason::TileOccupied, events);
            }
            let probe = Building {
                id: BuildingId(0),
                pos,
                material: item,
                kind: kind.clone(),
            };
            if probe.distance_from(me.pos) > REACH {
                return reject(RejectReason::OutOfReach, events);
            }

            let id = BuildingId(world.next_building_id);
            world.next_building_id += 1;
            let taken = world
                .player_mut(player)
                .expect("checked above")
                .inventory
                .remove(item, 1);
            debug_assert!(taken);
            world.buildings.push(Building {
                id,
                pos,
                material: item,
                kind,
            });
            events.push(Event::BuildingPlaced {
                player,
                building: id,
                item,
                pos,
            });
        }
        PlayerCommand::Insert {
            building,
            slot,
            item,
            count,
        } => {
            if count == 0 {
                return reject(RejectReason::ZeroCount, events);
            }
            let me_pos = world.player(player).expect("checked above").pos;
            let Some(b) = world.building(building) else {
                return reject(RejectReason::UnknownBuilding, events);
            };
            if b.distance_from(me_pos) > REACH {
                return reject(RejectReason::OutOfReach, events);
            }
            // A machine has no insertable slots at all: `Slot` names the
            // smelter's, and ore leaves a drill by `Take` (decision 9).
            if b.kind.machine().is_some() {
                return reject(RejectReason::NotInsertable, events);
            }
            if !world
                .player(player)
                .expect("checked above")
                .inventory
                .has(item, count)
            {
                return reject(RejectReason::MissingItems(item), events);
            }
            let walls = world.max_temperature(b);
            let (cap, target) = match slot {
                Slot::Input => {
                    let Some(recipe) = smelter_recipe_for(item.kind) else {
                        return reject(RejectReason::WrongItem, events);
                    };
                    if recipe.recipe().output_for(item).is_none() {
                        return reject(RejectReason::AlreadyBestGrade, events);
                    }
                    let needs = u32::from(world.species(item.species).sheet.heat_tolerance);
                    if needs > walls {
                        return reject(RejectReason::TooHotForWalls, events);
                    }
                    let BuildingKind::Smelter(s) =
                        &mut world.building_mut(building).expect("checked above").kind
                    else {
                        return reject(RejectReason::NotInsertable, events);
                    };
                    (SMELTER_INPUT_CAP, &mut s.input)
                }
                Slot::Fuel => {
                    if !matches!(item.kind, ItemKind::Ore | ItemKind::Refined) {
                        return reject(RejectReason::WrongItem, events);
                    }
                    if world.fuel_temperature(item).is_none() {
                        return reject(RejectReason::NotFuel, events);
                    }
                    let BuildingKind::Smelter(s) =
                        &mut world.building_mut(building).expect("checked above").kind
                    else {
                        return reject(RejectReason::NotInsertable, events);
                    };
                    (SMELTER_FUEL_CAP, &mut s.fuel)
                }
            };
            let have = match *target {
                None => 0,
                Some(stack) if stack.item == item => stack.count,
                Some(_) => return reject(RejectReason::SlotFull, events),
            };
            // TAKE WHAT FITS (ASSA-48, Game Director's ruling). This used to
            // reject the whole offer when `have + count > cap`, so a player who
            // had mined for thirty seconds and pressed one button was told
            // "that slot is full" about an EMPTY slot. One press is the client's
            // whole interface, and a client choosing a smaller number would be
            // deciding how much fuel a fire wants — a sheet reading it does not
            // have. The sim owns the cap, so the sim owns the clamp.
            //
            // Rejection survives for the one case that is not a clamp: no room
            // at all. "Nothing happened" is then true, and the player needs to
            // empty the slot rather than offer less.
            let room = cap.saturating_sub(have);
            if room == 0 {
                return reject(RejectReason::SlotFull, events);
            }
            let fits = count.min(room);
            *target = Some(ItemStack::new(item, have + fits));
            let taken = world
                .player_mut(player)
                .expect("checked above")
                .inventory
                .remove(item, fits);
            debug_assert!(taken);
            events.push(Event::ItemsInserted {
                player,
                building,
                slot,
                item,
                count: fits,
                left: count - fits,
            });
        }
        PlayerCommand::Take { building } => {
            let me_pos = world.player(player).expect("checked above").pos;
            let Some(b) = world.building_mut(building) else {
                return reject(RejectReason::UnknownBuilding, events);
            };
            if b.distance_from(me_pos) > REACH {
                return reject(RejectReason::OutOfReach, events);
            }
            // Ore comes out of a drill exactly as refined material comes out
            // of a smelter (decision 9): one command, two holders.
            let taken = match &mut b.kind {
                BuildingKind::Smelter(s) => s.output.take(),
                BuildingKind::Machine(m) => m.held.take(),
            };
            let Some(stack) = taken else {
                return reject(RejectReason::NothingToTake, events);
            };
            world
                .player_mut(player)
                .expect("checked above")
                .inventory
                .add_stack(stack);
            events.push(Event::ItemsTaken {
                player,
                building,
                item: stack.item,
                count: stack.count,
            });
        }
        PlayerCommand::Pickup { building } => {
            let me_pos = world.player(player).expect("checked above").pos;
            let Some(i) = world.buildings.iter().position(|b| b.id == building) else {
                return reject(RejectReason::UnknownBuilding, events);
            };
            if world.buildings[i].distance_from(me_pos) > REACH {
                return reject(RejectReason::OutOfReach, events);
            }
            let b = world.buildings.remove(i);
            let inv = &mut world.player_mut(player).expect("checked above").inventory;
            match b.kind {
                BuildingKind::Smelter(s) => {
                    inv.add(b.material, 1);
                    for stack in [s.input, s.fuel, s.output].into_iter().flatten() {
                        inv.add_stack(stack);
                    }
                }
                // A machine was never an item, so it comes back as its parts.
                // Picking one up is lossless: the mass test already passed.
                BuildingKind::Machine(m) => {
                    for item in m.assembly.part_items() {
                        inv.add(item, 1);
                    }
                    if let Some(stack) = m.held {
                        inv.add_stack(stack);
                    }
                }
            }
            events.push(Event::BuildingRemoved {
                player,
                building,
                item: b.material,
                pos: b.pos,
            });
        }
        PlayerCommand::Assay => {
            let pos = world.player(player).expect("checked above").pos;
            let Some(d) = world.deposit_at(pos) else {
                return reject(RejectReason::NotOnDeposit, events);
            };
            let (deposit, species) = (d.id, d.species);
            if world.species(species).assayed {
                return reject(RejectReason::AlreadyAssayed, events);
            }
            let p = world.player_mut(player).expect("checked above");
            if p.assaying.is_some_and(|a| a.deposit == deposit) {
                return; // already at it
            }
            p.assaying = Some(Assaying {
                deposit,
                progress: 0,
            });
            events.push(Event::AssayStarted {
                player,
                deposit,
                species,
            });
        }
        PlayerCommand::Rename { species, name } => {
            let s = world.species(species);
            if s.discoverer.is_none() {
                return reject(RejectReason::NotDiscovered, events);
            }
            if !s.may_rename(player) {
                return reject(RejectReason::NotDiscoverer, events);
            }
            if let Err(e) = validate_name(&name) {
                return reject(RejectReason::BadName(e), events);
            }
            world.species_mut(species).player_name = Some(name.clone());
            events.push(Event::SpeciesRenamed {
                player,
                species,
                name,
            });
        }
        PlayerCommand::GrantRename { species, to } => {
            let s = world.species(species);
            if s.discoverer.is_none() {
                return reject(RejectReason::NotDiscovered, events);
            }
            if s.discoverer != Some(player) {
                return reject(RejectReason::NotDiscoverer, events);
            }
            if world.player(to).is_none() {
                return reject(RejectReason::NoSuchPlayer, events);
            }
            if s.may_rename(to) {
                return reject(RejectReason::AlreadyGranted, events);
            }
            world.species_mut(species).rename_grants.push(to);
            events.push(Event::RenameGranted {
                species,
                from: player,
                to,
            });
        }
        PlayerCommand::MakePart {
            kind,
            material,
            count,
        } => {
            if count == 0 {
                return reject(RejectReason::ZeroCount, events);
            }
            // A part is made of refined material and nothing else, so say so
            // rather than quietly coercing whatever the client sent.
            if material.kind != ItemKind::Refined {
                return reject(RejectReason::WrongItem, events);
            }
            let needed = spec(kind).size.saturating_mul(count);
            let part = Part::of(kind, material).as_item();
            let p = world.player_mut(player).expect("checked above");
            if !p.inventory.remove(material, needed) {
                return reject(RejectReason::MissingItems(material), events);
            }
            p.inventory.add(part, count);
            events.push(Event::PartsMade {
                player,
                part,
                count,
            });
        }
        PlayerCommand::Assemble { frame, mounted } => {
            // ONE DECISION, AND THIS ARM DOES NOT OWN IT (ASSA-324).
            // `assembly::plan` holds the whole refusal chain and the tallied
            // cost, because a headless `design`, the Godot build screen and
            // this arm all have to agree — about the verdict, about the order
            // a design is refused in, and about WHICH item is missing. What is
            // left here is the only thing a preview must not do: spend.
            let me = world.player(player).expect("checked above");
            let plan = assembly::plan(frame, &mounted, &world.species, &me.inventory);
            if let Some(reason) = plan.refusal() {
                return reject(reason, events);
            }
            let AssemblyPlan::Weighed { built, cost, .. } = plan else {
                unreachable!("refusal() is None only for a Weighed plan the player can afford")
            };
            let p = world.player_mut(player).expect("checked above");
            for s in &cost {
                let taken = p.inventory.remove(s.item, s.count);
                debug_assert!(taken);
            }
            p.assemblies.push(built);
            events.push(Event::Assembled {
                player,
                assembly: (p.assemblies.len() - 1) as u32,
            });
        }
        PlayerCommand::Equip { assembly } => {
            let me = world.player(player).expect("checked above");
            let Some(built) = me.assemblies.get(assembly as usize) else {
                return reject(RejectReason::NoSuchAssembly, events);
            };
            if built.assembly.mount() != Some(Mount::Held) {
                return reject(RejectReason::WrongMount, events);
            }
            let taken = world
                .player_mut(player)
                .expect("checked above")
                .assemblies
                .remove(assembly as usize);
            let p = world.player_mut(player).expect("checked above");
            // Whatever was in hand goes back to the list, wear and all.
            if let Some(old) = p.tool.replace(taken) {
                p.assemblies.push(old);
            }
            events.push(Event::Equipped { player });
        }
        PlayerCommand::Unequip => {
            let p = world.player_mut(player).expect("checked above");
            let Some(tool) = p.tool.take() else {
                return reject(RejectReason::NothingEquipped, events);
            };
            p.assemblies.push(tool);
            events.push(Event::Unequipped { player });
        }
        PlayerCommand::PlaceAssembly { assembly, pos } => {
            let me = world.player(player).expect("checked above");
            let Some(built) = me.assemblies.get(assembly as usize) else {
                return reject(RejectReason::NoSuchAssembly, events);
            };
            if built.assembly.mount() != Some(Mount::Planted) {
                return reject(RejectReason::WrongMount, events);
            }
            let kind = BuildingKind::Machine(Machine::new(built.assembly.clone()));
            let material = built.assembly.frame.refined();

            // Where it goes is checked before whether it survives: an illegal
            // position is a rejection, not a broken machine.
            let tiles: Vec<TilePos> = footprint_tiles(pos, kind.footprint()).collect();
            if tiles.iter().any(|&t| !world.in_bounds(t)) {
                return reject(RejectReason::OutOfBounds, events);
            }
            if tiles.iter().any(|&t| world.building_at(t).is_some()) {
                return reject(RejectReason::TileOccupied, events);
            }
            let probe = Building {
                id: BuildingId(0),
                pos,
                material,
                kind: kind.clone(),
            };
            if probe.distance_from(me.pos) > REACH {
                return reject(RejectReason::OutOfReach, events);
            }

            let taken = world
                .player_mut(player)
                .expect("checked above")
                .assemblies
                .remove(assembly as usize);
            let stats = taken.assembly.stats(&world.species);

            // Decision 11: placement is the test.
            if stats.is_overweight() {
                // Disjoint field borrows: the roll needs the sheets and the
                // rng at once, and the parts go back to the player after.
                let World {
                    species,
                    rng,
                    players,
                    ..
                } = world;
                let outcome = taken.assembly.break_apart(species, rng);
                let inv = &mut players[player.0 as usize].inventory;
                for item in &outcome.returned {
                    inv.add(*item, 1);
                }
                events.push(Event::MachineBroke {
                    player,
                    pos: Some(pos),
                    mass: stats.mass,
                    budget: stats.budget,
                    lost: outcome.lost,
                    returned: outcome.returned,
                });
                return;
            }

            let id = BuildingId(world.next_building_id);
            world.next_building_id += 1;
            world.buildings.push(Building {
                id,
                pos,
                material,
                kind,
            });
            events.push(Event::MachinePlaced {
                player,
                building: id,
                pos,
            });
        }
        PlayerCommand::MoveTo { target } => {
            if !world.in_bounds(target) {
                return reject(RejectReason::OutOfBounds, events);
            }
            let p = world.player_mut(player).expect("checked above");
            if p.pos == target {
                p.target = None;
                return;
            }
            p.target = Some(target);
            events.push(Event::MoveStarted {
                player,
                from: p.pos,
                to: target,
            });
        }
        PlayerCommand::Stop => {
            let p = world.player_mut(player).expect("checked above");
            if p.target.take().is_some() {
                events.push(Event::PlayerStopped { player, pos: p.pos });
            }
            if let Some(m) = p.mining.take() {
                events.push(Event::MiningStopped {
                    player,
                    deposit: m.deposit,
                    reason: StopReason::Stopped,
                });
            }
            if let Some(c) = p.crafting.take() {
                refund(&mut p.inventory, c.recipe.recipe(), c.input);
                events.push(Event::CraftingStopped {
                    player,
                    recipe: c.recipe,
                    reason: StopReason::Stopped,
                });
            }
            if let Some(a) = p.assaying.take() {
                events.push(Event::AssayStopped {
                    player,
                    deposit: a.deposit,
                    reason: StopReason::Stopped,
                });
            }
        }
    }
}

/// First contact: the first player to mine or assay a species becomes its
/// discoverer and may name it.
fn discover(
    world: &mut World,
    species: crate::mineral::SpeciesId,
    player: PlayerId,
    events: &mut Vec<Event>,
) {
    let s = world.species_mut(species);
    if s.discoverer.is_none() {
        s.discoverer = Some(player);
        events.push(Event::SpeciesDiscovered { player, species });
    }
}

/// Take one batch of inputs, or take nothing and return false.
fn consume(inv: &mut Inventory, recipe: &Recipe, input: Item) -> bool {
    inv.remove(input, recipe.input.1)
}

/// Give back one batch of inputs (a cancelled craft).
fn refund(inv: &mut Inventory, recipe: &Recipe, input: Item) {
    inv.add(input, recipe.input.1);
}

/// Movement system: each walking player steps one tile toward their target.
fn move_players(world: &mut World, events: &mut Vec<Event>) {
    for p in &mut world.players {
        let Some(target) = p.target else { continue };
        p.pos.x += (target.x - p.pos.x).signum();
        p.pos.y += (target.y - p.pos.y).signum();
        if p.pos == target {
            p.target = None;
            events.push(Event::PlayerArrived {
                player: p.id,
                pos: target,
            });
        }
    }
}

/// Player mining system: every player standing on the deposit they are mining
/// accumulates work, and each `WORK_PER_UNIT` of it the deposit loses one unit
/// and the player gains the grade's yield.
///
/// **BARE HANDS AND A PICK ARE THE SAME CODE** (decision 6). The only thing a
/// tool changes is how much work a tick is worth — `HAND_WORK_PER_TICK`
/// without one, the design's `Speed` stat with one — and whether anything
/// drains afterwards. A tool is not a second way to mine.
///
/// **THE REMAINDER CARRIES.** Progress is reduced by `WORK_PER_UNIT`, never
/// reset, so the long-run rate is exactly `WORK_PER_UNIT / work` rather than
/// its ceiling: that is what makes the rate monotone in effective hardness
/// (A3) and what makes decision 8's grade comparison measurable.
///
/// **A PICK DOES NOT UNLOCK HARDER ORE** (decision 7). The hand hardness gate
/// is on the `Mine` command and this system never revisits it, so a tool buys
/// throughput and nothing else.
fn mine_by_hand(world: &mut World, events: &mut Vec<Event>) {
    for i in 0..world.players.len() {
        let Some(m) = world.players[i].mining else {
            continue;
        };
        let player = world.players[i].id;
        let pos = world.players[i].pos;
        let deposit = world
            .deposit(m.deposit)
            .expect("mining refers to an existing deposit");
        if !deposit.contains(pos) {
            world.players[i].mining = None;
            events.push(Event::MiningStopped {
                player,
                deposit: m.deposit,
                reason: StopReason::LeftDeposit,
            });
            continue;
        }

        let work = match &world.players[i].tool {
            Some(built) => built.assembly.stats(&world.species).speed,
            None => HAND_WORK_PER_TICK,
        };
        let progress = m.progress + work;
        if progress < WORK_PER_UNIT {
            world.players[i].mining = Some(Mining { progress, ..m });
            continue;
        }

        let d = world.deposit_mut(m.deposit).expect("checked above");
        d.amount -= 1;
        let grade = d.grade();
        let item = Item::new(ItemKind::Ore, d.species, grade);
        let amount = YIELD_BY_GRADE[grade as usize];
        let depleted = d.is_depleted();
        world.players[i].inventory.add(item, amount);
        events.push(Event::OreMined {
            player,
            deposit: m.deposit,
            item,
            amount,
        });
        discover(world, item.species, player, events);

        // ORE FIRST, THEN THE TOOL (A4 and the ruling on this item): the swing
        // that empties the pool still yields what it dug. Never lose work in
        // progress.
        wear_tool(world, i, events);

        if depleted {
            world.players[i].mining = None;
            events.push(Event::DepositDepleted { deposit: m.deposit });
            events.push(Event::MiningStopped {
                player,
                deposit: m.deposit,
                reason: StopReason::Depleted,
            });
        } else {
            world.players[i].mining = Some(Mining {
                progress: progress - WORK_PER_UNIT,
                ..m
            });
        }
    }
}

/// Drain one swing from the tool player `i` is holding, and dispose of it if
/// the pool is now empty. Does nothing to a player with empty hands.
///
/// **NO `rng` ON THIS PATH, EVER.** The mass break at placement rolls per
/// part; wearing out is certain. Keeping it deterministic also keeps the hash
/// path identical whether or not anyone is holding a pick.
///
/// **WHAT A WORN-OUT PICK LOSES** (Game Director's ruling on ASSA-6): the
/// **head** is consumed and the **handle** returns as an `ItemKind::Part`.
/// Durability is sourced from the head's strength, so the part whose number
/// ran out is the part that is gone — legible with no tutorial. Re-heading is
/// `Assemble` with the handle out of the inventory, which is why there is no
/// repair command anywhere in this crate.
fn wear_tool(world: &mut World, i: usize, events: &mut Vec<Event>) {
    let Some(built) = &world.players[i].tool else {
        return;
    };
    let remaining = built.durability.saturating_sub(PICK_WEAR_PER_SWING);
    if remaining > 0 {
        world.players[i]
            .tool
            .as_mut()
            .expect("checked above")
            .durability = remaining;
        return;
    }

    // Spent. `expect` rather than a fallback: a held frame always has a head,
    // because `Assemble` refuses a handle without one (min 1, max 1) and no
    // other path builds a tool.
    let worn = world.players[i].tool.take().expect("checked above");
    let head = worn
        .assembly
        .mounted
        .iter()
        .find(|p| p.kind == PartKind::Head)
        .expect("a held frame always carries a head")
        .as_item();
    let handle = worn.assembly.frame.as_item();
    world.players[i].inventory.add(handle, 1);
    events.push(Event::ToolWornOut {
        player: world.players[i].id,
        head,
        handle,
    });
}

/// Machine mining system: every placed machine sitting on a deposit it can
/// work accumulates its own `Speed` into its own buffer.
///
/// **THE SAME CURVE AS A PAIR OF HANDS** (decision 8: picks and drills alike).
/// It reads `Speed` off the same catalogue row and carries its remainder the
/// same way; a drill is a machine whose frame happens to be planted.
///
/// **A DRILL IS A THROUGHPUT UPGRADE, NOT A HARDNESS UNLOCK** (decision 7).
/// It is held to `HAND_MINE_MAX_HARDNESS` exactly as hands are, so a deposit
/// too hard to dig by hand is too hard to drill. The hardness ladder above
/// rung zero stays parked, and this is the line that parks it.
///
/// **NO WEAR** (decision 12): nothing here touches durability, so a planted
/// machine runs forever. That asymmetry is the decision's, not the model's —
/// the head still contributes a pool, and nothing drains it.
fn mine_by_machine(world: &mut World, events: &mut Vec<Event>) {
    for i in 0..world.buildings.len() {
        let BuildingKind::Machine(machine) = &world.buildings[i].kind else {
            continue;
        };
        let building = world.buildings[i].id;
        // **THE ONE QUESTION** (ASSA-94). Four `continue`s used to live here —
        // no deposit, mined out, too hard, no room — each a copy of a test
        // `debug::machine_status` also made in order to write its prose. They
        // are now one answer in `World::machine_state`, and the arm that works
        // carries what the work needs, so nothing below is looked up twice.
        let MachineState::Working {
            deposit,
            species,
            grade,
        } = world.machine_state(&world.buildings[i], machine)
        else {
            continue;
        };
        let item = Item::new(ItemKind::Ore, species, grade);
        let amount = YIELD_BY_GRADE[grade as usize];
        let stats = machine.assembly.stats(&world.species);
        let held = machine.held.map_or(0, |s| s.count);

        let progress = machine.progress + stats.speed;
        let Some(left) = progress.checked_sub(WORK_PER_UNIT) else {
            let BuildingKind::Machine(m) = &mut world.buildings[i].kind else {
                unreachable!("matched above")
            };
            m.progress = progress;
            continue;
        };

        world.deposit_mut(deposit).expect("checked above").amount -= 1;
        let depleted = world.deposit(deposit).expect("checked above").is_depleted();
        let BuildingKind::Machine(m) = &mut world.buildings[i].kind else {
            unreachable!("matched above")
        };
        m.progress = left;
        m.held = Some(match m.held {
            Some(stack) => ItemStack::new(stack.item, stack.count + amount),
            None => ItemStack::new(item, amount),
        });
        let now = held + amount;
        events.push(Event::MachineMined {
            building,
            deposit,
            item,
            amount,
            held: now,
        });
        // The stall is announced on the tick it fills, not on every tick it
        // sits full.
        //
        // **ASKED OF THE BUFFER, NOT OF `machine_state`, AND DELIBERATELY SO.**
        // `announce_new_stalls` can re-read the smelter's whole state because
        // every smelter stall outlives the tick. This one cannot: if the last
        // unit also mined the deposit out, `machine_state` now answers
        // `Idle(DepositMinedOut)` — the deposit arm comes first — and a stall
        // that fires today would go silent. So the edge asks decision 9's own
        // predicate, which is still the single copy `machine_state` uses.
        if !m.has_room_for(amount, stats.capacity) {
            events.push(Event::MachineStalled {
                building,
                held: now,
                capacity: stats.capacity,
            });
        }
        if depleted {
            events.push(Event::DepositDepleted { deposit });
        }
    }
}

/// Say so, once, when a smelter has just stopped.
///
/// **THE EDGE IS INTO A STALL FROM ANYTHING THAT IS NOT ONE**, which is wider
/// than the ruling's letter and narrower than its fear. The Game Director
/// ruled "working -> stalled"; her own reproduction is **idle -> stalled** —
/// insert ore and fuel that will not light into an empty smelter and it goes
/// from `idle: nothing to refine` straight to `stalled: fuel won't light from
/// cold` without ever working. A guard that only watched working -> stalled
/// would have stayed green through the exact 120 silent ticks she measured.
///
/// Her rule 2 is what is actually load-bearing and it holds: becoming **idle**
/// is never announced, so a finished batch is silent, and a smelter that sits
/// stalled says nothing after the first tick.
fn announce_new_stalls(world: &World, before: &[(BuildingId, bool)], events: &mut Vec<Event>) {
    for b in &world.buildings {
        let Some(why) = world.smelter_state(b).stall() else {
            continue;
        };
        // A building with no entry is one placed this tick: it is placed empty,
        // so it is idle, and an unknown past counts as not stalled.
        let was = before
            .iter()
            .find(|(id, _)| *id == b.id)
            .is_some_and(|(_, stalled)| *stalled);
        if !was {
            events.push(Event::SmelterStalled {
                building: b.id,
                why,
            });
        }
    }
}

/// Assay system: a player standing on the deposit they are assaying makes
/// progress; after `ASSAY_TICKS` the species' sheet is known exactly.
fn assay(world: &mut World, events: &mut Vec<Event>) {
    for i in 0..world.players.len() {
        let Some(a) = world.players[i].assaying else {
            continue;
        };
        let player = world.players[i].id;
        let pos = world.players[i].pos;
        let deposit = world
            .deposit(a.deposit)
            .expect("assaying refers to an existing deposit");
        if !deposit.contains(pos) {
            world.players[i].assaying = None;
            events.push(Event::AssayStopped {
                player,
                deposit: a.deposit,
                reason: StopReason::LeftDeposit,
            });
            continue;
        }
        let progress = a.progress + 1;
        if progress < ASSAY_TICKS {
            world.players[i].assaying = Some(Assaying { progress, ..a });
            continue;
        }
        let species = deposit.species;
        world.players[i].assaying = None;
        world.species_mut(species).assayed = true;
        events.push(Event::SpeciesAssayed { player, species });
        discover(world, species, player, events);
    }
}

/// Hand-crafting system: each crafting player advances their current batch;
/// when it completes, the output lands in their inventory and the next
/// batch starts if they still have the inputs.
fn craft_by_hand(world: &mut World, events: &mut Vec<Event>) {
    for p in &mut world.players {
        let Some(c) = p.crafting else { continue };
        let recipe: &Recipe = c.recipe.recipe();
        let progress = c.progress + 1;
        if progress < recipe.ticks {
            p.crafting = Some(Crafting { progress, ..c });
            continue;
        }

        let item = recipe
            .output_for(c.input)
            .expect("validated when the craft started");
        let count = recipe.output.1;
        p.inventory.add(item, count);
        let remaining = c.remaining - 1;
        events.push(Event::ItemCrafted {
            player: p.id,
            recipe: c.recipe,
            item,
            count,
            remaining,
        });
        if remaining == 0 {
            p.crafting = None;
        } else if consume(&mut p.inventory, recipe, c.input) {
            p.crafting = Some(Crafting {
                progress: 0,
                remaining,
                ..c
            });
        } else {
            p.crafting = None;
            events.push(Event::CraftingStopped {
                player: p.id,
                recipe: c.recipe,
                reason: StopReason::OutOfInputs,
            });
        }
    }
}

/// Smelting system. A smelter with ore, a fire hot enough for it, and room
/// in its output slot makes progress; each finished unit goes to the output
/// slot. The four stalls (no fuel, fuel too cool, fuel that won't light,
/// output full) are decided by `World::smelter_state` and announced ONCE by
/// `announce_new_stalls` on the tick a smelter enters one (ASSA-80). They used
/// to be silent here, with "inspect the building to see why" as the only
/// recourse -- true at a prompt, and at the window it meant hovering an 18x18
/// building on a 9-px map.
///
/// Fire rules: the running temperature is the lower of the walls' heat
/// tolerance and the burning fuel's effective reactivity, and must reach the
/// ore's heat tolerance. A unit of fuel burns for reactivity ×
/// `BURN_TICKS_PER_REACTIVITY` ticks, only while smelting. Fuel lights from
/// cold only if its heat tolerance is within the hand spark; otherwise the
/// fire already burning must be at least that hot.
fn run_smelters(world: &mut World, events: &mut Vec<Event>) {
    for i in 0..world.buildings.len() {
        let walls = world.max_temperature(&world.buildings[i]);
        let BuildingKind::Smelter(s) = &world.buildings[i].kind else {
            continue;
        };
        let Some(input) = s.input else { continue };
        let Some(recipe) = smelter_recipe_for(input.item.kind).map(|r| r.recipe()) else {
            continue;
        };
        if input.count < recipe.input.1 {
            continue;
        }
        let needs = u32::from(world.species(input.item.species).sheet.heat_tolerance);
        let Some(out_item) = recipe.output_for(input.item) else {
            continue; // grade A: nothing to improve (insert refuses it)
        };
        let out_count = recipe.output.1;
        let out_have = match s.output {
            None => 0,
            Some(o) if o.item == out_item => o.count,
            Some(_) => continue, // holds something else; wait to be emptied
        };
        if out_have + out_count > SMELTER_OUTPUT_CAP {
            continue;
        }
        let fuel_temp = s.fuel.and_then(|f| world.fuel_temperature(f.item));
        // **ASKED OF THE WORLD, NOT RE-DERIVED HERE** (ASSA-128). This used
        // to be its own copy of the comparison, and `World::smelter_state`'s
        // copy forgot that a unit lights off the dying fire of the one
        // before it — so a smelter that refined 19 ore told the player
        // "fuel won't light from cold" once per unit burned.
        let fuel_lights = s.fuel.is_some_and(|f| world.fuel_lights(s, f.item));

        let BuildingKind::Smelter(s) = &mut world.buildings[i].kind else {
            continue;
        };
        if s.burn_left == 0 {
            let (Some(temp), Some(fuel)) = (fuel_temp, s.fuel) else {
                s.burn_temperature = 0;
                continue;
            };
            if !fuel_lights {
                s.burn_temperature = 0;
                continue;
            }
            s.fuel = (fuel.count > 1).then(|| ItemStack::new(fuel.item, fuel.count - 1));
            s.burn_left = temp * BURN_TICKS_PER_REACTIVITY;
            s.burn_temperature = temp;
        }
        if s.burn_temperature.min(walls) < needs {
            continue; // the fire is lit but too cool for this ore
        }
        s.burn_left -= 1;
        s.progress += 1;
        if s.progress < recipe.ticks {
            continue;
        }

        s.progress = 0;
        s.input = (input.count > recipe.input.1)
            .then(|| ItemStack::new(input.item, input.count - recipe.input.1));
        s.output = Some(ItemStack::new(out_item, out_have + out_count));
        events.push(Event::ItemSmelted {
            building: world.buildings[i].id,
            item: out_item,
            count: out_count,
        });
    }
}
