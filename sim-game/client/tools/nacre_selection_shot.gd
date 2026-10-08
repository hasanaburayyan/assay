extends SceneTree
## CI: local -- a DRAWN selection needs a real window; --headless reads back a blank frame
## **WHAT THE HOST BOX LOOKS LIKE WITH ITS TEXT SELECTED** (ASSA-315 boxes 3 and 5, Maren's own
## flag on her own ruling).
##
##     godot --path . --script res://tools/nacre_selection_shot.gd -- <out_dir>
##
## **THE RULING SHE WROTE SAYS WHY THIS FILE HAS TO EXIST:** *"Godot may composite
## `selection_color` with alpha rather than painting it flat. If the drawn pixel is not (74,79,92),
## my 6.73 is wrong and the measurement must be re-earned on a real frame -- shoot it, do not
## assume it."* So the two numbers on that item (INK 6.73:1 on the bed, the bed 2.04:1 against the
## well) are DERIVED from `build_theme.gd`'s constants, and derived is not drawn. Nothing we own
## could put text in a real window and select it, which is why those boxes sat open while the fix
## itself was green.
##
## **NOT `--headless`, for two reasons and not one.** The frame comes back blank (`window_shot.gd`
## says that at length), and `grab_focus()` cannot succeed with no window to own the focus -- and
## `LineEdit` DESELECTS on focus loss by default, so a headless run would photograph nothing twice
## and call the pair a before and an after.
##
## IT WRITES THREE WHOLE 1280x720 FRAMES, not crops, because Maren judges at 1x on the panel and a
## crop is the thing she keeps catching me reading. `nacre_selection_bed.py` does the arithmetic off
## them; this file only drives the window and says what it drove.
##
## **WHY THREE AND NOT TWO, which is a defect this tool had and its own control caught.** Clicking
## into the box does two things at once: it FOCUSES the control and it selects. The first version
## shot unfocused-then-selected, and the focus stylebox changes every edge of the 240x30 box, so the
## changed-pixel region was the whole box and the probe read the WELL as the ink. The number it
## printed (2.03:1) was real arithmetic about the wrong two colours. So:
##   01-unfocused.png  the box as a stranger finds it
##   02-focused.png    focused, nothing selected -- the frame the bed is measured AGAINST
##   03-selected.png   focused and selected
## 02 against 03 isolates the selection; 01 against 03 is the pair for the eye.
##
## THE SELECTION IS MADE THE WAY A PLAYER MAKES IT: a real press-drag-release through
## `Viewport.push_input`, the viewport's own dispatch (`limpet_click_echo.gd`'s path). If that comes
## back with nothing selected the run falls back to a real Ctrl+A and then to `select_all()`, and
## **the report names which path produced the selection**, because a bed drawn after `select_all()`
## is still the engine's bed but is no longer evidence that a drag reaches this control.

const RUN_CEILING := 180.0
## The box is 240 px wide and carries `localhost:7777`. 6 px in from each edge keeps the press on
## the text rather than on the stylebox's margin, and the drag still runs past the last glyph.
const DRAG_INSET := 6.0

var _out := ""
var _screen: Node = null
var _frames := 0
var _stage := 0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING
var _path := "none"
var _rect := Rect2()
var _said: Array[String] = []
var _taken := {}
var _done := false


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_fail("usage: -- <out_dir>")
		return
	_out = String(argv[0])
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail("cannot write to %s" % _out)
		return
	# THE PRECONDITION, CHECKED BEFORE ANYTHING IS WRITTEN. A run under the dummy driver would
	# produce two black PNGs and a pass.
	if DisplayServer.get_name() == "headless":
		_fail("this tool needs a REAL window: the display driver is headless, so every frame it "
				+ "reads back is blank and nothing can hold the focus")
		return
	var scene: PackedScene = load("res://scenes/main.tscn")
	_screen = scene.instantiate()
	get_root().add_child(_screen)


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		_fail("ran past its %ds ceiling at stage %d after %d frames"
				% [int(RUN_CEILING), _stage, _frames])
		return true
	_frames += 1
	# The node reaches the tree during frame 1 and the door's own layout settles over the next few;
	# `custom_minimum_size` is not a rect until the container has run.
	if _frames < 8:
		return false
	match _stage:
		0:
			_stage = 1
			return _before()
		1:
			# THE FOCUS ON ITS OWN, one frame, so the bed is the only thing the next diff holds.
			_box().grab_focus()
			_stage = 2
			return false
		2:
			if _frames < 11:
				return false
			_stage = 3
			return not _shoot("02-focused.png")
		3:
			_stage = 4
			return _select()
		4:
			# TWO FRAMES BETWEEN THE SELECTION AND THE SHOT. `push_input` is synchronous but the
			# redraw is not: reading the texture in the same frame photographs the old bed.
			if _frames < 17:
				return false
			_stage = 5
			return _after()
		_:
			return true


