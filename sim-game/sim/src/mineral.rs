//! Generated mineral species, their property sheets, and purity grades.
//!
//! There is no fixed list of materials (ADR 0001). Every world rolls its own
//! species; rules and recipes read the six properties, never a name.

use serde::{Deserialize, Serialize};

use crate::tuning::{
    GRADE_A_MIN_PURITY, GRADE_B_MIN_PURITY, GRADE_MULTIPLIER_PERCENT, SHEET_BAND, SHEET_SCALE,
    SPECIES_NAME_MAX,
};
use crate::types::PlayerId;

/// Index into `World::species`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct SpeciesId(pub u8);

/// Whether a species index names a species of this world.
///
/// ONE GATE, NAMED ONCE (ASSA-43's lesson, applied before it bit). `step`
/// prechecks every command that carries a species index, and
/// [`crate::assembly::plan`] has to ask the same question before it weighs
/// anything, because both index `World::species` directly afterwards. Those
/// were going to be two `>=` comparisons that merely happened to agree.
///
/// Never trust a client's index: an item naming species 300 is a bug or an
/// attack, not a request.
pub fn known_species(species: &[MineralSpecies], id: SpeciesId) -> bool {
    usize::from(id.0) < species.len()
}

/// The six numbers that describe a species. Every one of them is on
/// [`SHEET_SCALE`], which is the pair a surface drawing one as a bar reads
/// (`debug::reading_scale`) — this line used to say "All 1–100", which was
/// prose, and nothing tests prose.
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

    /// The effective value a raw reading of `base` has at `grade`.
    ///
    /// The one place this arithmetic lives: [`Sheet::effective`] calls it, and
    /// so does anything mapping the *ends of a rough band* through it. Scaling
    /// a band after the fact instead would disagree with the sim at low
    /// values, because this divides and then floors at 1.
    pub const fn effective_value(self, base: u32, grade: Grade) -> u32 {
        if self.scales_with_grade() {
            let scaled = base * grade.multiplier_percent() / 100;
            if scaled < 1 { 1 } else { scaled }
        } else {
            base
        }
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

    /// The rough band a first-contact reading shows for a value: the
    /// `SHEET_BAND`-wide range it falls in, as (low, high) inclusive.
    ///
    /// The top band is cut off at the top of [`SHEET_SCALE`] rather than at a
    /// literal `100` (ASSA-279), so the day the scale moves this follows it
    /// instead of quietly promising a value the roll can no longer produce.
    pub fn band(value: u8) -> (u8, u8) {
        let low = (value - 1) / SHEET_BAND * SHEET_BAND + 1;
        (low, (low + SHEET_BAND - 1).min(SHEET_SCALE.1))
    }

    /// The value an item of this species has at `grade`.
    pub fn effective(&self, property: Property, grade: Grade) -> u32 {
        property.effective_value(u32::from(self.get(property)), grade)
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
    /// The first player to mine or assay it. Only they (and their
    /// grantees) may rename.
    pub discoverer: Option<PlayerId>,
    pub rename_grants: Vec<PlayerId>,
    /// Until a player assays a deposit of it, hosts should show the sheet
    /// as rough bands (`Sheet::band`), not exact numbers. The sim itself
    /// always uses the exact values.
    pub assayed: bool,
    pub sheet: Sheet,
}

/// Why a species name was refused.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum NameError {
    Empty,
    TooLong,
    /// Only letters, digits and hyphens.
    BadCharacter,
}

/// Check a player-given species name.
pub fn validate_name(name: &str) -> Result<(), NameError> {
    if name.is_empty() {
        return Err(NameError::Empty);
    }
    if name.chars().count() > SPECIES_NAME_MAX {
        return Err(NameError::TooLong);
    }
    if !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return Err(NameError::BadCharacter);
    }
    Ok(())
}

impl MineralSpecies {
    pub fn name(&self) -> &str {
        self.player_name.as_deref().unwrap_or(&self.generated_name)
    }

    /// Whether `player` may rename this species.
    pub fn may_rename(&self, player: PlayerId) -> bool {
        self.discoverer == Some(player) || self.rename_grants.contains(&player)
    }

    pub fn effective(&self, property: Property, grade: Grade) -> u32 {
        self.sheet.effective(property, grade)
    }
}
