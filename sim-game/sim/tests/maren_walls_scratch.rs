//! SCRATCH (Maren). Is a minable-but-unsmeltable rock scenery, or is it the
//! smelter you have to build? `ladder::rungs` sets walls to the max heat
//! tolerance of every MINABLE species, so the model already assumes you
//! build your smelter from the hottest rock you can mine -- including one
//! you can never refine. This asks whether that rock is load-bearing.
use sim::ladder;
use sim::mineral::{MineralSpecies, Property};
use sim::tuning::{FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, HAND_SPARK_TEMPERATURE};
use sim::{Grade, World, WorldConfig};

fn world(seed: u64) -> World {
    World::new(WorldConfig { seed, ..WorldConfig::default() })
}

fn burn(s: &MineralSpecies) -> Option<u32> {
    let t = s.effective(Property::Reactivity, Grade::B);
    (t >= FUEL_MIN_REACTIVITY).then_some(t)
}

fn best_fire(minable: &[&MineralSpecies]) -> u32 {
    let mut fire = 0u32;
    loop {
        let spark = HAND_SPARK_TEMPERATURE.max(fire);
        let reachable = minable.iter()
            .filter(|s| u32::from(s.sheet.heat_tolerance) <= spark)
            .filter_map(|s| burn(s)).max().unwrap_or(0);
        if reachable <= fire { return fire; }
        fire = reachable;
    }
}

/// Rung zero, given a ceiling on what the walls can be.
fn rung_zero(minable: &[&MineralSpecies], walls: u32) -> Vec<u8> {
    let fire = best_fire(minable);
    let cap = walls.min(fire);
    let mut v: Vec<u8> = minable.iter()
        .filter(|s| u32::from(s.sheet.heat_tolerance) <= cap)
        .map(|s| s.id.0).collect();
    v.sort_unstable();
    v
}

#[test]
fn is_unsmeltable_rock_scenery_or_the_smelter_you_must_build() {
    const N: u64 = 5000;
    let (mut worlds_with, mut load_bearing, mut walls_binding) = (0u64, 0u64, 0u64);
    let mut example = None;
    for seed in 0..N {
        let w = world(seed);
        let minable: Vec<&MineralSpecies> = w.species.iter()
            .filter(|s| u32::from(s.sheet.hardness) <= HAND_MINE_MAX_HARDNESS).collect();
        if minable.is_empty() { continue; }
        let walls_all = minable.iter().map(|s| u32::from(s.sheet.heat_tolerance)).max().unwrap_or(0);
        let base = rung_zero(&minable, walls_all);
        let fire = best_fire(&minable);
        // The unsmeltable minable species: mined, never refined.
        let unsmelt: Vec<&&MineralSpecies> = minable.iter()
            .filter(|s| !base.contains(&s.id.0)).collect();
        if unsmelt.is_empty() { continue; }
        worlds_with += 1;
        if walls_all < fire { walls_binding += 1; }
        // Walls you could get WITHOUT ever mining an unsmeltable species.
        let walls_without = minable.iter()
            .filter(|s| base.contains(&s.id.0))
            .map(|s| u32::from(s.sheet.heat_tolerance)).max().unwrap_or(0);
        let shrunk = rung_zero(&minable, walls_without);
        if shrunk != base {
            load_bearing += 1;
            if example.is_none() {
                example = Some((seed, base.clone(), shrunk.clone(), walls_all, walls_without, fire));
            }
        }
    }
    println!("worlds holding a minable-but-unsmeltable species: {worlds_with} of {N}");
    println!("  where that rock's WALLS are load-bearing (rung zero shrinks without it): {load_bearing} ({:.1}%)",
        100.0 * load_bearing as f64 / worlds_with as f64);
    println!("  where walls, not fire, are the binding limit at all: {walls_binding}");
    println!("example (seed, rung0, rung0_without, walls_all, walls_without, fire): {example:?}");
}

