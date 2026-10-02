//! The assembly model of ADR 0003: one catalogue table, every stat a sum.
//!
//! These tests are deliberately written so that **no test names a part
//! kind it does not have to**. The catalogue tests loop over
//! `PartKind::ALL`, so a part kind added later joins them without being
//! written into them — which is the difference between a small catalogue
//! and a small model.

use sim::assembly::{Source, contribute, spec};
use sim::mineral::Sheet;
use sim::{
    Assembly, AssemblyError, Contribution, Grade, Item, ItemKind, MachineStats, MineralSpecies,
    Mount, PART_SPECS, Part, PartKind, PartSpec, Property, SpeciesId, Stat, tuning,
};

/// A species with the three properties parts read, and middling values for
/// the three they do not.
fn species(id: u8, density: u8, strength: u8, hardness: u8) -> MineralSpecies {
    MineralSpecies {
        id: SpeciesId(id),
        generated_name: format!("s{id}"),
        player_name: None,
        discoverer: None,
        rename_grants: Vec::new(),
        assayed: true,
        sheet: Sheet {
            density,
            strength,
            hardness,
            heat_tolerance: 50,
            reactivity: 50,
            conductivity: 50,
        },
    }
}

/// Index 0 is middling in every property; index 1 is the same but dense.
fn roster() -> Vec<MineralSpecies> {
    vec![species(0, 50, 50, 50), species(1, 90, 50, 50)]
}

fn part(kind: PartKind, species: u8, grade: Grade) -> Part {
    Part::new(
        kind,
        Item::new(ItemKind::Refined, SpeciesId(species), grade),
    )
}

const HELD: PartKind = PartKind::Frame(Mount::Held);
const PLANTED: PartKind = PartKind::Frame(Mount::Planted);

/// A pick: a head on a held frame, all of one species.
fn pick(species: u8, grade: Grade) -> Assembly {
    Assembly::new(
        part(HELD, species, grade),
        vec![part(PartKind::Head, species, grade)],
    )
}

/// A drill: a head and `hoppers` hoppers on a planted frame.
fn drill(species: u8, grade: Grade, hoppers: u32) -> Assembly {
    let mut mounted = vec![part(PartKind::Head, species, grade)];
    for _ in 0..hoppers {
        mounted.push(part(PartKind::Hopper, species, grade));
    }
    Assembly::new(part(PLANTED, species, grade), mounted)
}

/// Decision 5's test, second half: "adding a second hopper changes capacity
/// without a new recipe." Written as a loop over every hopper count the
/// frame allows, because the claim is about the model and not about two.
#[test]
fn every_extra_hopper_raises_capacity_and_mass_with_no_new_code() {
    let roster = roster();
    let max = tuning::MAX_HOPPER_SLOTS;
    assert!(max >= 2, "the claim is about a *second* hopper");

    let mut previous = MachineStats::default();
    for hoppers in 0..=max {
        let d = drill(0, Grade::B, hoppers);
        d.validate()
            .unwrap_or_else(|e| panic!("{hoppers} hoppers should fit the frame's slots: {e:?}"));
        let stats = d.stats(&roster);
        if hoppers > 0 {
            assert!(
                stats.capacity > previous.capacity,
                "{hoppers} hoppers: capacity {} did not rise above {}",
                stats.capacity,
                previous.capacity
            );
            assert!(
                stats.mass > previous.mass,
                "{hoppers} hoppers: mass {} did not rise above {}",
                stats.mass,
                previous.mass
            );
            // The budget comes from the frame alone, so stacking hoppers
            // cannot buy the capacity to carry them.
            assert_eq!(stats.budget, previous.budget);
        }
        previous = stats;
    }

    // ...and mass, not a slot count, is what stops you (ADR 0003 pt 12).
    assert!(
        drill(0, Grade::B, max).stats(&roster).is_overweight(),
        "a full rack of hoppers should break the frame, or the budget is not the limit"
    );
}

