extends RefCounted
## THE SCENE, ASSERTED WITHOUT A SCREEN (ASSA-119 box 7).
##
## Maren wrote that box deliberately as a test and not as a screenshot, and her reason is the one that
## cost this studio two wake-ups: "a renderer whose only proof is a picture nobody in this studio can
## take is how two engineers each spent a wake-up proving the window did not exist when it did". There
## IS a renderer now (`tools/window_shot.gd`), and a picture still cannot tell you a sprite is one row
## off, half a tile high, or in the wrong species' tint. Those look plausible and nobody notices for a
## week. So every placement decision is arithmetic in `AssayScene` and this file checks the arithmetic.
##
## AGAINST THE REAL MANIFEST, NOT A FIXTURE OF MY OWN NUMBERS, wherever the question is "does the game
## draw what the pipeline shipped". A fixture would keep passing after Cove renames a row, which is the
## exact failure `AssaySprites._row_for` was written to avoid (ASSA-66). Fixtures are used only for the
## questions that are about the CAMERA, where a hand-built world is clearer than a real one.
##
## WHAT IS DELIBERATELY NOT HERE: anything about whether the picture is good. Taste cannot fail a test.
## What can fail a test is a tile that is not 32 px, a row that does not exist, a body drawn past a
## position the sim produced, and a click that lands on the wrong tile -- and all four have a test.

const SPRITES := "res://assets/sprites/"
const MANIFEST := SPRITES + "manifest.json"
## A window a bit smaller than the real 912x600, so the numbers in the assertions are easy to check by
## hand: 20 by 10 tiles exactly.
const WINDOW := Vector2(640.0, 320.0)

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


## A world with one small deposit and one player, far from every edge so the camera never clamps.
func _view(extra := {}) -> Dictionary:
	var at := {
		"world_tiles": Vector2i(96, 64),
		"origin": Vector2.ZERO,
		"size": WINDOW,
		"spawn": Vector2i(48, 32),
		"ore": {},
		"players": [],
		"manifest": _manifest(),
		"seconds": 0.0,
	}
	for key in extra:
		at[key] = extra[key]
	return at


func _of(places: Array, asset: String) -> Array:
	var found := []
	for place in places:
		if String((place as Dictionary).get("asset", "")) == asset:
			found.append(place)
	return found


## THE PREMISE OF EVERY TEST BELOW. If the manifest cannot be read, every count comes out zero and a
## suite full of zero-vs-zero comparisons passes while nothing is drawn at all.
func test_the_shipped_manifest_is_readable_and_names_the_four_world_assets() -> bool:
	var manifest := _manifest()
	if manifest.is_empty():
		return _fail("%s did not parse, so every assertion in this file is vacuous" % MANIFEST)
	for asset in ["ground", "ore", "player", "spawn"]:
		if not manifest.has(asset):
			return _fail("the manifest has no `%s`, which the world view draws" % asset)
	return true


## BOX 7, THE COUNT: a sprite per ground tile the window covers, and not one more.
func test_every_tile_the_camera_covers_gets_a_ground_sprite() -> bool:
	var places := AssayScene.placements(_view())
	var ground := _of(places, "ground")
	# 640/32 by 320/32, with the camera on a tile boundary.
	if ground.size() != 20 * 10:
		return _fail("a %s window at 32px is 20x10 tiles and got %d ground sprites"
				% [WINDOW, ground.size()])
	var seen := {}
	for place in ground:
		seen[(place as Dictionary)["dest"].position] = true
	if seen.size() != ground.size():
		return _fail("%d ground sprites landed on %d distinct places, so some tile is drawn twice"
				% [ground.size(), seen.size()])
	return true


## AND THE PARTIAL TILES AT THE EDGE ARE DRAWN. 912x600 is 28.5 by 18.75 tiles; a whole-tile window
## would leave a dark strip down one side that moves as you walk.
func test_a_camera_between_tiles_still_covers_the_whole_window() -> bool:
	var view := _view({"origin": Vector2(16.0, 8.0)})
	var ground := _of(AssayScene.placements(view), "ground")
	if ground.size() != 21 * 11:
		return _fail("half a tile off the grid needs 21x11 sprites to cover 20x10 tiles, got %d"
				% ground.size())
	var covered := Rect2()
	for place in ground:
		covered = covered.merge((place as Dictionary)["dest"])
	if not covered.encloses(Rect2(Vector2.ZERO, WINDOW)):
		return _fail("the ground covers %s, which does not cover the window %s" % [covered, WINDOW])
	return true


