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
	quit()


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
