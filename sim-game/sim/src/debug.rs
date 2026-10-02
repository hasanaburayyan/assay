//! Plain-text views of the world for terminals, logs and tests.
//! Debugging aids only; real rendering lives outside the sim.

use std::fmt::Write;

use crate::assembly::{Assembly, BreakVerdict, Built, Mount, PART_SPECS, PartKind, Source};
use crate::building::{Building, BuildingKind, Machine};
use crate::item::ItemStack;
use crate::mineral::{Grade, MineralSpecies, Property, Sheet};
use crate::recipe::{RECIPES, Station};
use crate::tuning::{FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, SMELTER_OUTPUT_CAP};
use crate::types::{PlayerId, TilePos};
use crate::world::World;

pub const MAP_LEGEND: &str =
    "P player   @ spawn   M smelter   letters = ore by species initial (lowercase = depleted)";

/// One-line summary: seed, tick, size, deposit count and state hash.
pub fn summary(world: &World) -> String {
    format!(
        "seed {} · tick {} · {}x{} tiles · {} species · {} deposits · hash {:016x}",
        world.seed,
        world.tick,
        world.width(),
        world.height(),
        world.species.len(),
        world.deposits.len(),
        world.state_hash()
    )
}

/// The map letter for a species: its generated name's initial, which is
/// unique per world (player names need not be).
pub fn species_symbol(species: &MineralSpecies) -> char {
    species
        .generated_name
        .chars()
        .next()
        .map_or('?', |c| c.to_ascii_uppercase())
}

/// ASCII map, one character per tile.
pub fn ascii_map(world: &World) -> String {
    let spawn = world.spawn_tile();
    let mut out = String::new();
    for y in 0..world.height() {
        for x in 0..world.width() {
            let pos = TilePos::new(x, y);
            let c = if world.players.iter().any(|p| p.pos == pos) {
                'P'
            } else if world.building_at(pos).is_some() {
                'M'
            } else if pos == spawn {
                '@'
            } else if let Some(d) = world.deposit_at(pos) {
                let s = species_symbol(world.species(d.species));
                if d.is_depleted() {
                    s.to_ascii_lowercase()
                } else {
                    s
                }
            } else {
                '.'
            };
            out.push(c);
        }
        out.push('\n');
    }
    out
}

/// Table of every deposit.
pub fn deposit_table(world: &World) -> String {
    let mut out = format!(
        "{:>4}  {:<12} {:>10}  {:>6}  {:>6}  {:>6}  {:>5}\n",
        "id", "species", "center", "radius", "amount", "purity", "grade"
    );
    for d in &world.deposits {
        let center = format!("({}, {})", d.center.x, d.center.y);
        let _ = writeln!(
            out,
            "{:>4}  {:<12} {:>10}  {:>6}  {:>6}  {:>6}  {:>5}",
            d.id.0,
            world.species(d.species).name(),
            center,
            d.radius,
            d.amount,
            d.purity,
            d.grade().letter()
        );
    }
    out
}

/// One property as a player sees it: exact once assayed, else its band.
pub fn reading(species: &MineralSpecies, property: Property) -> String {
    let v = species.sheet.get(property);
    if species.assayed {
        v.to_string()
    } else {
        let (lo, hi) = Sheet::band(v);
        format!("{lo}-{hi}")
    }
}

/// Table of every species with its sheet as the players know it (rough
/// bands until assayed), plus what the sheet means for the rules that
/// exist today. Notes use the exact values: the ground knows what it is.
pub fn species_table(world: &World) -> String {
    let mut out = format!(
        "{:>2}  {:<12} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6}  notes\n",
        "id", "name", "dens", "str", "hard", "heat", "reac", "cond"
    );
    for s in &world.species {
        let sh = &s.sheet;
        let mut notes = Vec::new();
        if !s.assayed {
            notes.push("rough: stand on it and `assay`".to_string());
        }
        if let Some(d) = s.discoverer {
            let who = world
                .player(d)
                .map_or(format!("player {}", d.0), |p| p.name.clone());
            notes.push(format!("found by {who}"));
        }
        if u32::from(sh.hardness) <= HAND_MINE_MAX_HARDNESS {
            notes.push("hand-minable".to_string());
        }
        for grade in Grade::ALL.into_iter().rev() {
            if s.effective(Property::Reactivity, grade) >= FUEL_MIN_REACTIVITY {
                notes.push(format!("fuel at {} or better", grade.letter()));
                break;
            }
        }
        let _ = sh;
        let _ = writeln!(
            out,
            "{:>2}  {:<12} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6}  {}",
            s.id.0,
            s.name(),
            reading(s, Property::Density),
            reading(s, Property::Strength),
            reading(s, Property::Hardness),
            reading(s, Property::HeatTolerance),
            reading(s, Property::Reactivity),
            reading(s, Property::Conductivity),
            notes.join(", ")
        );
    }
    out
}

