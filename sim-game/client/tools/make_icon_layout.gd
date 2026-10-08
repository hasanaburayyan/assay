extends SceneTree
## CI: gated -- art/check_make_icon_scale.py drives it
## WHAT SIZE IS A **CRAFTING ROW'S** ICON REALLY DRAWN AT (ASSA-306, the open half of ASSA-116 box 3)?
##
##   godot --headless --path . --script res://tools/make_icon_layout.gd [-- seed]
##
## `art/pack_icon_layout.gd` has asked this of PACK rows since ASSA-65 and nothing has ever asked it
## of the crafting menu. The two arguments offered in place of a measurement were:
##
##  1. the menu calls the same `_icon_box` as the pack, so the scale is right by construction;
##  2. `test_buttons.gd` reads `first.custom_minimum_size.x` back.
##
## **THE FIRST IS THE EXACT ARGUMENT `check_pack_icon_scale.py` REJECTS BY NAME** -- *"would pass by
## construction and would survive Godot changing its layout rules"* -- and ASSA-65's defect was a
## CONTAINER defect, not a property one: a `TextureRect` in an `HBoxContainer` FILLS, so the rect
## became 32 x whatever-the-row-was and an ore came out at 15/32. A make row is a different container
## shape from a pack row (ASSA-247 put the sentence and its one verb on a line inside a VBox inside
## the row), so "same function" says nothing about it. The second reads back the property `main.gd`
## set, in a suite whose own docstring says it runs in `SceneTree._initialize` before any layout
## pass: no pixel claim is possible there at all.
##
## So this stands the real screen up, PLAYS THE REAL LOOP, lets layout settle and prints what the
## engine laid out -- for BOTH row kinds, in one process, so "one box wherever it sits" can be asked
## across the two lists instead of within one.
##
## **THE OFFERS ARE THE SIM'S AND THE PACK IS THE LOOP'S.** Nothing here types a row. `make_offers`
## needs a player holding something, so a fresh world's menu says "nothing to make" and measures
## nothing; the offline session is how a probe gets a pack without inventing one. Seed 777042 on
## purpose: it is the seed `pack_icon_layout.gd`'s stacks were copied from, so the two halves of box 3
## speak about the same world.
##
## **WHAT IT REFUSES RATHER THAN MEASURES, and both have bitten me:**
##  - A FOLDED MENU. `_show_make(false)` collapses the rows' rects, and on 10-06 I delivered a 1x shot
##    whose crafting menu was folded: Godot had collapsed its rect onto the heading above it and
##    everything I measured through it was about five rows nobody could see. The default is
##    `_show_make(true)` from `_build_ui`, so this REPORTS `make_shown` instead of setting it -- the
##    day that default changes, the check says NO VERDICT rather than scoring collapsed boxes.
##  - A HIDDEN COLUMN. ASSA-231 Gap 5 hides the whole HUD column until a world exists. This probe has
##    a world, so the column should be visible on its own; `pack_icon_layout.gd` has to force it
##    because it never joins one. Forcing it here would hide a Gap-5 regression, so this reports it.
##
## Not `--headless`-shy, unlike `window_shot.gd`: this asks what the client KNOWS about its own
## layout, and the headless server has a full layout pass. Only the question "what does it LOOK like"
## needs a real window.

const RUN_CEILING := 180.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

