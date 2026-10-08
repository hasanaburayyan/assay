extends SceneTree
## HOW MUCH OF A MACHINE'S TILE ITS WESTERN NEIGHBOUR'S PICTURE COVERS, in the close-up view
## (ASSA-326 box 7, Maren).
##
## **WHY THIS IS A MEASUREMENT AND NOT A SCREENSHOT.** I ruled on ASSA-326 that the whole-world map
## cannot count machines and said "so the count's home is the close-up". I then read
## `scene_view.gd` and claimed the close-up is worse -- a 1x1 machine drawn 64 px on a 32 px tile,
## overhanging east. **That claim came off `tiles [2,1]` and an arithmetic I did in my head**, which
## is the fourth time this week one of my unmeasured numbers has travelled into somebody's work. Box
## 7 still needs a GUI run and a cold reader; this needs neither, because `canvas_of`'s own docstring
## says `AssayScene` "decides every rectangle in the world view headless, with no sheets decoded and
## no engine". So the geometry is answerable now and the eye is answerable later.
##
## **WHAT IT REPORTS AND WHAT IT REFUSES TO REPORT.** It prints the two drawn rects, how much of the
## eastern machine's own 32x32 tile its western neighbour's picture covers, and how much of the
## eastern machine's own picture is covered. It does NOT say whether a person can count them: that is
## a pixel question about a frame nobody has shot, and box 7 keeps it. A number here cannot tick
## box 7 and is not offered as doing so.
##
## **THE OVERLAP IS COMPUTED ON THE RECTS THE RENDERER USES, NOT ON A REPLICA I DREW.** It calls
## `AssayScene._composite_place` itself. My ASSA-326 seam probe was a replica and was right to be;
## this one does not have to be, and a replica where the real function is reachable would be a worse
## instrument for no reason.
##
# CI: local -- it reports numbers for a ruling and faults only on its own control, so gating it
# would buy a green that asserts nothing new. The invariant underneath it IS gated elsewhere:
# `the_manifest_agrees_with_the_sheet_about_a_drills_canvas` holds the manifest's `frame_px` equal to
# the real sheet, which is the one thing that could move these numbers without anyone touching a
# ruling. Run it: --headless --path . --script res://tools/maren_assa326_closeup.gd

const TILE := 32.0


func _init() -> void:
	var manifest := AssaySprites.manifest()
	var layout := AssayAssembly.contract()
	if manifest.is_empty() or layout.is_empty():
		push_error("no manifest or no assembly contract: run `make client-lib` and import twice")
		quit(1)
		return

	_sheet_facts(manifest)
	print("")
	if not _control(manifest, layout):
		quit(1)
		return
	print("")
	for hoppers in [0, 1, 2, 4]:
		_pair(manifest, layout, hoppers)
	print("")
	_sort_hazard()
	quit(0)


## THE CONTROL, AND IT RUNS BEFORE ANY NUMBER IS PRINTED SO A BROKEN INSTRUMENT CANNOT PUBLISH ONE.
##
## Six instruments of mine have lied this week, so a pair that must read ZERO goes first. A machine
## is drawn 64 px wide with a 1.5 px western overhang, so a neighbour FOUR tiles east (128 px) cannot
## be reached by any part of it: if that pair reports ink, my containment test is wrong and every
## number below it is noise. **A far pair reading 0 is the only thing that makes 43.5% mean
## anything** -- it is the same lesson as ASSA-314 box 4, where measuring a lap on the suppressed
## frame made the control pass by deleting the thing it measured.
func _control(manifest: Dictionary, layout: Dictionary) -> bool:
	var parts := _parts(2)
	var west: Dictionary = AssayScene._composite_place(manifest, parts, Vector2i(10, 10),
			Vector2.ZERO, layout)
	if west.is_empty():
		push_error("control: _composite_place returned {}")
		return false
	var far := Rect2(Vector2(14, 10) * TILE, Vector2(TILE, TILE))
	var ink := _ink_in(parts, west["dest"], far)
	print("CONTROL: a tile FOUR east of the west machine takes %.0f px of its ink (must be 0)" % ink)
	if ink > 0.0:
		push_error("CONTROL FAILED: the containment test reaches a tile the sprite cannot touch")
		return false
	var own := _ink_in(parts, west["dest"], Rect2(Vector2(10, 10) * TILE, Vector2(TILE, TILE)))
	print("CONTROL: and it does put ink (%.0f px) on its OWN tile, so the test is not blind" % own)
	return own > 0.0


