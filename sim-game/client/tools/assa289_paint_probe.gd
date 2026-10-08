extends SceneTree
## CI: local -- a pixel replica of one paint loop, for a number no assertion wants; read by a person
## **WHAT A NEIGHBOUR'S MARK ACTUALLY DELETES, PIXEL BY PIXEL, THROUGH THE REAL PAINT SEQUENCE**
## (ASSA-289 box 5).
##
##   $GODOT --headless --path client --script res://tools/assa289_paint_probe.gd
##
## **WHY IT EXISTS: EVERY NUMBER ON ASSA-289 SO FAR, MINE AND MAREN'S, COUNTS GEOMETRIC OVERLAP AND
## CALLS IT DELETION.** Her probe said a younger machine's keyline covers 28.1% of an older
## machine's band; mine said that at the shipped `BUILDING_MARK_PX` of 20 the younger machine's
## *band* covers 27.8%. Both are rect intersections. A band pixel is only LOST if the last thing
## painted on it is dark, and `AssayHud.MAP_MARKS` gives `building` and `building_keyline` no alpha
## at all -- so white over white is not a loss and dark over white is. **Overlap is a proxy for
## deletion and I shipped a comment built on the proxy.**
##
## So this paints. One dictionary of pixel -> ink, the three `draw_rect` loops of
## `main.gd::_draw_buildings` in their exact order and at their exact rects, and then it asks each
## mark's own band pixels what colour they ended up. Two sequences, so the fix is measured and not
## argued:
##
## - **ONE PASS** (main before #421): per building, keyline bands, then band, then the inner rim.
## - **TWO PASSES** (#421, Maren's rule 11.39): every building's keyline band, then per building the
##   band and the inner rim.
##
## **AND IT REPORTS THE LONGEST UNBROKEN RUN PER SIDE, NOT ONLY A COUNT** (ASSA-273's lesson: for a
## band the statistic is the longest run; mass is for a blob). A side that keeps 90% of its pixels in
## nine two-pixel scraps is not a side.
##
## NO WINDOW AND NO WORLD. `building_mark` is a pure function of pos, footprint, cell and origin, and
## `frame_bands` and `mark_ink_of` are pure too. What this therefore CANNOT say is whether the
## surviving band READS at 1x; that is a window shot's question (box 2's).

const CELL := 9.0
const GROUND := &"ground"
const BAND := &"band"
const DARK := &"dark"


func _initialize() -> void:
	print("ASSA-289  what a neighbour DELETES, through the real paint sequence")
	print("  BUILDING_MARK_PX %.0f, MARK_KEYLINE_PX %.0f, BUILDING_STROKE_PX %.0f, cell %.0f"
			% [AssayHud.BUILDING_MARK_PX, AssayHud.MARK_KEYLINE_PX, AssayHud.BUILDING_STROKE_PX,
			CELL])
	print("  a band pixel is LOST only if the last ink on it is dark; both inks are alpha 1.0")
	for case: Array in _cases():
		_case(String(case[0]), case[1], case[2], case[3])
	quit()


## Every adjacency a player can build, plus a control that is not adjacent at all. The control is
## the baseline: a lone mark's band is what "all four bands intact" means, and without it a count of
## surviving pixels has nothing to be a share OF.
func _cases() -> Array:
	var out: Array = []
	for foot: Vector2i in [Vector2i(1, 1), Vector2i(2, 2)]:
		var step := maxi(foot.x, foot.y)
		out.append(["%dx%d side by side" % [foot.x, foot.y], foot, Vector2i(54, 56),
				Vector2i(54 + step, 56)])
		out.append(["%dx%d one above the other" % [foot.x, foot.y], foot, Vector2i(54, 56),
				Vector2i(54, 56 + step)])
		out.append(["%dx%d corner to corner" % [foot.x, foot.y], foot, Vector2i(54, 56),
				Vector2i(54 + step, 56 + step)])
		out.append(["%dx%d CONTROL, far apart" % [foot.x, foot.y], foot, Vector2i(54, 56),
				Vector2i(64, 66)])
	return out


func _case(name: String, foot: Vector2i, a_pos: Vector2i, b_pos: Vector2i) -> void:
	var a := AssayHud.building_mark({"pos": a_pos, "footprint": foot}, CELL, AssayHud.MARGIN)
	var b := AssayHud.building_mark({"pos": b_pos, "footprint": foot}, CELL, AssayHud.MARGIN)
	print("")
	print("  %s   A at %s, B at %s   (B is painted second, as in _sim.buildings() order)"
			% [name, a_pos, b_pos])
	var a_rect: Rect2 = a["rect"]
	var b_rect: Rect2 = b["rect"]
	print("    A rect %s  B rect %s   rects overlap %s"
			% [a_rect, b_rect, a_rect.intersection(b_rect).size])
	for sequence: String in ["ONE PASS (main before #421)", "TWO PASSES (#421)"]:
		var grid := {}
		if sequence.begins_with("ONE"):
			_one_pass(grid, [a, b])
		else:
			_two_passes(grid, [a, b])
		print("    %s" % sequence)
		_report(grid, a, "A (older)")
		_report(grid, b, "B (younger)")


