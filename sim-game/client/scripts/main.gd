extends Node2D
## THE WHOLE CLIENT A PLAYER SEES, for now: a host address, a name, and the world you are in.
##
## Decision 1's test is "a friend with no terminal can download a build, enter a host address and
## play", so the address field is not a debug convenience -- it is the front door, and it is here on
## the first screen rather than behind a menu.
##
## WHAT IS DRAWN IS THE WORLD THE SIM STEPPED, not a guess at it. A tick bundle carries inputs, not
## state; turning inputs into a newer world is `sim::step`, which this client now runs through
## `AssaySimHost`. Nothing here predicts, interpolates or recomputes: a position on screen is a
## position the sim is actually on, and if the sim has not reached a tick yet then neither has the
## picture. Until the first `Welcome` there is nothing to draw at all.

## WHERE THINGS GO lives in `AssayHud` with the rest of the view's rules, so the one that matters can
## be tested: the HUD column sits BESIDE the map (Maren's ruling, ASSA-7), its width coming out of the
## map's own width term rather than covering it.
##
## AND THE COLUMN IS WHERE A PERSON ACTS (ASSA-37). Until now only the scripted probe could mine,
## craft, equip or plant; a human could walk, look and read. Every button below submits the SAME
## `PlayerCommand` `sim-cli` sends, built by `AssayActions` -- the one file that spells a command, so
## that the probe and the buttons cannot drift apart. No button predicts, none refuses, and none
## decides whether what it asked for was legal: `sim::step` validates on every peer, and the answer
## comes back in the event log a tick later.
const MARGIN := AssayHud.MARGIN
const VIEW := AssayHud.VIEW
const PANEL := AssayHud.PANEL
## Event lines kept on screen. A tick can produce several and they arrive ten times a second, so this
## is the last few seconds of the world, not a history.
const LOG_LINES := 14

var _client: AssayNetClient
## THE RELAY THIS CLIENT STARTED, or null when we joined somebody else's (ASSA-106). Held rather than
## local because it outlives the press: the address arrives frames later, and the process has to be
## stopped when the window closes.
var _solo: AssaySoloRelay = null
var _sim := AssaySimHost.new()
## THE FIRST DOOR. Held as a field so a test can find it without counting children -- the row's order
## is the thing under test, so a test that located the button BY its position in the row could never
## fail.
var _solo_button := Button.new()
var _host := LineEdit.new()
var _name := LineEdit.new()
## THE THREE CONTROLS NOTHING READS ONCE YOU ARE IN A WORLD, plus the two labels that name two of
## them: `Play solo`, `host`, `name` (ASSA-175). Held as ONE container so the hide is one statement
## and cannot leave a label standing over a field that is gone -- which is ASSA-127's defect
## recreated by this fix. `Join` is deliberately NOT in here; see `_refresh_join_band`.
var _join_band := HBoxContainer.new()
## **THE DOOR THAT STAYS IN EVERY STAGE A DOOR MEANS ANYTHING, WHICH IS NOT ALL OF THEM** (ASSA-237,
## Maren's Gap 2: *"A `Join` button sits in the top-left corner of a world you are already in."*).
##
## ASSA-175 left this outside `_join_band` on the reasoning that it is "the one control in the row
## that can still do something". **That is true in three stages and false in the fourth**, and the
## fourth is the one the board looks at: `_join_address` returns at its first line unless the stage is
## IDLE or DEAD, so a press at JOINED can only ever produce *"you are already in a world — restart the
## client to change host"*. A control whose single outcome is a refusal is exactly the class ASSA-175
## removed; it removed the three beside it and left this one.
##
## **THE RECONNECT HALF — the whole point of that item — IS UNTOUCHED**, because the stages differ:
## the band and this button are both gone at JOINED and both back at DEAD, which is where a dropped
## player reaches for them. See `_refresh_join_band`, which now carries one predicate for both.
var _join_button := Button.new()
## **THE JOIN SCREEN AS ONE COMPOSITION, AND THE SAME CONTROLS IN A WORLD** (ASSA-231, Maren's Gap 5
## in doc `assay-ui-direction`: *"one screen, one primary action, the empty column not shown at all
## before a world exists"*).
##
## Before there is a world the three join controls do not live in the top-left toolbar at all: they
## stand in the middle of the biggest surface in the game, under the game's name and the one
## sentence that names both doors, with `Play solo` alone on its line above the host path. The
## moment a world exists they move back into `_row`, where `Join` is the reconnect affordance a
## dropped player reaches for (ASSA-175/ASSA-177) and nothing is drawn over the world.
##
## **ONE SET OF NODES WITH TWO HOMES, NOT TWO SETS.** Two `Play solo` buttons would be two things to
## keep in step and two things to press, and the accent that gives this screen its rank is exactly
## one control deep (ASSA-224). `_place_join_controls` is the whole of the move.
var _row := HBoxContainer.new()
var _front_door := VBoxContainer.new()
var _door_title := Label.new()
## The two travelling cells: the primary on its own line, and the host path on the next one. They
## are what `_refresh_join_band` hides in a world, wherever they are currently parented.
var _solo_cell := HBoxContainer.new()
var _cred_cell := HBoxContainer.new()
var _door_primary := HBoxContainer.new()
var _door_secondary := HBoxContainer.new()
## What the client is SAYING, under the controls it is saying it about. In a world these two labels
## move into `_says_toast` over the world's bottom-left corner (ASSA-239 -- they used to go back to
## (24, 54) and (24, 74), in a header strip that no longer exists); on the join screen a refusal
## 300 px from the button that earned it is the same defect ASSA-127 fixed for the invitation.
var _door_says := VBoxContainer.new()
## **WHERE THE SAME TWO LABELS LIVE ONCE THERE IS A WORLD** (ASSA-239). A panel over the map's
## bottom-left rather than a line in a strip, because Maren's Gap 2 ruling gives the strip's 96 px to
## the world and leaves nothing in its place: *"a thinner status line is a thinner version of this
## defect."*
##
## **A TOAST IS NOT FURNITURE.** It is drawn only while it has something to say, so the resting state
## of a played screen is world and column and nothing else -- which is the Factorio half of Maren's
## §1 that this client could not have while the status line owned a permanent band.
##
## `MOUSE_FILTER_IGNORE`, like `_map_note` and for the same reason: it floats over a map that is
## clicked through `_unhandled_input`, and a panel that answered the mouse would eat clicks on the
## world in the one corner a player walks to.
var _says_toast := PanelContainer.new()
var _says_toast_box := VBoxContainer.new()
## THE PAINTED COLUMN SURFACE, held so the column can leave the screen before a world exists. Not
## its sections one at a time: the column is one object to a player and `COLUMN_SURFACE` is the
## ancestor every part of it hangs from, so a section added later is hidden by this with no second
## list to remember.
var _column: Panel = null
## **THE DARK SURFACE UNDER THE JOIN COMPOSITION** (ASSA-231). `_world` paints `MAP_BG` over
## `world_rect` and nowhere else, so with the column hidden the join screen was a map-sized dark panel
## with a 320 px strip of bare window beside it. This paints the same token over `join_rect`, under
## `_world` in child order, so before a world the screen is ONE surface; the moment a world exists it
## is hidden and the map is framed exactly as it always was. `MAP_BG` is the existing token -- no new
## colour enters the client for this.
var _door_backdrop := ColorRect.new()
var _status := Label.new()
## **WHAT THE STATUS LINE WOULD SAY IF THE LINK WERE FINE**: the last sentence `_say` was given, kept
## because the quiet warning is TEMPORARY and something has to be underneath it when it goes
## (ASSA-191). Not a saved-and-restored copy of the label -- the label is DERIVED from this plus the
## count, which is the difference between a rule and a pair of assignments that have to agree.
var _base_line := ""
var _base_level: int = AssayHud.Say.IDLE
## The world's tick when `_base_line` was said, or -1 if there was no world then. See
## `_age_the_saying`, which is what stops a healthy sentence becoming a permanent one.
var _said_at_tick := -1
## How long a `Say.JOINED` sentence stays on screen, in the WORLD's ticks (ASSA-239). 2 s at the
## relay's default 10 ticks/s. See `_age_the_saying` for why it is not seconds.
const SAYING_DWELL_TICKS := 20
## Whole seconds the host has been quiet, 0 when it is not. Set only by `AssayNetClient.link_quiet`.
var _quiet_seconds := 0
## **THE DEVELOPER'S READOUT, AND IT IS NOT A PLAYER'S** (ASSA-237, Maren's Gap 2: *"Debug output is
## the second-loudest text on the player's screen ... A **hex state hash**, on the screen we send the
## board. Fixed looks like: none of it in the player's view. Keep every word of it behind a developer
## toggle (it is genuinely useful to us)"*).
##
## Every word is kept and nothing is reworded -- the seed, the tile count, the species count, the
## player count, the tick, the state hash, the bundle and hash counts and the frame rate are still
## written on every refresh. What changed is who it is drawn for. (The hash is not quoted here even as
## an example: `test_shipped_scripts.gd` greps these files for a pinned one, correctly, because a
## golden hash copied into prose is a golden hash that goes stale the next time a rule moves.)
## `_refresh`'s own comment handed this call here by name: *"ASSA-198 decides where a player-facing one
## belongs."*
##
## **THE ONE SENTENCE THAT WAS NEVER DEBUG WENT WITH IT, AND HAD TO BE TAKEN BACK OUT** -- see
## `_refresh`. This label also printed *"joined at tick N, but no world is being simulated"*, which is
## a failure a player must see, and hiding the label would have hidden it. It is on the status line
## now, which is the surface this client already uses for the state it is in.
var _detail := Label.new()
## WHETHER THE READOUT ABOVE IS BEING DRAWN. INITIALISED TO THE WRONG ANSWER ON PURPOSE, which is this
## file's standing rule for a default a test has to be able to catch (`_log_shown`, `_make_shown`):
## `_build_ui` calls `_show_dev_readout(false)`, and starting this at `false` would make "the debug
## readout is hidden on first open" true before any code ran.
var _dev_shown := true
## THE PACK, AS ROWS YOU CAN ACT ON (ASSA-37). A container and not a Label any more: a stack's row
## carries the verbs that stack affords, which is what turns "3 × ore" from a readout into the start
## of the craft chain. The words are still `AssayHud.stack_line`'s, so the list reads the same.
var _carrying := VBoxContainer.new()
## WHAT YOU CAN DO WHERE YOU ARE: Mine, Stop, Assay, the tile every placement lands on, and the
## verbs of whatever building is on it.
var _actions := VBoxContainer.new()
var _cursor := Label.new()
## THE EVENT LOG, ONE CONTROL PER LINE (ASSA-117). It was a single Label holding `"\n".join(_events)`
## and A SINGLE LABEL IS A SINGLE COLOUR, so "the newest line is the most legible" was not something
## that control could be made to do at all. One Label per line is the cheapest structure that can
## carry a per-line colour, and it is also the one a test can read a line's colour back out of.
var _log := VBoxContainer.new()
## WHAT THE LOG LAST DREW, so fourteen Labels are not rebuilt ten times a second. Same signature rule
## as the pack and the bench. NOT "" -- an empty log has an empty shape, and starting this at "" made
## the first refresh a no-op, which is the bug that left the bench blank until something was mined.
var _log_showing := "\nnothing yet\n"
## WHAT HAS STOPPED, AND IT IS NOT IN THE LOG (ASSA-117 box 2, Maren's ASSA-89/94 ruling: a refusal
## is a MOMENT, a stall is a CONDITION). The sim answers this standing -- `sim::debug::halt_lines`
## through `AssaySimHost.halt_lines()` -- and this block is PINNED OUTSIDE THE SCROLL BOX, which is
## the only placement that makes "a later line cannot push it off" true structurally rather than by
## my remembering it. Empty is empty: no heading, no reassuring line, zero pixels.
## **AND SINCE ASSA-247 THIS BLOCK IS THE CONDITION ONLY, NOT THE LIST** (Maren's ruling, 17:22 UTC
## 2026-10-06, amending her own ASSA-89/94). Her words: *"the CONDITION stays always-on; the LIST does
## not. A stall is a condition, not a moment was about never losing the fact -- it never said every
## stalled machine must sit above the fold forever."*
##
## The reason is that `_halt` was the one UNBOUNDED thing in the pinned chrome: one line per stalled
## machine, growing with the factory, and it is where 161 px of the worst-case clip came from
## (measured on ASSA-247: the clip is 477 px at its worst against 638 at rest). So what is pinned
## here is the sim's own count -- `halt_summary`, "N of M buildings stopped" -- and the machines
## themselves are in the `bench` tab, where machines live. Nothing a player must not miss is lost:
## the fact that something has stopped, and how much of the factory it is, cannot be scrolled away.
var _halt := VBoxContainer.new()
var _halt_box: PanelContainer = null
## The stopped lines alone, without the heading. Rebuilt with the block -- and they live in
## `_halt_detail` now, so that "the lines of this block" is still one container and still the sim's
## words in the sim's order.
var _halt_lines: VBoxContainer = null
## WHERE THE STALLED MACHINES ARE LISTED: the `bench` tab's body, under the designs. Built and
## emptied by `_rebuild_halt` beside the pinned count, from the same call and the same lines, so the
## count and the list can never disagree about what has stopped.
var _halt_detail := VBoxContainer.new()
var _halt_showing := "\nnothing yet\n"
## WHAT IS RUNNING, BESIDE WHAT HAS STOPPED (ASSA-133, Maren's ruling 1; the list is ASSA-95's).
## `AssaySimHost.activity_lines()` -> `sim::debug::activity_lines`: mining, assaying and the running
## craft, one line each, in `step`'s own system order, worded entirely by the sim.
##
## **ANNOUNCING DOES NOT SCROLL.** The craft countdown used to be the head of the crafting menu,
## inside the scroll box. Maren's own reason for putting it there was that the menu was the TOP
## section, so that line was least likely to be carried off the bottom -- a probabilistic argument
## about position in a scroll box, which the chrome answers absolutely. `_halt_box` was already here
## for exactly that reason and is the precedent she overruled herself with.
##
## NO SCROLL IN HERE, EVER, AND NO CAP. A cap would hide a running activity, which is the defect the
## plural list exists to fix: a player mines THROUGH their own assay, so three lines is a real state
## and not an overflow. A fourth activity is a fourth line or it is not in this block.
var _running := VBoxContainer.new()
var _running_box: PanelContainer = null
## The running lines alone, without the heading. Rebuilt with the block.
var _running_lines: VBoxContainer = null
var _running_showing := "\nnothing yet\n"
## THE EVENT LOG'S CONTROL AND ITS STATE (ASSA-89). The log is the surface the team built the loop
## on and the board's one literal complaint about the window ("logs are hard on the eyes"), so it
## starts hidden and one named control brings it back. `_log_heading` is held because a hidden
## section under a visible heading is a labelled empty gap; see `_show_log`.
var _log_toggle := Button.new()
var _log_heading: Label = null
## THE SURFACE THE LOG IS NOW ON, AND IT IS NOT IN THE HUD COLUMN (ASSA-147, Maren's ruling).
##
## `_log_region` is the map's own rectangle with nothing in it; `_log_box` is the panel inside it that
## holds the heading and the lines. Both are held because `_show_log` raises and lowers the box and
## because `tools/window_shot.gd` measures it -- the surface is what a player sees, so the surface is
## what a verdict has to be read off.
var _log_region: VBoxContainer = null
var _log_box: PanelContainer = null
## HOW TALL THE LOG'S PANEL MAY BE, in the map's own pixels, or -1.0 when nothing bounds it
## (ASSA-156, Maren's measurement). `AssayScene.player_ceiling`: the panel is anchored to the map's
## top and the camera puts your body in the map's centre, so a panel sized only by its content owns
## the one tile the camera guarantees you are standing on. Read once, here, because it is a fact
## about the LAYOUT -- a bound that changed as you walked would be a panel that resized while you
## read it, which is worse than a short one.
var _log_room := -1.0
## HOW FAR ABOVE ROW 0 THE CAMERA MAY GO, in map pixels, so the north clamp cannot slide your body
## under that panel (ASSA-184, Maren's measurement: 6 of 64 rows hid the player completely and
## 12.5% of a world's deposits are in them). Read from the same manifest and the same rect as
## `_log_room`, in the same place and for the same reason -- these two numbers are one decision, and
## a camera bound computed somewhere else is a camera bound that drifts from the panel it exists to
## clear. 0.0 means "never leave the world", which is the camera this client had before.
var _north_room := 0.0
## THE BOX THAT SCROLLS THE COLUMN. Held since ASSA-117 and still held, for `window_shot.gd`'s clip
## report and for `test_main_screen.gd`'s invariant that the log is NOT inside it. What it is no
## longer held for is scrolling to the log: that whole mechanism is gone with ASSA-147, because the
## log is not in this box any more and there is nothing to scroll to.
var _scroll: ScrollContainer = null
## **THE TABBED SYSTEMS PANEL** (ASSA-247): the board's own shape, one system at a time. Held so the
## refreshes can ask which tab is open and so a test can add a fifth entry and assert that doing so
## moved nothing. `_scroll` is this strip's content box, which is why there is no second scroll box
## in the column any more.
var _tabs: AssayTabStrip = null
## INITIALISED TO THE WRONG ANSWER ON PURPOSE. `_build_ui` calls `_show_log(false)`, and starting
## this at `false` would make "the log is hidden on first open" true before anything ran -- a test
## that passes by construction, which is the failure I keep writing down. At `true` the default-state
## assertion can only pass if the call actually happened.
var _log_shown := true
## `_crafting` WAS HERE AND IS GONE (ASSA-133 ruling 1). The running-craft countdown was a Label held
## at the head of the crafting menu, a sibling of the menu's toggle so that collapsing the menu could
## not take it away (ASSA-49, then ASSA-88). It is now one line in the chrome's `_running` block,
## which is outside the scroll box entirely -- so "a later line cannot push it off" is structural
## rather than probabilistic, and the sentence it printed is still the sim's `crafting_readout`,
## reached through `activity_lines` beside the mining and assaying lines that never had a surface.
##
## There is deliberately no Label to put back: a second node holding that sentence would print the
## craft countdown twice, once in each block.
## THE CRAFTING MENU (ASSA-88): the home of every make-verb. One row per recipe and part the sim says
## this player could make from what they carry, in the sim's order, each row the sim's own sentence.
var _make := VBoxContainer.new()
var _make_toggle := Button.new()
## THE PARTS YOU HAVE CHOSEN FOR THE NEXT `Assemble`, AND ITS TWO BUTTONS (ASSA-107, Maren's ASSA-88
## ruling). They used to live in the `do` section, two sections away from the rows they were chosen
## on; the discriminator she gave is ACTIVITY, not widget -- making parts and assembling them are one
## activity in two stages, so the second stage belongs under the first. The menu now reads top to
## bottom as one thing: what is running, what you are assembling, what you can make.
##
## OUTSIDE THE COLLAPSIBLE ROWS, for the reason the running craft is: a half-chosen assembly is a
## CONDITION, not a moment. Fold the rows away with three parts in hand and a container inside them
## would take `Assemble` with it -- so this is a sibling of `_make`, not a child. Maren ruled that
## clause for the craft line and left this one to me; it is the same argument and she can overrule it.
var _assembling := VBoxContainer.new()
## INITIALISED TO THE WRONG ANSWER, same as `_log_shown` and for the same reason: `_build_ui` calls
## `_show_make(true)`, and starting this at `true` would make "the menu is open on first join" pass
## before any code ran. The board asked for a crafting menu, so unlike the log this one starts OPEN.
var _make_shown := false
## THE PART MENU'S HOME: one headline label plus one body label per design, rebuilt only when the
## list changes. Not a Label like the others, because the verdict is a WORD IN ITS OWN COLOUR above
## numbers in another (Maren's ruling) and one Label can only be one colour.
var _bench := VBoxContainer.new()
## THE SPECIES PANEL: the map's legend (ASSA-73, Maren's ruling). Every species the sim sends, with
## the same glyph and tint the map draws on its deposits, so a player who reads "lights from cold"
## next to a letter can go and find that letter on the map. The window player had none of the
## terminal's reference surfaces; this is the one that turns the map into a search tool.
var _species := VBoxContainer.new()
var _species_showing := UNBUILT
## THE MINERALOGY TAB'S BODY: Limpet's `AssayMineralogy` (ASSA-254), which is the sim's answer plus
## `go here` with `_species` underneath as the evidence for it. Built by that file, composed here --
## the strip's one-entry contract is what let his leg land and be gated green before this strip
## existed, and this variable is the whole of the cost of plugging it in.
var _mineralogy := AssayMineralogy.new()
## What each section was last built from, so ten refreshes a second do not rebuild nodes that have
## not changed. The sim's own values are the signature: if they are identical, so is the panel. This
## matters more now than it did -- rebuilding a row ten times a second would destroy a button under
## the pointer -- and A BUTTON NEVER CAPTURES THE STATE IT ACTS ON. It reads the target tile and the
## sim when it is PRESSED, so choosing a tile after seeing the button works and costs no rebuild.
## NOT "" -- AN EMPTY PACK AND AN EMPTY BENCH HAVE AN EMPTY SHAPE, so starting these at "" made the
## first refresh a no-op and left the sections blank until something was mined. The suite caught it
## because `test_main_screen.gd` asserts the empty bench says which kind of empty it is; without that
## line the shipped client would have had two headings over nothing on its first screen.
## HOW BIG A PACK-ROW ICON IS. 32px because that is the size Cove's sheets were drawn to survive: a
## 64px frame at 1x, halved, is still counting rocks, where the 9px map tile is speckle (ASSA-46).
## The pack row's sentence, by name. Everything that re-texts or reads a row finds it with this rather
## than by child index, because the row's shape now depends on whether the item has art.
const STACK_LINE := "StackLine"

## NO NAME FOR AN EVENT LINE OR A STOPPED LINE, AND I TRIED (ASSA-117). `STACK_LINE` works because
## there is ONE of it per row. Fourteen siblings all called `LogLine` is a different thing, and the
## engine's answer is worse than uniquifying: I asked it, and four Labels named `LogLine` come back
## as `["LogLine", "@Label@2", "@Label@3", "@Label@4"]` -- the name is DISCARDED for every sibling
## after the first. So `find_children("LogLine", ...)` returns exactly 1 of 14, and my own test read
## that as "2 lines went in and 1 came out" and called it a layout defect. A name that cannot
## survive a second sibling is worse than no name: it answers confidently and wrongly.
##
## Each block therefore holds nothing but its lines, in order, and they are selected by CLASS. That
## is also the honest statement of the property -- "the lines of this block, in order" -- which is
## why `_halt`'s heading sits beside `_halt_lines` rather than above its children.

## A bench row's two written parts. Named for the same reason, and because `_write_design` used to
## find them by child index 0 and 1.
const BENCH_VERDICT := "BenchVerdict"
const BENCH_BODY := "BenchBody"

## The crafting menu row's sentence, by name for the same reason `STACK_LINE` is: the fast path
## re-texts it ten times a second because it carries a count, and finding it by child index would
## break the first time a row grows a second line -- which it already does, for a dead end.
const MAKE_LINE := "MakeLine"

## The species row's name-and-state label, by name for the same reason `STACK_LINE` is: tests and
## probes find it without counting children, and the row's shape is free to change.
const SPECIES_LINE := "SpeciesLine"

## The six readings on a species row, named separately because it is the ONE part of the row that
## must be judged on the sim's own spelling -- a band carries a hyphen, an exact reading does not.
## My first test for that read the whole row and tripped over the `hand-minable` TAG's hyphen, which
## is the same mistake as measuring a shadow with a statistic the outline also satisfies.
const SPECIES_READINGS := "SpeciesReadings"
## The `Panel` behind the HUD column (ASSA-152). Named so a test and a probe can find it without
## counting children -- the thing it is named for is a SURFACE, and the whole defect was that the
## surface could not be found because it did not exist.
const COLUMN_SURFACE := "ColumnSurface"
## The `MarginContainer` that gives the column's content the inset the theme's panel stylebox
## already declares (ASSA-142). Named so a test can ask what its margins are without counting
## children -- the property being tested is where the number came FROM.
const COLUMN_PAD := "ColumnPad"

## The tabbed systems panel (ASSA-247). Named so a test, a probe and `window_shot.gd` can find the
## strip without counting children, and because the thing it is named for is the board's own
## structure: one panel, the systems selectable at the top.
const TABS := "SystemsTabs"

## The map glyph's disc in a species row. Big enough for a 12px letter to sit in, which is above the
## 10px floor `glyph_size` refuses to draw under.
const GLYPH_BOX_PX := 18.0

const ICON_PX := 32.0

## THE ICON'S OWN BOX, AND WHY IT HAS A HEIGHT (ASSA-65, Cove's measurement on ASSA-57).
##
## `custom_minimum_size` is a FLOOR, not a size. A `TextureRect` in an `HBoxContainer` fills the row
## vertically by default, so the rect was 32 x WHATEVER THE ROW WAS, and
## `STRETCH_KEEP_ASPECT_CENTERED` scales by `min(32/fw, h/fh)`. Cove asked the engine what that came
## to and it was **15/32** for an ore item -- 30 of 64 source columns surviving, spaced 2 and 3 apart,
## which is uneven sampling of pixel art rather than a scale. And because a row is as tall as its
## buttons, THE SAME ITEM CHANGED SIZE WHEN ITS VERBS CHANGED: a number from the UI deciding how art
## is resampled.
##
## 48 is the height that makes the ratios exact, and it is arithmetic rather than taste: the ore sheet
## is 64x96, so `min(32/64, 48/96)` is **1/2** on the nose, and a 128x102 part sheet is **1/4**. With
## `SIZE_SHRINK_CENTER` the rect is this box and nothing else, so neither scale can be moved by a verb.
const ICON_BOX_PX := Vector2(ICON_PX, 48.0)

const UNBUILT := "nothing built yet"
var _bench_showing := UNBUILT
var _pack_showing := UNBUILT
var _make_showing := UNBUILT
var _assembling_showing := UNBUILT
var _actions_showing := UNBUILT
## WHETHER THE COLUMN'S EMPTY SENTENCES WERE WRITTEN FOR A WORLD (ASSA-186). The five lines above
## cache a shape; this caches the one thing a shape cannot carry, because an empty section looks the
## same either side of a join. **FALSE IS THE TRUTH ON THE JOIN SCREEN, not a sentinel**: `_build_ui`
## draws these sections before anything has been joined, so a first `_refresh` with no world must see
## no transition and leave them alone. See `_resay_the_empty_sections`.
var _world_shown := false
## THE TILE EVERY PLACEMENT LANDS ON. `_targeted` false means "where you stand", which is not a
## placeholder: your own tile is the one tile every player has, and planting beside yourself is the
## common case. Right-click chooses another; left-click still walks, because walking is the thing a
## player does most.
var _target := Vector2i.ZERO
var _targeted := false
## THE PARTS CHOSEN FOR THE NEXT `Assemble`, as the SIM'S OWN STACKS so a row can be named on screen
## and sent as an item without this client inventing either. THE FIRST ONE IS THE FRAME, which is
## `sim-cli`'s rule (`assemble <frame> <part>...`) kept rather than invented.
var _building: Array = []
## The tile size the map is drawn at, so a click can be turned back into a tile. 0 means there is no
## world yet and a click means nothing.
##
## SET BY `_refresh`, NOT BY `_draw`, and that was a real bug rather than tidying. A click turning
## into a tile used to depend on a frame having already been painted: the first click after a Welcome
## could land before the first `_draw` and be silently dropped, and HEADLESS THERE IS NO `_draw` AT
## ALL -- so no test could ever press the map. It is `AssayHud.map_cell`'s pure answer either way.
var _cell := 0.0
## Hash reports actually put on the wire. See `_on_tick_bundle`.
var _hashes_sent := 0

## THE SCENE: THE WORLD AT 32 PX A TILE, with a camera on you (ASSA-119, Maren's ruling). The
## close-up is the MAIN view and the whole-world schematic `_draw` paints is the second one -- they
## occupy the same rectangle (`AssayHud.world_rect`) and exactly one is visible.
##
## WHY BOTH SURVIVE. The schematic is how you cross 96x64, it carries every other player, and its
## species discs and glyphs are the only colour-blindness-MEASURED read on this screen (Decision #36,
## worst observer dE 18.3, glyph contrast 4.52). Maren's constraint on the second view is a property
## and not a mechanism: you can always find a deposit you have not visited, and you can always see
## which player is you. A toggle over the view's own corner is what I chose to meet it, keyed like the
## other two toggles on this screen -- a key alone is not discoverable and a control that names its
## key is the pattern ASSA-88/89 already settled here.
var _world := AssayWorldLayer.new()
var _view_toggle := Button.new()
var _close_up := true

## **THE SHAPE KEY OVER THE MAP** (ASSA-206). Nine marks on this view and one of them named; our own
## QA misread it three times in six minutes. `AssayMapKey` draws the rows and every row comes out of
## `AssayHud.MAP_MARKS`, the table `_draw` paints from -- see that script and that constant.
##
## HIDDEN ON FIRST OPEN, WITH A CONTROL THAT NAMES ITS KEY, which is the log's bargain (ASSA-89) and
## is a choice Maren left to the builder. **MEASURED, NOT ESTIMATED** (`AssayMapKey.wants` at the
## theme's own 13px font, plus the panel's stylebox margins): the content is 286x280 px of the map's
## 912x672, which at 9 px a tile is 31.8 x 31.1 tiles -- **about 16% of a 96x64 world** -- on the one
## surface whose job is showing you a deposit you have not walked to. A sixth of the world behind a
## key you have already read is a cost a player should be able to put down. The half that makes that
## honest is the button -- `show the map key (K)` beside `whole world (V)`, inside the map's own
## corner, the one surface a stranger pressing V is already looking at. Default-on is one line
## (`_show_map_key(true)` at build) if Maren rules it on the 08/09 shot pair.
##
## ONLY ON THE SCHEMATIC. Every mark it names is painted by `_draw`, which returns on `_close_up`, so
## in the close-up the key would be a legend for marks nobody can see -- the labelled-empty-gap defect
## ASSA-134 and ASSA-186 both turned on. The toggle goes with it for ASSA-175's reason: a control that
## cannot do anything reads as available.
var _map_key := AssayMapKey.new()
var _map_key_box := PanelContainer.new()
var _map_key_toggle := Button.new()
var _map_key_shown := false

## WHAT THE MAP SAYS WHILE THERE IS NO WORLD ON IT (Maren's ruling 1, ASSA-127). Built in
## `_build_ui`, worded by `AssayHud.empty_map_line`, shown exactly when `_world.view` is empty.
##
## A LABEL AND NOT A `draw_string` IN `world_layer.gd`, on purpose. That file's own docstring says
## everything checkable is arithmetic in `AssayScene` and what is left there is a blit loop with no
## judgement in it to get wrong -- a string drawn in `_draw` would put the one sentence a stranger
## reads into the one file no test can question. A `Label` placed at absolute coordinates can be
## asked for its text, its rect and its alignment with no layout pass at all, which is what lets
## `test_main_screen.gd` hold this to the map's rectangle headless.
var _map_note: Label = null

## WHERE EVERY PLAYER WAS ONE TICK AGO, AND WHICH WAY THAT POINTED.
##
## MAREN'S MOTION RULING (ASSA-119, 18:07 UTC) IS WHY THIS EXISTS, and it is the sharpest statement
## of principle 1 anyone here has written for a renderer: **a renderer MAY interpolate the DRAWN
## position; it MAY NOT interpolate state.** At 9 px a tile a one-tile step was invisible; at 32 px it
## is a 32 px jump ten times a second. So the sprite tweens between the PREVIOUS tick's tile and the
## CURRENT tick's tile -- lagging one tick, inventing nothing, and always arriving at a position the
## sim actually produced. Never toward where a `target` suggests they are going: that is prediction,
## it is a second copy of the movement rule living outside `sim`, and it is wrong the moment they
## stop, change target or get refused.
##
## SO THESE ARE A HISTORY, NOT A GUESS. Both are positions the sim produced, and nothing here
## extrapolates past them.
##
## THEY ARE THE SEGMENT BEING DRAWN, WHICH IS NOT ALWAYS THE NEWEST ONE (ASSA-148). It used to be:
## `_seen` was whatever the last bundle said and `_was` the bundle before it. But bundles arrive in
## pairs, and a pair applied between two drawn frames moved BOTH of these on and left the segment
## between them undrawn -- a whole-tile teleport, 11 times in the demo walk's 25 steps. So produced
## positions now wait in `_pending` and these two advance on the PLAYOUT clock
## (`AssayScene.playout`), one segment at a time, in the order the sim produced them.
var _was := {}
var _seen := {}

## **THE CLICK YOU HAVE NOT HAD AN ANSWER TO YET** (ASSA-215, Maren's ruling): `{}`, or
## `{"tile": Vector2i, "confirmed": bool}` for the tile this client last asked to walk to.
##
## IT IS AN INPUT, NOT STATE, and that is the whole reason it may exist beside `_was`/`_seen` above
## without breaking the ruling they are written under. Those two are positions the SIM produced and
## nothing may extrapolate past them; this is a tile the PLAYER named, echoed back at them while the
## sim has not answered. The drawn body never reads it -- `AssayScene.placements` cannot see it --
## so no body moves a pixel sooner than the sim says it does.
##
## EVERY TRANSITION IS `AssayScene.walk_echo`'S and none of them is here: set on an accepted submit,
## cleared on arrival, on a refusal, and on the sim dropping a target it once confirmed. That is a
## state machine with four ways out and this file can only be tested through a window, so it lives
## where `tests/test_scene_view.gd` can hold each clause on its own.
var _walk_echo: Dictionary = {}

