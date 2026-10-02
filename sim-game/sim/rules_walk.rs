// Collecting the rule sources off disk, for the rules identity (ASSA-40).
//
// **DELIBERATELY NOT PART OF THE `sim` LIBRARY**, and not under `src/`.
// `sim` may not read the OS, and this reads directories; `build.rs` and
// `tests/rules_identity.rs` both `include!` it, which is also why it takes
// no dependency on the crate.
//
// It is outside `src/` for a second reason: it is not a rule, so changing
// how the walk works must not change the identity of the rules it walks.

/// Every `.rs` file under `dir`, as (path relative to `dir`, bytes), sorted
/// by path — a filesystem's own walk order must never move the identity.
pub fn source_files(dir: &std::path::Path) -> Vec<(String, Vec<u8>)> {
    let mut out = Vec::new();
    walk(dir, dir, &mut out);
    out.sort_by(|a, b| a.0.cmp(&b.0));
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
