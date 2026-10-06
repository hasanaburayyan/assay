extends SceneTree
## **FOUR TABS, FOUR PICTURES, AND THE ONE NUMBER THAT SAYS WHO SETS THE PANEL'S WIDTH** (ASSA-247).
##
## **WHY THIS TOOL EXISTS AND WHY IT IS NOT `window_shot.gd`.** `window_shot.gd` never selects a tab
## (Nacre, ASSA-247 21:27 UTC: *"every named shot now shows Mineralogy, so `04-pack.png` does not
## contain the pack"*), so on the tabbed panel it photographs ONE tab under five names and its own
## subject check still prints `yes` — the node is in the tree whether or not its tab is open. Nacre
## is fixing that tool. This one exists because gate line 1 is hours away and **three of the four
## tabs on the board's screen have never been photographed by anyone**, so there is nothing to judge
## Make, Inventory or Bench from. It shoots, it measures, it changes nothing a player sees.
##
## **THE MEASUREMENT, WHICH IS THE HALF A PICTURE CANNOT GIVE.** The overflow Nacre found (text to
## x=1279, painted column ending at x=1255) has a mechanism written down in this repo already —
## `main.gd::_cut_to_one_row`: *"a Label with `AUTOWRAP_OFF` alone reports a 1012px minimum width"*.
## The column's `pad` is a `MarginContainer` handed `column_rect.size`, and a Container is CLAMPED UP
## to `get_combined_minimum_size()`, while the `Panel` that paints the surface is not a Container and
## keeps the 344 px it was given. So one unwrapped row inside the column makes the content wider than
## the paint, and every later ruling about wrapping is downstream of that. This tool prints every
## control in the column with its own minimum width, biggest first, so the width-setter is NAMED
## instead of guessed at. **I guessed on the item at 18:34 — I said my own 125-char headline sets it.
## If the table says a species row does, I was wrong and it goes on the item.**
##
## **AND IT IS PER TAB, WHICH IS WHY EVERY TAB IS SHOT AND MEASURED SEPARATELY.** A hidden child
## contributes nothing to a container's minimum size, so only the OPEN tab's rows can push the
## column — the panel may be a different width on each tab. Nobody has seen a tab change.
##
## **THE REPEAT GUARD IS THE POINT, NOT A SAFETY RAIL.** Two tabs whose frames are pixel-identical
## means the strip did not change what is on screen, which is exactly the defect that made the last
## shot set worthless. It fails the run by name.
##
## **AND IT CAN BE ASKED FOR THE WORST MOMENT RATHER THAN THE LAST ONE** (`clip=<px>`). The fold
## budget is decided by the SMALLEST the tab's scroll box ever gets — the stopped state, where the
## blocks above the strip grow and a player most needs the controls. Given a ceiling, this plays
## until the clip first drops under it and shoots every tab THERE, so the pictures are of the moment
## the design is tightest instead of the moment the play happened to end.
##
## Usage (GUI, never --headless: a headless run has no layout pass and every size reads 0):
##   godot --path . --script res://tools/maren_tab_shots.gd -- <out_dir> [seed] [ticks] [clip=N]

const DEFAULT_SEED := "14247"
## The play the panel was budgeted against (Nacre's probe: 516 ticks, worst clip at tick 89).
const DEFAULT_TICKS := 520
const TICKS_PER_FRAME := 32
## Containers need frames, not time, to lay out; the strip hides one body and shows another.
const SETTLE_FRAMES := 4
## Below this a control is furniture and not a suspect. A themed row is 28 px tall and the column is
## 344 px wide, so anything asking for more than the column is already the defect.
const MIN_WIDTH_FLOOR := 120.0

## 600 s, `window_shot.gd`'s ceiling: this plays a 520-tick world before its first picture, and a
## loaded Mac triples that. MEMBER INITIALIZER, which is this repo's rule for every looping tool.
const RUN_CEILING := 600.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

enum Phase { JOIN, PLAY, PICK, SETTLE, SHOOT, DONE }

