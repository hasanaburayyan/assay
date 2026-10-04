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
static func ore_row(grade: String, depleted: bool, at: Vector2i) -> String:
	if depleted:
		return "depleted_full"
	return "%s_full_v%d" % [grade.to_upper(), variant_of(at, 2)]


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
			var place := _place(manifest, "ground", "v%d" % variant_of(at, _rows_in(manifest,
					"ground")), at, origin, Color.WHITE, seconds)
			if not place.is_empty():
				place["layer"] = FLOOR
				out.append(place)

	var ore: Dictionary = view.get("ore", {})
	for key in ore:
		var at: Vector2i = key
		var tile: Dictionary = ore[key]
		var row := ore_row(String(tile.get("grade", "C")), bool(tile.get("depleted", false)), at)
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
	# A KIND WITH NO SHEET DRAWS NOTHING, which is today's honest answer for `machine`: one is
	# "parts stacked by `part_layout.stack`" and no single frame exists for it. `_place` returns
	# empty for an asset the manifest does not have, so this needs no list of what is drawable.
	for entry in view.get("buildings", []):
		var building: Dictionary = entry
		var foot: Vector2i = building.get("footprint", Vector2i.ONE)
		var at: Vector2i = building.get("pos", Vector2i.ZERO)
		standing.append({
			"asset": String(building.get("kind", "")),
			"row": "lit" if bool(building.get("lit", false)) else "cold",
			"tile": at,
			# NO SPECIES TINT, unlike ore. A deposit is a rock of one material and the tint is how
			# you tell two patches apart; a smelter is a built thing whose sprite Cove authored
			# whole, and multiplying it by a species colour would be this file deciding what it
			# looks like. If the walls should carry their material, that is an art ruling.
			"tint": Color.WHITE,
			"bottom": float(at.y) + float(foot.y),
		})

	for entry in view.get("players", []):
		var player: Dictionary = entry
		var row := player_row(String(player.get("facing", "")), bool(player.get("moving", false)))
		standing.append(_standing(manifest, "player", row, player.get("at", Vector2.ZERO),
				Color.WHITE, false))
	standing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("bottom", 0.0)) < float(b.get("bottom", 0.0)))
	for entry in standing:
		if entry.is_empty():
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
