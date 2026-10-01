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

use crate::assembly::{AssemblyError, MachineStats, PartKind};
use crate::building::{BuildingId, Slot};
use crate::item::Item;
use crate::mineral::{NameError, Property, SpeciesId};
use crate::recipe::RecipeId;
use crate::types::{DepositId, PlayerId, TilePos};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PlayerCommand {
    /// Start mining the deposit you are standing on, by hand. Ore arrives
    /// one cycle at a time (see `tuning`) for as long as you stay on it.
    Mine,
    /// Hand-craft `count` batches of a recipe from the `item` stacks in your
    /// inventory. Inputs are taken as each batch starts; you keep walking
    /// or mining meanwhile.
    Craft {
        recipe: RecipeId,
        item: Item,
        count: u32,
    },
    /// Put a building item from your inventory on the map, with its
    /// top-left tile at `pos`. You must be within `tuning::REACH` of it.
    Place { item: Item, pos: TilePos },
    /// Move items from your inventory into one of a building's slots.
    Insert {
        building: BuildingId,
        slot: Slot,
        item: Item,
        count: u32,
    },
    /// Take everything from a building's output slot.
    Take { building: BuildingId },
    /// Remove a building, getting it and its contents back.
    Pickup { building: BuildingId },
    /// Study the deposit you are standing on for `tuning::ASSAY_TICKS`;
    /// afterwards its species shows exact numbers instead of rough bands.
    Assay,
    /// Give a species a name. Only its discoverer, or someone they granted,
    /// may. Replaces the generated name everywhere.
    Rename { species: SpeciesId, name: String },
    /// Let another player rename a species you discovered.
    GrantRename { species: SpeciesId, to: PlayerId },
    /// Make `count` parts of one kind from refined material in your
    /// inventory. The cost is the part's `size` in refined material of
    /// `material`'s species and grade, read from the catalogue — so a new part
    /// kind needs no recipe (ADR 0003 consequences).
    MakePart {
        kind: PartKind,
        material: Item,
        count: u32,
    },
    /// Build a machine from part items you are carrying: a frame, plus the
    /// parts mounted on it. Rejected only if the parts do not fit the frame's
    /// slots — **never for being overweight** (decision 11).
    ///
    /// One path for a pick and a drill alike; the frame's mount is the only
    /// thing that differs, and it decides which of `Equip` and `PlaceAssembly`
    /// the result can go to.
    Assemble { frame: Item, mounted: Vec<Item> },
    /// Take a held assembly into your hands. Anything already in hand goes
    /// back to the built list. Indexes `Player::assemblies`.
    Equip { assembly: u32 },
    /// Put the tool in hand back on the built list.
    Unequip,
    /// Plant an assembly on the map at `pos`. Indexes `Player::assemblies`.
    /// **This is where mass is tested** (decision 11): an overweight design
    /// breaks here instead of being placed.
    PlaceAssembly { assembly: u32, pos: TilePos },
    /// Start walking toward `target`, one tile per tick.
    MoveTo { target: TilePos },
    /// Stop walking, mining, crafting and assaying (the current craft batch
    /// is refunded).
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
        species: SpeciesId,
    },
    /// One mining cycle finished; `amount` units went into the inventory.
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
    /// First contact: this player was the first to mine or assay the
    /// species, and may now name it.
    SpeciesDiscovered {
        player: PlayerId,
        species: SpeciesId,
    },
    AssayStarted {
        player: PlayerId,
        deposit: DepositId,
        species: SpeciesId,
    },
    AssayStopped {
        player: PlayerId,
        deposit: DepositId,
        reason: StopReason,
    },
    /// The species' exact sheet is now known to everyone in the world.
    SpeciesAssayed {
        player: PlayerId,
        species: SpeciesId,
    },
    SpeciesRenamed {
        player: PlayerId,
        species: SpeciesId,
        name: String,
    },
    RenameGranted {
        species: SpeciesId,
        from: PlayerId,
        to: PlayerId,
    },
    CraftStarted {
        player: PlayerId,
        recipe: RecipeId,
        item: Item,
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
        slot: Slot,
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
    /// A smelter finished a unit; it is waiting in the output slot.
    ItemSmelted {
        building: BuildingId,
        item: Item,
        count: u32,
    },
    /// Parts went into the inventory, one item at a time.
    PartsMade {
        player: PlayerId,
        part: Item,
        count: u32,
    },
    /// A machine was built and added to the player's built list at `assembly`.
    /// Its stats ride along because they are the point of building it.
    Assembled {
        player: PlayerId,
        assembly: u32,
        stats: MachineStats,
    },
    Equipped {
        player: PlayerId,
        /// The stats of what is now in hand.
        stats: MachineStats,
    },
    Unequipped {
        player: PlayerId,
    },
    MachinePlaced {
        player: PlayerId,
        building: BuildingId,
        pos: TilePos,
    },
    /// A design broke under its own mass (decision 11). **Names the parts
    /// lost**, because a loss the player cannot attribute teaches nothing.
    MachineBroke {
        player: PlayerId,
        /// Where it was being planted, or `None` for a tool in hand.
        pos: Option<TilePos>,
        mass: u32,
        budget: u32,
        lost: Vec<Item>,
        returned: Vec<Item>,
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
    /// `Mine` and `Assay` need you to stand on a deposit.
    NotOnDeposit,
    /// This species' sheet is already exact.
    AlreadyAssayed,
    /// Nobody has discovered this species yet, so nobody may name it.
    NotDiscovered,
    /// Only the discoverer (or a grantee, for renaming) may do this.
    NotDiscoverer,
    BadName(NameError),
    /// The player to grant to does not exist.
    NoSuchPlayer,
    /// That player already has rename rights.
    AlreadyGranted,
    DepositDepleted,
    /// The species is harder than `tuning::HAND_MINE_MAX_HARDNESS`.
    TooHardForHands,
    UnknownPlayer,
    OutOfBounds,
    /// Counts must be at least 1.
    ZeroCount,
    /// This recipe needs a machine.
    NotHandCraftable,
    /// The item names a species this world does not have.
    UnknownSpecies,
    /// The player lacks enough of this item.
    MissingItems(Item),
    /// The item is the wrong kind for this recipe or slot.
    WrongItem,
    /// The input's effective property is below the recipe's threshold.
    RequirementNotMet(Property, u32),
    /// A refining recipe was given grade A, which cannot improve.
    AlreadyBestGrade,
    UnknownBuilding,
    /// Farther than `tuning::REACH` tiles away.
    OutOfReach,
    /// Another building is in the way.
    TileOccupied,
    /// This item is not a building.
    NotPlaceable,
    /// The ore's heat tolerance is above what the smelter's walls survive.
    TooHotForWalls,
    /// Effective reactivity is below `tuning::FUEL_MIN_REACTIVITY`.
    NotFuel,
    /// The slot is full, or holds something else.
    SlotFull,
    NothingToTake,
    /// The parts do not fit the frame's slots. **Never because of mass**:
    /// `AssemblyError` has no overweight variant (decision 11).
    BadAssembly(AssemblyError),
    /// An item given to `Assemble` is not a part at all.
    NotAPart(Item),
    /// No built assembly at that index.
    NoSuchAssembly,
    /// A held frame was planted, or a planted frame equipped. The mount is
    /// the only thing that separates a tool from a machine (decision 6).
    WrongMount,
    /// Nothing in hand to put down.
    NothingEquipped,
    /// This building has no slot to insert into. `Slot` names the smelter's
    /// two; a machine takes nothing in and gives ore out through `Take`.
    NotInsertable,
}
