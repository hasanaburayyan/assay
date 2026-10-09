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

## **THE WORLD BEHIND THE DOOR** (ASSA-292, ASSA-276 §4, Maren's ruling 2026-10-08).
##
## A SECOND SIM AND NOT THE SESSION'S ONE, which is the whole reason this is safe. `_sim` is the world
## you are PLAYING; this one is scenery, it is never stepped, no command is ever submitted to it, and
## nothing reads it except the view dictionary `_door_view` builds. The two can never be confused
## because every input path in this file guards on `_sim.running()` (`_tile_under`), which is false
## for the entire life of this one -- so *"the world behind the door is scenery and never responds"*
## (her floor 4) is a property of the existing guard rather than a new rule to remember.
##
## **IT IS THE SEED SOLO PLAYS, BY REFERENCE.** `AssaySoloRelay.DEFAULT_SEED`, never a copy of its
## digits, because the design is *"press the button and you walk into the field you were looking at"*
## and that sentence is only true while the two seeds are the same one.
## **THE PLATE THE WORDS STAND ON** (ASSA-292, Maren: *"THE PLATE IS APPROVED, with floors"*).
##
## **IT IS A BAND, AND I SHOULD SAY SO RATHER THAN CALL IT WHAT I MEANT TO BUILD.** I wrote that this
## would be "the size of the words, about a tenth of the door". It is not: the door's children are
## full-width containers with their content centred inside them, so the union of what they occupy is
## **912 x 261 -- 36% of the door**, a horizontal band and not a card. The words sit well on it and
## the world reads above and below, but the claim and the rectangle were two different things and the
## shot is what told me. **The composition is Maren's to rule on; the number is mine and it is real.**
##
## WHAT IS STILL TRUE AND IS THE REASON FOR A PLATE AT ALL: her floor 2 -- *"a scrim may help and may
## not be the whole answer. Dimming the world until text passes is how a title screen becomes a flat
## field with extra steps."* To lift `INK_MUTED` to 4.5:1 against the worst pixel the lit world
## actually puts behind a word -- (244,154,81), an ore deposit -- a scrim over the WHOLE door needs
## alpha 0.73. This band is opaque where it is and absent everywhere else, which is why 64% of the
## picture is still the picture.
var _door_plate := ColorRect.new()
var _door_sim := AssaySimHost.new()
## Ore in the door world, computed ONCE. The live `_ore_under` re-caches on `_sim.tick()`; this world
## never ticks, so the only thing that could move the answer is the camera, and the margin below
## covers every tile the whole drift can reach.
var _door_ore := {}
var _door_ore_built := false
## A binding with no `AssaySim` (an editor run without `make client-lib`) must fall back to the flat
## field rather than retry `fresh_welcome_json` sixty times a second forever.
var _door_dead := false
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
## **THE STANDING NOTICE, UNDER THE LINE ABOVE** (ASSA-370, the Game Director's amendment to her own
## ASSA-300 ruling: *"A TRANSIENT LINE MAY COVER A STANDING NOTICE. IT MAY NEVER DESTROY ONE. A
## CONDITION NOTICE'S LIFETIME BELONGS TO ITS CONDITION, SO NOTHING WHOSE OWN LIFETIME IS A TIMER MAY
## END IT."*).
##
## **ONE VISIBLE SLOT, TWO STORED LINES, AND THIS IS THE LOWER ONE.** `_base_*` above is the
## transient: a receipt, a refusal, a connection state. This is a claim about a machine *now*, and the
## bug that bought it is that every accepted command used to overwrite the triple outright — so a
## routine `Mine` press wiped a live stall warning and then aged out on its own 20-tick dwell, leaving
## the toast silent while the pinned count still read `1 of 1 buildings stopped`. A notice whose
## duration says nothing about its subject teaches a player to ignore notice durations.
##
## **NO `_said_at_tick` HERE, AND THAT IS THE RULING AND NOT A SAVING.** A standing notice has no
## stamp because nothing may end it on a timer; it ends when `is_halted` says its building is working,
## and that is the only way out. The transient keeps the stamp, because being read IS its lifetime.
var _standing_line := ""
var _standing_level: int = AssayHud.Say.IDLE
## **WHAT `_standing_line` IS A CLAIM ABOUT**: the building of a CONDITION, or `NOT_A_CONDITION` when
## there is no standing notice at all (ASSA-300). The sim decides which — `attention_conditions`,
## beside the sentence itself — and this client never reads a word of the line to find out, because
## the wording moved thirteen times in one afternoon on ASSA-67.
##
## **SET BY `_stand` AND NOWHERE ELSE, WHICH IS WHY IT IS AN ARGUMENT TO IT.** ASSA-300 made this an
## argument to `_say` for exactly this reason and the property survives the split: a second setter
## could leave one sentence's building attached to another, and then `_age_the_saying` would take down
## a refusal because some machine got fixed. What the split changes is that an ordinary `_say` no
## longer resets it — that reset WAS the bug — so the guarantee moves from "every sentence restates
## it" to "only its own condition can end it", which is the ruling in one line of state.
var _standing_building := NOT_A_CONDITION
## **NO BUILDING TO RE-ASK**, which is what every sentence in this client is except a stall notice:
## a refusal, a loss, a join, a connection state.
##
## The same -1 `attention_conditions` crosses, and the direction matters: an unset or out-of-range
## answer must mean "never take this down". The other way round, a stray 0 would mean "a condition
## about building 0" and could fade a refusal, which ASSA-239 calls the one class of sentence a player
## cannot recover.
const NOT_A_CONDITION := -1
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
## **THE MACHINE MENU'S SURFACE, THE SAME TWO-PART TRICK AS THE LOG'S AND THE BUILD SCREEN'S**
## (ASSA-316, ASSA-334).
##
## `_menu_region` is the WHOLE WORLD and it never moves; it exists to CLIP, which is what keeps this
## panel off the HUD column whatever the placing arithmetic does. **IT WAS ONE HALF OF THE MAP UNTIL
## ASSA-334**, because Maren's ruling 1 placed the menu by which half its machine was not in; she
## reversed that to anchoring, so the thing that moves is now `_menu_box`'s own rect and the region has
## one job. `_menu_box` takes the size the ENGINE gives it from its own widest row, floored and capped
## (`_place_machine_menu`) -- the door card's rule in ASSA-292: no literal width anywhere.
var _menu_region: Control = null
var _menu_box: PanelContainer = null
## The parts of the menu whose content moves on different clocks: the name on open, the state sentence
## and the batch every tick, the slot and act rows only when the pack's shape changes. Held rather than
## found so the per-tick path never walks the tree (`_refresh_machine_menu`).
var _menu_name: Label = null
var _menu_state: Label = null
var _menu_work: HBoxContainer = null
var _menu_rows: VBoxContainer = null
## THE STATE LINE'S ORDINARY INK, read once at build. A node whose `font_color` this file also WRITES
## cannot be asked what its ordinary colour is (`_refresh_machine_menu`).
var _menu_state_ink := Color.WHITE
## **EACH SLOT'S FILL ROW BY THE SIM'S OWN NAME FOR THAT SLOT** (ASSA-334), so the per-tick path can
## re-text a band without walking the tree or rebuilding a button under the cursor. Emptied by every
## rebuild, because a row held here after `_clear` freed it is a stale reference that reads fine until
## something touches it.
var _menu_slot_rows := {}
## WHAT THE MENU'S ROWS WERE BUILT FOR. Same contract as `_actions_showing`: the building's ID and the
## pack's SHAPE, never its counts or the machine's status. A smelter's status sentence changes every
## tick while it burns, and rebuilding on that would free the button under the player's cursor four
## times a second -- the defect `_refresh_actions` documents and this surface would have inherited.
var _menu_showing := UNBUILT
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

## The sim's verdict line on a species row -- `[too hard for anything you can build]`, or the
## mining/fuel/lighting tags. Named for `SPECIES_READINGS`' reason and for one more: ASSA-264 moved
## it from the bottom of the row to directly under the name, and a test that found it by child index
## would have passed either way (Maren asked for the name while ruling the move).
const SPECIES_TAGS := "SpeciesTags"
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

## **THE MACHINE MENU'S FOUR NAMED PARTS** (ASSA-316). The board asked for menus you can interact
## with; a test, a probe and a shot tool all have to find them, and every one of these is a node whose
## CONTENT changes on a different clock -- the name on open, the state every tick, the rows only when
## the pack's shape moves. ASSA-117's lesson with no half missing this time.
const MENU_BOX := "MachineMenu"
const MENU_NAME := "MachineMenuName"
const MENU_STATE := "MachineMenuState"
const MENU_ROWS := "MachineMenuRows"
## **FIVE SINCE ASSA-334**, on a fifth clock: the batch moves every tick like the state line, and
## appears and DISAPPEARS on its own (`work` is nil whenever nothing is in front of the machine), which
## is a thing no other part of this menu does.
const MENU_WORK := "MachineMenuWork"

## **THE THREE COLUMNS OF A RATIO ROW, NAMED SO A TEST CAN ASK FOR ONE** (ASSA-334, ASSA-339). Walking
## by `get_child(1)` is how ASSA-62 pressed nothing for days: the index is right until somebody adds a
## column, and nothing goes red for reading the wrong child -- it reads a real node and asserts about
## the wrong thing.
const ROW_WORDS := "Words"
const ROW_BAND := "Band"
const ROW_COUNTS := "Counts"

## **THE BUILD SCREEN'S NAMED PARTS** (ASSA-328, ASSA-317). Same reason the menu's four are named: a
## test, a probe and a shot tool have to find them without walking the tree by index, and each of
## these changes on its own clock -- the picker only when the catalogue's shape moves, the materials
## and the detail every time a material is chosen, the cost every refresh.
const BUILD_BOX := "BuildScreen"
const BUILD_TITLE := "BuildScreenTitle"
const BUILD_PICKER := "BuildScreenPicker"
const BUILD_MATERIALS := "BuildScreenMaterials"
const BUILD_DETAIL := "BuildScreenDetail"
const BUILD_COST := "BuildScreenCost"
const BUILD_BAR := "BuildScreenCommitBar"
const BUILD_SAID := "BuildScreenSaid"
const BUILD_ACT := "BuildScreenAct"
const BUILD_SLOTS := "BuildScreenSlots"
const BUILD_MOUNTS := "BuildScreenMounts"

## **THE SCREEN'S TWO MODES, AND THEY ARE THE SIM'S OWN COMMAND WORDS** (ASSA-317 slice 2; Maren's
## 00:32 ruling: *"BLOCK 2 IS THE SUBJECT IN BOTH MODES ... same two rects, same two jobs, so a
## player learns this screen once instead of twice"*).
##
## `_build_verb` already held `make_offers`' own `verb` -- `craft` or `make` -- and this adds the
## third. **It is spelled as the command the press sends** (`Assemble`), which is the rule
## `_send_build`'s match rests on: which command a screen sends is the sim's answer, never a label.
##
## **THE MAKE PATH NEVER ASKS "AM I ASSEMBLING"; IT ASKS WHETHER THERE IS AN OFFER**, because a make
## mode is one with a `tag` the catalogue knows. One predicate, `_assembling_mode()`, so the eleven
## branches this slice adds cannot drift from each other.
const BUILD_ASSEMBLE := "assemble"

## **THE THREE COLUMNS, AS SHARES OF THE SCREEN RATHER THAN PIXEL WIDTHS** (ASSA-328). Maren's mock
## fixes them at 287 / 304 / 240 inside 863 (`assay-build-screen` §0), and these are those three
## numbers over that total. **A share and not a literal, which is ASSA-287's ruling applied to a
## width**: the screen's own rect is derived from `world_rect()`, so three typed widths would be
## correct at 1280x720 and wrong at every other size, and the mock's proportions are the part of it
## she actually specified.
const BUILD_COLUMNS := [287.0 / 863.0, 304.0 / 863.0, 240.0 / 863.0]

## **THE GUTTER BETWEEN HER BLOCKS, READ OFF HER OWN RECTS** (ASSA-328): 335 -> 351 and 655 -> 671
## horizontally, 91 -> 107 and 569 -> 585 vertically. One number, four places, so it is named once.
const BUILD_GUTTER := 16

## **HOW THE RIGHT COLUMN SPLITS** (ASSA-328, moved by ASSA-332): her block 5 (the readout) is 300 px
## and block 6 (cost) is **90** of the **390** the columns get once the gutter is out. Shares for
## `BUILD_COLUMNS`' reason.
##
## **IT WAS 300 / 446 UNTIL THE COMMIT BAR GREW** (her §5.4): the columns used to end at y 569 and now
## end at **y 513**, so the right column holds 300 + 16 + 90 = 406 instead of 462. The number that
## moved is hers and the arithmetic is written out here rather than updated silently, because the only
## way to check a share is against the rects it came from.
const BUILD_READOUT_SHARE := 300.0 / 390.0

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
##
## **AND OPENING A MACHINE'S MENU CHOOSES ITS TILE TOO** (ASSA-366, Maren amending her ASSA-316 ruling
## 8). On an occupied tile a click opens that machine's menu and returns, so before this the only
## gesture that could set the field skipped every standing building: **the one subject three of the
## five verbs take was the one subject a player could not aim at.** It carries a TILE here either way;
## what stands on that tile is `_footprint_tiles`' question, asked fresh on every refresh, which is why
## picking a machine up leaves a one-tile cursor rather than a ring around nothing.
var _target := Vector2i.ZERO
var _targeted := false
## **THE MACHINE WHOSE MENU IS OPEN, BY ID, OR -1** (ASSA-316, the board: *"machines should have menus
## so we can interact with them"*).
##
## **THE ID IS THE SUBJECT AND THE TILE IS ONLY WHERE IT IS DRAWN.** Every command the menu sends takes
## a `BuildingId` (`AssayActions.take`/`pickup`/`insert`), the ring needs a tile, and a building that is
## picked up while its menu is open leaves the id behind on a tile that now holds nothing -- which is
## the one state this pair makes checkable (`_refresh_machine_menu` closes on it).
##
## **IT IS STILL NOT `_target`, BUT THE TWO NOW MOVE TOGETHER** (ASSA-366; ruling 8's second half
## reversed by Maren). This is an ID and `_target` is a tile, and that difference is load-bearing: this
## one cannot be inherited by the next building to land on the same tile, and `_target` can, because a
## tile is what a placement needs. What changed is that opening a menu now sets both, so the panel, the
## ring and the `do` column name one subject instead of three.
##
## **THE ARGUMENT THAT KEPT THEM APART IS ANSWERED RATHER THAN FORGOTTEN.** It was that `Place` is
## refused on a tile that already carries a building (`step.rs:225` `TileOccupied`), so aiming there
## arms a guaranteed refusal. True, and it is an OUTCOME the sim says out loud -- *"another building is
## in the way"* -- which the player reaches by placing a machine anyway. A mark nobody can aim is not an
## outcome; it is a mechanism no gesture invokes.
var _menu_at := -1
var _menu_tile := Vector2i.ZERO

## **WHAT THE BUILD SCREEN IS OPEN ON: THE SIM'S OWN TWO WORDS FOR A CATALOGUE ROW, OR "" FOR SHUT**
## (ASSA-328).
##
## **IT IS `verb` + `tag` AND NOT AN INDEX INTO `make_offers`, which is the whole of why the screen
## survives a tick.** The offer list is rebuilt from the pack every refresh and its length changes the
## moment a craft lands, so an index would silently come to mean a different recipe -- ASSA-55's
## defect (a count captured in a closure) moved into a screen that stays open for many ticks. `verb`
## and `tag` are the sim's own spelling, which is what `button_play` already matches a row by.
##
## **AND THE CHOSEN MATERIAL IS A THIRD FACT, NOT A FOURTH NODE.** A recipe plus a species plus a
## grade is one offer; keeping the three apart is what lets the material picker re-point at a
## different material without reopening the screen, and what lets the screen say "the sim no longer
## offers this" instead of drawing a stale row.
var _build_verb := ""
var _build_tag: Variant = null
var _build_species := -1
var _build_grade := ""
var _build_region: Control = null
var _build_box: PanelContainer = null
var _build_title: Label = null
var _build_picker: VBoxContainer = null
var _build_materials: VBoxContainer = null
## **BLOCK 3'S TWO SECTIONS ON THE ASSEMBLY PATH** (ASSA-317 slice 2b; Maren's 00:32 ruling (A)): the
## frame's slots drawn as a shape, and under them the parts you can mount. **Two SHAPES, not one
## list**, which is the whole of her sharpening: *"Slots are drawn boxes; mountable parts are a list.
## Two shapes, two jobs, each legible before you press."*
var _build_slots: VBoxContainer = null
var _build_mounts: VBoxContainer = null
var _build_detail: VBoxContainer = null
## **BLOCK 5's CROWN AND BLOCK 5's HEADING, HELD BECAUSE THE OUTPUT PICTURE IS SIZED FROM THE ROOM
## LEFT OVER AFTER THEM** (ASSA-357 box 5). Both are things the picture cannot move -- a sibling
## above it and a label beside it -- which is the whole reason they may be read live while the
## picture's own column may not (`AssayHud.build_columns_height`'s docstring: reading the laid-out
## column closes the chain on itself and the scale ratchets).
var _build_crown: HBoxContainer = null
var _build_detail_heading: Label = null
var _build_cost: VBoxContainer = null
## Block 6's whole SECTION -- heading and scroll box, not just the rows. Held because the make path
## hides the block entirely (ASSA-341) and a heading left standing over nothing is a labelled empty
## gap, which is `_show_log`'s lesson on this same screen.
var _build_cost_box: Control = null
var _build_bar: HBoxContainer = null
## The sentence's own inset inside the commit bar, so `Build` lands on row 1 (ASSA-341 box 8). Held
## because it is the bar's left-hand child and the test that keeps the sentence left and `Build`
## right asks the bar what its children are.
var _build_said_inset: MarginContainer = null
var _build_said: VBoxContainer = null
var _build_act: Button = null
var _build_showing := UNBUILT

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
	#
	# **AND THE PATH IS RESOLVED, NOT TAKEN AS TYPED** (ASSA-313): a bare `motion.txt` used to land in
	# `Assay.app/Contents/Resources/` on a Mac, because the engine's launcher chdirs into the bundle --
	# so the one file we ask a tester to send us was inside the app they were sent, and the README's
	# "beside this README" was false. `requested_report_path` measures a relative path from the folder
	# the player unzipped.
	_motion_probe_path = AssayMotionProbe.requested_report_path()
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
	# **AT THE DOOR'S RECTANGLE AND NOT THE MAP'S, BECAUSE THE DOOR IS WHAT IS UP AT BUILD TIME**
	# (ASSA-292, Maren's rectangle ruling -- see `AssayHud.world_layer_rect`). `_refresh_front_door`
	# moves it on every state change after this; starting it at the door's rect is what keeps the
	# door camera (`_door_view`, which reads `_world.size`) from being built once against the
	# narrower map on the very first frame, before any refresh has run.
	_place_world_layer(true)
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
	# **BETWEEN THE WORLD AND THE WORDS**: added after `_world` so it covers the picture, before
	# `_front_door` so the words sit on it. `MOUSE_FILTER_IGNORE` for the reason everything else over
	# this map has it -- the map is clicked through `_unhandled_input`.
	_door_plate.color = AssayHud.DOOR_PLATE
	_door_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_door_plate.visible = false
	add_child(_door_plate)
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
	# **`Wordmark`, THE FIFTH SIZE, AND MAREN RULED THE GROWTH** (ASSA-292). This said `Display` and
	# carried a comment that a bigger title "means a fifth size in build_theme.gd, which is a
	# type-scale ruling and hers". She ruled it on her own measurement -- the game name was 0.12% of
	# its own title screen -- so the size is in the scale by name and not poked in here.
	_door_title.theme_type_variation = &"Wordmark"
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
	# **AFTER THE LOG AND THE KEY, WHICH IS A DECISION ABOUT WHAT MAY COVER WHAT** (ASSA-316). Siblings
	# are drawn in tree order, so the menu -- the thing a player just opened and is reading -- sits over
	# the log's top-left panel if both are up. The other way round would hide a surface behind one the
	# player asked for, which is ASSA-147's defect; and the log is a CONSULTING surface they can lower
	# with one press. What the menu may never cover is the HUD column (Maren's ruling 2), and that is
	# true of its geometry rather than of this line: it lives in half of `world_rect`.
	_build_machine_menu_over_the_map(world)
	# **AFTER THE MENU, AND THE TWO CANNOT BOTH BE UP ANYWAY** (Maren's §1: mutually exclusive). The
	# order still matters for one case this file cannot rule out -- a bug that left both visible -- and
	# in it the thing the player opened last should be the thing they can read. The exclusion is
	# enforced in `_open_build_screen` and `_open_machine_menu`; this is the belt to that braces.
	_build_build_screen_over_the_map(world)

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
	# **WIDE ENOUGH FOR THE ADDRESS DECISION #40 SENDS A FRIEND** (ASSA-318, Maren's option 2). A
	# tailnet name is what somebody called their computer, so no width is "enough" -- the bar is one
	# NAMED string, `AssayHud.LONGEST_HOSTNAME`, measured in the live font rather than multiplied out
	# of a px/char ratio. At 240 this held 34 narrow characters or 29 wide ones and clipped a MagicDNS
	# name by 36 px.
	#
	# **AND NOTHING IS TAKEN FROM THE NAME FIELD TO PAY FOR IT, WHICH WAS MY OWN FINDING AND HER
	# RULING.** I measured that the name field has nothing to give (120 usable, 105 spent by the
	# shipped default). She then found the better reason: there is no card. `_front_door` is a centred
	# VBox with no panel, the row is ~513 px of a 1280 px window, and `SURFACE` across that whole
	# region is 171 px -- so the two fields were never sharing anything and option 1 was answering a
	# scarcity neither of us had checked for.
	_host.custom_minimum_size = Vector2(AssayHud.HOST_FIELD_PX, 0.0)
	_host.tooltip_text = "host, host:port, or [v6]:port. A bare address uses 7777."
	_cred_cell.add_child(_host)

	var name_label := Label.new()
	name_label.text = "name"
	_cred_cell.add_child(name_label)
	# **OUR OWN DEFAULT MUST NOT ARRIVE FULL**, which is the reason this number is not taste: the box
	# already holds `$USER` before the player touches it, and at 140 that was 105 px of 120 usable --
	# 87.5% full on arrival, with two more characters than the name we ship enough to scroll it.
	_name.text = OS.get_environment("USER")
	_name.custom_minimum_size = Vector2(AssayHud.NAME_FIELD_PX, 0.0)
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


## **THE MACHINE MENU'S SURFACE, BUILT ONCE AND EMPTY** (ASSA-316; the board, 10-08: *"machines should
## have menus so we can interact with them"*).
##
## **WHY THIS SCREEN NEEDED IT, IN OUR OWN PIXELS** (Maren's reading, and she disagreed with the pop-up
## before ruling it): on `nacre-assa292-rect/rect-only/02-play.png` the column already prints a
## machine's entire state -- `holding 0 of 210 · mining Minyte · mass 490 of 1095 budget · speed 44 ·
## frame(...) + hopper x4` -- **with nothing you can press.** The data was there and the interaction
## was not.
##
## **IT STOPS THE MOUSE AND THE REGION AROUND IT DOES NOT**, the log's rule for the log's reason: the
## map is clicked through `_unhandled_input`, so an `IGNORE` panel would let a press on a slot button
## fall through onto the tile behind it and walk the player away from the machine they were loading.
## The region is `IGNORE` so the rest of the world stays clickable -- the menu does NOT block input
## (ruling 2: *"a menu that freezes a co-op game stops your partner's factory being watchable"*).
##
## **`clip_contents` IS THE CAP, AND IT IS STRUCTURAL ON PURPOSE.** The box's size is the engine's
## answer about its own widest row, floored and capped by `_place_machine_menu`; the clip is the world,
## so no arithmetic mistake in this file can put a pixel of this panel over the HUD column where the
## sim's refusals are read. A clip cannot be forgotten the way a `minf` in a later refresh can.
## **A test holds the content inside the box** rather than trusting the clip to hide a defect: Maren's
## rule is that past its room it SCROLLS, and a scroll box nothing can reach yet is a control a player
## cannot use, so the bound is a red test today and a `ScrollContainer` the day a menu outgrows it.
func _build_machine_menu_over_the_map(world: Rect2) -> void:
	# A PLAIN `Control` AND NOT A `VBoxContainer` SINCE ASSA-334, which is the one structural change
	# anchoring costs. A container LAYS ITS CHILD OUT, so the box's position was the container's answer
	# and the only thing this file could choose was which half the container stood in. The region is now
	# the whole world -- the clip that makes "never over the HUD column" true of pixels rather than of
	# arithmetic -- and the box's rect is written by `_place_machine_menu`, the build screen's shape.
	_menu_region = Control.new()
	_menu_region.position = world.position
	_menu_region.size = world.size
	_menu_region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_region.clip_contents = true
	add_child(_menu_region)
	_menu_box = PanelContainer.new()
	_menu_box.name = MENU_BOX
	# **PLACED AGAIN WHENEVER THE ENGINE CHANGES ITS MIND ABOUT THE SIZE, AND A PICTURE IS THE ONLY
	# THING THAT COULD HAVE FOUND THIS** (ASSA-334). `_place_machine_menu` reads
	# `get_combined_minimum_size()` in the same frame as the rebuild that changed the content, and in a
	# real window that recalculation is DEFERRED -- so the first placement of an anchored menu used the
	# previous frame's height. Measured on `nacre-assa334-anchor/14-machine-menu.png`: placed as if 272
	# px tall, laid out at 356, hanging 84 px below the world and clipped to 76% of itself.
	#
	# **AND THE CLAMP COULD NOT SAVE IT, WHICH IS THE PART WORTH WRITING DOWN.** A `PanelContainer`
	# enforces its own minimum, so assigning a SMALLER size than its content needs does not cut the
	# panel -- it snaps back up and the box grows out of the rect I gave it. The arithmetic was right
	# about a height that was wrong. **The headless suite cannot see it**: nothing lays out there, so
	# the first ask computes lazily and comes back fresh, which is why 470 tests were green over it.
	_menu_box.minimum_size_changed.connect(_place_machine_menu)
	# SAID RATHER THAN INHERITED, as the log says it: `STOP` is a Control's default and the paragraph
	# above is the reason this panel has it. A default nobody wrote down is a default somebody changes.
	_menu_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_box.visible = false
	_menu_region.add_child(_menu_box)
	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", 6)
	_menu_box.add_child(inside)
	# THE MACHINE'S OWN NAME, AT HEADING SIZE (ruling 5). `debug::building_name` wrote it -- `Minyte
	# machine (B)` -- so the species that caps the fire and the grade that comes back in your pack are
	# in the title, and this file composes nothing. No punctuation the sim did not write (ASSA-305).
	_menu_name = Label.new()
	_menu_name.name = MENU_NAME
	_menu_name.theme_type_variation = &"Heading"
	inside.add_child(_menu_name)
	# **ITS CONDITION, ON ITS OWN LINE AND IN THE SIM'S OWN WORDS** (ruling 6 for the home, ASSA-334 §6
	# for the field). This was `status` -- the whole dense line the terminal table prints -- and at the
	# menu's width it wrapped to FIVE rows, which is what made Maren's first width floor come out at
	# 847 px and fit nowhere in a 912 px world. It is now `state_line`, one sentence per condition, and
	# the facts that paragraph also carried (what each slot holds, how far the batch has got) are rows
	# of their own below, as ruling 5's bands. Nothing in this menu wraps any more.
	#
	# **NOT WRAPPED, AND THAT IS THE ASSERTION RATHER THAN THE HOPE.** `_note` wraps, which is right for
	# a sentence in a fixed column and wrong for every line in a box whose width this file chooses: a
	# wrapping Label reports a 1 px minimum and silently takes the height it needs, so a regression to a
	# long string would come back as a tall menu nobody measured. With wrapping OFF the string's real
	# width reaches `get_combined_minimum_size()`, and `test_buttons.gd` fails the day one exceeds the
	# cap. The sim's longest stall sentence is 276 px (Maren's §6 table) against a 343 px floor.
	_menu_state = _note("")
	_menu_state.name = MENU_STATE
	_menu_state.autowrap_mode = TextServer.AUTOWRAP_OFF
	# **READ ONCE, HERE, WHILE THE ONLY OVERRIDE ON THIS NODE IS THE ONE `_note` JUST WROTE.** After the
	# first stall the node's own `font_color` is `FAILED`, and asking it then returns that. See
	# `_refresh_machine_menu` for the defect this closes.
	_menu_state_ink = _menu_state.get_theme_color(&"font_color", &"Muted")
	inside.add_child(_menu_state)
	# **THE BATCH, AS THE BAND RULING 5 ASKED FOR AND THE SENTENCE THE SIM WRITES FOR IT** (ASSA-339).
	# Built once and emptied by `_refresh_machine_menu`, because `work` is NIL whenever nothing is in
	# front of the machine and a nil batch draws NO band -- Marlow's reason, kept in his words:
	# *"`0 of 100` on a drill that will never produce reads as a promise."*
	_menu_work = _amount_row()
	_menu_work.name = MENU_WORK
	inside.add_child(_menu_work)
	_menu_rows = VBoxContainer.new()
	_menu_rows.name = MENU_ROWS
	_menu_rows.add_theme_constant_override("separation", 6)
	inside.add_child(_menu_rows)
	# **THE WAY OUT IS NAMED, WHICH IS THIS CLIENT'S OWN RULE AND NOT A THIRD DISMISSAL** (`_show_log`:
	# *"the control names the key, because the key is the half a stranger cannot discover"*). Maren ruled
	# Esc and a click outside; both are invisible, and the board's first act on a new surface is to look
	# for the way back. QUIET, because it is furniture (ASSA-224) and the menu spends no accent at all --
	# it offers several equal acts and must not choose for you.
	var close := _button(AssayHud.close_text(), func() -> void: _close_machine_menu(),
			"close this menu. Esc does the same, and so does a click on the map")
	close.theme_type_variation = &"Quiet"
	close.alignment = HORIZONTAL_ALIGNMENT_LEFT
	inside.add_child(close)


