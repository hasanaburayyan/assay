class_name AssayScene
extends RefCounted
## WHICH SPRITE GOES WHERE, AT 32 PX A TILE. The world view's rules, with no engine in them.
##
## ASSA-119, Maren's ruling: a camera at 32 px per tile following the player, and the shipped sheets
## finally drawn. The number is not invented -- `art/rig.py:18` says `TILE_PX = 64  # authoring size
## per tile (game shows 32 at 1x zoom)`, so every sprite in the repo has been drawn for a 32 px tile
## since the first one, and the client is the thing that never got the memo. Until now it drew the
## whole 96x64 world beside the HUD, which is a 9 px tile (`AssayHud.map_cell`) and a 7x downscale of
## a 64 px frame. ASSA-46 refused that downscale and was right to.
##
## WHY THIS FILE IS PURE, and it is the same reason `AssayHud` is. A renderer whose only proof is a
## picture is a renderer nobody in this studio can check: two engineers each spent a wake-up proving
## the client window did not exist when it did. So the DECISION -- which asset, which row, which
## frame, which rectangle, in what order -- is arithmetic here, asserted by `tests/test_scene_view.gd`
## under `--headless`, and `world_layer.gd` does nothing but hand the answers to `draw_texture_rect_
## region`. A wrong picture is then a failing test rather than a thing somebody has to notice.
##
## WHAT THIS FILE MAY NOT DO. It never decides a world fact. Which deposit covers a tile is a circle
## the sim owns (`tile_at`, "radius is a circle, not a square"), the grade a purity rounds to is the
## sim's banding, and where a player is, is `players()`. All of it arrives decided. The only thing
## chosen here is cosmetic: WHICH of two interchangeable rock drawings a tile gets, and that choice
## is a hash of the tile so it is the same every frame and on every peer.
##
## THE PLACEMENT CONVENTION IS `art/mock_scene.py`'s, DELIBERATELY, because that file is the picture
## the Game Director ruled the scale on (`shared/assay/maren-scene-at-32px-seed14247-2026-10-03.png`).
## Its `blit` puts a sprite's FOOTPRINT TOP-LEFT TILE at (tx, ty) and offsets by the manifest's
## `anchor_px`, so a sprite taller than its footprint rises ABOVE the tile it stands on -- the player
## frame is 64x128 for a 1x1 tile with anchor (0, 64), which is a body over a pair of feet. Drawing
## that any other way would make the game disagree with the only approved picture of it.

## ONE TILE ON SCREEN. The whole point of the item, and the one number not read from the manifest:
## the manifest says what a tile was DRAWN at (64), this says what it is SHOWN at.
const TILE_PX := 32.0

## THE TWO LAYERS, AND WHY THE RENDERER NEEDS TO BE TOLD WHICH IS WHICH. Ground and ore are the
## floor; the spawn pad and the bodies stand on it. The one thing drawn BETWEEN them is `foot_mark`,
## which has to sit on the floor and under the sprite it belongs to -- so the split is in the data
## rather than in `world_layer.gd` reading asset names it has no business knowing.
const FLOOR := 0
const STANDING := 1

## THE SHORTEST A PLAYED-OUT STEP MAY BE, in seconds. See `playout`.
##
## A FLOOR AND NOT A CHOICE OF RATE: the rate is measured from the bundles that arrive, because
## `sim-relay --tps N` is a flag and a constant here would draw a `--tps 20` world at half speed with
## nothing reporting it. This only stops a divide-by-zero before the second bundle has landed, and
## stops a harness that feeds ticks as fast as its loop runs from asking for an infinite rate.
const MIN_PLAYOUT_STEP := 0.01

## HOW FAR THE CAMERA MAY SIT FROM THE WORLD'S EDGE: nowhere. Clamped, so the view never shows void
## beside the world. A player walking into the north-west corner stops being centred, which is
## correct -- there is nothing up there to centre on.
##
## A world smaller than the view is CENTRED instead, because clamping has no answer there (the low
## bound would be above the high one). Worlds are 96x64 against a 28x18 view today, so this is the
## branch that only a test and a tiny world ever take; it is here because `clampf` with a reversed
## range returns the wrong edge silently.
static func camera_origin(centre_tile: Vector2, world_tiles: Vector2i, view: Vector2) -> Vector2:
	var world := Vector2(world_tiles) * TILE_PX
	# The CENTRE of the tile, not its corner, or a 28.5-tile-wide view puts the player half a tile
	# off-centre and the error looks like a rounding bug in the camera.
	var wanted := (centre_tile + Vector2(0.5, 0.5)) * TILE_PX - view * 0.5
	var at := Vector2.ZERO
	at.x = (world.x - view.x) * 0.5 if world.x <= view.x else clampf(wanted.x, 0.0, world.x - view.x)
	at.y = (world.y - view.y) * 0.5 if world.y <= view.y else clampf(wanted.y, 0.0, world.y - view.y)
	return at


