//! The rules identity baked into every binary (ASSA-40).
//!
//! `build.rs` computes `sim::RULES_ID` from this crate's own source. These
//! tests check the two properties the feature rests on — that it really is a
//! function of the source, and that it is the same function on every machine
//! — because the alternative is finding out at a playtest.

use std::path::Path;

use sim::rules_fingerprint::fingerprint;

// The directory walk, from outside the library: `sim` may not read the OS,
// so `build.rs` and this test share the file rather than the crate owning it.
include!("../rules_walk.rs");

fn rule_sources() -> Vec<(String, Vec<u8>)> {
    identity_inputs(Path::new(env!("CARGO_MANIFEST_DIR")))
}

/// **THE BAKED VALUE IS THE FINGERPRINT OF THE SOURCE THAT IS HERE NOW.**
///
/// This is the test that makes the identity worth anything. It would fail if
/// someone hand-typed `SIM_RULES_ID`, if `build.rs` stopped covering part of
/// the crate, or if the walk and the build script ever disagreed about which
/// files are rules.
#[test]
fn the_baked_identity_is_the_fingerprint_of_this_crates_source() {
    let files = rule_sources();
    assert!(
        files.len() > 15,
        "only {} rule source files found — the walk is broken, not the crate",
        files.len()
    );
    assert_eq!(
        fingerprint(&files),
        sim::RULES_ID,
        "the identity this binary carries is not the fingerprint of the \
         source it was built from. Either `build.rs` did not re-run, or it \
         no longer walks the same files this test does."
    );
}

/// Sixteen hex digits, like a world hash, because the two appear side by side
/// in logs and a refusal message.
#[test]
fn the_identity_reads_like_a_hash() {
    assert_eq!(sim::RULES_ID.len(), 16, "{}", sim::RULES_ID);
    assert!(
        sim::RULES_ID.chars().all(|c| c.is_ascii_hexdigit()),
        "{}",
        sim::RULES_ID
    );
}

/// **THE WHOLE POINT: A CHANGED RULE IS A DIFFERENT IDENTITY.** A git sha
/// cannot do this, which is why the identity is content and not a sha — a
/// dirty tree reports the commit it was edited from, so a local build with
/// one constant changed would claim to be clean `main`.
///
/// Done on the real sources with one byte flipped, so it is the actual
/// corpus being tested and not a toy pair of files.
#[test]
fn changing_one_byte_of_one_rule_changes_the_identity() {
    let mut edited = rule_sources();
    let (path, bytes) = edited
        .iter_mut()
        .find(|(p, _)| p.ends_with("tuning.rs"))
        .expect("tuning.rs is a rule source");
    let first_digit = bytes
        .iter()
        .position(|b| b.is_ascii_digit())
        .expect("tuning.rs contains a number");
    // '1' -> '2', or any digit to the next one: a tuning change, spelled the
    // way tuning changes actually arrive.
    bytes[first_digit] = if bytes[first_digit] == b'9' {
        b'8'
    } else {
        bytes[first_digit] + 1
    };
    let path = path.clone();
    assert_ne!(
        fingerprint(&edited),
        sim::RULES_ID,
        "one digit changed in {path} and the identity did not move, so a \
         retuned local build would claim to be the host's build"
    );
}

/// **A DEPENDENCY BUMP IS A DIFFERENT BUILD** (ASSA-40 follow-up, Wren's
/// ruling 2026-10-02). The rules live in the source, but they are not the only
/// thing that decides what a tick does: a dependency whose arithmetic changed
/// would have kept the old identity, and that failure mode is the silent
/// desync this whole feature exists to stop.
///
/// Non-vacuity matters more than usual here, because the lock file could be
/// in the list and contribute nothing — so this also checks it is really
/// present and really has bytes.
#[test]
fn changing_the_lock_file_changes_the_identity() {
    let mut edited = rule_sources();
    let (_, bytes) = edited
        .iter_mut()
        .find(|(path, _)| path == "Cargo.lock")
        .expect("the lock file is part of the identity");
    assert!(!bytes.is_empty(), "the lock file contributed no bytes");
    // How a bump actually arrives: a version string moves.
    bytes.extend_from_slice(b"\n# a dependency moved\n");
    assert_ne!(
        fingerprint(&edited),
        sim::RULES_ID,
        "the lock file changed and the identity did not move, so a build with \
         different dependencies would claim to be the host's build"
    );
}

/// Moving a rule between files is a different build, even with identical
/// bytes overall: the path is fed to the hash, not just the content.
#[test]
fn moving_a_rule_to_another_file_changes_the_identity() {
    let plain = vec![
        ("a.rs".to_string(), b"const A: u32 = 1;".to_vec()),
        ("b.rs".to_string(), b"const B: u32 = 2;".to_vec()),
    ];
    let swapped = vec![
        ("a.rs".to_string(), b"const B: u32 = 2;".to_vec()),
        ("b.rs".to_string(), b"const A: u32 = 1;".to_vec()),
    ];
    assert_ne!(fingerprint(&plain), fingerprint(&swapped));

    // And the field separator does its job: these two must not collide.
    let split_one = vec![("ab".to_string(), b"c".to_vec())];
    let split_two = vec![("a".to_string(), b"bc".to_vec())];
    assert_ne!(fingerprint(&split_one), fingerprint(&split_two));
}