## WHICH PLAYER FACTS THE BINDING LAST FAILED TO SEND, so the refusal is said ONCE and not at the
## frame rate (ASSA-196). Empty is the healthy state. A member initializer, not set in `_ready`:
## `_players()` is reachable from an input handler before any refresh has run.
var _player_facts_missing := PackedStringArray()
var _facing := {}
## POSITIONS THE SIM HAS PRODUCED THAT THE SCREEN HAS NOT FINISHED DRAWING, oldest first, and when
## the current segment started playing.
##
## CAPPED, AND THE CAP DEGRADES THE RIGHT WAY. A client that fell far behind would otherwise hold an
## unbounded queue and draw a body minutes in the past. Over the cap the OLDEST unplayed position is
## dropped, which makes the next segment span two tiles instead of one: the body then moves at double
## speed for a tenth of a second, CONTINUOUSLY, and never teleports. That is the worst thing this fix
## can do, and it is strictly better than the best thing the old code did on a real relay.
##
## THREE IS MEASURED, NOT PICKED. A real relay's worst gap is 0.254 s = 2.5 steps, so two would be
## trimming during normal play; the queue only ever reaches three when production genuinely outruns
## the clock, which on this machine means a test harness feeding ticks as fast as its loop runs.
##
## EACH ENTRY CARRIES ITS OWN ARRIVAL TIME (`{"at": seconds, "where": id -> tile}`) and that time is
## load-bearing, not diagnostics: a segment may not start before its own data existed, which is what
## makes resuming after a dry queue continuous (see `AssayScene.playout`). It rides INSIDE the entry
## because I tried it as a second parallel array first and then mutated it -- dropping the pop of the
## times while keeping the pop of the positions -- and all 229 client tests stayed green. A caller's
## bookkeeping is invisible to a test of the arithmetic, so the way to close it was to make the two
## impossible to separate rather than to write a check nobody would run.
## **HOW MANY PRODUCED POSITIONS THE SCREEN KEEPS AROUND THE ONE IT IS DRAWING** (ASSA-197). The
## clock runs `AssayScene.PLAYOUT_DELAY` ticks behind the newest, so the buffer must hold at least
## that many plus the longest burst; eight is 800 ms of history, which covers the 386 ms worst gap
## measured on this Mac with room over. Over the cap the OLDEST is dropped and the clock interpolates
## ACROSS the hole -- two tick-times for a two-tick segment, continuous, never a sprint.
const PLAYOUT_QUEUE := 8
var _pending: Array[Dictionary] = []
## WHERE THE CLOCK IS, as a fractional SIM TICK. **NEGATIVE UNTIL THE BUFFER HAS FILLED**, which is
## `AssayScene.playout_at`'s "not started" state and not a tick number -- it was 0.0, and 0.0 is the
## first tick of a fresh world, so the clock re-initialised itself on every frame of the first second
## of every session.
var _play_tick := AssayScene.PLAYOUT_UNSTARTED
## When the clock was last advanced, so a frame's own elapsed time drives it.
var _played_at := 0.0
## Whether the buffer ran dry on the last advance: the body is holding on the newest position the sim
## produced, which is a stalled host and not a renderer decision.
var _starved := false
## THE PLAYOUT CLOCK'S INTEGRAL TERM, and this client's only memory of it (see
## `AssayScene.PLAYOUT_TRIM`). 1.0 means the measured tick length is being taken at face value; 0.86
## means the clock has learnt that it is 14% short and is playing out that much slower than the
## measurement alone would. It lives here rather than in the scene because `playout_at` is pure.
var _play_trim := AssayScene.PLAYOUT_TRIM_NONE
## WHETHER DRAWN FRAMES ARE MOVING THE PLAYOUT CLOCK. Set the first time `_advance_playout` is
## called with a frame's delta; while it is false the clock is advanced by arrivals instead, which
## is the only thing a headless harness has. See `_remember_positions`.
var _frames_drive_playout := false
## The buffer's depth in ticks on the last advance, for the probes and the debug line: the quantity
## the clock is actually controlling, which until now could only be inferred from `_pending.size()`.
var _play_depth := 0.0
## **HOW MANY FRAMES THE QUEUE CAP HAS DRAGGED THE BODY FORWARD** (ASSA-212, Wren's gate (c)). The
## mirror of `_starved`: a clock running slow falls behind until `PLAYOUT_QUEUE` evicts history it has
## not played, and the clamp inside `playout_at` then pulls the drawn body to the tail. It is a jump a
## player sees, out of a loop that never starved, and no probe of a real window could report it --
## only the synthetic drive in `tests/test_scene_view.gd` counted it. A count rather than a flag
## because one dragged frame in a session is a different story from forty.
var _play_dragged := 0
## HOW MANY TIMES THE CLOCK HAS BEEN ADVANCED, for the probes alone.
##
## IT IS HERE BECAUSE A PROBE CANNOT OTHERWISE TELL HOW MANY INTERVALS ITS TWO SAMPLES SPAN. The
## clock advances on a drawn frame AND on a bundle landing (see `_remember_positions`), and the
## second kind moves `_played_at` without publishing a new drawn rectangle -- so a probe pairing one
## frame's worth of movement with `_played_at`'s last step divides by too little time and reports a
## sprint the screen never drew. `motion_speed_probe.gd` names the frames where that happened
## instead of leaving them in the distribution as if they were speed.
var _play_advances := 0
## The last few bundle ARRIVAL times, for the measured tick rate. See `AssayScene.playout_step`.
var _tick_times: Array[float] = []
## The sim tick each of those arrivals carried, so the rate is seconds per TICK and not per bundle.
var _tick_numbers: Array[int] = []
## When the newest tick landed, and how far apart the last few were, both in seconds of wall clock.
##
## MEASURED RATHER THAN ASSUMED, and that is not fussiness: the relay's rate is a FLAG
## (`sim-relay --tps N`, default 10), so a 100 ms constant in this client would draw a `--tps 20`
## world at half speed and nothing would report it. An observed gap also degrades the right way -- if
## the link stalls, the fraction saturates and the sprite SITS on the last position the sim produced,
## which is exactly where it should be.
var _tick_at := 0.0
var _tick_gap := 0.1
## The ore under the camera, as the sim answered it: tile -> {species, grade, depleted}.
##
## CACHED, AND THE CACHE'S KEY IS THE HONEST PART. Which deposit covers a tile is a circle the sim
## owns, so this is `tile_at` per tile and there are ~580 of them in a 28x18 window -- too many to ask
## every frame and not nearly enough to be worth asking twice. It is rebuilt when the window moves or
## when a visible patch runs out, and `depleted` is the only thing about a deposit that can change
## what is DRAWN (the row becomes `depleted_full`; `amount` itself is on no sprite).
var _ore := {}
var _ore_at := Rect2i()
var _ore_stamp := ""
var _ore_tick := -1
## `assets/sprites/manifest.json`, parsed once. `AssaySprites.manifest()` re-reads and re-parses the
## file on every call, which is fine for a pack row built on a tick and plainly not fine for a view
## rebuilt 60 times a second. Cached here rather than in that file so nothing else's behaviour
## changes with this item.
var _manifest := {}
## `assets/sprites/part_layout.json`, parsed once, for exactly the reason above: a planted machine's
## rectangle is worked out from the repeat offset on every frame it is on screen, and
## `AssayAssembly.contract()` opens and parses the file every call.
var _layout := {}
## The tile under the mouse, and whether the mouse has ever been over the map. Not a Vector2i alone,
## because tile (0, 0) is a real tile and "no hover" is not it.
var _hover := Vector2i.ZERO
var _hovering := false
## The newest event lines, oldest first. View state: the sim keeps only the last tick's events, so
## anything older than that is remembered here or nowhere.
var _events := PackedStringArray()
## **THE MOTION PROBE, WHEN THE PLAYER'S OWN BUILD WAS ASKED TO MEASURE ITSELF** (ASSA-211). Null on
## every normal run. Not a tool: `tools/*` is excluded from both export presets and `--script` is
## dropped by the official release templates, so a probe that lives out there can only ever measure a
## developer's project. This one comes in through the same door as `--selfcheck`.
var _motion_probe: AssayMotionProbe
var _motion_probe_path := ""


func _ready() -> void:
	# CI, not a player: prove the build it just exported works, then leave. Before any UI, because
	# a self-check that needed the window would not run on a build server.
	var selfcheck := AssaySelfCheck.requested_path()
	if selfcheck != "":
		get_tree().quit(AssaySelfCheck.run(selfcheck))
		return
	# THE WHOLE SCREEN IS BUILT ONCE, AND THE LINK IS PART OF THE SCREEN. The guard used to sit in
	# `_build_ui`, which covered the HUD and nothing else -- so a second `_ready` built a SECOND
	# `AssayNetClient` and left `_client` pointing at it. The first one stayed connected to every
	# handler here, so the world kept stepping while `_client.stage` read IDLE and
	# `_client.player_id` read -1: the HUD showed somebody else's empty inventory of a world that was
	# plainly moving. Found by `tools/button_session.gd` against a real relay, where it looked like a
	# join that never happened; the suite could not see it because nothing in it joins.
	if _built:
		return
	_built = true
	# **THE WINDOW'S OWN BACKGROUND IS A COLOUR SOMEBODY CHOSE** (ASSA-237).
	#
	# **MEASURED, NOT NOTICED**: on a real-window shot of main at 1280x720, **16.0% of the window is
	# `(77, 77, 77)`** -- Godot's default clear colour, which is not in `build_theme.gd`'s palette, not
	# in `AssayHud`'s marks, and chosen by nobody here. It was the 24px frame around the map and the
	# 96px header band above it (the band has since gone, ASSA-239; the frame remains), and it had been
	# in every screenshot of this game we had ever sent the board.
	#
	# **AND IT IS A CONTRAST DEFECT, WHICH IS WHY IT IS IN THIS SLICE RATHER THAN A TASTE ITEM.** This
	# is ASSA-152 one layer out: that item found the HUD column's text rendering on this same default
	# grey at **3.86:1** against a 4.5 floor, and fixed it by painting the column. The STATUS LINE
	# still sits on the bare window, and ASSA-233 has just moved it to `INK_MUTED` -- which on
	# `(77,77,77)` is that same **3.86:1**. On `MAP_BG` it is **7.79:1**. Maren's doc: *"Contrast floor
	# 4.5:1 ... not negotiable for a look."*
	#
	# `AssayHud.MAP_BG` AND NOT A LITERAL, and not a new token either: the window is the surface
	# FURTHEST back, the map's backing is the darkest value this game names, and two greys that have to
	# agree about one thing is the ASSA-116 defect. Set here rather than in `project.godot` for the
	# same reason -- a colour in a settings file is a second declaration of a value `hud.gd` owns.
	RenderingServer.set_default_clear_color(AssayHud.MAP_BG)
	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.refused.connect(_on_refused)
	_client.link_failed.connect(_on_link_failed)
	_client.tick_bundle.connect(_on_tick_bundle)
	# THE WARNING BEFORE THE DROP (ASSA-191). Not a `_say`: it is reversible, so it may not become the
	# last real sentence the window remembers. See `_render_status`.
	_client.link_quiet.connect(_on_link_quiet)
	# **THE QUESTION THIS COMMENT USED TO ASK HAS BEEN ANSWERED: A DESYNC DROPS YOU** (ASSA-190, and
	# it was my own question to answer -- the net layer is mine). It used to read "a desync is not a
	# drop, so Join refuses and there is genuinely nothing on this screen that can recover", which was
	# true and was the defect: the one failure in this client with no way out of the window.
	#
	# `net_client.gd` now hangs up on `Desync`, so the stage is DEAD, the join band is back and Join
	# is live -- one press and the relay's fresh `Welcome` replaces the world that drifted.
	#
	# **THE SENTENCE NAMES THE TICK AND BOTH HASHES, which is the evidence half.** A drop that says
	# only "we diverged" is indistinguishable from a bad connection, and a determinism bug that reads
	# as a network problem is the one this game cannot afford to lose. It stays `Say.FAILED`: the
	# session really did end, and Join is an offer, not a reassurance.
	_client.desynced.connect(func(tick, reported, expected): _on_desync(tick, reported, expected))
	# **A NOTE IS NARRATION, AND ONCE YOU ARE IN A WORLD IT STOPS BEING THE PLAYER'S** (ASSA-245,
	# Maren's Gap 2; found at 1x by Nerite and independently by my own suite).
	#
	# Before a world, a note is the only thing describing a door that has not opened yet --
	# `connecting to <host> as <name>`, `said hello on protocol 9`, `not joined, so nothing was sent`
	# -- so it goes on the status line, where a stranger is already looking.
	#
	# **AFTER a world exists, exactly one note can still fire: `offline, so no hash report was sent`**
	# (`net_client.gd:204`, every time a report is owed, which offline is every 20 ticks). That is a
	# sentence about THIS CLIENT'S HASH REPORTING on the screen we send the board -- the same category
	# Gap 2 sent away, and Maren named this very line in her ruling. Offline it also re-fires on
	# exactly the dwell `_age_the_saying` uses, so it owned the toast for the whole of a played
	# session: the status line was never once empty on a healthy world, which is what box 5 claims.
	#
	# **IT IS STILL PRINTED, SO NOTHING IS LOST TO US.** `_say` prints every sentence it shows; this
	# branch keeps the print and drops only the drawing, so every probe and session log reads exactly
	# as it did. The words are untouched -- they are not mine to change (Marlow's boundary); where
	# they are DRAWN is.
	_client.note.connect(func(line):
		if _client.stage == AssayNetClient.Stage.JOINED:
			print(line)
		else:
			_say(line, AssayHud.Say.CONNECTING))
	add_child(_client)
	_build_ui()
	# **TWO DOORS, SOLO FIRST** (Maren, ASSA-113). This used to read "enter a host address and join",
	# which sent a stranger to the one door that needs information they do not have -- and it survived
	# the whole of ASSA-106 because I never re-read the item between the branch and the PR.
	#
	# **THE SENTENCE MOVED, IT DID NOT GO** (Maren's ruling 1, ASSA-127). It is the same words, now in
	# `AssayHud.empty_map_line` on the map itself, because here it was ~1.5% of the window sitting
	# above a silent 59%. One sentence in one place, and the status line goes back to being what it is
	# everywhere else in this client: what just happened, not what to do.
	_say("", AssayHud.Say.IDLE)
	# **THE PLAYER'S OWN BUILD, MEASURING ITSELF** (ASSA-211). After `_build_ui`, because the probe
	# presses the real "Play solo" button and a button that does not exist yet cannot be found. Not
	# before the UI the way `--selfcheck` is: that one answers without a window, this one is ABOUT the
	# window, so it needs the whole screen standing.
	_motion_probe_path = AssayMotionProbe.requested_path()
	if _motion_probe_path != "":
		_motion_probe = AssayMotionProbe.new()
		_motion_probe.begin(self, AssayMotionProbe.requested_seconds(), OS.get_name())


## WHETHER `_ready` HAS ALREADY RUN. `tests/test_main_screen.gd` and `tools/button_session.gd` both
## call `_ready()` by hand (a `--script` run works inside `SceneTree._initialize`, before the root
## window is in the tree, so the engine's own call comes too late to be useful) AND put the node in
## the tree, so the engine calls it again.
##
## The first thing that caught was the HUD column being built twice, with every label reparented into
## the second one: harmless on screen, but it filled the suite's output with `Can't add child ...
## already has a parent`, and error spam nobody reads is where a real error goes to hide. The second
## was worse and is why this guard moved up to `_ready` -- see the note there.
var _built := false


func _build_ui() -> void:
	# THE WORLD FIRST, so every control built below this line draws on top of it. Nothing in the HUD
	# actually overlaps the world's rectangle today -- that is `AssayHud.world_rect`'s whole job -- but
	# child order is what would decide it if one ever did, and a panel UNDER the map is not a defect a
	# screenshot makes obvious.
	var world := AssayHud.world_rect()
	# **THE JOIN SURFACE GOES IN FIRST, UNDER THE MAP** (ASSA-231). Hidden whenever there is a world,
	# so it can never be between the player and the thing they are playing.
	var door := AssayHud.join_rect()
	_door_backdrop.position = door.position
	_door_backdrop.size = door.size
	_door_backdrop.color = AssayHud.MAP_BG
	_door_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_door_backdrop)
	_world.position = world.position
	_world.size = world.size
	add_child(_world)
	# **THE BIGGEST SURFACE IN THE GAME NAMES WHICH KIND OF EMPTY IT IS** (Maren, ASSA-127). Over the
	# world's own rectangle and added straight after it, so it covers exactly the surface it explains
	# and draws on top of the background `_world` paints.
	#
	# `MOUSE_FILTER_IGNORE` IS NOT DECORATION: this control spans 912x672 of the window, and the map
	# is clicked through `_unhandled_input`. A label that answered the mouse would swallow every
	# click on the world and the failure would be "Play solo does nothing", nowhere near this line.
	# **AND IT IS A COMPOSITION NOW, NOT A SENTENCE** (ASSA-231, Maren's Gap 5). The door spans the
	# same rectangle the sentence used to span and carries that sentence unchanged; what is new is
	# that the controls it talks about stand underneath it instead of in the far corner.
	#
	# `MOUSE_FILTER_IGNORE` FOR THE REASON THE NOTE HAS IT, one level up: this is a 912x672 Control
	# over the map, and a Container does NOT inherit the note's filter. IGNORE does not apply to
	# children, so every button inside it still gets its clicks -- and the failure if it did would
	# read as "Play solo does nothing", nowhere near this line.
	_front_door.position = door.position
	_front_door.size = door.size
	_front_door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front_door.alignment = BoxContainer.ALIGNMENT_CENTER
	_front_door.add_theme_constant_override("separation", 10)
	add_child(_front_door)
	# THE GAME'S NAME, AT THE TOP OF THE TYPE SCALE WE HAVE. `Display` is 20px/INK -- the size Maren
	# measured as "used exactly once in the game, on the bench verdict". A title screen is what it is
	# for. **AND IT IS THE CEILING:** a bigger title means a fifth size in `build_theme.gd`, which is
	# a type-scale ruling and hers, so the shot goes to her with the limit named rather than with a
	# number I invented in this file.
	_door_title.text = ProjectSettings.get_setting("application/config/name", "Assay")
	_door_title.theme_type_variation = &"Display"
	_door_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_door_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front_door.add_child(_door_title)
	# **THE SAME WORDS, AND NOT ONE WORD OF NEW COPY** (Maren's ruling 1, ASSA-127: "keep the existing
	# words"). The sentence names both doors, solo first, and now the two rows under it are in that
	# same order, so the layout and the sentence say one thing instead of two.
	_map_note = _note(AssayHud.empty_map_line())
	_map_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front_door.add_child(_map_note)

	_build_log_over_the_map(world)
	_build_map_key_over_the_map(world)

	_view_toggle.position = world.end - Vector2(152.0, 36.0)
	_view_toggle.custom_minimum_size = Vector2(144.0, 0.0)
	# IT LISTS BUILDINGS NOW BECAUSE THE VIEW DRAWS THEM NOW (ASSA-189). This sentence promised "every
	# deposit and every player" and never buildings, which was honest and was Maren's evidence that
	# the gap was never written down rather than a regression. A promise that outlives its own defect
	# is the next defect.
	_view_toggle.tooltip_text = ("the close-up follows you at 32px a tile; the whole world is the"
			+ " schematic, with every deposit, every factory and every player on it")
	_view_toggle.pressed.connect(func(): _show_close_up(not _close_up))
	add_child(_view_toggle)
	# NOT ON THE JOIN SCREEN (ASSA-142 box 3 / ASSA-161, Maren's ruling): there is never a world at
	# build time, and this button offers a view of one. It was the ONLY button inside the map's
	# rectangle before a join, 280px below the one sentence on it, while the five sections beside it
	# each say "no world yet" in words -- so the one surface that said nothing said it with a
	# control, and a control is a promise that pressing it does something.
	#
	# HIDDEN RATHER THAN DISABLED, which Maren left to the builder and leaned the same way: the
	# screen already carries five "no world yet" sentences and a sixth would be noise, and this
	# button has no world to describe even in the past tense.
	#
	# `_refresh` is what brings it back, on the world's existence rather than on the join event --
	# see there for why that is the honest test.
	_view_toggle.visible = false

	# THE KEY'S TOGGLE, LEFT OF THE VIEW'S, in the same corner and the same size: the two controls
	# are one sentence -- the view that has the marks, and what the marks mean -- and a key's toggle
	# anywhere else is a control about a surface it is not on. Hidden for the same two reasons the
	# view toggle is (no world, ASSA-142 box 3; and no schematic, see `_show_close_up`).
	_map_key_toggle.position = world.end - Vector2(312.0, 36.0)
	_map_key_toggle.custom_minimum_size = Vector2(144.0, 0.0)
	_map_key_toggle.text = AssayHud.map_key_toggle_text(false)
	_map_key_toggle.tooltip_text = ("every mark the whole-world map can draw, named: the shape key."
			+ " The species panel beside it is the colour one")
	_map_key_toggle.pressed.connect(func(): _show_map_key(not _map_key_shown))
	add_child(_map_key_toggle)
	_map_key_toggle.visible = false

	# THE ROW IS THE IN-WORLD HOME ONLY (ASSA-231). On the join screen it stands empty and the three
	# controls are in `_front_door`; `_place_join_controls` moves them here when a world appears, which
	# is also the state `Join` has to be reachable in (ASSA-175/ASSA-177).
	#
	# **AND IT IS NOT IN THE TOP-LEFT CORNER ANY MORE: IT IS IN THE TOAST** (ASSA-239). It was at
	# (24, 20), inside the 96px header strip Maren's Gap 2 ruling deleted, and a row left there would
	# have been the strip surviving its own removal -- the only control still drawn above the world.
	# My own `test_no_control_is_drawn_above_the_world_in_a_played_screen` is what found it.
	#
	# **THE TOAST IS THE RIGHT HOME AND NOT MERELY A FREE ONE.** Everything in this row is reachable
	# in exactly one in-world state: the link has died and these are the way back in (ASSA-177). The
	# toast is where the client says *why* it died. Limpet's own rule on ASSA-231 was that *"a refusal
	# 300 px from the button that earned it is the same defect ASSA-127 fixed"* -- so the sentence and
	# the button that answers it go in one panel. Added before the labels arrive and moved last by
	# `_place_join_controls`, so the panel always reads what happened, then what to do about it.
	_row.add_theme_constant_override("separation", 8)
	_says_toast_box.add_child(_row)

	# THE BAND INSIDE THE ROW: everything a player in a world can no longer use (ASSA-175). Same
	# separation as the row it sits in, so the band is a grouping for the hide and not a layout change
	# -- a `BoxContainer` skips invisible children, so the gap before `Join` closes when it goes.
	_join_band.add_theme_constant_override("separation", 8)
	_row.add_child(_join_band)

	# **PLAY SOLO: DOWNLOAD AND PLAY, WITH NOTHING TO TYPE** (ASSA-106, the board's own ask). The
	# host box already defaults to `localhost`, so the shortest honest version of their request was
	# never "a field with a better default" -- it was that nothing is listening on the other end.
	# This starts the `sim-relay` that shipped in the same zip, on loopback, and joins it.
	#
	# **FIRST IN READING ORDER AND IT TAKES THE FOCUS** (Maren, ASSA-113): the door that needs nothing
	# typed is the first thing a stranger reads and the thing Enter presses. Beside `Join` rather than
	# instead of it -- a friend's host address is the other half of the milestone and this must not
	# become the only way in.
	#
	# **THE AXIS CHANGED AND THE RULING DID NOT** (ASSA-231). Her sentence was "the row reads left to
	# right"; on the join screen the composition now reads top to bottom, with this button alone on
	# its line above the host path, so it is still the first control a stranger meets and still the
	# one Enter presses. In a world the controls are back in a left-to-right row and it is first there
	# too.
	#
	# FOCUS IS ASKED FOR ON `tree_entered`, NOT TAKEN HERE. `grab_focus` asserts `is_inside_tree()`,
	# and measured: inside `SceneTree._initialize` -- where the suite and every tool run -- a node
	# added under the root reports `is_inside_tree() == false`, `get_viewport()` is null, and
	# `grab_focus` errors out leaving `has_focus()` false. One frame later the same node IS in the
	# tree and the focus lands for real, headless included (`tools/focus_probe.gd` reads it back off
	# the viewport). So the request is attached to the moment the button reaches a tree, which is the
	# only time it can succeed, and it costs the suite nothing.
	_solo_button.text = "Play solo"
	_solo_button.tooltip_text = "start a world of your own on this machine and join it"
	# **THE ONE CONTROL ON THIS SCREEN THAT IS THE POINT OF IT** (ASSA-224, Maren's Gap 1: "the
	# accent belongs to the thing you are most likely to press next", and Gap 5: "the one thing a
	# stranger should press is a small outlined button in the top-left corner"). Until now every
	# button in the game was one grey box at 11 px, so the screen had no way to say this.
	#
	# **ONE `Primary` PER SCREEN, WHICH IS NOT THE SAME CLAIM THIS COMMENT USED TO MAKE** (ASSA-251,
	# Maren). It said "IT IS THE ONLY `Primary` IN THE CLIENT", and that stopped being true the
	# moment `Mine` earned the rank on ASSA-233 — a stale invariant in a comment is how someone
	# rebuilds the defect, and this one sat two lines above the code it was wrong about.
	#
	# The rule is per SCREEN: `Play solo` here, `Mine` on the played screen, and never both at once.
	# The dropped screen is exactly where that went wrong — `Mine` is accented off the sim's rock bit
	# and `Play solo` off the stage, so a dead session showed two greens with the useless one looking
	# the most alive. `_refresh_actions` now gates `Mine` on there being a session at all.
	#
	# WHICH IN-WORLD VERB EARNS IT IS MAREN'S RULING AND NOT MINE -- picking between Mine, Assay and
	# Make from a theme file would be tuning the game's emphasis by hand.
	_solo_button.theme_type_variation = &"Primary"
	_solo_button.focus_mode = Control.FOCUS_ALL
	_solo_button.pressed.connect(_on_play_solo)
	_solo_button.tree_entered.connect(_solo_button.grab_focus)
	# THE CELL AND NOT THE BUTTON IS WHAT TRAVELS AND WHAT HIDES (ASSA-231): one node to move, one
	# node to hide, and the two cells keep `Play solo` and the host path separable so the primary can
	# have a line of its own on the join screen.
	_solo_cell.add_child(_solo_button)

	var host_label := Label.new()
	host_label.text = "host"
	_cred_cell.add_theme_constant_override("separation", 8)
	_cred_cell.add_child(host_label)
	_host.text = "localhost:%d" % AssayProtocol.DEFAULT_PORT
	_host.custom_minimum_size = Vector2(240.0, 0.0)
	_host.tooltip_text = "host, host:port, or [v6]:port. A bare address uses 7777."
	_cred_cell.add_child(_host)

	var name_label := Label.new()
	name_label.text = "name"
	_cred_cell.add_child(name_label)
	_name.text = OS.get_environment("USER")
	_name.custom_minimum_size = Vector2(140.0, 0.0)
	_cred_cell.add_child(_name)

	_join_button.text = "Join"
	_join_button.pressed.connect(_on_join)

	# **THE TWO ROWS OF THE COMPOSITION, AND THE RANK IS THE LAYOUT AS WELL AS THE COLOUR.** Gap 5's
	# complaint is that the one thing to press is "visually subordinate to the host field, the name
	# field and Join"; ASSA-224 answered the colour half. A primary that shares its line with two text
	# boxes is still competing with them, so it gets the line.
	_door_primary.alignment = BoxContainer.ALIGNMENT_CENTER
	_door_primary.add_child(_solo_cell)
	_front_door.add_child(_door_primary)
	_door_secondary.alignment = BoxContainer.ALIGNMENT_CENTER
	_door_secondary.add_theme_constant_override("separation", 8)
	_door_secondary.add_child(_cred_cell)
	_door_secondary.add_child(_join_button)
	_front_door.add_child(_door_secondary)

	# WHAT THE CLIENT IS SAYING, UNDER WHAT IT IS SAYING IT ABOUT. `SHRINK_CENTER` so the block is its
	# own width and centred rather than two lines of left-aligned text across 912px; the labels keep
	# their own alignment, which is what they go back to in a world.
	_door_says.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_door_says.add_theme_constant_override("separation", 2)
	_door_says.add_child(_status)
	_door_says.add_child(_detail)
	_front_door.add_child(_door_says)

	# THE TOAST THE SAME TWO LABELS MOVE INTO ONCE THERE IS A WORLD (ASSA-239). Built here, empty:
	# `_place_join_controls` fills it by reparenting, so there is one copy of each label and never a
	# second that has to agree with the first.
	#
	# ADDED AFTER `_front_door` SO IT DRAWS OVER THE MAP, and `MOUSE_FILTER_IGNORE` on both the panel
	# and its box so the corner it floats in still answers clicks on the world.
	_says_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_says_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_says_toast_box.add_theme_constant_override("separation", 2)
	_says_toast.add_child(_says_toast_box)
	add_child(_says_toast)
	_says_toast.visible = false
	# **AND THE READOUT IS NOT DRAWN** (ASSA-237). Its PLACE is ASSA-231's and untouched here -- this
	# slice decides who it is drawn for, not where it sits. Called after the node is in the tree so
	# that "hidden on first open" is a state something actually set, not a default.
	_show_dev_readout(false)

	# THE HUD COLUMN, beside the map. Each section is the plainest thing that answers one question:
	# what am I carrying, what can I do here, what have I built, what is under the cursor, what just
	# happened.
	#
	# SCROLLED, SINCE THE ROWS GREW BUTTONS. A full pack plus a bench is taller than 720px, and a
	# button pushed off the bottom of the window is worse than a disabled one -- it looks available
	# and cannot be pressed. The scroll box is what carries the position now; the inner column sits at
	# the origin inside it.
	#
	# AND TWO THINGS ARE PINNED ABOVE IT, outside the scroll: the log's toggle (ASSA-89 -- a control
	# inside a column taller than the window is one a stranger has to scroll to find) and what has
	# stopped (ASSA-117 -- a condition a later line must not be able to push away).
	#
	# THE PANEL IS A COLUMN OF THREE NOW, laid out by a container rather than by arithmetic. The
	# scroll's height used to be `VIEW.y - MARGIN.y - LOG_TOGGLE_H - 24.0`: four numbers written down
	# and a fifth (`LOG_TOGGLE_H`) that was a guess at how tall a themed Button is.
	#
	# WHY A CONTAINER AND NOT A THIRD POSITION. The stopped block appears and disappears with the
	# world: a hand-placed scroll box would have to be moved and resized every time it did, and
	# whatever number I wrote for its height would be the floor that rots. `SIZE_EXPAND_FILL` on the
	# scroll is the derivation -- the scroll is whatever the other two leave, measured by the engine
	# on the frame they change, and nobody has to remember it.
	var chrome := VBoxContainer.new()
	# `COLUMN_TOP`, WHICH **IS** `MARGIN.y` NOW (ASSA-239). It was 8 against a `MARGIN.y` of 96,
	# because the header band spanned the map's width and not the window's and the column was allowed to
	# climb into the 347 x 96 of unowned chrome beside it. The band is gone, so there is nothing to
	# climb into and the column shares the world's top edge instead. Still named rather than inlined:
	# see `AssayHud.COLUMN_TOP` for why one decision gets one declaration.
	var column_rect := Rect2(Vector2(VIEW.x - PANEL - MARGIN.x, AssayHud.COLUMN_TOP),
			Vector2(PANEL, VIEW.y - AssayHud.COLUMN_TOP - 24.0))
	# THE COLUMN'S TEXT USED TO SIT ON NOTHING, AND "NOTHING" IS A COLOUR (ASSA-152, Maren).
	#
	# The theme styles `Panel` and `PanelContainer` (`build_theme.gd::_style_panel`) and this column
	# was neither -- `chrome`, `scroll` and `column` are a VBox, a ScrollContainer and a VBox. So
	# SURFACE was painted on ZERO pixels of the screen and every line in here rendered on Godot's
	# default clear colour, 0.3 grey = exactly (77,77,77). Measured on two real window shots:
	# INK_MUTED came out at 3.86:1, UNDER the 4.5 floor, where the guard had verified 6.74:1 against
	# the surface the theme declares. The board called the log "hard on the eyes" at 4.091:1; every
	# section heading, every crafting row and the status line have been worse than that ever since.
	#
	# A plain `Panel`, NOT a `PanelContainer` (Maren's ruling, and her reason is reflow): a
	# `PanelContainer` imposes its stylebox's content margins and re-lays everything inside it, and
	# the column's layout is what ASSA-147 just finished settling.
	#
	# **SHE RULED A SIBLING AND THIS IS A PARENT. I CHANGED THAT ONE THING AND SAID SO ON THE ITEM.**
	# Her amended box 3 asks the guard to "climb each Label's ancestors until one resolves a panel
	# stylebox" -- and a SIBLING is never an ancestor, so the two halves of her ruling cannot both be
	# built. A parent satisfies the reason she gave for the sibling: `Panel` is NOT a `Container`, so
	# it lays its children out exactly never; `chrome` keeps its own position and size and nothing
	# reflows. That is measured, not reasoned -- `test_the_painted_surface_moves_no_control` holds
	# every section's rect against the sibling arrangement, and `window_shot`'s fold report says the
	# same from a real window.
	#
	# IGNORE on the mouse because a `Panel` is a Control that would otherwise swallow clicks on empty
	# column; `MOUSE_FILTER_IGNORE` does not apply to children, so every button inside still gets its
	# events. This is the opposite choice to the log panel's STOP (ASSA-147), and deliberately: that
	# one is a surface a player reads ON TOP of the map and must not click through; this one is the
	# floor the column already stood on.
	var surface := Panel.new()
	surface.position = column_rect.position
	surface.size = column_rect.size
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.name = COLUMN_SURFACE
	add_child(surface)
	# **THE COLUMN IS NOT ON THE SCREEN BEFORE THERE IS A WORLD** (ASSA-231, Maren's Gap 5: "the empty
	# column not shown at all before a world exists").
	#
	# Six of its seven sections said which kind of empty they were, which was ASSA-134 and ASSA-186
	# working exactly as ruled -- and as a COMPOSITION Maren's own doc calls the result "a column of
	# six apologies". The rule has not changed for the state it is about; this is the state leaving.
	#
	# HIDDEN AT BUILD AND NOT ON THE FIRST REFRESH, because `_refresh_world` is not called on the join
	# screen at all (`_process` only calls it `if _close_up and _sim.running()`), so a column shown
	# here and hidden later would be shown for the whole of the join screen. Same reason
	# `_view_toggle.visible = false` is set at build a few lines up.
	_column = surface
	_column.visible = false
	# THE GUTTER, AND THE THEME ALREADY DECIDED IT (ASSA-142, Maren: "the number comes from the
	# container, not from this item").
	#
	# Measured on `01-join.png` from current main: the leftmost glyph is at x=936 and the panel's
	# first column is x=936 -- **zero padding**, with the map's hard colour boundary immediately to
	# its left. The rightmost glyph is x=1255 and the panel's last column is x=1255, so the right
	# is flush too; the 24px of air on that side is the WINDOW's margin outside the panel, not the
	# panel's own.
	#
	# **THE NUMBER IS `content_margin_left` OFF THE PANEL'S OWN STYLEBOX, READ, NEVER TYPED.**
	# `build_theme.gd::_box` sets it on every panel in the theme, and `_running_box` and `_halt_box`
	# get it for free because a `PanelContainer` IS a Container and applies it. This column is the
	# one panel in the window that does not -- a plain `Panel` draws the stylebox and lays out
	# nothing, which is exactly why it was chosen (ASSA-152) and exactly why its content had no
	# inset. So the padding was never missing from the design; it was declared and unapplied.
	#
	# A `MarginContainer` rather than arithmetic on `chrome`, for this file's standing reason: a
	# number written here is a number that rots when the theme is retuned. If `PAD_X` moves, the
	# column follows on the next build with nothing to remember.
	#
	# LEFT AND RIGHT ONLY, NOT TOP AND BOTTOM. The stylebox declares a vertical margin too, and
	# spending it costs the scroll box 12px of height -- the budget ASSA-154 is already open about
	# (587px of `rocks` pushing the cursor readout off screen). The defect Maren measured is
	# horizontal: text against a colour boundary. Taking only what the defect needs is the whole of
	# the reason, and if she wants the vertical too it is one more override.
	var pad := MarginContainer.new()
	pad.name = COLUMN_PAD
	pad.position = Vector2.ZERO
	pad.size = column_rect.size
	var panel_box := surface.get_theme_stylebox(&"panel")
	pad.add_theme_constant_override(&"margin_left", int(panel_box.content_margin_left))
	pad.add_theme_constant_override(&"margin_right", int(panel_box.content_margin_right))
	surface.add_child(pad)
	chrome.add_theme_constant_override("separation", 6)
	# NO POSITION OR SIZE SET ON `chrome` ANY MORE: the `MarginContainer` owns both now, and a rect
	# written here would be overwritten on the first layout pass and believed by every headless test
	# until a real window disagreed with it.
	pad.add_child(chrome)
	# QUIET, BECAUSE IT IS FURNITURE (ASSA-224). On `01-join.png` this toggle reads as loudly as the
	# section headings it sits above, so the column's structure competes with its own controls.
	_log_toggle.theme_type_variation = &"Quiet"
	# LEFT, INTO THE BODY COLUMN (ASSA-233, Maren at 1x). Centred and boxless, this read as the
	# PANEL'S TITLE -- a dim centred line across the top of a panel is where a title sits.
	_log_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_log_toggle.pressed.connect(func(): _show_log(not _log_shown))
	chrome.add_child(_log_toggle)
	# WHAT IS RUNNING, THEN WHAT HAS STOPPED, both above the scroll and never inside it (ASSA-133).
	# Running first because it is the thing you started and are waiting on; stopped is what you have
	# to go and deal with, and it keeps its place directly over the sections you deal with it in.
	# Each is a `PanelContainer` so the block reads as its own surface, from the theme (ASSA-116)
	# rather than from a colour typed here.
	_running_box = PanelContainer.new()
	_running.add_theme_constant_override("separation", 2)
	_running_box.add_child(_running)
	chrome.add_child(_running_box)
	_halt_box = PanelContainer.new()
	_halt.add_theme_constant_override("separation", 2)
	_halt_box.add_child(_halt)
	chrome.add_child(_halt_box)

	# **WHAT YOU CAN DO HERE, AND IT IS THE ONLY SECTION LEFT ABOVE THE TABS** (ASSA-247; Wren's
	# ruling 16:35 UTC 2026-10-06, Maren ratifying at 17:22 and withdrawing half of her own 17:05).
	#
	# THE RULING CAME OUT OF A MEASUREMENT, so the reason is a number rather than a preference:
	# `you` + `do` always-on is **434 px of a 477 px worst-case clip**, 91%, and no tab of any size
	# fits behind that. Maren's 17:05 ruling named the pack as always-on because it is the INPUT to
	# every make decision; what it protected is paid on Make instead -- an unavailable row says what
	# you lack -- and the pack is a tab, which is the structure Rainy named ("tabs such as Crafting,
	# Inventory, Research").
	#
	# `do` STAYS because it is the one section that is neither reference nor a system: it is the
	# verbs for the tile you are standing on or pointing at, it is 126 px with its heading, and it is
	# what a player presses. A tab you must open to reach Mine is the clunk restated.
	#
	# NO CARRY SUMMARY LINE ABOVE THE STRIP (Maren, 17:22): the budget clears the worst clip by about
	# 4 px, which she calls noise and I agree. It earns its place only if a playtest shows that
	# mining stops feeling like it accumulates.
	var do_heading := Label.new()
	do_heading.text = "do"
	do_heading.theme_type_variation = &"Heading"
	chrome.add_child(do_heading)
	chrome.add_child(_actions)
	# **ONE TABBED SYSTEMS PANEL, ONE SYSTEM AT A TIME** -- the board's own shape, ruled twice. See
	# `AssayTabStrip` for why it is a visible strip and not a keyboard summon, and for the property
	# the strip is built to: adding a tab is one entry, not a re-layout.
	#
	# `EXPAND_FILL` IS THE WHOLE LAYOUT. The strip takes exactly what the blocks above it leave, on
	# the frame they change, and nothing in this file writes a height for it -- the same derivation
	# the old scroll box used, and the reason the stopped block can appear and disappear with the
	# world without anybody moving a number.
	_tabs = AssayTabStrip.new()
	_tabs.name = TABS
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chrome.add_child(_tabs)
	# **THE COLUMN'S SCROLL BOX IS THE OPEN TAB'S BOX NOW**, which is what "the column stops
	# scrolling" means structurally rather than hopefully: there is no box around the whole column to
	# scroll any more, so no section can be reached only by scrolling PAST another section. What may
	# still scroll is one tab's own body, which is Wren's rule exactly -- a list of forty rocks
	# scrolling is a list. `_scroll` keeps its name because every reader of it (the clip report in
	# `window_shot.gd`, the tests that hold the log and the stopped block outside it) is asking the
	# same question about the same box.
	_scroll = _tabs.scroll_box()
	# **A SECTION MAY NOT SIT ABOVE THE SECTION IT IS DERIVED FROM** (ASSA-133, Maren's ruling 2) --
	# AND THE TABS RETIRE THAT PROBLEM RATHER THAN SOLVING IT AGAIN. Her measurement was that `make`
	# grew +198px across one craft session and pushed `you` 148px past the BOTTOM of the window,
	# because a derived list that outgrows its source and shares a scroll box with it will always be
	# what pushes the source off. `make` and the pack are now different tabs: neither is ever above
	# the other, and growth in one cannot move the other by a pixel. The ruling's REASON is kept --
	# nothing derived shares a box with its source -- which is why the pack did not simply move down.
	#
	# THE RUNNING CRAFT IS STILL NOT IN THE MENU (ruling 1): it is a line in the chrome's running
	# block with mining and assaying, pinned above the tabs.
	_make_toggle.theme_type_variation = &"Quiet"  # furniture, same as the log toggle (ASSA-224)
	# AND LEFT, for the same reason: centred under the `make` heading it read as that heading's
	# caption rather than as a control (ASSA-233).
	_make_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_make_toggle.pressed.connect(func(): _show_make(not _make_shown))
	# THE EVENT LOG IS NOT IN THIS LIST ANY MORE (ASSA-147). It was the last section; it is now a
	# panel over the map, built by `_build_log_over_the_map`. Maren's reason in one line: it is the
	# only CONSULTING surface in a column of ANNOUNCING ones, it is the only unbounded one, and in a
	# shared scroll box the unbounded one always wins -- what it won against was Mine, Stop and Assay.
	# WHICH KIND OF EMPTY THE `cursor` SECTION IS (Maren's ruling, ASSA-134). Every other section in
	# this column plants its own empty note from its `_refresh_*`, but `cursor` is a bare Label written
	# straight from `_refresh` -- which RETURNS before it on every not-joined path, so the heading sat
	# over a blank Label on the first screen a stranger sees. Maren measured it at 93px, the largest
	# labelled void in the column, and `_note`'s own docstring is the rule it broke.
	#
	# SET HERE, ONCE, because there is no `_refresh_cursor` to derive it in and inventing one for a
	# single Label would be two places that have to agree about one sentence. The limit that leaves:
	# if a joined world STOPS, this keeps its last tile reading rather than returning to this line --
	# the sentence the STATUS LINE carries in that case ("no world is being simulated") is the surface
	# that says so, and a frozen readout beside it is stale, not wrong. (That sentence was `_detail`'s
	# until ASSA-237 hid `_detail` from the player; it moved so that this clause stayed true.)
	_cursor.text = AssayHud.quiet_cursor_line()
	# **EVERY TAB IN ONE LIST, AND ITS NAME IS ITS HEADING.** The six sections each carried a
	# `Heading` Label inside one scroll box; a tab's own name is that heading, so a second one inside
	# the body would print the word twice and spend a line per section doing it. `do` keeps its
	# heading because it is not in the strip and nothing else names it.
	#
	# **THE FOUR NAMES ARE THE BOARD'S, NOT A SHORTLIST OF MINE** (Rainy, 16:53 UTC 10-05: "tabs such
	# as Crafting, Inventory, Research"). `inventory` is Rainy's word for what this column called
	# `you`; `make` keeps the name the loop and the sim's own `make_offers` use, because renaming a
	# surface in the same slice that moves it makes two changes impossible to judge apart.
	#
	# **`mineralogy` IS THIS COLUMN'S `rocks`, RENAMED — NOT A FIFTH TAB** (Maren, 18:45 UTC 10-06,
	# and Wren folded it into the gate at 18:54). `_species` already lists every species with its
	# sheet state, readings and tags, which is the index Rainy described; shipping both would ship
	# two tabs ~90% identical in pixels and give one species fact two places to drift.
	#
	# **THE LABEL IS RAINY'S WORD AND THE SECTION IS OURS.** This is the one rename in the slice, and
	# it is here rather than at the section because `_species` is still what the code calls the list
	# the sim fills; the tab is what the player reads.
	#
	# ASSA-254's body (Limpet's `AssayMineralogy`, merged in #340) IS WIRED, and it cost the one
	# `add_tab` argument this comment promised: `_species` moves inside his `evidence` box and the
	# tab's entry names his body instead of the bare list. Nothing in the strip changed to take it,
	# which is the one-entry contract being true rather than claimed.
	#
	# **AND IT IS WHY THE CONTROL ORDER IS RIGHT WITHOUT ME ARRANGING IT** (Maren, ASSA-241): his body
	# is headline, then `go here`, then the evidence. So the tab's only control is ABOVE its unbounded
	# list, which is Wren's fold rule, and the list is the thing free to scroll.
	#
	# NO `PANEL` FLOOR ON ANY BODY, and it was not tidying (ASSA-117 box 4, ASSA-98): a scroll box
	# hands its child the panel MINUS the scrollbar, so a 320px floor inside a ~308px viewport is
	# content wider than the box that holds it, and horizontal scrolling is off. `EXPAND_FILL` is the
	# derivation and the children inherit a `VBoxContainer`'s FILL, so no body needs a width.
	var tabs: Array[Array] = [
		["make", [_assembling, _make_toggle, _make] as Array[Control]],
		["inventory", [_carrying] as Array[Control]],
		["bench", [_bench, _halt_detail] as Array[Control]],
		["mineralogy", [_mineralogy] as Array[Control]],
	]
	# THE ROCKS LIST BECOMES THE ANSWER'S EVIDENCE, which is Maren's ruling in one line: Mineralogy is
	# this column's `rocks` with the sim's headline on top, not a fifth tab beside it. `_species` keeps
	# its name and its `_refresh_species` because it is still the same list the sim fills; what changed
	# is what it hangs under. Limpet's file documents `evidence` as the caller's to fill, and this is
	# the caller.
	_mineralogy.evidence.add_child(_species)
	# WALKING THERE IS THIS FILE'S JOB, NOT HIS. His body emits the tile the sim named and does no
	# arithmetic on it; submitting a command needs `_client`, which a tab body must never hold.
	_mineralogy.go_here_pressed.connect(_on_go_here_pressed)
	for part in tabs:
		var body := VBoxContainer.new()
		body.name = "%sBody" % String(part[0]).capitalize()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 10)
		var bodies: Array[Control] = part[1]
		for inner in bodies:
			if inner is Label:
				(inner as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(inner)
		_tabs.add_tab(String(part[0]), body)
	# **WHICH TAB OPENS ON ENTERING A WORLD: `mineralogy`, AND I CHANGED MY MIND** (mine to pick, Wren
	# 16:35 and again 18:54; Maren argued this and Wren said he shared it). I had `make`, on the ASSA-186
	# reasoning that the board asked for a crafting menu and the loop's controls are in it.
	#
	# **MAREN'S ARGUMENT IS BETTER AND IT IS ABOUT THE FIRST SCREEN, NOT ABOUT RANK: you enter a world
	# carrying nothing, so `make` opens on a refusal** -- "nothing you are carrying can be worked by
	# hand" -- while Mineralogy opens on a direction to walk. A first screen that states what you cannot
	# do teaches less than one that names a rock and offers `go here`.
	#
	# **THE CONDITION WREN PUT ON IT IS MET, WHICH IS WHY THIS IS NOW SAFE TO DO**: "if the answer is not
	# on screen by the bound, Make". ASSA-254's body is wired above, so the answer IS on screen, and the
	# sim has a sentence for every world including the ones where nothing answers -- so this tab can
	# never open on a blank.
	#
	# SELECTED BY NAME RATHER THAN BY REORDERING THE LIST: the strip's ENTRY ORDER is Wren's ruled entry
	# list (Make / Inventory / Bench / Mineralogy) and opening on the fourth is not a reason to shuffle
	# the names a player reads left to right.
	#
	# **AND IT PUTS TWO READINGS ON ASSA-88's RULING, SO I SAY WHICH ONE I KEPT** rather than let a green
	# test stand in for an answer. "The crafting menu is OPEN on first join" was made when the menu was a
	# section in a column, and it meant NOT FOLDED -- the opposite call to the event log's, because a menu
	# nobody finds is the clunk restated. Under one tabbed panel that sentence can also mean SELECTED, and
	# those two came apart the moment the board's shape arrived.
	#
	# **THE MENU IS STILL UNFOLDED** (`_show_make(true)` below is untouched), so the rule as it was made
	# still holds: open the Make tab and the rows are there, with no second press. What it no longer means
	# is "the first body you see", and it cannot: one system at a time is the ruling above it, so exactly
	# one tab has to lose this and Maren and Wren both picked which. Flagged on ASSA-247, not buried here.
	_tabs.select("mineralogy")
	#
	# **AND THE CURSOR READOUT IS A FOOTER, WHICH IS THE ONE PLACEMENT NOBODY RULED.** It is in the
	# scrolled area under whichever tab is open, so it carries no control below the fold and costs the
	# tab budget nothing. What I do not like about it, said here rather than discovered later: `do`
	# and this are both derived from the TILE, and ASSA-107's ruling is that a thing belongs with the
	# activity it is part of -- so splitting them top and bottom is the shape Maren ruled against
	# there. The alternatives cost real pixels (207px of a ~470px budget always-on) or hide a hover
	# readout behind a tab, which is a readout that does nothing while you hover. Maren's to rule on
	# the 1x shot; flagged on the item.
	_tabs.add_footer(_cursor)
	# HIDDEN ON FIRST OPEN, and this is the line the whole item is about.
	_show_log(false)
	# BOTH CHROME BLOCKS DRAWN ONCE AT BUILD, so the screen a stranger sees before any refresh is the
	# empty one. A `PanelContainer` is visible by default, and `_refresh_*` only rebuilds when the
	# shape CHANGES -- so without this the block starts visible-and-empty on the join screen, which
	# is the labelled-empty-gap defect ASSA-134 spent a whole item on.
	_refresh_halt()
	_refresh_running()
	# **AND THE EVENT LOG, FOR THE SAME REASON ONE PRESS LATER** (ASSA-186). It is folded at build and
	# its toggle is live before any join, and `_show_log` only raises the box -- so pressing (L) on
	# the join screen revealed a visible heading over NOTHING. Measured on the real screen: 0 children
	# in `_log` after the button's own `pressed`, and `_refresh_log` is below `_refresh`'s early
	# return, so no frame ever built it. **The item said this section read "nothing has happened yet"
	# before a join; that sentence came from the probe's own `_rebuild_log()` call, and the real
	# screen was the emptier defect of the two.** This is the one call that gives it its line.
	_refresh_log()
	# AND THE CRAFTING MENU IS OPEN ON FIRST JOIN, which is the opposite call for the opposite
	# reason: the board asked for a crafting menu, and a menu nobody finds is the clunk restated.
	_show_make(true)
	# THE CLOSE-UP IS THE MAIN VIEW (Maren, ASSA-119: "the scene becomes the main view; the
	# whole-world schematic survives as a second view"). Through the setter rather than by assigning
	# `_close_up`, so the toggle's own words can never disagree with what is on screen.
	_show_close_up(true)
	_refresh_make()
	_refresh_assembling()
	_refresh_pack()
	_refresh_actions()
	_refresh_bench()
	_refresh_species()
	_refresh_mineralogy()


## THE EVENT LOG'S OWN SURFACE, OVER THE MAP (ASSA-147, Maren's ruling: "the event log leaves the
## HUD column").
##
## WHAT WAS WRONG, MEASURED ON THE REAL WINDOW rather than argued: with the log open at seed 14247
## tick 519, `you` sat at y -1046..-894, `do` at y -852..-802 and `bench` at y -690..-549 -- four of
## seven sections off the top of the clip, and `do` is Mine, Stop and Assay. The log was the LAST
## section of a column 2023px tall in a 650px box, so revealing it scrolled to the bottom and
## everything above it left. ASSA-133's order was right; the consequence was still that pressing L to
## read what just happened cost you every control you had.
##
## WHY OVER THE MAP AND NOT A SECOND COLUMN OR A BOTTOM STRIP. Maren left the placement to me and
## named all three. The map is 912x672 and the window is 1280x720, so a strip under the map would
## have to come out of the map's own height -- `assay-rulings` §4 pins 32 px a tile, so that is fewer
## tiles, which is buying log space with the world. A second column would come out of the map's width
## for the same reason. The map's rectangle is the only surface this window has that is already
## PAID FOR and mostly empty ground, and a panel over it is also the honest picture of what the
## toggle does: it is a mode, which is Maren's ruling 2.
##
## THE TOP OF THE MAP, NOT THE BOTTOM, AND IT IS NOT TASTE. `_view_toggle` sits at
## `world.end - (152, 36)`, inside the map's bottom-right corner: a bottom-anchored panel would cover
## it, which is the same defect this item is about -- a control a player cannot reach because the log
## is open. The top of the map has no control in it.
##
## HEIGHT IS THE ENGINE'S ANSWER, NOT A NUMBER I WROTE. The region is exactly the map's rect and the
## box is `SIZE_SHRINK_BEGIN` inside it, so a `VBoxContainer` gives the box its content's minimum
## height at the region's top and re-does that on the frame the content changes. The alternative was
## a height constant, which would be dead space over the world when the log is short and a clipped
## newest line when it is long. MEASURED, so the bound is a fact and not a hope: fourteen lines are
## 304px and the widest line's minimum width is 1px (`AUTOWRAP_OFF` + `OVERRUN_TRIM_ELLIPSIS` takes
## the text out of a Label's minimum, which I asked the engine rather than reasoned), so the box
## wants about 350 of the 600px it may have. `window_shot.gd` fails the run if it ever leaves the
## map's rect, because that bound is the one thing here that a font change could move.
##
## AND THE LINES GET 912px INSTEAD OF 320, which is a second payoff I did not plan: an older line is
## cut to one row with an ellipsis, and in the column that ellipsis never appeared -- the row was
## simply sliced by the scroll box's clip at 320px. Three times the width is three times the sentence,
## on the surface the board called hard on the eyes.
##
## IT STOPS THE MOUSE, AND THAT IS DELIBERATE. The map is clicked through `_unhandled_input`, so a
## `MOUSE_FILTER_IGNORE` panel would let a click pass through the log onto the tile underneath it --
## placing a machine on a tile you cannot see. `STOP` means the covered tiles are not clickable while
## the log is up, which is the honest version: what you cannot see, you cannot click. The region
## itself is `IGNORE`, so the 912x672 of empty space around the box answers nothing.
func _build_log_over_the_map(world: Rect2) -> void:
	if _manifest.is_empty():
		_manifest = AssaySprites.manifest()
	_log_room = AssayScene.player_ceiling(_manifest, world.size)
	_north_room = AssayScene.north_headroom(_manifest, world.size)
	_log_region = VBoxContainer.new()
	_log_region.position = world.position
	_log_region.size = world.size
	_log_region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_region)
	_log_box = PanelContainer.new()
	_log_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# SAID RATHER THAN INHERITED. `STOP` is a Control's default, and the rule above is the reason this
	# panel has it -- a default nobody wrote down is a default somebody changes.
	_log_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_log_region.add_child(_log_box)
	var inside := VBoxContainer.new()
	_log_box.add_child(inside)
	# "event log", NOT "last tick" (Maren, ASSA-116 finding 4b/4c). Two defects in one word: the
	# switch offered an "event log" and the surface called itself something else, so even having found
	# it you would not know you had found what you asked for -- and `LOG_LINES` keeps the last
	# fourteen LINES, which span many ticks, so the old heading named a time window the content never
	# had. A heading is this client's word; the LINES in it stay the sim's (ASSA-80/93).
	#
	# IT IS INSIDE THE BOX NOW rather than being a row of the column, which is what makes "a heading
	# over nothing" impossible here: the heading cannot be on screen without the panel it is in.
	_log_heading = Label.new()
	_log_heading.text = "event log"
	_log_heading.theme_type_variation = &"Heading"
	inside.add_child(_log_heading)
	inside.add_child(_log)