## EVERY TILE THE VIEW TOUCHES, including the two partial ones at each edge: 912x600 is 28.5 by 18.75
## tiles, so a whole-tile window would leave a dark strip down one side that moves as you walk.
## Clipped to the world, so no caller ever asks the sim about a tile outside it.
static func visible_tiles(origin: Vector2, view: Vector2, world_tiles: Vector2i) -> Rect2i:
	var low := Vector2i((origin / TILE_PX).floor())
	var high := Vector2i(((origin + view) / TILE_PX).ceil())
	low = low.clamp(Vector2i.ZERO, world_tiles)
	high = high.clamp(Vector2i.ZERO, world_tiles)
	return Rect2i(low, high - low)


## WHICH TILE A POINT IN THE VIEW IS OVER. The inverse of the camera, and the reason the camera is a
## plain offset rather than a `Camera2D`: a click has to answer with the tile the player SEES, and
## that is one subtraction either way round.
static func tile_at_point(local: Vector2, origin: Vector2) -> Vector2i:
	return Vector2i(((local + origin) / TILE_PX).floor())


## WHICH WAY A STEP POINTS, as the suffix the player rows are named with. "" when it is not a step.
##
## EXACTLY THE EIGHT THE SIM PRODUCES, and that is not a coincidence I am relying on quietly:
## `sim/src/step.rs::move_players` is `pos.x += (target.x - pos.x).signum()` on both axes, so a
## walking player moves one tile per tick and the delta is always one of these eight. So a facing
## read off two positions the sim produced is exact -- there is no rounding, no nearest-of-eight, and
## nothing predicted.
static func facing_of(step: Vector2i) -> String:
	if step == Vector2i.ZERO:
		return ""
	var vertical := "N" if step.y < 0 else ("S" if step.y > 0 else "")
	var horizontal := "E" if step.x > 0 else ("W" if step.x < 0 else "")
	return vertical + horizontal


## HOW MUCH OF THE PRODUCED PATH IS DRAWN BY NOW: the playout clock, and nothing else in this file
## is arithmetic the board can feel as directly as this.
##
## THE DEFECT IT EXISTS FOR (ASSA-148, the board's own "the movement is choppy", measured by Maren).
## The screen used to keep exactly two positions -- last tick's and this tick's -- and restart the
## tween at every ARRIVAL. Bundles do not arrive evenly: on a real relay the client receives exactly
## 10.00 a second with gaps between 0.000 s and 0.254 s, i.e. in PAIRS. When two are applied between
## two drawn frames, the older of the two segments is never drawn at all and the body teleports a
## whole tile. Measured on the pinned demo seed: 11 of the walk's 25 tile-steps went undrawn.
##
## SO ARRIVAL IS NOT A CLOCK AND THIS STOPS TREATING IT AS ONE. Produced positions queue up, and the
## screen plays them out in order, one step of `step_seconds` each. `promote` is how many the queue
## owes the screen right now; `part` is how far through the one being drawn we are.
##
## IT IS STILL HISTORY AND THAT IS THE POINT -- MAREN'S ASSA-119 RULING DOES NOT BEND: a renderer may
## interpolate the DRAWN position, never state, never toward a `target`. A playout buffer can only
## ever draw LATER than the newest tick, never ahead of it, so this is the most conservative fix
## available rather than a cleverer one. Nothing here reads a target, a velocity or a direction.
##
## A SEGMENT STARTS AT THE LATER OF: WHEN THE ONE BEFORE IT ENDED, AND WHEN ITS OWN DATA ARRIVED.
## That one line is the whole of this function and I got it wrong first, in a way worth keeping
## written down because it is this item's defect at one third the size.
##
## My first rule was "start where the previous segment ended, unless we were parked longer than a
## step". It measures 0.549 and 0.768 tiles in a single frame on a real relay: when the queue runs dry
## the body parks on the segment's end position, and a bundle landing (say) 60 ms later was then
## treated as having started 60 ms AGO -- so the first frame of it drew the body 60% of the way along
## a tile it had not begun to cross. A jump, from a rule written to prevent jumps. The queue's cap was
## never reached in that run, so the mechanism I had suspected was not even involved; the probe's
## queue-depth number is what ruled it out.
##
## Taking each position's ARRIVAL TIME as the floor fixes it without a special case for being parked:
## - **Parked, then news:** `arrived == now`, so the segment starts now and the drawn position does
##   not move this frame. Continuous by construction -- the body was already standing on its first
##   position.
## - **A burst already waiting:** `arrived` is in the past, so the floor is the previous segment's
##   end and the queue drains phase-locked, each step its full length, no frame lost per step.
## - **Starved:** nothing to promote, `part` clamps at 1 and the body SITS on the newest position it
##   has been given. That is what the old code degraded to and the only honest thing to draw.
##
## `drawing` is false before the first position has ever been promoted, and then the first one is
## taken immediately: a world that has just been joined draws the player where the Welcome put them.
static func playout(seg_at: float, step_seconds: float, now: float, arrived: Array[float],
		drawing: bool) -> Dictionary:
	var step := maxf(step_seconds, MIN_PLAYOUT_STEP)
	var promote := 0
	var at := seg_at
	if not drawing and not arrived.is_empty():
		promote = 1
		at = now
	while promote < arrived.size() and now - at >= step:
		at = minf(maxf(at + step, arrived[promote]), now)
		promote += 1
	return {"promote": promote, "seg_at": at, "part": clampf((now - at) / step, 0.0, 1.0)}


