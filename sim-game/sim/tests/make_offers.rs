//! What a player could make by hand right now, as the sim words it.
//!
//! The menu on the Godot client and the terminal's own list both read
//! `debug::make_offers`, for the reason every readout moved into `debug`: the
//! sentence names an OUTPUT item, and the output's grade is a rule, not an
//! echo of the input. These tests exist to catch a host — or a later edit here
//! — quietly deciding that grade itself (ASSA-88).

use sim::debug::{self, MakeWhat};
use sim::{
    Event, Grade, Input, Item, ItemKind, PartKind, PlayerCommand, PlayerId, Property, RecipeId,
    Sheet, SpeciesId, SystemCommand, World, WorldConfig, step,
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

/// **THE SENTENCE A PLAYER MEETS FIRST, AND THE ONE NOBODY TESTED** (ASSA-129).
///
/// A row exists for every stack you hold and a smelter costs five ore, so from
/// your FIRST ore to your FIFTH the first thing this game says about making
/// anything is a row you cannot yet afford. The old shape was
/// `{cost} of your {have} {item}` — a partitive, which asserts you hold at
/// least `have` and are taking `cost` of them. Both numbers were right and
/// "5 of your 3 Tonore ore (A)" is not a sentence. Every `of your` the Director
/// could find in the tests was an affordable row; that is how it shipped.
///
/// **BOTH DIRECTIONS IN ONE TEST, which is the ruling itself.** One shape has
/// to read whether you can afford the thing or not, with no branch on
/// `have >= cost`: affordability changes tick to tick and `step` answers it at
/// the press, so a describer that picked its words by comparing them would be a
/// second opinion about affordability. Three counts across the boundary, same
/// shape, and the only thing that moves is the figure.
#[test]
fn a_row_reads_as_english_when_you_cannot_afford_it() {
    for (have, expect) in [(3u32, "you have 3"), (5, "you have 5"), (7, "you have 7")] {
        let (mut world, me) = world_with_player();
        give(&mut world, me, ore(X, Grade::B), have);

        let offer = debug::make_offers(&world, me)
            .into_iter()
            .find(|o| o.what == MakeWhat::Recipe(RecipeId::Smelter))
            .expect("a smelter offer");
        let made = world.item_name(offer.makes.unwrap());
        let spent = world.item_name(offer.input);

        assert_eq!(
            offer.cost, 5,
            "the recipe's cost does not depend on the pack"
        );
        assert_eq!(offer.have, have);
        assert_eq!(offer.line, format!("{made} — 5 {spent}, {expect}"));
        assert!(
            !offer.line.contains("of your"),
            "a partitive claims you hold what you are spending: {}",
            offer.line
        );
    }
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
    assert_eq!(offer.line, format!("{made} — 5 {spent}, you have 7"));
    assert!(
        offer.line.find(&made) < offer.line.find(&spent),
        "consequence first: {}",
        offer.line
    );
}

/// A ROW WITH NO OUTPUT IS STILL AN OFFER, AND ITS LIMIT BINDS THE CLAIM IT
/// KILLS (Maren's ruling on ASSA-88, which my first version failed).
///
/// Absence is never a cue, and the player holding grade A ore is exactly the one
/// wondering why they cannot refine it. **What shipped first read "nothing from
/// X ore (A): grade A is already the best" — a reason trailing after a colon,
/// naming no verb at all.** The ruling is one sentence in which grade A IS why
/// there is no sort, with no comma before the "if", the shape
/// `species_table` already uses for "fuel at B or better if you could mine it".
#[test]
fn sorting_grade_a_is_offered_and_its_limit_binds_what_it_would_have_made() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::A), 12);

    let offer = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Sort))
        .expect("the row is there even though it makes nothing");
    assert!(offer.makes.is_none());

    let line = offer.line.clone();
    let claim = line.split(" — ").next().expect("a claim before the cost");
    // THE CLAIM NAMES WHAT WOULD HAVE BEEN MADE, and the limit is inside it.
    assert!(
        claim.contains("a better grade") && claim.contains(world.species(X).name()),
        "the claim names no outcome: {claim}"
    );
    assert!(
        claim.contains(" if "),
        "the limit does not bind the claim: {claim}"
    );
    // AND NOT THE SHAPE THAT WAS RULED AGAINST: a reason trailing after a colon
    // or a comma. Asserted on the CLAIM and not the whole line, because the cost
    // half legitimately follows an em dash.
    assert!(
        !claim.contains(": ") && !claim.contains(", "),
        "the reason trails the claim instead of binding it: {claim}"
    );
    assert!(
        claim.contains(Grade::A.letter()),
        "grade A is the reason and must be in the sentence: {claim}"
    );
}

