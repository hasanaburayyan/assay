//! ADR 0001: generated species, grades, and how grade scales the sheet.

use sim::tuning::{GRADE_A_MIN_PURITY, GRADE_B_MIN_PURITY, SPECIES_PER_WORLD};
use sim::{
    Grade, Inventory, Item, ItemKind, ItemStack, Property, Sheet, SpeciesId, World, WorldConfig,
};

fn world(seed: u64) -> World {
    World::new(WorldConfig {
        seed,
        ..WorldConfig::default()
    })
}

#[test]
fn every_world_rolls_its_own_species_with_full_sheets() {
    let a = world(1);
    let b = world(2);
    assert_eq!(a.species.len(), SPECIES_PER_WORLD);
    assert_ne!(a.species[0].sheet, b.species[0].sheet);
    for s in &a.species {
        for p in Property::ALL {
            let v = s.sheet.get(p);
            assert!((1..=100).contains(&v), "{} {} = {v}", s.name(), p.name());
        }
        assert!(s.player_name.is_none() && s.discoverer.is_none());
    }
    // Names are distinct and start with distinct letters (the map glyph).
    let initials: Vec<char> = a
        .species
        .iter()
        .map(|s| s.name().chars().next().unwrap())
        .collect();
    let mut dedup = initials.clone();
    dedup.sort();
    dedup.dedup();
    assert_eq!(dedup.len(), initials.len(), "{initials:?}");
}

#[test]
fn no_named_ore_survives_in_the_sim() {
    // Decision 12: no Iron/Copper/Coal/Stone identifiers. Species names are
    // generated, so none of them is a real ore either.
    for seed in 0..50 {
        for s in &world(seed).species {
            let n = s.name().to_ascii_lowercase();
            assert!(
                !["iron", "copper", "coal", "stone"].contains(&n.as_str()),
                "seed {seed} rolled a real ore name"
            );
        }
    }
}

#[test]
fn purity_rounds_into_grades() {
    assert_eq!(Grade::from_purity(1), Grade::C);
    assert_eq!(Grade::from_purity(GRADE_B_MIN_PURITY - 1), Grade::C);
    assert_eq!(Grade::from_purity(GRADE_B_MIN_PURITY), Grade::B);
    assert_eq!(Grade::from_purity(GRADE_A_MIN_PURITY - 1), Grade::B);
    assert_eq!(Grade::from_purity(GRADE_A_MIN_PURITY), Grade::A);
    assert_eq!(Grade::from_purity(100), Grade::A);
    assert!(Grade::C < Grade::B && Grade::B < Grade::A);
    assert_eq!(Grade::C.better(), Some(Grade::B));
    assert_eq!(Grade::A.better(), None);
}

#[test]
fn items_stack_by_species_and_grade_only() {
    // Decision 2: same species and grade merge; different grades never do.
    let (x, y) = (SpeciesId(0), SpeciesId(1));
    let mut inv = Inventory::new();
    inv.add(Item::new(ItemKind::Ore, x, Grade::B), 3);
    inv.add(Item::new(ItemKind::Ore, x, Grade::B), 4);
    inv.add(Item::new(ItemKind::Ore, x, Grade::A), 1);
    inv.add(Item::new(ItemKind::Ore, y, Grade::B), 2);
    inv.add(Item::new(ItemKind::Refined, x, Grade::B), 2);
    assert_eq!(
        inv.stacks(),
        &[
            ItemStack::new(Item::new(ItemKind::Ore, x, Grade::B), 7),
            ItemStack::new(Item::new(ItemKind::Ore, x, Grade::A), 1),
            ItemStack::new(Item::new(ItemKind::Ore, y, Grade::B), 2),
            ItemStack::new(Item::new(ItemKind::Refined, x, Grade::B), 2),
        ]
    );
    assert_eq!(inv.count(Item::new(ItemKind::Ore, x, Grade::B)), 7);
    assert!(inv.remove(Item::new(ItemKind::Ore, x, Grade::A), 1));
    assert!(!inv.remove(Item::new(ItemKind::Ore, x, Grade::A), 1));
    assert_eq!(inv.stacks().len(), 3);
}

#[test]
fn grade_scales_four_properties_and_leaves_two_fixed() {
    // Decision 4.
    let sheet = Sheet {
        density: 50,
        strength: 50,
        hardness: 50,
        heat_tolerance: 50,
        reactivity: 50,
        conductivity: 50,
    };
    for p in [Property::Density, Property::HeatTolerance] {
        assert_eq!(sheet.effective(p, Grade::A), sheet.effective(p, Grade::C));
        assert_eq!(sheet.effective(p, Grade::C), 50);
    }
    for p in [
        Property::Strength,
        Property::Hardness,
        Property::Reactivity,
        Property::Conductivity,
    ] {
        assert!(sheet.effective(p, Grade::A) > sheet.effective(p, Grade::B));
        assert!(sheet.effective(p, Grade::B) > sheet.effective(p, Grade::C));
        assert_eq!(sheet.effective(p, Grade::A), 50);
    }
    assert!(sheet.effective(Property::Hardness, Grade::C) >= 1);
}

#[test]
fn a_grade_soft_mineral_can_beat_c_grade_hard_mineral() {
    // Decision 3: grade is a real multiplier. Search generated rosters for a
    // harder species X and a softer Y where Y at A beats X at C.
    let found = (0..30).any(|seed| {
        let w = world(seed);
        w.species.iter().any(|x| {
            w.species.iter().any(|y| {
                y.sheet.hardness < x.sheet.hardness
                    && y.effective(Property::Hardness, Grade::A)
                        > x.effective(Property::Hardness, Grade::C)
            })
        })
    });
    assert!(found);
}

#[test]
fn item_codes_and_kind_names_parse() {
    for k in ItemKind::ALL {
        assert_eq!(ItemKind::parse(k.name()), Some(k));
    }
    assert_eq!(ItemKind::parse("plate"), Some(ItemKind::Refined));
    assert_eq!(ItemKind::parse("coal"), None);
    let item = Item::new(ItemKind::Gear, SpeciesId(2), Grade::B);
    assert_eq!(item.code(), "gear#2(B)");
    assert_eq!(Grade::parse("b"), Some(Grade::B));
    let w = world(1);
    assert!(w.item_name(item).ends_with(" gear (B)"));
}