## SHOW OR HIDE THE EVENT LOG (ASSA-89). The board's words were "logs are hard on the eyes", and
## this is the toggle they asked for rather than the deletion they did not.
##
## HIDDEN, NOT REMOVED, AND THE DIFFERENCE IS THE WHOLE RISK. `_events` keeps filling and the line
## Labels keep being rebuilt while this is false: the lines are all still there, one `visible` away.
## The two ways to get this wrong are `queue_free` and clearing the lines on hide, and both of them
## pass a test that only ever looks at the default state -- which is why `test_main_screen.gd`
## asserts the lines are readable WHILE the toggle is hidden, not merely that they are readable.
##
## THE HEADING GOES WITH IT, because a heading over nothing is a labelled empty gap, and a stranger
## reading an empty section assumes the game has nothing to say rather than that they hid it.
##
## THE CONTROL NAMES THE KEY, because the key is the half a stranger cannot discover.
##
## **ASSA-117'S RULED PROPERTY IS NOW TRUE BY CONSTRUCTION, WHICH IS WHY THIS FUNCTION IS SHORTER.**
## Maren's property was *a control that reveals something must leave that thing visible*, and until
## ASSA-147 this function discharged it by SCROLLING: the log was the last section of a 2023px column
## in a 650px box, so showing it meant moving the view 1120px to the bottom, one frame after the
## press because a container had not laid out yet. That mechanism is deleted. The log now has a
## surface of its own at a fixed place over the map, so revealing it moves nothing -- and nothing it
## moves can carry a control off the screen, which was ASSA-147.
##
## WHAT THIS GREEN IS NOT A STATEMENT ABOUT: the column is still taller than its box (ASSA-98's
## ~1746px in a 566px clip is unchanged, minus the log's 304px). Buttons below the fold are still
## reached by scrolling. What cannot happen any more is the TOGGLE moving them.
##
## THREE FLAGS, ONE WRITER, AND THE REASON IS NOT TIDINESS. `_log_box` is the surface a player sees;
## `_log` and `_log_heading` are inside it, so hiding the box alone would be enough on screen -- and
## would leave every test, probe and tool that asks `_log.visible` reading `true` about a log nobody
## can see. That is the exact shape of the bug ASSA-117 was: a node answering honestly about a state
## the screen does not have. So all three move together, from this one function, and
## `test_main_screen.gd` asserts they cannot drift.
func _show_log(shown: bool) -> void:
	_log_shown = shown
	_log.visible = shown
	if is_instance_valid(_log_heading):
		_log_heading.visible = shown
	if is_instance_valid(_log_box):
		_log_box.visible = shown
	_log_toggle.text = "hide the event log (L)" if shown else "show the event log (L)"


## THE SHAPE KEY'S SURFACE, OVER THE MAP, AT THE BOTTOM-LEFT (ASSA-206).
##
## THE SAME REGION TRICK AS THE LOG, THE OTHER WAY UP. `SIZE_SHRINK_END` and `SIZE_SHRINK_BEGIN`
## horizontally put the box in the map's bottom-left corner at the size the panel asks for, so the
## engine answers for the height and nothing here writes a number that a font change could falsify.
##
## BOTTOM-LEFT AND NOT BOTTOM-RIGHT, which is where both buttons are: a panel over its own toggle is
## ASSA-147's defect exactly (a control a player cannot reach because the thing it opened is on top of
## it), and the log already owns the top.
##
## IT STOPS THE MOUSE for the log's reason, which is a rule about this window and not about this
## panel: the map is clicked through `_unhandled_input`, so an `IGNORE` panel would let a click land
## on a tile the player cannot see and place a machine there. The region around it is `IGNORE`.
##
## **THE ALIGNMENT BELOW IS STATED A SECOND TIME, IN ARITHMETIC, IN `AssayHud.map_key_rect`**
## (ASSA-281) -- the status toast has to keep off this panel, and in the headless suite no container
## has laid out, so it cannot ask this node where it ended up. **If you change `ALIGNMENT_END` or
## either size flag here, change that function too**; nothing will go red if you do not, because the
## only place the two disagree is a real window.
func _build_map_key_over_the_map(world: Rect2) -> void:
	var region := VBoxContainer.new()
	region.position = world.position
	region.size = world.size
	region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	region.alignment = BoxContainer.ALIGNMENT_END
	add_child(region)
	_map_key_box.size_flags_vertical = Control.SIZE_SHRINK_END
	_map_key_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# SAID RATHER THAN INHERITED, like the log's: `STOP` is a Control's default and the rule above is
	# the reason this panel has it.
	_map_key_box.mouse_filter = Control.MOUSE_FILTER_STOP
	region.add_child(_map_key_box)
	_map_key_box.add_child(_map_key)
	_map_key_box.visible = false


## SHOW OR HIDE THE SHAPE KEY (ASSA-206).
##
## TWO FLAGS, ONE WRITER, for the reason `_show_log`'s docstring gives: `_map_key` is inside the box,
## so hiding the box alone would be enough on screen and would leave every test and tool that asks
## `_map_key.visible` reading `true` about a key nobody can see. That is ASSA-117's shape of bug.
##
## `not _close_up` IS IN BOTH PLACES ON PURPOSE. The player's intent (`_map_key_shown`) and whether
## this view is up are different facts, so pressing K in the close-up arms the key for the moment you
## press V rather than doing nothing -- and `_show_close_up` re-reads the intent instead of keeping a
## second copy of it.
func _show_map_key(shown: bool) -> void:
	_map_key_shown = shown
	_map_key.visible = shown and not _close_up
	_map_key_box.visible = shown and not _close_up
	_map_key_toggle.text = AssayHud.map_key_toggle_text(shown)
	# THE TOAST GETS OUT OF THE WAY ON THE SAME FRAME (ASSA-281). Without this the toast only moves
	# on the next tick bundle, so pressing K while the client is saying something covers the key's
	# last row for up to a tenth of a second -- and a toast sitting on the row a player just opened
	# the key to read is the defect whether it lasts one frame or a thousand.
	_place_says_toast()


## SHOW OR HIDE THE DEVELOPER'S READOUT (ASSA-237, Maren's Gap 2).
##
## **THE TEXT IS NEVER STOPPED, ONLY THE DRAWING.** `_refresh` writes `_detail.text` on every tick
## whatever this says, which is what makes F3 answer instantly with the CURRENT tick and hash instead
## of with whatever was on screen when it was last hidden. A toggle that also gated the write would be
## a toggle that lies for one tick, and the one thing this readout is for is being exact.
##
## NO TOGGLE CONTROL AND NO LEGEND: see `_unhandled_key_input`. A visible control for this would put
## the debug readout back in the player's view one press away from where it just left.
func _show_dev_readout(shown: bool) -> void:
	_dev_shown = shown
	_detail.visible = shown
	# THE TOAST GROWS AND SHRINKS WITH IT (ASSA-239): the readout is the second line in that panel, so
	# its arrival changes the panel's height and therefore where its bottom-left corner sits.
	_place_says_toast()


## SHOW OR HIDE THE CRAFTING MENU'S ROWS (ASSA-88).
##
## THE ROWS ONLY, NEVER THE RUNNING CRAFT. Maren's clause from ASSA-89 applies here as she said:
## a craft is a CONDITION, not a moment, so a line a closed menu could hide would not discharge it.
## That used to be true because `_crafting` was a sibling of this container rather than a child of
## it; since ASSA-133 the countdown is not in this column at all -- it is a line in the chrome's
## `_running` block, above the scroll -- so nothing this function can do reaches it.
##
## THE HEADING STAYS TOO, unlike the log's. "make" over a control that says what it will show is not
## a labelled empty gap; "last tick" over nothing was.
func _show_make(shown: bool) -> void:
	_make_shown = shown
	_make.visible = shown
	_make_toggle.text = AssayHud.make_toggle_text(shown)


## SWAP THE TWO VIEWS OF THE WORLD (ASSA-119). The close-up is the main one; the schematic is how you
## cross a 96x64 world.
##
## ONE RECTANGLE, ONE VISIBLE VIEW, and `_cell` keeps its meaning in both: the schematic's tile size
## is still `AssayHud.map_cell`'s pure answer, so a click lands on the tile the player sees whichever
## view is up. `_tile_under` is the single place that knows which arithmetic applies.
func _show_close_up(close_up: bool) -> void:
	_close_up = close_up
	_world.visible = close_up
	_view_toggle.text = AssayHud.view_toggle_text(close_up)
	# THE KEY IS THE SCHEMATIC'S (ASSA-206). `_show_map_key` re-reads the player's own intent, so
	# switching views cannot change whether the key is armed -- only whether this view has marks for
	# it to name.
	_show_map_key(_map_key_shown)
	_map_key_toggle.visible = _sim.running() and not close_up
	if close_up:
		_refresh_world()
	queue_redraw()


## L SHOWS AND HIDES THE LOG, M THE CRAFTING MENU. `_unhandled_key_input` and not `_input`, so a
## focused `LineEdit` eats the key first: typing "localhost" into the host field must not toggle a
## panel on the `l`, and a name with an `m` in it must not fold the menu away.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_L:
		_show_log(not _log_shown)
	elif key.keycode == KEY_K:
		# K ARMS THE KEY IN EITHER VIEW, unlike V's shortcut, and that is not an inconsistency with
		# ASSA-142's rule: V promises a view of a world that may not exist, while K only records what
		# you want to see on the schematic when you are next on it. `_show_map_key` is what decides
		# whether anything appears, and in the close-up nothing does.
		_show_map_key(not _map_key_shown)
	elif key.keycode == KEY_M:
		_show_make(not _make_shown)
	elif key.keycode == KEY_V:
		# THE SHORTCUT IS AS DEAD AS THE BUTTON IT NAMES (ASSA-142 box 3). Hiding `whole world (V)`
		# and leaving V live would keep the promise this item removes -- a player who read the key
		# off the button earlier in the session could still toggle to a view of nothing, and the
		# control that would have explained what happened is the one that is gone. Maren's rule is
		# about what the control can DO, not about where it is drawn.
		if _sim.running():
			_show_close_up(not _close_up)
	elif key.keycode == KEY_F3:
		# **F3, AND IT IS NOT NAMED ON THE SCREEN ANYWHERE** (ASSA-237). Every other toggle in this
		# client prints its key on its own control -- `show the event log (L)`, `whole world (V)` --
		# because a player cannot be expected to guess one. This one has no control and no legend, and
		# that is the difference between the two kinds of toggle: those three are features, this is an
		# instrument. A labelled control for it would put the debug readout back on the player's screen
		# one indirection later, which is the thing Gap 2 is about.
		#
		# F3 rather than a launch flag, because the readout's whole value is being able to ask a
		# RUNNING client what tick and hash it is on -- the state a flag set before the window opened
		# cannot reach. It costs a player nothing: F3 is bound to nothing else here.
		_show_dev_readout(not _dev_shown)


## **THE THREE CONTROLS NOTHING READS ANY MORE LEAVE THE SCREEN** (ASSA-175, Maren's ruling: "a
## control that cannot do anything is worse than an absent one, because it reads as available" -- the
## same ruling that took `whole world (V)` off the join screen).
##
## Measured before the fix: `_host.text` has exactly one reader (`_on_join`) and `_name.text` exactly
## one (`_join_address`), and `_join_address` returns before either is used unless the stage is IDLE
## or DEAD. So both boxes stayed editable for the whole session with nothing ever looking at them
## again, and `Play solo` stood beside them refusing.
##
## **THE PREDICATE IS THE STAGE, AND IT IS `== JOINED` RATHER THAN "WE HAVE JOINED".** That is the
## whole of Maren's second ruling and it cuts both ways:
## - CONNECTING / GREETED: the band STAYS. The refusal is true in those stages (see `join_refusal`)
##   and they last a moment.
## - DEAD: the band COMES BACK, and this is the part worth not breaking. `_join_address` permits a
##   join attempt at stage DEAD, so this band is the only reconnect affordance the client has; a
##   predicate like `_sim.running()` or a latch on the welcome would have taken it away at exactly
##   the moment a player reaches for it. Whether that reconnect works is ASSA-177, unanswered -- but
##   a control that MIGHT work is not the class this item removes.
##
## `Join` IS NOT IN THE BAND for the same reason: it is the one control in the row that can still do
## something, so it is the one that stays.
##
## HIDDEN, NOT DISABLED (Maren, same call she made on the view toggle): the screen already carries
## five "no world yet" sentences and a sixth would be noise.
##
## CALLED FROM `_process`, NOT FROM A SIGNAL. There are four ways into DEAD (`refused`, `desynced`,
## a read failure, a write failure) -- and this line said "only two of them reach a handler here"
## while `desynced` did not reach DEAD at all; ASSA-190 made that list true and the count three. It
## is still not all four, so a signal-driven hide would be a list to keep in step with
## `net_client.gd`. Asking the
## stage every frame cannot miss a transition, and `CanvasItem.set_visible` early-returns when the
## value is unchanged.
## **IT HIDES THE CELLS AND NOT ONLY THE BAND NOW, BECAUSE THEY ARE NOT ALWAYS IN IT** (ASSA-231).
## Before a world the two cells stand in `_front_door`, and a hide that only reached `_join_band`
## would be a statement about an empty box -- true, green, and about nothing. The band keeps its own
## flag because it is the in-world grouping that closes the gap before `Join`, and because
## `tools/reconnect_probe.gd` reads it as the sign the band came back after a drop.
func _refresh_join_band() -> void:
	# **AND `Join` IS UNDER THE SAME PREDICATE NOW** (ASSA-237, Maren's Gap 2: *"a `Join` button sits
	# in the top-left corner of a world you are already in"*). ASSA-175's docstring above excludes it
	# as "the one control in the row that can still do something" -- true at IDLE, CONNECTING and
	# DEAD, and FALSE at JOINED, where `_join_address` returns on its first line and the only outcome
	# a press can reach is a refusal. The stage that makes the other three dead makes this one dead,
	# so it joins the list rather than earning a rule of its own.
	var offer: bool = _client.stage != AssayNetClient.Stage.JOINED
	for control: Control in [_join_band, _solo_cell, _cred_cell, _join_button]:
		control.visible = offer


## START A RELAY OF OUR OWN AND JOIN IT (ASSA-106).
##
## THE SAME JOIN PATH ONCE THE ADDRESS IS KNOWN, which is ruling 7 in one line: solo is co-op with
## one player and a host on 127.0.0.1, so there is no second way for this client to be wrong.
##
## **AND IT DOES NOT TOUCH THE HOST BOX** (Maren, ASSA-113). It used to do `_host.text = address`
## before joining, which meant pressing Play solo silently ERASED whatever the player had typed --
## the one genuinely confusing bug in reach here, and I shipped it in ASSA-106 with a docstring
## defending it. The address now reaches `_join_address` directly, so Play solo neither reads the box
## nor writes it.
func _on_play_solo() -> void:
	if _client.stage != AssayNetClient.Stage.IDLE and _client.stage != AssayNetClient.Stage.DEAD:
		# THE SENTENCE NAMES THE STAGE WE ARE ACTUALLY IN (ASSA-176). Unreachable by mouse once
		# ASSA-175 hides this button in a world -- and still fixed, because "the control is gone" is a
		# reason a wrong sentence is not SEEN, not a reason it is not wrong.
		_say(AssayHud.join_refusal(_client.stage == AssayNetClient.Stage.JOINED,
				"restart the client to start a world of your own"), AssayHud.Say.FAILED)
		return
	if _solo != null:
		_say("already starting a world of your own", AssayHud.Say.CONNECTING)
		return
	_solo = AssaySoloRelay.new()
	if not _solo.start_solo():
		# NO REFUSAL IS SILENT (ruling 6) and the sentence is the one `AssaySoloRelay` composed,
		# which names WHICH refusal this is -- a missing binary lists where it looked, a binary the
		# system will not run names itself.
		_say(_solo.failure, AssayHud.Say.FAILED)
		_solo = null
		return
	_say("starting a world of your own…", AssayHud.Say.CONNECTING)


