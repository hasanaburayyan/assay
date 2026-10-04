//! MAREN'S PROBE, ASSA-155: what would it COST to promise a first planted machine?
//!
//! `assay-rulings` §5 asks the design question this measures: rung zero today promises "you can
//! mine this and smelt it". It does not promise that anything you can build out of rung zero will
//! STAND. ASSA-140 measured the hole — 18.9% of worlds cannot carry even frame + head on the
//! starter species, of which 12.7 points is SELECTION (another rung-zero species would have done
//! it) and 6.2% is a world that genuinely holds no first planted machine.
//!
//! Before I rule, I owe the same measurement Marlow made me on the grade axis, where my instinct
//! was right in direction and wrong in price: widening the guarantee to grade C cost 22.4% of
//! rosters and deleted every world where the hardest rung-zero rock is also heat-tough. **A
//! guarantee that widens until every world looks alike is the wrong trade.** So this asks two
//! things and not one:
//!
//!   1. THE PRICE. Of rosters that already pass `starter_roster_ok`, what share would a new
//!      "some rung-zero species carries frame + head" clause reject?
//!   2. WHAT KIND OF WORLD IT DELETES. A rejection rate is only half an answer. If the rejected
//!      set is systematically a kind of world a player would notice the absence of, the price is
//!      higher than the percentage.
//!
//! JUDGED AT GRADE B, not A. `ladder::JUDGED_AT` is the standard the rest of the guarantee is
//! stated in, and ASSA-140's figures are at grade A — the grade the demo reaches after smelting,
//! not the grade the promise is made in. Measuring the promise in the promise's own units is the
//! whole lesson of ASSA-139.

use sim::assembly::{Assembly, BreakVerdict, Mount, Part, PartKind};
use sim::{Grade, Item, ItemKind, World, WorldConfig, ladder};

/// The world the promise is about, with sheets readable. A fresh `World::new` has nothing assayed,
/// so every sheet is a 25-wide band and every verdict computed on it is a property of the band
/// rather than of the design — that has burned me three times and is in the rulings page.
fn world(seed: u64) -> World {
    let mut w = World::new(WorldConfig {
        seed,
        width_chunks: 6,
        height_chunks: 4,
    });
    for s in &mut w.species {
        s.assayed = true;
    }
    w
}

/// The smallest thing that is a planted machine at all: one frame, one head, one species.
fn frame_and_head_stands(w: &World, id: sim::SpeciesId, grade: Grade) -> bool {
    let refined = Item::new(ItemKind::Refined, id, grade);
    Assembly::new(
        Part::of(PartKind::Frame(Mount::Planted), refined),
        vec![Part::of(PartKind::Head, refined)],
    )
    .stat_range(&w.species)
    .verdict()
        == BreakVerdict::Safe
}

#[test]
#[ignore = "a probe, not a guard: it measures and prints, and sets no threshold \
           of its own. Run it by name with --nocapture. Ignored so `cargo test --workspace` \
           stays a pass/fail gate rather than a report nobody reads."]
fn what_promising_a_first_machine_would_cost() {
    const SEEDS: u64 = 2000;

    for grade in [Grade::B, Grade::A] {
        // Every world here already passes `starter_roster_ok`: `World::new` rerolls until it does.
        // So "rejected" below means rejected IN ADDITION to today's filter, which is the number
        // that decides the price.
        let mut starter_carries = 0u32;
        let mut someone_carries = 0u32;
        let mut nobody_carries = 0u32;

        // WHAT KIND OF WORLD GETS DELETED. Collected over the rejected set and the kept set so the
        // two can be compared; a rejection rate alone cannot answer this.
        let mut rej_rung0_size = Vec::new();
        let mut keep_rung0_size = Vec::new();
        let mut rej_best_strength = Vec::new();
        let mut keep_best_strength = Vec::new();
        let mut rej_starter_hardness = Vec::new();
        let mut keep_starter_hardness = Vec::new();

        for seed in 0..SEEDS {
            let w = world(seed);
            let Some((material, _fuel)) = ladder::starter_species(&w.species) else {
                continue;
            };
            let rung0 = ladder::rungs(&w.species)
                .into_iter()
                .next()
                .unwrap_or_default();

            // The properties a frame and a head actually read, so the comparison is in the units
            // the rule is written in rather than in mine.
            let best_strength = rung0
                .iter()
                .map(|id| {
                    w.species[usize::from(id.0)].effective(sim::mineral::Property::Strength, grade)
                })
                .max()
                .unwrap_or(0);
            let starter_hardness = w.species[usize::from(material.0)]
                .effective(sim::mineral::Property::Hardness, grade);

            let starter_ok = frame_and_head_stands(&w, material, grade);
            let any_ok = rung0.iter().any(|id| frame_and_head_stands(&w, *id, grade));

            if starter_ok {
                starter_carries += 1;
            } else if any_ok {
                someone_carries += 1;
            }

            if any_ok {
                keep_rung0_size.push(rung0.len() as u32);
                keep_best_strength.push(best_strength);
                keep_starter_hardness.push(starter_hardness);
            } else {
                nobody_carries += 1;
                rej_rung0_size.push(rung0.len() as u32);
                rej_best_strength.push(best_strength);
                rej_starter_hardness.push(starter_hardness);
            }
        }

        let pc = |n: u32| 100.0 * f64::from(n) / SEEDS as f64;
        let mean = |v: &[u32]| {
            if v.is_empty() {
                f64::NAN
            } else {
                v.iter().map(|n| f64::from(*n)).sum::<f64>() / v.len() as f64
            }
        };

        println!(
            "\n=== {SEEDS} worlds, every one already passing starter_roster_ok, grade {} ===",
            grade.letter()
        );
        println!(
            "  the STARTER species carries frame + head     {starter_carries:>5} = {:.1}%",
            pc(starter_carries)
        );
        println!(
            "  only ANOTHER rung-zero species carries it    {someone_carries:>5} = {:.1}%  \
             (SELECTION: free, no roster rejected)",
            pc(someone_carries)
        );
        println!(
            "  NO rung-zero species carries it              {nobody_carries:>5} = {:.1}%  \
             <-- THE PRICE: rosters a guarantee would have to reject",
            pc(nobody_carries)
        );

        println!("  what the rejected worlds look like, against the kept ones:");
        println!(
            "    rung-zero species count   rejected {:.2}   kept {:.2}",
            mean(&rej_rung0_size),
            mean(&keep_rung0_size)
        );
        println!(
            "    best rung-zero strength   rejected {:.1}   kept {:.1}",
            mean(&rej_best_strength),
            mean(&keep_best_strength)
        );
        println!(
            "    starter hardness          rejected {:.1}   kept {:.1}",
            mean(&rej_starter_hardness),
            mean(&keep_starter_hardness)
        );
    }
}
