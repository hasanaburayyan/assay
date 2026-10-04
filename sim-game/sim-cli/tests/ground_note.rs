//! `at` on a tile with a building no longer calls that tile empty (ASSA-146),
//! driven through the REAL `sim-cli --plain` binary.
//!
//! **IT IS DRIVEN THROUGH THE BINARY FOR `reach.rs`'s REASON.** A unit test on
//! `debug::ground_note` proves the sentence is right and stays green if no
//! command ever prints it — and here that risk is not hypothetical: the fix
//! deletes a literal from this crate and replaces it with a call, so a
//! half-applied version compiles and says nothing at all on a bare tile.
//!
//! Three reads off one world, because the complaint is about composition and a
//! single read cannot show it:
//!
//! 1. the tile a smelter stands on — the bug: two lines, one naming the
//!    building and one that used to call the same tile empty;
//! 2. a bare tile with nothing on it — the control that the ground line still
//!    exists at all, and the one a fix-by-deletion would also pass;
//! 3. the deposit the player mined — the control that the case which already
//!    composed correctly reads exactly as it did before.

mod common;

use std::io::Write;
use std::process::{Command, Stdio};

use common::walk;
use sim::TilePos;

/// Tiles with no deposit whose 2×2 smelter footprint is on the map, nearest
/// `from` first so the script's walk is short.
///
/// Searched rather than hard-coded: there is one deposit per chunk and a
/// pinned tile would sometimes be covered, which would quietly turn read 1
/// into a second copy of read 3. For the same reason read 2 comes out of this
/// list too, instead of off a fixed offset from read 1 — an offset lands on a
/// deposit often enough, and then the control fails for a reason that has
/// nothing to do with the fix.
fn bare_tiles_near(world: &sim::World, from: TilePos) -> Vec<TilePos> {
    let spawn = world.spawn_tile();
    let mut tiles: Vec<TilePos> = (0..world.height())
        .flat_map(|y| (0..world.width()).map(move |x| TilePos::new(x, y)))
        .filter(|&t| {
            t != spawn
                && t.x > 0
                && world.in_bounds(TilePos::new(t.x + 1, t.y + 1))
                && [(0, 0), (1, 0), (0, 1), (1, 1)]
                    .iter()
                    .all(|(dx, dy)| world.deposit_at(TilePos::new(t.x + dx, t.y + dy)).is_none())
        })
        .collect();
    tiles.sort_by_key(|&t| walk(from, t));
    tiles
}

