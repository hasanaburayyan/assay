extends SceneTree
## CI: local -- measures how much of a drawn person survives a drawn mark, in a real window
## **HOW MUCH OF A PERSON STANDING ON A MACHINE SURVIVES THE MACHINE'S MARK** (ASSA-278).
##
##   $GODOT --headless --path client --script res://tools/person_under_machine.gd
##
## **WHY THIS EXISTS: MY OWN COSTING OF THE INWARD RIM NAMED THE HOLE AND NOT THE PERSON.** ASSA-278
## option 1 says *"a 1x1 drill keeps an 8x8 hole instead of 12x12, and a machine stops showing the ore
## under its own middle"* -- true, and it leaves out that `_draw` paints buildings AFTER players
## (`main.gd`, Maren's ASSA-203 box 5), so the rim is painted over whoever is standing there. The
## whole justification of the hollow frame was that it ENDED that trade: *"a partner standing on a
## drill keeps 25.3% of their mark today and 70.4% with the frame"*. A rim inside the hole buys some
## of the trade back, and nobody had the number.
##
## **THE REAL GEOMETRY, NOT A REPLICA.** Every shape comes from `AssayHud.building_mark`,
## `AssayHud.player_mark` and `AssayHud.frame_bands` at the shipped constants, in the painter's own
## order; the arms differ only in the inward rim's thickness. Sampled on a 1 px grid at a quarter-pixel
## offset, because the map's rects sit on half-pixels at cell 9 and on integers at cell 32 and a
## sample on an edge is a coin toss.
##
## WHAT IT CANNOT SEE: ink, antialiasing, or whether `_draw` paints any of it. It is an area count
## over polygons -- a lever for choosing, and a real window is the proof (ASSA-278's own figures).

const SAMPLE_OFFSET := 0.25


func _initialize() -> void:
	var cell := 9.0
	var origin := Vector2(24.0, 24.0)
	var tile := Vector2i(12, 7)
	# The tile's MIDDLE, which is where a mark sits (ASSA-220 box 3), and the same point both marks
	# are built about -- a person on the machine's own tile is the case.
	var at := origin + (Vector2(tile) + Vector2(0.5, 0.5)) * cell
	print("ASSA-278  a person standing on a 1x1 machine, cell %.0f px, marks at %s" % [cell, at])
	print("  machine mark = BUILDING_MARK_PX %.0f, stroke %.0f, keyline %.0f"
			% [AssayHud.BUILDING_MARK_PX, AssayHud.BUILDING_STROKE_PX, AssayHud.MARK_KEYLINE_PX])
	var mark := AssayHud.building_mark({"pos": tile, "footprint": Vector2i(1, 1)}, cell, origin)
	for rim: float in [0.0, 1.0, 2.0]:
		var ink := _machine_ink(mark, rim)
		print("")
		print("  INWARD RIM %.0f px%s" % [rim, "   <- main before ASSA-278" if rim == 0.0 else
				("   <- MARK_KEYLINE_PX, what #368 ships" if rim == AssayHud.MARK_KEYLINE_PX else "")])
		for mine: bool in [true, false]:
			var person := AssayHud.player_mark(at, mine)
			var body: PackedVector2Array = person["points"]
			var total := 0
			var kept := 0
			for point in _grid(_bounds(body)):
				if not Geometry2D.is_point_in_polygon(point, body):
					continue
				total += 1
				if not _covered(ink, point):
					kept += 1
			print("    %-8s body %3d px, keeps %3d px = %5.1f%%"
					% ["you" if mine else "partner", total, kept,
					100.0 * float(kept) / float(maxi(total, 1))])
		# AND THE HOLE ITSELF, which is what the ore under the machine shows through.
		var hole := _clear_hole(mark, rim)
		print("    hole      %.0f x %.0f px clear of ink" % [hole.x, hole.y])
	quit()


## The three lists `_draw` paints for one machine, in its order, with the inward rim at [param rim].
func _machine_ink(mark: Dictionary, rim: float) -> Array[Rect2]:
	var ink: Array[Rect2] = []
	ink.append_array(AssayHud.frame_bands(mark["keyline_rect"], AssayHud.MARK_KEYLINE_PX))
	ink.append_array(AssayHud.frame_bands(mark["rect"], float(mark["stroke"])))
	if rim > 0.0:
		ink.append_array(AssayHud.frame_bands(mark["hole_rect"], rim))
	return ink


func _covered(ink: Array[Rect2], point: Vector2) -> bool:
	for band in ink:
		if band.has_point(point):
			return true
	return false


func _clear_hole(mark: Dictionary, rim: float) -> Vector2:
	var hole: Rect2 = mark["hole_rect"]
	return hole.grow(-rim).size


func _bounds(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	return box


func _grid(box: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var y := floorf(box.position.y) + SAMPLE_OFFSET
	while y <= box.end.y:
		var x := floorf(box.position.x) + SAMPLE_OFFSET
		while x <= box.end.x:
			out.append(Vector2(x, y))
			x += 1.0
		y += 1.0
	return out
