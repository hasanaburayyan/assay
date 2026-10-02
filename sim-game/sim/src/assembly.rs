//! Machines built from parts: one catalogue table, and every stat a sum
//! (ADR 0003).
//!
//! A machine is a frame plus the parts mounted on it. Each part is a kind and
//! its own material, and what a part does to the machine's stats is a row of
//! data, not a branch of code. There are no machine recipes: a pick and a
//! drill differ only in which frame they carry and what is mounted on it.
//!
//! **Nothing here refuses an assembly for being too heavy.** Decision 11 puts
//! that test at placement, and an earlier refusal would make the frame budget
//! invisible. [`AssemblyError`] has no overweight variant on purpose.

use serde::{Deserialize, Serialize};

use crate::item::{Item, ItemKind};
use crate::mineral::{Grade, MineralSpecies, Property, Sheet};
use crate::rng::Rng;
use crate::tuning;

/// Whether a frame is carried in the hand or planted on the map. The only
/// thing a tool and a machine differ by (decision 6): the handle of a pick
/// *is* its frame, held instead of planted.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Mount {
    Held,
    Planted,
}

/// What a part is. Three kinds, and the slot a part fills is named by its
/// kind, so there is no separate slot type: a new kind names a new slot.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum PartKind {
    Head,
    Frame(Mount),
    Hopper,
}

impl PartKind {
    /// Every catalogue row. Three kinds, four rows: the frame's mount is a
    /// variant of one kind, not a fourth kind.
    pub const ALL: [PartKind; 4] = [
        PartKind::Head,
        PartKind::Frame(Mount::Held),
        PartKind::Frame(Mount::Planted),
        PartKind::Hopper,
    ];

    pub const fn is_frame(self) -> bool {
        matches!(self, PartKind::Frame(_))
    }

    pub fn name(self) -> &'static str {
        spec(self).name
    }

    /// What players type. Names come from the catalogue, so a new row is
    /// parseable without touching this.
    pub fn parse(s: &str) -> Option<PartKind> {
        let s = s.to_ascii_lowercase();
        PART_SPECS
            .iter()
            .find(|spec| spec.name == s)
            .map(|spec| spec.kind)
    }
}

/// One number a machine has. Every stat is the sum of its parts'
/// contributions, which is what makes a second hopper work with no new code.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Stat {
    /// What the design weighs. Checked against `Budget` at placement.
    Mass,
    /// How much mass the frame carries before it breaks.
    Budget,
    /// Work done per tick while mining (ASSA-6 turns this into ore).
    Speed,
    /// Durability pool, drained per swing on a held tool only.
    Durability,
    /// Ore the machine can hold before it stalls.
    Capacity,
}

impl Stat {
    pub const ALL: [Stat; 5] = [
        Stat::Mass,
        Stat::Budget,
        Stat::Speed,
        Stat::Durability,
        Stat::Capacity,
    ];
}

/// Where a contribution's number comes from.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Source {
    /// The part's own material, at its grade, times the part's size.
    Property(Property),
    /// A fixed amount from the kind, unscaled by material or size.
    Flat(u32),
}

/// One thing a part does to a machine. `contribute` is the only reader, and
/// it matches on [`Source`] and never on [`PartKind`] — that is the rule that
/// keeps this a model rather than a catalogue of special cases.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Contribution {
    pub stat: Stat,
    pub source: Source,
    pub factor: u32,
}

/// How many parts of one kind a frame accepts.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct SlotLimit {
    pub kind: PartKind,
    pub min: u32,
    pub max: u32,
}

/// One row of the part catalogue.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct PartSpec {
    pub kind: PartKind,
    /// What players type.
    pub name: &'static str,
    /// One number meaning two things: what the part costs in refined
    /// material, and how much stuff it is made of for mass. A part cannot be
    /// cheap and heavy.
    pub size: u32,
    pub contributions: &'static [Contribution],
    /// Slots this part offers to others. Only a frame offers any.
    pub slots: &'static [SlotLimit],
}

const fn from_property(stat: Stat, property: Property, factor: u32) -> Contribution {
    Contribution {
        stat,
        source: Source::Property(property),
        factor,
    }
}