/// Decision 10's test, both halves.
#[test]
fn a_denser_head_weighs_more_and_a_stronger_frame_carries_more() {
    let roster = roster();

    // Two drills identical except for the head's species.
    let light = drill(0, Grade::B, 1);
    let heavy = Assembly::new(
        part(PLANTED, 0, Grade::B),
        vec![
            part(PartKind::Head, 1, Grade::B),
            part(PartKind::Hopper, 0, Grade::B),
        ],
    );
    assert!(
        heavy.stats(&roster).mass > light.stats(&roster).mass,
        "a denser head must weigh more"
    );
    assert_eq!(
        heavy.stats(&roster).budget,
        light.stats(&roster).budget,
        "the head must not change the budget"
    );

    // A frame of a stronger species carries more.
    let roster = vec![species(0, 50, 20, 50), species(1, 50, 80, 50)];
    let weak = Assembly::new(
        part(HELD, 0, Grade::B),
        vec![part(PartKind::Head, 0, Grade::B)],
    );
    let strong = Assembly::new(
        part(HELD, 1, Grade::B),
        vec![part(PartKind::Head, 0, Grade::B)],
    );
    assert!(strong.stats(&roster).budget > weak.stats(&roster).budget);
    assert_eq!(
        strong.stats(&roster).mass,
        weak.stats(&roster).mass,
        "strength must not change what a design weighs"
    );
}

/// Decision 11, and the rule I was told to build nowhere: the sim never
/// refuses a design for its mass. An overweight assembly is **valid**; it
/// just breaks when it is placed.
#[test]
fn an_overweight_design_is_still_a_valid_assembly() {
    let roster = roster();
    let doomed = pick(1, Grade::B);
    assert_eq!(doomed.validate(), Ok(()));
    assert!(
        doomed.stats(&roster).is_overweight(),
        "the dense-species pick should be the overweight case"
    );
}

/// The frame decides which slots exist, so a hopper on a held frame is "no
/// such slot" rather than "too many".
#[test]
fn the_frame_decides_which_slots_exist() {
    let hopper = part(PartKind::Hopper, 0, Grade::B);
    let head = part(PartKind::Head, 0, Grade::B);

    let held_with_hopper = Assembly::new(part(HELD, 0, Grade::B), vec![head, hopper]);
    assert_eq!(
        held_with_hopper.validate(),
        Err(AssemblyError::NoSuchSlot(PartKind::Hopper))
    );

    let bare_frame = Assembly::new(part(PLANTED, 0, Grade::B), vec![]);
    assert_eq!(
        bare_frame.validate(),
        Err(AssemblyError::TooFew {
            kind: PartKind::Head,
            have: 0,
            min: 1
        })
    );

    let too_many = drill(0, Grade::B, tuning::MAX_HOPPER_SLOTS + 1);
    assert!(matches!(
        too_many.validate(),
        Err(AssemblyError::TooMany { .. })
    ));

    let frame_on_frame = Assembly::new(
        part(PLANTED, 0, Grade::B),
        vec![head, part(HELD, 0, Grade::B)],
    );
    assert_eq!(frame_on_frame.validate(), Err(AssemblyError::FrameMounted));

    let headless = Assembly::new(head, vec![]);
    assert_eq!(headless.validate(), Err(AssemblyError::FrameIsNotAFrame));
}

/// Amendment A1: the part a break loses is the heaviest that is **not** the
/// frame, ties going to the lowest index so two peers cannot disagree.
#[test]
fn the_lost_part_is_the_heaviest_that_is_not_the_frame() {
    let roster = roster();

    // The frame is the heaviest part of both demo designs, which is the whole
    // reason for the amendment. Assert that premise rather than trusting it.
    for a in [pick(0, Grade::B), drill(0, Grade::B, 1)] {
        let frame_mass = Assembly::part_mass(&a.frame, &roster[0]);
        assert!(
            a.mounted
                .iter()
                .all(|p| Assembly::part_mass(p, &roster[0]) < frame_mass),
            "the frame is supposed to be the heaviest part here"
        );
        // Resolve the index to the part it names, rather than trusting that
        // index 0 means the frame: a mutation that renumbered the parts
        // slipped past the index form of this assertion.
        let lost = a
            .parts()
            .nth(a.part_always_lost(&roster))
            .expect("the lost index must name a part of this assembly");
        assert!(
            !lost.kind.is_frame(),
            "the frame must not be the part lost, got {:?}",
            lost.kind
        );
    }

    // Of the mounted parts, the heaviest goes: the hopper (size 2) over the
    // head (size 1).
    let d = drill(0, Grade::B, 1);
    assert_eq!(d.part_always_lost(&roster), 2);

    // A tie between two identical hoppers goes to the lower index.
    let two = drill(0, Grade::B, 2);
    assert_eq!(two.part_always_lost(&roster), 2);

    // Defensive, and unreachable through `validate` today because every
    // frame demands a head: with nothing mounted, the frame is lost.
    let bare = Assembly::new(part(PLANTED, 0, Grade::B), vec![]);
    assert_eq!(bare.part_always_lost(&roster), 0);
}

