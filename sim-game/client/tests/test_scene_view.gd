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

## THE RELAY'S OWN TICK PERIOD, in ms: `sim-relay` runs at 10 ticks a second by default and
## `maren_bundle_gap_probe.gd` measured a real one at p50 100 ms exactly. Only the playout test below
## uses it, and it is a constant rather than a 100 because the number has a source. See there for why
## a test about a clock has to feed it wall clock at the rate the game really runs at.
const RELAY_TICK_MS := 100

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
		# EMPTY, BUT PRESENT. This fixture had no `buildings` key at all until ASSA-141, and
		# `placements` read it as `get("buildings", [])` -- so the fixture and the real view
		# disagreed about the contract and nothing could say so. Nineteen tests in this file went
		# red the moment the contract was checked, which is the item's own argument about fixtures.
		"buildings": [],
		"manifest": _manifest(),
		"layout": AssayAssembly.contract(),
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


## A BLOCK IS PLACED BY POSITION, WHICH IS THE WHOLE OF ASSA-115 BOX 2.
##
## `ground.png` stopped being interchangeable tiles: it is ONE 8x8-tile picture rendered from
## one Blender scene and cut into 64 cells, so a cell means a PLACE. Hash-picking one would
## cut every patch that crosses a cell boundary and come out worse than the six variants QA
## could point at. The sheet declares it (`manifest.ground.block`) and this asserts the client
## obeys: the cell repeats on the block's period, and a NEGATIVE coordinate continues the
## picture rather than snapping to row 0, which is the one thing `%` would get wrong.
##
## Read against the SHIPPED manifest on purpose. A fixture would let the sheet and the client
## disagree forever, which is the failure this whole box is about.
func test_a_ground_block_is_placed_by_position_and_not_by_hash() -> bool:
	var man := _manifest()
	var block: Array = ((man.get("ground", {}) as Dictionary).get("block", []) as Array)
	if block.size() != 2:
		return _fail("the shipped ground sheet declares no block, so this check is asleep")
	var w := int(block[0])
	var h := int(block[1])
	if w <= 1 or h <= 1:
		return _fail("a %dx%d block is not a block" % [w, h])
	for y in range(-2 * h, 2 * h):
		for x in range(-2 * w, 2 * w):
			var want := "v%d" % (posmod(y, h) * w + posmod(x, w))
			var got := AssayScene.ground_row(man, Vector2i(x, y))
			if got != want:
				return _fail("tile (%d,%d) drew ground/%s, not its cell %s" % [x, y, got, want])

	# WITHOUT a block, nothing changes: loose rows are still hash-picked, which is what
	# `ore` and any later set of interchangeable variants depend on.
	var loose := {"ground": {"rows": [{"name": "v0", "frames": 1}, {"name": "v1", "frames": 1},
			{"name": "v2", "frames": 1}, {"name": "v3", "frames": 1}]}}
	var seen := {}
	for y in range(20):
		for x in range(20):
			seen[AssayScene.ground_row(loose, Vector2i(x, y))] = true
	if seen.size() < 4:
		return _fail("with no block the rows must still be hash-picked; 400 tiles used %d of 4"
				% seen.size())
	return true


## THE CAMERA CENTRES YOU, AND STOPS AT THE EDGE rather than showing void beside the world -- in
## three directions out of four. **The north bound is `headroom` ABOVE the world (ASSA-184)**, and
## the assertion this test used to carry (`== Vector2.ZERO` in the north-west corner) is the one that
## encoded the defect: that camera is exactly the one that slid the player's body up behind the event
## log's panel in rows 0..7.
func test_the_camera_centres_you_and_clamps_at_the_world_edge() -> bool:
	var world := Vector2i(96, 64)
	var room := AssayScene.north_headroom(_manifest(), WINDOW)
	if room <= 0.0:
		return _fail(("north_headroom answered %f for the real manifest, so there is no north bound "
				+ "to check and every assertion below about row 0 is vacuous") % room)
	var middle := AssayScene.camera_origin(Vector2(48.0, 32.0), world, WINDOW, room)
	var want := Vector2(48.5 * 32.0 - 320.0, 32.5 * 32.0 - 160.0)
	if not middle.is_equal_approx(want):
		return _fail("centred on (48, 32) the camera is at %s and the middle is %s" % [middle, want])
	# THE NORTH-WEST CORNER, ONE AXIS AT A TIME, because the two axes now answer differently and a
	# `Vector2` comparison would not say which one moved.
	var corner := AssayScene.camera_origin(Vector2.ZERO, world, WINDOW, room)
	if corner.x != 0.0:
		return _fail("walking into the WEST edge the camera went to x %f, past the world" % corner.x)
	if not is_equal_approx(corner.y, -room):
		return _fail(("standing in row 0 the camera stopped at y %f and ASSA-184 bounds it at %f; "
				+ "at y 0 the body is drawn from y %f with the panel owning the top %f")
				% [corner.y, -room, -AssayScene.TILE_PX,
				AssayScene.player_ceiling(_manifest(), WINDOW)])
	# NO PLAYER ART, NO VOID: at headroom 0 this is the camera the client had before ASSA-184, which
	# is the honest answer when `player_ceiling` has nothing to measure and keeps all fourteen lines.
	if AssayScene.camera_origin(Vector2.ZERO, world, WINDOW, 0.0) != Vector2.ZERO:
		return _fail("with no headroom the north-west corner must still be the world's own corner")
	var far := AssayScene.camera_origin(Vector2(95.0, 63.0), world, WINDOW, room)
	var edge := Vector2(96.0 * 32.0, 64.0 * 32.0) - WINDOW
	if not far.is_equal_approx(edge):
		return _fail("in the south-east corner the camera is at %s and the last full view is %s"
				% [far, edge])
	# A world smaller than the view has no clamp to make, so it is centred instead -- but never
	# ABOVE the bound. `camera_origin` carries one invariant with no footnote: no camera it returns
	# lifts a body above the ceiling. A 4x4 world is drawn below its centre as the price.
	var tiny := AssayScene.camera_origin(Vector2(2.0, 2.0), Vector2i(4, 4), WINDOW, room)
	if not tiny.is_equal_approx(Vector2((128.0 - WINDOW.x) * 0.5, -room)):
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


## THE ARRIVAL PATTERN A REAL RELAY GIVES, PLAYED OUT AT 60 fps, WITH NO SOCKET AND NO CLOCK.
##
## THIS IS ASSA-148 AS A TEST, and it can only be one because `AssayScene.playout` takes its clock as
## an argument. The defect was not in the lerp and not in the cadence estimate: bundles arrive in
## PAIRS -- exactly 10.00 a second with gaps between 0.000 s and 0.268 s -- and a client that restarts
## its tween at every arrival never draws the older segment of a pair at all. The body teleports a
## whole tile; measured on the demo seed, 11 of the walk's 25 steps went undrawn.
##
## SO THE FEED HERE IS THE MEASURED ONE AND NOT A METRONOME. Thirteen pairs at 0.2 s, with ONE 0.27 s
## gap in the middle, because that gap is the case my first fix got wrong: the queue runs dry, the
## body parks on the segment's end position, and a rule that resumed "where the previous segment
## ended" then drew the next frame 70% of the way along a tile the body had not begun to cross. That
## is a 0.700-tile jump, and it is what this test fails on if the arrival floor in `playout` goes.
##
## THREE PROPERTIES, and the third is the one a picture cannot show:
## 1. **Every produced position is drawn, in the order the sim produced it.** `promoted` must be
##    0..25 with nothing skipped -- a skipped entry IS the teleport.
## 2. **No frame moves the body further than that frame's own share of a tile.** At 60 fps against a
##    0.1 s tick that is 1/6 of a tile, so the old defect is six times the bar.
## 3. **The body ends exactly on the last position the sim produced**, never past it. A playout
##    buffer can only draw later than the newest tick, which is why it keeps Maren's ASSA-119 ruling
##    by construction: there is nothing here to predict with.
func test_a_paired_tick_feed_is_drawn_one_whole_segment_at_a_time() -> bool:
	var step := 0.1
	var frame := 1.0 / 60.0
	var arrivals: Array[float] = []
	var t := 0.0
	for pair in range(13):
		arrivals.append(t)
		arrivals.append(t)
		t += 0.27 if pair == 4 else 0.2
	# Tick i leaves the player at x = i: one tile per tick, which is what `move_players` does.
	var pending: Array[int] = []
	var pending_at: Array[float] = []
	var promoted: Array[int] = []
	var delivered := 0
	var was := -1
	var seen := -1
	var seg_at := 0.0
	var drawn := 0.0
	var biggest := 0.0
	for f in range(int(4.0 / frame)):
		var now := frame * float(f)
		while delivered < arrivals.size() and arrivals[delivered] <= now:
			pending.append(delivered)
			pending_at.append(arrivals[delivered])
			delivered += 1
			while pending.size() > 3:
				pending.pop_front()
				pending_at.pop_front()
		var cursor := AssayScene.playout(seg_at, step, now, pending_at, seen >= 0)
		for _i in range(int(cursor["promote"])):
			was = seen if seen >= 0 else pending[0]
			seen = pending.pop_front()
			pending_at.pop_front()
			promoted.append(seen)
		seg_at = float(cursor["seg_at"])
		if seen < 0:
			continue
		var at := lerpf(float(was), float(seen), float(cursor["part"]))
		if f > 0:
			biggest = maxf(biggest, absf(at - drawn))
		drawn = at
	for i in range(arrivals.size()):
		if promoted.size() <= i or promoted[i] != i:
			return _fail(("the playout drew %s, so position %d was never drawn. A produced position"
					+ " that is skipped is the whole-tile teleport this item is about.")
					% [promoted, i])
	if biggest > frame / step + 0.0005:
		return _fail(("a frame moved the body %.3f tiles, and a frame's own share of a tile at 60 fps"
				+ " against a %.2fs tick is %.3f. Arrival is not a clock.")
				% [biggest, step, frame / step])
	if not is_equal_approx(drawn, float(arrivals.size() - 1)):
		return _fail("the walk ended drawn at %.3f, not on the last position the sim produced (%d)"
				% [drawn, arrivals.size() - 1])
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
##
## WHY THIS TEST WAITS A TICK OF WALL CLOCK PER TICK, which is the only thing ASSA-148 changed about
## it -- and `RELAY_TICK_MS` rather than the 20 ms it waited until ASSA-197, which was a flake. The
## playout clock is rate-ADAPTIVE: it measures the gap between arrivals and divides frame time by it,
## so feeding ticks five times faster than the relay produces them leaves the clock pinned to the
## newest position it holds, `from == to`, and nothing tweening. Whether it got there inside twelve
## ticks depended on how long the surrounding work took -- it failed on CI and passed on this Mac in
## the same hour, then failed here. A test about a clock has to feed it the rate the game runs at,
## and that rate has a source (`sim-relay`'s default, measured at p50 100 ms). The screen no
## longer advances the drawn segment when a bundle ARRIVES -- it advances it on a playout clock, so
## that a pair of bundles landing in the same frame can no longer leave the segment between them
## undrawn (a whole-tile teleport, 11 times in the demo walk's 25 steps). A test that feeds twelve
## ticks inside one millisecond is therefore asking a clock to move without time passing, and the
## honest answer is the one it got: the body has not been drawn anywhere yet. The delay makes this
## feed what every other input in the game is -- ticks separated by wall clock, at the rate the relay
## separates them by -- and twelve ticks is well inside the queue's depth, so the walk plays out step
## by step.
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
		OS.delay_msec(RELAY_TICK_MS)
		# **A FRAME'S WORTH OF TIME, STATED, which is what stops this test being a coin flip**
		# (ASSA-197; Nerite measured 283/1 then 284/0 on the same tree, 2026-10-05). The playout
		# clock used to advance by wall clock, so each iteration moved it by the 100 ms delay PLUS
		# whatever the sim step and the rebuild cost on a loaded box -- 130-140 ms against a host
		# producing 100 ms, which drains the buffer and pins the body on the newest position it
		# holds. Then whether twelve ticks produced three steps depended on the machine. Now the
		# frame's delta is an input, so one fed tick is played out by one tick of frame time and the
		# verdict is the client's rather than the loop's overhead.
		screen._refresh_world(float(RELAY_TICK_MS) / 1000.0)
		var was: Vector2i = screen._was.get(screen._client.player_id, from)
		var now: Vector2i = screen._seen.get(screen._client.player_id, from)
		if was != now:
			steps += 1
		# Rebuilt a frame's worth of time after the tick, so this is the position that would be
		# painted -- and it is read from the same advance that `_was` and `_seen` were read from.
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
		# HEADROOM 0.0: this is about which ore tiles a window covers, and a deposit's centre is the
		# camera's target. Giving it the real bound would only change the answer for a deposit in
		# rows 0..8, which is a different question (`test_the_north_edge_...` below).
		found = screen._ore_under(AssayScene.camera_origin(Vector2(centre), world,
				screen._world.size, 0.0), world)
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


## THE SIM TICK OF EVERY POSITION THE SCREEN IS STILL HOLDING, oldest first -- the queue whose cap
## decides whether the playout clock can be dragged forward by an arrival (`PLAYOUT_QUEUE`).
func _queue_ticks(screen: Node) -> Array[int]:
	var out: Array[int] = []
	for entry in (screen._pending as Array):
		out.append(int((entry as Dictionary)["tick"]))
	return out


