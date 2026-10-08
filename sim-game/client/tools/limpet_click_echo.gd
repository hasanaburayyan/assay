extends SceneTree
## CI: local -- clicks a real window and reads the frame it was painted in
## LIMPET, ASSA-215 BOXES 1 AND 2: DOES THE CLICKED TILE GET PAINTED IN THE FRAME YOU CLICKED IN,
## AND IS IT STILL THERE WHILE THE BODY IS FROZEN?
##
##   godot --path client --script res://tools/limpet_click_echo.gd --
##       <out_dir> [seed] [tx] [ty] [mark|nomark]
##
## NOT `--headless`. Two reasons, and the first is the item: `_draw` does not run without a window,
## so a headless run of this tool would measure nothing and say it measured. The second is that the
## 500 ms strip is a picture Maren judges at 1x (box 3) and a dummy rendering driver saves black.
##
## **THE CLICK IS A REAL MOUSE EVENT, NOT `_client.submit`.** `maren_corner_strip.gd` submits the
## command directly, which is right for a question about the WALK -- but the thing under test here is
## the input path: `_unhandled_input` -> `_tile_under` -> `submit` -> the echo -> `_draw`. Submitting
## would skip four of those five and still print a reassuring table. The event goes in through
## `root.push_input`, which is the viewport's own dispatch, so it reaches the same handler the mouse
## reaches.
##
## **THE PHASE, WHICH IS THE MEASUREMENT** (learned the hard way on ASSA-197/211). `_process` runs
## BEFORE the engine draws, so everything this tool reads about the picture -- `drawn_destination`,
## `drawn_body`, and `root.get_texture()` -- belongs to the PREVIOUS frame. A click pushed in row K
## is therefore answered by row K+1, and the table prints `drew_row` so no column has to be taken on
## trust. A tool that labelled the click's own row with the click's own draw would report the feature
## working one frame earlier than it does, which is the only fact box 1 asks about.
##
## `nomark` IS THE A/B AND IT CHECKS ITSELF. It clicks identically and clears the mark every frame,
## so the only difference in the run is eight `draw_rect` calls. If any frame in a `nomark` run
## reports the mark drawn anyway, the ordering assumption behind that suppression is wrong and the
## verdict says the comparison is DIRTY instead of printing a number nobody should believe.

const TILE_PX := 32.0
const TICK_SECONDS := 0.1
const SETTLE := 0.6
const STRIP_SECONDS := 0.5
const CROP := Vector2i(224, 224)
const RUN_CEILING := 180.0
## How long after the click the run waits for the walk to arrive before reporting anyway. A walk is
## one tile per tick, so 6 s is 60 tiles: further than any click in this tool's runs.
const WALK_CEILING := 6.0

