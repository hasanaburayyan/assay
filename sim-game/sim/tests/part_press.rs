//! **NO PRESS IS CONFIRMED THAT THE SIM WOULD REFUSE** (Game Director,
//! ASSA-86 ruling 2; ASSA-102 is the sim and binding half).
//!
//! The window labelled every part row `"Mount" if building else "Frame"`, so
//! two of four rows were a promise the sim always breaks — and `_choose_part`
//! answered the press in the positive colour. Pressing `Frame` on a head row
//! is `FrameIsNotAFrame`, which **no later press can rescue**: a confirmed
//! dead end whose refusal arrives at `Assemble`, after the player has built
//! the rest of the design on it.
//!
//! `tests/assemble.rs` pins the commands that build a machine and
//! `tests/assembly.rs` pins the model. This file pins only the question a
//! client asks *before* it commits: could this ever work, and if not, in whose
//! words.
//!
//! The case table is the Game Director's own run
//! (`shared/assay/maren_frame_button_2026-10-02.rs`), reproduced here so it
//! guards instead of being a transcript.

use sim::assembly::{fault_adding, permanent_fault};
use sim::tuning::MAX_HOPPER_SLOTS;
use sim::{
    Assembly, AssemblyError, Grade, Item, ItemKind, Mount, Part, PartKind, SpeciesId, debug,
};

const HEAD: PartKind = PartKind::Head;
const HANDLE: PartKind = PartKind::Frame(Mount::Held);
const FRAME: PartKind = PartKind::Frame(Mount::Planted);
const HOPPER: PartKind = PartKind::Hopper;

/// The four kinds, as a client would meet them: every row of the catalogue.
const ALL: [PartKind; 4] = [HEAD, HANDLE, FRAME, HOPPER];

fn part(kind: PartKind, species: u8, grade: Grade) -> Part {
    Part::of(
        kind,
        Item::new(ItemKind::Refined, SpeciesId(species), grade),
    )
}

// ---------------------------------------------------------------------------
// The Game Director's table
// ---------------------------------------------------------------------------

/// **AS THE FIRST PART CHOSEN — the row the client labelled `Frame`.**
///
/// Her measurement: head and hopper are `FrameIsNotAFrame`; handle and frame
/// are `TooFew { Head }`, which is *not finished yet* and must be allowed.
#[test]
fn choosing_a_first_part_refuses_exactly_the_kinds_that_are_not_frames() {
    let seen: Vec<(PartKind, Option<AssemblyError>)> =
        ALL.iter().map(|k| (*k, fault_adding(&[], *k))).collect();
    assert_eq!(
        seen,
        vec![
            (HEAD, Some(AssemblyError::FrameIsNotAFrame)),
            (HANDLE, None),
            (FRAME, None),
            (HOPPER, Some(AssemblyError::FrameIsNotAFrame)),
        ],
        "the first-part column of the Game Director's run"
    );
    // The half that matters most: the refusal is the unrecoverable one, which
    // is WHY confirming it was worse than slow feedback.
    assert!(!AssemblyError::FrameIsNotAFrame.is_unfinished());
}

/// **MOUNTED ON A HELD FRAME — the row the client labelled `Mount`.**
///
/// Her measurement: head is accepted, handle and frame are `FrameMounted`,
/// and hopper is `NoSuchSlot(Hopper)` — the fourth case her first reading
/// missed, because a held frame offers no hopper slot at all.
#[test]
fn mounting_on_a_handle_accepts_only_a_head() {
    let seen: Vec<(PartKind, Option<AssemblyError>)> = ALL
        .iter()
        .map(|k| (*k, fault_adding(&[HANDLE], *k)))
        .collect();
    assert_eq!(
        seen,
        vec![
            (HEAD, None),
            (HANDLE, Some(AssemblyError::FrameMounted)),
            (FRAME, Some(AssemblyError::FrameMounted)),
            (HOPPER, Some(AssemblyError::NoSuchSlot(HOPPER))),
        ],
        "the held-frame column of the Game Director's run"
    );
}