## HOW FAR ONE DRAWN FRAME OF `delta` MOVES THE PLAYOUT CLOCK, through the real `_process` path.
func _moved_by_process(screen: Node, delta: float) -> float:
	var was: float = screen._play_tick
	screen._process(delta)
	return float(screen._play_tick) - was


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
	if not rows.has("body"):
		return _fail("`smelter` ships no `body` row, and the view asks for it by name: %s" % [rows])
	# AND THE LIGHT ROW IS FOUND THE WAY THE VIEW FINDS IT -- by the manifest's own `light`/`over`
	# fields, not by the word "fire" typed here. A sheet that stopped flagging the row would leave
	# `light_row` returning "" and a burning smelter drawing nothing but walls, silently (ASSA-137).
	var light := AssayScene.light_row(manifest, "smelter", "body")
	if light == "":
		return _fail("no row of `smelter` is flagged `light` over `body`, so a burning smelter has "
				+ "no fire to draw: %s" % [rows])
	return true


func _smelter(at: Vector2i, lit := false, species := 2) -> Dictionary:
	# `parts` EMPTY AND PRESENT, as `BuildingFacts` sends it: "non-empty for a machine and empty for
	# a smelter, which is the sim's own answer to `is this an assembly`". `_drill` below always
	# carried it; this fixture never did.
	return {"kind": "smelter", "pos": at, "footprint": Vector2i(2, 2), "lit": lit,
			"species": species, "parts": []}


## **THE THING YOU PLACED AND THE THING STANDING THERE ARE ONE OBJECT** (Maren, ASSA-131 ruling 2).
## Asserted against the PACK's own function rather than a colour typed here: a literal would keep
## passing after someone changes the table, which is the failure mode this whole file exists to
## refuse. Two species must also differ, or "it is tinted" is satisfied by tinting everything grey.
func test_a_standing_smelter_wears_the_tint_its_item_wore_in_the_pack() -> bool:
	for species in [0, 3]:
		var places := _of(AssayScene.placements(_view({"buildings":
				[_smelter(Vector2i(10, 5), false, species)]})), "smelter")
		if places.size() != 1:
			return _fail("one smelter should draw once, drew %d" % places.size())
		var want := AssaySprites.tint_for({"species": species})
		if (places[0] as Dictionary)["tint"] != want:
			return _fail("species %d stands in %s and sits in your pack in %s"
					% [species, (places[0] as Dictionary)["tint"], want])
	if AssaySprites.tint_for({"species": 0}) == AssaySprites.tint_for({"species": 3}):
		return _fail("premise: two species share a tint, so this test cannot see a missing one")
	return true


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


## A BURNING SMELTER IS TWO PLACEMENTS: THE WALLS, AND THE LIGHT ON THEM (ASSA-137).
##
## This used to be one sprite picked by `lit`, both states multiplied by the species tint -- and a
## multiply can only subtract, so the brightest pixel of a fire came out darker than the dirt in
## three of six species. The walls keep the tint because they are made of the species; the fire is
## a second placement at `Color.WHITE` because light is not.
##
## Asserted on the source rectangle as well as the row name: a name that resolves to the same strip
## is a renamed nothing. And on the TINT of each, which is the whole property -- a fire drawn with
## the body's tint would pass every other assertion in this file.
func test_a_burning_smelter_draws_its_fire_untinted_over_its_tinted_walls() -> bool:
	var cold := _of(AssayScene.placements(_view({"buildings": [_smelter(Vector2i(10, 5))]})),
			"smelter")
	var lit := _of(AssayScene.placements(_view({"buildings": [_smelter(Vector2i(10, 5), true)]})),
			"smelter")
	if cold.size() != 1:
		return _fail("an unlit smelter should draw once, drew %d" % cold.size())
	if lit.size() != 2:
		return _fail("a burning smelter should draw its body and its fire, drew %d" % lit.size())
	var body: Dictionary = cold[0]
	if String(body["row"]) != "body":
		return _fail("an unlit smelter draws row `%s`" % body["row"])
	if String((lit[0] as Dictionary)["row"]) != "body":
		return _fail("a burning smelter draws `%s` first, not its body"
				% (lit[0] as Dictionary)["row"])
	var fire: Dictionary = lit[1]
	if String(fire["row"]) != AssayScene.light_row(_manifest(), "smelter", "body"):
		return _fail("the second placement is `%s`, which is not the sheet's light row"
				% fire["row"])
	if fire["src"] == body["src"]:
		return _fail("the fire reads the same strip of the sheet as the walls: %s" % body["src"])
	if fire["dest"] != body["dest"]:
		return _fail("the fire lands at %s and the walls at %s, so it is not on them"
				% [fire["dest"], body["dest"]])
	if fire["tint"] != Color.WHITE:
		return _fail("the fire is drawn tinted %s; a multiply can only subtract, so the species "
				% fire["tint"] + "would cap how bright a fire can be")
	if (lit[0] as Dictionary)["tint"] != body["tint"]:
		return _fail("lighting the fire changed the walls' tint to %s"
				% (lit[0] as Dictionary)["tint"])
	return true


## AND THE FIRE STAYS ON TOP WHEN SOMETHING ELSE SHARES ITS BOTTOM EDGE (Maren's hazard, ASSA-137).
##
## The two placements have exactly equal sort keys, and `Array.sort_custom` is NOT stable, so
## without the second key the renderer is free to draw the walls over their own fire -- and free to
## do it on some array lengths and not others, which is a wrong picture nobody can reproduce. The
## player here has the smelter's own bottom edge (6 + 1 == 5 + 2), so all three sort equal.
func test_a_fire_is_drawn_after_its_walls_even_when_a_body_sorts_equal_to_it() -> bool:
	var smelter := _smelter(Vector2i(10, 5), true)
	var player := {"at": Vector2(14, 6), "facing": "S", "moving": false}
	var all := AssayScene.placements(_view({"buildings": [smelter], "players": [player]}))
	var rows := []
	for place in all:
		if String((place as Dictionary).get("asset", "")) == "smelter":
			rows.append(String((place as Dictionary)["row"]))
	var light := AssayScene.light_row(_manifest(), "smelter", "body")
	if rows != ["body", light]:
		return _fail("the smelter drew %s; the fire has to come after the walls it is on" % [rows])
	return true


## A KIND NO SHEET DRAWS IS SKIPPED, AND THE SCENE AROUND IT STILL DRAWS.
##
## THE FIXTURE HERE HAS NO PARTS AND THAT IS THE WHOLE CASE: since ASSA-138 a machine IS drawn, from
## its parts, so the only way left to be a building with no picture is to be one the sim never
## reported parts for. That is not hypothetical -- it is what every machine looked like to this
## client before tonight, and what a building kind added after today will look like until it has
## art. The thing that must not happen is a missing asset taking the ground down with it.
func test_a_building_kind_with_no_sheet_draws_nothing_and_breaks_nothing() -> bool:
	# **A MISSING ASSET AND A MISSING SIM FACT ARE NOT THE SAME THING ANY MORE** (ASSA-141). This
	# fixture used to express "no art for this kind" by leaving `parts` and `species` OFF the
	# dictionary, and that is now a broken view rather than a drawable one: `BuildingFacts` always
	# sends `parts`, empty for anything that is not an assembly. The sim facts are all here and the
	# ART is what is absent -- the manifest has no `machine` sheet, because since ASSA-138 a machine
	# is composited from its parts -- which is the case this test is actually about. A sheet is the
	# renderer's own and may be missing; a fact may not.
	var view := _view({"buildings": [{"kind": "machine", "pos": Vector2i(10, 5),
			"footprint": Vector2i(1, 1), "lit": false, "species": 2, "parts": []}]})
	var all := AssayScene.placements(view)
	if _of(all, "machine").size() != 0:
		return _fail("something was drawn for a kind the sheets have no art for")
	if _composites(all).size() != 0:
		return _fail("a building that reported no parts was composited out of nothing")
	if _of(all, "ground").is_empty():
		return _fail("a building with no sheet stopped the ground being drawn")
	return true


# ---------------------------------------------------------------------------
# A PLANTED MACHINE (ASSA-138)
# ---------------------------------------------------------------------------

## A DRILL AS THE SIM REPORTS ONE: frame first, then the mounted parts, each with its own material.
## `hoppers` is the dial Maren measured the defect on, because hopper count IS capacity.
func _drill(at: Vector2i, hoppers: int, species := 2, grade := "A") -> Dictionary:
	var parts := [{"kind": "frame", "species": species, "grade": grade},
			{"kind": "head", "species": species, "grade": grade}]
	for _i in range(hoppers):
		parts.append({"kind": "hopper", "species": species, "grade": grade})
	return {"kind": "machine", "pos": at, "footprint": Vector2i(1, 1), "lit": false,
			"species": species, "parts": parts}


func _composites(places: Array) -> Array:
	var found := []
	for place in places:
		if bool((place as Dictionary).get("composite", false)):
			found.append(place)
	return found


## What one part sprite is drawn at, read from the manifest the way `_place` reads it: authored
## pixels per tile, then `TILE_PX` over that. Never a literal, so a re-render cannot pass this.
func _part_scale() -> float:
	var spec: Dictionary = _manifest().get("frame", {})
	var frame_px: Array = spec.get("frame_px", [])
	var tiles: Array = spec.get("tiles", [])
	if frame_px.size() != 2 or tiles.size() != 2 or float(tiles[0]) <= 0.0:
		return 0.0
	return AssayScene.TILE_PX / (float(frame_px[0]) / float(tiles[0]))


## **ADDING A HOPPER MAY NEVER MAKE ANY PART OF THE MACHINE DRAW SMALLER** (Maren's ruling, ASSA-138,
## and the box she wrote for this file).
##
## THIS IS THE ARITHMETIC OF THE DEFECT SHE MEASURED, pointed the other way. Squeezed into the 1x1
## footprint, a drill's 437 opaque pixels at one hopper fell to 377 at four: capacity up, picture
## down, and all four reading as one dark lump. The cause is that the canvas GROWS with each repeat,
## so a fixed box divides by a bigger number every time.
##
## SO THE PROPERTY IS A CONSTANT SCALE, and the test is in those terms rather than in pixel counts:
## one part occupies the same screen rectangle however many siblings it has, and the machine's own
## rectangle grows to hold them. A test that only checked the total area would pass on a drill that
## grew while every bar inside it shrank, which is the exact picture being refused.
func test_adding_a_hopper_never_makes_any_part_of_a_machine_draw_smaller() -> bool:
	var scale := _part_scale()
	if scale <= 0.0:
		return _fail("premise: the manifest will not say what a part sprite is drawn at")
	var spec: Dictionary = _manifest().get("frame", {})
	var frame_px := Vector2(float((spec["frame_px"] as Array)[0]),
			float((spec["frame_px"] as Array)[1]))
	var offset: Vector2i = AssayAssembly.contract().get("repeat_offset_px", Vector2i.ZERO)
	if offset == Vector2i.ZERO:
		return _fail("premise: the contract's repeat offset is zero, so no repeat ever moves")
	var seen := []
	for hoppers in [1, 2, 3, 4]:
		var places := _composites(AssayScene.placements(
				_view({"buildings": [_drill(Vector2i(10, 5), hoppers)]})))
		if places.size() != 1:
			return _fail("a planted %d-hopper drill drew %d times" % [hoppers, places.size()])
		var dest: Rect2 = (places[0] as Dictionary)["dest"]
		# EVERY PART IS STILL A WHOLE PART SPRITE. The canvas is the union of the parts' boxes, so
		# the box minus the climb of the last repeat IS one part's rectangle -- if that comes out
		# smaller than `frame_px * scale`, something scaled the parts down to fit.
		var box: Rect2i = AssayAssembly.canvas_of((_drill(Vector2i(10, 5), hoppers)["parts"] as
				Array), Vector2i(int(frame_px.x), int(frame_px.y)), offset)
		var climb := Vector2(box.size) - frame_px
		if climb.x < 0.0 or climb.y < 0.0:
			return _fail("the canvas for %d hoppers is %s, smaller than one part's %s"
					% [hoppers, box.size, frame_px])
		if not is_equal_approx(dest.size.x, float(box.size.x) * scale) \
				or not is_equal_approx(dest.size.y, float(box.size.y) * scale):
			return _fail("a %d-hopper drill is drawn at %s; its canvas %s at the part scale %.3f "
					% [hoppers, dest.size, box.size, scale] + "is %s"
					% [Vector2(box.size) * scale])
		seen.append({"hoppers": hoppers, "size": dest.size,
				"part": frame_px * scale, "climb": climb * scale})
	# AND THE PICTURE ACTUALLY GROWS. Without this the test above is satisfied by a machine whose
	# canvas never changes, which is what a renderer ignoring the repeat offset would produce --
	# every hopper on top of the last, invisible, capacity unreported (contract rule 1).
	for i in range(1, seen.size()):
		var now: Vector2 = (seen[i] as Dictionary)["size"]
		var before: Vector2 = (seen[i - 1] as Dictionary)["size"]
		if now.x <= before.x or now.y <= before.y:
			return _fail("%d hoppers draw %s and %d draw %s: adding one changed nothing, so the "
					% [int((seen[i - 1] as Dictionary)["hoppers"]), before,
					int((seen[i] as Dictionary)["hoppers"]), now]
					+ "repeats are stacked on each other and cannot be counted")
	return true