/// THE OFFER AND THE REFUSAL ARE ONE FACT IN TWO MOODS, and the only thing that
/// could drift between them is pinned.
///
/// **THIS TEST GOT WEAKER AND I WANT THAT ON THE RECORD.** It used to require
/// both to contain `best_grade_note()` verbatim, which was a strong guarantee of
/// one describer. Maren's ruling makes the offer a CONDITIONAL on the thing it
/// would have made, and English will not let a conditional and an indicative be
/// the same string. So what is asserted now is the part that can actually go
/// wrong: both must name the grade at which there is nothing better, and that
/// letter is taken from `Grade` rather than typed here — if `Grade::better` ever
/// stops returning `None` at A, this reddens instead of quietly describing the
/// wrong grade in two places.
#[test]
fn the_offer_and_the_refusal_name_the_same_grade() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::A), 12);
    let best = Grade::A.letter();
    assert!(
        Grade::A.better().is_none(),
        "A is the grade with nothing above it"
    );

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
        .map(|e| debug::event_line(&world, Some(me), e, debug::Audience::Typed))
        .expect("the sim refuses it");

    assert!(refusal.contains(debug::best_grade_note()), "{refusal}");
    assert!(
        refusal.contains(best),
        "the refusal names the grade: {refusal}"
    );
    assert!(
        offer.line.contains(best),
        "the offer names the grade: {}",
        offer.line
    );
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
        format!("{species} head (B) — {size} {species} refined (B), you have 9")
    );
}

/// MAREN'S CHECK BEFORE ASSA-86 LEAVES QA: **every make-verb that was reachable
/// from a pack row is reachable from the menu.** A verb now on NEITHER surface
/// is the defect the 88-before-86 ordering existed to prevent, and it would
/// pass every test written against the new row shape alone.
///
/// **COUNTED FROM THE CATALOGUES ON BOTH SIDES, NOT FROM THE DIFF.** The old
/// pack rule was not a list in the client: `stack_verbs` put a `Craft` on a row
/// when some HAND recipe's `input` matched that row's kind, and a `Make` on a
/// row when a part's `material` matched. So the "before" set is
/// `RecipeId::ALL.filter(is_hand_craftable)` plus `PartKind::ALL` — the same
/// source the deleted code read — and the "after" set is whatever
/// `make_offers` reports for a player carrying one stack of every input kind.
/// Equality is the property; a count alone would pass if one verb vanished and
/// another doubled.
#[test]
fn every_make_verb_the_pack_used_to_offer_is_reachable_from_the_menu() {
    let (mut world, me) = world_with_player();
    // ONE STACK OF EVERY KIND ANY HAND RECIPE OR PART EATS, so no verb is
    // missing merely because its material is not carried. Read off the
    // catalogues for the same reason the sets below are.
    let mut inputs: Vec<ItemKind> = RecipeId::ALL
        .iter()
        .filter(|id| id.is_hand_craftable())
        .map(|id| id.recipe().input.0)
        .collect();
    inputs.push(ItemKind::Refined); // what a part is made of (`step.rs`)
    inputs.dedup();
    for kind in inputs {
        give(&mut world, me, Item::new(kind, X, Grade::B), 9);
    }

    let before: Vec<MakeWhat> = RecipeId::ALL
        .iter()
        .filter(|id| id.is_hand_craftable())
        .map(|id| MakeWhat::Recipe(*id))
        .chain(PartKind::ALL.iter().map(|kind| MakeWhat::Part(*kind)))
        .collect();
    let mut after: Vec<MakeWhat> = debug::make_offers(&world, me)
        .into_iter()
        .map(|o| o.what)
        .collect();
    after.dedup();

    assert_eq!(
        before,
        after,
        "a make-verb is on neither surface: pack rows lost {:?}, menu gained {:?}",
        before
            .iter()
            .filter(|w| !after.contains(w))
            .collect::<Vec<_>>(),
        after
            .iter()
            .filter(|w| !before.contains(w))
            .collect::<Vec<_>>()
    );
    assert_eq!(before.len(), 7, "three hand recipes and four part kinds");
}

