//! Advancing the world one tick.

use crate::command::{Event, Input, PlayerCommand, RejectReason, StopReason, SystemCommand};
use crate::inventory::Inventory;
use crate::player::{Crafting, Mining, Player};
use crate::recipe::Recipe;
use crate::tuning::HAND_MINE_TICKS;
use crate::types::PlayerId;
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