## **FOOTPRINT IS A RULES FACT, NOT A DRAWING SIZE** (Maren's ruling 1). A 1x1 footprint says which
## deposit a drill works; it does not say the picture is 32 px.
##
## TWO HALVES, AND THE SECOND IS THE ONE THAT CATCHES AN ANCHOR BUG. The drawing must be bigger than
## the tile (the squeeze is refused), and the FRAME must land exactly where a lone frame sprite
## standing on that tile would have landed -- so the machine is anchored on its footprint and the
## extra canvas hangs off it. Anchoring on the box instead walks the whole machine south-west as you
## add hoppers, which passes a size check and is still the wrong picture.
func test_a_planted_machine_is_drawn_at_the_part_scale_anchored_on_its_footprint() -> bool:
	var at := Vector2i(10, 5)
	var scale := _part_scale()
	var spec: Dictionary = _manifest().get("frame", {})
	var anchor: Array = spec.get("anchor_px", [0, 0])
	var offset: Vector2i = AssayAssembly.contract().get("repeat_offset_px", Vector2i.ZERO)
	var frame_px := Vector2i(int((spec["frame_px"] as Array)[0]),
			int((spec["frame_px"] as Array)[1]))
	for hoppers in [1, 4]:
		var drill := _drill(at, hoppers)
		var places := _composites(AssayScene.placements(_view({"buildings": [drill]})))
		if places.size() != 1:
			return _fail("a planted drill drew %d times" % places.size())
		var dest: Rect2 = (places[0] as Dictionary)["dest"]
		if dest.size.x <= AssayScene.TILE_PX or dest.size.y <= AssayScene.TILE_PX:
			return _fail("a drill is drawn at %s, inside its own 1x1 footprint: the picture was "
					% dest.size + "squeezed to the tile, which is what ASSA-138 refuses")
		# WHERE A LONE FRAME SPRITE WOULD HAVE GONE, by `_place`'s own rule: the tile, less the
		# sheet's anchor at the drawn scale.
		var box: Rect2i = AssayAssembly.canvas_of(drill["parts"] as Array, frame_px, offset)
		var lone := Vector2(at) * AssayScene.TILE_PX
		lone -= Vector2(float(anchor[0]), float(anchor[1])) * scale
		var frame_at := dest.position - Vector2(box.position) * scale
		if not frame_at.is_equal_approx(lone):
			return _fail("with %d hoppers the frame lands at %s; a lone frame sprite on tile %s "
					% [hoppers, frame_at, at] + "lands at %s, so the machine is not anchored on "
					% lone + "its footprint tile")
	return true


## **THE MANIFEST AND THE SHEET AGREE ABOUT HOW BIG A DRILL IS**, which is the one thing holding the
## rectangle and the picture together.
##
## `AssayScene` sizes a machine from the manifest's `frame_px`, headless, with no sheet decoded --
## that is what lets every test above run without a screen. `AssayAssembly.image_of` sizes the same
## machine from the REAL sheet's pixels. Nothing makes those two agree except this, and if they ever
## part the drill is drawn into a rectangle of the wrong shape and simply looks a bit squashed, which
## is exactly the class of defect a screenshot does not catch.
func test_the_manifest_agrees_with_the_sheet_about_a_drills_canvas() -> bool:
	var offset: Vector2i = AssayAssembly.contract().get("repeat_offset_px", Vector2i.ZERO)
	var spec: Dictionary = _manifest().get("frame", {})
	var frame_px := Vector2i(int((spec["frame_px"] as Array)[0]),
			int((spec["frame_px"] as Array)[1]))
	for hoppers in [1, 4]:
		var parts: Array = _drill(Vector2i(10, 5), hoppers)["parts"]
		var image := AssayAssembly.image_of(parts)
		if image == null:
			return _fail("the shipped sheets cannot composite a %d-hopper drill, so a planted one "
					% hoppers + "draws nothing")
		var box: Rect2i = AssayAssembly.canvas_of(parts, frame_px, offset)
		if image.get_size() != box.size:
			return _fail("the sheet composites a %d-hopper drill at %s and the manifest says %s"
					% [hoppers, image.get_size(), box.size])
	return true


## A MACHINE MADE OF SOMETHING WITH NO ART DRAWS NOTHING, and takes nothing with it. `gear` is the
## real case: Maren ruled on ASSA-84 that nothing consumes a gear, so it has no sheet on purpose.
func test_a_machine_whose_parts_have_no_art_draws_nothing() -> bool:
	var drill := _drill(Vector2i(10, 5), 2)
	(drill["parts"] as Array).append({"kind": "gear", "species": 2, "grade": "A"})
	var all := AssayScene.placements(_view({"buildings": [drill]}))
	# The rectangle is still worked out -- it comes from the FRAME's sheet -- and the renderer is
	# the half that finds out there are no pixels. What must not happen is the scene falling over.
	if _of(all, "ground").is_empty():
		return _fail("a machine with an undrawable part stopped the ground being drawn")
	if AssayAssembly.image_of(drill["parts"] as Array) != null:
		return _fail("a part with no sheet composited into an image anyway")
	return true


## WITHOUT THE CONTRACT, NOTHING IS DRAWN -- the same refusal `assembly.gd` makes, for the same
## reason (ASSA-54): a client that falls back to geometry it invented draws a wrong machine
## confidently, and the only honest answer is a loud gap.
func test_a_machine_is_not_drawn_from_geometry_this_client_invented() -> bool:
	var view := _view({"buildings": [_drill(Vector2i(10, 5), 4)], "layout": {}})
	if _composites(AssayScene.placements(view)).size() != 0:
		return _fail("a machine was placed with no part contract to place it by")
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


## **NOTHING UNIT-TESTED THE CLOCK THE BOARD'S COMPLAINT IS ABOUT** (ASSA-197). `playout_step` and
## `playout_at` are pure static arithmetic and had no test of any kind; every number on this item came
## from a probe against a live relay, which is slow, loaded and unrepeatable. These two are the
## arithmetic, pinned.
##
## THE RATE. Two claims, and they fail differently:
##
## 1. **A dozen arrivals at a steady rate answer that rate exactly**, and a window that still holds
##    an older rate answers the average of two. That is what went wrong in a real window: a
##    four-second window had the client using 99.0 ms while the host was sending one every 110.5, so
##    the clock ran at 112% of true speed and emptied its own buffer.
## 2. **The answer is seconds per TICK, not per bundle.** A bundle carrying two ticks must not halve
##    it. No host does that today, so this is the assumption being removed rather than a defect being
##    fixed -- and an assumption about the host inside the renderer's arithmetic is worth a test
##    whether or not it is currently true.
func test_the_measured_tick_rate_is_per_tick_and_tracks_a_drifting_host() -> bool:
	var window := AssayScene.PLAYOUT_RATE_WINDOW
	# A HOST AT A STEADY 110.5 ms, DELIVERED IN PAIRS: two bundles 0.17 ms apart in one frame and
	# none in the next, which is what a real window measured (the client drains its socket once a
	# frame). Pairing must not move the answer at all.
	var arrivals: Array[float] = []
	var ticks: Array[int] = []
	var at := 10.0
	for i in window:
		arrivals.append(at if i % 2 == 0 else at + 0.00017)
		ticks.append(i)
		if i % 2 == 1:
			at += 0.221
	# **THE EXPECTATION IS THE RATE THE FIXTURE WAS BUILT FROM, NOT ONE DERIVED FROM IT.** This read
	# `span / (window - 1)`, which is the estimator's own arithmetic -- so it agreed with the 10/11
	# answer the pairing produces and could not see the defect at all. A test that asks the code what
	# to expect is the shape I keep writing; 0.1105 is a number the fixture puts in by construction.
	var steady := AssayScene.playout_step(arrivals, ticks, 0.1)
	var want := 0.1105
	if absf(steady - want) > 0.0005:
		return _fail(("a host delivering two bundles a frame at a true %.1f ms a tick was measured "
				+ "at %.1f ms (%.0f%% of it). The clock divides frame time by that, so it plays out "
				+ "%.0f%% fast, drains its buffer and holds the body still")
				% [want * 1000.0, steady * 1000.0, steady / want * 100.0,
				(want / steady - 1.0) * 100.0])
	# THE SAME SERIES WITH AN OLDER, FASTER RATE IN FRONT OF IT -- which is what a long window holds
	# after the host slows down. The estimate must be the NEW rate, not a blend.
	var long_arrivals: Array[float] = []
	var long_ticks: Array[int] = []
	for i in 28:
		long_arrivals.append(float(i) * 0.09)
		long_ticks.append(i)
	var shift := long_arrivals[long_arrivals.size() - 1] + want - arrivals[0]
	for i in arrivals.size():
		long_arrivals.append(arrivals[i] + shift)
		long_ticks.append(28 + ticks[i])
	var blended := AssayScene.playout_step(long_arrivals, long_ticks, 0.1)
	if absf(blended - want) <= absf(steady - want) + 0.005:
		return _fail(("a window holding 28 arrivals at 90 ms in front of the host's real %.1f ms "
				+ "answered %.1f ms, and the short window answered %.1f. The long window is not the "
				+ "worse answer, so this test is not measuring the convergence it claims to")
				% [want * 1000.0, blended * 1000.0, steady * 1000.0])
	# AND WHICH WAY IT IS WRONG IS THE WHOLE DEFECT, so it is asserted rather than left to the
	# reader: a window still holding a FASTER past underestimates how long a tick is, and the clock
	# divides frame time by that number -- so it plays out faster than the host produces, drains its
	# own buffer and holds the body still. The other direction would only add latency.
	if blended >= want:
		return _fail(("the stale window answered %.1f ms against a real %.1f: this test's premise is "
				+ "that it UNDER-estimates the tick, which is what makes the clock run fast")
				% [blended * 1000.0, want * 1000.0])
	# AND THE DENOMINATOR. The same arrivals, each carrying two ticks: the host is twice as fast and
	# the answer must halve. Dividing by the arrival count instead gives the unchanged number.
	var doubled: Array[int] = []
	for t in ticks:
		doubled.append(t * 2)
	var per_tick := AssayScene.playout_step(arrivals, doubled, 0.1)
	if absf(per_tick - want * 0.5) > 0.0005:
		return _fail(("bundles carrying two ticks each were measured at %.1f ms a tick; the same "
				+ "arrivals one tick each are %.1f ms, so this is counting bundles and not ticks")
				% [per_tick * 1000.0, want * 1000.0])
	# NO RATE YET IS THE FALLBACK AND NOT A GUESS, including when the caller's two arrays disagree:
	# a rate derived from mismatched arrays would be arithmetic on an accident.
	for bad: Array in [[[] as Array[float], [] as Array[int]],
			[[10.0, 10.1, 10.2] as Array[float], [0, 1] as Array[int]],
			[[10.0, 10.0, 10.0] as Array[float], [0, 1, 2] as Array[int]],
			[[10.0, 10.1, 10.2] as Array[float], [3, 3, 3] as Array[int]]]:
		if not is_equal_approx(AssayScene.playout_step(bad[0], bad[1], 0.077), 0.077):
			return _fail("playout_step(%s, %s) did not fall back to the caller's rate" % bad)
	return true


## **THE CLOCK WAITS FOR A BUFFER BEFORE IT STARTS, AND NEVER READS PAST THE NEWEST POSITION HELD**
## (ASSA-197).
##
## The init branch read `maxf(newest - delay, oldest)`, so with one position held it started the clock
## AT the newest -- zero buffer, the thing its own comment forbids -- and `PLAYOUT_NUDGE` needs 25
## ticks to win 2.5 back. `tools/playout_trace.gd` caught it on a real walk: 4 of the first 12 ticks
## came back `starved`, each a frame where the body holds still. Maren's bar on this item is zero.
##
## THE SECOND HALF IS MAREN'S ASSA-119 RULING, WHICH DOES NOT BEND: the drawn position is always
## between two positions the sim produced, never toward one it has not. So no `play_tick` this
## function returns may exceed the newest tick held, at any dt, including a dt longer than the whole
## buffer.
func test_the_playout_clock_waits_for_a_buffer_and_never_runs_past_the_newest() -> bool:
	var delay: float = AssayScene.PLAYOUT_DELAY
	var step := 0.1
	# A SESSION THAT HAS JUST JOINED: positions arrive one tick at a time from tick 0, which is the
	# number the old sentinel could not tell from "not started".
	var play: float = AssayScene.PLAYOUT_UNSTARTED
	var ticks: Array[int] = []
	for tick in 8:
		ticks.append(tick)
		var cursor := AssayScene.playout_at(play, ticks, step, step, delay)
		play = float(cursor["play_tick"])
		var deep := float(ticks[ticks.size() - 1] - ticks[0])
		if deep < delay:
			if play != AssayScene.PLAYOUT_UNSTARTED:
				return _fail(("the clock started at tick %.3f with only %.1f ticks of history, and "
						+ "the buffer it is meant to run behind is %.1f. A clock that starts with no "
						+ "buffer starves on its next frame") % [play, deep, delay])
			if bool(cursor["starved"]):
				return _fail("a clock that has not started yet reported STARVED, which is a stalled"
						+ " host and a different thing from a buffer still filling")
			continue
		if play < 0.0:
			return _fail("the clock is still unstarted with %.1f ticks of history and a %.1f delay"
					% [deep, delay])
		if play > float(ticks[ticks.size() - 1]) + 0.001:
			return _fail("the clock reads %.3f and the newest position held is tick %d: it is"
					+ " drawing toward a position the sim has not produced"
					% [play, ticks[ticks.size() - 1]])
	# A FRAME LONGER THAN THE WHOLE BUFFER, which is a hitch on a loaded machine and the one case
	# where "clamp it" is the whole of the safety.
	var hitched := AssayScene.playout_at(play, ticks, 5.0, step, delay)
	if float(hitched["play_tick"]) > float(ticks[ticks.size() - 1]) + 0.001:
		return _fail(("a 5 s frame carried the clock to %.3f past a newest tick of %d: the body is "
				+ "drawn where the sim has not been") % [hitched["play_tick"],
				ticks[ticks.size() - 1]])
	if not bool(hitched["starved"]):
		return _fail("a frame that outran the whole buffer did not report STARVED, so a stalled host"
				+ " is indistinguishable from a healthy one")
	return true


