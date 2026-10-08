extends SceneTree
## WHAT DOES A DESIGN ROW REALLY LOOK LIKE, laid out by the real screen? (ASSA-83, ASSA-173)
##
##   godot --path client --script "$PWD/art/design_row_layout.gd" -- /tmp/designs.json [seed]
##
## **NOT `--headless`, AND THAT IS WHAT CHANGED HERE** (ASSA-173). This script ran headless from the
## day it was written, and headless there is no layout pass: the bench reports `size [0, 0]`, a row
## reports `[1, 18]`, and `Label.get_line_count()` answers **98 drawn lines for a four-line
## paragraph**, because a Label with no width wraps after every word. `design_row_sheet.py` refuses
## that dump by name -- rightly, since it would draw the paragraph broken where the client does not
## break it -- so for as long as this ran headless NOBODY could redraw `design_rows.png`, with or
## without the live relay the old header blamed for it. The font widths below were the only honest
## numbers in the dump, because font measurement works headless and layout does not.
##
## `window_shot.gd` and `tools/nacre_tab_budget_probe.gd` both carry a warning about this trap in
## their headers. This file is the third, and a header is where the last one was.
##
## **SO THE TRAP IS A REFUSAL NOW, NOT A WARNING.** A measurement taken off a tree that never laid
## out is not a worse number; it is a different kind of thing, and it reads as data to everything
## downstream. `_refuse_if_unlaid` ends the run and names the cause, so the next person meets a
## sentence instead of a dump that looks fine.
##
## **AND LEAVING `--headless` WAS NOT ENOUGH, WHICH THE REFUSAL IS HOW I FOUND OUT.** The first real
## window run still reported the bench at **1 x 900 px**, because `main.gd:1004` builds the whole HUD
## column hidden (`_column.visible = false`) and only shows it once a world is running -- the same
## rule ASSA-231 holds the join screen to. This script used to push designs into a bench that was
## inside a hidden column, so there was a SECOND reason every number in the dump was fiction, and it
## would have survived the move to a window untouched. So a world is started here before anything is
## measured, offline, with no socket and no relay (`_begin_offline`, lifted from
## `tools/maren_tab_shots.gd`). The designs still come from the dump and not from that world: the
## world exists to make the column real, and `_rebuild_bench` then puts the dump's designs in it.
##
## THE DESIGNS ARE THE WORLD'S, NOT MINE. `client/tools/button_session.gd -- offline <seed>
## designs=<path>` writes this file's input from the offline loop (ASSA-173 slice 1, #357); the older
## `bench_read.gd` dumps the same shape off a live relay. Nothing here invents a verdict, a mass or a
## budget, and nothing here decides a colour: the verdict's colour is read back off the Label the
## client built, so if `AssayHud.verdict_color` changed tomorrow this picture would change with it.
##
## ONE CONVERSION, AND IT IS A REAL RISK rather than a formality. `AssayHud.design_lines` reads
## `unassayed` as a `PackedStringArray`, and JSON gives back a plain `Array` -- `as PackedStringArray`
## on an Array does not convert, it fails, so the "assay X to know" line would silently vanish. That
## line is the whole content of an UNCERTAIN row, so a picture missing it would be a picture of the
## wrong panel. Converted explicitly below, and the rendered text is checked against what the live
## probe printed.
##
## Prints `DESIGN_LAYOUT_JSON <...>` and then `DESIGN LAYOUT OK` last.

## The rebuild needs the screen to exist; the measurement needs the rebuild to have been laid out.
## Containers lay out on FRAMES, not on time, so these are frame counts and not a wait.
const REBUILD_FRAME := 2
const MEASURE_FRAME := 8
## The world the column is made real with. Its contents never reach the picture -- the designs come
## from the dump -- so this is only ever "a world that runs", and the demo seed is as good as any.
const DEFAULT_SEED := "14247"

