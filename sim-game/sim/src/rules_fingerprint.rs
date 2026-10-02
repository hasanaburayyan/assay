// The rules identity: a fingerprint of this crate's own source (ASSA-40).
//
// **THIS FILE IS COMPILED TWICE.** It is a module of `sim`, and `build.rs`
// `include!`s it to compute the identity baked into every binary. One
// implementation, so the value in a shipped build and the value a test
// recomputes cannot drift apart. That is also why it uses nothing but
// `std`: a build script cannot depend on the crate it is building.
//
// **THERE IS NO FILESYSTEM IN HERE ON PURPOSE.** `sim` may not read the OS
// (repo `CLAUDE.md`), so the directory walk lives in `sim/rules_walk.rs`,
// outside the library, where only `build.rs` and tests include it. What is
// left is pure data hashing, which is the same family of thing as `hash.rs`.
//
// **WHAT THE IDENTITY COVERS AND WHAT IT DOES NOT.** Every `.rs` file under
// `sim/src`, by path and by content, plus the workspace `Cargo.lock` — a
// dependency bump that changes arithmetic is a different build (Wren's ruling
// on the ASSA-40 follow-up, 2026-10-02). Not `Cargo.toml`, whose interesting
// content is in the lock file, and not the compiler version. The exact list
// lives in `rules_walk.rs::identity_inputs`, which is the one place
// `build.rs` and `tests/rules_identity.rs` both read it from;
// `PROTOCOL_VERSION` still covers the shape of the wire.

/// FNV-1a over the file list, in the order given. Sixteen hex digits, the
/// same shape as a world hash, so the two read alike in a log.
///
/// **CARRIAGE RETURNS ARE DROPPED.** A Windows checkout can arrive with CRLF
/// line endings and CI builds the Mac and Windows bundles from one commit;
/// without this the same rules would get two identities and every
/// cross-platform join would be refused. Paths are normalised to forward
/// slashes for the same reason.
///
/// The path is fed as well as the content, so moving a rule from one file to
/// another moves the identity: two builds whose sources differ only by layout
/// are still two different builds. The zero byte between fields is what stops
/// `("ab", "c")` and `("a", "bc")` from colliding.
pub fn fingerprint(files: &[(String, Vec<u8>)]) -> String {
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    let mut feed = |bytes: &[u8]| {
        for b in bytes {
            hash ^= u64::from(*b);
            hash = hash.wrapping_mul(0x100_0000_01b3);
        }
    };
    for (path, bytes) in files {
        feed(path.replace('\\', "/").as_bytes());
        feed(&[0]);
        for b in bytes {
            if *b != b'\r' {
                feed(std::slice::from_ref(b));
            }
        }
        feed(&[0]);
    }
    format!("{hash:016x}")
}
