//! What a player could make by hand right now, as the sim words it.
//!
//! The menu on the Godot client and the terminal's own list both read
//! `debug::make_offers`, for the reason every readout moved into `debug`: the
//! sentence names an OUTPUT item, and the output's grade is a rule, not an
//! echo of the input. These tests exist to catch a host — or a later edit here
//! — quietly deciding that grade itself (ASSA-88).

use sim::debug::{self, MakeWhat};
use sim::{
    Event, Grade, Input, Item, ItemKind, PartKind, PlayerCommand, PlayerId, RecipeId, SpeciesId,
    SystemCommand, World, WorldConfig, step,
};

const X: SpeciesId = SpeciesId(0);
const Y: SpeciesId = SpeciesId(1);

fn world_with_player() -> (World, PlayerId) {
    let mut world = World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    });
    // Hard enough for a gear at every grade, so no row is missing for a
    // reason this file is not about.
    world.species_mut(X).sheet.hardness = 100;
    world.species_mut(Y).sheet.hardness = 100;
    let join = Input::System(SystemCommand::AddPlayer { name: "ada".into() });
    step(&mut world, &[join], &mut Vec::new());
    (world, PlayerId(0))
}

fn give(world: &mut World, me: PlayerId, item: Item, count: u32) {
    world.player_mut(me).unwrap().inventory.add(item, count);
}

fn ore(species: SpeciesId, grade: Grade) -> Item {
    Item::new(ItemKind::Ore, species, grade)
}

fn refined(species: SpeciesId, grade: Grade) -> Item {
    Item::new(ItemKind::Refined, species, grade)
}

fn lines_for(world: &World, me: PlayerId, what: MakeWhat) -> Vec<String> {
    debug::make_offers(world, me)
        .into_iter()
        .filter(|o| o.what == what)
        .map(|o| o.line)
        .collect()
}

/// THE BUG MAREN MEASURED ON THE BOARD'S OWN PACK: two species of ore drew two
/// buttons both labelled exactly `Craft smelter`, building smelters with
/// different walls. One offer per recipe × material, and each names its own
/// material.
#[test]
fn two_species_of_ore_give_two_smelter_offers_that_do_not_read_alike() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 7);
    give(&mut world, me, ore(Y, Grade::B), 9);

    let lines = lines_for(&world, me, MakeWhat::Recipe(RecipeId::Smelter));
    assert_eq!(lines.len(), 2, "one per material: {lines:?}");
    assert_ne!(lines[0], lines[1], "identical labels, different machines");
    assert!(lines.iter().any(|l| l.contains(world.species(X).name())));
    assert!(lines.iter().any(|l| l.contains(world.species(Y).name())));
}

/// THE REASON THIS LIVES IN THE SIM. Two recipes, one stack, two output
/// grades: a smelter keeps the input's grade and `sort` raises it. A host
/// echoing the input's grade would be right on one row and wrong on the other.
#[test]
fn the_output_grade_is_the_recipes_and_not_the_inputs() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 7);

    let smelter = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Smelter))
        .expect("a smelter offer");
    let sort = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Sort))
        .expect("a sort offer");

    assert_eq!(smelter.makes.unwrap().grade, Grade::B);
    assert_eq!(sort.makes.unwrap().grade, Grade::A, "sort raises a grade");
    assert!(smelter.line.contains("(B)"), "{}", smelter.line);
    assert!(
        sort.line.contains("(A)"),
        "the row names what it makes, not what it spends: {}",
        sort.line
    );
}

/// WHAT IT MAKES COMES BEFORE WHAT IT COSTS, and the cost is the recipe's
/// while the count is the pack's. Those two numbers swapping places is the
/// mistake a row of digits invites.
#[test]
fn a_row_names_the_output_first_then_spends_out_of_what_you_hold() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 7);

    let offer = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Smelter))
        .expect("a smelter offer");
    let made = world.item_name(offer.makes.unwrap());
    let spent = world.item_name(offer.input);

    assert_eq!(offer.cost, 5);
    assert_eq!(offer.have, 7);
    assert_eq!(offer.line, format!("{made} — 5 of your 7 {spent}"));
    assert!(
        offer.line.find(&made) < offer.line.find(&spent),
        "consequence first: {}",
        offer.line
    );
}