## `main.gd::_draw_buildings` as it stood before #421: one loop, three draw_rect passes per building.
func _one_pass(grid: Dictionary, marks: Array) -> void:
	for mark_entry in marks:
		var mark: Dictionary = mark_entry
		_bands(grid, mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX, DARK)
		_bands(grid, mark["rect"], float(mark["stroke"]), BAND)
		_bands(grid, mark["hole_rect"], AssayHud.MARK_KEYLINE_PX, DARK)


## `main.gd::_draw_buildings` as #421 leaves it: every outward keyline, then every band and its own
## inward rim. The inward rim stays in the second pass because it lands inside the mark's own hole.
func _two_passes(grid: Dictionary, marks: Array) -> void:
	for mark_entry in marks:
		var mark: Dictionary = mark_entry
		_bands(grid, mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX, DARK)
	for mark_entry in marks:
		var mark: Dictionary = mark_entry
		_bands(grid, mark["rect"], float(mark["stroke"]), BAND)
		_bands(grid, mark["hole_rect"], AssayHud.MARK_KEYLINE_PX, DARK)


func _bands(grid: Dictionary, outer: Rect2, thickness: float, ink: StringName) -> void:
	for band: Rect2 in AssayHud.frame_bands(outer, thickness):
		_fill(grid, band, ink)


## **GODOT RASTERISES BY PIXEL CENTRE**, and these rects sit on half pixels (a 1x1's mark is centred
## on the middle of its tile), so a loop over integers from `position` would be off by one on half of
## them. A pixel `(i, j)` is painted when its centre `(i + 0.5, j + 0.5)` is inside the rect.
func _fill(grid: Dictionary, rect: Rect2, ink: StringName) -> void:
	var y := int(ceil(rect.position.y - 0.5))
	var y_end := int(ceil(rect.end.y - 0.5))
	while y < y_end:
		var x := int(ceil(rect.position.x - 0.5))
		var x_end := int(ceil(rect.end.x - 0.5))
		while x < x_end:
			grid[Vector2i(x, y)] = ink
			x += 1
		y += 1


## What this mark's OWN band pixels ended up as, per side, because a hollow mark's four sides are
## four reads and a total hides which one went.
func _report(grid: Dictionary, mark: Dictionary, who: String) -> void:
	var sides: Array[Rect2] = AssayHud.frame_bands(mark["rect"], float(mark["stroke"]))
	var labels: PackedStringArray = ["top", "bottom", "left", "right"]
	var total := 0
	var kept := 0
	var parts: PackedStringArray = []
	for i in range(sides.size()):
		var pixels := _pixels(sides[i])
		var side_kept := 0
		for pixel: Vector2i in pixels:
			if StringName(grid.get(pixel, GROUND)) == BAND:
				side_kept += 1
		total += pixels.size()
		kept += side_kept
		var run := _longest_run(grid, sides[i])
		parts.append("%s %d/%d run %d" % [labels[i], side_kept, pixels.size(), run])
	print("      %-12s band %3d px, kept %3d (%5.1f%%)   %s"
			% [who, total, kept, 100.0 * float(kept) / float(maxi(total, 1)), " ".join(parts)])


## THE LONGEST UNBROKEN RUN ALONG THE SIDE, measured ACROSS the band's short axis and ALONG its long
## one: a side of a frame is a line, and what makes it readable is its length, not its area.
func _longest_run(grid: Dictionary, side: Rect2) -> int:
	var along_x := side.size.x >= side.size.y
	var pixels := _pixels(side)
	# Group by the coordinate along the side, and a position counts as present only if EVERY pixel
	# across the band's thickness is still band ink. A half-eaten 2px line is a thinner line.
	var present := {}
	for pixel: Vector2i in pixels:
		var along := pixel.x if along_x else pixel.y
		var ok := StringName(grid.get(pixel, GROUND)) == BAND
		present[along] = bool(present.get(along, true)) and ok
	var keys := present.keys()
	keys.sort()
	var best := 0
	var run := 0
	var previous := -999
	for key: int in keys:
		if key != previous + 1:
			run = 0
		run = run + 1 if bool(present[key]) else 0
		best = maxi(best, run)
		previous = key
	return best


func _pixels(rect: Rect2) -> Array:
	var out: Array = []
	var y := int(ceil(rect.position.y - 0.5))
	var y_end := int(ceil(rect.end.y - 0.5))
	while y < y_end:
		var x := int(ceil(rect.position.x - 0.5))
		var x_end := int(ceil(rect.end.x - 0.5))
		while x < x_end:
			out.append(Vector2i(x, y))
			x += 1
		y += 1
	return out
