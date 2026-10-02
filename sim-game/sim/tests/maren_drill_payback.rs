//! SCRATCH (Game Director). Not a guard: **is a drill worth building inside
//! the demo, and what does owning one actually feel like?**
//!
//! The milestone is named "parts, picks, drills". Picks I have measured to
//! death; the drill I have only ruled about. Three numbers I do not have:
//!   (a) how long a drill runs UNATTENDED before its buffer stalls it,
//!   (b) what its parts cost in smelter ticks — the demo's scarcest resource,
//!       measured at 49% of the whole spawn-to-pick clock,
//!   (c) whether a drill out-mines the bare hands it replaces at all.
//! Measured against the demo loop's own clock: 326 ticks on seed 14247.

use sim::assembly::{Assembly, Part, PartKind};
use sim::{Grade, Item, ItemKind, MineralSpecies, Mount, World, WorldConfig};

/// `RECIPES` Refine: 1 ore -> 1 refined in a smelter, 20 ticks.
const REFINE_TICKS: u32 = 20;

const PLANTED: PartKind = PartKind::Frame(Mount::Planted);

fn host_world(seed: u64) -> World {
    World::new(WorldConfig {
        seed,
        width_chunks: 6,
        height_chunks: 4,
    })
}

fn refined(s: &MineralSpecies, g: Grade) -> Item {
    Item::new(ItemKind::Refined, s.id, g)
}

fn drill(s: &MineralSpecies, g: Grade, hoppers: u32) -> Assembly {
    let mut mounted = vec![Part::of(PartKind::Head, refined(s, g))];
    for _ in 0..hoppers {
        mounted.push(Part::of(PartKind::Hopper, refined(s, g)));
    }
    Assembly::new(Part::of(PLANTED, refined(s, g)), mounted)
}

/// Ticks of smelting the parts of a design cost: one refined per unit of part
/// size, `REFINE_TICKS` each. The ore to feed it is extra and not counted here.
fn smelter_ticks(a: &Assembly) -> u32 {
    a.parts().map(sim::assembly::Part::size).sum::<u32>() * REFINE_TICKS
}

#[test]
fn what_owning_a_drill_is_like() {
    const SEEDS: u32 = 500;
    const DEMO_TICKS: u32 = 326;
    let mut rows: Vec<(u32, u32, u32, u32, u32)> = Vec::new(); // speed, fill, cost, hand, cap
    let (mut beats_hands, mut worlds) = (0u32, 0u32);
    for seed in 1..=u64::from(SEEDS) {
        let w = host_world(seed);
        // The species a player would really build from: hand-minable, and the
        // hardest of those, because only hardness buys a head any speed.
        let Some(best) = w
            .species
            .iter()
            .filter(|s| sim::ladder::hand_minable(s))
            .filter(|s| sim::ladder::usable_from_bare_hands(&w.species, s.id))
            .max_by_key(|s| s.sheet.hardness)
        else {
            continue;
        };
        worlds += 1;
        for hoppers in [0u32, 1] {
            let a = drill(best, Grade::B, hoppers);
            let st = a.stats(&w.species);
            if hoppers == 1 && st.speed > 0 {
                // Hands: WORK_PER_UNIT / HAND_WORK_PER_TICK ticks per unit.
                let hand_ticks = sim::tuning::WORK_PER_UNIT / sim::tuning::HAND_WORK_PER_TICK;
                let drill_ticks = sim::tuning::WORK_PER_UNIT.div_ceil(st.speed);
                if drill_ticks < hand_ticks {
                    beats_hands += 1;
                }
                // Grade B yields 2 ore per unit mined.
                let per_unit = sim::tuning::YIELD_BY_GRADE[Grade::B as usize];
                let units = st.capacity / per_unit;
                let fill = units * drill_ticks;
                rows.push((st.speed, fill, smelter_ticks(&a), hand_ticks, st.capacity));
            }
        }
    }
    rows.sort_unstable();
    let med = rows[rows.len() / 2];
    let mean = |f: fn(&(u32, u32, u32, u32, u32)) -> u32| {
        rows.iter().map(f).sum::<u32>() as f64 / rows.len() as f64
    };
    println!("{worlds} worlds with a buildable starter species, one-hopper drill at grade B");
    println!(
        "speed mean {:.1} work/tick; {:.2} ticks per unit against the hands' {}",
        mean(|r| r.0),
        mean(|r| sim::tuning::WORK_PER_UNIT.div_ceil(r.0)),
        sim::tuning::WORK_PER_UNIT / sim::tuning::HAND_WORK_PER_TICK,
    );
    println!(
        "beats bare hands on rate: {beats_hands} of {} ({:.1}%)",
        rows.len(),
        100.0 * f64::from(beats_hands) / rows.len() as f64
    );
    println!(
        "capacity {} ore -> UNATTENDED RUN mean {:.0} ticks, median {} ({:.0}% of the {DEMO_TICKS}-tick demo loop)",
        med.4,
        mean(|r| r.1),
        med.1,
        100.0 * f64::from(med.1) / f64::from(DEMO_TICKS)
    );
    println!(
        "parts cost {} smelter ticks ({:.0}% of the demo loop), before the ore to feed it",
        med.2,
        100.0 * f64::from(med.2) / f64::from(DEMO_TICKS)
    );
    let zero = drill(
        host_world(1)
            .species
            .iter()
            .find(|s| sim::ladder::hand_minable(s))
            .unwrap(),
        Grade::B,
        0,
    );
    assert!(
        beats_hands * 2 > u32::try_from(rows.len()).unwrap(),
        "a drill that loses to bare hands in most worlds is not a throughput upgrade: {beats_hands} of {}",
        rows.len()
    );
    println!(
        "no-hopper drill: capacity {} ore, parts cost {} smelter ticks",
        zero.stats(&host_world(1).species).capacity,
        smelter_ticks(&zero)
    );
}

