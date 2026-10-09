//! **THE CATALOGUE TABLE SAYS WHAT A FRAME ACCEPTS** (ASSA-340).
//!
//! A slot limit was a rule with no headless surface: `part_table` printed
//! name, mount, size and contributions, so a `sim-cli` player learned that a
//! handle takes one head and offers no hopper slot at all by being refused at
//! `assemble`. The build screen is about to draw those same limits as a shape
//! in the Godot window, and a rule visible only with graphics is the one thing
//! this repo's `CLAUDE.md` says is never done.
//!
//! **EVERY EXPECTED VALUE HERE IS A LITERAL, AND THAT IS THE POINT.**
//! `assembly.rs`'s tests loop over `PartKind::ALL` so a fifth kind joins them
//! for free; these do the opposite on purpose. A test that re-derived
//! `head 1, hopper 0-4` from `spec()` would be the function agreeing with
//! itself and would stay green if the phrase came out as `head 1-1` or in the
//! wrong order. If `MAX_HOPPER_SLOTS` changes, this file goes red naming the
//! old number — which is what a golden string is for.

use sim::assembly::spec;
use sim::debug;
use sim::{Mount, PartKind};

/// The two frames are the two FORMS of the phrase, and both are reachable from
/// the shipped catalogue: a held frame's head slot is `min == max`, a planted
/// frame's hopper slot is a real range. So this is not defence against a case
/// nobody has — it is the difference between the two rows a player reads.
#[test]
fn a_frames_slots_read_as_a_count_or_a_range() {
    assert_eq!(
        debug::slots_phrase(spec(PartKind::Frame(Mount::Held)).slots),
        "head 1",
        "a held frame takes exactly one head; `min == max` is a count and not \
         a span, so `head 1-1` is wrong even though it is true"
    );
    assert_eq!(
        debug::slots_phrase(spec(PartKind::Frame(Mount::Planted)).slots),
        "head 1, hopper 0-4",
        "a planted frame's two slots, in the catalogue's own order, the \
         required one first; if MAX_HOPPER_SLOTS moved, that is the number to \
         change here"
    );
}

/// **A MOUNTED PART OFFERS NOTHING AND SAYS NOTHING.** `""` rather than a dash
/// or `none`: the column is blank for two of four rows, and a word there would
/// read as a fact about the part instead of as the absence of one.
#[test]
fn a_part_that_is_not_a_frame_accepts_nothing() {
    for kind in PartKind::ALL {
        let phrase = debug::slots_phrase(spec(kind).slots);
        assert_eq!(
            phrase.is_empty(),
            !kind.is_frame(),
            "{} printed {phrase:?} as what it accepts; only a frame offers \
             slots (`PartSpec::slots`: \"Only a frame offers any\")",
            kind.name()
        );
    }
}

/// **THE TABLE A PLAYER READS, LINE BY LINE AND NOT AS ONE HAYSTACK.**
///
/// Asserting against the whole table would let the handle's row be satisfied
/// by the planted frame's — both contain `head 1` — which is the shape of
/// check that has caught me repeatedly: satisfied by a line other than the one
/// it is about. So each row is found by its own first word and asked on its
/// own.
#[test]
fn the_part_table_prints_what_each_frame_accepts() {
    let table = debug::part_table();
    assert!(
        table
            .lines()
            .next()
            .is_some_and(|head| head.contains("accepts")),
        "the header names no `accepts` column:\n{table}"
    );

    let row = |name: &str| -> String {
        table
            .lines()
            .find(|line| line.starts_with(name))
            .unwrap_or_else(|| panic!("no row starts with {name:?}:\n{table}"))
            .to_string()
    };

    let handle = row("handle");
    assert!(
        handle.contains("head 1"),
        "a handle's row does not say it takes a head:\n{handle}"
    );
    assert!(
        !handle.contains("hopper"),
        "a handle's row mentions a hopper, and a held frame offers no hopper \
         slot at all — the limit a player most needs the table for:\n{handle}"
    );

    let frame = row("frame");
    assert!(
        frame.contains("head 1, hopper 0-4"),
        "a planted frame's row does not carry both slots:\n{frame}"
    );

    // The teaching paragraph says what the column means, since a bare `0-4`
    // does not say which end is the requirement.
    assert!(
        table.contains("minimum above zero is a slot the design is not finished without"),
        "the table explains the numbers nowhere:\n{table}"
    );
}
