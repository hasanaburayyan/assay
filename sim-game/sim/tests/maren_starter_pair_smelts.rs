//! MAREN'S PROBE (not a shipped guard yet): does the pair `ladder::starter_species` hands out
//! actually smelt, on the path the demo actually walks?
//!
//! `starter_species` picks the MATERIAL as the hardest species in rung zero — so some reachable
//! fire melts it — and then picks the FUEL independently, `species.iter().find(hand_lit_fuel)`,
//! which is roster order. Nothing checks that THAT fuel melts THAT material. The doc comment above
//! it describes exactly this defect for the material ("it used to be `rung0.first()` — roster
//! order, so effectively at random") and the fuel line still has it.
//!
//! The demo builds its smelter OUT OF THE MATERIAL, so walls == the material's heat tolerance ==
//! what the ore needs, and `fire = min(fuel_temp, walls)`. The pair therefore smelts iff
//! `fuel_temperature(fuel at its grade) >= material.heat_tolerance`.
//!
//! TWO HOLES, AND THE SECOND IS THE ONE THAT BITES. The ladder is judged at grade B
//! (`ladder::JUDGED_AT`), but `button_play::_choose_species` mines `nearest_of_species` — the
//! NEAREST deposit of the fuel species, at whatever purity that deposit rolled. Grade scales
//! reactivity to 60/80/100%, so a grade-C deposit of a fuel the ladder cleared at B burns at 60%
//! of the temperature the guarantee was stated in.

use sim::{Grade, Item, ItemKind, TilePos, World, WorldConfig, ladder};

fn world(seed: u64) -> World {
    World::new(WorldConfig {
        seed,
        width_chunks: 6,
        height_chunks: 4,
    })
}

/// Squared tile distance, the ordering `AssaySessionPlan.nearest_of_species` uses.
fn dist2(a: TilePos, b: TilePos) -> i64 {
    let dx = i64::from(a.x - b.x);
    let dy = i64::from(a.y - b.y);
    dx * dx + dy * dy
}

#[test]
#[ignore = "a probe, not a guard: it measures and prints, and sets no threshold \
           of its own. Run it by name with --nocapture. Ignored so `cargo test --workspace` \
           stays a pass/fail gate rather than a report nobody reads."]