## BOX 2: A TILE IS 32 SCREEN PIXELS, and a sprite taller than its footprint keeps its proportions.
##
## MEASURED AGAINST THE MANIFEST'S OWN FRAME, so this cannot drift into "32 because I typed 32": the
## expected size is `frame_px * (32 / authored px per tile)`, which for today's sheets means a ground
## tile is 32x32, a player is 32x64 (a body over a pair of feet) and the spawn pad is 96x104.
func test_a_tile_is_32_screen_pixels_and_every_sprite_is_at_that_scale() -> bool:
	var manifest := _manifest()
	var view := _view({
		"ore": {Vector2i(2, 2): {"species": 0, "grade": "B", "depleted": false}},
		"players": [{"at": Vector2(5.0, 5.0), "facing": "S", "moving": false}],
		"spawn": Vector2i(8, 4),
	})
	for place in AssayScene.placements(view):
		var asset := String((place as Dictionary)["asset"])
		var spec: Dictionary = manifest[asset]
		var frame: Array = spec["frame_px"]
		var tiles: Array = spec["tiles"]
		var scale := AssayScene.TILE_PX / (float(frame[0]) / float(tiles[0]))
		var want := Vector2(float(frame[0]), float(frame[1])) * scale
		var got: Vector2 = (place as Dictionary)["dest"].size
		if not got.is_equal_approx(want):
			return _fail("`%s` is drawn %s and its frame at 32px a tile is %s" % [asset, got, want])
		if not is_equal_approx(float(tiles[0]) * AssayScene.TILE_PX, got.x):
			return _fail("`%s` claims %s tiles wide but is drawn %d px" % [asset, tiles[0], got.x])
	return true


## THE RECTANGLE CUT OUT OF THE SHEET IS THE ROW THE MANIFEST NAMES, by index, not by a number here.
##
## This is the assertion a screenshot cannot make. One row off is a picture of the wrong grade of rock
## or a player facing the wrong way, and both look entirely plausible.
func test_the_source_rectangle_is_the_row_the_manifest_names() -> bool:
	var manifest := _manifest()
	var view := _view({
		"ore": {Vector2i(1, 1): {"species": 2, "grade": "A", "depleted": false}},
		"players": [{"at": Vector2(4.0, 4.0), "facing": "NE", "moving": true}],
	})
	for place in AssayScene.placements(view):
		var at: Dictionary = place
		var spec: Dictionary = manifest[String(at["asset"])]
		var rows: Array = spec["rows"]
		var names := []
		for row in rows:
			names.append(String((row as Dictionary).get("name", "")))
		var index := names.find(String(at["row"]))
		if index < 0:
			return _fail("`%s` is drawn from row `%s`, which `%s` does not have: %s"
					% [at["asset"], at["row"], MANIFEST, names])
		var frame: Array = spec["frame_px"]
		var want := Rect2(float(int(at["frame"])) * float(frame[0]), float(index) * float(frame[1]),
				float(frame[0]), float(frame[1]))
		if not at["src"].is_equal_approx(want):
			return _fail("`%s` row `%s` frame %d cuts %s, and the sheet's own grid says %s"
					% [at["asset"], at["row"], int(at["frame"]), at["src"], want])
	return true


## AND THE ASSETS IT NAMES ARE ONES THIS PROJECT CAN LOAD. `test_sprites.gd` proves every shipped PNG
## loads; this proves the VIEW asks for those and not for a name nothing ships.
func test_every_asset_the_scene_names_loads_with_pixels_in_it() -> bool:
	var view := _view({
		"ore": {Vector2i(1, 1): {"species": 0, "grade": "C", "depleted": true}},
		"players": [{"at": Vector2(3.0, 3.0), "facing": "W", "moving": false}],
		"spawn": Vector2i(8, 5),
	})
	var assets := {}
	for place in AssayScene.placements(view):
		assets[String((place as Dictionary)["asset"])] = true
	if assets.size() < 4:
		return _fail("the scene named %d assets; ground, ore, player and spawn are four" % assets.size())
	for asset in assets:
		var texture: Texture2D = load("%s%s.png" % [SPRITES, asset])
		if texture == null or texture.get_width() <= 0:
			return _fail("the scene draws `%s` and `%s%s.png` will not load" % [asset, SPRITES, asset])
	return true


## ORE: THE GRADE PICKS THE ROW, THE SPECIES PICKS THE TINT, and neither is decided here.
func test_an_ore_tile_wears_its_species_tint_and_its_grade_row() -> bool:
	for species in range(AssayHud.SPECIES_TINTS.size()):
		for grade in ["C", "B", "A"]:
			var view := _view({"ore": {Vector2i(3, 3):
					{"species": species, "grade": grade, "depleted": false}}})
			var ore := _of(AssayScene.placements(view), "ore")
			if ore.size() != 1:
				return _fail("one ore tile produced %d sprites" % ore.size())
			var at: Dictionary = ore[0]
			if not String(at["row"]).begins_with(grade + "_full"):
				return _fail("grade %s drew row `%s`" % [grade, at["row"]])
			if at["tint"] != AssayHud.species_tint(species):
				return _fail("species %d is tinted %s and the map's own table says %s"
						% [species, at["tint"], AssayHud.species_tint(species)])
	return true