## **A CLOCK WHOSE MEASURED TICK LENGTH IS BIASED STILL HOLDS ITS BUFFER** (ASSA-197, Wren's 23:45
## ruling, and the one thing on this item that is about a machine nobody here owns).
##
## THE RISK THIS PINS. `playout_step` measures the host's tick length from arrival times, and the
## clock divides frame time by it; every number proving that measurement right was taken on this Mac.
## On a Windows PC the relay child's sleep and the loopback arrivals sit on a ~15.6 ms timer, which
## has never been measured here -- and a measurement that comes out SHORT makes the clock play out
## faster than the host produces, drain its own buffer and hold the body still. That is the shape the
## board felt twice, and on this Mac it was real: the client used 86% of the host's true tick.
##
## **AND THE DEPTH LOOP ALONE DOES NOT SAVE IT, WHICH IS WHY THERE IS AN INTEGRAL.** Depth is at rest
## only where `rate` equals the ratio of measured tick to true, and `rate` is clamped to
## `PLAYOUT_NUDGE`; past that the controller sits on its stop and drains anyway. So this test drives
## one fixture TWICE, and the first leg is the control:
##
## 1. **The integral thrown away each frame** -- a pure proportional loop, which is what main did
##    before this -- must STARVE. If it does not, the fixture is too gentle to be about anything and
##    the leg below proves nothing.
## 2. **The integral fed back** must starve on no frame at all and settle its depth near the target.
##
## WHAT THE TEST EXPECTS COMES FROM THE FIXTURE AND NOT FROM THE CLOCK: the host's true tick is
## `RELAY_TICK_MS`, the bias is a constant written here, and the played-out rate is counted from how
## far `play_tick` actually travelled. Nothing asks `playout_at` what it ought to have done -- the
## mistake that let my own rate test pass the defect it was written for.
func test_a_biased_tick_measurement_does_not_drain_the_playout_buffer() -> bool:
	# 14% SHORT, which is not a round number for effect: it is what the real client measured against a
	# real relay on 2026-10-04 (89.8 ms used against 104.2 ms sent) before the pairing fix.
	var bias := 0.86
	var loose := _drive_playout(bias, false)
	if int(loose["starved"]) == 0:
		return _fail(("THE CONTROL DID NOT FAIL: a clock measuring the tick at %.0f%% of its true "
				+ "length, with the integral discarded every frame, starved on none of %d frames and "
				+ "settled its depth at %.2f. Then this fixture cannot tell a loop that holds its "
				+ "buffer from one that cannot, and the assertion below is vacuous")
				% [bias * 100.0, int(loose["frames"]), float(loose["depth_mean"])])
	var learnt := _drive_playout(bias, true)
	if int(learnt["starved"]) > 0:
		return _fail(("a clock measuring the tick at %.0f%% of true starved on %d of %d frames "
				+ "(depth %.2f-%.2f against a target of %.1f, trim settled at %.3f). Each starved "
				+ "frame is the body holding still, and the bar on this item is zero of them")
				% [bias * 100.0, int(learnt["starved"]), int(learnt["frames"]),
				float(learnt["depth_min"]), float(learnt["depth_max"]), AssayScene.PLAYOUT_DELAY,
				float(learnt["trim"])])
	# AND IT HOLDS THE BUFFER AT THE DEPTH IT IS AIMED AT, not merely above zero: a clock that
	# survived by sitting on one tick of history would starve on the first late bundle.
	if absf(float(learnt["depth_mean"]) - AssayScene.PLAYOUT_DELAY) > 0.5:
		return _fail(("the buffer averaged %.2f ticks deep against a target of %.1f: the loop is not "
				+ "holding the depth it is aimed at, it is parked somewhere else")
				% [float(learnt["depth_mean"]), AssayScene.PLAYOUT_DELAY])
	# **AND THE CORRECTION COSTS NO DRAWN SPEED, which is the half a buffer number cannot show.** The
	# clock must advance ticks at the rate the HOST produced them, or the body walks at the wrong
	# speed for as long as the session lasts.
	#
	# **THIS USED TO READ THE CLOCK'S PLAYED-OUT RATE AND THAT ASSERTION COULD NOT FAIL** (found by
	# sweeping it, 2026-10-05). `playout_at` clamps `at` into the span the queue holds, so a clock
	# running 2.2x too fast is dragged back to `newest` every frame and its AVERAGE rate comes out at
	# the host's exactly -- measured 1.000 of true at an estimate 45% short, while 600 frames of the
	# same run were starved. The quantity that is not laundered by the clamp is what the loop
	# INTENDED: `rate * trim` over the believed tick length, which is the speed the body is drawn at
	# whenever the clock is not against a stop. See `_drive_playout`.
	var intended := float(learnt["intend_mean"])
	if absf(intended - 1.0) > 0.02:
		return _fail(("the loop settled on %.1f%% of the host's real tick rate over the steady "
				+ "stretch: a body drawn at that rate is walking at the wrong speed, buffer or no "
				+ "buffer") % [intended * 100.0])
	# A HONEST MEASUREMENT MUST NOT BE MADE WORSE BY ANY OF THIS. The same drive with the estimate
	# exactly right is the case every number on this item was taken in.
	var exact := _drive_playout(1.0, true)
	if int(exact["starved"]) > 0 or absf(float(exact["depth_mean"]) - AssayScene.PLAYOUT_DELAY) > 0.5:
		return _fail(("with the tick measured exactly right the clock starved %d of %d frames and "
				+ "held %.2f ticks of buffer: the integral has broken the case that already worked")
				% [int(exact["starved"]), int(exact["frames"]), float(exact["depth_mean"])])
	# **AND A PERFECT HOST, PERFECTLY MEASURED, MUST NOT MAKE THE CLOCK BEND AT ALL.** This is the
	# ±10% the controller used to inject into every walk by itself: `newest` jumps a whole tick at
	# each arrival while the clock slides between them, so an error measured against the last whole
	# tick saw-tooths by ±0.5 even when nothing is wrong -- and at `PLAYOUT_CATCHUP` 0.5 that drives
	# the rate to BOTH of its stops inside every tick. Every frame outside the bar in three real
	# window runs was the rate sitting on a stop. 5% is a bar and not a measurement: the ripple with
	# the production estimate in place is far under it, and without it the number is the clamp.
	if float(exact["ripple"]) > 0.05:
		return _fail(("a steady host measured exactly right still bent the clock by %.1f%% -- the "
				+ "controller is modulating the body's drawn speed by that much on its own, ten "
				+ "times a second, with nothing wrong to correct")
				% [float(exact["ripple"]) * 100.0])
	return true


## **A FRAME MOVES THE BODY BY ITS OWN DELTA, NOT BY THE CLOCK ON THE WALL** (ASSA-197).
##
## THE DEFECT THIS EXISTS FOR WAS THE LAST 15% OF THE BAR AND NOTHING COULD SEE IT. The playout
## clock advanced by the difference between two `Time.get_ticks_msec()` readings taken wherever the
## clock happened to be advanced from -- a drawn frame, or a bundle landing between two frames. So
## the distance published in a frame was sized for an interval that frame was not shown for, and the
## error alternated: a long frame drew a short step and the next short frame drew a long one. In a
## real window (`tools/motion_speed_probe.gd`, 2026-10-05, seed 14247) the drawn speed was inside
## Wren's +/-25% on 95% of frames when the frame rate held steady at 90 fps and on 82-86% when frame
## time varied between 11 and 28 ms, with the out-of-bar frames in alternating too-fast/too-slow
## pairs. The reading is also quantised to a millisecond, which is 9% of a 90 fps frame and
## therefore 9% of the body's drawn speed, for nothing.
##
## **AND THE ARRIVAL PATH HAD TO STOP ADVANCING WITH IT**, or a bundle landing mid-frame adds its
## own wall-clock gap on top of the frame's delta and the clock runs fast by the fraction of the
## frame it landed in. Both halves are asserted here, because either one alone is a different bug.
func test_a_frame_moves_the_body_by_its_own_delta_and_not_by_the_wall_clock() -> bool:
	var screen := _joined()
	if not screen._sim.running():
		return _fail("no offline world: %s" % screen._sim.fail_reason)
	screen._show_close_up(true)
	# **A BUFFER FIRST, AND THE WARM-UP READS THE BOX'S OWN NUMBER BACK SO IT CANNOT DRAIN IT.** The
	# wall delay has to be real -- it is the only thing `playout_step` has to measure the host's tick
	# length from -- but how long the box then took to run the loop must not decide how deep the
	# buffer ends up. So each cycle produces one tick and plays out exactly one tick: the frame delta
	# handed in is `_tick_gap`, whatever this box just measured it to be.
	#
	# TWO EARLIER VERSIONS OF THIS WARM-UP GOT IT WRONG IN BOTH DIRECTIONS, which is why it is spelt
	# out. Frames of a fixed 0.09 s against a tick the loaded studio Mac measures at 0.16 s drained
	# the buffer on CI to 0.93 ticks (2026-10-05, run 37254774762); topping it up with three back-to-
	# back arrivals instead left the clock 5.75 ticks behind with the queue one slot from full, and
	# the end of this test then failed for a reason that had nothing to do with its subject (see the
	# premise below). A cycle that is balanced by construction has neither failure mode.
	for _i in range(12):
		OS.delay_msec(RELAY_TICK_MS)
		_tick(screen)
		# THROUGH `_process`, NOT `_refresh_world`: the hand-down from the engine's delta to the clock
		# is a step of this path, and a test that skips it cannot see it break. Nerite mutated
		# `_process`'s `_refresh_world(delta)` to a constant 1/60 on 2026-10-05 and the whole suite
		# stayed green, because every assertion here called `_refresh_world` directly.
		screen._process(float(screen._tick_gap))
	if float(screen._play_tick) < 0.0:
		return _fail("the playout clock never started over 12 ticks, so there is nothing to measure")
	if float(screen._play_depth) < 1.0:
		return _fail(("the buffer holds %.2f ticks after a balanced warm-up, under the one tick this "
				+ "measurement needs: six frames of play-out would hit the end of the queue and "
				+ "measure the clamp instead of what moves the clock") % [float(screen._play_depth)])
	# **THE TWO CLOCKS ARE THEN MADE TO DISAGREE BY 5x**: six frames of 10 ms each is 0.6 of a tick,
	# while the wall clock between them runs 300 ms, which is 3 ticks. A clock reading the wall
	# cannot pass this and a clock reading its frames cannot fail it.
	var before: float = screen._play_tick
	for _i in range(6):
		OS.delay_msec(50)
		screen._process(0.01)
	var moved: float = float(screen._play_tick) - before
	# IN THE CLOCK'S OWN UNITS, not the fixture's: `_tick_gap` is the tick length this client has
	# measured, and a frame of 10 ms is worth 0.01/_tick_gap of a tick whatever the box managed to
	# deliver. Pinning this to RELAY_TICK_MS would make a slow runner fail a test about a denominator
	# it has nothing to do with.
	var want := 6.0 * 0.01 / maxf(float(screen._tick_gap), 0.001)
	if bool(screen._starved):
		return _fail(("the clock starved during the measurement (depth %.2f): it ran out of "
				+ "positions, so how far it advanced says nothing about what moved it")
				% [float(screen._play_depth)])
	if absf(moved - want) > 0.25:
		return _fail(("six 10 ms frames spread over 300 ms of wall clock advanced the playout clock "
				+ "%.3f ticks. The frames are worth %.3f ticks and the wall clock %.3f: the body is "
				+ "being moved by %s") % [moved, want,
				6.0 * 0.05 / maxf(float(screen._tick_gap), 0.001),
				"the wall clock" if moved > want * 2.0 else "neither of them"])
	# **AND THE DELTA IS THE ONE THE ENGINE HANDED DOWN, not a constant this path invented.** The
	# assertion above compares against `_tick_gap` with a tolerance wide enough to swallow both rate
	# stops, so a `_process` passing a fixed 1/60 can hide inside it at some frame rates. This one
	# cannot be hidden from: two frames whose deltas differ by 8x must move the clock by 8x. A
	# constant delta -- of any value -- makes this ratio 1.
	var small := _moved_by_process(screen, 0.004)
	var large := _moved_by_process(screen, 0.032)
	if small <= 0.0:
		return _fail(("a 4 ms frame moved the playout clock %.4f ticks, so there is no ratio to "
				+ "measure (depth %.2f)") % [small, float(screen._play_depth)])
	# 8x, LOOSELY: `rate` is re-derived per frame from a depth the first of these two frames has
	# already changed, so the two are not scaled copies of each other. +/-25% of 8 still has no
	# overlap with the 1.0 a constant delta gives.
	var ratio := large / small
	if ratio < 6.0 or ratio > 10.0:
		return _fail(("a 32 ms frame moved the body %.4f ticks and a 4 ms frame %.4f: a ratio of "
				+ "%.2f where the deltas differ by 8x. The clock is being stepped by something "
				+ "other than the delta `_process` was handed") % [large, small, ratio])
	# **THE PREMISE OF THE LAST ASSERTION, WHICH IT DID NOT HAVE AND NEEDED** (ASSA-197, 2026-10-05).
	# `_pending` is capped at `PLAYOUT_QUEUE` and an arrival pops the oldest entry to make room. If
	# the clock is further behind than that cap, the position it is drawing FROM is the one thrown
	# away, and `playout_at`'s ASSA-119 clamp drags the clock up to the oldest position still held.
	# That is a real forward jump of the body -- `_drive_playout` counts it as `dragged` and the sweep
	# below requires zero of them -- but it is NOT a bundle moving the clock, and the assertion below
	# would report it as one. Measured on the version of this fixture that topped the buffer up with
	# three back-to-back arrivals: the clock sat 5.75 ticks behind with 7 of 8 slots full, two
	# arrivals evicted tick 6, and the clock went 6.254 -> 7.000 with `starved` false, `depth` 7.00
	# and no flag of any kind saying it had happened.
	var queue := _queue_ticks(screen)
	var cap: int = int((screen.get_script() as GDScript).get_script_constant_map()["PLAYOUT_QUEUE"])
	if queue.size() + 2 > cap:
		return _fail(("the queue holds %d of its %d slots (%s) with the clock %.2f ticks behind, so "
				+ "the two arrivals below would evict the position being drawn from and the clamp "
				+ "would drag the clock forward. That is a dragged frame, not a bundle moving the "
				+ "clock, and this fixture is supposed to leave room")
				% [queue.size(), cap, str(queue), float(screen._play_depth)])
	# AND A BUNDLE LANDING IS NOT A FRAME. It enqueues a position; it does not move the body.
	var held: float = screen._play_tick
	_tick(screen)
	OS.delay_msec(30)
	_tick(screen)
	if not is_equal_approx(float(screen._play_tick), held):
		return _fail(("two bundles landing moved the playout clock from %.3f to %.3f without a "
				+ "frame being drawn. Then a bundle that lands mid-frame adds its own wall-clock "
				+ "gap on top of that frame's delta and the clock runs fast")
				% [held, float(screen._play_tick)])
	screen.queue_free()
	return true


