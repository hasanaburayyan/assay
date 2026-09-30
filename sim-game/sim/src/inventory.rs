//! What a player is carrying.

use serde::{Deserialize, Serialize};

use crate::ore::OreKind;

#[derive(Clone, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Inventory {
    pub iron: u32,
    pub copper: u32,
    pub coal: u32,
    pub stone: u32,
}

impl Inventory {
    pub fn get(&self, kind: OreKind) -> u32 {
        match kind {
            OreKind::Iron => self.iron,
            OreKind::Copper => self.copper,
            OreKind::Coal => self.coal,
            OreKind::Stone => self.stone,
        }
    }

    fn slot(&mut self, kind: OreKind) -> &mut u32 {
        match kind {
            OreKind::Iron => &mut self.iron,
            OreKind::Copper => &mut self.copper,
            OreKind::Coal => &mut self.coal,
            OreKind::Stone => &mut self.stone,
        }
    }

    pub fn add(&mut self, kind: OreKind, amount: u32) {
        let slot = self.slot(kind);
        *slot = slot.saturating_add(amount);
    }

    pub fn total(&self) -> u32 {
        self.iron + self.copper + self.coal + self.stone
    }
}
