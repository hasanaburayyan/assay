//! Bakes the rules identity into the crate (ASSA-40).
//!
//! `PROTOCOL_VERSION` tracks the shape of the wire, and the rules now change
//! without the wire changing: #47 moved `HEAD_SPEED_PER_HARDNESS` 1 -> 2, and
//! a relay built before it ran a different game at the same protocol number,
//! which held a board playtest for an hour and a half. So every binary
//! carries a fingerprint of the rules it was built from, and the relay
//! refuses a peer that disagrees.
//!
//! **A GIT SHA WAS THE OTHER CANDIDATE AND IT LOSES**, for exactly the builds
//! we actually run. A dirty working tree reports the sha it was edited from,
//! so a local build with one constant changed would claim to be clean `main`
//! — the case this exists to catch. A content fingerprint cannot lie about
//! it: change a byte and the identity moves. It also needs no `git` on the
//! build machine and no fallback for a tarball checkout.

include!("src/rules_fingerprint.rs");
include!("rules_walk.rs");

fn main() {
    // Recursive, so a new rule file is covered without anyone remembering to
    // list it here.
    println!("cargo::rerun-if-changed=src");
    // And the lock file, or a dependency bump would keep the old identity
    // until something else happened to touch `src`.
    println!("cargo::rerun-if-changed=../Cargo.lock");

    let files = identity_inputs(std::path::Path::new("."));
    let sources = files
        .iter()
        .filter(|(path, _)| path.ends_with(".rs"))
        .count();
    assert!(
        sources > 5,
        "the rules fingerprint found only {sources} source files under src. \
         If the crate were really this small the identity would be worthless, \
         so read this as a broken walk rather than a small crate."
    );
    println!("cargo::rustc-env=SIM_RULES_ID={}", fingerprint(&files));
}