#[test]
fn the_ground_line_does_not_call_an_occupied_tile_empty() {
    let seed = 7;
    let (world, material, _fuel) = common::starters(seed);
    let spawn = world.spawn_tile();
    let ore = format!(
        "ore:{}:{}",
        world.species(material.species).name().to_ascii_lowercase(),
        material.grade().letter().to_ascii_lowercase()
    );
    // The smelter goes on the nearest bare 2×2 to the rock the player mines,
    // and they stand one tile west of it so `place`'s reach (3) holds.
    let bare = bare_tiles_near(&world, material.center);
    let built = bare[0];
    let stand = TilePos::new(built.x - 1, built.y);
    // Read 2's tile is clear of the smelter's own 2×2 AND of the tile the
    // player stands on, so the control cannot read the building's footprint.
    let control = *bare
        .iter()
        .find(|&&t| walk(built, t) >= 3)
        .expect("a second bare tile away from the first");
    assert!(
        world.deposit_at(built).is_none() && world.deposit_at(control).is_none(),
        "both reads must be about tiles with no deposit, or they prove nothing"
    );

    let script = format!(
        "new {seed}
pause
goto {} {}
tick {}
mine
tick 40
craft smelter {ore}
tick 25
goto {} {}
tick {}
place smelter {} {}
tick 2
buildings
at {} {}
at {} {}
at {} {}
quit
",
        material.center.x,
        material.center.y,
        walk(spawn, material.center).max(1),
        stand.x,
        stand.y,
        walk(material.center, stand).max(1),
        built.x,
        built.y,
        built.x,
        built.y,
        control.x,
        control.y,
        material.center.x,
        material.center.y,
    );

    let saves = std::env::temp_dir().join(format!("assay-ground-note-{}", std::process::id()));
    let mut child = Command::new(env!("CARGO_BIN_EXE_sim-cli"))
        .arg("--plain")
        .arg("--name")
        .arg("ada")
        .env("R2TS_SAVES_DIR", &saves)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("sim-cli starts");
    child
        .stdin
        .take()
        .unwrap()
        .write_all(script.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let _ = std::fs::remove_dir_all(&saves);
    let stdout = String::from_utf8_lossy(&out.stdout);
    let transcript = format!(
        "--- script\n{script}\n--- stdout\n{stdout}\n--- stderr\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.status.success(), "{transcript}");
    assert!(!stdout.contains("rejected"), "{transcript}");

    // The fixture, before anything is read off it: the smelter is really there.
    // `at` printing nothing about a building would otherwise pass box 1 for the
    // most boring reason there is.
    let occupied = format!("({}, {}): ", built.x, built.y);
    let read_one: Vec<&str> = stdout
        .lines()
        .filter(|l| l.starts_with(&occupied))
        .collect();
    assert!(
        read_one.iter().any(|l| l.contains("smelter")),
        "the script must actually have placed a smelter on ({}, {})\n{transcript}",
        built.x,
        built.y
    );

    // READ 1 — THE BUG. Both facts, no contradiction between them.
    //
    // **PINNED TO THE GROUND LINE, AND NOT BY TASTE.** Written as "no line in
    // this read says `empty`" it failed on the fix, because a smelter's own
    // status line says `in empty · … · out empty` about its two slots — true,
    // about a slot, and nothing to do with the tile. An assertion that cannot
    // tell those apart would have sent me looking for a bug in the fix. The
    // ground line is the one carrying the tile's `place`, which is `chunk (`.
    let ground = read_one
        .iter()
        .find(|l| l.contains("chunk ("))
        .unwrap_or_else(|| panic!("`at` printed no ground line at all\n{transcript}"));
    assert!(
        ground.contains("no deposit here"),
        "the ground fact must survive on an occupied tile: {ground}\n{transcript}"
    );
    assert!(
        !ground.contains("empty"),
        "the ground line may not call a tile with a smelter on it empty: \
         {ground}\n{transcript}"
    );

    // READ 2 — THE CONTROL FOR DELETION. A fix that hid the line when a
    // building was present would pass read 1 and this; a fix that dropped the
    // line altogether passes read 1 and fails here.
    let bare_prefix = format!("({}, {}): ", control.x, control.y);
    let read_two = stdout
        .lines()
        .find(|l| l.starts_with(&bare_prefix))
        .unwrap_or_else(|| panic!("`at` said nothing about a bare tile\n{transcript}"));
    assert!(
        read_two.contains("no deposit here") && read_two.contains("chunk ("),
        "a bare tile still gets its ground line and its place: {read_two}\n{transcript}"
    );

    // READ 3 — THE CASE THAT WAS ALREADY RIGHT. The deposit line is the ground
    // line on its own tile, so the new sentence must not appear beside it.
    let on_deposit = format!("({}, {}): ", material.center.x, material.center.y);
    let read_three = stdout
        .lines()
        .find(|l| l.starts_with(&on_deposit))
        .unwrap_or_else(|| panic!("`at` said nothing about the deposit\n{transcript}"));
    assert!(
        read_three.contains("deposit ") && !read_three.contains("no deposit here"),
        "a deposit tile reads as it always did: {read_three}\n{transcript}"
    );
}

/// NO HOST MAY WORD THE GROUND. The bug was three copies of one sentence, and
/// the two in this crate are the ones that can drift back silently — the Godot
/// client at least has to cross the binding to get a word out of the sim.
///
/// This reads the sources rather than the output because it is about what is
/// *absent*: a second literal would not break any assertion above, it would
/// just mean the inspector and `at` could disagree again the next time the
/// wording moves.
#[test]
fn neither_host_surface_spells_a_ground_sentence_itself() {
    for (name, src) in [
        ("host.rs", include_str!("../src/host.rs")),
        ("tui.rs", include_str!("../src/tui.rs")),
    ] {
        for banned in ["empty ground", "no deposit here"] {
            assert!(
                !src.contains(banned),
                "{name} spells {banned:?} itself; it belongs to sim::debug::ground_note"
            );
        }
        assert!(
            src.contains("ground_note"),
            "{name} must get the ground from the sim"
        );
    }
}
