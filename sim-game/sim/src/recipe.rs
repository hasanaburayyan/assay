//! Recipes: what turns into what, how long it takes, and where it can be
//! made. A fixed table for now; player-designed machines will add
//! generated recipes later.

use serde::{Deserialize, Serialize};

use crate::item::Item;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum RecipeId {
    Smelter,
    IronGear,
    IronPlate,
    CopperPlate,
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
    pub inputs: &'static [(Item, u32)],
    pub output: (Item, u32),
    /// Ticks per batch.
    pub ticks: u32,
    pub station: Station,
}

pub const RECIPES: [Recipe; 4] = [
    Recipe {
        id: RecipeId::Smelter,
        inputs: &[(Item::Stone, 5)],
        output: (Item::Smelter, 1),
        ticks: 20,
        station: Station::Hand,
    },
    Recipe {
        id: RecipeId::IronGear,
        inputs: &[(Item::IronPlate, 2)],
        output: (Item::IronGear, 1),
        ticks: 5,
        station: Station::Hand,
    },
    Recipe {
        id: RecipeId::IronPlate,
        inputs: &[(Item::IronOre, 1)],
        output: (Item::IronPlate, 1),
        ticks: 20,
        station: Station::Smelter,
    },
    Recipe {
        id: RecipeId::CopperPlate,
        inputs: &[(Item::CopperOre, 1)],
        output: (Item::CopperPlate, 1),
        ticks: 20,
        station: Station::Smelter,
    },
];

impl RecipeId {
    pub const ALL: [RecipeId; 4] = [
        RecipeId::Smelter,
        RecipeId::IronGear,
        RecipeId::IronPlate,
        RecipeId::CopperPlate,
    ];

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
        let item = Item::parse(s)?;
        RecipeId::ALL
            .into_iter()
            .find(|r| r.recipe().output.0 == item)
    }

    pub fn is_hand_craftable(self) -> bool {
        self.recipe().station == Station::Hand
    }
}

/// The smelter recipe that consumes `input`, if any.
pub fn smelting_recipe_for(input: Item) -> Option<RecipeId> {
    RECIPES
        .iter()
        .find(|r| r.station == Station::Smelter && r.inputs.iter().any(|(i, _)| *i == input))
        .map(|r| r.id)
}