/// THE FOLLOW-UP THAT MATTERS: the only way to buy a longer unattended run is
/// more hoppers, and hoppers are mass. If the hopper count that makes a drill
/// worth leaving alone is the count that breaks it, the tuning forbids the
/// machine's own purpose.
#[test]
fn can_a_drill_afford_the_hoppers_that_make_it_useful() {
    const SEEDS: u32 = 500;
    let mut safe = [0u32; 5];
    let mut runs = [0u64; 5];
    let mut worlds = 0u32;
    for seed in 1..=u64::from(SEEDS) {
        let w = host_world(seed);
        let Some(best) = w
            .species
            .iter()
            .filter(|s| sim::ladder::hand_minable(s))
            .filter(|s| sim::ladder::usable_from_bare_hands(&w.species, s.id))
            .max_by_key(|s| s.sheet.hardness)
        else {
            continue;
        };
        worlds += 1;
        for hoppers in 0..=4usize {
            let a = drill(best, Grade::B, hoppers as u32);
            let st = a.stats(&w.species);
            // Exact mass against exact budget: not the banded verdict, the
            // fact underneath it.
            if st.mass <= st.budget {
                safe[hoppers] += 1;
            }
            if st.speed > 0 {
                let per_unit = sim::tuning::YIELD_BY_GRADE[Grade::B as usize];
                let ticks = sim::tuning::WORK_PER_UNIT.div_ceil(st.speed);
                runs[hoppers] += u64::from((st.capacity / per_unit) * ticks);
            }
        }
    }
    println!("{worlds} worlds, drill from the best starter species at grade B");
    for h in 0..=4usize {
        println!(
            "  {h} hopper(s): survives placement in {:>5.1}% of worlds · mean unattended run {:>4} ticks ({:>4.1}s at 10 tps)",
            100.0 * f64::from(safe[h]) / f64::from(worlds),
            runs[h] / u64::from(worlds),
            (runs[h] / u64::from(worlds)) as f64 / 10.0
        );
    }

    // THE SHAPE, PINNED; THE PERCENTAGES, NOT. The numbers above are a
    // measurement and will move with any retune. What must not move without
    // someone deciding to is the drill's one design decision: **a hopper buys
    // runtime and spends survival**. If a retune ever makes hoppers free, or
    // makes them stop buying anything, the machine has quietly lost its
    // trade-off and this reddens.
    for h in 1..=4usize {
        assert!(
            runs[h] > runs[h - 1],
            "hopper {h} must buy runtime: {} vs {}",
            runs[h],
            runs[h - 1]
        );
        assert!(
            safe[h] <= safe[h - 1],
            "hopper {h} must cost survival, never add it: {} vs {}",
            safe[h],
            safe[h - 1]
        );
    }
    assert!(
        safe[4] * 10 < safe[0] * 9,
        "four hoppers must cost a real share of worlds, not a rounding error: {} vs {}",
        safe[4],
        safe[0]
    );
}
