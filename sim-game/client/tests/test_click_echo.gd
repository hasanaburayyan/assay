extends RefCounted
## THE CLICK ECHO ON THE CLOSE-UP (ASSA-215, Maren's ruling).
##
## WHAT IS BEING DEFENDED. For 190-394 ms after a left click the world is motionless -- that wait is
## the playout buffer and we are keeping it -- and until this item the screen you play on drew
## nothing in that time, so a registered walk and a dead button looked the same. The mark is the
## answer; every clause below is a way it must APPEAR OR DIE, because a mark that outlives its walk
## is worse than no mark: it is a promise the game has stopped keeping.
##
## **WHAT THIS FILE CANNOT DO, STATED FIRST.** A headless runner never draws: `_draw` runs under a
## real window and this suite has none, so no test here proves a pixel was painted. Two of the three
## tests are therefore arithmetic (`AssayScene`, which is where every drawable decision lives by this
## project's own split) and the third is a SOURCE SCAN over the painter -- it reads the call `_draw`
## makes and the order it makes it in, which is the pattern `test_map_key.gd` already uses on
## `main.gd::_draw`, and it is not evidence that the call ran.
##
## THE BEHAVIOURAL PROOF IS A REAL WINDOW AND IT IS NOT IN THIS FILE: `tools/limpet_click_echo.gd`
## clicks the map with a synthetic mouse event, reads `AssayWorldLayer.drawn_destination` (written
## inside `_draw` AFTER the `draw_rect` calls, so it cannot be true of an unpainted frame) and saves
## the frames as 1x crops. Boxes 1 and 2 are that tool's numbers, not these assertions.


const TILE := 32.0
## A tile far from every edge, so no camera clamp is in the arithmetic.
const CLICKED := Vector2i(50, 33)

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


## FOUR CORNERS OF THE TILE YOU CLICKED, AND NOTHING IN THE MIDDLE OF IT.
##
## The middle is the assertion that matters and it is Maren's box 3 in arithmetic: the mark sits on
## the thing you clicked -- ground, an ore disc, a rock with a species letter on it -- so a mark that
## filled the tile would hide the answer it is acknowledging. The corners are what makes it a
## bracket rather than a ring (`mine_ring` is already "which body is yours") or an ellipse (the foot
## mark, the other `MINE` mark on this very surface).
func test_the_clicked_tile_is_bracketed_at_its_corners_and_open_in_the_middle() -> bool:
	var origin := Vector2(117.0, 43.0)
	var bars := AssayScene.destination_mark(CLICKED, origin)
	if bars.size() != 8:
		return _fail("the destination mark is %d rectangles; it is four corners, so eight"
				% bars.size())
	var tile := Rect2(Vector2(CLICKED) * TILE - origin, Vector2(TILE, TILE))
	# NOT ONE PIXEL OUTSIDE THE TILE IT NAMES. A bracket straddling the boundary would be a click
	# acknowledgement that is ambiguous by one tile, which is the one thing it may not be.
	for bar in bars:
		if not tile.encloses(bar):
			return _fail(("a bar of the destination mark at %s is outside the tile %s it marks, so "
					+ "the mark claims a tile the player did not click") % [bar, tile])
	# EVERY CORNER CARRIES INK...
	var inset := AssayScene.DESTINATION_INSET_PX
	for dx in [inset + 0.5, TILE - inset - 0.5]:
		for dy in [inset + 0.5, TILE - inset - 0.5]:
			var corner := tile.position + Vector2(dx, dy)
			if not _covered(bars, corner):
				return _fail(("the destination mark leaves the corner %s of the clicked tile %s "
						+ "blank, so it is not a bracket on that tile") % [corner, tile])
	# ...AND THE MIDDLE CARRIES NONE. A fill, a cross or a ring all fail here; so does an arm long
	# enough to meet its neighbour, which would be a box and would cover the tile's edge pixels.
	if _covered(bars, tile.get_center()):
		return _fail("the destination mark paints the middle of the clicked tile, which is the "
				+ "ore disc or the ground the player clicked at")
	if _covered(bars, tile.position + Vector2(TILE * 0.5, inset + 0.5)):
		return _fail("the destination mark's top arms meet in the middle of the edge: that is a "
				+ "box, not four corners")
	# AND IT MOVES WITH THE CAMERA, not with the tile index: the same tile under a camera one tile
	# further east is drawn 32 px further west, the arithmetic `_place` uses for every sprite.
	var moved := AssayScene.destination_mark(CLICKED, origin + Vector2(TILE, 0.0))
	if not is_equal_approx(moved[0].position.x, bars[0].position.x - TILE):
		return _fail(("the destination mark did not follow the camera: origin + one tile moved the "
				+ "first bar from %.1f to %.1f, not %.1f") % [bars[0].position.x,
				moved[0].position.x, bars[0].position.x - TILE])
	return true


