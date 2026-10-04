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
var _status := Label.new()
var _detail := Label.new()
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
var _halt := VBoxContainer.new()
var _halt_box: PanelContainer = null
## The stopped lines alone, without the heading. Rebuilt with the block.
var _halt_lines: VBoxContainer = null
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
## THE BOX THAT SCROLLS THE COLUMN. Held since ASSA-117, for one reason: revealing the log has to
## MOVE THE VIEW to it. Maren verified in code that `ensure_control_visible` and `scroll_vertical`
## appeared nowhere in this file, which is why pressing the toggle changed a button's label and
## nothing a player could see -- the log is the last section of a column that already overflows.
var _scroll: ScrollContainer = null
## A SCROLL THE NEXT FRAME OWES THE PLAYER. True between pressing the log's toggle and the view
## actually moving to it; see `_show_log` for why those cannot be the same moment.
var _scroll_to_log := false
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
## SO THESE ARE A HISTORY, NOT A GUESS. `_was` is the snapshot's own answer from one tick ago; "now"
## is the snapshot's answer today, read live. Nothing here extrapolates past it.
var _was := {}
var _seen := {}
var _facing := {}
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
## The tile under the mouse, and whether the mouse has ever been over the map. Not a Vector2i alone,
## because tile (0, 0) is a real tile and "no hover" is not it.
var _hover := Vector2i.ZERO
var _hovering := false
## The newest event lines, oldest first. View state: the sim keeps only the last tick's events, so
## anything older than that is remembered here or nowhere.
var _events := PackedStringArray()


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
	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.refused.connect(func(reason): _say("refused: %s" % reason, AssayHud.Say.FAILED))
	_client.link_failed.connect(func(reason): _say(reason, AssayHud.Say.FAILED))
	_client.tick_bundle.connect(_on_tick_bundle)
	_client.desynced.connect(func(tick): _say(
			"desync at tick %d. Restart the client to rejoin (Decision 3: no reconnect)." % tick,
			AssayHud.Say.FAILED))
	# A note is narration, so its state is whatever the link's state already is.
	_client.note.connect(func(line): _say(line, AssayHud.Say.JOINED
			if _client.stage == AssayNetClient.Stage.JOINED else AssayHud.Say.CONNECTING))
	add_child(_client)
	_build_ui()
	# **TWO DOORS, SOLO FIRST** (Maren, ASSA-113). This used to read "enter a host address and join",
	# which sent a stranger to the one door that needs information they do not have -- and it survived
	# the whole of ASSA-106 because I never re-read the item between the branch and the PR.
	_say("Press Play solo to start your own world, or enter a host address to join someone.",
			AssayHud.Say.IDLE)


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
	_world.position = world.position
	_world.size = world.size
	add_child(_world)
	_view_toggle.position = world.end - Vector2(152.0, 36.0)
	_view_toggle.custom_minimum_size = Vector2(144.0, 0.0)
	_view_toggle.tooltip_text = ("the close-up follows you at 32px a tile; the whole world is the"
			+ " schematic, with every deposit and every player on it")
	_view_toggle.pressed.connect(func(): _show_close_up(not _close_up))
	add_child(_view_toggle)

	var row := HBoxContainer.new()
	row.position = Vector2(24.0, 20.0)
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	# **PLAY SOLO: DOWNLOAD AND PLAY, WITH NOTHING TO TYPE** (ASSA-106, the board's own ask). The
	# host box already defaults to `localhost`, so the shortest honest version of their request was
	# never "a field with a better default" -- it was that nothing is listening on the other end.
	# This starts the `sim-relay` that shipped in the same zip, on loopback, and joins it.
	#
	# **FIRST IN THE ROW AND IT TAKES THE FOCUS** (Maren, ASSA-113): the row reads left to right, so
	# the door that needs nothing typed is the first thing a stranger reads and the thing Enter
	# presses. Beside `Join` rather than instead of it -- a friend's host address is the other half of
	# the milestone and this must not become the only way in.
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
	_solo_button.focus_mode = Control.FOCUS_ALL
	_solo_button.pressed.connect(_on_play_solo)
	_solo_button.tree_entered.connect(_solo_button.grab_focus)
	row.add_child(_solo_button)

	var host_label := Label.new()
	host_label.text = "host"
	row.add_child(host_label)
	_host.text = "localhost:%d" % AssayProtocol.DEFAULT_PORT
	_host.custom_minimum_size = Vector2(240.0, 0.0)
	_host.tooltip_text = "host, host:port, or [v6]:port. A bare address uses 7777."
	row.add_child(_host)

	var name_label := Label.new()
	name_label.text = "name"
	row.add_child(name_label)
	_name.text = OS.get_environment("USER")
	_name.custom_minimum_size = Vector2(140.0, 0.0)
	row.add_child(_name)

	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(_on_join)
	row.add_child(join)

	_status.position = Vector2(24.0, 54.0)
	add_child(_status)
	_detail.position = Vector2(24.0, 74.0)
	add_child(_detail)

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
	# `COLUMN_TOP`, NOT `MARGIN.y`: the header band spans the map's width, not the window's, so the
	# column starts at the top of the window and the 347 x 96 of empty chrome in the corner becomes
	# clip. See `AssayHud.COLUMN_TOP` for the measurement and for why that rectangle gets no label.
	chrome.position = Vector2(VIEW.x - PANEL - MARGIN.x, AssayHud.COLUMN_TOP)
	chrome.size = Vector2(PANEL, VIEW.y - AssayHud.COLUMN_TOP - 24.0)
	chrome.add_theme_constant_override("separation", 6)
	add_child(chrome)
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

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chrome.add_child(scroll)
	_scroll = scroll
	var column := VBoxContainer.new()
	# NO `PANEL` FLOOR ON ANYTHING IN HERE ANY MORE, and it was not tidying (ASSA-117, box 4). A
	# `ScrollContainer` with a vertical scrollbar hands its child the panel MINUS the scrollbar, and
	# a 320px floor inside a ~308px viewport is content wider than the box that holds it -- with
	# `SCROLL_MODE_DISABLED` horizontally, the overflow is simply clipped. That is ASSA-98's bug one
	# level up: the row was fixed to derive its width and then the column it sits in was still told
	# a number. `EXPAND_FILL` is the derivation, and the sections below inherit a `VBoxContainer`
	# child's default FILL, so none of them needs a width of its own either.
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	# **A SECTION MAY NOT SIT ABOVE THE SECTION IT IS DERIVED FROM** (ASSA-133, Maren's ruling 2).
	# The crafting menu is generated from your pack -- `debug::make_offers` iterates your stacks --
	# and it grows FASTER than its source: one stack of refined produces five part rows plus a gear.
	# Maren measured it on the real window: across one craft session `make` grew +198px and pushed
	# `you` 148px past the BOTTOM of the window, mid-row, during the one minute you are crafting from
	# the pack it was built out of. A derived list that outgrows its source and sits on top of it will
	# always be the thing that pushes the source off the bottom.
	#
	# So the order is you -> do -> make -> bench -> rocks -> cursor -> event log, and `make` is built
	# in the loop below with the others instead of by hand ahead of them. `do` keeps its place above
	# `make` because it is derived from the TILE, not from the pack, and it is 51px.
	#
	# THE RUNNING CRAFT IS NO LONGER HERE AT ALL. It was the head of this menu; it is now a line in
	# the chrome's running block with mining and assaying (ruling 1, and `_running` above).
	#
	# WHAT THIS DOES NOT FIX, in Maren's words, so a green shot is not read as a solved column: every
	# menu row wraps to two lines because it repeats the material, and the panel still wants ~1746px
	# in a 566px clip. The reorder moves the loss to the section that can afford it; it does not
	# remove it.
	_make_toggle.pressed.connect(func(): _show_make(not _make_shown))
	# "event log", NOT "last tick" (Maren, ASSA-116 finding 4b/4c). Two defects in one word: the
	# switch offered an "event log" and the section called itself something else, so even having
	# scrolled to it you would not know you had found what you asked for -- and `LOG_LINES` keeps the
	# last fourteen LINES, which span many ticks, so the old heading named a time window the content
	# never had. A heading is this client's word; the LINES in it stay the sim's (ASSA-80/93).
	# WHICH KIND OF EMPTY THE `cursor` SECTION IS (Maren's ruling, ASSA-134). Every other section in
	# this column plants its own empty note from its `_refresh_*`, but `cursor` is a bare Label written
	# straight from `_refresh` -- which RETURNS before it on every not-joined path, so the heading sat
	# over a blank Label on the first screen a stranger sees. Maren measured it at 93px, the largest
	# labelled void in the column, and `_note`'s own docstring is the rule it broke.
	#
	# SET HERE, ONCE, because there is no `_refresh_cursor` to derive it in and inventing one for a
	# single Label would be two places that have to agree about one sentence. The limit that leaves:
	# if a joined world STOPS, this keeps its last tile reading rather than returning to this line --
	# the sentence `_detail` prints in that case ("no world is being simulated") is the surface that
	# says so, and a frozen readout beside it is stale, not wrong.
	_cursor.text = AssayHud.quiet_cursor_line()
	# EVERY SECTION IN ONE LIST, IN THE ORDER MAREN RULED. `make` used to be built by hand above this
	# loop because it is the only section with more than one body -- the chosen-parts box, its toggle
	# and the rows. A section whose ORDER is the whole point of the item should not be the one section
	# whose position is written somewhere else, so the loop takes a list of bodies and `make` joins it.
	var sections: Array[Array] = [
		["you", [_carrying] as Array[Control]],
		["do", [_actions] as Array[Control]],
		["make", [_assembling, _make_toggle, _make] as Array[Control]],
		["bench", [_bench] as Array[Control]],
		["rocks", [_species] as Array[Control]],
		["cursor", [_cursor] as Array[Control]],
		["event log", [_log] as Array[Control]],
	]
	for part in sections:
		var heading := Label.new()
		heading.text = String(part[0])
		heading.theme_type_variation = &"Heading"
		column.add_child(heading)
		var bodies: Array[Control] = part[1]
		# HELD, BECAUSE A HIDDEN SECTION WITH A VISIBLE HEADING IS A LABELLED EMPTY GAP. The headings
		# are otherwise anonymous on purpose; this is the only one anything else has to reach.
		if bodies.has(_log):
			_log_heading = heading
		for body in bodies:
			if body is Label:
				(body as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(body)
	# HIDDEN ON FIRST OPEN, and this is the line the whole item is about.
	_show_log(false)
	# BOTH CHROME BLOCKS DRAWN ONCE AT BUILD, so the screen a stranger sees before any refresh is the
	# empty one. A `PanelContainer` is visible by default, and `_refresh_*` only rebuilds when the
	# shape CHANGES -- so without this the block starts visible-and-empty on the join screen, which
	# is the labelled-empty-gap defect ASSA-134 spent a whole item on.
	_refresh_halt()
	_refresh_running()
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
## AND SHOWING IT MOVES THE VIEW TO IT (ASSA-117). Maren verified in code what two screenshots had
## shown her: `_show_log` set two `visible` flags and nothing else, `ensure_control_visible` appeared
## nowhere in this file, and the log is the LAST section of a column that is 2023px tall in a 720px
## window. So the toggle reported success, the button's label changed to "hide the event log", and
## not one line was anywhere on screen -- the board's "logs are hard on the eyes" describing
## something they could at least see. Her ruled property, which is the one this line answers: **a
## control that reveals something must leave that thing visible.**
##
## THE HEADING AND NOT THE BODY, so what you scroll to is the word you pressed for. Scrolling to the
## body alone can leave its own heading one line above the top edge, which is a section you have
## arrived at without being told you have.
func _show_log(shown: bool) -> void:
	_log_shown = shown
	_log.visible = shown
	if is_instance_valid(_log_heading):
		_log_heading.visible = shown
	_log_toggle.text = "hide the event log (L)" if shown else "show the event log (L)"
	# ASKED FOR HERE, CARRIED OUT A FRAME LATER, AND THAT IS NOT TIDINESS (ASSA-117). I called
	# `ensure_control_visible` on this line first and the real window said it did nothing: the
	# section was still 667px below the bottom edge. A container lays its children out on the frame
	# AFTER they change, so at this instant the heading's rect is the one it had while hidden, and
	# the scroll box honoured that rect exactly. This is the third time this week I have reached for
	# an engine call at the only moment it cannot work -- `grab_focus` inside `_initialize` was the
	# same shape -- and the only reason I caught it is that `window_shot.gd` reports the section's
	# rect against the window instead of asking the node whether it is visible.
	_scroll_to_log = shown


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
	elif key.keycode == KEY_M:
		_show_make(not _make_shown)
	elif key.keycode == KEY_V:
		_show_close_up(not _close_up)


## MOVE THE VIEW TO THE LOG, ONE FRAME AFTER THE PRESS THAT ASKED FOR IT.
##
## IN `_process` RATHER THAN `call_deferred`, because a Container's own layout is ALSO deferred
## (`queue_sort`), so a deferred call races it and the race is invisible when it is lost -- the
## scroll box honours a stale rect and reports success. The next `_process` is after that layout
## pass, which is the cheapest moment that is certainly late enough.
##
## ONE SHOT. Re-running it every frame would fight the player's own scrollbar: you would press L,
## look at the log, drag away to the pack, and be dragged back.
func _carry_out_the_scroll_to_the_log() -> void:
	if not _scroll_to_log:
		return
	_scroll_to_log = false
	if _scroll == null or not is_instance_valid(_log_heading):
		return
	# PUT THE HEADING'S TOP AT THE VIEWPORT'S TOP, by the distance between them, measured now.
	#
	# **TWO `ensure_control_visible` CALLS IN A ROW CANNOT DO THIS, AND I SHIPPED THAT VERSION.** It
	# asked for the body (minimum scroll down, body's end in view) and then for the heading (minimum
	# scroll back up), on the reasoning that two minimum scrolls in opposite directions land the
	# heading at the top. The reasoning is right about the rects and wrong about WHEN they exist:
	# `set_v_scroll` does not move a child's `get_global_rect()` until the scroll box re-lays its
	# contents, so the SECOND call measures the heading where it was BEFORE the first call scrolled.
	# On a column 2019px tall it therefore asks to scroll down again, the engine clamps it to the
	# maximum, and the view sits exactly where the body-only call left it. Measured on both pinned
	# seeds: `scrolled to 1453 of 1453, heading y -18..4` against a viewport of y 130..696 -- the
	# heading one line ABOVE the top edge and the newest log line torn in half.
	#
	# That is the third engine call I have made at the only moment it cannot work, and the first one
	# I shipped: `window_shot.gd`'s fold report measured sections against the WINDOW, so a section
	# scrolled up under the chrome read `on screen`. The report is clip-rect-aware now and carries the
	# verdict (`_reveal_report`), which is why this is a bug with a lever rather than a screenshot
	# somebody squints at.
	#
	# ARITHMETIC, THEN, AND SAID OUT LOUD: one subtraction between two rects read in the same frame,
	# after the layout pass that `_process` guarantees. No number is written down -- both sides are
	# measured -- and the engine clamps the result, so a log too short to reach the top simply stops
	# where the content does.
	_scroll.scroll_vertical += int(
			_log_heading.get_global_rect().position.y - _scroll.get_global_rect().position.y)


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
		_say("already joining; restart the client to start a world of your own",
				AssayHud.Say.FAILED)
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
func _process(_delta: float) -> void:
	_carry_out_the_scroll_to_the_log()
	# THE SCENE IS THE ONLY THING ON THIS SCREEN THAT MOVES BETWEEN TICKS, so it is the only thing
	# that redraws per frame: a body tweening between two tiles the sim produced, and two gaits
	# running off the wall clock. The schematic does not redraw here -- it is painted when a tick
	# lands, which is every state it has.
	if _close_up and _sim.running():
		_refresh_world()
	if _solo == null or _solo.address != "" or _solo.failure != "":
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


## THE JOIN BUTTON: the address is whatever is in the box, and only this path reads the box.
func _on_join() -> void:
	_join_address(_host.text)


## JOIN ONE ADDRESS. The only caller that reads `_host` is `_on_join`; solo passes the address its
## own relay reported, which is what keeps a typed host untouched (Maren, ASSA-113).
func _join_address(address: String) -> void:
	if _client.stage != AssayNetClient.Stage.IDLE and _client.stage != AssayNetClient.Stage.DEAD:
		_say("already joining; restart the client to change host (no reconnect in the demo)",
				AssayHud.Say.FAILED)
		return
	# SAID BEFORE THE CALL, not after it: `join` does reach a socket, and a button that shows nothing
	# until the answer comes back reads as a dead button. Maren's ruling, and she had the premise
	# slightly wrong -- `join` already emits a "connecting to ..." note of its own -- but only on the
	# path where `connect_to_host` succeeds, so this is the line that is true either way.
	_say("connecting to %s…" % address, AssayHud.Say.CONNECTING)
	_client.join(address, _name.text if _name.text != "" else "player")


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
func _remember_events() -> void:
	var tick := _sim.tick()
	for line in _sim.event_lines(_client.player_id):
		_events.append("%d · %s" % [tick, line])
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
## CHRONOLOGY SURVIVES BECAUSE EVERY LINE ALREADY CARRIES ITS TICK (`_remember_events` prefixes
## "%d · "), so the order is a presentation of a sequence that is still legible either way. That is
## the one thing that makes this cheap rather than confusing, and if the tick prefix ever goes, this
## decision has to be made again.
##
## THE INKS COME OUT OF THE THEME, NEVER OUT OF THIS FILE. `get_theme_color` asks the theme actually
## in force (`gui/theme/custom`, ASSA-116), so Maren's corrected ruling 3 holds by construction: the
## client gains no 22nd `Color` literal, and a palette change in `tools/build_theme.gd` moves this
## ramp with it. `build_theme.gd` refuses to write a theme whose own inks miss WCAG AA on its
## surface, and the ramp is the straight segment between them, so no step on it can be unreadable.
func _rebuild_log() -> void:
	_clear(_log)
	if _events.is_empty():
		# WHICH KIND OF EMPTY. A blank section reads as a game with nothing to say; this one says the
		# world has not spoken yet. Same reason the pack and the bench name their own emptiness.
		_log.add_child(_note(AssayHud.quiet_log_line()))
		return
	var ink := _log.get_theme_color(&"font_color", &"Label")
	var muted := _log.get_theme_color(&"font_color", &"Muted")
	var count := _events.size()
	for age in count:
		# `_events` is oldest-first (`trimmed_log` keeps the tail), so age 0 is the LAST entry.
		var line := _note(_events[count - 1 - age])
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
	var shape := "\n".join(lines)
	if shape == _halt_showing:
		return
	_halt_showing = shape
	_rebuild_halt(lines)


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
func _rebuild_halt(lines: PackedStringArray) -> void:
	_clear(_halt)
	_halt_lines = null
	if is_instance_valid(_halt_box):
		_halt_box.visible = not lines.is_empty()
	if lines.is_empty():
		return
	# "stopped" IS THIS CLIENT'S HEADING, the way "you", "do" and "event log" are; the lines under it
	# are the sim's words. A count would be a second claim about the world and the sim already makes
	# it (`halted_table`'s "N of M buildings stopped") -- one this block would have to keep true.
	var heading := Label.new()
	heading.text = "stopped"
	heading.theme_type_variation = &"Heading"
	_halt.add_child(heading)
	# THE LINES IN THEIR OWN BOX, so "the lines of this block" is a container and not a filter over
	# one. See the note on `STACK_LINE` for why they cannot be named instead.
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	_halt_lines = rows
	_halt.add_child(rows)
	for line in lines:
		rows.add_child(_note(line))


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
	_status.text = line
	_status.modulate = AssayHud.status_color(level)
	print(line)


func _refresh() -> void:
	if not _sim.running():
		var joined: Dictionary = _client.joined_world
		if joined.is_empty():
			return
		_detail.text = ("joined at tick %d, but no world is being simulated: %s"
				% [int(joined.get("tick", -1)), _sim.fail_reason])
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
	# WHICH WORLD, WHICH TICK, WHICH HASH. The seed and the hash are TEXT, because a u64 cannot
	# survive a GDScript number -- that is not caution, it is measured. The bundle and hash counts are
	# here because a client that has stopped applying bundles looks exactly like one that is idle.
	var size := _sim.size_tiles()
	# WHERE A CLICK LANDS, WORKED OUT WITHOUT PAINTING ANYTHING. See `_cell`. The scene's half of the
	# same promise is `_refresh_world`'s camera, built on the same tick and for the same reason.
	_cell = AssayHud.map_cell(size)
	_refresh_world()
	_detail.text = ("world seed %s, %d x %d tiles, %d species, %d players · tick %d, hash %s · "
			+ "%d bundles applied, %d hashes reported") % [
			_sim.seed_text(), size.x, size.y, _sim.species_names().size(), _sim.players().size(),
			_sim.tick(), _sim.hash_hex(), _sim.applied, _hashes_sent]
	_refresh_make()
	_refresh_assembling()
	_refresh_pack()
	_refresh_actions()
	_refresh_bench()
	_refresh_species()


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
	if sheets.is_empty():
		_species.add_child(_note("no world yet — join one and its rocks are listed here"))
		return
	for entry in sheets:
		_species.add_child(_species_row(entry as Dictionary))


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
		_bench.add_child(_note(AssayHud.no_designs_line()))
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
## SAME SIGNATURE RULE AS THE PACK, and the fast path matters MORE here: every row's sentence carries
## "of your N", which climbs every mining cycle. The shape is what a row IS (its catalogue row and its
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
func _make_shape(offers: Array) -> String:
	var shape := PackedStringArray()
	for entry in offers:
		var offer: Dictionary = entry
		var makes: Dictionary = offer.get("makes", {})
		shape.append("%s/%s/%s/%d/%s/%s/%d/%s" % [String(offer.get("verb", "?")),
				JSON.stringify(offer.get("tag")), String(offer.get("kind", "?")),
				int(offer.get("species", -1)), String(offer.get("grade", "?")),
				String(makes.get("kind", "-")), int(makes.get("species", -1)),
				String(makes.get("grade", "-"))])
	return "|".join(shape)


func _rebuild_make(offers: Array) -> void:
	_clear(_make)
	if offers.is_empty():
		_make.add_child(_note(AssayHud.nothing_to_make_line()))
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
		# block and the sentence names it in words ("2 of your 8 Tonore refined"), so the icon spends
		# its 32px on the half the player cannot otherwise see.
		#
		# `makes` IS THE SIM'S, out of `make_offers`, and absent on a row that makes nothing (`sort`
		# on grade A) -- so `{}` is the honest argument there and `_icon_box` returns null for it,
		# the same way it does for a gear.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var slot := _icon_box(offer.get("makes", {}) as Dictionary)
		if slot != null:
			row.add_child(slot)
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
		var line := _note(String(offer.get("line", "")))
		line.name = MAKE_LINE
		body.add_child(line)
		# ASSA-84'S CLAUSE, CARRIED AND NOT REWRITTEN (Maren's ruling here: a recipe row is a better
		# home for it than a button tooltip). Still the sim's own sentence, still empty unless the sim
		# says so, and still nothing in this client that names a gear.
		var dead_end := String(offer.get("dead_end", ""))
		if dead_end != "":
			body.add_child(_note("— %s" % dead_end))
		# MAREN'S WALLS CLAUSE (ASSA-125), APPENDED AND NEVER COMPOSED, by the same route and for the
		# same reason: a smelter's walls are its material's heat tolerance, and what the player may
		# know of that is a band until they assay. The sim words it; this client would have to decide
		# how to say "somewhere between 50 and 74" and would be deciding a rule.
		var walls := String(offer.get("walls", ""))
		if walls != "":
			body.add_child(_note("— %s" % walls))
		body.add_child(_verb_row([offer], func(descriptor: Dictionary) -> Button:
				return _make_button(descriptor)))
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
func _icon_box(stack: Dictionary) -> Control:
	# THE ICON IS REDUNDANT AND MOST ROWS DO NOT GET ONE. `items.png` carries ore, refined and
	# smelter, so a gear comes back null; the four part kinds have a row per grade. Every sentence
	# beside one of these reads completely without it, which is Maren's rule and the same one the
	# species glyph carries: a redundant cue promoted to the only cue is no longer redundant.
	var icon := AssaySprites.icon_for(stack)
	if icon == null:
		return null
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
	var signature := "%s/%s/%d/%s" % [target, _targeted, at, _building]
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
	here.add_child(_button("Mine", func() -> void: _act("Mine", AssayActions.mine()),
			"hand-mine the deposit under you. Keeps swinging until you Stop."))
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
## It says what it sent, because a button that shows nothing reads as a dead button (Maren's ruling
## on Join, and the same argument applies here). It does not predict: the world changes when a bundle
## carrying this command comes back around and the sim steps, which for the player's own action is
## about a tick later.
func _act(what: String, command: Variant) -> void:
	if _client.submit(command):
		_say("%s · submitted at tick %d" % [what, _sim.tick()], AssayHud.Say.JOINED)
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
## `sim/src/debug.rs:1785` says so in writing: *"Verdict first, then the numbers, then the parts.
## Deliberate: a side panel is narrow and the line gets truncated, so the thing the player needs
## before spending parts must not be the thing that is cut."* A design verdict became SIX rows here,
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
func _refresh_world() -> void:
	if not _sim.running():
		_world.view = {}
		_world.me = null
		_world.queue_redraw()
		return
	if _manifest.is_empty():
		_manifest = AssaySprites.manifest()
	var size := _sim.size_tiles()
	var now := float(Time.get_ticks_msec()) / 1000.0
	# HOW FAR THROUGH THE GAP BETWEEN THE LAST TWO TICKS WE ARE. Clamped at 1, which is the whole
	# safety of the thing: past the end of a gap the body stops on the newest position the sim
	# produced rather than carrying on toward one it has not. 1.0 before any tick has landed, so an
	# unplayed world draws everyone exactly where the Welcome put them.
	var part := 1.0
	if _tick_at > 0.0:
		part = clampf((now - _tick_at) / maxf(_tick_gap, 0.01), 0.0, 1.0)
	var players: Array = []
	var me: Variant = null
	for entry in _sim.players():
		var player: Dictionary = entry
		var id := int(player.get("id", -1))
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
	var origin := AssayScene.camera_origin(me if me != null else Vector2(_sim.spawn_tile()),
			size, _world.size)
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
		"seconds": now,
	}
	_world.me = me
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
	_was = _seen
	_seen = {}
	for entry in _sim.players():
		var player: Dictionary = entry
		var id := int(player.get("id", -1))
		var at: Vector2i = player.get("pos", Vector2i.ZERO)
		_seen[id] = at
		if _was.has(id):
			var way := AssayScene.facing_of(at - (_was[id] as Vector2i))
			if way != "":
				_facing[id] = way
	var now := float(Time.get_ticks_msec()) / 1000.0
	if _tick_at > 0.0:
		# SMOOTHED, because the gap between two bundles is a network measurement and a single late
		# packet should not stretch one step across half a second. A quarter weight settles on a
		# changed rate in a handful of ticks and ignores one hiccup.
		_tick_gap = lerpf(_tick_gap, clampf(now - _tick_at, 0.01, 1.0), 0.25)
	_tick_at = now