## WAIT FOR THE RELAY TO SAY IT IS LISTENING, one frame at a time.
##
## IN `_process` AND NOT IN `_refresh`, because `_refresh` runs on tick bundles and there are no
## bundles until we have joined -- polling there would wait for the thing it is waiting to start.
func _process(delta: float) -> void:
	# **THE PROBE STEPS FIRST, AND THE ORDER IS THE MEASUREMENT** (ASSA-211). `_refresh_world` below
	# publishes the rectangle the probe reads, so stepping afterwards would hand it a rectangle from
	# THIS frame where the dev tool's SceneTree loop reads one from the PREVIOUS frame -- measured age
	# 0.99-1.01 frames over six Windows runs. #284's verdict divides by the previous frame's delta
	# precisely because of that one-frame phase, so sampling in the other phase would silently invert
	# the fix and charge the client for the instrument again. Stepping above the publish keeps both
	# drivers in the same phase, and the report states the age it measured so the claim is checkable
	# rather than asserted: a run whose age came out near 0 would be this comment being wrong.
	if _motion_probe != null:
		_step_motion_probe(delta)
	# THE SCENE IS THE ONLY THING ON THIS SCREEN THAT MOVES BETWEEN TICKS, so it is the only thing
	# that redraws per frame: a body tweening between two tiles the sim produced, and two gaits
	# running off the wall clock. The schematic does not redraw here -- it is painted when a tick
	# lands, which is every state it has.
	#
	# **AND THE FRAME'S OWN DELTA GOES WITH IT** (ASSA-197). This used to be `_delta`, thrown away,
	# and the playout clock moved the body by its own `Time.get_ticks_msec()` readings instead. Two
	# things were wrong with that and both are visible in a real window: the reading is quantised to
	# a millisecond, which is 9% of a 90 fps frame and therefore 9% of the body's drawn speed; and
	# the interval it measures runs between the clock's own advance instants, which are not the
	# frame boundaries, so the movement published in a frame was sized for a different interval than
	# the one the frame was shown for. Measured: on runs where frame time was steady the drawn speed
	# was inside the bar 95% of the time, and on runs where it varied 11-28 ms it fell to 82-86%,
	# with the failing frames alternating too-fast and too-slow in pairs.
	if _close_up and _sim.running():
		_refresh_world(delta)
	# ABOVE THE EARLY RETURN BELOW, which is about the solo relay and skips most frames of a session.
	_refresh_join_band()
	if _solo == null:
		return
	# **AND THE RELAY'S PIPES ARE DRAINED ABOVE THAT RETURN TOO, FOR THE WHOLE SESSION** (ASSA-219).
	#
	# THIS LINE IS THE FIX, AND THE GUARD BELOW WAS THE BUG. It read `or _solo.address != ""`, so on
	# the very frame the relay said where it was listening this screen stopped talking to it -- and
	# `sim-relay` prints a line per submitted command into a pipe with nobody at the other end. Around
	# two thousand lines later (measured: 2385 on this Mac, and SMALLER on Windows, where anonymous
	# pipes can be 4 KB) the pipe is full, the relay's `println!` blocks inside its own tick loop, and
	# the world stops for good. `poll()` had a matching early return of its own, so fixing
	# only that one would have changed nothing a player could feel: the call never happened.
	#
	# UNCONDITIONAL ON PURPOSE. There is no state of a started relay in which not reading its output
	# is correct, so there is no condition here to get wrong later.
	var was_waiting := _solo.address == "" and _solo.failure == ""
	_solo.pump()
	# AND THE JOIN STILL HAPPENS ONCE. `was_waiting` is read before the pump because an address that
	# arrives in it must be acted on in this frame and in no later one -- `_join_address` is not a
	# question, it opens a socket.
	if not was_waiting:
		return
	if _solo.poll():
		_join_address(_solo.address)
	elif _solo.failure != "":
		_say(_solo.failure, AssayHud.Say.FAILED)


## THE RELAY WE STARTED DIES WITH US (ruling 4). An orphan holding a port is the kind of mess a
## player cannot clear up without a terminal, which is the whole thing this feature exists to avoid.
##
## BOTH NOTIFICATIONS, because they are different events and only one of them is the window's X:
## `WM_CLOSE_REQUEST` is the close box, `PREDELETE` covers the scene being torn down (which is how
## every test and probe ends). A relay left running by a test run would hold a port for the next one.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_solo_relay()


## Stop the relay this client started, if it started one. Safe to call twice.
func stop_solo_relay() -> void:
	if _solo != null:
		_solo.stop()
		_solo = null


## **ONE FRAME OF THE PROBE, THEN THE FILE, THEN OUT** (ASSA-211). The counterpart of
## `AssaySelfCheck.run`: the measuring is the probe's, the window and the frames are this screen's, and
## writing a file and quitting is a host's job and never the sim's or the measurement's.
##
## **A FILE THAT COULD NOT BE WRITTEN EXITS NON-ZERO AND SAYS WHICH PATH** -- the whole ask is "send me
## the text file", so a run that measured perfectly and saved nothing is a failed run. `push_error` as
## well as the line, because on an exported build stdout is often nobody's terminal.
func _step_motion_probe(delta: float) -> void:
	if _motion_probe.step(delta) == AssayMotionProbe.Status.RUNNING:
		return
	var code := _motion_probe.exit_code()
	var out := FileAccess.open(_motion_probe_path, FileAccess.WRITE)
	if out == null:
		push_error("the motion probe could not write %s (error %d)"
				% [_motion_probe_path, FileAccess.get_open_error()])
		code = 1
	else:
		out.store_string(_motion_probe.report_text())
		out.close()
		print("motion probe report written to %s" % _motion_probe_path)
	_motion_probe = null
	get_tree().quit(code)


## THE JOIN BUTTON: the address is whatever is in the box, and only this path reads the box.
func _on_join() -> void:
	_join_address(_host.text)


## JOIN ONE ADDRESS. The only caller that reads `_host` is `_on_join`; solo passes the address its
## own relay reported, which is what keeps a typed host untouched (Maren, ASSA-113).
##
## **`DEAD` IS A DOOR, NOT A WRECK, AND NOW THAT IS MEASURED RATHER THAN TOLERATED** (ASSA-177). The
## `or DEAD` below is the whole of this client's reconnect: `tools/reconnect_probe.gd` kills a real
## relay under a real session and presses this path, and the player is back in the same `PlayerId`
## with the world stepping -- after a host restart and after the socket alone dying. Narrowing this
## guard to IDLE would delete a working feature nobody wrote down.
func _join_address(address: String) -> void:
	if _client.stage != AssayNetClient.Stage.IDLE and _client.stage != AssayNetClient.Stage.DEAD:
		# ASSA-176, and this is the site that matters: `Join` is the control ASSA-175 deliberately
		# leaves on screen, so this is the sentence a joined player gets when they press the one thing
		# still there.
		#
		# **AND THE REMEDY LOST A FALSE CLAUSE** (ASSA-177). It used to read "(no reconnect in the
		# demo)", which I shipped on ASSA-176 saying out loud that I believed it and had not measured
		# it. The probe says it is false. What is left is true in both stages this sentence can reach:
		# while a handshake is in flight or while you are in a world, changing host does take a
		# restart, because this is the guard that says so.
		_say(AssayHud.join_refusal(_client.stage == AssayNetClient.Stage.JOINED,
				"restart the client to change host"), AssayHud.Say.FAILED)
		return
	# SAID BEFORE THE CALL, not after it: `join` does reach a socket, and a button that shows nothing
	# until the answer comes back reads as a dead button. Maren's ruling, and she had the premise
	# slightly wrong -- `join` already emits a "connecting to ..." note of its own -- but only on the
	# path where `connect_to_host` succeeds, so this is the line that is true either way.
	_say("connecting to %s…" % address, AssayHud.Say.CONNECTING)
	_client.join(address, _name.text if _name.text != "" else "player")


## **A REFUSAL TAKES THE DESTINATION MARK WITH IT** (ASSA-215, Maren's box 4). This was a one-line
## lambda that only said the sentence; the mark is the reason it is a method now.
##
## WHY THE MARK GOES ON ANY REFUSAL AND NOT ONLY A REFUSED WALK. The signal carries a reason STRING
## and no command, so "was that my walk?" would have to be decided by matching prose -- which is the
## shape of bug this file has been bitten by twice (a sentence test that passed off the digits in an
## unrelated message). An unrelated refusal clearing the mark costs a mark the player can re-ask for
## with one click; a refused WALK keeping its mark is the game promising to go somewhere it has
## already declined to go. Of the two wrong answers, this is the honest one, and it is still strictly
## better than before, where a refused walk and an accepted one looked identical for a quarter second.
func _on_refused(reason: String) -> void:
	_say("refused: %s" % reason, AssayHud.Say.FAILED)
	_session_ended()


## **EVERY WAY A SESSION ENDS GOES THROUGH HERE, AND THERE ARE TWO OF THEM** (ASSA-251).
##
## `net_client` has two exits and they are different signals: `Refused` sets `Stage.DEAD` and emits
## `refused` (the host said no), while `_fail` sets `Stage.DEAD` and emits `link_failed` (the host
## went away -- a closed socket, or the silence timeout). I put the action-row rebuild on
## `link_failed` first and my own test still failed, because the test drops the link the way the
## existing suite does: with a `Refused` frame, down the OTHER path.
##
## **SO IT IS ONE FUNCTION RATHER THAN A LINE IN TWO HANDLERS.** A third exit added later gets this
## by calling it, instead of being the route that quietly keeps a green button. That is the same
## mistake as ASSA-219 and ASSA-225 -- a correct fix sitting where the event does not pass -- and it
## is the third time this week, so the structure changes rather than the line being copied.
##
## WHAT THE REBUILD IS FOR: `_refresh_actions` gates `Mine`'s accent on there being a session, and it
## otherwise runs only from `_refresh`, which runs on tick bundles. A dropped link is exactly the
## state where no bundle will ever arrive again, so without this the button keeps the green it had on
## the last tick before the host went away.
##
## **A DESYNC COMES HERE NOW, AND THIS COMMENT USED TO SAY IT DELIBERATELY DID NOT** (ASSA-190). It
## read: "`desynced` leaves the stage at JOINED, so `Mine` stays accented there. Whether a desync
## should also grey it is a question about what a desync IS, and it is not this item's to answer."
## The answer is that a desync ends the session -- `net_client.gd` hangs up on it -- so there are
## three routes into here, and `Mine` greys for the same reason it does on a drop: no bundle will
## ever confirm a swing at a world we have stopped trusting.
func _session_ended() -> void:
	_forget_click()
	# **AND THE SELECTION GOES WITH THE WORLD IT WAS MADE IN, WHICH IS A BUG THAT PREDATES THIS
	# LINE** (found building ASSA-276 move 4). `_targeted` is set by a right-click and was never set
	# back to `false` anywhere, so after a session died and the player pressed Join, `_target_tile()`
	# still answered a tile picked in the PREVIOUS world -- and Mine, Assay, Place and Pick up all
	# read it. That is not cosmetic: it is the buttons acting on somewhere the player never chose.
	#
	# **I AM FIXING IT HERE RATHER THAN FILING IT because move 4 draws this state**, and shipping a
	# mark that paints a stale tile in a fresh world would turn an invisible wrong answer into a
	# visible one and call it a feature. The schematic has had the same stale mark since ASSA-119
	# and nobody saw it, which is the whole argument of ASSA-198 in one variable.
	#
	# IT COSTS A RECONNECTING PLAYER THEIR SELECTION. A rejoin lands in the same slot (ASSA-177), so
	# this clears something that would sometimes still have been right -- one right-click to remake,
	# against a button that acts on the wrong tile. Say so rather than pretend the trade is free.
	_targeted = false
	_world.selection = null
	_refresh_actions()


## A DEAD LINK ABANDONS THE CLICK TOO, and this one is mine rather than Maren's (ASSA-215). The walk
## is not refused here, it is unanswerable: the host is gone, so nothing will ever confirm or arrive.
## Left alone the bracket sits over a frozen world and then over the NEXT session, because pressing
## Join rejoins the same slot (ASSA-177) and an unconfirmed echo has nothing to clear it.
func _on_link_failed(reason: String) -> void:
	# **AND IF THE HOST THAT DIED WAS OURS, IT GETS TO SAY WHY** (ASSA-225). Nerite killed a relay
	# under a joined client and got "127.0.0.1:53794 closed the connection" and nothing else: true,
	# and useless, because a socket closing is the one thing a player can already see. The relay's own
	# last words are the only part of this report that is not our guess about it.
	#
	# ONLY FOR A RELAY WE STARTED. Someone else's host dying is not ours to explain and we have no
	# pipe to it, so `last_words_if_it_died()` answers "" and the sentence is unchanged -- which is
	# every case except Play solo.
	var said := "" if _solo == null else _solo.last_words_if_it_died()
	_say(reason if said == "" else "%s It said: %s" % [reason, said], AssayHud.Say.FAILED)
	# THE OTHER EXIT (ASSA-251). See `_session_ended`: the action row has to be rebuilt when a
	# session dies, and this is one of the two routes that can kill one.
	_session_ended()


## **THE WORLDS DIVERGED, AND THAT IS NOT A CONNECTION FAILURE** (ASSA-190).
##
## A handler rather than a lambda because it does three things now, and because the one thing a
## player in this state is owed is a sentence they can act on plus the evidence they cannot get
## anywhere else: the host's hash does not exist on this client until the `Desync` message carries it
## (protocol 10).
##
## **IT NEVER READS AS A DROPPED CABLE.** `_on_link_failed`'s sentences are about a socket; this one
## is about two worlds disagreeing, and the difference matters because a determinism bug that reads
## as a network problem is the one class of bug we cannot afford to mistake. The hashes are quoted
## rather than summarised for the same reason the F3 readout exists -- they are the only thing that
## tells you which of the two builds to go and look at.
##
## `_session_ended` for `_on_link_failed`'s reason: the link really is gone (we hung up), so the
## click is unanswerable and `Mine`'s accent has to go with it. This used to be the comment on
## `_session_ended` saying a desync deliberately did NOT come here, because a desync left the stage
## at JOINED. It does not any more.
func _on_desync(tick: int, reported: String, expected: String) -> void:
	_say(("the worlds diverged at tick %d: we hashed %s, the host has %s. The link is closed; "
			+ "press Join to rebuild this world from the host's.")
			% [tick, reported, expected], AssayHud.Say.FAILED)
	_session_ended()


## THE CLICK ECHO GOES, THROUGH THE SAME FUNCTION THE REFRESH USES. Two callers, one derivation --
## a `_walk_echo = {}` here would be a third place that knows what the mark means.
func _forget_click() -> void:
	_walk_echo = AssayScene.walk_echo(_walk_echo, null, null, true)
	_world.destination = null
	_world.queue_redraw()


## THE RAW TEXT GOES TO THE SIM, the dictionary does not. By the time a `Welcome` is a Godot
## Dictionary its numbers have been through a double, so the world is built from the bytes.
func _on_welcomed(player: int, _world: Dictionary, raw: String) -> void:
	if not _sim.start(raw):
		_say("joined as player %d, but cannot simulate: %s" % [player, _sim.fail_reason],
				AssayHud.Say.FAILED)
		_refresh()
		return
	_say("joined as player %d" % player, AssayHud.Say.JOINED)
	# NO HISTORY YET AND THAT IS THE RIGHT STATE: everyone is drawn standing where the Welcome put
	# them, with nothing tweening, because the sim has produced exactly one position for each of them.
	_remember_positions()
	_refresh()
	queue_redraw()


## One tick: step the world, then report a hash if one is owed.
##
## The hash is the whole point of being a lockstep peer -- it is how the relay tells us our world has
## drifted instead of letting us play a different game quietly. The message is written in Rust
## because its `hash` is a `u64`; see `protocol.gd`.
func _on_tick_bundle(_tick: int, _inputs: Array, raw: String) -> void:
	var report := _sim.apply(raw)
	# Counted on the SEND, not on the produce: a report that never left is a report the relay never
	# checked, and the status line would be claiming a check that did not happen.
	if report != "" and _client.send_text(report):
		_hashes_sent += 1
	_remember_events()
	_remember_positions()
	_refresh()
	queue_redraw()


## What the tick we just applied did, kept where it can be read. The sim holds only the newest tick's
## events, so a line not copied out here is gone a tenth of a second later.
## **NO `tick N ·` PREFIX, AND THAT IS A RULING NOT A TIDY-UP** (ASSA-222, Maren: *"drop the `tick N
## ·` prefix: the log is already in order, newest last, and a tick is the inspector's clock, not a
## player's"*). This appended `"%d · %s"` and Nerite read the result at 1x as **"292 ·"** — a number
## a player cannot interpret, in front of every line, on the surface the board called *hard on the
## eyes*. Order is already carried by position, and `_log_row`'s dimming reads age by index, not by
## parsing this. Nothing anywhere splits on it: the repo has no `split(" · ")`.
##
## **THE OTHER TWO CLAUSES HAVE LANDED AND THEY ARE NOT HERE EITHER** (ASSA-222 slice 2). This said
## they "need `sim::debug::event_line` to take an audience" and "the sim half waits for a wake-up
## that can afford the Rust gate" — both were true when written and the second is now stale, which
## is the ASSA-174 shape with no constant to catch it. `event_line` takes an audience now, this host
## passes `Audience::Pointed`, and the lines arriving below already name the building and carry no
## bare id.
##
## **NOTHING IN THIS FILE CHANGED FOR IT, AND THAT IS THE DESIGN HOLDING.** The client does not
## reword the sim; `sim-cli` keeps the id because `Take`/`Pickup` take a `BuildingId` and typing it
## is how text play works. Where this host's one word is chosen is `AssaySim::describe`, guarded by
## `sim-godot`'s `this_client_describes_events_to_a_reader_who_points` — nothing in `sim/tests` can
## see which audience we pass, so flipping it would otherwise be silent.
func _remember_events() -> void:
	for line in _sim.event_lines(_client.player_id):
		_events.append(line)
	_events = AssayHud.trimmed_log(_events, LOG_LINES)
	# WHAT A HIDDEN LOG MAY NOT SWALLOW (ASSA-89). The sim says which lines those are
	# (`sim::debug::event_needs_attention`) and these are the SAME SENTENCES, word for word -- a
	# subset of the log, mapped through the same describer. The client does not decide how loud a
	# line is by reading it, because the wording moved thirteen times in one afternoon on ASSA-67 and
	# a classifier made of string matches would have gone quiet without a test going red.
	#
	# NOT CONDITIONAL ON THE TOGGLE. A refusal belongs on the always-visible line whether or not the
	# log is open, and a notice that only fired while hidden would be a notice whose test passes or
	# fails on the state of a different control.
	#
	# THE NEWEST ONE WINS. The surface holds one line; events arrive in the order the sim emitted
	# them, so the last is the most recent thing that did not happen.
	var notices := _sim.attention_lines(_client.player_id)
	if not notices.is_empty():
		_say(notices[notices.size() - 1], AssayHud.Say.FAILED)


## THE EVENT LOG, NEWEST FIRST AND BRIGHTEST FIRST (ASSA-117, box 1).
##
## SAME SIGNATURE RULE AS EVERY OTHER SECTION: fourteen Labels are not rebuilt ten times a second,
## and the lines themselves are the signature -- if the text is identical so is the block.
func _refresh_log() -> void:
	var shape := "\n".join(_events)
	if shape == _log_showing:
		return
	_log_showing = shape
	_rebuild_log()


## NEWEST AT THE TOP, AND IT IS A DECISION RATHER THAN A HABIT.
##
## ASSA-117 box 3 grants ordering as presentation ("dimming and ordering are presentation,
## re-phrasing is a second vocabulary"), so this is mine to make and Maren's to overrule in one
## sentence. The argument is the fold and it is measured, not taste: this section is the LAST in a
## column that reports 2023px of content in a 720px window, so its bottom edge is the first thing
## the window cuts off. Oldest-first puts the fourteenth-newest line at the top and spends the
## surviving rows on the lines that matter least. Newest-first means that whatever height the
## section is given, the lines you keep are the newest ones.
##
## AND IT MAKES BRIGHTNESS AND POSITION AGREE: the line you reach first is the line that is most
## legible, instead of the eye having to travel to the bottom to find the bright one.
##
## **THE CLAUSE IN THIS PARAGRAPH FIRED, SO THE DECISION IS RE-MADE HERE.** It used to read
## *"chronology survives because every line already carries its tick (`_remember_events` prefixes
## `%d · `) ... and if the tick prefix ever goes, this decision has to be made again"*. It went
## (ASSA-222 slice 1, Maren: *"a tick is the inspector's clock, not a player's"*), and the sentence
## sat here for three merges describing a prefix that no longer exists -- the ASSA-174 shape, in a
## repo that reads its own prose as fact.
##
## **RE-MADE, AND IT COMES OUT NEWEST-FIRST AGAIN.** The fold argument is untouched: this section is
## still the last in a column reporting 2023px of content into a 720px window. What carried direction
## is now the RAMP rather than a number in the text -- the brightest line is the newest and it is the
## one at the top, so position and brightness say the same thing instead of one of them standing in
## for a tick. What is genuinely lost is reconstructing the order from the words alone, which was
## exactly the trade Maren made -- and it is about to be the whole of it: the only other tick on this
## screen is `_detail`'s (`_render_detail`), which ASSA-237 puts behind F3, and the status line only
## carries one in the moment after a command. So the ramp is not one cue among several; soon it is
## the only one. Ordering is presentation, so this is mine to make and hers to overrule in one
## sentence (ASSA-117 box 3) -- and if the ramp ever goes, this decision has to be made again.
##
## THE INKS COME OUT OF THE THEME, NEVER OUT OF THIS FILE. `get_theme_color` asks the theme actually
## in force (`gui/theme/custom`, ASSA-116), so Maren's corrected ruling 3 holds by construction: the
## client gains no 22nd `Color` literal, and a palette change in `tools/build_theme.gd` moves this
## ramp with it. `build_theme.gd` refuses to write a theme whose own inks miss WCAG AA on its
## surface, and the ramp is the straight segment between them, so no step on it can be unreadable.
func _rebuild_log() -> void:
	_clear(_log)
	if _events.is_empty():
		# WHICH KIND OF EMPTY -- AND THERE ARE TWO OF THEM (ASSA-186). A blank section reads as a game
		# with nothing to say; in a world this one says the world has not spoken yet, and on the join
		# screen that a world is what it is missing. Same reason the pack and the bench name theirs.
		_log.add_child(_note(AssayHud.quiet_log_line(_has_world())))
		return
	var ink := _log.get_theme_color(&"font_color", &"Label")
	var muted := _log.get_theme_color(&"font_color", &"Muted")
	# THE OLDEST LINES ARE WHAT THE PLAYER'S OWN BODY COSTS (ASSA-156), and ASSA-117 box 3 is the
	# argument rather than my preference: newest-first was ruled so that "whatever height the section
	# is given, the lines you keep are the newest ones". This is that height arriving. The ramp is
	# over the lines actually drawn, so the oldest one on screen is still the dimmest.
	var count := mini(_events.size(), _log_lines_that_fit())
	for age in count:
		# `_events` is oldest-first (`trimmed_log` keeps the tail), so age 0 is the LAST entry.
		#
		# **OFF `_events.size()` AND NOT OFF `count`, SINCE ASSA-156.** They were the same number
		# until the panel got a height bound, and `count - 1 - age` with a count of 8 and fourteen
		# events starts at the EIGHTH-oldest line and walks away from the newest -- a log showing
		# older lines in newest-first order, which reads as correct and is the one defect this loop
		# can have. The newest line is `_events`' last entry whatever the room allows.
		var line := _note(_events[_events.size() - 1 - age])
		# ONE ROW EACH, AND THE NEWEST WHOLE (Maren's ruling, ASSA-117 box 8). Age 0 keeps the
		# wrapping `_note` gives every other readout; everything older is cut to the width it has.
		if age > 0:
			_cut_to_one_row(line)
		# A FONT COLOUR OVERRIDE, NOT `modulate`. `modulate` multiplies whatever the theme chose, so
		# the colour a line ends up drawn in would depend on two things and a contrast test could
		# only ever check one of them. This states the colour, and `get_theme_color` reads it back --
		# which is how `test_main_screen.gd` asserts the ramp off the engine instead of off my
		# arithmetic.
		line.add_theme_color_override(&"font_color",
				AssayHud.log_line_color(age, count, ink, muted))
		_log.add_child(line)


## HOW MANY LOG LINES THE ROOM ABOVE THE PLAYER HOLDS (ASSA-156). The sum is
## `AssayHud.log_lines_that_fit`; every term in it is asked of the engine here.
##
## EVERY THEME LOOKUP NAMES ITS TYPE, and that is not style. These nodes are built inside
## `SceneTree._initialize` in the suite and in every probe, where `is_inside_tree()` is false, and a
## variation chain does not resolve off the tree: measured in `tools/log_room_probe.gd`, the heading
## answers `font_size` 13 (the plain `Label` default) without the type and 15 with it -- a 4px error
## per panel, in the direction of a panel taller than it measured. Naming the type is what makes the
## headless number and the window's number the same number.
##
## THE NEWEST LINE IS MEASURED WRAPPED, through the TextServer at the width the panel will give it,
## because it is the one line that keeps its wrapping (ASSA-117 box 8) and a Label's own minimum
## height does not know its width yet.
func _log_lines_that_fit() -> int:
	if _log_room <= 0.0 or _events.is_empty() or not is_instance_valid(_log_box):
		return LOG_LINES
	var style: StyleBox = _log_box.get_theme_stylebox(&"panel")
	var pad := Vector2.ZERO
	if style != null:
		pad = Vector2(style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT),
				style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM))
	var font: Font = _log.get_theme_font(&"font", &"Label")
	var size := _log.get_theme_font_size(&"font_size", &"Label")
	if font == null:
		return LOG_LINES
	var head: Font = _log_heading.get_theme_font(&"font", &"Heading")
	var head_size := _log_heading.get_theme_font_size(&"font_size", &"Heading")
	var inside: Control = _log_box.get_child(0)
	var chrome := pad.y + float(inside.get_theme_constant(&"separation"))
	if head != null:
		chrome += head.get_height(head_size)
	# **AND THE AIR ABOVE THAT HEADING, WHICH THE FONT DOES NOT KNOW ABOUT** (ASSA-224). `Heading`
	# now carries a stylebox with a top margin, so a heading occupies more height than
	# `get_height()` reports -- and this function decides how many log lines fit. Measuring the
	# heading by its font alone was exactly right until the margin existed, and would now
	# over-count the room by `HEADING_AIR` and let the log run past the bottom of its box.
	var head_style: StyleBox = _log_heading.get_theme_stylebox(&"normal", &"Heading")
	if head_style != null:
		chrome += head_style.get_margin(SIDE_TOP) + head_style.get_margin(SIDE_BOTTOM)
	var newest := font.get_multiline_string_size(_events[_events.size() - 1],
			HORIZONTAL_ALIGNMENT_LEFT, AssayHud.world_rect().size.x - pad.x, size).y
	return AssayHud.log_lines_that_fit(_log_room, chrome, newest,
			font.get_height(size) + float(_log.get_theme_constant(&"separation")), LOG_LINES)


## WHAT HAS STOPPED (ASSA-117, box 2). The sim's standing answer, `sim::debug::halt_lines` through
## `AssaySimHost.halt_lines()` (Marlow, ASSA-94): every building that has stopped, one line each,
## worst-placed first in placement order.
##
## RENDERED VERBATIM AND NEVER SORTED. The order is the sim's and the sentence is the sim's -- this
## block decides that the lines are on screen and nothing else about them.
##
## EMPTY MEANS NOTHING IS DRAWN AT ALL, not a reassuring line. `halted_table` has a "nothing has
## stopped" sentence for the terminal and it is right there, but a panel that permanently says
## nothing is wrong is furniture competing with the world (Maren's one-screen target), and this block
## has to cost zero pixels when it has nothing to say or it cannot be pinned above the scroll.
func _refresh_halt() -> void:
	var lines := _sim.halt_lines() if _sim != null else PackedStringArray()
	var summary := _sim.halt_summary() if _sim != null else ""
	var shape := _halt_shape(summary, lines)
	if shape == _halt_showing:
		return
	_halt_showing = shape
	_rebuild_halt(lines, summary)


## **WHAT THIS BLOCK IS SHOWING, AS ONE STRING, AND THE SUMMARY IS PART OF IT** (ASSA-94). Split out
## for `_rebuild_halt`'s reason: the suite cannot reach a world with a stalled building in it, so a
## hazard that lives inside `_refresh_halt` is a hazard nothing can hold me to.
##
## **THE HAZARD IT EXISTS FOR.** The count is "N of M buildings stopped", so M moves when a building
## is PLACED -- and placing a WORKING building changes nothing about which buildings are stopped. "1
## of 2" and "1 of 3" therefore carry identical `lines`, and a shape made of the lines alone would
## compare equal, skip the rebuild and leave the old total on screen. The number the Game Director
## ruled must always be stated would be quietly wrong, which is worse than absent.
func _halt_shape(summary: String, lines: PackedStringArray) -> String:
	return summary + "\n" + "\n".join(lines)


## THE BLOCK, FROM LINES. Split from `_refresh_halt` so a test can drive the drawing without a world
## that has a stalled building in it.
##
## AND A REAL ONE HAS NOW BEEN SEEN, which I did not expect and had written the opposite of here.
## `tools/window_shot.gd` plays the demo loop, and the loop PLANTS a machine on ground with no
## deposit under it -- `MachineState::Idle`, which `halted()` reports for a machine precisely because
## idle means "planted somewhere it cannot work". So the 2026-10-03 shots carry this block drawn from
## a live `halt_lines()`: "machine 1 at (71, 38) · idle: no deposit underneath", the sim's sentence,
## pinned above the scroll. The suite still cannot reach it -- `button_play.gd` can, and that is the
## path a test would take (`test_buttons.gd:300` is where the chain was last declined).
func _rebuild_halt(lines: PackedStringArray, summary := "") -> void:
	_clear(_halt)
	_clear(_halt_detail)
	_halt_lines = null
	if is_instance_valid(_halt_box):
		_halt_box.visible = not lines.is_empty()
	# EMPTY IS EMPTY IN BOTH PLACES, and the bench tab's list is hidden rather than left as a bare
	# heading: a `bench` tab carrying the word "stopped" over nothing is the labelled-empty-gap defect
	# ASSA-134 spent a whole item on, and it would be there on every screen where nothing has stalled.
	_halt_detail.visible = not lines.is_empty()
	if lines.is_empty():
		return
	# **THE MACHINES, IN THE `bench` TAB** (Maren, 17:22 UTC 2026-10-06). Built before the pinned
	# count, from the same `lines`, so there is no path that draws one and not the other.
	#
	# "stopped" IS THIS CLIENT'S HEADING, exactly as "running" is in `_rebuild_running`, and for the
	# same reason: the lines under it are the sim's words and the one word above them is the column's
	# own furniture. NOT `summary` again -- that sentence is pinned four inches above this list, and
	# printing it twice would be two copies of one claim that a later change could let drift apart.
	var detail_heading := Label.new()
	detail_heading.text = "stopped"
	detail_heading.theme_type_variation = &"Heading"
	_halt_detail.add_child(detail_heading)
	var detail_rows := VBoxContainer.new()
	detail_rows.add_theme_constant_override("separation", 2)
	_halt_lines = detail_rows
	_halt_detail.add_child(detail_rows)
	for line in lines:
		detail_rows.add_child(_note(line))
	# **THE HEADING IS THE SIM'S COUNT, AND THE COMMENT THAT USED TO BE HERE WAS RIGHT ABOUT THE
	# DANGER AND WRONG ABOUT THE FIX** (ASSA-94). It read: *"a count would be a second claim about the
	# world and the sim already makes it (`halted_table`'s 'N of M buildings stopped') -- one this
	# block would have to keep true."* The objection holds for a client that COUNTS -- that is the
	# ASSA-43/52 shape exactly -- and the conclusion does not follow, because the answer was never to
	# count. It was to read the sentence the sim was already composing, which is now `halt_summary`.
	#
	# **AND THIS BLOCK COULD NOT HAVE COUNTED IT ANYWAY.** The ruled total is "N of M", and M -- how
	# many buildings exist -- is not in `halt_lines` at all. `lines.size()` is N on its own.
	#
	# THE GAME DIRECTOR'S RULING: the count is the floor and must never truncate; the reasons are the
	# extra and are bounded by the column's height. So the number lives in the HEADING, which is
	# pinned, and the reasons below it are what a short column drops.
	# **AND THE PINNED BLOCK IS THIS ONE LINE.** The count was always the floor Maren ruled must never
	# truncate; what has changed is that it is now the whole of what is pinned, because the reasons
	# below it were the unbounded half. One `Heading` Label, the sim's own sentence, and the tab that
	# holds the machines is one press away and named on screen.
	var heading := Label.new()
	heading.text = summary if summary != "" else "stopped"
	heading.theme_type_variation = &"Heading"
	_halt.add_child(heading)


## WHAT IS RUNNING, the same shape as `_refresh_halt` and for the same reason (ASSA-133 ruling 1,
## ASSA-95's list). Rebuilt only when the set of sentences changes, so the assay's countdown moves
## the block every tick it is running and nothing else does.
func _refresh_running() -> void:
	var lines := PackedStringArray()
	if _sim != null and _client != null:
		lines = _sim.activity_lines(_client.player_id)
	var shape := "\n".join(lines)
	if shape == _running_showing:
		return
	_running_showing = shape
	_rebuild_running(lines)


## THE BLOCK, FROM LINES. Split from `_refresh_running` so a test can drive the drawing without a
## world in which something is being mined, assayed or crafted.
##
## EMPTY IS EMPTY: no heading, no "nothing running", zero pixels. A window with nothing running and
## nothing stopped looks exactly as it did before this item, which is most windows.
func _rebuild_running(lines: PackedStringArray) -> void:
	_clear(_running)
	_running_lines = null
	if is_instance_valid(_running_box):
		_running_box.visible = not lines.is_empty()
	if lines.is_empty():
		return
	# "running" IS THIS CLIENT'S HEADING, beside "stopped"; the lines under it are the sim's words.
	# No count and no ordering of our own -- `activity_lines` is already in `step`'s system order and
	# a host that sorted it would be ranking a player's own activities.
	var heading := Label.new()
	heading.text = "running"
	heading.theme_type_variation = &"Heading"
	_running.add_child(heading)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	_running_lines = rows
	_running.add_child(rows)
	for line in lines:
		rows.add_child(_note(line))


func _say(line: String, level: int) -> void:
	_base_line = line
	_base_level = level
	# WHEN, IN THE WORLD'S OWN CLOCK, so `_age_the_saying` can let a healthy line go. -1 while there is
	# no world: a sentence said during the handshake has no tick to be older than, and it is cleared by
	# the world arriving rather than by ageing.
	_said_at_tick = _sim.tick() if _sim != null else -1
	_render_status()
	print(line)