## THE FOUR WAYS THE MARK DIES, AND THE ONE WAY IT LIVES.
##
## `walk_echo` is the whole state machine; `main.gd` only sets it from a click and hands it back
## every frame. Each clause below is one of Maren's boxes or the reason the box is possible.
func test_the_click_echo_survives_the_silence_and_dies_four_ways() -> bool:
	var pending := {"tile": CLICKED, "confirmed": false}
	var here := Vector2i(48, 32)
	var elsewhere := Vector2i(60, 40)

	# NOTHING CLICKED, NOTHING DRAWN. The resting state of the whole feature.
	if not AssayScene.walk_echo({}, null, here, false).is_empty():
		return _fail("walk_echo invented a mark with no click behind it")

	# **THE SILENCE ITSELF, WHICH IS THE FEATURE.** The sim has no target for me yet and I am not
	# there: the mark must stay. A state machine that read "no target" as "no walk" would clear the
	# mark in the first frame after the click and draw nothing for the 190-394 ms this exists for.
	var waited := AssayScene.walk_echo(pending, null, here, false)
	if waited != pending:
		return _fail(("walk_echo dropped the mark while the sim had not answered yet (%s): that is "
				+ "the entire quarter second the feature is for") % waited)

	# THE BUNDLE COMES BACK: the sim says it is walking me there, so the echo is confirmed. The
	# drawn tile does not change -- the point of `confirmed` is what happens when the target LEAVES.
	var confirmed := AssayScene.walk_echo(pending, CLICKED, here, false)
	if confirmed.get("tile") != CLICKED or not bool(confirmed.get("confirmed", false)):
		return _fail("the sim confirming the walk to %s left the echo %s" % [CLICKED, confirmed])

	# ARRIVAL (Maren's box 4, first half). The SIM's position, not the drawn one: the body is still
	# tweening toward that tile for up to a tick after the sim has put it there, and a mark that
	# cleared on the drawn position would vanish a tick early, under a body still walking.
	if not AssayScene.walk_echo(confirmed, null, CLICKED, false).is_empty():
		return _fail("the mark survived arrival at the tile it marks")
	if not AssayScene.walk_echo(pending, CLICKED, CLICKED, false).is_empty():
		return _fail("a walk that arrived inside one tick kept its mark")

	# A REFUSAL (box 4, second half). Before this item a refused walk and an accepted one looked
	# identical for a quarter of a second; this is what makes them different.
	if not AssayScene.walk_echo(pending, null, here, true).is_empty():
		return _fail("a REFUSED walk kept its destination mark, which is the game promising to go "
				+ "somewhere the sim has already declined")
	if not AssayScene.walk_echo(confirmed, CLICKED, here, true).is_empty():
		return _fail("a refusal did not clear a confirmed mark")

	# THE WALK ABANDONED AFTER IT STARTED: a Stop, a second walk, anything that takes the sim's
	# target away once it has been seen. Only reachable because `confirmed` exists.
	if not AssayScene.walk_echo(confirmed, null, here, false).is_empty():
		return _fail("the sim stopped walking me there and the mark stayed, hanging over a tile "
				+ "nobody is heading to")
	if not AssayScene.walk_echo(confirmed, elsewhere, here, false).is_empty():
		return _fail("the sim is walking me to %s and the mark still says %s"
				% [elsewhere, CLICKED])

	# AND THE CASE THAT MUST NOT CLEAR: an unconfirmed click while the sim is still finishing an
	# earlier walk somewhere else. The command has not been ordered into a tick yet, so this is the
	# silence again, not an abandonment.
	if AssayScene.walk_echo(pending, elsewhere, here, false) != pending:
		return _fail("an unanswered click was dropped because the sim was still walking an older "
				+ "target, so a click during a walk draws nothing")
	return true


