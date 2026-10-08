extends SceneTree
## CI: local -- an instrument for one ruling (ASSA-317 §5, the readout sentence), not a gate.
##
##   godot --headless --path . --script res://tools/maren_readout_rows.gd -- <file-of-lines>
##
## **HOW WIDE IS THE SIM'S OWN SENTENCE IN THE SHIPPED BODY FONT.** `design_preview` prints a
## 147-character line (`SAFE · mass 3-75 of 240-360 budget · ...`) and ASSA-305 says it is drawn
## whole, never recomposed and never bracketed. `assay-build-screen` §0 gives block 5 **240 px**
## (x 671..911), not the 304 px of block 3. Those two cannot both hold, and the number that decides
## which gives way has to come off the shipped theme rather than off a character count: this prints
## the one-row width, the row count at every candidate width, and the pixel height those rows eat.
##
## The font is `BODY` (13 px) off the real theme via a plain `Label`, not `Heading` -- the readout is
## a row of numbers, not a section title, and `maren_headline_rows.gd` is the Heading instrument.
const WIDTHS: Array[int] = [240, 288, 431, 687, 847, 863]  # block 5, +pad, half, the commit bar, the screen


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

	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	var probe := Label.new()
	screen.add_child(probe)
	var font: Font = probe.get_theme_font(&"font")
	var size: int = probe.get_theme_font_size(&"font_size")
	var breaks: int = load("res://tools/maren_headline_wrap.gd").WORD_SMART_BREAKS
	var line_h := font.get_height(size)
	print(
		(
			"body font: %s at %d px (plain Label), line height %.2f, break flags %d"
			% [font.get_font_name(), size, line_h, breaks]
		)
	)

	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line == "":
			continue
		if line.begins_with("#"):
			print("\n%s" % line)
			continue
		var one := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		print("  %d chars, one row = %.1f px" % [line.length(), one])
		for w in WIDTHS:
			var para := TextParagraph.new()
			para.break_flags = breaks
			para.add_string(line, font, size)
			para.width = float(w)
			var n := para.get_line_count()
			print("    %4d px -> %d rows, %.0f px tall" % [w, n, n * line_h])
			for i in n:
				var r: Vector2i = para.get_line_range(i)
				print("        [%d] %s" % [i + 1, line.substr(r.x, r.y - r.x)])
	quit(0)