/// A1's consequence, pinned so it is never read later as a bug: a pick has
/// exactly two parts, so the head is **always** the part lost — at any
/// density, including pairings where the head out-weighs the frame. Intended:
/// the head is the size-1 piece. The mass lesson lives in drills, where which
/// non-frame part is heaviest does vary with density.
#[test]
fn a_picks_lost_part_is_always_the_head() {
    let mut saw_a_heavier_head = false;
    for (frame_density, head_density) in [(50, 50), (99, 1), (1, 99)] {
        let roster = vec![
            species(0, frame_density, 50, 50),
            species(1, head_density, 50, 50),
        ];
        let p = Assembly::new(
            part(HELD, 0, Grade::B),
            vec![part(PartKind::Head, 1, Grade::B)],
        );
        if Assembly::part_mass(&p.mounted[0], &roster[1])
            > Assembly::part_mass(&p.frame, &roster[0])
        {
            saw_a_heavier_head = true;
        }
        let lost = p
            .parts()
            .nth(p.part_always_lost(&roster))
            .expect("the lost index must name a part");
        assert_eq!(
            lost.kind,
            PartKind::Head,
            "frame density {frame_density}, head density {head_density}"
        );
    }
    assert!(
        saw_a_heavier_head,
        "the interesting case — a head heavier than its frame — was never reached"
    );
}

/// Every row in the catalogue earns its place: it is reachable, it costs
/// something, and it moves at least one stat. Names no kind, so a kind added
/// later is covered by this test without editing it.
#[test]
fn every_catalogue_row_earns_its_place() {
    let roster = roster();
    assert_eq!(
        PartKind::ALL.len(),
        PART_SPECS.len(),
        "every kind needs a row and every row a kind"
    );

    for kind in PartKind::ALL {
        let s = spec(kind);
        assert_eq!(s.kind, kind, "spec() returned another kind's row");
        assert!(!s.name.is_empty(), "{kind:?} has no name");
        assert!(s.size >= 1, "{kind:?} costs nothing and weighs nothing");
        assert!(!s.contributions.is_empty(), "{kind:?} does nothing");

        let mut stats = MachineStats::default();
        contribute(
            s,
            Item::new(ItemKind::Refined, SpeciesId(0), Grade::B),
            &roster[0],
            &mut stats,
        );
        assert!(
            Stat::ALL.iter().any(|&st| stats.get(st) > 0),
            "{kind:?} contributes to no stat"
        );
        // Every part weighs something: mass is the one universal.
        assert!(stats.mass > 0, "{kind:?} is weightless");
    }
}

/// The model's own generality, proved rather than asserted: `contribute`
/// takes a `PartSpec`, so a row that is **not in the catalogue** — with a
/// contribution shape no demo part uses — works identically. If this ever
/// needs the row to be registered, or needs a new `Source`, the model has
/// become a catalogue and this test says so.
#[test]
fn a_part_spec_outside_the_catalogue_contributes_the_same_way() {
    let roster = roster();
    let uncatalogued = PartSpec {
        // The kind is never read by `contribute`; only the row is.
        kind: PartKind::Hopper,
        name: "sensor",
        size: 3,
        contributions: &[
            // A shape no shipped part has: capacity from a property.
            Contribution {
                stat: Stat::Capacity,
                source: Source::Property(Property::Strength),
                factor: 2,
            },
            Contribution {
                stat: Stat::Speed,
                source: Source::Flat(7),
                factor: 1,
            },
        ],
        slots: &[],
    };
    assert!(
        !PART_SPECS.iter().any(|s| s.name == uncatalogued.name),
        "the point of this test is that the row is not in the catalogue"
    );

    let mut stats = MachineStats::default();
    contribute(
        &uncatalogued,
        Item::new(ItemKind::Refined, SpeciesId(0), Grade::B),
        &roster[0],
        &mut stats,
    );

    // size 3 × effective strength 40 × factor 2.
    assert_eq!(stats.capacity, 3 * 40 * 2);
    // Flat sources are unscaled by size or material.
    assert_eq!(stats.speed, 7);
    // And nothing is bolted on behind the row's back.
    assert_eq!(stats.mass, 0);
    assert_eq!(stats.budget, 0);
    assert_eq!(stats.durability, 0);
}

