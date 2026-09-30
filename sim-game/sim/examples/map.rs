//! Print a world as ASCII, with no renderer involved.
//!
//!     cargo run --example map                          # seed 1
//!     cargo run --example map -- 42                    # seed 42
//!     cargo run --example map -- 42 --save             # also write sim-game/saves/world-42.json
//!     cargo run --example map -- --load saves/world-42.json

use std::process::exit;

use sim::{World, WorldConfig, debug};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let save = args.iter().any(|a| a == "--save");
    let load_path = args.iter().position(|a| a == "--load").map(|i| {
        args.get(i + 1).cloned().unwrap_or_else(|| {
            eprintln!("--load needs a file path, e.g. --load saves/world-42.json");
            exit(1);
        })
    });

    // Saves always live in `sim-game/saves/`, whichever folder you run from.
    let saves = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("sim sits inside the sim-game workspace")
        .join("saves");

    let world = match &load_path {
        Some(path) => World::load_json(path).unwrap_or_else(|e| {
            eprintln!("Could not load {path}: {e}");
            exit(1);
        }),
        None => {
            let seed = args.iter().find_map(|a| a.parse().ok()).unwrap_or(1);
            World::new(WorldConfig {
                seed,
                width_chunks: 6,
                height_chunks: 4,
            })
        }
    };

    println!("{}\n", debug::summary(&world));
    println!("{}", debug::ascii_map(&world));
    println!("{}\n", debug::MAP_LEGEND);
    print!("{}", debug::deposit_table(&world));

    if save {
        let path = saves.join(format!("world-{}.json", world.seed));
        if let Err(e) = world.save_json(&path) {
            eprintln!("Could not save {}: {e}", path.display());
            exit(1);
        }
        println!("\nSaved to {}", path.display());
    }
}