## The seed `art/pack_icon_layout.gd`'s stacks came out of. See the docstring.
const SEED := "777042"
## The offline session's own cap, `button_session.gd`'s number. The showcase plan finishes near tick
## 480, so this is room and not a budget.
const PLAY_TICKS := 4000
## Frames to let layout settle before reading a rect. `pack_icon_layout.gd` uses the same count for
## the same reason: the first frames are the engine still deciding.
const SETTLE_FRAMES := 6
## How much a row that can FALSIFY the claim is worth against one that merely exists. Bigger than
## any row count this loop reaches, so it is a priority and not a thumb on the scale. See `_rows_now`.
const FALSIFIABLE_WEIGHT := 1000
## **THE WINDOW THE PROJECT DECLARES**, so the column is its real width while the rows are measured.
## `--script` gives the root viewport 100x100 and the engine shrinks it to **64x64 on the first
## frame**, in which a make row is 95 px wide and its sentence wraps to 1361 px of height -- a layout
## nobody will ever see. The icon's own box survives that (it is a `custom_minimum_size`), which is
## why `pack_icon_layout.gd` has got away with never setting it, but **a make row's height is a
## function of how its sentence wraps, and the height is what ASSA-65's bug moved**: measured in a
## 64 px window, every row is far TALLER than the icon and `min(w/fw, h/fh)` is pinned by the width,
## so a FILLing icon would report the right scale and this check would pass over the bug it exists
## for. I measured that before fixing it.
##
## SET IN `_process` AND NOT IN `_initialize`, because the engine undoes it on frame one -- and then
## CHECKED at measurement time, so the day it stops sticking this says NO VERDICT instead of scoring
## a 64 px layout. Read out of `ProjectSettings` rather than typed: the day the client ships at
## another size, this follows it.
const SETTINGS_W := "display/window/size/viewport_width"
const SETTINGS_H := "display/window/size/viewport_height"

var _screen: Node = null
var _seed := SEED
var _frames := 0
var _quitting := false
## The best score seen so far and the tick it was seen on, per question. See `_find_the_moments`.
var _best: Dictionary = {}
## `[{"label": ..., "tick": ...}, ...]`, in play order. See `_find_the_moments`.
var _moments: Array = []
var _moment := 0


## **THE MOMENT WORTH MEASURING IS NOT THE END OF THE PLAY, AND IT IS NOT THE FULLEST ONE EITHER.**
##
## The loop spends what it makes: at tick 481 this player holds nothing and the menu says "nothing
## you are carrying can be worked", so a probe that measured the final state would measure no
## crafting rows at all. `window_shot.gd` has the same problem and the same answer for
## `04-pack.png`: *a moment the tool notices, found by the play and not chosen by me*.
##
## **THEN THE FULLEST MOMENT TURNED OUT NOT TO BE ABLE TO FAIL, AND I FOUND THAT THE RIGHT WAY -- BY
## MUTATING THE CLIENT AND WATCHING THE CHECK STAY GREEN.** Tick 462 is five crafting rows, four of
## them drawn, and taking `SIZE_SHRINK_CENTER` off the slot so the icon FILLS its row changed nothing
## there: on that tick every row carrying art is exactly `ICON_BOX_PX` tall, because the icon is the
## tallest thing in it. The one taller row was the gear, which has no art. A moment where the bug is
## invisible is a green that costs more than no check.
##
## So two moments, each the best the play offers for one question, and the check scores each claim
## where that claim could fail:
##
##  - `falsifiable`: a row that carries art AND is taller than the icon box, which is what a walls or
##    dead-end clause does. This is the moment the SCALE claim is measured on.
##  - `fullest`: the most rows the two panels ever hold at once. The moment the RESERVED box
##    (ASSA-240) is measured on -- the gear row only exists late, and no tick of this seed's loop
##    carries a reserved row and a tall drawn row at the same time. I scanned every tick to find that
##    out rather than assuming it.
##
## **YOU CANNOT KNOW A HIGH-WATER MARK HAS BEEN REACHED UNTIL IT STOPS RISING**, so one pass plays
## the whole loop to find the ticks and the frame loop replays to each. **Every replay asserts it saw
## the same score at the same tick**, which turns "the loop is deterministic" from something I
## believe into something this probe reports: if the plan ever stops being a pure function of the
## world, this says so instead of measuring a different moment than it names.
##
## Every score is read off the SIM (`make_offers`, `inventory_of`, `AssaySprites.icon_for`), never
## off the panels, for `window_shot.gd`'s reason: the panels are the thing under test, so asking them
## how many rows they have is asking the thing under test.
func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else SEED
	if not _play_offline(-1):
		_quitting = true
		quit(1)
		return
	_find_the_moments()
	if _moments.is_empty():
		print(("FAIL  no tick of the play had a crafting row on it, so there is nothing to measure. "
				+ "The loop on seed %s never held anything workable.") % _seed)
		_quitting = true
		quit(1)


