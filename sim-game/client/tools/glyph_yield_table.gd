extends SceneTree
## **WHAT A SPECIES LETTER STILL COVERS OF A MACHINE'S MARK, TILE BY TILE** (ASSA-273).
##
##   $GODOT --headless --path client --script res://tools/glyph_yield_table.gd
##
## **WHY THIS EXISTS: MAREN'S RULING SAYS RING 1 AND RING 1 CANNOT WORK.** Her build note is
## *"candidates are the patch's own tiles at ring 1 in a fixed order, first one no building mark
## laps"*, priced at *"about 3.5 px of letter past its own colour"*. Both assume one tile of travel
## separates the glyph from the mark. The glyph's cap box is 23-25 px wide and 27-35 px tall at a 9 px
## cell, against a 16 px mark, so it cannot: this table is the arithmetic, done by the painter's own
## functions instead of by me.
##
## **IT IS A REPLICA AND SAYS SO.** The marks come from `AssayHud.building_mark` and the glyph boxes
## from the same measure-and-centre arithmetic `main.gd::_glyph_box` uses, at the shipped cell and
## margin, with the engine's fallback font -- the one the client draws with. What it CANNOT see is
## ink, antialiasing or the bed's eight stamps. A real window is the proof; this is the lever for
## choosing (ASSA-278's own method note).
const CELL := 9.0
const ORIGIN := Vector2(24.0, 24.0)


func _initialize() -> void:
	var font := ThemeDB.fallback_font
	var tile := Vector2i(11, 6)
	print("ASSA-273  a 1x1 machine on a letter's own tile, cell %.0f px, mark %.0f px, keyline %.0f"
			% [CELL, AssayHud.BUILDING_MARK_PX, AssayHud.MARK_KEYLINE_PX])
	var mark := AssayHud.building_mark({"pos": tile, "footprint": Vector2i(1, 1)}, CELL, ORIGIN)
	var band := AssayHud.polygon_area(mark["points"]) - AssayHud.polygon_area(mark["hole_points"])
	for radius: int in [2, 3, 4]:
		var size := AssayHud.glyph_size(maxf(CELL, float(radius) * CELL))
		var box := _box(tile, "M", size, font)
		print("")
		print("  RADIUS %d PATCH: glyph size %d, cap box %.0f x %.0f px, disc radius %.0f px"
				% [radius, size, box.size.x, box.size.y, float(radius) * CELL])
		print("    tile        d2   lapped px   share of the mark's %3.0f px band   past the disc"
				% band)
		for candidate: Vector2i in _walk(tile, radius):
			var here := _box(candidate, "M", size, font)
			var covered := _lap(mark, here)
			var step := candidate - tile
			var d2 := step.x * step.x + step.y * step.y
			# HOW FAR THE CAP BOX REACHES FROM THE PATCH'S CENTRE, against the disc that coloured the
			# ink: Maren's overhang number, computed per candidate instead of once for one tile.
			var centre := ORIGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * CELL
			var reach := 0.0
			for corner in AssayHud.rect_points(here):
				reach = maxf(reach, (corner as Vector2).distance_to(centre))
			print("    %-10s %3d %10.1f %28.1f%% %14.1f px"
					% [str(candidate), d2, covered, 100.0 * covered / maxf(band, 1.0),
					maxf(0.0, reach - float(radius) * CELL)])
	_option_one(tile, font)
	quit()


