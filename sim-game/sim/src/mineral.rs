//! Generated mineral species, their property sheets, and purity grades.
//!
//! There is no fixed list of materials (ADR 0001). Every world rolls its own
//! species; rules and recipes read the six properties, never a name.

use serde::{Deserialize, Serialize};

use crate::tuning::{GRADE_A_MIN_PURITY, GRADE_B_MIN_PURITY, GRADE_MULTIPLIER_PERCENT};
use crate::types::PlayerId;

/// Index into `World::species`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct SpeciesId(pub u8);

/// The six numbers that describe a species. All 1–100.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Sheet {
    pub density: u8,
    pub strength: u8,
    pub hardness: u8,
    pub heat_tolerance: u8,
    pub reactivity: u8,
    pub conductivity: u8,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Property {
    Density,
    Strength,
    Hardness,
    HeatTolerance,
    Reactivity,
    /// Generated and shown from day one; no rule reads it until power exists.
    Conductivity,
}

impl Property {
    pub const ALL: [Property; 6] = [
        Property::Density,
        Property::Strength,
        Property::Hardness,
        Property::HeatTolerance,
        Property::Reactivity,
        Property::Conductivity,
    ];

    pub const fn name(self) -> &'static str {
        match self {
            Property::Density => "density",
            Property::Strength => "strength",
            Property::Hardness => "hardness",
            Property::HeatTolerance => "heat tolerance",
            Property::Reactivity => "reactivity",
            Property::Conductivity => "conductivity",
        }
    }

    /// Whether impurity weakens this property. Density and heat tolerance
    /// are fixed per species; the rest scale with grade.
    pub const fn scales_with_grade(self) -> bool {
        !matches!(self, Property::Density | Property::HeatTolerance)
    }
}

impl Sheet {
    pub const fn get(&self, property: Property) -> u8 {
        match property {
            Property::Density => self.density,
            Property::Strength => self.strength,
            Property::Hardness => self.hardness,
            Property::HeatTolerance => self.heat_tolerance,
            Property::Reactivity => self.reactivity,
            Property::Conductivity => self.conductivity,
        }
    }

    /// The value an item of this species has at `grade`.
    pub fn effective(&self, property: Property, grade: Grade) -> u32 {
        let base = u32::from(self.get(property));
        if property.scales_with_grade() {
            (base * grade.multiplier_percent() / 100).max(1)
        } else {
            base
        }
    }
}

/// Purity rounded into a letter. Items stack by species and grade.
/// Ordered worst to best so `C < B < A`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Grade {
    C,
    B,
    A,
}

impl Grade {
    pub const ALL: [Grade; 3] = [Grade::C, Grade::B, Grade::A];

    pub fn from_purity(purity: u8) -> Grade {
        if purity >= GRADE_A_MIN_PURITY {
            Grade::A
        } else if purity >= GRADE_B_MIN_PURITY {
            Grade::B
        } else {
            Grade::C
        }
    }

    pub const fn letter(self) -> char {
        match self {
            Grade::C => 'C',
            Grade::B => 'B',
            Grade::A => 'A',
        }
    }

    pub fn parse(s: &str) -> Option<Grade> {
        match s.to_ascii_uppercase().as_str() {
            "A" => Some(Grade::A),
            "B" => Some(Grade::B),
            "C" => Some(Grade::C),
            _ => None,
        }
    }

    pub const fn multiplier_percent(self) -> u32 {
        GRADE_MULTIPLIER_PERCENT[self as usize]
    }

    /// One grade better, if there is one.
    pub const fn better(self) -> Option<Grade> {
        match self {
            Grade::C => Some(Grade::B),
            Grade::B => Some(Grade::A),
            Grade::A => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct MineralSpecies {
    pub id: SpeciesId,
    /// Rolled at generation. Shown until a player renames the species.
    pub generated_name: String,
    /// Set by the discoverer (or someone they granted); replaces the
    /// generated name everywhere.
    pub player_name: Option<String>,
    /// The first player to mine it. Only they (and their grantees) may rename.
    pub discoverer: Option<PlayerId>,
    pub rename_grants: Vec<PlayerId>,
    pub sheet: Sheet,
}

impl MineralSpecies {
    pub fn name(&self) -> &str {
        self.player_name.as_deref().unwrap_or(&self.generated_name)
    }

    pub fn effective(&self, property: Property, grade: Grade) -> u32 {
        self.sheet.effective(property, grade)
    }
}
