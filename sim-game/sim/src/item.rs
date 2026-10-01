//! Everything a player or machine can hold. Every item is of one species at
//! one grade: raw ore, refined material, parts made from it, and buildings
//! waiting to be placed. Items stack only when all three match.

use serde::{Deserialize, Serialize};

use crate::mineral::{Grade, SpeciesId};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum ItemKind {
    /// Straight out of the ground.
    Ore,
    /// Smelted ore. What parts are made from.
    Refined,
    Gear,
    /// A smelter built from raw ore; its walls are that species.
    Smelter,
}

impl ItemKind {
    pub const ALL: [ItemKind; 4] = [
        ItemKind::Ore,
        ItemKind::Refined,
        ItemKind::Gear,
        ItemKind::Smelter,
    ];

    pub const fn name(self) -> &'static str {
        match self {
            ItemKind::Ore => "ore",
            ItemKind::Refined => "refined",
            ItemKind::Gear => "gear",
            ItemKind::Smelter => "smelter",
        }
    }

    pub fn parse(s: &str) -> Option<ItemKind> {
        match s.to_ascii_lowercase().as_str() {
            "ore" => Some(ItemKind::Ore),
            "refined" | "ref" | "ingot" | "plate" => Some(ItemKind::Refined),
            "gear" | "gears" => Some(ItemKind::Gear),
            "smelter" => Some(ItemKind::Smelter),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct Item {
    pub kind: ItemKind,
    pub species: SpeciesId,
    pub grade: Grade,
}

impl Item {
    pub const fn new(kind: ItemKind, species: SpeciesId, grade: Grade) -> Self {
        Self {
            kind,
            species,
            grade,
        }
    }

    /// Short machine-readable form, e.g. `ore#2(B)`. Hosts with a world
    /// show species names instead (`World::item_name`).
    pub fn code(&self) -> String {
        format!(
            "{}#{}({})",
            self.kind.name(),
            self.species.0,
            self.grade.letter()
        )
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