func _my_tile() -> Vector2i:
	for entry in _sim.players():
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


## THE WHOLE-WORLD SCHEMATIC: bounds, every deposit, every player, and spawn. THE SECOND VIEW NOW.
##
## THE SPRITES ARE DRAWN, AND THEY ARE NOT DRAWN HERE. ASSA-119 is the camera at 32 px a tile, and it
## lives in `AssayScene` + `AssayWorldLayer` over the same rectangle this paints -- `_close_up` says
## which of the two is up. This function is the one that fits a 96x64 world into 912x600, which is
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
	draw_rect(Rect2(MARGIN, Vector2(size) * _cell), AssayHud.MAP_BG, true)

	var spawn := _sim.spawn_tile()
	draw_rect(Rect2(MARGIN + Vector2(spawn) * _cell - Vector2(_cell, _cell) * 2.0,
			Vector2(_cell, _cell) * 4.0), AssayHud.SPAWN_PAD, true)

	# SPECIES IS A DESIGNED SLOT, PURITY IS BRIGHTNESS, and the rule plus the two versions of this I
	# got wrong are in `AssayHud.deposit_color`. Grade bands (C < 40, B 40-69, A >= 70) are the
	# sim's, not invented.
	#
	# AND COLOUR IS NOT THE ONLY READ: the species' letter goes on the patch, once per deposit
	# (Decision #36). The tints clear the colour-blindness floor by single digits, so for the ~8% of
	# men with a red-green deficiency the glyph is the read and the colour is the hint. `symbol`
	# comes from the sim -- a generated name's initial, distinct per world -- never from the first
	# character of a name a player may have renamed.
	var font := ThemeDB.fallback_font
	for entry in _sim.deposits():
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) <= 0:
			continue
		var at := MARGIN + Vector2(deposit.get("center", Vector2i.ZERO) as Vector2i) * _cell
		var radius := maxf(_cell, float(int(deposit.get("radius", 1))) * _cell)
		var colour := AssayHud.deposit_color(int(deposit.get("species", 0)),
				int(deposit.get("purity", 1)))
		draw_circle(at, radius, colour)
		var symbol := String(deposit.get("symbol", ""))
		var glyph := AssayHud.glyph_size(radius)
		if glyph > 0 and not symbol.is_empty() and font != null:
			# Centred by measurement, not by a guessed offset: the width is the font's and the
			# vertical nudge is the usual "half the cap height" for a baseline-drawn capital.
			var wide := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph).x
			draw_string(font, at + Vector2(-wide * 0.5, float(glyph) * 0.36), symbol,
					HORIZONTAL_ALIGNMENT_LEFT, -1, glyph, AssayHud.glyph_color(colour))

	# EVERY PLAYER, AT A SIZE THAT DOES NOT COME FROM THE TILE (ASSA-119 box 6, Maren's finding 1).
	# This mark used to be two cells square, which made it 18 px on this world and would make it 36 on
	# a small one -- so the bigger and more confusing the world, the smaller you got. Measured on the
	# real shot: 324 px of an 864x576 view, 0.065% of it, smaller than all eleven deposits and twelve
	# times smaller than one pink patch. `AssayHud.PLAYER_MARK_PX` now says how big a person is on any
	# world, and yours carries a ring so two players at the same size are still told apart.
	var mark := Vector2(AssayHud.PLAYER_MARK_PX, AssayHud.PLAYER_MARK_PX)
	for entry in _sim.players():
		var player: Dictionary = entry
		var at := MARGIN + (Vector2(player.get("pos", Vector2i.ZERO) as Vector2i)
				+ Vector2(0.5, 0.5)) * _cell
		var mine := int(player.get("id", -1)) == _client.player_id
		var colour := AssayHud.MINE if mine else AssayHud.THEIRS
		# Where the sim is walking them, drawn as a line to there. Not a tween: the sim owns the
		# position and this is its intention, not a frame of motion we invented. (The scene DOES
		# tween the body, between two positions the sim produced -- Maren's motion ruling -- and this
		# line stays a line there for the same reason it is one here.)
		var target: Variant = player.get("target")
		if target != null:
			draw_line(at, MARGIN + (Vector2(target as Vector2i) + Vector2(0.5, 0.5)) * _cell,
					Color(colour.r, colour.g, colour.b, 0.35 if mine else 0.25), 1.0)
		draw_rect(Rect2(at - mark * 0.5, mark), colour, true)
		if mine:
			draw_rect(Rect2(at - mark * 0.8, mark * 1.6), colour, false, 2.0)

	# THE TILE THE BUTTONS ACT ON, AND IT IS A SHAPE NOW, NOT A THINNER YOU (ASSA-119 box 6).
	#
	# MAREN CORRECTED HERSELF ON THIS ONE AND THE CORRECTION IS THE INTERESTING HALF. She defended the
	# shared yellow in the morning -- you, your walk line and your target are one meaning, "yours", at
	# three weights, and the old comment here said so on purpose -- then measured the shot: at 9 px a
	# tile the weights are indistinguishable and a solid 18 px square beside a hollow 9 px one reads
	# as two of something. So the target keeps the tile it marks and loses the hue: four corner
	# brackets in the neutral ink, which cannot be mistaken for a body at any tile size, and no 22nd
	# colour literal added to the 21 she counted.
	if _targeted:
		var corner := MARGIN + Vector2(_target) * _cell
		var reach := maxf(4.0, _cell * 0.45)
		for step in [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)]:
			var from := corner + Vector2(0.0 if step.x > 0.0 else _cell,
					0.0 if step.y > 0.0 else _cell)
			draw_line(from, from + Vector2(reach * step.x, 0.0), AssayHud.HOVER, 2.0)
			draw_line(from, from + Vector2(0.0, reach * step.y), AssayHud.HOVER, 2.0)

	# The tile the readout is talking about, outlined. Drawn last so it is never buried, and only
	# while the mouse is actually over the map -- an outline left behind would point at an answer the
	# panel is no longer giving.
	if _hovering:
		draw_rect(Rect2(MARGIN + Vector2(_hover) * _cell, Vector2(_cell, _cell)),
				Color(AssayHud.HOVER.r, AssayHud.HOVER.g, AssayHud.HOVER.b, 0.55), false, 1.0)