const fn flat(stat: Stat, amount: u32) -> Contribution {
    Contribution {
        stat,
        source: Source::Flat(amount),
        factor: 1,
    }
}

/// Every part the demo ships. A new part is a row here and nothing else; a
/// new machine is a frame row with different slots.
pub const PART_SPECS: [PartSpec; 4] = [
    PartSpec {
        kind: PartKind::Head,
        name: "head",
        size: tuning::HEAD_SIZE,
        // Hardness buys speed, strength buys life, and neither ever reads
        // the other: a hard but weak species is fast and fragile.
        contributions: &[
            from_property(Stat::Mass, Property::Density, 1),
            from_property(
                Stat::Speed,
                Property::Hardness,
                tuning::HEAD_SPEED_PER_HARDNESS,
            ),
            from_property(
                Stat::Durability,
                Property::Strength,
                tuning::PICK_DURABILITY_PER_STRENGTH,
            ),
        ],
        slots: &[],
    },
    PartSpec {
        kind: PartKind::Frame(Mount::Held),
        name: "handle",
        size: tuning::HELD_FRAME_SIZE,
        contributions: &[
            from_property(Stat::Mass, Property::Density, 1),
            from_property(
                Stat::Budget,
                Property::Strength,
                tuning::FRAME_BUDGET_PER_STRENGTH,
            ),
        ],
        // A held frame offers no hopper slot at all, so a hopper on one is
        // "no such slot" rather than "too many".
        slots: &[SlotLimit {
            kind: PartKind::Head,
            min: 1,
            max: 1,
        }],
    },
    PartSpec {
        kind: PartKind::Frame(Mount::Planted),
        name: "frame",
        size: tuning::PLANTED_FRAME_SIZE,
        contributions: &[
            from_property(Stat::Mass, Property::Density, 1),
            from_property(
                Stat::Budget,
                Property::Strength,
                tuning::FRAME_BUDGET_PER_STRENGTH,
            ),
            flat(Stat::Capacity, tuning::PLANTED_FRAME_BUFFER),
        ],
        slots: &[
            SlotLimit {
                kind: PartKind::Head,
                min: 1,
                max: 1,
            },
            // Generous on purpose: mass is what stops you stacking hoppers,
            // not a slot count.
            SlotLimit {
                kind: PartKind::Hopper,
                min: 0,
                max: tuning::MAX_HOPPER_SLOTS,
            },
        ],
    },
    PartSpec {
        kind: PartKind::Hopper,
        name: "hopper",
        size: tuning::HOPPER_SIZE,
        // Material sets mass only. Capacity is flat from the kind, so hopper
        // species is one legible choice: make it light.
        contributions: &[
            from_property(Stat::Mass, Property::Density, 1),
            flat(Stat::Capacity, tuning::HOPPER_CAPACITY),
        ],
        slots: &[],
    },
];

/// The catalogue row for a kind.
pub fn spec(kind: PartKind) -> &'static PartSpec {
    PART_SPECS
        .iter()
        .find(|s| s.kind == kind)
        .expect("every PartKind has a catalogue row")
}

/// A part: what it is, and what it is made of. The material is a `Refined`
/// item, so it carries a species and a grade.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Part {
    pub kind: PartKind,
    pub material: Item,
}

impl Part {
    pub const fn new(kind: PartKind, material: Item) -> Self {
        Self { kind, material }
    }

    /// A part made of `material`'s species and grade. The material of a part
    /// is always refined, whatever kind of item it was named by.
    pub const fn of(kind: PartKind, material: Item) -> Self {
        Self::new(
            kind,
            Item::new(ItemKind::Refined, material.species, material.grade),
        )
    }

    /// This part as an inventory item. Round-trips with [`Part::from_item`].
    pub const fn as_item(&self) -> Item {
        Item::new(
            ItemKind::Part(self.kind),
            self.material.species,
            self.material.grade,
        )
    }

    /// The part an item is, or `None` if the item is not a part.
    pub fn from_item(item: Item) -> Option<Part> {
        item.kind.part().map(|kind| Part::of(kind, item))
    }

    /// What this part costs in refined material, which is also how much
    /// stuff it is made of for mass.
    pub fn size(&self) -> u32 {
        spec(self.kind).size
    }

