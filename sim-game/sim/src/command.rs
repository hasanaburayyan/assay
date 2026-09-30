//! Inputs go in, events come out.
//!
//! Inputs are the only way to change the world. Every tick receives a list of
//! inputs in a fixed order; in multiplayer the relay decides that order and
//! every peer applies the same list, so every peer computes the same world.
//!
//! There are two kinds:
//! - [`PlayerCommand`]: what a player can ask for. The relay stamps which
//!   player sent it, so a client can never act as someone else.
//! - [`SystemCommand`]: things only the host may do (joins now, galaxy
//!   shipments later). Clients have no way to send these.
//!
//! Events report what happened; renderers, audio, logs and the relay listen
//! to them, and the sim never knows who is listening.

use serde::{Deserialize, Serialize};

use crate::ore::OreKind;
use crate::types::{DepositId, PlayerId, TilePos};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PlayerCommand {
    /// Take up to `amount` ore from a deposit. Stand-in until mining drills
    /// exist as entities.
    Extract { deposit: DepositId, amount: u32 },
    /// Start walking toward `target`, one tile per tick.
    MoveTo { target: TilePos },
    /// Stop walking.
    Stop,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SystemCommand {
    /// Add a player at spawn. They get the next free `PlayerId`.
    AddPlayer { name: String },
}

/// One entry in a tick's input list.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Input {
    Player {
        player: PlayerId,
        command: PlayerCommand,
    },
    System(SystemCommand),
}

impl Input {
    pub fn player(player: PlayerId, command: PlayerCommand) -> Self {
        Input::Player { player, command }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Event {
    PlayerJoined {
        player: PlayerId,
        name: String,
    },
    OreExtracted {
        player: PlayerId,
        deposit: DepositId,
        kind: OreKind,
        amount: u32,
    },
    DepositDepleted {
        deposit: DepositId,
    },
    MoveStarted {
        player: PlayerId,
        from: TilePos,
        to: TilePos,
    },
    PlayerArrived {
        player: PlayerId,
        pos: TilePos,
    },
    PlayerStopped {
        player: PlayerId,
        pos: TilePos,
    },
    CommandRejected {
        player: PlayerId,
        command: PlayerCommand,
        reason: RejectReason,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RejectReason {
    UnknownDeposit,
    DepositDepleted,
    UnknownPlayer,
    OutOfBounds,
}
