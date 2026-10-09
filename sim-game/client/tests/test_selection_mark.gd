extends RefCounted
## THE TILE THE BUTTONS ACT ON, MARKED ON THE CLOSE-UP (ASSA-276 move 4; Maren's colour ruling,
## Wren's ranking).
##
## **WHAT IS BEING DEFENDED, AND IT IS AN ABSENCE RATHER THAN A FAULT.** `main.gd::_target_tile`
## decides what Mine, Assay, Place and Pick up do. The schematic has drawn that tile since ASSA-119
## box 6. The close-up -- the view a player is in for nearly the whole session -- drew nothing for
## it at all, so the only thing on screen naming the subject of the next button press was a line of
## text in the column. Nothing was wrong; something was missing, and no test can go red for that.
##
## **WHAT THIS FILE CANNOT DO, STATED FIRST**, in the words `test_click_echo.gd` already earned: a
## headless runner never draws. `_draw` runs under a real window and this suite has none, so nothing
## here proves a pixel was painted. The geometry tests are arithmetic in `AssayScene`, which is where
## every drawable decision lives by this project's own split, and the last one is a SOURCE SCAN over
## the painter -- it reads the calls `_draw` makes and the order it makes them in. **That is not
## evidence the call ran.** The behavioural proof is `AssayWorldLayer.drawn_selection` (written
## inside `_draw` AFTER the `draw_rect` calls) read off a real window shot, and it is on ASSA-276.

const TILE := 32.0
## A tile far from every edge, so no camera clamp is in the arithmetic.
const PICKED := Vector2i(50, 33)

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


func _covered(bars: Array[Rect2], point: Vector2) -> bool:
	for bar in bars:
		if bar.has_point(point):
			return true
	return false


## AN OUTLINE ROUND THE TILE, OPEN IN THE MIDDLE, AND INSIDE ITS OWN TILE.
##
## The middle is the assertion that carries the design: the selection is ABOUT the thing on that
## tile -- a rock, a machine, its species letter -- so a mark that filled the tile would hide its own
## subject. That is the same clause Maren put on the verb bar ("the bar may never cover its own
## subject"), asserted here on the painter's geometry rather than trusted to a layout that happens
## to be right at one tile.
##
## **AND NOT ONE PIXEL OUTSIDE THE TILE**, which is ASSA-215's reason unchanged: an outline centred
## on the tile boundary straddles two tiles and is ambiguous by exactly one tile. On a mark that
## says "this is what the button will act on", being one tile out is the only error that matters.
## **RUN OVER BOTH SPANS SINCE ASSA-348**, because every clause below was written about a tile and
## every one of them is really about the SUBJECT: a 2x2 smelter must be as enclosed, as open in the
## middle and as fully edged as a 1x1. Asserting it at one span was how a one-tile mark sat under a
## four-tile subject for two weeks with this file green.
func test_the_selected_tile_is_outlined_and_open_in_the_middle() -> bool:
	var origin := Vector2(117.0, 43.0)
	for span in [Vector2i.ONE, Vector2i(2, 2)]:
		var area := Rect2i(PICKED, span as Vector2i)
		var bars := AssayScene.selection_mark(area, origin)
		if bars.size() != 4:
			return _fail("the %s selection mark is %d rectangles; it is a four-sided outline, so four"
					% [span, bars.size()])
		var box := Rect2(Vector2(PICKED) * TILE - origin, Vector2(span as Vector2i) * TILE)
		for bar in bars:
			if not box.encloses(bar):
				return _fail(("a %s selection bar at %s is not inside the footprint it marks (%s): "
						+ "an outline on the boundary is ambiguous by one tile") % [span, bar, box])
		# THE MIDDLE. Not the exact centre pixel alone -- a thin cross would pass that -- but the
		# whole inner half of the footprint, which is where a sprite's readable part is.
		var inner := Rect2(box.position + box.size * 0.25, box.size * 0.5)
		for x in range(int(inner.position.x), int(inner.end.x)):
			for y in range(int(inner.position.y), int(inner.end.y)):
				if _covered(bars, Vector2(x, y)):
					return _fail(("the %s selection mark covers (%d, %d), inside the middle half of "
							+ "the footprint: it would hide the machine it is selecting")
							% [span, x, y])
		# AND IT REALLY IS AN OUTLINE: all four edges carry ink, or it is a bracket by another name.
		var mid := box.position + box.size * 0.5
		for named in [["top", Vector2(mid.x, box.position.y + 1.0)],
				["bottom", Vector2(mid.x, box.end.y - 2.0)],
				["left", Vector2(box.position.x + 1.0, mid.y)],
				["right", Vector2(box.end.x - 2.0, mid.y)]]:
			if not _covered(bars, named[1] as Vector2):
				return _fail("the %s edge of the %s selection carries no ink at %s, so this is not "
						% [named[0], span, named[1]] + "an outline")
	return true


