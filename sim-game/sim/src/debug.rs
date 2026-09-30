//! Plain-text views of the world for terminals, logs and tests.
//! Debugging aids only; real rendering lives outside the sim.

use std::fmt::Write;

use crate::building::BuildingKind;
use crate::recipe::{RECIPES, Station};
use crate::types::TilePos;
use crate::world::World;

pub const MAP_LEGEND: &str = "P player   @ spawn   M smelter   I iron   C copper   K coal   S stone   (lowercase = depleted)";

/// One-line summary: seed, tick, size, deposit count and state hash.
pub fn summary(world: &World) -> String {
    format!(
        "seed {} · tick {} · {}x{} tiles · {} deposits · hash {:016x}",
        world.seed,
        world.tick,
        world.width(),
        world.height(),
        world.deposits.len(),
        world.state_hash()
    )
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
                if d.is_depleted() {
                    d.kind.symbol().to_ascii_lowercase()
                } else {
                    d.kind.symbol()
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
        "{:>4}  {:<7} {:>10}  {:>6}  {:>6}  {:>6}\n",
        "id", "kind", "center", "radius", "amount", "purity"
    );
    for d in &world.deposits {
        let center = format!("({}, {})", d.center.x, d.center.y);
        let kind = format!("{:?}", d.kind);
        let _ = writeln!(
            out,
            "{:>4}  {:<7} {:>10}  {:>6}  {:>6}  {:>6}",
            d.id.0, kind, center, d.radius, d.amount, d.purity
        );
    }
    out
}

/// Table of every recipe.
pub fn recipe_table() -> String {
    let mut out = format!(
        "{:<13} {:<24} {:>5}  {}\n",
        "makes", "from", "ticks", "where"
    );
    for r in &RECIPES {
        let inputs = r
            .inputs
            .iter()
            .map(|(item, n)| format!("{n} {}", item.name()))
            .collect::<Vec<_>>()
            .join(" + ");
        let makes = format!("{} {}", r.output.1, r.output.0.name());
        let station = match r.station {
            Station::Hand => "by hand (craft)",
            Station::Smelter => "in a smelter",
        };
        let _ = writeln!(out, "{makes:<13} {inputs:<24} {:>5}  {station}", r.ticks);
    }
    out
}

/// One line describing what a building holds and whether it is working.
pub fn building_status(b: &crate::building::Building) -> String {
    let BuildingKind::Smelter(s) = &b.kind;
    let slot = |stack: Option<crate::item::ItemStack>| {
        stack.map_or("empty".to_string(), |st| {
            format!("{} {}", st.count, st.item.name())
        })
    };
    let state = if s.input.is_none() {
        "idle: no ore"
    } else if s
        .output
        .is_some_and(|o| o.count >= crate::tuning::SMELTER_OUTPUT_CAP)
    {
        "stalled: output full"
    } else if s.fuel == 0 && s.burn_left == 0 {
        "stalled: no fuel"
    } else {
        "working"
    };
    format!(
        "in {} · fuel {} coal (+{} ticks burning) · out {} · {state}",
        slot(s.input),
        s.fuel,
        s.burn_left,
        slot(s.output)
    )
}

/// Table of every building.
pub fn building_table(world: &World) -> String {
    if world.buildings.is_empty() {
        return "No buildings yet. Craft a smelter and `place smelter`.\n".into();
    }
    let mut out = format!("{:>4}  {:<8} {:>9}  status\n", "id", "kind", "at");
    for b in &world.buildings {
        let _ = writeln!(
            out,
            "{:>4}  {:<8} {:>9}  {}",
            b.id.0,
            b.kind.name(),
            format!("({}, {})", b.pos.x, b.pos.y),
            building_status(b)
        );
    }
    out
}
