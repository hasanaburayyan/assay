//! Recipes: what turns into what, how long it takes, where, and which
//! property thresholds the input must meet. Recipes never name a species
//! (ADR 0001): they take N of a kind of item and keep its species and grade.

use serde::{Deserialize, Serialize};

use crate::item::{Item, ItemKind};
use crate::mineral::{MineralSpecies, Property};
use crate::tuning::GEAR_MIN_HARDNESS;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum RecipeId {
    /// 5 ore of any species → 1 smelter whose walls are that species.
    Smelter,
    /// 2 refined → 1 gear, if the material is hard enough.
    Gear,
    /// 1 ore → 1 refined, inside a smelter hot enough for the species.
    Refine,
}

/// Where a recipe can be made.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Station {
    /// By a player, from their inventory.
    Hand,
    /// Inside a placed smelter, which also burns fuel.
    Smelter,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Recipe {
    pub id: RecipeId,
    pub input: (ItemKind, u32),
    pub output: (ItemKind, u32),
    /// Ticks per batch.
    pub ticks: u32,
    pub station: Station,
    /// Effective property values the input must reach, at its grade.
    pub requires: &'static [(Property, u32)],
}

pub const RECIPES: [Recipe; 3] = [
    Recipe {
        id: RecipeId::Smelter,
        input: (ItemKind::Ore, 5),
        output: (ItemKind::Smelter, 1),
        ticks: 20,
        station: Station::Hand,
        requires: &[],
    },
    Recipe {
        id: RecipeId::Gear,
        input: (ItemKind::Refined, 2),
        output: (ItemKind::Gear, 1),
        ticks: 5,
        station: Station::Hand,
        requires: &[(Property::Hardness, GEAR_MIN_HARDNESS)],
    },
    Recipe {
        id: RecipeId::Refine,
        input: (ItemKind::Ore, 1),
        output: (ItemKind::Refined, 1),
        ticks: 20,
        station: Station::Smelter,
        requires: &[],
    },
];

impl RecipeId {
    pub const ALL: [RecipeId; 3] = [RecipeId::Smelter, RecipeId::Gear, RecipeId::Refine];

    pub fn recipe(self) -> &'static Recipe {
        RECIPES
            .iter()
            .find(|r| r.id == self)
            .expect("every RecipeId has a table entry")
    }

    /// A recipe is named after what it makes.
    pub fn name(self) -> &'static str {
        self.recipe().output.0.name()
    }

    pub fn parse(s: &str) -> Option<RecipeId> {
        let kind = ItemKind::parse(s)?;
        RecipeId::ALL
            .into_iter()
            .find(|r| r.recipe().output.0 == kind)
    }

    pub fn is_hand_craftable(self) -> bool {
        self.recipe().station == Station::Hand
    }
}

impl Recipe {
    /// The item one batch makes from `input`: same species and grade.
    pub fn output_for(&self, input: Item) -> Item {
        Item::new(self.output.0, input.species, input.grade)
    }

    /// The first threshold `input` fails, if any.
    pub fn unmet_requirement(
        &self,
        species: &MineralSpecies,
        input: Item,
    ) -> Option<(Property, u32)> {
        self.requires
            .iter()
            .copied()
            .find(|&(p, min)| species.effective(p, input.grade) < min)
    }
}
