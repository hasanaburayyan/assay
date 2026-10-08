extends SceneTree
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
	_band_neighbours(mark, at)
	quit()


## **BOX 7: WHAT THE BAND'S INNER NEIGHBOUR ACTUALLY IS WHEN A PERSON IS STANDING THERE** (ASSA-278,
## Maren's box-7 ruling, option 3: *"the rim goes under the player pass"*).
##
## Her ruling carries a condition and says it must be asserted rather than assumed: *"Where a person
## covers the rim, the band's inner neighbour becomes the person's own `MAP_BG` keyline -- dark, so
## the band is still separated. That holds only while the keyline sits between the body's fill and
## the band."* **IT DOES NOT SIT THERE.** `mark_keyline_rect`'s own docs say the person's rim GROWS
## OUTWARDS so the body is untouched in pixels, so on a tile where body and band are concentric the
## order outward from the centre is `fill, band, keyline` -- the keyline is OUTSIDE the band, and
## between the fill and the band there is nothing at all.
##
## So this counts it. For every band pixel, its inward neighbours inside the hole are classified by
## the TOPMOST paint standing on them in each arm's order, and a band pixel FAILS if any of them is
## bright body fill. Conservative on purpose: a corner pixel whose only inward step is still band is
## skipped, and one bright neighbour out of four is a failure, because what an eye reads is an edge
## and an edge needs only one side.
func _band_neighbours(mark: Dictionary, at: Vector2) -> void:
	print("")
	print("  BOX 7: IS EVERY BAND PIXEL'S INNER NEIGHBOUR DARK, WITH A PERSON ON THE TILE?")
	print("    band vs MAP_BG %.2f:1   vs MINE %.2f:1   vs THEIRS %.2f:1  (WCAG)"
			% [_contrast(AssayHud.HOVER, AssayHud.MAP_BG), _contrast(AssayHud.HOVER, AssayHud.MINE),
			_contrast(AssayHud.HOVER, AssayHud.THEIRS)])
	var rim := AssayHud.MARK_KEYLINE_PX
	var band := AssayHud.frame_bands(mark["rect"], float(mark["stroke"]))
	var rim_bands := AssayHud.frame_bands(mark["hole_rect"], rim)
	var hole: Rect2 = mark["hole_rect"]
	for arm: String in ["rim AFTER the player pass (shipped, 1d8b6af)",
			"rim BEFORE the player pass (option 3)", "no inward rim at all (main before 278)"]:
		var rim_under := arm.begins_with("rim BEFORE")
		var has_rim := not arm.begins_with("no inward")
		print("")
		print("    %s" % arm)
		for mine: bool in [true, false]:
			var person := AssayHud.player_mark(at, mine)
			var body: PackedVector2Array = person["points"]
			var keyline: PackedVector2Array = person["keyline_points"]
			var total := 0
			var bright := 0
			for point in _grid((mark["rect"] as Rect2).grow(1.0)):
				if not _covered(band, point):
					continue
				var inner := _inward(point, hole)
				if inner.is_empty():
					continue
				total += 1
				for neighbour in inner:
					# THE PAINT STACK AT THAT PIXEL, TOPMOST LAST, IN THE ARM'S ORDER. The rim is the
					# only thing that moves; the person is always painted after the deposits and
					# before the frame's own bands.
					var lit := false
					if has_rim and not rim_under and _covered(rim_bands, neighbour):
						lit = false
					elif Geometry2D.is_point_in_polygon(neighbour, body):
						lit = true
					elif Geometry2D.is_point_in_polygon(neighbour, keyline):
						lit = false
					elif has_rim and _covered(rim_bands, neighbour):
						lit = false
					else:
						# Bare ground, or the deposit tint under it: the ASSA-278 defect itself, which
						# is exactly what the rim was ruled in to answer. Counted separately below.
						lit = false
					if lit:
						bright += 1
						break
			print("      %-8s %3d band px with an inner neighbour, %3d touch bright body fill = %5.1f%%"
					% ["you" if mine else "partner", total, bright,
					100.0 * float(bright) / float(maxi(total, 1))])
	print("")
	print("    A band pixel touching bright body fill reads 1.26:1 (you) or 1.54:1 (partner)")
	print("    against the 15.37:1 the rim buys -- so those pixels are back to the ASSA-278 defect.")
	_mass_sweep(at)


