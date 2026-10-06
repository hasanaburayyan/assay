//! WHERE THE NEAREST USEFUL ROCK IS — the one spatial question nothing in the
//! game could answer (ASSA-248, from Rainy's "what is nearby that's viable as
//! fuel").
//!
//! Everything else about a species was already here: the six properties rough
//! or exact, who found it, the three mining states, the grade it burns at and
//! whether anything in this world can light it. `species_table` has printed all
//! of that since ASSA-58. **What no surface could say is *where*** — so a
//! player read "fuel at C or better, lights from cold" and then had to go and
//! look for it on the map themselves.
//!
//! **WHY THIS IS IN THE IDENTITY AND `Mining` IS NOT.** `debug.rs` is excluded
//! from `RULES_ID` (`rules_walk::NOT_RULES`) on the ground that it is pure
//! readout — every function takes `&World` and returns a `String`, so prose in
//! it cannot desync anybody. This module returns **data**, not sentences, and
//! the data is geometry: [`walking_ticks`] is the number of ticks
//! `step::move_players` takes to cover a gap. A distance that stopped agreeing
//! with the walk would be a lie about the rules, not a wording change, so it
//! belongs on the rules side of that line and the words for it live in
//! `debug.rs` — the same split `ladder::Lighting` and `debug::lighting_clause`
//! already use.
//!
//! The cost of being in the identity is real and worth saying once: `RULES_ID`
//! moves, so `sim_net::check_join` refuses a peer built from an older commit
//! until both halves are rebuilt. That is the pairing rule the repo already
//! has, and it is the price of the distance being a rule.
//!
//! **NO PER-PLAYER KNOWLEDGE IS ADDED HERE** (Wren's ruling on ASSA-241).
//! Positions are public — `debug::ascii_map` and the client's whole-world view
//! have drawn every deposit and its letter since tick 0 — so proximity leaks
//! nothing the map does not already show. The secret is the *numbers*, and the
//! numbers are gated where they always were, on `MineralSpecies::assayed` in
//! `debug::reading`.

use crate::ladder;
use crate::mineral::{Grade, MineralSpecies, Property, SpeciesId};
use crate::ore::OreDeposit;
use crate::recipe::RECIPES;
use crate::types::{DepositId, TilePos};
use crate::world::World;

/// How many ticks a player needs to walk from `from` to `to`.
///
/// **THIS IS THE MOVEMENT RULE, NOT A DISTANCE METRIC CHOSEN TO LOOK RIGHT.**
/// `step::move_players` adds `signum` to each axis every tick, independently,
/// so a diagonal step costs exactly what a straight one costs and the trip
/// takes `max(|dx|, |dy|)` ticks — Chebyshev. Euclidean or Manhattan would
/// both be wrong here, and wrong in the direction that matters: they would
/// make the headline's "14 tiles" disagree with the fourteen ticks the player
/// then spends.
///
/// `OreDeposit::contains` is Euclidean by contrast, because a deposit is a
/// disc of ore and that is a different question from how long it takes to
/// reach one. The two metrics live side by side on purpose.
pub fn walking_ticks(from: TilePos, to: TilePos) -> u32 {
    (to.x - from.x).abs().max((to.y - from.y).abs()) as u32
}

/// One of the eight ways a walking player can set off.
///
/// **NORTH IS `-y`, AND THAT IS READ OFF THE DRAWN MAP RATHER THAN ASSUMED.**
/// `debug::ascii_map` emits one row per `y`, ascending, so `y` grows *down* the
/// printed map and down the client's view. Nothing in the game said a compass
/// word before this module, so the convention is new; it is this one because it
/// is the only one under which "north" means up on the surface the player is
/// looking at.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Heading {
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
    NorthWest,
}