## **THE CORE OF ASSA-348: A 2x2 SUBJECT IS OUTLINED WHOLE, NOT A QUARTER OF IT.**
##
## The sim splits its verbs the other way from the mark. `Take`, `Pickup` and `Insert` carry a
## `BuildingId` (`sim/src/command.rs`), so on three of the five verbs the subject is a whole
## building, and a smelter covers four tiles. Click any quarter of one, press Pick up, and the sim
## takes the building while the outline claimed a quarter of it.
##
## **THIS IS THE CHECK MARLOW ASKED TO BE MUTATED**: trace one tile under a 2x2 on disk and this goes
## red. It compares the two spans against each other rather than against typed pixel numbers, so it
## cannot be satisfied by a constant that happens to match today's `TILE_PX`.
func test_a_two_by_two_subject_is_outlined_whole_and_not_a_quarter() -> bool:
	var origin := Vector2(117.0, 43.0)
	var one := AssayScene.selection_box(Rect2i(PICKED, Vector2i.ONE), origin)
	var four := AssayScene.selection_box(Rect2i(PICKED, Vector2i(2, 2)), origin)
	if is_equal_approx(one.size.x, four.size.x) and is_equal_approx(one.size.y, four.size.y):
		return _fail(("a 2x2 subject is outlined %s, exactly what a 1x1 gets: three of the five "
				+ "verbs take a BUILDING, so this mark understates its own subject on a smelter")
				% four.size)
	# EXACTLY ONE TILE WIDER AND TALLER -- the span, not "bigger". A mark that grew by a fixed
	# padding would pass a looser assertion and still be wrong on a 3-wide kind.
	var want := one.size + Vector2(TILE, TILE)
	if not four.size.is_equal_approx(want):
		return _fail("a 2x2 subject is outlined %s; one tile more than the 1x1's %s is %s"
				% [four.size, one.size, want])
	# AND IT GREW THE RIGHT WAY: same top-left, because `area.position` IS the building's `pos`.
	if not four.position.is_equal_approx(one.position):
		return _fail(("the 2x2 outline starts at %s and the 1x1 at %s: the span must grow from the "
				+ "building's own `pos`, not around the clicked tile") % [four.position, one.position])
	return true


## **WHAT A PROBE READS IS THE UNION OF WHAT WAS DRAWN** (ASSA-348's hazard box, Marlow's ask).
##
## `world_layer.gd::drawn_selection` built its rect from the TILE while the bars were built from the
## geometry; two arithmetics for one rectangle. If the bars trace one tile under a 2x2 while
## `drawn_selection` goes on answering 2x2, every source-scanning check reads the wrong rect and goes
## green over the defect. `selection_box` is defined AS the union of the bars, so it cannot disagree
## with them -- this test pins that definition rather than restating the arithmetic.
func test_the_box_a_probe_reads_is_the_union_of_the_bars_that_were_drawn() -> bool:
	var origin := Vector2(117.0, 43.0)
	for span in [Vector2i.ONE, Vector2i(2, 2)]:
		var area := Rect2i(PICKED, span as Vector2i)
		var bars := AssayScene.selection_mark(area, origin)
		var union: Rect2 = bars[0]
		for i in range(1, bars.size()):
			union = union.merge(bars[i] as Rect2)
		var box := AssayScene.selection_box(area, origin)
		if not box.is_equal_approx(union):
			return _fail(("`selection_box` reports %s for a %s subject and the bars actually cover "
					+ "%s: a probe would prove a rectangle nothing painted") % [box, span, union])
		# AND IT IS THE INSET BOX, NOT THE FOOTPRINT. Stated so the 1 px is a decision on the record
		# rather than a discrepancy someone later "fixes" back into a second arithmetic.
		var foot := Rect2(Vector2(PICKED) * TILE - origin, Vector2(span as Vector2i) * TILE)
		if not foot.encloses(box):
			return _fail("the %s outline's box %s is not inside its footprint %s" % [span, box, foot])
	return true


## THE KEYLINE IS THE SAME SHAPE, ONE PIXEL BIGGER, AND IT EXISTS FOR A MEASURED REASON.
##
## ASSA-215 photographed a bare light mark on this surface at **1.55-1.64:1** against the ground and
## the ore it was marking. The guidance for a graphic that must be seen is 3:1 and this client
## refuses to write a theme under 4.5:1 for text, so an unrimmed mark here is one a player can look
## straight at and miss. `MAP_BG` under the ink makes the contrast a fact about two inks we own
## rather than about whichever species the world happened to roll.
func test_every_bar_carries_a_rim_a_pixel_bigger_than_itself() -> bool:
	var origin := Vector2(0.0, 0.0)
	for span in [Vector2i.ONE, Vector2i(2, 2)]:
		var area := Rect2i(PICKED, span as Vector2i)
		var bars := AssayScene.selection_mark(area, origin)
		var rims := AssayScene.selection_keyline(area, origin)
		if rims.size() != bars.size():
			return _fail("%d bars but %d rims at %s: every bar is rimmed or the one that is not is "
					% [bars.size(), rims.size(), span] + "the one a player loses on a bright rock")
		for i in range(bars.size()):
			if not (rims[i] as Rect2).encloses(bars[i] as Rect2):
				return _fail("rim %d (%s) does not enclose its bar (%s) at span %s"
						% [i, rims[i], bars[i], span])
	return true


