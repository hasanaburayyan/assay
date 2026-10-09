//! **A STALL THAT BECOMES A DIFFERENT STALL, THROUGH THE REAL `sim-cli`
//! BINARY** (ASSA-364 box 6: *"`sim-cli` can show the second sentence without
//! the Godot client"*).
//!
//! The rule and its wording are pinned in `sim`
//! (`smelter.rs::a_stall_that_becomes_a_different_stall_is_announced_once` and
//! `both_notices_about_one_machine_name_their_reason_and_never_claim_a_stop`).
//! Those tests build a fixture world and call `step` in-process. **Neither of
//! them proves a person can reach the second sentence by typing**, which is the
//! charter's second principle — the headless game is the reference client, not
//! a stopgap — and it is the only box on the item that a source reading cannot
//! answer. `describe_event` routes `debug::event_line`, so the surface exists;
//! what did not exist is a run that arrives at it.
//!
//! **THE WORLD IS GENERATED, NOT A FIXTURE, AND THAT IS THE POINT.** The sim
//! tests hand themselves a species built to not light. Here the script has to
//! find a rock in a rolled world that a player can mine, that the sim accepts as
//! fuel, and that a hand spark will not set alight — and then walk to it. If
//! `NoFuel -> FuelWontLight` were unreachable in a real world, this test could
//! not be written, and the item's claim that it costs one `Insert` would be
//! false.
//!
//! **BOTH SURFACES, BECAUSE THE DEFECT WAS ABOUT A SENTENCE OUTLIVING ITS
//! CONDITION:** the event stream (the toast's words) and `halted` (the standing
//! table). A fix that announced the new reason but left the table reading `no
//! fuel` would be half of it.

mod common;

use std::io::Write;
use std::process::{Command, Stdio};

use common::walk;
use sim::{OreDeposit, SmelterStall, SmelterState, World, debug, ladder};

/// The nearest rock in this world that a player can mine, that counts as fuel
/// at the grade its deposit rolled, and that a hand spark will not light.
///
/// **ASKS THE SIM FOR ALL THREE, and the third is asked as `lights_from_cold`
/// rather than as a heat-tolerance comparison.** `ladder` is the one place that
/// decides whether a rock is fuel and what lights it (ASSA-93, ASSA-139); a
/// fourth copy of either comparison in a test is how a test comes to prove a
/// different game from the one that ships.
///
/// The grade matters on one half and not the other, which is not a slip:
/// reactivity scales with grade so "is it fuel" is asked at the deposit's own
/// grade — the grade the mined ore will carry, and the grade `Insert` will
/// judge it at — while heat tolerance never scales, so lightability is a
/// per-species constant (`ladder::lights_in_fire`'s own note).
fn wont_light_fuel(world: &World) -> Option<OreDeposit> {
    let spawn = world.spawn_tile();
    world
        .deposits
        .iter()
        .filter(|d| {
            let s = world.species(d.species);
            ladder::hand_minable(s)
                && ladder::burn_temperature_at(s, d.grade()).is_some()
                && !ladder::lights_from_cold(s)
        })
        .min_by_key(|d| walk(spawn, d.center))
        .cloned()
}

