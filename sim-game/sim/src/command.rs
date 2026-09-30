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

use crate::building::BuildingId;
use crate::item::Item;
use crate::ore::OreKind;
use crate::recipe::RecipeId;
use crate::types::{DepositId, PlayerId, TilePos};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PlayerCommand {
    /// Start mining the deposit you are standing on, by hand. Ore arrives
    /// one unit at a time (see `tuning::HAND_MINE_TICKS`) for as long as you
    /// stay on the deposit.
    Mine,
    /// Hand-craft `count` batches of a recipe from your inventory. Inputs
    /// are taken as each batch starts; you keep walking or mining meanwhile.
    Craft { recipe: RecipeId, count: u32 },
    /// Put a building item from your inventory on the map, with its
    /// top-left tile at `pos`. You must be within `tuning::REACH` of it.
    Place { item: Item, pos: TilePos },
    /// Move items from your inventory into a building's slots.
    Insert {
        building: BuildingId,
        item: Item,
        count: u32,
    },
    /// Take everything from a building's output slot.
    Take { building: BuildingId },
    /// Remove a building, getting it and its contents back.
    Pickup { building: BuildingId },
    /// Start walking toward `target`, one tile per tick.
    MoveTo { target: TilePos },
    /// Stop walking, mining and crafting (the current batch is refunded).
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
    MiningStarted {
        player: PlayerId,
        deposit: DepositId,
        kind: OreKind,
    },
    /// One unit of ore went into the player's inventory.
    OreMined {
        player: PlayerId,
        deposit: DepositId,
        item: Item,
        amount: u32,
    },
    MiningStopped {
        player: PlayerId,
        deposit: DepositId,
        reason: StopReason,
    },
    DepositDepleted {
        deposit: DepositId,
    },
    CraftStarted {
        player: PlayerId,
        recipe: RecipeId,
        count: u32,
    },
    /// One batch finished and its output is in the player's inventory.
    ItemCrafted {
        player: PlayerId,
        recipe: RecipeId,
        item: Item,
        count: u32,
        /// Batches still queued after this one.
        remaining: u32,
    },
    /// Crafting ended before every batch was made.
    CraftingStopped {
        player: PlayerId,
        recipe: RecipeId,
        reason: StopReason,
    },
    BuildingPlaced {
        player: PlayerId,
        building: BuildingId,
        item: Item,
        pos: TilePos,
    },
    ItemsInserted {
        player: PlayerId,
        building: BuildingId,
        item: Item,
        count: u32,
    },
    ItemsTaken {
        player: PlayerId,
        building: BuildingId,
        item: Item,
        count: u32,
    },
    BuildingRemoved {
        player: PlayerId,
        building: BuildingId,
        item: Item,
        pos: TilePos,
    },
    /// A smelter finished a plate; it is waiting in the output slot.
    ItemSmelted {
        building: BuildingId,
        item: Item,
        count: u32,
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

/// Why an activity that was running on its own came to an end.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StopReason {
    /// The player asked for it.
    Stopped,
    /// The player walked off the deposit.
    LeftDeposit,
    /// There is nothing left to mine.
    Depleted,
    /// The next batch needs an item the player no longer has.
    OutOfInputs,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RejectReason {
    /// `Mine` needs you to stand on a deposit.
    NotOnDeposit,
    DepositDepleted,
    UnknownPlayer,
    OutOfBounds,
    /// Counts must be at least 1.
    ZeroCount,
    /// This recipe needs a machine.
    NotHandCraftable,
    /// The player lacks enough of this item.
    MissingItems(Item),
    UnknownBuilding,
    /// Farther than `tuning::REACH` tiles away.
    OutOfReach,
    /// Another building is in the way.
    TileOccupied,
    /// This item is not a building.
    NotPlaceable,
    /// The building has no slot that takes this item.
    WrongItem,
    /// The slot is full, or holds something else.
    SlotFull,
    NothingToTake,
}