var _out := ""
var _seed := DEFAULT_SEED
var _left := DEFAULT_TICKS
var _phase := Phase.JOIN
var _waited := 0
var _started := false
var _done := false
var _screen: Node = null
var _play: AssayButtonPlay = null
var _asked: Array = []
var _names := PackedStringArray()
var _at := 0
var _taken := {}
var _lines := PackedStringArray()
## Shoot at the first tick whose clip is under this, instead of at the end of the play. 0 = off.
var _clip_ceiling := 0.0
## The smallest the open tab's scroll box has been, and when.
var _clip_worst := 1e9
var _clip_tick := -1


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_finish(false, "usage: -- <out_dir> [seed] [ticks]")
		return
	# `clip=N` IS NAMED AND NOT POSITIONAL, `window_shot.gd`'s reason: a fourth slot whose meaning
	# depends on counting the three in front of it is a number that gets passed wrong.
	var positional := PackedStringArray()
	for raw in argv:
		var arg := String(raw)
		if arg.begins_with("clip="):
			_clip_ceiling = float(arg.substr(5))
		else:
			positional.append(arg)
	_out = String(positional[0])
	_seed = String(positional[1]) if positional.size() > 1 else DEFAULT_SEED
	_left = int(positional[2]) if positional.size() > 2 else DEFAULT_TICKS
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_finish(false, "cannot write to %s" % _out)
		return
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND: a `--script` run works inside `SceneTree._initialize`, before the root window
	# is in the tree, so the engine's own call comes too late (`button_session.gd`'s reason).
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])
	print("rules %s, protocol %d, godot %s" % [AssayProtocol.rules_id(),
			AssayProtocol.protocol_version(), Engine.get_version_info()["string"]])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  maren_tab_shots.gd ran past its %ds ceiling in phase %d"
				% [int(RUN_CEILING), _phase])
		quit(1)
		return true
	match _phase:
		Phase.JOIN:
			# **THE FIRST SCREEN, BEFORE ANY WORLD EXISTS, AND IT IS SHOT HERE FOR A REASON.** A
			# stranger meets this one first, and ASSA-231 is the rule it has to keep: the column is
			# not on screen at all before a world, so a tab strip of four names over nothing is the
			# labelled-empty-gap defect with four labels. The test that holds it lives in
			# `test_main_screen.gd` — which does not load on this head, so the picture is the only
			# witness tonight.
			_waited += 1
			if _waited >= SETTLE_FRAMES:
				_waited = 0
				var column: Control = _screen._column
				_lines.append("join screen: column visible %s, strip visible %s"
						% [column.visible, _screen._tabs.is_visible_in_tree()])
				_shoot("join")
				_phase = Phase.PLAY
		Phase.PLAY:
			_play_frames()
		Phase.PICK:
			if _at >= _names.size():
				_phase = Phase.DONE
				return false
			var name_of := String(_names[_at])
			if not _screen._tabs.select(name_of):
				_finish(false, "the strip refused tab '%s'" % name_of)
				return true
			_phase = Phase.SETTLE
		Phase.SETTLE:
			_waited += 1
			if _waited >= SETTLE_FRAMES:
				_waited = 0
				_phase = Phase.SHOOT
		Phase.SHOOT:
			_shoot(String(_names[_at]))
			_at += 1
			_phase = Phase.PICK
		Phase.DONE:
			_report()
	return _done