/// A ROW WITH NO OUTPUT IS STILL AN OFFER. Absence is never a cue, and the
/// player holding grade A ore is exactly the one wondering why they cannot
/// refine it.
#[test]
fn sorting_grade_a_is_offered_and_says_it_makes_nothing() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::A), 12);

    let offer = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Sort))
        .expect("the row is there even though it makes nothing");
    assert!(offer.makes.is_none());
    assert!(
        offer.line.contains(debug::best_grade_note()),
        "{}",
        offer.line
    );
    assert!(
        offer.line.contains(world.species(X).name()),
        "it still names what you would have spent: {}",
        offer.line
    );
}

/// ONE DESCRIBER, TWO MOMENTS. The sentence an offer row shows before the
/// press is the same one the refusal shows after it; that is why
/// `best_grade_note` was pulled out of `event_line`'s match instead of being
/// written a second time for the menu.
#[test]
fn the_offer_and_the_refusal_give_the_same_reason() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::A), 12);

    let offer = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Sort))
        .expect("a sort offer");

    let mut events = Vec::new();
    step(
        &mut world,
        &[Input::Player {
            player: me,
            command: PlayerCommand::Craft {
                recipe: RecipeId::Sort,
                item: ore(X, Grade::A),
                count: 1,
            },
        }],
        &mut events,
    );
    let refusal = events
        .iter()
        .find(|e| matches!(e, Event::CommandRejected { .. }))
        .map(|e| debug::event_line(&world, Some(me), e))
        .expect("the sim refuses it");

    assert!(refusal.contains(debug::best_grade_note()), "{refusal}");
    assert!(offer.line.contains(debug::best_grade_note()));
}

/// ORDER IS THE SIM'S: the recipe table, then the part catalogue, then the
/// pack's own order inside each. A host that sorted again would be a second
/// opinion that drifts from the terminal's.
#[test]
fn the_order_is_the_catalogues_then_the_pack() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 7);
    give(&mut world, me, refined(X, Grade::B), 4);
    give(&mut world, me, refined(Y, Grade::B), 3);

    let what: Vec<MakeWhat> = debug::make_offers(&world, me)
        .into_iter()
        .map(|o| o.what)
        .collect();
    let mut expected = vec![
        MakeWhat::Recipe(RecipeId::Smelter),
        MakeWhat::Recipe(RecipeId::Gear),
        MakeWhat::Recipe(RecipeId::Gear),
        MakeWhat::Recipe(RecipeId::Sort),
    ];
    for kind in PartKind::ALL {
        expected.push(MakeWhat::Part(kind));
        expected.push(MakeWhat::Part(kind));
    }
    assert_eq!(what, expected);

    // And the two offers of one part kind are in the pack's order, which
    // `Inventory` already sorts.
    let species: Vec<SpeciesId> = debug::make_offers(&world, me)
        .into_iter()
        .filter(|o| o.what == MakeWhat::Part(PartKind::Head))
        .map(|o| o.input.species)
        .collect();
    let pack: Vec<SpeciesId> = world
        .player(me)
        .unwrap()
        .inventory
        .stacks()
        .iter()
        .filter(|s| s.item.kind == ItemKind::Refined)
        .map(|s| s.item.species)
        .collect();
    assert_eq!(species, pack);
}

/// SMELTER WORK IS NOBODY'S BUTTON. `Refine` and `Resmelt` happen inside a
/// placed smelter, so they are never offered as hand work however much ore is
/// carried.
#[test]
fn nothing_made_in_a_smelter_is_offered_as_hand_work() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 9);
    give(&mut world, me, refined(X, Grade::B), 9);

    for id in [RecipeId::Refine, RecipeId::Resmelt] {
        assert!(
            lines_for(&world, me, MakeWhat::Recipe(id)).is_empty(),
            "{id:?} is made in a smelter"
        );
    }
    assert!(!lines_for(&world, me, MakeWhat::Recipe(RecipeId::Sort)).is_empty());
}

