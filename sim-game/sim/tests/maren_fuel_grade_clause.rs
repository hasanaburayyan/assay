//! MAREN'S PROBE (ASSA-135, Nerite's box-1 gap): the window drops the "fuel at X or better"
//! clause. Does that cost the player anything, or is the grade always C?
//!
//! `sim-godot/src/lib.rs:1638` CALLS `ladder::fuel_grade(species)` and keeps only `.is_some()`.
//! The threshold is computed and thrown away, so the window says a rock is fuel without saying
//! at which grade it becomes fuel. If a species is "fuel at B or better", a grade-C deposit of
//! it is not fuel at all -- which is exactly the trap ASSA-139 is filed for.

use sim::mineral::Property;
use sim::{Grade, ladder, worldgen};

#[test]
#[ignore = "a probe, not a guard: it measures and prints. Run it by name with --nocapture."]
fn how_often_the_dropped_fuel_grade_clause_says_something() {
    const SEEDS: u64 = 2000;
    let mut by_grade = [0u32; 3]; // C, B, A
    let mut not_fuel = 0u32;
    let mut rows_in_window = 0u32; // rows the window actually shows a fuel tag on
    let mut window_rows_not_c = 0u32;

    for seed in 0..SEEDS {
        for s in &worldgen::species_roster(seed) {
            match ladder::fuel_grade(s) {
                None => not_fuel += 1,
                Some(g) => {
                    by_grade[match g {
                        Grade::C => 0,
                        Grade::B => 1,
                        Grade::A => 2,
                    }] += 1;
                    // The window shows the lighting tag only when the rock is fuel AND minable.
                    if ladder::hand_minable(s) {
                        rows_in_window += 1;
                        if g != Grade::C {
                            window_rows_not_c += 1;
                        }
                    }
                }
            }
        }
    }

    let total = by_grade.iter().sum::<u32>() + not_fuel;
    let pc = |n: u32, d: u32| 100.0 * f64::from(n) / f64::from(d);
    println!("{SEEDS} rosters, {total} species rows");
    println!(
        "  not fuel at any grade: {not_fuel} = {:.1}%",
        pc(not_fuel, total)
    );
    for (i, letter) in ["C", "B", "A"].iter().enumerate() {
        println!(
            "  fuel at {letter} or better: {} = {:.1}% of all rows",
            by_grade[i],
            pc(by_grade[i], total)
        );
    }
    println!("\nROWS THE WINDOW ACTUALLY TAGS AS FUEL (fuel AND hand-minable): {rows_in_window}");
    println!(
        "  of those, the dropped clause would have said something OTHER than C: \
         {window_rows_not_c} = {:.1}%",
        pc(window_rows_not_c, rows_in_window)
    );
    println!(
        "  ...meaning a grade-C deposit of that rock is NOT fuel, and the window never says so."
    );

    // The thresholds, derived rather than asserted from my arithmetic.
    println!("\nthresholds (base reactivity -> cheapest fuel grade), read off the sim:");
    let roster = worldgen::species_roster(0);
    let mut shown = [false; 4];
    for r in 1u8..=100 {
        let mut s = roster[0].clone();
        s.sheet.reactivity = r;
        let idx = match ladder::fuel_grade(&s) {
            None => 3,
            Some(Grade::A) => 2,
            Some(Grade::B) => 1,
            Some(Grade::C) => 0,
        };
        if !shown[idx] {
            shown[idx] = true;
            println!(
                "  reactivity {r:>3} -> {} (effective at C = {})",
                match idx {
                    0 => "fuel at C or better",
                    1 => "fuel at B or better",
                    2 => "fuel at A or better",
                    _ => "not fuel",
                },
                s.effective(Property::Reactivity, Grade::C)
            );
        }
    }
}
