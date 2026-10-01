//! Every rate, duration and limit the rules use, in one place so the game
//! can be retuned without hunting through systems.
//!
//! Durations are in ticks. The terminal clock runs at 10 ticks/s by default
//! and the game is planned to run at 60, so expect these to be rescaled.
//! Property values are whole numbers from 1 to 100 (see `mineral.rs`).

/// Mineral species generated per world.
pub const SPECIES_PER_WORLD: usize = 6;

/// Rosters are rerolled until at least this many ladder rungs are reachable
/// from bare hands (see `ladder.rs`). Only rung zero can exist until drills
/// (and a decision on the step factor) let hardness progress, so this is 1.
pub const MIN_STARTER_RUNGS: usize = 1;

/// The world's **core quality**: the baseline every deposit's purity is
/// rolled around (ADR 0002, from decision 13 of the 2026-10-01 demo-loop
/// note). Raising it shifts the whole world toward higher purity without
/// removing variance.
///
/// ONE CONSTANT FOR EVERY WORLD, deliberately, until the galaxy layer
/// assigns it per planet. `worldgen::deposit_in_chunk` takes it as an
/// argument rather than reading it here, so that later change is a caller
/// change and not a rewrite of the roll.
///
/// RETUNED 50 → 42 (ASSA-13, ruled on ASSA-3). At 50/45 grade A was 28.6% of
/// deposits, and the only purpose of `sort` and `resmelt` is climbing to A:
/// if A is that easy to find, refining is dominated by walking one chunk
/// over, and a built, tested ladder ships as dead content.
pub const CORE_QUALITY: u32 = 42;

/// How far either side of `CORE_QUALITY` a deposit's purity may roll, before
/// clamping to 1–100. The spread is what keeps a world varied.
///
/// With `CORE_QUALITY` 42 this spans 2–82: 81 values, no clamping, so the
/// roll stays symmetric and uniform. Split by the grade bands (C below 40,
/// B 40–69, A at 70 and up) that is **C 47% / B 37% / A 16%**, so a 6×4
/// world's ~13 deposits hold about two of grade A — rare enough that sorting
/// has a job, common enough that A is not a rumour.
pub const PURITY_SPREAD: u32 = 40;

/// Starter deposits (next to spawn) are floored at this purity, so the
/// first fuel burns hot enough and the first ore is worth mining.
///
/// A FLOOR AND NOT A RANGE since ADR 0002: the starter ladder needs a
/// guarantee, not a distribution, and a floor keeps the guarantee no matter
/// where `CORE_QUALITY` is set. The ladder is judged at grade B (40), so
/// this has room to spare.
pub const STARTER_MIN_PURITY: u32 = 50;

/// Purity at or above which a deposit is grade B / grade A. Below B is C.
pub const GRADE_B_MIN_PURITY: u8 = 40;
pub const GRADE_A_MIN_PURITY: u8 = 70;

/// How much of a species' strength, hardness, reactivity and conductivity
/// an item keeps at grade C, B and A, in percent. Density and heat
/// tolerance never scale.
pub const GRADE_MULTIPLIER_PERCENT: [u32; 3] = [60, 80, 100];

/// Units of ore a player gets per hand-mining cycle at grade C, B and A.
/// The deposit loses one unit per cycle either way: purer ore wastes less.
pub const YIELD_BY_GRADE: [u32; 3] = [1, 2, 3];

/// Ticks of standing on a deposit per hand-mining cycle.
pub const HAND_MINE_TICKS: u32 = 4;

/// Ticks of standing on a deposit to assay its species: afterwards the
/// exact sheet shows instead of rough bands.
pub const ASSAY_TICKS: u32 = 30;

/// Width of the bands a rough (unassayed) sheet reading shows, e.g. 26–50.
pub const SHEET_BAND: u8 = 25;

/// Longest name a player may give a species.
pub const SPECIES_NAME_MAX: usize = 20;

/// Hardest ore (species hardness) a player can mine with bare hands.
/// Anything harder waits for drills.
pub const HAND_MINE_MAX_HARDNESS: u32 = 40;

/// The hottest fire a player can start by hand. A fuel whose species heat
/// tolerance is at most this lights in a cold smelter; hotter fuels need a
/// smelter that is already burning at least that hot.
pub const HAND_SPARK_TEMPERATURE: u32 = 30;

/// Effective reactivity an item needs to count as fuel at all.
pub const FUEL_MIN_REACTIVITY: u32 = 25;

/// Ticks one unit of fuel burns per point of effective reactivity.
pub const BURN_TICKS_PER_REACTIVITY: u32 = 2;

/// Effective hardness refined material needs to be made into a gear.
pub const GEAR_MIN_HARDNESS: u32 = 20;

/// How far (in tiles, diagonals counting as one) a player can reach to
/// place, fill, empty or pick up a building.
pub const REACH: i32 = 3;

// ---------------------------------------------------------------------------
// Assemblies (ADR 0003). PROVISIONAL: nothing has been played yet. The two
// anchors the numbers have to keep are in `sim/tests/assembly.rs`, which
// asserts the ADR's own arithmetic, so retuning these shows up there first.
// ---------------------------------------------------------------------------

/// Each part's size: what it costs in refined material AND how much stuff it
/// is made of for mass. One number for both, so no part is cheap and heavy.
pub const HEAD_SIZE: u32 = 1;
pub const HELD_FRAME_SIZE: u32 = 2;
pub const PLANTED_FRAME_SIZE: u32 = 5;
pub const HOPPER_SIZE: u32 = 2;

/// Mass a frame carries per point of its material's effective strength, per
/// point of its own size. A frame carries this many times its own mass when
/// its strength equals its density.
///
/// Stays 3 deliberately (ASSA-5 ruling): a same-species pick breaks about
/// 31% of the time at grade B, and breaking is the teeth behind assaying.
pub const FRAME_BUDGET_PER_STRENGTH: u32 = 3;

/// Ore a planted frame holds on its own before it stalls — the tiny internal
/// buffer of decision 9. Hoppers add to it.
pub const PLANTED_FRAME_BUFFER: u32 = 10;

/// Ore one hopper adds. Flat from the kind: a hopper's material sets its mass
/// and nothing else, so hopper species is one legible choice (make it light).
pub const HOPPER_CAPACITY: u32 = 50;

/// Hopper slots a planted frame offers. Generous on purpose, so that **mass**
/// is what stops you stacking hoppers rather than a slot count.
pub const MAX_HOPPER_SLOTS: u32 = 4;

/// Durability pool per point of the head's effective strength, per point of
/// head size. Pool = head size × effective head strength × this.
///
/// RAISED 10 → 60 (ADR 0003 amendment A2): at a grade-B strength-50 head that
/// is 2400 points, so **120 swings** at `PICK_WEAR_PER_SWING`. A pick buys
/// only time (decision 7 parks the hardness ladder), and 20 swings could not
/// repay the 60 ticks of smelting its 3 refined cost.
pub const PICK_DURABILITY_PER_STRENGTH: u32 = 60;

/// Durability drained per swing. The one knob that retunes a pick's life.
pub const PICK_WEAR_PER_SWING: u32 = 20;

/// Most ore a smelter's input slot holds.
pub const SMELTER_INPUT_CAP: u32 = 50;
/// Most fuel units a smelter holds in reserve.
pub const SMELTER_FUEL_CAP: u32 = 50;
/// Most output a smelter holds before it stops until someone empties it.
pub const SMELTER_OUTPUT_CAP: u32 = 50;
