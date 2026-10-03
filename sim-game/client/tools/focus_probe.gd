extends SceneTree
## **DOES ENTER PRESS PLAY SOLO ON A REAL SCREEN** (Maren's ruling 2, ASSA-113).
##
## `tests/test_main_screen.gd` can assert that the button is first in the row and that something asks
## it for the focus, and that is all it can do: the suite works inside `SceneTree._initialize`, where
## a node added under the root reports `is_inside_tree() == false`, `get_viewport()` is null, and
## `grab_focus()` errors out leaving `has_focus()` false. Measured, not assumed.
##
## **ONE FRAME LATER ALL OF THAT WORKS, HEADLESS INCLUDED** -- also measured, which is why this file
## exists rather than the box going unticked. So this adds the real `main.tscn` under the root, lets
## the engine call `_ready` itself (the client's own path, not a hand call), waits for frames, and
## then reads the focus owner back OFF THE VIEWPORT and pushes a real Enter at it.
##
## Run it from `sim-game/client`:
##     godot --headless --path . --script tools/focus_probe.gd
##
## It prints `FOCUS PROBE OK` or a line naming what it found instead, and it stops any relay the
## press started before it quits.

var _screen: Node = null
var _frames := 0
var _presses := 0
var _owner_before := ""
var _said_after := ""


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_screen = scene.instantiate()
	# NO HAND CALL TO `_ready`. The engine calling it when the node enters the tree is the path the
	# shipped client takes, and `tree_entered` -> `grab_focus` only happens on that path.
	get_root().add_child(_screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		return false  # The node reaches the tree during this frame; nothing is focused yet.
	if _frames == 2:
		var viewport := _screen.get_viewport()
		if viewport == null:
			print("NO VERDICT: the screen has no viewport even in the tree")
			return true
		var owner := viewport.gui_get_focus_owner()
		_owner_before = "null" if owner == null else "%s(%s)" % [owner.get_class(),
				String(owner.get("text"))]
		if owner != _screen._solo_button:
			print("FOCUS PROBE FAIL: the focus is on %s, so Enter would not press Play solo"
					% _owner_before)
			_finish()
			return true
		# A SECOND LISTENER, so the press is counted without replacing the real handler -- what is
		# under test is the engine delivering Enter to the focused button, and the wiring to
		# `_on_play_solo` has to stay live or the next check below means nothing.
		_screen._solo_button.pressed.connect(func(): _presses += 1)
		var down := InputEventKey.new()
		down.keycode = KEY_ENTER
		down.physical_keycode = KEY_ENTER
		down.pressed = true
		viewport.push_input(down)
		var up := InputEventKey.new()
		up.keycode = KEY_ENTER
		up.physical_keycode = KEY_ENTER
		up.pressed = false
		viewport.push_input(up)
		return false
	if _frames < 5:
		return false
	_said_after = String(_screen._status.text)
	var ok := _presses == 1
	if not ok:
		print("FOCUS PROBE FAIL: Enter on the focused Play solo button fired %d presses" % _presses)
	# AND THE REAL HANDLER RAN, not just the signal. The status line is the evidence either way: a
	# relay that started says so, and one that could not says which refusal. Both prove the press
	# reached `_on_play_solo`; only "enter a host address"-style silence would mean it did not.
	elif _said_after == "" or _said_after.contains("Play solo to start"):
		print("FOCUS PROBE FAIL: the press changed nothing on screen; it says %s" % _said_after)
		ok = false
	else:
		print("FOCUS PROBE OK - focus owner was %s, one Enter, screen then said: %s"
				% [_owner_before, _said_after])
	_finish()
	return true


## STOP ANYTHING THE PRESS STARTED. A real press really does spawn the relay beside this checkout, and
## an orphan holding a port is worse than no probe at all.
func _finish() -> void:
	if _screen != null and _screen.has_method("stop_solo_relay"):
		_screen.stop_solo_relay()
