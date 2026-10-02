//! A sim sentence names the action, never the keystrokes (ASSA-67).
//!
//! `debug::event_line` is the one function whose output a host renders
//! **verbatim**: `sim-cli` prints it and the Godot client puts it in its log
//! (`AssaySim.event_lines` → `main.gd::_remember_events`). Thirteen of its
//! lines used to name a `sim-cli` command — the worst at the pivot of the whole
//! demo, telling a player to `insert 0 fuel <item>` while **Fuel** and
//! **Smelt** buttons sat on their ore row in the same window. It did not merely
//! fail to help; it pointed away from the thing that works.
//!
//! The Game Director's ruling is a rule and not thirteen patches: the sim knows
//! "this building needs fuel and ore before it runs" and must not know that
//! some host spells that `insert`. That is principle 1 of the repo's
//! `CLAUDE.md` applied to prose — the sim should no more know there is a
//! command line than it should know there is a renderer.
//!
//! **The table functions keep their syntax and that is correct.**
//! `species_table`, `building_table`, `part_table`, `built_table` and
//! `recipe_table` are read at a prompt by someone who has one.

use sim::{
    BuildingId, Event, Grade, Input, Item, ItemKind, Mount, PartKind, PlayerCommand, PlayerId,
    RecipeId, RejectReason, Slot, SpeciesId, SystemCommand, TilePos, World, WorldConfig, debug,
    step,
};

/// This crate's own source, so the guard cannot drift from the thing it
/// guards: there is no second copy to update.
const DEBUG_RS: &str = include_str!("../src/debug.rs");

/// `event_line`'s body, from its signature to the next item at column zero.
fn event_line_body() -> &'static str {
    let start = DEBUG_RS
        .find("pub fn event_line")
        .expect("event_line is still called that");
    let rest = &DEBUG_RS[start..];
    let end = rest[1..]
        .find("\npub fn ")
        .map_or(rest.len(), |i| i + 1 + 1);
    &rest[..end]
}

/// **THE RULE IS MECHANICAL, WHICH IS WHY IT CAN BE A GUARD: no backtick
/// survives in this function's prose at all.**
///
/// It used to be the weaker "no backtick is followed by a letter", because one
/// pair was legitimate — the echo of the command the player sent, `` `{}` was
/// rejected ``, a placeholder rather than a literal. **ASSA-70 took the echo
/// away** (it was `sim-cli` syntax too, assembled at runtime where no source
/// scan could see it), so the exception went with it and what is left is the
/// simpler rule. A backtick here now means somebody is quoting something at a
/// player, and in this function there is nothing a player could be shown in
/// backticks that is not a host's dialect.
///
/// Checked against the source rather than against a list of today's sentences,
/// because the thing to prevent is the next one.
#[test]
fn no_event_line_sentence_spells_a_command() {
    let body = event_line_body();
    let mut prose_lines = 0;
    for (n, line) in body.lines().enumerate() {
        // Comments may discuss `insert` and `sim-cli` freely; players never
        // read them.
        if line.trim_start().starts_with("//") {
            continue;
        }
        prose_lines += 1;
        assert!(
            !line.contains('`'),
            "event_line quotes something at a player, body line {n}: {line}\n\
             A sim sentence names the ACTION, not the keystrokes: a host with \
             buttons cannot type it, and the sim must not know that some host \
             has a prompt (ASSA-67, ASSA-70)."
        );
    }
    // **NON-VACUITY HAD TO CHANGE SHAPE WITH THE RULE.** While one backtick pair
    // was legal, "I found some" proved the scan was looking at the right text.
    // Now zero is the passing answer, so the thing to prove is that there was
    // text to scan at all — and the slice itself is pinned at both ends by the
    // test below, which is the other half of this.
    assert!(
        prose_lines > 200,
        "only {prose_lines} non-comment lines in event_line; it is a long match \
         over every Event, so this guard is reading the wrong slice"
    );
}