/// `size` is one number meaning two things (ADR 0003 pt 5): what a part
/// costs in refined material, and what it weighs per point of density.
#[test]
fn size_is_both_the_refined_cost_and_the_mass() {
    let roster = roster();
    let p = pick(0, Grade::B);
    let d = drill(0, Grade::B, 1);

    assert_eq!(
        p.refined_cost(),
        tuning::HELD_FRAME_SIZE + tuning::HEAD_SIZE
    );
    assert_eq!(
        d.refined_cost(),
        tuning::PLANTED_FRAME_SIZE + tuning::HEAD_SIZE + tuning::HOPPER_SIZE
    );
    // Mass is the same sum of sizes, times density.
    assert_eq!(p.stats(&roster).mass, p.refined_cost() * 50);
    assert_eq!(d.stats(&roster).mass, d.refined_cost() * 50);
}

/// Grade changes what a design can carry but never what it weighs, because
/// mass reads density and density does not scale with grade.
#[test]
fn grade_moves_the_budget_and_never_the_mass() {
    let roster = roster();
    let mut last_budget = 0;
    for grade in [Grade::C, Grade::B, Grade::A] {
        let stats = pick(0, grade).stats(&roster);
        assert_eq!(
            stats.mass,
            pick(0, Grade::C).stats(&roster).mass,
            "{grade:?} changed the mass"
        );
        assert!(
            stats.budget > last_budget,
            "{grade:?} did not raise the budget above {last_budget}"
        );
        last_budget = stats.budget;
    }
}

/// The arithmetic ADR 0003 states, made executable. If anyone retunes the
/// constants, the claims in the ADR fail here rather than quietly going
/// stale.
#[test]
fn the_adr_anchors_hold_exactly() {
    let roster = roster();

    // A middling design fits: a grade-B strength-50 held frame carries 240
    // against a 150-mass pick.
    let middling = pick(0, Grade::B).stats(&roster);
    assert_eq!((middling.mass, middling.budget), (150, 240));
    assert!(!middling.is_overweight());

    // The same pick in a density-90 species is 270 and breaks.
    let dense = pick(1, Grade::B).stats(&roster);
    assert_eq!((dense.mass, dense.budget), (270, 240));
    assert!(dense.is_overweight());

    // A drill with one hopper fits: 400 against 600.
    let d = drill(0, Grade::B, 1).stats(&roster);
    assert_eq!((d.mass, d.budget), (400, 600));
    assert!(!d.is_overweight());
    // Its buffer is the frame's plus one hopper.
    assert_eq!(
        d.capacity,
        tuning::PLANTED_FRAME_BUFFER + tuning::HOPPER_CAPACITY
    );

    // Amendment A2: a grade-B strength-50 head is a 2400-point pool, which
    // is 120 swings — not the 20 the ADR first recorded.
    assert_eq!(middling.durability, 2400);
    assert_eq!(middling.durability / tuning::PICK_WEAR_PER_SWING, 120);
}

/// ADR 0003 amendment A6: a hopper's **grade** changes nothing about it, and
/// that is intended rather than an oversight.
///
/// Capacity is flat from the kind and mass is size × density, which never
/// scales with grade, so the only material decision a hopper carries is its
/// species: make it light. That is what makes hoppers the sink for grade-C
/// refined, which is otherwise near-dead. If this test ever fails because
/// someone scaled `HOPPER_CAPACITY` with grade, the junk sink dies with it and
/// a four-hopper drill becomes a grade-A tax.
#[test]
fn a_hoppers_grade_changes_nothing() {
    let species = roster();
    let readings: Vec<MachineStats> = Grade::ALL
        .into_iter()
        .map(|grade| {
            let mut stats = MachineStats::default();
            let hopper = part(PartKind::Hopper, 0, grade);
            contribute(
                spec(PartKind::Hopper),
                hopper.material,
                &species[0],
                &mut stats,
            );
            stats
        })
        .collect();

    assert_eq!(
        readings[0], readings[1],
        "grade C and B hoppers must be identical"
    );
    assert_eq!(
        readings[1], readings[2],
        "grade B and A hoppers must be identical"
    );
    // And the reason: a hopper reads no grade-scaling property. Density is
    // fixed per species, capacity is flat from the kind.
    for c in spec(PartKind::Hopper).contributions {
        if let Source::Property(p) = c.source {
            assert!(
                !p.scales_with_grade(),
                "a hopper reading {} would make its grade matter",
                p.name()
            );
        }
    }
    // Species, by contrast, is a real choice: index 1 is denser than index 0.
    let light = Assembly::part_mass(&part(PartKind::Hopper, 0, Grade::B), &species[0]);
    let heavy = Assembly::part_mass(&part(PartKind::Hopper, 1, Grade::B), &species[1]);
    assert!(heavy > light, "a denser species must make a heavier hopper");
}
