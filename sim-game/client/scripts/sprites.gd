class_name AssaySprites
extends RefCounted
## THE SHEETS, AND WHICH FRAME AN ITEM IS. Nothing about rules, nothing about layout.
##
## ASSA-46, Maren's ruling B: sprites only where the scale suits. The map stays discs and glyphs --
## `map_cell` fits a whole 96x64 world beside the HUD, so a tile is 9px and a 64px frame would be a 7x
## downscale; Cove measured that it does not degrade into the disc, it becomes speckle 29 dE from flat.
## So the first surface that gets art is the PACK ROW, where 32px is a size the art was drawn to
## survive. The departure from judge-at-1x is written down on the item with that number.
##
## WHAT THIS FILE MAY NOT DO:
##  - DECIDE ANYTHING ABOUT AN ITEM. The grade picks the row and the species picks the tint, and both
##    arrive decided (`inventory_of`). No thresholds, no mapping of numbers to words.
##  - BE REQUIRED. Every row it draws on reads completely without it (Maren's rule, the same one the
##    species glyph carries: a redundant cue that becomes the only cue is no longer redundant).
##    `icon_for` returns null for every item we have no art for, which today is most of them.
##
## THE MANIFEST IS READ, NOT COPIED. Frame sizes, row names and counts come out of
## `res://assets/sprites/manifest.json` at load, because Cove generates it beside the sheets and a
## second copy of those numbers in GDScript is the kind of drift that has cost me two wrong readouts
## this week. If a row is renamed the icon disappears; it does not draw the wrong frame.

const MANIFEST := "res://assets/sprites/manifest.json"
const SHEET_DIR := "res://assets/sprites/"

## COLOURS THE CLIENT DRAWS THAT ARE IN NO SPRITE, beside the manifest and read the same way.
## A sibling file rather than a manifest key because the manifest's top level is an asset namespace:
## every key there is expected to have a sheet, and `build.py` drops anything that is not an asset on
## its next run. Same reason `part_layout.json` is its own file (ASSA-54/71).
const UI_THEME := "res://assets/sprites/ui_theme.json"

## WHICH SHEET AND ROW AN ITEM KIND USES, and the honest gaps.
##
## `ore` as an ITEM is `items.png`'s own row, not the `ore.png` world tile: the tile is a rock on the
## ground and the item is a thing in a pack, and Cove drew them separately. `refined` is the second
## row of the same sheet (ASSA-66) and `smelter` the third (ASSA-87). `gear` has NO art and is listed
## here as empty on purpose, so the gap is visible in this file rather than looking like a missing
## case.
##
## THE FOUR PART KINDS ARE ALSO `items` ROWS NOW (ASSA-121), AND THAT IS A CHANGE OF SURFACE, NOT OF
## ART. A pack slot is 32x48 -- portrait, 2:3 -- and an item's authoring frame is 64x96, exactly 2:3,
## so it fills the plate. A part's ASSEMBLY frame is 128x102, landscape, because `PART_TILES = (2, 1)`
## exists to hold an assembly JOIN and not to hold an object; fitted into a portrait slot the same
## four parts filled 4.5-13.3% of it where every item fills 24.7-35.2%. So Maren ruled (ASSA-112) that
## a part in your pack is a LOOSE THING and gets a row on the items sheet, and Cove drew them: 26.6 /
## 31.2 / 37.7 / 38.9%, all above the floor ore sets at 24.7. This dictionary is where that ruling
## reaches the screen.
##
## THE ASSEMBLY DRAWINGS DID NOT GO ANYWHERE -- see `ASSEMBLY_SHEET_OF` below, which is the map this
## one used to be for parts. Two drawings of one object, each for the surface it serves.
##
## THESE EMPTY ENTRIES ARE DOCUMENTATION, NOT THE GUARD, and that was checked rather than assumed:
## before `items` had a second row, pointing `refined` here still drew nothing, because `_row_for`
## found no row named for the grade. The row lookup is what actually refuses. Said here so the next
## person does not trust the wrong line -- and it is why adding the row to the sheet was not on its
## own enough to make the icon appear.
##
## THE GEAR'S GAP IS SETTLED, NOT PENDING. Maren ruled on ASSA-84 that nothing in the game consumes
## a gear, so a gear icon would be art for a dead recipe. It stays empty until that changes.
const SHEET_OF := {
	"ore": "items",
	"refined": "items",
	"smelter": "items",
	"head": "items",
	"handle": "items",
	"frame": "items",
	"hopper": "items",
	"gear": "",
}