/// **THE PRECEDENCE, AND IT IS THE RULING: a dead end outranks the material's
/// shortfall, and the shortfall is then not shown AT ALL** (Maren, ASSA-88,
/// copied from `deposit_dead_end_note`'s `reach.or_else(unsmeltable)`).
///
/// Her reason is the whole of it: told its hardness is short, a player goes and
/// finds harder rock and spends 2 refined, only to learn nothing consumes the
/// thing.
///
/// **AND THIS IS WHERE THE CATALOGUE MAKES THE OTHER CLAUSE UNREACHABLE.**
/// `Gear` is the only recipe with a `requires` AND the only one whose output
/// nothing consumes, so the two sets coincide exactly: today the dead end always
/// wins and the shortfall never reaches a player. This test pins the ruled
/// order; `the_shortfall_clause_binds_the_item_it_would_have_made` below is the
/// only witness the shortfall wording has, because `make_offers` cannot produce
/// it. Both facts are on ASSA-107 rather than left for the next reader.
#[test]
fn a_dead_end_outranks_the_materials_shortfall_and_hides_it() {
    let (mut world, me) = world_with_player();
    // A ROCK TOO SOFT FOR A GEAR AT ANY GRADE, so both clauses apply at once.
    world.species_mut(X).sheet.hardness = 1;
    give(&mut world, me, refined(X, Grade::B), 9);

    let recipe = RecipeId::Gear.recipe();
    let short = recipe
        .unmet_requirement(world.species(X), refined(X, Grade::B))
        .expect("this rock is too soft for a gear, so both clauses apply");
    assert_eq!(short.0, Property::Hardness);
    let dead_end = debug::recipe_dead_end(recipe);
    assert!(!dead_end.is_empty(), "a gear is still a dead end");

    let offer = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Gear))
        .expect("the row stays: never filtered, never disabled");

    assert_eq!(offer.dead_end, dead_end, "the dead end takes the one slot");
    assert!(
        !offer.line.contains(short.0.name()),
        "the shortfall is shown while a dead end applies, which sends the player \
         hunting harder rock for something nothing uses: {}",
        offer.line
    );
    // AND THE ROW STILL SAYS WHAT IT MAKES. A dead end produces its item; that
    // the item is useless is exactly what the slot is for. A row claiming
    // nothing AND warning about nothing would be the worst of both.
    assert!(
        offer.makes.is_some()
            && offer
                .line
                .starts_with(&world.item_name(offer.makes.unwrap())),
        "a dead-end row stops naming its output: {}",
        offer.line
    );
}