## The two ticks worth replaying to, in play order, each with the score that named it. A question
## whose score never rose above zero contributes no moment: the check is told which questions were
## measured and refuses the ones that were not, rather than being handed a moment that cannot answer.
func _find_the_moments() -> void:
	var found: Array = []
	for label in SCORES:
		var seen: Dictionary = _best.get(label, {})
		if int(seen.get("score", 0)) <= 0:
			continue
		found.append({"label": label, "tick": int(seen["tick"]), "score": int(seen["score"])})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tick"] < b["tick"])
	_moments = found


## PLAY THE LOOP, OFFLINE: this script is the relay. Lifted from `button_session.gd::_run_offline`,
## including the thing I would have got wrong -- A BUNDLE IS NUMBERED WITH THE TICK WE ARE AT, not
## the one it produces.
##
## `stop_at` of -1 plays to the end and only records the high-water ticks; any other value plays
## until the world is at that tick and leaves the screen standing there.
##
## A FRESH SCREEN EVERY TIME, AND THE OLD ONE IS FREED. A replay against a screen that has already
## been welcomed into a world is not the same play, and two live `main.tscn` under one root would
## both be laid out -- the measurement would then be of whichever one `_screen` happened to name.
func _play_offline(stop_at: int) -> bool:
	if _screen != null:
		_screen.queue_free()
		root.remove_child(_screen)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, as `button_session.gd` and `tests/test_main_screen.gd` do it: a `--script` run
	# works inside `SceneTree._initialize`, before the root window is in the tree, so the engine's own
	# call comes too late to be useful.
	_screen._ready()
	var asked: Array = []
	_screen._client.asked.connect(func(command: Variant) -> void: asked.append(command))
	var play := AssayButtonPlay.new(_screen, 0)
	var welcome := AssaySimHost.fresh_welcome_json(_seed, "marlow")
	if welcome == "":
		print("FAIL  could not make a world on seed %s" % _seed)
		return false
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		print("FAIL  the offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return false
	for _i in range(PLAY_TICKS):
		# **THE BAIL IS HERE AND IT IS NON-ZERO, rather than a `return false` the caller turns into
		# one.** `test_tool_ceilings.gd` caught exactly that and was right: a bail that unwinds
		# through two frames of someone else's code is one refactor away from exiting 0, and CI
		# reads a 0 as a pass. Measured by the suite, not by me reading it.
		if Time.get_unix_time_from_system() > _ceiling:
			print("FAIL  make_icon_layout.gd ran past its %ds ceiling inside the play loop"
					% int(RUN_CEILING))
			_quitting = true
			quit(1)
			return false
		for label in SCORES:
			var score := _score(label)
			if score > int((_best.get(label, {}) as Dictionary).get("score", 0)):
				_best[label] = {"score": score, "tick": _screen._sim.tick()}
		if stop_at >= 0 and _screen._sim.tick() >= stop_at:
			return true
		play.advance()
		if play.finished:
			break
		var inputs: Array = []
		for command in asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		asked.clear()
		var at: int = _screen._sim.tick()
		var before: int = _screen._sim.applied
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		if _screen._sim.applied == before:
			print("FAIL  the sim refused the bundle for tick %d" % at)
			return false
	if play.failed != "":
		print("FAIL  the loop did not play: %s" % play.failed)
		return false
	if stop_at >= 0:
		print("FAIL  the replay ended at tick %d without reaching tick %d"
				% [_screen._sim.tick(), stop_at])
		return false
	return true


## The window the project ships at. See `SETTINGS_W`.
func _declared_viewport() -> Vector2i:
	return Vector2i(int(ProjectSettings.get_setting(SETTINGS_W, 1280)),
			int(ProjectSettings.get_setting(SETTINGS_H, 720)))


## HOW GOOD THIS TICK IS FOR EACH QUESTION, keyed by the name the report uses. See `_initialize` for
## why there are two and why the obvious one is not enough.
##
## Every score is zero when the panel cannot answer its question at all -- a tick with no crafting
## offers scores zero however full the pack is -- so `_find_the_moments` can tell "the best moment"
## from "no moment", and the check is refused rather than passed in the second case.
##
## `AssaySprites.icon_for` is the same call `_icon_box` makes, so "will this row carry art" follows
## what the client can draw instead of asserting a roster of kinds with sheets.
const SCORES := ["falsifiable", "fullest"]


func _score(label: String) -> int:
	var player: int = _screen._client.player_id
	var offers: Array = _screen._sim.make_offers(player)
	if offers.is_empty():
		return 0
	match label:
		# A ROW THAT CARRIES ART AND IS TALLER THAN THE ICON BOX: the only shape in which a
		# vertically FILLing icon shows up as a wrong scale. A walls clause (ASSA-125) or a dead-end
		# clause (ASSA-158) is what adds the line. Row count breaks ties and nothing more.
		"falsifiable":
			var tall := 0
			for entry in offers:
				var offer: Dictionary = entry
				if AssaySprites.icon_for(offer.get("makes", {}) as Dictionary) == null:
					continue
				if String(offer.get("dead_end", "")) != "" or String(offer.get("walls", "")) != "":
					tall += 1
			if tall == 0:
				return 0
			return FALSIFIABLE_WEIGHT * tall + offers.size()
		# THE MOST ROWS THE TWO PANELS EVER HOLD AT ONCE, which is where the reserved box lives: a
		# kind with no sheet (ASSA-240). Scores zero until one of this tick's offers really has none,
		# so "fullest" cannot be chosen for a frame that could not answer the question it is for.
		"fullest":
			var reserved := 0
			for entry in offers:
				var offer: Dictionary = entry
				if AssaySprites.icon_for(offer.get("makes", {}) as Dictionary) == null:
					reserved += 1
			if reserved == 0:
				return 0
			var stacks: Array = _screen._sim.inventory_of(player)
			return offers.size() + stacks.size()
	return 0


## **ONE TAB AT A TIME, BECAUSE A HIDDEN TAB IS NOT LAID OUT -- AND THAT IS THE FINDING UNDER
## ASSA-306, not a detail of this tool.**
##
## ASSA-264 put the column's sections in tabs and `mineralogy` is the one that opens (Maren's
## argument: you enter a world carrying nothing, so `make` would open on a refusal). So `MakeBody`
## and `InventoryBody` are BOTH `visible = false` until a player presses their tab, and an invisible
## container keeps nothing but its children's MINIMUM sizes.
##
## **THAT IS WHY THE PACK HALF GOT AWAY WITH IT AND THE MAKE HALF CANNOT.** A pack row's real size
## IS its minimum -- icon, sentence, buttons, nothing expanding -- so `pack_icon_layout.gd` reads
## 48 px-tall rows out of a hidden tab and is right by luck. A make row's sentence is
## `EXPAND_FILL` and wraps, so its minimum at zero width is a column of single words: measured
## before this function existed, the five make rows came back **95 px wide and 837 to 1361 px
## tall**, and the scale scored green over all of it because `min(w/fw, h/fh)` was pinned by the
## width. A check that passes on a layout nobody can see is the same green as a blank frame.
##
## So each list is measured with its own tab OPEN, through `AssayTabStrip.select` -- the function the
## tab's own button calls -- and `visible_in_tree` is reported per list so the Python can refuse
## rather than score a collapsed one.
## THE REPLAY IS IN THE FRAME LOOP AND NOT IN `_initialize`, because a measurement needs frames: a
## moment is replayed to, then its two tabs are opened and read a settle apart, and only then is the
## next moment replayed to. Each replay re-checks the score it was sent for (see `_replay`).
enum Phase { REPLAY, SIZE, MAKE_TAB, MAKE_READ, PACK_TAB, PACK_READ }

var _phase: Phase = Phase.REPLAY
var _settling := 0
var _measured: Dictionary = {"moments": []}
var _here: Dictionary = {}


func _process(_delta: float) -> bool:
	if _quitting:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  make_icon_layout.gd ran past its %ds ceiling: nothing finished it"
				% int(RUN_CEILING))
		_quitting = true
		quit(1)
		return true
	_frames += 1
	# THE WINDOW FIRST. See `SETTINGS_W`: the engine shrinks the viewport to 64x64 on frame one, so
	# this is undone on every frame rather than once.
	root.size = _declared_viewport()
	match _phase:
		Phase.REPLAY:
			if not _replay():
				return true
			_phase = Phase.SIZE
		Phase.SIZE:
			if _settle():
				_phase = Phase.MAKE_TAB
		Phase.MAKE_TAB:
			if not _open("make"):
				return true
			_phase = Phase.MAKE_READ
		Phase.MAKE_READ:
			if _settle():
				_here["make_rows"] = _rows_of(_screen._make, "make")
				_here["make_visible_in_tree"] = _screen._make.is_visible_in_tree()
				_here["make_shown"] = _screen._make_shown
				_phase = Phase.PACK_TAB
		Phase.PACK_TAB:
			if not _open("inventory"):
				return true
			_phase = Phase.PACK_READ
		Phase.PACK_READ:
			if _settle():
				_here["pack_rows"] = _rows_of(_screen._carrying, "pack")
				_here["pack_visible_in_tree"] = _screen._carrying.is_visible_in_tree()
				_here["column_visible"] = _screen._column != null and _screen._column.visible
				_measured["moments"].append(_here)
				_moment += 1
				if _moment >= _moments.size():
					_report()
					return true
				_phase = Phase.REPLAY
	return false