/// Table of every recipe.
pub fn recipe_table() -> String {
    let mut out = format!(
        "{:<8} {:<16} {:<12} {:>5}  {:<16} needs\n",
        "name", "makes", "from", "ticks", "where"
    );
    for r in &RECIPES {
        let from = format!("{} {}", r.input.1, r.input.0.name());
        let makes = format!(
            "{} {}{}",
            r.output.1,
            r.output.0.name(),
            if r.raises_grade { " +1 grade" } else { "" }
        );
        let station = match r.station {
            Station::Hand => "by hand (craft)",
            Station::Smelter => "in a smelter",
        };
        let mut needs: Vec<String> = r
            .requires
            .iter()
            .map(|(p, min)| format!("{} ≥ {min}", p.name()))
            .collect();
        if r.station == Station::Smelter {
            needs.push("fire ≥ the ore's heat tolerance".into());
        }
        let _ = writeln!(
            out,
            "{:<8} {makes:<16} {from:<12} {:>5}  {station:<16} {}",
            r.name,
            r.ticks,
            if needs.is_empty() {
                "nothing".to_string()
            } else {
                needs.join(", ")
            }
        );
    }
    out.push_str(
        "Every recipe keeps the input's species. sort and resmelt raise its grade by one\n(C->B->A) and lose two thirds of the material; by hand: craft sort <ore> [n].\n",
    );
    out
}

fn slot(world: &World, stack: Option<ItemStack>) -> String {
    stack.map_or("empty".to_string(), |st| {
        format!("{} {}", st.count, world.item_name(st.item))
    })
}

/// The parts a design is made of, as `handle(Korvite B 150) + head(Adaite A
/// 26-50)`.
///
/// **The mass is per part and banded like every other sheet reading**, because
/// a player looking at an over-budget design picks which part to change out of
/// this line, and the heaviest non-frame part is also the one a break always
/// loses. Last on the line on purpose: the inspector's side panel truncates it
/// and the kinds and species must survive that.
pub fn parts_summary(world: &World, assembly: &Assembly) -> String {
    assembly
        .parts()
        .map(|p| {
            let species = world.species(p.material.species);
            let (low, high) = Assembly::part_mass_range(p, species);
            format!(
                "{}({} {} {})",
                p.kind.name(),
                species.name(),
                p.material.grade.letter(),
                if low == high {
                    low.to_string()
                } else {
                    format!("{low}-{high}")
                }
            )
        })
        .collect::<Vec<_>>()
        .join(" + ")
}

/// One line describing a planted machine.
///
/// **No durability here, on purpose** (Game Director's ruling on ASSA-5):
/// the head contributes a durability pool whatever frame it sits on, but
/// decision 12 parks drill wear, so on a planted machine that number would
/// never move — and a number that never moves teaches a mechanic that does not
/// exist. The catalogue row is untouched; this is a display rule.
pub fn machine_status(world: &World, b: &Building, m: &Machine) -> String {
    let range = m.assembly.stat_range(&world.species);
    let show = |low: u32, high: u32| {
        if low == high {
            low.to_string()
        } else {
            format!("{low}-{high}")
        }
    };
    // Capacity is flat from the kind, so it is exact whether or not anyone has
    // assayed anything; mass and speed are read off sheets and are not.
    let capacity = range.low.capacity;
    let state = match world.deposit_at(b.pos) {
        None => "idle: no deposit underneath".to_string(),
        Some(_) if m.held.is_some_and(|h| h.count >= capacity) => "stalled: full".to_string(),
        // Deliberately not "working": decision 12 parks drill wear and the
        // mining system is ASSA-6, so today a planted machine sits on its
        // deposit and does nothing. Saying otherwise would be a lie in the
        // one place a player looks to find out.
        Some(d) => format!("on {}", world.species(d.species).name()),
    };
    // Same reason as `assembly_readout`: what it is holding and what it is
    // doing come before the design it was built from, because the table line
    // is truncated in the inspector's side panel.
    format!(
        "holding {} of {} · {state} · mass {} of {} budget · speed {} · {}",
        m.held.map_or(0, |h| h.count),
        capacity,
        show(range.low.mass, range.high.mass),
        show(range.low.budget, range.high.budget),
        show(range.low.speed, range.high.speed),
        parts_summary(world, &m.assembly),
    )
}