/// The body slice is the other half of the guard: if it silently captured
/// nothing, or captured the whole file, the test above would be about the wrong
/// text. Both ends are pinned to something only `event_line` contains.
#[test]
fn the_guard_reads_event_line_and_not_the_tables() {
    let body = event_line_body();
    assert!(
        body.contains("Event::BuildingPlaced"),
        "the slice must reach into the match"
    );
    assert!(
        !body.contains("pub fn summary"),
        "the slice must stop at the next function"
    );
    // The tables are outside it and keep their syntax, which is the point of
    // slicing at all.
    assert!(
        debug::recipe_table().contains('`') || debug::part_table().contains('`'),
        "a CLI table may still teach syntax; if neither does any more, this \
         guard's scope has changed and should be re-read"
    );
}

fn world() -> World {
    World::new(WorldConfig {
        seed: 9,
        ..WorldConfig::default()
    })
}

fn placed(item: Item) -> String {
    debug::event_line(
        &world(),
        Some(PlayerId(0)),
        &Event::BuildingPlaced {
            player: PlayerId(0),
            building: BuildingId(0),
            item,
            pos: TilePos::new(1, 1),
        },
    )
}

/// **THE HINT GOES ONLY WHERE IT IS TRUE.** The line it replaced told the owner
/// of a drill to insert fuel and ore into it — a machine takes nothing in, and
/// says so in its own rejection. So a smelter gets the clause and anything else
/// gets the bare placement sentence, rather than a hint I would be inventing.
///
/// **CORRECTION, MINE** (the Game Director read #94 after it merged): I wrote
/// that `BuildingPlaced` fires for a planted machine too. It does not — `Place`
/// accepts only a smelter and a planted machine emits `MachinePlaced` — so the
/// machine arm is unreachable through `step` today and this test reaches it by
/// constructing the event directly. It stays as future-proofing for the day a
/// second placeable exists, which is also why the `if` in `debug.rs` stays.
#[test]
fn a_placed_smelter_says_what_it_needs_and_a_machine_does_not() {
    let smelter = placed(Item::new(ItemKind::Smelter, SpeciesId(0), Grade::C));
    assert!(
        smelter.contains("it needs fuel and ore before it will run"),
        "{smelter}"
    );
    let drill = placed(Item::new(
        ItemKind::Part(PartKind::Frame(Mount::Planted)),
        SpeciesId(0),
        Grade::C,
    ));
    assert!(
        !drill.contains("fuel"),
        "a machine takes nothing in, so it must not be sent looking for fuel: {drill}"
    );
    assert!(
        drill.contains("as building 0 at (1, 1)"),
        "it still says what was placed and where: {drill}"
    );
}

/// A rejection a player meets by clicking rather than typing has to be readable
/// without a prompt.
///
/// **THIS TEST USED TO PIN THE OPPOSITE OF ITS LAST ASSERTION** — that the echo
/// of the player's own command survived in backticks, which was the one place
/// ASSA-67 left syntax standing. ASSA-70 ruled it out: the echo was `sim-cli`
/// spelling too, built at runtime from a value, so no scan of the source ever
/// saw it. The pin went to `no_refusal_shows_a_player_a_command_line` below,
/// inverted.
#[test]
fn a_rejection_reads_without_a_prompt() {
    let line = refusal(&world(), PlayerCommand::Mine, RejectReason::NotInsertable);
    assert!(
        line.contains("it only gives out what it has mined"),
        "{line}"
    );
    assert!(
        !line.contains('`'),
        "nothing is quoted at a player who has nowhere to type it: {line}"
    );
    assert!(
        line.starts_with("mining was refused: "),
        "the action is named, in words: {line}"
    );
}

fn refusal(world: &World, command: PlayerCommand, reason: RejectReason) -> String {
    debug::event_line(
        world,
        Some(PlayerId(0)),
        &Event::CommandRejected {
            player: PlayerId(0),
            command,
            reason,
        },
    )
}

fn world_with_players() -> World {
    let mut world = world();
    let joins = [
        Input::System(SystemCommand::AddPlayer { name: "ada".into() }),
        Input::System(SystemCommand::AddPlayer {
            name: "grace".into(),
        }),
    ];
    step(&mut world, &joins, &mut Vec::new());
    world
}