var _out := "."
var _seed := "14247"
var _target := Vector2i(76, 48)
var _mode := "mark"
var _screen: Node
var _asked: Array = []
var _started := false
var _done := false
var _started_at := 0.0
var _clicked_at := -1.0
var _click_row := -1
var _next_tick := 0.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING
var _rows: Array[Dictionary] = []
var _crop_at := Vector2i(-1, -1)
var _saved := 0
var _last_frame := 0.0
var _click_point := Vector2.ZERO
var _suppressed := 0
var _arrived_at := -1.0
## The world tile the scroll is read off: fixed for the run, printed, and the spawn tile in practice.
var _anchor := Vector2i.ZERO


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_out = String(argv[0]) if argv.size() > 0 else "."
	_seed = String(argv[1]) if argv.size() > 1 else "14247"
	if argv.size() > 3:
		_target = Vector2i(int(argv[2]), int(argv[3]))
	if argv.size() > 4:
		_mode = String(argv[4])
	if _mode != "mark" and _mode != "nomark":
		print("FAIL  mode must be mark or nomark, not %s" % _mode)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	print("LIMPET CLICK ECHO -- seed %s, click %s, mode %s, window %s, map rect %s"
			% [_seed, _target, _mode, DisplayServer.window_get_size(), AssayHud.world_rect()])


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  limpet_click_echo.gd ran past its %ds ceiling" % int(RUN_CEILING))
		quit(1)
		return true
	if not _started:
		return _begin()
	# THE A/B's SUPPRESSION, AT THE TOP OF THE FRAME. `_walk_echo` goes too, or `_refresh_world`
	# would put the tile straight back from state this tool never cleared.
	if _mode == "nomark":
		_screen._walk_echo = {}
		_screen._world.destination = null

	var now := _now()
	var since := now - _started_at
	var frame := now - _last_frame
	_last_frame = now
	if now >= _next_tick:
		_next_tick += TICK_SECONDS
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
	_sample(since, frame)
	# THE CLICK, ONCE, AFTER THE WORLD HAS SETTLED. Pushed AFTER this frame's sample, so the row the
	# click happened in is in the table with the picture that preceded it, and row K+1 carries the
	# first draw that could possibly hold the mark.
	if _clicked_at < 0.0 and since > SETTLE:
		_click()
	# THE RUN ENDS WHEN THE WALK DOES, not when the strip does. The strip is the first 500 ms; the
	# frames AFTER it, with the mark still up and nothing being photographed, are the only honest
	# A/B window for what eight `draw_rect` calls cost. A click one tile away would leave that
	# window empty -- aim far.
	if _clicked_at >= 0.0 and now - _clicked_at > STRIP_SECONDS + 0.2:
		# **NOT IN THE ARRIVAL FRAME: THE CLEARING IS WHAT ARRIVAL MEANS HERE.** A run that stopped
		# the moment the sim put me on the tile ended one frame before the only frame that can show
		# the mark gone, and the first version did exactly that and printed "last painted in row -2".
		if _arrived_at >= 0.0:
			if now - _arrived_at > 0.4:
				_report()
				return true
		elif _my_tile() == _target:
			_arrived_at = now
		elif now - _clicked_at > WALK_CEILING:
			_report()
			return true
	return false