## **THE BUILD SCREEN'S SURFACE, BUILT ONCE AND EMPTY** (ASSA-328, slice 1 of ASSA-317; the board,
## 10-08: *"We should have pop up modals and interactive build screens for crafting not just 'make'
## buttons"*).
##
## **THE REGION IS THE WHOLE WORLD AND THE BOX IS PLACED INSIDE IT BY RECT**, which is the one
## structural difference from the machine menu. That menu's position is a RULE (the half the machine
## is not in) and its size is the engine's answer about its widest row, so it needs neither. This
## screen's rect is SPECIFIED -- Maren's §1, the world less a pad, clear of the control band -- so
## `_place_build_screen` writes it and `AssayHud.build_screen_rect` derives it.
##
## **IT STOPS THE MOUSE AND THE REGION AROUND IT DOES NOT**, the log's and the menu's rule for the
## log's reason: the map is clicked through `_unhandled_input`, so an `IGNORE` panel would let a press
## on the material picker fall through onto the tile behind it and walk the player away.
##
## **IT DOES NOT BLOCK INPUT, AND THAT IS A RULING AND NOT AN OVERSIGHT** (Maren's §1, carried from
## ASSA-316 ruling 2): *"a screen that freezes a co-op game stops your partner's factory being
## watchable, and watching each other work is the only reason this is co-op. 'Modal' is Hasan's word
## for pop-up. I take the pop and leave the block."* So the region stays `IGNORE` and the world keeps
## taking clicks everywhere this box is not.
##
## **THREE COLUMNS AS SHARES, NOT WIDTHS** -- see `BUILD_COLUMNS`. The box is sized to the derived
## rect, so every column inside it is a fraction of a number nothing here typed.
func _build_build_screen_over_the_map(world: Rect2) -> void:
	_build_region = Control.new()
	_build_region.position = world.position
	_build_region.size = world.size
	_build_region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_region.clip_contents = true
	add_child(_build_region)
	_build_box = PanelContainer.new()
	_build_box.name = BUILD_BOX
	# SAID RATHER THAN INHERITED, as the log and the menu say it: `STOP` is a Control's default and
	# the paragraph above is the reason this panel has it.
	_build_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_box.visible = false
	# **PLACED AGAIN WHENEVER ITS OWN MINIMUM MOVES, AND THAT IS NOT BELT-AND-BRACES** (ASSA-332,
	# measured in a real window by `tools/limpet_build_screen_shot.gd`).
	#
	# **A `Control`'S `size` IS CLAMPED UP TO ITS COMBINED MINIMUM AT THE INSTANT IT IS ASSIGNED, and
	# right after a rebuild that minimum is briefly the whole content** -- the rows are in the tree
	# and the `ScrollContainer`s have not yet been told they can absorb them. Measured: the box was
	# asked for **864 x 592 and came out 864 x 1042**, hanging 450 px past the world's own control
	# band and covering the status toast by 113 x 32 px, which is the one thing Maren's §1 forbids.
	# One frame later the same box reports a minimum of 276 -- so neither the rect nor the content was
	# ever wrong, and nothing re-applied the size.
	#
	# **THE SIGNAL AND NOT `call_deferred`, WHICH I TRIED FIRST AND MEASURED AS NO FIX AT ALL**: the
	# minimum's own recalculation is deferred too, so a deferred placement can run BEFORE it and get
	# clamped by the same stale number. `minimum_size_changed` fires when the minimum DROPS, which is
	# exactly the moment the rect becomes applicable, and placing changes no minimum so it cannot
	# loop. In the running game the next tick's refresh hid this behind ~100 ms of oversize screen; a
	# surface that is briefly over the toast is still over the toast.
	_build_box.minimum_size_changed.connect(_place_build_screen)
	_build_region.add_child(_build_box)
	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", BUILD_GUTTER)
	_build_box.add_child(inside)
	# **BLOCK 1: THE TITLE AND THE WAY OUT, ON ONE LINE** (Maren's block 1, x 48..911 y 51..91).
	#
	# **THE TITLE IS THE SCREEN'S NAME AND NOT THE THING BEING MADE, which is a decision and is on the
	# item.** `make_offers` crosses `makes` as an item's three FIELDS -- kind, species, grade -- and no
	# name: `inventory_of` gets a sim-written `name` per stack and this does not. So a title naming the
	# output would be GDScript composing "Tonore head (B)" out of three fields, which is ASSA-43/52's
	# defect and is forbidden by `make_offers`' own docstring. The thing being made is named by the
	# SIM's sentence in the detail column instead (ASSA-88: a row's identity lives in its sentence).
	var crown := HBoxContainer.new()
	crown.add_theme_constant_override("separation", BUILD_GUTTER)
	_build_crown = crown
	_build_title = Label.new()
	_build_title.name = BUILD_TITLE
	_build_title.theme_type_variation = &"Display"
	_build_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_title.text = "make"
	crown.add_child(_build_title)
	# **THE WAY OUT IS NAMED, AND IT NAMES ITS KEY** -- this client's own rule (`_show_log`: *"the
	# control names the key, because the key is the half a stranger cannot discover"*). Maren's §1 gives
	# the screen Esc and *"a visible way out"* in the title bar; Esc alone is invisible, and the board's
	# first act on a new surface is to look for the way back (ASSA-316's close got the same treatment).
	# QUIET, because the screen spends its one accent on `Build` (her §5).
	var leave := _button(AssayHud.close_text(), func() -> void: _close_build_screen(),
			"close this screen. Esc does the same, and nothing you have chosen is lost")
	leave.theme_type_variation = &"Quiet"
	crown.add_child(leave)
	inside.add_child(crown)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", BUILD_GUTTER)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inside.add_child(columns)
	# **BLOCK 2: THE CATALOGUE, AS THE PICKER** (her block 2, x 48..335). What you can make, by the
	# sim's own name for it.
	_build_picker = _build_column(columns, BUILD_COLUMNS[0], "what to make")
	_build_picker.name = BUILD_PICKER
	# **BLOCKS 3+4: THE MATERIAL PICKER, AND THIS IS THE ONE PLACE I DEPART FROM HER MOCK** (on the
	# item, for her to reverse). Those two rects are drawn for the ASSEMBLY flow -- the frame's slots
	# and the held part -- and a recipe has no slots. A recipe's one choice past the recipe itself is
	# WHICH MATERIAL, so slice 1 gives the middle column to that, undivided; slice 2 takes it back for
	# slots when a frame is chosen. ONI's picker is her §3 reference and this is it exactly: pick a
	# material and the card's numbers move.
	#
	# **AND SLICE 2 TAKES IT BACK FOR THE SLOTS EXACTLY AS THAT PARAGRAPH SAID IT WOULD** (ASSA-317
	# slice 2b). The column now holds THREE sections and never more than two of them at once: the
	# material picker on the make path, and on the assembly path the frame's slots over the parts you
	# can mount. **Built once and shown by mode rather than built per mode**, which is `_show_log`'s
	# rule on this screen: a section that exists only in one mode is a node whose tests can only run
	# in that mode, and the two modes share one rebuild clock.
	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", BUILD_GUTTER)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_stretch_ratio = BUILD_COLUMNS[1]
	columns.add_child(middle)
	_build_materials = _build_section(middle, 1.0, "from which material")
	_build_materials.name = BUILD_MATERIALS
	# **THE SLOTS SHRINK TO THE SHAPE THEY DRAW AND THE MOUNT LIST GETS THE REST** (ASSA-343's ruling,
	# Maren's ASSA-328: *"let the air collect at the BOTTOM of a block"*). A frame's shape is at most
	# two rows of boxes; a filling section would put the column's whole slack between the shape and the
	# list of parts a player is moving between.
	_build_slots = _build_section(middle, 1.0, "the frame's slots", false)
	_build_slots.name = BUILD_SLOTS
	_build_mounts = _build_section(middle, 1.0, "what to mount")
	_build_mounts.name = BUILD_MOUNTS
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", BUILD_GUTTER)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = BUILD_COLUMNS[2]
	columns.add_child(right)
	# **BLOCK 5: WHAT YOU GET** (her block 5, x 671..911 y 107..407). In slice 1 that is the output
	# item's picture and the `walls` clause. **The RATIO fill and the SAFE / WILL BREAK verdict her §5
	# specifies are the ASSEMBLY readout and are slice 2/3**: `design_preview` is the sim's answer for a
	# design and a recipe is not one, so there is nothing for a recipe's screen to draw them from and I
	# will not do the banding in GDScript.
	#
	# **TWO SENTENCES LEFT THIS BLOCK IN ASSA-332 AND ONE STAYED, WHICH IS A SPLIT I CHOSE** (her §5.4
	# ruling 3 is about the design readout, so slice 1 had to be mapped onto it and box 10 of ASSA-332
	# is hers to reverse). `line` and `dead_end` went to the commit bar because both are about the act:
	# what it spends, and that it cannot be undone. `walls` stayed because it is a property of the
	# thing produced -- the smelter's heat figure -- and this block is what you get.
	#
	# **AND IT SHRINKS TO WHAT IS IN IT, SO THE COLUMN'S SLACK FALLS UNDER `cost` AND NOT ABOVE IT**
	# (ASSA-343; Maren's ASSA-328 ruling: *"let the air collect at the BOTTOM of a block, never between
	# a thing and its label … Air at the bottom of the block — under `cost`, not above it"*). She
	# measured ~200 px of air between the two things a player compares, and the cause is this share:
	# an `EXPAND_FILL` section took 300 px whatever stood in it, which on slice 1 is a 32 px picture
	# and one clause. `cost` keeps its own `EXPAND_FILL`, so the leftover lands inside the LAST block
	# -- which is also what keeps her overflow guarantee (§5.4: *"blocks 4 and 6 scroll … six distinct
	# cost entries are reachable"*): the entries still scroll inside a box that now has room.
	#
	# **THE WIDTHS DO NOT MOVE, AND THAT IS HER SENTENCE TOO**: *"the blocks keep their widths — sized
	# by the worst case a player is handed (§11.41), which this state is not."* `BUILD_COLUMNS` is
	# untouched; `BUILD_READOUT_SHARE` now only decides how tall this block may GROW to.
	_build_detail = _build_section(right, BUILD_READOUT_SHARE, "what you get", false)
	_build_detail.name = BUILD_DETAIL
	# **THE HEADING, WALKED ONCE HERE AND NEVER AGAIN** (ASSA-357 box 5). `_build_section` builds
	# holder -> [heading, scroll -> rows] and returns the rows, so the heading is two parents up and
	# the holder's first child. Walked at CONSTRUCTION rather than per refresh so a refresh cannot
	# depend on the tree's shape, and held as a `Label` so the day that shape changes this is a null
	# the sizing below falls back from instead of a wrong number.
	_build_detail_heading = _build_detail.get_parent().get_parent().get_child(0) as Label
	# **BLOCK 6: COST, AS TWO COUNTS** (her block 6, now x 671..911 y 423..**513** since the commit bar
	# grew; her §5.5: need first, no slash, text, never a band).
	_build_cost = _build_section(right, 1.0 - BUILD_READOUT_SHARE, "cost")
	_build_cost.name = BUILD_COST
	# **THE SECTION, NOT THE ROWS** -- `_build_section` builds holder -> scroll -> rows and returns the
	# rows, so the heading is two parents up. The make path hides the whole thing (ASSA-341), and
	# hiding the rows alone would leave the word `cost` standing over nothing: `_show_log`'s defect,
	# on this same screen, which was a node answering honestly about a state the screen does not have.
	_build_cost_box = _build_cost.get_parent().get_parent() as Control
	# **BLOCK 7: THE COMMIT BAR -- THE SIM'S SENTENCE AND THE ONE ACT, IN ONE RECT** (ASSA-332; Maren's
	# §5.4 ruling 3, which MOVED this rect after slice 1 shipped: *"block 7 becomes the COMMIT BAR,
	# 863 x 112 at y 529..641"*, the sentence left, `Build` right-aligned and still the one accent).
	#
	# **THE SENTENCE IS HERE AND NOT IN THE READOUT FOR A DESIGN REASON, HERS AND MINE AGREEING.** It is
	# the sim saying whether you are about to waste parts you cannot get back, so it belongs beside the
	# irreversible act rather than in a side column you scan while choosing. The measurement that forced
	# the move is `maren_readout_rows.gd`: the sim's readout is 916 px at `BODY` 13 against a 863 px
	# screen, so it is one row at NO width here, and in block 5's 240 it was five rows with the wrap
	# cutting a material from its grade letter.
	#
	# **AND THE MOVE FIXES A STALENESS I SHIPPED.** `_refresh_build_screen`'s signature is
	# `_pack_shape`, which is deliberately "which items, in which order" and NOT their counts -- so the
	# `line` this bar now carries, whose last clause is *"you have 8"*, was drawn once per shape change
	# and went stale on every mining cycle while sitting in block 5. The bar is written every refresh,
	# like the cost.
	_build_bar = HBoxContainer.new()
	_build_bar.name = BUILD_BAR
	_build_bar.add_theme_constant_override("separation", BUILD_GUTTER)
	# **THE ONE TYPED NUMBER OF THE THREE IN HER RULING** (112). The other two are derived: the columns
	# get what is left, which puts them at y 513 exactly as she specifies, and the sentence's floor of
	# 687 comes out of `AssayHud.commit_sentence_width`.
	_build_bar.custom_minimum_size.y = AssayHud.BUILD_COMMIT_BAR
	inside.add_child(_build_bar)
	# THE SENTENCE, TOP-LEFT, GROWING DOWNWARD. Top rather than centred because it is up to six rows in
	# the catalogue's worst case and a block that grows from its middle moves its own first row.
	#
	# **INSET FROM THE BAR'S TOP SO THAT `Build` SITS ON ROW 1** (ASSA-341 box 8; Maren's ruling 4). A
	# `MarginContainer` rather than a spacer child, because the children of this block ARE the sentence
	# -- `_refresh_build_said` walks them and a test re-joins them against the sim's own string, so a
	# padding node among them would be a clause that is not one. The margin is on the sentence and not
	# on the bar: `Build` must stay at the bar's top.
	#
	# **THE MARGIN STARTS AT 0 AND IS WRITTEN BY `_align_commit_row` FROM THE HEIGHTS THIS WINDOW
	# RENDERED** (ASSA-363). It used to be `AssayHud.BUILD_SENTENCE_INSET`, a 6 derived from a `BODY`
	# row, and a 1x shot measured `Build` 5 px off row 1 on the assembly path, where row 1 is a
	# `Display`. A zero here is not the screen's inset: it is the value before the first layout, and
	# there is nothing to align to until a row exists.
	_build_said_inset = MarginContainer.new()
	_build_said_inset.add_theme_constant_override("margin_top", 0)
	_build_said_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_said_inset.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build_bar.add_child(_build_said_inset)
	_build_said = VBoxContainer.new()
	_build_said.name = BUILD_SAID
	# **SEPARATION 0, WHICH IS MAREN'S RULING AND NOT A TIDY-UP** (ASSA-341 boxes 8-9, 00:31): *"These
	# rows are ONE SENTENCE broken at the sim's own `·`, not a list of things. An 18 px row already
	# carries the leading -- a 13 px body in an 18 px line is 5 px of it -- and `separation = 2` adds
	# paragraph air INSIDE a sentence, which says the clauses are separate items. They are not."*
	# The `dead_end` row does not buy the gap back either: it is genuinely not in the same series, and
	# `FAILED` already carries that distinction without a second channel.
	_build_said.add_theme_constant_override("separation", 0)
	_build_said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_said.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build_said_inset.add_child(_build_said)
	# **THE ONE ACT, AND THE SCREEN'S ONE ACCENT** (her §5: *"`Build` is the one ACCENT -- the only
	# difference from the machine menu, where no act is primary"*).
	#
	# **IT IS NEVER DISABLED AND NEVER REFUSES**, which is the rule this whole item rests on (ASSA-5/7,
	# ASSA-316 ruling 2): a player may always try a design and be TOLD, never refused, and the refusal
	# is a line in the log. That is a deliberate difference from the make ROW, which disables an
	# unaffordable press (ASSA-247) -- a row is a list where weight has to follow availability, and this
	# is the one control on a screen the player opened on purpose to look at the cost.
	#
	# **`SHRINK_END` AND NO WIDTH SET**, which is `AssayHud.BUILD_ACT_WIDTH`'s docstring: the button
	# takes its text's natural size at the right end of the bar, and a test holds that size under her
	# 160 px ceiling rather than a `custom_minimum_size` clipping a longer word into a lie.
	_build_act = _button(AssayHud.build_button_text(), func() -> void: _send_build(),
			"make one batch of this, out of the material you chose")
	_build_act.name = BUILD_ACT
	_build_act.theme_type_variation = &"Primary"
	_build_act.size_flags_horizontal = Control.SIZE_SHRINK_END
	# **TOP-ANCHORED, NOT CENTRED IN THE BAR** (ASSA-341 box 9; Maren's ruling 4: *"`Build`'s y must be
	# fixed -- a control that drifts down as the sentence grows moves under the cursor while you mine
	# (ASSA-213)"*). `SHRINK_CENTER` is centred in whatever the bar GREW to, so at six rows the button
	# moved while the row it is aligned to did not. With both controls anchored to the bar's top,
	# neither y is a function of the other's height.
	_build_act.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build_bar.add_child(_build_act)
	# **AND THE ALIGNMENT IS RE-DERIVED WHENEVER THE ENGINE GIVES THIS BUTTON A SIZE** (ASSA-363;
	# Maren: *"compute it at layout time, never precomputed and never off a headless read"*). This is
	# the only moment the window's own 30 px exists -- before any layout the same button measures 28 --
	# so the inset is written from here and from row 1's own `resized`, never from a constant.
	_build_act.resized.connect(_align_commit_row)