/// One sample of every `PlayerCommand`, and **the exhaustive match is what keeps
/// the list honest**: a new variant fails to compile here until somebody words
/// its refusal, which is the only way a list like this does not go stale. (The
/// samples need not be legal — a refused command never happened.)
fn variant_name(cmd: &PlayerCommand) -> &'static str {
    match cmd {
        PlayerCommand::Mine => "Mine",
        PlayerCommand::Craft { .. } => "Craft",
        PlayerCommand::Place { .. } => "Place",
        PlayerCommand::Insert { .. } => "Insert",
        PlayerCommand::Take { .. } => "Take",
        PlayerCommand::Pickup { .. } => "Pickup",
        PlayerCommand::Assay => "Assay",
        PlayerCommand::Rename { .. } => "Rename",
        PlayerCommand::GrantRename { .. } => "GrantRename",
        PlayerCommand::MakePart { .. } => "MakePart",
        PlayerCommand::Assemble { .. } => "Assemble",
        PlayerCommand::Equip { .. } => "Equip",
        PlayerCommand::Unequip => "Unequip",
        PlayerCommand::PlaceAssembly { .. } => "PlaceAssembly",
        PlayerCommand::MoveTo { .. } => "MoveTo",
        PlayerCommand::Stop => "Stop",
    }
}

fn every_command() -> Vec<PlayerCommand> {
    let ore = Item::new(ItemKind::Ore, SpeciesId(0), Grade::C);
    let refined = Item::new(ItemKind::Refined, SpeciesId(1), Grade::B);
    let head = Item::new(ItemKind::Part(PartKind::Head), SpeciesId(1), Grade::B);
    let frame = Item::new(
        ItemKind::Part(PartKind::Frame(Mount::Held)),
        SpeciesId(0),
        Grade::C,
    );
    vec![
        PlayerCommand::Mine,
        PlayerCommand::Craft {
            recipe: RecipeId::Sort,
            item: ore,
            count: 3,
        },
        PlayerCommand::Place {
            item: Item::new(ItemKind::Smelter, SpeciesId(0), Grade::C),
            pos: TilePos::new(4, 5),
        },
        PlayerCommand::Insert {
            building: BuildingId(0),
            slot: Slot::Fuel,
            item: ore,
            count: 10,
        },
        PlayerCommand::Take {
            building: BuildingId(0),
        },
        PlayerCommand::Pickup {
            building: BuildingId(0),
        },
        PlayerCommand::Assay,
        PlayerCommand::Rename {
            species: SpeciesId(0),
            name: "tin".into(),
        },
        PlayerCommand::GrantRename {
            species: SpeciesId(0),
            to: PlayerId(1),
        },
        PlayerCommand::MakePart {
            kind: PartKind::Head,
            material: refined,
            count: 1,
        },
        PlayerCommand::Assemble {
            frame,
            mounted: vec![head],
        },
        PlayerCommand::Equip { assembly: 0 },
        PlayerCommand::Unequip,
        PlayerCommand::PlaceAssembly {
            assembly: 0,
            pos: TilePos::new(6, 7),
        },
        PlayerCommand::MoveTo {
            target: TilePos::new(12, 5),
        },
        PlayerCommand::Stop,
    ]
}

