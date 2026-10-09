//! `design` can name the part you are SAVING UP FOR (ASSA-330), driven through
//! the real `sim-cli --plain` binary.
//!
//! The sim goes out of its way to weigh a design the pack cannot pay for:
//! `assembly::plan` answers `Weighed { missing }` instead of refusing and
//! `design_preview` prints have/need beside the verdict (the Game Director's
//! §5.3, ruled again on ASSA-324 box 6). The terminal could not TYPE one,
//! because every argument was resolved against the player's own stacks — so
//! the Godot build screen could ask a question the reference client could not,
//! which is CLAUDE.md's second principle inverted.
//!
//! **A FRESH WORLD IS THE WHOLE FIXTURE, AND THAT IS THE POINT.** Nothing is
//! mined and nothing is made, so the pack is empty and every spec below names
//! a part that does not exist anywhere in the world. Five reads off one
//! session:
//!
//! 1. a design named in full — the numbers, `need 1 · have 0`, and the refusal
//!    PREDICTED;
//! 2. `assemble` with the very same words — still "you have no", because it
//!    spends what it names;
//! 3. `make` likewise, so the change is not loose in the resolver everything
//!    shares;
//! 4. a spec with no grade — refused, naming the grade;
//! 5. a spec with no species — refused, naming the species.
//!
//! Reads 2 and 3 are the ones that would catch this going too far. The item's
//! own words: *"Resolving against the pack is right for a command that SPENDS
//! things"*.

use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn design_prices_a_part_nobody_has_made_and_the_spending_commands_still_refuse() {
    let seed = 7;
    // Species names are generated per seed, so the spec is built from the
    // roster rather than written out. Any species does: `design` spends
    // nothing, so this test needs no deposit, no fuel and no ladder.
    let world = sim_net::fresh_world(seed);
    let species = world.species[0].name().to_ascii_lowercase();
    let handle = format!("handle:{species}:a");
    let head = format!("head:{species}:a");
    let refined = format!("refined:{species}:a");

    let script = format!(
        "new {seed}
pause
inv
design {handle} {head}
assemble {handle} {head}
make head {refined}
design head:{species}
design head
quit
"
    );

    let saves = std::env::temp_dir().join(format!("assay-design-unowned-{}", std::process::id()));
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

    // THE PREMISE FIRST. With anything in the pack, read 1 could be the old
    // behaviour answering and nobody would know.
    let carrying = stdout
        .lines()
        .find(|l| l.starts_with("Carrying "))
        .unwrap_or_else(|| panic!("no inventory line\n{transcript}"));
    assert!(
        carrying.contains("nothing"),
        "this test is about an empty pack: {carrying}\n{transcript}"
    );

    // READ 1 — THE DESIGN IS WEIGHED. Its verdict line carries mass, and it is
    // not a refusal: `not a machine` would mean the preview declined to answer.
    let readout = stdout
        .lines()
        .find(|l| l.contains("· mass "))
        .unwrap_or_else(|| {
            panic!("`design` printed no readout for a part nobody owns\n{transcript}")
        });
    assert!(
        !readout.contains("not a machine"),
        "a design you cannot afford is weighed, not refused: {readout}\n{transcript}"
    );

    // ...and the counts the Game Director asked for, plus the press's own
    // refusal said before it is pressed.
    //
    // MOVED TO §5.5's WORDING (ASSA-338), which is what the comment that used
    // to sit here predicted: `0/1` is now `need 1 · have 0`, because a slash is
    // a ratio's mark and `2/1` reads as 200% of something. The window's block 6
    // already said it her way, so until this landed the two clients spelled one
    // fact apart — and this is the one the charter calls the reference client.
    // ONE ENTRY PER LINE as of her third ruling, so the counts and the refusal
    // are no longer one string to search: the entries sit under the header and
    // the clause closes them at the header's own indent.
    let lines: Vec<&str> = stdout.lines().collect();
    let header = lines
        .iter()
        .position(|l| l.contains("your pack:"))
        .unwrap_or_else(|| panic!("the readout counted no parts\n{transcript}"));
    let entries: Vec<&&str> = lines[header + 1..]
        .iter()
        .take_while(|l| l.contains(" need ") && l.contains(" · have "))
        .collect();
    assert!(
        !entries.is_empty() && entries.iter().all(|l| l.ends_with("need 1 · have 0")),
        "every part of this design is unowned, so each entry is its own line \
         reading `need 1 · have 0`: {entries:?}\n{transcript}"
    );
    let clause = lines[header + 1 + entries.len()..]
        .iter()
        .find(|l| l.contains("not enough"))
        .unwrap_or_else(|| panic!("the refusal was not predicted\n{transcript}"));
    // The clause carries the item's DISPLAY name (`Bokase handle (A)`), not the
    // spec that was typed (`handle:bokase:a`), so the kind word is what this
    // can honestly assert without rebuilding an `Item` from a string here.
    assert!(
        clause.contains("handle"),
        "the clause names `plan`'s own choice — the FIRST entry the pack cannot \
         pay for, which is the frame here: {clause:?}\n{transcript}"
    );

    // READS 2 AND 3 — NO COMMAND THAT SPENDS SOMETHING MOVED. Same words as
    // read 1, one line apart in the same session.
    for expected in [
        format!("You have no handle matching `{handle}`"),
        format!("You have no refined matching `{refined}`"),
    ] {
        assert!(
            stdout.contains(&expected),
            "missing {expected:?} — a command that spends items must still \
             resolve against the pack\n{transcript}"
        );
    }

    // READS 4 AND 5 — A HALF-SPEC NAMES THE PART OF ITSELF THAT IS MISSING,
    // and does not answer "you have no" to a player who is asking about a
    // part they know they do not have.
    for expected in ["does not say which grade", "does not say which species"] {
        assert!(
            stdout.contains(expected),
            "missing {expected:?}\n{transcript}"
        );
    }
}
