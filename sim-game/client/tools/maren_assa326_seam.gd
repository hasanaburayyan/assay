extends SceneTree
## CI: local -- a pixel replica for a picture a person has to judge; no assertion wants its numbers
## **CAN TWO ADJACENT MACHINES BE COUNTED WITHOUT MOVING THE FLOOR?** (ASSA-326, ASSA-289 box 5.)
##
##   $GODOT --headless --path client --script res://tools/maren_assa326_seam.gd -- [png_dir]
##
## Cove's `assa289_paint_probe.gd` settled what a neighbour DELETES and I am not re-asking that. This
## asks the question their box 5 leaves: at the shipped `BUILDING_MARK_PX` of 20, two machines on
## adjacent tiles produce ONE outline, because a mark wider than its tile puts its own edges inside
## its neighbour. Their four-floor sweep answers it by shrinking the mark; the floor is a HOLE bar
## (`person_under_machine.gd`: the hole is 12x12 at 20 and 8x8 at 16), so every floor below 20 takes
## a person's body back and 11 or 9 buys the count with §11.14. The floor is not the lever.
##
## **SO THE LEVER TESTED HERE IS THE PAINT ORDER, WHICH IS THE OTHER THING 11.42 MOVED.** Three
## sequences on the same two marks:
##
## - ONE PASS (main before #421): a keyline landing on a neighbour's band. Two shapes, older one
##   mutilated to an open bracket.
## - THREE PASSES (11.42, shipped): no deletion anywhere, and one wide box with three panes.
## - SEAM (this proposal): 11.42, and then every outward keyline AGAIN, restricted to the part of it
##   that falls inside ANOTHER mark's rect. A rim yields to a neighbour's band on open ground, where
##   its only job is independence from the GROUND (§11.1); where it divides two machines it is not
##   doing that job and does not yield.
##
## It reports, per mark, the longest unbroken run of each side (Cove's statistic, kept deliberately:
## for a band the number that matters is the run, not the mass) so the seam's cost is visible in the
## same currency their table used.
##
## NO WINDOW AND NO WORLD, so it cannot say whether the result READS at 1x on a deposit tint; that is
## a window shot's question and it is why the 1x PNG is the file to judge.

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
	print("ASSA-326  can two adjacent machines be COUNTED at the shipped floor?")
	print("  BUILDING_MARK_PX %.0f, MARK_KEYLINE_PX %.0f, BUILDING_STROKE_PX %.0f, cell %.0f"
			% [AssayHud.BUILDING_MARK_PX, AssayHud.MARK_KEYLINE_PX, AssayHud.BUILDING_STROKE_PX,
			CELL])
	for case: Array in _cases():
		_case(String(case[0]), case[1], case[2], case[3])
	quit()


func _cases() -> Array:
	var out: Array = []
	for foot: Vector2i in [Vector2i(1, 1), Vector2i(2, 2)]:
		var step := maxi(foot.x, foot.y)
		out.append(["%dx%d side by side" % [foot.x, foot.y], foot, Vector2i(54, 56),
				Vector2i(54 + step, 56)])
		out.append(["%dx%d corner to corner" % [foot.x, foot.y], foot, Vector2i(54, 56),
				Vector2i(54 + step, 56 + step)])
		out.append(["%dx%d CONTROL, far apart" % [foot.x, foot.y], foot, Vector2i(54, 56),
				Vector2i(64, 66)])
	# A row of three, because two is the case we argue about and three is what a factory looks like.
	out.append(["1x1 three in a row", Vector2i(1, 1), Vector2i(54, 56), Vector2i(55, 56)])
	return out