/// **THE FOURTEENTH SENTENCE, AND NO SOURCE SCAN COULD EVER HAVE FOUND IT**
/// (Game Director, ASSA-70). The refusal wrapper spelled the command with
/// `command_line`, so a player who pressed **Fuel** read `` `insert 0 fuel
/// ore:minyte:b 10` was rejected ``. The syntax was a runtime *value*, which is
/// exactly why this guard renders every variant instead of reading the source
/// like the one at the top of this file.
///
/// **THE CHECK IS AGAINST `command_line` ITSELF, not against a list of words.**
/// The CLI verb is read out of the CLI spelling of the same command, so the day
/// someone renames `goto` the guard follows without being edited. Matching is by
/// whole word, which is what lets the prose keep the *nouns* a player sees on a
/// button ("fuel slot") while refusing the *verbs* only a prompt accepts
/// ("stopping" is not "stop").
#[test]
fn no_refusal_shows_a_player_a_command_line() {
    let world = world_with_players();
    let commands = every_command();
    let mut seen: Vec<&str> = commands.iter().map(variant_name).collect();
    seen.sort_unstable();
    let before = seen.len();
    seen.dedup();
    assert_eq!(
        seen.len(),
        before,
        "one sample per variant, and these repeat: {seen:?}"
    );
    assert_eq!(
        before, 16,
        "every PlayerCommand variant has a sample; variant_name is exhaustive, so \
         a new one cannot reach here unlisted"
    );

    for command in &commands {
        let cli = debug::command_line(command, &world);
        let verb = cli
            .split(' ')
            .next()
            .expect("a command spells as something");
        let line = refusal(&world, command.clone(), RejectReason::SlotFull);
        let what = variant_name(command);

        assert!(
            !line.contains('`'),
            "{what}: a refused command is quoted at a player who may have clicked \
             a button: {line}"
        );
        // **ONLY FOR THE SPELLINGS THAT CARRY ARGUMENTS**, which is where the
        // defect lived ("insert 0 fuel ore:minyte:b 10"). A one-word spelling
        // cannot be checked as a substring, because a gerund legitimately
        // contains its own verb: "assaying" holds "assay", "stopping" holds
        // "stop". Those are covered by the whole-word check below, which is the
        // real rule.
        assert!(
            !cli.contains(' ') || !line.contains(&cli),
            "{what}: the refusal spells the command as sim-cli syntax (`{cli}`): {line}"
        );
        for token in line.split(|c: char| !c.is_ascii_alphanumeric()) {
            assert_ne!(
                token, verb,
                "{what}: `{verb}` is a keystroke, not an action, and only a host \
                 with a prompt can accept it: {line}"
            );
        }
        // An `item_spec` is the other CLI-only spelling (`ore:tonore:c`); the
        // wrapper's own colon before the reason is the only one that belongs.
        assert_eq!(
            line.matches(':').count(),
            1,
            "{what}: a colon-spelled item or a second clause has crept in: {line}"
        );
        assert!(
            line.contains("was refused: that slot is full"),
            "{what}: the reason half is unchanged and still said once: {line}"
        );
    }
}

/// **A REFUSAL READS AS THE MIRROR OF THE EVENT THAT DID NOT HAPPEN**, which is
/// the Game Director's own test for whether the prose is right. Derived from the
/// success sentence at runtime rather than written out twice: the object phrase
/// of `ItemsInserted` must appear verbatim in the refusal of the `Insert` that
/// would have produced it, so the two cannot drift apart.
#[test]
fn a_refusal_mirrors_the_success_it_would_have_been() {
    let world = world_with_players();
    let (building, slot, count) = (BuildingId(0), Slot::Fuel, 10);
    let item = Item::new(ItemKind::Ore, SpeciesId(0), Grade::C);

    let success = debug::event_line(
        &world,
        Some(PlayerId(0)),
        &Event::ItemsInserted {
            player: PlayerId(0),
            building,
            slot,
            item,
            count,
            left: 0,
        },
    );
    let object = success
        .split_once(" put ")
        .expect("the success sentence still reads \"you put ...\"")
        .1;
    assert!(
        object.contains("fuel slot"),
        "the phrase under test is the whole object of the sentence: {object}"
    );

    let refused = refusal(
        &world,
        PlayerCommand::Insert {
            building,
            slot,
            item,
            count,
        },
        RejectReason::SlotFull,
    );
    assert!(
        refused.contains(object),
        "the refusal must name what the success would have: \n  success: {success}\n  \
         refused: {refused}"
    );

    // And the co-op half: somebody else's refusal still names them, which is
    // what the possessive prefix is for and why every phrase is a gerund.
    let theirs = debug::event_line(
        &world,
        Some(PlayerId(1)),
        &Event::CommandRejected {
            player: PlayerId(0),
            command: PlayerCommand::MoveTo {
                target: TilePos::new(12, 5),
            },
            reason: RejectReason::OutOfBounds,
        },
    );
    assert!(
        theirs.starts_with("ada's moving to (12, 5) was refused"),
        "a teammate's refusal is theirs and reads as English: {theirs}"
    );
}
