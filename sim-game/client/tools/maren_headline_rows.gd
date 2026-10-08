extends SceneTree
## CI: local -- an instrument for one ruling (ASSA-272 box 7), not a gate.
##
##   godot --headless --path . --script res://tools/maren_headline_rows.gd -- <file-of-lines>
##
## **WHERE DOES A MINERALOGY HEADLINE BREAK, not just how many times.** `maren_headline_wrap.gd`
## answers the vertical cost (rows, and the species index they push down). It cannot answer the
## question ASSA-272 box 7 actually turns on: a merged answer is `reading · verdict · reading ·
## verdict`, and **a row break landing between a reading and the verdict it earns separates them on
## screen even though the byte order is right.** Identical row COUNTS before and after a reorder say
## nothing about that -- the same four rows can cut the pairs in different places. So this prints
## each row's own text, and the ruling is made on the rows rather than on the sentence.
##
## WHAT IT FOUND, kept here because it is the reason the file exists: on the demo seed at the
## measured 318 px column the reorder moves the cut from `reactivity · hardness · fuel at` (two
## readings, then a verdict orphaned onto the next row) to `reactivity 51-75 · fuel at C or better,
## lights` -- each reading now begins its row WITH the verdict it earns. The reorder costs a row only
## at a wrap width of 299-300 px; at 301+ and at 298- both orders wrap identically.
##
## Flags come from `maren_headline_wrap.gd`'s `WORD_SMART_BREAKS` so the two instruments of this
## family cannot disagree about the surface -- which they did until 2026-10-08, when that file was
## passing `GRAPHEME_BOUND` and breaking inside words.
const WIDTHS: Array[int] = [318, 300, 286]


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
	screen.add_child(probe)
	var font: Font = probe.get_theme_font(&"font")
	var size: int = probe.get_theme_font_size(&"font_size")
	var breaks: int = load("res://tools/maren_headline_wrap.gd").WORD_SMART_BREAKS
	print("headline font: %s at %d px (Heading), break flags %d" % [font.get_font_name(), size, breaks])

	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line == "":
			continue
		if line.begins_with("#"):
			print("\n%s" % line)
			continue
		for w in WIDTHS:
			var para := TextParagraph.new()
			para.break_flags = breaks
			para.add_string(line, font, size)
			para.width = float(w)
			print("  %d px -> %d rows" % [w, para.get_line_count()])
			for i in para.get_line_count():
				var r: Vector2i = para.get_line_range(i)
				print("    [%d] %s" % [i + 1, line.substr(r.x, r.y - r.x)])
	quit(0)