## WHICH ROW OF `player.png`: the gait and the facing. South when nothing has moved yet, because a
## player who has never walked still has to be drawn and the sheet has no neutral row.
static func player_row(facing: String, moving: bool) -> String:
	var way := facing if facing != "" else "S"
	return "%s_%s" % ["walk" if moving else "idle", way]


## WHICH FRAME OF A ROW, from seconds of wall clock.
##
## WALL CLOCK AND NOT THE TICK, on Maren's ruling: `walk` is 12 fps against 10 ticks a second and
## those two must NOT be made to line up. The gait is a look; the tick is the clock. Lining them up
## would make the animation slow down with the relay, which is a renderer taking a lesson from
## something that is none of its business.
##
## THE FPS COMES OUT OF THE MANIFEST, never from here. The rule for finding it: an animation whose
## name is the row's prefix wins (`walk_SE` -> `walk`, 12 fps), and failing that, an asset with
## exactly ONE animation applies it to every row (`spawn`'s single `blink` over its one `pad` row).
## Neither is a convention I invented for this file -- they are how `rig.py` already writes the two
## animated assets -- and an asset with no animation at all is simply static.
static func frame_of(spec: Dictionary, row: String, seconds: float) -> int:
	var frames := _frames_in(spec, row)
	if frames <= 1:
		return 0
	var fps := _fps_for(spec, row)
	if fps <= 0.0:
		return 0
	return posmod(int(floor(seconds * fps)), frames)


