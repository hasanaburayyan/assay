extends SceneTree
## CI: local -- a pixel replica of one paint loop, for a number no assertion wants; read by a person
## **WHAT A NEIGHBOUR'S MARK ACTUALLY DELETES, PIXEL BY PIXEL, THROUGH THE REAL PAINT SEQUENCE**
## (ASSA-289 box 5).
##
##   $GODOT --headless --path client --script res://tools/assa289_paint_probe.gd -- [png_dir]
##
## With `png_dir` it also writes the grid out as PNGs, at 1x and at 6x nearest-neighbour, because a
## table cannot answer "does a band with a 12 px run still read as a side" and a picture can. The 1x
## file is the one to judge; the 6x is only for pointing at a pixel.
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


var _png_dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_png_dir = String(args[0])
		DirAccess.make_dir_recursive_absolute(_png_dir)
		print("  writing pictures to %s" % _png_dir)
	print("ASSA-289  what a neighbour DELETES, through the real paint sequence")
	print("  BUILDING_MARK_PX %.0f, MARK_KEYLINE_PX %.0f, BUILDING_STROKE_PX %.0f, cell %.0f"
			% [AssayHud.BUILDING_MARK_PX, AssayHud.MARK_KEYLINE_PX, AssayHud.BUILDING_STROKE_PX,
			CELL])
	print("  a band pixel is LOST only if the last ink on it is dark; both inks are alpha 1.0")
	for case: Array in _cases():
		_case(String(case[0]), case[1], case[2], case[3])
	_shipped()
	_floors()
	quit()


## **THE PAIR THE DEMO LOOP ACTUALLY PLANTS, WHICH IS THE ONLY PAIR ANY SHOT OF OURS CONTAINS.**
##
## Every case above is a pair a PLAYER can build. None of them is a pair we have ever photographed,
## and the reason is worth writing down: `AssayDemoPlan.smelter_spot` and `drill_spot` both offset
## from where the player stands, in a fixed order, so the demo's two machines land at the **same
## relative offset in every world**. Twenty-five whole-world shots in `shared/assay/` -- nine
## people's, back to ASSA-189, across every seed anyone has used -- and `08-whole-world-marks.json`
## says `dx +22.5, dy +22.5` in **all twenty-five**, at mark 12, 16, 18 and 20 alike.
##
## So this case is not a hypothetical: it is the shipped world, and it is here to be the honest
## answer to "does this bug happen in the game" rather than "can it happen". A 2.5 px diagonal gap,
## no band touched, at the shipped floor.
func _shipped() -> void:
	print("")
	print("  THE SHIPPED DEMO PAIR: a 1x1 drill and a 2x2 smelter, +2 tiles diagonally.")
	print("    the offset in all 25 whole-world shots in shared/assay/ is dx +22.5, dy +22.5 px")
	var drill := AssayHud.building_mark({"pos": Vector2i(52, 54), "footprint": Vector2i(1, 1)},
			CELL, AssayHud.MARGIN)
	var smelter := AssayHud.building_mark({"pos": Vector2i(54, 56), "footprint": Vector2i(2, 2)},
			CELL, AssayHud.MARGIN)
	var grid := {}
	_two_passes(grid, [drill, smelter])
	var gap: Rect2 = (drill["rect"] as Rect2).intersection(smelter["rect"])
	print("    drill rect %s  smelter rect %s" % [drill["rect"], smelter["rect"]])
	print("    marks overlap: %s   keyline rects overlap: %s"
			% [gap.size, (drill["keyline_rect"] as Rect2).intersection(
			smelter["keyline_rect"]).size])
	_report(grid, drill, "drill 1x1")
	_report(grid, smelter, "smelter 2x2")
	if _png_dir != "":
		_write(grid, [drill, smelter], "shipped-demo-pair")


## **BOX 5 AS A PICTURE INSTEAD OF A NUMBER: THE SAME TWO 1x1 MACHINES AT FOUR FLOORS.**
##
## The shipped floor is 20 px on a 9 px tile, so each mark's wall lands 5.5 px INSIDE its neighbour's
## tile and the pair cannot read as two machines however it is painted. That is a vocabulary defect,
## not a deletion one, and `kept 136/144` does not say it -- which is the point of rendering it.
##
## **THIS IS A REPLICA AND IT IS FOR CHOOSING, NOT FOR SHIPPING.** `_mark_at_floor` repeats
## `AssayHud.building_mark`'s three lines of arithmetic with the floor as a parameter, because a
## const cannot be swept. `building_mark` stays the only path anything draws through; if a floor is
## ever picked, it moves in `hud.gd` and this sweep is re-shot against it rather than trusted.
func _floors() -> void:
	print("")
	print("  BOX 5, DRAFT: two adjacent 1x1 machines at four floors, two passes (a replica)")
	print("    a 1x1's tile is %.0f px. The mark's wall sits (floor - cell) / 2 inside the next tile."
			% CELL)
	for floor_px: float in [AssayHud.BUILDING_MARK_PX, 15.0, 11.0, CELL]:
		var a := _mark_at_floor(Vector2i(54, 56), Vector2i(1, 1), floor_px)
		var b := _mark_at_floor(Vector2i(55, 56), Vector2i(1, 1), floor_px)
		var grid := {}
		_two_passes(grid, [a, b])
		var into := (floor_px - CELL) * 0.5
		print("    floor %2.0f px  reaches %4.1f px into the tile next door%s"
				% [floor_px, maxf(into, 0.0), "   <- shipped"
				if floor_px == AssayHud.BUILDING_MARK_PX else ""])
		_report(grid, a, "A (older)")
		_report(grid, b, "B (younger)")
		if _png_dir != "":
			_write(grid, [a, b], "box5-floor-%02.0f-DRAFT" % floor_px)
			var lone := {}
			_two_passes(lone, [_mark_at_floor(Vector2i(54, 56), Vector2i(1, 1), floor_px)])
			_write(lone, [a], "box5-floor-%02.0f-DRAFT-lone" % floor_px)


