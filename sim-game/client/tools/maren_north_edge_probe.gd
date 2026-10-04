extends SceneTree
## ASSA-156 FOLLOW-UP: THE CAMERA CLAMP THE PANEL'S CEILING DOES NOT COVER (Maren).
##
## `AssayScene.player_ceiling` says in its own words why one number answers for every world: "an
## UNCLAMPED camera is one that is centring, and a centred camera draws you in the same place in
## every world". True, and it is the whole of the claim -- a CLAMPED camera does not centre, and the
## north clamp is the direction that moves you UP, toward a panel anchored to the map's top.
##
## So: ask, do not reason. Walk the player down column 48 of a real 96x64 world, take the player's
## drawn rect out of the REAL `placements()` at the REAL `world_rect()`, and compare its top against
## the REAL ceiling the panel is capped to.
##
##   godot --headless --path client --script res://tools/maren_north_edge_probe.gd
##
## **IT NOW RUNS TWICE, AND THE FIRST PASS IS MAREN'S ORIGINAL READING** (Marlow, ASSA-184). The fix
## is a bound on the camera's north clamp (`AssayScene.north_headroom`), which is a fourth argument
## to `camera_origin` -- so a probe that took three would no longer compile, and a probe quietly
## updated to pass the new bound would print a clean table with no way to see what it used to print.
## Pass 1 is `headroom 0`: the camera this file was written to measure, so the 6-and-2 finding stays
## reproducible from the instrument that found it. Pass 2 is the shipped bound.
func _initialize() -> void:
	var map := AssayHud.world_rect()
	var manifest: Dictionary = AssaySprites.manifest()
	var world := Vector2i(96, 64)
	var ceiling: float = AssayScene.player_ceiling(manifest, map.size)
	print("map rect ", map, "   world ", world, "   player_ceiling (map-local px) ", ceiling)
	for headroom: float in [0.0, AssayScene.north_headroom(manifest, map.size)]:
		print("\n=== camera north bound %.1f px (%s) ===" % [-headroom,
				"before ASSA-184" if headroom == 0.0 else "shipped"])
		_walk(map, manifest, world, ceiling, headroom)
	quit(0)


func _walk(map: Rect2, manifest: Dictionary, world: Vector2i, ceiling: float,
		headroom: float) -> void:
	var covered := PackedInt32Array()
	var touched := PackedInt32Array()
	for row in range(0, world.y):
		var at := Vector2(48.0, float(row))
		var origin := AssayScene.camera_origin(at, world, map.size, headroom)
		var places: Array[Dictionary] = AssayScene.placements({
			"world_tiles": world, "origin": origin, "size": map.size,
			"spawn": Vector2i(48, 32), "ore": {}, "players": [
				{"at": at, "facing": "S", "moving": false, "mine": true}],
			"buildings": [], "manifest": manifest, "seconds": 0.0,
		})
		var body := Rect2()
		for p in places:
			if String(p.get("asset", "")) == "player":
				body = p["dest"] as Rect2
		if body.size == Vector2.ZERO:
			print("row %d: NO PLAYER PLACEMENT" % row)
			continue
		var clamped := origin.y <= -headroom or origin.y >= float(world.y) * 32.0 - map.size.y
		# WHOLLY behind a panel that fills the map's width from its top down to `ceiling`.
		if body.end.y <= ceiling:
			covered.append(row)
		elif body.position.y < ceiling:
			touched.append(row)
		if row < 12 or clamped:
			print("row %2d  origin.y %8.1f  clamped %s  body y %7.1f..%7.1f  %s" % [row, origin.y,
					clamped, body.position.y, body.end.y,
					("WHOLLY BEHIND" if body.end.y <= ceiling
					else ("part behind" if body.position.y < ceiling else "clear"))])
	print("ceiling %.1f" % ceiling)
	print("rows WHOLLY behind the panel: %d of %d -> %s" % [covered.size(), world.y, covered])
	print("rows PART behind the panel:   %d of %d -> %s" % [touched.size(), world.y, touched])
