//! The world: every piece of simulation state lives in here.

use crate::building::{Building, BuildingId};
use crate::hash::fnv64;
use crate::item::Item;
use crate::mineral::{MineralSpecies, SpeciesId};
use crate::ore::OreDeposit;
use crate::player::Player;
use crate::rng::{Rng, mix};
use crate::tuning;
use crate::types::{ChunkPos, DepositId, PlayerId, TilePos};
use crate::worldgen;
use serde::{Deserialize, Serialize};

/// Tiles per chunk side.
pub const CHUNK_SIZE: i32 = 16;

/// Salt that separates the runtime RNG stream from world generation.
const SALT_RUNTIME: u64 = 0x005E_ED0F_71C4;

#[derive(Clone, Copy, Debug)]
pub struct WorldConfig {
    pub seed: u64,
    pub width_chunks: i32,
    pub height_chunks: i32,
}

impl Default for WorldConfig {
    fn default() -> Self {
        Self {
            seed: 1,
            width_chunks: 8,
            height_chunks: 8,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct World {
    /// Ticks simulated so far. The sim's only clock.
    pub tick: u64,
    pub seed: u64,
    /// Randomness for runtime rules (e.g. drone jitter, breakdowns).
    pub rng: Rng,
    pub width_chunks: i32,
    pub height_chunks: i32,
    /// The chunk players start in.
    pub spawn: ChunkPos,
    /// This world's mineral species, indexed by `SpeciesId`.
    pub species: Vec<MineralSpecies>,
    /// All deposits, indexed by `DepositId`. Depleted deposits stay in the
    /// list with `amount == 0` so IDs remain stable.
    pub deposits: Vec<OreDeposit>,
    /// Players, indexed by `PlayerId`. A new world has none; players join
    /// through `SystemCommand::AddPlayer` so every peer adds them on the
    /// same tick.
    pub players: Vec<Player>,
    /// Placed buildings, in placement order. Look up by `BuildingId`, not
    /// index: picking one up removes it from the list.
    pub buildings: Vec<Building>,
    /// The next `BuildingId` to hand out.
    pub next_building_id: u32,
}

impl World {
    pub fn new(config: WorldConfig) -> Self {
        let spawn = ChunkPos::new(config.width_chunks / 2, config.height_chunks / 2);
        let species = worldgen::species_roster(config.seed);

        // Row-major chunk order makes deposit IDs deterministic.
        let mut deposits = Vec::new();
        for cy in 0..config.height_chunks {
            for cx in 0..config.width_chunks {
                let id = DepositId(deposits.len() as u32);
                if let Some(d) = worldgen::deposit_in_chunk(
                    config.seed,
                    ChunkPos::new(cx, cy),
                    spawn,
                    id,
                    &species,
                    tuning::CORE_QUALITY,
                ) {
                    deposits.push(d);
                }
            }
        }

        Self {
            tick: 0,
            seed: config.seed,
            rng: Rng::new(mix(config.seed ^ SALT_RUNTIME)),
            width_chunks: config.width_chunks,
            height_chunks: config.height_chunks,
            spawn,
            species,
            deposits,
            players: Vec::new(),
            buildings: Vec::new(),
            next_building_id: 0,
        }
    }

    pub fn width(&self) -> i32 {
        self.width_chunks * CHUNK_SIZE
    }

    pub fn height(&self) -> i32 {
        self.height_chunks * CHUNK_SIZE
    }

    pub fn in_bounds(&self, pos: TilePos) -> bool {
        (0..self.width()).contains(&pos.x) && (0..self.height()).contains(&pos.y)
    }

    /// The center tile of the spawn chunk.
    pub fn spawn_tile(&self) -> TilePos {
        TilePos::new(
            self.spawn.x * CHUNK_SIZE + CHUNK_SIZE / 2,
            self.spawn.y * CHUNK_SIZE + CHUNK_SIZE / 2,
        )
    }

    pub fn species(&self, id: SpeciesId) -> &MineralSpecies {
        &self.species[usize::from(id.0)]
    }

    pub fn species_mut(&mut self, id: SpeciesId) -> &mut MineralSpecies {
        &mut self.species[usize::from(id.0)]
    }

    /// Human-readable item name, e.g. `Korvite ore (B)`.
    pub fn item_name(&self, item: Item) -> String {
        format!(
            "{} {} ({})",
            self.species(item.species).name(),
            item.kind.name(),
            item.grade.letter()
        )
    }

    pub fn deposit(&self, id: DepositId) -> Option<&OreDeposit> {
        self.deposits.get(id.0 as usize)
    }

    pub fn deposit_mut(&mut self, id: DepositId) -> Option<&mut OreDeposit> {
        self.deposits.get_mut(id.0 as usize)
    }

    pub fn player(&self, id: PlayerId) -> Option<&Player> {
        self.players.get(id.0 as usize)
    }

    pub fn player_mut(&mut self, id: PlayerId) -> Option<&mut Player> {
        self.players.get_mut(id.0 as usize)
    }

    pub fn building(&self, id: BuildingId) -> Option<&Building> {
        self.buildings.iter().find(|b| b.id == id)
    }

    pub fn building_mut(&mut self, id: BuildingId) -> Option<&mut Building> {
        self.buildings.iter_mut().find(|b| b.id == id)
    }

    /// The building covering `pos`, if any.
    pub fn building_at(&self, pos: TilePos) -> Option<&Building> {
        self.buildings.iter().find(|b| b.covers(pos))
    }

    /// The hottest a building's walls survive: its material's heat
    /// tolerance, which does not scale with grade.
    pub fn max_temperature(&self, b: &Building) -> u32 {
        u32::from(self.species(b.material.species).sheet.heat_tolerance)
    }

    /// The deposit covering `pos`, if any.
    pub fn deposit_at(&self, pos: TilePos) -> Option<&OreDeposit> {
        self.deposits.iter().find(|d| d.contains(pos))
    }

    /// Hash of the entire world state. Two worlds with equal hashes are
    /// (practically) identical; use it to check replays and detect desyncs.
    pub fn state_hash(&self) -> u64 {
        fnv64(self)
    }
}
