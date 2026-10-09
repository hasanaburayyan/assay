class_name AssayWorldLayer
extends Control
## THE SCENE, DRAWN. Every decision in it was made by `AssayScene`; this file owns the engine calls
## and nothing else.
##
## THAT SPLIT IS THE POINT, not tidiness. `window_shot.gd` can photograph this, but a photograph
## cannot tell you a sprite is one row off or half a tile high -- it looks plausible and nobody
## notices for a week. So everything checkable is arithmetic in `AssayScene`, asserted headless by
## `tests/test_scene_view.gd`, and what is left here is `draw_texture_rect_region` in a loop. There
## is no judgement in this file to get wrong.
##
## A `Control` WITH `clip_contents`, AND THAT IS WHY IT IS A CONTROL. The world is 912x672 inside a
## 1280x720 window and 912 is 28.5 tiles, so the camera's edge tiles are always half outside the
## view. Without a clip they would paint over the HUD column beside them. A `Camera2D` would have
## wanted a `SubViewport` to be confined to a panel, which is a second input path for clicks to be
## wrong in; a clipped `Control` with an offset is the same picture and one subtraction.

## The sheets Godot has decoded, by asset name. `load()` caches internally, but it still resolves a
## path and takes a lock every call, and this runs once per placement per frame -- 580 of them.
var _textures := {}

## COMPOSITED MACHINES, by `AssayAssembly.key_of` -- kind, species and grade of every part, which is
## everything that chooses a sheet, a row or a tint. A machine has no sheet to blit from, so its
## picture is built pixel by pixel in GDScript (`assembly.gd` explains why that cannot be a canvas
## call: rule 2 is an alpha-MAX composite and Godot has no MAX blend mode). At 170x120 authoring
## pixels that is ~20k `get_pixel`/`set_pixel` pairs per part, which is affordable ONCE and ruinous
## at 60 fps -- so the cache is not an optimisation, it is the reason this is drawable at all.
##
## KEYED BY THE DESIGN AND NOT BY THE BUILDING, deliberately: four identical drills on a map are one
## picture, and a drill rebuilt from the same parts after being picked up is the same picture again.
## A null in here is a remembered REFUSAL (a part with no art), so a machine we cannot draw is not
## re-attempted every frame.
var _machines := {}

## WHAT TO DRAW. Set by `main.gd` every refresh (and every frame while anyone is walking); the exact
## dictionary `AssayScene.placements` documents. Empty means there is no world yet, which is a normal
## state: before the first `Welcome` there is nothing to draw and the view is the map's background.
var view := {}

## WHERE YOU ARE, in fractional tiles, or null when you have no player yet. Separate from `view` so
## `AssayScene.placements` cannot be tempted to care which body is yours -- "yours" is a fact about
## the client, not about the world.
var me: Variant = null

## **THE TILE YOU CLICKED, OR null** (ASSA-215). A `Vector2i`, set by `main.gd` from the player's own
## click and cleared by `AssayScene.walk_echo` the frame the walk arrives, is refused or is dropped.
##
## BESIDE `view` FOR `me`'s REASON, and it is the stronger case of the two: a destination is not a
## fact about the world at all -- the sim has not heard of it yet when it is first drawn -- so a
## `view` key for it would put a client's unanswered input in the dictionary `AssayScene.placements`
## reads as sim state. `placements` cannot see this, which is the ASSA-119 guarantee: nothing here
## can move a body.
var destination: Variant = null

## **WHAT THE BUTTONS ACT ON, OR null** (ASSA-276 move 4). A **`Rect2i` IN TILES** -- `position` is
## the subject's top-left tile and `size` its span -- set by `main.gd` from `_target` whenever a tile
## is actually targeted.
##
## **IT WAS A `Vector2i` UNTIL ASSA-348 AND THE SPAN IS NOT DECORATION.** Three of the sim's five
## verbs (`Take`, `Pickup`, `Insert`) take a `BuildingId`, and a smelter covers four tiles, so the
## mark understated its own subject on every one of them. `main.gd` crosses `BuildingFacts.footprint`
## to fill this in; the span is never inferred here from a sprite or a kind, because this node draws
## and decides nothing (`_blit`'s rule, one screen down).
##
## SEPARATE FROM `destination` BECAUSE THEY ARE DIFFERENT FACTS AND CAN BE THE SAME TILE: one is
## "where I asked to walk", alive for a quarter of a second; this is "what the buttons will do
## something to", and it stays until the player picks another. A single field would make the mark
## flicker to the other meaning every time somebody walked.
var selection: Variant = null

