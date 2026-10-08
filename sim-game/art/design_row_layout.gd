extends SceneTree
## WHAT DOES A DESIGN ROW REALLY LOOK LIKE, laid out by the real screen? (ASSA-83, ASSA-173)
##
##   godot [--headless] --path client --script "$PWD/art/design_row_layout.gd" -- designs.json [seed]
##
## **THE CAUSE IS A HIDDEN SUBTREE. `--headless` IS FINE *FOR WHAT THIS FILE MEASURES*, AND THAT
## QUALIFIER IS LOAD-BEARING — I LEFT IT OUT ONCE AND IT WAS THE SAME MISTAKE AGAIN.**
##
## The rule is not "headless lays out" or "headless does not". It is **where a size COMES FROM**:
##
##   - **CONTENT-DERIVED sizes survive headless.** A `VBoxContainer` sizes itself from its children's
##     minimums and a `Label` wraps against the width it is given, so the bench's `[300, 141]` and
##     `line_count 4` are the same windowed or not. Everything this file reports is of that kind.
##   - **WINDOW-DERIVED sizes do NOT.** Headless there is no window -- this script prints
##     `window (0, 0)` -- so anything measured off the viewport reads 0. Run
##     `tools/nacre_tab_budget_probe.gd --headless` and its CLIP comes back **0 px at every tick**,
##     so every tab reads "BELOW THE FOLD" and it exits 1. Its header says headless has no layout
##     pass; the mechanism in that sentence is wrong and **its conclusion is right for that tool**,
##     because the clip is the scroll box's share of the window.
##
## So: this probe may be re-asked headless, which is what CI can run. A probe measuring the fold may
## not. Do not carry either verdict across to the other.
##
## I got this wrong in the first version of this header and in #361's own title, so the correction is
## here rather than in a commit nobody re-reads. What I saw was real: the bench reported `size [0,0]`,
## a row `[1, 18]`, and `Label.get_line_count()` answered **98 drawn lines for a four-line
## paragraph**, because a label with no width wraps after every word. `design_row_sheet.py` refuses
## that dump by name, rightly. **I attributed it to `--headless` and to the hidden column both, and
## the two were confounded in every run I had: the column is hidden until a world runs, so I never
## once measured headless WITH a world up.**
##
## Measured since, same script, same world started, the only difference the flag:
##
##     windowed    bench [300, 141]   line_count 4   body [300, 81]
##     --headless  bench [300, 141]   line_count 4   body [300, 81]     byte-identical
##
## So Godot lays out headless perfectly well. The real and sufficient cause was that `main.gd` builds
## the whole HUD column hidden (`_column.visible = false`) and shows it only once a world is running
## -- the same rule ASSA-231 holds the join screen to -- and since the tabbed panel landed, a tab's
## body is hidden too unless it is the selected one. A hidden control has no width, which produces
## every symptom above. **One cause, three doors into it.**
##
## This matters beyond tidiness: `art/ask_layout.py::ask_the_engine` re-asks a probe with
## `--headless`, because that is what CI can run. A probe that genuinely needed a window could never
## be re-asked, and I nearly wrote that impossibility down as a fact about this one.
##
## So a world is started here before anything is measured, offline, with no socket and no relay
## (`_begin_offline`), and the bench's tab is selected. The designs still come from the dump and not
## from that world: the world exists to make the column real, and `_rebuild_bench` puts the dump's
## designs into it.
##
## **AND THE TRAP IS A REFUSAL, NOT A WARNING.** A measurement taken off a tree that never laid out is
## not a worse number; it is a different kind of thing, and it reads as data to everything
## downstream. `_refuse_if_unlaid` ends the run and names the causes, so the next person meets a
## sentence instead of a dump that looks fine. `window_shot.gd` and `tools/nacre_tab_budget_probe.gd`
## carry this as a warning in their headers; a warning is what the last two were.
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
## The two labels in a bench row, named as `main.gd` names them (`BENCH_VERDICT` / `BENCH_BODY`).
## Spelled rather than imported because `main.gd` is a scene script, not a class_name.
const VERDICT_NAME := "BenchVerdict"
const BODY_NAME := "BenchBody"

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
## **THE INK A LABEL IS ACTUALLY DRAWN IN, WHICH IS NOT `modulate` AND HAS NOT BEEN FOR A WHILE.**
##
## This read `modulate` until 2026-10-07, and `modulate` is now WHITE on every bench label, so the
## dump reported `ffffff` for SAFE, UNCERTAIN and WILL BREAK alike -- one colour for the three words
## whose difference is the entire question Decision #38 asks of this sheet. Measured, not guessed:
## tonight's dump came back `SAFE ffffff` while `AssayHud.verdict_color("SAFE")` is (0.55,0.82,0.60).
##
## The client moved deliberately and wrote down why (`main.gd::_write_design`): `modulate` MULTIPLIES
## the theme's ink, so the word was drawn in `verdict_color` times `INK` and the colour on screen was
## nobody's decision. It uses `add_theme_color_override(&"font_color", ...)` now. **A probe that reads
## the field the surface it measures has abandoned does not go red -- it goes WHITE, and keeps
## drawing.** `get_theme_color` returns a node's own override when it has one, so this follows the
## client wherever the colour is set rather than naming a mechanism that can move again.
func _ink_of(label: Label) -> String:
	return label.get_theme_color("font_color").to_html(false)


