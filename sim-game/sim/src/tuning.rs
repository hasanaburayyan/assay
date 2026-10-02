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

/// Rosters are also rerolled until at least this many species are minable by
/// hand (see `ladder::starter_roster_ok`).
///
/// **Two, because one makes assaying decoration.** With a single hand-minable
/// species there is nothing to compare a property sheet against and no
/// material decision anywhere in the demo. 9.2% of rosters that pass the rung
/// check hold exactly one (2000 seeds, ASSA-35).
pub const MIN_HAND_MINABLE_SPECIES: usize = 2;

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

/// Ticks of standing on a deposit per hand-mining cycle. Now a derived
/// anchor rather than the rule: mining accumulates work, and
/// `WORK_PER_UNIT / HAND_WORK_PER_TICK` is exactly this. `tests/mining.rs`
/// pins the identity, so changing either constant without the other fails
/// loudly instead of quietly retuning hand mining.
pub const HAND_MINE_TICKS: u32 = 4;

/// Work one unit of ore costs, whoever is doing the digging.
///
/// MINING ACCUMULATES WORK PER TICK AGAINST THIS, rather than counting ticks
/// (ADR 0003 amendment A3). Counting ticks offered only 4/3/2/1 ticks per
/// unit, and decision 8 needs a grade-C head and a grade-A head of the SAME
/// species to differ — 60% and 100% of one hardness land in the same integer
/// tick count more often than not. Accumulating makes the average rate
/// exactly monotone in effective hardness. **The remainder carries**, so no
/// work in progress is ever lost.
pub const WORK_PER_UNIT: u32 = 100;

/// Work bare hands do per tick. Chosen so hand mining is unchanged by the
/// curve: 4 ticks × 25 = one unit, exactly `HAND_MINE_TICKS`.
///
/// It is also the bar a pick has to clear, and it is a real bar: a head
/// contributes its effective hardness as `Speed`, so a head below 25 is a
/// tool slower than the hands holding it.
pub const HAND_WORK_PER_TICK: u32 = 25;

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

/// Work per tick per point of the head's effective hardness. The head's
/// `Speed` contribution is `effective hardness × this`.
///
/// **RAISED 1 → 2 (the Game Director's ruling on ASSA-6).** At 1 the demo's
/// first assembly was slower than the hands that built it: the hand gate
/// (`HAND_MINE_MAX_HARDNESS` 40) is read off BASE hardness, so no head can
/// exceed 40 effective, and against bare hands at `HAND_WORK_PER_TICK` 25 a
/// grade-C pick lost to bare hands for **every** minable species, repaying its
/// own build for 10% of them at grade B. A loop whose first tool is a downgrade
/// teaches "do not build".
///
/// **WHAT 2 DOES AND DOES NOT BUY.** It moves the whole ladder relative to the
/// hands (47/60/70% of minable species beat bare hands at C/B/A, from 0/23/40),
/// and it changes how grade FEELS by exactly nothing: the within-species C:A
/// rate ratio is `floor(0.6 × base) / base`, in which this factor cancels. It
/// also does not close the tail — the first pick is built from the STARTER
/// species, and at 2 that still lost to bare hands in **40%** of worlds (2000
/// seeds; 38.9% over 4000, so quote it as "about 40%" and not to a decimal),
/// because a linear factor cannot fix a starter of hardness 5. **Worldgen
/// fixed it, not this number** — `ladder::starter_roster_ok` and ASSA-35.
///
/// **NOT 3, and the reason is a cap rather than taste.** `mine_by_hand` mines
/// at most one unit per tick, so work above `WORK_PER_UNIT` 100 is discarded
/// and the rate stops being monotone in hardness, which is the whole point of
/// A3's carried remainder. At 2 the best reachable head tops out at 80 with
/// headroom; at 3 it is 120 and the top of the ladder flattens.
/// `tests/tools.rs::the_rate_curve_cannot_flatten_without_ci_saying_so` is the
/// guard, and it names the two ways out if mining's reach ever rises.
pub const HEAD_SPEED_PER_HARDNESS: u32 = 2;

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

/// Chance in 100 that a part other than the always-lost one comes back when a
/// design breaks (ADR 0003 point 10).
///
/// **STILL THE WORKING DEFAULT, NOT A BOARD ANSWER.** The demo-loop note left
/// "what fraction of parts come back on a break, and is it per part or a
/// roll?" open; the CEO set 50% per part on 2026-10-01 to unblock, the Game
/// Director backed it, and the board has not spoken. Changing it is this one
/// line: which part is always lost is `Assembly::part_always_lost`, and the
/// roll is `Assembly::break_apart`.
pub const BREAK_RETURN_PERCENT: u32 = 50;

/// Most ore a smelter's input slot holds.
pub const SMELTER_INPUT_CAP: u32 = 50;
/// Most fuel units a smelter holds in reserve.
pub const SMELTER_FUEL_CAP: u32 = 50;
/// Most output a smelter holds before it stops until someone empties it.
pub const SMELTER_OUTPUT_CAP: u32 = 50;
