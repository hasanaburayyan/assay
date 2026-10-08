extends SceneTree
## CI: local -- an instrument for one ruling (ASSA-326), not a gate.
##
##   godot --headless --path . --script res://tools/maren_letter_size_for_hole.gd
##
## **IS THERE ANY SIZE AT WHICH A SPECIES LETTER FITS A MACHINE'S HOLE, and does it clear the floor
## below which a letter stops being a letter?** `maren_hole_vs_letter.gd` answers ASSA-314 box 2 at
## the ONE size the game uses -- `glyph_size_held`, 25 px at the shipped cell -- and the answer there
## is 0 of 26. That is the right instrument for that ruling and it is deliberately left alone.
##
## ASSA-326 asks a different question. A machine has no positive identity on the schematic (ASSA-278
## box 5 failed: two cold readers named zero machines), the identity it most obviously wants is its
## own material's species letter -- `Building.material` is an `Item`, so the species is already a SIM
## fact needing no new rule -- and the only thing said to stop it is that a letter does not fit the
## hole. "Does not fit" was measured at 25 px. **The honest question is whether the letter is dead at
## EVERY size, or only at the deposit's size**, and those are different rulings: the second one costs
## a second letter size in a frame, which is ASSA-293 / my own 11.35 ("one size for every species
## letter in a frame, and it means nothing"), and the first one closes the option outright.
##
## So this sweeps the size down from `glyph_size`'s own ceiling and prints, per size, how many of the
## 26 capitals fit inside `hole_rect` whole -- for both placements, because a 1x1's mark is concentric
## with its tile and a 2x2's sits on the join of four, which pushes a letter further out and not in.
## Geometry, font and arithmetic are the same reads as `maren_hole_vs_letter.gd`: `AssayHud.map_cell`,
## `AssayHud.building_mark`, `main.gd`'s baseline and cap-box, `ThemeDB.fallback_font`.
##
## It reports `glyph_size`'s 10 px FLOOR beside the answer, because a size that fits the hole and is
## under the floor is not an option -- it is the same "worse than no glyph" the floor exists for.
const WORLD := Vector2i(96, 64)
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const FLOOR_PX := 10  # `AssayHud.glyph_size`: below this a letter is a smudge, so it returns 0.


func _initialize() -> void:
	var cell := AssayHud.map_cell(WORLD)
	var shipped := AssayHud.glyph_size_held(cell)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		print("FAIL  no font")
		quit(1)
		return
	print("cell %.1f px · glyph_size_held %d px (the one size a species letter is drawn at today)"
			% [cell, shipped])
	print("font %s · glyph_size floor %d px" % [font.get_font_name(), FLOOR_PX])

	for foot in [Vector2i(1, 1), Vector2i(2, 2)]:
		var tile := Vector2i(56, 36)
		var mark := AssayHud.building_mark(
				{"pos": tile, "footprint": foot, "kind": "drill"}, cell, AssayHud.MARGIN)
		var hole: Rect2 = mark["hole_rect"]
		var at := AssayHud.MARGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * cell
		print("\n%dx%d · mark span %.1f px · hole %.1f x %.1f px · letter offset from the hole %s"
				% [foot.x, foot.y, (mark["span"] as Vector2).x, hole.size.x, hole.size.y,
				at - (mark["at"] as Vector2)])
		var all_fit_at := -1
		for size in range(shipped, 0, -1):
			var ascent := font.get_ascent(size)
			var fits := 0
			var widest := ""
			var widest_px := 0.0
			for i in LETTERS.length():
				var ch := LETTERS[i]
				var measured := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
				var baseline := at + Vector2(-measured.x * 0.5, float(size) * 0.36)
				var box := Rect2(baseline - Vector2(0.0, ascent), Vector2(measured.x, ascent))
				if measured.x > widest_px:
					widest_px = measured.x
					widest = ch
				# WHOLE cap box inside the hole, not merely overlapping it: a letter whose box
				# leaves the hole is drawing on the band, which is what ASSA-314 is about.
				if hole.encloses(box):
					fits += 1
			if fits == LETTERS.length() and all_fit_at < 0:
				all_fit_at = size
			if size == shipped or fits > 0 or size <= FLOOR_PX + 2:
				print("  size %2d px  ascent %5.2f  widest %s %5.2f  fit whole: %d of 26%s"
						% [size, ascent, widest, widest_px, fits,
						"   <- UNDER THE FLOOR" if size < FLOOR_PX else ""])
		if all_fit_at < 0:
			print("  NO SIZE from %d down to 1 fits all 26." % shipped)
		else:
			print("  ALL 26 FIT AT %d px%s" % [all_fit_at,
					"  -- AND IT CLEARS THE %d px FLOOR" % FLOOR_PX if all_fit_at >= FLOOR_PX
					else "  -- BUT IT IS UNDER THE %d px FLOOR, so it is not an option" % FLOOR_PX])
	quit(0)
