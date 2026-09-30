use sim::{Inventory, Item, ItemStack, OreKind};

#[test]
fn stacks_stay_sorted_and_merge() {
    let mut inv = Inventory::new();
    inv.add(Item::Stone, 3);
    inv.add(Item::IronOre, 2);
    inv.add(Item::Stone, 4);
    assert_eq!(
        inv.stacks(),
        &[
            ItemStack::new(Item::IronOre, 2),
            ItemStack::new(Item::Stone, 7)
        ]
    );
    assert_eq!(inv.count(Item::Stone), 7);
    assert_eq!(inv.count(Item::Coal), 0);
    assert_eq!(inv.total(), 9);
}

#[test]
fn same_contents_in_any_order_are_equal() {
    let mut a = Inventory::new();
    a.add(Item::Coal, 1);
    a.add(Item::IronPlate, 5);
    let mut b = Inventory::new();
    b.add(Item::IronPlate, 5);
    b.add(Item::Coal, 1);
    assert_eq!(a, b);
}

#[test]
fn remove_is_all_or_nothing_and_drops_empty_stacks() {
    let mut inv = Inventory::new();
    inv.add(Item::IronPlate, 2);
    assert!(!inv.remove(Item::IronPlate, 3));
    assert_eq!(inv.count(Item::IronPlate), 2);
    assert!(!inv.remove(Item::Coal, 1));
    assert!(inv.remove(Item::Coal, 0));
    assert!(inv.remove(Item::IronPlate, 2));
    assert!(inv.is_empty());
    assert!(inv.stacks().is_empty());
}

#[test]
fn adding_zero_changes_nothing() {
    let mut inv = Inventory::new();
    inv.add(Item::Smelter, 0);
    assert!(inv.is_empty());
}

#[test]
fn ore_kinds_map_to_raw_items() {
    assert_eq!(Item::from(OreKind::Iron), Item::IronOre);
    assert_eq!(Item::from(OreKind::Copper), Item::CopperOre);
    assert_eq!(Item::from(OreKind::Coal), Item::Coal);
    assert_eq!(Item::from(OreKind::Stone), Item::Stone);
}

#[test]
fn item_names_round_trip_and_accept_short_forms() {
    for item in Item::ALL {
        assert_eq!(Item::parse(item.name()), Some(item), "{}", item.name());
    }
    assert_eq!(Item::parse("Iron"), Some(Item::IronOre));
    assert_eq!(Item::parse("gear"), Some(Item::IronGear));
    assert_eq!(Item::parse("plate"), Some(Item::IronPlate));
    assert_eq!(Item::parse("unobtainium"), None);
}
