extends SceneTree
## WHAT DOES A DESIGN ROW REALLY LOOK LIKE, laid out by the real screen? (ASSA-83)
##
##   godot --headless --path client --script "$PWD/art/design_row_layout.gd" -- /tmp/designs.json
##
## The other half of `pack_icon_layout.gd`, pointed at the bench instead of the pack. Decision #38
## asks the board whether the part menu reads as A DESIGN or as A DEBUG STRIP, and until this script
## existed the only ways to answer were reading `hud.gd` and playing the text client -- neither of
## which is the thing being judged.
##
## THE DESIGNS ARE THE WORLD'S, NOT MINE. `bench_read.gd` joins the standing bench and dumps
## `designs_of` verbatim; this reads that file. Nothing here invents a verdict, a mass or a budget,
## and nothing here decides a colour: the verdict's colour is read back off the Label the client
## built, so if `AssayHud.verdict_color` changed tomorrow this picture would change with it.
##
## ONE CONVERSION, AND IT IS A REAL RISK rather than a formality. `AssayHud.design_lines` reads
## `unassayed` as a `PackedStringArray`, and JSON gives back a plain `Array` -- `as PackedStringArray`
## on an Array does not convert, it fails, so the "assay X to know" line would silently vanish. That
## line is the whole content of an UNCERTAIN row, so a picture missing it would be a picture of the
## wrong panel. Converted explicitly below, and the rendered text is checked against what the live
## probe printed.
##
## Prints `DESIGN_LAYOUT_JSON <...>` and then `DESIGN LAYOUT OK` last.

var _screen: Node = null
var _frames := 0
var _designs: Array = []


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  usage: -- <designs.json from bench_read.gd>")
		quit(1)
		return
	var text := FileAccess.get_file_as_string(String(argv[0]))
	if text.is_empty():
		print("FAIL  could not read %s" % argv[0])
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not (parsed as Dictionary).has("designs"):
		print("FAIL  %s is not a bench_read dump" % argv[0])
		quit(1)
		return
	for entry in (parsed as Dictionary)["designs"]:
		_designs.append(_retyped(entry as Dictionary))
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)


## A design dictionary with the types the client expects, after a JSON round trip.
func _retyped(design: Dictionary) -> Dictionary:
	var out := design.duplicate(true)
	var names := PackedStringArray()
	for n in design.get("unassayed", []):
		names.append(String(n))
	out["unassayed"] = names
	return out


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 2:
		_screen._rebuild_bench(_designs)
		return false
	if _frames < 6:
		return false
	var rows: Array = []
	for child in _screen._bench.get_children():
		if not (child is Control):
			continue
		var row: Control = child
		var verdict: Label = row.get_child(0) as Label if row.get_child_count() > 0 else null
		var body: Label = row.get_child(1) as Label if row.get_child_count() > 1 else null
		var verbs: Array = []
		for b in _buttons_in(row):
			verbs.append({"label": b.text, "size": [b.size.x, b.size.y],
					"pos": [b.global_position.x - row.global_position.x,
						b.global_position.y - row.global_position.y]})
		rows.append({
			"row_size": [row.size.x, row.size.y],
			"separation": row.get_theme_constant("separation"),
			"verdict": {} if verdict == null else {
				"text": verdict.text,
				"font_size": verdict.get_theme_font_size("font_size"),
				"color": verdict.modulate.to_html(false),
				"size": [verdict.size.x, verdict.size.y],
				"pos": [verdict.global_position.x - row.global_position.x,
					verdict.global_position.y - row.global_position.y],
			},
			"body": {} if body == null else {
				"text": body.text,
				"font_size": body.get_theme_font_size("font_size"),
				"color": body.modulate.to_html(false),
				"size": [body.size.x, body.size.y],
				"pos": [body.global_position.x - row.global_position.x,
					body.global_position.y - row.global_position.y],
				# WHETHER THE ENGINE WRAPPED THIS PARAGRAPH, and how wide each written line is in
				# the Label's own font. The body is AUTOWRAP_WORD_SMART at PANEL width, so where it
				# wraps is a fact about the font, and a sheet script re-wrapping it in a different
				# font would be drawing a different paragraph while claiming to show this one.
				#
				# So instead of guessing: `line_count` is the engine's count of DRAWN lines and
				# `logical` is the text's own newlines. When they are equal nothing wrapped and
				# drawing the logical lines is exact -- which the sheet asserts rather than assumes.
				# `widths` is each logical line measured in the real font, so an overflow is visible
				# as a number as well as in the picture.
				"logical": body.text.split("\n"),
				"widths": _line_widths(body),
				"line_count": body.get_line_count(),
			},
			"verbs": verbs,
		})
	print("DESIGN_LAYOUT_JSON ", JSON.stringify({
		"rows": rows,
		"panel_px": _screen.PANEL,
		"bench_size": [_screen._bench.size.x, _screen._bench.size.y],
		"clear_color": str(ProjectSettings.get_setting(
			"rendering/environment/defaults/default_clear_color", "UNSET")),
	}))
	print("DESIGN LAYOUT OK")
	return true


## Each written line's width IN THE LABEL'S OWN FONT, which is the only authority on whether a line
## fits the panel. Measured through the same Font resource the Label draws with, not through a
## metric this script chose.
func _line_widths(label: Label) -> Array:
	var out: Array = []
	var f: Font = label.get_theme_font("font")
	var fs: int = label.get_theme_font_size("font_size")
	if f == null:
		return out
	for line in label.text.split("\n"):
		out.append(f.get_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)
	return out


func _buttons_in(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Button:
			found.append(child)
		found.append_array(_buttons_in(child))
	return found
