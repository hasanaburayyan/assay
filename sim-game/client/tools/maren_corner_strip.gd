extends SceneTree
## MAREN, ASSA-201 BOX 4: WHAT A DIAGONAL `goto` LOOKS LIKE WHEN IT TURNS THE CORNER.
##
##   godot --path client --script res://tools/maren_corner_strip.gd -- <out_dir> [seed] [tx] [ty]
##
## NOT `--headless`. The question on box 4 is not "what is the number", it is "can my eye see it at
## 1x", and a dummy rendering driver answers that with a blank image (`window_shot.gd` says the same
## thing at more length). Every frame between `CAPTURE_FROM` and `CAPTURE_TO` seconds after the
## `goto` is read back off the real window and written as a crop, so the strip is consecutive
## frames and not every nth.
##
## WHY A CROP AND NOT THE WHOLE WINDOW. `main.gd:2396` puts the CAMERA on the drawn position, so on
## this walk the body barely moves on screen and the WORLD slides underneath it. A fixed screen
## rectangle is therefore the honest frame: whatever moves inside it is what the player sees moving.
## The rect is fixed for the whole run (chosen from the body's position in the first captured frame)
## because a crop that follows the body would subtract the very motion under judgement.
##
## WHAT IT MEASURES BESIDE THE PICTURE, and this is the part that reframes the item. ASSA-201 is
## titled "one goto changes drawn speed mid-walk by 29%". That is true of the velocity MAGNITUDE.
## On `goto 76 48` from (56,40) the sim advances x by one tile on all 20 ticks and y on the first 8
## (`goto-14247-76-48.txt`), so the component in the direction of travel for 12 of 20 ticks never
## changes rate at all. This tool reads the x and y scroll of a NAMED FIXED WORLD TILE per frame, so
## the two components are reported separately instead of being collapsed into a magnitude.
##
## THE CONTROL IS THE SAME ONE ASSA-200 NEEDED: a fixed world tile, named here and not "the first
## ground placement", because `visible_tiles` floors the camera and a sample that moves with the
## window reports a jump of its own.
##
## THE INSTRUMENT COSTS FRAMES AND SAYS SO. A GPU read-back per frame is not free, so the report
## prints the frame deltas during capture beside the deltas of the uncaptured stretch before it. A
## strip is a picture of this Mac at the frame rate printed on it (Marlow's point, and right).

const TILE_PX := 32.0
const TICK_SECONDS := 0.1
## The corner on seed 14247's `goto 76 48` is at tick 8, i.e. 0.8 s in. Capture a window around it
## wide enough to hold the last diagonal frames and the first straight ones.
const CAPTURE_FROM := 0.45
const CAPTURE_TO := 1.25
const CROP := Vector2i(192, 192)
const RUN_CEILING := 180.0