## WHICH OF TWO INTERCHANGEABLE DRAWINGS A TILE GETS, stable forever.
##
## The one cosmetic choice in this file, and it has to be a function of the TILE and nothing else. A
## `randi()` per frame makes the ground boil; a running counter makes it crawl sideways as the camera
## moves, because the nth visible tile is a different tile after you take a step. This is a small FNV
## over the two coordinates, which also means every peer draws the same rocks -- not required by
## anything, and still better than three players looking at three different grounds.
static func variant_of(at: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	var hash := 2166136261
	for part in [at.x, at.y]:
		for byte in range(4):
			hash = (hash ^ ((part >> (byte * 8)) & 255)) * 16777619 & 0xFFFFFFFF
	return posmod(hash >> 8, count)


## WHICH DRAWING A GROUND TILE GETS, and why that is no longer `variant_of` alone.
##
## A TILE SHEET'S ROWS MAY BE A BLOCK RATHER THAN A BAG, and only the sheet knows which:
## `manifest.ground.block == [8, 8]` says its sixty-four rows are the row-major cells of ONE
## continuous 8x8-tile picture, rendered from a single Blender scene with the camera moved
## sixty-four times, so a patch crossing a cell boundary is the SAME object in both cells
## (`art/assets/ground.py`). Cells like that are not interchangeable. Hash-picking them
## would cut every patch that crosses a boundary and come out WORSE than the six
## independent variants that shipped -- the ones QA could point at (ASSA-115 box 2).
##
## So a block is placed BY POSITION, cell (x mod w, y mod h) at tile (x, y). Inside a block
## there is no tile lattice to find, because there is no join; what repeats is the block, on
## a 256 px period at 32 px/tile instead of a 32 px one. `posmod` and not `%` because a
## tile coordinate goes negative and a negative cell must continue the picture, not snap to
## row 0.
##
## WITHOUT `block` NOTHING CHANGES: interchangeable rows, hash-picked, which is still right
## for `ore` and for any later sheet of loose variants. A block bigger than the rows it has
## falls back the same way rather than drawing nothing: a mismatched manifest is a build
## error, and it may not take the whole floor down with it.
static func ground_row(manifest: Dictionary, at: Vector2i) -> String:
	var rows := _rows_in(manifest, "ground")
	var block: Array = ((manifest.get("ground", {}) as Dictionary).get("block", []) as Array)
	if block.size() == 2:
		var w := int(block[0])
		var h := int(block[1])
		if w > 0 and h > 0 and w * h <= rows:
			return "v%d" % (posmod(at.y, h) * w + posmod(at.x, w))
	return "v%d" % variant_of(at, rows)


## WHICH ROW OF `ore.png` A TILE OF A DEPOSIT GETS.
##
## THE GRADE PICKS THE ROW AND THE SPECIES PICKS THE TINT (`art/mock_scene.py`, Maren ASSA-19/20), so
## nothing here maps a number to a word: `grade` arrives as the sim's own letter. A depleted patch has
## its own drawing and keeps its tint -- an empty rock you can still see is the sim's state, since
## `sim` keeps a spent deposit so its id stays stable.
##
## EVERY TILE INSIDE THE CIRCLE IS THE SAME TILE: no rim variant, no sparser edge. `amount` is one
## number for the WHOLE patch, so a thinner border would be a visible mark for a difference the game
## does not have, and the hard edge is exactly where mining and placing stop working.
##
## HOW MANY ARRANGEMENTS THERE ARE IS THE SHEET'S ANSWER, NOT A LITERAL HERE. This read 2 until
## ASSA-115 rendered v2/v3, and a hardcoded count does not fail when the art grows -- it silently
## ships the new rows to nobody, which is the same shape as the ground that was rendered for a
## client that never opened it. The ground above already counts its own rows; ore could not reuse
## `_rows_in` only because its rows are grade-prefixed.
static func ore_row(grade: String, depleted: bool, at: Vector2i, manifest: Dictionary) -> String:
	if depleted:
		return "depleted_full"
	var letter := grade.to_upper()
	return "%s_full_v%d" % [letter, variant_of(at, _ore_variants(manifest, letter))]


## THE ROW OF `asset` THAT IS LIGHT FALLING ON `body`, or "" when the sheet has none.
##
## LIGHT IS NOT MATERIAL (Maren, ASSA-137). The tint above is a per-channel MULTIPLY, which is the
## right answer for a wall -- the wall is made of the species -- and has no bottom for a pixel that
## stands for emitted light: a multiply can only subtract, so the brightest pixel of a burning fire
## measured BELOW the ground's median luminance in three of the six species, and the one the demo
## plants cleared it by 11.7. No emission strength in Blender can move that number.
##
## So a sheet may carry a row flagged `light`, which says what it sits `over`. The caller draws
## `over` with the species tint and this row on top of it at `Color.WHITE`. Both fields come out of
## the manifest rather than out of a name here, for `ore_row`'s reason one screen up: a client that
## knows the word "fire" ships the next light row to nobody.
static func light_row(manifest: Dictionary, asset: String, body: String) -> String:
	var rows: Array = ((manifest.get(asset, {}) as Dictionary).get("rows", []) as Array)
	for entry in rows:
		var row: Dictionary = entry
		if bool(row.get("light", false)) and String(row.get("over", "")) == body:
			return String(row.get("name", ""))
	return ""


static func _ore_variants(manifest: Dictionary, letter: String) -> int:
	var rows: Array = ((manifest.get("ore", {}) as Dictionary).get("rows", []) as Array)
	var n := 0
	for row in rows:
		if String((row as Dictionary).get("name", "")).begins_with("%s_full_v" % letter):
			n += 1
	return maxi(n, 1)


## EVERYTHING TO DRAW, IN THE ORDER TO DRAW IT.
##
## `view` is the whole question, so that this function has no way to ask anything else:
##   world_tiles  Vector2i    the world's size, from the sim
##   origin       Vector2     the camera, from `camera_origin`
##   size         Vector2     the view's pixels
##   spawn        Vector2i    the sim's one spawn tile
##   ore          Dictionary  Vector2i -> {species, grade, depleted}, from `tile_at` per tile
##   players      Array       [{at: Vector2 (tiles, fractional), facing, moving, mine}]
##   buildings    Array       `AssaySim.buildings()` as it comes: {kind, pos, footprint, lit, ...}
##   manifest     Dictionary  `assets/sprites/manifest.json`, parsed
##   seconds      float       wall clock, for the gaits
##
## Each placement is {asset, row, frame, src (sheet px), dest (view px), tint}.
##
## ORDER IS `mock_scene.py`'s: ground, then ore, then everything that stands on it sorted by its
## BOTTOM EDGE, so the nearer thing wins. Ore after ground and before bodies; a player south of the
## spawn pad stands in front of it and one north of it stands behind.
static func placements(view: Dictionary) -> Array[Dictionary]:
	var manifest: Dictionary = view.get("manifest", {})
	var out: Array[Dictionary] = []
	if manifest.is_empty():
		return out
	var world: Vector2i = view.get("world_tiles", Vector2i.ZERO)
	var origin: Vector2 = view.get("origin", Vector2.ZERO)
	var size: Vector2 = view.get("size", Vector2.ZERO)
	var seconds := float(view.get("seconds", 0.0))
	var window := visible_tiles(origin, size, world)
	var clip := Rect2(Vector2.ZERO, size)

	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			var at := Vector2i(x, y)
			var place := _place(manifest, "ground", ground_row(manifest, at), at, origin,
					Color.WHITE, seconds)
			if not place.is_empty():
				place["layer"] = FLOOR
				out.append(place)

	var ore: Dictionary = view.get("ore", {})
	for key in ore:
		var at: Vector2i = key
		var tile: Dictionary = ore[key]
		var row := ore_row(String(tile.get("grade", "C")), bool(tile.get("depleted", false)), at,
				manifest)
		var place := _place(manifest, "ore", row, at, origin,
				AssayHud.species_tint(int(tile.get("species", 0))), seconds)
		if not place.is_empty():
			place["layer"] = FLOOR
			out.append(place)

	# THE SPAWN PAD IS FLOOR, AND THAT IS A DEPARTURE FROM `mock_scene.py` WITH A MEASUREMENT BEHIND
	# IT. That file sorts the pad in with the bodies by bottom edge, which is right for anything you
	# stand BESIDE -- and the first shot of this view showed what it does to the thing you stand ON:
	# the pad's footprint ends one row south of the player's, so a player standing on spawn sorted
	# BEHIND it and vanished completely. On seed 14247 that is the whole of your first second in the
	# game. Nothing in `mock_scene.py` was wrong; it simply never put a player on the pad.
	var pad := _standing(manifest, "spawn", "pad", Vector2(view.get("spawn", Vector2i.ZERO)),
			Color.WHITE, true)
	if not pad.is_empty():
		var place := _place(manifest, "spawn", "pad", pad["tile"], origin, pad["tint"], seconds)
		if not place.is_empty():
			place["layer"] = FLOOR
			out.append(place)

	# WHAT STANDS ON THE GROUND, sorted by bottom edge, so the nearer body wins.
	var standing: Array[Dictionary] = []

	# WHAT THE PLAYER HAS BUILT. Until now the one machine in the demo was invisible: the smelter
	# that refines everything stood three tiles from you at (59, 61) for 435 ticks of the pinned
	# seed's play and nothing was drawn there (Maren, ASSA-119 box 11).
	#
	# `pos` IS THE TOP-LEFT OF THE FOOTPRINT, never a centre -- `Building::pos`'s own meaning, and
	# the thing `every_building_is_listed_with_the_footprint_the_sim_gave_it` pins in Rust. So no
	# `centred` here: the spawn pad is centred because the sim has ONE spawn tile and the art is
	# 3x3, and a building has no such disagreement.
	#
	# THE SORT KEY IS THE SIM'S FOOTPRINT, NOT THE SHEET'S `tiles`. They agree today (2x2 and
	# 2x2) and the test says so out loud, but occupancy is sim state and a sprite may overhang its
	# tile (ASSA-30/38) -- so if they ever part, what the thing COVERS decides what stands in
	# front of it, and the drawing can overhang as it likes.
	#
	# A KIND WITH NO SHEET DRAWS NOTHING, and for every building but a machine that is still the
	# honest answer: `_place` returns empty for an asset the manifest does not have, so this needs
	# no list of what is drawable.
	#
	# A MACHINE HAS NO SHEET AND IS DRAWN ANYWAY, FROM ITS PARTS (ASSA-138). It is the one building
	# the pipeline cannot draw as a frame, because a machine is a DESIGN the player invented --
	# "parts stacked by `part_layout.stack`" -- and there is no single picture of a thing nobody
	# authored. `_composite_place` works out its rectangle exactly as `_place` works out a sprite's;
	# what goes INSIDE that rectangle is `AssayAssembly.image_of`, and the pixels are the renderer's
	# business alone. `parts` is non-empty for a machine and empty for a smelter, which is the sim's
	# own answer to "is this an assembly" rather than a kind name matched here.
	for entry in view.get("buildings", []):
		var building: Dictionary = entry
		var foot: Vector2i = building.get("footprint", Vector2i.ONE)
		var at: Vector2i = building.get("pos", Vector2i.ZERO)
		var parts: Array = building.get("parts", [])
		if not parts.is_empty():
			var machine := _composite_place(manifest, parts, at, origin, view.get("layout", {}))
			if not machine.is_empty():
				machine["bottom"] = float(at.y) + float(foot.y)
				standing.append(machine)
			continue
		var kind := String(building.get("kind", ""))
		standing.append({
			"asset": kind,
			# THE BODY IS THE ONLY THING THE SPECIES TINT TOUCHES (ASSA-137). This read
			# `"lit" if lit else "cold"` -- one sprite for both states, both multiplied by the
			# species -- and that put a fire in a channel the species owns. The lit state is now
			# a SECOND placement below, so the row drawn here is the same whether it burns or not.
			"row": "body",
			"tile": at,
			# THE SPECIES TINT THE ITEM WORE IN YOUR PACK (Maren's ruling 2 on ASSA-131): "the thing
			# you placed and the thing standing there are one object and must read as one". I had
			# this as `Color.WHITE` and was wrong -- the sheets are authored species-neutral on
			# light rock precisely so `modulate` is what makes a thing look like its material
			# (ASSA-19/20), so leaving it white is not neutrality, it is every smelter in the world
			# looking like the same material. `tint_for` is the pack's own function, called here
			# rather than copied, so the two surfaces cannot drift apart.
			"tint": AssaySprites.tint_for(building),
			"bottom": float(at.y) + float(foot.y),
		})
		# THE FIRE, UNTINTED AND ON TOP. `light_row` finds it in the manifest, so a sheet without
		# one draws nothing extra and this needs no list of what can burn.
		#
		# `above` EXISTS BECAUSE `sort_custom` IS NOT STABLE (Maren's hazard on ASSA-137). These two
		# placements share a bottom edge exactly, and a sort that is free to swap equal elements is
		# free to draw the body over its own fire -- intermittently, on some array lengths and not
		# others, which is the worst kind of wrong picture to be handed. It is a second sort key and
		# not a hope: everything else leaves it 0.
		#
		# WHAT IT DOES NOT FIX, said out loud: it is a key on the whole standing list, so a PLAYER
		# whose bottom edge is exactly a lit smelter's now sorts under that smelter's fire. Equal
		# bottoms were already arbitrary there and this makes them at least deterministic; a wall
		# over its own fire is the worse of the two and the one with a cause.
		if bool(building.get("lit", false)):
			var light := light_row(manifest, kind, "body")
			if light != "":
				standing.append({
					"asset": kind, "row": light, "tile": at, "tint": Color.WHITE,
					"bottom": float(at.y) + float(foot.y), "above": 1,
				})

	for entry in view.get("players", []):
		var player: Dictionary = entry
		var row := player_row(String(player.get("facing", "")), bool(player.get("moving", false)))
		standing.append(_standing(manifest, "player", row, player.get("at", Vector2.ZERO),
				Color.WHITE, false))
	standing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ab := float(a.get("bottom", 0.0))
		var bb := float(b.get("bottom", 0.0))
		if ab != bb:
			return ab < bb
		return int(a.get("above", 0)) < int(b.get("above", 0)))
	for entry in standing:
		if entry.is_empty():
			continue
		# A COMPOSITE ARRIVES FINISHED, because there is no sheet to look a row up in: its rectangle
		# was settled by `_composite_place` before the sort, and the sort is the only reason it waited
		# in `standing` at all. `bottom` is dropped here so every placement handed to the renderer has
		# the same keys whatever made it.
		if bool(entry.get("composite", false)):
			entry.erase("bottom")
			entry["layer"] = STANDING
			out.append(entry)
			continue
		var place := _place(manifest, String(entry["asset"]), String(entry["row"]),
				entry["tile"], origin, entry["tint"], seconds)
		if not place.is_empty():
			place["layer"] = STANDING
			out.append(place)

	# CULLED LAST, ON THE RECTANGLE THAT WILL ACTUALLY BE DRAWN. A player one tile above the window
	# still has 32 px of body inside it, and a 3x3 pad reaches further; culling by TILE would clip
	# the top off both. The view clips too (`clip_contents`), so this is about not handing the
	# renderer work it cannot see, not about correctness of the edge.
	var seen: Array[Dictionary] = []
	for place in out:
		if clip.intersects(place["dest"]):
			seen.append(place)
	return seen