impl Heading {
    /// The heading of the first step a walk across `(dx, dy)` takes, or `None`
    /// when there is no step to take.
    ///
    /// **IT TAKES THE WHOLE GAP AND SIGNUMS IT ITSELF, which is the movement
    /// system's own arithmetic** (`step::move_players`), so this cannot drift
    /// into a second opinion about which way a player sets off.
    ///
    /// A heading is therefore the direction of the FIRST STEP and not a bearing
    /// to the target: across `(5, 2)` the walk goes south-east twice and then
    /// due east three times. Anything claiming "walk 5 tiles south-east and you
    /// arrive" would be false, which is why [`NearestDeposit`] carries the
    /// `tile` as well — positions are public, so it can.
    pub fn of_gap(dx: i32, dy: i32) -> Option<Heading> {
        match (dx.signum(), dy.signum()) {
            (0, 0) => None,
            (0, -1) => Some(Heading::North),
            (1, -1) => Some(Heading::NorthEast),
            (1, 0) => Some(Heading::East),
            (1, 1) => Some(Heading::SouthEast),
            (0, 1) => Some(Heading::South),
            (-1, 1) => Some(Heading::SouthWest),
            (-1, 0) => Some(Heading::West),
            (-1, -1) => Some(Heading::NorthWest),
            // `signum` returns -1, 0 or 1 and every pair is listed above.
            _ => unreachable!("signum is -1, 0 or 1"),
        }
    }
}

/// A deposit, located: which one, the tile to walk to, how long that walk
/// takes and which way it sets off.
///
/// **THE TILE IS IN HERE BECAUSE A DISTANCE AND A DIRECTION ARE NOT ENOUGH TO
/// ARRIVE.** A walk across a gap that is neither straight nor diagonal changes
/// heading partway (see [`Heading::of_gap`]), so "N tiles north-east" is a true
/// statement about the first step and a false statement about the destination.
/// A caller that wants the player to actually get there sends
/// `PlayerCommand::MoveTo { target: tile }`, and `distance` is then exactly how
/// many ticks that takes. Carrying the tile costs nothing in secrecy: deposit
/// positions have been public since ASSA-73.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct NearestDeposit {
    pub deposit: DepositId,
    /// The tile of this deposit closest to where the player stood.
    pub tile: TilePos,
    /// Ticks of walking to `tile` — see [`walking_ticks`].
    pub distance: u32,
    /// The first step of that walk; `None` when the player is already on it.
    pub heading: Option<Heading>,
}

/// A QUESTION A PLAYER ASKS THE GROUND, as a selector rather than a hardcoded
/// fuel string (Game Director's ruling on ASSA-241: *"fuel is the first
/// question, not the only one"*).
///
/// **THE SELECTOR EXISTS SO THE SECOND QUESTION COSTS NOTHING**, and
/// [`Question::HardEnough`] is here to prove that rather than to be asked yet:
/// a shape claimed by one instance is not a shape. Adding a third means a
/// variant, a [`Question::property`] arm and a sentence in
/// `debug::question_asked`, and the search below does not change.
///
/// **EVERY QUESTION IS JUDGED AT THE GRADE THE DEPOSIT ACTUALLY YIELDS, and
/// that is the whole of ASSA-143 closed.** `fuel_tag` says "fuel at B or
/// better" about a *species*; 18.8% of those rows name a grade above C, so a
/// player who read one, walked to the nearest patch and mined it could feed a
/// smelter that then would not light — no surface having said purity was the
/// variable. Here we know *which* deposit, so the question can be asked of
/// `deposit.grade()` and the gap cannot open.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Question {
    /// Something to burn: fuel at the grade this patch yields, that this world
    /// can light, in rock a player can get out of the ground.
    Burns,
    /// Something hard enough to be worth a part, at the grade this patch
    /// yields.
    HardEnough,
}

impl Question {
    pub const ALL: [Question; 2] = [Question::Burns, Question::HardEnough];

    /// The property the answer turns on.
    ///
    /// Hosts print it through `debug::reading`, which is what keeps box 5 true
    /// by construction: an unassayed species reads as a band there and cannot
    /// read as a number here.
    pub fn property(self) -> Property {
        match self {
            Question::Burns => Property::Reactivity,
            Question::HardEnough => Property::Hardness,
        }
    }