## **THE LEVER THAT ANSWERS BOX 5 AND BOX 7 WITH ONE NUMBER, AND IT IS MAREN'S SIZE TO RULE.**
##
## Box 7's conflict is not the paint order, it is that `PLAYER_MARK_PX` and `BUILDING_MARK_PX` are
## BOTH 16: on a 1x1 the body is exactly inscribed in the frame's outer rect, so body and band are
## concentric and the same size and cannot both own that boundary. Either the rim is painted over the
## person (the person pays) or it is not (the band pays) -- the two arms above, and there is no third
## paint order, because what is missing is SPACE.
##
## Box 5 is open for an unrelated-looking reason: Limpet's cold read of the shipped seed-63 frame
## named ZERO machines. Maren's named next lever for that is *"the mark's MASS on a bright ground --
## a thicker keyline -- and not the ink"*. Mass is the same knob. So this sweeps
## `BUILDING_MARK_PX`'s floor and prints, for each, what the person keeps and how much of the band
## still has a bright inner neighbour. The row where both go clean is the row where the body fits
## INSIDE the hole and stops touching the band at all.
##
## It changes a size Maren set, so nothing here is built: this is a table to rule from.
func _mass_sweep(at: Vector2) -> void:
	print("")
	print("  THE MASS LEVER (BUILDING_MARK_PX's floor on a 1x1), rim 2 px AFTER the player pass:")
	print("    floor  hole  you keep  partner keep  band px w/ bright inner nbr (you/partner)")
	var tile := Vector2i(12, 7)
	var origin := Vector2(24.0, 24.0)
	for floor_px: float in [16.0, 20.0, 22.0, 24.0, 26.0, 28.0]:
		var span := maxf(9.0, floor_px)
		var centre := origin + (Vector2(tile) + Vector2(0.5, 0.5)) * 9.0
		var outer := Rect2(centre - Vector2(span, span) * 0.5, Vector2(span, span))
		var mark := {"rect": outer, "hole_rect": outer.grow(-AssayHud.BUILDING_STROKE_PX),
				"keyline_rect": outer.grow(AssayHud.MARK_KEYLINE_PX),
				"stroke": AssayHud.BUILDING_STROKE_PX}
		var ink := _machine_ink(mark, AssayHud.MARK_KEYLINE_PX)
		var kept: Array[float] = []
		var lit: Array[String] = []
		for mine: bool in [true, false]:
			var person := AssayHud.player_mark(at, mine)
			var body: PackedVector2Array = person["points"]
			var total := 0
			var alive := 0
			for point in _grid(_bounds(body)):
				if not Geometry2D.is_point_in_polygon(point, body):
					continue
				total += 1
				if not _covered(ink, point):
					alive += 1
			kept.append(100.0 * float(alive) / float(maxi(total, 1)))
			lit.append(_bright_inner(mark, person, true))
		print("    %5.0f %5.0f %8.1f%% %12.1f%%  %s / %s"
				% [floor_px, (mark["hole_rect"] as Rect2).grow(-AssayHud.MARK_KEYLINE_PX).size.x,
				kept[0], kept[1], lit[0], lit[1]])
	print("    (hole = px clear of ink; the body's diamond is 16 px across and its tips are what")
	print("     reach the band, so the body stops touching it once the clear hole passes 16.)")


## How many of the band's pixels have a bright body fill one step inward. [param rim_on_top]
## is the shipped order, where the rim is painted over whoever is standing there.
func _bright_inner(mark: Dictionary, person: Dictionary, rim_on_top: bool) -> String:
	var band := AssayHud.frame_bands(mark["rect"], float(mark["stroke"]))
	var rim_bands := AssayHud.frame_bands(mark["hole_rect"], AssayHud.MARK_KEYLINE_PX)
	var hole: Rect2 = mark["hole_rect"]
	var body: PackedVector2Array = person["points"]
	var total := 0
	var bright := 0
	for point in _grid((mark["rect"] as Rect2).grow(1.0)):
		if not _covered(band, point):
			continue
		var inner := _inward(point, hole)
		if inner.is_empty():
			continue
		total += 1
		for neighbour in inner:
			if rim_on_top and _covered(rim_bands, neighbour):
				continue
			if Geometry2D.is_point_in_polygon(neighbour, body):
				bright += 1
				break
	return "%d/%d" % [bright, total]


## The band pixel's neighbours one step toward the mark's centre that land inside the hole.
func _inward(point: Vector2, hole: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for step: Vector2 in [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0),
			Vector2(0.0, -1.0)]:
		var neighbour := point + step
		if hole.has_point(neighbour):
			out.append(neighbour)
	return out


## WCAG contrast between two colours, as `framecontrast.py` computes it on the shipped frames.
func _contrast(a: Color, b: Color) -> float:
	var la := _relative_luminance(a)
	var lb := _relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _relative_luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


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