/// **ONE COMMIT MUST MEAN ONE IDENTITY ON MAC AND ON WINDOWS**, or every
/// cross-platform join from a single CI run is refused — and CI builds both
/// bundles from one commit, which is exactly how we hand a zip to a tester.
///
/// A Windows checkout can arrive with CRLF line endings, so the fingerprint
/// drops carriage returns and normalises path separators. This is the only
/// property of the feature I cannot test on the machine it matters for, so
/// it is tested as the transformation instead.
#[test]
fn line_endings_and_path_separators_do_not_change_the_identity() {
    let unix = vec![(
        "src/step.rs".to_string(),
        b"fn a() {}\nfn b() {}\n".to_vec(),
    )];
    let windows = vec![(
        "src\\step.rs".to_string(),
        b"fn a() {}\r\nfn b() {}\r\n".to_vec(),
    )];
    assert_eq!(
        fingerprint(&unix),
        fingerprint(&windows),
        "a CRLF checkout or a backslash path produced a different identity, \
         so the Mac and Windows bundles from one CI run would refuse each \
         other"
    );

    // Non-vacuity: the normalisation must not be flattening everything. A
    // real content difference still has to register.
    let different = vec![("src/step.rs".to_string(), b"fn a() {}\n".to_vec())];
    assert_ne!(fingerprint(&unix), fingerprint(&different));
}

/// **AN EXCLUSION IS A CLAIM, AND THIS IS THE CHECK ON IT** (ASSA-85).
///
/// `debug.rs` is out of the identity because prose cannot desync anybody.
/// That is true exactly while nothing which *does* decide behaviour reaches
/// it. Move a rule into `debug.rs`, or have `step` call one of its functions,
/// and the identity silently stops covering a rule — the same shape as
/// ASSA-51 and ASSA-53, where one of two spellings was exercised only where
/// it happened to work.
///
/// Comments are stripped first, because the rules path legitimately *mentions*
/// `debug.rs` in doc comments (`World::smelter_state` explains that the stall
/// chain used to live there). Stripping from the first `//` also truncates a
/// line holding a `//` inside a string literal, which can only make this less
/// sensitive on that line, never more.
#[test]
fn nothing_in_the_identity_reaches_the_excluded_files() {
    let mut checked = 0;
    for (path, bytes) in rule_sources() {
        if path == "Cargo.lock" {
            continue;
        }
        checked += 1;
        let text = String::from_utf8_lossy(&bytes);
        let code: String = text
            .lines()
            .map(|line| line.split("//").next().unwrap_or(""))
            .collect::<Vec<_>>()
            .join("\n");
        for excluded in NOT_RULES {
            let module = excluded.trim_end_matches(".rs");
            // **THE NEEDLE IS `debug::`, NOT `debug`.** `lib.rs` has to say
            // `pub mod debug;` for the module to exist at all, and declaring
            // it is not depending on it. Every way of reaching into it from
            // rules code spells the path — `debug::f()`, `crate::debug::f()`,
            // `use crate::debug::f` — so the separator is the discriminator.
            // An aliased import (`use crate::debug as d`) would slip past;
            // noted rather than guarded, because the alias would also have to
            // survive review.
            assert!(
                !code.contains(&format!("{module}::")),
                "{path} references `{module}`, which is EXCLUDED from the rules \
                 identity on the grounds that it cannot change what a tick \
                 computes. One of two things is now true: the reference is \
                 harmless and `{module}` should be read again to confirm it is \
                 still pure readout, or a rule has moved into it and the \
                 identity has stopped covering a rule. Do not silence this by \
                 renaming the call — take `{excluded}` back into NOT_RULES's \
                 opposite, the identity itself."
            );
        }
    }
    // Non-vacuity: the sweep is worthless if the walk handed it nothing.
    assert!(checked > 15, "only {checked} source files swept");
}

/// The exclusion must not have taken the whole crate with it, and the files
/// that decide behaviour must still be there to be fingerprinted.
#[test]
fn the_identity_still_covers_the_files_that_decide_behaviour() {
    let paths: Vec<String> = rule_sources().into_iter().map(|(p, _)| p).collect();
    for rule in [
        "step.rs",
        "tuning.rs",
        "worldgen.rs",
        "ladder.rs",
        "recipe.rs",
        "assembly.rs",
        "world.rs",
        "hash.rs",
        "save.rs",
        "Cargo.lock",
    ] {
        assert!(
            paths.iter().any(|p| p == rule),
            "{rule} is not in the rules identity: {paths:?}"
        );
    }
    for excluded in NOT_RULES {
        assert!(
            !paths.iter().any(|p| p == excluded),
            "{excluded} was supposed to be out of the identity: {paths:?}"
        );
    }
}
