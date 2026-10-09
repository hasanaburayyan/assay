//! The world: every piece of simulation state lives in here.

use crate::building::{
    Building, BuildingId, BuildingKind, BuildingState, Machine, MachineIdle, MachineStall,
    MachineState, SlotRole, Smelter, SmelterIdle, SmelterStall, SmelterState, WorkReading,
};
use crate::hash::fnv64;
use crate::item::{Item, ItemStack};
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

    /// **THE TWO DEPOSITS THE STARTER GUARANTEE ACTUALLY POINTS AT**, as
    /// `(material, fuel)`, or `None` if this roster has no starter pair.
    ///
    /// `ladder::starter_species` names two *species*; this names the two
    /// *deposits* worldgen placed for them, in the `STARTER_CHUNKS` beside
    /// spawn with purity floored at `STARTER_MIN_PURITY`. **The difference is
    /// a whole grade and that is ASSA-139's second half.** The promise is
    /// located, not global: other deposits of the same fuel species sit all
    /// over the map at whatever purity they rolled, and a scripted session
    /// that walked to the NEAREST one of the right species reached a grade-C
    /// patch in 1.5% of worlds and stalled on a fire too cool to melt its own
    /// ore — the pair was never at fault.
    ///
    /// So picking a deposit is a rule and not a convenience, for the same
    /// reason `AssaySim::starter_pair` gives its caller the answer instead of
    /// the inputs: grade scales reactivity, and a client choosing between two
    /// patches is deciding whether a smelter will run. It is also deciding it
    /// from the ROUGH sheet, before anything is assayed.
    ///
    /// Three callers hand-rolled this chunk lookup before it lived here
    /// (`sim-cli/tests/common`, `tests/ladder.rs`, the demo), which is how
    /// ASSA-43 and ASSA-52 happened.
    pub fn starter_deposits(&self) -> Option<(DepositId, DepositId)> {
        let (material, fuel) = crate::ladder::starter_species(&self.species)?;
        let at = |i: usize, species: SpeciesId| {
            let (dx, dy) = worldgen::STARTER_CHUNKS[i];
            let chunk = ChunkPos::new(self.spawn.x + dx, self.spawn.y + dy);
            self.deposits
                .iter()
                .find(|d| d.center.chunk() == chunk && d.species == species)
                .map(|d| d.id)
        };
        Some((at(0, material)?, at(1, fuel)?))
    }

    /// Whether this deposit is one of [`World::starter_deposits`].
    pub fn is_starter_deposit(&self, id: DepositId) -> bool {
        self.starter_deposits()
            .is_some_and(|(material, fuel)| id == material || id == fuel)
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

    /// How hot this item burns, or `None` if it is not fuel at all.
    ///
    /// Grade belongs here and not in [`World::fuel_lights`]: reactivity
    /// scales with grade, heat tolerance never does (`mineral.rs`).
    ///
    /// Asks [`crate::ladder::burn_temperature_at`], the one place that decides
    /// (ASSA-139), the same way [`World::fuel_lights`] asks
    /// [`crate::ladder::lights_in_fire`]. This held its own copy of the
    /// comparison and the ladder held two more; they agreed by hand.
    pub fn fuel_temperature(&self, item: Item) -> Option<u32> {
        crate::ladder::burn_temperature_at(self.species(item.species), item.grade)
    }

    /// Whether the fuel in this smelter's slot catches, given the fire it has
    /// now — which may be a unit that is one tick from burning out, and that
    /// is how a hotter fuel gets lit at all.
    ///
    /// Asks [`crate::ladder::lights_in_fire`], the one place that decides
    /// (ASSA-128). `step` asks this same method, so the sentence a player
    /// reads cannot disagree with whether the fire actually catches.
    pub fn fuel_lights(&self, s: &Smelter, fuel: Item) -> bool {
        crate::ladder::lights_in_fire(self.species(fuel.species), s.burn_temperature)
    }

    /// What this smelter is doing, and why if it has stopped.
    ///
    /// **THE ONE PLACE THAT DECIDES** (ASSA-80). This chain used to live in
    /// `debug::building_status`, which meant the only way for `step` to know a
    /// smelter had stalled was to re-derive it — and a second copy of a
    /// decision is how ASSA-43 and ASSA-52 happened. The order of the arms is
    /// the order of the old status line, unchanged, because it is also the
    /// order a player fixes things in.
    ///
    /// Returns [`SmelterState::Idle`] for anything that is not a smelter, so
    /// callers do not have to match the kind twice.
    pub fn smelter_state(&self, b: &Building) -> SmelterState {
        let BuildingKind::Smelter(s) = &b.kind else {
            return SmelterState::Idle(SmelterIdle::Empty);
        };
        let walls = self.max_temperature(b);
        // The fire this smelter is running on: what is burning now, or what
        // the fuel in the slot will catch at next tick, or nothing.
        //
        // **THE SEAM BETWEEN TWO UNITS OF FUEL IS NOT A STALL** (ASSA-128).
        // `run_smelters` spends the last tick of a unit and relights on the
        // next one, so `burn_left == 0` with lightable fuel in the slot is a
        // working smelter mid-stride. Reading the dying fire's own
        // temperature here instead would report `FireTooCool` on a cold
        // start, which is the same lie wearing the other arm's sentence.
        let burning = if s.burn_left > 0 {
            Some(s.burn_temperature)
        } else {
            s.fuel
                .filter(|f| self.fuel_lights(s, f.item))
                .and_then(|f| self.fuel_temperature(f.item))
        };
        let fire = burning.unwrap_or(0).min(walls);
        let needs = s
            .input
            .map(|i| u32::from(self.species(i.item.species).sheet.heat_tolerance));
        if let Some(idle) = Self::input_idle(s) {
            SmelterState::Idle(idle)
        } else if s
            .output
            .is_some_and(|o| o.count >= crate::tuning::SMELTER_OUTPUT_CAP)
        {
            SmelterState::Stalled(SmelterStall::OutputFull)
        } else if s.burn_left == 0 && s.fuel.is_none() {
            SmelterState::Stalled(SmelterStall::NoFuel)
        } else if burning.is_none() {
            SmelterState::Stalled(SmelterStall::FuelWontLight)
        } else if needs.is_some_and(|n| fire < n) {
            SmelterState::Stalled(SmelterStall::FireTooCool {
                fire,
                needs: needs.unwrap_or(0),
            })
        } else {
            SmelterState::Working { at: fire }
        }
    }

    /// The input slot's own answer: empty, or holding less than one batch.
    /// `None` means there is a batch to work on and the rest of the chain
    /// decides.
    ///
    /// **THIS IS `run_smelters`' OWN PRECONDITION, READ OFF THE SAME TABLE**
    /// (ASSA-322). `step.rs` skips a smelter whose `input.count` is below
    /// `recipe.input.1` and used to be the only place that knew: a smelter
    /// holding 2 of a 3-refined resmelt reported `working at 60` on every
    /// surface, forever, and `lit` in the Godot binding reads the same answer —
    /// so the window drew a fire on a smelter that had never lit and would
    /// never consume a unit.
    ///
    /// It sits where `input.is_none()` sat, and that is the Game Director's
    /// placement, not a convenience: holding 0 of 3 and holding 2 of 3 are one
    /// condition in degree, and the input shortfall already outranks fuel here
    /// (an empty smelter with no fuel says `nothing to refine`, not `no fuel`).
    ///
    /// An input kind with no smelter recipe answers `None` and falls through,
    /// exactly as before. `Insert` refuses that kind at the door
    /// (`RejectReason::WrongItem`), so it is unreachable rather than handled.
    fn input_idle(s: &Smelter) -> Option<SmelterIdle> {
        let Some(input) = s.input else {
            return Some(SmelterIdle::Empty);
        };
        let recipe = crate::recipe::smelter_recipe_for(input.item.kind)?;
        (input.count < recipe.recipe().input.1).then_some(SmelterIdle::ShortBatch {
            recipe,
            holding: input.count,
        })
    }

    /// What this planted machine is doing, and why if it has stopped.
    ///
    /// **THE ONE PLACE THAT DECIDES** (ASSA-94), the way
    /// [`World::smelter_state`] has decided for the smelter since ASSA-80.
    /// The arms are in the order `debug::machine_status` printed them and the
    /// order `step` tested them — which were already the same order, and now
    /// are the same code.
    ///
    /// Takes the machine as well as the building so there is no arm for "not
    /// a machine" to answer wrongly; [`World::building_state`] matches the
    /// kind once for callers that have only a `Building`.
    pub fn machine_state(&self, b: &Building, m: &Machine) -> MachineState {
        let Some(d) = self.deposit_at(b.pos) else {
            return MachineState::Idle(MachineIdle::NoDeposit);
        };
        if d.is_depleted() {
            return MachineState::Idle(MachineIdle::DepositMinedOut);
        }
        if !crate::ladder::hand_minable(self.species(d.species)) {
            return MachineState::Idle(MachineIdle::DepositTooHard { species: d.species });
        }
        // `stats`, not `stat_range().low`, and that is the point of ASSA-94:
        // the rules read the exact stat, so the one place that decides reads
        // what the rules read. Capacity is flat from the part kind, so the
        // banded reading a menu shows cannot differ from it — proved by
        // `capacity_is_flat_so_a_band_cannot_disagree` rather than assumed.
        let capacity = m.assembly.stats(&self.species).capacity;
        let amount = crate::tuning::YIELD_BY_GRADE[d.grade() as usize];
        if m.has_room_for(amount, capacity) {
            MachineState::Working {
                deposit: d.id,
                species: d.species,
                grade: d.grade(),
            }
        } else {
            MachineState::Stalled(MachineStall::BufferFull {
                held: m.held.map_or(0, |h| h.count),
                capacity,
            })
        }
    }

    /// What any building is doing, whatever kind it is.
    pub fn building_state(&self, b: &Building) -> BuildingState {
        match &b.kind {
            BuildingKind::Smelter(_) => BuildingState::Smelter(self.smelter_state(b)),
            BuildingKind::Machine(m) => BuildingState::Machine(self.machine_state(b, m)),
        }
    }

    /// Every holder this building has: what it is for, what is in it, and how
    /// much it takes. In the order a player fixes things in, which is
    /// `building_status`' order and `smelter_state`'s.
    ///
    /// **THE SET OF ROWS IS THE SIM'S, NOT A MENU'S.** A host that listed the
    /// slots itself would have to know that a smelter has three and a machine
    /// has one, that the third takes no inserts, and that the machine's cap is
    /// its parts' `Capacity` rather than a tuning constant — four rules, in
    /// GDScript, that a new building kind would silently leave behind. Adding a
    /// `BuildingKind` fails to compile here instead.
    ///
    /// The cap is what the *sim* will accept, so a fill is two sim numbers and
    /// no host divides anything it had to derive first (ASSA-276 move 3).
    pub fn building_slots(&self, b: &Building) -> Vec<(SlotRole, Option<ItemStack>, u32)> {
        match &b.kind {
            BuildingKind::Smelter(s) => vec![
                (SlotRole::Input, s.input, tuning::SMELTER_INPUT_CAP),
                (SlotRole::Fuel, s.fuel, tuning::SMELTER_FUEL_CAP),
                (SlotRole::Output, s.output, tuning::SMELTER_OUTPUT_CAP),
            ],
            BuildingKind::Machine(m) => vec![(
                SlotRole::Buffer,
                m.held,
                m.assembly.stats(&self.species).capacity,
            )],
        }
    }

    /// How far through the unit in front of it this building is, or `None` when
    /// there is no unit in front of it at all.
    ///
    /// **THE ONE PLACE THAT DECIDES**, for [`World::smelter_state`]'s reason
    /// (ASSA-80/94). Until ASSA-321 both `progress` fields were printed by
    /// nothing: not `building_status`, not the inspector, not the binding — so
    /// the smelter you fed was the only thing in the game that worked in
    /// silence, while your own hand-craft counted its ticks down at you. A
    /// client reaching for it would have had to divide by `recipe.ticks`
    /// itself, which is a sim rule written in GDScript.
    ///
    /// **A STALL STILL HAS A READING, AND THAT IS THE POINT.** The gate is "is
    /// there a unit in front of it", not "is it moving". A smelter holding ore
    /// and no fuel reads `0 of 20` beside `stalled: no fuel` — the batch has
    /// not started, which is a different sentence from the stall alone — and a
    /// drill whose buffer filled mid-unit keeps a *non-zero* reading, because
    /// `Machine::has_room_for` banks that progress on purpose so emptying the
    /// buffer carries on. `None` there would hide the one mechanic that
    /// comment exists to protect.
    ///
    /// **ONLY THE DRILL CAN BE STALLED PART-WAY THROUGH A UNIT, AND I WROTE
    /// THE OPPOSITE HERE FIRST.** All four smelter stalls are tested in
    /// `run_smelters` *before* `s.progress += 1`, and the fire cannot die
    /// mid-batch: one unit of anything that passes the fuel gate burns
    /// `>= FUEL_MIN_REACTIVITY * BURN_TICKS_PER_REACTIVITY` = 50 ticks against
    /// a 40-tick resmelt. So for a smelter `done > 0` implies it refined last
    /// tick. The gate is still not "is it moving", because `0 of 20` while
    /// stalled is a reading a player needs; it just means the dramatic version
    /// of this paragraph described a world the rules forbid.
    /// `a_smelters_progress_is_zero_unless_it_refined_last_tick` pins the
    /// invariant, so a fuel rule that ever makes it false arrives as a red test
    /// beside a reading that already handles it.
    ///
    /// **`None` MEANS NOTHING IS BEING WORKED, AND THE TWO KINDS DISAGREE
    /// ABOUT WHEN** — the same asymmetry [`MachineState::halted`] documents,
    /// for the same reason. An empty smelter has nothing in front of it and one
    /// insert fixes that. A drill on no deposit, a mined-out one, or rock
    /// nothing can break has nothing in front of it *and never will*; reading
    /// `0 of 100` there would invite a player to wait for a unit that cannot
    /// arrive (ASSA-43's rule).
    ///
    /// **THE SMELTER'S GATE MIRRORS `run_smelters`' OWN PRECONDITIONS** rather
    /// than guessing at them: a slot holding 2 refined against a recipe that
    /// eats 3 is not a batch, and the step loop skips it. See
    /// `sim/tests/smelter.rs::a_part_batch_makes_no_progress_and_the_state_line_does_not_know_it`
    /// for what that currently costs us elsewhere.
    pub fn building_work(&self, b: &Building) -> Option<WorkReading> {
        match &b.kind {
            BuildingKind::Smelter(s) => {
                let input = s.input?;
                let recipe = crate::recipe::smelter_recipe_for(input.item.kind)?.recipe();
                if input.count < recipe.input.1 {
                    return None;
                }
                // Grade A against a grade-raising recipe: `Insert` refuses it,
                // so this is unreachable from play and still answered, because
                // a save or a future inserter could put it there and "0 of 40
                // forever" is the worst of the three possible answers.
                recipe.output_for(input.item)?;
                Some(WorkReading {
                    done: s.progress,
                    total: recipe.ticks,
                })
            }
            BuildingKind::Machine(m) => match self.machine_state(b, m) {
                MachineState::Idle(_) => None,
                MachineState::Working { .. } | MachineState::Stalled(_) => Some(WorkReading {
                    done: m.progress,
                    total: crate::tuning::WORK_PER_UNIT,
                }),
            },
        }
    }

    /// Every building a player has to do something about, in placement order.
    ///
    /// **THE STANDING ANSWER TO A STANDING CONDITION** (Game Director,
    /// ASSA-94: "a refusal is a MOMENT; a stall is a CONDITION"). The stall
    /// *events* are edges — each fires once, on the tick it happens, and is
    /// gone. This is the question a host can ask on any tick, forever, which
    /// is what a surface that outlives a scrolling log needs.
    ///
    /// Whoever placed it: `Building` carries no owner, so the sim cannot
    /// answer "something *you* built". In co-op that is the better answer
    /// anyway — a cold smelter is everyone's problem — but it is a widening
    /// of the ruling and is flagged as one on the item.
    pub fn halted(&self) -> impl Iterator<Item = &Building> + '_ {
        self.buildings
            .iter()
            .filter(|b| self.building_state(b).halted())
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
