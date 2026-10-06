//! The starter ladder (ADR 0001, decision 10): given a roster, which species
//! can a fresh player use, and which become usable once those are in hand?
//!
//! Worldgen rerolls a roster until this check passes, so every world starts
//! climbable. The model is deliberately simple and only reads the rules
//! that exist today plus the next one (drill heads):
//!
//! - **Mine** a species if its hardness is within what you can mine: bare
//!   hands at first, later the best drill head you could make, which is
//!   *modelled* here as mining up to its own effective hardness.
//!   **THE SIM DOES NOT IMPLEMENT THAT YET** — `HAND_MINE_MAX_HARDNESS`
//!   gates machine mining as well as hand mining (`step.rs`), so nothing in
//!   the game mines hardness above 40 whatever it is made of. Harmless only
//!   because `MIN_STARTER_RUNGS` is 1, so no rung above zero is ever
//!   required. When reach is built, gate it on the head's **effective
//!   hardness** and not on `HEAD_SPEED_PER_HARDNESS`: reach is not speed.
//! - **Build a smelter** from any minable species; its walls take that
//!   species' heat tolerance.
//! - **Fuel** is any minable species reactive enough. It lights by hand if
//!   its heat tolerance is within the hand spark, or from a fire already
//!   burning at least that hot.
//! - A species is **usable** once it is minable and a fire you can build
//!   and feed reaches its heat tolerance. Each rung is the set of species
//!   that become usable together.
//!
//! Capabilities are judged at grade B, a margin below the best roll, so the
//! guarantee holds with average ore.

use crate::assembly::{Assembly, Mount, Part, PartKind};
use crate::item::{Item, ItemKind};
use crate::mineral::{Grade, MineralSpecies, Property, SpeciesId};
use crate::tuning::{
    FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, HAND_SPARK_TEMPERATURE, HAND_WORK_PER_TICK,
    MIN_HAND_MINABLE_SPECIES, MIN_STARTER_RUNGS,
};

/// The grade capabilities are judged at.
pub const JUDGED_AT: Grade = Grade::B;

pub fn hand_minable(s: &MineralSpecies) -> bool {
    u32::from(s.sheet.hardness) <= HAND_MINE_MAX_HARDNESS
}

/// How hot this species burns **at one named grade**, if it counts as fuel at
/// that grade at all.
///
/// **ONE PLACE DECIDES HOW HOT A ROCK BURNS.** There were three copies of this
/// comparison: this function at [`JUDGED_AT`], [`fuel_grade`]'s loop over every
/// grade, and `World::fuel_temperature` for an item in a slot. They agreed, but
/// only by hand — and ASSA-139 is what you get when one caller needs the answer
/// at a grade the others never ask about and writes a fourth copy to get it.
/// Reactivity is the one fuel property grade scales, so the grade is never
/// optional; [`burn_temperature`] names [`JUDGED_AT`] rather than defaulting it.
pub fn burn_temperature_at(s: &MineralSpecies, grade: Grade) -> Option<u32> {
    let t = s.effective(Property::Reactivity, grade);
    (t >= FUEL_MIN_REACTIVITY).then_some(t)
}

/// How hot this species burns at the judged grade, if it counts as fuel.
pub fn burn_temperature(s: &MineralSpecies) -> Option<u32> {
    burn_temperature_at(s, JUDGED_AT)
}

/// The cheapest grade at which a species counts as fuel at all, or `None` if
/// no grade does.
///
/// **ONE PLACE DECIDES WHETHER A ROCK IS FUEL** (ASSA-93). `species_table` had
/// this loop inline and the Godot binding had nothing, so the window could not
/// tell a fuel nobody can light from a rock that is not fuel — it was handed a
/// bit where the sim holds a three-state answer. Grades ascend (`Grade::ALL`
/// is C, B, A), so the first hit is the cheapest; iterating the other way is
/// the bug ASSA-58 found, where every row claimed grade A.
///
/// Distinct from [`burn_temperature`], which judges at [`JUDGED_AT`] because
/// the ladder models what a player can *rely* on. This answers what the
/// roster affords at any grade, which is what a readout should say.
pub fn fuel_grade(s: &MineralSpecies) -> Option<Grade> {
    Grade::ALL
        .into_iter()
        .find(|g| burn_temperature_at(s, *g).is_some())
}