## **HOW WRONG THE CLIENT'S IDEA OF A TICK MAY BE BEFORE A PLAYER SEES IT** (ASSA-197; Wren asked
## for this test ahead of the three window runs, and it is the only thing on this item that speaks
## about a machine none of us owns).
##
## The board plays on Windows. `playout_step` measures the host's tick length from arrival instants,
## and on Windows the relay child's sleep and the loopback socket sit on a ~15.6 ms timer, so the
## measurement can be biased there in a way no probe of ours can see. This test asks the arithmetic
## instead: how wrong may that measurement be before the body holds still or jumps?
##
## **MEASURED HERE, 2026-10-05 (and printed when it passes, because it is the number the demo
## request quotes):** zero held frames and zero jumps from an estimate **0.58x to 1.49x of the true
## tick length**, with the buffer at its target and the body's drawn speed inside +/-7% of true
## every frame. Wren asked for 0.75-1.25; the mechanism is wider than that on both sides.
##
## **AND THE EDGES ARE NOT A COINCIDENCE, WHICH IS WHY THEY ARE ASSERTED AGAINST THE CONSTANTS.**
## Depth rests only where the clock advances at the host's real rate, which needs
## `rate * trim = bias`. `rate` is clamped to 1 +/- `PLAYOUT_NUDGE` and `trim` to
## 1 +/- `PLAYOUT_TRIM_MAX`, so the widest bias the loop can answer is their product -- 0.585 and
## 1.485 with today's constants. The search below finds the real edge in 1% steps and requires it to
## sit within 0.05 of that product: if someone widens a clamp, the tolerance moves with it and this
## test says so with both numbers.
func test_the_playout_clock_states_how_wrong_a_tick_measurement_may_be() -> bool:
	# **THE PREMISE, FIRST.** The sweep is only evidence if the swept range is a range the clock
	# needs its integral for: with the trim discarded every frame, both ends must break, and they
	# must break in the two different ways (see `_drive_playout`).
	var low_control := _drive_playout(0.75, false, 40.0, 20.0)
	var high_control := _drive_playout(1.25, false, 40.0, 20.0)
	if int(low_control["starved"]) == 0 or int(high_control["dragged"]) == 0:
		return _fail(("THE CONTROL HELD: with the integral discarded, an estimate 25% short starved "
				+ "%d frames and one 25% long dragged the body %d times. Both must be non-zero or "
				+ "the sweep below is a sweep of a range the proportional term covers on its own, "
				+ "and it proves nothing about the trim")
				% [int(low_control["starved"]), int(high_control["dragged"])])
	var biases: Array[float] = []
	var bias := 0.75
	while bias <= 1.2501:
		biases.append(bias)
		bias += 0.05
	for b in biases:
		var steady := _drive_playout(b, true, 40.0, 20.0)
		if int(steady["starved"]) > 0 or int(steady["dragged"]) > 0:
			return _fail(("an estimate at %.0f%% of the true tick length held the body %d times and "
					+ "jumped it %d times after settling (depth %.2f-%.2f, trim %.3f): the bar on "
					+ "this item is zero of either") % [b * 100.0, int(steady["starved"]),
					int(steady["dragged"]), float(steady["depth_min"]), float(steady["depth_max"]),
					float(steady["trim"])])
		if absf(float(steady["depth_mean"]) - AssayScene.PLAYOUT_DELAY) > 0.6:
			return _fail(("at %.0f%% of true the buffer settled %.2f ticks deep against a target of "
					+ "%.1f: the loop is parked somewhere other than where it is aimed, so the next "
					+ "late bundle is felt") % [b * 100.0, float(steady["depth_mean"]),
					AssayScene.PLAYOUT_DELAY])
		if absf(float(steady["intend_mean"]) - 1.0) > 0.02:
			return _fail(("at %.0f%% of true the loop settled on %.1f%% of the host's rate: the body "
					+ "walks at that speed for the whole session")
					% [b * 100.0, float(steady["intend_mean"]) * 100.0])
		# AND THE BAR ITSELF, per frame, on the quantity the window probe reads off the screen.
		if float(steady["ratio_min"]) < 1.0 - 0.25 or float(steady["ratio_max"]) > 1.0 + 0.25:
			return _fail(("at %.0f%% of true the drawn speed ranged %.3f-%.3f of true frame by "
					+ "frame, outside the +/-25%% this item is gated on")
					% [b * 100.0, float(steady["ratio_min"]), float(steady["ratio_max"])])
		# **THE COLD START IS JUDGED TOO, AND IT IS THE HALF THAT WAS RED ON MAIN.** The sweep above
		# skips the first 20 s; a player does not. Judged from the first frame the clock runs, an
		# estimate 25% short used to hold the body 13 times while the trim wound up (`PLAYOUT_TRIM`
		# 0.05, 2026-10-04). That is a session's first second, which is the one the board feels.
		var cold := _drive_playout(b, true, 40.0, 0.0)
		if int(cold["starved"]) > 0 or int(cold["dragged"]) > 0:
			return _fail(("FROM A COLD START at %.0f%% of true the body held still %d times and "
					+ "jumped %d times while the integral wound up (90%% of the correction took "
					+ "%.1f s, buffer down to %.2f ticks): the first seconds of a session are what "
					+ "a player judges") % [b * 100.0, int(cold["starved"]), int(cold["dragged"]),
					float(cold["settle90"]), float(cold["wind_depth"])])
	# **NOT A FUNCTION OF THE FRAME RATE.** The integral learns per second (`dt` is in it) rather
	# than per frame, so the same host must be tracked the same way on a 30 Hz laptop and a 144 Hz
	# PC. Both ends of the swept range, both rates.
	for fps in [30.0, 144.0]:
		for b in [0.75, 1.25]:
			var paced := _drive_playout(float(b), true, 40.0, 20.0, AssayScene.PLAYOUT_TRIM_NONE,
					float(fps))
			if int(paced["starved"]) > 0 or int(paced["dragged"]) > 0:
				return _fail(("at %.0f fps an estimate at %.0f%% of true held the body %d times and "
						+ "jumped it %d times, where the same estimate is clean at 90 fps: the loop "
						+ "is learning per frame instead of per second")
						% [float(fps), float(b) * 100.0, int(paced["starved"]),
						int(paced["dragged"])])
	var predicted_low := (1.0 - AssayScene.PLAYOUT_NUDGE) * (1.0 - AssayScene.PLAYOUT_TRIM_MAX)
	var predicted_high := (1.0 + AssayScene.PLAYOUT_NUDGE) * (1.0 + AssayScene.PLAYOUT_TRIM_MAX)
	var edge_low := _playout_edge(predicted_low, -1.0)
	var edge_high := _playout_edge(predicted_high, 1.0)
	if edge_low < 0.0 or edge_high < 0.0:
		return _fail(("the search for the clock's breaking point did not find one within 8% of the "
				+ "%.3f-%.3f the clamps predict: either the clamps are no longer what bounds this, "
				+ "or the fixture has stopped being able to break the clock at all")
				% [predicted_low, predicted_high])
	if absf(edge_low - predicted_low) > 0.05 or absf(edge_high - predicted_high) > 0.05:
		return _fail(("the clock breaks at %.2fx and %.2fx the true tick length, where the clamps "
				+ "(rate 1+/-%.2f, trim 1+/-%.2f) predict %.3f and %.3f. Something other than the "
				+ "two clamps is bounding the tolerance, so the sentence this test exists to say -- "
				+ "how wrong a PC's tick measurement may be -- is no longer derivable from them")
				% [edge_low, edge_high, AssayScene.PLAYOUT_NUDGE, AssayScene.PLAYOUT_TRIM_MAX,
				predicted_low, predicted_high])
	# THE EDGES ARE THE FIRST BIAS THAT BROKE, so what the clock HOLDS is one 1% step inside them.
	print(("  the playout clock holds a tick-rate misread from %.2fx to %.2fx of true (%.0f%% short "
			+ "to %.0f%% long) with no held and no jumped frame; it first breaks at %.2fx (holds "
			+ "still) and %.2fx (jumps), and the clamps predict %.2fx/%.2fx")
			% [edge_low + 0.01, edge_high - 0.01, (1.0 - edge_low - 0.01) * 100.0,
			(edge_high - 0.01 - 1.0) * 100.0, edge_low, edge_high, predicted_low, predicted_high])
	return true


## THE FIRST MISREAD THAT BREAKS THE CLOCK, searched in 1% steps from inside the range the clamps
## predict outwards. Returns -1.0 if nothing broke within 8%, which is a failure of the fixture
## rather than a wider tolerance: a loop that cannot be broken by a 2x misread is not being driven.
func _playout_edge(predicted: float, direction: float) -> float:
	var bias := predicted - direction * 0.06
	for _step in range(14):
		var run := _drive_playout(bias, true, 40.0, 20.0)
		if int(run["starved"]) > 0 or int(run["dragged"]) > 0:
			return bias
		bias += direction * 0.01
	return -1.0


## **WHAT THE BODY DOES WHILE THE INTEGRAL IS STILL LEARNING** (ASSA-197, Wren's third ask), at the
## error this Mac actually produced: the client measured 89.8 ms against a host sending every
## 104.2 ms, 86% of true, before the pairing fix. A clock that ends up right after twenty seconds of
## winding is still wrong for twenty seconds, and the first seconds of a walk are what a player
## judges.
##
## **MEASURED: nothing visible.** 90% of the correction is in by 4.3 s, no held frame, no jump, the
## buffer never shallower than 1.4 of its 2.5 ticks, and the drawn speed inside 0.94-1.07 of true
## for the whole wind-up. **And it is paid once per session, not once per walk:** the trim is a
## member of `main.gd` written only from this function's output, so the second walk starts where the
## first left off -- asserted below on the source, because the bias belongs to the platform and a
## reset hidden in a join or a respawn would put the transient back on every walk.
func test_the_playout_trim_settles_from_a_cold_start_without_holding_the_body() -> bool:
	var bias := 0.86
	var cold := _drive_playout(bias, true, 40.0, 0.0)
	# PREMISE: there has to be something to learn, or every assertion below passes on a clock that
	# never moved its trim at all.
	if absf(float(cold["trim"]) - 1.0) < 0.10:
		return _fail(("THE TRIM BARELY MOVED (%.3f) at an estimate 14%% short, so this test is not "
				+ "watching an integral wind up and its numbers mean nothing")
				% [float(cold["trim"])])
	if int(cold["starved"]) > 0 or int(cold["dragged"]) > 0:
		return _fail(("winding up from a 14%% error held the body %d times and jumped it %d times "
				+ "(90%% of the correction took %.1f s): the bar on this item is zero")
				% [int(cold["starved"]), int(cold["dragged"]), float(cold["settle90"])])
	if float(cold["ratio_min"]) < 0.85 or float(cold["ratio_max"]) > 1.15:
		return _fail(("while the trim wound up the body was drawn at %.3f-%.3f of true speed: the "
				+ "transient is visible, and it is the first seconds of every session")
				% [float(cold["ratio_min"]), float(cold["ratio_max"])])
	if float(cold["settle90"]) > 8.0:
		return _fail(("the integral took %.1f s to cover 90%% of a 14%% error (and %.1f s to come "
				+ "within 1%%): the buffer runs shallow for that whole stretch, where a host stall "
				+ "has less to absorb it") % [float(cold["settle90"]), float(cold["settle_s"])])
	if float(cold["wind_depth"]) < 0.75:
		return _fail(("the buffer fell to %.2f ticks during the first five seconds while the trim "
				+ "learnt: that is a quarter of a tick from holding the body still, and the next "
				+ "late bundle spends it") % [float(cold["wind_depth"])])
	# **A WARM START, which is what every walk after the first one is.** Handed the trim the cold run
	# settled on, the clock has no transient at all: judged from its very first frame.
	var warm := _drive_playout(bias, true, 12.0, 0.0, float(cold["trim"]))
	if int(warm["starved"]) > 0 or int(warm["dragged"]) > 0:
		return _fail(("a clock STARTED at the settled trim %.3f still held the body %d times and "
				+ "jumped it %d times: then the wind-up is not what the first seconds cost and the "
				+ "cause is elsewhere") % [float(cold["trim"]), int(warm["starved"]),
				int(warm["dragged"])])
	if float(warm["ratio_min"]) < 0.88 or float(warm["ratio_max"]) > 1.12:
		return _fail(("a warm clock drew the body at %.3f-%.3f of true from its first frame: the "
				+ "steady state is not steady") % [float(warm["ratio_min"]),
				float(warm["ratio_max"])])
	# **AND THE TRIM IS SESSION STATE.** One assignment in `main.gd` and it is the loop's own output;
	# a `_play_trim = PLAYOUT_TRIM_NONE` anywhere -- a join, a respawn, a new walk -- would put the
	# wind-up above back on every walk, and no run of this fixture could see it.
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	if source.is_empty():
		return _fail("could not read res://scripts/main.gd to check how the trim is carried")
	var writes: Array[String] = []
	for line in source.split("\n"):
		var text := String(line).strip_edges()
		if text.begins_with("_play_trim =") or text.begins_with("_play_trim:"):
			writes.append(text)
	if writes.size() != 1 or writes[0] != "_play_trim = float(cursor[\"trim\"])":
		return _fail(("the playout trim is written %d times in main.gd (%s). It must be written "
				+ "once, from the loop's own output: anything that resets it hands every walk the "
				+ "wind-up this test just measured") % [writes.size(), ", ".join(writes)])
	return true