    /// Whether this deposit answers the question.
    ///
    /// **MINABLE AND NOT MINED OUT ARE PART OF EVERY QUESTION**, not a caller's
    /// job to remember. "What near me burns" pointing at a patch whose ore
    /// nothing can break is ASSA-68's defect with a distance attached, and
    /// pointing at a mined-out one is worse: the player walks it and finds
    /// nothing at all.
    ///
    /// Each arm asks `ladder`, which is where these three decisions already
    /// live one-apiece. No comparison is re-spelled here.
    /// This question's tiers, best first. `None` entries are skipped so every
    /// question has the same shape whether or not it ranks.
    ///
    /// **THE RANK IS A PROPERTY OF THE QUESTION, NOT OF THE SEARCH**, so a
    /// caller cannot get a worse answer by forgetting to ask for a better one —
    /// the mistake `nearest_answering` made before ruling 4.
    pub fn tiers(self) -> [Option<Tier>; 2] {
        match self {
            Question::Burns => [Some(Tier::BurnsFromCold), Some(Tier::Burns)],
            Question::HardEnough => [Some(Tier::HardEnough), None],
        }
    }

    /// Whether this deposit answers the question **at any tier**.
    ///
    /// This is the question's own predicate and is what a test should ask when
    /// it means "does this count at all", separately from which tier it lands
    /// in.
    pub fn answered_by(self, species: &[MineralSpecies], d: &OreDeposit) -> bool {
        self.tiers()
            .into_iter()
            .flatten()
            .any(|t| t.keeps(species, d))
    }

    /// Whether this deposit could EVER answer, if its patch were the richest
    /// grade in the game.
    ///
    /// **IT EXISTS TO TELL TWO EMPTY ANSWERS APART** (Game Director, ruling 3):
    /// "nothing in this world burns" and "this world's patches of it are too
    /// poor" are different news, and only one of them is about grade. Asking
    /// the same predicate at `Grade::A` isolates exactly the grade-dependent
    /// half, because every species-level gate (`hand_minable`, `lighting`,
    /// `usable_from_bare_hands`) answers the same at every grade.
    pub fn could_answer_at_best_grade(self, species: &[MineralSpecies], d: &OreDeposit) -> bool {
        self.tiers()
            .into_iter()
            .flatten()
            .any(|t| t.keeps_at(species, d, LADDER_TOP))
    }
}

/// The best grade the refining ladder can reach, and therefore the grade at
/// which "could this ever answer" is asked.
///
/// **IT IS NAMED BECAUSE THE SELECTOR AND THE CONDITION ARE THE SAME QUESTION**
/// (Game Director, ASSA-257). She ruled the too-poor sentence may point at
/// sorting *only* when sorting actually reaches an answering grade — otherwise
/// it is "walk further" relocated: spend ore, end in the same dead end. Asked of
/// the predicate the search already uses, not a second copy of it.
///
/// **AND THAT CONDITION IS ALREADY ENFORCED BY [`Question::could_answer_at_best_grade`],
/// which is the half of her ruling I would otherwise have built twice.**
/// `recipe::Sort` raises one grade and [`Grade::better`] is `C -> B -> A ->
/// None`, so A *is* the ladder's top: "could this patch answer at A" and "can
/// sorting lift this rock to a grade that answers" are one question.
///
/// Three links hold it up, each read rather than assumed:
/// - `keeps_at` takes the grade as a parameter, and every species-level gate in
///   it (`is_depleted`, `hand_minable`, `lighting`, `usable_from_bare_hands`) is
///   grade-independent — so A isolates the grade-dependent half alone.
/// - That half is monotone: `effective_value` multiplies by
///   `GRADE_MULTIPLIER_PERCENT` `[60, 80, 100]` for `[C, B, A]`, strictly
///   ascending, and both deciding properties scale with grade. A is the most
///   favourable grade, so testing at A tests the ladder's best.
/// - The named patch cannot already be A: `too_poor_for` is only reached when no
///   deposit answers at its own grade, so `keeps_at(A)` is true while
///   `keeps_at(own)` is false — hence `own != A`, hence `Grade::better` is
///   `Some` and a sort path genuinely exists.
///
/// **NO MECHANISM IS NEEDED, which makes her ruling stronger than she knew.**
/// She ruled "do not gate it on whether the player owns a sorter"; `Sort` is
/// `Station::Hand`, so there is no sorter to own.
pub const LADDER_TOP: Grade = Grade::A;

/// One rank of answer to a [`Question`].
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tier {
    /// Burns at this patch's grade **and a hand spark lights it**.
    BurnsFromCold,
    /// Burns at this patch's grade; this world can build a fire hot enough,
    /// but you cannot start one from cold.
    Burns,
    /// Hard enough to be worth a part, at this patch's grade.
    HardEnough,
}