    /// The refined material one of these is made from.
    pub const fn refined(&self) -> Item {
        self.material
    }
}

/// Every stat of one assembly.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct MachineStats {
    pub mass: u32,
    pub budget: u32,
    pub speed: u32,
    pub durability: u32,
    pub capacity: u32,
}

impl MachineStats {
    pub const fn get(&self, stat: Stat) -> u32 {
        match stat {
            Stat::Mass => self.mass,
            Stat::Budget => self.budget,
            Stat::Speed => self.speed,
            Stat::Durability => self.durability,
            Stat::Capacity => self.capacity,
        }
    }

    fn add(&mut self, stat: Stat, amount: u32) {
        let slot = match stat {
            Stat::Mass => &mut self.mass,
            Stat::Budget => &mut self.budget,
            Stat::Speed => &mut self.speed,
            Stat::Durability => &mut self.durability,
            Stat::Capacity => &mut self.capacity,
        };
        *slot = slot.saturating_add(amount);
    }

    /// Whether this design breaks when it is placed, or first used if it is
    /// held (decision 11). Nothing else in the sim asks this question.
    pub const fn is_overweight(&self) -> bool {
        self.mass > self.budget
    }
}

/// Add one part's contributions to `stats`.
///
/// Takes a [`PartSpec`] rather than a [`PartKind`] so that a spec which is
/// not in [`PART_SPECS`] works identically — that is how the model's
/// generality is tested rather than asserted. It matches on [`Source`] and
/// never on the kind.
pub fn contribute(
    spec: &PartSpec,
    material: Item,
    species: &MineralSpecies,
    stats: &mut MachineStats,
) {
    contribute_reading(spec, &|p| species.effective(p, material.grade), stats);
}

/// [`contribute`] over an arbitrary way of reading a property, which is what
/// lets the same arithmetic produce both exact stats and the ends of a banded
/// one. The only reader of [`Source`], and it still never sees a [`PartKind`].
fn contribute_reading(spec: &PartSpec, read: &dyn Fn(Property) -> u32, stats: &mut MachineStats) {
    for c in spec.contributions {
        let amount = match c.source {
            Source::Property(p) => spec.size * read(p) * c.factor,
            Source::Flat(n) => n,
        };
        stats.add(c.stat, amount);
    }
}

/// What a player can actually read of a material's property, as (low, high):
/// exact once the species has been assayed, and the two ends of its
/// `SHEET_BAND` band before that.
///
/// Both ends go through [`Property::effective_value`], per the Game Director's
/// ruling on ASSA-5: scaling a band afterwards disagrees with the sim's own
/// numbers at low values.
pub fn reading(species: &MineralSpecies, property: Property, grade: Grade) -> (u32, u32) {
    if species.assayed {
        let exact = species.effective(property, grade);
        return (exact, exact);
    }
    let (low, high) = Sheet::band(species.sheet.get(property));
    (
        property.effective_value(u32::from(low), grade),
        property.effective_value(u32::from(high), grade),
    )
}

/// Every stat of an assembly as the range a player can read it in. Exact
/// species give `low == high`.
///
/// Sound because every contribution is non-decreasing in its reading: reading
/// each property at the low end of its band therefore bounds every stat from
/// below, and the high end bounds every stat from above.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct StatRange {
    pub low: MachineStats,
    pub high: MachineStats,
}

/// Whether a design will break when it is placed, as far as the player can
/// tell from what they have read so far.
///
/// Three states and not a percentage (Game Director's ruling on ASSA-5): this
/// verdict is never wrong, so a player learns to trust it in one session,
/// where "62%" is not actionable and invites them to re-derive it. The
/// numbers are shown underneath for anyone who wants them.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum BreakVerdict {
    /// The heaviest this can be still fits the smallest budget it can have.
    Safe,
    /// The ranges overlap. Only an assay resolves it.
    Uncertain,
    /// The lightest this can be already exceeds the largest budget.
    WillBreak,
}

impl BreakVerdict {
    pub const fn label(self) -> &'static str {
        match self {
            BreakVerdict::Safe => "SAFE",
            BreakVerdict::Uncertain => "UNCERTAIN",
            BreakVerdict::WillBreak => "WILL BREAK",
        }
    }
}