## EVERY ARRANGEMENT THE SHEET SHIPS GETS DRAWN. The count used to be the literal 2 in `ore_row`,
## which is a failure nothing could see: rendering v2/v3 would have passed every test here and
## every art check, and shipped two rows of art to a client that never asked for them. So this
## test reads the count out of the manifest and fails if any row the sheet has goes unused.
func test_the_view_uses_every_ore_arrangement_the_sheet_ships() -> bool:
	var rows: Array = ((_manifest().get("ore", {}) as Dictionary).get("rows", []) as Array)
	for grade in ["C", "B", "A"]:
		var want := []
		for row in rows:
			var name := String((row as Dictionary).get("name", ""))
			if name.begins_with(grade + "_full_v"):
				want.append(name)
		if want.is_empty():
			return _fail("the shipped sheet has no `%s_full_v*` row at all" % grade)
		var tiles := {}
		# Inside the 20x10-tile window at origin zero, so nothing is culled before it is counted.
		for y in range(10):
			for x in range(20):
				tiles[Vector2i(x, y)] = {"species": 0, "grade": grade, "depleted": false}
		var seen := {}
		for place in _of(AssayScene.placements(_view({"ore": tiles})), "ore"):
			seen[String((place as Dictionary)["row"])] = true
		for name in want:
			if not seen.has(name):
				return _fail("the sheet ships `%s` and 200 tiles of grade %s never drew it: %s"
						% [name, grade, seen.keys()])
	return true


## A SPENT PATCH IS STILL VISIBLE, and still its species. `sim` keeps a depleted deposit so its id
## stays stable, so the view has to have an answer for it, and the sheet ships one.
func test_a_depleted_patch_has_its_own_drawing_and_keeps_its_tint() -> bool:
	var view := _view({"ore": {Vector2i(3, 3): {"species": 4, "grade": "A", "depleted": true}}})
	var ore := _of(AssayScene.placements(view), "ore")
	if ore.size() != 1:
		return _fail("a depleted tile produced %d sprites, not one" % ore.size())
	var at: Dictionary = ore[0]
	if String(at["row"]) != "depleted_full":
		return _fail("a depleted patch drew `%s`" % at["row"])
	if at["tint"] != AssayHud.species_tint(4):
		return _fail("a depleted patch lost its species tint: %s" % at["tint"])
	return true


## THE ROCK DOES NOT BOIL AND DOES NOT CRAWL. Both halves matter: a variant that is random per frame
## makes the ground shimmer, and a constant one makes every tile identical.
func test_a_tiles_variant_is_fixed_to_the_tile_and_not_to_all_tiles() -> bool:
	var first := AssayScene.variant_of(Vector2i(7, 11), 4)
	for _i in range(50):
		if AssayScene.variant_of(Vector2i(7, 11), 4) != first:
			return _fail("the same tile answered two different variants, so the ground shimmers")
	var seen := {}
	for y in range(20):
		for x in range(20):
			seen[AssayScene.variant_of(Vector2i(x, y), 4)] = true
	if seen.size() < 4:
		return _fail("400 tiles used %d of 4 ground variants, so the ground is one drawing"
				% seen.size())
	if AssayScene.variant_of(Vector2i(7, 11), 1) != 0:
		return _fail("an asset with one row must always answer row 0")
	return true


## THE CAMERA CENTRES YOU, AND STOPS AT THE EDGE rather than showing void beside the world.
func test_the_camera_centres_you_and_clamps_at_the_world_edge() -> bool:
	var world := Vector2i(96, 64)
	var middle := AssayScene.camera_origin(Vector2(48.0, 32.0), world, WINDOW)
	var want := Vector2(48.5 * 32.0 - 320.0, 32.5 * 32.0 - 160.0)
	if not middle.is_equal_approx(want):
		return _fail("centred on (48, 32) the camera is at %s and the middle is %s" % [middle, want])
	if AssayScene.camera_origin(Vector2.ZERO, world, WINDOW) != Vector2.ZERO:
		return _fail("standing in the north-west corner the camera went to %s, past the world"
				% AssayScene.camera_origin(Vector2.ZERO, world, WINDOW))
	var far := AssayScene.camera_origin(Vector2(95.0, 63.0), world, WINDOW)
	var edge := Vector2(96.0 * 32.0, 64.0 * 32.0) - WINDOW
	if not far.is_equal_approx(edge):
		return _fail("in the south-east corner the camera is at %s and the last full view is %s"
				% [far, edge])
	# A world smaller than the view has no clamp to make, so it is centred instead.
	var tiny := AssayScene.camera_origin(Vector2(2.0, 2.0), Vector2i(4, 4), WINDOW)
	if not tiny.is_equal_approx((Vector2(128.0, 128.0) - WINDOW) * 0.5):
		return _fail("a world smaller than the window put the camera at %s" % tiny)
	return true