## WHAT THE PAINTER ACTUALLY DOES WITH IT -- AND THIS IS A SOURCE SCAN, NOT A MEASUREMENT.
##
## It reads `world_layer.gd::_draw` as text. It cannot tell you the call ran, which is why
## `drawn_destination` and `tools/limpet_click_echo.gd` exist. What it CAN hold is the two decisions
## a picture would not show as broken for a week: that the brackets are painted between the floor
## and the things standing on it, and that the ink is `MINE` rather than a 22nd colour literal
## (Maren's box 6). Both are one line away from silently drifting.
func test_the_floor_mark_is_painted_between_the_floor_and_what_stands_on_it() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/world_layer.gd")
	if source.is_empty():
		return _fail("could not read res://scripts/world_layer.gd")
	var body := source.substr(source.find("func _draw() -> void:"))
	body = body.substr(0, body.find("\nfunc "))
	if body.is_empty() or not body.contains("destination_mark("):
		return _fail("world_layer.gd::_draw does not call AssayScene.destination_mark: the clicked "
				+ "tile is decided nowhere the suite can see it")
	var floor_blit := body.find("AssayScene.FLOOR:")
	var standing_blit := body.find("AssayScene.STANDING:")
	var mark := body.find("destination_mark(")
	if floor_blit < 0 or standing_blit < 0:
		return _fail("could not find the FLOOR and STANDING blit loops in _draw to place the mark "
				+ "between them")
	if mark < floor_blit or mark > standing_blit:
		return _fail(("the destination mark is painted outside the gap between the floor (at %d) "
				+ "and what stands on it (at %d): it is at %d. On the floor it marks the ground; "
				+ "over the bodies it would be a mark that hides the person it is walking")
				% [floor_blit, standing_blit, mark])
	# THE INK. Not a new literal: `AssayHud.MINE` is the ink the walk line and the player mark
	# already share, which is the whole of box 6. Read off the `draw_rect` line itself rather than
	# off the block, so a MINE mentioned in a comment nearby cannot pass for it.
	var painted := -1
	for line in body.split("\n"):
		var text := String(line).strip_edges()
		if text.begins_with("draw_rect(bar"):
			painted = 0 if text.contains("AssayHud.MINE") else 1
			break
	if painted < 0:
		return _fail("could not find the draw_rect that paints the destination bars in _draw")
	if painted == 1:
		return _fail("the destination mark's draw_rect does not take AssayHud.MINE: it is a 22nd "
				+ "colour literal for a meaning this client already has an ink for")
	return true


## NOTHING IN `main.gd` MAY SET THE MARK FROM A SIM FACT -- ALSO A SOURCE SCAN, AND THE REASON IT
## EXISTS IS ASSA-119.
##
## The mark is an echo of an INPUT. The moment someone sets it from the sim's own `target` instead --
## which is one plausible-looking line, and it would even look better, because it would show other
## people's walks -- the client is drawing where a body is GOING, in a file whose whole discipline is
## that it may not. Every write is listed here, so adding a fifth is a red test and a decision rather
## than a tidy-up. It cannot tell you the writes RAN; it can tell you no new one appeared.
func test_the_mark_is_written_from_the_click_and_from_nowhere_else() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	if source.is_empty():
		return _fail("could not read res://scripts/main.gd")
	var allowed := {
		"_world.destination = tile": "the click handler, in the frame the click happened",
		"_world.destination = null": "_forget_click, on a refusal or a dead link",
		"_world.destination = _walk_echo.get(\"tile\")": "_refresh_world, re-derived every frame",
		"_walk_echo = {\"tile\": tile, \"confirmed\": false}": "the click handler's own echo",
		"_walk_echo = AssayScene.walk_echo(_walk_echo, null, null, true)": "_forget_click",
		"_walk_echo = AssayScene.walk_echo(_walk_echo, my_target, my_pos, false)": "_refresh_world",
	}
	var seen := {}
	for line in source.split("\n"):
		var text := String(line).strip_edges()
		if not (text.begins_with("_world.destination") or text.begins_with("_walk_echo")):
			continue
		if not allowed.has(text):
			return _fail(("main.gd writes the destination mark in a way this test does not know: "
					+ "`%s`. If it reads a sim fact, the close-up is predicting a body (ASSA-119); "
					+ "if it is honest, add it here with its reason") % text)
		seen[text] = true
	for text in allowed:
		if not seen.has(text):
			return _fail(("main.gd no longer writes `%s` (%s), so one of the three states of the "
					+ "click echo is unreachable") % [text, allowed[text]])
	return true