## DRIVE `playout_at` AGAINST A SYNTHETIC HOST: `bias` is how long the clock BELIEVES a tick is as a
## fraction of how long it really is, and `learn` is whether the integral term is handed back.
##
## NO WALL CLOCK AND NO SOCKET -- the host's ticks and the frames are both counted out of a loop, so
## this is the same arithmetic the window runs with none of the load that makes a probe unrepeatable.
## The queue cap and the dropping of positions the clock has passed are `main.gd`'s, copied here
## because they decide what `ticks` holds and therefore what depth means.
##
## **TWO FAILURES, NOT ONE, AND A COUNT OF STARVED FRAMES ONLY SEES THE FIRST.** A clock that runs
## too fast outruns its data and the body HOLDS (`starved`). A clock that runs too slow falls behind
## until the queue cap evicts history the clock has not played yet, and then `playout_at`'s own
## `clampf(at, oldest, newest)` DRAGS the body forward to catch the tail -- a jump, from a loop that
## never starved once. `dragged` counts a frame whose free-running advance landed behind `oldest`,
## which is the mirror of `starved` and the only way the slow side is visible at all.
##
## `judge_from` is when the statistics start, so a caller can ask about the steady state (the default
## skips the buffer filling and the integral learning) or about the cold start (0.0, which judges
## every frame from the first one the clock runs). `trim_in` is a WARM START: the trim a previous
## session settled on, because that is what the real client carries (`main.gd::_play_trim` is a
## member written only from this function's own output).
func _drive_playout(bias: float, learn: bool, seconds := 12.0, judge_from := 3.0,
		trim_in := AssayScene.PLAYOUT_TRIM_NONE, fps := 90.0) -> Dictionary:
	var tick := float(RELAY_TICK_MS) / 1000.0
	var frame := 1.0 / fps
	var delay: float = AssayScene.PLAYOUT_DELAY
	var play: float = AssayScene.PLAYOUT_UNSTARTED
	var trim := trim_in
	var ticks: Array[int] = []
	var next_tick := 0.0
	var tick_no := 0
	var now := 0.0
	# WHEN THE NEWEST POSITION LANDED, as the client would see it: on the frame it was drained, which
	# is what `main.gd` stamps. The loop's error is measured against it (see `playout_at`).
	var landed := 0.0
	var starved := 0
	var dragged := 0
	var frames := 0
	var depth_min := INF
	var depth_max := -INF
	var depth_sum := 0.0
	var wind_depth := INF
	var intend_min := INF
	var intend_max := -INF
	var intend_sum := 0.0
	var ratio_min := INF
	var ratio_max := -INF
	var ripple := 0.0
	var play_prev := -1.0
	var started_at := -1.0
	var trim_path: Array[float] = []
	var trim_when: Array[float] = []
	while now < seconds:
		now += frame
		while next_tick <= now:
			ticks.append(tick_no)
			tick_no += 1
			next_tick += tick
			landed = now
			while ticks.size() > 8:
				ticks.pop_front()
		var oldest := float(ticks[0]) if not ticks.is_empty() else 0.0
		var was := play
		var cursor := AssayScene.playout_at(play, ticks, frame, tick * bias, delay, now - landed, trim)
		play = float(cursor["play_tick"])
		if learn:
			trim = float(cursor["trim"])
		for _i in range(int(cursor["index"])):
			ticks.pop_front()
		if was >= 0.0:
			var free := was + frame / (tick * bias) * float(cursor["rate"]) * float(cursor["trim"])
			if free < oldest - 1e-9:
				dragged += 1
		if play >= 0.0 and started_at < 0.0:
			started_at = now
		# HOW FAR THE CLOCK ACTUALLY MOVED THIS FRAME, as a fraction of the host's true tick rate:
		# the drawn speed of a body walking one tile a tick, which is the bar on ASSA-197.
		var ratio := -1.0
		if play >= 0.0 and play_prev >= 0.0:
			ratio = (play - play_prev) / frame * tick
		play_prev = play
		if play >= 0.0:
			trim_path.append(trim)
			trim_when.append(now)
			if now - started_at < 5.0:
				wind_depth = minf(wind_depth, float(cursor["depth"]))
		if now < judge_from or play < 0.0:
			continue
		frames += 1
		if bool(cursor["starved"]):
			starved += 1
		var depth := float(cursor["depth"])
		depth_min = minf(depth_min, depth)
		depth_max = maxf(depth_max, depth)
		depth_sum += depth
		# WHAT THE LOOP INTENDED, which the clamp launders out of any measurement of what it did:
		# `rate * trim` believed ticks a second over `bias` real ones. See the test above.
		var intend := float(cursor["rate"]) * float(cursor["trim"]) / bias
		intend_min = minf(intend_min, intend)
		intend_max = maxf(intend_max, intend)
		intend_sum += intend
		if ratio >= 0.0:
			ratio_min = minf(ratio_min, ratio)
			ratio_max = maxf(ratio_max, ratio)
		ripple = maxf(ripple, absf(float(cursor["rate"]) - 1.0))
	# **WHEN THE INTEGRAL ARRIVED**, two ways, because one number hides the shape: `settle_s` is the
	# last instant it was more than 1% from where it ends (a slow tail keeps this high), `settle90`
	# the first instant it had covered 90% of the correction it eventually makes.
	var settle := 0.0
	var settle90 := 0.0
	var need := absf(trim - 1.0) * 0.9
	for i in trim_path.size():
		if absf(trim_path[i] - trim) > 0.01:
			settle = trim_when[i] - started_at
		if absf(trim_path[i] - 1.0) < need:
			settle90 = trim_when[i] - started_at
	return {
		"starved": starved,
		"dragged": dragged,
		"frames": frames,
		"depth_min": depth_min,
		"depth_max": depth_max,
		"depth_mean": depth_sum / maxf(float(frames), 1.0),
		"wind_depth": wind_depth if wind_depth < INF else -1.0,
		"intend_min": intend_min if intend_min < INF else -1.0,
		"intend_max": intend_max if intend_max > -INF else -1.0,
		"intend_mean": intend_sum / maxf(float(frames), 1.0),
		"ratio_min": ratio_min if ratio_min < INF else -1.0,
		"ratio_max": ratio_max if ratio_max > -INF else -1.0,
		"ripple": ripple,
		"trim": trim,
		"trim_in": trim_in,
		"settle_s": settle,
		"settle90": settle90,
	}


## **A WALKING BODY'S OWN RECTANGLE MOVES WITH IT, SUB-TILE** (ASSA-197, and ASSA-200 is the
## measurement).
##
## THE BUG THIS EXISTS FOR IS THE ONE EVERY TEST IN THIS FILE AGREED WITH FOR A FORTNIGHT. `main.gd`
## lerped a player's position between the two ticks bracketing it and handed the view a fractional
## `at`; `AssayScene._place` then took `Vector2i`, so the lerp was floored away before anything
## reached the screen. The body was drawn on a whole-tile grid while the camera slid continuously
## under it. Maren's `tools/maren_snap_probe.gd` read the drawn `dest` rather than the lerp's output
## and found a **32 px peak-to-peak saw-tooth at the tick rate**, the body separating from its own
## camera-locked foot mark by 34.2 px -- more than a whole tile -- ten times a second. The board
## called it jumpy three times and no assertion we owned could see it, because every one of them
## read `view["players"][i]["at"]`, which is the lerp's INPUT to the thing that was broken.
##
## SO THIS READS THE `dest` RECT AND NOTHING ELSE, in the two camera cases that fail differently:
##
## 1. **A FIXED camera** isolates the renderer: a body a fraction of a tile further east must be
##    drawn exactly that fraction of 32 px further east, and the ground must not move at all. The
##    floored code drew 16 of 17 samples in the same place and then jumped a whole tile.
## 2. **The REAL centring camera**, which is the case a player is actually in: the body is drawn in
##    the same place every frame and the GROUND slides under it. That is the pairing Maren measured
##    -- `d(body)` must equal `d(ground)` -- and it is the half that says the picture is right
##    rather than that the arithmetic is.
##
## ONE TEST AND NOT TWO, on the rule that two tests earn their keep only when a mutation separates
## them: both halves read the single `corner * TILE_PX` in `_place`, so flooring it again reddens
## both and nothing reddens one.
func test_a_walking_bodys_own_rectangle_moves_with_it_sub_tile() -> bool:
	var world := Vector2i(96, 64)
	var fixed := AssayScene.camera_origin(Vector2(48.0, 32.0), world, WINDOW, 0.0)
	var samples := 16
	var first_body := Vector2.ZERO
	var first_pad := Vector2.ZERO
	var still_pad := Vector2.ZERO
	var slid_with_the_walk := 0
	for step in samples + 1:
		var frac := float(step) / float(samples)
		var at := Vector2(48.0 + frac, 32.0)
		# CASE 1: THE CAMERA DOES NOT MOVE, so every pixel the body moves is the renderer's -- and
		# the spawn pad is the control that says so, because a fixed camera may not move it at all.
		var still := _view({"origin": fixed,
				"players": [{"at": at, "facing": "E", "moving": true}]})
		var frozen := AssayScene.placements(still)
		var bodies := _of(frozen, "player")
		var anchors := _of(frozen, "spawn")
		if bodies.size() != 1 or anchors.size() != 1:
			return _fail("a body at %s drew %d sprites and %d spawn pads, not one of each"
					% [at, bodies.size(), anchors.size()])
		var body: Vector2 = ((bodies[0] as Dictionary)["dest"] as Rect2).position
		var anchor: Vector2 = ((anchors[0] as Dictionary)["dest"] as Rect2).position
		if step == 0:
			first_body = body
			still_pad = anchor
		if anchor.distance_to(still_pad) > 0.01:
			return _fail(("the spawn tile moved from %s to %s under a camera that did not move, so "
					+ "case 1 is measuring the whole scene sliding and not the body")
					% [still_pad, anchor])
		var want := first_body + Vector2(frac * AssayScene.TILE_PX, 0.0)
		if body.distance_to(want) > 0.01:
			return _fail(("%.3f of a tile east of (48, 32) the body's own rect is drawn at %s; a "
					+ "renderer that moves with its subject draws it at %s. %.1f px of the sim's "
					+ "position never reached the screen") % [frac, body, want,
					body.distance_to(want)])
		# CASE 2: THE REAL CAMERA. The body holds still and the WORLD slides, which is the pair of
		# facts a player sees.
		#
		# THE SPAWN PAD IS THE CONTROL AND THE FIRST `ground` PLACEMENT IS NOT, which this test's own
		# premise guard caught before its assertion did (15 of 16 steps, not 16). `visible_tiles`
		# slides with the camera, so `_of(places, "ground")[0]` is a DIFFERENT sim tile once the
		# window crosses a column and its rect jumps a tile back. The pad is the sim's one spawn
		# tile, so it is the same tile in every sample -- Maren's "one FIXED ground tile as control".
		var rolling := _view({"origin": AssayScene.camera_origin(at, world, WINDOW, 0.0),
				"players": [{"at": at, "facing": "E", "moving": true}]})
		var places := AssayScene.placements(rolling)
		var drawn := _of(places, "player")
		var pads := _of(places, "spawn")
		if drawn.size() != 1 or pads.size() != 1:
			return _fail(("under the real camera %s drew %d bodies and %d spawn pads, so there is "
					+ "nothing to compare") % [at, drawn.size(), pads.size()])
		var rolled: Vector2 = ((drawn[0] as Dictionary)["dest"] as Rect2).position
		var pad: Vector2 = ((pads[0] as Dictionary)["dest"] as Rect2).position
		if step == 0:
			first_pad = pad
			continue
		if pad.distance_to(first_pad - Vector2(frac * AssayScene.TILE_PX, 0.0)) < 0.01:
			slid_with_the_walk += 1
		if rolled.distance_to(first_body) > 0.01:
			return _fail(("under a CENTRING camera a body %.3f of a tile east is drawn at %s and "
					+ "not at %s, so your body moves across the window while the world stands "
					+ "still -- the camera and the sprite disagree about where you are")
					% [frac, rolled, first_body])
	# THE PREMISE OF CASE 2, AND WITHOUT IT THE ASSERTION ABOVE PASSES ON A FROZEN SCENE. A body that
	# holds still is only correct because the world moves underneath it by exactly as much as the
	# body would have; if the world never moved either, nothing was walking and this test would be
	# green on a renderer that ignores `at` completely.
	if slid_with_the_walk < samples:
		return _fail(("the spawn tile slid by exactly the walk under %d of %d sub-tile steps, so "
				+ "case 2's still body is a frozen scene rather than a camera tracking a walk")
				% [slid_with_the_walk, samples])
	return true


