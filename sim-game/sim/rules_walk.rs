// Collecting the rule sources off disk, for the rules identity (ASSA-40).
//
// **DELIBERATELY NOT PART OF THE `sim` LIBRARY**, and not under `src/`.
// `sim` may not read the OS, and this reads directories; `build.rs` and
// `tests/rules_identity.rs` both `include!` it, which is also why it takes
// no dependency on the crate.
//
// It is outside `src/` for a second reason: it is not a rule, so changing
// how the walk works must not change the identity of the rules it walks.

/// Everything the rules identity covers: every `.rs` under `<crate>/src`,
/// plus the workspace `Cargo.lock`.
///
/// **THE LOCK FILE IS IN IT** (ASSA-40 follow-up, Wren's ruling 2026-10-02).
/// A dependency bump that changes arithmetic is rare, but its failure mode is
/// the silent desync the identity exists to stop, and the cost of a false
/// move is only "rebuild both halves from the same commit", which the pairing
/// rule already requires. The compiler version stays out.
///
/// **ONE LIST, TWO CALLERS.** `build.rs` bakes it and
/// `tests/rules_identity.rs` recomputes it. If they disagreed about what is
/// in the identity, the agreement test would go red for a reason nobody could
/// read from the failure.
///
/// The lock file is keyed `Cargo.lock`, which no `.rs` path can equal, and it
/// is appended after the sort rather than mixed into it — both so that adding
/// it cannot change what any source file contributes, and because the order
/// only has to be the same everywhere, not alphabetical.
pub fn identity_inputs(crate_dir: &std::path::Path) -> Vec<(String, Vec<u8>)> {
    let mut files = source_files(&crate_dir.join("src"));
    let lock = crate_dir.join("..").join("Cargo.lock");
    let bytes =
        std::fs::read(&lock).unwrap_or_else(|e| panic!("read {}: {e}", lock.display()));
    assert!(
        !bytes.is_empty(),
        "{} is empty, so it would contribute nothing to the identity",
        lock.display()
    );
    files.push(("Cargo.lock".to_string(), bytes));
    files
}

/// Files under `src` that CANNOT change what a tick computes, and so are not
/// part of the rules identity (ASSA-85).
///
/// **THE ID ANSWERS ONE QUESTION: would these two peers compute different
/// worlds from the same inputs?** That is what `check_join` asks and the only
/// thing a refusal can honestly defend. `debug.rs` is pure readout — every
/// function in it takes `&World` and returns a `String` — so prose in it
/// cannot desync anybody, and before this it did: four identity moves in one
/// afternoon, all from wording changes, with both golden hashes unmoved
/// through every one. The Decision #38 bench spent hours refusing clients
/// built from current main because of it, which would have turned the board
/// away on an open hard gate.
///
/// **EXCLUDING A FILE IS A CLAIM THAT ROTS**, so it is checked rather than
/// trusted: `tests/rules_identity.rs::nothing_in_the_identity_reaches_the_
/// excluded_files` fails if anything still in the identity references one of
/// these modules. Move a rule into `debug.rs` and that test tells you the id
/// has stopped covering it, instead of a player finding out as a desync.
///
/// Exact relative paths, not patterns: a `debug.rs` that moved or split would
/// fall back INTO the identity, which is the safe direction, and the
/// assertion below catches the list going stale either way.
pub const NOT_RULES: &[&str] = &["debug.rs"];

/// Every `.rs` file under `dir` that is a rule, as (path relative to `dir`,
/// bytes), sorted by path — a filesystem's own walk order must never move the
/// identity.
pub fn source_files(dir: &std::path::Path) -> Vec<(String, Vec<u8>)> {
    let mut out = Vec::new();
    walk(dir, dir, &mut out);
    out.sort_by(|a, b| a.0.cmp(&b.0));
    for name in NOT_RULES {
        let before = out.len();
        out.retain(|(path, _)| path != name);
        // A LYING EXCLUSION LIST IS WORSE THAN NO LIST. If the file it names
        // is gone, the list was written for a tree that no longer exists and
        // the next reader would believe a claim nobody is checking.
        assert!(
            out.len() < before,
            "{name} is excluded from the rules identity and no such file is              under {}. Either it moved — in which case it is back IN the              identity and this list must say so — or the exclusion is stale.",
            dir.display()
        );
    }
    out
}

fn walk(root: &std::path::Path, dir: &std::path::Path, out: &mut Vec<(String, Vec<u8>)>) {
    let entries = std::fs::read_dir(dir).unwrap_or_else(|e| panic!("read {}: {e}", dir.display()));
    for entry in entries {
        let path = entry.expect("a readable directory entry").path();
        if path.is_dir() {
            walk(root, &path, out);
        } else if path.extension().is_some_and(|e| e == "rs") {
            let rel = path
                .strip_prefix(root)
                .expect("under the root we started from")
                .to_string_lossy()
                .into_owned();
            let bytes = std::fs::read(&path).unwrap_or_else(|e| panic!("read {rel}: {e}"));
            out.push((rel, bytes));
        }
    }
}