## ONE OF THE SCREEN'S COLUMNS: a heading, then a scroll box for its rows. Factored because the three
## are the same shape and a fourth is coming in slice 2.
##
## **IT SCROLLS, AND THAT IS NOT THE MACHINE MENU'S CALL REVERSED.** ASSA-316 left the menu's overflow
## as a red test rather than a `ScrollContainer`, because the menu's size is derived from its content
## and a scroll box nothing can reach yet is a control a player cannot use. This screen's size is
## FIXED by the spec and its content is the catalogue, which grows with the game -- so overflow here
## is a certainty rather than a hypothetical, and ASSA-98 is what an unscrollable fixed column costs.
func _build_column(into: HBoxContainer, share: float, heading: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = share
	into.add_child(column)
	return _build_section(column, 1.0, heading)


## A heading over a scrolling list of rows, returning the list. The heading is this file's word for a
## section of its own screen and is not a second copy of anything the sim says.
##
## **`fill` IS WHERE THE SLACK GOES, WHICH IS A DESIGN RULING AND NOT A FLAG I FANCIED** (ASSA-343;
## Maren: *"let the air collect at the BOTTOM of a block, never between a thing and its label"*). A
## filling section takes its whole share whatever stands in it, so a block with a 32 px picture in a
## 300 px share puts 250 px of air between itself and the block below. `false` sizes the section to
## its content and leaves the column's leftover to whichever section still fills -- the last one, by
## construction, because a column's blocks are added top to bottom.
##
## **A SHRINKING SECTION GIVES UP ITS OWN SCROLLING, AND THAT IS NOT A DETAIL I CAN LEAVE OUT.** A
## `ScrollContainer`'s minimum size on a scrolling axis is ZERO -- that is what makes it a scroll box
## -- so a `SHRINK_BEGIN` holder around one collapses to the heading alone instead of sizing to its
## content. So the shrinking kind disables vertical scrolling, which makes the scroll box's minimum
## its content's height. The cost is named rather than discovered: this section can now GROW, and a
## column whose blocks ask for more than it has squeezes the FILLING ones first -- so an overlong
## shrinking block takes room from `cost`, which scrolls, before anything reaches the column's edge.
## Bounded today by what block 5 holds (one `ICON_PX` picture and one clause); the slice that fills it
## with the design readout re-reads this.
func _build_section(into: BoxContainer, share: float, heading: String,
		fill := true) -> VBoxContainer:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	holder.size_flags_stretch_ratio = share
	into.add_child(holder)
	var title := Label.new()
	title.text = heading
	title.theme_type_variation = &"Heading"
	holder.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if not fill:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows


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
	if key.keycode == KEY_ESCAPE:
		# **ESC CLOSES WHICHEVER POP-UP IS UP, AND NOTHING ELSE** (ASSA-316 ruling 2; ASSA-328 and
		# Maren's §1 for the build screen). It is the key every pop-up in every game answers to, which
		# is why both may rely on it; and with neither open this does nothing at all, because Esc
		# meaning "and otherwise, something" is how a key ends up quitting a session somebody was
		# playing.
		#
		# **BOTH, NOT A BRANCH, AND THE TWO CANNOT BOTH BE UP** (her §1: mutually exclusive). A branch
		# here would be a third place that knows the exclusion, and the day a bug left both open Esc
		# would close one and leave the other -- so each close is a no-op on a surface that is shut and
		# both are called.
		_close_machine_menu()
		_close_build_screen()
	elif key.keycode == KEY_L:
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
	# **THE DOOR HAS A WORLD NOW, SO THIS MAY NOT REQUIRE A SESSION** (ASSA-292). This read
	# `_close_up and _sim.running()`, which was exactly right for as long as the door was a dark
	# rectangle: before a world existed nothing on this screen moved. `_door_view` is built inside
	# `_refresh_world`, so under the old guard the title camera advanced only on frames where
	# something else happened to refresh -- which at the door is never.
	#
	# **THE TITLE SCREEN WAS A STILL PHOTOGRAPH OF A DRIFTING CAMERA, and all three of my drift tests
	# passed the whole time** (ASSA-292): they assert `AssayScene.title_drift`, which is correct
	# arithmetic that nothing was calling. A unit test cannot see an unwired caller -- hence
	# `test_the_door_keeps_refreshing_itself_with_no_session` below the fix, which asserts the CALL.
	#
	# It also fixed the door plate, which is sized from laid-out children: `_place_door_plate` ran
	# exactly once, inside `_ready()`, where every child is still 0x0 -- so it hid itself and was
	# never asked again. Two defects, one guard.
	if _close_up:
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
	# **THE PREVIOUS WORLD'S STANDING NOTICE DOES NOT CROSS INTO THIS ONE** (ASSA-370). A `Welcome`
	# replaces the world, so a sentence about building 3 being stopped is about a building that no
	# longer exists and nothing will ever retire it. Before both branches: a `Welcome` we cannot
	# simulate has also replaced the world.
	_forget_the_standing_notice()
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
	#
	# **AND WHAT EACH ONE IS ABOUT COMES WITH IT** (ASSA-300). `attention_conditions` is the same
	# `attention_pairs` call as the lines above, mapped the other way, so element i is element i by
	# construction rather than by agreement. A stall notice arrives carrying the building it is a claim
	# about and `_age_the_saying` can take it down when that building is working again; everything else
	# arrives as -1 and nothing will ever take it down.
	var notices := _sim.attention_lines(_client.player_id)
	if not notices.is_empty():
		var about := _sim.attention_conditions(_client.player_id)
		# THE SIZES AGREE OR NOTHING IS A CONDITION, and the fallback is the safe direction. Reading
		# past the end of a `PackedInt64Array` yields 0 in GDScript, which would read as "a condition
		# about building 0" and could fade a refusal -- the one class of sentence ASSA-239 says a
		# player cannot recover. `test_sim_binding.gd` asserts the two really are the same length; this
		# is what happens if that ever stops being true in a shipped build.
		var kind: int = (about[notices.size() - 1] if about.size() == notices.size()
				else NOT_A_CONDITION)
		# **AND THE KIND CHOOSES THE SLOT, WHICH IS THE WHOLE OF ASSA-370** (the Game Director's
		# amendment). A condition goes to the standing notice, where only its own condition can end it.
		# An act — a refusal, with no building — goes to the transient line over it, where the next
		# thing that happens to this player replaces it and nothing re-asks the sim about it.
		if kind == NOT_A_CONDITION:
			_say(notices[notices.size() - 1], AssayHud.Say.FAILED)
		else:
			_stand(notices[notices.size() - 1], AssayHud.Say.FAILED, kind)


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


## **THE TRANSIENT LINE, AND IT NO LONGER TAKES A BUILDING** (ASSA-370). ASSA-300 gave this function a
## third argument so the sim's answer to *what is this a claim about* could never be set by anything
## else; the argument has moved to `_stand`, which is now the only setter of that triple, so the
## property is intact and the thing that caused ASSA-370 is gone: **a sentence about an act cannot
## reach the standing notice at all, not even to clear it.**
##
## Everything that comes through here is about a moment — a receipt, a refusal, a connection state —
## and it is DRAWN OVER whatever standing notice exists. It never destroys one.
func _say(line: String, level: int) -> void:
	_base_line = line
	_base_level = level
	# WHEN, IN THE WORLD'S OWN CLOCK, so `_age_the_saying` can let a healthy line go. -1 while there is
	# no world: a sentence said during the handshake has no tick to be older than, and it is cleared by
	# the world arriving rather than by ageing.
	_said_at_tick = _sim.tick() if _sim != null else -1
	_render_status()
	print(line)


## **THE STANDING NOTICE, AND `about_building` IS THE SIM'S ANSWER, NEVER THIS FILE'S GUESS**
## (ASSA-300 for the question, ASSA-370 for the separate home). The only caller is `_remember_events`,
## handing over the sentence and the building `attention_conditions` crossed with it.
##
## **PRINTED ONLY WHEN THE SENTENCE CHANGES, BECAUSE THIS ONE CAN BE RE-SAID.** The transient above is
## said once per thing that happened; a standing notice can arrive again for a condition already
## standing (the sim's attention list is re-read whenever it is non-empty), and an unguarded `print`
## would put the same line in the console as fast as bundles land and bury the one that matters. Same
## reason `_refresh`'s `joined at tick N, but no world` branch is guarded.
func _stand(line: String, level: int, about_building: int) -> void:
	var changed := line != _standing_line
	_standing_line = line
	_standing_level = level
	_standing_building = about_building
	_render_status()
	if changed and line != "":
		print(line)


## **A NOTICE ABOUT A BUILDING IN A WORLD THAT IS GOING AWAY GOES WITH IT** (ASSA-370). Not an ageing
## rule: the condition is not resolved, the subject has ceased to exist, and a sentence about a
## building in a replaced world is false in the only way that matters — nothing can ever retire it,
## because `is_halted` will be answering about a different world's buildings.
##
## **REACHABLE, AND I ONLY SAW IT BECAUSE THE SLOTS SPLIT.** Before the split every world-death path
## set a non-empty FAILED transient over the triple, so a stranded notice was permanently covered and
## nothing showed. Afterwards `_on_welcomed`'s `joined as player N` is a JOINED transient that AGES —
## so a drop, a second Join, and two seconds later the previous world's stall sentence would surface
## over a fresh world.
func _forget_the_standing_notice() -> void:
	_stand("", AssayHud.Say.IDLE, NOT_A_CONDITION)


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
## **AND THE SECOND WAY A SENTENCE CAN STOP BEING TRUE: ITS CONDITION CLEARED** (ASSA-300, the Game
## Director's §300 ruling: *"a sentence about a CONDITION comes down when the condition does. A
## sentence about an ACT does not."*).
##
## **THE PARAGRAPH ABOVE WAS WRONG ABOUT `FAILED` AND IT TOOK AN ITEM TO SEE IT.** It read *"`FAILED`
## is a refusal, and no refusal is silent"* — true of a refusal and false of the other thing this
## level carries. A stall notice is not about an act of yours: it is a claim about a machine *now*, it
## already has a standing home in the pinned block and the `bench` list, and when it outlasts the
## condition it is simply false. Fuel the smelter and the sim stops reporting it, the pinned count
## drops to zero — and before this clause the toast still read `the … smelter (A) stopped: no fuel`
## until something unrelated happened to replace it. The screen contradicted itself and the half that
## was wrong was the half with the reason on it.
##
## **NO DWELL HERE, AND THAT IS THE POINT OF THE SPLIT.** A `JOINED` line goes quiet because it has
## been read; this one goes the moment it stops being true, which is not a duration. A dwell would
## leave a false sentence on screen for two seconds, and a false sentence is worse the longer it is
## legible.
##
## **THE QUESTION IS THE SIM'S AND IT IS ASKED BY ID, NOT BY TEXT.** `is_halted` is `World::halted`
## asked about one building — the same predicate `halt_lines` is worded from, so the toast and the
## pinned count cannot disagree about whether anything is stopped (box 6). Matching the two sentences
## instead would never clear anything: the pinned list says `smelter 3 at (12, 7) … stalled: the fuel
## will not light` where this one says `the Tonore smelter (A) stopped: no fuel`. Two wordings, one
## condition — and matching them loosely is the client classifying by reading, which
## `_remember_events` refuses by name (ASSA-67).
##
## **WHAT IT DELIBERATELY DOES NOT ASK IS WHETHER THE STALL IS THE SAME ONE.** A drill whose buffer
## you empty while its deposit runs out stays halted, so its notice stays up naming a reason that has
## been replaced. That is the coarse answer on purpose: the fine one would take the toast down while
## that building was still listed in the block, and the block carries the live reason. A moment's
## sentence may be out of date; the standing surface may not.
## **AND THE TWO CLAUSES ARE ASKED INDEPENDENTLY, WHICH IS ASSA-370 IN THE CONTROL FLOW** (the Game
## Director's amendment: *"a transient line may COVER a standing notice. It may never DESTROY one"*).
##
## This used to be one chain with an early return: a line carrying a building took the condition
## clause and nothing else, a line without one took the dwell. That was correct while the two kinds
## shared a slot, and the sharing was the bug. Now the standing notice and the transient over it are
## separate state, so **both can need ending on the same tick** — the smelter you just fuelled, and
## the receipt for having fuelled it — and a chain would silently do only the first.
func _age_the_saying() -> void:
	# THE CONDITION FIRST, SO AN UNCOVERING FRAME CANNOT SHOW A SENTENCE THAT IS ALREADY FALSE. If the
	# transient went first, this function's own two writes would leave one frame's worth of
	# `_render_status` drawing a stall notice whose building is working again — and the uncovering tick
	# is exactly the tick a player is looking at the toast.
	#
	# `_sim` is non-null here: a building id only ever arrives from `attention_conditions`, which needs
	# a world to have answered.
	if _standing_building != NOT_A_CONDITION and not _sim.is_halted(_standing_building):
		_forget_the_standing_notice()
	if _base_line == "":
		return
	if _base_level != AssayHud.Say.JOINED:
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
	_status.text = _shown_line()
	_say_in(_shown_level())
	_place_says_toast()


## **THE ONE VISIBLE SLOT, DERIVED FROM THE TWO STORED LINES** (ASSA-370). A pair of accessors rather
## than a third pair of fields, for the same reason the status label is derived from `_base_line`
## instead of being saved and restored: the cover rule is then a RULE, in one place, and not two
## assignments somewhere that have to agree.
##
## **THE TRANSIENT WINS WHILE IT EXISTS, WHATEVER ARRIVED LAST.** Not newest-wins: a standing notice
## that displaced a receipt would make the receipt channel unreliable exactly while a machine is
## stopped, which is the trade the Game Director refused in shape (a). The transient is covering
## furniture with a short life of its own; when it goes, the condition underneath is still true,
## because `_age_the_saying` has been re-asking the sim about it the whole time.
##
## **AND A REFUSAL COVERS INDEFINITELY, WHICH IS CORRECT AND NOT A GAP** (her section 4): a refusal is
## about an act of yours and never ages, so it holds this slot for as long as it is the last thing
## that happened to you. A standing fact about a machine has the pinned block and the `bench` list; a
## refusal has nowhere else to be.
func _shown_line() -> String:
	return _base_line if _base_line != "" else _standing_line


func _shown_level() -> int:
	return _base_level if _base_line != "" else _standing_level


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
	# **BEFORE THE READOUT, AND THE ORDER IS THE WHOLE REASON THIS CALL IS HERE AND NOT BELOW** (ASSA-316).
	# This is the function that closes the menu when its machine stops existing -- `Pick up` is one of its
	# own buttons -- and the readout under it gives that machine's prose up while a menu is open. Asked
	# the other way round, the tick a machine is picked up prints neither: the menu is gone and the line
	# it displaced was already composed.
	_refresh_machine_menu()
	# **AND THE BUILD SCREEN, WHICH IS WATCHING A COUNT THAT CLIMBS EVERY MINING CYCLE** (ASSA-328). A
	# screen whose whole job is *"can you afford this"* and which answered with the pack you had when
	# you opened it would be wrong for as long as it was up -- and this one is meant to be left up.
	_refresh_build_screen()
	# **THE MACHINE WHOSE MENU IS OPEN DOES NOT STATE ITS CASE TWICE** (Maren's ruling 6). One fact, one
	# home, and the home is the surface that can act on it.
	_cursor.text = "%s\n%s" % [source, "\n".join(AssayHud.tile_lines(_sim.tile_at(at), _menu_at))]
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

	# **THE VERDICT GOES ABOVE THE NUMBERS** (ASSA-264, Maren's ruling of 2026-10-08: ORDER BEFORE
	# RANK). This row rendered the tags LAST, which put `[too hard for anything you can build]` 80 px
	# below the name it belongs to, under six readings that no longer matter if it says that. Her
	# measurement off the shipped tab: the row spends two inks on five kinds of fact, and the free move
	# is order rather than a third grey.
	#
	# **THE REASON WAS ALREADY WRITTEN IN THIS CLIENT AND THE SCREEN DID THE OPPOSITE.**
	# `species_tags`' own docstring says *"`mining` LEADS, because it is the question a player is
	# asking of six rows at once"* -- the helper has ordered the tags by that reason all along, and the
	# row then put the whole line last. Same ruling as ASSA-130/242: a surface answers before it
	# reports.
	var tags := AssayHud.species_tags(species)
	if not tags.is_empty():
		var verdict := _note("[%s]" % "] [".join(tags))
		verdict.name = SPECIES_TAGS
		_indent_under_the_name(verdict, head, disc)
		row.add_child(verdict)
	row.add_child(_readings_table(species))
	return row


## **THE VERDICT STARTS WHERE ITS NAME STARTS** (ASSA-264, Maren's ruling of 2026-10-08 11:02Z, the
## second half of ORDER BEFORE RANK).
##
## Moving the verdict under the name fixed the 80 px but left it **flush with the readings table**:
## measured on a 1x real window, the verdict's ink began at x947 and the property labels under it at
## x946, while the name it belongs to began at x970 -- 24 px right, because the name sits past its
## 18 px map disc. So the line read as the table's first row rather than as the name's answer.
##
## **THE REASON IS HERS AND IT IS WHY THERE IS STILL NO THIRD INK.** A verdict that can never change
## and a reading that will are different kinds of fact; flush and same-grey are two signals both
## saying *same kind*. Alignment is the second free signal, spent before a colour.
##
## **THE NUMBER IS READ OFF THE ROW, NEVER TYPED.** The disc's own box plus the head's own gap are
## what put the name where it is, so they are what put the verdict there too: change `GLYPH_BOX_PX`
## or the gap and this follows, with nothing to remember. A typed 24 would be correct today and a
## silent lie the first time the disc grew.
##
## The no-type-argument `get_theme_constant` read is honest for the one reason ASSA-246 leaves open:
## this separation is an OVERRIDE on this very node, and an override is consulted before the type
## chain, so there is no unpoked variation to resolve through (Limpet, ASSA-312).
##
## **AND NOTHING ELSE MOVES** -- in particular the readings table is not shifted to meet it, because
## ASSA-288's axis geometry is measured and 24 px would re-derive it. The inset narrows the verdict's
## own wrap width by exactly those 24 px, which is the cost of an indent and not a bug: a shift
## without the narrowing would push the longest verdict off the column's right edge (ASSA-98).
func _indent_under_the_name(line: Label, head: HBoxContainer, disc: Control) -> void:
	var inset := disc.custom_minimum_size.x + float(head.get_theme_constant(&"separation"))
	var pad := line.get_theme_stylebox(&"normal", &"Label").duplicate() as StyleBox
	pad.content_margin_left = inset
	line.add_theme_stylebox_override(&"normal", pad)


## **THE SIX READINGS AS A TABLE WITH AN AXIS, WHERE THEY WERE ONE WRAPPED SENTENCE** (ASSA-288,
## ASSA-276 move 3, Maren's two rulings of 2026-10-08).
##
## WHAT WAS HERE: `AssayHud.species_readings_line`, which joined all six into
## `density 26-50 · strength 51-75 · ...` and let it wrap in a 318 px column. Every number was
## present and none of them could be COMPARED -- not against each other, and not against the scale
## they sit on, which a reader had no way to know was `(1, 100)`. Maren's rule 2 is that comparing
## down the column is the only thing a position encoding is for.
##
## **EVERY STRING IS STILL THE SIM'S.** The label is the property key as `Property::ALL` spelled it,
## the value is `readings[property]` verbatim, and the mark is `reading_ranges[property]` against
## `AssaySim.reading_scale()`. This function joins nothing, parses nothing and orders nothing: a
## seventh property appears here with no change, exactly as it did when this was one line.
##
## **THE SCALE IS ASKED ONCE PER TABLE, NOT ONCE PER ROW.** It is one call either way, but asking per
## row invites the next reader to pass a different denominator to one of six tracks, and six tracks on
## six different axes is the defect this whole move exists to end.
##
## **A PROPERTY WITH NO RANGE GETS ITS TEXT AND NO AXIS, AND THIS IS THE BRANCH I FIRST WROTE AS A
## DEFAULT.** My own comment claimed `ranges.get(property, Vector2i.ZERO)` would draw nothing,
## because (0,0) is off the bottom of a `(1, 100)` scale. It is not: `reading_span` CLAMPS into the
## axis and then applies Maren's 2 px floor, so the absent case would have rendered as a confident
## 2 px mark at the very bottom of the scale -- the most specific possible claim about a number
## nobody sent. `reading_ranges` carries one pair per property (`test_sim_host.gd` asserts the count
## against `Property::ALL`), so a missing key is a binding regression, and an absent axis is how a
## readout says "I was not given this" instead of guessing. The default was the bug.
func _readings_table(species: Dictionary) -> Control:
	var table := VBoxContainer.new()
	table.name = SPECIES_READINGS
	table.add_theme_constant_override("separation", 1)
	var readings: Dictionary = species.get("readings", {})
	var ranges: Dictionary = species.get("reading_ranges", {})
	var scale: Vector2i = _sim.reading_scale() if _sim != null else Vector2i.ZERO
	var assayed := bool(species.get("assayed", false))
	for property in readings:
		var name := String(property)
		var text := String(readings[property])
		var row := AssayReadingRow.new()
		if ranges.has(property):
			var span: Vector2i = ranges[property]
			row.show_reading(name, text, span.x, span.y, scale, assayed)
		else:
			row.show_unmarked(name, text)
		table.add_child(row)
	return table


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
	# **AND THAT RULE DIED WITH THE VERB IT WAS ABOUT** (ASSA-328). Every paragraph above is kept
	# because it is the record of why `cost` crosses the binding at all, and the DISABLE it justified is
	# gone: the row's control no longer makes anything, it opens the screen where have/need is printed
	# for every material at once (Maren's §3, Factorio). **A launcher disabled on affordability hides
	# the one surface that explains the shortfall from the one player who needs it** -- which is
	# ASSA-247's own principle, not an exception to it: a weight that does not follow availability is a
	# lying control, and "you may look at what this costs" is available always.
	#
	# `cost` IS STILL READ, ON THE SCREEN, AS DATA (`AssayHud.cost_counts_line`), so nothing about the
	# binding field or the reasoning above is withdrawn -- only the control it used to grey out.
	return button


## THE PRESS ITSELF, split out so the availability rule above reads as one decision over one button
## rather than three returns each having to remember it.
func _make_verb_button(offer: Dictionary, what: String, _item: Dictionary) -> Button:
	# **THERE IS NO ONE-CLICK MAKE ANY MORE, AND THAT IS THE PRICE MAREN SAID OUT LOUD** (ASSA-328;
	# her §2: *"THE PRICE, SAID OUT LOUD: there is no one-click make any more. Crafting goes from one
	# gesture to two. I am paying it because (a) Hasan asked for 'not just make buttons', which is a
	# request for the step to exist, and (b) ASSA-316 ruling 6 -- one fact, one home. A row that both
	# makes and opens a maker is the same verb with two homes."*)
	#
	# **SO THE MATCH ON `verb` LEFT THIS FUNCTION RATHER THAN BEING DUPLICATED.** Which command a row
	# sends is now decided once, at the press of `Build`, in `_send_build` -- the row no longer sends
	# anything, so the row no longer needs to know. The verb still crosses and is still the sim's
	# answer; this button just stopped being the thing that acts on it.
	#
	# `_item` IS KEPT IN THE SIGNATURE AND UNUSED, because `_make_button` above reads `offer` for the
	# affordability rule and builds the item for it; dropping the parameter would move that call and
	# make this diff about two things.
	return _button(AssayHud.make_launch_text(), func() -> void: _open_build_screen(offer),
			"open the build screen on this: %s" % what)


## THE PACK, AS ROWS YOU CAN ACT ON. The words are `AssayHud.stack_line`'s and the verbs are
## `AssayHud.stack_verbs`', which reads them out of the sim's own part catalogue and the item's
## footprint -- so a Frame button exists because the sim has that part kind, and for no other reason.
## **IT READ THE RECIPE TABLE TOO UNTIL ASSA-331** (Maren's ruling: the insert pair is deleted).
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


## **WHAT A MACHINE'S SLOTS LOOK LIKE: which slots, how big, and what is in each** (ASSA-334). Not how
## MUCH is in each, which is the fill and climbs every tick a fire burns -- `_pack_shape`'s rule and
## `_pack_shape`'s reason: a rebuild on a number that moves four times a second frees the button under
## the player's cursor. The fill is re-texted by `_refresh_machine_slot_fills` instead.
##
## **THE HELD ITEM'S NAME IS SHAPE AND ITS COUNT IS NOT**, which is the one judgement in here. Swapping
## what a slot holds changes a LINE on screen, so it has to rebuild; burning through it does not.
func _slot_shape(it: Dictionary) -> String:
	var shape := PackedStringArray()
	for entry in it.get("slots", []) as Array:
		var slot: Dictionary = entry
		var held: Variant = slot.get("held")
		shape.append("%s/%d/%s" % [String(slot.get("role", "?")), int(slot.get("cap", 0)),
				String((held as Dictionary).get("name", "?")) if held != null else ""])
	return "|".join(shape)


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
##
## **`plated` IS WHICH GROUND THE SPRITE STANDS ON, AND IT IS A CONTRAST BAR RATHER THAN A TASTE**
## (ASSA-341; Maren's ruling off my own 1x shot). ASSA-71 put the ground sheet's median under pack
## icons *"so the spread between species closes BECAUSE they all sit on one surface"* -- a reason
## about a LIST of ore. The build screen's one picture has nothing to compare itself to, and a
## smelter is not ore: on that olive plate it measures **1.24:1**, below 11.9's 3:1 for a mark and
## below the board's standing 4.091:1. On the panel's own `SURFACE` the same sprite is **5.57:1**.
##
## **HER RULE IS THE BAR, NOT THE GEOMETRY: any sprite placed on that plate must clear 3:1 against
## it.** So the plate survives wherever it earns its 3:1 -- which is the whole pack, unchanged, where
## the species spread is the thing it was measured on -- and a caller whose sprite does not clear the
## bar passes `false` and takes the panel's ground instead. Defaulted to `true` so ASSA-71 holds for
## every existing caller without a word changing at their call sites.
func _icon_box(stack: Dictionary, reserve := false, plated := true) -> Control:
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
	# A PANEL AROUND THE RECT, NOT A CONTAINER WITH MARGINS. The `Panel` adds no content margin, so
	# the TextureRect fills it exactly and the scale ASSA-65 made exact (1/2 for an item, 1/4 for a
	# part) is untouched -- a `MarginContainer` or a `PanelContainer` would have quietly eaten it,
	# which is the bug ASSA-65 fixed.
	#
	# **THIS NO LONGER CLAIMS THE BOX STAYS EXACTLY `ICON_BOX_PX`, BECAUSE THAT SENTENCE WAS FALSE**
	# (ASSA-341 box 3, Maren's: *"a docstring that is false on its only call path"*). Two separate
	# reasons, and only the first is fixed:
	#
	# 1. Nothing here sets `size_flags_horizontal`, and a `VBoxContainer` child FILLS horizontally by
	#    default -- so in the build screen's column this plate stretched to 235 px while staying 48
	#    tall and read as a progress bar. **ASSA-343 fixed that at the call site** (`SHRINK_BEGIN`
	#    plus a square box), so her measurement is no longer reproducible on main.
	# 2. And the fix means the sentence is still false, now deliberately: that caller RESIZES the box
	#    it is handed. A docstring promising callers cannot do the thing a caller does is worth less
	#    than no docstring, so it says what is actually invariant -- the margins -- and leaves the
	#    box's size to whoever lays it out.
	var plate := AssaySprites.pack_icon_plate() if plated else Color(0, 0, 0, 0)
	if plate.a <= 0.0:
		# NO PLATE MEANS THE PANEL'S OWN GROUND, and the two ways here are not the same thing: a
		# `plated := false` caller is choosing it (ASSA-341's 3:1 bar), while a transparent
		# `pack_icon_plate()` means `ui_theme.json` is missing. Both want the bare art, so they share
		# this line -- but the horizontal flag has to be set here too, or the no-plate path rebuilds
		# ASSA-343's defect one branch over: a bare `TextureRect` in a VBox fills just as a `Panel`
		# does, and nothing in the suite would say so because nothing headless has a size.
		art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
	# **THE RECIPE TABLE IS NOT READ HERE ANY MORE** (ASSA-331). It was read for one thing: whether some
	# non-hand recipe eats this kind, which is what made the row's `Fuel`/`Smelt` pair. The pair is
	# deleted and the reading moved to the machine menu, so a pack row now asks the part catalogue and
	# the footprint and nothing else.
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
		var verbs := AssayHud.stack_verbs(stack, part_kinds, footprint)
		if not verbs.is_empty():
			body.add_child(_verb_row(verbs, func(descriptor: Dictionary) -> Button:
					return _stack_button(descriptor, stack, footprint)))
		_carrying.add_child(row)
		label.text = AssayHud.stack_line(stack)


## One verb on one stack. EVERY ITEM SENT IS THE ONE THE SIM NAMED: `item_of_stack` rearranges the
## three fields out of `inventory_of` and this client never works out what it is carrying.
## WITH THE MAKE-VERBS GONE (ASSA-86) AND THE INSERT PAIR GONE (ASSA-331) THIS HANDLES TWO: Place and
## Frame/Mount. The two locals that went with the make-verbs were `count` and the stack's sentence,
## both only ever read by the craft and make arms -- and `count` had in fact been dead since ASSA-55
## took the number out of the Fuel tooltip, which is the sort of thing that survives a deletion
## unnoticed.
##
## **THE `insert` ARM IS DELETED RATHER THAN LEFT HARMLESS** (ASSA-331, Maren's ruling). It read a
## slot out of the descriptor and sent the whole stack at whatever `_target_tile` pointed to, and under
## ruling 8 that cursor could never be on a building, so every press could only say *nothing to insert
## into*. An arm kept for a descriptor nothing produces is how the button comes back.
##
## **THAT REASON EXPIRED WITH ASSA-366 AND THE DELETION DID NOT.** The cursor CAN sit on a building now
## -- opening its menu puts it there -- so a pack-row insert would be aimable again. It stays deleted
## because of the OTHER half of her ruling: there is one door for every insert and it is the menu, which
## already knows which machine it is about and cannot be pointed at the wrong one. A rule whose stated
## reason has gone false is a rule the next person deletes; this one is kept on purpose.
func _stack_button(descriptor: Dictionary, stack: Dictionary, footprint: Vector2i) -> Button:
	var label := String(descriptor.get("label", "?"))
	match String(descriptor.get("verb", "")):
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
			# **A FRAME ROW LAUNCHES THE BUILD SCREEN; A MOUNT ROW STILL MOUNTS** (ASSA-317 slice
			# 2b; Maren's §2: *"tabs stay as launcher and ledger; the screen is where you build"*).
			# Starting a design is where the screen belongs -- its slots are what you are about to
			# fill -- and the asymmetry is deliberate rather than half a migration: `Mount` on a
			# pack row is the gesture that works with no screen open, and from inside the screen the
			# same press comes through the mount list. Both land in `_choose_part`, so there is one
			# refusal path and one sentence.
			if bool(descriptor.get("is_frame", false)):
				return _button(label, func() -> void: _open_assembly_screen(stack),
						"open the build screen on this frame")
			return _button(label, func() -> void: _choose_part(stack),
					"mount on the frame of the next machine")
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
	# **THE BUILDING'S ID IS BACK, AND THE PREMISE THAT TOOK IT OUT WAS FALSE WHEN IT WAS WRITTEN**
	# (ASSA-353, found by Cove off a 1x frame; the reader was Nacre, who did not know this line
	# existed). This comment used to say: *"it was here for `Take` and `Pick up`, which now live in
	# the machine's own menu; a term in a cache key that no drawn thing depends on is a rebuild
	# nobody asked for."* **Maren's ruling 3 is sound -- those two acts do belong in the menu -- but
	# a drawn thing does depend on it:** `AssayHud.target_line`, thirty-five lines below at the
	# bottom of this very function, names the building standing on the target. With the id gone its
	# clause froze at whatever stood there when the target was last chosen, so a machine you had just
	# placed was described as the bare rock it replaced.
	#
	# **AND ON MAIN THAT CLAUSE WAS ONLY EVER DRAWN WHILE IT WAS WRONG** (Cove's second measurement,
	# which is why this is a behaviour fix and not a tidy-up). A right-click on a tile carrying a
	# building opens that building's MENU and returns before `_target` is set, so no gesture could
	# ever point this sentence at a standing building on purpose: the only way it named one was the
	# stale path, and `clear ground` after a `Pick up` was right by cancellation rather than by
	# refresh. This is the first state of the client in which the building clause can be true.
	#
	# **THE ID, NEVER THE STATUS**, which is the docstring's rule above and is why this is one term
	# and not `facts` itself: a smelter's status sentence changes every tick while it burns, and
	# rebuilding on that would free the Take button four times a second. `-1` is safe as the absent
	# value because `BuildingId` is a `u32` counting from zero.
	var standing: Variant = facts.get("building")
	var building_here := -1
	if standing != null:
		var b := standing as Dictionary
		# `building_dict` always sets `id`; an absent one means a stale `libsim_godot.dylib`, the
		# same cause `target_line` names when `name` is missing. Loud there, harmless here -- a
		# missing id just keeps the old value, and that file already pushes the error.
		if b.has("id"):
			building_here = int(b["id"])
	# **AND WHETHER A POP-UP IS HOLDING THE ACCENT, FOR THE THIRD TIME THE REASON ABOVE IS WRITTEN**
	# (ASSA-374). `Mine` stands down while the build screen is up, and opening or closing that screen
	# moves NONE of the other terms here -- not the target, not the cursor, not the rock, not the
	# link. Left out, the row keeps the accent it had when the pop-up opened and gets it back only
	# when something unrelated happens to move, which is `minable`'s defect and `live`'s defect again.
	#
	# **MEASURED: the guard below was CORRECT and did nothing without this term.** With the `if`
	# already asking `_popup_holds_the_accent` and this signature unchanged, the test read two
	# `Primary` controls with the build screen open -- the row simply never rebuilt.
	var accented := _popup_holds_the_accent()
	var signature := "%s/%s/%s/%s/%s/%s/%s" % [target, _targeted, _building, minable, live,
			building_here, accented]
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
	#
	# **AND IT STANDS DOWN WHILE A POP-UP CARRYING ITS OWN `Primary` IS OPEN** (ASSA-374, Maren's
	# ruling, on a collision of two of her own rules). Her §4 keeps this column uncovered while the
	# build screen is up and ASSA-317 ruling 5 makes `Build` *"the one ACCENT"*, so a green `Mine` and
	# a green `Build` sat on one 1280x720 screen together -- against ASSA-335 ruling 1, *accent marks
	# the one act a screen is for, one region per screen*. With the build screen up that act is
	# `Build`: a pop-up is the answer to a question the player just asked, and two greens makes them
	# choose between answers while their question is still open.
	#
	# **IT DISABLES NOTHING.** Standing down to the default weight is not a grey-out -- `Stop` and
	# `Assay` have always sat there and are pressable. Same callback, same tooltip, same hover and
	# pressed states; the rank returns the moment the pop-up closes.
	#
	# **AND THE CONDITION IS THE POP-UP *HAVING* A `Primary`, NOT A POP-UP EXISTING** -- which is why
	# `_popup_holds_the_accent` walks for one rather than naming the build screen. A machine menu has
	# no primary act by ASSA-316, so standing `Mine` down for it would leave the screen with no accent
	# at all: a loss with nothing bought. Her rule is *never two at once*, not *the world dims when
	# anything opens*, and a structural test keeps those two apart without this file deciding which
	# pop-up is which.
	var mine_button := _button("Mine", func() -> void: _act("Mine", AssayActions.mine()),
			"hand-mine the deposit under you. Keeps swinging until you Stop.")
	if minable and live and not accented:
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

	# **`Take` AND `Pick up` ARE NOT HERE ANY MORE: THEY ARE IN THE MACHINE'S OWN MENU** (ASSA-316,
	# Maren's ruling 3, and her condition that they leave on the commit that makes the menu reachable --
	# which is this one).
	#
	# THE REASON IS THAT THEY WERE ALREADY CONDITIONAL ON A BUILDING. This block ran `if building !=
	# null`, so both verbs only ever existed when a machine was chosen; the menu is their true home and
	# two homes for one verb is the defect. **AND IT DISCHARGES §11.36 FOR FREE** (a verb may not sit
	# under a subject it does not act on, ASSA-276 move 2): what is left in `do` is Mine / Stop / Assay,
	# all three acting under your own body, so there is nothing left to disambiguate and the two-bar
	# redesign that move had costed is not needed.

	# THE CHOSEN PARTS USED TO BE DRAWN HERE and are now in the crafting menu, under the running
	# craft (ASSA-107). `_refresh_assembling` owns them.


## **OPEN A MACHINE'S MENU** (ASSA-316). Either mouse button on a tile carrying a building, which is
## Maren's rulings 7 and 8 together: left-click because *"in a click-to-move game the single gesture a
## player has must resolve on what is under the cursor, ground meaning go"*, and right-click because
## after ruling 3 a right-click on a building would otherwise arm a placement the sim is guaranteed to
## refuse (`TileOccupied`) and offer no verb that acts on it.
##
## **ONE MENU AT A TIME, AND OPENING A SECOND CLOSES THE FIRST RATHER THAN STACKING** (ruling 2). That
## is this function with no extra code: there is one `_menu_at`, so a second machine replaces the first.
##
## **IT CHANGES NO SIM STATE AND SENDS NOTHING.** Opening is a client gesture; every act inside the menu
## is a command the sim judges.
##
## **AND IT AIMS THE VERBS AT THIS MACHINE** (ASSA-366; Maren amending her own ruling 8: *"opening a
## machine's menu also targets that machine ... a mechanism no gesture invokes is not a design, it is
## dead weight"*). This paragraph used to say the opposite -- that opening deliberately does NOT set
## `_target` -- and the consequence nobody had measured is that the branch above returns before the one
## line that assigns it, so **a player could never aim at a building that was already standing.** The
## only way a ring ever sat on one was a residue: aim at bare ground, plant a machine there, and the
## target is left standing on what you built. That is where ASSA-326's ringed drill came from -- a state
## a player cannot ask for.
##
## **IT CREATES NO NEW STATE, WHICH IS WHY IT IS SAFE** (hers). Placing already leaves the target on the
## new building and `Place` is then refused with *"another building is in the way"*; this makes a state
## that already existed reachable on purpose. A refusal is an outcome; a mark you cannot aim is not.
func _open_machine_menu(tile: Vector2i, id: int) -> void:
	# **AND IT CLOSES THE BUILD SCREEN** (ASSA-328; Maren's §1: *"the build screen and a machine menu
	# are mutually exclusive -- opening either closes the other"*). Said at both ends, because a rule
	# written at one end holds only until somebody opens the other.
	_close_build_screen()
	_menu_at = id
	_menu_tile = tile
	# **THE CLICKED TILE, NOT THE BUILDING'S ANCHOR** (ASSA-366). `_target` is a tile and every reader of
	# it wants the tile a player pointed at; the EXTENT of what stands there is `_footprint_tiles`' job
	# and the ring asks it on every refresh. Storing the anchor instead would be this file deciding a
	# building's shape in a second place, which is the two-subjects defect one layer down.
	_target = tile
	_targeted = true
	# THE ROWS ARE REBUILT EVEN IF THE SAME MACHINE IS CLICKED TWICE, because the pack may have changed
	# while the menu was shut and the signature cannot tell "closed" from "unchanged".
	_menu_showing = UNBUILT
	_refresh_machine_menu()
	# **A FULL `_refresh()` AND NOT `_refresh_world()`, AND THE DIFFERENCE IS THE WHOLE POINT OF ASSA-366.**
	# The ring is published by `_refresh_world` and the `do` column's `acting on ...` line by
	# `_refresh_actions`; refreshing only the world would move the mark in the frame of the click and leave
	# the column naming the tile you aimed at before -- two subjects on one screen for up to a bundle, which
	# is the exact defect this item and ASSA-334 exist to kill. The right-click branch in `_unhandled_input`
	# has always called `_refresh()` here for the same reason, and this is now the same kind of gesture.
	# It also still does what it did before: `_place_machine_menu` runs inside the menu refresh above, so
	# the panel lands beside its machine in the click's own frame rather than on the next tick bundle --
	# the quarter-second ASSA-215 measured for the walk echo.
	_refresh()
	queue_redraw()


## **CLOSE IT. Esc, the named control, or a click on the map outside it** (ruling 2).
##
## NOTHING IS SENT AND NOTHING IS CLEARED BUT THIS. Walking out of range does not close the menu
## either: the sim refuses an act at distance and the refusal is a line in the log, which is the rule
## this whole item is built on -- *no act is ever disabled, the sim refuses and says why.*
func _close_machine_menu() -> void:
	if _menu_at == -1:
		return
	_menu_at = -1
	_menu_showing = UNBUILT
	if is_instance_valid(_menu_box):
		_menu_box.visible = false
	_refresh_world()
	queue_redraw()


## **WHAT THE MENU SAYS, ON THE THREE CLOCKS ITS THREE PARTS MOVE ON** (ASSA-316).
##
## **IT CLOSES ITSELF WHEN THE MACHINE IS GONE, AND THAT IS THE ONE BRANCH THIS SURFACE CANNOT DO
## WITHOUT.** `Pick up` is in this menu, so the common way to leave it is to delete the thing it is
## about: the building comes back into your pack and the tile is bare. A menu left open over nothing
## would be the only surface in this client making a claim the sim has withdrawn -- and `_menu_at` is
## an id, so it cannot be mistaken for the next building that lands on the same tile.
##
## THE STATE SENTENCE IS RE-TEXTED EVERY TICK AND THE ROWS ARE NOT. A Label's text is idempotent and
## free; a row carries a Button a cursor may be resting on (`_refresh_actions`' note).
func _refresh_machine_menu() -> void:
	if _menu_at == -1 or not is_instance_valid(_menu_box):
		return
	if not _sim.running():
		_close_machine_menu()
		return
	var facts := _sim.tile_at(_menu_tile)
	var building: Variant = facts.get("building")
	if building == null or int((building as Dictionary).get("id", -1)) != _menu_at:
		_close_machine_menu()
		return
	var it: Dictionary = building
	_menu_box.visible = true
	var named := String(it.get("name", ""))
	# A MISSING NAME IS LOUD AND NOT PAPERED OVER, the same contract as `AssayHud.target_line`: the only
	# way here is a stale `libsim_godot.dylib`, and falling back to `kind` would look fine.
	_menu_name.text = named if named != "" else "building %d" % _menu_at
	# **THE CONDITION, AS THE SIM'S ONE SENTENCE FOR IT, RED ONLY WHEN IT IS A STALL** (ASSA-334 §6;
	# the binding's own words for this field: *"the condition on its own line, in `FAILED` when it is a
	# stall"*). The verdict is `state`, which the sim publishes for exactly this -- see
	# `AssayHud.state_is_failure` for why neither `stopped` nor "not working" may stand in for it.
	# **THE INK IT GOES BACK TO IS HELD, NOT ASKED OF THE NODE, AND THAT IS A BUG I SHIPPED INTO A
	# SCREENSHOT.** This read `_menu_state.get_theme_color(&"font_color", &"Label")` for the normal
	# case -- and `get_theme_color` answers out of the node's OWN OVERRIDES first, so the moment a
	# machine stalled once, the "normal" colour it read back was the `FAILED` it had just written. The
	# line stayed red for the rest of the session. Measured on `nacre-assa334-anchor`: `idle: nothing to
	# refine` drawn in (242,102,89) on a smelter the sim called idle. A node is not a place to store a
	# constant you are also writing to.
	_menu_state.text = String(it.get("state_line", ""))
	_menu_state.add_theme_color_override(&"font_color",
			AssayHud.status_color(AssayHud.Say.FAILED) \
			if AssayHud.state_is_failure(String(it.get("state", ""))) else _menu_state_ink)
	# **THE BATCH: THE SIM'S CLAUSE AND THE SIM'S PAIR, OR NOTHING AT ALL** (ASSA-339). `work` is nil
	# whenever nothing is in front of the machine and `work_clause` is nil in exactly the same cases
	# (asserted in `sim-godot`), so this reads the pair for the band and the clause for the words and
	# invents neither. The NOUN in that clause is a sim decision -- ticks of a recipe for a smelter,
	# work toward a unit for a drill -- and ASSA-334 crossed it through the binding rather than let
	# this file pick one.
	# **`nil` IS READ AS `nil` AND NOT THROUGH A DEFAULT.** `Dictionary.get(key, "")` returns the default
	# only when the KEY is missing, and these two keys are always present and carry `nil` for "there is
	# no batch" -- so `String(it.get("work_clause", ""))` is `String(null)`, which is a runtime error and
	# not an empty string. Five tests found it; the binding is explicit that both fields are nil
	# together, and this is the branch that reads them that way.
	var work: Variant = it.get("work")
	var clause: Variant = it.get("work_clause")
	var batch: Vector2i = work if work != null else Vector2i.ZERO
	_set_amount_row(_menu_work, String(clause) if clause != null else "", batch.x, batch.y)
	var stacks := _sim.inventory_of(_client.player_id) if _client != null else []
	# **THE SLOTS ARE IN THE SIGNATURE NOW AND THE REASON IS THE BANDS** (ASSA-339). The rows used to
	# depend on the pack alone; a slot's fill is a row too, and its CAP and its contents' NAME change
	# only when something moves in or out. `_slot_shape` is counts-free for `_pack_shape`'s reason -- a
	# smelter burning through a stack would otherwise free the button under the player's cursor four
	# times a second -- so the FILL itself is re-texted below, outside the rebuild.
	var signature := "%d/%s/%s" % [_menu_at, _pack_shape(stacks), _slot_shape(it)]
	if signature != _menu_showing:
		_menu_showing = signature
		_rebuild_machine_menu_rows(stacks, it)
	_refresh_machine_slot_fills(it)
	_place_machine_menu()


## **THE SLOT ROWS AND THE ACTS** (ASSA-316, Maren's ruling 4).
##
## **A SLOT ROW LISTS THE STACKS THAT CAN GO IN IT, ONE BUTTON PER STACK, AND THE LABEL IS THE RESULT**
## -- `put all 37 Tonore ore` -- so the common case is one gesture and the button says what it does. The
## column's old pair said `Fuel` and `Smelt` with the number hidden in a tooltip.
##
## **WHICH SLOTS EXIST AND WHAT MAY GO IN THEM IS THE SIM'S ANSWER, ASKED PER STACK.**
## `AssayHud.insert_slots` names the slots a kind some non-hand recipe eats may enter, out of the sim's
## own recipe table -- *"which one a species is good for (hot enough fuel, or ore that melts) is a sheet
## reading and only the sim has it"*. So this walks the pack and groups by the slot the sim named, rather
## than this file knowing a smelter has two slots. **That reading used to arrive as the pack row's
## `insert` verb descriptors and now has its own function** (ASSA-331): the buttons it fed were deleted,
## and a menu asking `stack_verbs` for a verb no row draws would have been a dead argument away from
## bringing them back.
##
## **NOTHING IS EVER GREYED OUT AND NOTHING IS HIDDEN FOR BEING REFUSABLE** (ruling 4, ASSA-37): a stack
## of 1 simply has no fractions to offer, which is a shorter row and not a disabled control.
##
## **AND EVERY SLOT THE MACHINE HAS SAYS WHAT IS IN IT, AS A BAND** (ASSA-339, ASSA-334; ruling 5:
## *"a slot's fill and a burn's progress are RATIOS, so they take ASSA-276 move 3's band grammar. A
## count is text. No third grammar for a third kind of number."*). This docstring used to say those
## facts were unreachable, behind the binding's one `status` string. **THAT REASON EXPIRED ON
## 2026-10-08**, when Marlow's ASSA-321 crossed `slots[i].count` over `slots[i].cap` as data -- so the
## fill is a band off the sim's own pair, and the `status` paragraph that carried it in prose is gone.
##
## **A SLOT ROW IS DRAWN FOR EVERY SLOT, NOT ONLY THE ONES YOU CAN FILL.** `output` and `buffer` take
## no insert (`AssayActions`: *"offering an insert into an output slot would be a button whose only
## outcome is a refusal"*), and they are the two that answer the questions this menu exists for -- is
## there anything for `Take` to get, and is the thing jamming this smelter its own full output. A menu
## that listed only what you can press would hide the reason the machine stopped.
##
## **THE SLOT'S NAME IS ABOVE ITS BUTTONS AGAIN, AND IT IS NOT THE HEADING ASSA-331 DELETED.** That one
## was the word `Fuel slot` and nothing else -- the same answer the buttons under it already gave,
## which is ruling 6. This row is a READOUT: the slot, how full it is, and what is in it, none of which
## any button says. The grouping comes back for free, and the buttons still name their own slot, so
## each one survives being read alone.
func _rebuild_machine_menu_rows(stacks: Array, it: Dictionary) -> void:
	_clear(_menu_rows)
	_menu_slot_rows = {}
	var recipes := AssaySimHost.recipes()
	# **THE MACHINE'S OWN SLOTS, IN THE SIM'S ORDER, AND THAT IS A CHANGE FROM ASSA-316.** The rows used
	# to be built by walking the PACK and asking each stack which slots would take it, so a machine's
	# slots appeared in the order your pack happened to be sorted in and a slot nothing could go into
	# did not appear at all. Now the machine's `slots` list is the spine -- `insert_tag` is the slot name
	# the SIM parses (`sim-godot::insert_tag`, serde's own tag) rather than a constant this file keeps in
	# step with it -- and the pack is only asked which of its stacks may enter each one.
	for entry in it.get("slots", []) as Array:
		var slot: Dictionary = entry
		var role := String(slot.get("role", "?"))
		var held: Variant = slot.get("held")
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 2)
		var fill := _amount_row()
		# THE SLOT'S OWN WORD FROM THE SIM (`SlotRole::name`) AND NOTHING ELSE ON THIS LINE. An empty
		# slot says the slot and the band says the rest: `0 of 5` with no fill is what empty looks like,
		# so no word for it is invented here.
		_set_amount_row(fill, role, int(slot.get("count", 0)), int(slot.get("cap", 0)))
		group.add_child(fill)
		# **WHAT IS IN IT GETS ITS OWN LINE, AND THE REASON IS A MEASUREMENT.** The name was on the line
		# above, after the slot -- and that line's label column is CLIPPED (it has to be, or a long word
		# would push the band out of line with the band above it), so a 20-char species came out as an
		# ellipsis: `output · Remdornitexxxxx…`. The sim's own name for an item is not a thing this menu
		# may cut. On its own line it is 237 px of the 343 px floor (Maren's §6 table) and whole.
		if held != null:
			var what := _note(String((held as Dictionary).get("name", "")))
			what.autowrap_mode = TextServer.AUTOWRAP_OFF
			group.add_child(what)
		_menu_rows.add_child(group)
		_menu_slot_rows[role] = fill
		var tag: Variant = slot.get("insert_tag")
		if tag == null:
			continue
		var into := String(tag)
		for carried in stacks:
			var stack: Dictionary = carried
			if not AssayHud.insert_slots(stack, recipes).has(into):
				continue
			var count := int(stack.get("count", 0))
			var named := String(stack.get("name", "?"))
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			row.add_child(_button(AssayHud.insert_label(count, named, into),
					func() -> void: _insert_into(_menu_at, stack, into, 0),
					"put everything you are carrying of this into the %s slot" % into))
			# THE FRACTIONS, AS A ROW OF QUIET BUTTONS THAT NAME WHAT YOU WILL GET. `put 1 · put 18`,
			# never `put half`: a toggle that named a fraction would make the player do the arithmetic the
			# stack already answers. Empty for a stack of 1, which adds no row at all.
			var some := AssayHud.insert_fractions(count)
			if not some.is_empty():
				var fractions := HFlowContainer.new()
				fractions.add_theme_constant_override("h_separation", 4)
				for want in some:
					var part := _button(AssayHud.insert_some_label(want),
							func() -> void: _insert_into(_menu_at, stack, into, want),
							"put %d of your %d %s into the %s slot" % [want, count, named, into])
					part.theme_type_variation = &"Quiet"
					fractions.add_child(part)
				row.add_child(fractions)
			_menu_rows.add_child(row)
	# **THE TWO VERBS THAT LEFT `do` ON ASSA-316's COMMIT, AND THEY ACT ON THE MACHINE** (ruling 3).
	# Their words are the ones the column used, because that item moved a control and did not retune a
	# sentence.
	#
	# **THEY NO LONGER SIT UNDER A SLOT'S HEADING, WHICH IS MAREN'S §11.36 FINDING ON ASSA-334**: in her
	# shot they stood under `Input slot` and act on neither the input slot nor any other. They are the
	# LAST thing in the box, after every slot, which is the "or none" half of her ruling -- a heading of
	# their own would be a third kind of label in a box that now has two.
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 4)
	acts.add_child(_button("Take", func() -> void: _act("Take", AssayActions.take(_menu_at)),
			"empty the output slot into your pack"))
	acts.add_child(_button("Pick up", func() -> void: _act("Pick up", AssayActions.pickup(_menu_at)),
			"take the building back, with whatever is inside it"))
	_menu_rows.add_child(acts)