## REPLAY TO THE NEXT MOMENT, and check that it is the moment it was sent for.
##
## **THIS IS WHERE "THE LOOP IS DETERMINISTIC" STOPS BEING SOMETHING I BELIEVE.** The ticks were
## found in a first play and these are fresh worlds; if the demo plan ever stops being a pure
## function of the world, the replay lands on a different state at the same tick and the probe would
## otherwise report a measurement under a label that no longer describes it.
func _replay() -> bool:
	var moment: Dictionary = _moments[_moment]
	var label := String(moment["label"])
	var at := int(moment["tick"])
	if not _play_offline(at):
		_quitting = true
		quit(1)
		return false
	var here := _score(label)
	if _screen._sim.tick() != at or here != int(moment["score"]):
		print(("FAIL  the replay is not the same play: the first pass scored %d for `%s` at tick %d, "
				+ "the replay scores %d at tick %d. The demo plan has stopped being a pure function "
				+ "of the world, so this probe can no longer name the moment it measured.")
				% [int(moment["score"]), label, at, here, _screen._sim.tick()])
		_quitting = true
		quit(1)
		return false
	_here = {"label": label, "tick": at, "score": here}
	return true


## SETTLE_FRAMES of nothing, then true once. Each phase gets its own count: a tab that has just been
## shown has a layout pass ahead of it, and reading on the frame of the press is reading the frame
## before the one the press produced -- the mistake that cost ASSA-158 a day in `window_shot.gd`.
func _settle() -> bool:
	_settling += 1
	if _settling < SETTLE_FRAMES:
		return false
	_settling = 0
	return true