func _refuse_if_unlaid(bench: Control) -> bool:
	if bench.size.x > 1.0 and bench.size.y > 1.0:
		return false
	print("FAIL  the bench laid out %.0f x %.0f px, so nothing in it has a real width."
			% [bench.size.x, bench.size.y])
	print("      Every wrap count and every rect in this dump would be a fact about an unlaid tree,")
	print("      and it would read as data to the sheet. ONE CAUSE, THREE DOORS INTO IT: a control")
	print("      that is HIDDEN has no width, and a label with no width wraps after every word.")
	print("      1. the HUD column is built hidden and shown only once a world runs")
	print("         (main.gd `_column.visible = false`), so `_begin_offline` must have succeeded.")
	print("      2. a tab's body is hidden unless it is the selected one -- select `bench`.")
	print("      3. the bench itself is empty, so there is nothing to lay out.")
	print("      NOT a cause: `--headless`. Everything this probe reports is CONTENT-derived, and")
	print("      that was measured byte-identical both ways once a world was up. (A WINDOW-derived")
	print("      size is the other story: headless there is no window, so a fold/clip measurement")
	print("      reads 0 -- see nacre_tab_budget_probe.) The first version of this list blamed")
	print("      headless outright and was wrong.")
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
		# **WHICH RUN THIS ROW IS A PICTURE OF, carried from the dump entry that built it.**
		# A sheet may merge two runs -- SAFE from the plain loop, UNCERTAIN from `hold-assay` --
		# and the dump has ONE `tick` and ONE `hash` for the lot, so those fields named the
		# showcase run and lied about the other row. Maren on this item, 06:01: "a sheet that
		# cannot say which client each row reviews is ASSA-144 with the names changed." So
		# provenance rides the DESIGN and reaches the sheet per row.
		#
		# BY POSITION, and the refusal after this loop is what buys that: `_rebuild_bench`
		# builds one row per design in order, so the pairing is a contract this function can
		# check in full rather than an assumption about a scene someone else edits. Inside a
		# row it is still `find_child` by name (ASSA-117); that has not changed.
		var source: Variant = {}
		if rows.size() < _designs.size():
			source = (_designs[rows.size()] as Dictionary).get("source", {})
		# **BY NAME, NOT BY CHILD INDEX, and the client learned this the expensive way first.**
		# `main.gd::_write_design` reads these two with `find_child(BENCH_VERDICT/BENCH_BODY)` and says
		# why in its own comment: they *were* `get_child(0)` and `get_child(1)`, and adding a sprite to
		# a row made child 0 a `TextureRect`, so the re-text silently stopped finding its label
		# (ASSA-117). A bench row is the next surface Maren's icon ruling reaches. This file was still
		# counting children, so the day that icon lands this probe would not have gone red -- it would
		# have reported the ICON's rect as the verdict's and drawn a sheet from it.
		var verdict := row.find_child(VERDICT_NAME, true, false) as Label
		var body := row.find_child(BODY_NAME, true, false) as Label
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
				"color": _ink_of(verdict),
				"size": [verdict.size.x, verdict.size.y],
				"pos": [verdict.global_position.x - row.global_position.x,
					verdict.global_position.y - row.global_position.y],
			},
			"body": {} if body == null else {
				"text": body.text,
				"font_size": body.get_theme_font_size("font_size"),
				"color": _ink_of(body),
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
			"source": source,
		})
	# THE PAIRING IS CHECKED, NOT TRUSTED. If the bench ever stops being one row per design
	# -- a header child, a filtered row, a design the client declines to show -- then every
	# `source` above is attached to the wrong row and the sheet would stamp confident
	# provenance onto the wrong picture. That is worse than no provenance, so it refuses.
	if rows.size() != _designs.size():
		print("FAIL  the bench laid out %d row(s) for %d design(s), so this script cannot say"
				% [rows.size(), _designs.size()])
		print("      which run each row came from. `_rebuild_bench` is no longer one row per")
		print("      design; pair them by something other than order before drawing a sheet.")
		quit(1)
		return true
	var ground := _ground_behind(bench)
	print("DESIGN_LAYOUT_JSON ", JSON.stringify({
		"rows": rows,
		"panel_px": _screen.PANEL,
		"bench_size": [bench.size.x, bench.size.y],
		"clear_color": str(ProjectSettings.get_setting(
			"rendering/environment/defaults/default_clear_color", "UNSET")),
		"ground": ground["colour"],
		"ground_from": ground["from"],
	}))
	print("DESIGN LAYOUT OK")
	return true


