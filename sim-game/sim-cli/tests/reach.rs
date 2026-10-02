//! The headless game says whether a rock can be mined (ASSA-43), driven
//! through the REAL `sim-cli --plain` binary.
//!
//! **IT IS DRIVEN THROUGH THE BINARY ON PURPOSE.** A unit test on
//! `deposit_reach_note` proves the sentence is right and stays green if no
//! command ever prints it; that mistake has bitten me before. `env!(
//! "CARGO_BIN_EXE_sim-cli")` from inside `sim-cli`'s own package rebuilds the
//! binary first, so this cannot pass against a previous build either.
//!
//! The control is half the test: on a deposit that CAN be mined, `where` must
//! still read exactly as it always did. The bug was silence, and the fix for
//! silence is very easy to overcorrect into noise on every tile.

mod common;

use std::io::Write;
use std::process::{Command, Stdio};

use common::walk;
use sim::OreDeposit;

/// The first seed whose world holds a deposit nothing can mine, with the
/// nearest such deposit to spawn so the walk is short. 97.9% of worlds hold
/// one, so this search is a formality — but searching beats hard-coding,
/// because a hard-coded seed tests one world instead of the game.
fn seed_with_an_unreachable_deposit() -> (u64, OreDeposit, OreDeposit) {
    for seed in 1..400 {
        let (world, material, _fuel) = common::starters(seed);
        if !sim::ladder::hand_minable(world.species(material.species)) {
            continue; // the control needs a starter that CAN be mined
        }
        let spawn = world.spawn_tile();
        let bad = world
            .deposits
            .iter()
            .filter(|d| !sim::ladder::hand_minable(world.species(d.species)))
            .min_by_key(|d| walk(spawn, d.center));
        if let Some(bad) = bad {
            return (seed, bad.clone(), material);
        }
    }
    panic!("no seed in 1..400 had an unreachable deposit");
}

#[test]
fn the_plain_prompt_states_reach_and_never_invites_the_impossible() {
    let (seed, bad, good) = seed_with_an_unreachable_deposit();
    let (world, _, _) = common::starters(seed);
    let spawn = world.spawn_tile();
    let (bad_name, good_name) = (
        world.species(bad.species).name().to_string(),
        world.species(good.species).name().to_string(),
    );
    assert_ne!(bad_name, good_name, "the two halves must be different rock");

    let script = format!(
        "new {seed}
pause
deposits
at {} {}
goto {} {}
tick {}
where
mine
tick 1
goto {} {}
tick {}
where
quit
",
        bad.center.x,
        bad.center.y,
        bad.center.x,
        bad.center.y,
        walk(spawn, bad.center).max(1),
        good.center.x,
        good.center.y,
        walk(bad.center, good.center).max(1),
    );

    let saves = std::env::temp_dir().join(format!("assay-reach-{}", std::process::id()));
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

    // `at` reports reach without standing there.
    //
    // **PINNED TO ITS OWN LINE, NOT TO THE TRANSCRIPT.** This assertion was
    // first written against the whole of `stdout`, and deleting the note from
    // `at` altogether did not redden it: the `where` report below prints the
    // same sentence a few lines later, so the test passed for the wrong
    // reason. An assertion that cannot fail for the reason it exists is not an
    // assertion.
    let at_line = stdout
        .lines()
        .find(|l| l.starts_with(&format!("({}, {}): deposit", bad.center.x, bad.center.y)))
        .unwrap_or_else(|| panic!("`at` printed no deposit line\n{transcript}"));
    assert!(
        at_line.contains(&format!("{bad_name} is too hard for anything we can build")),
        "`at` on an unreachable deposit must say so: {at_line}\n{transcript}"
    );

    // `where`, twice: once on the dead rock, once on the starter.
    let standing: Vec<&str> = stdout
        .lines()
        .filter(|l| l.starts_with("You're on deposit"))
        .collect();
    assert_eq!(standing.len(), 2, "two `where` reports\n{transcript}");
    let (on_bad, on_good) = (standing[0], standing[1]);

    assert!(
        on_bad.contains(&format!("{bad_name} is too hard for anything we can build")),
        "standing on it must explain it\n{transcript}"
    );
    assert!(
        !on_bad.contains("`mine` to start mining it"),
        "NEVER INVITE THE IMPOSSIBLE: this was the worst line in the headless \
         game, an instruction that cannot work\n{transcript}"
    );

    // THE CONTROL. A deposit that yields must read exactly as before.
    assert!(
        on_good.contains("`mine` to start mining it"),
        "a minable deposit still invites the swing\n{transcript}"
    );
    assert!(
        !on_good.contains("too hard for anything"),
        "the fix for silence must not become noise on every tile\n{transcript}"
    );

    // And the refusal itself reaches the player, worded, with no drill promise.
    assert!(
        stdout.contains("too hard to mine"),
        "a refused swing says why\n{transcript}"
    );
    assert!(
        !stdout.contains("drills come later"),
        "decision 7: no drill reaches this ore\n{transcript}"
    );
}
