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
## A `Control` WITH `clip_contents`, AND THAT IS WHY IT IS A CONTROL. The world is 912x600 inside a
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


func _init() -> void:
	clip_contents = true
	# THE HUD OWNS THE MOUSE, STILL. `main.gd::_unhandled_input` has handled clicks on the map since
	# ASSA-7 and it keeps that job: this node going first would mean two files deciding what a click
	# on a tile means. IGNORE, so the event passes straight through to the node that already knows.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), AssayHud.MAP_BG, true)
	if view.is_empty():
		return
	var all := AssayScene.placements(view)
	for place in all:
		if int(place.get("layer", AssayScene.FLOOR)) == AssayScene.FLOOR:
			_blit(place)
	if me != null:
		# THE ONE MARK ON THIS VIEW THAT IS NOT ART (ASSA-119 box 5). Drawn in the colour the
		# schematic has used for "yours" since ASSA-7 rather than in a new one, because Maren's
		# ruling-3 correction is that this client already holds 21 colour literals nobody chose as a
		# set, and a 22nd for the same meaning would be the same mistake again.
		draw_rect(AssayScene.foot_mark(me, view.get("origin", Vector2.ZERO)),
				Color(AssayHud.MINE.r, AssayHud.MINE.g, AssayHud.MINE.b, 0.55), true)
	for place in all:
		if int(place.get("layer", AssayScene.FLOOR)) == AssayScene.STANDING:
			_blit(place)


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