/// My first attempt at "is the rock load-bearing" was VACUOUS: `walls_without`
/// was the max heat tolerance OF the base set, so filtering the base set by it
/// always returns the base set. A check must not share a quantity with the
/// thing it checks. The non-circular question is simply whether the `walls`
/// term in `ladder::rungs` ever binds at all: rung zero caps at
/// `walls.min(fire)`, so if walls >= fire always, the wall material is
/// irrelevant and no rock is ever worth mining for its heat tolerance.
#[test]
fn does_the_walls_term_ever_bind() {
    const N: u64 = 20000;
    let (mut worlds, mut walls_bind, mut equal) = (0u64, 0u64, 0u64);
    let mut min_margin = i64::MAX;
    for seed in 0..N {
        let w = world(seed);
        let minable: Vec<&MineralSpecies> = w.species.iter()
            .filter(|s| u32::from(s.sheet.hardness) <= HAND_MINE_MAX_HARDNESS).collect();
        if minable.is_empty() { continue; }
        worlds += 1;
        let walls = minable.iter().map(|s| u32::from(s.sheet.heat_tolerance)).max().unwrap_or(0);
        let fire = best_fire(&minable);
        let margin = i64::from(walls) - i64::from(fire);
        min_margin = min_margin.min(margin);
        if margin < 0 { walls_bind += 1; }
        if margin == 0 { equal += 1; }
    }
    println!("worlds with a minable species: {worlds} of {N}");
    println!("  walls < fire (the walls term actually binds): {walls_bind}");
    println!("  walls == fire (exactly on the line):          {equal}");
    println!("  smallest walls-minus-fire margin seen:        {min_margin}");
}

/// THE REAL QUESTION. `ladder::rungs` sets walls to the max heat tolerance of
/// every MINABLE species -- it assumes the player built their smelter from the
/// hottest rock they can mine. A smelter's real walls are its OWN species'
/// heat tolerance. So a player who builds from the rock they are standing on
/// can get a worse smelter than the reachability model promises, and nothing
/// in the game tells them the choice matters.
#[test]
fn does_building_from_the_starter_rock_cost_you_rung_zero() {
    const N: u64 = 5000;
    let (mut worlds, mut worse, mut shrinks) = (0u64, 0u64, 0u64);
    let mut example = None;
    for seed in 0..N {
        let w = world(seed);
        let minable: Vec<&MineralSpecies> = w.species.iter()
            .filter(|s| u32::from(s.sheet.hardness) <= HAND_MINE_MAX_HARDNESS).collect();
        if minable.is_empty() { continue; }
        let Some((material, _fuel)) = ladder::starter_species(&w.species) else { continue };
        worlds += 1;
        let best_walls = minable.iter().map(|s| u32::from(s.sheet.heat_tolerance)).max().unwrap_or(0);
        let starter_walls = u32::from(w.species[usize::from(material.0)].sheet.heat_tolerance);
        if starter_walls < best_walls { worse += 1; }
        let model = rung_zero(&minable, best_walls);
        let actual = rung_zero(&minable, starter_walls);
        if actual != model {
            shrinks += 1;
            if example.is_none() {
                example = Some((seed, w.species[usize::from(material.0)].name().to_string(),
                    starter_walls, best_walls, best_fire(&minable), model.len(), actual.len()));
            }
        }
    }
    println!("worlds: {worlds}");
    println!("  starter rock gives WORSE walls than the best minable rock: {worse} ({:.1}%)",
        100.0 * worse as f64 / worlds as f64);
    println!("  and that actually SHRINKS rung zero for the player:        {shrinks} ({:.1}%)",
        100.0 * shrinks as f64 / worlds as f64);
    println!("example (seed, starter, its walls, best walls, fire, rung0 model, rung0 actual): {example:?}");
}

/// THE SAFETY CLAIM, checked rather than argued. If a player builds their
/// smelter from the starter rock they are standing on, can they always still
/// refine that same rock? If yes, the finding above costs variety, not
/// progress, and the demo's critical path is never blocked.
#[test]
fn the_starter_rock_can_always_be_smelted_in_its_own_smelter() {
    const N: u64 = 20000;
    let (mut worlds, mut blocked) = (0u64, 0u64);
    for seed in 0..N {
        let w = world(seed);
        let minable: Vec<&MineralSpecies> = w.species.iter()
            .filter(|s| u32::from(s.sheet.hardness) <= HAND_MINE_MAX_HARDNESS).collect();
        if minable.is_empty() { continue; }
        let Some((material, _)) = ladder::starter_species(&w.species) else { continue };
        worlds += 1;
        let heat = u32::from(w.species[usize::from(material.0)].sheet.heat_tolerance);
        // Smelter built from the starter rock: walls = its own heat tolerance.
        let cap = heat.min(best_fire(&minable));
        if heat > cap { blocked += 1; }
    }
    println!("worlds checked: {worlds}");
    println!("  where the starter rock CANNOT be refined in a smelter made of itself: {blocked}");
    assert_eq!(blocked, 0, "the demo's critical path would be blocked in some world");
}