func _begin() -> bool:
	var welcome := AssaySimHost.fresh_welcome_json(_seed, "limpet")
	if welcome == "":
		print("DEAD: no world on seed %s" % _seed)
		quit(1)
		return true
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		print("DEAD: offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		quit(1)
		return true
	_started = true
	_started_at = _now()
	_next_tick = _started_at
	_last_frame = _started_at
	_anchor = _screen._sim.spawn_tile()
	# WHAT IS UNDER THE TILE BEING CLICKED, PRINTED, because Maren's box 3 is "it reads on ground AND
	# on an ore disc" and a strip that does not say which one it photographed cannot answer half of
	# it. The deposits are listed too, so the next run can aim at one without a second tool.
	var facts: Dictionary = _screen._sim.tile_at(_target)
	var under: Variant = facts.get("deposit")
	print("spawn %s -> click %s ; under the clicked tile: %s"
			% [_screen._sim.spawn_tile(), _target,
			"GROUND (no deposit)" if under == null else "ORE %s" % facts])
	var near: Array = []
	for entry in _screen._sim.deposits():
		var deposit: Dictionary = entry
		var at: Vector2i = deposit["center"]
		if Vector2(at).distance_to(Vector2(_screen._sim.spawn_tile())) <= 14.0:
			near.append("%s r%d" % [at, int(deposit.get("radius", 0))])
	print("deposits within 14 tiles of spawn: %s" % ", ".join(near))
	return false


## ONE SYNTHETIC LEFT CLICK ON THE TILE, through the viewport.
## **AN UNCLICKABLE TILE IS A BROKEN RUN, NOT A NEGATIVE RESULT, AND THE FIRST VERSION OF THIS TOOL
## REPORTED IT AS ONE.** Two runs at tile (76, 40) printed "dest EMPTY, the mark was painted in 0 of
## 448 frames" -- which reads exactly like the feature not working, and was in fact the click landing
## at screen x 1120 on a map that ends at 936. The camera centres on the body, so only the ~28 tiles
## under the view can be clicked at all; a tile 20 east of you is not on screen to click. So the tool
## now refuses: it checks the point is on the map, and then checks the click actually reached the
## handler, and dies rather than printing a table of zeroes.
func _click() -> void:
	_click_point = _screen.point_of_tile(_target)
	var map := AssayHud.world_rect()
	if not map.has_point(_click_point):
		print(("FAIL  tile %s is drawn at %s, which is outside the map rect %s -- the camera is on "
				+ "your body, so nothing more than ~14 tiles away is on screen to click. Pick a "
				+ "nearer tile; this run measured nothing.") % [_target, _click_point, map])
		_done = true
		quit(1)
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _click_point
	press.global_position = _click_point
	root.push_input(press)
	_clicked_at = _now()
	_click_row = _rows.size() - 1
	# DID THE EVENT REACH THE HANDLER AT ALL. `push_input` is synchronous, so by here `main.gd` has
	# either taken the click or not, and an echo of `{}` means the walk was never submitted -- a
	# viewport that swallowed the event, a panel over the point, a dead sim. Every number after this
	# would be about a click that never happened.
	if _screen._walk_echo.is_empty():
		print(("FAIL  the click on %s at %s did not reach main.gd: no walk was submitted and no "
				+ "echo was set. Nothing below this line is a measurement.")
				% [_target, _click_point])
		_done = true
		quit(1)
		return
	print("clicked tile %s at screen point %s (row %d, t=%.3f); echo %s; map rect %s"
			% [_target, _click_point, _click_row, _clicked_at - _started_at,
			_screen._walk_echo, AssayHud.world_rect()])


func _sample(since: float, frame: float) -> void:
	var layer = _screen._world
	var dest: Rect2 = layer.drawn_destination
	var body: Rect2 = layer.drawn_body
	# **THE WORLD'S OWN POSITION, WHICH IS WHAT "FROZEN" MEANS ON THIS SURFACE.** `drawn_body` is
	# the wrong column for it and the first run of this tool proved it: the camera is locked to the
	# drawn body (`main.gd:2396`), so the body sits at 440,252 for the entire walk and a freeze and
	# a sprint look identical in those two numbers. The world slides underneath instead -- Maren's
	# `d_scroll` in the ASSA-197 strip, zero while the click goes unanswered -- so the honest column
	# is a FIXED world tile's drawn position.
	var origin: Vector2 = (layer.view as Dictionary).get("origin", Vector2.ZERO)
	var scroll := (layer as Control).position + Vector2(_anchor) * TILE_PX - origin
	var row := {
		"t": since,
		"frame": frame,
		"dest": dest,
		"body": body,
		"scroll": scroll,
		"tile": _my_tile(),
		"target": _my_target(),
		"state": _screen._walk_echo.duplicate(),
		"shot": "",
	}
	# **THE CLICK'S OWN FRAME IS NOT A DIRTY FRAME AND COUNTING IT COST ME A RUN.** The suppression
	# runs at the TOP of `_process` and the click is pushed at the BOTTOM of it, so in `nomark` the
	# echo is always set once, after the clearing, and that one frame paints by construction. Two
	# runs reported "DIRTY: 1 frame" and the 1 was always this. Counted from the frame AFTER the
	# click's answer frame, a real race -- `_refresh_world` putting the tile back -- still shows up
	# as a count in the dozens.
	if _mode == "nomark" and dest != Rect2() and _click_row >= 0 and _rows.size() > _click_row + 1:
		_suppressed += 1
	# **THE STRIP OPENS BEFORE THE CLICK**, by a tenth of a second, and that is not decoration: the
	# only picture that proves the mark is the CLICK's is the same tile photographed without it. The
	# first version started at the click and every frame in it had the mark, so a reader had to take
	# "it was not there before" from a column of numbers.
	var photograph := since > SETTLE - 0.12 if _clicked_at < 0.0 \
			else _now() - _clicked_at <= STRIP_SECONDS
	if photograph:
		if _crop_at.x < 0:
			# POINT_OF_TILE BEFORE THE CLICK IS THE SAME POINT: the camera is on a body that has not
			# moved yet, so the rect is fixed for the whole strip either way.
			_click_point = _screen.point_of_tile(_target)
			_crop_at = Vector2i(_click_point) - CROP / 2
			_crop_at = _crop_at.clamp(Vector2i.ZERO, Vector2i(root.size) - CROP)
			print("crop rect fixed at %s %s (click point %s)" % [_crop_at, CROP, _click_point])
		var image := root.get_texture().get_image()
		if image != null:
			var cut := image.get_region(Rect2i(_crop_at, CROP))
			var name := "f%03d.png" % _saved
			if cut.save_png("%s/%s" % [_out, name]) == OK:
				_saved += 1
				# ONE FRAME BACK, like every column here: see the header.
				if _rows.size() >= 1:
					_rows[_rows.size() - 1]["shot"] = name
				else:
					row["shot"] = name
	_rows.append(row)


func _my_tile() -> Vector2i:
	for entry in _screen._sim.players():
		var player: Dictionary = entry
		if int(player["id"]) == _screen._client.player_id:
			return player["pos"]
	return Vector2i(-1, -1)


func _my_target() -> Variant:
	for entry in _screen._sim.players():
		var player: Dictionary = entry
		if int(player["id"]) == _screen._client.player_id:
			return player.get("target")
	return null


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	return values[values.size() / 2]


func _report() -> void:
	_done = true
	print("")
	print("  row     t  frame_ms  drew_row  dest_rect                  scroll.x scroll.y d_scroll  tile      target    echo       shot")
	var prev: Dictionary = {}
	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var dest: Rect2 = r["dest"]
		var scroll: Vector2 = r["scroll"]
		var moved := 0.0
		if not prev.is_empty():
			moved = (scroll - (prev["scroll"] as Vector2)).length()
		print("%5d %6.3f %8.1f  %8s  %-25s %8.2f %8.2f %8.2f  %-9s %-9s %-10s %s"
				% [i, r["t"], r["frame"] * 1000.0, "-" if i == 0 else str(i - 1),
				"EMPTY" if dest == Rect2() else str(dest), scroll.x, scroll.y, moved,
				str(r["tile"]), str(r["target"]), str(r["state"]), r["shot"]])
		prev = r
	print("")
	print("VERDICT  mode %s, %d frames, %d crops in %s" % [_mode, _rows.size(), _saved, _out])
	if _click_row < 0:
		print("(a) NO CLICK WAS PUSHED: the run never settled, so nothing here is a measurement")
		quit(1)
		return
	# BOX 1. The click went in during row `_click_row`; the draw of that frame is reported by the
	# NEXT row, which is the one-frame phase this tool is built around.
	var answer_row := _click_row + 1
	if answer_row >= _rows.size():
		print("(a) the run ended before the frame after the click was sampled")
		quit(1)
		return
	var answer: Dictionary = _rows[answer_row]
	var before: Dictionary = _rows[_click_row]
	print("(1) THE FRAME THE CLICK HAPPENED IN: dest %s, before the click it was %s"
			% ["EMPTY" if answer["dest"] == Rect2() else str(answer["dest"]),
			"EMPTY" if before["dest"] == Rect2() else str(before["dest"])])
	print("    the sim had target %s and pos %s in that frame -- a target of <null> is the proof "
			% [str(answer["target"]), str(answer["tile"])]
			+ "the mark came from the click and not from a bundle")
	# BOX 2. HOW LONG NOT ONE WORLD PIXEL MOVED, and whether the mark was up for all of it. Measured
	# off the scroll and not off the sim's tile: the sim advancing a tile is not the screen moving,
	# because the playout buffer holds that position for up to 2.5 ticks before the body is drawn
	# anywhere new. The screen is what the player is complaining about.
	var frozen := 0
	var marked := 0
	var at_rest: Vector2 = before["scroll"]
	var froze_until := float(before["t"])
	for i in range(answer_row, _rows.size()):
		var r: Dictionary = _rows[i]
		if ((r["scroll"] as Vector2) - at_rest).length() > 0.01:
			break
		frozen += 1
		froze_until = r["t"]
		if r["dest"] != Rect2():
			marked += 1
	print("(2) NOT ONE WORLD PIXEL MOVED FOR %d frames (%.0f ms from the click); the mark was "
			% [frozen, (froze_until - float(before["t"])) * 1000.0]
			+ "painted in %d of them" % marked)
	print("    NOTE: this harness ticks its own sim locally, so the wait here is one local tick and "
			+ "not the relay's 190-394 ms (Maren, ASSA-197). The wait is her measurement; what this "
			+ "tool measures is that the mark is up for the whole of it, starting in frame one.")
	# BOX 4, FIRST HALF: arrival clears it.
	var arrived := -1
	var cleared := -1
	for i in range(answer_row, _rows.size()):
		var r: Dictionary = _rows[i]
		if arrived < 0 and (r["tile"] as Vector2i) == _target:
			arrived = i
		if arrived >= 0 and cleared < 0 and r["dest"] == Rect2():
			cleared = i
	if arrived < 0:
		print("(4) the walk had not arrived when the run ended, so arrival is not measured here")
	elif cleared < 0:
		print(("(4) ARRIVED at %s in row %d (t=%.3f) and the mark was STILL PAINTED in every frame "
				+ "to the end of the run: either it does not clear on arrival, or the run ended too "
				+ "early to show it") % [_target, arrived, float(_rows[arrived]["t"])])
	else:
		print(("(4) ARRIVED at %s in row %d (t=%.3f); the mark was last painted in row %d and was "
				+ "gone from row %d (t=%.3f) on, %d frames of the run later")
				% [_target, arrived, float(_rows[arrived]["t"]), cleared - 1, cleared,
				float(_rows[cleared]["t"]), _rows.size() - cleared])
	# (5) THE FRAME COST, AND THE ONLY COLUMN WORTH COMPARING IS THE THIRD ONE. The strip's frames
	# each carry a GPU read-back and a PNG write, which cost more than everything else in this run
	# put together -- a median over them is a median of the instrument. So the A/B number is the
	# stretch after the strip closes, where the mark is still up (or still suppressed) and nothing
	# is being photographed.
	var all_frames: Array[float] = []
	var after_click: Array[float] = []
	var unphotographed: Array[float] = []
	for i in range(_rows.size()):
		if i == 0:
			continue
		var ms := float(_rows[i]["frame"]) * 1000.0
		all_frames.append(ms)
		if i > _click_row:
			after_click.append(ms)
			if float(_rows[i]["t"]) > (_clicked_at - _started_at) + STRIP_SECONDS + 0.05:
				unphotographed.append(ms)
	print("(5) FRAME COST: median %.2f ms over %d frames; %.2f ms over the %d after the click; "
			% [_median(all_frames), all_frames.size(), _median(after_click), after_click.size()]
			+ "**%.2f ms over the %d after the strip closed** -- compare the modes on THAT one"
			% [_median(unphotographed), unphotographed.size()])
	if _mode == "nomark":
		if _suppressed > 0:
			print("    DIRTY: %d frames of this nomark run drew the mark anyway, so the A/B is not "
					% _suppressed + "a comparison -- the suppression races main.gd's own refresh")
		else:
			print("    clean: 0 of %d frames drew the mark" % _rows.size())
	quit(0)
