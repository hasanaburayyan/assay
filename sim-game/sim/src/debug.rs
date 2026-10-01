//! Plain-text views of the world for terminals, logs and tests.
//! Debugging aids only; real rendering lives outside the sim.

use std::fmt::Write;

use crate::assembly::Assembly;
use crate::building::{Building, BuildingKind, Machine};
use crate::item::ItemStack;
use crate::mineral::{Grade, MineralSpecies, Property, Sheet};
use crate::recipe::{RECIPES, Station};
use crate::tuning::{FUEL_MIN_REACTIVITY, HAND_MINE_MAX_HARDNESS, SMELTER_OUTPUT_CAP};
use crate::types::TilePos;
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

/// The parts a design is made of, as `handle(Korvite B) + head(Adaite A)`.
pub fn parts_summary(world: &World, assembly: &Assembly) -> String {
    assembly
        .parts()
        .map(|p| {
            format!(
                "{}({} {})",
                p.kind.name(),
                world.species(p.material.species).name(),
                p.material.grade.letter()
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
    let stats = m.assembly.stats(&world.species);
    let state = if world.deposit_at(b.pos).is_none() {
        "idle: no deposit underneath".to_string()
    } else if m.held.is_some_and(|h| h.count >= stats.capacity) {
        "stalled: full".to_string()
    } else {
        "working".to_string()
    };
    format!(
        "{} · mass {}/{} · speed {} · holding {} of {} · {state}",
        parts_summary(world, &m.assembly),
        stats.mass,
        stats.budget,
        stats.speed,
        m.held.map_or(0, |h| h.count),
        stats.capacity,
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
