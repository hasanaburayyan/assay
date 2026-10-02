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

## WHICH SHEET AND ROW AN ITEM KIND USES, and the honest gaps.
##
## `ore` as an ITEM is `items.png`'s own row, not the `ore.png` world tile: the tile is a rock on the
## ground and the item is a thing in a pack, and Cove drew them separately. The four part kinds have a
## row per grade. `refined`, `gear` and `smelter` have NO art yet and are listed here as empty on
## purpose, so the gap is visible in this file rather than looking like a missing case.
##
## THESE EMPTY ENTRIES ARE DOCUMENTATION, NOT THE GUARD, and I checked rather than assuming: pointing
## `refined` at `items` still draws nothing, because `items` has one row called `ore` and `_row_for`
## finds no row named for the grade. The row lookup is what actually refuses. Said here so the next
## person does not trust the wrong line.
const SHEET_OF := {
	"ore": "items",
	"head": "head",
	"handle": "handle",
	"frame": "frame",
	"hopper": "hopper",
	"refined": "",
	"gear": "",
	"smelter": "",
}


## The manifest, parsed once per call site that needs it. Returns {} if it cannot be read, which makes
## every icon absent rather than making the panel an error.
static func manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string(MANIFEST)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## THE FRAME FOR ONE PACK STACK, or null when we have no art for it.
##
## Null is a normal answer and not a failure: `items.png` carries ore and nothing else, so a refined
## bar, a gear and a smelter all come back null today. The caller draws a row without an icon, which
## is why `stack_line` has to stay a complete sentence.
static func icon_for(stack: Dictionary) -> AtlasTexture:
	var kind := String(stack.get("kind", "")).to_lower()
	var sheet := String(SHEET_OF.get(kind, ""))
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
	# A ROW IS A ROW OF THE SHEET, so y is the row index times the frame height. Column 0: every row we
	# use here is one frame wide for an item, and a part's second column is its planted variant, which
	# is not what a pack row is showing.
	atlas.region = Rect2(0.0, float(row) * float(frame[1]), float(frame[0]), float(frame[1]))
	return atlas


## WHICH ROW, BY THE SIM'S OWN GRADE LETTER. `items` has a single row, so ore ignores grade -- Cove
## drew one ore icon, and inventing a per-grade variation it does not have would be this file deciding
## something. The part sheets have exactly C, B and A.
static func _row_for(kind: String, grade: String, spec: Dictionary) -> int:
	var rows: Array = spec.get("rows", [])
	if rows.is_empty():
		return -1
	if kind == "ore":
		return 0
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
