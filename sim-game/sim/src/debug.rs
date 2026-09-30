//! Plain-text views of the world for terminals, logs and tests.
//! Debugging aids only; real rendering lives outside the sim.

use std::fmt::Write;

use crate::recipe::{RECIPES, Station};
use crate::types::TilePos;
use crate::world::World;

pub const MAP_LEGEND: &str =
    "P player   @ spawn   I iron   C copper   K coal   S stone   (lowercase = depleted)";

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
