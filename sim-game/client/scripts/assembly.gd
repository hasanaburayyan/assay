class_name AssayAssembly
## A MACHINE'S PARTS, DRAWN AS ONE MACHINE, by the pipeline's rules rather than this client's.
##
## `art/part_layout.json` is Cove's drawing contract (ASSA-54, PR #79), written by `art/build.py` from
## `art/part_layout.py` and held equal to it in CI. It carries the two rules a renderer gets WRONG by
## default, and both of them are the sort of wrong that still looks like a picture:
##
## 1. REPEATS NEED AN OFFSET. The nth repeat of a part KIND goes at `n * repeat_offset_px`, counting
##    from 0 in the sim's `Assembly::parts()` order. Drawn on top of each other, hoppers two, three and
##    four are invisible while capacity is a real number in the sim -- so a machine would under-report
##    what it does.
## 2. SHADOWS MUST NOT ACCUMULATE. Every part sprite carries its own contact shadow. Composite colour
##    OVER, but take alpha MAX wherever the source pixel's brightest channel is below
##    `shadow_ceiling`. Plain `over` deepens the shadow with every part added, which turns a gradient
##    into a readout of part count.
##
## WHY PIXELS AND NOT `draw_texture`. A canvas loop cannot express alpha-MAX -- Godot's blend modes
## are mix/add/sub/mul/premultiplied and none of them is max -- so rule 2 needs a shader, art changes,
## or this: composite into one `Image` and hand back a texture. That is affordable because an assembly
## changes when a player builds or equips, not per tick, so the caller caches by `key_of`.
##
## AT AUTHORING RESOLUTION, DELIBERATELY. The offset is "the same authoring pixels as `frame_px`", so
## composing at 128x102 keeps it the integer (14, -6) the contract states and resamples nothing. A
## caller drawing the frame at half size draws this at half size too, and Cove's "(7, -3) at 1x" falls
## out of that instead of being a second number someone has to keep.
##
## NOTHING HERE DECIDES WHAT A MACHINE IS: the part list and its order are the sim's
## (`AssaySim.designs_of` -> `parts`), the sheets and their rows are the pipeline's
## (`AssaySprites`), and the geometry is the contract's.

const CONTRACT := "res://assets/sprites/part_layout.json"

## The contract, or {} when it cannot be read or is missing a key this file needs.
##
## EVERY NUMBER IS CAST. Godot's JSON parses every number as a double, so the file hands back `14.0`
## and `34.0`; Cove confirmed that from a headless run rather than from Python. `Vector2i` of a float
## is a silent truncation everywhere else in this client, so the cast is here where it is visible.
##
## {} rather than a default: a client that silently fell back to its own geometry is exactly what
## ASSA-54 was filed about. The caller draws nothing and the gap is loud.
static func contract() -> Dictionary:
	var text := FileAccess.get_file_as_string(CONTRACT)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	var raw: Dictionary = parsed
	var offset: Array = raw.get("repeat_offset_px", [])
	if offset.size() != 2 or not raw.has("shadow_ceiling"):
		return {}
	return {
		"repeat_offset_px": Vector2i(int(offset[0]), int(offset[1])),
		"shadow_ceiling": int(raw.get("shadow_ceiling", 0)),
	}


## ONE IMAGE OF ONE ASSEMBLY, or null when any part has no art or the contract will not read.
##
## `parts` is the sim's list, in the sim's order, each entry kind+species+grade -- which is what
## `AssaySprites.icon_for` already takes, because a part dict and a pack stack are the same shape.
## `rules` is for tests to hand in a doctored contract; production passes nothing and reads the file.
##
## Null is an honest answer and callers must handle it: three of the sim's item kinds have no art at
## all, so "no picture" is a state this game is really in (ASSA-46).
static func image_of(parts: Array, rules: Dictionary = {}) -> Image:
	var layout: Dictionary = contract() if rules.is_empty() else rules
	if layout.is_empty() or parts.is_empty():
		return null
	var offset: Vector2i = layout.get("repeat_offset_px", Vector2i.ZERO)
	var ceiling := float(int(layout.get("shadow_ceiling", 0))) / 255.0
	var placed := _placements(parts, offset)
	if placed.is_empty():
		return null
	var frames: Array[Image] = []
	for part in parts:
		var frame := _frame_of(part as Dictionary)
		if frame == null:
			return null
		frames.append(frame)
	var box := canvas_of(parts, Vector2i(frames[0].get_width(), frames[0].get_height()), offset)
	if box.size.x <= 0 or box.size.y <= 0:
		return null
	var out := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBAF)
	out.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i in range(parts.size()):
		_composite(out, frames[i], (placed[i] as Vector2i) - box.position,
				AssaySprites.tint_for(parts[i] as Dictionary), ceiling)
	return out