## **A HEALTHY SENTENCE GETS A MOMENT AND THEN THE SCREEN GOES QUIET** (ASSA-239, Maren's ruling on
## ASSA-237: *"the line is empty when healthy and carries the stall sentence when the sim stalls"*).
##
## **FOUND BY MY OWN PROBE, NOT REASONED ABOUT.** `tools/nacre_toast_shot.gd` photographs a played
## world and REFUSES the run if the toast is drawn on a healthy one. Its first run failed: `joined as
## player 0` is a `Say.JOINED` line said once at the handshake and never taken back, so the toast sat
## over the world for the whole session -- the header strip returning at a quarter of the height,
## which is the exact thing Maren ruled against in advance. Removing `_act`'s echo was not enough; a
## line that is never cleared is permanent whoever wrote it.
##
## **ONLY `JOINED` AGES, AND THE OTHER THREE LEVELS MUST NOT.** `FAILED` is a refusal, and no refusal
## is silent -- a failure that faded out would be the one class of sentence a player cannot recover.
## `CONNECTING` is a live state that resolves itself. `IDLE` is already nothing. So this clause is
## about success only, which is the only level whose sentence stops being true once you can see the
## thing it announced.
##
## **THE DWELL IS IN THE SIM'S TICKS, NOT IN SECONDS.** This client has no clock of its own and must
## not grow one: the only time it knows is the world's, and a wall-clock dwell would make a line's
## lifetime depend on the frame rate of the machine reading it. 20 ticks is 2 s at the relay's default
## 10 ticks/s, and it is long enough to read `walking to 57, 59` and short enough that the resting
## state of a played screen is world and column and nothing else.
func _age_the_saying() -> void:
	if _base_level != AssayHud.Say.JOINED or _base_line == "":
		return
	if _said_at_tick < 0 or _sim.tick() - _said_at_tick < SAYING_DWELL_TICKS:
		return
	_say("", AssayHud.Say.IDLE)


## **THE STATUS LINE, FROM THE TWO THINGS THAT CAN WANT IT** (ASSA-191). One function so the rule is
## in one place: the last real sentence, unless the host has gone quiet, in which case the count.
##
## **THE WARNING OUTRANKS THE SENTENCE UNDERNEATH IT, AND THAT CALL IS MINE** (Maren can overrule it
## here in one line). While the link is quiet, a refusal from a click is about a world that is not
## moving and a command that reached nobody, so the warning is the more useful of the two sentences --
## and it is the one that keeps changing, which is what a player needs to see. The alternative,
## newest-wins, makes the warning vanish on every click and flicker back a second later.
##
## NOTHING IS LOST BY THAT: the sentence it covers is still `_base_line`, and the moment a bundle
## lands the line goes back to it rather than to blank.
func _render_status() -> void:
	if _quiet_seconds > 0:
		_status.text = AssayHud.quiet_host_line(_quiet_seconds)
		# THE AMBER THIS LINE ALREADY USES FOR A TRANSIENT STATE ("connecting to …"), not the red it
		# uses for failures: nothing has failed yet, and a red line that takes itself back down would
		# be the client crying off. Not a new colour -- the one state surface's palette is
		# `AssayHud.status_color` and ASSA-116 is what happens when something invents its own.
		_say_in(AssayHud.Say.CONNECTING)
		_place_says_toast()
		return
	_status.text = _base_line
	_say_in(_base_level)
	_place_says_toast()


## **STATE THE COLOUR, NEVER MULTIPLY THE INK** (ASSA-251, Maren's ruling being applied for the third
## time in this file).
##
## `_status.modulate = status_color(level)` is what this was, and `modulate` MULTIPLIES the theme's
## ink rather than replacing it, so the sentence was drawn in `status_color` TIMES `INK` and the
## colour on screen was nobody's decision. `_note` (ASSA-117) and the bench verdict both already
## carry this fix citing her; the status line is the one that never got it.
##
## **MEASURED, AND ONLY ONE OF THE FOUR STATES WAS BELOW THE FLOOR, WHICH IS WHY IT SURVIVED**
## (against the toast's panel, `SURFACE`):
##
##     level        declared   as drawn by modulate
##     CONNECTING      8.70         7.17
##     FAILED          4.79         3.98   <- the only one under 4.5
##     JOINED          6.73         5.64
##     IDLE            9.63         7.99
##
## So the defect was invisible in three states and bit exactly the one whose job is to say the game
## stopped — below even the 4.091 the board called "hard on the eyes". Maren found it on the first
## picture anyone ever took of a dropped relay.
##
## **AND `modulate` IS PUT BACK TO WHITE RATHER THAN LEFT ALONE.** A stale multiplier from an older
## build of this function would silently scale whatever this override states, which is the same
## defect wearing a different line.
func _say_in(level: int) -> void:
	_status.modulate = Color.WHITE
	_status.add_theme_color_override(&"font_color", AssayHud.status_color(level))


## **THE TOAST IS DRAWN ONLY WHILE IT HAS SOMETHING TO SAY, AND IT IS PLACED FROM ITS OWN SIZE**
## (ASSA-239).
##
## Maren's Gap 2 ruling gives the header strip's 96 px to the world and puts NOTHING in its place, so
## what the client is saying cannot go back to being a permanent line. It is a transient: empty for
## most of a session, and when it is empty the played screen is world and column and nothing else.
##
## **THE PREDICATE IS THE TEXT, NOT A FLAG.** `_status.text` and `_detail.text` are what a player
## would read; a `_has_said_something` bool would be a second idea of the same fact, free to be true
## while both labels are blank. `_detail` counts only while the developer toggle is on, because a
## readout nobody is drawing is not something the screen is saying.
##
## `get_combined_minimum_size()` RATHER THAN `size`: the suite runs inside `SceneTree._initialize`
## where no layout pass has happened, so `size` is whatever the node was born with and a toast placed
## from it would be in the right corner only in a real window. The minimum size is computed from the
## children on demand, so the headless tests and the shipped window agree.
func _place_says_toast() -> void:
	if _status.get_parent() != _says_toast_box:
		# PRE-WORLD THE LABELS ARE IN THE CENTRED FRONT DOOR (ASSA-231) and this panel owns nothing.
		_says_toast.visible = false
		return
	# **THE RECONNECT ROW COUNTS TOO** (ASSA-239). It is empty at JOINED -- `_refresh_join_band` hides
	# every cell in it -- and it is the way back in after a drop, so a toast that only watched the
	# labels would hide the one control a dropped player needs on the frame the sentence under it
	# changed. `_join_band.visible` is that row's own answer, not a second copy of the stage.
	var saying := _status.text != "" or (_dev_shown and _detail.text != "") or _join_band.visible
	_says_toast.visible = saying
	if not saying:
		return
	# **AND IT KEEPS OFF THE SHAPE KEY, WHICH I SPENT A MONTH COVERING** (ASSA-281). Both surfaces are
	# pinned to the world's bottom-left; the key was there first and the toast arrived on top of it,
	# hiding 64% of its last row's sample in every key shot taken since #327. `map_key_rect` rather
	# than the node's own rect for the reason three lines up: no layout pass has run in the suite, so
	# `_map_key_box.position` reads (0, 0) and a toast told to avoid THAT would avoid the wrong corner.
	# `_map_key_box.visible` and not `_map_key_shown`: the player's intent is on even in the close-up,
	# where no key is drawn and there is nothing to keep off.
	var blocked := Rect2()
	if _map_key_box.visible:
		blocked = AssayHud.map_key_rect(_map_key_box.get_combined_minimum_size())
	var at := AssayHud.status_toast_rect(_says_toast.get_combined_minimum_size(), blocked)
	_says_toast.position = at.position
	_says_toast.size = at.size


## The host went quiet, or came back. `seconds == 0` is "came back": see `AssayNetClient.link_quiet`.
func _on_link_quiet(seconds: int) -> void:
	if seconds == _quiet_seconds:
		return
	_quiet_seconds = seconds
	_render_status()
	# ONE LINE PER SECOND IN THE CONSOLE, AND IT IS THE SAME SENTENCE THE SCREEN HAS. `_say` prints
	# every other sentence this window shows, and a probe log of a silent host that said nothing for
	# eight seconds would be indistinguishable from a probe log of a client that never noticed.
	if seconds > 0:
		print(AssayHud.quiet_host_line(seconds))


## **WHETHER THERE IS A WORLD TO TALK ABOUT**, which is the question the three "which kind of empty"
## sentences in the column turn on (ASSA-186: the bench, the crafting menu and the event log).
##
## `_sim.running()` AND NOT THE JOIN EVENT, which is Maren's ruling and also the argument `_refresh`
## already makes about `_view_toggle` a few lines down: a join that is accepted and simulates nothing
## is a real state this screen handles, and in it "mine some rock first" is the same defect wearing a
## different cause. What the renderer can draw is the question; whether a handshake succeeded is a
## proxy for it. ONE PREDICATE FOR ALL THREE because it is one fact, and three copies of it is how
## two sections end up disagreeing about whether a world exists.
func _has_world() -> bool:
	return _sim.running()


## **THE THREE EMPTY SECTIONS SAY THEIR LINE AGAIN, BECAUSE NOTHING ELSE WOULD MAKE THEM** (ASSA-186).
##
## Every section in this column caches what it last drew by SHAPE -- `_bench_shape`, `_make_shape`,
## and the log's joined lines -- so that fourteen Labels are not rebuilt ten times a second. **An
## empty section has the same shape either side of a join**: no designs is `""` before and after, and
## so is an empty log. So the one thing that changed, whether a world exists, is invisible to all
## three caches, and without this the join screen's "join a world and the machines you build appear
## here" would still be on the bench of a world you are standing in, and the in-world wording would
## outlive the world after a drop.
##
## A FOURTH TERM IN EACH SHAPE KEY WOULD ALSO WORK and is worse: `_bench_shape` is documented as what
## the panel looks like given its designs, world-ness is not a property of a design list, and three
## keys to keep in step is three chances to forget one. This is one place, and it is the place that
## already knows the transition happened.
##
## IT ASKS THE SIM FOR NOTHING WHEN THERE IS NO WORLD. Going the other way -- a desync or a dropped
## host -- this runs with the sim stopped, and `designs_of`/`make_offers` would be questions about a
## world that is gone; the honest answer on the join screen is the empty list it draws there.
func _resay_the_empty_sections() -> void:
	var asking := _world_shown and _client != null
	var designs: Array = _sim.designs_of(_client.player_id) if asking else []
	var offers: Array = _sim.make_offers(_client.player_id) if asking else []
	_bench_showing = _bench_shape(designs)
	_make_showing = _make_shape(offers)
	_rebuild_bench(designs)
	_rebuild_make(offers)
	_rebuild_log()


func _refresh() -> void:
	# THE VIEW TOGGLE TRACKS WHETHER THERE IS A WORLD, and it is set HERE, above the early return,
	# because everything below this line runs only when there IS one (ASSA-142 box 3 / ASSA-161).
	#
	# ON `_sim.running()` AND NOT ON THE JOIN EVENT. A join that is accepted but produces no world is
	# a real state this screen already handles two lines down -- `joined at tick N, but no world is
	# being simulated` -- and in it the button would be back, offering a view of a world that does
	# not exist, which is the defect again wearing a different cause. Asking what the renderer can
	# actually draw is the question; asking whether a handshake succeeded is a proxy for it.
	_view_toggle.visible = _sim.running()
	# AND SO DOES THE KEY'S TOGGLE, on the same question and with one more clause: there is nothing to
	# key in the close-up (ASSA-206).
	_map_key_toggle.visible = _sim.running() and not _close_up
	# AND SO DOES WHICH KIND OF EMPTY THE COLUMN IS SAYING (ASSA-186), for the same reason and in the
	# same place: this is the one stretch of `_refresh` that runs on both sides of the early return,
	# so it is the only place a world appearing or going away can be noticed at all.
	if _has_world() != _world_shown:
		_world_shown = _has_world()
		_resay_the_empty_sections()
	if not _sim.running():
		var joined: Dictionary = _client.joined_world
		if joined.is_empty():
			return
		# **THIS SENTENCE IS NOT DEBUG AND IT CHANGED SURFACE RATHER THAN WORDS** (ASSA-237). It was
		# written into `_detail`, which is now hidden unless a developer asks for it -- so leaving it
		# there would have made the one state where the client joined and can draw nothing the one
		# state the client says nothing about. That is "no refusal is silent" lost to a layout change,
		# which is the quietest way this fix could have gone wrong.
		#
		# THE STRING IS BYTE-FOR-BYTE THE ONE `_detail` PRINTED: the words a client composes are not
		# mine to retune (they are Marlow's), and this item is about where a thing is drawn.
		#
		# `FAILED`, BECAUSE THAT IS WHAT IT IS. `_say` also prints it to the console, so the probes
		# that read this client's output gain a line here rather than losing one.
		#
		# **GUARDED, BECAUSE A LABEL IS IDEMPOTENT AND `_say` IS NOT.** `_detail.text = ...` could run
		# on every bundle for free; `_say` prints, and this branch is a CONDITION the client can sit in
		# for a whole session -- unguarded it would put the same line in the console ten times a second
		# and bury the one that matters. The comparison is against `_base_line` rather than a flag of
		# my own: that field already is "the last sentence this screen was given".
		var stalled := ("joined at tick %d, but no world is being simulated: %s"
				% [int(joined.get("tick", -1)), _sim.fail_reason])
		if stalled != _base_line:
			_say(stalled, AssayHud.Say.FAILED)
		return
	# The tile under the mouse, or your own tile until the mouse has been over the map. Which one it
	# is has to be on screen: a readout that silently changed subject would be unreadable.
	var at := _hover
	var source := "under the mouse"
	if not _hovering:
		at = _my_tile()
		source = "where you stand"
	_cursor.text = "%s\n%s" % [source, "\n".join(AssayHud.tile_lines(_sim.tile_at(at)))]
	_refresh_log()
	_refresh_halt()
	# WHAT IS RUNNING, beside what has stopped. This replaces the running-craft label that used to
	# sit at the head of the crafting menu: `activity_lines` already carries the craft countdown --
	# `crafting_readout` byte for byte, the same sentence that label printed -- plus the mining and
	# assaying lines that had no surface at all (ASSA-95). Keeping both would print the craft twice.
	_refresh_running()
	# AND A HEALTHY SENTENCE AGES OUT OF THE TOAST (ASSA-239). Here rather than in `_process` because
	# the dwell is counted in the WORLD's ticks and this is the function a tick bundle drives; in
	# `_process` it would be asked sixty times a second about a number that moves ten.
	_age_the_saying()
	# WHICH WORLD, WHICH TICK, WHICH HASH. The seed and the hash are TEXT, because a u64 cannot
	# survive a GDScript number -- that is not caution, it is measured. The bundle and hash counts are
	# here because a client that has stopped applying bundles looks exactly like one that is idle.
	var size := _sim.size_tiles()
	# WHERE A CLICK LANDS, WORKED OUT WITHOUT PAINTING ANYTHING. See `_cell`. The scene's half of the
	# same promise is `_refresh_world`'s camera, built on the same tick and for the same reason.
	_cell = AssayHud.map_cell(size)
	_refresh_world()
	# COUNTS AGREE WITH THEIR NOUNS, FROM THE SIM (ASSA-145). `1 players` was the second line of
	# every screenshot of Assay that exists -- solo is `Play solo`, which is how every window shot
	# was made and how a stranger opens the game. `AssaySimHost.counted` is `sim::debug::counted`,
	# so this line and the terminal's cannot drift. `tiles` and `species` are left alone: one is
	# always >= 2 and the other is invariant in English.
	#
	# **AND THE FRAME RATE, LAST** (Wren's ruling 3 on ASSA-197). Not for us -- every probe measures
	# its own `dt` -- but so that one demo request can ask one thing: how does the walk feel, and
	# what does the fps number say. We cannot know the board's frame rate and every speed number on
	# this item is half a number without it. It goes on the line the debug readouts already live on;
	# ASSA-198 decides where a player-facing one belongs.
	_detail.text = ("world seed %s, %d x %d tiles, %d species, %s · tick %d, hash %s · "
			+ "%s applied, %s reported · %d fps") % [
			_sim.seed_text(), size.x, size.y, _sim.species_names().size(),
			AssaySimHost.counted(_sim.players().size(), "player", "players"),
			_sim.tick(), _sim.hash_hex(),
			AssaySimHost.counted(_sim.applied, "bundle", "bundles"),
			AssaySimHost.counted(_hashes_sent, "hash", "hashes"),
			int(Engine.get_frames_per_second())]
	_refresh_make()
	_refresh_assembling()
	_refresh_pack()
	_refresh_actions()
	_refresh_bench()
	_refresh_species()
	_refresh_mineralogy()


## THE PART MENU: every design you hold, verdict first, with the one verb that design affords.
##
## Maren's ruling, and the reason this is nodes rather than one Label: THE VERDICT IS THE HEADLINE
## AND THE NUMBERS ARE THE SMALL PRINT. A player predicting a break should read one word, not
## compare two integers -- so the word is its own label, in the verdict's own colour and larger,
## with the spans under it in grey.
##
## NOTHING HERE DECIDES ANYTHING. The verdict, the spans, the durability wording and the list of
## species still reading rough all arrive from `sim` through the binding. The one thing this client
## adds is the arrangement -- and now the button, whose command is `AssayActions`' and whose legality
## is `sim::step`'s. PLACE IS ON EVERY PLANTED ROW WHATEVER THE VERDICT SAYS: an over-budget design
## breaks at placement, which is where the sim tests mass, and hiding the button would turn a
## mechanic into an error message (Maren's ruling, ASSA-5/7).
##
## THE STRUCTURE IS THE SIGNATURE, NOT THE WHOLE LIST, and that is not an optimisation. Durability
## moves every swing, so rebuilding on any change at all would free the Place button under the
## pointer four times a second while the player is mining. The rows stay; the numbers in them are
## rewritten.
## THE ROCKS OF THIS WORLD, AS THE SIM DESCRIBES THEM (ASSA-73).
##
## The sim has always handed the client every species -- name, the six readings as TEXT, whether the
## sheet is exact, and the two facts that decide a first fire -- and nothing on screen ever read it.
## The terminal player had `species`; the window player had nothing, and the milestone's test is a
## friend with no terminal.
##
## REBUILT ON CONTENT, NOT ON A SHAPE. The pack and the bench use a shape signature because their
## numbers move every tick and rebuilding would destroy a button under the pointer. A species sheet
## moves about twice a session -- an assay, a rename -- so the signature here is the WHOLE CONTENT
## and a change rebuilds the rows. That costs nothing at this rate and it cannot leave a stale label
## behind, which is the bug the fast path has already produced twice in this file.
func _refresh_species() -> void:
	var sheets := _sim.species_sheets() if _sim != null else []
	var signature := JSON.stringify(sheets)
	if signature == _species_showing:
		return
	_species_showing = signature
	_clear(_species)
	# **NO EMPTY NOTE HERE ANY MORE, AND DELETING ONE IS NORMALLY THE MISTAKE I MADE ON ASSA-237** --
	# so the reason, not the tidy. `_note`'s rule (ASSA-134) is that a HEADING may never sit over
	# nothing; the heading of this list used to be the `rocks` section's own. It is now the Mineralogy
	# tab's headline, and `show_answer([])` writes "no world yet — join one and what is near you is
	# answered here" into it on exactly the path this note covered. Keeping both put two sentences of
	# the same news six pixels apart on the first screen a stranger sees. The rule is honoured by the
	# surface that still has a heading, which is the body above this box, not by a second copy.
	if sheets.is_empty():
		return
	for entry in sheets:
		_species.add_child(_species_row(entry as Dictionary))


## **THE SIM'S ANSWER TO RAINY'S QUESTION, TEN TIMES A SECOND** (ASSA-254 wired into ASSA-247).
##
## NOT BEHIND `_refresh_species`' SIGNATURE, and that is the whole reason this is its own function.
## That signature is the species SHEETS, which move about twice a session; this headline carries a
## distance and a heading from where the player is STANDING, so gated on sheets it would freeze the
## moment you started walking towards the rock it named. It is the one surface in this column whose
## content changes because you moved and nothing else did.
##
## AND IT IS CHEAP AT THIS RATE: `_refresh` runs per tick bundle, not per frame (ten a second at the
## relay's clock), and the binding call beside it already asks for sheets, offers, designs and the
## inventory. `Label.set_text` returns early on an identical string, so a standing player costs no
## layout pass at all.
##
## `_client.player_id` IS -1 UNTIL A WELCOME LANDS, and the binding answers `[]` for a player who is
## not in the world, which `show_answer` renders as its no-world sentence. So the not-joined screen is
## the empty arm of the same path rather than a branch here.
func _refresh_mineralogy() -> void:
	var answers := _sim.proximity_answers(_client.player_id) if _client != null else []
	_mineralogy.show_answer(answers)


## WALK TO THE ROCK THE MINERALOGY TAB NAMED.
##
## THE TILE IS THE SIM'S AND THIS DOES NO ARITHMETIC ON IT -- not even a step to stand beside the
## patch rather than on it, which is the helpfulness ASSA-254 forbids: the sim chose the tile and a
## client that adjusts it is redoing a decision that has already been made.
##
## THE SAME COMMAND A LEFT CLICK ON THE MAP SENDS, through the same `AssayActions.move_to`, so the
## sim's legality check is the only thing that decides whether the walk happens. The echo is written
## here for the reason ASSA-215 measured on that click: everything else about this walk takes a
## quarter of a second, and the press needs an answer in the frame it happened in.
func _on_go_here_pressed(tile: Vector2i) -> void:
	if _client == null:
		return
	if _client.submit(AssayActions.move_to(tile)):
		_say("walking to %d, %d" % [tile.x, tile.y], AssayHud.Say.JOINED)


## ONE SPECIES, WEARING THE MARK THE MAP DRAWS ON IT.
##
## The glyph is the map's: the letter is `symbol`, which is `sim::debug::species_symbol` -- the same
## call a deposit's letter comes from, never the name's first character, because a renamed species
## keeps the mark already drawn. The disc is `AssayHud.species_tint`, the same table and the same
## lookup `deposit_color` uses, undimmed because purity belongs to a patch and not to a species. The
## letter's colour is `AssayHud.glyph_color`, the map's own readability rule.
##
## So a player reads "lights from cold" beside a letter here and goes looking for that letter out
## there. That is Maren's whole point: the map was already drawn in a code nobody had the key to.
func _species_row(species: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)

	var tint := AssayHud.species_tint(int(species.get("id", 0)))
	var disc := Panel.new()
	disc.custom_minimum_size = Vector2(GLYPH_BOX_PX, GLYPH_BOX_PX)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	# A CIRCLE, because that is what the map draws. A square swatch would be a second vocabulary for
	# the same fact, and the whole value of this row is that the two surfaces match.
	style.set_corner_radius_all(int(GLYPH_BOX_PX / 2.0))
	disc.add_theme_stylebox_override("panel", style)
	var letter := Label.new()
	letter.text = String(species.get("symbol", ""))
	letter.add_theme_color_override("font_color", AssayHud.glyph_color(tint))
	# THE ONE HAND-WRITTEN SIZE LEFT IN THIS FILE, AND IT IS ARITHMETIC RATHER THAN TASTE (ASSA-117).
	# This letter has to fit inside an 18px disc, and `GLYPH_BOX_PX`'s own comment is "big enough for
	# a 12px letter to sit in" -- the two numbers are one decision. Letting the theme's `BODY` decide
	# it would make the disc's size depend on a type scale chosen for readouts, and a letter that
	# outgrew its circle is a worse defect than a size written down beside the number it agrees with.
	letter.add_theme_font_size_override("font_size", 12)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disc.add_child(letter)
	head.add_child(disc)

	var title := Label.new()
	title.name = SPECIES_LINE
	title.text = "%s · %s" % [String(species.get("name", "?")),
			AssayHud.species_sheet_state(species)]
	head.add_child(title)
	row.add_child(head)

	var readings := _note(AssayHud.species_readings_line(species))
	readings.name = SPECIES_READINGS
	row.add_child(readings)
	var tags := AssayHud.species_tags(species)
	if not tags.is_empty():
		row.add_child(_note("[%s]" % "] [".join(tags)))
	return row


func _refresh_bench() -> void:
	var designs := _sim.designs_of(_client.player_id) if _client != null else []
	var signature := _bench_shape(designs)
	if signature != _bench_showing:
		_bench_showing = signature
		_rebuild_bench(designs)
		return
	for i in range(designs.size()):
		_write_design(_bench.get_child(i), designs[i] as Dictionary)


## What a bench LOOKS like, ignoring every number that moves on its own: which designs, in which
## order, on which mount, and which verb each one offers.
func _bench_shape(designs: Array) -> String:
	var shape := PackedStringArray()
	for entry in designs:
		var design: Dictionary = entry
		shape.append("%d/%s/%s" % [int(design.get("index", -1)),
				"hand" if bool(design.get("in_hand", false)) else "bench",
				String(design.get("mount", "?"))])
	return "|".join(shape)


func _rebuild_bench(designs: Array) -> void:
	_clear(_bench)
	if designs.is_empty():
		_bench.add_child(_note(AssayHud.no_designs_line(_has_world())))
		return
	for entry in designs:
		var design: Dictionary = entry
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		# THE VERDICT IS THE THEME'S `Display`, not a hand-written 19. `build_theme.gd` names this
		# exact control in the comment on its own `DISPLAY` constant -- "the bench verdict, SAFE /
		# UNCERTAIN / WILL BREAK, the one word to read first" -- so the size was already decided in
		# the one place that decides sizes, and this call site was a second opinion about it.
		var verdict := Label.new()
		verdict.name = BENCH_VERDICT
		verdict.theme_type_variation = &"Display"
		row.add_child(verdict)
		var body := _note("")
		body.name = BENCH_BODY
		row.add_child(body)
		row.add_child(_verb_row(AssayHud.design_verbs(design),
				func(descriptor: Dictionary) -> Button: return _design_button(descriptor, design)))
		_bench.add_child(row)
		_write_design(row, design)


## The numbers in one row, rewritten. The verdict is a WORD IN ITS OWN COLOUR, and it can change
## under a static row -- an assay turns UNCERTAIN into SAFE or WILL BREAK without the design moving.
## BY NAME, NOT BY CHILD INDEX (ASSA-117). These were `get_child(0)` and `get_child(1)`, which is the
## bug that already cost me a silently dead fast path once: adding a sprite to a pack row made child
## 0 a `TextureRect` and the re-text stopped finding its label. A bench row is the next surface
## Maren's icon ruling reaches, and when it gets one these two lines would have gone quiet the same
## way -- `_write_design` would have written the verdict into the icon and returned happy.
func _write_design(row: Node, design: Dictionary) -> void:
	var verdict := row.find_child(BENCH_VERDICT, true, false) as Label
	var body := row.find_child(BENCH_BODY, true, false) as Label
	if verdict == null or body == null:
		return
	verdict.text = String(design.get("verdict", "?"))
	# A `font_color` OVERRIDE AND NOT `modulate`, for the reason measured in `_note`: `modulate`
	# multiplies the theme's ink, so the word was being drawn in `verdict_color` TIMES `INK` and the
	# colour on screen was nobody's decision. Maren's ruling is that the verdict is a word in its own
	# colour; this is what makes the colour on screen that colour.
	verdict.add_theme_color_override(&"font_color", AssayHud.verdict_color(verdict.text))
	body.text = "\n".join(AssayHud.design_lines(design))


## One verb on one design row. `index` is the sim's, NOT the row's position: the tool in hand is a
## row with no index of its own (`designs_of` reports -1 for it), so counting rows would equip the
## wrong design the moment anything was in hand.
func _design_button(descriptor: Dictionary, design: Dictionary) -> Button:
	var label := String(descriptor.get("label", "?"))
	var index := int(design.get("index", -1))
	match String(descriptor.get("verb", "")):
		"equip":
			return _button(label, func() -> void: _act(label, AssayActions.equip(index)),
					"take this design into your hands")
		"unequip":
			return _button(label, func() -> void: _act(label, AssayActions.unequip()),
					"put the tool in your hands back on the bench")
		"place_assembly":
			# NEVER DISABLED AND NEVER CHECKED FIRST. Over budget is not this client's verdict to act
			# on: the sim breaks the design at placement and hands the parts back.
			return _button(label, func() -> void: _act("%s %d" % [label, index],
					AssayActions.place_assembly(index, _target_tile())),
					"plant this design on the tile you are acting on")
		_:
			return _button(label, func() -> void: _say(
					"no command for %s" % label, AssayHud.Say.FAILED))


## WHAT YOU ARE ASSEMBLING, under the running craft (ASSA-107, Maren's ASSA-88 ruling).
##
## ITS OWN SIGNATURE, so this is not rebuilt ten times a second: `_building` only changes when a
## `Frame`/`Mount` is pressed or an `Assemble` clears it, and rebuilding a container destroys any
## button the pointer happens to be over. The shape is what the sim named for each chosen stack --
## the same `stack_line` sentences the pack rows use, through `AssayHud.building_line`.
func _refresh_assembling() -> void:
	var signature := AssayHud.building_line(_building) if not _building.is_empty() else ""
	if signature == _assembling_showing:
		return
	_assembling_showing = signature
	_clear(_assembling)
	# NO PARTS CHOSEN COSTS NO PIXELS (ASSA-134). An empty `VBoxContainer` draws nothing and still
	# takes the column's `separation`, so this box was a 10px gap under the `make` heading for the
	# whole of every session in which nobody is holding parts -- including the join screen, where it
	# cannot have content at all. `_refresh_assembling` is the one place that knows whether it has
	# anything to show, so the `visible` flag is derived here rather than set at build.
	_assembling.visible = not _building.is_empty()
	if _building.is_empty():
		# NOTHING, NOT A NOTE. This sits inside the menu's own section under a heading that is
		# already about making things, so "no parts chosen" would be a line telling a player about
		# a thing they have not started. The pack's empty note exists because `you` is a heading
		# with its own section; this is not.
		return
	_assembling.add_child(_note(AssayHud.building_line(_building)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_button("Assemble", _assemble, "build the machine from the parts you chose"))
	row.add_child(_button("Clear", _clear_build, "put the chosen parts back"))
	_assembling.add_child(row)


## THE CRAFTING MENU'S ROWS (ASSA-88). One per recipe and part the sim says this player could make
## from what they carry, in the sim's own order, each row the sim's own sentence.
##
## THE CLIENT FILTERS NOTHING AND SORTS NOTHING. `make_offers` is the whole answer: which rows there
## are, what order they come in, and what each one says. A row that makes nothing arrives too (`sort`
## on grade A) and is shown, because absence is never a cue -- the player holding grade A ore is
## exactly the one wondering why they cannot refine it.
##
## SAME SIGNATURE RULE AS THE PACK, and the fast path matters MORE here: every row's sentence ends
## with "you have N", which climbs every mining cycle (ASSA-129 reshaped that clause; the sim still
## owns every word of it). The shape is what a row IS (its catalogue row and its
## material); the count is text, re-set every refresh without rebuilding a button under the pointer.
func _refresh_make() -> void:
	var offers := _sim.make_offers(_client.player_id) if _client != null else []
	var signature := _make_shape(offers)
	if signature != _make_showing:
		_make_showing = signature
		_rebuild_make(offers)
		return
	for i in range(offers.size()):
		var offer: Dictionary = offers[i]
		var label := _make.get_child(i).find_child(MAKE_LINE, true, false) as Label
		if label != null:
			label.text = String(offer.get("line", ""))


## What the menu LOOKS like: which catalogue row, made of which material. NOT the sentence, which
## carries a count that climbs on its own, and not the player's count either.
##
## `JSON.stringify` on the tag because a recipe's tag is a bare string and a part's is a nested
## dictionary (`{"Frame": "Held"}`), and only one of those can be glued into a string by hand.
## AND THE OUTPUT IS IN THE KEY BECAUSE THE ROW NOW DRAWS IT (ASSA-117 box 4). The standing rule
## here is "a term in a cache key that no drawn thing depends on is a rebuild nobody asked for"
## (ASSA-103); its converse is worse and silent -- a drawn thing MISSING from the key is a stale
## picture that the fast path cannot repair, because the fast path only re-texts the sentence. The
## output happens to be a function of the verb, the tag and the input today, so this term adds no
## rebuild; it is here so that stops being something a reader has to verify.
## **AND AFFORDABILITY IS IN THE KEY, AS A BOOLEAN, WHICH THE COUNT DELIBERATELY IS NOT** (ASSA-247).
## This function's standing rule is that a drawn thing missing from the key is a stale picture the
## fast path cannot repair -- it only re-texts the sentence -- and since this slice the row draws one
## more thing: whether its button is pressable. `count` stays out, because a count climbs every
## mining cycle and would rebuild five rows ten times a second; `count >= cost` flips at most once
## per threshold, which is exactly when the button must change and no other time.
func _make_shape(offers: Array) -> String:
	var shape := PackedStringArray()
	for entry in offers:
		var offer: Dictionary = entry
		var makes: Dictionary = offer.get("makes", {})
		var cost: int = int(offer.get("cost", -1))
		var afford := "?" if cost < 0 else ("y" if int(offer.get("count", 0)) >= cost else "n")
		shape.append("%s/%s/%s/%d/%s/%s/%d/%s/%s" % [String(offer.get("verb", "?")),
				JSON.stringify(offer.get("tag")), String(offer.get("kind", "?")),
				int(offer.get("species", -1)), String(offer.get("grade", "?")),
				String(makes.get("kind", "-")), int(makes.get("species", -1)),
				String(makes.get("grade", "-")), afford])
	return "|".join(shape)


func _rebuild_make(offers: Array) -> void:
	_clear(_make)
	if offers.is_empty():
		_make.add_child(_note(AssayHud.nothing_to_make_line(_has_world())))
		return
	for entry in offers:
		var offer: Dictionary = entry
		# THE SAME SHAPE AS A PACK ROW NOW (ASSA-117, box 4): [icon][VBox: the sentence, the dead
		# end, the verb]. The crafting menu had no art at all -- this is the half of box 4 that was
		# actually open, because the pack's icons were already exact and guarded (ASSA-65/71/98).
		#
		# **THE ICON IS WHAT THE ROW MAKES, NOT WHAT IT SPENDS** (Maren's ruling, ASSA-117 box 4),
		# and the comment that used to sit here claimed the opposite of what the code did: it said
		# "the thing you press make on is the thing that turns up in your pack a tick later" while
		# `_icon_box(offer)` read `offer.input` and drew the thing you spend. Maren hashed the plates
		# in `04-pack.png` and found all five rows drawing one picture -- the refined slab -- in a
		# menu whose only job is choosing between five things.
		#
		# THE INPUT IS NOT LOST AND NEVER NEEDED ART: it is identical on every row of a material's
		# block and the sentence names it in words ("2 Tonore refined (A), you have 8"), so the icon spends
		# its 32px on the half the player cannot otherwise see.
		#
		# `makes` IS THE SIM'S, out of `make_offers`, and absent on a row that makes nothing (`sort`
		# on grade A) -- so `{}` is the honest argument there and `_icon_box` returns null for it,
		# the same way it does for a gear.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		# **THE COLUMN IS RESERVED WHETHER OR NOT THERE IS ART FOR THIS ROW** (ASSA-240, Maren's
		# ruling). Measured at 1x on main `03c8966`: `Tonore head`, `handle` and `frame` each carry a
		# 32px icon and start at x=985; `Tonore gear` carries none and starts at x=946. **One list,
		# two left edges, 39px apart** -- and the thing that decides which a row gets is not the game,
		# it is whether `assets/sprites` happens to ship a sheet for that kind (Marlow). An icon column
		# that is sometimes there is worse than none: it is the only vertical line a list of wrapped
		# sentences has, and it breaks on the one row whose art has not been drawn yet.
		row.add_child(_icon_box(offer.get("makes", {}) as Dictionary, true))
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 2)
		# TAKES THE SPACE THE ICON LEAVES, AND THAT IS WHAT KEEPS THE ROW IN THE PANEL (ASSA-98). A
		# `FILL` child of an `HBox` gets its own MINIMUM, not the room left over, which is how every
		# pack row came to be 358px wide inside a 320px box. `EXPAND_FILL` is the derivation.
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(body)
		# THE SENTENCE IS THE ROW, AND IT IS A LABEL RATHER THAN THE BUTTON'S TEXT. Not a style call:
		# the engine reports a 320px-panel-busting MINIMUM for a Button holding this sentence --
		# `Button.autowrap_mode` exists in 4.6 and does NOT lower `get_combined_minimum_size`, which
		# I asked the engine rather than assuming (661px for the grade-A row). A row wider than the
		# panel is clipped, because the column does not scroll sideways: ASSA-98 exactly.
		# **THE SENTENCE AND ITS ONE CONTROL SHARE A LINE, AND THAT IS THE WHOLE OF GAP 3's DENSITY
		# HERE** (ASSA-247; Maren's Gap 3 in `assay-ui-direction`: *"the column is prose where it
		# should be data"*).
		#
		# MEASURED, NOT STYLED. `tools/nacre_tab_budget_probe.gd` put a make row at **73 px** with the
		# verb on its own line below the sentence, and this section needs 500 px of reachable button
		# against a budget of about 313. The row's floor is the icon box's **48 px** (`ICON_BOX_PX`,
		# which is arithmetic from the sprite sheets -- see its own comment), so a two-line sentence
		# beside a 48 px icon is ALREADY PAID FOR: putting the button on the sentence's line takes the
		# row to `max(48, sentence)` and the wrap costs nothing. 5 rows x 73 becomes 5 rows x 48.
		#
		# **SO NO WORD ON THIS ROW CHANGED AND NOTHING IS PARSED OUT OF ONE.** The cheap way to get
		# the same pixels was to stop drawing `offer.line` and compose a short label out of `makes`
		# and the species -- which is the client wording a sentence the sim owns, and `make_offers`'
		# own docstring warns against it by name (a `sort` row moves a grade). The density was
		# available in the LAYOUT, so the words were never the thing to spend.
		#
		# `EXPAND_FILL` on the sentence is what puts the button hard right and gives the text the rest
		# (ASSA-98's rule: a FILL child of an HBox gets its own minimum, not the room left over).
		var said := HBoxContainer.new()
		said.add_theme_constant_override("separation", 6)
		var line := _note(String(offer.get("line", "")))
		line.name = MAKE_LINE
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		said.add_child(line)
		# SHRINK_CENTER VERTICALLY so a 28px button beside a two-line sentence stays a 28px button:
		# an HBox child's default is to fill the row's height, which would stretch the one control on
		# the row to 38px and make its size a function of how long the sim's sentence happens to be.
		var verbs := _verb_row([offer], func(descriptor: Dictionary) -> Button:
				return _make_button(descriptor))
		verbs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		said.add_child(verbs)
		body.add_child(said)
		# **A DEAD END IS NOT A COST, AND THIS ROW DREW THEM IN ONE VOICE** (ASSA-158, Maren's
		# ruling: *"a permanent dead end may not be drawn in the same series as a cost"*). The
		# clause arrived with the same em dash and the same `_note` ink as the cost line above it --
		# she measured both at (167,176,190), byte-identical -- so a player scanning five rows read
		# "this is useless" as more of "what this costs". One of those can become true by playing;
		# the other never can.
		#
		# **THE LABEL IS THE SIM'S, NOT THIS FILE'S.** `sim-cli`'s catalogue has printed
		# `dead end: nothing uses a gear` since ASSA-122; the window is the surface that never got
		# it. Typing the words here would be a second copy of the Game Director's wording, which is
		# how ASSA-43 and ASSA-52 happened -- so it comes through the binding from
		# `debug::DEAD_END_LABEL`. Still the sim's own sentence, still empty unless the sim says so,
		# and still nothing in this client that names a gear (ASSA-84's clause, carried).
		#
		# The row stays listed and `Make` stays pressable (ASSA-5/7): a player may always try a
		# doomed design and be told, never refused.
		var dead_end := String(offer.get("dead_end", ""))
		if dead_end != "":
				body.add_child(_note("%s%s" % [_sim.dead_end_label(), dead_end]))
		# MAREN'S WALLS CLAUSE (ASSA-125), APPENDED AND NEVER COMPOSED, by the same route and for the
		# same reason: a smelter's walls are its material's heat tolerance, and what the player may
		# know of that is a band until they assay. The sim words it; this client would have to decide
		# how to say "somewhere between 50 and 74" and would be deciding a rule.
		var walls := String(offer.get("walls", ""))
		if walls != "":
			body.add_child(_note("— %s" % walls))
		_make.add_child(row)