## Press a tab, through the same call its button makes. Refuses loudly: a tab name that silently did
## nothing would leave the next phase measuring whatever was open instead.
func _open(tab_name: String) -> bool:
	if _screen._tabs == null:
		print("FAIL  the column has no tab strip, so there is no `%s` tab to open" % tab_name)
		_quitting = true
		quit(1)
		return false
	if not _screen._tabs.select(tab_name):
		print("FAIL  could not open the `%s` tab. The strip has: %s"
				% [tab_name, ", ".join(_screen._tabs.tab_names())])
		_quitting = true
		quit(1)
		return false
	return true


func _report() -> void:
	_measured["seed"] = _seed
	# WHICH QUESTIONS THIS RUN COULD NOT FIND A MOMENT FOR, by name. A claim whose moment never
	# occurred must reach the check as a refusal and not as silence: that is the difference between
	# "measured and fine" and "not measured", and the second one looked exactly like the first until
	# the mutation that passed.
	var unmeasured := PackedStringArray()
	for label in SCORES:
		if int((_best.get(label, {}) as Dictionary).get("score", 0)) <= 0:
			unmeasured.append(String(label))
	_measured["unmeasured"] = unmeasured
	_measured["viewport"] = [root.size.x, root.size.y]
	_measured["viewport_declared"] = [_declared_viewport().x, _declared_viewport().y]
	_measured["icon_box_px"] = [_screen.ICON_BOX_PX.x, _screen.ICON_BOX_PX.y]
	_measured["panel_px"] = _screen.PANEL
	print("LAYOUT_JSON ", JSON.stringify(_measured))