impl StatRange {
    pub const fn verdict(&self) -> BreakVerdict {
        if self.high.mass <= self.low.budget {
            BreakVerdict::Safe
        } else if self.low.mass > self.high.budget {
            BreakVerdict::WillBreak
        } else {
            BreakVerdict::Uncertain
        }
    }
}

/// What is left of a design that broke: the parts handed back, and the parts
/// gone for good. Both in the assembly's part order.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct BreakOutcome {
    pub returned: Vec<Item>,
    pub lost: Vec<Item>,
}

/// A machine: a frame and the parts mounted on it.
///
/// Part order is the frame first, then the mounted parts in the order they
/// were given. Every rule that has to pick a part (the break roll, the lost
/// part) walks that order, so two peers can never disagree.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Assembly {
    pub frame: Part,
    pub mounted: Vec<Part>,
}

/// A machine a player has built: the assembly plus the state that follows it
/// around whether it is in hand or on the built list.
///
/// `durability` is established **when the machine is built**, not when it is
/// equipped, so putting a worn tool down and taking it up again cannot refill
/// its pool. Only a held frame ever drains it (decision 12 parks drill wear),
/// and planting a machine drops it for the same reason.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Built {
    pub assembly: Assembly,
    /// Durability left. ASSA-6 drains it per swing.
    pub durability: u32,
}

impl Built {
    /// A machine fresh off the assembly, with a full pool.
    pub fn new(assembly: Assembly, species: &[MineralSpecies]) -> Self {
        let durability = assembly.stats(species).durability;
        Self {
            assembly,
            durability,
        }
    }
}

/// Why an assembly was refused. **There is no overweight variant**: the sim
/// never refuses a design for its mass (decision 11).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AssemblyError {
    /// The frame position got something that is not a frame.
    FrameIsNotAFrame,
    /// A frame cannot be mounted on another frame.
    FrameMounted,
    /// This frame offers no slot for that kind at all.
    NoSuchSlot(PartKind),
    TooFew {
        kind: PartKind,
        have: u32,
        min: u32,
    },
    TooMany {
        kind: PartKind,
        have: u32,
        max: u32,
    },
}

impl Assembly {
    pub fn new(frame: Part, mounted: Vec<Part>) -> Self {
        Self { frame, mounted }
    }

    /// The frame first, then the mounted parts: the one canonical order.
    pub fn parts(&self) -> impl Iterator<Item = &Part> {
        std::iter::once(&self.frame).chain(self.mounted.iter())
    }

    pub fn part_count(&self) -> usize {
        1 + self.mounted.len()
    }

    /// Held or planted, from the frame alone.
    pub fn mount(&self) -> Option<Mount> {
        match self.frame.kind {
            PartKind::Frame(mount) => Some(mount),
            _ => None,
        }
    }

    /// Whether the parts fit the frame's slots. Mass is never consulted.
    pub fn validate(&self) -> Result<(), AssemblyError> {
        if !self.frame.kind.is_frame() {
            return Err(AssemblyError::FrameIsNotAFrame);
        }
        let frame = spec(self.frame.kind);
        for part in &self.mounted {
            if part.kind.is_frame() {
                return Err(AssemblyError::FrameMounted);
            }
            if !frame.slots.iter().any(|s| s.kind == part.kind) {
                return Err(AssemblyError::NoSuchSlot(part.kind));
            }
        }
        for limit in frame.slots {
            let have = self.mounted.iter().filter(|p| p.kind == limit.kind).count() as u32;
            if have < limit.min {
                return Err(AssemblyError::TooFew {
                    kind: limit.kind,
                    have,
                    min: limit.min,
                });
            }
            if have > limit.max {
                return Err(AssemblyError::TooMany {
                    kind: limit.kind,
                    have,
                    max: limit.max,
                });
            }
        }
        Ok(())
    }

    /// Every stat, summed over the parts.
    pub fn stats(&self, species: &[MineralSpecies]) -> MachineStats {
        let mut stats = MachineStats::default();
        for part in self.parts() {
            let s = &species[part.material.species.0 as usize];
            contribute(spec(part.kind), part.material, s, &mut stats);
        }
        stats
    }