## **THE RECTANGLES THIS FUNCTION ACTUALLY BLITTED LAST FRAME, for the probes only** (ASSA-197).
## Map pixels. Nothing here reads them and no decision depends on them; `_draw` writes them on its
## way past.
##
## WHY A PROBE MUST NOT RECOMPUTE THEM INSTEAD. `AssayScene.placements` is pure, so a probe can call
## it beside the renderer and get an answer -- and then it is measuring its own copy of the renderer
## on its own copy of the view, which is exactly the mistake that let a whole-tile saw-tooth live in
## this file for a fortnight: every assertion we owned read `view["players"][i]["at"]`, the lerp's
## INPUT to the thing that was broken (Maren, ASSA-200). It also costs a second pass over ~580
## placements inside the frame whose length the probe is trying to measure.
##
## **EMPTY UNLESS THERE IS EXACTLY ONE BODY ON THE SCENE**, and that is a refusal rather than a
## guess: a view's player entries carry no `id`, so with two players there is no honest way to say
## from here which rectangle is yours. The probe reads an empty rect as a blind frame and says so.
var drawn_body := Rect2()
var drawn_foot := Rect2()

## **THE TILE THE DESTINATION BRACKETS WERE ACTUALLY PAINTED ON LAST FRAME, for the probes only**
## (ASSA-215), in map pixels, and `Rect2()` when nothing was painted. Written on the way past like
## the two above, and read by nothing in the client.
##
## IT IS WHAT MAKES "THE MARK WAS ON SCREEN IN THAT FRAME" A MEASUREMENT. A probe can ask `main.gd`
## what it thinks the destination is, and then it is reading the state rather than the picture --
## which is exactly how a mark that was computed every frame and drawn in none of them would pass.
## This is set inside `_draw`, after the `draw_rect` calls, so it cannot be true of a frame the
## brackets were not painted in.
var drawn_destination := Rect2()

## **THE TILE THE SELECTION OUTLINE WAS ACTUALLY PAINTED ON LAST FRAME, for the probes only**
## (ASSA-276 move 4), in map pixels, `Rect2()` when nothing was painted. Same contract and same
## reason as `drawn_destination`: set inside `_draw` after the `draw_rect` calls, so it cannot be
## true of a frame the outline was not painted in.
var drawn_selection := Rect2()


