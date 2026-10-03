//! Everything a player or machine can hold. Every item is of one species at
//! one grade: raw ore, refined material, parts made from it, and buildings
//! waiting to be placed. Items stack only when all three match.

use serde::{Deserialize, Serialize};

use crate::assembly::PartKind;
use crate::mineral::{Grade, SpeciesId};

/// How many item kinds are not parts.
const PLAIN_KINDS: usize = 4;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum ItemKind {
    /// Straight out of the ground.
    Ore,
    /// Smelted ore. What parts are made from.
    Refined,
    Gear,
    /// A smelter built from raw ore; its walls are that species.
    Smelter,
    /// One machine part, of the kind named here and made of this item's own
    /// species and grade (ADR 0003 point 1). A part kind is a row in
    /// `PART_SPECS`, so this is one variant however many parts exist.
    Part(PartKind),
}

impl ItemKind {
    /// Every item kind, with the part kinds taken from [`PartKind::ALL`] so
    /// that a part added to the catalogue joins this list for free.
    pub const ALL: [ItemKind; PLAIN_KINDS + PartKind::ALL.len()] = {
        let mut all = [ItemKind::Ore; PLAIN_KINDS + PartKind::ALL.len()];
        all[1] = ItemKind::Refined;
        all[2] = ItemKind::Gear;
        all[3] = ItemKind::Smelter;
        let mut i = 0;
        while i < PartKind::ALL.len() {
            all[PLAIN_KINDS + i] = ItemKind::Part(PartKind::ALL[i]);
            i += 1;
        }
        all
    };

    /// What players type and read. A part is named by its catalogue row, so
    /// a handle is a "handle" and not a "part".
    pub fn name(self) -> &'static str {
        match self {
            ItemKind::Ore => "ore",
            ItemKind::Refined => "refined",
            ItemKind::Gear => "gear",
            ItemKind::Smelter => "smelter",
            ItemKind::Part(kind) => kind.name(),
        }
    }

    /// The kind that goes by this name, if any.
    ///
    /// The inverse of [`ItemKind::name`], over the catalogue rather than a
    /// second match, so a new kind is findable here the moment it is named.
    /// A host handing a name back to the sim is the alternative to a host
    /// keeping its own table of them (ASSA-102).
    pub fn from_name(name: &str) -> Option<ItemKind> {
        ItemKind::ALL.into_iter().find(|k| k.name() == name)
    }

    /// The part kind this item is, if it is a part at all.
    pub const fn part(self) -> Option<PartKind> {
        match self {
            ItemKind::Part(kind) => Some(kind),
            _ => None,
        }
    }

    pub fn parse(s: &str) -> Option<ItemKind> {
        let s = s.to_ascii_lowercase();
        // `part:head` as well as a bare `head`, since `code()` writes the
        // prefix; a prefixed name is only ever a part.
        if let Some(name) = s.strip_prefix("part:") {
            return PartKind::parse(name).map(ItemKind::Part);
        }
        match s.as_str() {
            "ore" => Some(ItemKind::Ore),
            "refined" | "ref" | "ingot" | "plate" => Some(ItemKind::Refined),
            "gear" | "gears" => Some(ItemKind::Gear),
            "smelter" => Some(ItemKind::Smelter),
            name => PartKind::parse(name).map(ItemKind::Part),
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

    /// Short machine-readable form, e.g. `ore#2(B)`, and `part:head#2(B)` for
    /// a part. Hosts with a world show species names instead
    /// (`World::item_name`).
    pub fn code(&self) -> String {
        let prefix = if self.kind.part().is_some() {
            "part:"
        } else {
            ""
        };
        format!(
            "{prefix}{}#{}({})",
            self.kind.name(),
            self.species.0,
            self.grade.letter()
        )
    }

    /// Whether this item is one machine part.
    pub const fn is_part(&self) -> bool {
        self.kind.part().is_some()
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