## ONE PRESS ON ONE OFFER. ONE WORD ON EVERY BUTTON (Maren's ruling): the bug she measured was two
## buttons both labelled exactly `Craft smelter` making smelters with different walls, so a row's
## identity lives in its sentence and never in its label.
##
## WHICH COMMAND IS THE SIM'S ANSWER TOO. `verb` comes from `MakeWhat` -- `Craft` and `MakePart` are
## different commands with differently shaped payloads -- and the item is built by the same
## `item_of_stack` the pack rows use, because the offer carries `kind`/`species`/`grade` spelled
## exactly as `inventory_of` spells them.
##
## ONE BATCH, AND THE COUNT IS NEVER CAPTURED (ASSA-55). The sentence says how many you hold; what is
## sent is 1, so there is no number in this closure that can go stale.
func _make_button(offer: Dictionary) -> Button:
	var what := String(offer.get("line", "?"))
	var item := AssayActions.item_of_stack(offer)
	var button := _make_verb_button(offer, what, item)
	# **A ROW YOU CANNOT AFFORD DOES NOT OFFER A PRESSABLE BUTTON** (ASSA-247; Maren, 17:22 UTC
	# 2026-10-06: *"when a recipe is unavailable, the line says what you LACK"*, and ASSA-224's rule
	# for the primary -- a weight that does not follow availability is a lying control).
	#
	# **THIS IS WHAT `cost` CROSSED THE BINDING FOR** (Wren's routing ruling, 16:58 UTC). `line` and
	# `count` crossed and `cost` did not, so the only ways to know whether a press could succeed were
	# to parse the first integer out of "2 Tonore refined (A), you have 1" or to press and let the sim
	# refuse. The first is the client deriving a rule from Marlow's wording; the second is the button
	# that looks available and is not.
	#
	# **THE WORDS FOR WHAT YOU LACK ARE ALREADY THE SIM'S AND ARE NOT RE-SAID HERE.** `offer.line`
	# states the cost and what you hold in one sentence, so the row says what is missing and this
	# only stops the control claiming otherwise. If Maren wants an explicit shortfall clause it is a
	# sentence, which makes it `make_offers`' to add and not this file's.
	#
	# **ABSENT IS UNKNOWN, NOT AFFORDABLE** (ASSA-141's rule, read without a default): a binding that
	# stopped sending `cost` leaves every row pressable exactly as it was before this slice rather
	# than disabling the whole menu on a missing key. `test_sim_binding.gd` is what holds the field
	# there; this path is the honest behaviour if it ever goes.
	var cost: int = int(offer.get("cost", -1))
	if cost >= 0 and int(offer.get("count", 0)) < cost:
		button.disabled = true
	return button


## THE PRESS ITSELF, split out so the availability rule above reads as one decision over one button
## rather than three returns each having to remember it.
func _make_verb_button(offer: Dictionary, what: String, item: Dictionary) -> Button:
	match String(offer.get("verb", "")):
		"craft":
			var recipe: Variant = offer.get("tag")
			return _button(AssayHud.make_button_text(), func() -> void: _act(what,
					AssayActions.craft(recipe, item, 1)), "one batch: %s" % what)
		"make":
			var kind: Variant = offer.get("tag")
			return _button(AssayHud.make_button_text(), func() -> void: _act(what,
					AssayActions.make_part(kind, item, 1)), "one part: %s" % what)
		_:
			# A VERB THIS CLIENT DOES NOT KNOW IS NAMED, NOT GUESSED AT. The day the sim grows a third
			# catalogue the menu says so rather than sending one of the two commands it does know.
			return _button(AssayHud.make_button_text(), func() -> void: _say(
					"this client has no command for %s" % String(offer.get("verb", "?")),
					AssayHud.Say.FAILED))


## THE PACK, AS ROWS YOU CAN ACT ON. The words are `AssayHud.stack_line`'s and the verbs are
## `AssayHud.stack_verbs`', which reads them out of the sim's own recipe table and part catalogue --
## so a Craft button exists because some hand recipe eats this kind of item, and for no other reason.
##
## SAME SIGNATURE RULE AS THE BENCH: a count climbs every mining cycle, so only the shape of the pack
## rebuilds the rows.
func _refresh_pack() -> void:
	var stacks := _sim.inventory_of(_client.player_id) if _client != null else []
	# **AND THE PACK NO LONGER REBUILDS WHEN A PART IS CHOSEN** (ASSA-103). The signature carried
	# `_building.size()` for one reason: the part row's word turned on it. It reads `is_frame` now, so
	# nothing on a pack row changes when you pick something up -- and a term in a cache key that no
	# drawn thing depends on is a rebuild nobody asked for, every press.
	var signature := _pack_shape(stacks)
	if signature != _pack_showing:
		_pack_showing = signature
		_rebuild_pack(stacks)
		return
	for i in range(stacks.size()):
		var label := _carrying.get_child(i).find_child(STACK_LINE, true, false) as Label
		if label != null:
			label.text = AssayHud.stack_line(stacks[i] as Dictionary)


## What a pack LOOKS like: which items, in which order. Not how many of each, which climbs on its
## own every mining cycle.
func _pack_shape(stacks: Array) -> String:
	var shape := PackedStringArray()
	for entry in stacks:
		var stack: Dictionary = entry
		shape.append("%s/%d/%s" % [String(stack.get("kind", "?")), int(stack.get("species", -1)),
				String(stack.get("grade", "?"))])
	return "|".join(shape)


## ONE ITEM'S ICON, PLATE AND ALL, or null when there is no art for it (ASSA-117).
##
## PULLED OUT OF `_rebuild_pack` BECAUSE THE CRAFTING MENU NEEDS THE SAME THING, and this body is
## forty lines of measured detail from ASSA-65/71/98 that I was not going to type a second time. A
## second copy is the defect the comment inside it already names: two arms that must agree about a
## thing. `art/check_pack_icon_scale.py` measures the SHIPPED build, so it guards one of them.
##
## IT TAKES A STACK-SHAPED DICTIONARY AND NOTHING ELSE: `kind`/`species`/`grade` spelled as
## `inventory_of` spells them. A pack stack is one. A crafting offer is NOT -- its own three fields
## are the INPUT, which is what the row spends, so the crafting menu passes `offer.makes` (the sim's
## output item, same three spellings) and this function never learns which surface asked.
##
## AN EMPTY DICTIONARY IS A VALID ARGUMENT and returns null: `makes` is absent on a row that makes
## nothing (`sort` on grade A), and "no art" is already this function's answer for a gear.
## `reserve` KEEPS THE COLUMN WHEN THERE IS NO ART (ASSA-240). Callers that pass `false` get `null`
## for a kind with no sheet and must skip the child themselves, which is what every caller did until
## today. Defaulted to `false` ON PURPOSE rather than flipped for everyone: the PACK rows have the
## same defect and the same fix, but their layout is pinned by `art/pack_icon_layout.gd` and ten files
## in `art/` are drawn from it -- changing them without redrawing `pack_icons.png`, `pack_rows.png`
## and `pack_icon_kinds.png` turns CI's "A review sheet is still a picture of the client it drew"
## red. That half is pipeline work with its own cost, written down on ASSA-240; this half is free.
func _icon_box(stack: Dictionary, reserve := false) -> Control:
	# THE ICON IS REDUNDANT AND MOST ROWS DO NOT GET ONE. `items.png` carries ore, refined and
	# smelter, so a gear comes back null; the four part kinds have a row per grade. Every sentence
	# beside one of these reads completely without it, which is Maren's rule and the same one the
	# species glyph carries: a redundant cue promoted to the only cue is no longer redundant.
	#
	# **THAT RULE IS UNTOUCHED BY ASSA-240 AND IT IS WORTH SAYING SO.** Nothing below invents an icon
	# for a kind that has none. What a reserved row gets is SPACE: `ICON_BOX_PX` of nothing, so the
	# sentence beside it starts where every other sentence in the list starts.
	var icon := AssaySprites.icon_for(stack)
	if icon == null:
		if not reserve:
			return null
		# **IT DRAWS NOTHING, AND THAT IS MAREN'S RULING WORD FOR WORD** (ASSA-237, 15:50): *"A
		# reserved-but-empty icon box draws NOTHING -- reserve the 32 px so the text column never
		# moves; no outline, no ghost, no glyph. A box around nothing is a claim; space is
		# structure."* So this is a bare `Control`, not a `Panel` with a dimmed plate: the plate would
		# be the screen asserting there is an item picture here and it is merely dark.
		#
		# THE SAME BOX AND THE SAME ANCHORING AS A FILLED ONE, from the same constant, because a
		# reserved column that is a different width from a drawn one is the defect it was built to
		# fix wearing smaller numbers.
		var gap := Control.new()
		gap.custom_minimum_size = ICON_BOX_PX
		gap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return gap
	var art := TextureRect.new()
	art.texture = icon
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The species' own slot, from the table CI holds equal to the art pipeline's copy. The sheets are
	# drawn species-neutral on light rock precisely so this works (ASSA-19/20).
	art.modulate = AssaySprites.tint_for(stack)
	# NEAREST, not linear: these are pixel-art frames and the shipped import defaults say so.
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# THE BOX IS SET ONCE, FOR BOTH PATHS. It used to be set inside each arm, and the no-plate arm
	# set only `custom_minimum_size` -- no `SIZE_SHRINK_CENTER` -- which is ASSA-65's bug exactly: a
	# TextureRect in an HBox FILLS, so the rect becomes 32 x whatever the row is and the scale goes
	# back to being decided by how many verbs the stack affords. Nothing caught it, because
	# `check_pack_icon_scale.py` measures the shipped build and a plate always ships, so that arm is
	# only reachable when `ui_theme.json` is missing. Two arms that must agree is the defect; one
	# assignment above the branch is the fix.
	art.custom_minimum_size = ICON_BOX_PX
	# SHRINK_CENTER, or the row's height is still half of the scale: FILL stretches this rect to
	# whatever the buttons beside it need, and the ratio is nobody's decision again.
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# THE SLOT PLATE (ASSA-71, Maren's ruling). The ground's own median, so a stack in the pack and a
	# rock on the map read as the same object -- the panel is the one surface this art was never
	# judged on. One colour for every species and grade; it never carries information. The colour
	# comes from the pipeline (`ui_theme.json`), never a hex here.
	#
	# A PANEL AROUND THE RECT, NOT A RESIZE OF IT. The box stays exactly `ICON_BOX_PX` and the
	# TextureRect fills it, so the scale ASSA-65 made exact (1/2 for an item, 1/4 for a part) is
	# untouched -- a container with content margins would have quietly eaten it, which is the same
	# bug ASSA-65 fixed.
	var plate := AssaySprites.pack_icon_plate()
	if plate.a <= 0.0:
		return art
	var slot := Panel.new()
	slot.custom_minimum_size = ICON_BOX_PX
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = plate
	slot.add_theme_stylebox_override("panel", style)
	# Inside a Panel the rect is placed by anchors, so the two lines above are inert here --
	# harmless, and worth more than a branch that has to remember them.
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(art)
	return slot


func _rebuild_pack(stacks: Array) -> void:
	_clear(_carrying)
	if stacks.is_empty():
		_carrying.add_child(_note(AssayHud.nothing_carried_line()))
		return
	var recipes := AssaySimHost.recipes()
	var part_kinds := AssaySimHost.part_kinds()
	for entry in stacks:
		var stack: Dictionary = entry
		# MAREN'S SHAPE (ASSA-46, ruling B): [32px icon][VBox: the sentence, then the verbs]. The row
		# was already a container rather than a Label, which is the only reason an icon has anywhere to
		# live -- that fell out of ASSA-37 giving every row buttons.
		#
		# THE ICON IS REDUNDANT AND MOST ROWS DO NOT GET ONE. `items.png` carries ore and nothing else,
		# so refined, gears and smelters come back null today; the four part kinds have a row per grade.
		# `stack_line` stays a complete sentence either way, which is Maren's rule and the same one the
		# species glyph carries: a redundant cue promoted to the only cue is no longer redundant.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var slot := _icon_box(stack)
		if slot != null:
			row.add_child(slot)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 2)
		# TAKES THE SPACE THE ICON LEAVES, AND THAT IS WHAT MAKES THE ROW FIT (ASSA-98). A `FILL`
		# child of an `HBox` gets its own MINIMUM, not the room left over -- which is why the verb
		# row used to carry a `PANEL`-wide floor, and why that floor made every row 358 wide inside a
		# 320 box. `EXPAND_FILL` is the derivation: whatever sits beside this body, the body is the
		# rest of the row, and nothing has a width written down to keep in step.
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(body)
		var label := Label.new()
		# NAMED, NOT FOUND BY POSITION. `_refresh_pack`'s fast path re-texts this label ten times a
		# second without rebuilding the row, and it used to reach for `row.get_child(0)`. Adding the
		# icon made child 0 a TextureRect, so the fast path silently stopped updating the count -- I
		# broke it doing exactly that and three tests caught it. A name survives the next layout change
		# too, and Maren's ruling has two more surfaces coming (bench rows, then the spawn marker).
		label.name = STACK_LINE
		# NO WIDTH OF ITS OWN EITHER, FOR THE SAME REASON AS THE VERB ROW (ASSA-98). This used to be
		# `PANEL - ICON_PX - 6.0`, which was the right number and the wrong kind of thing: it is the
		# icon's width and the row's separation written down a second time, so a 64px icon one day
		# would push the row back over the panel with this floor as the thing doing the pushing. The
		# body expands into whatever the icon leaves, and the label fills the body.
		body.add_child(label)
		# WHETHER AN ITEM CAN BE PLACED IS THE SIM'S ANSWER TOO, by footprint: 2x2 for a smelter, 0x0
		# for a thing that is not a building.
		var footprint := AssaySimHost.footprint_of_item(String(stack.get("kind", "")),
				int(stack.get("species", -1)), String(stack.get("grade", "C")))
		var verbs := AssayHud.stack_verbs(stack, recipes, part_kinds, footprint)
		if not verbs.is_empty():
			body.add_child(_verb_row(verbs, func(descriptor: Dictionary) -> Button:
					return _stack_button(descriptor, stack, footprint)))
		_carrying.add_child(row)
		label.text = AssayHud.stack_line(stack)


## One verb on one stack. EVERY ITEM SENT IS THE ONE THE SIM NAMED: `item_of_stack` rearranges the
## three fields out of `inventory_of` and this client never works out what it is carrying.
## WITH THE MAKE-VERBS GONE (ASSA-86) THIS HANDLES THREE: Fuel/Smelt, Place, Frame/Mount. The two
## locals that went with them were `count` and the stack's sentence, both only ever read by the craft
## and make arms -- and `count` had in fact been dead since ASSA-55 took the number out of the Fuel
## tooltip, which is the sort of thing that survives a deletion unnoticed.
func _stack_button(descriptor: Dictionary, stack: Dictionary, footprint: Vector2i) -> Button:
	var label := String(descriptor.get("label", "?"))
	match String(descriptor.get("verb", "")):
		"insert":
			# THE WHOLE STACK. A button cannot ask for a quantity without growing a field, and
			# picking a smaller number for the player would be this client deciding how much fuel a
			# fire wants -- which is a sheet reading it does not have. `Pick up` gives a building and
			# its contents back, so nothing is spent for good.
			#
			# AND "THE WHOLE STACK" IS COUNTED WHEN THE BUTTON IS PRESSED, NOT WHEN IT WAS BUILT.
			# This is the rule at the top of the file and I broke it here first: the row only
			# rebuilds when the pack's SHAPE changes, so a count captured in the closure froze at
			# whatever was in hand the moment the row appeared. The button-driven session caught it
			# -- it pressed `Fuel` on a row reading 12 and inserted 2, and the fire went out
			# mid-stack. A tooltip with a number in it would go stale the same way, so it has none.
			var slot := String(descriptor.get("slot", ""))
			return _button(label, func() -> void: _insert(stack, slot),
					"put everything you are carrying of this into the %s slot of the building you "
							% slot + "are acting on")
		"place":
			return _button(label, func() -> void: _act(label,
					AssayActions.place(AssayActions.item_of_stack(stack), _target_tile())),
					"stand it on the %d x %d tiles from the one you are acting on"
							% [footprint.x, footprint.y])
		"build":
			# THE SAME FACT AS THE LABEL, FROM THE SAME PLACE (ASSA-103). The tooltip is the label's
			# claim at length, so it reads `is_frame` out of the descriptor rather than asking the
			# screen's state what the button probably means. It used to say "mount on the frame you
			# chose" to anything pressed after a first part -- including another frame, which the sim
			# refuses.
			return _button(label, func() -> void: _choose_part(stack),
					"use as the frame of the next machine"
							if bool(descriptor.get("is_frame", false))
							else "mount on the frame of the next machine")
		_:
			return _button(label, func() -> void: _say(
					"no command for %s" % label, AssayHud.Say.FAILED))


## WHAT YOU CAN DO WHERE YOU ARE: the three actions that need no item, the tile every placement lands
## on, the verbs of whatever building is on it, and the assembly you are part-way through.
##
## THE SIGNATURE HOLDS ONLY THE BUILDING'S ID, never its status. A smelter's status sentence changes
## every tick while it burns, and rebuilding on that would free the Take button four times a second.
func _refresh_actions() -> void:
	var target := _target_tile()
	var facts := _sim.tile_at(target) if _sim.running() else {}
	var building: Variant = facts.get("building")
	var at := -1 if building == null else int((building as Dictionary).get("id", -1))
	# **AND THE MINABLE BIT IS IN THE SIGNATURE, WHICH IS THE HALF THAT WOULD HAVE FAILED SILENTLY.**
	# This row is only rebuilt when the signature changes, and `Mine` acts on the tile you are
	# STANDING on while every other term here is about the tile you are ACTING on. Walking off a
	# deposit without touching the cursor changes none of the old terms, so the button would have
	# kept an accent that no longer meant anything until something else happened to move.
	var minable := _can_hand_mine_here()
	# **AND WHETHER THERE IS ANYWHERE TO SEND A COMMAND, WHICH IS A DIFFERENT QUESTION FROM THE ROCK**
	# (ASSA-251, Maren). `minable` is the sim's bit about the deposit under you; it knows nothing
	# about whether a relay is listening. On the dropped screen both were true, so `Mine` was green
	# while pressing it could only reach `_act` -> `submit` fails -> "not submitted; join a world
	# first". A green button that refuses is worse than a grey one that refuses (her ASSA-215/233
	# clause), and it put TWO greens on screen with the live-looking one being the dead one.
	#
	# IT IS IN THE SIGNATURE FOR THE SAME REASON `minable` IS: this row only rebuilds when the
	# signature changes, and a dropped link moves none of the other terms, so the button would keep
	# an accent that no longer means anything until something else happened to move.
	var live := _client.stage == AssayNetClient.Stage.JOINED
	var signature := "%s/%s/%d/%s/%s/%s" % [target, _targeted, at, _building, minable, live]
	if signature == _actions_showing:
		return
	_actions_showing = signature
	_clear(_actions)
	if not _sim.running():
		# Before a Welcome there is no tile to act on and no player to act as. A row of buttons that
		# could only report "not joined" would be the Join button's answer in a worse place.
		_actions.add_child(_note("join a world and these become the things you can do"))
		return

	var here := HBoxContainer.new()
	here.add_theme_constant_override("separation", 4)
	# **THE PLAYED SCREEN'S ONE PRIMARY, AND ONLY WHERE IT WOULD WORK** (ASSA-233, Maren's ruling 2).
	# Nine buttons at identical weight is the join screen's old defect one room over: "Mine is the
	# verb that makes something from nothing, and the first thing a player with no tutorial must do".
	#
	# **HER `CHECK, DO NOT ASSUME` CLAUSE, CHECKED: `do` DOES NOT GATE ANYTHING.** Mine, Stop and
	# Assay are added unconditionally the moment `_sim.running()`, so a green Mine would be offered
	# over bare grass and over rock no hand can break -- and "a green button that refuses is worse
	# than a grey one that refuses" is the whole of her clause.
	#
	# **THE FACT IS THE SIM'S BIT, NOT A RULE COPIED INTO THIS FILE.** `hand_minable` on the deposit
	# comes from `sim::ladder::hand_minable`; the client may not re-derive "hardness <= 40 at grade",
	# and could not honestly anyway -- a sheet reads as a 25-wide BAND until the species is assayed,
	# so this screen does not know the hardness it would need. One bit, from the one authority.
	var mine_button := _button("Mine", func() -> void: _act("Mine", AssayActions.mine()),
			"hand-mine the deposit under you. Keeps swinging until you Stop.")
	if minable and live:
		mine_button.theme_type_variation = &"Primary"
	here.add_child(mine_button)
	here.add_child(_button("Stop", func() -> void: _act("Stop", AssayActions.stop()),
			"stop walking, mining, crafting and assaying"))
	here.add_child(_button("Assay", func() -> void: _act("Assay", AssayActions.assay()),
			"study the deposit under you until its sheet reads exact instead of in bands"))
	_actions.add_child(here)
	_actions.add_child(_note(AssayHud.target_line(target, _targeted, facts)))
	# THE RUNNING CRAFT USED TO BE MADE HERE and is now made once in `_build_ui`, at the head of the
	# crafting menu (ASSA-88, Maren's ruling). Rebuilding it with this section was always a liability
	# as well as the wrong place: `_refresh_actions` runs whenever the target tile or the building
	# under it changes, and every run replaced the node whose text `_refresh` sets.

	if building != null:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(_button("Take", func() -> void: _act("Take", AssayActions.take(at)),
				"empty the output slot into your pack"))
		row.add_child(_button("Pick up", func() -> void: _act("Pick up", AssayActions.pickup(at)),
				"take the building back, with whatever is inside it"))
		_actions.add_child(row)

	# THE CHOSEN PARTS USED TO BE DRAWN HERE and are now in the crafting menu, under the running
	# craft (ASSA-107). `_refresh_assembling` owns them.


## ONE DOOR FOR EVERY BUTTON ON THIS SCREEN, and the only place any of them reaches the wire.
##
## **IT SAYS THE ACCEPTANCE AND NOT THE TICK, AND I HAD DELETED BOTH** (ASSA-245).
##
## ASSA-239 shipped this as `_say("", IDLE)` -- an accepted command said nothing at all. That was my
## reading of half of Maren's ASSA-237 ruling (*"the line is empty when healthy"*) and I missed the
## other half, which she had already written: **"The acceptance is a fact a player uses; the tick is
## not. Press-to-motion on this relay is 204-362 ms, so 'the game took your command' is real feedback
## and must not simply be deleted. Keep the acceptance, drop `at tick 514`, and move it out of the
## band."**
##
## **SHE IS RIGHT AND THE NUMBER IS WHY.** A fifth of a second to a third of a second passes between
## the press and anything moving, because this client never predicts: the world changes when a bundle
## carrying this command comes back round and the sim steps. For that long, a silent screen and a
## dead button are the same picture. The sim's own event in the log is the describer for WHAT
## HAPPENED (ASSA-222, and that has not changed); this line is the only thing that answers *did it
## hear me*, which the log cannot answer until the tick it is waiting for.
##
## **THE TICK GOES AND NOTHING ELSE DOES.** `Place 0 · submitted at tick 514` becomes `Place 0 ·
## submitted`. A tick number is the thing Gap 2 sent off this screen, and re-admitting it on a
## different line would be the debug readout coming back one clause at a time.
##
## **"OUT OF THE BAND" AND "TRANSIENT" ARE BOTH ALREADY TRUE** (ASSA-239): there is no band -- the
## status line lives in a toast over the world's bottom-left -- and a `Say.JOINED` line ages out
## after `SAYING_DWELL_TICKS` of the world's own clock, so the resting state of a played screen is
## still world and column and nothing else. Maren offered the log or a transient; this is the
## transient.
##
## **THE REFUSAL STAYS, LOUD.** No refusal is silent is not a style rule here, and this is the branch
## it protects: a press that never reached the wire is the one thing a player cannot find out any
## other way, because a command that was never sent produces no event to read in the log. It is also
## the one `_say` here that must NOT age out, which is why only `Say.JOINED` does.
func _act(what: String, command: Variant) -> void:
	if _client.submit(command):
		_say("%s · submitted" % what, AssayHud.Say.JOINED)
		return
	_say("%s · not submitted; join a world first" % what, AssayHud.Say.FAILED)


## Insert needs a building, and there may not be one. THIS IS NOT A REFUSAL -- with no building there
## is no `BuildingId` to put in the command at all, so there is nothing to send and saying so is the
## only honest answer. Maren's "never refuse" is about commands the sim should judge.
func _insert(stack: Dictionary, slot: String) -> void:
	var target := _target_tile()
	var building: Variant = _sim.tile_at(target).get("building")
	if building == null:
		_say("nothing to insert into at %d, %d — right-click a building first"
				% [target.x, target.y], AssayHud.Say.FAILED)
		return
	# HOW MANY WE ARE ACTUALLY CARRYING, ASKED NOW. Grade is part of the question: two grades of one
	# ore are two stacks and two rows, and inserting the other row's count would be a number from a
	# different row.
	var count := AssayInventory.held(_sim.inventory_of(_client.player_id),
			String(stack.get("kind", "")), int(stack.get("species", -1)),
			String(stack.get("grade", "")))
	if count <= 0:
		_say("you are not carrying any %s any more" % String(stack.get("name", "?")),
				AssayHud.Say.FAILED)
		return
	_act("Insert %d into %s" % [count, slot], AssayActions.insert(
			int((building as Dictionary).get("id", -1)), slot,
			AssayActions.item_of_stack(stack), count))


## Choose a part for the next `Assemble`. The first one is the FRAME, which is `sim-cli`'s rule kept
## rather than invented, and the row's button says whether this kind is one.
##
## **A PRESS THE SIM WOULD REFUSE IS ANSWERED AT THE PRESS, IN THE SIM'S OWN SENTENCE** (Maren,
## ASSA-103). This used to append whatever it was handed and confirm it in the JOINED colour, so a
## head chosen as a frame looked accepted and the refusal arrived at `Assemble` -- which clears the
## whole sequence, so the player lost every good press as well as the bad one.
##
## THE SIM ANSWERS, NOT THIS FILE. `part_press_refusal` is `sim::assembly::fault_adding` with the
## sim's own wording (ASSA-102); a design that is merely half built answers `""`, because the
## recoverable/permanent line is a rule in there and not something GDScript gets to guess at.
## Nothing is disabled either (ASSA-37): the button stays pressable and the sim does the refusing.
func _choose_part(stack: Dictionary) -> void:
	var chosen := PackedStringArray()
	for entry in _building:
		chosen.append(String((entry as Dictionary).get("kind", "")))
	var refusal := AssaySimHost.part_press_refusal(chosen,
			String(stack.get("kind", "")))
	if refusal != "":
		_say(refusal, AssayHud.Say.FAILED)
		return
	_building.append(stack)
	_say("%s %s" % ["frame:" if _building.size() == 1 else "mounting", AssayHud.stack_line(stack)],
			AssayHud.Say.JOINED)
	_refresh_pack()
	_refresh_assembling()
	_refresh_actions()


## Build the machine. REJECTED ONLY FOR PARTS THAT DO NOT FIT, never for weight -- mass is tested at
## placement (sim decision 11). The choice is cleared either way: the event log carries the sim's
## reason, and a half-chosen assembly left on screen after a refusal reads as a stuck button.
func _assemble() -> void:
	if _building.is_empty():
		return
	var mounted := []
	for stack in _building.slice(1):
		mounted.append(AssayActions.item_of_stack(stack as Dictionary))
	_act("Assemble", AssayActions.assemble(
			AssayActions.item_of_stack(_building[0] as Dictionary), mounted))
	_clear_build()


func _clear_build() -> void:
	_building.clear()
	_refresh_pack()
	_refresh_assembling()
	_refresh_actions()


## THE TILE EVERY PLACEMENT LANDS ON: the one you chose, or the one you stand on until you choose.
func _target_tile() -> Vector2i:
	return _target if _targeted else _my_tile()


## A ROW OF VERB BUTTONS THAT WRAPS. An `HFlowContainer`, not an `HBoxContainer`, and that is not a
## style choice: an HBox would run buttons off the right edge of a 320px panel, and the column only
## scrolls vertically, so a button pushed sideways is a button that cannot be pressed -- the exact
## failure the scroll box was added to avoid.
##
## **THE NUMBER THIS COMMENT USED TO QUOTE IS GONE AND SO IS THE REASON FOR IT** (ASSA-86). It said a
## refined stack offers SEVEN buttons -- Craft gear, Fuel, Smelt and one Make per part kind -- which
## was true, was the clunk the board hit, and is now three: the make-verbs live in the crafting menu.
## The wrapping stays because the bench calls this too and because a row with three buttons and a
## wider font still has to fit; what it must not do is go back to being load-bearing for a row the
## panel cannot hold.
##
## **AND FOR A WHILE THAT COMMENT WAS TRUE AND THIS CODE WAS NOT** (ASSA-98). It used to claim
## `custom_minimum_size.x = PANEL`, the whole panel width, which was right while a stack row was just
## `[VBox(line, verbs)]`. ASSA-46 put a 32px icon BESIDE that VBox and nobody subtracted it, so every
## pack row's minimum became 320 + 32 + 6 = **358 inside a box 320 wide that clips and does not
## scroll sideways**. Measured, not reasoned: `art/pack_icon_layout.gd` reported `row_size [358, 48]`
## against `panel_px 320`.
##
## **SO IT CLAIMS NOTHING NOW AND TAKES THE WIDTH IT IS GIVEN.** That is the version that cannot rot:
## the bench calls this too, where its row IS the full panel, and a width passed in as an argument
## would be one more number to keep in step with whatever gets added to a row next. What makes it
## work is `SIZE_EXPAND_FILL` on the stack row's body -- without it a `FILL` child of an `HBox` gets
## its own minimum rather than the space left over, which is why the floor was there in the first
## place.
func _verb_row(verbs: Array, make_button: Callable) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 2)
	for descriptor in verbs:
		row.add_child(make_button.call(descriptor as Dictionary))
	return row


func _button(label: String, on_press: Callable, hint := "") -> Button:
	var button := Button.new()
	button.text = label
	button.tooltip_text = hint
	button.pressed.connect(on_press)
	return button