/// Whether a fire burning at `fire` sets this species alight, counting the
/// hand spark a player always has.
///
/// **ONE PLACE DECIDES WHETHER FUEL CATCHES** (ASSA-128). `run_smelters` and
/// `World::smelter_state` each had their own copy of this comparison and they
/// disagreed: the rules let a unit light off the dying fire of the one before
/// it, and the state function only ever asked the hand spark — so a smelter
/// that refined 19 ore announced "fuel won't light from cold" once per unit
/// burned. A caller gets the question answered, never the inputs to answer it
/// with, the same way [`lighting`] keeps [`best_fire`] private.
///
/// **NO GRADE ANYWHERE IN HERE** (Game Director's ruling on ASSA-58). Heat
/// tolerance is the one property grade never scales (`mineral.rs`), so
/// lightability is a per-species constant and a grade on the clause would be
/// a lie. Reactivity *does* scale, which is why the "fuel at X or better"
/// half of the same sentence keeps its grade. The asymmetry is real.
pub fn lights_in_fire(s: &MineralSpecies, fire: u32) -> bool {
    u32::from(s.sheet.heat_tolerance) <= fire.max(HAND_SPARK_TEMPERATURE)
}

/// Whether a hand spark alone sets this species alight: [`lights_in_fire`]
/// with no fire at all.
pub fn lights_from_cold(s: &MineralSpecies) -> bool {
    lights_in_fire(s, 0)
}

/// Fuel a player can mine and light with no machine at all.
pub fn hand_lit_fuel(s: &MineralSpecies) -> bool {
    hand_minable(s) && burn_temperature(s).is_some() && lights_from_cold(s)
}

/// How a player could ever get this species burning **in this world**.
///
/// Three states and not two, because the two ways of collapsing them are both
/// a lie we have already paid for: folding "needs a hotter fire" into "cannot
/// be lit" is ASSA-43's trap in reverse, and folding it the other way promises
/// a fire that does not exist — 56.3% of the time, over 5000 worlds (Game
/// Director's measurement on ASSA-58).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Lighting {
    /// A hand spark is enough.
    FromCold,
    /// Not from cold, but this world can build a fire that hot.
    FromAHotterFire,
    /// Nothing this world can keep burning reaches it.
    NothingBurnsHotEnough,
}

/// Which of the three [`Lighting`] states a species is in, for a roster.
///
/// **THIS IS THE EXPORT AND [`best_fire`] STAYS PRIVATE, on purpose.** A
/// caller handed the hottest-fire number has to re-derive "heat tolerance ≤
/// that", and a second copy of a comparison is exactly how ASSA-43 and
/// ASSA-52 happened: the note and the rule drifted because each did its own
/// arithmetic. Hosts get the question answered, never the inputs to answer it
/// with.
///
/// One conservatism inherited from [`best_fire`] and deliberately not changed
/// here: the chain counts a species as fuel only at [`JUDGED_AT`], so a
/// species that burns only at grade A is invisible to it. That same function
/// feeds [`starter_roster_ok`], so widening it would re-roll every world in
/// the game — a worldgen decision, not a wording one.
pub fn lighting(species: &[MineralSpecies], id: SpeciesId) -> Lighting {
    let s = &species[usize::from(id.0)];
    if lights_from_cold(s) {
        return Lighting::FromCold;
    }
    let minable: Vec<&MineralSpecies> = species.iter().filter(|s| hand_minable(s)).collect();
    if u32::from(s.sheet.heat_tolerance) <= best_fire(&minable) {
        Lighting::FromAHotterFire
    } else {
        Lighting::NothingBurnsHotEnough
    }
}

/// The hottest fire you can keep going with these minable species: light
/// what the hand spark lights, then anything that fire lights, and so on.
fn best_fire(minable: &[&MineralSpecies]) -> u32 {
    let mut fire = 0;
    let mut spark = HAND_SPARK_TEMPERATURE;
    loop {
        let reachable = minable
            .iter()
            .filter(|s| u32::from(s.sheet.heat_tolerance) <= spark)
            .filter_map(|s| burn_temperature(s))
            .max()
            .unwrap_or(0);
        if reachable <= fire {
            return fire;
        }
        fire = reachable;
        spark = spark.max(fire);
    }
}