impl Tier {
    /// Whether this deposit is in this tier, judged at the patch's own grade.
    pub fn keeps(self, species: &[MineralSpecies], d: &OreDeposit) -> bool {
        self.keeps_at(species, d, d.grade())
    }

    /// As [`Self::keeps`], at an arbitrary grade.
    ///
    /// **THE GRADE IS A PARAMETER SO THE "TOO POOR" ANSWER CANNOT DRIFT FROM
    /// THE REAL ONE.** Deciding emptiness with a second, hand-written copy of
    /// these comparisons is how ASSA-43 and ASSA-52 happened; this is the same
    /// predicate asked a different question.
    pub fn keeps_at(self, species: &[MineralSpecies], d: &OreDeposit, grade: Grade) -> bool {
        if d.is_depleted() {
            return false;
        }
        let s = &species[usize::from(d.species.0)];
        if !ladder::hand_minable(s) {
            return false;
        }
        match self {
            Tier::BurnsFromCold => {
                ladder::burn_temperature_at(s, grade).is_some()
                    && ladder::lighting(species, d.species) == ladder::Lighting::FromCold
            }
            Tier::Burns => {
                ladder::burn_temperature_at(s, grade).is_some()
                    && ladder::lighting(species, d.species)
                        != ladder::Lighting::NothingBurnsHotEnough
            }
            // **"HARD ENOUGH" MEANS HARD ENOUGH TO BECOME SOMETHING, so the ore
            // has to go somewhere** — and my first version asked only
            // `hand_minable`, which is ASSA-52's defect rebuilt on a new
            // surface. `sim-cli/tests/unsmeltable.rs` caught it: on seed 10027
            // the player SPAWNS on Meline, grade A, purity 80, the best yield on
            // the map and hard enough for a gear — with a heat tolerance no fire
            // a player can light will ever reach. It is scenery. My headline
            // told them to go and mine it, which is the two hundred wasted ore
            // that sentence was written to prevent.
            //
            // `usable_from_bare_hands` is rung zero and the same authority the
            // test states its own premise with, so this re-derives nothing.
            Tier::HardEnough => {
                ladder::usable_from_bare_hands(species, d.species)
                    && required_at_least(Property::Hardness)
                        .is_some_and(|min| s.effective(Property::Hardness, grade) >= min)
            }
        }
    }
}

/// The lowest threshold any recipe in the game sets on `property`, or `None`
/// when nothing asks for it.
///
/// **READ OUT OF `RECIPES`, NEVER TYPED HERE.** "Hard enough" means hard enough
/// for the easiest thing that cares, and the easiest thing that cares is a fact
/// about the recipe table — `GEAR_MIN_HARDNESS` today, whatever the table says
/// tomorrow. A constant copied into this file would answer yesterday's question
/// with a straight face, which is how ASSA-43 and ASSA-52 happened.
fn required_at_least(property: Property) -> Option<u32> {
    RECIPES
        .iter()
        .flat_map(|r| r.requires)
        .filter(|(p, _)| *p == property)
        .map(|(_, min)| *min)
        .min()
}

impl World {
    /// The nearest patch of this species that still holds ore, from `from`.
    ///
    /// **"ORE" AND NOT "DEPOSIT", because a mined-out patch is not a place to
    /// walk to.** It is still a deposit, still drawn on the map in lower case
    /// (`debug::ascii_map`), and still the wrong answer to every question a
    /// player asks with their feet.
    pub fn nearest_ore_of(&self, species: SpeciesId, from: TilePos) -> Option<NearestDeposit> {
        self.nearest(from, |d| d.species == species && !d.is_depleted())
    }

