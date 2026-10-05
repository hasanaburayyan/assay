extends SceneTree
## WHAT SIZE IS THE PACK ICON REALLY DRAWN AT, for the REAL pack the demo loop produces?
## `custom_minimum_size` is a FLOOR: the row is an HBoxContainer and a TextureRect fills vertically,
## so the rect is 32 x (row height) and STRETCH_KEEP_ASPECT_CENTERED scales by min(w/fw, h/fh).
## The stacks below are the richest pack `tools/button_session.gd -- offline` actually held (seed
## 777042), not stacks I typed.
var _screen: Node = null
var _frames := 0
var _stacks: Array = []

func _initialize() -> void:
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)

## WHICH SIM VERB A BUTTON CARRIES, asked of the same source `main.gd` asks (ASSA-99).
##
## Maren's ASSA-86 ruling splits a row's buttons into the ones that MOVE an item (insert, place,
## build -- Fuel, Smelt, Place, Frame/Mount) and the ones that MAKE something (craft, make), which
## leave for the crafting menu. Drawing that split means knowing which is which, and the one way NOT
## to know it is to parse my own labels: "Craft gear" starting with the word Craft is a fact about
## English, not about the command the button submits.
##
## `AssayHud.stack_verbs` returns descriptors carrying a `verb` -- the sim-facing name -- in the same
## order the buttons are built, out of `AssaySimHost.recipes()` and `part_kinds()`. So this asks the
## recipe table, exactly as the screen did when it made the button.
func _verb_kinds(stack: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _verbs_for(stack):
		out.append(String((entry as Dictionary).get("verb", "?")))
	return out


## The descriptors `main.gd` would build for this stack, asked of the same function it asks.
##
## IT USED TO TAKE THE CLIENT'S "a frame has already been chosen" STATE. ASSA-103 removed that
## argument from `stack_verbs` -- a part row's word is its kind's `is_frame` and no longer moves --
## so there is nothing left to pass.
func _verbs_for(stack: Dictionary) -> Array:
	var footprint := AssaySimHost.footprint_of_item(String(stack.get("kind", "")),
			int(stack.get("species", -1)), String(stack.get("grade", "C")))
	return AssayHud.stack_verbs(stack, AssaySimHost.recipes(), AssaySimHost.part_kinds(),
			footprint)


## **THE LABELS WITH A FRAME ALREADY CHOSEN, WHICH SINCE ASSA-103 ARE THE SAME LABELS.** That is
## now the point of this field rather than a reason to delete it: the defect Maren filed was that a
## part row's word SWAPPED when an assembly was part-way built, so a second column showing the same
## words is the evidence that it has stopped swapping.
##
## STILL ASKED OF THE SAME FUNCTION, never typed in here. `stack_verbs` no longer takes the state at
## all, so this cannot drift from the screen without the whole first column drifting with it.
##
## `art/pack_row_sheet.py` NO LONGER DRAWS THIS, and that is the ruling rather than a regression:
## a second identical column cost half the sheet's width to say "nothing changed", so the sheet now
## DIFFS the two label sets and prints a line that fires, naming the rows, if the word ever swaps
## again. That is why this field is still worth exporting -- it is the input to a check, not a
## picture. Proved to fire by feeding the sheet a pre-ASSA-103 `labels_building`.
func _labels_building(stack: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _verbs_for(stack):
		out.append(String((entry as Dictionary).get("label", "?")))
	return out

## IS THIS STACK'S KIND A FRAME, according to the SIM'S OWN CATALOGUE?
##
## Maren's ASSA-86 ruling 1 says the part label is a property of the KIND: a frame kind says
## `Frame` forever, every other kind says `Mount` forever, picked by `is_frame()`.
##
## PREFERS THE EXPLICIT FIELD, WHICH NOW EXISTS. When this was written, `part_kinds()` carried
## name/size/material/tag and Maren's ruling said the field "is simply absent". It was not absent,
## only structural: `tag` is the serde form of the sim's `PartTag`, so `{"Frame": "Held"}` is a
## frame and `"Head"` is not. ASSA-102 (#131) then added a real `is_frame` to `part_kinds()`, so
## that inference is now the WORSE source and is kept only as a fallback.
##
## Reading the enum's SHAPE was always the fragile half of this: had `PartTag` become a struct with
## a `kind` field, the inference would have gone QUIET -- every part reported as mounted -- rather
## than failing. I said so when I reported the finding; the explicit field is what retires it.
##
## Either way this asks the CATALOGUE and never the button's text: "Frame" starting with the word
## Frame would be a fact about English, not about the sim (ASSA-99's lesson).
##
## CHECKED AGAINST THE SIM'S OWN VERDICTS rather than trusted: Maren ran `Assembly::validate`
## (shared/assay/maren_frame_button_2026-10-02.out) and got head/hopper FrameIsNotAFrame,
## handle/frame accepted as the first part. Both sources agree with it on all four kinds.
##
## Returns 1 for a frame kind, 0 for a mounted kind, -1 when the stack is not a part at all.
func _is_frame_kind(stack: Dictionary) -> int:
	var kind := String(stack.get("kind", ""))
	for entry in AssaySimHost.part_kinds():
		var part: Dictionary = entry as Dictionary
		if String(part.get("name", "")) != kind:
			continue
		if part.has("is_frame"):
			return 1 if bool(part["is_frame"]) else 0
		var tag: Variant = part.get("tag")
		return 1 if (tag is Dictionary and (tag as Dictionary).has("Frame")) else 0
	return -1


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2:
		_stacks = [
			{"kind": "refined", "species": 4, "grade": "B", "count": 6,
				"name": "Minyte refined (B)"},
			{"kind": "head", "species": 4, "grade": "B", "count": 2, "name": "Minyte head (B)"},
			{"kind": "handle", "species": 4, "grade": "B", "count": 1, "name": "Minyte handle (B)"},
			{"kind": "frame", "species": 4, "grade": "B", "count": 1, "name": "Minyte frame (B)"},
			{"kind": "hopper", "species": 4, "grade": "B", "count": 1, "name": "Minyte hopper (B)"},
			{"kind": "ore", "species": 4, "grade": "B", "count": 22, "name": "Minyte ore (B)"},
			{"kind": "smelter", "species": 4, "grade": "B", "count": 1,
				"name": "Minyte smelter (B)"},
		]
		_screen._rebuild_pack(_stacks)
		# **THE COLUMN IS SHOWN ON PURPOSE, AND ASSA-231 IS WHY THIS LINE EXISTS.** Maren's Gap 5
		# hides the whole HUD column until a world exists, and this probe never joins one -- it
		# hand-builds stacks and measures how the client lays them out. Without this, the rows are
		# laid out INSIDE A HIDDEN PANEL, their rects collapse, and the stamp moves: the first run
		# after Gap 5 reported pack_icons, pack_rows and pack_icon_kinds all STALE against a client
		# whose pack layout had not changed by one pixel.
		#
		# IT RESTORES THE STATE THE SHEET IS A PICTURE OF, rather than inventing one. These sheets
		# are about icon and plate geometry inside the column, which is a thing a player only ever
		# sees in a world; the join screen's emptiness is a different picture and window_shot.gd's.
		_screen._column.visible = true
		return false
	if _frames < 6:
		return false
	var rows: Array = []
	for child in _screen._carrying.get_children():
		if not (child is Control):
			continue
		var row: Control = child
		# RECURSIVELY, because the icon is not a direct child any more: ASSA-71 put it inside a Panel
		# that paints the slot plate behind it. This loop used to walk `row.get_children()` only, and
		# the day the plate landed it stopped finding the icon at all -- the probe reported rows with
		# no `icon` key and `check_pack_icon_scale.py` had nothing to score, which is a check going
		# quiet rather than red. Same lesson as `find_child("StackLine")` on the line below: look for
		# the thing, not for where it used to sit.
		var art: TextureRect = _icon_in(row)
		var label: Label = row.find_child("StackLine", true, false) as Label
		var verbs := PackedStringArray()
		var boxes: Array = []
		for b in _buttons_in(row):
			verbs.append(b.text)
			# WHERE EACH BUTTON ACTUALLY LANDED, so a sheet can draw the row rather than guess at it
			# (ASSA-99). Relative to the row, because the row is what gets pasted.
			boxes.append([b.global_position.x - row.global_position.x,
					b.global_position.y - row.global_position.y, b.size.x, b.size.y])
		var entry: Dictionary = {
			"line": "" if label == null else label.text,
			"font_size": 0 if label == null else label.get_theme_font_size("font_size"),
			"row_size": [row.size.x, row.size.y],
			"separation": row.get_theme_constant("separation"),
			"verbs": verbs,
			"verb_boxes": boxes,
			# The SIM's name for each verb, in button order. See `_verb_kinds`.
			"verb_kinds": _verb_kinds(_stacks[rows.size()] as Dictionary),
			# 1 frame kind, 0 mounted kind, -1 not a part. From the catalogue; see `_is_frame_kind`.
			"is_frame": _is_frame_kind(_stacks[rows.size()] as Dictionary),
			# The same row's labels once a frame has been chosen. See `_labels_building`.
			"labels_building": _labels_building(_stacks[rows.size()] as Dictionary),
		}
		if art != null:
			var fw: float = art.texture.get_width()
			var fh: float = art.texture.get_height()
			var s: float = min(art.size.x / fw, art.size.y / fh)
			var region: Rect2 = (art.texture as AtlasTexture).region
			entry["icon"] = {
				"rect": [art.size.x, art.size.y],
				"frame": [fw, fh],
				"region": [region.position.x, region.position.y, region.size.x, region.size.y],
				"sheet": (art.texture as AtlasTexture).atlas.resource_path,
				"scale": s,
				"drawn": [fw * s, fh * s],
				"modulate": art.modulate.to_html(false),
				"filter": art.texture_filter,
				# THE PLATE THE ENGINE ACTUALLY PAINTED, not the colour the pipeline computed.
				# `pack_icon_sheet.py` used to read `ground.png` and work the median out for itself,
				# which measured a plate nobody had drawn yet. Taking it from here keeps that script
				# honest the same way every other number in it is: it reports what the client did.
				# "" when there is no plate behind this icon.
				"plate": _plate_behind(art),
				"plate_rect": _plate_rect(art),
			}
		rows.append(entry)
	print("LAYOUT_JSON ", JSON.stringify({"rows": rows,
			"clear_color": str(ProjectSettings.get_setting(
				"rendering/environment/defaults/default_clear_color", "UNSET")),
			"panel_px": _screen.PANEL, "icon_px": _screen.ICON_PX}))
	return true

## The icon anywhere under a row, however it is wrapped.
func _icon_in(node: Node) -> TextureRect:
	for child in node.get_children():
		if child is TextureRect:
			return child
		var deeper: TextureRect = _icon_in(child)
		if deeper != null:
			return deeper
	return null


## The slot plate's colour as the engine holds it, read off the StyleBoxFlat of the icon's parent.
## "" when the icon has no plate behind it, which is what a client with no `ui_theme.json` draws.
func _plate_behind(art: TextureRect) -> String:
	var parent := art.get_parent()
	if not (parent is Panel):
		return ""
	var style: StyleBox = (parent as Panel).get_theme_stylebox("panel")
	if not (style is StyleBoxFlat):
		return ""
	return (style as StyleBoxFlat).bg_color.to_html(false)


## How big that plate is. The point of ASSA-71 is that the plate is the icon's BOX, so if these two
## ever disagree the icon is sitting on something other than its own slot.
func _plate_rect(art: TextureRect) -> Array:
	var parent := art.get_parent()
	if not (parent is Panel):
		return []
	return [(parent as Panel).size.x, (parent as Panel).size.y]


func _buttons_in(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_buttons_in(child))
	return found