/// Which species become usable at each rung, starting from bare hands.
/// Empty if nothing at all can be smelted by hand.
pub fn rungs(species: &[MineralSpecies]) -> Vec<Vec<SpeciesId>> {
    let mut usable = vec![false; species.len()];
    let mut rungs = Vec::new();
    let mut mine = HAND_MINE_MAX_HARDNESS;
    loop {
        let minable: Vec<&MineralSpecies> = species
            .iter()
            .filter(|s| u32::from(s.sheet.hardness) <= mine)
            .collect();
        let walls = minable
            .iter()
            .map(|s| u32::from(s.sheet.heat_tolerance))
            .max()
            .unwrap_or(0);
        let fire = best_fire(&minable);
        let newly: Vec<SpeciesId> = minable
            .iter()
            .filter(|s| !usable[usize::from(s.id.0)])
            .filter(|s| u32::from(s.sheet.heat_tolerance) <= walls.min(fire))
            .map(|s| s.id)
            .collect();
        if newly.is_empty() {
            return rungs;
        }
        for id in &newly {
            usable[usize::from(id.0)] = true;
        }
        rungs.push(newly);
        // The model's climb: drill heads made from what's usable mine up to
        // their own hardness. See the module doc — `step.rs` does not do this
        // yet, and no rung above zero is required while `MIN_STARTER_RUNGS`
        // is 1.
        mine = species
            .iter()
            .filter(|s| usable[usize::from(s.id.0)])
            .map(|s| s.effective(Property::Hardness, JUDGED_AT))
            .fold(mine, u32::max);
    }
}

/// Can bare hands actually *use* this species — mine it **and** smelt it?
///
/// **RUNG ZERO IS THE AUTHORITY AND THIS RE-DERIVES NOTHING** (Game Director's
/// ruling on ASSA-52). [`hand_minable`] answers a smaller question than it
/// looks: a species can pass the hardness gate and still never become a part,
/// because smelting needs a fire hot enough for its heat tolerance **and** a
/// smelter whose walls survive that fire. Over 2000 worlds 13.6% of deposits
/// are exactly that, 59.3% of worlds hold one, and 13.9% put one under spawn.
///
/// Asking [`rungs`] rather than comparing temperatures here is the whole point:
/// the fire you can build, what it can light, and what those walls survive are
/// already decided in one place, and a second copy would drift from it the
/// first time the chain changed.
pub fn usable_from_bare_hands(species: &[MineralSpecies], id: SpeciesId) -> bool {
    rungs(species)
        .first()
        .is_some_and(|rung_zero| rung_zero.contains(&id))
}

/// Does this exact pair smelt — a smelter built **out of `material`**, fed
/// `fuel` mined at `grade`?
///
/// **[`rungs`] ASKS A STRICTLY EASIER QUESTION AND THAT IS THE WHOLE OF
/// ASSA-139.** Rung zero counts a species usable if the *best* walls in the
/// roster survive the *hottest chained* fire, so membership says "somebody
/// could smelt this here". The starter pair promises far more: one hand-lit
/// fuel, and walls made of the material itself, because that is the only
/// smelter a player with nothing else can build. A pair can sit in rung zero
/// and still never light — 1.8% of worlds did.
///
/// The fire is `min(fuel temperature, walls)` and the walls are the material's
/// own heat tolerance, which is also exactly what its ore needs. So the `min`
/// can never bite today and the comparison reduces to the fuel; it is written
/// as the real rule anyway, because the day a smelter's walls stop being its
/// material's heat tolerance this still answers correctly.
///
/// **NO TEST CAN CATCH A CHANGE TO THAT `min`, and I would rather say so than
/// let a green run read as cover.** `walls` and `needs` are the same number,
/// so `min` and `max` give the same answer on every input the game can
/// produce; I mutated it to `max` and all 14 ladder tests stayed green. The
/// clause is here for the reader and for the day the two stop being equal,
/// and on that day it needs a test of its own.
///
/// Heat only. Whether the player can light it at all is [`hand_lit_fuel`]'s
/// question, and [`starter_species`] asks both.
pub fn pair_smelts(material: &MineralSpecies, fuel: &MineralSpecies, grade: Grade) -> bool {
    let walls = u32::from(material.sheet.heat_tolerance);
    let needs = u32::from(material.sheet.heat_tolerance);
    burn_temperature_at(fuel, grade).unwrap_or(0).min(walls) >= needs
}

