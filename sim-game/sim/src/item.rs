//! Everything a player or machine can hold: raw ore, smelted plates, parts,
//! and machines waiting to be placed.
//!
//! Items are fungible for now. Ore purity and part quality will attach to
//! stacks later (a tier on `ItemStack`), which is why inventories are lists
//! of stacks rather than a fixed set of counters.

use serde::{Deserialize, Serialize};

use crate::ore::OreKind;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Item {
    IronOre,
    CopperOre,
    Coal,
    Stone,
    IronPlate,
    CopperPlate,
    IronGear,
    Smelter,
}

impl Item {
    pub const ALL: [Item; 8] = [
        Item::IronOre,
        Item::CopperOre,
        Item::Coal,
        Item::Stone,
        Item::IronPlate,
        Item::CopperPlate,
        Item::IronGear,
        Item::Smelter,
    ];

    /// The name players type and see, e.g. `iron-ore`.
    pub const fn name(self) -> &'static str {
        match self {
            Item::IronOre => "iron-ore",
            Item::CopperOre => "copper-ore",
            Item::Coal => "coal",
            Item::Stone => "stone",
            Item::IronPlate => "iron-plate",
            Item::CopperPlate => "copper-plate",
            Item::IronGear => "iron-gear",
            Item::Smelter => "smelter",
        }
    }

    /// Parse a typed name. Accepts the canonical name plus a few short
    /// forms (`iron`, `gear`, `plate`), case-insensitively.
    pub fn parse(s: &str) -> Option<Item> {
        let s = s.to_ascii_lowercase();
        Some(match s.as_str() {
            "iron-ore" | "iron_ore" | "ironore" | "iron" => Item::IronOre,
            "copper-ore" | "copper_ore" | "copperore" | "copper" => Item::CopperOre,
            "coal" => Item::Coal,
            "stone" => Item::Stone,
            "iron-plate" | "iron_plate" | "ironplate" | "plate" => Item::IronPlate,
            "copper-plate" | "copper_plate" | "copperplate" => Item::CopperPlate,
            "iron-gear" | "iron_gear" | "irongear" | "gear" => Item::IronGear,
            "smelter" => Item::Smelter,
            _ => return None,
        })
    }

    /// The raw item a deposit of this ore kind yields.
    pub const fn from_ore(kind: OreKind) -> Item {
        match kind {
            OreKind::Iron => Item::IronOre,
            OreKind::Copper => Item::CopperOre,
            OreKind::Coal => Item::Coal,
            OreKind::Stone => Item::Stone,
        }
    }
}

impl From<OreKind> for Item {
    fn from(kind: OreKind) -> Self {
        Item::from_ore(kind)
    }
}

/// Some of one item.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ItemStack {
    pub item: Item,
    pub count: u32,
}

impl ItemStack {
    pub const fn new(item: Item, count: u32) -> Self {
        Self { item, count }
    }
}