## THE AUTHORED GEOMETRY, PRINTED BEFORE ANY DERIVED NUMBER, so a reader can check my scale.
func _sheet_facts(manifest: Dictionary) -> void:
	var spec: Dictionary = manifest.get("frame", {})
	var frame_px: Array = spec.get("frame_px", [])
	var tiles: Array = spec.get("tiles", [])
	var anchor: Array = spec.get("anchor_px", [0, 0])
	if frame_px.size() != 2 or tiles.size() != 2:
		push_error("the frame sheet has no frame_px/tiles; the manifest shape moved")
		quit(1)
		return
	var authored := float(frame_px[0]) / float(tiles[0])
	print("SHEET 'frame': frame_px %dx%d  tiles [%d,%d]  anchor_px [%d,%d]"
			% [int(frame_px[0]), int(frame_px[1]), int(tiles[0]), int(tiles[1]),
			int(anchor[0]), int(anchor[1])])
	print("  authored px per tile = frame_px.x / tiles.x = %.1f" % authored)
	print("  scale = TILE_PX / authored = %.1f / %.1f = %.4f" % [TILE, authored, TILE / authored])
	print("  a LONE FRAME is therefore drawn %.1f x %.1f px on a %.0f px tile"
			% [float(frame_px[0]) * TILE / authored, float(frame_px[1]) * TILE / authored, TILE])


## TWO MACHINES ON ADJACENT TILES, AND WHAT THE WESTERN ONE'S PICTURE DOES TO THE EASTERN ONE'S TILE.
##
## The pair is east-west because that is the direction the sheet overhangs and the direction
## ASSA-326's map defect runs. `origin` is zero: every number here is a difference between two rects
## in the same frame, so the camera cancels and a non-zero origin would only add noise.
func _pair(manifest: Dictionary, layout: Dictionary, hoppers: int) -> void:
	var parts := _parts(hoppers)
	var west: Dictionary = AssayScene._composite_place(manifest, parts, Vector2i(10, 10),
			Vector2.ZERO, layout)
	var east: Dictionary = AssayScene._composite_place(manifest, parts, Vector2i(11, 10),
			Vector2.ZERO, layout)
	if west.is_empty() or east.is_empty():
		push_error("_composite_place returned {} for %d hoppers" % hoppers)
		quit(1)
		return
	var wr: Rect2 = west["dest"]
	var er: Rect2 = east["dest"]
	# THE EASTERN MACHINE'S OWN TILE, which is the thing a player is counting: the sim says the
	# machine is ON this tile, and ASSA-30/38 says a sprite may overhang its own. Neither rule says
	# anything about a sprite overhanging SOMEBODY ELSE'S, which is the question.
	var tile_e := Rect2(Vector2(11, 10) * TILE, Vector2(TILE, TILE))
	var on_tile := wr.intersection(tile_e)
	var on_pic := wr.intersection(er)
	print("PARTS frame + head + %d hopper(s)" % hoppers)
	print("  west drawn  %s   %.0fx%.0f px = %.1f tiles wide"
			% [str(wr.position.round()), wr.size.x, wr.size.y, wr.size.x / TILE])
	print("  east drawn  %s" % str(er.position.round()))
	print("  west RECT covers %.0f of the east machine's 1024 px tile (%.1f%%)"
			% [on_tile.get_area(), 100.0 * on_tile.get_area() / (TILE * TILE)])
	print("  west RECT covers %.0f px of the east machine's own %.0f px rect (%.1f%%)"
			% [on_pic.get_area(), er.get_area(), 100.0 * on_pic.get_area() / er.get_area()])
	_ink_on_tile(parts, wr, tile_e)