/// **THE SMALLEST THING THAT IS A PLANTED MACHINE AT ALL**: one frame and one
/// head, both of `id` at `grade`. True when it does not break under its own
/// weight.
///
/// A FRAME READS STRENGTH AND SETS THE WHOLE MASS BUDGET; a head reads
/// hardness. So this is the one question that asks both of the jobs
/// [`starter_species`] hands its answer, and asking it is the whole of ASSA-170
/// step 1 — see that selection's own comment for the price.
///
/// **IT ASKS [`Assembly::stats`] AND NOT `stat_range`, WHICH IS NOT A STYLE
/// CHOICE.** `stat_range` reads a species' *band*, which is 25 wide until
/// somebody assays it — so a rule built on it would give a different answer
/// before and after an assay, and worldgen runs before anything is assayed at
/// all. A rule may not read a presentation state. Maren's probe
/// (`tests/maren_first_machine_promise.rs`) uses `stat_range` and is right to:
/// it assays every species first, which makes the band a point, and on a point
/// the two agree.
pub fn carries_first_machine(species: &[MineralSpecies], id: SpeciesId, grade: Grade) -> bool {
    let refined = Item::new(ItemKind::Refined, id, grade);
    !Assembly::new(
        Part::of(PartKind::Frame(Mount::Planted), refined),
        vec![Part::of(PartKind::Head, refined)],
    )
    .stats(species)
    .is_overweight()
}

/// Rung zero's two guaranteed deposits: a species to mine, smelt and build
/// with, and a fuel the player can light by hand. May be the same species.
///
/// **WHAT THIS ANSWER IS VALID FOR, BECAUSE IT HAS BEEN WRONG TWICE BY BEING
/// REUSED FOR A JOB IT WAS NOT SELECTED ON** (`assay-rulings` §5, "one species,
/// selected on one property, then used for three jobs"). The material is what
/// you MINE, SMELT and BUILD THE FIRST MACHINE FROM; the fuel is what LIGHTS
/// BY HAND AND MELTS IT. Neither is a general "best rock": every other species
/// stays a gamble you have to assay.
///
/// **THE MATERIAL IS THE HARDEST SPECIES IN RUNG ZERO THAT CARRIES A FIRST
/// MACHINE**, at the judged grade, ties by lowest id (Game Director's ruling on
/// ASSA-6; ASSA-35; ASSA-170). It used to be `rung0.first()` — roster order, so
/// effectively at random among the hand-minable species — and over 2000 seeds
/// the pick built from it was *slower than the bare hands that built it* in 40%
/// of worlds. Hardness is the only property a head reads, so selecting on
/// anything else was selecting on nothing.
///
/// **AND THEN THE FRAME WAS BUILT FROM THAT SAME PICK, AND A FRAME READS
/// STRENGTH** (ASSA-170, Maren's ruling on ASSA-155: rung zero promises a first
/// *planted machine*). Measured over the same 2000 worlds at [`JUDGED_AT`]: the
/// hardest rung-zero species carried frame + head in 75.6%, and in a further
/// **15.2% another rung-zero species would have** — selection, not scarcity.
/// [`carries_first_machine`] now leads the key, so that 15.2% is taken and the
/// hardness rule decides everything else exactly as before. **It rejects no
/// roster**: where nothing in rung zero carries a machine, every candidate ties
/// on the leading term and the old answer survives untouched. The remaining
/// 9.2% is a world that genuinely holds no first planted machine and is
/// [`starter_roster_ok`]'s question, not this one.
///
/// **HARDNESS STAYS THE TIE-BREAK AND IS NOT DEMOTED TO A HINT.** It is what
/// the first pick's speed reads, and `starter_roster_ok` still refuses a roster
/// whose first pick is slower than bare hands; selecting a softer carrier over
/// a harder one would buy a machine that stands by making the tool that builds
/// it useless. See `docs/design-notes/2026-10-01-hardness-gears-and-alloys.md`.
///
/// **AND THE FUEL IS THE HOTTEST HAND-LIT SPECIES**, at the judged grade, ties
/// by lowest id (ASSA-139). It used to be `species.iter().find(hand_lit_fuel)`
/// — roster order, first match, with nothing asking whether that fuel melts
/// *that* material. The paragraph above says why that is wrong and it was
/// fixed for the material and left on the fuel line: temperature is the only
/// property a fuel's job reads, so selecting on anything else here is again
/// selecting on nothing. Over 2000 worlds the pair could not smelt in 1.8%,
/// and a player following the one path the game guarantees reached a smelter
/// stalled forever at `fire 44 too cool for ore needing 54`.
///
/// Hottest and not merely hot-enough, deliberately: it keeps the pick a
/// best-of-one-property answer like the material's, so neither line needs to
/// know about the other, and [`starter_roster_ok`] can then ask one question
/// — does the best pair this roster affords smelt — instead of searching.
///
/// Ties must break deterministically or two peers disagree about the world.
pub fn starter_species(species: &[MineralSpecies]) -> Option<(SpeciesId, SpeciesId)> {
    let rung0 = rungs(species).into_iter().next()?;
    let material = *rung0.iter().min_by_key(|id| {
        let s = &species[usize::from(id.0)];
        (
            // `Reverse(bool)` puts `true` first, so a carrier outranks a
            // non-carrier and nothing else about the key changes.
            std::cmp::Reverse(carries_first_machine(species, **id, JUDGED_AT)),
            std::cmp::Reverse(s.effective(Property::Hardness, JUDGED_AT)),
            id.0,
        )
    })?;
    let fuel = species
        .iter()
        .filter(|s| hand_lit_fuel(s))
        .min_by_key(|s| (std::cmp::Reverse(burn_temperature(s).unwrap_or(0)), s.id.0))?
        .id;
    Some((material, fuel))
}