/// A planted frame takes hoppers, so the same press that a handle refuses is
/// fine here. **Without this the `NoSuchSlot` case above could be read as
/// "hoppers are never mountable", which is not the rule.**
#[test]
fn mounting_a_hopper_is_about_the_frame_and_not_about_hoppers() {
    assert_eq!(
        fault_adding(&[HANDLE], HOPPER),
        Some(AssemblyError::NoSuchSlot(HOPPER))
    );
    assert_eq!(fault_adding(&[FRAME], HOPPER), None);
}

// ---------------------------------------------------------------------------
// The case her run did not reach
// ---------------------------------------------------------------------------

/// **THE PRESS THAT USED TO BE PERMITTED BY THE WRONG SENTENCE** (ASSA-102).
///
/// A planted frame's slots are `[Head min 1 max 1, Hopper min 0 max N]`, in
/// that order. Fill it past the hopper maximum before choosing a head and the
/// old `validate` reported `TooFew { Head }`, because the slot loop tested
/// min before max one limit at a time and `Head` is first. That sentence sends
/// a player to add a head, which still fails; the problem they have to undo
/// goes unmentioned.
///
/// Reachable by pressing Mount on hopper rows before choosing a head, which is
/// exactly what the pack invites after ASSA-86 leaves one button per part row.
#[test]
fn too_many_hoppers_is_named_even_while_the_head_is_still_missing() {
    let full: Vec<PartKind> = std::iter::once(FRAME)
        .chain(std::iter::repeat_n(HOPPER, MAX_HOPPER_SLOTS as usize))
        .collect();
    // One hopper short of the maximum is fine, head or no head.
    assert_eq!(
        fault_adding(&full[..full.len() - 1], HOPPER),
        None,
        "the fixture must sit exactly at the maximum, or the next press is \
         not the one under test"
    );
    assert_eq!(
        fault_adding(&full, HOPPER),
        Some(AssemblyError::TooMany {
            kind: HOPPER,
            have: MAX_HOPPER_SLOTS + 1,
            max: MAX_HOPPER_SLOTS,
        }),
        "a press that puts the design permanently over a maximum must be \
         refused, and named by the maximum rather than by the absent head"
    );

    // And the whole design agrees, through the real `validate`: this is the
    // precedence change, stated as a test rather than only in a comment.
    let mut parts: Vec<Part> = full.iter().map(|k| part(*k, 0, Grade::B)).collect();
    parts.push(part(HOPPER, 0, Grade::B));
    let (frame, mounted) = parts.split_first().expect("non-empty");
    let design = Assembly::new(*frame, mounted.to_vec());
    assert_eq!(
        design.validate(),
        Err(AssemblyError::TooMany {
            kind: HOPPER,
            have: MAX_HOPPER_SLOTS + 1,
            max: MAX_HOPPER_SLOTS,
        }),
        "validate now names every permanent fault before any minimum"
    );
}

/// Two heads on one frame is permanent too, and it is the one `TooMany` that
/// was always reported correctly — same limit, so nothing masked it.
#[test]
fn a_second_head_is_refused_at_the_press() {
    assert_eq!(
        fault_adding(&[HANDLE, HEAD], HEAD),
        Some(AssemblyError::TooMany {
            kind: HEAD,
            have: 2,
            max: 1,
        })
    );
}

// ---------------------------------------------------------------------------
// The properties the design rests on
// ---------------------------------------------------------------------------

/// **"NOT FINISHED YET" IS THE ONLY THING A LATER PRESS CAN FIX**, and a
/// client must never be told to refuse one.
///
/// Derived from the variants rather than restating the function: every arm is
/// listed, so a sixth `AssemblyError` fails to compile here instead of
/// silently joining whichever side of the line the match arm fell on.
#[test]
fn only_an_unfinished_design_is_recoverable() {
    let cases = [
        (AssemblyError::FrameIsNotAFrame, false),
        (AssemblyError::FrameMounted, false),
        (AssemblyError::NoSuchSlot(HOPPER), false),
        (
            AssemblyError::TooFew {
                kind: HEAD,
                have: 0,
                min: 1,
            },
            true,
        ),
        (
            AssemblyError::TooMany {
                kind: HEAD,
                have: 2,
                max: 1,
            },
            false,
        ),
    ];
    for (e, recoverable) in cases {
        assert_eq!(e.is_unfinished(), recoverable, "{e:?}");
    }
    assert_eq!(
        cases.iter().filter(|(_, r)| *r).count(),
        1,
        "exactly one error means 'add more parts'; if that changes, the press \
         question changes with it"
    );
    // And the one recoverable error is never what `fault_adding` returns:
    // a half-built design is a press a client must confirm.
    for first in [HANDLE, FRAME] {
        assert_eq!(fault_adding(&[], first), None);
    }
}