var _screen: Node = null
var _frames := 0
var _designs: Array = []
var _seed := DEFAULT_SEED


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  usage: -- <designs.json from button_session.gd designs= or bench_read.gd>")
		quit(1)
		return
	var text := FileAccess.get_file_as_string(String(argv[0]))
	if text.is_empty():
		print("FAIL  could not read %s" % argv[0])
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not (parsed as Dictionary).has("designs"):
		print("FAIL  %s is not a bench dump" % argv[0])
		quit(1)
		return
	for entry in (parsed as Dictionary)["designs"]:
		_designs.append(_retyped(entry as Dictionary))
	# **THE DUMP'S OWN `seed` IS DELIBERATELY NOT USED, and that is worth a sentence because reaching
	# for it is the obvious move.** I wrote that version first: the world and the designs should not
	# be able to disagree about which world they are from. It refused itself on the first run --
	# `could not make a world on seed 00000000000037a7` -- because seeds cross into GDScript as HEX
	# TEXT (repo CLAUDE.md) and `fresh_welcome_json` wants the decimal string. Converting would mean
	# a u64 through GDScript's signed int64 for no gain in the picture: the designs are the dump's
	# and are rebuilt into the bench, so this world's only job is to make the column visible.
	if argv.size() > 1:
		_seed = String(argv[1])
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, for the reason `tools/window_shot.gd` and `tools/button_session.gd` both
	# give: a `--script` run works inside `SceneTree._initialize`, before the root window is in the
	# tree, so the engine's own call comes too late. The screen is built once however often.
	_screen._ready()
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])
	if not _begin_offline():
		return


## OFFLINE: THIS SCRIPT IS THE RELAY (`tools/maren_tab_shots.gd::_begin_offline`, lifted whole).
##
## Not a nicety: the HUD column is built hidden and only shown once a world runs (`main.gd:1004`,
## `_column.visible = false`), so without this the bench is measured inside a hidden subtree and
## every rect in the dump is a fact about nothing. No socket is opened and no relay is contacted.
func _begin_offline() -> bool:
	var welcome := AssaySimHost.fresh_welcome_json(_seed, "art")
	if welcome == "":
		print("FAIL  could not make a world on seed %s" % _seed)
		quit(1)
		return false
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		print("FAIL  offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		quit(1)
		return false
	return true


## A design dictionary with the types the client expects, after a JSON round trip.
func _retyped(design: Dictionary) -> Dictionary:
	var out := design.duplicate(true)
	var names := PackedStringArray()
	for n in design.get("unassayed", []):
		names.append(String(n))
	out["unassayed"] = names
	return out


## **THE BENCH HAS TO BE ON SCREEN BEFORE IT CAN BE MEASURED**, and once the tabbed panel lands it is
## not on screen by default: a hidden child contributes nothing to a container and keeps whatever
## rect it last had, which is the SAME wrong answer `--headless` gives and is just as quiet. If the
## screen has a tab strip, open the bench tab; if it has not, this is a no-op and nothing here has
## guessed at an API that does not exist yet.
func _show_bench() -> void:
	if not ("_tabs" in _screen):
		return
	var tabs: Object = _screen._tabs
	if tabs == null or not tabs.has_method("select"):
		return
	if not tabs.select("bench"):
		print("WARN  the strip refused the 'bench' tab; measuring whatever is open")


## **THE ONE CHECK THAT MAKES THIS DUMP EVIDENCE.** Every number below comes from a laid-out tree or
## from none at all, so this asks the engine for the two that cannot be anything but zero when no
## layout pass ran, and ends the run naming the cause. Returns true when it refused.
func _refuse_if_unlaid(bench: Control) -> bool:
	if bench.size.x > 1.0 and bench.size.y > 1.0:
		return false
	print("FAIL  the bench laid out %.0f x %.0f px, so nothing in it has a real width."
			% [bench.size.x, bench.size.y])
	print("      Every wrap count and every rect in this dump would be a fact about an unlaid tree,")
	print("      and it would read as data to the sheet. The known causes, in the order they bit:")
	print("      1. `--headless`: no layout pass runs at all. Run this WITHOUT it.")
	print("      2. the HUD column is hidden until a world runs (main.gd `_column.visible = false`),")
	print("         so a visible window is not enough -- `_begin_offline` must have succeeded.")
	print("      3. after the tabbed panel lands, the bench is also hidden unless its tab is open.")
	print("      column visible: %s" % (_screen._column.visible if "_column" in _screen else "?"))
	quit(1)
	return true


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == REBUILD_FRAME:
		_screen._rebuild_bench(_designs)
		_show_bench()
		return false
	if _frames < MEASURE_FRAME:
		return false
	var bench: Control = _screen._bench
	if _refuse_if_unlaid(bench):
		return true
	var rows: Array = []
	for child in bench.get_children():
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
				#
				# THIS PAIR IS ALSO THE REASON THIS SCRIPT LEFT `--headless`: with no layout pass
				# `line_count` came back 98 against 4 logical lines and the sheet refused the dump.
				"logical": body.text.split("\n"),
				"widths": _line_widths(body),
				"line_count": body.get_line_count(),
			},
			"verbs": verbs,
		})
	print("DESIGN_LAYOUT_JSON ", JSON.stringify({
		"rows": rows,
		"panel_px": _screen.PANEL,
		"bench_size": [bench.size.x, bench.size.y],
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