## WHICH SHEET A PART USES WHEN IT IS PART OF A MACHINE, which is a different question (ASSA-121).
##
## This is what `SHEET_OF` held for the four part kinds until the pack rows moved to the items sheet,
## and it has to keep holding it, because the two surfaces want different pictures of the same object:
##
##  - a PACK ROW wants the loose drawing -- one object, filling a portrait slot, no join.
##  - a MACHINE wants the ASSEMBLY drawing -- registered so parts join, at `frame_px` 128x102 with
##    `anchor_px` and `tiles` that `part_layout.json`'s repeat offset is expressed in. Composite an
##    items row instead and every repeat offset is in the wrong space and the machine comes apart.
##
## SO THE SPLIT IS NOT TIDINESS: before it, `assembly.gd::_frame_of` and `scene_view.gd` reached the
## assembly sheets THROUGH `SHEET_OF`, so pointing the pack rows at `items` would have silently
## redrawn every planted machine out of loose-part pictures. ASSA-138's composite path landed between
## ASSA-121 being filed and being built, which is why the item reads as a four-line remap and is not.
##
## ONE ROW PER GRADE here, where the items rows are one row per kind: `_row_for` finds a part's C/B/A
## row by the grade the sim gave it. Nothing in this file decides which; both arrive decided.
const ASSEMBLY_SHEET_OF := {
	"head": "head",
	"handle": "handle",
	"frame": "frame",
	"hopper": "hopper",
}


## The manifest, parsed once per call site that needs it. Returns {} if it cannot be read, which makes
## every icon absent rather than making the panel an error.
static func manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string(MANIFEST)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## THE PACK-ROW ICON'S SLOT PLATE, or TRANSPARENT when the pipeline has not shipped one.
##
## The colour is the ground sheet's own median, computed by `art/ui_theme.py` on every build. It is
## not written down here, and it must not be: Maren's ruling (ASSA-71) is that the plate is "the
## ground's own colour", which is a claim about `ground.png`. A hex in this file would stop being
## true the day the ground is re-rendered and nobody would find out.
##
## ONE COLOUR FOR EVERY SPECIES AND EVERY GRADE. The plate never carries information. A tinted plate
## would be a second colour channel competing with the icon, which is the ASSA-39 mistake, and it
## would also undo the point: the spread between species closes BECAUSE they all sit on one surface.
##
## TRANSPARENT, NOT A GUESSED COLOUR, when the file is missing. Unlike the geometry in
## `part_layout.json` -- where a client inventing its own numbers draws a wrong picture confidently
## (ASSA-54) -- a plate that is not there is simply not there, and the panel underneath is what
## shipped before ASSA-71. Drawing a grey I made up would be the invention.
static func pack_icon_plate() -> Color:
	var text := FileAccess.get_file_as_string(UI_THEME)
	if text.is_empty():
		return Color.TRANSPARENT
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return Color.TRANSPARENT
	var rgb: Array = (parsed as Dictionary).get("pack_icon_plate_rgb", [])
	if rgb.size() != 3:
		return Color.TRANSPARENT
	# Godot parses every JSON number as a double, so these arrive as 136.0. Cast at the one visible
	# place rather than letting Color8 truncate silently -- the same note as the part contract's.
	return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))


## THE FRAME FOR ONE PACK STACK, or null when we have no art for it.
##
## Null is a normal answer and not a failure: `items.png` carries ore, refined and smelter, so a gear
## is the one kind that still comes back null. The caller draws a row without an icon, which is why
## `stack_line` has to stay a complete sentence.
static func icon_for(stack: Dictionary) -> AtlasTexture:
	return _frame_from(stack, SHEET_OF)