## **RE-TEXT EVERY SLOT'S FILL WITHOUT REBUILDING A BUTTON** (ASSA-334). A fill is the one number in
## this menu that moves on the sim's clock rather than on a gesture -- a fire eats its fuel, a batch
## fills an output -- and `_rebuild_machine_menu_rows` is on the pack-and-shape clock for
## `_refresh_actions`' reason: a rebuild frees the button under the cursor.
##
## **IT WALKS THE SIM'S LIST AND NOT THE HELD DICTIONARY'S KEYS**, so a slot the sim stopped reporting
## leaves no stale row behind re-texted with its own last value. A missing row is skipped rather than
## created: creating one here would put a slot's readout below the acts, in a function whose job is a
## string.
func _refresh_machine_slot_fills(it: Dictionary) -> void:
	for entry in it.get("slots", []) as Array:
		var slot: Dictionary = entry
		var row: Variant = _menu_slot_rows.get(String(slot.get("role", "?")))
		if row == null:
			continue
		# THE ROLE AND THE TWO NUMBERS, WHICH ARE THE THREE THINGS ON THIS LINE. What the slot HOLDS is
		# the line below and is `_slot_shape`'s business: swapping it rebuilds, so re-texting it here
		# would be a second writer for one fact.
		_set_amount_row(row, String(slot.get("role", "?")), int(slot.get("count", 0)),
				int(slot.get("cap", 0)))


## **BESIDE ITS MACHINE, RE-ASKED EVERY REFRESH** (ASSA-334; Maren's reversal of her own ruling 1).
##
## **EVERY REFRESH AND NOT ONCE AT OPEN, WHICH IS WHAT ANCHORING IS FOR.** In the close-up the camera
## follows the player, so the machine's footprint moves across the screen while you walk; a position
## decided at open would drift off its subject and the menu would be a panel parked near nothing. Under
## the two halves this re-asking was a COST -- walking past the centre line made the menu jump sides --
## and under an anchor it is the whole mechanism: the panel travels with the thing it is about.
##
## **THE WIDTH IS FLOORED AND THEN CAPPED, IN THAT ORDER** (ASSA-281's lesson, which I learned by doing
## it backwards): the engine's answer about the widest row is raised to Maren's floor, and only then cut
## to her cap by `machine_menu_rect`. Capping first and flooring after would hand the floor the power to
## undo the cap, which is a fix that silently stops fixing.
##
## **THE FLOOR IS THE CONTENT'S AND THE PANEL'S PADDING IS ASKED OF THE THEME.** 343 px is the widest
## string the sim can hand this menu; the stylebox either side of it is the theme's business, so this
## reads the margins in force rather than baking today's numbers into the constant. `_note`'s own
## comment is the precedent for an off-tree theme lookup being the honest way to ask.
## **HOW FAR UP THE WORLD'S OWN CONTROL BAND REACHES RIGHT NOW**, measured off the live controls, with
## `AssayHud.WORLD_CONTROLS_BAND` as the answer before anything has laid out (ASSA-328).
##
## **IT IS A FUNCTION BECAUSE TWO SURFACES MUST NOT COVER THAT BAND AND ONLY ONE OF THEM KNEW**
## (ASSA-334). The build screen has kept off it since ASSA-328 -- Maren listed the status toast and
## `whole world (V)` as things no surface may cover -- and the machine menu never had to, because the
## two halves kept it top-aligned. Anchored, it reaches the bottom corner: in
## `nacre-assa334-anchor/14-machine-menu.png` the toast `Place 0 · submitted` is drawn over the menu's
## own `close (Esc)`. One copy of the measurement, so the next surface inherits the rule.
func _world_band_top() -> float:
	var band := AssayHud.world_rect().end.y - AssayHud.WORLD_CONTROLS_BAND
	for control in [_view_toggle, _map_key_toggle, _says_toast]:
		var node := control as Control
		if node != null and node.visible and node.size.y > 0.0:
			band = minf(band, node.global_position.y)
	return band


func _place_machine_menu() -> void:
	if not is_instance_valid(_menu_region):
		return
	var world := AssayHud.world_rect()
	var pad := 0.0
	var skin := _menu_box.get_theme_stylebox(&"panel")
	if skin != null:
		pad = skin.get_margin(SIDE_LEFT) + skin.get_margin(SIDE_RIGHT)
	var want := _menu_box.get_combined_minimum_size()
	want.x = maxf(want.x, AssayHud.MENU_FLOOR_PX + pad)
	# **THE ROOM IS THE WORLD LESS THE CONTROL BAND, NOT THE WORLD** (ASSA-334; `_world_band_top`). The
	# REGION still clips at the world -- that is the HUD column's guarantee and it does not move -- but
	# the panel is placed inside the shorter rect, so an anchored menu on a machine at the bottom of the
	# screen stops above the status toast instead of being drawn under it.
	var rect := AssayHud.machine_menu_rect(AssayHud.build_screen_rect(world, _world_band_top()),
			_footprint_rect(), want)
	_menu_region.position = world.position
	_menu_region.size = world.size
	_menu_box.position = rect.position - world.position
	_menu_box.size = rect.size


## **WHERE THE MENU'S MACHINE IS ON SCREEN, FOOTPRINT AND ALL, in whichever view is up** (ASSA-334).
##
## **THE FOOTPRINT AND NOT THE CLICKED TILE, WHICH IS THE DIFFERENCE BETWEEN A PANEL BESIDE A MACHINE
## AND A PANEL ON TOP OF ONE.** A smelter is 2x2 and `_menu_tile` is whichever of its four tiles the
## player pressed, so anchoring to that tile would put the menu over the other half of its own subject
## half the time. The size is the sim's `footprint` for the building the menu is open on, and the origin
## is that building's own `pos`.
##
## **THE CELL IS ASKED OF `point_of_tile` TWICE RATHER THAN NAMED**, because the two views draw a tile
## at different scales (`TILE_PX` in the close-up, `_cell` in the whole world) and a third copy of that
## answer here is the constant-in-two-places defect. Two centres one tile apart differ by exactly one
## cell, which is a measurement of the view in force and cannot drift from it.
##
## A machine with no footprint -- which means the binding sent none -- falls back to one cell, so the
## menu lands beside the tile that was clicked instead of inside a zero-sized rect.
func _footprint_rect() -> Rect2:
	var centre := point_of_tile(_menu_tile)
	var cell := point_of_tile(_menu_tile + Vector2i.ONE) - centre
	var area := _footprint_tiles(_menu_tile)
	return Rect2(point_of_tile(area.position) - cell * 0.5, cell * Vector2(area.size))


## **WHAT THE SIM SAYS OCCUPIES `tile`, IN TILES: the whole building, or that one tile** (ASSA-348).
##
## `position` is the subject's top-left tile and `size` its span. A tile with no building on it
## answers `Rect2i(tile, Vector2i.ONE)`, and that is the RIGHT answer rather than a fallback: `Place`
## and `PlaceAssembly` carry a `TilePos`, so there the subject genuinely is one tile.
##
## **THE SPAN IS A SIM FACT AND IS NEVER INFERRED FROM A KIND OR A SPRITE.** `BuildingFacts.footprint`
## is already crossing the binding (`sim-godot/src/lib.rs`: *"A smelter is (2, 2) and a machine (1, 1)
## -- `BuildingKind::footprint`"*), and reading `"smelter" -> 2x2` on this side would be the client
## inventing a rule it does not own -- the same crossing `sim-godot`'s own note forbids. A building
## whose footprint the binding did not send falls back to one tile rather than to a zero-sized rect.
##
## **ONE COPY, BECAUSE THERE WERE ABOUT TO BE TWO.** `_footprint_rect` above wants this in screen
## pixels for the anchored menu (ASSA-334) and the selection outline wants it in tiles; written twice,
## the menu and the ring would be free to disagree about the extent of the very same machine, which
## is the two-subjects defect ASSA-334 was filed for, reintroduced one layer down.
func _footprint_tiles(tile: Vector2i) -> Rect2i:
	var origin := tile
	var span := Vector2i.ONE
	var facts := _sim.tile_at(tile)
	var building: Variant = facts.get("building")
	if building != null:
		var it: Dictionary = building
		origin = it.get("pos", tile)
		span = it.get("footprint", Vector2i.ONE)
	return Rect2i(origin, Vector2i(maxi(1, span.x), maxi(1, span.y)))


## **OPEN THE BUILD SCREEN ON ONE CATALOGUE ROW** (ASSA-328). Maren's §2: a make row's button *"opens
## this screen with that recipe already chosen -- one gesture from the thing you pointed at to the
## screen that builds it"*.
##
## **ONE AT A TIME, AND THE OTHER ONE IS THE MACHINE MENU** (her §1: *"the build screen and a machine
## menu are mutually exclusive -- opening either closes the other"*). Said in both directions, here
## and in `_open_machine_menu`, because a rule stated at one end holds until somebody opens the other.
##
## **IT CHANGES NO SIM STATE AND SENDS NOTHING.** Opening is a client gesture; `Build` is the command.
func _open_build_screen(offer: Dictionary) -> void:
	_close_machine_menu()
	_build_verb = String(offer.get("verb", ""))
	_build_tag = offer.get("tag")
	_build_species = int(offer.get("species", -1))
	_build_grade = String(offer.get("grade", ""))
	# REBUILT EVEN WHEN THE SAME ROW IS PRESSED TWICE, the menu's reason: the pack may have changed
	# while the screen was shut and the signature cannot tell "closed" from "unchanged".
	_build_showing = UNBUILT
	_refresh_build_screen()


## **OPEN IT ON A FRAME YOU ARE CARRYING: THE ASSEMBLY PATH** (ASSA-317 slice 2b; Maren's §2, *"tabs
## stay as launcher and ledger; the screen is where you build"*).
##
## **THE PACK ROW LAUNCHES AND NO LONGER BUILDS, WHICH IS THE PRICE SHE NAMED ON THE MAKE PATH PAID A
## SECOND TIME** (her §2: *"there is no one-click make any more ... a row that both makes and opens a
## maker is the same verb with two homes"*). `Frame` used to append to `_building` from the pack and
## leave the player to find `Assemble` in the bench; it now opens the screen with that frame chosen.
##
## **THE MOUNTED PARTS SURVIVE A NEW FRAME, AND THAT IS A RULING RATHER THAN LAZINESS** (Maren, 00:32:
## *"switching the frame may never silently unmount anything ... the three that no longer fit become
## `extra`, drawn and visible"*). So this writes `_building[0]` and leaves the rest of the array
## alone; `AssayHud.slot_fill` is what turns the parts that no longer fit into `extra`.
##
## **AND THE SIM IS ASKED WHETHER THE PRESS CAN LEAD TO A MACHINE, EVEN THOUGH THE BUTTON IS ONLY ON
## FRAME ROWS** (`part_press_refusal`, ASSA-86 ruling 2). A `Mount` row cannot reach here today, but
## the refusal is the sim's answer and reading `is_frame` instead would be this client deciding
## legality -- the one rule ASSA-317 says does not bend.
func _open_assembly_screen(stack: Dictionary) -> void:
	var refusal := AssaySimHost.part_press_refusal(PackedStringArray(),
			String(stack.get("kind", "")))
	if refusal != "":
		_say(refusal, AssayHud.Say.FAILED)
		return
	_close_machine_menu()
	_build_verb = BUILD_ASSEMBLE
	_build_tag = null
	_build_species = -1
	_build_grade = ""
	_choose_frame(stack)


## **PUT A FRAME UNDER THE DESIGN WITHOUT DISTURBING WHAT IS MOUNTED ON IT** (ASSA-317 slice 2b).
## `_building[0]` is the frame by `sim-cli`'s own convention, which `_choose_part` and `_assemble`
## already keep; this is the one writer of that slot.
func _choose_frame(stack: Dictionary) -> void:
	if _building.is_empty():
		_building.append(stack)
	else:
		_building[0] = stack
	_build_showing = UNBUILT
	_refresh_pack()
	_refresh_assembling()
	_refresh_actions()
	_refresh_build_screen()


## **WHETHER THE SCREEN IS BUILDING A MACHINE RATHER THAN MAKING A THING** (ASSA-317 slice 2b). One
## predicate so the branches this slice adds cannot drift, and it reads the verb the press will send
## rather than the presence of a design: a player who opens the screen and takes every part back off
## again is still assembling, and a screen that fell back to the make path under them would move the
## columns out from under the cursor.
func _assembling_mode() -> bool:
	return _build_verb == BUILD_ASSEMBLE


## The frame of the design being placed, or `{}` before one is chosen.
func _design_frame() -> Dictionary:
	return _building[0] as Dictionary if not _building.is_empty() else {}


## What is mounted on it, in the order the player pressed. `_building.slice(1)` is the one home for
## this (`AssayHud.slot_fill`'s docstring) and this is its one reader on the screen.
func _design_mounted() -> Array:
	return _building.slice(1) if _building.size() > 1 else []


## **CLOSE IT. Esc or the named control** (Maren's §1).
##
## **CLOSING DISCARDS NOTHING AND THAT IS HER RULING, NOT A SHORTCUT** (§1: *"a half-built design is
## client state until Build; it survives a close and re-opens as you left it"*). So the three fields
## that say what is chosen are untouched here and only `_build_verb` is cleared -- which is what
## "shut" means -- and re-opening on the same row finds the material still chosen.
##
## **A CLICK ON THE MAP DOES NOT CLOSE THIS ONE, UNLIKE THE MACHINE MENU.** The menu is ABOUT a tile,
## so clicking another tile is a way of pointing at something else; this screen is about nothing on
## the map, so a click outside it is just a click and closing on it would throw away a half-made
## choice for a gesture the player did not mean as a dismissal.
func _close_build_screen() -> void:
	if _build_verb == "":
		return
	_build_verb = ""
	_build_showing = UNBUILT
	if is_instance_valid(_build_box):
		_build_box.visible = false


