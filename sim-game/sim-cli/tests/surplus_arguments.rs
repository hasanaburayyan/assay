//! The reference client says when it ignored a word (ASSA-79), through the
//! REAL binary and the prompt a player actually types at.
//!
//! **THE REPRODUCTIONS ARE THE GAME DIRECTOR'S OWN**, typed on the board's
//! bench: `mine 12` expecting twelve ore and getting continuous mining,
//! `take 0 banana`, `where now`. Each extra word was neither used nor refused.
//!
//! Driven through `--plain` rather than against `Args` directly, because the
//! claim is about what a person at the prompt is told. A unit test on the
//! wrapper would prove it can count and say nothing about whether the
//! dispatcher consults it — the shape that let `check_join` be right and
//! uncalled (ASSA-40).

use std::io::Write;
use std::process::{Command, Stdio};

/// What `--plain` prints for this script.
fn play(script: &str) -> String {
    let saves = std::env::temp_dir().join(format!("assay-assa79-{}", std::process::id()));
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
        .expect("piped")
        .write_all(script.as_bytes())
        .expect("write the script");
    let out = child.wait_with_output().expect("sim-cli finishes");
    let _ = std::fs::remove_dir_all(&saves);
    assert!(
        out.status.success(),
        "sim-cli failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

/// **BOTH DIRECTIONS, OR THIS PROVES NOTHING.** A check that only looked at
/// the surplus cases would pass just as well against a client that complains
/// about every command.
#[test]
fn a_word_the_command_never_read_is_named_and_a_clean_command_is_silent() {
    let said = play(
        "new 14247
pause
mine 12
tick 2
where now
assay now
quit
",
    );
    for (line, word) in [
        ("`mine` takes no arguments", "12"),
        ("`where` takes no arguments", "now"),
        ("`assay` takes no arguments", "now"),
    ] {
        let complaint = said
            .lines()
            .find(|l| l.starts_with(line))
            .unwrap_or_else(|| panic!("no complaint for {line:?}\n{said}"));
        assert!(
            complaint.contains(word),
            "the complaint must quote the words it ignored: {complaint}"
        );
    }
    // AND THE COMMAND STILL RAN. The surplus is reported, not a refusal: the
    // player asked to mine and the ore must arrive.
    assert!(
        said.contains("you started mining"),
        "the command itself was swallowed by the complaint\n{said}"
    );

    // THE CONTROL: the same verbs, clean, say nothing.
    let clean = play(
        "new 14247
pause
mine
tick 2
where
assay
quit
",
    );
    assert!(
        !clean.contains("takes no arguments"),
        "a clean command was accused of a surplus\n{clean}"
    );
    assert!(clean.contains("you started mining"), "{clean}");
}

/// A command that takes arguments counts them, and the one that takes a LIST
/// does not: `assemble` reads every word by design, and a variadic arm that
/// started complaining would be the check turning into a bug of its own.
#[test]
fn counting_is_per_command_and_a_list_command_reads_everything() {
    let said = play(
        "new 14247
pause
take 0 banana
assemble handle:tonore head:tonore extra:tonore
quit
",
    );
    assert!(
        said.contains("`take` takes one argument"),
        "take swallowed its extra word\n{said}"
    );
    assert!(
        said.contains("banana"),
        "the complaint must quote what it ignored\n{said}"
    );
    // `assemble` fails here for want of the parts, which is fine and expected
    // — what must NOT appear is a surplus complaint about its own list.
    assert!(
        !said.contains("`assemble` takes"),
        "a variadic command counted its arguments\n{said}"
    );
}

/// **ONLY ON SUCCESS**, because a command that failed has already said
/// something more useful than a count. A player who typed `goto 1` wants
/// "Missing y", not "goto takes two arguments" — and a player who typed
/// `goto 1 2 3 banana` wants to know the banana went nowhere.
#[test]
fn a_failed_command_keeps_its_own_error_instead_of_a_count() {
    let said = play(
        "new 14247
pause
goto 1
quit
",
    );
    assert!(
        said.contains("Missing y"),
        "the command's own error is the useful one\n{said}"
    );
    assert!(
        !said.contains("takes"),
        "a failing command was told about arity instead of its real problem\n{said}"
    );
}
