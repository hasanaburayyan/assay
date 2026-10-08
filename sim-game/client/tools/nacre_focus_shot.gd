extends SceneTree
## CI: local -- a real window, and focus is the whole subject. Headless is not a weaker version of
## this run, it is a blind one: inside `_initialize` there is no viewport with focus to give.
##
## **DOES A CLICK LEAVE FOCUS ON `Mine`, THE MOST-PRESSED BUTTON IN THE GAME?** (ASSA-304 box 5,
## Maren: *"Press it, shoot it, measure it: that is box 5, and it decides whether this is one
## screen or the most-pressed button in the game."*)
##
## **A HEADLESS PROBE CANNOT ANSWER THIS AND I TRIED ONE FIRST.** Inside `SceneTree._initialize`
## there is no viewport with focus to give, so `grab_focus()` leaves `has_focus()` false -- the
## instrument reports "no" for a reason that has nothing to do with the question. This is the same
## tool run in a REAL window, where focus is a real thing.
##
## IT PRESSES THE BUTTON THE WAY A PLAYER DOES -- a real `InputEventMouseButton` at the button's own
## centre through `Viewport.push_input` -- rather than calling `grab_focus()`, because the claim is
## about what a CLICK leaves behind. Calling `grab_focus` would assert the state I am trying to find
## out whether a click reaches.
##
## Then it shoots the frame, so the answer is a picture and not only a boolean: Maren's
## `accent_buttons.py` classifies the ink on every ACCENT bed in it.
##
## Usage: --path client --script res://tools/nacre_focus_shot.gd -- <out_dir>

const SEED := "777042"
const SETTLE_FRAMES := 12

var _out := ""
var _screen: Node = null
var _frames := 0
var _mine: Button = null
var _pressed := false
var _said := PackedStringArray()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_finish(false, "usage: -- <out_dir>")
		return
	_out = String(args[0])
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var welcome := AssaySimHost.fresh_welcome_json(SEED, "nacre")
		if welcome == "":
			_finish(false, "no offline world")
			return true
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		return false
	if _frames < SETTLE_FRAMES:
		return false
	if _mine == null:
		_mine = _find_mine()
		if _mine == null:
			_finish(false, "no Mine button on the played screen, so nothing was asked")
			return true
		_say("BEFORE  Mine variation=%s focus_mode=%d has_focus=%s"
				% [_mine.theme_type_variation, _mine.focus_mode, _mine.has_focus()])
		_shoot("before-mine-unfocused.png")
		return false
	if not _pressed:
		_pressed = true
		_click(_mine)
		return false
	# ONE FRAME AFTER THE RELEASE, which is where a player's eye is.
	_say("AFTER   Mine has_focus=%s  (a real click, not grab_focus)" % _mine.has_focus())
	_say("        focused ink the theme gives it: %s" % _mine.get_theme_color(&"font_focus_color"))
	_say("        its resting ink:                %s" % _mine.get_theme_color(&"font_color"))
	_shoot("after-mine-clicked.png")
	var report := "\n".join(_said) + "\n"
	var handle := FileAccess.open(_out.path_join("mine-focus.txt"), FileAccess.WRITE)
	if handle != null:
		handle.store_string(report)
		handle.close()
	print(report)
	_finish(true, "pressed Mine in a real window and shot both states")
	return true


func _find_mine() -> Button:
	var walk: Array[Node] = [_screen]
	while not walk.is_empty():
		var node: Node = walk.pop_back()
		for child in node.get_children():
			walk.append(child)
		var button := node as Button
		if button != null and button.text == "Mine":
			return button
	return null


func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event)


func _shoot(name: String) -> void:
	await_draw()
	var image := root.get_texture().get_image()
	if image.save_png(_out.path_join(name)) != OK:
		_say("could not write %s" % name)
	else:
		_say("wrote %s  %dx%d" % [name, image.get_width(), image.get_height()])


func await_draw() -> void:
	RenderingServer.force_draw()


func _say(line: String) -> void:
	_said.append(line)


func _finish(ok: bool, why: String) -> void:
	print(("OK    " if ok else "FAIL  ") + why)
	quit(0 if ok else 1)
