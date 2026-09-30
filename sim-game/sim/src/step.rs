//! Advancing the world one tick.

use crate::building::{Building, BuildingId, BuildingKind, footprint_tiles};
use crate::command::{Event, Input, PlayerCommand, RejectReason, StopReason, SystemCommand};
use crate::inventory::Inventory;
use crate::item::{Item, ItemStack};
use crate::player::{Crafting, Mining, Player};
use crate::recipe::{Recipe, smelting_recipe_for};
use crate::tuning::{
    COAL_BURN_TICKS, HAND_MINE_TICKS, REACH, SMELTER_FUEL_CAP, SMELTER_INPUT_CAP,
    SMELTER_OUTPUT_CAP,
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

    match *command {
        PlayerCommand::Mine => {
            let pos = world.player(player).expect("checked above").pos;
            let Some(d) = world.deposit_at(pos) else {
                return reject(RejectReason::NotOnDeposit, events);
            };
            if d.is_depleted() {
                return reject(RejectReason::DepositDepleted, events);
            }
            let (deposit, kind) = (d.id, d.kind);
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
                kind,
            });
        }
        PlayerCommand::Craft { recipe, count } => {
            if count == 0 {
                return reject(RejectReason::ZeroCount, events);
            }
            if !recipe.is_hand_craftable() {
                return reject(RejectReason::NotHandCraftable, events);
            }
            let p = world.player_mut(player).expect("checked above");
            if let Some(c) = p.crafting {
                // Finish what's in progress first; refund it like Stop does.
                refund(&mut p.inventory, c.recipe.recipe());
                events.push(Event::CraftingStopped {
                    player,
                    recipe: c.recipe,
                    reason: StopReason::Stopped,
                });
            }
            p.crafting = None;
            if let Err(missing) = consume(&mut p.inventory, recipe.recipe()) {
                return reject(RejectReason::MissingItems(missing), events);
            }
            p.crafting = Some(Crafting {
                recipe,
                progress: 0,
                remaining: count,
            });
            events.push(Event::CraftStarted {
                player,
                recipe,
                count,
            });
        }
        PlayerCommand::Place { item, pos } => {
            let Some(kind) = BuildingKind::from_item(item) else {
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
            world.buildings.push(Building { id, pos, kind });
            events.push(Event::BuildingPlaced {
                player,
                building: id,
                item,
                pos,
            });
        }
        PlayerCommand::Insert {
            building,
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
            if !world
                .player(player)
                .expect("checked above")
                .inventory
                .has(item, count)
            {
                return reject(RejectReason::MissingItems(item), events);
            }
            let b = world.building_mut(building).expect("checked above");
            let BuildingKind::Smelter(s) = &mut b.kind;
            if item == Item::Coal {
                if s.fuel + count > SMELTER_FUEL_CAP {
                    return reject(RejectReason::SlotFull, events);
                }
                s.fuel += count;
            } else if smelting_recipe_for(item).is_some() {
                let have = match s.input {
                    None => 0,
                    Some(stack) if stack.item == item => stack.count,
                    Some(_) => return reject(RejectReason::SlotFull, events),
                };
                if have + count > SMELTER_INPUT_CAP {
                    return reject(RejectReason::SlotFull, events);
                }
                s.input = Some(ItemStack::new(item, have + count));
            } else {
                return reject(RejectReason::WrongItem, events);
            }
            let taken = world
                .player_mut(player)
                .expect("checked above")
                .inventory
                .remove(item, count);
            debug_assert!(taken);
            events.push(Event::ItemsInserted {
                player,
                building,
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
            let BuildingKind::Smelter(s) = &mut b.kind;
            let Some(stack) = s.output.take() else {
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
            let item = b.kind.item();
            let inv = &mut world.player_mut(player).expect("checked above").inventory;
            inv.add(item, 1);
            let BuildingKind::Smelter(s) = b.kind;
            for stack in [s.input, s.output].into_iter().flatten() {
                inv.add_stack(stack);
            }
            inv.add(Item::Coal, s.fuel);
            events.push(Event::BuildingRemoved {
                player,
                building,
                item,
                pos: b.pos,
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
                refund(&mut p.inventory, c.recipe.recipe());
                events.push(Event::CraftingStopped {
                    player,
                    recipe: c.recipe,
                    reason: StopReason::Stopped,
                });
            }
        }
    }
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
/// makes progress, and takes one unit of ore each `HAND_MINE_TICKS`.
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
        let item = d.kind.into();
        let depleted = d.is_depleted();
        world.players[i].inventory.add(item, 1);
        events.push(Event::OreMined {
            player,
            deposit: m.deposit,
            item,
            amount: 1,
        });
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

/// Take one batch of inputs, or take nothing and say what's missing.
fn consume(inv: &mut Inventory, recipe: &Recipe) -> Result<(), crate::item::Item> {
    if let Some(&(item, _)) = recipe.inputs.iter().find(|(i, n)| !inv.has(*i, *n)) {
        return Err(item);
    }
    for &(item, n) in recipe.inputs {
        let ok = inv.remove(item, n);
        debug_assert!(ok, "checked above");
    }
    Ok(())
}

/// Give back one batch of inputs (a cancelled craft).
fn refund(inv: &mut Inventory, recipe: &Recipe) {
    for &(item, n) in recipe.inputs {
        inv.add(item, n);
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

        let (item, count) = recipe.output;
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
        } else if consume(&mut p.inventory, recipe).is_ok() {
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

/// Smelting system: every smelter with ore, fuel and room in its output
/// slot burns coal and makes progress; each finished plate goes to the
/// output slot. A full output slot or an empty fire stalls it silently;
/// inspect the building to see why.
fn run_smelters(world: &mut World, events: &mut Vec<Event>) {
    for b in &mut world.buildings {
        let BuildingKind::Smelter(s) = &mut b.kind;
        let Some(input) = s.input else { continue };
        let Some(recipe) = smelting_recipe_for(input.item).map(|r| r.recipe()) else {
            continue;
        };
        let need = recipe.inputs[0].1;
        if input.count < need {
            continue;
        }
        let (out_item, out_count) = recipe.output;
        let out_have = match s.output {
            None => 0,
            Some(o) if o.item == out_item => o.count,
            Some(_) => continue, // holds a different plate; wait to be emptied
        };
        if out_have + out_count > SMELTER_OUTPUT_CAP {
            continue;
        }
        if s.burn_left == 0 {
            if s.fuel == 0 {
                continue;
            }
            s.fuel -= 1;
            s.burn_left = COAL_BURN_TICKS;
        }
        s.burn_left -= 1;
        s.progress += 1;
        if s.progress < recipe.ticks {
            continue;
        }

        s.progress = 0;
        s.input = (input.count > need).then(|| ItemStack::new(input.item, input.count - need));
        s.output = Some(ItemStack::new(out_item, out_have + out_count));
        events.push(Event::ItemSmelted {
            building: b.id,
            item: out_item,
            count: out_count,
        });
    }
}