/// One line describing what a building holds and whether it is working.
pub fn building_status(world: &World, b: &Building) -> String {
    let s = match &b.kind {
        BuildingKind::Smelter(s) => s,
        BuildingKind::Machine(m) => return machine_status(world, b, m),
    };
    let walls = world.max_temperature(b);
    let needs = s
        .input
        .map(|i| u32::from(world.species(i.item.species).sheet.heat_tolerance));
    let state = if s.input.is_none() {
        "idle: nothing to refine".to_string()
    } else if s.output.is_some_and(|o| o.count >= SMELTER_OUTPUT_CAP) {
        "stalled: output full".to_string()
    } else if s.burn_left == 0 && s.fuel.is_none() {
        "stalled: no fuel".to_string()
    } else if s.burn_left == 0 {
        "stalled: fuel won't light from cold".to_string()
    } else if needs.is_some_and(|n| s.burn_temperature.min(walls) < n) {
        format!(
            "stalled: fire {} too cool for ore needing {}",
            s.burn_temperature.min(walls),
            needs.unwrap_or(0)
        )
    } else {
        format!("working at {}", s.burn_temperature.min(walls))
    };
    format!(
        "walls {walls} · in {} · fuel {} ({} ticks burning at {}) · out {} · {state}",
        slot(world, s.input),
        slot(world, s.fuel),
        s.burn_left,
        s.burn_temperature,
        slot(world, s.output)
    )
}

/// Table of every building.
pub fn building_table(world: &World) -> String {
    if world.buildings.is_empty() {
        return "No buildings yet. Craft a smelter from 5 ore and `place smelter`.\n".into();
    }
    let mut out = format!("{:>4}  {:<8} {:>9}  status\n", "id", "kind", "at");
    for b in &world.buildings {
        let _ = writeln!(
            out,
            "{:>4}  {:<8} {:>9}  {} · {}",
            b.id.0,
            b.kind.name(),
            format!("({}, {})", b.pos.x, b.pos.y),
            world.item_name(b.material),
            building_status(world, b)
        );
    }
    out
}

/// The part catalogue: every row, what it costs, and what it contributes.
///
/// Generated from `PART_SPECS` and naming no kind, so a row added to the
/// catalogue appears here without this function being touched.
pub fn part_table() -> String {
    let mut out = format!("{:<8} {:<9} {:>5}  contributes\n", "name", "mount", "size");
    for s in &PART_SPECS {
        let mount = match s.kind {
            PartKind::Frame(Mount::Held) => "held",
            PartKind::Frame(Mount::Planted) => "planted",
            _ => "mounted",
        };
        let gives = s
            .contributions
            .iter()
            .map(|c| match c.source {
                Source::Property(p) => format!("{:?} from {}", c.stat, p.name()),
                Source::Flat(n) => format!("{:?} {n}", c.stat),
            })
            .collect::<Vec<_>>()
            .join(", ");
        let _ = writeln!(out, "{:<8} {mount:<9} {:>5}  {gives}", s.name, s.size);
    }
    let _ = write!(
        out,
        "\nsize is both the refined cost and how much stuff the part is made of for\n\
         mass. A frame carries mass = size x strength x {}; over that, the design\n\
         breaks when it is planted or first used. `make <part> <refined>` then\n\
         `assemble <frame> <part>...`.\n",
        crate::tuning::FRAME_BUDGET_PER_STRENGTH
    );
    out
}

/// THE DURABILITY POOL AS A PLAYER MAY READ IT: exact against the exact pool
/// once every species in the design is assayed, a percentage of the banded
/// pool while any of them is still rough.
///
/// **Public and shared on purpose.** The Godot part menu shows this same
/// number (`sim-godot`'s `designs_of`), and A10 is a rule about what a player
/// is allowed to know, not a formatting preference — two hosts spelling it
/// two ways is how the leak comes back in one of them. One wording, one place.
///
/// The denominator is the TRUE max from `stats()`, never a band end: a
/// percentage over a published band end is the exact pool with extra
/// arithmetic. `div_ceil` so a pick with swings left never reads 0%.
pub fn durability_readout(world: &World, built: &Built) -> String {
    let range = built.assembly.stat_range(&world.species);
    let max = built.assembly.stats(&world.species).durability;
    if range.low.durability == range.high.durability {
        format!("{}/{}", built.durability, max)
    } else {
        format!(
            "{}% of {}-{}",
            (100 * built.durability).div_ceil(max.max(1)),
            range.low.durability,
            range.high.durability
        )
    }
}