## BOX 3, THE FACING: the eight the sim produces, read off the step it took.
##
## `move_players` is `signum` on both axes, so these eight are the complete set and there is no
## nearest-of-eight rounding to get wrong. "" for no step, which is what keeps a stopped player
## looking the way they were going instead of snapping south.
func test_a_facing_is_the_step_the_sim_actually_took() -> bool:
	var want := {
		Vector2i(0, -1): "N", Vector2i(1, -1): "NE", Vector2i(1, 0): "E", Vector2i(1, 1): "SE",
		Vector2i(0, 1): "S", Vector2i(-1, 1): "SW", Vector2i(-1, 0): "W", Vector2i(-1, -1): "NW",
	}
	for step in want:
		if AssayScene.facing_of(step) != want[step]:
			return _fail("a step of %s faces `%s`, not `%s`"
					% [step, AssayScene.facing_of(step), want[step]])
	if AssayScene.facing_of(Vector2i.ZERO) != "":
		return _fail("standing still reported a facing, which would snap a stopped player round")
	# Every one of the eight has to be a row of the sheet, in both gaits, or a facing is a sprite
	# that does not exist.
	var manifest := _manifest()
	for step in want:
		for moving in [true, false]:
			var row := AssayScene.player_row(want[step], moving)
			var view := _view({"players": [{"at": Vector2(5.0, 5.0), "facing": want[step],
					"moving": moving}]})
			var drawn := _of(AssayScene.placements(view), "player")
			if drawn.size() != 1 or String((drawn[0] as Dictionary)["row"]) != row:
				return _fail("facing %s %s wanted row `%s` and drew %s"
						% [want[step], "walking" if moving else "idle", row, drawn])
			if AssayScene._row_index(manifest["player"], row) < 0:
				return _fail("row `%s` is not in the shipped player sheet" % row)
	return true


## BOX 3, THE GAIT: the walk cycle plays while moving and stops when stopped, off the WALL CLOCK.
##
## MAREN'S RULING, AND IT IS THE OPPOSITE OF WHAT A LOCKSTEP CLIENT WOULD REACH FOR: `walk` is 12 fps
## against 10 ticks a second and the two must NOT be made to line up. The gait is a look; the tick is
## the clock. So this asserts the frame moves with seconds and at the sheet's own rate.
func test_the_walk_cycle_runs_off_the_clock_at_the_sheets_own_rate() -> bool:
	var player: Dictionary = _manifest()["player"]
	var walk: Dictionary = (player["animations"] as Dictionary)["walk"]
	var fps := float(walk["fps"])
	var frames := int(walk["frames"])
	if fps <= 0.0 or frames <= 1:
		return _fail("the shipped walk is %d frames at %s fps, so nothing can animate" % [frames, fps])
	var seen := {}
	for step in range(frames * 2):
		seen[AssayScene.frame_of(player, "walk_S", float(step) / fps)] = true
	if seen.size() != frames:
		return _fail("over two walk cycles the frame took %d of %d values" % [seen.size(), frames])
	if AssayScene.frame_of(player, "walk_S", 0.0) != 0:
		return _fail("the walk does not start on its first frame")
	if AssayScene.frame_of(player, "walk_S", 1.0 / fps) == 0:
		return _fail("one frame's worth of seconds did not advance the walk, so it is frozen")
	# A STATIC ROW NEVER ANIMATES, however much time passes: `ground` has no animations at all.
	for second in [0.0, 0.5, 97.3]:
		if AssayScene.frame_of(_manifest()["ground"], "v0", second) != 0:
			return _fail("the ground animated, and it has no animation in the manifest")
	# AND THE TWO GAITS RUN AT DIFFERENT RATES, which is the thing a single hard-coded fps would lose.
	var idle: Dictionary = (player["animations"] as Dictionary)["idle"]
	if is_equal_approx(float(idle["fps"]), fps):
		return _fail("idle and walk are the same rate in the manifest, so this test proves nothing")
	if AssayScene.frame_of(player, "idle_S", 1.0 / fps) != 0:
		return _fail("idle advanced at the WALK's rate, so one fps is being used for both")
	return true


## THE SPAWN PAD IS CENTRED ON THE SIM'S ONE SPAWN TILE. 3x3 of art over `World::spawn_tile`, which is
## a single tile -- so the art is centred on it rather than the sim's tile being the pad's corner.
func test_the_spawn_pad_is_centred_on_the_sims_spawn_tile() -> bool:
	var view := _view({"spawn": Vector2i(10, 6), "origin": Vector2.ZERO})
	var pad := _of(AssayScene.placements(view), "spawn")
	if pad.size() != 1:
		return _fail("one spawn tile produced %d pads" % pad.size())
	var dest: Rect2 = (pad[0] as Dictionary)["dest"]
	# The pad is 3 tiles wide, so its middle tile is the sim's and it starts one tile west of it.
	var middle := dest.position.x + dest.size.x * 0.5
	if not is_equal_approx(middle, (10.0 + 0.5) * AssayScene.TILE_PX):
		return _fail("the pad's middle is at %s and spawn tile 10 is at %s"
				% [middle, (10.0 + 0.5) * AssayScene.TILE_PX])
	return true