## THE MARK UNDER YOUR OWN FEET, as a rectangle to draw an ellipse in.
##
## ASSA-119 box 5, Maren's finding 1: "whatever else is on screen, the player reads first", measured
## off the real shot where you were 0.065% of the view and smaller than all eleven deposits. The
## camera answers most of that -- you are at the centre of the view by construction now -- but the
## camera does not tell two players apart, and a 32 px sprite among 32 px rocks is still a sprite
## among rocks. So the one mark on the scene that is not art: an ellipse at your feet, in the colour
## the schematic has always used for "yours".
##
## A FLAT ELLIPSE AND NOT A RING ROUND THE BODY, because the body is 64 px of a 32 px tile and a ring
## round it would overlap the two tiles behind. This sits in the footprint, where the sprite's own
## contact shadow already is.
static func foot_mark(at: Vector2, origin: Vector2) -> Rect2:
	var centre := (at + Vector2(0.5, 0.9)) * TILE_PX - origin
	return Rect2(centre - Vector2(TILE_PX * 0.42, TILE_PX * 0.18),
			Vector2(TILE_PX * 0.84, TILE_PX * 0.36))


## A MACHINE'S RECTANGLE, or {} when its parts have no art or the contract will not read.
##
## **FOOTPRINT IS A RULES FACT, NOT A DRAWING SIZE** (Maren's ruling, ASSA-138). `building.rs:282`
## gives a machine a 1x1 footprint and says why in its own words -- "One tile, so a drill sits on the
## deposit tile it works" -- which answers WHICH DEPOSIT IT WORKS and nothing about how big it looks.
## So this scales the composite by exactly what `_place` scales a part sprite by, and lets it be
## taller and wider than the tile it stands on, which is the standing rule for every sprite here
## (ASSA-30/38, and the smelter is already 2x2 of art reaching above its tile).
##
## WHAT SQUEEZING IT INTO 32x32 WOULD HAVE DONE, measured by Maren before anything was built: the
## composite's canvas GROWS with each repeat, so a fixed box scales every part down by a further 16%
## -- 437 opaque px at one hopper falling to 377 at four. Hopper count IS capacity, so the one
## quantity the drawing carries would have moved backwards, and all four would read as one dark lump.
## That defect is not avoided by care here; it is avoided by the scale being a constant.
##
## THE SCALE IS THE FRAME'S OWN, DERIVED, NEVER A LITERAL. `_place` reads authored-pixels-per-tile out
## of the manifest (`frame_px / tiles`) so a re-render at a different authoring size still draws a
## 32 px tile; a composite drawn at a scale of its own would be the one sprite in the world that
## changed size when the pipeline did.
##
## AND THE ANCHOR IS THE FRAME'S. `canvas_of().position` is where the box starts relative to the
## frame part's top-left -- zero or negative, since repeats climb north-east -- so subtracting it puts
## the FRAME exactly where a lone frame sprite would have gone, on the footprint tile, and the
## repeats hang above and east of it. Anchoring on the box instead would walk the whole machine south
## as you added hoppers, which is the same defect as the squeeze wearing different clothes.
static func _composite_place(manifest: Dictionary, parts: Array, tile: Vector2i, origin: Vector2,
		layout: Dictionary) -> Dictionary:
	if parts.is_empty() or layout.is_empty():
		return {}
	var offset: Vector2i = layout.get("repeat_offset_px", Vector2i.ZERO)
	# THE FRAME'S SHEET DECIDES THE GEOMETRY, and the frame is `Assembly::parts()`' first entry --
	# the sim's order, which `BuildingFacts::parts` preserves. `image_of` sizes every part to the
	# first one's frame as well, so this reads the same sheet that file reads.
	# ASSEMBLY_SHEET_OF, NOT SHEET_OF (ASSA-121): the geometry below is the assembly frame's --
	# `frame_px` 128x102, `tiles` [2,1], `anchor_px` -- and `image_of` composites that same sheet. The
	# pack row's items frame is 64x96 at `tiles` [1,1], so reading it here would scale every machine by
	# the wrong factor and anchor it off its footprint tile.
	var spec: Dictionary = manifest.get(AssaySprites.ASSEMBLY_SHEET_OF.get(
			String((parts[0] as Dictionary).get("kind", "")).to_lower(), ""), {})
	var frame_px: Array = spec.get("frame_px", [])
	var tiles: Array = spec.get("tiles", [])
	if frame_px.size() != 2 or tiles.size() != 2 or float(tiles[0]) <= 0.0:
		return {}
	var authored := float(frame_px[0]) / float(tiles[0])
	if authored <= 0.0:
		return {}
	var scale := TILE_PX / authored
	var box := AssayAssembly.canvas_of(parts,
			Vector2i(int(frame_px[0]), int(frame_px[1])), offset)
	if box.size.x <= 0 or box.size.y <= 0:
		return {}
	var anchor: Array = spec.get("anchor_px", [0, 0])
	var at := Vector2.ZERO
	if anchor.size() == 2:
		at = Vector2(float(anchor[0]), float(anchor[1]))
	return {
		"asset": "",
		"composite": true,
		# THE PARTS GO WITH THE RECTANGLE, so the renderer has no reason to go back to the sim for
		# them -- and `key` is what it caches the finished image under. An assembly changes when a
		# player builds or places, never per tick, so this is composited once per design.
		"parts": parts,
		"key": AssayAssembly.key_of(parts),
		"dest": Rect2(Vector2(tile) * TILE_PX - (at - Vector2(box.position)) * scale - origin,
				Vector2(box.size) * scale),
		# WHITE, AND THAT IS NOT A MISSING TINT. Every part is tinted by its OWN species inside
		# `image_of`, because a drill can be built from two materials and one `modulate` over the
		# finished image would repaint the whole machine in the frame's.
		"tint": Color.WHITE,
	}


