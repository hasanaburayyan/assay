//! THE ROOT `CLAUDE.md` STATES THREE VERSION NUMBERS, AND THEY MUST BE THE
//! CODE'S (ASSA-174).
//!
//! On 2026-10-04 that file said `SAVE_VERSION = 10` and `PROTOCOL_VERSION = 4`
//! while the constants were 12 and 9: two and five versions stale, in the
//! document whose own first line is "Read this first", and stale in the way
//! that reads as authoritative — a specific, true-sounding historical detail
//! ("v9 never shipped") sitting next to a number that had moved twice.
//!
//! **WHY THIS IS A TEST AND NOT A CORRECTION.** Changing 10 to 12 leaves the
//! mechanism that let it rot: the next bump is somebody editing a constant in
//! `sim/src/save.rs` with no reason to open a markdown file two directories up.
//! It is the third committed description this week that could not say what it
//! described (ASSA-164's `rules_fingerprint` header, CO-6's docstring claiming
//! a case its own scan could not run). So the doc goes stale **red**.
//!
//! **WHY HERE.** `sim-cli` is the one crate that depends on both `sim` and
//! `sim-net`, so one test can hold both numbers beside the prose. Same shape as
//! `sim/tests/host_neutral.rs`, which reads `debug.rs`'s own source: the guard
//! cannot drift from the thing it guards, because there is no second copy.
//!
//! **WHAT IS DELIBERATELY NOT CHECKED:** the version numbers in `docs/adr/`.
//! An ADR records what one decision did on its own date; ADR 0003 saying
//! "`SAVE_VERSION` 10 → 11" is correct history and pinning it to today's
//! constant would make a correct document fail.

/// The committed file itself, not a copy of it. `include_str!` is relative to
/// this source file: `tests` → `sim-cli` → `sim-game` → the repo root.
const ROOT_DOC: &str = include_str!("../../../CLAUDE.md");

/// Pull the integer out of the doc's own `` `NAME = N` `` spelling.
///
/// **IT INSISTS ON EXACTLY ONE OCCURRENCE**, which is half the value of this
/// test: two sentences stating the same constant is the drift this item is
/// about, one step earlier. The parse is on the backticked code span and not on
/// the surrounding prose, so an en dash or a reflowed line cannot break it.
fn documented(name: &str) -> u32 {
    let needle = format!("`{name} = ");
    let hits = ROOT_DOC.matches(needle.as_str()).count();
    assert_eq!(
        hits, 1,
        "the root CLAUDE.md states `{name} = ` {hits} times; this test and the document it \
         describes both need exactly one place for it to live"
    );
    let tail = &ROOT_DOC[ROOT_DOC.find(needle.as_str()).unwrap() + needle.len()..];
    let digits: String = tail.chars().take_while(|c| c.is_ascii_digit()).collect();
    assert!(
        !digits.is_empty(),
        "the root CLAUDE.md spells `{name} = ` with no number after it: {:?}",
        &tail[..tail.len().min(40)]
    );
    digits.parse().expect("digits parse")
}

/// **EVERY NUMBER, NAMED SEPARATELY WHEN IT MOVES.** A single combined
/// assertion would say "the doc is stale" and leave whoever reads it to find
/// out which of three claims it meant.
#[test]
fn the_root_document_states_the_versions_the_code_holds() {
    assert_eq!(
        documented("SAVE_VERSION"),
        sim::save::SAVE_VERSION,
        "the root CLAUDE.md claims SAVE_VERSION {} and sim::save::SAVE_VERSION is {}. The \
         constant is right and the sentence is wrong: fix the document, not this test.",
        documented("SAVE_VERSION"),
        sim::save::SAVE_VERSION
    );
    assert_eq!(
        documented("OLDEST_SAVE_VERSION"),
        sim::save::OLDEST_SAVE_VERSION,
        "the root CLAUDE.md claims this build loads saves back to {} and \
         sim::save::OLDEST_SAVE_VERSION is {}. This is the number a player hits as 'save format \
         version N is not supported', so a wrong one in the docs is a wrong one in a bug report.",
        documented("OLDEST_SAVE_VERSION"),
        sim::save::OLDEST_SAVE_VERSION
    );
    assert_eq!(
        documented("PROTOCOL_VERSION"),
        sim_net::PROTOCOL_VERSION,
        "the root CLAUDE.md claims PROTOCOL_VERSION {} and sim_net::PROTOCOL_VERSION is {}. The \
         relay refuses a client on another version, so this number is what somebody reads when \
         deciding whether two builds can play together.",
        documented("PROTOCOL_VERSION"),
        sim_net::PROTOCOL_VERSION
    );
}

/// **THE SENTENCE BESIDE THE NUMBER, NOT ONLY THE DIGITS** (ASSA-174's last
/// box). The digits were not the only thing wrong: "Versions 1–8 (named ores)
/// do not load ... v9 never shipped" is a claim about what this build REFUSES,
/// and it is true only while nothing below v10 can be loaded. The moment
/// somebody writes a migration reaching back to v9, that sentence becomes a lie
/// that no number-comparison would notice.
///
/// It is a weaker guard than the one above and it is honest about being one: it
/// cannot check that the history list is complete, only that its one falsifiable
/// claim has not been falsified.
#[test]
fn the_claim_about_which_saves_refuse_to_load_is_still_true() {
    let claim = "v9 never shipped";
    assert!(
        ROOT_DOC.contains(claim),
        "the root CLAUDE.md no longer says {claim:?} beside SAVE_VERSION. If that history was \
         deliberately rewritten, update this test and say why; if it was reflowed away, the \
         sentence about which saves refuse to load went with it."
    );
    assert!(
        sim::save::OLDEST_SAVE_VERSION > 9,
        "the document says {claim:?} and that versions 1–8 do not load, but \
         OLDEST_SAVE_VERSION is {} — this build now accepts a save the document says it refuses.",
        sim::save::OLDEST_SAVE_VERSION
    );
}