## AND YOU ARE VISIBLE WHILE STANDING ON IT. THIS TEST IS A DEFECT THE FIRST REAL SHOT OF THIS VIEW
## FOUND, which is the reason to take a shot at all.
##
## The pad was sorted in with the bodies by bottom edge, the way `art/mock_scene.py` does it -- and a
## 3x3 pad's footprint ends one row south of the 1x1 player standing in the middle of it, so the pad
## counted as NEARER and painted over them. You spawn on spawn, so that was the whole of your first
## second in the game: a world with no player in it. `mock_scene.py` was never wrong; it just never
## put a body on the pad.
func test_a_player_standing_on_the_spawn_pad_is_drawn_over_it() -> bool:
	var view := _view({"spawn": Vector2i(8, 5),
			"players": [{"at": Vector2(8.0, 5.0), "facing": "S", "moving": false}]})
	var places := AssayScene.placements(view)
	var pad := -1
	var body := -1
	for i in range(places.size()):
		match String((places[i] as Dictionary)["asset"]):
			"spawn": pad = i
			"player": body = i
	if pad < 0:
		return _fail("no spawn pad was drawn, so this test proves nothing")
	if body < 0:
		return _fail("the player standing on spawn was not drawn at all")
	if body < pad:
		return _fail("the pad is drawn after the player standing on it, so you are invisible on "
				+ "the one tile every game starts on")
	return true


## WHAT STANDS IN FRONT OF WHAT: row order, so the nearer thing wins (`art/mock_scene.py`'s rule).
func test_a_nearer_body_is_drawn_over_a_further_one() -> bool:
	var view := _view({"players": [
		{"at": Vector2(5.0, 9.0), "facing": "S", "moving": false},
		{"at": Vector2(5.0, 3.0), "facing": "S", "moving": false},
	]})
	var drawn := _of(AssayScene.placements(view), "player")
	if drawn.size() != 2:
		return _fail("two players drew %d sprites" % drawn.size())
	if (drawn[0] as Dictionary)["dest"].position.y >= (drawn[1] as Dictionary)["dest"].position.y:
		return _fail("the souther player was drawn first, so a body behind covers one in front")
	return true


## NOTHING OUTSIDE THE WINDOW IS HANDED TO THE RENDERER, AND THE CULL IS BY RECTANGLE.
##
## A player's frame is 64x128 for a 1x1 tile, so a body standing on the window's TOP ROW has half of
## itself above the window. Culling by tile would be correct for that one and would clip the head off
## nothing; culling by rectangle is what makes the two different, and the player one row ABOVE the
## top is the case that proves the rectangle is being used -- their feet land exactly on y=0 and not
## one pixel of them is inside, so a tile-based cull would keep them.
func test_the_scene_culls_by_the_rectangle_it_will_draw() -> bool:
	var far := _view({"players": [{"at": Vector2(60.0, 60.0), "facing": "S", "moving": false}]})
	if not _of(AssayScene.placements(far), "player").is_empty():
		return _fail("a player 60 tiles off the window was still handed to the renderer")
	# On the top row: the feet are inside and the head is above. Drawn, and drawn ABOVE the window's
	# own origin, which is the thing `clip_contents` is for.
	var edge := _view({"players": [{"at": Vector2(5.0, 0.0), "facing": "S", "moving": false}]})
	var standing := _of(AssayScene.placements(edge), "player")
	if standing.size() != 1:
		return _fail("a player on the window's top row drew %d sprites" % standing.size())
	if (standing[0] as Dictionary)["dest"].position.y >= 0.0:
		return _fail(("a player on the top row is drawn entirely inside the window, so the frame is"
				+ " not standing on its feet: %s") % (standing[0] as Dictionary)["dest"])
	# One row higher: their feet are on y=0 and nothing of them is inside.
	var gone := _view({"players": [{"at": Vector2(5.0, -1.0), "facing": "S", "moving": false}]})
	if not _of(AssayScene.placements(gone), "player").is_empty():
		return _fail("a player whose whole frame is above the window was handed to the renderer")
	return true


## BOX 6'S HALF THAT A TEST CAN HOLD: the schematic's player mark is not a function of the tile.
##
## It used to be two cells square, so the bigger and harder to navigate the world, the SMALLER you
## got: 18 px on the 96x64 world, 36 on a 32x32 one. Maren measured the consequence on the real shot
## (you were 0.065% of the view, smaller than all eleven deposits). This fails the day somebody writes
## the mark back in terms of `_cell`.
func test_your_mark_on_the_schematic_does_not_shrink_as_the_world_grows() -> bool:
	var small := AssayHud.map_cell(Vector2i(32, 32))
	var big := AssayHud.map_cell(Vector2i(96, 64))
	if small <= big:
		return _fail("the premise is gone: a 32x32 world draws a %s tile and a 96x64 one %s"
				% [small, big])
	if AssayHud.PLAYER_MARK_PX <= 0.0:
		return _fail("a player's mark is %s px" % AssayHud.PLAYER_MARK_PX)
	if is_equal_approx(AssayHud.PLAYER_MARK_PX, big * 2.0):
		return _fail(("a player's mark is exactly two tiles of the 96x64 world, which is what it was"
				+ " when it scaled with the tile"))
	return true