## **THE COLOUR ACTUALLY BEHIND THE ROW, ASKED OF THE BUILT TREE** (ASSA-308; same shape as
## ASSA-152's "the surface actually behind a label").
##
## **WHAT THIS REPLACES AND WHY IT WAS WRONG.** The sheet used to paint its ground from this dump's
## `clear_color` — the VIEWPORT's clear colour, Godot's default 0.3 grey, `(76,76,76)`. That is what
## sits behind *everything*, and in the shipped client it is COVERED: a bench row lives inside a
## panel whose `StyleBoxFlat` fills `SURFACE` `(37,40,48)`. So the sheet painted the layer furthest
## back instead of the one under the text, and Maren caught it by measuring the PNG:
## **`INK_MUTED` ships at 6.74:1 and read 3.92:1 on the sheet** — under the 4.5:1 floor
## `build_theme.gd` refuses to ship. A reviewer judging legibility off that sheet judges a screen we
## do not ship, and judges it WORSE than it is, which invites a retune of a palette that was fine.
##
## Note the shape of the original defect: it was not a typed literal, it was a DERIVATION POINTED
## ONE LAYER TOO DEEP. The fix is to aim it, not to replace it with `(37,40,48)` — a literal here
## would be a colour nobody chose (ASSA-233) and would not follow a retune.
##
## **IT RETURNS WHERE IT GOT THE ANSWER, AND THE SHEET PRINTS THAT.** A fallback that quietly hands
## back the clear colour is exactly how the wrong ground shipped for days, so `from` is part of the
## answer rather than a detail: the sheet says on its face which layer it painted.
func _ground_behind(node: Control) -> Dictionary:
	var at: Node = node
	while at != null:
		# `Panel` and `PanelContainer` are the two that FILL in this client. A plain container draws
		# nothing, so walking past it is correct rather than lossy.
		if at is Panel or at is PanelContainer:
			var box := (at as Control).get_theme_stylebox("panel") as StyleBoxFlat
			if box != null:
				return {"colour": str(box.bg_color),
						"from": "%s/panel bg_color" % (at as Node).name}
		at = at.get_parent()
	return {"colour": str(ProjectSettings.get_setting(
			"rendering/environment/defaults/default_clear_color", "UNSET")),
			"from": "NO PANEL ANCESTOR -- the viewport clear colour, which the client covers"}


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
