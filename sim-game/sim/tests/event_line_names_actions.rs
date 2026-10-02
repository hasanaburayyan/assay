//! A sim sentence names the ACTION, never the KEYSTROKES (ASSA-67).
//!
//! `debug::event_line` is the one function whose output the Godot client
//! renders verbatim (`AssaySim.event_lines` -> `main.gd:_remember_events`),
//! and it is also where every rejection is worded. Thirteen of its sentences
//! told a player to type a `sim-cli` command. A friend at the client window
//! has no command line to type it into, and the worst of them fired at
//! placement — sending the player to a prompt while **Fuel** and **Smelt**
//! buttons sat on their ore row in the same window.
//!
//! This is principle 1 of the repo's `CLAUDE.md` applied to prose: the sim
//! should no more know there is a command line than it should know there is a
//! renderer. The CLI reader loses nothing, because `sim-cli/src/host.rs` keeps
//! the syntax hints in its own usage messages, where host knowledge belongs.
//!
//! **THE TABLE FUNCTIONS KEEP THEIR SYNTAX AND ARE NOT CHECKED HERE.**
//! `species_table`, `building_table`, `part_table`, `built_table` and
//! `recipe_table` are CLI-only surfaces; no client renders them.
//!
//! WHY THIS READS SOURCE. The honest alternative — render every `Event` and
//! every `RejectReason` and grep the strings — needs a constructor for each
//! variant, and the day someone adds a variant and forgets the constructor the
//! guard goes quiet while the defect ships. The text of the function cannot go
//! quiet. `include_str!` is compile-time, so no test and nothing in `sim` reads
//! a file at runtime.
//!
//! NOT COVERED, ON PURPOSE: the rejection wrapper spells the refused command
//! as `sim-cli` syntax at RUNTIME (`command_line`, whose own doc comment admits
//! the wart). That is a value, not a literal, so no source check can see it;
//! it is filed as its own item.

const DEBUG_RS: &str = include_str!("../src/debug.rs");

/// Every verb `sim-cli` accepts (`host.rs`), which is the vocabulary a sentence
/// in `sim` must not use. Duplicated here on purpose: a test that imported the
/// list from the thing it checks would go green the moment a command was
/// renamed, which is the defect we keep paying for — a check must not share a
/// quantity with the thing it checks.
const CLI_COMMANDS: &[&str] = &[
    "new",
    "load",
    "save",
    "pause",
    "resume",
    "speed",
    "tick",
    "goto",
    "move",
    "mine",
    "craft",
    "place",
    "insert",
    "take",
    "pickup",
    "assay",
    "rename",
    "grant",
    "make",
    "assemble",
    "built",
    "equip",
    "unequip",
    "plant",
    "stop",
    "where",
    "inv",
    "map",
    "players",
    "species",
    "deposits",
    "recipes",
    "parts",
    "buildings",
    "at",
    "events",
    "status",
    "help",
    "quit",
];

/// The body of one top-level `fn`, by name. Top-level items close on a brace in
/// column 0, which is what `cargo fmt` guarantees and CI enforces.
fn function_body(src: &str, name: &str) -> String {
    let needle = format!("pub fn {name}");
    let start = src
        .find(&needle)
        .unwrap_or_else(|| panic!("no `{needle}` in debug.rs"));
    let rest = &src[start..];
    let end = rest
        .find("\n}\n")
        .unwrap_or_else(|| panic!("`{needle}` never closes in column 0"));
    rest[..end].to_string()
}

/// Backticked tokens in a line of source, ignoring doc and line comments.
fn backticked(line: &str) -> Vec<String> {
    let trimmed = line.trim_start();
    if trimmed.starts_with("//") {
        return Vec::new();
    }
    let mut out = Vec::new();
    let mut rest = line;
    while let Some(open) = rest.find('`') {
        let after = &rest[open + 1..];
        let Some(close) = after.find('`') else { break };
        out.push(after[..close].to_string());
        rest = &after[close + 1..];
    }
    out
}

#[test]
fn no_sentence_in_event_line_names_a_command() {
    let body = function_body(DEBUG_RS, "event_line");
    let mut found = Vec::new();
    for (i, line) in body.lines().enumerate() {
        for token in backticked(line) {
            let first = token.split_whitespace().next().unwrap_or("");
            if CLI_COMMANDS.contains(&first) {
                found.push(format!("  line {i} of event_line: `{token}`"));
            }
        }
    }
    assert!(
        found.is_empty(),
        "event_line is rendered verbatim at a window with no command line, so it names the \
         ACTION and never the keystrokes (ASSA-67). These name a command:\n{}",
        found.join("\n")
    );
}

/// The guard above is worth nothing if it cannot see the function at all — a
/// renamed `event_line`, a reformatted brace, or a `find` that matched a doc
/// comment would all leave it green and blind. So: the slice really is the
/// function, and the same scan over a function we deliberately left alone still
/// finds syntax.
#[test]
fn the_guard_is_looking_at_the_right_text() {
    let body = function_body(DEBUG_RS, "event_line");
    assert!(
        body.contains("Event::BuildingPlaced"),
        "the slice is not event_line's body"
    );
    assert!(
        body.contains("it needs fuel and ore before it will run"),
        "the slice does not reach the placement sentence"
    );
    assert!(
        !body.contains("pub fn species_table"),
        "the slice ran past the end of event_line"
    );

    // `built_table` is a CLI-only surface and keeps its syntax (`parts`,
    // `make`, `assemble`, `equip`, `plant`). If the scan finds nothing there,
    // the scan is broken, not the code. I picked `recipe_table` for this first
    // and it has none — the canary caught my assumption, which is the job.
    let table = function_body(DEBUG_RS, "built_table");
    let hits: usize = table
        .lines()
        .flat_map(backticked)
        .filter(|t| CLI_COMMANDS.contains(&t.split_whitespace().next().unwrap_or("")))
        .count();
    assert!(
        hits > 0,
        "the scan found no command syntax in recipe_table, which still has some"
    );
}