/// How fast the demo's first pick mines: a handle and a head, both of
/// `material` at the judged grade.
///
/// **This is the number `step` reads for a held tool**, not a re-derivation
/// of it — it goes through the real `PART_SPECS` row and the real
/// [`Assembly::stats`], so a handle that started contributing speed, or a
/// head row that stopped reading hardness, changes this too. Compare it
/// against [`HAND_WORK_PER_TICK`], which is what `mine_by_hand` uses when a
/// player holds nothing.
pub fn starter_pick_speed(species: &[MineralSpecies], material: SpeciesId) -> u32 {
    let refined = Item::new(ItemKind::Refined, material, JUDGED_AT);
    Assembly::new(
        Part::of(PartKind::Frame(Mount::Held), refined),
        vec![Part::of(PartKind::Head, refined)],
    )
    .stats(species)
    .speed
}

/// Every condition worldgen rerolls a roster until it meets. One place, so
/// the reroll loop and the tests that measure its cost read the same list.
///
/// 1. At least [`MIN_STARTER_RUNGS`] rungs, with a hand-lit fuel — a world
///    nobody can mine or smelt is not a world.
/// 2. **The first pick beats bare hands.** The demo's first build is a pick
///    of the starter species; if it is slower than hands, the loop's first
///    lesson is "do not build". A rate factor cannot fix this, because it is
///    a tail and not a mean: a starter of hardness 5 makes a useless head at
///    any factor.
/// 3. **At least [`MIN_HAND_MINABLE_SPECIES`] species are hand-minable.**
///    With one, assaying is decoration — five property sheets and nothing to
///    compare them against, so no material decision anywhere.
///
/// 4. **The pair actually smelts** — [`pair_smelts`] at [`JUDGED_AT`]
///    (ASSA-139). Rung-zero membership is not this: it is judged against the
///    best walls and the hottest chained fire in the roster, where the pair
///    gets one hand-lit fuel and walls made of the material. With the fuel
///    picked on temperature this rejects a further **0.7%** of rosters, so it
///    is close to free; before that fix the same condition would have rejected
///    1.8%, and rejecting is the wrong fix for a bad pick.
///
/// **WHY [`JUDGED_AT`] IS THE RIGHT GRADE HERE AND NOT GRADE C.** The promise
/// is located, not idealised: `worldgen::deposit_in_chunk` puts the pair in the
/// two `STARTER_CHUNKS` beside spawn with purity floored at
/// `STARTER_MIN_PURITY`, which grades B or better — 0 of 2000 worlds put a
/// guaranteed starter deposit below B. `tests/ladder.rs` pins that floor to
/// this grade, because the whole guarantee rests on the two constants agreeing.
/// Demanding the pair smelt at grade C instead would widen the promise to
/// *every* deposit of those species and costs 22.4% of rosters, measured; that
/// is a different and much more expensive guarantee than the one ADR 0001
/// bought, and the surface fix for a player who walks to a poorer deposit is
/// ASSA-143 (the window naming the grade) rather than deleting those worlds.
///
/// Together these accept 70.9% of rosters that already pass (1), measured
/// over 2000 seeds, and the guarantee is the **starter species only**: every
/// other species stays a gamble you have to assay to read.
pub fn starter_roster_ok(species: &[MineralSpecies]) -> bool {
    let Some((material, fuel)) = starter_species(species) else {
        return false;
    };
    rungs(species).len() >= MIN_STARTER_RUNGS
        && starter_pick_speed(species, material) > HAND_WORK_PER_TICK
        && species.iter().filter(|s| hand_minable(s)).count() >= MIN_HAND_MINABLE_SPECIES
        && pair_smelts(
            &species[usize::from(material.0)],
            &species[usize::from(fuel.0)],
            JUDGED_AT,
        )
}