## EVERY ROW OF ONE LIST, as the engine laid it out.
##
## A ROW WITH NO ICON IS STILL A ROW, and says which of the two reasons it has none: ASSA-240 reserves
## `ICON_BOX_PX` of empty space on a row whose kind has no sheet (`gear`), so "no art" and "no column"
## are different facts and a check that could not tell them apart would read Maren's reserved gap as a
## missing icon.
func _rows_of(list: Node, kind: String) -> Array:
	var rows: Array = []
	for child in list.get_children():
		if not (child is Control):
			continue
		var row: Control = child
		var label: Label = row.find_child("StackLine", true, false) as Label
		if label == null:
			label = row.find_child("MakeLine", true, false) as Label
		var entry: Dictionary = {
			"kind": kind,
			"line": "" if label == null else label.text,
			"row_size": [row.size.x, row.size.y],
			"verbs": _verbs_in(row),
		}
		var art: TextureRect = _icon_in(row)
		if art != null and art.texture != null:
			var fw: float = art.texture.get_width()
			var fh: float = art.texture.get_height()
			var s: float = min(art.size.x / fw, art.size.y / fh)
			entry["icon"] = {
				"rect": [art.size.x, art.size.y],
				"frame": [fw, fh],
				"scale": s,
				"drawn": [fw * s, fh * s],
				"plate_rect": _plate_rect(art),
			}
		else:
			# `reserved` is ASSA-240's empty box: `ICON_BOX_PX` of nothing, so the sentence beside it
			# starts where every other sentence starts. A row with neither is one that asked for no
			# column at all, which is what every pack row of a kind with no sheet gets.
			entry["reserved"] = _reserved_gap(row)
		rows.append(entry)
	return rows


## The icon anywhere under a row, however it is wrapped -- RECURSIVELY, because ASSA-71 put it inside
## a Panel that paints the slot plate. `pack_icon_layout.gd` walked direct children only and the day
## the plate landed it stopped finding the icon at all: a check going QUIET rather than red.
func _icon_in(node: Node) -> TextureRect:
	for child in node.get_children():
		if child is TextureRect:
			return child
		var deeper: TextureRect = _icon_in(child)
		if deeper != null:
			return deeper
	return null


## The size of the reserved-but-empty box, or `[]` if this row has no icon column at all. Maren's
## ruling (ASSA-237) is that the box draws NOTHING, so it is a bare `Control` with a minimum size and
## no children -- which is also how it is told apart from the containers that wrap the row.
func _reserved_gap(row: Control) -> Array:
	for child in row.get_children():
		if not (child is Control):
			continue
		var c: Control = child
		if c.get_child_count() == 0 and not (c is Label) and not (c is Button):
			return [c.size.x, c.size.y]
	return []


## How big the slot plate is. ASSA-71's point is that the plate is the icon's BOX, so if these two
## disagree the icon is sitting on something other than its own slot.
func _plate_rect(art: TextureRect) -> Array:
	var parent := art.get_parent()
	if not (parent is Panel):
		return []
	return [(parent as Panel).size.x, (parent as Panel).size.y]


## The words on this row's buttons. The ANTI-VACUITY input, nothing more: `check_pack_icon_scale.py`
## scores invariance against what used to move the scale, and these are read off the laid-out row
## rather than from a roster so they follow the client instead of asserting one.
func _verbs_in(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.get_children():
		if child is Button:
			out.append((child as Button).text)
		out.append_array(_verbs_in(child))
	return out