## A POINT GOES BACK TO THE TILE IT CAME FROM, IN BOTH VIEWS.
##
## `point_of_tile` and `_tile_under` are inverses and this is what holds them to it. Sixteen tests
## broke the hour the close-up arrived because three harnesses each held their own copy of the
## schematic's arithmetic; the pair being asserted together is what stops that being a surprise again.
func test_a_click_lands_on_the_tile_the_player_sees_in_both_views() -> bool:
	var screen := _joined()
	if not screen._sim.running():
		return _fail("no offline world: %s" % screen._sim.fail_reason)
	var mine: Vector2i = screen._my_tile()
	for close_up in [true, false]:
		screen._show_close_up(close_up)
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(3, 0), Vector2i(-3, 2), Vector2i(0, -4),
				Vector2i(5, 5)]:
			var tile: Vector2i = mine + offset
			var point: Vector2 = screen.point_of_tile(tile)
			if not AssayHud.world_rect().has_point(point):
				return _fail("%s is %s in the %s view, which is outside the world's rectangle %s"
						% [tile, point, "close-up" if close_up else "schematic",
						AssayHud.world_rect()])
			var back: Variant = screen._tile_under(point)
			if back == null or back != tile:
				return _fail("in the %s view, tile %s is at %s and that point reads back as %s"
						% ["close-up" if close_up else "schematic", tile, point, back])
	screen.queue_free()
	return true


## AND A CLICK IN THE CLOSE-UP WALKS YOU, which is box 7's other half: the view is not a picture, it
## is where a player acts.
func test_a_left_click_in_the_close_up_asks_the_sim_to_walk_there() -> bool:
	var screen := _joined()
	if not screen._sim.running():
		return _fail("no offline world: %s" % screen._sim.fail_reason)
	screen._show_close_up(true)
	var want: Vector2i = screen._my_tile() + Vector2i(4, 3)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen.point_of_tile(want)
	screen._unhandled_input(event)
	if _asked.is_empty():
		return _fail("a left click in the close-up submitted nothing")
	var command: Dictionary = _asked[_asked.size() - 1]
	var target: Dictionary = (command.get("MoveTo", {}) as Dictionary).get("target", {})
	if int(target.get("x", -1)) != want.x or int(target.get("y", -1)) != want.y:
		return _fail("clicked %s in the close-up and the command says %s" % [want, command])
	screen.queue_free()
	return true


## A BODY IS NEVER DRAWN PAST A POSITION THE SIM PRODUCED.
##
## MAREN'S MOTION RULING, AS A TEST, and it is the one assertion in this file that is about the repo's
## first principle rather than about a picture. A renderer may interpolate the DRAWN position; it may
## not interpolate state. So the drawn position must always sit on the segment between the PREVIOUS
## tick's tile and the CURRENT one -- never past it toward where a `target` suggests they are going,
## because that is a second copy of the movement rule living outside `sim`.
##
## Walked for real through the screen's own click path, so what is checked is the client that ships.
func test_a_walking_body_is_drawn_between_two_tiles_the_sim_produced() -> bool:
	var screen := _joined()
	if not screen._sim.running():
		return _fail("no offline world: %s" % screen._sim.fail_reason)
	screen._show_close_up(true)
	var from: Vector2i = screen._my_tile()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen.point_of_tile(from + Vector2i(6, 4))
	screen._unhandled_input(event)
	var steps := 0
	for _i in range(12):
		_tick(screen)
		var was: Vector2i = screen._was.get(screen._client.player_id, from)
		var now: Vector2i = screen._seen.get(screen._client.player_id, from)
		if was != now:
			steps += 1
		# The view is rebuilt on the tick, so this is the position that would be painted.
		var players: Array = screen._world.view.get("players", [])
		if players.is_empty():
			return _fail("the scene has no player to draw after tick %d" % screen._sim.tick())
		var at: Vector2 = (players[0] as Dictionary)["at"]
		var span := Rect2(Vector2(was), Vector2.ZERO).expand(Vector2(now))
		if not span.grow(0.001).has_point(at):
			return _fail(("drawn at %s, which is outside the segment from last tick's %s to this"
					+ " tick's %s. A renderer may interpolate a drawn position, never state.")
					% [at, was, now])
	if steps < 3:
		return _fail("the player took %d steps in 12 ticks, so nothing was tweening" % steps)
	screen.queue_free()
	return true


