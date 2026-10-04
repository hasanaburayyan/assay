//! MAREN'S PROBE: how many hoppers does the demo's drill actually have room for?
//!
//! `button_play.gd:39` builds `[["handle", 1], ["head", 2], ["frame", 1], ["hopper", 4]]` and
//! plants frame + head + 4 hoppers whatever the sim's verdict says. On the pinned showcase seed
//! 14247 that is 1078 mass against a 705 budget — 53% over — and the sim had ALREADY said WILL
//! BREAK before the press. So the demo's last beat, a machine standing on the map, does not happen.
//!
//! The demo pressing Place on a doomed design is not a violation of my ASSA-5/7 ruling (Place must
//! never be hidden or disabled — a player may always try). It is a demo choosing a design the game
//! told it not to build. This asks what it should build instead.

use sim::assembly::{Assembly, Mount, Part, PartKind};
use sim::{Grade, Item, ItemKind, World, WorldConfig, ladder};

/// THE WORLD THE DEMO IS IN WHEN IT PLANTS: the starter species ASSAYED.
///
/// My first pass measured a fresh world, where every sheet is a 25-wide band, so `low.budget` came
/// back as 15 and almost every verdict was UNCERTAIN -- a property of the band, not of the design.
/// The giveaway was that the largest safe hopper count was never 1 or 3. The demo assays the
/// material before it builds, so this is the condition the verdict is actually formed in.
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

/// The demo's planted design with `hoppers` hoppers, all of refined starter material at `grade`.
fn drill(w: &World, grade: Grade, hoppers: usize) -> Option<Assembly> {
    let (material, _) = ladder::starter_species(&w.species)?;
    let refined = Item::new(ItemKind::Refined, material, grade);
    Some(Assembly::new(
        Part::of(PartKind::Frame(Mount::Planted), refined),
        std::iter::once(Part::of(PartKind::Head, refined))
            .chain((0..hoppers).map(|_| Part::of(PartKind::Hopper, refined)))
            .collect(),
    ))
}

#[test]
#[ignore = "a probe, not a guard: it measures and prints, and sets no threshold \
           of its own. Run it by name with --nocapture. Ignored so `cargo test --workspace` \
           stays a pass/fail gate rather than a report nobody reads."]
fn how_many_hoppers_the_demos_drill_has_room_for() {
    // The grade the demo actually plants with: it smelts its ore up, and on 14247 the parts are
    // grade A. Checked at all three, because the budget is the frame's and grade scales strength.
    for grade in [Grade::C, Grade::B, Grade::A] {
        println!("=== parts at grade {} ===", grade.letter());
        for seed in [14247u64, 777042, 42, 1, 2026, 7803] {
            let w = world(seed);
            let mut line = format!("  seed {seed:>6}: ");
            for hoppers in 0..=4 {
                let Some(a) = drill(&w, grade, hoppers) else {
                    continue;
                };
                let r = a.stat_range(&w.species);
                line += &format!(
                    "{}h {} ({}/{})  ",
                    hoppers,
                    r.verdict().label(),
                    r.high.mass,
                    r.low.budget
                );
            }
            println!("{line}");
        }
    }

    // THE POPULATION QUESTION: over real worlds, what is the largest SAFE hopper count, and how
    // often is the demo's hard-coded 4 one of them?
    const SEEDS: u64 = 2000;
    let mut best_counts = [0u32; 6]; // index = largest safe hopper count, 5 = "4 is safe"
    let mut four_safe = 0u32;
    let mut none_safe = 0u32;
    for seed in 0..SEEDS {
        let w = world(seed);
        let mut largest: Option<usize> = None;
        for hoppers in 0..=4 {
            let Some(a) = drill(&w, Grade::A, hoppers) else {
                continue;
            };
            if a.stat_range(&w.species).verdict() == sim::assembly::BreakVerdict::Safe {
                largest = Some(hoppers);
            }
        }
        match largest {
            None => none_safe += 1,
            Some(n) => {
                best_counts[n] += 1;
                if n == 4 {
                    four_safe += 1;
                }
            }
        }
    }
    let pc = |n: u32| 100.0 * f64::from(n) / SEEDS as f64;
    println!("\n=== over {SEEDS} real worlds, parts at grade A ===");
    println!(
        "the demo's hard-coded 4 hoppers is SAFE in {four_safe} worlds = {:.1}%",
        pc(four_safe)
    );
    println!(
        "not even 0 hoppers (frame + head alone) is safe: {none_safe} = {:.1}%",
        pc(none_safe)
    );
    for (n, count) in best_counts.iter().enumerate().take(5) {
        println!(
            "  largest safe hopper count = {n}: {count} worlds = {:.1}%",
            pc(*count)
        );
    }
}

/// THE 18.9% WHERE NOT EVEN FRAME + HEAD FITS: is that the world, or the SELECTION?
///
/// `ladder::starter_species` picks the material as THE HARDEST species in rung zero, which is right
/// for a pick head — hardness is the only property a head reads. The demo then builds the drill's
/// FRAME out of that same species, where the only property that matters is strength, because the
/// frame is what sets the mass budget. Hardness and strength are independent rolls, so the demo is
/// selecting its frame material on a property the frame does not read. That is the same defect the
/// doc comment above `starter_species` describes for its own history ("selecting on anything else
/// here is selecting on nothing") — twice over, counting the fuel line.
#[test]
#[ignore = "a probe, not a guard: it measures and prints, and sets no threshold \
           of its own. Run it by name with --nocapture. Ignored so `cargo test --workspace` \
           stays a pass/fail gate rather than a report nobody reads."]
fn whether_a_strength_chosen_frame_would_carry_the_head() {
    const SEEDS: u64 = 2000;
    let mut starter_cannot = 0u32;
    let mut nobody_can = 0u32;
    let mut a_rung_zero_species_can = 0u32;

    for seed in 0..SEEDS {
        let w = world(seed);
        let Some(a) = drill(&w, Grade::A, 0) else {
            continue;
        };
        if a.stat_range(&w.species).verdict() == sim::assembly::BreakVerdict::Safe {
            continue;
        }
        starter_cannot += 1;
        // Any species on rung zero — all hand-minable and smeltable — used for the WHOLE design.
        let rung0 = ladder::rungs(&w.species)
            .into_iter()
            .next()
            .unwrap_or_default();
        let any = rung0.iter().any(|id| {
            let refined = Item::new(ItemKind::Refined, *id, Grade::A);
            Assembly::new(
                Part::of(PartKind::Frame(Mount::Planted), refined),
                vec![Part::of(PartKind::Head, refined)],
            )
            .stat_range(&w.species)
            .verdict()
                == sim::assembly::BreakVerdict::Safe
        });
        if any {
            a_rung_zero_species_can += 1;
        } else {
            nobody_can += 1;
        }
    }

    let pc = |n: u32| 100.0 * f64::from(n) / SEEDS as f64;
    println!("=== over {SEEDS} worlds: the smallest planted machine, frame + head, grade A ===");
    println!(
        "the STARTER species cannot carry a head: {starter_cannot} = {:.1}%",
        pc(starter_cannot)
    );
    println!(
        "  ...but ANOTHER rung-zero species could have: {a_rung_zero_species_can} = {:.1}% of all \
         worlds — SELECTION, not world",
        pc(a_rung_zero_species_can)
    );
    println!(
        "  ...and no rung-zero species can: {nobody_can} = {:.1}% of all worlds — the world really \
         has no first drill in it",
        pc(nobody_can)
    );
}