## ONE SPRITE'S RECTANGLES, or {} when the manifest has no such asset or row.
##
## {} RATHER THAN A GUESS, the same answer `AssaySprites.icon_for` gives: a row that has been renamed
## makes its sprite disappear, and nothing draws the wrong frame. The scale is DERIVED -- authored
## pixels per tile come out of the manifest (`frame_px / tiles`) -- so a re-render at a different
## authoring size still draws a 32 px tile instead of silently changing the zoom.
static func _place(manifest: Dictionary, asset: String, row: String, tile: Vector2i,
		origin: Vector2, tint: Color, seconds: float) -> Dictionary:
	if not manifest.has(asset):
		return {}
	var spec: Dictionary = manifest[asset]
	var index := _row_index(spec, row)
	if index < 0:
		return {}
	var frame_px: Array = spec.get("frame_px", [])
	var tiles: Array = spec.get("tiles", [])
	if frame_px.size() != 2 or tiles.size() != 2 or float(tiles[0]) <= 0.0:
		return {}
	var authored := float(frame_px[0]) / float(tiles[0])
	if authored <= 0.0:
		return {}
	var scale := TILE_PX / authored
	var anchor: Array = spec.get("anchor_px", [0, 0])
	var offset := Vector2.ZERO
	if anchor.size() == 2:
		offset = Vector2(float(anchor[0]), float(anchor[1])) * scale
	var frame := frame_of(spec, row, seconds)
	var size := Vector2(float(frame_px[0]), float(frame_px[1]))
	return {
		"asset": asset,
		"row": row,
		"frame": frame,
		"src": Rect2(Vector2(float(frame) * size.x, float(index) * size.y), size),
		"dest": Rect2(Vector2(tile) * TILE_PX - offset - origin, size * scale),
		"tint": tint,
	}