## THE ORE UNDER THE CAMERA IS THE SIM'S CIRCLE, NOT A BOX THIS CLIENT DREW.
##
## A deposit's `radius` is a circle and `contains` is sim code. A client that walked the bounding box
## itself would draw rock on tiles nobody can mine -- a picture that lies about where the game stops
## working -- and it would look completely fine in a screenshot. So: every tile the view draws ore on
## is a tile `tile_at` names a deposit for, and the corners of the bounding box are not drawn.
func test_the_ore_drawn_is_the_tiles_the_sim_names_and_not_a_bounding_box() -> bool:
	var screen := _joined()
	if not screen._sim.running():
		return _fail("no offline world: %s" % screen._sim.fail_reason)
	screen._show_close_up(true)
	# THE CAMERA IS PUT ON A DEPOSIT RATHER THAN LEFT AT SPAWN, and that is a measurement and not a
	# convenience: on the pinned seed 777042 the 28x18 window at spawn is over NO ore at all. One
	# deposit per 16x16 chunk means four chunks are partly in view and each one's patch can sit in
	# the part that is not. Worth knowing for a demo seed; fatal for a test, which would be asserting
	# over an empty dictionary and passing.
	var world: Vector2i = screen._sim.size_tiles()
	var found := {}
	var radius := 0
	for entry in screen._sim.deposits():
		var deposit: Dictionary = entry
		if int(deposit.get("radius", 0)) < 2:
			continue
		var centre: Vector2i = deposit.get("center", Vector2i.ZERO)
		radius = int(deposit["radius"])
		found = screen._ore_under(AssayScene.camera_origin(Vector2(centre), world,
				screen._world.size), world)
		if found.has(centre):
			# A radius-r patch is a circle, so the corners of its bounding box are outside it.
			for step: Vector2i in [Vector2i(radius, radius), Vector2i(-radius, radius),
					Vector2i(radius, -radius), Vector2i(-radius, -radius)]:
				if found.has(centre + step):
					return _fail(("%s is a corner of the bounding box of the deposit at %s radius"
							+ " %d, and ore is drawn there -- the view is painting a box over the"
							+ " sim's circle") % [centre + step, centre, radius])
			break
	if found.is_empty() or radius < 2:
		return _fail("no deposit of radius 2 or more in this world, so the circle was never checked")
	for at in found:
		if screen._sim.tile_at(at).get("deposit") == null:
			return _fail("ore is drawn on %s and the sim says there is no deposit there" % at)
	screen.queue_free()
	return true


## WITH NO WORLD THERE IS NOTHING TO DRAW, and that must be a quiet empty rather than a frame of
## sprites at the origin. `--selfcheck` and the join screen are both in this state.
func test_before_a_welcome_the_scene_is_empty() -> bool:
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	runner.root_node.add_child(screen)
	screen._ready()
	if not screen._world.view.is_empty():
		return _fail("the scene has %d things to draw before any world exists"
				% screen._world.view.size())
	if AssayScene.placements({}).size() != 0:
		return _fail("an empty view produced placements")
	if not screen._close_up:
		return _fail("the close-up is the main view (Maren, ASSA-119) and the screen opened on the "
				+ "schematic")
	screen.queue_free()
	return true


## ---- the harness, the same one `test_buttons.gd` uses: a real screen, a real world, no relay ----

var _asked: Array = []


func _joined(seed_text := "777042") -> Node:
	_asked = []
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	runner.root_node.add_child(screen)
	screen._ready()
	screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	var welcome := AssaySimHost.fresh_welcome_json(seed_text, "marlow")
	if welcome == "":
		return screen
	screen._client.play_offline()
	screen._client.feed_offline(welcome)
	return screen


func _tick(screen: Node, count := 1) -> void:
	for _i in range(count):
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = screen._sim.tick()
		screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))


## THE PREMISE OF THE THREE BELOW, and the bridge nothing else checks: a building's `kind` from the
## sim is used as the ASSET NAME, so a sheet renamed or a kind renamed makes the demo's one machine
## silently invisible again -- which is the state ASSA-119 box 11 was open on for two days.
func test_the_shipped_manifest_draws_the_building_kinds_the_sim_can_place() -> bool:
	var manifest := _manifest()
	if not manifest.has("smelter"):
		return _fail("the manifest has no `smelter`, so a placed smelter draws nothing at all")
	var rows := []
	for row in ((manifest["smelter"] as Dictionary).get("rows", []) as Array):
		rows.append(String((row as Dictionary).get("name", "")))
	for want in ["cold", "lit"]:
		if not rows.has(want):
			return _fail("`smelter` ships no `%s` row, and the view asks for it by name: %s"
					% [want, rows])
	return true


func _smelter(at: Vector2i, lit := false) -> Dictionary:
	return {"kind": "smelter", "pos": at, "footprint": Vector2i(2, 2), "lit": lit}