    /// The nearest patch that answers `question`, from `from`, **best tier
    /// first**.
    ///
    /// **A NEARER PATCH YOU CANNOT LIGHT IS WORSE THAN A FURTHER ONE YOU CAN**
    /// (Game Director, ASSA-248 ruling 4). `Burns` has two tiers: a patch that
    /// lights from cold, else one that needs a hotter fire. Handing a fireless
    /// player the nearest patch they cannot light sends them back to the table
    /// this headline exists to replace — `debug.rs` records that we *trained*
    /// them to scan for "lights from cold" (ASSA-58).
    ///
    /// **IT STRICTLY DOMINATES, which is why there was no trade to weigh.** The
    /// tiers can only disagree in a world that HAS a cold-lightable mineable
    /// patch; in the 56.3% that can never light anything, tier 1 is empty and
    /// this returns exactly what one flat search returned. Never worse, decisive
    /// when it matters, and grade-independent: `HAND_SPARK_TEMPERATURE` is fixed
    /// and heat tolerance never scales with grade, so ranking does not interact
    /// with the patch-grade judgement at all.
    ///
    /// Distance still decides WITHIN a tier, so this is not "furthest
    /// lightable" — it is the nearest of the better kind.
    pub fn nearest_answering(&self, question: Question, from: TilePos) -> Option<NearestDeposit> {
        question
            .tiers()
            .into_iter()
            .flatten()
            .find_map(|tier| self.nearest(from, |d| tier.keeps(&self.species, d)))
    }

    /// When nothing answers `question`, the species whose patches are merely
    /// **too poor** — or `None` when no species in this world could ever
    /// answer at any grade.
    ///
    /// **IT SEPARATES TWO EMPTY ANSWERS THAT ARE DIFFERENT NEWS** (Game
    /// Director, ASSA-248 ruling 3): judging at the patch's own grade makes the
    /// empty sentence fire in worlds where the species table still truthfully
    /// reads "fuel at B or better", and an answer its own evidence appears to
    /// contradict reads as a bug. Only one of the two states is about grade.
    ///
    /// **AND THE ACTION THE RULING IMPLIED IS NOT AVAILABLE — see the caller.**
    /// Ties break on deposit order, which is worldgen's chunk order, so two
    /// peers name the same species.
    pub fn too_poor_for(&self, question: Question) -> Option<SpeciesId> {
        self.deposits
            .iter()
            .find(|d| question.could_answer_at_best_grade(&self.species, d))
            .map(|d| d.species)
    }

    /// Nearest kept deposit, ties by lowest id.
    ///
    /// **TIES MUST BREAK DETERMINISTICALLY OR TWO PEERS DISAGREE ABOUT THE
    /// WORLD** — the same reason `ladder::starter_species` breaks its ties by
    /// id. Deposits are iterated in `World::deposits` order, which is worldgen's
    /// chunk order, and a strict `<` keeps the first of equals.
    fn nearest(&self, from: TilePos, keep: impl Fn(&OreDeposit) -> bool) -> Option<NearestDeposit> {
        let mut best: Option<NearestDeposit> = None;
        for d in &self.deposits {
            if !keep(d) {
                continue;
            }
            let Some((tile, distance)) = self.nearest_tile_of(d, from) else {
                continue;
            };
            if best.is_some_and(|b| distance >= b.distance) {
                continue;
            }
            best = Some(NearestDeposit {
                deposit: d.id,
                tile,
                distance,
                heading: Heading::of_gap(tile.x - from.x, tile.y - from.y),
            });
        }
        best
    }

    /// The tile of this deposit a player would walk to, and the ticks it takes.
    ///
    /// **THE DISC IS SCANNED RATHER THAN SOLVED.** Clamping `from` into a circle
    /// is a closed-form I would get wrong at the rim, and the whole scan is at
    /// most 81 tiles (`radius` is 2–4 by ADR 0001). Row-major with a strict `<`
    /// settles ties on the lowest `(y, x)`, so the answer does not depend on
    /// iteration luck.
    ///
    /// Tiles off the map are skipped: a deposit centred near an edge has a disc
    /// that runs past it, and no player can stand there.
    fn nearest_tile_of(&self, d: &OreDeposit, from: TilePos) -> Option<(TilePos, u32)> {
        let r = i32::from(d.radius);
        let mut best: Option<(TilePos, u32)> = None;
        for y in (d.center.y - r)..=(d.center.y + r) {
            for x in (d.center.x - r)..=(d.center.x + r) {
                let tile = TilePos::new(x, y);
                if !d.contains(tile) || !self.in_bounds(tile) {
                    continue;
                }
                let distance = walking_ticks(from, tile);
                if best.is_some_and(|(_, b)| distance >= b) {
                    continue;
                }
                best = Some((tile, distance));
            }
        }
        best
    }
}