/// THE SHORTFALL CLAUSE ITSELF, through the only door it has.
///
/// `make_offers` cannot reach this today (see the precedence test above), so it
/// is reached through `recipe_table`'s own path: the property and the number
/// come from `Recipe::unmet_requirement`, the same call `step` makes before
/// refusing, which is what makes the figure in an offer and the figure in a
/// refusal the same figure.
///
/// **A LEVER THAT CANNOT FAIL IS NOT EVIDENCE, so this one asserts the SHAPE
/// the ruling is about** — the claim first, the limit bound to it with no comma
/// — rather than the exact sentence, which Maren may still reword.
#[test]
fn the_shortfall_clause_binds_the_item_it_would_have_made() {
    let (mut world, me) = world_with_player();
    world.species_mut(X).sheet.hardness = 1;
    give(&mut world, me, refined(X, Grade::B), 9);

    let recipe = RecipeId::Gear.recipe();
    let made = world.item_name(
        recipe
            .output_for(refined(X, Grade::B))
            .expect("a gear does not raise grade"),
    );
    let (property, min) = recipe
        .unmet_requirement(world.species(X), refined(X, Grade::B))
        .expect("too soft");
    let clause = debug::shortfall_clause(&made, property, min);

    assert!(clause.starts_with(&made), "the claim comes first: {clause}");
    assert!(
        clause.contains(" if "),
        "the limit binds the claim: {clause}"
    );
    assert!(
        !clause.contains(", ") && !clause.contains(": "),
        "the reason trails instead of binding: {clause}"
    );
    assert!(
        clause.contains(&min.to_string()) && clause.contains(property.name()),
        "the clause names the property and the number this species misses: {clause}"
    );
    assert_eq!(
        min,
        sim::tuning::GEAR_MIN_HARDNESS,
        "the number is the sim's threshold, not one typed into a sentence"
    );
}

/// MAREN'S WALLS CLAUSE (ASSA-88 → ASSA-125). A smelter's walls are its
/// material's heat tolerance, `fire = min(fuel burn, walls)`, and five ore are
/// spent before anything tells a player whether the rock they chose can melt
/// anything. The row names the figure at the moment of choice.
///
/// **THE FIGURE, NOT A VERDICT.** It says what the walls would be and never
/// whether they are enough: the comparison against the ore is the game.
#[test]
fn the_smelter_row_names_the_walls_that_smelter_would_have() {
    let (mut world, me) = world_with_player();
    world.species_mut(X).sheet.heat_tolerance = 57;
    give(&mut world, me, ore(X, Grade::B), 7);

    let smelter = debug::make_offers(&world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Smelter))
        .expect("a smelter offer");
    let (lo, hi) = Sheet::band(57);
    assert_eq!(
        smelter.walls,
        format!("walls {lo}-{hi}"),
        "the player's reading of this species' heat tolerance, not the ground's"
    );
}

/// **IT IS WHAT THEY KNOW, NOT WHAT IS TRUE.** A sheet reads as a 25-wide band
/// until that species is assayed, so until then a player can only predict their
/// walls to within a band — which is a reason to assay before spending, and a
/// claim this clause must not quietly skip past.
#[test]
fn the_walls_sharpen_from_a_band_to_a_number_when_the_species_is_assayed() {
    let (mut world, me) = world_with_player();
    world.species_mut(X).sheet.heat_tolerance = 57;
    give(&mut world, me, ore(X, Grade::B), 7);
    let rough = walls_of(&world, me);

    world.species_mut(X).assayed = true;
    let exact = walls_of(&world, me);

    assert!(rough.contains('-'), "a band before the assay: {rough}");
    assert_eq!(exact, "walls 57", "the number after it");
    assert_ne!(rough, exact);
}

/// **THE TRAP, AND THE REASON THIS SENTENCE IS THE SIM'S.** Everything else on
/// the row moves with grade — the output item is `ore (A)`, the shortfall is
/// judged at grade — but heat tolerance is one of the two properties grade
/// never scales. A host composing this from a stack would reasonably scale it
/// and be wrong, and the player would choose their first smelter on it.
///
/// **WHAT THIS LEVER CAN AND CANNOT CATCH, measured rather than assumed.**
/// Rewriting the clause to `effective(HeatTolerance, grade)` — the obvious
/// wrong move — leaves this test GREEN, because `Sheet::effective` itself
/// refuses to scale heat tolerance, so the sim already protects that route.
/// It reddens against a scaling written out by hand (60/80/100 on the grade),
/// which is the version a host would invent, and that is the mutation I ran.
/// Recorded so nobody reads its green as cover for the first case.
#[test]
fn the_walls_do_not_move_with_the_grade_of_the_ore_they_are_built_from() {
    let (mut world, me) = world_with_player();
    world.species_mut(X).sheet.heat_tolerance = 57;
    world.species_mut(X).assayed = true;
    give(&mut world, me, ore(X, Grade::C), 7);
    give(&mut world, me, ore(X, Grade::A), 7);

    let walls: Vec<String> = debug::make_offers(&world, me)
        .into_iter()
        .filter(|o| o.what == MakeWhat::Recipe(RecipeId::Smelter))
        .map(|o| o.walls)
        .collect();
    assert_eq!(walls.len(), 2, "one row per stack's species × grade");
    assert_eq!(
        walls[0], walls[1],
        "grade C and grade A build the same walls"
    );
    assert_eq!(walls[0], "walls 57");
}