## Whether the build screen is up. One reader, so the two surfaces' mutual exclusion and the tests ask
## the same question rather than each spelling `_build_verb != ""`.
func _build_screen_open() -> bool:
	return _build_verb != "" and is_instance_valid(_build_box)


## **IS A POP-UP OPEN THAT CARRIES ITS OWN `Primary`?** (ASSA-374.)
##
## **THE QUESTION IS ASKED OF THE TREE, NOT OF A LIST OF POP-UP NAMES**, and that is the whole point.
## Maren's rule is *never two accents at once*, not *the world dims when anything opens*: the build
## screen has a primary act (`Build`), a machine menu has none by ASSA-316, and standing the world's
## `Primary` down for the menu would leave the screen with no accent at all. Naming the build screen
## here would encode today's answer to a question the next pop-up re-asks; walking for the variation
## means a pop-up that grows a `Primary` later is handled on the day it grows one, and one that loses
## it gives the world its accent back -- neither needing anyone to find this function.
##
## **ONLY VISIBLE POP-UPS COUNT.** Both boxes outlive their open state (`_build_box.visible = false`
## is how the screen closes), so a walk that ignored visibility would keep the column stood down for
## the rest of the session -- a rank that never comes back, which is the half of the ruling that says
## it must.
func _popup_holds_the_accent() -> bool:
	for root in [_build_box, _menu_box]:
		var box := root as Control
		if not is_instance_valid(box) or not box.visible:
			continue
		for child in box.find_children("*", "Button", true, false):
			if (child as Button).theme_type_variation == &"Primary":
				return true
	return false


## **EVERY OFFER THE SIM MAKES FOR THE ROW THIS SCREEN IS OPEN ON** -- same `verb` and same `tag`, one
## per material in the pack that the recipe accepts. That list IS the material picker (ASSA-328).
##
## **MATCHED BY THE SIM'S OWN TWO WORDS, THE WAY `button_play` MATCHES A ROW.** `JSON.stringify` on
## the tag because a part's tag is a Variant and may be a Dictionary (`{"Frame": "Held"}` for a
## handle), which `==` compares by reference rather than by value for some shapes -- the same
## comparison `_press_on_offer` has used since ASSA-86 and for the same reason.
func _offers_for_open_row() -> Array:
	var same: Array = []
	if _build_verb == "" or _client == null or not _sim.running():
		return same
	var wanted := JSON.stringify(_build_tag)
	for entry in _sim.make_offers(_client.player_id):
		var offer: Dictionary = entry
		if String(offer.get("verb", "")) == _build_verb:
			if JSON.stringify(offer.get("tag")) == wanted:
				same.append(offer)
	return same


## The one offer the screen is pointed at: the open row's recipe in the chosen material. `{}` when the
## sim no longer makes that -- the pack ran out, or a `sort` moved the last stack to grade A -- which
## is a state the screen SAYS rather than papering over with the first material it can find.
func _chosen_offer() -> Dictionary:
	for entry in _offers_for_open_row():
		var offer: Dictionary = entry
		if int(offer.get("species", -1)) == _build_species:
			if String(offer.get("grade", "")) == _build_grade:
				return offer
	return {}


## **WHAT THE SCREEN SAYS, AND ON WHICH CLOCK EACH PART SAYS IT** (ASSA-328, the machine menu's split).
##
## **IT CLOSES ITSELF WHEN THERE IS NO WORLD, AND NOT WHEN THE OFFER GOES.** No world means no
## catalogue and no pack, so every row on it would be a claim about nothing (the menu's rule). A
## chosen material running out is different: the screen stays up and the detail column says the sim no
## longer offers it, because that is a thing the player did -- they built the last one -- and a screen
## that vanished on success would hide the answer.
##
## **THE SIGNATURE IS THE PACK'S SHAPE PLUS WHAT IS CHOSEN**, so the rows are rebuilt when the
## catalogue moves or the player picks another material, and NOT every tick: a row carries a Button a
## cursor may be resting on (`_refresh_actions`' note). The cost text is re-written every refresh,
## because a count climbs every mining cycle and a Label's text is idempotent and free.
func _refresh_build_screen() -> void:
	if not _build_screen_open():
		return
	if not _sim.running():
		_close_build_screen()
		return
	_build_box.visible = true
	var stacks := _sim.inventory_of(_client.player_id) if _client != null else []
	# **THE DESIGN IS IN THE KEY, AND ON THE ASSEMBLY PATH IT IS THE TERM THAT MOVES** (ASSA-317 slice
	# 2b). Every click mounts or unmounts a part, which changes which box holds what and which rows
	# the mount list offers -- a drawn thing missing from the key is a stale picture the per-refresh
	# writes cannot repair, because they only re-text the bar (`_make_shape`'s standing rule).
	# `_pack_shape` and not `AssayHud.building_line`: the shape is which items in which order, and the
	# sentence carries counts that climb on their own.
	var signature := "%s/%s/%d/%s/%s/%s" % [_build_verb, JSON.stringify(_build_tag), _build_species,
			_build_grade, _pack_shape(stacks), _pack_shape(_building)]
	if signature != _build_showing:
		_build_showing = signature
		_rebuild_build_screen()
	# **THE BAR AND THE COST ARE THE TWO THINGS WRITTEN EVERY REFRESH** (ASSA-332). Both carry a count
	# the pack changes without changing its SHAPE, which is what `_pack_shape` deliberately leaves out,
	# and the bar's sentence ends in `you have 8`.
	_refresh_build_said()
	_refresh_build_cost()
	_place_build_screen()
	# **AND AGAIN ONCE THE LAYOUT HAS SETTLED, WHICH IS THE WHOLE OF ASSA-377** (P0: with the world
	# ticking, `Build` left the bottom of the window on the empty-pack assembly screen and could not
	# be pressed at all). The call above runs in the SAME frame as `_rebuild_build_screen`, when the
	# sentence's `Label`s have just been re-added and have no width yet. An autowrapped `Label`
	# reports its height for the width it currently has, so at width 0 it answers the
	# one-letter-per-row height -- `BuildScreenSaid`'s minimum width is **1** -- and the commit bar's
	# minimum momentarily reads 570 on the assembly path (1365 on the make path) against its own 114.
	# `set_size` CLAMPS UP to the minimum, so the `PanelContainer` is written 804 instead of the 588
	# `build_screen_rect` asked for, which that function cannot even return (its ceiling here is 624).
	# One frame later the minimum has relaxed to 348 and **nothing re-places the box**, so the screen
	# keeps the oversized rect and the bar sits at y732 in a 720 px window.
	#
	# **MEASURED, NOT REASONED, AND THE PNG IS THE AUTHORITY.** With one tick per frame -- what a relay
	# actually delivers -- `shared/assay/limpet-assa377-empty-pack/` holds the shot with no `Build` on
	# it; a single `_place_build_screen()` on a frame carrying no refresh put the box back to 588 and
	# `Build` back to y516 (`replace2.log`). Deferring is that frame, taken for free.
	_place_build_screen.call_deferred()


## **WHERE THE SCREEN GOES, FROM A MEASUREMENT AND NOT FROM A CONSTANT** (ASSA-328).
##
## **THE BAND IT MAY NOT COVER IS ASKED FOR, NOT ASSUMED.** Maren's §1 forbids covering the status
## toast and `whole world (V)`, which live INSIDE the world rect and are not the world -- the thing
## her mock caught before any code did. Both are real nodes with real rects once a window has laid
## out, so this takes the TOP of the highest one that is actually on screen and
## `AssayHud.build_screen_rect` keeps its clearance from that.
##
## **AND `WORLD_CONTROLS_BAND` IS ONLY THE HEADLESS ANSWER.** Nothing has a size in the test suite, so
## a node's rect there is `(0,0,0,0)` and taking its top would put the band at the top of the window
## and leave the screen no room at all. A zero-sized node is "not laid out", not "at the origin", so
## it is skipped and the constant answers instead -- which is why that constant's docstring says the
## check that matters is a real-window one.
func _place_build_screen() -> void:
	if not is_instance_valid(_build_box):
		return
	var world := AssayHud.world_rect()
	var rect := AssayHud.build_screen_rect(world, _world_band_top())
	_build_region.position = world.position
	_build_region.size = world.size
	_build_box.position = rect.position - world.position
	_build_box.size = rect.size


## **THE THREE LISTS, REBUILT TOGETHER** (ASSA-328). They move on one clock -- the catalogue's shape
## and what is chosen -- so they are one function and one signature.
##
## **AND THE MODE IS DECIDED HERE, ONCE, FOR EVERY BLOCK** (ASSA-317 slice 2b). Maren's 00:32 ruling
## puts the SUBJECT in block 2 and its PARAMETERS in block 3 on both paths -- recipes then materials
## when making, frames then slots-and-mounts when assembling -- so the two modes are the same two
## rects doing the same two jobs and a player learns the screen once.
##
## **THE HEADINGS MOVE WITH THE ROWS**, because a heading is this file's word for what is under it and
## `what to make` over a list of frames is the labelled-wrong-thing defect rather than a stale string.
func _rebuild_build_screen() -> void:
	var assembling := _assembling_mode()
	_build_title.text = "assemble" if assembling else "make"
	var heading := _section_heading(_build_picker)
	if heading != null:
		heading.text = "which frame" if assembling else "what to make"
	_show_section(_build_materials, not assembling)
	_show_section(_build_slots, assembling)
	_show_section(_build_mounts, assembling)
	if assembling:
		_rebuild_build_frames()
		_rebuild_build_slots()
		_rebuild_build_mounts()
	else:
		_rebuild_build_picker()
		_rebuild_build_materials()
	_rebuild_build_detail()


## **BLOCK 2: WHAT YOU CAN MAKE, ONE ROW PER CATALOGUE ENTRY, NAMED BY THE SIM** (ASSA-328).
##
## **THE ROWS ARE THE SIM'S LIST AND THE ORDER IS THE SIM'S TOO.** `make_offers` is ordered
## `RecipeId::ALL`, then `PartKind::ALL`, then the pack's own order (its docstring), and this walks it
## in that order keeping the first of each `verb`+`tag` -- so a recipe appears where the sim puts it
## and nothing here sorts a catalogue.
##
## **THE LABEL IS THE SIM'S NAME OUT OF THE CATALOGUE, NOT THE TAG.** A tag is serde's spelling --
## a bare `"Head"`, or `{"Frame": "Held"}` for a handle -- and `recipes()` / `part_kinds()` each cross
## a sim-written `name` beside it for exactly this. Printing a tag would put an enum variant on a
## player's screen and would read `{ "Frame": "Held" }` on the one row that is a Dictionary.
##
## **ONE ROW PER RECIPE AND NOT PER MATERIAL, WHICH IS THE WHOLE POINT OF THE SCREEN.** The make tab
## lists an offer per (recipe x material you hold), which is how five materials became twenty-odd rows
## of prose. Here the recipe is chosen once and the material is the other column.
func _rebuild_build_picker() -> void:
	_clear(_build_picker)
	var seen := {}
	var group := ButtonGroup.new()
	var chosen := JSON.stringify(_build_tag)
	for entry in (_sim.make_offers(_client.player_id) if _client != null else []):
		var offer: Dictionary = entry
		var verb := String(offer.get("verb", ""))
		var key := "%s/%s" % [verb, JSON.stringify(offer.get("tag"))]
		if seen.has(key):
			continue
		seen[key] = true
		var named := _catalogue_name(verb, offer.get("tag"))
		_build_picker.add_child(_pick_row(named, func() -> void: _choose_build_row(offer),
				key == "%s/%s" % [_build_verb, chosen], group, "make %s instead" % named))


## **ONE ROW OF A PICKER: ONE OBJECT IN TWO STATES, NEVER TWO OBJECTS** (ASSA-343; Maren's ASSA-328
## ruling 3: *"A selected and an unselected member of one list must be one object in two states, never
## two objects — otherwise the state reads as a difference in kind"*).
##
## **IT IS A TOGGLE BUTTON IN A `ButtonGroup`, WHICH IS THE ENGINE'S OWN RADIO GROUP.** The chosen row
## is the same `Button` as every other row with `button_pressed` true, so the theme's own `Quiet`
## `pressed` stylebox and `font_pressed_color` draw the state -- no second control type, no colour
## invented here, and "exactly one is chosen" is structural rather than something each rebuild has to
## remember. `smelter` and `sort` read as two states of one list because they are.
##
## **WHAT THIS REVERSES OF MINE, AND THE TENSION IS REAL RATHER THAN A SLIP.** The chosen row was a
## `Label` on ASSA-175's rule -- a control that cannot do anything reads as available -- and pressing
## the open row does nothing but re-point the screen at where it already is. Her 20:22 clause is the
## tie-break: *"a control that cannot be pressed should not look pressable"*. A pressed toggle in a
## group **is** a control that cannot be un-pressed, and it does not look like an idle one; that is the
## difference from the dead button ASSA-175 was about, which looked exactly like its live neighbours.
##
## **THE PRESS IS STILL CONNECTED ON THE CHOSEN ROW**, deliberately: `ButtonGroup` keeps it pressed, so
## the callback re-points the screen at itself and the rebuild is idempotent. The alternative -- a
## disconnected button -- is the dead control again.
func _pick_row(label: String, on_press: Callable, chosen: bool, group: ButtonGroup,
		hint: String) -> Button:
	var row := _button(label, on_press, hint)
	row.theme_type_variation = &"Quiet"
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.toggle_mode = true
	row.button_group = group
	row.button_pressed = chosen
	return row


## **A MATERIAL ROW'S LABEL: THE MATERIAL, IN THE SIM'S WORDS, WITHOUT ITS COUNT** (ASSA-343).
##
## `mine` is the pack stack this offer eats, so `name` is the sim-written wording (`inventory_of`) and
## nothing here words an item. **The empty case is the one Maren declined to call a defect and handed
## to me:** `_pack_stack_of` returns `{}` only when the pack does not hold what the offer eats, and
## every `MakeOffer` comes from a stack you hold (`make_offers` walks `p.inventory.stacks()`), so it is
## unreachable. It falls back to the sim's whole sentence -- a second grammar, which is why it may not
## pass silently: a `push_error` makes the unreachable state say so in the log the day it is reached,
## rather than the row quietly reading differently depending on your pack.
func _material_label(offer: Dictionary, mine: Dictionary) -> String:
	if mine.is_empty():
		push_error("a make offer names no pack stack: %s" % [offer.get("line", offer)])
		return String(offer.get("line", ""))
	return String(mine.get("name", ""))


## **MOVE THE SCREEN TO ANOTHER CATALOGUE ROW WITHOUT CLOSING IT** (ASSA-328). The material goes with
## it -- this offer's own species and grade -- because the material a `sort` can eat is not the
## material a `head` can, and carrying the old choice across would point the screen at an offer the
## sim does not make and then have to say so.
func _choose_build_row(offer: Dictionary) -> void:
	_build_verb = String(offer.get("verb", ""))
	_build_tag = offer.get("tag")
	_build_species = int(offer.get("species", -1))
	_build_grade = String(offer.get("grade", ""))
	_build_showing = UNBUILT
	_refresh_build_screen()


## **BLOCKS 3+4: THE MATERIAL PICKER -- ONI's, WHICH IS MAREN'S CLOSEST REFERENCE** (§3: *"you pick the
## material and the card's numbers move ... ONI proves a player will happily shop by consequence"*).
##
## **ONE ROW PER MATERIAL THE SIM OFFERS THIS RECIPE, AND THE WORDS ARE THE SIM'S.** The label is the
## `name` the sim wrote on that pack stack -- `Tonore refined (A)` -- because `make_offers` crosses an
## offer's input as three fields and no name, and spelling that out of kind, species and grade here
## would be this client wording an item (ASSA-43/52, and `make_offers`' own docstring forbids it).
##
## **IT IS THE MATERIAL AND NOT THE STACK, WHICH IS MAREN'S ASSA-343 RULING AND MY OWN DOCSTRING'S
## CONTRACT.** This printed `AssayHud.stack_line(mine)` = `8 × Tonore refined (A)`, one row above a
## `need · have` that is about that very count. `have_need_line`'s rule was *"it names no item and so
## it is not a second copy of a sim sentence … the thing they are about is named once, by the sim,
## elsewhere on the screen"* -- written for a name row that does not count, and handed one that does.
## `stack_line` is untouched in the pack list, so ASSA-90 holds: the pack's wording stays the pack's.
##
## **THE COUNTS THEMSELVES STAY, AND THAT IS THE HALF SHE REVERSED HERSELF ON** (§5.5, 20:51): *"the
## material row is the picker; its counts are what make the choice"*. Strip them and comparing two
## materials means selecting each and reading block 6 -- affordability computed across two gestures,
## the exact thing §3 took from Factorio in order to refuse.
##
## **HAVE / NEED UNDER EACH ONE, WHICH IS WHAT MAKES THIS A CHOICE AND NOT A LIST** (her §3, Factorio):
## affordability is read rather than computed in the player's head, on every material at once.
func _rebuild_build_materials() -> void:
	_clear(_build_materials)
	var offers := _offers_for_open_row()
	if offers.is_empty():
		_build_materials.add_child(_note("nothing you are carrying can be worked into this"))
		return
	var group := ButtonGroup.new()
	for entry in offers:
		var offer: Dictionary = entry
		var mine := _pack_stack_of(offer)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var chosen := int(offer.get("species", -1)) == _build_species \
				and String(offer.get("grade", "")) == _build_grade
		var press := _pick_row(_material_label(offer, mine),
				func() -> void: _choose_build_material(offer), chosen, group,
				"make it out of this instead")
		row.add_child(press)
		# **THE SAME TWO COUNTS AS BLOCK 6, IN THE SAME WORDS AND THE SAME ORDER** (ASSA-332): one
		# grammar for one kind of number, wherever it is drawn. **The FAILED ink goes on the counts and
		# not on the row's button**: a material you cannot afford is still a material you may CHOOSE,
		# because the screen's job is showing you what it would cost, and a control painted in the
		# status scale reads as refused (ASSA-175). Block 6's entry is the one that goes `FAILED` whole,
		# because there the whole entry is a statement rather than a choice.
		var counts := _note(AssayHud.cost_counts_line(int(offer.get("cost", 0)),
				int(offer.get("count", 0))))
		if AssayHud.cost_entry_short(int(offer.get("cost", 0)), int(offer.get("count", 0))):
			counts.add_theme_color_override(&"font_color",
					AssayHud.status_color(AssayHud.Say.FAILED))
		row.add_child(counts)
		_build_materials.add_child(row)


## **BLOCK 2 ON THE ASSEMBLY PATH: THE FRAMES YOU ARE CARRYING, WHICH ARE THE SUBJECT** (ASSA-317
## slice 2b; Maren's 00:32 ruling: *"An assembly's subject is the FRAME, and its parameters are the
## parts that go into its slots. Same two rects, same two jobs, so a player learns this screen once
## instead of twice."*)
##
## **ONE ROW PER FRAME STACK, AND `is_frame` IS THE SIM'S FIELD** (ASSA-102) -- so a fifth frame kind
## appears here with no change to this client, and nothing in GDScript decides what a frame is.
##
## **THE LABEL IS `stack_line`, COUNT AND ALL, WHICH BLOCK 2 ON THE MAKE PATH DELIBERATELY IS NOT.**
## A recipe row names a catalogue entry, of which there is one; a frame row names a STACK, and how
## many you have is part of choosing which to build on (ASSA-90: the pack's wording stays the pack's).
##
## **AND THE ROWS ARE A RADIO GROUP FOR `_pick_row`'S REASON** (ASSA-343): the chosen frame is the
## same object in a pressed state, never a second kind of control.
func _rebuild_build_frames() -> void:
	_clear(_build_picker)
	var kinds := AssaySimHost.part_kinds()
	var group := ButtonGroup.new()
	var chosen := _pack_shape([_design_frame()])
	var frames := 0
	for entry in (_sim.inventory_of(_client.player_id) if _client != null else []):
		var stack: Dictionary = entry
		var part := AssayHud.part_kind_of(stack, kinds)
		if part.is_empty() or not bool(part.get("is_frame", false)):
			continue
		frames += 1
		_build_picker.add_child(_pick_row(AssayHud.stack_line(stack),
				func() -> void: _choose_frame(stack), _pack_shape([stack]) == chosen, group,
				"build on this frame instead"))
	if frames == 0:
		# **IT SAYS SO RATHER THAN DRAWING AN EMPTY LIST** -- the make path's own rule on this screen
		# (`_rebuild_build_materials`): absence is never a cue, and the player who opened a build
		# screen with no frame in the pack is exactly the one wondering what is missing.
		_build_picker.add_child(_note("you are not carrying a frame to build on"))


## **BLOCK 3, UPPER: THE FRAME'S SLOTS AS A DRAWN SHAPE** (ASSA-317 slice 2b; `assay-build-screen`
## §3's take from Satisfactory: *"slots drawn as a shape, not listed as rows … a list hides a limit
## that a drawn shape states"*).
##
## **THE SHAPE IS `AssayHud.slot_fill`'S ANSWER AND THE JOIN IS THE SIM'S** (ASSA-346): one box per
## unit of room, in the catalogue's order, each carrying the part standing in it or `{}`.
##
## **ONE LABELLED ROW PER SLOT KIND, BROKEN WHERE THE NAME CHANGES AND NOT WHERE I FANCY A BREAK.**
## `slot_boxes` emits a kind's boxes contiguously because it walks the sim's `slots` in order, so
## grouping on a change of name re-reads the catalogue's own grouping rather than sorting it. Five
## boxes with five copies of the word `hopper` under them is the list that a shape was supposed to
## replace; `hopper [][][][]` is the shape.
##
## **`extra` IS DRAWN, NEVER DROPPED** (Maren, 00:32: *"switching the frame may never silently unmount
## anything … the alternative is a player losing an arrangement with no sentence anywhere"*). Five
## hoppers on a four-hopper frame, or a four-hopper arrangement carried onto a one-hopper frame, leave
## parts with nowhere to stand. **The word on that row is MINE and is the one thing here I want
## ruled**: it is a client state, so no sim sentence exists for it until `Build` is pressed.
func _rebuild_build_slots() -> void:
	_clear(_build_slots)
	var frame := _design_frame()
	if frame.is_empty():
		_build_slots.add_child(_note("choose a frame and its slots are drawn here"))
		return
	var part := AssayHud.part_kind_of(frame, AssaySimHost.part_kinds())
	var filled := AssayHud.slot_fill(part.get("slots", []) as Array, _design_mounted())
	var row: HBoxContainer = null
	var named := ""
	for entry in (filled.get("boxes", []) as Array):
		var box: Dictionary = entry
		if row == null or String(box.get("name", "")) != named:
			named = String(box.get("name", ""))
			row = _slot_row(named)
		row.add_child(_slot_box(box))
	var extra := filled.get("extra", []) as Array
	if not extra.is_empty():
		var over := _slot_row("nowhere to stand")
		for entry in extra:
			over.add_child(_slot_box({"part": entry}))


