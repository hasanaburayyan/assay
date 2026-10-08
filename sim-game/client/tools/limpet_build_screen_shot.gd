extends SceneTree
## CI: local -- a shot: --headless writes a BLANK frame and reports success, the worst kind of green
## **A PICTURE OF THE OPEN BUILD SCREEN, AND THE ONE MEASUREMENT ARITHMETIC CANNOT GIVE** (ASSA-328).
##
##   godot --path . --script res://tools/limpet_build_screen_shot.gd -- <out_dir> [seed] [ticks]
##
## **WHY IT IS NOT A STATE IN `window_shot.gd`.** That tool shoots seven fixed moments of a played
## world and every one of them is about the HUD column. This is about a surface that only exists
## after a press, and it carries a second job no shot tool has: it REPORTS the overlap.
##
## **THE JOB ARITHMETIC CANNOT DO.** `AssayHud.build_screen_rect` keeps the screen clear of the
## world's own control band -- the status toast and `whole world (V)`, which live inside the world
## rect and are not the world (Maren's §0). Headless, the band's top comes from
## `AssayHud.WORLD_CONTROLS_BAND`, a constant measured off a screenshot, and **a constant for a
## laid-out height is the shape of defect that goes stale in silence** (my own ASSA-320: a number
## written in prose beside asserted facts reads as fact). So this asks the three real controls where
## they ACTUALLY are in a laid-out window and intersects them with where the screen ACTUALLY is.
##
## **NOT `--headless`, for `window_shot`'s reason doubled.** A dummy driver writes a blank PNG and
## reports success, AND it lays nothing out -- so every rect in the report would read `(0,0,0,0)` and
## every overlap would be empty. **This tool would pass perfectly while measuring nothing**, which is
## the exact failure I wrote down after generalising from the one configuration I had measured.

## The seed Maren's mock was built on, so the picture is comparable to it (`assay-build-screen` §0).
const DEFAULT_SEED := "14247"

## Enough of the loop to have a pack worth making something out of. The session's own budget is far
## longer; a shot only needs the catalogue to have rows.
const DEFAULT_TICKS := 60

## Ticks between handing the frame back, so containers lay out before anything is measured.
const TICKS_PER_FRAME := 10

## **THE WALL CLOCK THIS RUN MAY NOT OUTLIVE** (ASSA-182's guard, `tests/test_tool_ceilings.gd`).
##
## **I SHIPPED THIS TOOL WITHOUT ONE AND CI CAUGHT IT, which is the guard doing exactly its job.**
## A looping `_process` that dies on a runtime error inside `_initialize` never reaches `_finish`,
## so it holds the machine until a person notices -- and the night this Mac hit load 151 is what
## that costs. 120 s is four times the longest this has taken (the play is 60 ticks and the shot is
## one frame), so reaching it means something stopped advancing rather than that the world was slow.
const RUN_CEILING := 120.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

