extends SceneTree
## MAREN'S PROBE: IS THE BODY'S DRAWN POSITION QUANTISED TO A WHOLE TILE?
##
##   godot --headless --path client --script res://tools/maren_snap_probe.gd
##
## WHY THIS IS NOT THE MOTION PROBE AGAIN. `maren_motion_probe.gd` samples
## `main.gd::_refresh_world`'s `view["players"][i]["at"]`, which is the LERP'S OUTPUT. Every motion
## number this studio owns -- mine on ASSA-148, Marlow's "0.25 to 0.79 tiles", the bar on ASSA-197 --
## is measured there. But `AssayScene._standing` does `Vector2i(corner.floor())` on that float and
## `_place` draws from `Vector2(tile) * TILE_PX`, so the number we measure is thrown away one call
## later. A probe that reads `at` cannot see a floor that happens after it: a playout clock could go
## perfectly smooth and this probe would be unchanged.
##
## SO THIS ONE READS THE RENDERER'S OWN OUTPUT RECTANGLE. It sweeps a player's fractional position
## across one tile, calls `AssayScene.placements` (not a copy of its arithmetic), and prints the
## player placement's `dest.position` beside `foot_mark`'s, which takes the float `at` directly.
## If the body is quantised and the mark is not, they separate by up to a whole tile within one tick.
##
## THE CONTROL IS BUILT IN: ONE FIXED GROUND TILE comes out of the same call and its dest must slide
## smoothly with the camera. A run where the GROUND also steps would mean the camera is the quantised
## thing and this probe is measuring the wrong floor.
##
## AND THE CONTROL'S OWN FIRST VERSION WAS BROKEN, which is why it names a tile. It took "the first
## ground placement", and `visible_tiles` floors the camera, so the first VISIBLE tile changes as the
## window scrolls: the control printed a 28.8 px jump of its own at frac 0.80 and would have let me
## argue the camera steps too. The instrument moved, not the subject.

const WORLD := Vector2i(96, 64)
const VIEW := Vector2(912.0, 600.0)
const STEPS := 10
## A tile well inside the window at every frac of the sweep, named so the control cannot drift.
const GROUND_TILE := Vector2i(50, 40)


func _initialize() -> void:
	var manifest: Dictionary = AssaySprites.manifest()
	if manifest.is_empty():
		print("NO MANIFEST: assets/sprites/manifest.json did not parse")
		quit(1)
		return
	print("MAREN SNAP PROBE -- world %s, view %s, TILE_PX %d" % [WORLD, VIEW, int(AssayScene.TILE_PX)])
	print("control ground tile: %s (fixed, so the sample cannot move with the window)" % GROUND_TILE)
	print("frac  body_dest.x  foot_mark.x  body-foot  ground_dest.x  d(body)  d(ground)")
	var prev_body := INF
	var prev_ground := INF
	var body_steps: Array[float] = []
	var ground_steps: Array[float] = []
	for i in range(STEPS + 1):
		var frac := float(i) / float(STEPS)
		var at := Vector2(56.0 + frac, 40.0)
		var origin := AssayScene.camera_origin(at, WORLD, VIEW, 0.0)
		var view := {
			"world_tiles": WORLD,
			"origin": origin,
			"size": VIEW,
			"spawn": Vector2i(56, 40),
			"ore": {},
			"players": [{"at": at, "facing": "E", "moving": true, "mine": true}],
			"buildings": [],
			"manifest": manifest,
			"seconds": 0.0,
		}
		var body := INF
		var ground := INF
		for entry in AssayScene.placements(view):
			var place: Dictionary = entry
			if String(place["asset"]) == "player" and body == INF:
				body = (place["dest"] as Rect2).position.x
			if String(place["asset"]) == "ground" and _is_tile(place, GROUND_TILE, origin):
				ground = (place["dest"] as Rect2).position.x
		var foot := AssayScene.foot_mark(at, origin).position.x
		var db := 0.0 if prev_body == INF else body - prev_body
		var dg := 0.0 if prev_ground == INF else ground - prev_ground
		if prev_body != INF:
			body_steps.append(db)
			ground_steps.append(dg)
		print("%.2f  %11.2f  %11.2f  %9.2f  %13.2f  %7.2f  %9.2f"
				% [frac, body, foot, body - foot, ground, db, dg])
		prev_body = body
		prev_ground = ground
	print("")
	print("BODY per-step dx: min %.2f max %.2f  (0 means the body does not move on screen at all)"
			% [_min(body_steps), _max(body_steps)])
	print("GROUND per-step dx: min %.2f max %.2f  (the control: the camera is continuous)"
			% [_min(ground_steps), _max(ground_steps)])
	print("")
	print("ONE WHOLE TICK, tile 56 -> 57, the step the player sees:")
	_tick_edge(manifest)
	quit(0)


## THE TILE BOUNDARY, which the sweep above stops just short of: the drawn body's screen position at
## frac -> 1 on tile 56 against frac = 0 on tile 57. A quantised body pays the whole tile here.
func _tick_edge(manifest: Dictionary) -> void:
	for pair in [[56.0, 0.99], [57.0, 0.0]]:
		var at := Vector2(float(pair[0]) + float(pair[1]), 40.0)
		var origin := AssayScene.camera_origin(at, WORLD, VIEW, 0.0)
		var view := {
			"world_tiles": WORLD, "origin": origin, "size": VIEW, "spawn": Vector2i(56, 40),
			"ore": {}, "players": [{"at": at, "facing": "E", "moving": true, "mine": true}],
			"buildings": [], "manifest": manifest, "seconds": 0.0,
		}
		for entry in AssayScene.placements(view):
			var place: Dictionary = entry
			if String(place["asset"]) == "player":
				print("  at %.2f -> body_dest.x %.2f, foot_mark.x %.2f"
						% [at.x, (place["dest"] as Rect2).position.x,
						AssayScene.foot_mark(at, origin).position.x])
				break


## IS THIS PLACEMENT THE NAMED TILE? Asked of the dest rect rather than carried in the placement,
## because `placements` does not label a tile and I am not adding a field to the thing under test.
func _is_tile(place: Dictionary, tile: Vector2i, origin: Vector2) -> bool:
	var want := Vector2(tile) * AssayScene.TILE_PX - origin
	return (place["dest"] as Rect2).position.is_equal_approx(want)


func _min(xs: Array[float]) -> float:
	var out := INF
	for x in xs:
		out = minf(out, x)
	return out


func _max(xs: Array[float]) -> float:
	var out := -INF
	for x in xs:
		out = maxf(out, x)
	return out
