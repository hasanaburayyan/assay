extends SceneTree
## **WHAT HAPPENS WHEN YOU PRESS EACH PART ROW, IN EVERY STATE THE PACK CAN BE IN** (ASSA-103 box 7).
##
##   godot --headless --path . --script res://tools/part_press_table.gd -- [seed]
##
## Nerite could get two of the four answers box 7 asks for by playing `button_session.gd` and reading
## what it printed -- the two the demo loop happens to press. The other two are the REFUSALS, and the
## loop never presses a button it expects to be refused, so no amount of replaying it reaches them.
## This presses every cell on purpose.
##
## THE TABLE IS NOT 4x2. Maren's ruling on ASSA-103: *"A frame chosen" was never one state* --
## `FrameMounted` and `NoSuchSlot` both depend on WHICH frame was chosen, because `sim/src/assembly.rs`
## says a HELD frame offers no hopper slot and a PLANTED one does. So the states are: nothing chosen,
## a held frame chosen, a planted frame chosen; and the rows are every part the pack actually holds.
##
## EVERY CELL IS A REAL PRESS ON THE REAL ROW'S REAL BUTTON. Not `_choose_part`, which is the function
## under test: the whole defect ASSA-103 fixed lived between the row and that call. The row is found by
## its sentence (`STACK_LINE`, read from `main.gd`) and the button by its TOOLTIP, because the button's
## LABEL is the thing being measured and a finder that knows the label in advance cannot see it change.
##
## WHAT IT ASSERTS, so a green line is a claim and not a printout:
##  - the verb word on a row is the SAME in all three states (ASSA-103 ruling 1: the word follows the
##    sim's `is_frame`, never the client's state);
##  - the screen's sentence is `part_press_refusal`'s, CHARACTER FOR CHARACTER, never one of its own;
##  - a refusal is drawn in the FAILED colour and does not reach `_building`;
##  - an acceptance does reach `_building`;
##  - **and the table contains at least one of each.** A run in which nothing was refused proves
##    nothing about refusals, and would otherwise print twelve confident lines and exit 0.
##
## Prints `PART PRESS TABLE OK` LAST and only on success: Godot exits 0 even on a compile error.

## The chain to a pack holding every part kind is ~470 ticks; the budget is `button_session.gd`'s.
const TICKS := 4000
const DEFAULT_SEED := "777042"
## The two tooltips `main.gd::_stack_button` writes for the "build" verb. A part row is identified by
## these rather than by `Frame`/`Mount`, which are the words under test.
const FRAME_TIP := "use as the frame"
const MOUNT_TIP := "mount on the frame"