## **THE CEILING IS A LIMIT AND NOT A SAFE GUESS** (ASSA-156).
##
## `player_ceiling` is the sprite's top at a whole-tile position under a centring camera, and since
## ASSA-197 that is the whole answer -- it used to subtract a tile to cover the climb a floored body
## made across one tile. The claim is still REASONING, and reasoning in a comment is a claim nobody
## ran. So this walks a body across one tile in 64 steps, through the real camera and the real
## `placements`, and asserts the bound from BOTH sides: no step is drawn above the ceiling, and the
## highest step reaches it to within one step. The second half is the one that matters -- `- TILE_PX`
## satisfied the first assertion for ever and quietly cost the event log a line.
func test_the_player_ceiling_is_the_highest_a_body_is_ever_drawn() -> bool:
	var ceiling := AssayScene.player_ceiling(_manifest(), WINDOW)
	if ceiling <= 0.0:
		return _fail("player_ceiling answered %f for the real manifest, so no panel has a bound"
				% ceiling)
	var steps := 64
	var highest := INF
	for step in steps:
		var at := Vector2(48.0, 32.0 + float(step) / float(steps))
		# HEADROOM 0.0, AND THE GUARD BELOW IS WHY IT IS SAFE: this walks one INTERIOR tile, the
		# assertion refuses to run if any bound binds, and the whole claim is about a camera that is
		# centring. ASSA-184's north bound cannot reach row 32.
		var origin := AssayScene.camera_origin(at, Vector2i(96, 64), WINDOW, 0.0)
		if origin.y <= 0.0 or origin.y >= float(64 * 32) - WINDOW.y:
			return _fail("the camera clamped at %s, so this test is about the wrong case" % at)
		var bodies := _of(AssayScene.placements(_view({"origin": origin,
				"players": [{"at": at, "facing": "S", "moving": true}]})), "player")
		if bodies.size() != 1:
			return _fail("a body at %s drew %d sprites, not one" % [at, bodies.size()])
		var top: float = ((bodies[0] as Dictionary)["dest"] as Rect2).position.y
		if top < ceiling - 0.01:
			return _fail(("a body at %s is drawn from y %f, ABOVE the ceiling %f that the log's "
					+ "panel is sized by: the panel would be covering its head") % [at, top, ceiling])
		highest = minf(highest, top)
	var slack := AssayScene.TILE_PX / float(steps) + 0.01
	if highest - ceiling > slack:
		return _fail(("the highest a body reaches is y %f and the ceiling claims %f, %f px lower "
				+ "than anything it bounds: the log's panel is paying for room nothing uses")
				% [highest, ceiling, highest - ceiling])
	return true


## AND IT IS THE SAME ANSWER WHEREVER YOU STAND, which is the whole reason the log's panel can be
## sized once at build time instead of being resized as you walk. An unclamped camera is one that is
## centring; `player_ceiling` therefore takes no tile at all, and this is the assertion that makes
## that signature honest rather than convenient.
func test_the_player_ceiling_does_not_depend_on_which_interior_tile_you_stand_on() -> bool:
	var ceiling := AssayScene.player_ceiling(_manifest(), WINDOW)
	for at in [Vector2(20.0, 10.0), Vector2(48.0, 32.0), Vector2(70.0, 50.0), Vector2(11.0, 6.0)]:
		# HEADROOM 0.0: every tile here is interior and the assertion is that the camera CENTRES, so
		# a bound of any sign binding would be the thing this test is written to catch.
		var origin := AssayScene.camera_origin(at, Vector2i(96, 64), WINDOW, 0.0)
		var bodies := _of(AssayScene.placements(_view({"origin": origin,
				"players": [{"at": at, "facing": "S", "moving": false}]})), "player")
		if bodies.size() != 1:
			return _fail("a body at %s drew %d sprites, not one" % [at, bodies.size()])
		var top: float = ((bodies[0] as Dictionary)["dest"] as Rect2).position.y
		# EXACTLY THE CEILING, AND IT USED TO BE A TILE BELOW IT. This read
		# `absf(top - TILE_PX - ceiling)`, and that `TILE_PX` was the floor `_place` has stopped
		# doing (ASSA-197): a body could be drawn a whole tile higher than its position said, so the
		# bound had to stand off by one. With the floor gone the bound is the position.
		if absf(top - ceiling) > 0.01:
			return _fail(("a body standing on tile %s is drawn from y %f; the ceiling is %f, so the "
					+ "camera is not centring there and one bound cannot serve every tile")
					% [at, top, ceiling])
	return true


## **AT THE WORLD'S NORTH EDGE THE CLAMP USED TO PUT YOUR BODY BEHIND THE PANEL** (ASSA-184).
##
## Maren's measurement on the real `placements()`: 6 of 64 rows drew the player WHOLLY above the log
## panel's ceiling and 2 more cut them in half, because `player_ceiling`'s single answer is derived
## from a camera that is CENTRING and the north clamp is a camera that has stopped. 12.5% of a
## world's deposits are centred in rows 0..7; on seed 777042 both grade-A Minyte deposits are.
##
## **WHAT MAKES THIS MORE THAN THE ARITHMETIC I ALREADY WROTE IN `camera_origin`.** It walks the
## whole north band through the real camera and the real `placements`, at four positions inside each
## row, and asserts three different things that a wrong `north_headroom` breaks differently:
##
## 1. no body is drawn above the ceiling -- the defect;
## 2. no body leaves the map rect at all -- row 0 used to draw from y -32, so you saw your legs;
## 3. every row from 1 south is still drawn at EXACTLY the centred position -- which is the half a
##    generous bound would silently cost, because a bound that binds in rows 1..8 pins the body and
##    jerks the world 32px per step instead.
func test_the_north_edge_rows_draw_a_whole_body_below_the_panel() -> bool:
	var world := Vector2i(96, 64)
	var ceiling := AssayScene.player_ceiling(_manifest(), WINDOW)
	var room := AssayScene.north_headroom(_manifest(), WINDOW)
	if ceiling <= 0.0 or room <= 0.0:
		return _fail(("ceiling %f and headroom %f: one of them has nothing to say, so every "
				+ "assertion below is vacuous") % [ceiling, room])
	# THE CENTRED ANSWER, MEASURED THROUGH THE RENDERER AT AN INTERIOR ROW and not read back off
	# `ceiling`: this is where a body is drawn when no bound of any sign binds, so a camera that
	# quietly stopped centring fails assertion 3 rather than agreeing with itself.
	#
	# IT USED TO BE `ceiling + TILE_PX` AND THE EXPECTATION USED TO SLIDE, `centred - TILE_PX *
	# quarter * 0.25` -- which is the saw-tooth Maren measured on ASSA-200 written in as the correct
	# answer. It WAS the correct answer: `_place` floored a body to a tile, so across one row the
	# sprite stood still while the camera descended 32 px under it, and this test pinned that. The
	# floor is gone (ASSA-197), so a centring camera draws a body in the same place at every fraction
	# of every row, and assertion 3 is now one number instead of a ramp.
	var interior := Vector2(48.0, 32.0)
	var sample := _of(AssayScene.placements(_view({
			"origin": AssayScene.camera_origin(interior, world, WINDOW, 0.0),
			"players": [{"at": interior, "facing": "S", "moving": false}]})), "player")
	if sample.size() != 1:
		return _fail(("an interior body at %s drew %d sprites, so there is no centred position to "
				+ "compare the north band against") % [interior, sample.size()])
	var centred: float = ((sample[0] as Dictionary)["dest"] as Rect2).position.y
	for row in 11:
		for quarter in 4:
			var at := Vector2(48.0, float(row) + float(quarter) * 0.25)
			var origin := AssayScene.camera_origin(at, world, WINDOW, room)
			var bodies := _of(AssayScene.placements(_view({"origin": origin,
					"players": [{"at": at, "facing": "S", "moving": quarter != 0}]})), "player")
			if bodies.size() != 1:
				return _fail(("a body at %s drew %d sprites, not one -- it was culled, which is the "
						+ "same picture as being hidden") % [at, bodies.size()])
			var body: Rect2 = (bodies[0] as Dictionary)["dest"]
			if body.position.y < ceiling - 0.01:
				return _fail(("standing at %s your body is drawn from y %.1f and the log panel owns "
						+ "the map's top %.1f: %.1fpx of you is behind it, which is Maren's zero "
						+ "player pixels") % [at, body.position.y, ceiling,
						ceiling - body.position.y])
			if body.position.y < -0.01 or body.end.y > WINDOW.y + 0.01:
				return _fail(("standing at %s your body is drawn y %.1f..%.1f and the map rect is "
						+ "0..%.1f: part of you is outside the picture") % [at, body.position.y,
						body.end.y, WINDOW.y])
			if row >= 1 and absf(body.position.y - centred) > 0.01:
				return _fail(("at %s the body is drawn from y %.1f; a centring camera draws it at "
						+ "%.1f. The north bound is binding south of row 1, so it pins the body and "
						+ "the WORLD jerks a tile per step instead")
						% [at, body.position.y, centred])
	# AND THE SOUTH CLAMP IS UNTOUCHED, which is the direction that was always safe: it pushes you
	# DOWN, away from a panel anchored to the top. Rows 59..63 clamp here (320px of a 2048px world).
	for row in range(54, 64):
		var at := Vector2(48.0, float(row))
		var origin := AssayScene.camera_origin(at, world, WINDOW, room)
		var bodies := _of(AssayScene.placements(_view({"origin": origin,
				"players": [{"at": at, "facing": "N", "moving": false}]})), "player")
		if bodies.size() != 1:
			return _fail("a body in the south band at %s drew %d sprites" % [at, bodies.size()])
		var body: Rect2 = (bodies[0] as Dictionary)["dest"]
		if body.position.y < ceiling - 0.01 or body.end.y > WINDOW.y + 0.01:
			return _fail(("the SOUTH clamp moved a body out of the picture at %s: y %.1f..%.1f "
					+ "against a ceiling of %.1f and a map %.1f tall")
					% [at, body.position.y, body.end.y, ceiling, WINDOW.y])
	return true


## NO ART, NO CLAIM. The caller reads a negative as "nobody bounds the panel" and keeps all fourteen
## lines, which is the right failure: a missing manifest must not silently shrink the log to one line.
func test_the_player_ceiling_refuses_to_answer_without_player_art() -> bool:
	if AssayScene.player_ceiling({}, WINDOW) >= 0.0:
		return _fail("player_ceiling invented a bound from an empty manifest")
	if AssayScene.player_ceiling({"ground": {"tiles": [1, 1]}}, WINDOW) >= 0.0:
		return _fail("player_ceiling bounded a panel off a manifest with no player in it")
	return true


# ---------------------------------------------------------------------------
# A SIM FACT IS NEVER DEFAULTED (ASSA-141)
# ---------------------------------------------------------------------------

## A COMPLETE VIEW WITH ONE BUILDING AND ONE PLAYER, so that dropping a single key is the only
## difference between the two halves of every test below.
func _whole_view() -> Dictionary:
	return _view({
		"ore": {Vector2i(9, 9): {"species": 1, "grade": "B", "depleted": false}},
		"players": [{"at": Vector2(5.0, 5.0), "facing": "S", "moving": false}],
		"buildings": [_smelter(Vector2i(10, 5), true), _drill(Vector2i(14, 6), 1)],
	})


## THE SAME VIEW WITH ONE FACT TAKEN OFF ONE ENTRY. Returns the view and what the loss should be
## called, so the test asserts on the name as well as on the refusal.
func _view_without(what: String, key: String) -> Dictionary:
	var view := _whole_view()
	match what:
		"view":
			view.erase(key)
		"ore tile":
			var tiles: Dictionary = (view["ore"] as Dictionary).duplicate(true)
			(tiles.values()[0] as Dictionary).erase(key)
			view["ore"] = tiles
		"building":
			var buildings: Array = (view["buildings"] as Array).duplicate(true)
			(buildings[0] as Dictionary).erase(key)
			view["buildings"] = buildings
		"player":
			var players: Array = (view["players"] as Array).duplicate(true)
			(players[0] as Dictionary).erase(key)
			view["players"] = players
		"machine part":
			var buildings: Array = (view["buildings"] as Array).duplicate(true)
			var parts: Array = (buildings[1] as Dictionary)["parts"]
			(parts[0] as Dictionary).erase(key)
			view["buildings"] = buildings
	return view


## **THE PREMISE OF EVERY TEST BELOW, AND IT IS NOT A FORMALITY.** If the whole view were already
## missing something, every "dropping X is noticed" test would pass without the drop doing anything
## -- the shape of my own ASSA-156 mistake, where a test asked the function under test what to
## expect. So: the complete view is clean, and it DRAWS the things the tests below watch disappear.
func test_the_whole_view_fixture_satisfies_the_contract_and_draws() -> bool:
	var missing := AssayScene.missing_sim_facts(_whole_view())
	if not missing.is_empty():
		return _fail("the fixture every test below starts from is itself incomplete: %s" % [missing])
	var places := AssayScene.placements(_whole_view())
	for asset in ["ground", "ore", "smelter", "player"]:
		if _of(places, asset).is_empty():
			return _fail("the complete fixture drew no `%s`, so nothing below can measure its loss"
					% asset)
	if _composites(places).is_empty():
		return _fail("the complete fixture drew no machine, so a lost part fact measures nothing")
	return true