## A SMELTER IS DRAWN ON THE FOUR TILES THE SIM GAVE IT, not on one and not centred on two.
##
## `pos` is the TOP-LEFT of the footprint (`Building::pos`), so the drawing's own bottom-right corner
## has to be the block's: 2 tiles of 32 px across, with the sheet's anchor lifting it clear above.
## Every number here is read from the footprint and the manifest -- a literal 64 would pass just as
## well with `TILE_PX` at 16.
func test_a_placed_smelter_is_drawn_across_its_whole_footprint() -> bool:
	var at := Vector2i(10, 5)
	var places := _of(AssayScene.placements(_view({"buildings": [_smelter(at)]})), "smelter")
	if places.size() != 1:
		return _fail("one placed smelter should draw once, drew %d" % places.size())
	var dest: Rect2 = (places[0] as Dictionary)["dest"]
	var block := Rect2(Vector2(at) * AssayScene.TILE_PX, Vector2(2, 2) * AssayScene.TILE_PX)
	if dest.size.x != block.size.x:
		return _fail("drawn %d px wide over a %d px footprint" % [dest.size.x, block.size.x])
	if dest.end != block.end:
		return _fail("the drawing's bottom-right is %s, the footprint's is %s" % [dest.end,
				block.end])
	# THE SHEET IS TALLER THAN THE FOOTPRINT ON PURPOSE (128x144 for 2x2), so it rises above the
	# tiles it stands on the way the player sprite does. Equal would mean the anchor was dropped.
	if dest.position.y >= block.position.y:
		return _fail("a 2x2 smelter drawn at y %s does not rise above its block at y %s"
				% [dest.position.y, block.position.y])
	return true


## COLD AND LIT ARE TWO DIFFERENT ROWS OF THE SAME SHEET, and `lit` is the only thing that picks.
## Asserted on the source rectangle as well as the row name, because a name that resolves to the same
## strip is a renamed nothing.
func test_the_fire_in_a_smelter_chooses_the_row() -> bool:
	var cold := _of(AssayScene.placements(_view({"buildings": [_smelter(Vector2i(10, 5))]})),
			"smelter")
	var lit := _of(AssayScene.placements(_view({"buildings": [_smelter(Vector2i(10, 5), true)]})),
			"smelter")
	if cold.size() != 1 or lit.size() != 1:
		return _fail("expected one placement each, got %d and %d" % [cold.size(), lit.size()])
	if String((cold[0] as Dictionary)["row"]) != "cold":
		return _fail("an unlit smelter draws row `%s`" % (cold[0] as Dictionary)["row"])
	if String((lit[0] as Dictionary)["row"]) != "lit":
		return _fail("a burning smelter draws row `%s`" % (lit[0] as Dictionary)["row"])
	if (cold[0] as Dictionary)["src"] == (lit[0] as Dictionary)["src"]:
		return _fail("both rows read the same strip of the sheet: %s"
				% (cold[0] as Dictionary)["src"])
	return true


## A KIND NO SHEET DRAWS IS SKIPPED, AND THE SCENE AROUND IT STILL DRAWS. A machine has no single
## frame -- it is parts stacked by `part_layout.stack` -- so today the honest answer is nothing, and
## the thing that must not happen is a missing asset taking the ground down with it.
func test_a_building_kind_with_no_sheet_draws_nothing_and_breaks_nothing() -> bool:
	var view := _view({"buildings": [{"kind": "machine", "pos": Vector2i(10, 5),
			"footprint": Vector2i(1, 1), "lit": false}]})
	var all := AssayScene.placements(view)
	if _of(all, "machine").size() != 0:
		return _fail("something was drawn for a kind the sheets have no art for")
	if _of(all, "ground").is_empty():
		return _fail("a building with no sheet stopped the ground being drawn")
	return true


## WHAT STANDS IN FRONT OF WHAT, AND THE KEY IS THE SIM'S FOOTPRINT. A player standing south of a
## smelter walks in FRONT of it; one standing north of it is hidden behind. The 2x2 is why this
## matters: sorting on `pos.y` alone would put a player on the smelter's own southern row behind it,
## which is the bug that lost the player inside the spawn pad on the first shot of this view.
func test_a_player_south_of_a_smelter_is_drawn_in_front_of_it() -> bool:
	var smelter := _smelter(Vector2i(10, 5))
	for case in [{"at": Vector2(10, 7), "front": true}, {"at": Vector2(10, 3), "front": false}]:
		var player := {"at": case["at"], "facing": "S", "moving": false}
		var all := AssayScene.placements(_view({"buildings": [smelter], "players": [player]}))
		var order := []
		for place in all:
			var asset := String((place as Dictionary).get("asset", ""))
			if asset == "smelter" or asset == "player":
				order.append(asset)
		if order.size() != 2:
			return _fail("expected the smelter and the player, drew %s" % [order])
		var drawn_last := String(order[1])
		var want := "player" if bool(case["front"]) else "smelter"
		if drawn_last != want:
			return _fail("a player at %s should be drawn %s the smelter; order was %s"
					% [case["at"], "after" if bool(case["front"]) else "before", order])
	return true
