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
func test_the_selected_tile_is_outlined_and_open_in_the_middle() -> bool:
	var origin := Vector2(117.0, 43.0)
	var bars := AssayScene.selection_mark(PICKED, origin)
	if bars.size() != 4:
		return _fail("the selection mark is %d rectangles; it is a four-sided outline, so four"
				% bars.size())
	var tile := Rect2(Vector2(PICKED) * TILE - origin, Vector2(TILE, TILE))
	for bar in bars:
		if not tile.encloses(bar):
			return _fail(("a selection bar at %s is not inside the tile it marks (%s): an outline "
					+ "on the boundary is ambiguous by one tile") % [bar, tile])
	# THE MIDDLE. Not the exact centre pixel alone -- a thin cross would pass that -- but the whole
	# inner half of the tile, which is where a sprite's readable part is.
	var inner := Rect2(tile.position + Vector2.ONE * (TILE * 0.25), Vector2(TILE, TILE) * 0.5)
	for x in range(int(inner.position.x), int(inner.end.x)):
		for y in range(int(inner.position.y), int(inner.end.y)):
			if _covered(bars, Vector2(x, y)):
				return _fail(("the selection mark covers (%d, %d), inside the middle half of the "
						+ "tile: it would hide the rock or machine it is selecting") % [x, y])
	# AND IT REALLY IS AN OUTLINE: all four edges carry ink, or it is a bracket by another name.
	var mid := tile.position + Vector2(TILE, TILE) * 0.5
	for named in [["top", Vector2(mid.x, tile.position.y + 1.0)],
			["bottom", Vector2(mid.x, tile.end.y - 2.0)],
			["left", Vector2(tile.position.x + 1.0, mid.y)],
			["right", Vector2(tile.end.x - 2.0, mid.y)]]:
		if not _covered(bars, named[1] as Vector2):
			return _fail("the %s edge of the selected tile carries no ink at %s, so this is not an "
					% [named[0], named[1]] + "outline")
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
	var bars := AssayScene.selection_mark(PICKED, origin)
	var rims := AssayScene.selection_keyline(PICKED, origin)
	if rims.size() != bars.size():
		return _fail("%d bars but %d rims: every bar is rimmed or the one that is not is the one "
				% [bars.size(), rims.size()] + "a player loses on a bright rock")
	for i in range(bars.size()):
		if not (rims[i] as Rect2).encloses(bars[i] as Rect2):
			return _fail("rim %d (%s) does not enclose its bar (%s)" % [i, rims[i], bars[i]])
	return true


## THE MARK TRAVELS WITH THE CAMERA, which is the one way this arithmetic can be wrong without
## looking wrong: a mark that ignored the origin would sit on the right tile only while the camera
## happened to be at the world's corner, and every shot we take is of a camera near a player.
func test_the_mark_moves_with_the_camera_and_not_with_the_world() -> bool:
	var at := AssayScene.selection_mark(PICKED, Vector2.ZERO)
	var moved := AssayScene.selection_mark(PICKED, Vector2(TILE, 0.0))
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
	return true