var _out := "."
var _seed := "14247"
var _target := Vector2i(76, 48)
var _screen: Node
var _asked: Array = []
var _started := false
var _done := false
var _started_at := 0.0
var _next_tick := 0.0
var _ceiling := 0.0
var _crop_at := Vector2i(-1, -1)
var _rows: Array[Dictionary] = []
var _saved := 0
## Which world tile the scroll is read off. Fixed for the run and printed.
var _anchor := Vector2i(56, 40)
var _last_frame := 0.0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_out = String(argv[0]) if argv.size() > 0 else "."
	_seed = String(argv[1]) if argv.size() > 1 else "14247"
	if argv.size() > 3:
		_target = Vector2i(int(argv[2]), int(argv[3]))
	_ceiling = Time.get_unix_time_from_system() + RUN_CEILING
	DirAccess.make_dir_recursive_absolute(_out)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	print("MAREN CORNER STRIP -- seed %s, goto %s, window %s, map rect %s"
			% [_seed, _target, DisplayServer.window_get_size(), Rect2(Vector2.ZERO, root.size)])


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  maren_corner_strip.gd ran past its %ds ceiling" % int(RUN_CEILING))
		quit(1)
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "maren")
		if welcome == "":
			print("DEAD: no world on seed %s" % _seed)
			_done = true
			quit(1)
			return true
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		if not _screen._sim.running():
			print("DEAD: offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
			_done = true
			quit(1)
			return true
		_started = true
		_started_at = _now()
		_next_tick = _started_at
		_last_frame = _started_at
		_anchor = _screen._sim.spawn_tile() as Vector2i
		_screen._client.submit(AssayActions.move_to(_target))
		print("spawn %s -> goto %s ; scroll read off the fixed world tile %s"
				% [_anchor, _target, _anchor])
		return false

	var now := _now()
	var since := now - _started_at
	var frame := now - _last_frame
	_last_frame = now
	if since > CAPTURE_TO + 0.35:
		_report()
		return true
	if now >= _next_tick:
		_next_tick += TICK_SECONDS
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
	_sample(since, frame)
	return false


## ONE FRAME: where the body is drawn, where a fixed world tile is drawn, and -- inside the capture
## window -- the pixels themselves.
func _sample(since: float, frame: float) -> void:
	var view: Dictionary = _screen._world.view
	if view.is_empty():
		return
	var origin: Vector2 = view.get("origin", Vector2.ZERO)
	var map: Vector2 = (_screen._world as Control).position
	var body := Vector2(INF, INF)
	for entry in AssayScene.placements(view):
		var place: Dictionary = entry
		if String(place["asset"]) == "player":
			body = map + (place["dest"] as Rect2).position
			break
	if body.x == INF:
		return
	# The fixed world tile, computed the way `_place` does it: tile * TILE_PX - origin.
	var scroll := map + Vector2(_anchor) * TILE_PX - origin
	# ONE PLAYER IN THIS RUN, so the first entry is mine. `mine` is not a key every build sets and
	# a `get("mine")` that silently misses prints an empty column that reads as "no facing" -- it
	# did exactly that on the first run of this tool.
	var facing := ""
	var players: Array = view.get("players", [])
	if not players.is_empty():
		facing = String((players[0] as Dictionary).get("facing", ""))
	var row := {"t": since, "frame": frame, "body": body, "scroll": scroll,
			"tile": _my_tile(), "facing": facing, "shot": ""}
	if since >= CAPTURE_FROM and since <= CAPTURE_TO:
		if _crop_at.x < 0:
			# FIXED FOR THE RUN, from the first captured frame. A rect that followed the body would
			# subtract the motion this strip exists to show.
			_crop_at = Vector2i(body) - CROP / 2 + Vector2i(int(TILE_PX / 2), int(TILE_PX / 2))
			_crop_at = _crop_at.clamp(Vector2i.ZERO, Vector2i(root.size) - CROP)
			print("crop rect fixed at %s %s (body was at %s)" % [_crop_at, CROP, body])
		var image := root.get_texture().get_image()
		if image != null:
			var cut := image.get_region(Rect2i(_crop_at, CROP))
			var name := "f%03d.png" % _saved
			if cut.save_png("%s/%s" % [_out, name]) == OK:
				row["shot"] = name
				_saved += 1
	_rows.append(row)


func _my_tile() -> Vector2i:
	var id: int = _screen._client.player_id
	for entry in _screen._sim.players():
		var player: Dictionary = entry
		if int(player["id"]) == id:
			return player["pos"]
	return Vector2i(-1, -1)


func _report() -> void:
	_done = true
	print("")
	print("frames %d, crops %d, crop rect %s %s" % [_rows.size(), _saved, _crop_at, CROP])
	print("  t     frame_ms  body.x   body.y   scroll.x scroll.y  d_scroll.x d_scroll.y  tile      face shot")
	var prev: Dictionary = {}
	for entry in _rows:
		var r: Dictionary = entry
		var dx := 0.0
		var dy := 0.0
		if not prev.is_empty():
			dx = (r["scroll"] as Vector2).x - (prev["scroll"] as Vector2).x
			dy = (r["scroll"] as Vector2).y - (prev["scroll"] as Vector2).y
		print("%6.3f %8.1f %8.2f %8.2f %9.2f %9.2f %11.2f %10.2f  %-9s %-4s %s"
				% [r["t"], r["frame"] * 1000.0, (r["body"] as Vector2).x, (r["body"] as Vector2).y,
				(r["scroll"] as Vector2).x, (r["scroll"] as Vector2).y, dx, dy,
				str(r["tile"]), r["facing"], r["shot"]])
		prev = r
	# THE TWO COMPONENTS, REPORTED APART. A magnitude hides which of them changed.
	_leg("DIAGONAL leg (both axes stepping)", 0.15, 0.78)
	_leg("STRAIGHT leg (x only)", 0.92, CAPTURE_TO)
	print("")
	print("NOTE: the scroll is the world moving under a camera locked to the drawn body, so its")
	print("per-frame delta IS the drawn speed. x and y are printed apart on purpose: on this walk")
	print("the sim steps x on every tick and y only on the first 8, so a magnitude change of -29%")
	print("can be an x-rate that never changed. Read the two columns, not their hypotenuse.")
	quit(0)


func _leg(label: String, from: float, to: float) -> void:
	var xs := 0.0
	var ys := 0.0
	var secs := 0.0
	var n := 0
	var prev: Dictionary = {}
	for entry in _rows:
		var r: Dictionary = entry
		var t: float = r["t"]
		if t < from or t > to:
			prev = r
			continue
		if not prev.is_empty() and float(prev["t"]) >= from:
			xs += absf((r["scroll"] as Vector2).x - (prev["scroll"] as Vector2).x)
			ys += absf((r["scroll"] as Vector2).y - (prev["scroll"] as Vector2).y)
			secs += t - float(prev["t"])
			n += 1
		prev = r
	if secs <= 0.0:
		print("%s: no frames in %.2f..%.2f" % [label, from, to])
		return
	print("%s  %d frames over %.3fs: |x| %.1f px/s (%.2f tiles/s), |y| %.1f px/s (%.2f tiles/s), speed %.2f tiles/s"
			% [label, n, secs, xs / secs, xs / secs / TILE_PX, ys / secs, ys / secs / TILE_PX,
			Vector2(xs / secs, ys / secs).length() / TILE_PX])