func _case(name: String, foot: Vector2i, a_pos: Vector2i, b_pos: Vector2i) -> void:
	var marks: Array = [_mark(a_pos, foot), _mark(b_pos, foot)]
	if name.ends_with("three in a row"):
		marks.append(_mark(b_pos + Vector2i(1, 0), foot))
	print("")
	print("  %s  (%d marks, painted in sim order)" % [name, marks.size()])
	for sequence: String in ["ONE PASS", "THREE PASSES (11.42, shipped)", "SEAM (proposed)"]:
		var grid := {}
		var slug := "one-pass"
		match sequence.split(" ")[0]:
			"ONE":
				_one_pass(grid, marks)
			"THREE":
				_three_passes(grid, marks)
				slug = "three-passes"
			_:
				_three_passes(grid, marks)
				_seam(grid, marks)
				slug = "seam"
		print("    %s" % sequence)
		for i in range(marks.size()):
			_report(grid, marks[i], "mark %d" % i)
		if _png_dir != "":
			_write(grid, marks, "%s-%s" % [_slug(name), slug])


func _mark(pos: Vector2i, foot: Vector2i) -> Dictionary:
	return AssayHud.building_mark({"pos": pos, "footprint": foot}, CELL, AssayHud.MARGIN)


## Every outward keyline again, clipped to the parts of it that lie inside another mark's rect.
func _seam(grid: Dictionary, marks: Array) -> void:
	for i in range(marks.size()):
		var mark: Dictionary = marks[i]
		for band: Rect2 in AssayHud.frame_bands(mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX):
			for j in range(marks.size()):
				if i == j:
					continue
				var inside: Rect2 = band.intersection((marks[j] as Dictionary)["rect"])
				if inside.size.x > 0.0 and inside.size.y > 0.0:
					_fill(grid, inside, DARK)


func _one_pass(grid: Dictionary, marks: Array) -> void:
	for mark_entry in marks:
		var mark: Dictionary = mark_entry
		_bands(grid, mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX, DARK)
		_bands(grid, mark["rect"], float(mark["stroke"]), BAND)
		_bands(grid, mark["hole_rect"], AssayHud.MARK_KEYLINE_PX, DARK)


func _three_passes(grid: Dictionary, marks: Array) -> void:
	for mark_entry in marks:
		var mark: Dictionary = mark_entry
		_bands(grid, mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX, DARK)
		_bands(grid, mark["hole_rect"], AssayHud.MARK_KEYLINE_PX, DARK)
	for mark_entry in marks:
		var mark: Dictionary = mark_entry
		_bands(grid, mark["rect"], float(mark["stroke"]), BAND)


func _bands(grid: Dictionary, outer: Rect2, thickness: float, ink: StringName) -> void:
	for band: Rect2 in AssayHud.frame_bands(outer, thickness):
		_fill(grid, band, ink)


## Godot rasterises by pixel centre and these rects sit on half pixels (Cove's note on the same
## arithmetic): a pixel is painted when its centre is inside the rect.
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


func _report(grid: Dictionary, mark: Dictionary, who: String) -> void:
	var sides: Array[Rect2] = AssayHud.frame_bands(mark["rect"], float(mark["stroke"]))
	var labels: PackedStringArray = ["top", "bottom", "left", "right"]
	var parts: PackedStringArray = []
	var total := 0
	var kept := 0
	for i in range(sides.size()):
		var pixels := _pixels(sides[i])
		var side_kept := 0
		for pixel: Vector2i in pixels:
			if StringName(grid.get(pixel, GROUND)) == BAND:
				side_kept += 1
		total += pixels.size()
		kept += side_kept
		parts.append("%s %d/%d run %d" % [labels[i], side_kept, pixels.size(),
				_longest_run(grid, sides[i])])
	print("      %-8s band %3d px, kept %3d (%5.1f%%)   %s"
			% [who, total, kept, 100.0 * float(kept) / float(maxi(total, 1)), " ".join(parts)])


func _longest_run(grid: Dictionary, side: Rect2) -> int:
	var along_x := side.size.x >= side.size.y
	var present := {}
	for pixel: Vector2i in _pixels(side):
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
