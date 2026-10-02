//! Advancing the world one tick.

use crate::assembly::{Assembly, Built, Mount, Part, spec};
use crate::building::{Building, BuildingId, BuildingKind, Machine, Slot, footprint_tiles};
use crate::command::{Event, Input, PlayerCommand, RejectReason, StopReason, SystemCommand};
use crate::inventory::Inventory;
use crate::item::{Item, ItemKind, ItemStack};
use crate::mineral::{Property, SpeciesId, validate_name};
use crate::player::{Assaying, Crafting, Mining, Player};
use crate::recipe::{Recipe, smelter_recipe_for};
use crate::tuning::{
    ASSAY_TICKS, BURN_TICKS_PER_REACTIVITY, FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS,
    HAND_MINE_TICKS, HAND_SPARK_TEMPERATURE, REACH, SMELTER_FUEL_CAP, SMELTER_INPUT_CAP,
    SMELTER_OUTPUT_CAP, YIELD_BY_GRADE,
};
use crate::types::{PlayerId, TilePos};
use crate::world::World;

/// Advance the world by exactly one tick.
///
/// `inputs` are everything scheduled for this tick, in the order every peer
/// agreed on. Anything that happened is appended to `events`.
pub fn step(world: &mut World, inputs: &[Input], events: &mut Vec<Event>) {
    for input in inputs {
        match input {
            Input::System(command) => apply_system(world, command, events),
            Input::Player { player, command } => apply_player(world, *player, command, events),
        }
    }

    // Systems run here in a fixed order. Later: drills, belts, inserters,
    // machines, drones.
    move_players(world, events);
    mine_by_hand(world, events);
    assay(world, events);
    craft_by_hand(world, events);
    run_smelters(world, events);

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

/// Whether `item` burns well enough to be fuel, and how hot.
fn fuel_temperature(world: &World, item: Item) -> Option<u32> {
    let t = world
        .species(item.species)
        .effective(Property::Reactivity, item.grade);
    (t >= FUEL_MIN_REACTIVITY).then_some(t)
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
    let unknown = |s: &SpeciesId| usize::from(s.0) >= world.species.len();
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
            if u32::from(world.species(species).sheet.hardness) > HAND_MINE_MAX_HARDNESS {
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
                    if fuel_temperature(world, item).is_none() {
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
            if have + count > cap {
                return reject(RejectReason::SlotFull, events);
            }
            *target = Some(ItemStack::new(item, have + count));
            let taken = world
                .player_mut(player)
                .expect("checked above")
                .inventory
                .remove(item, count);
            debug_assert!(taken);
            events.push(Event::ItemsInserted {
                player,
                building,
                slot,
                item,
                count,
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
            let Some(frame_part) = Part::from_item(frame) else {
                return reject(RejectReason::NotAPart(frame), events);
            };
            let mut parts = Vec::with_capacity(mounted.len());
            for item in &mounted {
                let Some(part) = Part::from_item(*item) else {
                    return reject(RejectReason::NotAPart(*item), events);
                };
                parts.push(part);
            }
            let assembly = Assembly::new(frame_part, parts);
            // Slots only. **Mass is never consulted here** (decision 11): the
            // sim does not protect a player from their own design, and a
            // refusal now would make the frame budget invisible.
            if let Err(e) = assembly.validate() {
                return reject(RejectReason::BadAssembly(e), events);
            }

            // Tally first so duplicates (two hoppers of one material) are
            // taken all-or-nothing instead of one at a time.
            let mut needed: Vec<ItemStack> = Vec::new();
            for item in assembly.part_items() {
                match needed.iter_mut().find(|s| s.item == item) {
                    Some(s) => s.count += 1,
                    None => needed.push(ItemStack::new(item, 1)),
                }
            }
            let p = world.player_mut(player).expect("checked above");
            if let Some(s) = needed.iter().find(|s| !p.inventory.has(s.item, s.count)) {
                return reject(RejectReason::MissingItems(s.item), events);
            }
            for s in &needed {
                let taken = p.inventory.remove(s.item, s.count);
                debug_assert!(taken);
            }

            let built = Built::new(assembly, &world.species);
            let p = world.player_mut(player).expect("checked above");
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

/// Hand-mining system: every player standing on the deposit they are mining
/// makes progress; each `HAND_MINE_TICKS` the deposit loses one unit and the
/// player gains the grade's yield.
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

        let progress = m.progress + 1;
        if progress < HAND_MINE_TICKS {
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
        if depleted {
            world.players[i].mining = None;
            events.push(Event::DepositDepleted { deposit: m.deposit });
            events.push(Event::MiningStopped {
                player,
                deposit: m.deposit,
                reason: StopReason::Depleted,
            });
        } else {
            world.players[i].mining = Some(Mining { progress: 0, ..m });
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
/// slot. Stalls (no fuel, fuel too cool, fuel that won't light, output full)
/// are silent here; inspect the building to see why.
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
        let fuel_temp = s.fuel.and_then(|f| fuel_temperature(world, f.item));
        let fuel_lights = s.fuel.is_some_and(|f| {
            let ignition = u32::from(world.species(f.item.species).sheet.heat_tolerance);
            ignition <= HAND_SPARK_TEMPERATURE || ignition <= s.burn_temperature
        });

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