fn how_often_the_guaranteed_starter_pair_cannot_smelt() {
    const SEEDS: u64 = 2000;
    let mut at_judged_grade = 0u32;
    let mut on_the_demos_path = 0u32;
    let mut hottest_would_fix = 0u32;
    let mut best_grade_would_fix = 0u32;
    let mut named: Vec<String> = Vec::new();

    for seed in 0..SEEDS {
        let w = world(seed);
        let species = &w.species;
        let Some((material, fuel)) = ladder::starter_species(species) else {
            continue;
        };
        let mat = &species[usize::from(material.0)];
        let needs = u32::from(mat.sheet.heat_tolerance);

        // HOLE 1: the guarantee as the ladder states it, at grade B.
        let judged = ladder::burn_temperature(&species[usize::from(fuel.0)]).unwrap_or(0);
        if judged < needs {
            at_judged_grade += 1;
        }

        // HOLE 2: the fuel the demo actually mines — nearest deposit of that species, at ITS grade.
        let spawn = w.spawn_tile();
        let nearest = w
            .deposits
            .iter()
            .filter(|d| d.species == fuel && d.amount > 0)
            .min_by_key(|d| (dist2(d.center, spawn), d.id.0));
        let Some(near) = nearest else { continue };
        let grade = Grade::from_purity(near.purity);
        let burns = w
            .fuel_temperature(Item::new(ItemKind::Ore, fuel, grade))
            .unwrap_or(0);
        if burns < needs {
            on_the_demos_path += 1;
            if named.len() < 8 {
                named.push(format!(
                    "seed {seed}: ore needs {needs}; nearest fuel deposit is grade {} and burns \
                     at {burns} (the same species at grade B burns at {judged})",
                    grade.letter(),
                ));
            }
            // Would picking a hotter DEPOSIT of the same species fix it?
            let best = w
                .deposits
                .iter()
                .filter(|d| d.species == fuel && d.amount > 0)
                .filter_map(|d| {
                    w.fuel_temperature(Item::new(ItemKind::Ore, fuel, Grade::from_purity(d.purity)))
                })
                .max()
                .unwrap_or(0);
            if best >= needs {
                best_grade_would_fix += 1;
            }
            // Would picking a hotter hand-lit SPECIES fix it, at its own nearest deposit's grade?
            let hottest = species
                .iter()
                .filter(|s| ladder::hand_lit_fuel(s))
                .filter_map(|s| {
                    let d = w
                        .deposits
                        .iter()
                        .filter(|d| d.species == s.id && d.amount > 0)
                        .min_by_key(|d| (dist2(d.center, spawn), d.id.0))?;
                    w.fuel_temperature(Item::new(ItemKind::Ore, s.id, Grade::from_purity(d.purity)))
                })
                .max()
                .unwrap_or(0);
            if hottest >= needs {
                hottest_would_fix += 1;
            }
        }
    }

    let pc = |n: u32| 100.0 * f64::from(n) / SEEDS as f64;
    println!("seeds: {SEEDS}  (real 6x4 worlds, the demo's own config)");
    println!(
        "HOLE 1 — the pair cannot smelt even at the JUDGED grade B: {at_judged_grade} = {:.1}%",
        pc(at_judged_grade)
    );
    println!(
        "HOLE 2 — the pair cannot smelt ON THE DEMO'S PATH (nearest fuel deposit, its grade): \
         {on_the_demos_path} = {:.1}%",
        pc(on_the_demos_path)
    );
    println!(
        "  ...of those, a BETTER-GRADE DEPOSIT of the same fuel species would have worked: \
         {best_grade_would_fix}"
    );
    println!("  ...of those, a HOTTER HAND-LIT SPECIES would have worked: {hottest_would_fix}");
    println!("  (the two overlap; both are selection, not world)");
    for line in &named {
        println!("  {line}");
    }
    println!(
        "  note: the fire is min(fuel, walls), and the demo builds the smelter out of the \
         material, so walls == what the ore needs and the fuel is the whole question."
    );
}

/// THE TWO SEEDS THAT FAIL LIVE: does the rule above predict the exact numbers the stall line
/// prints? `button_session.gd -- offline 10027` dies with "fire 44 too cool for ore needing 54"
/// and 7069 with "fire 52 too cool for ore needing 54". If this probe reproduces 44/54 and 52/54
/// from the roster alone, the diagnosis is the cause and not a correlated population statistic.
#[test]
#[ignore = "a probe, not a guard: run it by name with --nocapture."]
fn the_two_live_failures_are_predicted_from_the_roster() {
    for seed in [10027u64, 7069] {
        let w = world(seed);
        let Some((material, fuel)) = ladder::starter_species(&w.species) else {
            continue;
        };
        let mat = &w.species[usize::from(material.0)];
        let needs = u32::from(mat.sheet.heat_tolerance);
        let spawn = w.spawn_tile();
        let near = w
            .deposits
            .iter()
            .filter(|d| d.species == fuel && d.amount > 0)
            .min_by_key(|d| (dist2(d.center, spawn), d.id.0))
            .expect("a starter fuel deposit");
        let grade = Grade::from_purity(near.purity);
        let burns = w
            .fuel_temperature(Item::new(ItemKind::Ore, fuel, grade))
            .unwrap_or(0);
        println!(
            "seed {seed}: material {} needs {needs}; nearest fuel {} is grade {} and burns at \
             {burns} -> fire {} {}",
            mat.name(),
            w.species[usize::from(fuel.0)].name(),
            grade.letter(),
            burns.min(needs),
            if burns < needs { "TOO COOL" } else { "ok" }
        );
    }
}