var _screen: Node = null
var _play: RefCounted = null
var _asked: Array = []
var _out := ""
var _seed := DEFAULT_SEED
var _left := DEFAULT_TICKS
var _started := false
var _shot := false
var _done := false
var _faults: Array = []


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_finish(false, "usage: -- <out_dir> [seed] [ticks]")
		return
	_out = String(argv[0])
	_seed = String(argv[1]) if argv.size() > 1 else DEFAULT_SEED
	_left = int(argv[2]) if argv.size() > 2 else DEFAULT_TICKS
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_finish(false, "cannot write to %s" % _out)
		return
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, the reason `button_session.gd` and `window_shot.gd` both give: a `--script`
	# run works inside `SceneTree._initialize`, before the root window is in the tree.
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  limpet_build_screen_shot.gd ran past its %ds ceiling: nothing advanced it"
				% int(RUN_CEILING))
		quit(1)
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "limpet")
		if welcome == "":
			_finish(false, "could not make a world on seed %s" % _seed)
			return true
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		if not _screen._sim.running():
			_finish(false, "offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
			return true
		_started = true
		return false
	if _left > 0:
		for _i in range(TICKS_PER_FRAME):
			if _left <= 0:
				break
			_left -= 1
			_play.advance()
			var inputs := []
			for command in _asked:
				inputs.append({"Player": {"player": _screen._client.player_id,
						"command": command}})
			_asked.clear()
			var at: int = _screen._sim.tick()
			_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		return false
	if not _shot:
		_shot = true
		_open_and_settle()
		return false
	_measure()
	_write()
	return _done


## **PRESS THE ROW A PLAYER WOULD PRESS.** Not `_open_build_screen`: the launcher opening nothing is
## one of the two defects this picture is evidence against, and calling the open function directly
## would take the row's one control out of the test.
func _open_and_settle() -> void:
	for row in _screen._make.get_children():
		var button := _find(row, AssayHud.make_launch_text())
		if button != null:
			button.pressed.emit()
			return
	_faults.append("no make row carried a `%s` control at all" % AssayHud.make_launch_text())


## **THE OVERLAP, IN PIXELS, AGAINST THE THREE CONTROLS MAREN'S §1 PROTECTS.**
##
## **A ZERO-SIZED CONTROL IS REPORTED AND NOT SKIPPED HERE**, which is the opposite of what
## `main.gd::_place_build_screen` does with one -- and deliberately. There, a zero size means
## "nothing has laid out" and the constant has to answer. Here, a laid-out window that reports a
## control with no size is itself the finding: it means this tool measured nothing and must not say
## so in green.
func _measure() -> void:
	if not _screen._build_box.visible:
		_faults.append("the screen is not visible after pressing a row's launcher")
		return
	var screen_rect := Rect2(_screen._build_box.global_position, _screen._build_box.size)
	print("SCREEN   %s  (%.0f x %.0f)" % [screen_rect, screen_rect.size.x, screen_rect.size.y])
	# **WHAT THE SCREEN WAS ASKED TO BE, BESIDE WHAT IT IS** (ASSA-332). A `Control` cannot be smaller
	# than its combined minimum, so a box whose content demands more height than
	# `build_screen_rect` allows GROWS -- and grows down, over the band Maren's §1 protects. The rect
	# is arithmetic the suite already holds; this is the only place the two can be compared.
	var room := AssayHud.world_rect()
	var reached := room.end.y
	for control in [_screen._view_toggle, _screen._map_key_toggle, _screen._says_toast]:
		var node := control as Control
		if node != null and node.visible and node.size.y > 0.0:
			reached = minf(reached, node.global_position.y)
	var asked := AssayHud.build_screen_rect(room, reached)
	print("ASKED    %s  (%.0f x %.0f); the box's own minimum is %s"
			% [asked, asked.size.x, asked.size.y, _screen._build_box.get_combined_minimum_size()])
	print("VIEWPORT root %s, window %s" % [root.size, DisplayServer.window_get_size()])
	# **AND IF THE BOX IS NOT THE SIZE IT WAS ASKED FOR, WHERE THE HEIGHT CAME FROM** -- the chain of
	# minimums from each named part up to the box, because the answer is a sum and only the chain
	# shows which node is paying it. Printed ONLY when there is something to explain: this found a
	# 450 px overshoot (ASSA-332) and would be five lines of noise on every other run.
	if screen_rect.size.y > asked.size.y + 1.0 or screen_rect.size.x > asked.size.x + 1.0:
		_faults.append("the box is %.0f x %.0f and `build_screen_rect` asked for %.0f x %.0f"
				% [screen_rect.size.x, screen_rect.size.y, asked.size.x, asked.size.y])
		for leaf in [_screen._build_picker, _screen._build_materials, _screen._build_detail,
				_screen._build_cost, _screen._build_said]:
			var node := leaf as Control
			var trail := PackedStringArray()
			while node != null and node != _screen._build_box:
				trail.append("%s min %.0fx%.0f size %.0fx%.0f" % [node.name,
						node.get_combined_minimum_size().x, node.get_combined_minimum_size().y,
						node.size.x, node.size.y])
				node = node.get_parent() as Control
			print("    %s" % " <- ".join(trail))
	var column := AssayHud.VIEW.x - AssayHud.PANEL
	if screen_rect.end.x > column:
		_faults.append("the screen reaches x %.0f and the HUD column starts at %.0f"
				% [screen_rect.end.x, column])
	var watched := {
		"whole world (V)": _screen._view_toggle,
		"show the map key (K)": _screen._map_key_toggle,
		"the status toast": _screen._says_toast,
	}
	for named in watched:
		var node := watched[named] as Control
		var rect := Rect2(node.global_position, node.size)
		var over := screen_rect.intersection(rect)
		print("%-22s %s  visible=%s  overlap=%s" % [named, rect, node.visible, over.size])
		if not node.visible:
			# **AN INVISIBLE CONTROL IS NOT A PASS AND NOT A FAIL.** The toast is drawn only while the
			# client has something to say (ASSA-239), so it is legitimately absent here -- and that
			# means this run did NOT measure the screen against it. Said out loud, because a silent
			# skip is how "measured" comes to mean "assumed".
			print("    NOT MEASURED: this control is hidden in this frame, so nothing was compared")
			continue
		if rect.size.y <= 0.0:
			_faults.append("%s reports no size in a laid-out window, so nothing was measured"
					% named)
		elif over.size.x > 0.0 and over.size.y > 0.0:
			_faults.append("the screen covers %s by %.0f x %.0f px"
					% [named, over.size.x, over.size.y])
	# **AND THE CONSTANT IS COMPARED TO THE MEASUREMENT, which is the whole reason this tool exists.**
	# The band's real top is the highest of the visible controls; `WORLD_CONTROLS_BAND` is what the
	# headless suite believes. A drift is not a failure -- the constant is deliberately generous -- but
	# an unreported drift is how it rots, so the number is printed either way.
	var world := AssayHud.world_rect()
	var top := world.end.y
	for named in watched:
		var node := watched[named] as Control
		if node.visible and node.size.y > 0.0:
			top = minf(top, node.global_position.y)
	print("BAND     measured top %.0f, world bottom %.0f, so the band is %.0f px tall"
			% [top, world.end.y, world.end.y - top])
	print("         WORLD_CONTROLS_BAND says %.0f; %s"
			% [AssayHud.WORLD_CONTROLS_BAND,
			"generous by %.0f px" % (AssayHud.WORLD_CONTROLS_BAND - (world.end.y - top))
			if AssayHud.WORLD_CONTROLS_BAND >= world.end.y - top
			else "SHORT by %.0f px" % ((world.end.y - top) - AssayHud.WORLD_CONTROLS_BAND)])
	if AssayHud.WORLD_CONTROLS_BAND < world.end.y - top:
		_faults.append(("WORLD_CONTROLS_BAND is %.0f and the real band is %.0f px tall, so the "
				+ "headless answer would put the screen over a control")
				% [AssayHud.WORLD_CONTROLS_BAND, world.end.y - top])
	_measure_commit_bar(screen_rect)


## **THE COMMIT BAR, IN A LAID-OUT WINDOW** (ASSA-332; Maren's §5.4 ruling 3: *"the COMMIT BAR,
## 863 x 112 at y 529..641"*, `Build` ≤ 160 px, the sentence ≥ 687, blocks 2/4/6 ending at y 513).
##
## **EVERY ABSOLUTE NUMBER IS PRINTED AND NONE OF THEM IS A FAULT, which is deliberate.** Her rects
## are measured on a 1280x720 window whose control band is where it was the day she measured it; the
## screen's own top and bottom come from `build_screen_rect` reading the LIVE band, so a toast that is
## one pixel taller moves all four numbers and none of that is a defect. **So the numbers go to her
## and the RELATIONS are the faults**: the bar is her height, `Build` is inside her ceiling and at the
## bar's right end, and the sentence gets at least the width the wrap was measured at. That is the
## rule I keep writing down -- hand over the picture and the numbers, never the verdict.
func _measure_commit_bar(screen_rect: Rect2) -> void:
	var bar := _screen._build_bar as Control
	var act := _screen._build_act as Control
	var said := _screen._build_said as Control
	if bar == null or act == null or said == null:
		_faults.append("the screen has no commit bar, sentence or `Build` to measure")
		return
	var bar_rect := Rect2(bar.global_position, bar.size)
	var act_rect := Rect2(act.global_position, act.size)
	var said_rect := Rect2(said.global_position, said.size)
	print("BAR      %s  (%.0f x %.0f)  y %.0f..%.0f"
			% [bar_rect, bar_rect.size.x, bar_rect.size.y, bar_rect.position.y, bar_rect.end.y])
	print("         her rect is 863 x 112 at y 529..641, on the band she measured")
	print("BUILD    %s  width %.0f  right edge %.0f (bar's is %.0f)"
			% [act_rect, act_rect.size.x, act_rect.end.x, bar_rect.end.x])
	var owed := AssayHud.commit_sentence_width(bar_rect.size.x, float(_screen.BUILD_GUTTER))
	print("SENTENCE %s  width %.0f, floor %.0f (bar %.0f - Build's %.0f ceiling - gutter %d)"
			% [said_rect, said_rect.size.x, owed, bar_rect.size.x, AssayHud.BUILD_ACT_WIDTH,
			_screen.BUILD_GUTTER])
	var block6 := (_screen._build_cost as Control).get_parent() as Control
	if block6 != null:
		print("BLOCK 6  bottom %.0f, bar top %.0f, gap %.0f (her blocks end at y 513)"
				% [block6.global_position.y + block6.size.y, bar_rect.position.y,
				bar_rect.position.y - (block6.global_position.y + block6.size.y)])
	if absf(bar_rect.size.y - AssayHud.BUILD_COMMIT_BAR) > 1.0:
		_faults.append("the bar is %.0f px tall and `BUILD_COMMIT_BAR` asks for %.0f"
				% [bar_rect.size.y, AssayHud.BUILD_COMMIT_BAR])
	if act_rect.size.x > AssayHud.BUILD_ACT_WIDTH:
		_faults.append(("`Build` is %.0f px wide and her ceiling is %.0f, so the sentence is below "
				+ "the width the wrap was measured at")
				% [act_rect.size.x, AssayHud.BUILD_ACT_WIDTH])
	if absf(act_rect.end.x - bar_rect.end.x) > 1.0:
		_faults.append("`Build` ends at x %.0f and the bar ends at x %.0f: it is not right-aligned"
				% [act_rect.end.x, bar_rect.end.x])
	if said_rect.size.x + 1.0 < owed:
		_faults.append("the sentence gets %.0f px of the bar and is owed %.0f"
				% [said_rect.size.x, owed])
	# **AND THE BAR IS INSIDE THE SCREEN IT IS A BLOCK OF**, which is the one absolute that IS a fault:
	# a 112 px bar on a screen too short for it would hang past the world's control band, and the whole
	# of `build_screen_rect` is about not covering that.
	if bar_rect.end.y > screen_rect.end.y + 1.0:
		_faults.append("the bar's bottom is %.0f and the screen ends at %.0f"
				% [bar_rect.end.y, screen_rect.end.y])


func _write() -> void:
	var image := root.get_texture().get_image()
	var path := "%s/build-screen-%s.png" % [_out, _seed]
	if image.save_png(path) != OK:
		_finish(false, "could not write %s" % path)
		return
	print("  %s  %dx%d" % [path, image.get_width(), image.get_height()])
	if _faults.is_empty():
		_finish(true, "")
		return
	_finish(false, "\n".join(PackedStringArray(_faults)))


func _find(node: Node, label: String) -> Button:
	for child in node.find_children("*", "Button", true, false):
		if (child as Button).text == label:
			return child as Button
	return null


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_screen) and _screen.has_method("stop_solo_relay"):
		_screen.stop_solo_relay()
	if ok:
		print("BUILD SCREEN SHOT OK · nothing covered")
	else:
		print("FAIL  %s" % why)
	quit(0 if ok else 1)