/// EVERY OTHER ROW IS SILENT ABOUT WALLS, because every other row makes
/// something that has none. Keyed on the recipe's output kind, so a later
/// placeable recipe arrives here as a row with no clause rather than as one
/// inheriting the smelter's.
#[test]
fn no_other_row_claims_walls() {
    let (mut world, me) = world_with_player();
    give(&mut world, me, ore(X, Grade::B), 7);
    give(&mut world, me, refined(X, Grade::B), 9);

    for offer in debug::make_offers(&world, me) {
        if offer.what == MakeWhat::Recipe(RecipeId::Smelter) {
            assert!(
                !offer.walls.is_empty(),
                "the smelter row is the one that does"
            );
        } else {
            assert!(
                offer.walls.is_empty(),
                "{:?} claims walls: {}",
                offer.what,
                offer.walls
            );
        }
    }
}

/// **BEHAVIOURAL, NOT A WORDING TEST.** What keeps this clause true is not that
/// it reads well: it is that a smelter actually built from that species has the
/// walls the row promised. Assert the sentence against `World::max_temperature`
/// — the one place that decides — and a rule change moves both or reddens this.
#[test]
fn a_smelter_built_from_that_species_has_the_walls_the_row_promised() {
    let (mut world, me) = world_with_player();
    world.species_mut(X).sheet.heat_tolerance = 57;
    world.species_mut(X).assayed = true;
    give(&mut world, me, ore(X, Grade::B), 7);
    let promised = walls_of(&world, me);

    let built = Item::new(ItemKind::Smelter, X, Grade::B);
    give(&mut world, me, built, 1);
    let spawn = world.spawn_tile();
    let pos = sim::TilePos::new(spawn.x + 1, spawn.y);
    step(
        &mut world,
        &[Input::player(me, PlayerCommand::Place { item: built, pos })],
        &mut Vec::new(),
    );
    let standing = world.building_at(pos).expect("a smelter on the ground");

    assert_eq!(
        promised,
        format!("walls {}", world.max_temperature(standing)),
        "the row promised walls the placed smelter does not have"
    );
}

fn walls_of(world: &World, me: PlayerId) -> String {
    debug::make_offers(world, me)
        .into_iter()
        .find(|o| o.what == MakeWhat::Recipe(RecipeId::Smelter))
        .expect("a smelter offer")
        .walls
}

/// **THE TERMINAL SAYS IT TOO**, because a menu only the window has is a
/// feature that only works with graphics, which this repo does not allow. The
/// table is what `makes` and `recipes` print, so this is the headless half of
/// Maren's ruling rather than a second assertion about the same function.
#[test]
fn the_terminal_table_carries_the_walls_clause_too() {
    let (mut world, me) = world_with_player();
    world.species_mut(X).sheet.heat_tolerance = 57;
    world.species_mut(X).assayed = true;
    give(&mut world, me, ore(X, Grade::B), 7);

    let table = debug::make_offer_table(&world, me);
    let clause = walls_of(&world, me);
    assert!(
        !clause.is_empty(),
        "the premise: there is a clause to carry"
    );
    assert!(table.contains(&clause), "{table}");
    // ON THE SMELTER'S OWN ROW, not loose in the table. A clause that landed on
    // the wrong line would still pass a `contains` over the whole string.
    let row = table
        .lines()
        .find(|l| l.contains(&clause))
        .expect("a row with the clause");
    assert!(
        row.contains(&world.item_name(Item::new(ItemKind::Smelter, X, Grade::B))),
        "the clause is not on the row that makes the smelter: {row}"
    );
}