## THE MARK TRAVELS WITH THE CAMERA, which is the one way this arithmetic can be wrong without
## looking wrong: a mark that ignored the origin would sit on the right tile only while the camera
## happened to be at the world's corner, and every shot we take is of a camera near a player.
func test_the_mark_moves_with_the_camera_and_not_with_the_world() -> bool:
	var at := AssayScene.selection_mark(Rect2i(PICKED, Vector2i(2, 2)), Vector2.ZERO)
	var moved := AssayScene.selection_mark(Rect2i(PICKED, Vector2i(2, 2)), Vector2(TILE, 0.0))
	for i in range(at.size()):
		var shifted: Rect2 = (at[i] as Rect2)
		shifted.position.x -= TILE
		if not shifted.is_equal_approx(moved[i] as Rect2):
			return _fail(("bar %d is at %s with the camera at the origin and %s one tile east; "
					+ "it should have moved exactly one tile west") % [i, at[i], moved[i]])
	return true


## **THE PAINTER PUTS IT ON TOP, WHICH IS THE OPPOSITE OF THE CLICK ECHO, AND THAT IS A DECISION.**
##
## `destination_mark` is painted between the floor and the standing layer because it marks the
## GROUND a body is walking to. This one marks the SUBJECT of the next button press, and the
## commonest subject is a machine or a rock that stands on its tile -- painted under the sprites it
## would be invisible exactly when it matters. It can sit on top without hiding anything only
## because the test above holds the middle of the tile open.
##
## A source scan, with `test_click_echo.gd`'s caveat in full: it cannot tell you the call ran. What
## it holds is the two things a picture would not show as broken for a week -- the paint order, and
## that the ink is the map's own `target` token rather than a 22nd colour literal.
func test_the_selection_is_painted_over_what_stands_on_the_tile() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/world_layer.gd")
	if source.is_empty():
		return _fail("could not read res://scripts/world_layer.gd")
	var body := source.substr(source.find("func _draw() -> void:"))
	body = body.substr(0, body.find("\nfunc "))
	if body.is_empty() or not body.contains("selection_mark("):
		return _fail("world_layer.gd::_draw does not call AssayScene.selection_mark: the tile the "
				+ "buttons act on is drawn nowhere the suite can see it")
	var standing_blit := body.find("AssayScene.STANDING:")
	var mark := body.find("selection_mark(")
	if standing_blit < 0:
		return _fail("could not find the STANDING blit loop in _draw to place the mark after it")
	if mark < standing_blit:
		return _fail(("the selection outline is painted at %d, before the standing layer at %d: "
				+ "under a machine's sprite it is invisible on exactly the tiles a player selects "
				+ "a machine on") % [mark, standing_blit])
	# THE INK, read off the `draw_rect` line itself so a token named in a nearby comment cannot pass
	# for it. `mark_ink(&"target")` is what the schematic already paints this same fact in.
	# `draw_rect(edge` AND NOT `draw_rect(bar`: the destination's scan in `test_click_echo.gd`
	# already owns that prefix, and when this block first used it too, the older test started
	# inspecting the newer mark and went red. Two scans over one function need two names.
	var painted := ""
	for line in body.split("\n"):
		var text := String(line).strip_edges()
		if text.begins_with("draw_rect(edge,"):
			painted = text
	if painted == "":
		return _fail("no `draw_rect(edge, ...)` line found for the selection outline")
	if not painted.contains("mark_ink(&\"target\")"):
		return _fail(("the selection outline is painted with `%s`. It must be "
				+ "`AssayHud.mark_ink(&\"target\")` -- the token the schematic already uses for the "
				+ "tile the buttons act on, so one fact has one ink on both surfaces") % painted)
	# **AND THE PROBE'S RECT IS THE BARS' OWN UNION** (ASSA-348). `drawn_selection` used to be
	# rebuilt here out of the tile and `TILE_PX`, which is a second arithmetic for one rectangle: let
	# the bars trace a quarter of a smelter and it would go on reporting the whole of it. Scanned
	# rather than measured because `_draw` never runs in a headless suite, so the assignment itself is
	# the only thing this runner can see.
	var reported := ""
	for line in body.split("\n"):
		var text := String(line).strip_edges()
		if text.begins_with("drawn_selection ="):
			reported = text
	if reported == "":
		return _fail("no `drawn_selection =` line in _draw: nothing records what was painted")
	if not reported.contains("AssayScene.selection_box("):
		return _fail(("`%s` builds the probe's rect a second way. It must be "
				+ "`AssayScene.selection_box(...)`, which is defined as the union of the very bars "
				+ "drawn above, so a mark that shrinks cannot keep reporting the size it had")
				% reported)
	return true