/// A PART IS MADE OF REFINED MATERIAL AND NOTHING ELSE (`step.rs`), so an
/// ore-only pack gets no part offers at all, and one refined stack gets one
/// offer per catalogue row — a fifth part kind joins the menu with no edit.
#[test]
fn parts_are_offered_from_refined_material_only() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 9);
    assert!(
        !debug::make_offers(&world, me)
            .iter()
            .any(|o| matches!(o.what, MakeWhat::Part(_))),
        "ore is not part material"
    );

    give(&mut world, me, refined(X, Grade::B), 4);
    let parts: Vec<MakeOfferKind> = debug::make_offers(&world, me)
        .into_iter()
        .filter_map(|o| match o.what {
            MakeWhat::Part(kind) => Some((kind, o.cost, o.makes.unwrap().kind)),
            _ => None,
        })
        .collect();
    assert_eq!(parts.len(), PartKind::ALL.len());
    for (kind, cost, made) in parts {
        assert_eq!(made, ItemKind::Part(kind), "a head offer makes a head");
        assert_eq!(cost, sim::assembly::spec(kind).size, "the catalogue's cost");
    }
}

type MakeOfferKind = (PartKind, u32, ItemKind);

/// ASSA-84'S CLAUSE SURVIVES THE MOVE OFF THE PACK ROW (Maren: carried, not
/// rewritten). It rides on the offer whose output nothing uses, and is empty
/// on the others — derived, so the day something consumes a gear it goes away
/// here with no edit.
#[test]
fn the_dead_end_clause_rides_on_the_offer_it_belongs_to() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 9);
    give(&mut world, me, refined(X, Grade::B), 9);

    for offer in debug::make_offers(&world, me) {
        let expected = match offer.what {
            MakeWhat::Recipe(id) => debug::recipe_dead_end(id.recipe()),
            MakeWhat::Part(_) => String::new(),
        };
        assert_eq!(offer.dead_end, expected, "{:?}", offer.what);
    }
    assert!(
        debug::make_offers(&world, me)
            .iter()
            .any(|o| !o.dead_end.is_empty()),
        "a lever that cannot fail is not evidence: something is a dead end today"
    );
}

/// NO TYPED SPECS IN A SENTENCE. `item_spec` is the `ore:species:c` form a
/// player types; a row reads the item's NAME. This is the regression a host
/// would make by reaching for the nearest string.
#[test]
fn a_row_never_falls_back_to_the_typed_item_spec() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 7);
    give(&mut world, me, refined(Y, Grade::C), 5);

    let offers = debug::make_offers(&world, me);
    assert!(!offers.is_empty());
    for offer in offers {
        assert!(
            !offer.line.contains(&debug::item_spec(&world, offer.input)),
            "{}",
            offer.line
        );
        assert!(
            offer.line.contains(&world.item_name(offer.input)),
            "{}",
            offer.line
        );
    }
}

/// A CLIENT HAS NO PLAYER ID UNTIL ITS `Welcome`, and asks anyway.
#[test]
fn a_player_the_world_does_not_have_can_make_nothing() {
    let (world, _) = world_with_player();
    assert!(debug::make_offers(&world, PlayerId(7)).is_empty());
}

/// THE EXACT WORDS OF A PART ROW, which the terminal cannot easily be driven
/// to (refined material is a smelter away) and which therefore has no other
/// witness. A head costs its catalogue size in refined of the same species and
/// grade, and the row names the part before the cost like every other row.
#[test]
fn a_part_row_reads_as_the_part_it_makes_then_the_material() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, refined(X, Grade::B), 9);
    let species = world.species(X).name().to_string();
    let size = sim::assembly::spec(PartKind::Head).size;

    let offer = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Part(PartKind::Head))
        .expect("a head offer");
    assert_eq!(
        offer.line,
        format!("{species} head (B) — {size} of your 9 {species} refined (B)")
    );
}
