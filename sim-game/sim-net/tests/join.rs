//! Who may join, and what a refusal says (ASSA-40).
//!
//! `check_join` is the only place the two refusals are worded, so these tests
//! are about the sentence as much as the verdict: a stranger with a
//! downloaded zip has to be able to act on it.

use sim_net::{PROTOCOL_VERSION, RULES_ID, check_join};

const OTHER_RULES: &str = "0123456789abcdef";

#[test]
fn a_peer_on_the_same_protocol_and_rules_joins() {
    assert_eq!(check_join(PROTOCOL_VERSION, RULES_ID), Ok(()));
}

#[test]
fn the_rules_identity_this_host_advertises_is_the_sims_own() {
    assert_eq!(RULES_ID, sim::RULES_ID);
    assert_ne!(RULES_ID, OTHER_RULES, "the fake id must not be real");
}

/// A build from a different commit is refused **by name, on both sides**, and
/// told the one thing that fixes it. "Your client is wrong" without saying
/// which build to get is a dead end for someone who has only a zip.
#[test]
fn a_peer_built_from_different_rules_is_refused_naming_both() {
    let refusal = check_join(PROTOCOL_VERSION, OTHER_RULES).expect_err("must refuse");
    assert!(
        refusal.contains(RULES_ID),
        "the refusal must name the host's rules so a tester can match a \
         build to it: {refusal}"
    );
    assert!(
        refusal.contains(OTHER_RULES),
        "and the peer's own rules, so they can tell which build they ran: \
         {refusal}"
    );
    assert!(
        refusal.contains("Download the build that matches this host"),
        "and the action that fixes it: {refusal}"
    );
}

/// The wire check still happens and still comes first: two builds that cannot
/// parse each other's messages must not be told they have a rules problem.
#[test]
fn a_peer_on_another_protocol_is_refused_for_that_and_not_the_rules() {
    let refusal = check_join(PROTOCOL_VERSION + 1, RULES_ID).expect_err("must refuse");
    assert!(
        refusal.contains(&format!("v{PROTOCOL_VERSION}"))
            && refusal.contains(&format!("v{}", PROTOCOL_VERSION + 1)),
        "name both protocol versions: {refusal}"
    );
    assert!(
        !refusal.contains(RULES_ID),
        "a protocol mismatch must not be reported as a rules mismatch, or \
         the reader chases the wrong thing: {refusal}"
    );
}

/// **THE CASE THAT CAUSED THIS WORK.** A relay and a client from different
/// commits, both on the protocol the wire has always had. Before ASSA-40 this
/// was a clean join followed by a desync twenty ticks later; it must now be
/// a refusal at the door.
#[test]
fn matching_protocol_is_not_enough_on_its_own() {
    assert!(
        check_join(PROTOCOL_VERSION, OTHER_RULES).is_err(),
        "the same protocol with different rules joined, which is the exact \
         failure ASSA-40 exists to stop"
    );
}
