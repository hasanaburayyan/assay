//! Recipes: what turns into what, how long it takes, where, and which
//! property thresholds the input must meet. Recipes never name a species
//! (ADR 0001): they take N of a kind of item and keep its species. Most
//! keep its grade too; the refining recipes raise it by one, at a loss.

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
    /// Refining rung one, mechanical: crush and pick through 3 ore by hand
    /// and keep the 1 best, one grade up.
    Sort,
    /// Refining rung two, heat and fuel: melt 3 refined down to 1, one
    /// grade up, inside a smelter.
    Resmelt,
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
    /// What players type.
    pub name: &'static str,
    pub input: (ItemKind, u32),
    pub output: (ItemKind, u32),
    /// Ticks per batch.
    pub ticks: u32,
    pub station: Station,
    /// Effective property values the input must reach, at its grade.
    pub requires: &'static [(Property, u32)],
    /// Whether the output is one grade better than the input. Such a
    /// recipe cannot take grade A.
    pub raises_grade: bool,
}

pub const RECIPES: [Recipe; 5] = [
    Recipe {
        id: RecipeId::Smelter,
        name: "smelter",
        input: (ItemKind::Ore, 5),
        output: (ItemKind::Smelter, 1),
        ticks: 20,
        station: Station::Hand,
        requires: &[],
        raises_grade: false,
    },
    Recipe {
        id: RecipeId::Gear,
        name: "gear",
        input: (ItemKind::Refined, 2),
        output: (ItemKind::Gear, 1),
        ticks: 5,
        station: Station::Hand,
        requires: &[(Property::Hardness, GEAR_MIN_HARDNESS)],
        raises_grade: false,
    },
    Recipe {
        id: RecipeId::Refine,
        name: "refine",
        input: (ItemKind::Ore, 1),
        output: (ItemKind::Refined, 1),
        ticks: 20,
        station: Station::Smelter,
        requires: &[],
        raises_grade: false,
    },
    Recipe {
        id: RecipeId::Sort,
        name: "sort",
        input: (ItemKind::Ore, 3),
        output: (ItemKind::Ore, 1),
        ticks: 20,
        station: Station::Hand,
        requires: &[],
        raises_grade: true,
    },
    Recipe {
        id: RecipeId::Resmelt,
        name: "resmelt",
        input: (ItemKind::Refined, 3),
        output: (ItemKind::Refined, 1),
        ticks: 40,
        station: Station::Smelter,
        requires: &[],
        raises_grade: true,
    },
];

impl RecipeId {
    pub const ALL: [RecipeId; 5] = [
        RecipeId::Smelter,
        RecipeId::Gear,
        RecipeId::Refine,
        RecipeId::Sort,
        RecipeId::Resmelt,
    ];

    pub fn recipe(self) -> &'static Recipe {
        RECIPES
            .iter()
            .find(|r| r.id == self)
            .expect("every RecipeId has a table entry")
    }

    pub fn name(self) -> &'static str {
        self.recipe().name
    }

    pub fn parse(s: &str) -> Option<RecipeId> {
        let s = s.to_ascii_lowercase();
        RecipeId::ALL
            .into_iter()
            .find(|r| r.name() == s || r.recipe().output.0.name() == s && !r.recipe().raises_grade)
    }

    pub fn is_hand_craftable(self) -> bool {
        self.recipe().station == Station::Hand
    }
}

/// The recipe a smelter runs on an item in its input slot, if any.
pub fn smelter_recipe_for(kind: ItemKind) -> Option<RecipeId> {
    match kind {
        ItemKind::Ore => Some(RecipeId::Refine),
        ItemKind::Refined => Some(RecipeId::Resmelt),
        _ => None,
    }
}

impl Recipe {
    /// The item one batch makes from `input`: same species, same or one
    /// better grade. `None` if the recipe raises grade and `input` is
    /// already grade A.
    pub fn output_for(&self, input: Item) -> Option<Item> {
        let grade = if self.raises_grade {
            input.grade.better()?
        } else {
            input.grade
        };
        Some(Item::new(self.output.0, input.species, grade))
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
