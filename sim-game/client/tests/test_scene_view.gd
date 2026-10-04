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
		screen._refresh_world()
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