## A line of small grey print: a heading with nothing under it reads as a bug, so every empty section
## says which kind of empty it is.
func _note(line: String) -> Label:
	var label := Label.new()
	label.text = line
	# THE SECONDARY INK, FROM THE THEME, AND THIS IS THE BOARD'S COMPLAINT MEASURED (ASSA-117).
	#
	# This line was `modulate = Color(0.55, 0.58, 0.64)`, and `modulate` MULTIPLIES the colour the
	# theme chose instead of replacing it. So every note in this client -- every pack sentence, every
	# crafting row, the running-craft line, every log line -- was drawn at (0.494, 0.530, 0.605) and
	# scored **4.091:1** against the panel. `tools/build_theme.gd` refuses to WRITE a theme whose
	# inks miss 4.5:1, and this went round the outside of that guard: the same hole Maren found for
	# the status line (ASSA-116), on roughly every readout in the window rather than on one line.
	# Measured in the engine against the shipped `theme/assay.tres`, not computed here: 4.091 before,
	# 6.731 after. "logs are hard on the eyes" was a true report of a number.
	#
	# A `font_color` OVERRIDE READ OUT OF THE THEME, so there is no colour written down and no 22nd
	# `Color` literal (Maren's corrected ruling 3). Off-tree lookup reaches the project theme --
	# asked, not assumed, because this label is built before it has a parent.
	label.add_theme_color_override(&"font_color", label.get_theme_color(&"font_color", &"Muted"))
	# NO FONT SIZE AND NO WIDTH. The size was a hand-written 13, which is exactly what the theme's
	# `BODY` already is, so the override only existed to be wrong one day. The width was a `PANEL`
	# floor on EVERY note in the window -- 320px of minimum inside a scroll viewport that is 320
	# minus its scrollbar, which is ASSA-98's clipping with the floor doing the pushing.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A LOG LINE CUT TO THE WIDTH IT HAS, instead of wrapped to the height it wants (Maren's ruling,
## ASSA-117 box 8).
##
## **THE SIM AUTHORED THESE LINES TO BE TRUNCATED AND THIS CLIENT WAS WRAPPING THEM.**
## `sim::debug::assembly_readout` says so in writing: *"Verdict first, then the numbers, then
## the parts. Deliberate: a side panel is narrow and the line gets truncated, so the thing the player
## needs before spending parts must not be the thing that is cut."* A design verdict became SIX rows,
## so the ordering that exists to survive a cut bought nothing and the log inherited a panel per
## event: Maren measured entries 1, 4, 4, 5 and 6 rows tall, 682px of them in a 566px box.
##
## NOTHING IS REWORDED. The wording stays the sim's (ASSA-117 box 3 grants presentation and nothing
## else), and the ellipsis is the engine's, drawn where the box ends rather than at a character count
## this file would have to pick.
##
## **MEASURED, BECAUSE THE OBVIOUS SPELLING IS ASSA-98's BUG AGAIN.** Asked of the engine with the
## real sentence at the real font: a Label with `AUTOWRAP_OFF` alone reports a **1012px** minimum
## width, which is a row 692px wider than the 320px panel that clips it -- exactly the 358-in-320
## defect ASSA-98 fixed. With `OVERRUN_TRIM_ELLIPSIS` the minimum is **1px**, so the row takes the
## width the column gives it and the cut happens in the draw. `clip_text` measures the same and is not
## set: the ellipsis says that something was cut, and a silent cut is a sentence that lies about
## being complete.
##
## WHAT STILL COSTS MORE THAN ONE ROW: a line the SIM wrote with a newline in it (`event_lines` keeps
## them, `_remember_events` stores them whole). Those are the sim's own notes, deliberately two rows,
## and `AUTOWRAP_OFF` does not fold them into one -- which is what Maren's arithmetic counted.
##
## **BUT EACH OF THOSE ROWS IS CUT TOO, and the first version of this comment did not say so.** I
## wrote "`AUTOWRAP_OFF` does not touch them", which is true of the row COUNT and false about the
## text: the trim applies per drawn row, so the sim's second row ends in an ellipsis like any other.
## Seen in `03-log.png` at 14247 rather than reasoned about — `516 you assembled #0: WILL BREAK ...`
## keeps its note row, and that row reads `this is over budget: it will break when planted…`. The
## newest entry is exempt and shows every row of itself whole, which is where `broke` lives.
##
## If the sim's own notes should survive a cut that the event line does not, that is a ruling and not
## a line of mine to change: it would mean a log entry is a list of rows with different rules, and
## today it is one Label holding one string.
func _cut_to_one_row(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _clear(box: Node) -> void:
	for child in box.get_children():
		child.queue_free()
		box.remove_child(child)


## The tile my own player is on, as the sim has them. Spawn before there is a player of mine to find:
## it is the one tile every world has and it is where I am about to be.
## HAND THE SCENE EVERYTHING IT DRAWS. One dictionary, built here and consumed by `AssayScene`, which
## is what keeps every decision in the scene testable headless.
##
## CALLED FROM BOTH `_refresh` AND `_process`, DELIBERATELY. `_refresh` is the tick path and it is the
## one that matters for correctness: the suite and every probe run inside `SceneTree._initialize`
## where `_process` never fires, so a camera that only existed on a frame would mean no headless test
## could ever click the scene. `_process` adds the frames between ticks, which is only ever motion.
## THE MAP'S NOTE IS SHOWN EXACTLY WHEN THE MAP HAS NOTHING ON IT, read off `_world.view` rather
## than off a second idea of "is there a world yet".
##
## `world_layer.gd` already states that an empty `view` IS the no-world state, and it is the thing
## that decides whether anything is painted. Asking `_sim.running()` here instead would be a second
## condition for one fact, and the frame where the two disagree is a sentence over a drawn world or
## a bare rectangle with no sentence -- both of which look like the bug this item is about.
## **AND THE WHOLE JOIN SCREEN GOES WITH IT NOW** (ASSA-231). The note is one line inside
## `_front_door`, so what is shown or hidden is the composition: the title, the sentence, the two
## rows of controls and what the client is saying. The HUD column is the other half of the same
## fact, which is why it is set here rather than on a predicate of its own -- Maren's Gap 5 is one
## ruling about one screen, and two conditions for it is how a door and a column end up both on
## screen for a frame.
func _refresh_front_door() -> void:
	var empty: bool = _world.view.is_empty()
	_front_door.visible = empty
	_door_backdrop.visible = empty
	if _column != null:
		_column.visible = not empty
	_place_join_controls(not empty)
	# AFTER THE MOVE, NEVER BEFORE IT (ASSA-239): the toast's own predicate is "are the labels mine",
	# so asking on the frame they arrive is the difference between a toast that appears with the world
	# and one that appears a tick later.
	_place_says_toast()


## **WHERE THE THREE JOIN CONTROLS LIVE, WHICH IS A FUNCTION OF WHETHER THERE IS A WORLD** (ASSA-231).
##
## IDEMPOTENT ON PURPOSE: this runs on every refresh and `reparent` is skipped unless the home is
## actually wrong, so the normal frame costs three comparisons and moves nothing. That is also what
## keeps the order inside `_row` right -- the cells are appended in this dictionary's order the one
## time they move, and never shuffled again.
##
## AND THE FOCUS IS DROPPED ON THE WAY IN. `_solo_button` asks for the focus whenever it enters a
## tree (see `_build_ui`), which a reparent is: landing in a world holding the focus would mean Enter
## pressing a hidden `Play solo` and getting a refusal nobody asked for.
func _place_join_controls(in_world: bool) -> void:
	var homes := {
		_solo_cell: _join_band if in_world else _door_primary,
		_cred_cell: _join_band if in_world else _door_secondary,
		_join_button: _row if in_world else _door_secondary,
		# **A CONTAINER AT BOTH ENDS NOW, AND THAT DELETED A WHOLE CLASS OF BUG** (ASSA-239). These two
		# used to come home to `self` and be parked at (24, 54) and (24, 74) by hand -- two coordinates
		# in a header strip that no longer exists. They now move between two VBoxes, so nothing here
		# positions anything and `reset_size` has nothing to undo.
		_status: _says_toast_box if in_world else _door_says,
		_detail: _says_toast_box if in_world else _door_says,
	}
	var moved := false
	for control: Control in homes:
		var home: Node = homes[control]
		if control.get_parent() == home:
			continue
		control.reparent(home, false)
		moved = true
	if not moved:
		return
	if in_world:
		# WHAT HAPPENED, THEN WHAT TO DO ABOUT IT (ASSA-239). `reparent` appends, so the two labels
		# land after the row they should read above. One move, only on the frame something actually
		# changed home, which is what the `moved` guard above buys.
		_says_toast_box.move_child(_row, -1)
		if _solo_button.has_focus():
			_solo_button.release_focus()


## **EVERY PLAYER THE BINDING IS SENDING, OR NOTHING AT ALL** (ASSA-196 box 3, and box 5 is the
## decision this implements: REFUSE THE FRAME, not the player).
##
## Five places in this file read a player's `id` and `pos` with a silent default, so a binding that
## stopped sending `pos` would put every player on tile (0, 0) -- one tile off the world's corner --
## CONFIDENTLY, and one that stopped sending `id` would make every player -1, so `id ==
## _client.player_id` is false and the camera follows nobody. Marlow found it in my file and left it
## for me; `AssayScene.missing_sim_facts` cannot see it, because by the time it looks the view carries
## `at`/`facing`/`moving` and all three are present.
##
## **WHY THE FRAME AND NOT THE PLAYER.** A dict with no `pos` is not one missing body in an otherwise
## honest picture: the same dicts decide where the CAMERA is, so a view that cannot place one player
## cannot say what it is looking at, and every other body, building and tile in that frame sits at an
## offset nobody checked. "Nothing to draw" is a state this screen already has words for (ASSA-161,
## ASSA-186), so refusing costs no new vocabulary.
##
## **AND IT IS HERE RATHER THAN IN `_refresh_world`, WHICH IS A CORRECTION TO MY OWN PLAN.** I wrote
## that the boundary would be `_refresh_world` and that the other reads would keep their defaults
## "with a comment naming the boundary that makes them unreachable", with the open worry that
## `_my_tile` is called from INPUT handlers so the ordering would need measuring. The ordering turns
## out not to be the question: **`_my_tile` does not read `_refresh_world`'s view at all, it re-reads
## `_sim.players()` itself**, and so does `_remember_positions`, and so does the schematic's own loop.
## A refusal in `_refresh_world` would have left three readers defaulting on their own, no matter what
## order the engine ran things in. A data-flow fact, and it would have survived any frame-ordering
## measurement I made, because the measurement was of the wrong claim.
##
## So every reader goes through here and the defaults downstream are genuinely unreachable: on a
## refusal the list is EMPTY, so each loop runs zero times instead of once with a made-up tile.
func _players() -> Array:
	var players: Array = _sim.players()
	var missing := AssaySimHost.missing_player_facts(players)
	if missing.is_empty():
		_player_facts_missing = PackedStringArray()
		return players
	# SAID ONCE, NOT EVERY FRAME. This runs at the frame rate, and a line that repeats sixty times a
	# second buries the first copy -- which is the one with the context in it. The comparison is on
	# WHAT IS MISSING and not a latch, so a second, different cause still gets said.
	if String(", ").join(missing) != String(", ").join(_player_facts_missing):
		_player_facts_missing = missing
		# **`_say`, NOT `_note`, AND THAT WAS A DEFECT I SHIPPED IN #273.** `_note` BUILDS a Label and
		# returns it; every other caller in this file hands the result to an `add_child`. This one
		# dropped it, so the player-facing half of the refusal was a sentence nobody could ever see --
		# found by the behavioural test ASSA-196 was missing, which counted the sentence on screen and
		# got zero. `_log` is not the home for it either: `_rebuild_log` clears that container and
		# re-fills it from `_events`, which are the SIM's lines, so a child added here would vanish on
		# the next frame. The status line is where this client's own sentences live (ASSA-161/186/191).
		_say("the simulation is not describing its players (%s) -- nothing to draw"
				% String(", ").join(missing), AssayHud.Say.FAILED)
		push_error("AssaySim.players() is missing %s" % String(", ").join(missing))
	return []


func _refresh_world(frame_dt := -1.0) -> void:
	if not _sim.running():
		_world.view = {}
		_world.me = null
		_refresh_front_door()
		_world.queue_redraw()
		return
	if _manifest.is_empty():
		_manifest = AssaySprites.manifest()
	if _layout.is_empty():
		_layout = AssayAssembly.contract()
	var size := _sim.size_tiles()
	var now := float(Time.get_ticks_msec()) / 1000.0
	# HOW FAR THROUGH THE SEGMENT BEING DRAWN WE ARE, and whether the queue owes us a new one.
	# Clamped at 1 inside `AssayScene.playout`, which is the whole safety of the thing: past the end
	# of a segment the body stops on the newest position it has been given rather than carrying on
	# toward one the sim has not produced. 1.0 before any tick has landed, so an unplayed world draws
	# everyone exactly where the Welcome put them.
	var part := _advance_playout(now, frame_dt)
	var players: Array = []
	var me: Variant = null
	var described := _players()
	# **THE REFUSAL, WHICH IS BOX 5's DECISION AND NOT A DROPPED PLAYER.** An empty list here is two
	# different worlds -- one nobody has joined yet, and one whose binding stopped describing people --
	# and only the second may blank the screen. `_players()` tells them apart; a mid-join frame and
	# `--selfcheck` both legitimately have no players and must still draw their world.
	if not _player_facts_missing.is_empty():
		_world.view = {}
		_world.me = null
		_refresh_front_door()
		_world.queue_redraw()
		return
	# THE TWO SIM FACTS THE CLICK ECHO DIES ON (ASSA-215), picked up in the loop that is already
	# reading my player: the tile the sim says I am ON, and the tile the sim says it is walking me
	# TO. Null when the sim has not said -- which is the normal state for the first 190-394 ms after
	# a click and is why `walk_echo` cannot read a missing target as "stop drawing it".
	var my_pos: Variant = null
	var my_target: Variant = null
	for entry in described:
		var player: Dictionary = entry
		var id := int(player.get("id", -1))
		if id == _client.player_id:
			my_pos = player.get("pos")
			my_target = player.get("target")
		var at_now: Vector2i = _seen.get(id, player.get("pos", Vector2i.ZERO))
		var at_was: Vector2i = _was.get(id, at_now)
		players.append({
			"at": Vector2(at_was).lerp(Vector2(at_now), part),
			"facing": String(_facing.get(id, "")),
			"moving": at_was != at_now,
		})
		if id == _client.player_id:
			me = players[players.size() - 1]["at"]
	# THE CAMERA IS ON YOUR DRAWN POSITION, not on your tile, or the world would jerk 32 px under a
	# body that is moving smoothly over it. Spawn when you have no player yet, which is the state
	# `--selfcheck` and a mid-join frame are both in.
	# `_north_room` IS WHY YOU ARE STILL ON SCREEN IN ROW 0 (ASSA-184). The y clamp used to stop at
	# the world's edge, which is where the event log's panel is: standing in the top eight rows slid
	# your body up behind it. The bound is the panel's, derived from the same manifest.
	var origin := AssayScene.camera_origin(me if me != null else Vector2(_sim.spawn_tile()),
			size, _world.size, _north_room)
	_world.view = {
		"world_tiles": size,
		"origin": origin,
		"size": _world.size,
		"spawn": _sim.spawn_tile(),
		"ore": _ore_under(origin, size),
		"players": players,
		# STRAIGHT FROM THE SIM, UNCHANGED AND UNCACHED. The list is one dictionary per building and
		# there are single digits of them; `_ore_under` is cached because it is ~580 `tile_at` calls
		# over the window, which is a different problem.
		"buildings": _sim.buildings(),
		"manifest": _manifest,
		# THE PART CONTRACT, for the one building with no sheet. Beside the manifest and not inside
		# it for `AssaySprites`' own reason: the manifest's top level is an asset namespace and
		# `build.py` drops anything there that is not an asset (ASSA-54/71).
		"layout": _layout,
		"seconds": now,
	}
	_world.me = me
	# **THE CLICK ECHO, RE-DERIVED EVERY FRAME AND CLEARED ONLY HERE** (ASSA-215). The input handler
	# sets it; this is the only place that can take it away, which is what keeps "it clears when the
	# walk arrives" a fact about the SIM's position rather than about the drawn one -- the body is
	# still tweening toward that tile for up to a tick after the sim has put it there.
	#
	# `refused` IS FALSE HERE AND THAT IS NOT A SHRUG: a refusal is an event, not a per-frame state,
	# and `_on_refused` already passes `true` through this same function the moment one arrives. A
	# flag latched for the refresh to read would be a mark that survives one more frame than the
	# refusal that killed it, on the one surface whose whole job this frame is answering the click.
	_walk_echo = AssayScene.walk_echo(_walk_echo, my_target, my_pos, false)
	_world.destination = _walk_echo.get("tile")
	# **AND WHAT THE BUTTONS ACT ON** (ASSA-276 move 4). `_targeted` and not `_target_tile()`: with
	# nothing targeted the buttons act on your own feet, and the foot mark already says where those
	# are -- an outline permanently wrapped round your own body would be a second mark for a fact
	# this surface already carries, which is the 22nd-literal mistake in shape form.
	#
	# RE-READ EVERY REFRESH RATHER THAN PUSHED FROM THE INPUT HANDLER, which is the opposite choice
	# to `destination` one line up and deliberately so: a click echo is an unanswered input that
	# only the player's own click knows about, while `_target` is state this screen already owns.
	# Pushing it would give the same fact two writers and a way to go stale.
	_world.selection = _target if _targeted else null
	_refresh_front_door()
	_world.queue_redraw()


## WHICH TILES UNDER THE CAMERA HOLD ORE, as the sim answered it, cached.
##
## THE SIM DECIDES, ONE TILE AT A TIME, and that is not laziness about a faster query. A deposit's
## `radius` is a CIRCLE (`tile_at`: "radius is a circle, not a square") and `contains` is sim code, so
## a client walking the bounding box itself would eventually draw rock on tiles that cannot be mined
## -- a picture that lies about where the game stops working. ~580 calls for a 28x18 window, which is
## why this is cached rather than why it is done differently.
##
## WHAT INVALIDATES IT: the window moving, or a patch running out. `depleted` is the only fact about a
## deposit that changes what is DRAWN -- the row becomes `depleted_full` -- and `amount` appears on no
## sprite, which is `sim`'s own position: one number for the whole patch, so a sparser rim would be a
## mark for a difference the game does not have.
func _ore_under(origin: Vector2, size: Vector2i) -> Dictionary:
	var window := AssayScene.visible_tiles(origin, _world.size, size)
	var stamp := _ore_stamp
	if _sim.tick() != _ore_tick:
		_ore_tick = _sim.tick()
		var bits := PackedStringArray()
		for entry in _sim.deposits():
			bits.append("1" if bool((entry as Dictionary).get("depleted", false)) else "0")
		stamp = "".join(bits)
	if window == _ore_at and stamp == _ore_stamp:
		return _ore
	_ore_at = window
	_ore_stamp = stamp
	_ore = {}
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var at := Vector2i(x, y)
			var patch: Variant = (_sim.tile_at(at) as Dictionary).get("deposit")
			if patch == null:
				continue
			var deposit: Dictionary = patch
			_ore[at] = {
				"species": int(deposit.get("species", 0)),
				"grade": String(deposit.get("grade", "C")),
				"depleted": bool(deposit.get("depleted", false)),
			}
	return _ore


## WHERE EVERYONE IS NOW AND WAS ONE TICK AGO. Called after a bundle has been applied, so "now" is
## the world the sim just produced and the previous "now" becomes "was".
##
## THE FACING IS THE STEP THEY ACTUALLY TOOK, never the direction of their `target`. A target is an
## INTENTION -- the walk line draws it as one -- and a sprite turned to face an intention is turned by
## a rule this client worked out, which is the prediction Maren's ruling forbids. The last real step
## is remembered so a player who has stopped keeps looking the way they were going instead of
## snapping south.
func _remember_positions() -> void:
	var produced := {}
	for entry in _players():
		var player: Dictionary = entry
		produced[int(player.get("id", -1))] = player.get("pos", Vector2i.ZERO) as Vector2i
	var now := float(Time.get_ticks_msec()) / 1000.0
	# **STAMPED WITH THE SIM'S OWN TICK NUMBER** (ASSA-197), which is the timeline the clock runs on.
	# The arrival time stays for diagnostics and for the rate, but it no longer decides when a
	# segment may start -- that was the arrival-driven playout the board felt as jumpy.
	_pending.append({"at": now, "tick": _sim.tick(), "where": produced})
	while _pending.size() > PLAYOUT_QUEUE:
		_pending.pop_front()
	# THE RATE, OVER A WINDOW RATHER THAN AN EMA. Arrivals come in pairs 0.17 ms apart at this frame
	# rate; an EMA of consecutive gaps swings by a factor of ten and used to be the denominator the
	# whole tween was divided by. `playout_step` takes the mean over the window instead.
	_tick_times.append(now)
	_tick_numbers.append(_sim.tick())
	while _tick_times.size() > AssayScene.PLAYOUT_RATE_WINDOW:
		_tick_times.pop_front()
		_tick_numbers.pop_front()
	_tick_gap = AssayScene.playout_step(_tick_times, _tick_numbers, _tick_gap)
	_tick_at = now
	# ADVANCED ON THIS PATH TOO, not only on a drawn frame, and that is not belt-and-braces: every
	# headless test and probe runs inside `SceneTree._initialize` where `_process` never fires, so a
	# playout that only moved on a frame would leave the suite drawing a body that never starts.
	#
	# **BUT NOT ONCE FRAMES ARE DRIVING THE CLOCK** (ASSA-197). With the frame's own delta as the
	# step, an arrival that also advanced would add its own wall-clock gap on top of a frame's delta
	# and the clock would run fast by whatever fraction of the frame it landed in. In a window
	# `_process` fires for seconds before any bundle arrives, so this is off by the time it matters;
	# headless, nothing ever sets it and the behaviour is exactly as it was.
	if not _frames_drive_playout:
		_advance_playout(now)


## MOVE THE DRAWN SEGMENT ON IF THE PLAYOUT CLOCK SAYS SO, and answer how far through it we are.
##
## THE DECISION IS `AssayScene.playout` AND NOT THIS FUNCTION. The arithmetic is where every other
## renderer decision lives -- pure, static, and unit-tested without an engine clock or a socket --
## because it is exactly the kind of thing that looks obviously right and is not: the resume rule
## alone has two cases, and getting the second one wrong reproduces a smaller copy of the defect this
## whole item is about. This half only moves dictionaries.
##
## THE FACING IS TAKEN AT PROMOTION, so the sprite faces the step it is DRAWING rather than one the
## sim has produced but nobody has seen yet. Still the step they actually took, never a target.
func _advance_playout(now: float, frame_dt := -1.0) -> float:
	if _pending.is_empty():
		return 1.0
	if frame_dt >= 0.0:
		_frames_drive_playout = true
	var ticks: Array[int] = []
	for entry in _pending:
		ticks.append(int(entry["tick"]))
	# **THE FRAME'S OWN ELAPSED TIME, FROM THE ENGINE, clamped** (ASSA-197). `frame_dt` is the delta
	# `_process` was handed; the fallback is "time since the clock last moved", which is what every
	# caller that is not a frame has to use -- a bundle landing in a headless harness, where
	# `_process` never fires at all.
	#
	# THEY ARE NOT THE SAME NUMBER AND THE DIFFERENCE IS A PLAYER-VISIBLE ONE. The fallback is built
	# from `Time.get_ticks_msec()`, quantised to a millisecond, and it measures the gap between the
	# clock's own advance instants rather than between two frames -- so the movement published in a
	# frame was sized for an interval the frame was not shown for. See `_process`.
	var dt := 0.0 if _played_at <= 0.0 else clampf(now - _played_at, 0.0, 1.0)
	if frame_dt >= 0.0:
		dt = clampf(frame_dt, 0.0, 1.0)
	elif _frames_drive_playout:
		# **ONLY A FRAME MOVES THE CLOCK.** This function is also reached from a tick landing and
		# from two UI refreshes, none of which is a frame; while frames are driving the clock those
		# callers repaint at the position it is already at. Letting them advance by their own
		# wall-clock gap is how a bundle that lands mid-frame used to add that gap on top of the
		# frame's delta -- the clock then runs fast by the fraction of the frame it landed in, and
		# the body is drawn somewhere the next frame has to take back.
		dt = 0.0
	_played_at = now
	# **HOW LONG AGO THE NEWEST POSITION LANDED**, so the loop's error is measured against what the
	# host has produced by now rather than against its last whole tick (see `playout_at`): the
	# difference is a ±10% modulation of the body's speed at the tick rate. Zero on the frame a
	# bundle lands, which is when `_tick_at` is set.
	var since := 0.0 if _tick_at <= 0.0 else maxf(now - _tick_at, 0.0)
	var cursor := AssayScene.playout_at(_play_tick, ticks, dt, _tick_gap, AssayScene.PLAYOUT_DELAY,
			since, _play_trim)
	_play_tick = float(cursor["play_tick"])
	_starved = bool(cursor["starved"])
	# THE INTEGRAL GOES BACK IN NEXT FRAME. `playout_at` is pure, so the one piece of state the PI
	# loop needs is carried by its caller and by nothing else.
	_play_trim = float(cursor["trim"])
	_play_depth = float(cursor["depth"])
	if bool(cursor["dragged"]):
		_play_dragged += 1
	_play_advances += 1
	var index := int(cursor["index"])
	# EVERYTHING THE CLOCK HAS GONE PAST IS DROPPED, except the position being drawn FROM. `_pending`
	# keeps its documented meaning for the probes that read its depth: produced positions the screen
	# has not finished drawing.
	for _i in range(index):
		_pending.pop_front()
	var from: Dictionary = _pending[0]["where"]
	var to: Dictionary = _pending[1]["where"] if _pending.size() > 1 else from
	# THE FACING IS TAKEN WHEN THE SEGMENT CHANGES, not every frame, and it is still the step the
	# body is DRAWING rather than one the sim has produced but nobody has seen (ASSA-119).
	if _seen != to or _was != from:
		for id in to:
			if from.has(id):
				var way := AssayScene.facing_of((to[id] as Vector2i) - (from[id] as Vector2i))
				if way != "":
					_facing[id] = way
	_was = from
	_seen = to
	return float(cursor["part"])


## **CAN THIS PLAYER SWING AT THE ROCK THEY ARE STANDING ON, RIGHT NOW** (ASSA-233).
##
## THREE FACTS, ALL THE SIM'S: there is a deposit under us, it is not worked out, and the sim says a
## hand can break it. `hand_minable` is `sim::ladder::hand_minable`'s answer carried across the
## binding as a BIT -- never the deposit's sentence, which is prose for a person and is a wider gate
## than this one (it also covers rock you can mine and cannot smelt).
##
## **THE TILE IS `_my_tile()` AND NOT THE TARGET**, because that is what the button does: "hand-mine
## the deposit under you". Reading the cursor's tile here would light the accent for a rock across
## the map that this press would not touch.
func _can_hand_mine_here() -> bool:
	if not _sim.running():
		return false
	var deposit: Variant = _sim.tile_at(_my_tile()).get("deposit")
	if deposit == null:
		return false
	var rock: Dictionary = deposit
	return bool(rock.get("hand_minable", false)) and not bool(rock.get("depleted", false))


func _my_tile() -> Vector2i:
	for entry in _players():
		var player: Dictionary = entry
		if int(player.get("id", -1)) == _client.player_id:
			return player.get("pos", Vector2i.ZERO) as Vector2i
	return _sim.spawn_tile()


## TWO THINGS A MOUSE DOES ON THE MAP, and which is which matters.
##
## LEFT CLICK WALKS. The command is the same `PlayerCommand::MoveTo` `sim-cli` sends; the sim decides
## whether it is legal and the movement system walks us one tile per tick. NOTHING MOVES HERE -- the
## player on screen moves when a bundle carrying this command comes back around.
##
## RIGHT CLICK CHOOSES THE TILE THE BUTTONS ACT ON (ASSA-37). Place, Insert and Take all need a tile,
## and ONE mechanism serving all three is what keeps the rule explainable: a placement is never a
## second click on a button, and a click never means two things at once. Walking kept the left button
## because it is the thing a player does most.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_track_hover(event.position)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var at: Variant = _tile_under(event.position)
	if at == null:
		return
	var tile: Vector2i = at
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_target = tile
		_targeted = true
		_say("acting on %d, %d" % [tile.x, tile.y], AssayHud.Say.JOINED)
		_refresh()
		queue_redraw()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _client.submit(AssayActions.move_to(tile)):
		_say("walking to %d, %d" % [tile.x, tile.y], AssayHud.Say.JOINED)
		# **THE ONE THING ON THIS SCREEN THAT ANSWERS IN THE FRAME YOU CLICKED IN** (ASSA-215).
		# Everything else about this walk takes 190-394 ms: the command goes to the host, the host
		# orders it into a tick, the bundle comes back, the playout buffer holds it. So this is set
		# here, inside the input handler, and NOT in `_refresh_world` from the sim's own `target` --
		# that is the same quarter second of silence with extra steps.
		#
		# **IT IS WRITTEN TWICE, AND I MEASURED WHAT EACH WRITE IS WORTH RATHER THAN ASSERTING IT.**
		# Deleting this line and keeping only `_refresh_world`'s costs NOTHING on Godot 4.6: input is
		# flushed before `_process` in the same iteration, so the refresh still publishes the tile
		# before that frame is drawn -- `tools/limpet_click_echo.gd` reported the mark in the click's
		# own frame with this line removed. I had written the opposite here ("correct in every frame
		# but the first") and the lever said no.
		#
		# It stays because the guarantee is then this file's rather than the engine's frame ordering,
		# and because the refresh is skipped entirely while the schematic is up. The lever that DOES
		# bite is the other one: delete the refresh's write and the mark appears on the click and
		# then never clears, which that tool's clause (4) catches.
		#
		# NO `_refresh()` HERE. That rebuilds the whole HUD (the schematic, every panel) and this is
		# eight rectangles on the scene; the right-click branch above calls it because a TARGET
		# changes what the buttons say.
		_walk_echo = {"tile": tile, "confirmed": false}
		_world.destination = tile
		_world.queue_redraw()


## Which tile a screen position is on, or null for anywhere that is not a tile. ONE PLACE DOES THIS,
## because a hover readout that disagreed with where a click goes would be worse than no readout.
## TWO VIEWS, TWO PIECES OF ARITHMETIC, ONE FUNCTION. The scene is the camera's offset inverted; the
## schematic is the tile size it was painted at. A second copy of either would be a click that lands
## on a tile next to the one the player is pointing at, which is the kind of wrong that gets blamed on
## the sim.
func _tile_under(at: Vector2) -> Variant:
	if not _sim.running():
		return null
	var size := _sim.size_tiles()
	var tile := Vector2i.ZERO
	if _close_up:
		var world := AssayHud.world_rect()
		if not world.has_point(at):
			return null
		# The camera the view was last BUILT with, not one recomputed here: the body is mid-tween and
		# a camera worked out a frame later would be a few pixels along from the picture that was
		# clicked. `_refresh` keeps this current on every tick, headless included.
		tile = AssayScene.tile_at_point(at - world.position,
				_world.view.get("origin", Vector2.ZERO))
	else:
		if _cell <= 0.0:
			return null
		var cell := ((at - MARGIN) / _cell).floor()
		tile = Vector2i(int(cell.x), int(cell.y))
	if tile.x < 0 or tile.y < 0 or tile.x >= size.x or tile.y >= size.y:
		return null
	return tile


## WHERE ON SCREEN A TILE IS: the centre of it, in whichever view is up. `_tile_under`'s inverse, and
## the one thing on this node with no leading underscore because it is the only thing outside it that
## needs to point at a tile.
##
## IT EXISTS BECAUSE THIS ITEM BROKE SEVENTEEN TESTS, and the failure is worth writing down. Three
## places -- `tests/test_buttons.gd`, `tests/test_species_panel.gd` and `tools/button_play.gd` -- each
## held their own copy of `MARGIN + (tile + 0.5) * _cell`, which was correct for exactly as long as
## there was one view. The moment the close-up became the default they were all pressing a point 40
## tiles from the tile they named, and the symptom was "walked toward the deposit at (74, 36) and
## stopped at (63, 41)": a sim that looked like it had refused a walk. Nothing in those three files
## was wrong about the game; they were wrong about the screen, which is not their subject.
##
## `tests/test_scene_view.gd` asserts the round trip (`_tile_under(point_of_tile(t)) == t`) in BOTH
## views, so the pair cannot drift again without a red suite.
func point_of_tile(tile: Vector2i) -> Vector2:
	if not _close_up:
		return MARGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * _cell
	var world := AssayHud.world_rect()
	var origin: Vector2 = _world.view.get("origin", Vector2.ZERO)
	return world.position + (Vector2(tile) + Vector2(0.5, 0.5)) * AssayScene.TILE_PX - origin


func _track_hover(at: Vector2) -> void:
	var tile: Variant = _tile_under(at)
	var now_on: bool = tile != null
	# Off the map, the readout goes back to your own tile rather than freezing on the last tile the
	# mouse crossed, which would be a stale answer that looks live.
	if not now_on:
		if _hovering:
			_hovering = false
			_refresh()
			queue_redraw()
		return
	var found: Vector2i = tile
	if _hovering and found == _hover:
		return
	_hover = found
	_hovering = true
	_refresh()
	queue_redraw()


## THE WHOLE-WORLD SCHEMATIC: bounds, every deposit, every FACTORY, every player, and spawn. THE
## SECOND VIEW NOW. (Buildings only since ASSA-189: for a month this list was four things and the one
## the game is about was not among them.)
##
## THE SPRITES ARE DRAWN, AND THEY ARE NOT DRAWN HERE. ASSA-119 is the camera at 32 px a tile, and it
## lives in `AssayScene` + `AssayWorldLayer` over the same rectangle this paints -- `_close_up` says
## which of the two is up. This function is the one that fits a 96x64 world into 912x672, which is
## what makes it a map rather than a view.
##
## THAT WAS THE ONE THING IN THE WAY FOR TWO ITEMS (ASSA-46). A tile here is 9 px (measured; 18 px on
## a 32x32 world) against a 64 px frame of art, which is a 7x downscale, and the art direction's one
## rule is readability at 1x. Cove measured what it costs: the sprite does not degrade into the disc,
## it becomes speckle 29 dE from flat. So the answer was never sprites on THIS map -- it was a second
## view at the size the pipeline has been authoring for since the first asset (`art/rig.py:18`).
##
## AND IT SURVIVES RATHER THAN BEING REPLACED, on Maren's ruling, for three reasons that are all about
## what a close-up cannot do: it is how you cross 96x64, it carries players you are nowhere near, and
## its species discs and glyphs are the only colour-blindness-MEASURED read on this screen (Decision
## #36 -- worst observer dE 18.3, glyph contrast 4.52 over all six species and all 100 purities).
##
## Two older reasons for the lack of sprites are long gone and worth naming, because this comment has
## been wrong twice and each time it sent a reader to the wrong place. It was never the ART (the ore
## art is species-neutral and tinted since ASSA-19/20, and `AssayHud.SPECIES_TINTS` is checked against
## the pipeline's copy in CI), and it stopped being a PATH at ASSA-34 (`res://` is `client/`, so
## `art/build.py` writes into the project; `tests/test_sprites.gd` holds the engine's half).
func _draw() -> void:
	# A self-check run returns out of `_ready` before there is a client, and the engine still calls
	# `_draw` once. In the editor that is a caught script error; in an EXPORTED RELEASE BUILD it
	# segfaulted on exit (measured: exit 139 after the marker was already written). Nothing to draw
	# without a client is also just true.
	if _client == null or not _sim.running() or _close_up:
		return
	var size := _sim.size_tiles()
	if size.x <= 0 or size.y <= 0 or _cell <= 0.0:
		return
	draw_rect(Rect2(MARGIN, Vector2(size) * _cell), AssayHud.mark_ink(&"ground"), true)

	# **ONE TILE, NOT FOUR CELLS** (ASSA-206 box 7, Maren's ruling, taken on two real shots). It was
	# `cell * 4` square here: 36x36 px, 1296 px, 5.1x the player mark and the largest non-deposit mark
	# on the view, for a fact about ONE tile. The geometry is `AssayHud.spawn_pad_rect` -- including
	# the clause that keeps it no bigger than a person on a world with fatter tiles -- so a test can
	# read the size this view gives it instead of a human counting pixels in a shot.
	var spawn := _sim.spawn_tile()
	draw_rect(AssayHud.spawn_pad_rect(spawn, _cell, MARGIN), AssayHud.mark_ink(&"spawn"), true)

	# SPECIES IS A DESIGNED SLOT, PURITY IS BRIGHTNESS, and the rule plus the two versions of this I
	# got wrong are in `AssayHud.deposit_color`. Grade bands (C < 40, B 40-69, A >= 70) are the
	# sim's, not invented.
	#
	# AND COLOUR IS NOT THE ONLY READ: the species' letter goes on the patch, once per deposit
	# (Decision #36). The tints clear the colour-blindness floor by single digits, so for the ~8% of
	# men with a red-green deficiency the glyph is the read and the colour is the hint. `symbol`
	# comes from the sim -- a generated name's initial, distinct per world -- never from the first
	# character of a name a player may have renamed.
	# **AND THE LETTER IS NOT PAINTED HERE ANY MORE** (ASSA-213, Maren's P1): it is the last mark on
	# this view, below, because a 16 px building diamond on a deposit's centre tile was painting out a
	# 25 px letter whole. The list is read ONCE and handed to both passes -- the discs here and
	# `_glyph_marks` down there -- so the two cannot be looking at different worlds.
	var font := ThemeDB.fallback_font
	var deposits := _sim.deposits()
	for entry in deposits:
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) <= 0:
			continue
		# **THE TILE'S MIDDLE, THROUGH `point_of_tile`, AND NOT A COPY OF ITS ARITHMETIC** (ASSA-220).
		# This read `MARGIN + Vector2(centre) * _cell` -- the tile's top-left CORNER -- while the player,
		# the spawn pad and every building mark used its middle, so at 9 px a tile every rock on this map
		# was drawn 4.5 px up and left of itself. Maren's law on ASSA-213 is that a mark may lie about its
		# size or its colour to be legible and never about its POSITION, and she refused an offset mark at
		# 13-15 px under it; this was 4.5 px in the opposite direction and had been shipping the whole
		# time. The hatch follows for free, being a pure function of `at`.
		var at := point_of_tile(deposit.get("center", Vector2i.ZERO) as Vector2i)
		var radius := maxf(_cell, float(int(deposit.get("radius", 1))) * _cell)
		# **HATCHED IF NOTHING CAN GET THE ORE OUT, CLEAN IF THE ROCK PAYS** (ASSA-199, Maren's
		# ruling on Cove's sheet; it replaces the outline ASSA-187 shipped). Three channels were
		# already spoken for -- hue is the species, brightness is the purity, radius is the radius --
		# and the fact that decides whether a 40-tile walk pays had none, on the one surface whose
		# whole job is choosing where to walk. The answer is geometry, so it survives a greyscale
		# copy of the shot, which Maren's box 3 asks for; and it is SUBTRACTIVE, so the clean disc
		# is what the eye picks out, which is the right way round when 55.1% of rocks are dead.
		#
		# THE DECISION IS `AssayHud.deposit_disc`'S AND NOT THIS LOOP'S, so a headless test can read
		# it: nothing here can be asked what it painted. This function only paints what it is told,
		# and the geometry of the hatch is `AssayHud.hatch_segments`, a pure function of the circle.
		var disc := AssayHud.deposit_disc(deposit, radius)
		var colour: Color = disc["colour"]
		# **ALWAYS SOLID NOW** (ASSA-199 box 4). #259 drew a dead end as a hollow ring, which
		# spent the fill that purity's brightness and the species hue both live in; Maren ruled
		# Cove's hatch instead, and the hollow is GONE rather than left underneath it.
		draw_circle(at, radius, AssayHud.mark_ink_of(&"deposit", colour))
		if bool(disc["hatch"]):
			# **BEFORE THE LETTER, WHICH IS WHAT KEEPS THE LETTER.** Cove's constraint is that the
			# hatch repaints only pixels already inside the disc: the strokes are cut to the chord
			# so the edge survives, and the glyph simply goes on last. An ORDER, not a clip -- and
			# the one frame-ordering fact in here I do not have to ask the engine about.
			var strokes := AssayHud.hatch_segments(at, radius)
			var ink: Color = disc["hatch_ink"]
			var thick := float(disc["hatch_width"])
			for i in range(0, strokes.size(), 2):
				draw_line(strokes[i], strokes[i + 1], AssayHud.mark_ink_of(&"dead_end", ink), thick)

	# EVERY PLAYER, AT A SIZE THAT DOES NOT COME FROM THE TILE (ASSA-119 box 6, Maren's finding 1).
	# This mark used to be two cells square, which made it 18 px on this world and would make it 36 on
	# a small one -- so the bigger and more confusing the world, the smaller you got. Measured on the
	# real shot: 324 px of an 864x576 view, 0.065% of it, smaller than all eleven deposits and twelve
	# times smaller than one pink patch. `AssayHud.PLAYER_MARK_PX` now says how big a person is on any
	# world, and yours carries a ring so two players at the same size are still told apart.
	#
	# **THE SIZE IS STILL HERS AND THE SHAPE IS NOT A RECT ANY MORE** (ASSA-236). The box held a
	# `Vector2` of that constant to build two `draw_rect`s from; the geometry is `AssayHud.player_mark`
	# now, for `building_mark`'s reason -- a suite cannot read a polygon back off a canvas, and the
	# three marks a co-op player separates at a glance are exactly what QA got backwards.
	for entry in _players():
		var player: Dictionary = entry
		# THROUGH `point_of_tile` TOO, AND THIS ONE MOVES NOTHING (ASSA-220). It spelled
		# `MARGIN + (pos + 0.5) * _cell` itself, which is byte-for-byte what `point_of_tile` returns in
		# this view -- so it was CORRECT and still a copy. It is converted because the copies are the
		# defect: the disc's corner formula and this one sat eight lines apart, and nothing could tell
		# you which of the two was the odd one out. The suite proves no player mark moved.
		var at := point_of_tile(player.get("pos", Vector2i.ZERO) as Vector2i)
		var mine := int(player.get("id", -1)) == _client.player_id
		var colour := AssayHud.mark_ink(&"player_mine" if mine else &"player_theirs")
		# Where the sim is walking them, drawn as a line to there. Not a tween: the sim owns the
		# position and this is its intention, not a frame of motion we invented. (The scene DOES
		# tween the body, between two positions the sim produced -- Maren's motion ruling -- and this
		# line stays a line there for the same reason it is one here.)
		var target: Variant = player.get("target")
		if target != null:
			draw_line(at, point_of_tile(target as Vector2i),
					AssayHud.mark_ink_of(&"walk_mine" if mine else &"walk_theirs", colour), 1.0)
		# **A KEYLINE ON A PERSON, WHICH IS MAREN'S SECOND RULING ON ASSA-189 AND A DEFECT THAT WAS
		# ALREADY SHIPPING.** `THEIRS` is a pale near-white, and with no rim a partner standing on a
		# deposit with a light species letter fuses with that letter into one blob -- Cove found it
		# hunting for a control for their own keyline-0 diamond, which failed the same way. Drawn
		# UNDER the body and growing outwards, so the 16 px Maren set from a measurement is untouched
		# in pixels and the rim is not paid for out of the body.
		#
		# **A PERSON IS NO LONGER A FILLED RECT** (ASSA-236, Maren: "a point (you) gets the footprint
		# shape"). You are a diamond carrying your ring, a partner is a cross, and the square they both
		# were belongs to the one thing on this map with a tile footprint. The rim is the same device at
		# the same 2 px on both bodies, which is why it stays one call -- `AssayHud.player_mark` picks the
		# shape and the keyline's id follows it, so the table can still say which body each rim is under.
		var person := AssayHud.player_mark(at, mine)
		draw_colored_polygon(person["keyline_points"],
				AssayHud.mark_ink(&"player_keyline" if mine else &"partner_keyline"))
		draw_colored_polygon(person["points"],
				AssayHud.mark_ink_of(&"player_mine" if mine else &"player_theirs", colour))
		if mine:
			# YOUR RING IS A DIAMOND RING NOW, for the same reason the body changed: a yellow 25.6 px
			# SQUARE outline round you, on a map where a hollow square is what a machine's footprint
			# looks like, would put this item's own defect back one line below its fix. A closed
			# polyline, so the stroke straddles its path exactly as `draw_rect(..., false, 2.0)` did.
			var ring := person["ring_points"] as PackedVector2Array
			ring.append(ring[0])
			draw_polyline(ring, AssayHud.mark_ink_of(&"mine_ring", colour), 2.0)

	# EVERY FACTORY, WHICH THIS VIEW DID NOT DRAW AT ALL UNTIL ASSA-189.
	#
	# **AFTER THE PLAYERS, WHICH IS WHAT MAREN RULED ON ASSA-203 (01:22Z, box 5) AND WHAT THE CALLS
	# IN THIS FUNCTION DO:** deposits, then players, then these marks, then the species letter last
	# (ASSA-213). Cove's hand-off and Maren's 17:40 ruling had both said deposits -> buildings ->
	# players, for a reason that is right as a sentence: *a drill must be visible on the rock it
	# works, and a person must never be hidden by a thing.*
	#
	# **THIS PARAGRAPH CLAIMED THE OPPOSITE FOR A DAY AFTER THE RULING LANDED** -- "the one clause of
	# the approved design I have not applied, and it is open for Maren to rule" -- sitting directly
	# above the calls that refute it. Maren read it and believed it for a minute before checking the
	# line numbers (ASSA-203, 02:55). Mine, and left there by me: nothing tests prose and this studio
	# reads its own prose as fact (ASSA-207). What she measured when she ruled: of a machine's mark,
	# 134 px -- 92.4% -- survives with the buildings painted after the players and 0 px, 0.0%, with
	# them painted before; a smelter's 162 px survives either way, because nobody stands on it.
	#
	# The measurement is that on this world it costs the first half to buy the second. The play loop
	# plants on the tile you are STANDING on (`_targeted` false is "where you stand"), so a machine's
	# mark and your body are at the same point TO THE PIXEL, and the mark is `BUILDING_MARK_PX` 16
	# against a 16 px filled square: at the approved size a diamond is exactly INSCRIBED in the body
	# that would be painted over it. Not mostly hidden -- gone. The keyline does not rescue it either:
	# its four points clear the body by 2.8 px and they are `MAP_BG` drawn on a `MAP_BG` background.
	# `shared/assay/limpet-assa203-both-orders-14247/` has both frames at 1x and the surviving-pixel
	# count for each.
	#
	# **AND THE ORDER ONLY WORKS AT ALL BECAUSE OF THE SHAPE.** A diamond leaves its bounding box's
	# corners alone, so a player under a building still shows four triangles of their own colour --
	# half the body's area -- and your hollow ring (1.6x the body, outside the mark entirely) is
	# untouched at any footprint. A filled rect on top, Maren's banned shape, really would hide the
	# person, which is why "buildings last" is only an option on the shape Cove picked.
	#
	# **SINCE ASSA-236 THE ORDER COSTS NOTHING, AND THAT IS THE ITEM'S REAL FINDING.** 92.4% against
	# 0.0% was never a fact about the order: it was what two FILLED marks on one tile do to each other,
	# and the diamond was a way of losing less. The mark is a hollow footprint frame now, so the
	# machine keeps 100% of it either way and the person under it keeps everything but the tips their
	# own shape pokes through the bands. Measured at the shipped sizes on the replica in
	# `shared/assay/cove-assa236/`: a partner standing on a drill keeps 25.3% of their mark today and
	# 70.4% with the frame. The order below is unchanged -- there is no longer anything to trade.
	#
	# THE DECISION IS `AssayHud.building_mark`'S, like the disc's above, and this loop only paints what
	# `_building_marks` hands it -- see that function for why a test can read it and this cannot.
	# HELD IN A LOCAL AND NOT CALLED TWICE: the glyph pass below asks `letter_occlusions` which of
	# these diamonds laps a letter (ASSA-218 box 9), and two calls could be two different worlds in
	# the same frame -- the mistake `window_shot.gd` already carries a comment about.
	var shapes := _building_marks(_sim.buildings())
	for shape_entry in shapes:
		var shape: Dictionary = shape_entry
		# **FOUR BANDS AND FOUR BANDS, NOT A STROKE** (ASSA-236). The rim is drawn OUTSIDE the frame so
		# the frame keeps every pixel of its own size -- the same rule the diamond's two polygons kept --
		# and the frame itself is four filled rects because an unfilled `draw_rect` straddles the edge it
		# is given, which on this mark would put white on the tile next door at every machine on the map.
		for band: Rect2 in AssayHud.frame_bands(shape["keyline_rect"], AssayHud.MARK_KEYLINE_PX):
			draw_rect(band, AssayHud.mark_ink_of(&"building_keyline", shape["keyline"]), true)
		for band: Rect2 in AssayHud.frame_bands(shape["rect"], float(shape["stroke"])):
			draw_rect(band, AssayHud.mark_ink_of(&"building", shape["colour"]), true)
		# **AND A RIM INSIDE THE HOLE, SO EVERY PIXEL OF THE BAND HAS A DARK NEIGHBOUR ON BOTH SIDES**
		# (ASSA-278, Maren ruled option 1 at 23:10 EDT). Drawn AFTER the frame and INSIDE it, so the
		# frame keeps every pixel of its own size -- the same rule the outward rim keeps. The species
		# letter is painted later still (the glyph pass below), so ASSA-213 is untouched: a letter on a
		# machine's tile still lands on top of both rims, and this does NOT fix ASSA-273.
		#
		# **I FILED THIS AS "A HOLLOW MARK SHOULD LOOK HOLLOW" AND THAT IS NOT THE RULING.** Hers is
		# about the band: without an inner rim the band's weight is rented from whatever the map put
		# under the mark, which on seed 63's grade-A disc was 1.53:1 and unreadable. A claim about the
		# hole is a claim about one seed's disc; a claim about the band's neighbours holds on any tint.
		#
		# **AND IT IS PAID FOR OUT OF THE PERSON STANDING THERE, WHICH MY OWN COSTING LEFT OUT.** These
		# marks go in AFTER the players (the paragraph above), so this rim is painted over them: a
		# partner on a 1x1 machine keeps 69.2% of their cross without it and 38.5% with it, and your
		# own body 85.3% -> 47.1% (your ring is outside the frame and untouched). Measured on the real
		# geometry by `tools/person_under_machine.gd`. ASSA-236's case for the hollow frame was that it
		# ENDED that trade (25.3% -> 70.4%), so this buys part of it back; the lever that would not is
		# painting this rim BEFORE the player pass, where a person replaces the rim they stand on and
		# their own MAP_BG keyline holds the band apart. That is Maren's to rule and it is on ASSA-278.
		for band: Rect2 in AssayHud.frame_bands(shape["hole_rect"], AssayHud.MARK_KEYLINE_PX):
			draw_rect(band, AssayHud.mark_ink_of(&"building_keyline", shape["keyline"]), true)

	# **THE SPECIES LETTER, LAST, BECAUSE A MACHINE STANDS ON THE ROCK IT WORKS** (ASSA-213, Maren's
	# P1: "a building mark may not remove the species letter from a deposit it stands on").
	#
	# WHAT WAS WRONG, AND IT WAS NOT AN UNLUCKY TILE. The letter was painted inside the deposit loop,
	# four passes before the factories. `sim/src/step.rs:213` checks bounds, occupancy and reach and
	# nothing else, so a building on a deposit is legal -- and it is the NORMAL case, because a drill
	# is on the rock it mines by definition. At 9 px a tile the diamond is 16 px and the letter 25, so
	# the diamond ate the middle of it: Maren photographed that at 1x on two seeds
	# (`shared/assay/maren-assa206-coop/`), and the map lost the one read that names ore.
	#
	# **THE ORDER IS THE FIX AND THE BED IS WHAT MAKES THE ORDER SAFE.** Painting a letter over a
	# `HOVER` diamond on its own would swap one erasure for another: `AssayHud.glyph_color` picks the
	# ink by contrast against the DISC, so a `GLYPH_LIGHT` letter chosen for a dark rock is white on a
	# pale diamond. Each letter therefore carries its own disc colour under its strokes. Over an
	# unoccupied disc the bed is the colour already there and nothing changes -- measured, not argued:
	# the four unhatched, unoccupied discs of seed 777042 read **0 px changed** with the whole bed
	# levered out (`shared/assay/marlow-assa218-bedclaim/sweep.py`).
	#
	# **IT IS NOT "THE SURFACE DECISION #36's 4.52 WAS MEASURED ON", WHICH IS WHAT THIS COMMENT SAID
	# UNTIL ASSA-218.** Every bed copy is an antialiased `draw_string`, so a bed pixel is a blend: on
	# the light-ink case the bed as drawn reads 4.35:1 against the letter where the bare fill reads
	# 9.20:1, and 5 of 63 bed pixels are the fill itself. What the bed buys is a readable EDGE at the
	# letter's boundary (13% -> 81% of it carrying 4.5:1 within 2 px), not the surround the ink was
	# picked against. See `AssayHud.GLYPH_BED_PX` for the table and the lever that produced it.
	#
	# **AND THE BED IS A STAMPED SILHOUETTE, NOT ONLY AN OUTLINE** (ASSA-218). The outline is
	# antialiased and left 87% of the letter's boundary inside a mark with no 4.5:1 edge, on the
	# light-ink majority (56.8% of the 600 species-and-purity states). See `GLYPH_BED_STAMPS`.
	#
	# **IT IS OVER THE PLAYER MARKS TOO, which is a consequence and not a preference.** Buildings are
	# painted after players (ASSA-203), so the only position that satisfies the ruling is after both.
	# A letter is strokes and not a fill, so a body keeps its own colour around them, and the pale
	# `THEIRS` body on a light letter is exactly the fusion ASSA-189's keyline was added for -- which
	# the bed now states instead of hoping for.
	#
	# **"THE 1x COST TO A BODY IS MEASURED IN THE ITEM" IS WHAT THIS LINE SAID, AND IT WAS FALSE**
	# (Maren, who went looking because I wrote the claim here rather than letting her find it).
	# ASSA-213 box 1 measures what a building costs a LETTER; box 5 says the player rect and ring are
	# untouched, which is true of their SHAPE in code and silent about what paints on top afterwards.
	# **No box on ASSA-213 measures a body at all.** It is now ASSA-221.
	#
	# WHAT IS MEASURED, AND IT IS SMALLER THAN THE FIRST ANSWER: Maren's geometry said 94.1% of a body
	# eaten, then she photographed it and corrected herself to **36.3% player ink left under the
	# letter against 100% for a body with nothing over it** -- the first figure measured the glyph on
	# an r=27 disc and applied that footprint to a body on a small one. "A control must be the same
	# object", her words, twice in one morning.
	#
	# **AND THE CASE THAT MATTERS IS STILL NOT PHOTOGRAPHED.** Your own mark carries the ring, which
	# grows OUTWARDS (`hud.gd`'s `PLAYER_MARK_PX` ring) and survives outside the glyph box, so you can
	# always find yourself. `THEIRS` is the body alone. The body that goes substantially missing is a
	# PARTNER's, on the one screen for "where is everyone", on a milestone called the minimal co-op
	# demo -- and the co-op shot tool spaced the two players four tiles apart, so no frame we have
	# holds a partner on a deposit centre. Do not build to a number here; ASSA-221 carries the state.
	#
	# THE DECISION IS `_glyph_marks`', like `_building_marks` above; this loop paints what it is told.
	for glyph_entry in _glyph_marks(deposits, font, shapes):
		var glyph: Dictionary = glyph_entry
		draw_string_outline(font, glyph["baseline"], glyph["symbol"], HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(glyph["size"]), int(glyph["bed_px"]),
				AssayHud.mark_ink_of(&"species_bed", glyph["bed"]))
		# **AND A SOLID CORE UNDER IT, ON THE LETTERS THAT NEED ONE** (ASSA-218, Maren's P1 on the half
		# of ASSA-213 that did not work, built as the fallback she named once I had measured her
		# condition for it). The outline above is antialiased, so a 2 px rim left the letter's boundary
		# inside a mark with a 4.5:1 edge on 13% of itself; stamping the letter once per neighbouring
		# pixel takes that to 81%. `AssayHud.GLYPH_BED_STAMPS` carries the five candidates I measured.
		#
		# **`bedded` AND NOT EVERY LETTER, BECAUSE THE PRICE IS REAL** (box 9): eight extra
		# `draw_string` each, 104 on a 13-letter world against ASSA-214's whole-map median of 42. A
		# letter with nothing over it and no hatch through it sits on its own disc, which is the
		# surface `glyph_color` picked its ink against, so the stamps buy it nothing. `_glyph_marks`
		# decides; this loop paints what it is told.
		#
		# **THE NUMBER MOVED WHEN MAREN AMENDED BOX 9** (lapped -> lapped OR hatched): on seed 777042
		# that is **9 of 13 letters, so 72 stamps** where lapped-only paid 8 and every letter would
		# pay 104. Said plainly, because I wrote the looser version first: 72 is **1.7x** ASSA-214's
		# whole-map median of 42, and what that costs in frame time is NOT measured by anyone. She
		# ruled it with the 96 -> 32 saving in front of her and the legibility delta beside it
		# (+1.16 to +2.43 ratio points per hatched letter); the trade is hers, the unmeasured half
		# is mine to say out loud.
		if bool(glyph["bedded"]):
			for offset: Vector2 in AssayHud.GLYPH_BED_STAMPS:
				draw_string(font, glyph["baseline"] + offset, glyph["symbol"],
						HORIZONTAL_ALIGNMENT_LEFT, -1, int(glyph["size"]),
						AssayHud.mark_ink_of(&"species_bed", glyph["bed"]))
		draw_string(font, glyph["baseline"], glyph["symbol"], HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(glyph["size"]), AssayHud.mark_ink_of(&"species_glyph", glyph["ink"]))

	# THE TILE THE BUTTONS ACT ON, AND IT IS A SHAPE NOW, NOT A THINNER YOU (ASSA-119 box 6).
	#
	# MAREN CORRECTED HERSELF ON THIS ONE AND THE CORRECTION IS THE INTERESTING HALF. She defended the
	# shared yellow in the morning -- you, your walk line and your target are one meaning, "yours", at
	# three weights, and the old comment here said so on purpose -- then measured the shot: at 9 px a
	# tile the weights are indistinguishable and a solid 18 px square beside a hollow 9 px one reads
	# as two of something. So the target keeps the tile it marks and loses the hue: four corner
	# brackets in the neutral ink, which cannot be mistaken for a body at any tile size, and no 22nd
	# colour literal added to the 21 she counted.
	# **THIS CORNER AND THE HOVER RECT BELOW ARE THE TWO PLACES THAT MUST NOT GO THROUGH
	# `point_of_tile`** (ASSA-220, Maren's second point). A RECT THAT COVERS A CELL IS NOT A MARK THAT
	# NAMES IT: these two start at the tile's top-left and span `_cell`, so the corner IS their correct
	# origin, and the brackets below are placed off it by `_cell` on each axis. The deposit pass used the
	# same expression for a CENTRE, which is probably where the habit came from -- so the arithmetic
	# looking identical to the bug three hundred lines up is not a reason to change it.
	if _targeted:
		var corner := MARGIN + Vector2(_target) * _cell
		var reach := maxf(4.0, _cell * 0.45)
		for step in [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)]:
			var from := corner + Vector2(0.0 if step.x > 0.0 else _cell,
					0.0 if step.y > 0.0 else _cell)
			draw_line(from, from + Vector2(reach * step.x, 0.0), AssayHud.mark_ink(&"target"), 2.0)
			draw_line(from, from + Vector2(0.0, reach * step.y), AssayHud.mark_ink(&"target"), 2.0)

	# The tile the readout is talking about, outlined. Drawn last so it is never buried, and only
	# while the mouse is actually over the map -- an outline left behind would point at an answer the
	# panel is no longer giving.
	#
	# **AND IT CARRIES A RIM NOW, WHICH IT WAS THE LAST MARK ON THIS MAP WITHOUT** (ASSA-284, Maren on
	# ASSA-275 box 5). At alpha 0.55 this outline has no value of its own, only the ground's, so on
	# grade-A ore it moved one channel -- `234,234,47` to `239,239,154`, nearly all of it BLUE, and
	# gone in a greyscale copy. Beside a machine it was worse than invisible: it ate one of the 2 px
	# that hold two hollow squares apart. **NOT FIXED BY PAINT ORDER**, which is the tempting one-line
	# version: hovering a machine's own tile is the commonest useful hover and this outline must stay
	# on top of it. The rim is drawn first, and INWARD -- which is a correction to the ruling and not
	# the ruling: outward it lands on the neighbouring tile, where a machine's own mark starts, and
	# the smelter's band went 242 -> 28 at the shared edge on both seeds. `AssayHud.hover_mark` carries
	# the rows. What inward does NOT fix is the outline's own pixel sitting on the machine's rim; that
	# needs the outline moved inside its own cell, which is ASSA-284's open box and Maren's call.
	if _hovering:
		var hover := AssayHud.hover_mark(_hover, _cell, MARGIN)
		draw_rect(hover["keyline_rect"], AssayHud.mark_ink(&"hover_keyline"), false,
				float(hover["width"]))
		draw_rect(hover["rect"], AssayHud.mark_ink(&"hover_tile"), false, float(hover["width"]))


