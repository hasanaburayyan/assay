//! Advancing the world one tick.

use crate::command::{Event, Input, PlayerCommand, RejectReason, SystemCommand};
use crate::player::Player;
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
        PlayerCommand::Extract { deposit, amount } => {
            let Some(d) = world.deposit_mut(deposit) else {
                return reject(RejectReason::UnknownDeposit, events);
            };
            if d.is_depleted() {
                return reject(RejectReason::DepositDepleted, events);
            }

            let taken = amount.min(d.amount);
            d.amount -= taken;
            let (kind, depleted) = (d.kind, d.is_depleted());
            world
                .player_mut(player)
                .expect("checked above")
                .inventory
                .add(kind.into(), taken);
            events.push(Event::OreExtracted {
                player,
                deposit,
                kind,
                amount: taken,
            });
            if depleted {
                events.push(Event::DepositDepleted { deposit });
            }
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