## ONE ROW OF THE SHAPE: what the boxes are, then the boxes. The label is the SIM's name for the slot
## kind, which is the same string `slot_fill` joined on.
##
## **THE KIND DOES NOT WRAP, AND THE DEFAULT WAS NOT "A BIT NARROW" -- IT WAS ONE LETTER PER ROW**
## (ASSA-362). `_note` sets `AUTOWRAP_WORD_SMART`, which is right for every sentence on this screen
## and wrong for a one-word label in an `HBoxContainer` that gives its width to the boxes: squeezed
## under one character, WORD_SMART breaks anywhere, so the first 1x shot of this screen drew
## `h`/`e`/`a`/`d` stacked vertically beside the head box and `h`/`o`/`p`/`p`/`e`/`r` beside the
## hoppers. **A six-letter word then costs ~126 px of column height instead of 18.**
##
## **AND IT WAS NOT A COSMETIC BUG, WHICH IS WHY THE FIX IS HERE AND NOT IN A STYLESHEET.** This
## block is the one section built `fill := false`, so its `ScrollContainer` cannot scroll and cannot
## shrink and its content's height is a hard floor under the WHOLE screen. Six letters tall twice
## over took the screen 137 px past the rect `build_screen_rect` computed, over the two world
## controls Maren's §1 protects, and put `Build` off the bottom of a 720 px window.
##
## **NOT FIXED IN `_note`:** a note is a sentence and sentences must wrap. This is a label that
## happens to be built by the same helper.
func _slot_row(named: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var kind := _note(named)
	kind.autowrap_mode = TextServer.AUTOWRAP_OFF
	kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(kind)
	_build_slots.add_child(row)
	return row


## **ONE BOX OF THE SHAPE: ROOM FOR A PART, OR THE PART STANDING IN IT** (ASSA-317 slice 2b).
##
## **AN EMPTY BOX IS DRAWN, AND THAT IS NOT ASSA-237 REVERSED.** Maren's ruling there -- *"a
## reserved-but-empty icon box draws NOTHING … a box around nothing is a claim; space is
## structure"* -- is about the icon column of a LIST, where the box would claim there is a picture.
## Here the claim is the point: an empty box says *a part fits here*, which is the whole reason §3
## draws slots as a shape instead of printing `hopper 0-4`. The engine's own `Panel` draws it, so the
## edge is the theme's `BORDER` and this file invents no ink.
##
## **ICON_PX SQUARE, WHICH KEEPS THE PART SHEET'S EXACT 1/4** (ASSA-65, and ASSA-343's reasoning on
## this screen's one picture): `STRETCH_KEEP_ASPECT_CENTERED` scales by `min(32/128, 32/102)` = 1/4
## for a 128x102 part cell, so the width is what binds and nothing is resampled. A box of
## `ICON_BOX_PX`'s 48 height would be the pack ROW's number, which this is not.
##
## **NO PLATE UNDER THE SPRITE** (ASSA-341, Maren's ruling off my own 1x shot): a part on the panel's
## `SURFACE` measures 5.57:1 and on the pack's plate 1.24:1, and ASSA-71's one-surface reason is about
## a LIST of ore rather than one picture in a box.
##
## **TAKING A PART BACK OFF IS NOT HERE AND IS NOT FORGOTTEN.** `Clear` in the column is the way back
## today; a box you can press needs an affordance that says so before you press it, and every device
## I have for that is a new colour or a new stylebox -- Maren's call, filed rather than invented at
## the end of a night.
func _slot_box(box: Dictionary) -> Control:
	var plate := Panel.new()
	plate.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var part := box.get("part", {}) as Dictionary
	if part.is_empty():
		plate.tooltip_text = "room for a %s" % String(box.get("name", "part"))
		return plate
	plate.tooltip_text = String(part.get("name", ""))
	var art := _icon_box(part, false, false)
	if art != null:
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.add_child(art)
	return plate


## **BLOCK 3, LOWER: THE PARTS YOU CAN MOUNT, AS A LIST** (ASSA-317 slice 2b; Maren's 00:32
## sharpening: *"Slots are drawn boxes; mountable parts are a list. Two shapes, two jobs, each
## legible before you press."*)
##
## **FRAMES ARE NOT IN THIS LIST, AND THAT IS HER LAYOUT RULING RATHER THAN THIS CLIENT FILTERING A
## SIM ANSWER.** A frame is block 2's subject; a row here that changed the subject instead of
## mounting something is (B), *"two consequences behind identical-looking rows, invisible until you
## press"*. `is_frame` is the sim's own field, so the split is read and not derived.
##
## **THE PRESS IS `_choose_part`, WHICH ASKS THE SIM FIRST** (ASSA-86 ruling 2): a press that could
## never lead to a machine is refused in the sim's own sentence, at the press, rather than confirmed
## here and refused at `Assemble` -- which clears the whole design and loses the good presses too.
##
## **AND THE SAME QUESTION IS NOW ASKED BEFORE THE ROW IS DRAWN, NOT ONLY AT THE PRESS** (ASSA-371,
## Maren reading the `slots-full` frame cold). On a full frame every row in this list was a live
## control whose only outcome was a refusal: press `2 x Tonore head (A)` with the head box filled and
## `fault_adding` answers `TooMany`, the toast says so, and nothing is appended. Nothing lied -- but
## **learning it cost a press**, which ASSA-316 ruling 2 forbids: *the reason is always reachable and
## reaching it must never cost a press.* This is ASSA-351's defect one screen over, and the remedy is
## ASSA-351's: the sim's own refusal chain as a predicate, asked before the control is drawn.
##
## **THE ROW STAYS, WHICH IS THE HALF THAT IS A RULING RATHER THAN AN IMPLEMENTATION.** A pack stack
## vanishing from this list because the design happens to be full is a list that changes membership
## for a reason the player cannot see -- and it would come back on the next unmount, which reads as
## the game forgetting what you are carrying. So a refused kind is drawn present, not pressable, and
## **carries `part_press_refusal`'s sentence verbatim** under it. Both the contingent refusal
## (`TooMany`, cured by taking a hopper off) and the frame-permanent one (`NoSuchSlot`) SHOW, per
## ASSA-351 box 4: the lever for both is on this screen, one click away in block 2.
##
## **THE SENTENCE IS NEVER COMPOSED HERE AND THE LABEL IS NEVER TOUCHED.** The refusal goes in its own
## `_note`, not appended to the button's text, because `stack_line` IS that button's text and three
## instruments look rows up by it (`tools/limpet_build_screen_shot.gd::_mount_one` among them). A
## reason glued onto a label would have broken the lookup and read as a missing row.
func _rebuild_build_mounts() -> void:
	_clear(_build_mounts)
	var kinds := AssaySimHost.part_kinds()
	# **THE SAME `chosen` `_choose_part` BUILDS AT THE PRESS**, frame included, so the control and its
	# press are asking the sim one question and cannot disagree about the answer.
	var chosen := PackedStringArray()
	for entry in _building:
		chosen.append(String((entry as Dictionary).get("kind", "")))
	var offered := 0
	for entry in (_sim.inventory_of(_client.player_id) if _client != null else []):
		var stack: Dictionary = entry
		var part := AssayHud.part_kind_of(stack, kinds)
		if part.is_empty() or bool(part.get("is_frame", false)):
			continue
		offered += 1
		var refusal := AssaySimHost.part_press_refusal(chosen, String(stack.get("kind", "")))
		var row := _button(AssayHud.stack_line(stack),
				func() -> void: _choose_part(stack),
				"mount one on the frame you are building on" if refusal == "" else refusal)
		if refusal == "":
			_build_mounts.add_child(row)
			continue
		# **THE PRESS STAYS CONNECTED UNDER THE DISABLED FLAG.** ASSA-37's rule was that the sim does
		# the refusing, and that is still true one layer down: if anything ever reaches this control
		# anyway -- a synthetic `pressed.emit()`, a future keyboard path -- `_choose_part` asks the
		# same question again and still refuses. Disabling is what saves the press, not what decides.
		row.disabled = true
		var held := VBoxContainer.new()
		held.add_child(row)
		held.add_child(_note(refusal))
		_build_mounts.add_child(held)
	if offered == 0:
		_build_mounts.add_child(_note("you are not carrying anything that mounts on a frame"))


## Point the open row at another material. The recipe does not move, which is the difference from
## `_choose_build_row`.
func _choose_build_material(offer: Dictionary) -> void:
	_build_species = int(offer.get("species", -1))
	_build_grade = String(offer.get("grade", ""))
	_build_showing = UNBUILT
	_refresh_build_screen()


## **BLOCK 5: WHAT YOU GET** (ASSA-328, narrowed by ASSA-332 when the sentence moved to the bar).
##
## **EVERY SENTENCE HERE IS THE SIM'S, APPENDED AND NEVER COMPOSED**, which is the make row's rule
## (ASSA-125/158) carried onto a bigger surface: `walls` is the smelter's figure as a SENTENCE because
## what a player may know of a heat tolerance is a band until they assay.
##
## **WHAT LEFT, AND WHY IT IS NOT A LOSS:** `line` and `dead_end` are drawn by `_refresh_build_said`
## in the commit bar (Maren's §5.4 ruling 3), because both are about the irreversible act rather than
## about the thing produced. One fact, one home (ASSA-316 ruling 6) -- they are not drawn twice.
##
## **AND WHAT IS NOT ON THE MAKE PATH IS SAID OUT LOUD RATHER THAN QUIETLY MISSING:** the RATIO fill
## of mass against budget and the SAFE / UNCERTAIN / WILL BREAK verdict her §5 specifies are about a
## DESIGN. A recipe is not one: it has no frame, no budget and no parts, so there is nothing for
## those marks to be about here. Drawing them on this path would mean inventing numbers in GDScript,
## which is the one rule this item says does not bend.
##
## **THE FILL IS BUILT, ON THE OTHER PATH** (ASSA-369). This paragraph used to end *"which is slice
## 2/3"* -- true until the slice landed, and a sentence that goes on calling a built thing pending is
## how the next reader re-derives a gap that is closed. `_design_mass_row` is where it lives; the
## verdict still belongs to the bar, because it is about the irreversible act.
func _rebuild_build_detail() -> void:
	_clear(_build_detail)
	# **BLOCK 5 IS DRAWN ON BOTH PATHS SINCE ASSA-369, AND IT USED TO BE HIDDEN ON THIS ONE.** The
	# old reason -- *"that picture is the next slice; drawing anything else under `what you get`
	# would be me specifying a rect she has already specified"* -- was right on the day and is
	# spent: Maren's 00:32 ruling makes this rect *"the relationship, not the figures"*, and the
	# first half of that relationship needs nothing new across the binding. `design_readout` has
	# carried `mass_low/high` and `budget_low/high` all along.
	#
	# **WHAT IS STILL HIDDEN, AND IT IS THE SAME RULE RATHER THAN A LEFTOVER:** with no frame chosen
	# the sim answers `{}` -- a design with neither numbers nor a fault is a thing it never answers
	# -- and a `what you get` heading over that is `_show_log`'s labelled empty gap. So the section
	# follows the FACT, not the path.
	if _assembling_mode():
		var design := _design_readout()
		_show_section(_build_detail, not design.is_empty())
		if not design.is_empty():
			_build_detail.add_child(_design_mass_row(design))
		return
	_show_section(_build_detail, true)
	var offer := _chosen_offer()
	if offer.is_empty():
		# **THE SCREEN SAYS THE SIM HAS STOPPED OFFERING THIS, WHICH IS THE STATE AFTER A SUCCESSFUL
		# BUILD OF YOUR LAST STACK.** It is not an error and it is not empty: the player did a thing and
		# this is its consequence, so the one surface that was watching says so.
		_build_detail.add_child(_note("the sim no longer offers this in that material"))
		return
	var makes: Dictionary = offer.get("makes", {}) as Dictionary
	# **NO PLATE: THE ONE PICTURE ON THIS SCREEN READS AT 1.24:1 ON IT** (ASSA-341; Maren's ruling off
	# my own 1x shot, and the plate was her ASSA-71 ruling, so she overturned herself here).
	#
	# ASSA-71's reason is that a LIST of ore closes its species spread by sitting on one surface. This
	# is one picture of a smelter with nothing beside it to compare, so the reason does not travel and
	# the 1.24:1 is paid for nothing: the plate samples (130,149,99) at 91% uniform and the sprite is
	# (238,119,181). On the panel's own `SURFACE` the same sprite measures **5.57:1**.
	#
	# **ASSA-71 IS UNTOUCHED FOR THE PACK**, which is the half of her ruling that still holds and the
	# reason `plated` defaults to `true`: every pack row keeps its plate and its one-colour-per-species
	# reason, because that is the surface the 3:1 bar was measured on and passes.
	# **BUILT BEFORE THE PICTURE AND ADDED AFTER IT, BECAUSE THE PICTURE IS SIZED FROM THE ROOM THIS
	# LEAVES** (ASSA-357 box 5). The tree's order is unchanged -- picture, then clause -- but the
	# clause's own minimum has to exist before the scale can be derived, and a Label's minimum does not
	# depend on being in a tree. Measuring it rather than allowing a row for it is the difference
	# between furniture that is read and furniture that is remembered.
	var walls := String(offer.get("walls", ""))
	var said: Label = null
	if walls != "":
		# **NO EM-DASH: `— walls 44` READ AS A FRAGMENT OF A SENTENCE THAT ENDED TWO LINES EARLIER**
		# (ASSA-343; Maren's ASSA-328 ruling 5). The dash was mine, not the sim's, and it was a
		# continuation mark from when this block sat under the sim's own sentence -- which moved to
		# the commit bar in ASSA-332. The figure itself stays here: it is her ASSA-332 box 10 ruling,
		# *"the one number on slice 1 that MOVES when you change your pick"*.
		said = _note(walls)
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var picture := _icon_box(makes, true, false)
	if picture != null:
		# **A PLATE IS SIZED BY WHAT STANDS ON IT, NOT BY THE COLUMN IT SITS IN** (ASSA-343; Maren's
		# ASSA-328 ruling 2, confirmed off the shot: *"a pale olive band the full width of the column
		# with a 32 px icon lost in the middle: it reads as a progress bar, not a picture"*).
		#
		# **THE CAUSE WAS A DEFAULT, NOT A WIDTH I CHOSE.** `_icon_box` hands back a `Panel` carrying
		# `ICON_BOX_PX`; in a pack ROW an HBox gives it that minimum and it stays 32 px wide, but a
		# `VBoxContainer` child FILLS horizontally by default, so the same plate stretched to the
		# column's 304 px while staying 48 px tall. `SHRINK_BEGIN` is the whole fix, and it also
		# left-aligns it, which is the rest of her sentence.
		#
		# **AND IT IS THE AUTHORED FRAME AT A WHOLE-NUMBER SCALE OF THE ROOM IT IS GIVEN, WHICH
		# REPLACES THE `ICON_PX` SQUARE THIS LINE HELD** (ASSA-357 box 5; Maren's box 4 ruling, 3x
		# today and derived rather than typed). `ICON_PX` is untouched and the pack is untouched:
		# `check_pack_icon_scale.py` reads the pack's rows, and nothing here reaches them.
		#
		# **THE `ICON_PX` SQUARE WAS NOT WRONG, IT WAS THE PACK'S NUMBER STANDING IN FOR THIS SCREEN'S.**
		# ASSA-343 set it to stop a full-width plate reading as a progress bar, and square-at-32 was
		# the smallest thing that did that. It is the only picture on a 235 px column whose job is to
		# show the player the object they are about to spend parts on, and at 32 px it is the same
		# size as a row icon in a list of twelve.
		#
		# **AND ONE SENTENCE THAT WENT WITH IT WAS FALSE, WHICH I AM NAMING RATHER THAN DELETING** (my
		# own, ASSA-343). It said the square keeps *"the `KEEP_ASPECT_CENTERED` scale ASSA-65 made
		# exact (1/2 for an item, 1/4 for a part)"* because the WIDTH was unchanged. The width is not
		# what that mode reads: it fits by the SMALLER ratio, so a 64x96 frame in a 32x32 box drew at
		# `min(32/64, 32/96)` = **1/3**, and ASSA-65's exact 1/2 had been gone since ASSA-343 shipped.
		#
		# **MEASURED OFF THE PAINT IN A 1x WINDOW, NOT ARGUED FROM THE DOCS** -- Limpet's make-path
		# shot `shared/assay/limpet-assa363-centres/build-screen-14247.png`, binned by hue because
		# every frame is tinted: the smelter's ink is **17 x 22 px, x 675..691 y 146..167**, which is
		# its own 54x69 opaque box at 1/3 (18x23, one px of edge alpha). Not 32x48 and not 32x32: a
		# 17 px object on a 235 px column. Nothing headless could have said so -- a drawn size needs a
		# laid-out window -- which is why this is a shot and not a test.
		#
		# **THE WHOLE CLASS OF MISTAKE GOES AWAY FROM HERE**: the box is the frame times a whole
		# number, so both ratios ARE that number and there is no smaller one to lose to.
		var art := picture as TextureRect
		if art != null and art.texture != null:
			# **THE FRAME OFF THE `AtlasTexture`'S OWN REGION, NOT A 64x96 TYPED HERE.** `icon_for`
			# slices the sheet by `manifest.json`'s `frame_px`, so the region IS the authored frame and
			# the day the sheets are re-authored at another size this follows without an edit.
			var frame := art.texture.get_size()
			picture.custom_minimum_size = frame * float(AssayHud.picture_scale(frame,
					_build_picture_room(said)))
		else:
			# **A RESERVED-BUT-EMPTY BOX HAS NO FRAME TO SCALE**, so it keeps the reserved square:
			# `_icon_box`'s `reserve` arm returns a bare `Control` drawing nothing (ASSA-237, Maren's
			# *"space is structure"*), and scaling nothing by 3 is 3x of a gap.
			picture.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		picture.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_build_detail.add_child(picture)
	if said != null:
		_build_detail.add_child(said)


## **THE ROOM BLOCK 5's OUTPUT PICTURE HAS, DERIVED FROM THE SCREEN'S RECT AND NEVER FROM THE COLUMN
## THE PICTURE STANDS IN** (ASSA-357 box 5; Maren's box 4 ruling and her 04:17 reason for it).
##
## **EVERY TERM AND WHERE IT COMES FROM.** Width: the screen's rect less the panel's own content
## margin, shared out by `BUILD_COLUMNS` and `BUILD_GUTTER` exactly as the `HBoxContainer` does it,
## taking the LAST column because `right` is the last one added. Height: the same rect less the pad,
## less the crown, less two gutters, less `BUILD_COMMIT_BAR` -- which is the columns region -- and
## then less block 5's own furniture, the heading plus the `walls` clause plus the two separations
## between the three.
##
## **NOT ONE TERM IS READ OFF THE LAID-OUT COLUMN, AND THAT IS THE WHOLE DESIGN.** Block 5 is built
## `fill := false`, so it is `SHRINK_BEGIN` with scrolling disabled and its content's height is a hard
## FLOOR under the section, the column and the screen (ASSA-362's mechanism, a P0 the night this was
## ruled). Size the picture from the laid-out column and the chain closes on itself -- picture 288 ->
## column >= 288 -> room >= 288 -> scale >= 3 -- a ratchet that can only grow, which is the opposite
## of what the derived scale is for. Every quantity here is either the window's or a sibling's.
##
## **THE CROWN, THE HEADING AND THE CLAUSE ARE READ LIVE BECAUSE THEY ARE FONT METRICS.** A `Display`
## label beside a `Quiet` button, a `Heading` label, and one `BODY` row are the engine's answers, not
## numbers this project owns, and none of the three can be moved by the picture. The two separations
## are asked of the containers that were given them, so this cannot disagree with the layout.
##
## **WHAT IT ANSWERS AGAINST THE 1x WINDOW THAT FITS** (`shared/assay/limpet-assa317-assembly/`):
## `864x588` -> inside `844x576` -> columns `402` -> room **234 x ~341**, and `floor(min(234/64,
## 341/96))` = 3. **The ceiling is the width**: 4x needs 256 against a 235 px column.
##
## **`walls` IS MEASURED UNWRAPPED AND THAT IS THIS FUNCTION'S ONE KNOWN SOFT EDGE.** A Label that has
## never been laid out reports a one-row minimum, so a clause that wraps to three rows in the window
## leaves 36 px less than this allows for. Maren priced that case before ruling: 3x sits 57 px under
## the column at one row and 21 px under it at three, so the scale does not move -- and the direction
## of the error is the safe one, because the clause is a `ScrollContainer`'s child in a block whose
## slack falls under `cost`.
func _build_picture_room(said: Label) -> Vector2:
	var rect := AssayHud.build_screen_rect(AssayHud.world_rect(), _world_band_top())
	# **THE PANEL'S OWN CONTENT MARGIN, ASKED OF THE PANEL** (`build_theme.gd`'s `PAD_X` 10 / `PAD_Y`
	# 6, which this file may not hold a second copy of -- ASSA-320's defect is prose and a constant
	# agreeing today). No stylebox means no theme, and then no padding either, which is consistent
	# rather than a guess.
	var pad := Vector2.ZERO
	if is_instance_valid(_build_box):
		var skin := _build_box.get_theme_stylebox(&"panel")
		if skin != null:
			pad = Vector2(skin.get_margin(SIDE_LEFT), skin.get_margin(SIDE_TOP))
	var crown := 0.0
	if is_instance_valid(_build_crown):
		# THE MINIMUM AND NOT THE LAID-OUT SIZE: a minimum is what the control asks for and is the same
		# answer in a window and in the test suite, where nothing has a size at all.
		crown = _build_crown.get_combined_minimum_size().y
	var furniture := float(_build_detail.get_theme_constant(&"separation"))
	var holder := _build_detail.get_parent().get_parent() as Control
	if holder != null:
		furniture += float(holder.get_theme_constant(&"separation"))
	if is_instance_valid(_build_detail_heading):
		furniture += _build_detail_heading.get_combined_minimum_size().y
	if said != null:
		furniture += said.get_combined_minimum_size().y
	var columns := AssayHud.build_columns_height(rect, pad, crown, float(BUILD_GUTTER))
	return Vector2(AssayHud.build_column_width(rect.size.x - pad.x * 2.0, BUILD_COLUMNS,
			BUILD_COLUMNS.size() - 1, float(BUILD_GUTTER)),
			maxf(0.0, columns - furniture))


## **THE COMMIT BAR'S LEFT: THE SIM'S SENTENCE ABOUT THE ACT, BROKEN ONLY WHERE THE SIM BROKE IT**
## (ASSA-332; Maren's §5.4).
##
## **ONE CLAUSE PER ROW, AND THE ROWS ARE THE SENTENCE** -- `AssayHud.sentence_clauses` splits at the
## sim's own `·` and keeps the mark, so joining what this block draws with a single space gives the
## sim's sentence back, character for character, in its order. That is what "whole" means after her
## ruling that **wrapping is not recomposing** (ASSA-305), and `test_main_screen.gd` asserts the
## re-joined text against `offer.line` rather than against a shape I typed.
##
## **IT IS `INK` AND NOT A `_note`, WHICH IS A WEIGHT CHANGE I MADE AND NAMED.** In block 5 this
## sentence was small print beside a picture; in the bar it is the thing the screen is for, read in the
## second before an irreversible press. Her ruling moved the rect and left the ink to me (box 10).
##
## **THE DEAD END KEEPS ITS OWN VOICE** (her ASSA-158 ruling: *"a permanent dead end may not be drawn
## in the same series as a cost"*). One of those can become true by playing and the other never can, so
## it is `FAILED`, the one colour this screen takes from the status scale -- and it is the sim's words
## either way, `debug::DEAD_END_LABEL` plus the sim's clause.
##
## **EMPTY WHEN THE SIM OFFERS NOTHING, AND THAT IS NOT A MISSING STATE.** The sentence is the sim's;
## with no offer there is no sentence, and block 5 already says the sim no longer offers this. Saying
## it twice is the two-homes-for-one-fact defect she ruled against on ASSA-316.
## **`_clear` AND NOT A `queue_free` LOOP, WHICH IS A DEFECT MY OWN SLICE-2b TEST FOUND IN CODE I
## SHIPPED ON THE MAKE PATH** (ASSA-332). `queue_free()` is DEFERRED: the old children are still in
## the tree when the new ones are added, so this block holds BOTH sentences until the frame ends --
## and two refreshes inside one frame (a click that mounts a part, which refreshes the screen, inside
## a tick that refreshes it too) draw the stale clause above the fresh one. `_clear` removes the child
## as well as freeing it, which is why it exists and why four other blocks on this screen call it.
##
## **IT WAS INVISIBLE BECAUSE EVERY TEST OF THIS BLOCK USED `contains`.** A joined readout containing
## the sim's sentence is satisfied by a block that also contains yesterday's; the slice-2b test holds
## the LABEL COUNT at one, and that is the assertion that went red.
## **AND IT ENDS BY ALIGNING `Build` TO WHATEVER ROW 1 TURNED OUT TO BE** (ASSA-363). The two halves
## below draw row 1 at two different heights -- a clause at `BODY` on the make path, the sim's verdict
## word at `Display` on the assembly path -- so the inset is a function of which half just ran, and
## the one writer that knows that is this one.
func _refresh_build_said() -> void:
	_clear(_build_said)
	if _assembling_mode():
		_said_about_design()
	else:
		_said_about_offer()
	_align_commit_row()


## **THE MAKE PATH'S HALF OF `_refresh_build_said`** -- its docstring above covers both halves and the
## reasons for every line here. Split out in ASSA-363 only so that the alignment at the end of the
## writer cannot be skipped by an early return, which is how the old constant's two paths diverged in
## the first place.
func _said_about_offer() -> void:
	var offer := _chosen_offer()
	if offer.is_empty():
		return
	for clause in AssayHud.sentence_clauses(String(offer.get("line", ""))):
		var said := Label.new()
		said.text = clause
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_build_said.add_child(said)
	var dead_end := String(offer.get("dead_end", ""))
	if dead_end != "":
		var warned := Label.new()
		warned.text = "%s%s" % [_sim.dead_end_label(), dead_end]
		warned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warned.add_theme_color_override(&"font_color",
				AssayHud.status_color(AssayHud.Say.FAILED))
		_build_said.add_child(warned)


## **THE COMMIT BAR ON THE ASSEMBLY PATH: THE SIM'S VERDICT, MOVING ON EVERY CLICK** (ASSA-317 slice
## 2b, over ASSA-325's `design_readout` and ASSA-329's third state).
##
## **THREE STATES, ALL THREE THE SIM'S, AND NOT ONE OF THEM DECIDED HERE.** `verdict` non-empty is a
## machine and gets `Display` -- the theme's own note on that size is *"the bench verdict, SAFE /
## UNCERTAIN / WILL BREAK -- the one word to read first"*. Otherwise the sim's `fault` goes where the
## verdict word went (`DesignReadout`'s own docstring says to), at `BODY`, because it is a sentence
## and not a word and this bar is 114 px. `unfinished` is what separates a design still being placed
## -- real numbers, a slot still empty -- from a selection the rules throw out, so **only the second
## takes `FAILED`**: a half-placed design is the normal state of building one a click at a time, and
## painting it in the status scale would say the player had done something wrong by starting.
##
## **AND THE FIGURES ARE NOT HERE, WHICH IS A GAP I AM NAMING RATHER THAN FILLING.** Maren's §5.4
## gives this bar *"the sim's sentence, whole, unchanged"* and `sim::debug`'s `readout_after` is that
## sentence -- but **no binding call crosses it**: `design_readout` carries the NUMBERS (mass, budget,
## speed, swings, capacity, hand_speed) and `design_preview`'s wording stays in `sim-cli`. Spelling
## `mass 3 of 240-360 budget` out of those fields here would be this client composing a sim sentence,
## which is ASSA-43/52 and the one rule ASSA-317 says does not bend. So the verdict is drawn, the
## figures wait on a sentence crossing the binding, and the item carries the ask.
func _said_about_design() -> void:
	var readout := _design_readout()
	if readout.is_empty():
		return
	var verdict := String(readout.get("verdict", ""))
	var said := Label.new()
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if verdict != "":
		said.text = verdict
		said.theme_type_variation = &"Display"
	else:
		said.text = String(readout.get("fault", ""))
		if not bool(readout.get("unfinished", false)):
			said.add_theme_color_override(&"font_color",
					AssayHud.status_color(AssayHud.Say.FAILED))
	_build_said.add_child(said)


## **`Build` AND THE SENTENCE'S FIRST ROW MEET AT THEIR CENTRES, FROM THE HEIGHTS THIS WINDOW
## RENDERED** (ASSA-363; Maren's ruling: *"inset whichever of `Build` and row 1 is shorter, by half
## the difference, from the heights actually rendered... compute it at layout time, never precomputed
## and never off a headless read"*).
##
## **ROW 1 IS THE FIRST LABEL'S LINE HEIGHT AND NOT ITS RECT**, which matters the moment a clause
## wraps: a two-row clause is 36 px tall and `Build` aligns to the first of those rows, not to the
## middle of both. `get_line_height()` is the engine's own answer to "how tall is one row of this
## label", and it is the same number `tools/limpet_build_screen_shot.gd` prints as `row 1 is N px
## tall`, so the tool and the layout cannot disagree about what they are measuring.
##
## **IT WIRES ITSELF TO ROW 1 RATHER THAN TRUSTING ITS CALLERS.** The rows are rebuilt from scratch on
## every refresh, so each row 1 is a different node and its `resized` -- the one moment its laid-out
## height exists -- has to be connected again. Doing that here means no refresh path can forget it,
## which is exactly how this defect got in: two paths, each correct for the one its author measured.
func _align_commit_row() -> void:
	if _build_said_inset == null or _build_said == null or _build_act == null:
		return
	var row := _row_one()
	if row != null and not row.resized.is_connected(_align_commit_row):
		row.resized.connect(_align_commit_row)
	_write_commit_inset(_build_act.size.y,
			float(row.get_line_height()) if row != null else 0.0)


## **THE INSET ITSELF, GIVEN THE TWO HEIGHTS** (ASSA-363). Split from the measuring above for a reason
## that is a finding and not a convenience: **no test outside a window can produce a `Display` row.** A
## variation does not resolve in the suite at all -- nothing there is inside the tree, so no theme owner
## is ever assigned and a `Display` Label measures the same 18 px as a `BODY` one, while the 1x shot
## measures 28. A font-size override does not move it either. So a test that drove this through
## `_align_commit_row` alone could only ever hold the `BODY` case, held twice, which is exactly how the
## constant this replaces shipped. Handing the window's own measured pair in is the honest form.
##
## **ONLY THE SENTENCE IS EVER INSET, AND THAT IS THE CLAMP RATHER THAN HALF A RULING** (named because
## her ruling covers both directions). `Build` renders at 30 and row 1 at 18 (`BODY`) or 28
## (`Display`), so the button is the taller control on every path that exists; `commit_inset` returns 0
## for the other direction and nothing moves. A second `MarginContainer` around `Build` would be a
## branch no screen can reach today -- and it would falsify the bar's own structural test, which holds
## that the bar's two children ARE the sentence and the button. If a row-1 kind ever measures over 30,
## this is where the mirror goes.
##
## **A 0 px ROW MEANS THERE IS NO SENTENCE**, which is not the same as an inset of 0 being right for a
## row: with nothing to align to, half of `Build` would be 15 px of air above an empty block.
##
## **ASSIGNED ONLY WHEN IT MOVES**, because writing a theme constant re-lays the bar out, which is what
## calls this back.
func _write_commit_inset(act_height: float, row_height: float) -> void:
	var inset := 0
	if row_height > 0.0:
		inset = int(roundf(AssayHud.commit_inset(act_height, row_height)))
	if _build_said_inset.get_theme_constant(&"margin_top") != inset:
		_build_said_inset.add_theme_constant_override("margin_top", inset)


## **THE SENTENCE'S FIRST ROW, WHICH IS ITS FIRST `Label` AND NOT ITS FIRST CHILD** (ASSA-363). Null
## when the sim offers no sentence.
func _row_one() -> Label:
	for child in _build_said.get_children():
		var text := child as Label
		if text != null:
			return text
	return null


## **BLOCK 5 ON THE ASSEMBLY PATH: THE DESIGN'S MASS AGAINST ITS FRAME'S BUDGET, AS A FILL**
## (ASSA-369 box 1; Maren's §5.1 -- *"a RATIO with a hard end. A ratio fill; the axis's end is the
## budget. When mass is over, the fill is full and the sim's verdict supplies the word"*).
##
## **WHICH TWO OF THE FOUR NUMBERS, AND WHY IT IS NOT A CHOICE I MADE.** Mass and budget both cross
## as RANGES, because density is read in 25-wide bands until the species is assayed. The sim's own
## verdict is decided on one pair of them (`assembly.rs::StatRange::verdict`): **`SAFE` is exactly
## `mass_high <= budget_low`** -- *"the heaviest this can be still fits the smallest budget it can
## have"*. Feeding the fill that same pair makes it full **when and only when the sim stops saying
## `SAFE`**, so the picture and the word in the bar can never disagree. Any other pairing would be
## this file inventing a second opinion about a comparison the sim already owns, which is
## `design_readout`'s own standing warning.
##
## **NO SPECIAL CASE FOR A REFUSED DESIGN** (box 5). With an extra part parked the sim answers every
## number 0, so this asks for 0 of 0 and `AssayTrack` draws nothing -- its documented answer for an
## absent fact, reached by the same code path as every other caller. Keeping numbers alive for a
## design the sim throws out would be the screen disagreeing with its own `Build`.
func _design_mass_row(readout: Dictionary) -> AssayReadingRow:
	var row := AssayReadingRow.new()
	row.show_amount("mass", int(readout.get("mass_high", 0)), int(readout.get("budget_low", 0)))
	return row


## **WHAT THE SIM SAYS ABOUT THE DESIGN ON THE SCREEN RIGHT NOW** (ASSA-317 slice 2b). `{}` before a
## frame is chosen or with no world, which `_said_about_design` treats as "nothing to say" rather than
## as a refusal -- a design with neither numbers nor a fault is a thing the sim never answers.
##
## **THE ITEMS ARE THE SIM'S OWN JSON, BUILT BY THE SIM** (`AssaySimHost.item_json`): the three fields
## came out of `inventory_of` and go back as the text the binding parses, so nothing here spells an
## item (ASSA-43/52).
func _design_readout() -> Dictionary:
	var frame := _design_frame()
	if frame.is_empty() or not _sim.running():
		return {}
	var mounted := PackedStringArray()
	for entry in _design_mounted():
		var stack: Dictionary = entry
		mounted.append(AssaySimHost.item_json(String(stack.get("kind", "")),
				int(stack.get("species", -1)), String(stack.get("grade", ""))))
	return _sim.design_readout(AssaySimHost.item_json(String(frame.get("kind", "")),
			int(frame.get("species", -1)), String(frame.get("grade", ""))), mounted)


## **BLOCK 6: COST AS AN ENTRY OF TWO ROWS, RE-READ EVERY REFRESH** (ASSA-332; Maren's §5.5, which
## replaces the §5.3 shape slice 1 shipped).
##
## **TWO ROWS, NAME THEN COUNTS, ALWAYS** -- her measurement, not a preference:
## `Abcdefghijklmnopqrst hopper (A)   need 4 · have 2` is **312 px at block 6's 240**, and even the
## terse `2/4` form is 239 px, one row with 1 px spare. No wording fits a worst-case entry on one row
## at this width, so the counts go under the name every time: *"a column you scan, not a wrap that
## happens sometimes"*.
##
## **THE COUNTS ARE RIGHT-ALIGNED FOR THAT SAME REASON** -- a column of ragged-left numbers is not one
## you can scan down.
##
## **THE NAME IS THE SIM'S `name` ON THE PACK STACK, WITHOUT ITS COUNT.** `stack_line` would print
## `8 × Tonore refined (A)`, which puts `have` on both rows of a two-row entry; the field is the
## sim-written wording either way (`inventory_of`), so nothing here words an item (ASSA-43/52).
##
## **THE WHOLE ENTRY GOES `FAILED` WHEN YOU ARE SHORT** (her §5.5), through
## `AssayHud.cost_entry_short` -- see that function for why reading the sim's two numbers is not this
## client deciding affordability.
##
## **THIS IS THE ONE PART THAT MOVES ON THE TICK CLOCK** -- with the bar, since ASSA-332 -- which is
## why it is not in `_rebuild_build_screen`: `count` is what the pack holds AT THIS TICK and climbs
## every mining cycle, so a cost drawn once would be stale on the surface whose whole job is telling
## you whether you can afford something. It is Labels only, and a Label's text is idempotent and free.
## **AND ON THE MAKE PATH THERE IS NO BLOCK 6 AT ALL ANY MORE** (ASSA-341 ruling 3; Maren's, off my
## own 1x shot, with her own scope correction read first).
##
## **THE SHOT PRINTED `need 5 · have 19` TWICE VERBATIM AND THE SAME PAIR A THIRD TIME INSIDE THE
## SIM'S SENTENCE.** It can never be otherwise here, and that is the shape of the type rather than a
## thin recipe list: `sim/src/debug.rs`'s `MakeOffer` carries **`pub input: Item` -- singular**. One
## offer is one recipe x one material, so there is one `cost` and one `have`, so this block can only
## ever hold ONE entry and that entry is always the material row the player just selected. A second
## copy of a sim sentence is the ASSA-43/52 defect quoted in `have_need_line`'s own docstring -- the
## function I wrote.
##
## **WHAT STAYS, BECAUSE SHE RULED SO EXPLICITLY:** the sim's sentence in the commit bar (§5.4,
## ASSA-88 ranks that clause highest and it is read before an irreversible press), and the material
## column's counts -- *they are the picker, and comparing two materials must not cost two gestures*
## (§3's Factorio borrowing). So the number does not leave the screen; its DUPLICATE does.
##
## **HIDING ALSO CURES ONE NOBODY FLAGGED:** `cost` sat under the `what you get` heading at the same
## x, reading as the heading that governs it (11.36).
##
## **THE WIDGET SURVIVES AND THAT IS THE POINT OF HIDING RATHER THAN DELETING.** Her correction:
## `AssemblyPlan::{Weighed,Unfinished}` carry `cost: Vec<ItemStack>` -- a real tallied list, frame +
## head + handle (+ hoppers) -- so on the ASSEMBLY path this block holds several entries and earns
## its 240x146. `_cost_entry` below is untouched and still tested without a world; slice 2 calls
## `_show_build_cost(true)` and fills it once Marlow's binding call crosses `cost` and `missing`.
## **If I had read ASSA-341's body before her ASSA-317 comment I would have deleted the thing slice 2
## needs**, which is worth recording next to the code rather than only in the item.
func _refresh_build_cost() -> void:
	_clear(_build_cost)
	_show_build_cost(false)


## **SHOW OR HIDE BLOCK 6, HEADING AND ALL, FROM ONE WRITER** (ASSA-341) -- `_show_log`'s shape and
## for its reason: the rows are inside the section, so hiding the rows alone would leave every test,
## probe and tool that asks `_build_cost.visible` reading `true` about a block nobody can see, which
## is the bug ASSA-117 was. Both nodes move together or neither does.
## **AND SINCE SLICE 2b IT IS ONE CASE OF A GENERAL RULE** rather than block 6's own trick: block 3's
## three sections swap by mode and would each have needed this paragraph.
func _show_build_cost(shown: bool) -> void:
	_show_section(_build_cost, shown)


## **SHOW OR HIDE ONE SECTION OF THE SCREEN, ROWS AND HEADING TOGETHER, FROM ONE WRITER** (ASSA-341,
## generalised by ASSA-317 slice 2b) -- `_show_log`'s shape and for its reason: the rows live INSIDE
## the section, so hiding the rows alone would leave every test, probe and tool that asks
## `_build_cost.visible` reading `true` about a block nobody can see, which is the bug ASSA-117 was.
## Both nodes move together or neither does.
func _show_section(rows: Control, shown: bool) -> void:
	rows.visible = shown
	var holder := _section_holder(rows)
	if holder != null:
		holder.visible = shown


## **A SECTION'S WHOLE RECT, GIVEN ITS ROWS** -- `_build_section` builds holder -> [heading, scroll ->
## rows], so the holder is two parents up. **One reader of that shape rather than five**, which is the
## same walk `_build_cost_box` was set from: the day a section grows a wrapper, five copies of this
## walk would each hide the wrong node and nothing would go red.
func _section_holder(rows: Control) -> Control:
	var scroll := rows.get_parent()
	if scroll == null:
		return null
	return scroll.get_parent() as Control


## **THE HEADING OVER A SECTION'S ROWS**: the holder's first child, by `_build_section`'s own order.
## Held by lookup rather than in five fields because the heading is a thing the MODE writes
## (`_rebuild_build_screen`) and `what to make` over a list of frames is the labelled-wrong-thing
## defect rather than a stale string.
func _section_heading(rows: Control) -> Label:
	var holder := _section_holder(rows)
	if holder == null or holder.get_child_count() == 0:
		return null
	return holder.get_child(0) as Label


## **ONE COST ENTRY: THE NAME, THEN THE TWO COUNTS** (ASSA-332).
##
## **SPLIT OUT SO A TEST CAN DRIVE THE DRAWING WITHOUT A WORLD**, which is `_refresh_halt`'s reason in
## this file and here it is the only way to see both branches. `_chosen_offer` re-reads `make_offers`
## at every refresh and matches on the sim's own `verb`/`tag` (ASSA-55), so an offer a test file
## invents never reaches the block above -- and whether a seeded fixture's pack happens to be short of
## the recipe it opens is worldgen's business. **A `FAILED` branch only a lucky fixture reaches is a
## state green for free**, so the two counts arrive here as plain `int`s and a test states them.
func _cost_entry(named: String, need: int, have: int) -> VBoxContainer:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := Label.new()
	name_row.text = named
	name_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(name_row)
	var counted := Label.new()
	counted.text = AssayHud.cost_counts_line(need, have)
	counted.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counted.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(counted)
	if AssayHud.cost_entry_short(need, have):
		for row in [name_row, counted]:
			(row as Label).add_theme_color_override(&"font_color",
					AssayHud.status_color(AssayHud.Say.FAILED))
	return entry


## **PRESS `Build`: THE SAME COMMAND THE ROW USED TO SEND** (ASSA-328).
##
## **IT IS `_make_verb_button`'s BODY WITH THE BUTTON TAKEN OFF**, deliberately: the two commands are
## `Craft` and `MakePart`, they have differently shaped payloads, and which one to send is the SIM's
## answer in `offer.verb` (`make_offers`' docstring: *"`verb` IS WHICH COMMAND, NOT A LABEL"*). A
## third copy of that match is how ASSA-146 happened, so the day a catalogue grows a verb there are
## two places to look and both of them say the verb is unknown rather than guessing.
##
## **ONE BATCH, AND THE COUNT IS NEVER CAPTURED** (ASSA-55): the offer is re-read from the sim at the
## press, not from what the screen was showing when it was opened, so a screen left up for a thousand
## ticks sends what is true now.
func _send_build() -> void:
	if _assembling_mode():
		# **THE ASSEMBLY PATH SENDS `Assemble` THROUGH THE ONE FUNCTION THAT ALREADY DID** (ASSA-317
		# slice 2b). `_assemble` builds the item list out of `_building`, and a second copy of that
		# here is how ASSA-146 happened. The screen stays open: closing it on a press would hide the
		# sim's refusal from the surface the player is reading, and on success the pack has changed
		# under a screen whose whole job is showing the pack.
		#
		# **AND THE EMPTY CASE ANSWERS RATHER THAN DOING NOTHING**, which is the make path's rule
		# three lines down: a primary control that is never disabled has to answer every press, and
		# `_assemble` returns silently on an empty design because the bench's button sits beside a
		# sentence that says what is chosen. This one does not.
		if _design_frame().is_empty():
			_say("choose a frame to build on first", AssayHud.Say.FAILED)
			return
		# **A DESIGN THE SIM CALLS UNFINISHED IS ANSWERED HERE AND NOT SUBMITTED** (ASSA-373 part 1,
		# Maren). `_assemble` clears `_building` on the SUBMISSION, so a press on a design still
		# missing a required part threw away every good mount with the bad press -- word for word the
		# harm `_choose_part`'s docstring records as fixed for PART presses, still live for this one.
		# The bar has been saying `it needs at least 1 head and has 0` the whole time; the press used
		# to answer that sentence by deleting the design it was about.
		#
		# **IT IS THE SIM'S FLAG, NEVER ITS SENTENCE, AND NEVER A COUNT OF SLOTS HERE.** `unfinished`
		# exists to be read (ASSA-329, crossed *"so a client reads the flag rather than testing
		# `fault`'s text"*), and a non-empty `fault` is ALSO how a REFUSED plan reads --
		# `DesignReadout::refused` leaves `unfinished` false -- so a text test would catch two
		# different states in one branch and refuse a press the sim would have accepted.
		#
		# **AN EMPTY READOUT FALLS THROUGH, DELIBERATELY.** `_design_readout` answers `{}` with no
		# world, and the honest answer to a press with no world is `_act`'s *join a world first*,
		# not a silence invented here.
		var readout := _design_readout()
		if bool(readout.get("unfinished", false)):
			_say(String(readout.get("fault", "")), AssayHud.Say.FAILED)
			return
		_assemble()
		return
	var offer := _chosen_offer()
	if offer.is_empty():
		# **IT SAYS SO RATHER THAN DOING NOTHING.** A primary control that is never disabled has to
		# answer every press, and "the sim does not offer this any more" is the honest answer -- the
		# alternative is the dead button ASSA-262 found in Mineralogy.
		_say("the sim no longer offers this in that material", AssayHud.Say.FAILED)
		return
	var what := String(offer.get("line", "?"))
	var item := AssayActions.item_of_stack(offer)
	match _build_verb:
		"craft":
			_act(what, AssayActions.craft(offer.get("tag"), item, 1))
		"make":
			_act(what, AssayActions.make_part(offer.get("tag"), item, 1))
		_:
			_say("this client has no command for %s" % _build_verb, AssayHud.Say.FAILED)


## **THE SIM'S NAME FOR A CATALOGUE ROW, ASKED BY TAG** (ASSA-328). `recipes()` and `part_kinds()` each
## cross a sim-written `name` beside the tag the wire carries, and they *"differ in case, which is
## exactly the kind of thing a client should not be guessing at"* (`recipes`' docstring).
##
## **A TAG WITH NO CATALOGUE ENTRY IS NAMED AS UNKNOWN AND NOT PAPERED OVER**, the contract
## `AssayHud.target_line` and the machine menu's name both keep: the only way here is a
## `libsim_godot.dylib` older than the sim it was built from, and printing the tag instead would look
## almost right.
func _catalogue_name(verb: String, tag: Variant) -> String:
	var wanted := JSON.stringify(tag)
	for entry in (AssaySimHost.recipes() if verb == "craft" else AssaySimHost.part_kinds()):
		var row: Dictionary = entry
		if JSON.stringify(row.get("tag")) == wanted:
			return String(row.get("name", ""))
	return "unknown %s %s" % [verb, wanted]


## The pack stack an offer eats, so a material row can be named in the SIM's words. `{}` when the pack
## does not hold it, which the caller treats as "fall back to the sim's whole sentence" rather than as
## an error: an offer always comes FROM a stack, so this is unreachable today and is the honest shape
## if `make_offers` ever offers something out of a slot instead.
func _pack_stack_of(offer: Dictionary) -> Dictionary:
	for entry in (_sim.inventory_of(_client.player_id) if _client != null else []):
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) == String(offer.get("kind", "")):
			if int(stack.get("species", -1)) == int(offer.get("species", -2)):
				if String(stack.get("grade", "")) == String(offer.get("grade", "")):
					return stack
	return {}


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


