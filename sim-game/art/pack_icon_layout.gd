extends SceneTree
## WHAT SIZE IS THE PACK ICON REALLY DRAWN AT, for the REAL pack the demo loop produces?
## `custom_minimum_size` is a FLOOR: the row is an HBoxContainer and a TextureRect fills vertically,
## so the rect is 32 x (row height) and STRETCH_KEEP_ASPECT_CENTERED scales by min(w/fw, h/fh).
## The stacks below are the richest pack `tools/button_session.gd -- offline` actually held (seed
## 777042), not stacks I typed.
var _screen: Node = null
var _frames := 0

func _initialize() -> void:
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2:
		_screen._rebuild_pack([
			{"kind": "refined", "species": 4, "grade": "B", "count": 6,
				"name": "Minyte refined (B)"},
			{"kind": "head", "species": 4, "grade": "B", "count": 2, "name": "Minyte head (B)"},
			{"kind": "handle", "species": 4, "grade": "B", "count": 1, "name": "Minyte handle (B)"},
			{"kind": "frame", "species": 4, "grade": "B", "count": 1, "name": "Minyte frame (B)"},
			{"kind": "hopper", "species": 4, "grade": "B", "count": 1, "name": "Minyte hopper (B)"},
			{"kind": "ore", "species": 4, "grade": "B", "count": 22, "name": "Minyte ore (B)"},
			{"kind": "smelter", "species": 4, "grade": "B", "count": 1,
				"name": "Minyte smelter (B)"},
		])
		return false
	if _frames < 6:
		return false
	var rows: Array = []
	for child in _screen._carrying.get_children():
		if not (child is Control):
			continue
		var row: Control = child
		var art: TextureRect = null
		for g in row.get_children():
			if g is TextureRect:
				art = g
		var label: Label = row.find_child("StackLine", true, false) as Label
		var verbs := PackedStringArray()
		for b in _buttons_in(row):
			verbs.append(b.text)
		var entry: Dictionary = {
			"line": "" if label == null else label.text,
			"font_size": 0 if label == null else label.get_theme_font_size("font_size"),
			"row_size": [row.size.x, row.size.y],
			"separation": row.get_theme_constant("separation"),
			"verbs": verbs,
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
			}
		rows.append(entry)
	print("LAYOUT_JSON ", JSON.stringify({"rows": rows,
			"clear_color": str(ProjectSettings.get_setting(
				"rendering/environment/defaults/default_clear_color", "UNSET")),
			"panel_px": _screen.PANEL, "icon_px": _screen.ICON_PX}))
	return true

func _buttons_in(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_buttons_in(child))
	return found