func _init() -> void:
	clip_contents = true
	# THE HUD OWNS THE MOUSE, STILL. `main.gd::_unhandled_input` has handled clicks on the map since
	# ASSA-7 and it keeps that job: this node going first would mean two files deciding what a click
	# on a tile means. IGNORE, so the event passes straight through to the node that already knows.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), AssayHud.MAP_BG, true)
	drawn_body = Rect2()
	drawn_foot = Rect2()
	drawn_destination = Rect2()
	drawn_selection = Rect2()
	if view.is_empty():
		return
	var all := AssayScene.placements(view)
	var bodies := 0
	for place in all:
		if String(place.get("asset", "")) == "player":
			bodies += 1
			drawn_body = place["dest"]
	if bodies != 1:
		drawn_body = Rect2()
	for place in all:
		if int(place.get("layer", AssayScene.FLOOR)) == AssayScene.FLOOR:
			_blit(place)
	# WHERE YOU ASKED TO GO (ASSA-215), ON THE FLOOR AND UNDER EVERYTHING THAT STANDS ON IT. Above
	# the ground and the ore because the tile it marks is one of those two; below the bodies and the
	# buildings because it marks the GROUND there, so a person or a machine standing on that tile is
	# in front of their own floor, the way the spawn pad already is.
	#
	# `MINE` AT A FOURTH WEIGHT AND NO NEW LITERAL (Maren's box 6): the schematic's walk line is
	# `MINE` at 0.35, the foot mark below is 0.55, the player mark is solid. This is the brightest
	# of the three because it is the only one that answers an input, and it is on screen for a
	# quarter of a second.
	if destination != null:
		var tile: Vector2i = destination
		var origin: Vector2 = view.get("origin", Vector2.ZERO)
		# EVERY KEYLINE FIRST, THEN EVERY BAR. The two bars of one corner overlap, so a per-bar
		# keyline painted immediately before its own bar would lay MAP_BG over the yellow of the bar
		# beside it and bite a notch out of the corner.
		for rim in AssayScene.destination_keyline(tile, origin):
			draw_rect(rim, AssayHud.MAP_BG, true)
		for bar in AssayScene.destination_mark(tile, origin):
			draw_rect(bar, AssayHud.MINE, true)
		drawn_destination = Rect2(Vector2(tile) * AssayScene.TILE_PX - origin,
				Vector2(AssayScene.TILE_PX, AssayScene.TILE_PX))
	if me != null:
		# THE ONE MARK ON THIS VIEW THAT IS NOT ART (ASSA-119 box 5). Drawn in the colour the
		# schematic has used for "yours" since ASSA-7 rather than in a new one, because Maren's
		# ruling-3 correction is that this client already holds 21 colour literals nobody chose as a
		# set, and a 22nd for the same meaning would be the same mistake again.
		drawn_foot = AssayScene.foot_mark(me, view.get("origin", Vector2.ZERO))
		draw_rect(drawn_foot,
				Color(AssayHud.MINE.r, AssayHud.MINE.g, AssayHud.MINE.b, 0.55), true)
	for place in all:
		if int(place.get("layer", AssayScene.FLOOR)) == AssayScene.STANDING:
			_blit(place)
	# **WHAT THE BUTTONS ACT ON (ASSA-276 move 4), AND IT IS DRAWN LAST, WHICH IS THE OPPOSITE OF
	# THE DESTINATION ABOVE.** That one goes under the standing layer because it marks the GROUND a
	# body is walking to. This one marks the SUBJECT of the next button press, and that subject is
	# usually a BUILDING standing on its tiles -- under the sprites it would be invisible exactly
	# when it matters. It can sit on top without hiding anything because it is a 2 px outline inset
	# inside the footprint: the middle, which is the thing selected, is untouched.
	#
	# **THIS USED TO SAY "a machine or a ROCK that stands on its tile" AND THE ROCK WAS WRONG**
	# (ASSA-348). `Mine` carries no argument at all, so a rock is never the subject of any command;
	# the example quietly justified a one-tile mark by naming the one thing that is always one tile.
	# The span arrives as `selection`, in tiles, and the sim is what decided it.
	if selection != null:
		var at: Rect2i = selection
		var from: Vector2 = view.get("origin", Vector2.ZERO)
		# EVERY KEYLINE FIRST, THEN EVERY BAR, for `destination`'s reason one block up: the sides of
		# the outline meet at the corners, so a per-bar rim would lay MAP_BG over the ink beside it.
		#
		# **`edge`/`halo` AND NOT `bar`/`rim`, WHICH IS NOT A STYLE CHOICE.** `test_click_echo.gd`
		# proves the destination's ink by scanning this function for a line beginning `draw_rect(bar`
		# -- and a second one of those, added here, silently became the line it inspected. The first
		# run of this change turned that test red, which is the scan doing its job. Two source scans
		# over one function need two names, or the newer mark quietly answers for the older one.
		for halo in AssayScene.selection_keyline(at, from):
			draw_rect(halo, AssayHud.MAP_BG, true)
		for edge in AssayScene.selection_mark(at, from):
			draw_rect(edge, AssayHud.mark_ink(&"target"), true)
		# THE UNION OF THE BARS, ASKED OF THE SAME FUNCTION THAT MADE THEM (ASSA-348). This line used
		# to rebuild the rect out of the tile and `TILE_PX`, which is a second arithmetic for one
		# rectangle: the bars could trace a quarter of a smelter while this went on reporting the
		# whole of it, and the probe that reads this would have proved the defect correct.
		drawn_selection = AssayScene.selection_box(at, from)


## ONE SPRITE. Nothing is decided here; `src`, `dest` and `tint` all arrive worked out.
func _blit(place: Dictionary) -> void:
	if bool(place.get("composite", false)):
		_blit_machine(place)
		return
	var asset := String(place.get("asset", ""))
	if not _textures.has(asset):
		_textures[asset] = load("%s%s.png" % [AssaySprites.SHEET_DIR, asset])
	var texture: Texture2D = _textures[asset]
	if texture == null:
		return
	draw_texture_rect_region(texture, place["dest"], place["src"], place["tint"])


## ONE MACHINE, FROM ITS PARTS. The rectangle is `AssayScene`'s as always; the only thing this adds
## is the image to put in it, built once per design and kept.
##
## `draw_texture_rect` AND NOT `_region`: the composite IS the frame, so there is no row to pick out
## of a sheet. `false` for `tile` -- a machine bigger than its rectangle would otherwise repeat
## instead of scaling, which is the silent kind of wrong that looks like a pattern someone chose.
##
## A MACHINE WE CANNOT DRAW DRAWS NOTHING, the same answer `_place` gives for a missing row. Three of
## the sim's item kinds still have no art, so a part with no sheet is a state the game is really in
## (ASSA-46) and an invented box would be worse than a gap.
func _blit_machine(place: Dictionary) -> void:
	var key := String(place.get("key", ""))
	if not _machines.has(key):
		var image := AssayAssembly.image_of(place.get("parts", []))
		_machines[key] = ImageTexture.create_from_image(image) if image != null else null
	var texture: Texture2D = _machines[key]
	if texture == null:
		return
	draw_texture_rect(texture, place["dest"], false, place["tint"])