## THE BOX THE COMPOSITE FILLS, IN AUTHORING PIXELS, AS ARITHMETIC ALONE.
##
## `position` is where the box starts relative to the FRAME's own top-left -- zero or negative, since
## repeats climb -- and `size` is how big the finished image is. The union of where the parts land:
## the vertical offset is negative, so the box grows upward, and sizing to one frame would crop the
## parts that make the machine readable.
##
## **IT IS SEPARATE FROM `image_of` BECAUSE A RENDERER HAS TO KNOW WHERE A MACHINE WILL BE BEFORE IT
## HAS ITS PIXELS.** `AssayScene` decides every rectangle in the world view headless, with no sheets
## decoded and no engine (that is the whole reason `test_scene_view.gd` can hold the picture to
## account), and it cannot ask an `Image` how tall a drill is. So the size comes from the manifest's
## `frame_px` here, and `image_of` above derives the same box from the REAL sheet -- which is what
## makes `the_manifest_agrees_with_the_sheet_about_a_drills_canvas` a test worth having rather than a
## tautology: the two numbers come from different files and CI is the only thing holding them equal.
##
## `position` is also the whole of the anchor answer. A caller that knows where a lone frame sprite
## would go subtracts `position` to put the composite's frame in exactly that place, and the repeats
## then hang above and to the east of the footprint tile -- which they are allowed to do (ASSA-30/38:
## a sprite may overhang its tile and says nothing about which tile it stands on).
static func canvas_of(parts: Array, frame_px: Vector2i, offset: Vector2i) -> Rect2i:
	if frame_px.x <= 0 or frame_px.y <= 0:
		return Rect2i()
	var placed := _placements(parts, offset)
	if placed.is_empty():
		return Rect2i()
	var lo := Vector2i.ZERO
	var hi := frame_px
	for at: Vector2i in placed:
		lo.x = mini(lo.x, at.x)
		lo.y = mini(lo.y, at.y)
		hi.x = maxi(hi.x, at.x + frame_px.x)
		hi.y = maxi(hi.y, at.y + frame_px.y)
	return Rect2i(lo, hi - lo)


## WHERE EACH PART GOES: `n * repeat_offset_px` for the nth part OF THAT KIND, n from 0, in the order
## the sim handed the parts over (frame first). Counting per KIND is the contract's wording -- a drill
## with a head and three hoppers offsets the hoppers 0, 1, 2 and leaves the head where the frame is.
static func _placements(parts: Array, offset: Vector2i) -> Array:
	var seen := {}
	var out := []
	for entry in parts:
		var kind := String((entry as Dictionary).get("kind", "")).to_lower()
		if kind == "":
			return []
		var n := int(seen.get(kind, 0))
		seen[kind] = n + 1
		out.append(offset * n)
	return out


## One part's pixels, from the sheet the pipeline drew, at the row the sim's grade names.
static func _frame_of(part: Dictionary) -> Image:
	# THE ASSEMBLY DRAWING, NOT THE PACK ONE (ASSA-121). A part has two pictures: the loose object a
	# pack slot shows and the registered frame a machine is built out of. `part_layout.json`'s repeat
	# offset is expressed in THIS sheet's authoring pixels, so compositing the items row instead would
	# put every repeat in the wrong space.
	var icon := AssaySprites.assembly_icon_for(part)
	if icon == null or icon.atlas == null:
		return null
	var sheet := icon.atlas.get_image()
	if sheet == null:
		return null
	var region := Rect2i(icon.region)
	if region.size.x <= 0 or region.size.y <= 0:
		return null
	var frame := sheet.get_region(region)
	# A VRAM-COMPRESSED SHEET HAS NO PIXELS TO READ. Block compression also eats the exact alphas rule
	# 2 is about, so this says so rather than returning a picture made of mush -- the sheets are
	# imported lossless on purpose (ASSA-34: never re-import with `detect_3d` on).
	if frame.is_compressed() and frame.decompress() != OK:
		return null
	# RGBAF to composite in: the sheets are 8-bit, and taking alpha MAX of two values that were each
	# rounded to 1/255 is how a flat shadow picks up banding.
	frame.convert(Image.FORMAT_RGBAF)
	return frame


## RULE 2, LITERALLY: colour OVER, alpha MAX on the source's shadow pixels.
##
## THE SHADOW TEST IS ON THE UNTINTED PIXEL, because `shadow_ceiling` is a number about what Cove drew.
## A species tint is a multiply, so classifying after tinting would let a dark tint push a dark-grey
## pixel of the part itself under the ceiling and quietly turn machinery into shadow.
static func _composite(out: Image, part: Image, at: Vector2i, tint: Color, ceiling: float) -> void:
	for y in range(part.get_height()):
		for x in range(part.get_width()):
			var src := part.get_pixel(x, y)
			if src.a <= 0.0:
				continue
			var shadow := maxf(maxf(src.r, src.g), src.b) < ceiling
			var col := Color(src.r * tint.r, src.g * tint.g, src.b * tint.b, src.a)
			var dst := out.get_pixel(at.x + x, at.y + y)
			var over := col.a + dst.a * (1.0 - col.a)
			if over <= 0.0:
				continue
			var weight := dst.a * (1.0 - col.a)
			out.set_pixel(at.x + x, at.y + y, Color(
					(col.r * col.a + dst.r * weight) / over,
					(col.g * col.a + dst.g * weight) / over,
					(col.b * col.a + dst.b * weight) / over,
					maxf(col.a, dst.a) if shadow else over))


## WHAT MAKES TWO ASSEMBLIES THE SAME PICTURE, for a caller's cache. Kind, species and grade of every
## part in the sim's order -- the three things that choose a sheet, a row and a tint, and nothing
## else. Mass and the verdict change without the picture changing.
static func key_of(parts: Array) -> String:
	var out := PackedStringArray()
	for entry in parts:
		var part: Dictionary = entry
		out.append("%s:%d:%s" % [String(part.get("kind", "")), int(part.get("species", -1)),
				String(part.get("grade", ""))])
	return "|".join(out)
