extends SceneTree
## CI: local -- an instrument for one ruling (ASSA-314 box 2), not a gate.
##
##   godot --headless --path . --script res://tools/maren_hole_vs_letter.gd
##
## **DOES A SPECIES LETTER FIT INSIDE THE MACHINE MARK IT STANDS IN?** ASSA-314 ruled option 1 -- no
## letter on a tile carrying a building mark -- on a hole-fill census (`shared/assay/maren-assa314/
## hole_fill.py`) that classified a shipped frame's PIXELS by colour. Box 2 asks for the same claim
## out of the client's own geometry instead, because a colour threshold is the kind of instrument
## that has lied to me five times this week and the ruling rests on this number.
##
## Everything here is read off the shipped code, nothing is re-derived: `AssayHud.map_cell` for the
## cell, `AssayHud.glyph_size_held` for the letter's size, `AssayHud.building_mark` for the mark and
## its `hole_rect`, and `main.gd`'s own baseline and cap-box arithmetic for the letter's box (the
## ascent above the baseline, the advance across, the descent left out because `symbol` is one
## capital). The font is `ThemeDB.fallback_font`, which is what `main.gd:4583` hands both passes.
##
## THE TWO PLACEMENTS ARE NOT THE SAME CASE. A 1x1's mark centres on its tile, so the letter and the
## hole are concentric. A 2x2 centres on the JOIN of its four tiles, so a letter on any one of them
## sits half a cell up-left of the hole -- which can push the letter further out, not further in.
const WORLD := Vector2i(96, 64)
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


func _initialize() -> void:
	var cell := AssayHud.map_cell(WORLD)
	var size := AssayHud.glyph_size_held(cell)
	var font: Font = ThemeDB.fallback_font
	if font == null or size <= 0:
		print("FAIL  no font or glyph_size_held(%.1f) = %d" % [cell, size])
		quit(1)
		return
	print("cell %.1f px (AssayHud.map_cell on a %dx%d world) · glyph_size_held %d px" %
			[cell, WORLD.x, WORLD.y, size])
	var ascent := font.get_ascent(size)
	print("font %s · ascent %.2f px" % [font.get_font_name(), ascent])

	for foot in [Vector2i(1, 1), Vector2i(2, 2)]:
		var tile := Vector2i(56, 36)
		var mark := AssayHud.building_mark(
				{"pos": tile, "footprint": foot, "kind": "drill"}, cell, AssayHud.MARGIN)
		var hole: Rect2 = mark["hole_rect"]
		# `main.gd`'s own letter geometry: `point_of_tile` on the schematic, then its baseline.
		var at := AssayHud.MARGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * cell
		print("\n%dx%d at %s · mark span %.1f px · hole %.1f x %.1f px · letter tile offset %s" %
				[foot.x, foot.y, tile, (mark["span"] as Vector2).x, hole.size.x, hole.size.y,
				at - (mark["at"] as Vector2)])
		var worst_in := 101.0
		var worst_letter := ""
		var fits := 0
		for i in LETTERS.length():
			var ch := LETTERS[i]
			var measured := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
			var baseline := at + Vector2(-measured.x * 0.5, float(size) * 0.36)
			var box := Rect2(baseline - Vector2(0.0, ascent), Vector2(measured.x, ascent))
			var over := box.intersection(hole)
			var box_area := box.size.x * box.size.y
			var inside := 0.0 if over.size.x <= 0.0 or over.size.y <= 0.0 \
					else (over.size.x * over.size.y) / box_area * 100.0
			var hole_area := hole.size.x * hole.size.y
			var covered := 0.0 if over.size.x <= 0.0 or over.size.y <= 0.0 \
					else (over.size.x * over.size.y) / hole_area * 100.0
			if box.size.x <= hole.size.x and box.size.y <= hole.size.y:
				fits += 1
			if inside < worst_in:
				worst_in = inside
				worst_letter = ch
			if i < 4 or ch == "M" or ch == "I":
				print("  %s  cap box %5.2f x %5.2f  inside the hole %5.1f%%  covers the hole %5.1f%%"
						% [ch, box.size.x, box.size.y, inside, covered])
		print("  LETTERS WHOSE WHOLE CAP BOX FITS INSIDE THE HOLE: %d of %d (worst %s, %.1f%% inside)"
				% [fits, LETTERS.length(), worst_letter, worst_in])
	quit(0)
