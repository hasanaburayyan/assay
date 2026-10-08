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
var _frames := 0
var _quitting := false
## The tick the first pass found the panels fullest on, and the count it saw there. See `_initialize`.
var _best_tick := -1
var _best_rows := 0


## TWO PASSES, AND THE SECOND ONE CHECKS THE FIRST.
##
## **THE MOMENT WORTH MEASURING IS NOT THE END OF THE PLAY.** The loop spends what it makes: at tick
## 481 this player holds nothing and the menu says "nothing you are carrying can be worked", so a
## probe that measured the final state would measure no crafting rows at all. The fullest the two
## panels ever get lasts about four ticks in the middle -- `window_shot.gd` has the same problem and
## the same answer for `04-pack.png`: *a moment the tool notices, found by the play and not chosen
## by me*.
##
## You cannot know a high-water mark has been reached until it stops rising, so pass one plays the
## whole loop to find the tick and pass two replays and stops there. **The replay then asserts it
## found the same count at the same tick**, which is what turns "the loop is deterministic" from
## something I believe into something this probe reports -- and if the plan ever stops being a pure
## function of the world, this says so instead of measuring a different moment than it names.
##
## The count is read off the SIM (`make_offers` + `inventory_of`), never off the panels, for
## `window_shot.gd`'s reason: the panels are the thing under test, so asking them how many rows they
## have is asking the thing under test.
func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var seed_text := String(argv[0]) if argv.size() > 0 else SEED
	if not _play_offline(seed_text, -1):
		_quitting = true
		quit(1)
		return
	if _best_tick < 0:
		print("FAIL  no tick of the play had a crafting row on it, so there is nothing to measure. "
				+ "The loop on seed %s never held anything workable." % seed_text)
		_quitting = true
		quit(1)
		return
	var wanted := _best_rows
	var at := _best_tick
	_best_rows = 0
	_best_tick = -1
	if not _play_offline(seed_text, at):
		_quitting = true
		quit(1)
		return
	if _screen._sim.tick() != at or _best_rows != wanted:
		print(("FAIL  the replay is not the same play: pass 1 saw %d rows at tick %d, pass 2 saw %d "
				+ "at tick %d. The demo plan has stopped being a pure function of the world, so this "
				+ "probe can no longer name the moment it measured.")
				% [wanted, at, _best_rows, _screen._sim.tick()])
		_quitting = true
		quit(1)


## PLAY THE LOOP, OFFLINE: this script is the relay. Lifted from `button_session.gd::_run_offline`,
## including the thing I would have got wrong -- A BUNDLE IS NUMBERED WITH THE TICK WE ARE AT, not
## the one it produces.
##
## `stop_at` of -1 plays to the end and only records the high-water tick; any other value plays until
## the world is at that tick and leaves the screen standing there.
func _play_offline(seed_text: String, stop_at: int) -> bool:
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, as `button_session.gd` and `tests/test_main_screen.gd` do it: a `--script` run
	# works inside `SceneTree._initialize`, before the root window is in the tree, so the engine's own
	# call comes too late to be useful.
	_screen._ready()
	var asked: Array = []
	_screen._client.asked.connect(func(command: Variant) -> void: asked.append(command))
	var play := AssayButtonPlay.new(_screen, 0)
	var welcome := AssaySimHost.fresh_welcome_json(seed_text, "marlow")
	if welcome == "":
		print("FAIL  could not make a world on seed %s" % seed_text)
		return false
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		print("FAIL  the offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return false
	for _i in range(PLAY_TICKS):
		if Time.get_unix_time_from_system() > _ceiling:
			print("FAIL  make_icon_layout.gd ran past its %ds ceiling inside the play loop"
					% int(RUN_CEILING))
			return false
		var rows := _rows_now()
		if rows > _best_rows:
			_best_rows = rows
			_best_tick = _screen._sim.tick()
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


## HOW MANY ROWS THE TWO PANELS ARE ABOUT TO HAVE, asked of the sim. See `_initialize`.
func _rows_now() -> int:
	var player: int = _screen._client.player_id
	var offers: Array = _screen._sim.make_offers(player)
	var stacks: Array = _screen._sim.inventory_of(player)
	# A CRAFTING ROW IS THE POINT, so a moment with a huge pack and no offers is not an improvement
	# on one with both. Zero offers scores zero however full the pack is.
	return 0 if offers.is_empty() else offers.size() + stacks.size()


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
enum Phase { SIZE, MAKE_TAB, MAKE_READ, PACK_TAB, PACK_READ }

var _phase: Phase = Phase.SIZE
var _settling := 0
var _measured: Dictionary = {}


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
	# this is undone on every frame of the sizing phase.
	root.size = _declared_viewport()
	match _phase:
		Phase.SIZE:
			if _settle():
				_phase = Phase.MAKE_TAB
		Phase.MAKE_TAB:
			if not _open("make"):
				return true
			_phase = Phase.MAKE_READ
		Phase.MAKE_READ:
			if _settle():
				_measured["make_rows"] = _rows_of(_screen._make, "make")
				_measured["make_visible_in_tree"] = _screen._make.is_visible_in_tree()
				_measured["make_shown"] = _screen._make_shown
				_phase = Phase.PACK_TAB
		Phase.PACK_TAB:
			if not _open("inventory"):
				return true
			_phase = Phase.PACK_READ
		Phase.PACK_READ:
			if _settle():
				_measured["pack_rows"] = _rows_of(_screen._carrying, "pack")
				_measured["pack_visible_in_tree"] = _screen._carrying.is_visible_in_tree()
				_report()
				return true
	return false


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
	_measured["column_visible"] = _screen._column != null and _screen._column.visible
	_measured["tick"] = _screen._sim.tick()
	_measured["rows_now"] = _best_rows
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