## OFFLINE: THIS SCRIPT IS THE RELAY (`window_shot.gd::_begin_offline`, lifted whole).
func _begin_offline() -> bool:
	var welcome := AssaySimHost.fresh_welcome_json(_seed, "maren")
	if welcome == "":
		_finish(false, "could not make a world on seed %s" % _seed)
		return false
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		_finish(false, "offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return false
	return true


## PLAY THE DEMO LOOP WITH THE REAL BUTTONS, then hand the frame back so containers lay out. Every
## picture is of the SAME world state — one state, four tabs — because the question is the panel and
## not the play, and a tab shot at a different tick could differ for reasons nothing here chose.
func _play_frames() -> void:
	if not _started:
		if not _begin_offline():
			return
		_started = true
	for _i in range(TICKS_PER_FRAME):
		if _left <= 0:
			_end_play()
			return
		_left -= 1
		_play.advance()
		if _play.finished:
			_end_play()
			return
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		var before: int = _screen._sim.applied
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		if _screen._sim.applied == before:
			_finish(false, "the sim refused the bundle for tick %d" % at)
			return
		# THE CLIP IS READ EVERY TICK, because the number that decides the fold rule is the SMALLEST
		# this box ever is and that moment lasts a handful of ticks in the middle of a long play.
		var clip: float = _screen._tabs.scroll_box().size.y
		if clip > 0.0 and clip < _clip_worst:
			_clip_worst = clip
			_clip_tick = _screen._sim.tick()
		if _clip_ceiling > 0.0 and clip > 0.0 and clip <= _clip_ceiling:
			print("clip %.0f px at tick %d is under the %.0f px asked for: shooting here"
					% [clip, _clip_tick, _clip_ceiling])
			_end_play()
			return


func _end_play() -> void:
	_names = _screen._tabs.tab_names()
	if _names.is_empty():
		_finish(false, "the strip has no tabs: there is nothing to photograph")
		return
	print("played to tick %d, tabs: %s" % [_screen._sim.tick(), ", ".join(_names)])
	_phase = Phase.PICK


## ONE TAB'S PICTURE AND ONE TAB'S NUMBERS.
func _shoot(tab_name: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		_finish(false, "%s: no frame to read" % tab_name)
		return
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(image.get_data())
	var print_of := hasher.finish().hex_encode()
	if _taken.has(print_of):
		_finish(false, "tab '%s' is pixel-identical to '%s': selecting it changed nothing on screen"
				% [tab_name, _taken[print_of]])
		return
	_taken[print_of] = tab_name
	var path := "%s/tab-%d-%s.png" % [_out, _at + 1, tab_name]
	if image.save_png(path) != OK:
		_finish(false, "cannot write %s" % path)
		return
	# THE RIGHTMOST DRAWN PIXEL IN THE COLUMN, which is the overflow as a player meets it. Asked of
	# the IMAGE and not of a rect: a rect says what was laid out, a pixel says what was drawn, and
	# this is the fourth defect this week where those two disagreed.
	var surface: Control = _screen._column
	var paint_right := int(surface.get_global_rect().end.x) - 1
	# THE BACKGROUND IS SAMPLED IN THE TOP MARGIN, not beside the column: the whole question here is
	# whether ink reaches the window's right edge, so a sample taken there could be the ink itself.
	var bg := image.get_pixel(image.get_width() - 2, 2)
	var ink_right := -1
	for x in range(image.get_width() - 1, int(surface.get_global_rect().position.x), -1):
		for y in range(0, image.get_height()):
			if not image.get_pixel(x, y).is_equal_approx(bg):
				ink_right = x
				break
		if ink_right >= 0:
			break
	_lines.append("%-12s paint right x=%d   rightmost ink x=%d   %s" % [tab_name, paint_right,
			ink_right, "OVERFLOW %d px" % (ink_right - paint_right) if ink_right > paint_right
			else "inside the paint"])
	_lines.append("             %s" % _width_table(tab_name))
	_lines.append("             %s" % _button_table(tab_name, paint_right))


## **WHERE EVERY CONTROL IN THIS TAB IS ACTUALLY DRAWN, LEFT TO RIGHT.** Wren's fold rule says no
## control is ever below the fold, and the budget probe measures exactly that — vertically. A column
## whose content is laid out wider than the window has a SECOND edge to fall off, and nothing
## measures it: a button whose row is 998 px wide is centred near x=1400 and simply is not on the
## screen. `go here`'s blank slab was one of these. This asks the one question that catches it.
func _button_table(tab_name: String, paint_right: int) -> String:
	var found: Array = []
	_walk_buttons(_screen._column, found)
	var out := PackedStringArray()
	var off := 0
	# THE OTHER EDGE, AND IT IS THE ONE WREN'S RULE IS ABOUT. Only the buttons inside the scroll box
	# can fall below it; `Mine` and the strip are pinned above it by construction.
	var clip: Rect2 = _screen._tabs.scroll_box().get_global_rect()
	var deepest := 0.0
	for row in found:
		var rect: Rect2 = row[1]
		var verdict := "ok"
		if rect.position.x > float(paint_right):
			verdict = "OFF THE SCREEN RIGHT"
			off += 1
		elif rect.end.x > float(paint_right) + 1.0:
			verdict = "cut at the paint"
			off += 1
		if rect.position.y >= clip.position.y - 1.0:
			deepest = maxf(deepest, rect.end.y)
			if rect.end.y > clip.end.y + 1.0:
				verdict = "%s BELOW THE FOLD by %.0f px" % [verdict, rect.end.y - clip.end.y]
				off += 1
		out.append("      %-26s x %4.0f..%4.0f  y %4.0f..%4.0f  %s"
				% [row[0], rect.position.x, rect.end.x, rect.position.y, rect.end.y, verdict])
	out.insert(0, "buttons: %d, %d not fully inside the painted column" % [found.size(), off])
	out.insert(1, "      clip y %.0f..%.0f (%.0f px, worst %.0f at tick %d); deepest button bottom "
			% [clip.position.y, clip.end.y, clip.size.y, _clip_worst, _clip_tick]
			+ "%.0f -> %s" % [deepest, "%.0f px to spare" % (clip.end.y - deepest)
			if deepest <= clip.end.y else "OVER by %.0f px" % (deepest - clip.end.y)])
	return "\n".join(out)


func _walk_buttons(node: Node, found: Array) -> void:
	for child in node.get_children():
		var button := child as Button
		if button != null and button.is_visible_in_tree():
			found.append([button.text.substr(0, 24), button.get_global_rect()])
		var control := child as Control
		if control == null or control.is_visible_in_tree():
			_walk_buttons(child, found)


## **WHO ASKS FOR MORE WIDTH THAN THE COLUMN HAS.** Every visible control under the painted surface,
## with its own minimum width, biggest first. A Container is clamped UP to this, so the largest
## number here IS the column's content width and the name beside it is the cause.
func _width_table(tab_name: String) -> String:
	var found: Array = []
	_walk(_screen._column, found)
	found.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var pad: Control = _screen._column.get_node_or_null(_screen.COLUMN_PAD)
	var out := PackedStringArray()
	out.append("surface %.0f / pad %.0f / content min %.0f px" % [
			_screen._column.size.x,
			pad.size.x if pad != null else -1.0,
			pad.get_combined_minimum_size().x if pad != null else -1.0])
	for row in found.slice(0, 6):
		out.append("      %6.0f px  %-12s %s" % [row[0], row[1], row[2]])
	var file := FileAccess.open("%s/widths-%s.txt" % [_out, tab_name], FileAccess.WRITE)
	if file != null:
		for row in found:
			file.store_line("%8.0f  %-14s %s" % [row[0], row[1], row[2]])
	return "\n".join(out)


func _walk(node: Node, found: Array) -> void:
	for child in node.get_children():
		var control := child as Control
		if control != null and control.is_visible_in_tree():
			var min_x := control.get_combined_minimum_size().x
			if min_x >= MIN_WIDTH_FLOOR:
				var text := ""
				if control is Label:
					text = (control as Label).text
				elif control is Button:
					text = (control as Button).text
				found.append([min_x, control.get_class(),
						"%s  %s" % [control.name, text.replace("\n", " / ").substr(0, 90)]])
		if control == null or control.is_visible_in_tree():
			_walk(child, found)


## THE REPORT GOES IN THE OUT DIR AS WELL AS TO STDOUT, for `window_shot.gd`'s provenance reason: a
## shots directory gets copied into `shared/` on its own and a console log does not travel with it.
func _report() -> void:
	var head := "== MAREN TAB SHOTS, seed %s, %d tabs ==" % [_seed, _names.size()]
	print("\n%s" % head)
	for line in _lines:
		print(line)
	var tail := "TAB SHOTS OK  %d tabs, %d distinct frames -> %s" % [_names.size(), _taken.size(),
			_out]
	print(tail)
	var file := FileAccess.open("%s/00-report.txt" % _out, FileAccess.WRITE)
	if file != null:
		file.store_line(head)
		file.store_line("rules %s, godot %s" % [AssayProtocol.rules_id(),
				Engine.get_version_info()["string"]])
		for line in _lines:
			file.store_line(line)
		file.store_line(tail)
	_done = true
	quit(0)


func _finish(ok: bool, why: String) -> void:
	print("%s  %s" % ["OK" if ok else "FAIL", why])
	_done = true
	quit(0 if ok else 1)