## **WHAT THE SCHEMATIC IS ABOUT TO PAINT FOR EVERY BUILDING** (ASSA-189). One mark per building, in
## the map's own view pixels, at this screen's real `_cell` and `MARGIN`.
##
## **IT EXISTS SO SOMETHING CAN BE ASKED WHAT `_draw` PAINTED.** Nothing in a headless suite can read
## a `draw_colored_polygon` back off a canvas and `--headless` has no frame to photograph, so a
## building mark computed inside the loop would be unreachable by any test and checkable only by a
## human looking at a PNG -- which is how this view went a month with no factories on it. The
## geometry is here, the painting is three lines there, and `tools/window_shot.gd` reads THIS rather
## than re-deriving the arithmetic: a second copy of it is a table that can disagree with the picture.
##
## The LIST is an argument and not `_sim.buildings()` read in here, so a test can hand it a building
## on a world that has none yet -- a fresh `Welcome` carries no factories, and a test whose list is
## empty passes for the absence of the data it is about.
func _building_marks(buildings: Array) -> Array:
	var marks := []
	for entry in buildings:
		marks.append(AssayHud.building_mark(entry as Dictionary, _cell, MARGIN))
	return marks


## **WHAT THE SCHEMATIC IS ABOUT TO PAINT FOR EVERY SPECIES LETTER** (ASSA-213), in the same shape and
## for the same reason as `_building_marks`: the letter is now the LAST mark on this view, over the
## machines, and a test has to be able to ask what it will paint and where.
##
## `baseline` IS WHERE `draw_string` IS TOLD TO START, not the centre of the glyph: the width comes
## from the font and the vertical nudge is the usual "half the cap height" for a baseline-drawn
## capital, so a letter is centred by measurement rather than by a guessed offset. `box` is the
## rectangle that measured letter occupies, which is what a check about a mark covering it has to
## intersect -- the ink inside it is the font's business and nothing headless can rasterise it.
##
## THE BED IS THE DISC'S OWN FILL. `AssayHud.deposit_disc` is asked a second time rather than the
## colour being carried out of the loop above, because the two passes must agree with the DATA and
## not with each other: a bed that remembered a colour the disc has since recomputed would be a rim
## of the wrong species, which is worse than no rim.
##
## A DEPOSIT WITH NOTHING LEFT CARRIES NO LETTER, the same `amount` test the disc pass makes -- a
## spent patch keeps its tint on this map but has no species worth naming over a factory.
## **`building_marks` IS HALF OF WHY ONLY SOME LETTERS GET THE EXPENSIVE BED** (ASSA-218 box 9, Maren:
## "it matters"). The eight stamps are eight extra `draw_string` per letter, and a 13-letter world
## paid 104 of them against ASSA-214's whole-map median of 42 draw calls -- 2.5x the map's entire
## budget, to protect the one letter a machine was standing on. `AssayHud.letter_occlusions` already
## decides which letters a building diamond laps, so it decides this half.
##
## **THE OTHER HALF IS THE HATCH, AND IT IS THE BIGGER ONE** (box 9 AMENDED, 13:00 EDT). Box 9 first
## shipped as lapped-only and Maren measured what that cost: the stamps are worth **+1.16 to +2.43
## ratio points on every hatched disc** of seed 777042 against **+1.55** on the lapped one, because
## `hatch_ink` and `glyph_ink` can be the **same white** -- the footprint with no bed measures 1.00:1,
## no edge at all. So lapped-only kept the bed on the letter least at risk. The widened rule is
## `lapped OR hatched`, and `hatched` is the sim's `reach_note`, not a palette.
##
## **THE DECISION IS A FACT ON THE MARK, NOT AN `if` IN THE DRAW LOOP**, which is the whole reason
## this is testable. `_draw` cannot be asked how many times it called `draw_string`; a dictionary
## can. So `bedded` is published here and `_draw` paints what it is told, exactly as the comment
## over the glyph pass already claims ("THE DECISION IS `_glyph_marks`'"). Mutating either half --
## back to lapped-only, or `true` everywhere -- reddens
## `test_a_letter_is_bedded_when_a_mark_laps_it_or_a_hatch_crosses_it`.
##
## AN EMPTY LIST MEANS NO BUILDINGS, AND THEREFORE ONLY THE HATCHED LETTERS -- not "stamp
## everything", and no longer "stamp nothing", which is what this paragraph said until the amendment.
## A hatch is a property of the rock, so it decides the bed whether or not anything stands on the
## map; a letter with neither is on its own disc, where `glyph_color` picked its ink against that
## exact surface, and the stamps buy it nothing.
func _glyph_marks(deposits: Array, font: Font, building_marks: Array = []) -> Array:
	var marks := []
	if font == null:
		return marks
	for entry in deposits:
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) <= 0:
			continue
		var symbol := String(deposit.get("symbol", ""))
		if symbol.is_empty():
			continue
		# **`center` WITHOUT A DEFAULT** (ASSA-141), unlike `amount` and `symbol` above, where a missing
		# key means "skip this rock" and costs one letter. A defaulted centre is worse than no letter:
		# every deposit would stack its glyph on tile (0,0), and `AssayHud.machines_on_letters` would
		# then report a machine near the origin as standing on all six species at once.
		var centre: Vector2i = deposit["center"]
		# **THE SAME `point_of_tile` THE DISC PASS USES** (ASSA-220). These were two independent copies of
		# the corner formula, which is why one defect sat in two places: a letter centred on `at` inherited
		# the disc's half-tile error exactly.
		var at := point_of_tile(centre)
		var radius := maxf(_cell, float(int(deposit.get("radius", 1))) * _cell)
		var size := AssayHud.glyph_size(radius)
		if size <= 0:
			continue
		var disc := AssayHud.deposit_disc(deposit, radius)
		var measured := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var baseline := at + Vector2(-measured.x * 0.5, float(size) * 0.36)
		marks.append({
			"symbol": symbol,
			"size": size,
			"baseline": baseline,
			"ink": disc["ink"],
			"bed": disc["colour"],
			"bed_px": AssayHud.GLYPH_BED_PX,
			# THE FONT'S OWN BOX AND NOT A TYPED CAP HEIGHT: the ascent above the baseline, the
			# advance across. A "0.72 x size" would be a number I invented about a font I did not
			# ask. THE DESCENT IS LEFT OUT ON PURPOSE -- `symbol` is one capital, a generated name's
			# initial, so there is no descender and a box that reserved room for one would say a
			# mark lands on the letter when it lands under it.
			"box": Rect2(baseline - Vector2(0.0, font.get_ascent(size)),
					Vector2(measured.x, font.get_ascent(size))),
			"at": at,
			# **THE TILE, NOT ONLY THE PIXEL** (ASSA-213 box 2). `at` is where the letter is drawn and
			# cannot be compared with a footprint: a shot has to be able to ask the SIM whether a
			# machine stands on the tile this letter names, because pixels alone cannot tell "no
			# machine was on a rock today" from "one was and the map did not mark it".
			# `AssayHud.machines_on_letters` is the comparison and `tools/window_shot.gd` the caller.
			"tile": centre,
			# **BEDDED IF A HATCH CROSSES IT, AND ALSO IF A MARK LAPS IT** (ASSA-218 box 9 as Maren
			# AMENDED it, 13:00 EDT, after measuring my own priced alternative). Box 9 first shipped
			# as *lapped only*, and the measurement says that keeps the bed on the one letter that
			# was never at risk and strips it from the eight that are: on seed 777042 the eight
			# stamps are worth **1.16 to 2.43 ratio points** on every hatched disc (2 H 1.67->3.37,
			# 3 N 1.93->4.36, 12 D 1.42->2.59), against **+1.55** on the lapped one.
			#
			# WHY A HATCH IS THE WORSE SURFACE OF THE TWO, which is not what either of us expected:
			# on discs 2/5/12 `hatch_ink` IS white and so is `glyph_ink`, so where a stroke crosses
			# the letter there is **no edge at all** -- the footprint with no bed measures 100% pure
			# white, 1.00:1. A building mark at least has its own grey. The stamps are the only thing
			# holding a white letter and a white hatch apart.
			#
			# `hatch` IS THE SIM'S FACT, not a look: `deposit_disc` sets it from a non-empty
			# `reach_note`, so this reads "nothing can get this ore out" and never a palette.
			#
			# The lapped half is filled in below, once every letter's box exists: `letter_occlusions`
			# needs the whole list, so it cannot be answered one letter at a time inside this loop.
			"bedded": bool(disc["hatch"]),
		})
	# **WHICH LETTERS A BUILDING ACTUALLY LAPS** -- the same `letter_occlusions` the window shot's
	# `case` leg reports, so the painter and the picture cannot disagree about which letter was at
	# risk. It returns one entry per (building, letter) pair that overlaps at all, and a letter lapped
	# by two buildings is still one letter, hence the set rather than a count.
	for raw in AssayHud.letter_occlusions(building_marks, marks):
		var lap: Dictionary = raw
		var j := int(lap["letter"])
		if j >= 0 and j < marks.size():
			(marks[j] as Dictionary)["bedded"] = true
	return marks