var _screen: Node
var _play: AssayButtonPlay
var _asked: Array = []
var _refused := 0
var _accepted := 0
var _rows: Array = []


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var seed_text := String(argv[0]) if argv.size() > 0 else DEFAULT_SEED

	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND: a `--script` run works inside `SceneTree._initialize`, before the root window
	# is in the tree, so the engine's own call never comes. Same note as `button_session.gd`.
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)

	var welcome := AssaySimHost.fresh_welcome_json(seed_text, "limpet")
	if welcome == "":
		_fail("could not make a world on seed %s" % seed_text)
		return
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		_fail("offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return

	# PLAY THE DEMO LOOP, AND STOP IT THE TICK THE PACK IS FULL ENOUGH. The loop's next move after it
	# has made its parts is to press them, which would spend the rows this table is about.
	for _i in range(TICKS):
		if _parts_in_pack().size() >= AssaySimHost.part_kinds().size():
			break
		_play.advance()
		if _play.finished:
			break
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		var before: int = _screen._sim.applied
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		if _screen._sim.applied == before:
			_fail("the sim refused the bundle for tick %d" % at)
			return

	var parts := _parts_in_pack()
	var missing := AssaySimHost.part_kinds().size() - parts.size()
	if missing > 0:
		# AN HONEST BLANK RATHER THAN A SHORT TABLE. A table missing a row is a table whose missing row
		# is the one nobody checked, and it would read as coverage.
		_fail("the loop stopped at tick %d with only %d of %d part kinds in the pack: %s"
				% [_screen._sim.tick(), parts.size(), AssaySimHost.part_kinds().size(),
				_kinds_of(parts)])
		return
	print("  seed %s, tick %d, pack holds %s"
			% [seed_text, _screen._sim.tick(), _kinds_of(parts)])
	_table(parts)


## THE STATES, EACH NAMED BY THE FRAME IT STARTS FROM. `[]` is nothing chosen; the others are the pack
## stacks whose kind the sim calls a frame, which on today's catalogue is the held handle and the
## planted frame -- read out of `part_kinds()`, so a fifth frame kind adds a state here by itself.
func _table(parts: Array) -> void:
	var states: Array = [{"name": "nothing chosen", "first": {}}]
	for stack in parts:
		if _is_frame(String(stack.get("kind", ""))):
			states.append({"name": "%s chosen" % String(stack.get("kind", "?")), "first": stack})
	if states.size() < 2:
		_fail("no frame kind in the pack, so there is no second state and the table is half a table")
		return

	var words := {}
	for state in states:
		var first: Dictionary = state["first"]
		for stack in parts:
			_screen._building.clear()
			_screen._refresh_pack()
			if not first.is_empty():
				_screen._choose_part(first)
				if _screen._building.size() != 1:
					_fail("the frame %s was itself refused, so this state cannot be set up: %s"
							% [String(first.get("kind", "?")), _screen._status.text])
					return
			# THE SAME STACK CANNOT BE THE FRAME AND THE CELL: pressing the row you are standing on is
			# a different question (a second press of one stack) and it is not box 7's.
			if first.get("kind", "") == stack.get("kind", "") and not first.is_empty():
				continue
			if not _press_row(state["name"], stack, first):
				return
			var kind := String(stack.get("kind", "?"))
			if words.has(kind) and words[kind] != _rows[-1]["word"]:
				_fail(("the row for %s says `%s` with %s and `%s` with nothing chosen. ASSA-103: the "
						+ "word is the sim's `is_frame`, never the client's state")
						% [kind, _rows[-1]["word"], state["name"], words[kind]])
				return
			words[kind] = _rows[-1]["word"]

	for row in _rows:
		print("  %-22s press %-6s on %-28s -> %s"
				% [row["state"], row["word"], row["kind"], row["said"]])
	if _refused == 0:
		_fail("every cell was accepted, so this run says nothing about refusals")
		return
	if _accepted == 0:
		_fail("every cell was refused, so this run says nothing about the presses that work")
		return
	print("  %d cells: %d accepted, %d refused in the sim's own words"
			% [_rows.size(), _accepted, _refused])
	print("PART PRESS TABLE OK")
	quit(0)


## ONE CELL. Press the row's own button and judge what the screen did, against what the sim says.
func _press_row(state: String, stack: Dictionary, first: Dictionary) -> bool:
	var chosen := PackedStringArray()
	for entry in _screen._building:
		chosen.append(String((entry as Dictionary).get("kind", "")))
	var refusal := AssaySimHost.part_press_refusal(chosen, String(stack.get("kind", "")))
	var sentence := AssayHud.stack_line(stack)
	var button := _part_button(sentence)
	if button == null:
		_fail("no part button on the row reading `%s`" % sentence)
		return false
	var word := button.text
	var before: int = _screen._building.size()
	button.pressed.emit()
	var landed: bool = _screen._building.size() > before
	var said: String = _screen._status.text
	var colour: Color = _screen._status.modulate
	if refusal == "":
		if not landed:
			_fail("the sim would accept %s with %s, and the press did not land: %s"
					% [String(stack.get("kind", "?")), state, said])
			return false
		_accepted += 1
	else:
		if landed:
			_fail("the sim refuses %s with %s and the press landed anyway: the parts already chosen "
					% [String(stack.get("kind", "?")), state] + "never reached it")
			return false
		if said != refusal:
			_fail("the screen says `%s`; the sim's own sentence is `%s`" % [said, refusal])
			return false
		# A REFUSAL IN THE COLOUR THAT MEANS "YOU ARE IN" IS A CONFIRMATION, whatever it says.
		if colour != AssayHud.status_color(AssayHud.Say.FAILED):
			_fail("the refusal of %s is drawn in %s, not the failed colour"
					% [String(stack.get("kind", "?")), colour])
			return false
		_refused += 1
	_rows.append({"state": state, "word": word, "kind": sentence,
			"said": said if refusal != "" else "accepted (%s)" % said})
	return true


## The part button on the pack row whose sentence is `sentence`, found by TOOLTIP. See the header: the
## label is the measurement, so a finder keyed on the label is blind to the defect.
func _part_button(sentence: String) -> Button:
	for row in _screen._carrying.get_children():
		var line: Label = row.find_child(_screen.STACK_LINE, true, false) as Label
		if line == null or line.text != sentence:
			continue
		for button in row.find_children("*", "Button", true, false):
			var tip: String = (button as Button).tooltip_text
			if tip.begins_with(FRAME_TIP) or tip.begins_with(MOUNT_TIP):
				return button as Button
	return null


## Every stack in the pack whose kind the sim's catalogue calls a part, in the pack's own order.
func _parts_in_pack() -> Array:
	if not _screen._sim.running():
		return []
	var out: Array = []
	var seen := {}
	for entry in _screen._sim.inventory_of(_screen._client.player_id):
		var stack: Dictionary = entry
		var kind := String(stack.get("kind", ""))
		if _kind_row(kind).is_empty() or seen.has(kind):
			continue
		seen[kind] = true
		out.append(stack)
	return out


func _kind_row(kind: String) -> Dictionary:
	for entry in AssaySimHost.part_kinds():
		var part: Dictionary = entry
		if String(part.get("name", "")).to_lower() == kind.to_lower():
			return part
	return {}


func _is_frame(kind: String) -> bool:
	return bool(_kind_row(kind).get("is_frame", false))


func _kinds_of(parts: Array) -> String:
	var names := PackedStringArray()
	for stack in parts:
		names.append(String((stack as Dictionary).get("kind", "?")))
	return ", ".join(names)


func _fail(why: String) -> void:
	print("FAIL  %s" % why)
	for row in _rows:
		print("  %-22s press %-6s on %-28s -> %s"
				% [row["state"], row["word"], row["kind"], row["said"]])
	quit(1)