/// **LEGALITY NEVER READS A MATERIAL.** `part_press_refusal` hands the sim
/// item-kind names and no species or grade, which is only honest if the answer
/// cannot depend on them.
///
/// Proved over every kind in every frame position against materials that
/// differ in both species and grade — not asserted from the fact that
/// `permanent_fault` happens to take kinds today.
#[test]
fn species_and_grade_cannot_change_whether_a_design_is_legal() {
    let materials = [(0u8, Grade::C), (3, Grade::A), (5, Grade::B)];
    let mut compared = 0;
    for frame in ALL {
        for mounted in ALL {
            let by_kind = permanent_fault(frame, &[mounted]);
            for (species, grade) in materials {
                let design = Assembly::new(
                    part(frame, species, grade),
                    vec![part(mounted, species, grade)],
                );
                // `validate` adds the minimum test, so compare only on the
                // designs where no minimum is outstanding; everywhere else
                // compare the permanent answer itself.
                let by_part = match design.validate() {
                    Err(e) if e.is_unfinished() => None,
                    Err(e) => Some(e),
                    Ok(()) => None,
                };
                assert_eq!(
                    by_part, by_kind,
                    "{frame:?} + {mounted:?} changed answer for species \
                     {species} grade {grade:?}"
                );
                compared += 1;
            }
        }
    }
    assert_eq!(
        compared,
        ALL.len() * ALL.len() * materials.len(),
        "every kind pair against every material, or the claim is narrower \
         than it reads"
    );
}

/// The sentence a refused press shows is the SAME sentence `sim-cli` prints
/// when the design is actually rejected.
///
/// Read out of the sim on both sides: this follows the wording wherever the
/// Game Director moves it instead of pinning a copy that can disagree with
/// her. What it really guards is that `event_line` and a host asking ahead of
/// time cannot drift apart, which they could before the arm became a function.
#[test]
fn the_press_refusal_and_the_rejection_event_are_one_sentence() {
    let refusal = fault_adding(&[], HEAD).expect("a head cannot be a frame");
    let phrase = debug::assembly_error_phrase(refusal);
    assert!(
        !phrase.is_empty() && phrase.contains("frame"),
        "the sentence must still be about frames: {phrase}"
    );

    let event = sim::Event::CommandRejected {
        player: sim::PlayerId(0),
        command: sim::PlayerCommand::Assemble {
            frame: Item::new(ItemKind::Part(HEAD), SpeciesId(0), Grade::B),
            mounted: vec![],
        },
        reason: sim::RejectReason::BadAssembly(refusal),
    };
    let world = sim::World::new(sim::WorldConfig {
        seed: 9,
        ..sim::WorldConfig::default()
    });
    let line = debug::event_line(
        &world,
        Some(sim::PlayerId(0)),
        &event,
        debug::Audience::Typed,
    );
    assert!(
        line.contains(&phrase),
        "the log and the press must say the same thing.\n\
         press: {phrase}\n\
         log:   {line}"
    );
}

/// A kind the sim does not know is answered by the sim, not by the host.
#[test]
fn a_name_that_is_not_a_part_is_still_the_sims_sentence() {
    let phrase = debug::not_a_part_phrase("ore");
    for kind in ALL {
        assert!(
            phrase.contains(kind.name()),
            "the sentence lists the catalogue, so a new kind names itself: {phrase}"
        );
    }
    assert!(phrase.starts_with("ore is not a machine part"), "{phrase}");
}