## `AssayHud.building_mark`'s arithmetic with the floor lifted out. Every other key it returns is
## derived from `outer` exactly as it is there, so the paint loops above cannot tell the difference.
func _mark_at_floor(pos: Vector2i, foot: Vector2i, floor_px: float) -> Dictionary:
	var span := maxf(float(maxi(foot.x, foot.y)) * CELL, floor_px)
	var at := AssayHud.MARGIN + (Vector2(pos) + Vector2(foot) * 0.5) * CELL
	var outer := Rect2(at - Vector2(span, span) * 0.5, Vector2(span, span))
	return {
		"rect": outer,
		"hole_rect": outer.grow(-AssayHud.BUILDING_STROKE_PX),
		"keyline_rect": outer.grow(AssayHud.MARK_KEYLINE_PX),
		"stroke": AssayHud.BUILDING_STROKE_PX,
	}


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
	for sequence: String in ["ONE PASS (main before #421)", "TWO PASSES (#421)",
			"THREE PASSES (11.42)"]:
		var grid := {}
		var slug := "two-passes"
		match sequence.split(" ")[0]:
			"ONE":
				_one_pass(grid, [a, b])
				slug = "one-pass"
			"TWO":
				_two_passes(grid, [a, b])
			_:
				_three_passes(grid, [a, b])
				slug = "three-passes"
		print("    %s" % sequence)
		_report(grid, a, "A (older)")
		_report(grid, b, "B (younger)")
		if _png_dir != "":
			_write(grid, [a, b], "%s-%s" % [_slug(name), slug])


## **THE GRID AS A PICTURE, ON THE REAL GROUND INK.** Only two things are visible to a player here:
## the band is `HOVER` and the keyline is `MAP_BG`, which is the same colour as the ground off a
## deposit -- so a keyline that ate a band shows up as a BITE out of a white line and nothing else.
## That is the whole read, and it is why this is worth a file rather than a column.
func _write(grid: Dictionary, marks: Array, name: String) -> void:
	var box := Rect2i()
	for i in range(marks.size()):
		var rect: Rect2 = (marks[i] as Dictionary)["keyline_rect"]
		var as_int := Rect2i(int(floor(rect.position.x)) - 4, int(floor(rect.position.y)) - 4,
				int(ceil(rect.size.x)) + 8, int(ceil(rect.size.y)) + 8)
		box = as_int if i == 0 else box.merge(as_int)
	var image := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGB8)
	image.fill(AssayHud.MAP_BG)
	for y in range(box.size.y):
		for x in range(box.size.x):
			if StringName(grid.get(Vector2i(box.position.x + x, box.position.y + y), GROUND)) == BAND:
				image.set_pixel(x, y, AssayHud.HOVER)
	image.save_png("%s/%s-1x.png" % [_png_dir, name])
	var big := image.duplicate() as Image
	big.resize(box.size.x * 6, box.size.y * 6, Image.INTERPOLATE_NEAREST)
	big.save_png("%s/%s-6x.png" % [_png_dir, name])


func _slug(name: String) -> String:
	return name.to_lower().replace(" ", "-").replace(",", "")


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


## **MAREN'S RULE 11.42, WHICH IS WIDER THAN THE FIX I BUILT AND REACHES WHAT I SAID NOTHING COULD.**
## *Paint order is global, not per-mark: one pass of every SEPARATOR, then PEOPLE, then every
## IDENTITY.* Players are not modelled here — this probe has no world — so what it measures is the
## half that bears on ASSA-289: **both rims of every machine before any machine's band.**
##
## I told her on the item that the 1x1 residual was out of reach of paint order, *"because a mark's
## own rim is painted after its own band by construction"*. That construction is exactly what 11.42
## dissolves. Measured here rather than conceded on paper.
func _three_passes(grid: Dictionary, marks: Array) -> void:
	for mark_entry in marks:
		var mark: Dictionary = mark_entry
		_bands(grid, mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX, DARK)
		_bands(grid, mark["hole_rect"], AssayHud.MARK_KEYLINE_PX, DARK)
	# (pass 2 is the players, which need a world and are measured by `person_under_machine.gd`)
	for mark_entry in marks:
		var mark: Dictionary = mark_entry
		_bands(grid, mark["rect"], float(mark["stroke"]), BAND)


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