## **OPTION 1'S ARITHMETIC, DONE BEFORE BUILDING IT** (Maren, 06:57 UTC: option 3 is dead and *"the
## frame grows to enclose the letter's cap box when it laps one"*, with *"the frame's POSITION is the
## claim; its HOLE is not"*).
##
## **SO THE GROWTH HAS TO BE SYMMETRIC ABOUT THE FOOTPRINT'S CENTRE, and that is what sets the price.**
## If the frame grew only on the side the letter is on, its centre would leave the tiles it names, and
## ASSA-213 lets a mark lie about SIZE and never about POSITION -- the clause her own ruling rests on.
## Symmetric growth costs double: the span is set by the FARTHEST corner of the cap box, mirrored.
##
## For the box to sit in the HOLE rather than under the band, the clear half-width must reach the
## box's farthest corner on each axis, plus the band and the inward rim:
##
##   span = 2 * (max(|dx|, |dy|) over the cap box's corners  +  BUILDING_STROKE_PX + MARK_KEYLINE_PX)
##
## It reports the span in TILES as well as pixels, because that is the question Maren put her ruling
## at risk on: *"what would prove me wrong is a cold reader who says the machine covers more tiles
## than it does."* And it reports whether the GROWN frame reaches the next tile's letter, because a
## growth that creates a new lap is either a second round of growth or a rule that stops -- which is a
## decision and not an implementation detail.
func _option_one(tile: Vector2i, font: Font) -> void:
	var centre := ORIGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * CELL
	var clearance := AssayHud.BUILDING_STROKE_PX + AssayHud.MARK_KEYLINE_PX
	print("")
	print("  OPTION 1: GROW THE FRAME TO PUT THE CAP BOX IN ITS HOLE, centre fixed on the footprint")
	print("    mark today %.0f px (%.2f tiles), band %.0f + rim %.0f, so the hole needs %.0f px of"
			% [AssayHud.BUILDING_MARK_PX, AssayHud.BUILDING_MARK_PX / CELL,
			AssayHud.BUILDING_STROKE_PX, AssayHud.MARK_KEYLINE_PX, clearance]
			+ " clearance a side")
	print("    patch  glyph  cap box      reach from centre   span needed   in tiles   vs today")
	for radius: int in [2, 3, 4]:
		var size := AssayHud.glyph_size(maxf(CELL, float(radius) * CELL))
		var box := _box(tile, "M", size, font)
		var reach_x := 0.0
		var reach_y := 0.0
		for corner in AssayHud.rect_points(box):
			var point: Vector2 = corner
			reach_x = maxf(reach_x, absf(point.x - centre.x))
			reach_y = maxf(reach_y, absf(point.y - centre.y))
		var span := 2.0 * (maxf(reach_x, reach_y) + clearance)
		print("    r%d     %4d   %.0f x %-5.0f  x %5.1f  y %5.1f px   %8.1f px %8.2f   x%.2f"
				% [radius, size, box.size.x, box.size.y, reach_x, reach_y, span, span / CELL,
				span / AssayHud.BUILDING_MARK_PX])
		# **AND DOES THE GROWN FRAME THEN LAP THE NEXT TILE'S LETTER?** One step east is the nearest
		# other letter a patch can have; if the grown frame reaches that box too, option 1 either
		# iterates or needs a stopping rule, and the arithmetic should say which before anyone builds.
		var grown := Rect2(centre - Vector2(span, span) * 0.5, Vector2(span, span))
		var neighbour := _box(tile + Vector2i(1, 0), "M", size, font)
		var reaches := grown.intersects(neighbour)
		print("        a letter one tile east: the grown frame %s it (%s)"
				% ["LAPS" if reaches else "clears",
				"so growing creates a new lap and needs a stopping rule" if reaches
				else "one pass is enough at this radius"])


## Home first, then the candidate order the painter walks.
func _walk(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [centre]
	out.append_array(AssayHud.glyph_yield_candidates(centre, radius))
	return out


## `main.gd::_glyph_box`'s arithmetic. Copied rather than called because a `SceneTree` tool has no
## screen to ask, and kept to five lines so the copy is checkable by eye against that function.
func _box(tile: Vector2i, symbol: String, size: int, font: Font) -> Rect2:
	var at := ORIGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * CELL
	var measured := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var baseline := at + Vector2(-measured.x * 0.5, float(size) * 0.36)
	return Rect2(baseline - Vector2(0.0, font.get_ascent(size)),
			Vector2(measured.x, font.get_ascent(size)))


## `letter_occlusions`' own answer for one box against one mark.
func _lap(mark: Dictionary, box: Rect2) -> float:
	var total := 0.0
	for raw in AssayHud.letter_occlusions([mark], [{"box": box, "symbol": "M"}]):
		total += float((raw as Dictionary)["covered_px"])
	return total