## **ONE DOOR FOR EVERY INSERT, AND NOW THERE IS ONE SURFACE TO PRESS IT** (ASSA-316/331). This was
## shared by a pack row that found its building through `_target_tile` and a menu that already knew
## which machine it was about; **the pack row is deleted**, so the cursor path is gone with it and the
## only caller is a menu whose building cannot be the wrong one. The `want` rules below outlived the
## button they were learned on, which is why they stayed here rather than in `_insert`.
##
## `want` 0 MEANS THE WHOLE STACK, counted here. **AND "THE WHOLE STACK" IS COUNTED WHEN THE BUTTON IS
## PRESSED, NOT WHEN IT WAS BUILT** -- learned from a `Fuel` press on a row reading 12 that inserted 2
## and let the fire go out mid-stack. The menu is no safer by being newer: it rebuilds on the pack's
## SHAPE too (`_menu_showing`), so a count captured in a closure would freeze there the same way.
## Grade is part of the question:
## two grades of one ore are two stacks and two rows, and inserting the other row's count would be a
## number from a different row.
##
## **A FRACTION IS CLAMPED TO WHAT IS LEFT RATHER THAN SENT AS TYPED.** `or 18` was written on the
## button when the row was built; a mining cycle or a partner's hands can leave fewer than that by the
## time it is pressed, and a count larger than the pack is a refusal the player did not earn. Floored to
## 1 only when something is held at all -- which is why the zero case is answered first and separately.
func _insert_into(at: int, stack: Dictionary, slot: String, want: int) -> void:
	var count := AssayInventory.held(_sim.inventory_of(_client.player_id),
			String(stack.get("kind", "")), int(stack.get("species", -1)),
			String(stack.get("grade", "")))
	if count <= 0:
		_say("you are not carrying any %s any more" % String(stack.get("name", "?")),
				AssayHud.Say.FAILED)
		return
	var sending := count if want <= 0 else mini(want, count)
	_act("Insert %d into %s" % [sending, slot], AssayActions.insert(
			at, slot, AssayActions.item_of_stack(stack), sending))


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
##
## **THAT LAST SENTENCE IS NARROWED BY ASSA-371 AND I AM NOT DELETING IT, BECAUSE ITS REASON STILL
## HOLDS WHERE IT WAS WRITTEN.** `what to mount` now disables a row the sim would refuse and draws
## the refusal under it, so on that list the reason no longer costs a press (ASSA-316 ruling 2).
## **What has not changed is who decides:** the predicate `_rebuild_build_mounts` asks is this same
## `part_press_refusal`, the press stays connected beneath the disabled flag, and this function
## refuses again if anything reaches it. ASSA-37's rule was that GDScript may not invent a limit;
## disabling a control whose refusal the SIM has already stated is not inventing one.
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
	# **THE BUILD SCREEN IS A READER OF `_building` SINCE SLICE 2b**, and it is the surface a mount is
	# pressed FROM: its slot shape, its mount list and the sim's verdict all move on this press. The
	# refresh is a no-op when the screen is shut (`_build_screen_open`), so the bench path pays
	# nothing for it -- and leaving it out would mean the one gesture the screen exists for was the
	# one gesture that did not redraw it.
	_refresh_build_screen()


## Build the machine. REJECTED ONLY FOR PARTS THAT DO NOT FIT, never for weight -- mass is tested at
## placement (sim decision 11).
##
## **THE CHOICE IS STILL CLEARED ON THE SUBMISSION, AND THE REASON THAT USED TO JUSTIFY IT IS GONE**
## (ASSA-373). It read: *"the event log carries the sim's reason, and a half-chosen assembly left on
## screen after a refusal reads as a stuck button."* That was written for the BENCH, where the design
## was a line of text with nowhere to put a refusal. The build screen has a home for one --
## `design_readout.fault`, drawn where the verdict goes -- so the premise no longer holds, and
## Maren's rule for the behaviour that outlived it is **a refusal may cost you a press; it may never
## cost you your work.**
##
## **WHAT IS FIXED: THE UNFINISHED CASE, AND IT IS FIXED IN `_send_build` RATHER THAN HERE.** The
## guard belongs at the press because this function is also the bench's, and the bench's button has
## no readout to be answered from.
##
## **WHAT IS NOT FIXED, AND WHY IT IS NOT A CHOICE** (ASSA-373 part 2): clearing on the OUTCOME needs
## the outcome, and no outcome crosses the binding. `AssaySim` exposes events as SENTENCES only
## (`event_lines`, `attention_lines`), so reading them here would be this client deciding what a sim
## sentence means -- the one thing `unfinished` was crossed to stop. The other route, refusing an
## unaffordable design before the press, needs `cost`/`missing`, which `design_readout` deliberately
## does not carry (it plans against an EMPTY inventory, so `MissingItems` is dropped on the floor).
## So `MissingItems` and a post-frame-switch `TooMany` still cost the design, and the item carries
## the ask rather than this file guessing a sentence apart.
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
	_refresh_build_screen()


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


## **ONE RATIO AS THREE COLUMNS: words | band | counts** (ASSA-334, ASSA-339; Maren's ASSA-316 ruling
## 5: *"a slot's fill and a burn's progress are RATIOS, so they take ASSA-276 move 3's band grammar"*).
##
## **IT IS `AssayReadingRow`'S SHAPE AND NOT A SECOND INVENTION**, because ASSA-288 already ruled what
## a ratio row looks like in this game and a menu that chose its own would be the "two of something"
## failure one surface along. What differs is the LABEL COLUMN: a reading row's is a fixed 104 px
## because its rows live in six separate grids, and these all live in one `VBoxContainer`, so
## `EXPAND_FILL` makes every row the same width and therefore puts every band on the same x by
## construction. The label is CLIPPED for the same reason it is there: a Label grows to its text, and a
## long word would push this row's band out of line with the one above it (Maren's rule 2 --
## *"a position encoding whose axes are not aligned cannot be compared down the column"*).
##
## **BUILT EMPTY AND FILLED BY `_set_amount_row`**, because the thing a nil batch has to draw is
## NOTHING and a row that is rebuilt to show absence is a row that can be forgotten in one branch.
func _amount_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", AssayReadingRow.GAP)
	var words := Label.new()
	words.name = ROW_WORDS
	words.clip_text = true
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var band := AssayTrack.new()
	band.name = ROW_BAND
	row.add_child(band)
	var counts := Label.new()
	counts.name = ROW_COUNTS
	counts.custom_minimum_size = Vector2(AssayHud.MENU_COUNTS_W, 0.0)
	# RIGHT-ALIGNED, which is what puts a slot's digits under the digits of the slot above it.
	counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(counts)
	return row


## **FILL ONE RATIO ROW FROM THE SIM'S TWO NUMBERS, or empty it when there is no ratio.**
##
## `total <= 0` is the absent case and it hides the WHOLE row rather than drawing a zero band: that is
## Marlow's ruling on `work` kept in his words -- *"`0 of 100` on a drill standing on bare ground is a
## number that reads as a promise"* -- and `AssayTrack.show_amount` refuses the same input for the same
## reason one layer down. **Both refusals, deliberately:** the track's keeps a band off the screen and
## this one keeps the COUNTS off it, and a row reading `0 of 0` with no band would be the louder defect.
func _set_amount_row(row: HBoxContainer, words: String, have: int, total: int) -> void:
	row.visible = total > 0
	(row.get_node(ROW_WORDS) as Label).text = words
	(row.get_node(ROW_COUNTS) as Label).text = \
			AssayHud.amount_counts_line(have, total) if total > 0 else ""
	(row.get_node(ROW_BAND) as AssayTrack).show_amount(have, total)


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
## THE PLATE, FITTED TO THE WORDS AND BOUNDED BY THE DOOR (ASSA-292).
##
## **`get_global_rect()` AND NOT MY OWN `parent.position + child.position`**, which is what the
## withdrawn first version did. A hand-rolled walk up the tree is a second implementation of
## something the engine already knows, and it is wrong the moment a child is nested one level deeper
## than I assumed -- the kind of defect that looks like a layout mystery.
##
## The judgement is all in `AssayHud.door_plate_rect`, which clips to the door, so the worst this
## function can do is ask about a rectangle that is not there yet. That case hides the plate: before
## a layout pass every child is 0x0, which is the headless state, so headless draws no plate and
## nothing in the suite asserts this node -- the arithmetic is tested directly instead and the
## picture is measured off the PNG.
##
## **IT ASKS `_door_words_rect` NOW AND NOT THE CHILDREN'S UNION** (Maren's card ruling, ASSA-292):
## every child here is a full-width container, so their union is a band across the whole door no
## matter how few words are in it.
func _place_door_plate(showing: bool) -> void:
	_door_plate.visible = false
	if not showing:
		return
	var content := _door_words_rect()
	if content.size.x <= 0.0 or content.size.y <= 0.0:
		return
	# **CLIPPED TO THE DOOR, AND THIS LINE HAS NOW BEEN BOTH WAYS ROUND.** It read `world_rect()` for
	# one night, with a note saying the shot had corrected it: clipping to the door put a 344 px
	# tongue of plate out over bare window beside the world, *"scrim where there is nothing to
	# scrim"*. **THAT WAS A SYMPTOM AND I TREATED IT AS THE CAUSE.** The bare window was the defect
	# (Maren, ASSA-292: the backdrop belongs in `join_rect`), and now that the door's picture IS the
	# whole window there is no margin for a plate to spill onto -- so the clip goes back to the rect
	# the layer actually occupies. One source for all three: `AssayHud.world_layer_rect(true)`.
	var plate := AssayHud.door_plate_rect(AssayHud.world_layer_rect(true), content)
	# A sliver is not a plate. Below one pad in either direction the words are not standing on
	# anything, and drawing it would be a dark line across the world for no legibility at all.
	if plate.size.x < AssayHud.DOOR_PLATE_PAD or plate.size.y < AssayHud.DOOR_PLATE_PAD:
		return
	_door_plate.position = plate.position
	_door_plate.size = plate.size
	_door_plate.visible = true


## **THE SMALLEST RECTANGLE THAT CARRIES THE WORDS** (ASSA-292, Maren's card ruling), in screen
## pixels, or an empty rect when there is nothing laid out to measure.
##
## **LEAVES ONLY, AND THAT IS THE WHOLE IDEA.** A container's rect is its parent's width; a leaf's is
## its own. Every ancestor on this screen is a full-width `BoxContainer` with centred content, so a
## walk that stopped at the direct children (which is what this did until tonight) could only ever
## return a band. Descending to the controls that actually paint something -- two Labels, two Buttons
## and two text boxes -- and asking each one what it drew is the difference between 912 px and the
## ~570 the words occupy.
##
## **AND A LABEL IS ASKED FOR ITS INK, NOT ITS RECT**, through `AssayHud.label_ink_rect`: a centred
## Label 1280 px wide holding a 152 px wordmark is 1280 px of control and 152 px of word. Buttons and
## text boxes are the other way round -- they paint their own opaque bed edge to edge, so their rect
## IS what they draw, and shrinking a plate inside a button's own background would be a seam.
##
## A LABEL WITH NO TEXT CARRIES NO WORDS. `_status` and `_detail` stand in this composition empty for
## most of a session; counting their line boxes would grow the card by two rows of nothing.
func _door_words_rect() -> Rect2:
	var words := Rect2()
	var found := false
	var walk: Array[Node] = [_front_door]
	while not walk.is_empty():
		var node: Node = walk.pop_back()
		var control := node as Control
		if control != null and control != _front_door and not control.is_visible_in_tree():
			continue
		var descended := false
		for child in node.get_children():
			if child is Control:
				descended = true
				walk.append(child)
		if descended or control == null or control == _front_door:
			continue
		var rect := control.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var ink := _control_ink_rect(control, rect)
		if ink.size.x <= 0.0 or ink.size.y <= 0.0:
			continue
		words = ink if not found else words.merge(ink)
		found = true
	return words if found else Rect2()


## WHAT ONE LEAF CONTROL ACTUALLY PAINTS, given the rect the engine gave it.
##
## THE MEASUREMENT IS THE ENGINE'S OWN, not a character count: `get_multiline_string_size` on the
## font the Label resolves through its own `theme_type_variation`, so the `Wordmark` at 56 px and the
## sentence at 13 px are each measured in the face they are drawn in. Asking the theme for a size
## here instead would be a second copy of `build_theme.gd`'s type scale.
##
## THE WRAP WIDTH IS THE CONTROL'S OWN WIDTH when the Label wraps, and `-1` when it does not -- which
## is the one number that makes a wrapped sentence's longest line come back instead of its whole
## length on one line.
func _control_ink_rect(control: Control, rect: Rect2) -> Rect2:
	var label := control as Label
	if label == null:
		return rect
	if label.text.strip_edges() == "":
		return Rect2()
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null or font_size <= 0:
		return rect
	var wrap := rect.size.x if label.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
	var measured := font.get_multiline_string_size(label.text, label.horizontal_alignment, wrap,
			font_size)
	return AssayHud.label_ink_rect(rect, measured, label.horizontal_alignment)


## **THE PICTURE MOVES WITH THE SCREEN IT IS ON** (ASSA-292, Maren's rectangle ruling). Two states,
## one call site each way, and `AssayHud.world_layer_rect` owns which rectangle is which.
##
## IT IS A SETTER AND NOT A BRANCH AT THE THREE READERS for the reason the helper's note gives: the
## door camera reads `_world.size` while it composes the view, so the layer has to be the right size
## BEFORE `_door_view` runs, not after. `_refresh_world`'s door branch calls this first; everything
## else comes through `_refresh_front_door`, which knows whether there is a world. Setting a Control
## to the size it already has is free, so calling it twice on one frame costs nothing.
func _place_world_layer(door: bool) -> void:
	var at := AssayHud.world_layer_rect(door)
	_world.position = at.position
	_world.size = at.size