## THE FRAME FOR ONE PART AS PART OF A MACHINE, or null when we have no art for it.
##
## `assembly.gd` and `scene_view.gd` call this and not `icon_for`, because a machine is composited out
## of the ASSEMBLY drawings -- see `ASSEMBLY_SHEET_OF` for why the two surfaces cannot share one map.
## A part dict and a pack stack are the same shape, so the body is the same; only the map differs.
static func assembly_icon_for(part: Dictionary) -> AtlasTexture:
	return _frame_from(part, ASSEMBLY_SHEET_OF)


## One frame out of whichever sheet the given map names for this kind. Shared so the pack row and the
## machine composite cannot drift in how they slice a sheet -- only in WHICH sheet they slice.
static func _frame_from(stack: Dictionary, sheets_of: Dictionary) -> AtlasTexture:
	var kind := String(stack.get("kind", "")).to_lower()
	var sheet := String(sheets_of.get(kind, ""))
	if sheet == "":
		return null
	var sheets := manifest()
	if not sheets.has(sheet):
		return null
	var spec: Dictionary = sheets[sheet]
	var row := _row_for(kind, String(stack.get("grade", "")), spec)
	if row < 0:
		return null
	var frame: Array = spec.get("frame_px", [])
	if frame.size() != 2:
		return null
	var texture: Texture2D = load("%s%s.png" % [SHEET_DIR, sheet])
	if texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	# A ROW IS A ROW OF THE SHEET, so y is the row index times the frame height. Column 0 because
	# column 0 is ALL THERE IS: every sheet this file reads is `"columns": 1` in the manifest and
	# every row is one frame. This comment used to say a part's second column was its planted
	# variant; that is not true of any sheet we ship and it sent a reader looking for a choice they
	# do not have (ASSA-66). "Held" and "planted" are a property of a DESIGN in the sim -- `mount`,
	# which `hud.gd` reads -- not two drawings of a part. A frame sprite is drawn with feet, and the
	# feet are the whole of standing up, so the part art is already the planted one. A held machine
	# that wanted to look different would be new art, not another column.
	atlas.region = Rect2(0.0, float(row) * float(frame[1]), float(frame[0]), float(frame[1]))
	return atlas


## WHICH ROW: AN ITEM SHEET NAMES ITS ROW FOR THE KIND, A PART SHEET FOR THE GRADE.
##
## `items` rows are called `ore` and `refined`, so the kind finds them by name. That used to be
## `if kind == "ore": return 0` -- an index this file chose, which was correct only while `items` had
## exactly one row, and silently wrong the moment a second was added above or below it (ASSA-66).
## Asking the manifest for the row by name is the same thing the part sheets already do with C/B/A,
## and it means adding a third item row needs nothing here.
##
## ITEM ROWS IGNORE GRADE, DELIBERATELY. Ore and refined are each one drawing: a refined bar is held
## at C, B and A and the grade is in the row's sentence, and inventing a per-grade variation the art
## does not have would be this file deciding something. The part sheets have exactly C, B and A.
static func _row_for(kind: String, grade: String, spec: Dictionary) -> int:
	var rows: Array = spec.get("rows", [])
	if rows.is_empty():
		return -1
	for i in range(rows.size()):
		if String((rows[i] as Dictionary).get("name", "")) == kind:
			return i
	var wanted := grade.to_upper()
	for i in range(rows.size()):
		if String((rows[i] as Dictionary).get("name", "")) == wanted:
			return i
	return -1


## THE TINT FOR A STACK'S ICON: the species' own slot, undimmed.
##
## The same table the map discs use (`AssayHud.SPECIES_TINTS`), which CI holds equal to the pipeline's
## copy in `art/species_tints.py`. The sheets are drawn species-neutral on light rock for exactly this
## reason (ASSA-19/20), so `modulate` is what makes an item look like its species.
##
## PURITY IS NOT IN THIS. A pack stack has a grade and no purity -- purity belongs to a deposit in the
## ground, and the item that came out of it carries the grade the sim gave it. Dimming an icon by a
## number the stack does not have would be an invention.
static func tint_for(stack: Dictionary) -> Color:
	var species := int(stack.get("species", -1))
	if species < 0:
		return Color.WHITE
	return Color(AssayHud.SPECIES_TINTS[posmod(species, AssayHud.SPECIES_TINTS.size())])