## HOW MUCH INK -- NOT RECTANGLE -- THE WESTERN MACHINE PUTS ON ITS NEIGHBOUR'S TILE.
##
## **THIS FUNCTION EXISTS BECAUSE OF A MISTAKE OF MINE ON THIS VERY ITEM.** ASSA-326's body records
## it: Cove's 27.8% and my 28.1% were *"rect intersections reported as deletions"*, and the rects
## above are the same kind of number. A sprite is mostly transparent, so a rect that covers 95% of a
## tile may put almost no paint on it. The only honest version decodes the sheet, which `image_of`
## already does -- so the rect answer and the ink answer are both printed and never conflated.
##
## Authoring space, scaled on the way out: one authored pixel is `scale` x `scale` drawn pixels, so
## the count is multiplied by `scale * scale` to be comparable with the rect areas above. Alpha > 0
## is the test, which counts a 1% edge pixel as ink -- deliberately generous, because a measurement
## meant to bound how BAD the overlap is should not be the one that flatters it.
func _ink_on_tile(parts: Array, drawn: Rect2, tile_e: Rect2) -> void:
	var img := AssayAssembly.image_of(parts)
	if img == null:
		print("  INK: no image (a part has no art); rect numbers above stand alone")
		return
	var on := _ink_in(parts, drawn, tile_e)
	var all := _ink_in(parts, drawn, Rect2(drawn.position, drawn.size))
	print("  west INK %.0f px opaque in all, %.0f px of it on the EAST tile (%.1f%% of that tile)"
			% [all, on, 100.0 * on / (TILE * TILE)])


## OPAQUE DRAWN PIXELS OF ONE MACHINE THAT LAND INSIDE ONE RECT. The single arithmetic both the
## control and the measurement go through, so a bug cannot be in one and not the other.
func _ink_in(parts: Array, drawn: Rect2, box: Rect2) -> float:
	var img := AssayAssembly.image_of(parts)
	if img == null:
		return -1.0
	var w := img.get_width()
	var h := img.get_height()
	var scale := drawn.size.x / float(w)
	var on := 0
	for py in range(h):
		for px in range(w):
			if img.get_pixel(px, py).a <= 0.0:
				continue
			if box.has_point(drawn.position + Vector2(float(px), float(py)) * scale):
				on += 1
	return float(on) * scale * scale


## THE PARTS LIST THE SIM WOULD HAND US. Order is the sim's: the frame first, which is the entry
## `_composite_place` reads the geometry out of.
func _parts(hoppers: int) -> Array:
	var parts: Array = [
		{"kind": "Frame", "species": 0, "grade": "B"},
		{"kind": "Head", "species": 0, "grade": "B"},
	]
	for _i in range(hoppers):
		parts.append({"kind": "Hopper", "species": 0, "grade": "B"})
	return parts


## THE SECOND HALF OF THE FINDING, AND IT IS A FACT ABOUT THE SORT RATHER THAN A RECT.
##
## `_sorted_standing` orders on `bottom`, then `above`. Two machines in the same ROW share a bottom,
## and `above` is 0 for a building, so the pair is EQUAL under both keys and `sort_custom` is free to
## swap them. The file says so itself. This prints the condition rather than trying to provoke it:
## an unstable sort that happens not to swap on this array length proves nothing, and a probe that
## reported "no swap today" would be the most expensive kind of green there is.
func _sort_hazard() -> void:
	print("SORT: two machines in one row share `bottom` and both have `above` 0, so they are equal")
	print("      under every key `_sorted_standing` uses. scene_view.gd documents sort_custom as")
	print("      'free to swap equal elements ... intermittently, on some array lengths and not")
	print("      others'. NOT PROVOKED HERE ON PURPOSE: a run that did not swap would be a green")
	print("      that means nothing. The condition is the finding.")