## ONE THING THAT STANDS ON THE GROUND, with the sort key it is drawn in order of.
##
## `bottom` is the tile row its feet are on plus its footprint's height, which is `mock_scene.py`'s
## `e[3] + tiles[1]`. Fractional for a player, because a player half a tile north of another is
## behind them and the sprites overlap by 32 px.
##
## `centred` is for the spawn PAD, and it is the one place art and sim disagree about a size. The sim
## has ONE spawn tile (`World::spawn_tile`, the centre tile of the spawn chunk); the pad is drawn 3x3.
## So the art is centred on the sim's tile rather than the sim's tile being the pad's corner, which
## keeps `is_spawn` and the picture talking about the same place.
static func _standing(manifest: Dictionary, asset: String, row: String, at: Vector2,
		tint: Color, centred: bool) -> Dictionary:
	if not manifest.has(asset):
		return {}
	var tiles: Array = (manifest[asset] as Dictionary).get("tiles", [1, 1])
	if tiles.size() != 2:
		return {}
	var span := Vector2(float(tiles[0]), float(tiles[1]))
	var corner := at - ((span - Vector2.ONE) * 0.5).floor() if centred else at
	return {
		"asset": asset,
		"row": row,
		"tile": Vector2i(corner.floor()),
		"tint": tint,
		"bottom": at.y + span.y,
	}


static func _row_index(spec: Dictionary, row: String) -> int:
	var rows: Array = spec.get("rows", [])
	for i in range(rows.size()):
		if String((rows[i] as Dictionary).get("name", "")) == row:
			return i
	return -1


static func _rows_in(manifest: Dictionary, asset: String) -> int:
	if not manifest.has(asset):
		return 0
	return ((manifest[asset] as Dictionary).get("rows", []) as Array).size()


static func _frames_in(spec: Dictionary, row: String) -> int:
	var index := _row_index(spec, row)
	if index < 0:
		return 0
	return int(((spec.get("rows", []) as Array)[index] as Dictionary).get("frames", 1))


static func _fps_for(spec: Dictionary, row: String) -> float:
	var animations: Dictionary = spec.get("animations", {})
	if animations.is_empty():
		return 0.0
	for name in animations:
		if row.begins_with(String(name)):
			return float((animations[name] as Dictionary).get("fps", 0))
	if animations.size() == 1:
		return float((animations.values()[0] as Dictionary).get("fps", 0))
	return 0.0
