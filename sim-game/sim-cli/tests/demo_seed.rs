//! The world a stranger is actually handed keeps its promises (ASSA-60).
//!
//! **WHY A TEST AND NOT A VERIFICATION.** Seed 14247 is the Game Director's
//! pin for the friend playtest (ASSA-45). Before this file, `grep -rn 14247`
//! over the whole repo found two comments and nothing else: the world a
//! stranger will judge the game by existed only in a work item. That matters
//! because **worldgen moves** — ASSA-35 re-mapped 571 of 1000 seeds in one
//! morning — and because **the golden hash does not cover this**: that same
//! change left seed 42, the only seed either hash pins, untouched. A demo is
//! a prepared world, and nothing green could tell us when it stopped being
//! the world she played.
//!
//! The same morning showed what the failure costs. 10027 was pinned at 12:11
//! and withdrawn at 13:27, because spawn there stands on grade-A ore that no
//! hand-lit fire can smelt — and it had already been verified, exactly and
//! cleanly, by QA. Verification is an act; this file is the guard.
//!
//! **THESE ARE PROMISES, NOT A FINGERPRINT.** No tick-0 hash is pinned here
//! on purpose: a hash reddens on every worldgen move and says only "something
//! moved". Each assertion below names the promise it protects, so a failure
//! says which one broke and who has to answer for it. **The answer is never
//! to loosen a bound.** The seed is the Game Director's call: if one of these
//! reddens, the pin gets re-chosen or re-played by her.
//!
//! Measured on `5b152aa`, over seeds 1..=400, so that no box here is ticked on
//! a check that cannot fail:
//!
//! | promise | seeds that keep it |
//! |---|---|
//! | a deposit under spawn, hand-minable **and** rung-zero | 27 / 400 |
//! | a dead end within `SHORT_WALK` tiles | 139 / 400 |
//! | all three verdicts from the rocks beside spawn | 64 / 400 |
//!
//! 10027, the withdrawn pin, fails the first and the third.

use std::collections::BTreeSet;

use sim::{Assembly, Grade, Item, ItemKind, Mount, OreDeposit, Part, PartKind, SpeciesId, World};
use sim::{debug, ladder};

/// The Game Director's pin, 2026-10-02 13:27 (ASSA-45). A literal, because
/// this is the one world a stranger is handed; everything else is derived from
/// it, so only this number changes if the pin moves.
const FRIEND_SEED: u64 = 14247;

/// The pin she withdrew the same day. It is here as the **control**: the
/// checks below are only worth running if they can fail, and this seed is a
/// world that really was chosen and really was wrong. `unsmeltable.rs` plays
/// it through the prompt for the sentence it earned (ASSA-52).
const WITHDRAWN_SEED: u64 = 10027;

/// Tiles from spawn that still count as "the first minute". She walked to
/// 14247's dead end in 11 ticks at 10 ticks/s, and it sits at 9 tiles, so
/// this bound carries three tiles of headroom and 35% of seeds pass it.
const SHORT_WALK: i32 = 12;

/// Tiles from spawn whose rocks a player meets before they have decided
/// anything. On the pin this is exactly the two species her ruling names
/// (Tonore and Remdornite), which is the point: the design's whole lesson
/// comes out of the pair, not out of a hike across the map.
const NEAR_SPAWN: i32 = 20;

/// Distance from spawn to the nearest tile of a patch, which is what a player
/// walks: a radius-4 deposit whose centre is 13 away is 9 tiles of walking.
fn walk_from_spawn(world: &World, d: &OreDeposit) -> i32 {
    let spawn = world.spawn_tile();
    let dx = f64::from(d.center.x - spawn.x);
    let dy = f64::from(d.center.y - spawn.y);
    (dx * dx + dy * dy).sqrt() as i32 - i32::from(d.radius)
}

fn refined(species: SpeciesId, grade: Grade) -> Item {
    Item::new(ItemKind::Refined, species, grade)
}

/// Species a player can hold refined material of without building anything
/// first — hand-minable *and* smeltable by a hand-lit fire — and which this
/// world has a patch of within `NEAR_SPAWN`.
fn usable_rocks_beside_spawn(world: &World) -> Vec<SpeciesId> {
    let mut ids: Vec<SpeciesId> = world
        .deposits
        .iter()
        .filter(|d| walk_from_spawn(world, d) <= NEAR_SPAWN)
        .map(|d| d.species)
        .filter(|id| ladder::usable_from_bare_hands(&world.species, *id))
        .collect();
    ids.sort();
    ids.dedup();
    ids
}

/// Every verdict a one-head pick made of `from` can show a player who has
/// assayed nothing.
///
/// Both grades are swept because **grade is reachable, not given**: `sort`
/// raises any ore C->B->A at a loss (`recipe.rs`), so a C patch can still
/// yield an A part. The sweep goes through the real `stat_range`, so a part
/// row that stopped reading density, or a budget rule that changed, changes
/// this too.
fn verdicts_from(world: &World, from: &[SpeciesId]) -> BTreeSet<&'static str> {
    let mut seen = BTreeSet::new();
    for handle in from {
        for head in from {
            for handle_grade in Grade::ALL {
                for head_grade in Grade::ALL {
                    let pick = Assembly::new(
                        Part::of(PartKind::Frame(Mount::Held), refined(*handle, handle_grade)),
                        vec![Part::of(PartKind::Head, refined(*head, head_grade))],
                    );
                    seen.insert(pick.stat_range(&world.species).verdict().label());
                }
            }
        }
    }
    seen
}