#[test]
fn the_plain_prompt_shows_the_second_stall_and_the_halted_table_follows_it() {
    // The loop conditions come from `common` for the same reason `first_plate`
    // takes them from there: two tests that choose their own worlds are two
    // tests of two different games. The extra condition is this test's own.
    let starter = common::demo_seed(|w, _, _| wont_light_fuel(w).is_some());
    let common::Starter {
        seed,
        world,
        material,
        ..
    } = &starter;
    let (seed, world, material) = (*seed, world, material);
    let hot = wont_light_fuel(world).expect("the search above only returns such a seed");
    let ms = world.species(material.species);
    let hs = world.species(hot.species);
    let spawn = world.spawn_tile();

    // THE PREMISES, ASSERTED RATHER THAN ASSUMED. Each one is a way this test
    // could pass while measuring nothing: a rock nobody can mine never reaches
    // the slot, a rock the sim refuses as fuel is rejected before the slot is
    // looked at (`RejectReason::NotFuel`), and a rock that lights from cold
    // puts the smelter to WORK instead of into a second stall — which would
    // leave one stall sentence in the transcript and an assertion counting it.
    assert!(
        ladder::hand_minable(hs),
        "the fuel has to be minable by hand: {}",
        hs.name()
    );
    assert!(
        ladder::burn_temperature_at(hs, hot.grade()).is_some(),
        "and the sim has to accept it as fuel at the grade the deposit rolled: {} ({})",
        hs.name(),
        hot.grade().letter()
    );
    assert!(
        !ladder::lights_from_cold(hs),
        "and a hand spark must NOT light it, or the smelter works instead of stalling: {}",
        hs.name()
    );

    let mat_ore = format!(
        "ore:{}:{}",
        ms.name().to_ascii_lowercase(),
        material.grade().letter().to_ascii_lowercase()
    );
    let hot_ore = format!(
        "ore:{}:{}",
        hs.name().to_ascii_lowercase(),
        hot.grade().letter().to_ascii_lowercase()
    );

    // **`halted` IS ASKED TWICE AND THE TWO ANSWERS ARE THE MEASUREMENT.** One
    // between the stalls and one after, so the standing table is read in both
    // conditions by one script. `log` is deliberately NOT in here: it reprints
    // every event line, and the counts below would then be two for free.
    let script = format!(
        "new {seed}
pause
goto {mx} {my}
tick {to_material}
mine
tick 80
stop
craft smelter {mat_ore}
tick 40
goto {hx} {hy}
tick {to_hot}
mine
tick 80
stop
place smelter
tick 1
insert 0 ore {mat_ore} 10
tick 30
halted
insert 0 fuel {hot_ore} 3
tick 60
halted
buildings
quit
",
        mx = material.center.x,
        my = material.center.y,
        to_material = walk(spawn, material.center).max(1),
        hx = hot.center.x,
        hy = hot.center.y,
        to_hot = walk(material.center, hot.center).max(1),
    );

    let saves = std::env::temp_dir().join(format!("assay-second-stall-{}", std::process::id()));
    let mut child = Command::new(env!("CARGO_BIN_EXE_sim-cli"))
        .arg("--plain")
        .arg("--name")
        .arg("ada")
        .env("R2TS_SAVES_DIR", &saves)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("sim-cli starts");
    child
        .stdin
        .take()
        .unwrap()
        .write_all(script.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let _ = std::fs::remove_dir_all(&saves);
    let stdout = String::from_utf8_lossy(&out.stdout);
    let transcript = format!(
        "--- script\n{script}\n--- stdout\n{stdout}\n--- stderr\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.status.success(), "{transcript}");
    assert!(
        !stdout.contains("rejected"),
        "every command in this script is legal; a rejection means the \
         play-through did not happen\n{transcript}"
    );

    // **THE TWO EXPECTED CLAUSES ARE BUILT, NOT TYPED.** `smelter_state_line`
    // is the function the shipped arm uses, so a wording change moves this
    // test's expectation with it and cannot leave it passing on a sentence that
    // no longer exists. Calling it on a locally built world is safe for exactly
    // these two stalls: `stall_reason`'s `NoFuel` and `FuelWontLight` arms read
    // nothing out of the world (unlike `OutputHoldsAnother`, which names an
    // item), and the world is the same seed either way.
    let first = debug::smelter_state_line(world, SmelterState::Stalled(SmelterStall::NoFuel));
    let second =
        debug::smelter_state_line(world, SmelterState::Stalled(SmelterStall::FuelWontLight));
    assert_ne!(
        first, second,
        "if these two ever word the same, this whole test is comparing a \
         sentence with itself"
    );

    // Event lines are the only ones that lead with `tick <n> ·`; the halted
    // table's rows lead with the state clause itself. That is what keeps the
    // two surfaces countable apart in one transcript.
    let announced: Vec<&str> = stdout
        .lines()
        .map(str::trim_start)
        .filter(|l| l.starts_with("tick ") && l.contains("stalled:"))
        .collect();
    assert_eq!(
        announced.len(),
        2,
        "one smelter, two stalls, two notices: a third is the Game Director's \
         rule 2 broken and a second is the whole defect\n{transcript}"
    );
    assert!(
        announced[0].contains(&first),
        "the first notice names the first reason: {}\n{transcript}",
        announced[0]
    );
    assert!(
        announced[1].contains(&second),
        "THE DEFECT: one `Insert` later the smelter is still stopped for a NEW \
         reason, and this is the sentence that was never printed: {}\n{transcript}",
        announced[1]
    );

    // **SAME SUBJECT PHRASE BOTH TIMES** (her test 3), read off the transcript
    // rather than typed, so it is the CLI's own way of naming a building that
    // is being compared. Two notices whose identities differ read as a second
    // machine stalling rather than one machine changing its mind.
    let subject = |line: &str| line.rsplit(" · ").next().unwrap_or("").to_string();
    assert_eq!(
        subject(announced[0]),
        subject(announced[1]),
        "both notices are about one machine\n{transcript}"
    );
    assert!(
        subject(announced[0]).contains("smelter"),
        "and the subject phrase has to name the smelter: {}\n{transcript}",
        subject(announced[0])
    );

    // **AND THE STANDING TABLE MOVED WITH IT.** The defect's cost was a screen
    // reading `no fuel` about a smelter with fuel in its slot; a sim that
    // announced the new reason and left `halted` on the old one would have
    // fixed the toast and kept the lie.
    let standing: Vec<&str> = stdout
        .lines()
        .map(str::trim_start)
        .filter(|l| l.starts_with("stalled:"))
        .collect();
    assert_eq!(
        standing.len(),
        2,
        "`halted` is typed twice and answers once each\n{transcript}"
    );
    assert!(
        standing[0].starts_with(&first),
        "between the stalls the table says the first reason: {}\n{transcript}",
        standing[0]
    );
    assert!(
        standing[1].starts_with(&second),
        "after the insert it says the second, and NOT the reason the player \
         just dealt with: {}\n{transcript}",
        standing[1]
    );

    // The machine really is still stopped, which is what makes the second
    // notice a correction rather than a new event: `buildings` lists it with
    // the stall on its row.
    let row = stdout
        .lines()
        .find(|l| l.contains("   0  smelter"))
        .unwrap_or_else(|| panic!("no smelter row\n{transcript}"));
    assert!(row.contains(&second), "{row}\n{transcript}");
}