/// One line for a design the player has built: what it is, what it weighs
/// against its budget, and the verdict.
///
/// The verdict and the numbers come from `sim` (the Game Director's ruling on
/// ASSA-5): two clients computing this would eventually disagree, and a
/// renderer does not own rules. Banded while any part's species is unassayed,
/// exact once they are all known.
///
/// **Durability only for a held frame** (same ruling): the head contributes a
/// pool whatever frame it sits on, but drill wear is parked, so showing it on a
/// planted design would teach a mechanic that does not exist.
///
/// **The pool itself is banded like everything else** (amendment A10): exact
/// against its true max once the sheet is known, a percentage of the pool's
/// *class* while it is not. See the held branch for why a number there was a
/// leak.
pub fn assembly_readout(world: &World, built: &Built) -> String {
    let a = &built.assembly;
    let range = a.stat_range(&world.species);
    let show = |low: u32, high: u32| {
        if low == high {
            low.to_string()
        } else {
            format!("{low}-{high}")
        }
    };
    // Verdict first, then the numbers, then the parts. Deliberate: a side
    // panel is narrow and the line gets truncated, so the thing the player
    // needs before spending parts must not be the thing that is cut.
    let mut out = format!(
        "{} · mass {} of {} budget",
        range.verdict().label(),
        show(range.low.mass, range.high.mass),
        show(range.low.budget, range.high.budget),
    );
    match a.mount() {
        Some(Mount::Held) => {
            // THE POOL IS NEVER PRINTED AS A NUMBER WHILE THE SHEET IS BANDED
            // (ADR 0003 amendment A10). `pool_max = HEAD_SIZE x eff strength x
            // PICK_DURABILITY_PER_STRENGTH`, and both constants are published,
            // so an exact pool divided by 60 *is* the head's effective
            // strength -- and `(pool + 20 x swings) / 60` recovers it at any
            // moment, not only at full. It was the one `Source::Property` stat
            // read exactly while mass and budget were banded, which made a
            // pick a free assay of strength.
            //
            // The denominator is the TRUE max from `stats()`, never a band
            // end: a percentage over a published band end is the exact pool
            // with extra arithmetic. `div_ceil` so a pick with swings left
            // never reads 0%.
            let _ = write!(out, " · durability {}", durability_readout(world, built));
        }
        _ => {
            let _ = write!(
                out,
                " · holds {}",
                show(range.low.capacity, range.high.capacity)
            );
        }
    }
    let _ = write!(
        out,
        " · speed {} · {}",
        show(range.low.speed, range.high.speed),
        parts_summary(world, a)
    );
    if range.verdict() != BreakVerdict::Safe {
        let _ = write!(
            out,
            "\n      {}",
            match range.verdict() {
                BreakVerdict::WillBreak =>
                    "this is over budget: it will break when planted or first used",
                _ => "assay every species in it to know whether it will hold",
            }
        );
    }
    out
}

/// What the player has built but not placed, and what is in their hand.
pub fn built_table(world: &World, player: PlayerId) -> String {
    let Some(p) = world.player(player) else {
        return "No such player.\n".into();
    };
    let mut out = String::new();
    match &p.tool {
        Some(t) => {
            let _ = writeln!(out, "in hand  {}", assembly_readout(world, t));
        }
        None => out.push_str("in hand  nothing (bare hands)\n"),
    }
    if p.assemblies.is_empty() {
        out.push_str(
            "built    nothing. `parts` lists the catalogue; `make <part> <refined>`\n\
             \x20        then `assemble <frame> <part>...`.\n",
        );
        return out;
    }
    for (i, built) in p.assemblies.iter().enumerate() {
        let _ = writeln!(out, "{i:>5}    {}", assembly_readout(world, built));
    }
    let _ = write!(
        out,
        "\n`equip <n>` takes a held design in hand; `plant <n> [x y]` puts a planted\n\
         one on the map.\n"
    );
    out
}
