extends SceneTree
## WHAT THE LOG PANEL'S BOUND ACTUALLY IS, on the real map and on the test window.
##
##   godot --headless --path client --script res://tools/ceiling_numbers.gd
##
## `AssayScene.player_ceiling` and `north_headroom` are pure, so this is four numbers and no world.
## It exists because ASSA-197 moved them -- removing the floor from `_place` made the ceiling the
## sprite's top instead of a tile above it -- and a comment that claims "8 lines becomes 9" should be
## something somebody can re-run rather than something I did once. Measured 2026-10-04 on the real
## 912x600 map: ceiling 220 -> 252, north_headroom 252 -> 284, log lines 8 -> 9 of 14 at a 22 px
## pitch. The 640x320 row is the size `tests/test_scene_view.gd` asserts against.

func _initialize() -> void:
	var manifest := AssaySprites.manifest()
	var map: Vector2 = AssayHud.world_rect().size
	for view: Vector2 in [map, Vector2(640.0, 320.0)]:
		var ceiling := AssayScene.player_ceiling(manifest, view)
		var room := AssayScene.north_headroom(manifest, view)
		print("view %s  ceiling %.1f  north_headroom %.1f" % [view, ceiling, room])
		for pitch: float in [18.0, 20.0, 22.0]:
			print("   pitch %.0f chrome 38 newest 18 -> %d lines of 14" % [pitch,
					AssayHud.log_lines_that_fit(ceiling, 38.0, 18.0, pitch, 14)])
	quit(0)