## THE BOX, AND THE THREE FACTS THAT MAKE THE AFTER FRAME READABLE.
func _box() -> LineEdit:
	var host: LineEdit = _screen._host
	return host


func _before() -> bool:
	var host := _box()
	if host == null or not host.is_visible_in_tree():
		_fail("the host box is not on screen, so there is nothing to select")
		return true
	_rect = host.get_global_rect()
	if _rect.size.x < 40.0 or _rect.size.y < 10.0:
		_fail("the host box has no laid-out rect yet: %s" % str(_rect))
		return true
	if host.has_selection():
		_fail("the host box already has a selection before anything was pressed, so a diff of the "
				+ "two frames would measure nothing")
		return true
	if host.has_focus():
		_fail("the host box already has the focus, so 02 and 01 would be one picture")
		return true
	_said.append("  box        %s, text %s" % [str(_rect), host.text])
	return not _shoot("01-unfocused.png")


func _select() -> bool:
	var host := _box()
	# THE FOCUS IS ALREADY TAKEN (stage 1), and it has to be: `deselect_on_focus_loss_enabled` is
	# true by default, so a selection on an unfocused box is not drawn at all -- the one way this
	# tool could photograph a blank bed and report a contrast failure that is really a focus failure.
	if not host.has_focus():
		_fail("the host box did not take the focus, so any selection would be undrawn")
		return true
	var from := Vector2(_rect.position.x + DRAG_INSET, _rect.position.y + _rect.size.y / 2.0)
	var to := Vector2(_rect.end.x - DRAG_INSET, from.y)
	_drag(from, to)
	if host.has_selection():
		_path = "a real press-drag-release through the viewport"
	else:
		_keys(KEY_A, true)
		if host.has_selection():
			_path = "a real Ctrl+A (the drag selected nothing)"
		else:
			host.select_all()
			_path = "select_all() -- FALLBACK: neither a drag nor Ctrl+A reached this control, so "
			_path += "the bed below is drawn by the engine but no gesture of a player's is proved"
	if not host.has_selection():
		_fail("nothing is selected after a drag, a Ctrl+A and select_all(): there is no after "
				+ "frame to measure")
		return true
	_said.append("  selection  %s" % _path)
	_said.append("  focus      has_focus %s, selected %d..%d of %s"
			% [str(host.has_focus()), host.get_selection_from_column(),
			host.get_selection_to_column(), host.text])
	return false


func _after() -> bool:
	var host := _box()
	if not host.has_selection():
		_fail("the selection was lost between the gesture and the shot")
		return true
	var ok := _shoot("03-selected.png")
	if ok:
		print("SELECTION SHOT OK")
		for line in _said:
			print(line)
		print("  measure it: tools/nacre_selection_bed.py %s/02-focused.png %s/03-selected.png %d %d %d %d"
				% [_out, _out, int(_rect.position.x), int(_rect.position.y),
				int(_rect.size.x), int(_rect.size.y)])
	_done = true
	quit(0 if ok else 1)
	return true


func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	release.global_position = to
	root.push_input(release)


func _keys(code: Key, ctrl: bool) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		event.command_or_control_autoremap = ctrl
		root.push_input(event)


## A SHOT IS ONLY A SHOT IF THE FRAME CARRIES MORE THAN ONE COLOUR (`window_shot.gd`'s guard, and
## the reason it exists: a dummy driver answers "what does it look like" with a flat black pass).
func _shoot(leaf: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null:
		_fail("%s: no frame to read" % leaf)
		return false
	var seen := {}
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			seen[image.get_pixel(x, y).to_rgba32()] = true
	if seen.size() < 2:
		_fail("%s: the frame is one flat colour, so nothing drew" % leaf)
		return false
	var path := "%s/%s" % [_out, leaf]
	if image.save_png(path) != OK:
		_fail("cannot write %s" % path)
		return false
	# WHICH OF THE THREE FRAMES ARE THE SAME PICTURE, said out loud rather than left to the probe.
	# `01 == 02` would mean taking the focus draws nothing, and then the three-frame structure above
	# is unnecessary rather than wrong; `02 == 03` means no selection was drawn at all.
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(image.get_data())
	var fingerprint := hasher.finish().hex_encode()
	var same := " (PIXEL-IDENTICAL to %s)" % _taken[fingerprint] if _taken.has(fingerprint) else ""
	if not _taken.has(fingerprint):
		_taken[fingerprint] = leaf
	_said.append("  wrote      %s  %dx%d  %d colours  %s%s"
			% [leaf, image.get_width(), image.get_height(), seen.size(),
			fingerprint.substr(0, 12), same])
	return true


func _fail(why: String) -> void:
	print("FAIL  nacre_selection_shot.gd: %s" % why)
	for line in _said:
		print(line)
	_done = true
	quit(1)
