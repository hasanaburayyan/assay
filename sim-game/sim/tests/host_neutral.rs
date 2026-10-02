//! A sim sentence names the action, never the keystrokes (ASSA-67).
//!
//! `debug::event_line` is the one function whose output a host renders
//! **verbatim**: `sim-cli` prints it and the Godot client puts it in its log
//! (`AssaySim.event_lines` → `main.gd::_remember_events`). Thirteen of its
//! lines used to name a `sim-cli` command — the worst at the pivot of the whole
//! demo, telling a player to `insert 0 fuel <item>` while **Fuel** and
//! **Smelt** buttons sat on their ore row in the same window. It did not merely
//! fail to help; it pointed away from the thing that works.
//!
//! The Game Director's ruling is a rule and not thirteen patches: the sim knows
//! "this building needs fuel and ore before it runs" and must not know that
//! some host spells that `insert`. That is principle 1 of the repo's
//! `CLAUDE.md` applied to prose — the sim should no more know there is a
//! command line than it should know there is a renderer.
//!
//! **The table functions keep their syntax and that is correct.**
//! `species_table`, `building_table`, `part_table`, `built_table` and
//! `recipe_table` are read at a prompt by someone who has one.

use sim::{
    BuildingId, Event, Grade, Item, ItemKind, Mount, PartKind, PlayerCommand, PlayerId,
    RejectReason, SpeciesId, TilePos, World, WorldConfig, debug,
};

/// This crate's own source, so the guard cannot drift from the thing it
/// guards: there is no second copy to update.
const DEBUG_RS: &str = include_str!("../src/debug.rs");

/// `event_line`'s body, from its signature to the next item at column zero.
fn event_line_body() -> &'static str {
    let start = DEBUG_RS
        .find("pub fn event_line")
        .expect("event_line is still called that");
    let rest = &DEBUG_RS[start..];
    let end = rest[1..]
        .find("\npub fn ")
        .map_or(rest.len(), |i| i + 1 + 1);
    &rest[..end]
}

/// **THE RULE IS MECHANICAL, WHICH IS WHY IT CAN BE A GUARD.** A backtick in
/// this function may only quote a *placeholder* — the echo of the command a
/// player actually sent, as in "`{}` was rejected" — and never a literal word,
/// because a backticked word here is always a command name. So: **no backtick
/// is followed by a letter.** The closing backtick of the echo is followed by a
/// space, which is why the rule is stated this way round rather than as
/// "followed by `{`" — I wrote that first and the echo tripped it.
///
/// Checked against the source rather than against a list of today's thirteen
/// sentences, because the thing to prevent is the fourteenth.
#[test]
fn no_event_line_sentence_spells_a_command() {
    let body = event_line_body();
    let mut checked = 0;
    for (n, line) in body.lines().enumerate() {
        // Comments may discuss `insert` and `sim-cli` freely; players never
        // read them.
        if line.trim_start().starts_with("//") {
            continue;
        }
        let bytes: Vec<char> = line.chars().collect();
        for (i, c) in bytes.iter().enumerate() {
            if *c != '`' {
                continue;
            }
            checked += 1;
            let next = bytes.get(i + 1).copied().unwrap_or(' ');
            assert!(
                !next.is_ascii_alphabetic(),
                "event_line spells a command at body line {n}: {line}\n\
                 A sim sentence names the ACTION, not the keystrokes: a host with \
                 buttons cannot type it, and the sim must not know that some host \
                 has a prompt (ASSA-67)."
            );
        }
    }
    // Non-vacuity: the echo backticks are still in there, so a guard that
    // simply found nothing to check would not pass this.
    assert!(
        checked >= 2,
        "found only {checked} backticks in event_line; the rejection echo should \
         still have a pair, so this guard is probably reading the wrong slice"
    );
}

/// The body slice is the other half of the guard: if it silently captured
/// nothing, or captured the whole file, the test above would be about the wrong
/// text. Both ends are pinned to something only `event_line` contains.
#[test]
fn the_guard_reads_event_line_and_not_the_tables() {
    let body = event_line_body();
    assert!(
        body.contains("Event::BuildingPlaced"),
        "the slice must reach into the match"
    );
    assert!(
        !body.contains("pub fn summary"),
        "the slice must stop at the next function"
    );
    // The tables are outside it and keep their syntax, which is the point of
    // slicing at all.
    assert!(
        debug::recipe_table().contains('`') || debug::part_table().contains('`'),
        "a CLI table may still teach syntax; if neither does any more, this \
         guard's scope has changed and should be re-read"
    );
}

fn world() -> World {
    World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    })
}

fn placed(item: Item) -> String {
    debug::event_line(
        &world(),
        Some(PlayerId(0)),
        &Event::BuildingPlaced {
            player: PlayerId(0),
            building: BuildingId(0),
            item,
            pos: TilePos::new(1, 1),
        },
    )
}

/// **THE HINT GOES ONLY WHERE IT IS TRUE.** This event fires for a planted
/// machine as well as a smelter, and the line it replaced told the owner of a
/// drill to insert fuel and ore into it — a machine takes nothing in, and says
/// so in its own rejection. So the smelter gets the clause and the machine gets
/// the bare placement sentence, rather than a hint I would be inventing.
#[test]
fn a_placed_smelter_says_what_it_needs_and_a_machine_does_not() {
    let smelter = placed(Item::new(ItemKind::Smelter, SpeciesId(0), Grade::C));
    assert!(
        smelter.contains("it needs fuel and ore before it will run"),
        "{smelter}"
    );
    let drill = placed(Item::new(
        ItemKind::Part(PartKind::Frame(Mount::Planted)),
        SpeciesId(0),
        Grade::C,
    ));
    assert!(
        !drill.contains("fuel"),
        "a machine takes nothing in, so it must not be sent looking for fuel: {drill}"
    );
    assert!(
        drill.contains("as building 0 at (1, 1)"),
        "it still says what was placed and where: {drill}"
    );
}

/// A rejection a player meets by clicking rather than typing still has to be
/// readable without a prompt — and the echo of their own command is the one
/// place backticks survive.
#[test]
fn a_rejection_reads_without_a_prompt_and_still_echoes_the_command() {
    let line = debug::event_line(
        &world(),
        Some(PlayerId(0)),
        &Event::CommandRejected {
            player: PlayerId(0),
            command: PlayerCommand::Mine,
            reason: RejectReason::NotInsertable,
        },
    );
    assert!(
        line.contains("it only gives out what it has mined"),
        "{line}"
    );
    assert!(
        !line.contains("`take`"),
        "the reason must not name a command: {line}"
    );
    assert!(
        line.contains("`mine`"),
        "but the echo of what the player sent stays, placeholder and all: {line}"
    );
}