## **EVERY SIM FACT, NOT JUST `lit`.** The item's box 2: `footprint`, `pos`, `kind`, `species` and
## the rest are read the same way `lit` was, so the rule has to be true for all of them or it is a
## patch rather than a rule. Driven off `SIM_FACTS` itself, so a fact added to the contract
## tomorrow is covered by this test the moment it is listed.
func test_every_sim_fact_is_named_when_it_does_not_arrive() -> bool:
	for what in AssayScene.SIM_FACTS:
		for key in AssayScene.SIM_FACTS[what]:
			var view := _view_without(String(what), String(key))
			var missing := AssayScene.missing_sim_facts(view)
			if missing.is_empty():
				return _fail(("dropping `%s` from a %s was not noticed at all, so the renderer "
						+ "would draw whatever its default invents") % [String(key), String(what)])
			var named := false
			for complaint in missing:
				if String(complaint).begins_with(String(what)) \
						and String(complaint).ends_with("." + String(key)):
					named = true
			if not named:
				return _fail("dropping `%s` from a %s was reported as %s, which does not name it"
						% [String(key), String(what), missing])
	return true


## **IT DRAWS NOTHING, RATHER THAN DRAWING COLD.** Box 1, and the measurement is the whole point: a
## smelter whose `lit` never arrived used to draw the `cold` row -- a picture indistinguishable from
## a fire that is genuinely out, for every smelter in the world, with every test green. The frame is
## refused instead, which is a thing somebody notices.
func test_a_building_with_no_lit_key_draws_nothing_instead_of_cold() -> bool:
	var lit := _of(AssayScene.placements(_whole_view()), "smelter")
	if lit.is_empty():
		return _fail("the complete fixture drew no smelter, so this test cannot measure one")
	var without := AssayScene.placements(_view_without("building", "lit"))
	if not _of(without, "smelter").is_empty():
		return _fail("a smelter with no `lit` fact was still drawn %d time(s): a renderer may not "
				% _of(without, "smelter").size() + "substitute a value for a sim fact")
	if not without.is_empty():
		return _fail("the frame was not refused: %d placements survived a missing sim fact"
				% without.size())
	return true


## AN EMPTY VIEW IS NOT A BROKEN ONE, and this is the line between the two. `{}` is the state before
## a snapshot lands -- `--selfcheck` and a mid-join frame are both in it -- so it must stay silent,
## while a view that claims to be a world and is missing one fact must not.
func test_an_empty_view_is_silent_and_a_half_built_one_is_not() -> bool:
	if not AssayScene.missing_sim_facts({}).is_empty():
		return _fail("an empty view was called broken: %s" % [AssayScene.missing_sim_facts({})])
	if AssayScene.placements({}).size() != 0:
		return _fail("an empty view produced placements")
	if AssayScene.missing_sim_facts({"world_tiles": Vector2i(96, 64)}).is_empty():
		return _fail("a view with one key and no world was called complete")
	return true


## **THE CONTRACT IS CHECKED AGAINST THE READS, BECAUSE A LIST IS NOT A MECHANISM.**
##
## Found by mutation, after two mutations reddened NOTHING: with `lit` quietly deleted from
## `SIM_FACTS`, and with the boundary check disabled outright, all 248 tests stayed green. The reason
## is that both failures look identical from outside -- GDScript's own invalid-key abort empties the
## frame exactly as the refusal does -- so no test could tell the rule from a crash, and the test
## that walks `SIM_FACTS` cannot see a fact that is no longer in `SIM_FACTS` to walk.
##
## So the list is measured against the thing that depends on it: every `subject["key"]` read in
## `scene_view.gd` must be a fact the contract declares. Drop `lit` from the list and line ~508 still
## reads `building["lit"]`, so this reddens. It is Limpet's CO-6 shape -- measure the call that takes
## the answer, not a second copy of the list.
func test_every_sim_fact_the_scene_reads_is_one_the_contract_declares() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/scene_view.gd")
	if source.is_empty():
		return _fail("could not read scene_view.gd, so this guard is vacuous")
	var subjects := {"view": "view", "building": "building", "player": "player", "tile": "ore tile"}
	var re := RegEx.new()
	re.compile("\\b(view|building|player|tile)\\[\"([a-z_]+)\"\\]")
	var found := 0
	for m in re.search_all(source):
		var subject := m.get_string(1)
		var key := m.get_string(2)
		var what := String(subjects[subject])
		found += 1
		if not (AssayScene.SIM_FACTS[what] as Array).has(key):
			return _fail(("`%s[\"%s\"]` is read in scene_view.gd and the contract's `%s` list does "
					+ "not declare it, so the boundary check cannot know it is required and the "
					+ "renderer reaches a key nobody promised") % [subject, key, what])
	# NON-VACUITY: zero is the passing answer for the loop above, so a regex that matches nothing
	# would pass. Eleven sim-fact reads is what the file has; the bar is low enough not to break on
	# a refactor and high enough that a broken pattern cannot slip under it.
	if found < 9:
		return _fail("only %d sim-fact reads found in scene_view.gd; this guard is reading the "
				% found + "wrong text or the pattern no longer matches the code")
	return true


## **AND NO SIM FACT COMES BACK AS A DEFAULT.** The other half: the guard above is satisfied by a
## contract that lists everything, and the defect this item is about is the `get(key, default)` FORM
## -- `get("lit", false)` is what drew every smelter in the world cold. A fact may be indexed, never
## defaulted, in this file. The manifest, the layout, the camera and `seconds` are the renderer's own
## and keep their defaults, which is why this scans for the fact NAMES rather than for `get(`.
func test_no_sim_fact_in_this_file_is_read_with_a_default() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/scene_view.gd")
	var code := ""
	for line in source.split("\n"):
		# Comments discuss `get("lit", false)` on purpose: that is the history being recorded.
		if String(line).strip_edges().begins_with("#"):
			continue
		code += String(line) + "\n"
	for what in AssayScene.SIM_FACTS:
		for key in AssayScene.SIM_FACTS[what]:
			var defaulted := '.get("%s"' % String(key)
			if code.contains(defaulted):
				# `missing_sim_facts` is the one place that must tolerate absence: it is the
				# function whose whole job is to report it, and it reads the COLLECTIONS, never a
				# fact off an entry.
				if String(key) in ["ore", "players", "buildings", "parts"]:
					continue
				return _fail(("scene_view.gd reads the sim fact `%s` as %s..., which invents a "
						+ "value for state the sim did not send (ASSA-141)") % [String(key),
						defaulted])
	return true


## **THE SUB-TILE OFFSET MUST SURVIVE TO `dest`, AND NO TEST WE OWNED COULD SEE IT FLOORED.**
##
## This is ASSA-197's lesson applied one layer up, and it is here because the Lead asked for it by
## name: `test_a_walking_bodys_own_rectangle_moves_with_it_sub_tile` catches a floor INSIDE `_place`,
## and would stay green if the floor were in the scatter loop's own line. The scatter layer exists to
## not read as a grid; quantising its props onto whole tiles turns nine rows of props back into a
## repeating texture, which is the exact criticism ASSA-115 drew for the six ground variants.
##
## IT ASSERTS ON PIXELS, NOT ON MY READING OF THE CODE. The placed rectangle must differ from the
## same prop placed on its whole tile by EXACTLY the offset `scatter_at` asked for; an `int()`,
## a `round()` or a `Vector2i` anywhere on the path collapses that difference and this goes red.
func test_scatter_offsets_are_sub_tile_and_reach_dest_unfloored() -> bool:
	var manifest := _manifest()
	if not manifest.has("scatter"):
		return _fail("the shipped manifest has no `scatter` asset, so this layer cannot draw at all")
	# IT ASKS `placements` AND NOT `_place`, AND THAT IS THE WHOLE POINT. My first version of this
	# test called `_place` with a fractional corner and asserted the rectangle moved -- which is
	# ASSA-197's property, already covered, and it stayed GREEN when I floored the scatter loop's own
	# line. An instrument that cannot fail for the reason it was written. The Lead warned about this
	# exact gap in the routing note and I built it anyway; what follows reads the drawn output.
	var view := _view({"origin": Vector2(10.0, 10.0) * AssayScene.TILE_PX})
	var origin: Vector2 = view["origin"]
	var window := AssayScene.visible_tiles(origin, view["size"], view["world_tiles"])
	var grown := Rect2i(window.position - Vector2i.ONE, window.size + Vector2i.ONE * 2)
	grown = grown.intersection(Rect2i(Vector2i.ZERO, view["world_tiles"]))

	# WHAT THE SCREEN SHOULD SHOW, and what it would show if the offset were thrown away.
	var want := {}
	var floored := {}
	var movable := 0
	for y in range(grown.position.y, grown.end.y):
		for x in range(grown.position.x, grown.end.x):
			var at := Vector2i(x, y)
			for prop in AssayScene.scatter_at(at):
				var off: Vector2 = prop[1]
				# SUB-TILE BY CONSTRUCTION: both jitter constants are peak-to-peak drawn px under a
				# tile, so an offset at or past 32 px would draw a prop on a tile that never asked.
				if absf(off.x) >= AssayScene.TILE_PX or absf(off.y) >= AssayScene.TILE_PX:
					return _fail("scatter offset %s at %s is a whole tile or more" % [off, at])
				var moved: Dictionary = AssayScene._place(manifest, "scatter", prop[0],
						Vector2(at) + off / AssayScene.TILE_PX, origin, Color.WHITE, 0.0)
				var still: Dictionary = AssayScene._place(manifest, "scatter", prop[0],
						Vector2(at), origin, Color.WHITE, 0.0)
				if moved.is_empty() or still.is_empty():
					return _fail("scatter row %s did not place at all" % String(prop[0]))
				var a := (moved["dest"] as Rect2).position
				var b := (still["dest"] as Rect2).position
				want[_at_key(a)] = true
				floored[_at_key(b)] = true
				if absf(a.x - b.x) > 0.5 or absf(a.y - b.y) > 0.5:
					movable += 1
	# THE TEETH: unless some props are drawn more than half a pixel off their tile, "unfloored" and
	# "floored" are the same picture and nothing below could tell them apart.
	if movable < 20:
		return _fail(("only %d of the scatter props in this window sit more than 0.5 px off their "
				+ "tile, so this test cannot tell a floored layer from an unfloored one") % movable)

	var drawn := _of(AssayScene.placements(view), "scatter")
	if drawn.size() < 20:
		return _fail("placements drew %d scatter props in a full window: too few to judge"
				% drawn.size())
	# ONE BUCKET, NOT TWO. An earlier version sorted misplacements into "on its bare tile" and
	# "somewhere else", which was complexity for nothing: a truncation toward zero lands on `at - 1`
	# for a negative offset, so the tidy "bare tile" case is not even the common one. Every drawn
	# prop must be exactly where its own offset puts it; anything else is the defect.
	for place in drawn:
		var dest: Rect2 = (place as Dictionary)["dest"]
		if want.has(_at_key(dest.position)):
			continue
		var bare := floored.has(_at_key(dest.position))
		return _fail(("a scatter prop is drawn at %s, which is not where its sub-tile offset puts "
				+ "it (%s). The offset is being quantised on the way to the screen, which puts the "
				+ "whole layer back on the tile grid and makes it read as a repeating texture "
				+ "rather than as scattered props (ASSA-197).") % [dest.position,
				"its bare tile" if bare else "nor on its bare tile"])
	return true


## A DRAWN POSITION AS A KEY, ROUNDED TO 0.01 px. `Vector2` is float32 and the offset makes the round
## trip `tile + px/32` then `* 32`, so the answer comes back ~1e-5 px out -- tighter than the type the
## engine draws with, and far below the whole-pixel error this is looking for.
func _at_key(at: Vector2) -> String:
	return "%.2f,%.2f" % [at.x, at.y]


## **SCATTER MAY NEVER COVER A DEPOSIT.** Ore is one of the two things in this game you can act on;
## a prop drawn over it hides the thing the whole layer is forbidden to compete with (ASSA-202 box 3).
func test_scatter_never_lands_on_an_ore_tile() -> bool:
	var ore := {}
	var tiles := 0
	for y in range(0, 20):
		for x in range(0, 20):
			var at := Vector2i(x, y)
			if not AssayScene.scatter_at(at).is_empty():
				ore[at] = {"species": 0, "grade": "C", "depleted": false, "purity": 50}
				tiles += 1
	if tiles < 10:
		return _fail("fixture put only %d deposits down: it cannot see a prop on ore" % tiles)
	var places := AssayScene.placements(_view({"ore": ore}))
	for place in _of(places, "scatter"):
		var dest: Rect2 = (place as Dictionary)["dest"]
		var tile := Vector2i((dest.position / AssayScene.TILE_PX).floor())
		if ore.has(tile):
			return _fail("a scatter prop is drawn on ore tile %s" % tile)
	return true


## **THE WINDOW IS GROWN ONE TILE, OR PROPS POP IN AT THE EDGE.** A prop is up to 42 drawn px tall
## with 9 px of jitter, so a tile just off screen still puts ink on screen. Without the grow the ink
## appears only once its own tile crosses the boundary, which is a visible pop as the camera moves.
func test_scatter_is_drawn_for_tiles_just_outside_the_window() -> bool:
	var view := _view({"origin": Vector2(20.0 * AssayScene.TILE_PX, 20.0 * AssayScene.TILE_PX)})
	var window := AssayScene.visible_tiles(view["origin"], view["size"], view["world_tiles"])
	var outside := 0
	for place in _of(AssayScene.placements(view), "scatter"):
		var dest: Rect2 = (place as Dictionary)["dest"]
		var tile := Vector2i(((dest.position + view["origin"]) / AssayScene.TILE_PX).floor())
		if not window.has_point(tile):
			outside += 1
	if outside == 0:
		return _fail(("no scatter prop comes from outside the visible window, so the one-tile grow "
				+ "is not happening and props will pop in at the edge as the camera moves"))
	return true