/// PROMISE 1: the friend's first press mines, and what it mines can become a
/// part. Two conditions and not one — "hand-minable" was read as the whole
/// gate once already, and that is exactly how 10027 was chosen.
#[test]
fn the_rock_under_spawn_can_be_both_mined_and_smelted_by_hand() {
    let world = sim_net::fresh_world(FRIEND_SEED);
    let spawn = world.spawn_tile();
    let under_foot = world.deposit_at(spawn).unwrap_or_else(|| {
        panic!("seed {FRIEND_SEED} must put a deposit under spawn {spawn:?}: the friend's first press is `mine`, with no walking")
    });
    let rock = world.species(under_foot.species);
    let context = format!(
        "{} grade {} purity {} at {:?}",
        rock.name(),
        under_foot.grade().letter(),
        under_foot.purity,
        under_foot.center
    );

    assert!(
        ladder::hand_minable(rock),
        "spawn rock must be minable by hand: {context}"
    );
    assert!(
        ladder::usable_from_bare_hands(&world.species, under_foot.species),
        "SPAWN ROCK MINES BUT NEVER SMELTS, which is why seed {WITHDRAWN_SEED} was withdrawn: {context}. \
         A part needs REFINED material, so the gate is rung zero, not hand-minable"
    );
    assert!(
        debug::deposit_dead_end_note(&world, under_foot).is_none(),
        "and the sim must have nothing to warn about it: {context}"
    );

    // THE CONTROL, and the whole reason the assertion above is worth having:
    // the seed that was really chosen fails it. If this half ever goes green,
    // the check above has stopped proving anything and this file is wrong.
    let withdrawn = sim_net::fresh_world(WITHDRAWN_SEED);
    let bad = withdrawn
        .deposit_at(withdrawn.spawn_tile())
        .expect("the withdrawn pin also had a deposit under spawn");
    assert!(
        ladder::hand_minable(withdrawn.species(bad.species)),
        "the control's defect is subtle: the rock CAN be mined"
    );
    assert!(
        !ladder::usable_from_bare_hands(&withdrawn.species, bad.species),
        "CONTROL BROKEN: seed {WITHDRAWN_SEED}'s spawn rock became smeltable, so the check above \
         can no longer be shown to have teeth. Pick another failing world, do not delete this"
    );
}

/// PROMISE 2: the friend meets a rock nothing can mine in their first minute,
/// so ASSA-43's refusal is a thing they see rather than a thing we tested.
#[test]
fn a_dead_end_is_a_short_walk_from_spawn_and_says_so() {
    let world = sim_net::fresh_world(FRIEND_SEED);
    let mut dead_ends: Vec<&OreDeposit> = world
        .deposits
        .iter()
        .filter(|d| !ladder::hand_minable(world.species(d.species)))
        .collect();
    dead_ends.sort_by_key(|d| walk_from_spawn(&world, d));
    let nearest = dead_ends.first().unwrap_or_else(|| {
        panic!("seed {FRIEND_SEED} must contain a rock nothing can mine: it is how a player learns that hardness is a wall")
    });
    let walk = walk_from_spawn(&world, nearest);
    assert!(
        walk <= SHORT_WALK,
        "the nearest dead end is {walk} tiles away ({} at {:?}), past the first minute: \
         the friend would never meet the refusal",
        world.species(nearest.species).name(),
        nearest.center
    );

    // The promise is the sentence, not the predicate. `hand_minable` being
    // false is the sim's opinion; this is what the player is told, and the
    // two stopped being opposites on ASSA-52.
    let note = debug::deposit_reach_note(&world, nearest).unwrap_or_else(|| {
        panic!(
            "a rock nothing can mine must say so: {} at {:?} has no reach note",
            world.species(nearest.species).name(),
            nearest.center
        )
    });
    assert!(
        note.contains(world.species(nearest.species).name()),
        "the refusal must name the rock the player is standing on: {note}"
    );
}

/// PROMISE 3: the design lesson is visible from the rocks beside spawn. All
/// three verdicts, out of the two species a player meets first, decided by
/// which one they make the handle from — which is the lesson in one pair.
#[test]
fn all_three_verdicts_come_out_of_the_two_rocks_beside_spawn() {
    let world = sim_net::fresh_world(FRIEND_SEED);
    assert!(
        world.species.iter().all(|s| !s.assayed),
        "a fresh world is unassayed, which is what makes UNCERTAIN reachable at all"
    );

    let near = usable_rocks_beside_spawn(&world);
    let names: Vec<&str> = near.iter().map(|id| world.species(*id).name()).collect();
    let seen = verdicts_from(&world, &near);
    for want in ["SAFE", "UNCERTAIN", "WILL BREAK"] {
        assert!(
            seen.contains(want),
            "no pick built from {names:?} reads {want}, so a friend cannot meet that verdict \
             in their first session: got {seen:?}"
        );
    }

    // THE CONTROL: this is a property of 16% of worlds, not of worlds. The
    // withdrawn pin is one of the other 84% — nothing a player could build
    // there from any rock in the world reads WILL BREAK, so the verdict that
    // teaches them to assay before planting never appears.
    let withdrawn = sim_net::fresh_world(WITHDRAWN_SEED);
    let everywhere: Vec<SpeciesId> = {
        let mut ids: Vec<SpeciesId> = withdrawn
            .deposits
            .iter()
            .map(|d| d.species)
            .filter(|id| ladder::usable_from_bare_hands(&withdrawn.species, *id))
            .collect();
        ids.sort();
        ids.dedup();
        ids
    };
    assert!(
        !verdicts_from(&withdrawn, &everywhere).contains("WILL BREAK"),
        "CONTROL BROKEN: seed {WITHDRAWN_SEED} now shows WILL BREAK, so passing this check is \
         no longer evidence of anything. Find another world that fails it"
    );
}