func _refresh_front_door() -> void:
	# **THE PREDICATE IS "AM I IN A WORLD I CAN SEE", AND IT USED TO BE "IS ANYTHING DRAWN"**
	# (ASSA-292). `_world.view.is_empty()` alone was a correct proxy for exactly as long as the door
	# was a dark rectangle; the moment the door draws a world (`_door_view`) that proxy says a stranger
	# who has pressed nothing is playing -- it hid the front door and raised the whole HUD column over
	# the title screen. Seventeen tests said so, which is the cheapest way I have ever been told.
	#
	# BOTH CLAUSES ARE LOAD-BEARING AND THE SECOND IS NOT REDUNDANT: the `_player_facts_missing`
	# refusal in `_refresh_world` blanks the view while `_sim` is still running (box 5's decision), and
	# that case must go back to the door exactly as it did before. `_sim.running()` alone would leave
	# the column up over nothing.
	var empty: bool = not _sim.running() or _world.view.is_empty()
	_front_door.visible = empty
	_place_world_layer(empty)
	_place_door_plate(empty)
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
		# **THE DOOR IS NOT A DARK RECTANGLE ANY MORE** (ASSA-292). Same renderer, same sheets, a real
		# world at the seed solo plays -- so the first screen is the game instead of a picture of a
		# menu. `_door_view` returns `{}` if the binding cannot build one, which is exactly the empty
		# dictionary that used to be here, so the flat field is still the fallback and never the plan.
		#
		# **THE RECTANGLE BEFORE THE VIEW, AND THE ORDER IS THE WHOLE REASON THIS IS A CALL AND NOT A
		# FIELD** (ASSA-292). `_door_view` reads `_world.size` twice -- the camera's clamp and the
		# view's own `size` -- so a layer resized after the view was composed would spend the frame a
		# session ends showing a 912-wide camera stretched over a 1280-wide door.
		_place_world_layer(true)
		_world.view = _door_view()
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
	# **AN OPEN MACHINE MENU USED TO OUTRANK THE PLACEMENT TARGET HERE AND NO LONGER DOES** (ASSA-334,
	# Maren reversing her ASSA-316 ruling 8: *"the ring on the machine comes from the open menu, not from
	# `_target`"*). Her ruling 1 had put the menu in the far half of the map, so the ring was the only
	# thing tying the panel to its subject -- and ruling 1's own argument for not anchoring was that the
	# ring already provided that tie. **Both halves spent the same mark.** The shot shows the bill: a ring
	# on the menu's smelter while the column read `acting on (57, 59) · on a deposit`, two subjects and
	# one mark, with the one the buttons act on unmarked.
	#
	# **ANCHORING FREES IT.** The menu's tie to its machine is now its POSITION (`_place_machine_menu`),
	# so this line goes back to what ASSA-276 move 4 ruled: the ring is on the tile the verbs act on, and
	# no frame draws two.
	#
	# **AND SINCE ASSA-366 THE TWO CANNOT COMPETE AT ALL**: opening a menu sets `_target` to its machine,
	# so "the tile the verbs act on" and "the machine the panel is about" are the same tile by
	# construction. The contest this paragraph is about was between two answers to one question; there is
	# now one answer, and this line is still the only place that spends the mark.
	#
	# **AND IT IS THE SUBJECT'S FOOTPRINT, NOT THE TILE THAT WAS CLICKED** (ASSA-348, Maren: *"the
	# outline follows the subject, and the sim says what the subject is"*). `Take`, `Pickup` and
	# `Insert` all carry a `BuildingId`, so on a 2x2 smelter the one-tile outline claimed a quarter of
	# what the button was about to act on -- and since the menus shipped, the anchored panel and the
	# ring were two marks on screen disagreeing about the extent of one subject.
	_world.selection = _footprint_tiles(_target) if _targeted else null
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
## HOW MANY TILES OF ORE ARE WORKED OUT BEYOND THE DOOR CAMERA'S RESTING WINDOW. The drift reaches
## `AssayScene.TITLE_DRIFT_TILES` (1.75) in each direction, so 3 covers it with a tile to spare and the
## one-shot cache below can never be caught short by the camera moving.
const DOOR_ORE_MARGIN := 3

## **WHERE THE TITLE SCREEN'S CAMERA LOOKS, AND IT IS NOT SPAWN** (ASSA-311, Maren).
##
## ASSA-292 pointed this camera at `spawn_tile()`, and the card is centred on the window, so the two
## were the same place: the words sat on the patch you start on. Her measurement over the whole
## 128-frame drift loop -- **46.7% of the card's area was world showing through, 14,214 px of it
## pink**, the hero patch cut at its widest row, while the 258 px strip below the card (25.8% of the
## first screen) was **100.0% grass**.
##
## **AND IT WAS NOT THIS SEED'S BAD LUCK.** ADR 0001 guarantees the two chunks beside spawn hold the
## starter material, so a camera centred on spawn is centred on ore *by construction*, in every seed.
## Framing is the only lever, and it is free: the contrast spread across the loop is 0.15 / 0.09, so
## what the words read at does not depend on what the camera sees.
##
## **DERIVED FROM THE DEPOSIT TABLE, NOT NUDGED UNTIL A SCREENSHOT LOOKED RIGHT.** Her
## `workspaces/maren/probes/door_lookat.py` scores every half-tile look-at in the world at nine
## phases of the drift ellipse, against the sim's own deposits and the card's measured rect. 86 hold
## her bar -- nothing under the card at any phase, something below it -- and this is the best of them:
##
## ```
## look-at        under card  whole in frame  clipped  above/below  spawn pad
## (56,40) spawn    1 always        2            2        0 / 0      under the card
## (72.5,29.5)      0 EVERY phase  >=3          <=2       1 / 1      below it in 6 of 9 phases
## ```
##
## Her deposit table is controlled: `08-whole-world-marks.json` from a real 1x window shot of the
## same seed lists the same 13 deposits, tile and radius identical.
##
## **IT IS A LOOK-AT AND NOT A SEED.** The door world is still the world solo plays at tick 0
## (ASSA-292 box 6 asserts the seed by reference), because *"press the button and you walk into the
## field you were looking at"* has to stay true. We moved the camera, not the world.
##
## **HALF-TILES ARE ALLOWED AND MEANT:** the camera takes a float centre, and the drift already moves
## it in fractions of a tile every frame, so rounding to a whole tile would only coarsen the search.
const DOOR_LOOK_AT := Vector2(72.5, 29.5)


## THE VIEW DICTIONARY FOR THE WORLD BEHIND THE DOOR (ASSA-292), or `{}` if there is no binding to
## build one from -- in which case the caller draws the flat field this screen had before.
##
## **NOBODY IS DRAWN IN IT, AND THAT IS THE DESIGN AND NOT AN OMISSION.** `players` is empty and
## `_world.me` stays null, because the sentence this screen makes is *"press the button and you walk
## into the field you were looking at"*. A body already standing in the field contradicts the button.
##
## IT ASKS `AssayScene.title_drift` FOR THE CAMERA AND NOTHING ELSE. All the judgement -- that the
## path is a closed loop, how wide, how finely a measurement has to sample it -- is arithmetic over
## there with three tests on it, so this function has nothing in it to get wrong.
func _door_view() -> Dictionary:
	if _door_dead:
		return {}
	if not _door_sim.running():
		var welcome := AssaySimHost.fresh_welcome_json(AssaySoloRelay.DEFAULT_SEED, "the door")
		if welcome == "" or not _door_sim.start(welcome):
			_door_dead = true
			return {}
	if _manifest.is_empty():
		_manifest = AssaySprites.manifest()
	if _layout.is_empty():
		_layout = AssayAssembly.contract()
	var size := _door_sim.size_tiles()
	var seconds := float(Time.get_ticks_msec()) / 1000.0
	# THE DRIFT IS ADDED TO THE CENTRE TILE AND NOT TO THE ORIGIN, so it passes through
	# `camera_origin`'s world-edge clamp like any other camera. Added afterwards it would be the one
	# camera in the client allowed to show the void beside the world.
	var centre := DOOR_LOOK_AT + AssayScene.title_drift(seconds)
	# `0.0` headroom: the north exception exists for the event log hanging over the map, and at the
	# door there is no log and no body for it to hide (ASSA-184).
	var origin := AssayScene.camera_origin(centre, size, _world.size, 0.0)
	return {
		"world_tiles": size,
		"origin": origin,
		"size": _world.size,
		"spawn": _door_sim.spawn_tile(),
		"ore": _door_ore_under(size),
		"players": [],
		"buildings": _door_sim.buildings(),
		"manifest": _manifest,
		"layout": _layout,
		"seconds": seconds,
	}


## ORE IN THE DOOR WORLD, WORKED OUT ONCE AND KEPT. A separate `_door_ore_built` flag rather than
## `_door_ore.is_empty()`: a world with no ore in frame is a legitimate answer, and an emptiness test
## would recompute ~600 `tile_at` calls every frame forever on exactly that world.
func _door_ore_under(size: Vector2i) -> Dictionary:
	if _door_ore_built:
		return _door_ore
	# **THE SAME `DOOR_LOOK_AT` THE CAMERA USES, AND THAT IS THE WHOLE POINT OF THE CONSTANT**
	# (ASSA-311). This window is built ONCE and kept, so a look-at that moved the camera and not this
	# would hand the drawing code a camera pointing somewhere the ore was never gathered -- a title
	# screen of empty grass, with every unit test still green. `test_the_door_gathers_its_ore_where_
	# its_camera_is_pointing` asserts the two agree; swapping this line back to spawn reddens it.
	var home := AssayScene.camera_origin(DOOR_LOOK_AT, size, _world.size, 0.0)
	var window := AssayScene.visible_tiles(home, _world.size, size).grow(DOOR_ORE_MARGIN)
	window = window.intersection(Rect2i(Vector2i.ZERO, size))
	_door_ore = {}
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var at := Vector2i(x, y)
			var patch: Variant = (_door_sim.tile_at(at) as Dictionary).get("deposit")
			if patch == null:
				continue
			var deposit: Dictionary = patch
			_door_ore[at] = {
				"species": int(deposit.get("species", 0)),
				"grade": String(deposit.get("grade", "C")),
				"depleted": bool(deposit.get("depleted", false)),
			}
	_door_ore_built = true
	return _door_ore


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
## RIGHT CLICK CHOOSES THE TILE THE BUTTONS ACT ON (ASSA-37). **PLACE IS THE LAST VERB ON IT**: the
## mechanism was built for Place, Insert and Take together, and ONE mechanism serving all three is what
## kept the rule explainable -- then Take moved to the machine menu (ASSA-316 ruling 3) and Insert
## followed (ASSA-331), so what is left is a placement cursor and nothing else. Still true of it: a
## placement is never a second click on a button, and a click never means two things at once. Walking
## kept the left button because it is the thing a player does most.
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
	# **A TILE CARRYING A BUILDING ANSWERS BOTH BUTTONS WITH ITS MENU** (ASSA-316, Maren's rulings 7 and
	# 8). An EMPTY tile keeps today's split exactly: left walks, right targets the placement.
	#
	# **AND THE MENU IS NOW ALSO HOW A STANDING BUILDING IS AIMED AT** (ASSA-366). This return is what
	# used to make that impossible: it is above the only assignment to `_target`, so a tile with a
	# building on it could never become the aimed one. The aiming moved INTO `_open_machine_menu` rather
	# than being duplicated here, so there is still exactly one line in this file that aims at a tile for
	# a menu and one that aims for a right-click, and neither can drift from the other's meaning.
	#
	# **THIS IS NOT THE THING ASSA-37 FORBIDS.** Its rule is that a click never means two things at once;
	# two buttons reaching one result is the opposite -- the same meaning from either hand, which is what
	# makes it impossible for the board to miss the feature they asked for.
	#
	# IT IS ASKED BEFORE THE DISMISSAL BELOW, so clicking a second machine opens that machine's menu
	# instead of merely shutting the first (ruling 2: opening a second closes the first).
	if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
		var standing: Variant = _sim.tile_at(tile).get("building") if _sim.running() else null
		if standing != null:
			_open_machine_menu(tile, int((standing as Dictionary).get("id", -1)))
			return
	# **THE DISMISSING LEFT CLICK IS CONSUMED: IT CLOSES AND DOES NOT WALK. A SECOND CLICK WALKS**
	# (ruling 7's condition). A gesture that both shut a panel and sent the player across the map would
	# be two meanings on one press, and the player who wanted the walk still gets it from the next click,
	# with the menu already out of the way.
	#
	# **THE RIGHT BUTTON CLOSES AND STILL TARGETS, AND THAT IS MEASURED RATHER THAN PREFERRED.** I
	# consumed both buttons first, and `window_shot.gd`'s own demo loop then failed on the next beat: it
	# opens a machine's menu to Take, then right-clicks a free tile to aim the next placement, and that
	# press was swallowed -- so `Place` landed on the STALE target, which was the smelter, and the sim
	# refused with *"another building is in the way"*. The loop is a player proxy, so that is a player
	# losing a gesture they can see no reason for.
	#
	# Maren's ruling 8 is the authority for the fix rather than my taste: *"an empty tile keeps today's
	# split EXACTLY"*. A cursor is not travel -- the whole reason the walk is consumed is that it sends
	# you somewhere -- so moving it costs nothing and surprises nobody. Hers to reverse in one line.
	if _menu_at != -1:
		_close_machine_menu()
		if event.button_index != MOUSE_BUTTON_RIGHT:
			return
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

	# **PASS 1 OF 3: EVERY MACHINE'S RIMS, BOTH OF THEM, BEFORE THE PEOPLE** (Maren's rule 11.42 of
	# 2026-10-08: *paint order is global, not per-mark — one pass of every SEPARATOR, then PEOPLE, then
	# every IDENTITY*). Rims here, players below, bands further down. The list is fetched once and read
	# by all three passes plus the glyph pass, because two calls to `_building_marks` could be two
	# different worlds in one frame.
	#
	# **THIS IS TWO ITEMS' FIX AND ONE ORDER, WHICH IS WHY IT IS A LAW AND NOT A PATCH.**
	# - Pass 1 before pass 3 is **ASSA-289**: a younger machine's rim can no longer delete an older
	#   one's band, because no rim is painted after any band.
	# - Pass 1 before pass 2 is **ASSA-278 box 7** (#392, reopened): a rim no longer takes a person's
	#   fill. §11.39, which Maren wrote in the ruling that first closed #392, forbids exactly that —
	#   keyline over ink — and 11.42 is its global form.
	#
	# **AND IT REACHES WHAT I TOLD HER NOTHING COULD.** I wrote on ASSA-289 that the 1x1 residual was
	# out of reach of paint order *"because a mark's own rim is painted after its own band by
	# construction"*. 11.42 dissolves that construction, and `tools/assa289_paint_probe.gd` says so:
	#
	#   a neighbour's band kept      one loop   two passes (#421)   three passes (11.42)
	#   2x2 adjacent, all three ways  136/144      144/144              144/144
	#   1x1 adjacent, all three ways  128/144      136/144              **144/144**
	#
	# What survives is not a deletion and no order can touch it: a 20 px mark on a 9 px tile leaves the
	# older machine's wall standing INSIDE the younger one's hole, so two adjacent drills read as one
	# box with a tick in it. That is the floor, it is ASSA-289 box 5, and it is Maren's.
	var shapes := _building_marks(_sim.buildings())
	for shape_entry in shapes:
		var shape: Dictionary = shape_entry
		# **FOUR BANDS, NOT A STROKE** (ASSA-236): an unfilled `draw_rect` straddles the edge it is
		# given, which on this mark would put ink on the tile next door at every machine on the map.
		# The outward rim separates the mark from the ground it stands on; the inward one gives the
		# band's inner edge a dark neighbour on a bright deposit (ASSA-278, 1.53:1 without it). Both
		# are separators, both are `building_keyline`, and `test_map_key.gd` holds that as ONE row —
		# so splitting them across the player pass would need a 22nd key row for an ink already in it.
		for band: Rect2 in AssayHud.frame_bands(shape["keyline_rect"], AssayHud.MARK_KEYLINE_PX):
			draw_rect(band, AssayHud.mark_ink_of(&"building_keyline", shape["keyline"]), true)
		# **AND THE INWARD RIM IS THE WHOLE HOLE NOW, NOT A 2 PX RING INSIDE IT** (ASSA-273 box 1,
		# Maren's ruling of 22:16Z: *"the hole takes `MAP_BG`, the bed already drawn 2 px deep inside
		# it"*). Same ink, same key row, same pass, one `draw_rect` instead of four: everything
		# ASSA-278 bought the band's inner edge is still bought, because a filled hole is a superset
		# of the ring that used to line it.
		#
		# **WHAT IT BUYS IS THAT A MACHINE'S PICTURE STOPS BEING A PER-WORLD ROLL.** Of a 1x1's
		# 24x24 = 576 px² box, 144 px² was the GROUND showing through the hole -- our ink and the
		# world's at 1.00:1, and the world's half swinging 7.5x between seeds (`disc:map` 11.58:1 on
		# seed 63 against 1.54:1 on 777042, `shared/assay/cove-assa273/costume/`). That is what
		# Marlow's cold read named without a number: *"the two pictures do not even agree with each
		# other about what a machine looks like."* Filled, every pixel of a mark's own box is a mark
		# ink, so two worlds paint the same picture -- which is the one check this item never had, and
		# `test_hud.gd`'s `no_ground_shows_through` is it.
		#
		# **IT IS IN THIS PASS AND NOT THE BAND PASS, AND THAT IS WHAT KEEPS IT LEGAL** (Maren's
		# condition (i); 11.14, 11.42). `PLAYER_MARK_PX` 16 against a 12 px hole: painted after the
		# people it would bury a player standing on their own machine. Painted with the rims it sits
		# UNDER them, as the 2 px ring already did, and the order scan in `test_hud.gd` is the leg
		# that holds it rather than this paragraph.
		#
		# **ONE THING THIS DOES NOT DO, SO NOBODY READS IT AS DONE: the surround is untouched.** The
		# costume Marlow described is mostly OUTSIDE the keyline -- `ring disc` **88.0%** on 63
		# against 31.7% on 777042, where `hole disc` was 32.8% on BOTH. Maren's own ruling says the
		# surround tells a reader 2.7x more than the hole. This closes the rented quarter of the
		# mark's box and leaves a machine still standing in whatever the worldgen rolled around it.
		# (**88.0 CORRECTS AN 89.3 I TYPED HERE AND IN THE PR BODY.** No file ever held 89.3;
		# `shared/assay/cove-assa273/holefill/costume-filled.txt` and its README both say 88.0, and
		# the number I sent Maren was 88.0, so the code was the only wrong copy.)
		#
		# **AND WHAT THE COSTUME NOW RESTS ON, IN MAREN'S WORDS RATHER THAN A DOC** (22:16Z, her
		# ruling 5): before this fill, a machine on ore and a machine on bare ground differed
		# INSIDE. After it they are identical inside and differ only in the ring -- so the surround
		# is not merely the bigger tell, it is the WHOLE tell. **If anyone later beds the ring the
		# way ASSA-278 bedded the band, the costume goes with it**, and a machine on ore stops
		# looking different from a machine on rock at all. That is a consequence to choose on
		# purpose, not to discover in a frame.
		draw_rect(shape["hole_rect"], AssayHud.mark_ink_of(&"building_keyline", shape["keyline"]),
				true)

	# **PASS 2 OF 3.** EVERY PLAYER, AT A SIZE THAT DOES NOT COME FROM THE TILE (ASSA-119 box 6,
	# Maren's finding 1).
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
	# mark and your body are at the same point TO THE PIXEL, and the mark was `BUILDING_MARK_PX` **16
	# at the time of this measurement** (it is 20 since #395, and this mark is a hollow rect since
	# ASSA-236; the past tense is ASSA-289's bill for leaving a dead constant in the present tense)
	# against a 16 px filled square: at that size a diamond is exactly INSCRIBED in the body
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
	# **PASS 3 OF 3: EVERY MACHINE'S BAND, AFTER EVERY RIM AND AFTER THE PEOPLE** (rule 11.42, above
	# the player pass, where the list is fetched and the rims are painted). The band is this mark's
	# IDENTITY — a hollow frame's four sides have been the whole of what says "machine" since
	# ASSA-236 — and identity goes last so nothing of another mark's can bite it.
	#
	# **THE NUMBER THIS COMMENT CARRIED FIRST -- "ate 36 of the older one's 128 band px (28.1%), a
	# contiguous 2x14 run" -- IS DEAD, AND SO IS MY OWN REPLACEMENT FOR IT.** Maren's probe ran at
	# `BUILDING_MARK_PX` 16, where two adjacent 2x2 marks abut exactly so a 2 px rim lands squarely on
	# a 2 px band; #395 moved the constant to 20 and every number measured against 16 died with it. I
	# then wrote that the dominant eater was the neighbour's BAND, at 27.8%. **It is not. Both numbers
	# count rect OVERLAP and call it deletion.** `building` and `building_keyline` carry no alpha in
	# `AssayHud.MAP_MARKS`, so white over white loses nothing and only dark over white does.
	#
	# **AND NOT AN INWARD-ONLY KEYLINE, WHICH IS THE OTHER MECHANISM SHE NAMED ON ASSA-289.** Turning
	# the outward rim inward would retire the only thing that gives the band's OUTER edge a dark
	# neighbour: on a grade-A deposit the band is 2.19:1 against the ground and 11.40:1 against this
	# rim (ASSA-278). That trade re-opens the defect ASSA-278 was filed for, on the other edge.
	for shape_entry in shapes:
		var shape: Dictionary = shape_entry
		for band: Rect2 in AssayHud.frame_bands(shape["rect"], float(shape["stroke"])):
			draw_rect(band, AssayHud.mark_ink_of(&"building", shape["colour"]), true)
		# **THE GLYPH PASS BELOW REPEATS THIS LOOP FOR A FRAME A LETTER'S BED COVERS**
		# (ASSA-273 box 3, DRAFT). I tried to factor it into `_paint_building_frame(shape)` first
		# and `test_map_key.gd` is right to refuse it: its scan reads `_draw`'s OWN source, so a draw
		# call moved into a helper is a mark the key can stop naming. The painter has one entry point
		# on purpose, so the repetition stays here where the scan can see it.

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
	# `_sim.buildings()` a second time and NOT `shapes`: ASSA-314's condition is a SIM fact (which
	# tiles a footprint holds) and `shapes` are pixels. The list is the same one `_building_marks`
	# read at the top of this frame — the sim is not stepped inside `_draw`.
	for glyph_entry in _glyph_marks(deposits, font, shapes, _sim.buildings()):
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
		# **ASSA-273 BOX 3: THE BED YIELDS TO THE BAND IT LAPS; THE LETTER'S INK DOES NOT.** Maren's
		# ruling 2026-10-08 13:29, under §11.39 of the same night: **where two marks overlap, the
		# KEYLINE yields and the INK does not.** A bed is a separator; a machine's band has been its
		# whole identity since ASSA-236. Nothing above this line changes -- the bed is still stamped
		# whole, because it is one glyph and a halo cannot be drawn in pieces -- and then the frames
		# the letter laps are stroked again, so the band gets its own pixels back from its own bed
		# while the letter's strokes go on top of everything as ASSA-213 requires.
		#
		# **WHY THE BED AND NOT THE LETTER.** On real co-op frames with a drill on a deposit centre,
		# the band keeps 13.2% of its own ink on seed 777042 and 62.5% on 63, and WHAT TOOK IT is not
		# the letter: 65.3% of that band is bed on 777042 (the letter's own ink is 19.4%). A band is a
		# shape, so the statistic is its longest unbroken run, and two of the four sides hold no pixel
		# of the mark at all. (This said 44.4% for seed 63 while it was a draft; that was measured
		# against the 32 px letter ASSA-293 retired, and the re-shot figure is 62.5 -> 86.8%.)
		#
		# **THE PRICE IS ASSA-218's FAILURE IN A SMALLER PLACE, AND IT IS THE COMMON CASE, NOT ONE
		# SEED.** Where a stroke crosses the restored band there is no bed between a `GLYPH_LIGHT`
		# letter and a 242 band -- white on near-white. I offered to condition this on `glyph_color`
		# picking `GLYPH_DARK` and Maren refused it with a sweep of all 600 disc states: LIGHT is
		# picked **342/600 (57.0%)**, and in **222/600 (37.0%) no single ink clears 3:1 against both
		# its disc and the band**. So a letter cannot be whole on an occupied tile whatever the bed
		# does, the condition would have read the DISC while the risk lives on the BAND, and the
		# design call is hers: **the machine wins the overlap** -- you chose that tile and built on
		# it, so you already own its species, and "something is built here" is the fact two cold
		# readers could not get at all (ASSA-278 box 5, failed). The letter left at 1.12:1 on top of
		# the mark that won is **ASSA-314**, hers.
		#
		# **THE BAND ALONE, NOT THE WHOLE FRAME, AND THAT IS A MEASUREMENT AND NOT A PREFERENCE.**
		# Restoring the two `MAP_BG` keylines as well costs a DARK letter a quarter of its boundary:
		# on seed 63 the share of the letter's boundary carrying a 4.5:1 edge went 80.2% -> 54.0%,
		# because `GLYPH_DARK` (5,5,8) against a `MAP_BG` keyline (26,28,33) is 1.3:1 where the
		# yellow bed it replaced was an edge. The keylines hold the band apart from the marks NEXT
		# DOOR, and the bed is not next door -- it is on top. So only the band comes back.
		for lapped_index in glyph.get("lapped_by", []):
			var lapped: Dictionary = shapes[int(lapped_index)]
			for band: Rect2 in AssayHud.frame_bands(lapped["rect"], float(lapped["stroke"])):
				draw_rect(band, AssayHud.mark_ink_of(&"building", lapped["colour"]), true)
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
	# the rows.
	#
	# **AND THE OUTLINE IS NOW INSET INSIDE ITS OWN CELL** (ASSA-284 box 7; this paragraph said the
	# inset "is ASSA-284's open box and Maren's call" and she called it at 05:55 EDT). Both rects are
	# half-stroke insets, so every pixel either stroke paints belongs to the hovered tile -- it used to
	# paint x=500 for a cell starting at 501. A mark that IS a cell has no size to hide behind, which
	# is ASSA-213's rule about position with nothing left over.
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
func _glyph_marks(deposits: Array, font: Font, building_marks: Array = [],
		buildings: Array = []) -> Array:
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
		# **ONE SIZE FOR EVERY LETTER ON THE MAP, AND IT IS NOT THIS DISC'S** (ASSA-293, Maren's
		# ruling 11.35). This was `glyph_size(radius)`, which made the letter a second, lossier copy
		# of the channel the disc under it already carries: three radii, two letter sizes, 63.6% of
		# deposits over ten seeds wearing a size that distinguished nothing. `radius` stays, because
		# `deposit_disc` below is about the patch and its edge is a claim about which tiles hold ore.
		# The LETTER is not, so it is held at `glyph_size_held`. See `tools/letter_size_spread.gd`.
		var size := AssayHud.glyph_size_held(_cell)
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
			# **ASSA-273 box 3: WHICH BUILDINGS LAP THIS LETTER, not just whether any does.**
			# `bedded` is one bit and the bed's PRICE is per-building: the bed is a halo in the disc's
			# colour and on a dark disc it is the thing that eats the band (65.3% of it on seed
			# 777042, measured by `shared/assay/cove-assa273/bandread.py` on a real frame). To let the
			# band back over its own bed, the painter has to know which frame to re-stroke.
			# `test_a_letters_bed_yields_to_the_band_it_laps_and_its_ink_does_not` holds this list
			# against `letter_occlusions` and holds its indices against the shapes `_draw` is given,
			# because the painter subscripts `shapes[...]` with them.
			"lapped_by": [],
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
			((marks[j] as Dictionary)["lapped_by"] as Array).append(int(lap["building"]))
	# **AND A LETTER ON A TILE A MACHINE STANDS ON IS NOT DRAWN AT ALL** (ASSA-314, Maren ruled
	# option 1 at 16:38 EDT: *no species letter on a tile carrying a building mark*).
	#
	# **THE RULING RESTS ON THE HOLE, NOT ON INK.** ASSA-236 made this mark hollow so the rock shows
	# through it; her census of a real frame says a drill's 16x16 hole is **56.2% species letter** on
	# the placement a drill always has, because a drill mines the rock it stands on. The inward rim
	# (ASSA-278) and the 16->20 size bump were both bought to protect that hollowness and it was
	# already gone. Her geometry leg agrees from the other side: **0 of 26 capitals fit the hole**,
	# and the killer is the 27 px ASCENT against 16 px, which no letter and no species roster
	# escapes. No ink could have fixed it, which is why option 2 and option 3 are dead.
	#
	# **`machines_on_letters` AND NOT `letter_occlusions`, WHICH IS THE OBVIOUS WRONG ONE.** Her rule
	# says *a tile carrying a building mark*: a SIM fact about occupancy. `letter_occlusions` is a
	# PIXEL lap, and a 20 px mark laps a 23x27 cap box on a 9 px grid out to **two tiles away** — so
	# building this on the helper two lines above would delete the letters of deposits nothing is
	# standing on. **A patch whose centre is free keeps its letter**; that clause is the difference,
	# and `test_a_letter_is_not_drawn_on_a_tile_a_machine_stands_on` holds both halves.
	#
	# Suppressed LAST, after `lapped_by` is filled, so ASSA-273's bed yield is untouched on every
	# letter that survives: this removes letters, it does not re-score them.
	var covered := {}
	for raw in AssayHud.machines_on_letters(buildings, marks):
		covered[int((raw as Dictionary)["letter"])] = true
	if not covered.is_empty():
		var kept := []
		for j in range(marks.size()):
			if not covered.has(j):
				kept.append(marks[j])
		# `lapped_by` indexes `building_marks`, which this does not touch, so the surviving letters'
		# lists stay valid. Dropping a letter cannot invalidate another letter's indices.
		marks = kept
	return marks
