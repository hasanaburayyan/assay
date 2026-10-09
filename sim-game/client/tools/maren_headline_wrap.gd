extends SceneTree
## CI: local -- an instrument for one ruling (ASSA-272 box 7), not a gate.
##
##   godot --headless --path . --script res://tools/maren_headline_wrap.gd -- <file-of-lines>
##
## **HOW DOES A MINERALOGY HEADLINE BREAK IN ITS OWN COLUMN?** Marlow's `line_width.gd` measures a
## line in the LOG's font (`main.gd::_note`). A proximity answer does not live in the log: it is the
## `headline` Label of a `mineralogy.gd` block, `Heading` variation, AUTOWRAP_WORD_SMART. Measuring
## it with the log's font would be measuring the wrong surface confidently.
##
## **WHY WRAPPED LINES AND NOT PIXELS.** In the log a long line is CUT, so width is the question. In
## the tab it WRAPS, so the cost is vertical: rows of the species index below it. That is the
## currency ASSA-272 is priced in (~90 px of regained index), so this prints line counts and heights.
##
## **THE WIDTH IS QUOTED, NOT COMPUTED, for the reason line_width.gd quotes its two homes:** headless
## has no layout pass, so a width this file computed would be an arithmetic claim about a window
## nobody opened. Three widths are swept instead of one, so the verdict cannot rest on a guess at the
## padding: 318 px is Maren's measured HUD column, 300 and 286 are it less plausible inner padding.
##
## **THE BREAK FLAGS WERE WRONG UNTIL 2026-10-08 AND THAT IS MINE.** This file passed
## `BREAK_WORD_BOUND | BREAK_GRAPHEME_BOUND`, reasoning that `AUTOWRAP_WORD_SMART` is those two
## flags. It is not: `AutowrapMode` and `LineBreakFlag` are different enums (WORD_SMART is 3, that
## pair is 6), and a `Label` on WORD_SMART asks for `MANDATORY | WORD_BOUND | ADAPTIVE |
## TRIM_EDGE_SPACES`. `GRAPHEME_BOUND` is what ARBITRARY wraps with, so the old flags let a break
## land INSIDE a word and so undercounted rows. Measured cost of the bug on ASSA-272's own sentence:
## the reorder reads as 4 rows at 300 px under the old flags and **5 under a Label's**. Every row
## count this tool printed before today is suspect by a row; the unwrapped px are not, since they
## never went through a break.
const WIDTHS: Array[int] = [318, 300, 286]
## What a `Label` set to `AUTOWRAP_WORD_SMART` passes to the text server. Named rather than inlined
## so the next instrument of this family cannot quietly disagree with this one.
const WORD_SMART_BREAKS: int = (
	TextServer.BREAK_MANDATORY
	| TextServer.BREAK_WORD_BOUND
	| TextServer.BREAK_ADAPTIVE
	| TextServer.BREAK_TRIM_EDGE_SPACES
)


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  usage: -- <file-of-lines>")
		quit(1)
		return
	var text := FileAccess.get_file_as_string(String(argv[0]))
	if text == "":
		print("FAIL  could not read %s" % argv[0])
		quit(1)
		return

	# The real screen, so the font comes off the shipped theme's `Heading` and moves with it.
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	var probe := Label.new()
	probe.theme_type_variation = &"Heading"
	probe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screen.add_child(probe)
	# **ASK FOR `Heading` BY NAME; `theme_type_variation` does not reach a QUERY.** Against the
	# PROJECT theme (this client assigns none in the tree) the one-argument form returns
	# `default_font_size` = 13 = `BODY`, while the screen draws the variation's 15 — measured on the
	# real `_log_heading` and in pixels on a shipped 1x frame. This file swept its widths at 13 until
	# 2026-10-09, so every wrap column it has ever reported is ~15% light. See the note in
	# `maren_headline_rows.gd`; `main.gd:2872` has used the two-argument form all along.
	var font: Font = probe.get_theme_font(&"font", &"Heading")
	var size: int = probe.get_theme_font_size(&"font_size", &"Heading")
	var line_h := font.get_height(size)
	print("headline font: %s at %d px (Heading), line height %.1f px" % [font.get_font_name(), size, line_h])
	print("widths swept: %s" % str(WIDTHS))
	print("")

	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line == "":
			continue
		if line.begins_with("#"):
			print(line)
			continue
		var unwrapped := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		var counts := PackedStringArray()
		for w in WIDTHS:
			# get_multiline_string_size wraps the same way a Label does at a given width -- which is
			# true only with the flags a Label actually passes; see WORD_SMART_BREAKS.
			var h := font.get_multiline_string_size(
					line, HORIZONTAL_ALIGNMENT_LEFT, float(w), size,
					-1, WORD_SMART_BREAKS).y
			var rows := int(round(h / line_h))
			counts.append("%d px: %d rows (%d px tall)" % [w, rows, int(round(h))])
		print("%7.1f px unwrapped | %s" % [unwrapped, " · ".join(counts)])
		print("        %s" % line)
	quit(0)