    /// What one part weighs on its own: size times its material's density,
    /// which never scales with grade, so grade does not change what a design
    /// weighs.
    pub fn part_mass(part: &Part, species: &MineralSpecies) -> u32 {
        let mut stats = MachineStats::default();
        contribute(spec(part.kind), part.material, species, &mut stats);
        stats.mass
    }

    /// What one part weighs as a player can read it: exact once its species is
    /// assayed, the two ends of its density band before that.
    ///
    /// The banded twin of [`Assembly::part_mass`], and the per-part half of
    /// [`Assembly::stat_range`] — a menu that lists the parts under a banded
    /// total needs rows that add up to it, and a row showing an exact mass for
    /// a species still reading rough would invent certainty the sim does not
    /// have. Density never scales with grade, so assaying is the only thing
    /// that narrows this.
    pub fn part_mass_range(part: &Part, species: &MineralSpecies) -> (u32, u32) {
        let mut low = MachineStats::default();
        let mut high = MachineStats::default();
        let s = spec(part.kind);
        let grade = part.material.grade;
        contribute_reading(s, &|p| reading(species, p, grade).0, &mut low);
        contribute_reading(s, &|p| reading(species, p, grade).1, &mut high);
        (low.mass, high.mass)
    }

    /// Refined material the whole design costs, which is the sum of sizes.
    pub fn refined_cost(&self) -> u32 {
        self.parts().map(|p| spec(p.kind).size).sum()
    }

    /// Every stat as the range a player can read it in, banded per part from
    /// that part's own species — so a mixed-species design is two sheets and
    /// two bands with no special case.
    pub fn stat_range(&self, species: &[MineralSpecies]) -> StatRange {
        let mut range = StatRange {
            low: MachineStats::default(),
            high: MachineStats::default(),
        };
        for part in self.parts() {
            let s = &species[part.material.species.0 as usize];
            let grade = part.material.grade;
            let spec = spec(part.kind);
            contribute_reading(spec, &|p| reading(s, p, grade).0, &mut range.low);
            contribute_reading(spec, &|p| reading(s, p, grade).1, &mut range.high);
        }
        range
    }

    /// Every part as an inventory item, in part order.
    pub fn part_items(&self) -> Vec<Item> {
        self.parts().map(Part::as_item).collect()
    }

    /// Take this design apart after it broke: the always-lost part goes, and
    /// every other part comes back on a `BREAK_RETURN_PERCENT` roll
    /// (ADR 0003 point 10, amended by A1).
    ///
    /// **Exactly one `rng` call per part, in part order, on every path** —
    /// including for the part that was always going to be lost. Rolling only
    /// for the parts whose fate is undecided would make the number of draws
    /// depend on which part happened to be heaviest, and two peers would
    /// walk the rng stream at different rates and desync.
    pub fn break_apart(&self, species: &[MineralSpecies], rng: &mut Rng) -> BreakOutcome {
        let always_lost = self.part_always_lost(species);
        let mut outcome = BreakOutcome::default();
        for (i, part) in self.parts().enumerate() {
            let returns = rng.range(0, 100) < tuning::BREAK_RETURN_PERCENT;
            if i == always_lost || !returns {
                outcome.lost.push(part.as_item());
            } else {
                outcome.returned.push(part.as_item());
            }
        }
        outcome
    }

    /// The part a break always loses, as an index into [`Assembly::parts`].
    ///
    /// **The heaviest part that is not the frame** (ADR 0003 amendment A1),
    /// ties going to the lowest index so peers agree. With nothing mounted,
    /// the frame itself is lost. The whole rule is this function, so moving
    /// it back to "the heaviest part, frame included" is one line.
    pub fn part_always_lost(&self, species: &[MineralSpecies]) -> usize {
        let heaviest = self
            .mounted
            .iter()
            .enumerate()
            .max_by_key(|(i, p)| {
                let s = &species[p.material.species.0 as usize];
                // Negate the index so an earlier part wins a tie.
                (Self::part_mass(p, s), std::cmp::Reverse(*i))
            })
            .map(|(i, _)| i + 1);
        heaviest.unwrap_or(0)
    }
}
