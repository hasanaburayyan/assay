extends SceneTree
## CI: local -- a shot: --headless writes a BLANK frame and reports success
## TWO BUILT THINGS ON ADJACENT TILES, IN THE CLOSE-UP, ON THE REAL WINDOW (ASSA-326 box 7).
##
##   godot --path . --script res://tools/cove_assa326_adjacent.gd -- <out_dir> [seed] [east|west]
##
## **WHY THIS TOOL EXISTS AND `window_shot.gd` CANNOT ANSWER IT.** ASSA-326 asks how many built
## things a cold reader counts in one picture. Every frame anybody here has shot holds the demo
## loop's own pair -- a smelter and a planted drill, 2.5 tiles apart on both axes, because
## `AssayDemoPlan.smelter_spot` starts at `(2, 2)` and `drill_spot` at `(0, 0)`. **No played frame in
## this repo has ever contained two buildings on ADJACENT tiles** (Cove, #427), so the one question
## the item is parked on has never had a picture to ask it of.
##
## **THE FIXTURE IS TWO SIM COMMANDS, NOT A SECOND CHAIN.** Maren priced box 1 as "a chain that
## mines for a second machine, plus a GUI run". It is cheaper than that: the loop already builds and
## places a smelter, `PlayerCommand::Pickup` returns it to the pack with its contents (`step.rs:389`,
## reach is its only gate), and `Place` puts it back wherever the sim allows. So the pair is the
## play's own two buildings, moved -- no extra ore mined, no part invented, every command the same
## `AssayActions` builder a button sends.
##
## **WHAT IT MAY NOT DO, AND DOES NOT.** It does not reach into `World`. It submits `MoveTo`,
## `Pickup` and `Place` and reads the answer back out of `AssaySim.buildings()`: a refused `Place`
## leaves the smelter in the pack, and this run fails on that state rather than reporting a pair it
## never saw. `REACH` below is used only to CHOOSE a tile to stand on; the sim still decides.
##
## **EAST BY DEFAULT, BECAUSE THE OVERHANG GOES EAST.** `_composite_place` draws a 1x1 machine 64 px
## wide on a 32 px tile (`tiles [2, 1]`, Maren's #442: 95.3% of the neighbour's RECT, 43.5% of its
## INK), so a smelter placed east of the drill is standing exactly where the drill's picture already
## is. `west` puts it on the other side for the control, and the run prints which it took.
##
## **AND THE PAIR IS NOT THE UNSTABLE SORT CASE, WHICH I SAY HERE SO NOBODY READS IT AS ONE.** Box 8
## is about two machines sharing a `bottom` and therefore a `sort_custom` the file calls unstable. A
## 2x2 smelter's bottom row is one south of a 1x1 machine's, so this pair sorts deterministically and
## the smelter is painted over the drill's overhang. Two ONE-TILE machines in a row is the unstable
## case and it needs two full part chains; it is not this shot.
##
## Writes one frame and prints `ADJACENT SHOT OK` LAST and only on success, because Godot exits 0
## even on a compile error.
##
## **THE LAYOUT IS ASSA-294's BLIND LAYOUT, ALWAYS, WITH NO FLAG.** The picture goes to
## `<out_dir>/frames/` and everything that NAMES what is in it to `<out_dir>/key/`. This tool has
## exactly one purpose and it is a cold read, so the safe layout is not an option a tired asker can
## forget to pass.
##
## **AND THE FRAME'S OWN NAME IS PART OF THE FRAMES DIRECTORY** — see `blind_frame_name` below. It
## used to be `01-closeup-two-machines-east.png`, which told the cold reader the answer to the only
## question being asked, from inside the directory the split was supposed to make safe.

## The seed the ASSA-273 pair was shot on, so a reader comparing frames is on known ground.
const DEFAULT_SEED := "777042"
## Offline ticks the loop may take. `button_session.gd`'s own budget, for the same reason: an
## underestimate turns a real failure into "ask for more ticks", which is the confusing way round.
const PLAY_TICKS := 4000
## Ticks per frame while the world runs, so containers get to lay out between slices.
const TICKS_PER_FRAME := 40
## Ticks a walk may take. The stand tile is within four tiles of the machine, so this is slack.
const WALK_TICKS := 200
## Ticks the toast gets to age out before the shot. `main.gd::SAYING_DWELL_TICKS` is 20 and this is
## ten times it, because the dwell is measured from the LAST thing said and the world keeps acting.
const QUIET_TICKS := 200
## Frames to let the screen settle before a shot: layout is deferred, so the first frame after a
## change photographs the state before it.
const SETTLE_FRAMES := 6
const RUN_CEILING := 900.0
## `sim::tuning::REACH`, repeated ONLY to pick a tile to stand on -- the same licence
## `AssayDemoPlan` takes for its quantities. Nothing here decides whether a command is legal.
const REACH := 3

var _out := ""
var _frames := ""
var _key := ""
var _seed := DEFAULT_SEED
var _side := "east"

var _screen: Node = null
var _play: AssayButtonPlay = null
var _asked: Array = []
var _step := 0
var _settle := 0
var _left := PLAY_TICKS
var _started := false
var _done := false
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

var _smelter_id := -1
var _smelter_item: Dictionary = {}
var _machine_at := Vector2i(-1, -1)
var _anchor := Vector2i(-1, -1)
var _stand := Vector2i(-1, -1)
var _walk_sent := false
var _walked := 0
var _quiet_ticks := 0
var _pair: Array = []
var _notes := PackedStringArray()


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_bail("usage: -- <out_dir> [seed] [east|west]")
		return
	_out = String(argv[0])
	if argv.size() > 1:
		_seed = String(argv[1])
	if argv.size() > 2:
		_side = String(argv[2])
	if _side != "east" and _side != "west":
		_bail("side must be east or west, not %s" % _side)
		return
	_frames = _out.path_join("frames")
	_key = _out.path_join("key")
	for dir in [_frames, _key]:
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			_bail("cannot write to %s" % dir)
			return
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND: a `--script` run works inside `SceneTree._initialize`, before the root window
	# is in the tree, so the engine's own call comes too late. Same note as `window_shot.gd`.
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)
	print("window %s, viewport %s, seed %s, side %s"
			% [DisplayServer.window_get_size(), root.size, _seed, _side])
	_step = 1


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		_bail("ran past its %ds ceiling at step %d" % [int(RUN_CEILING), _step])
		return true
	match _step:
		1:
			_settle_then(2)
		2:
			_play_frames()
		3:
			_plan()
		4:
			_walk()
		5:
			_take()
		6:
			_put()
		10:
			_aim_off_the_pair()
		7:
			_settle_then(8)
		9:
			_quiet()
		8:
			_shoot_and_report()
	return _done


## OFFLINE: THIS SCRIPT IS THE RELAY. Lifted from `window_shot.gd::_begin_offline`, which lifted it
## from `button_session.gd`, so the handshake has one implementation and this has no command path of
## its own.
func _begin_offline() -> bool:
	var welcome := AssaySimHost.fresh_welcome_json(_seed, "cove")
	if welcome == "":
		_bail("could not make a world on seed %s" % _seed)
		return false
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		_bail("offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return false
	return true


func _play_frames() -> void:
	if not _started:
		if not _begin_offline():
			return
		_started = true
	for _i in range(TICKS_PER_FRAME):
		if _left <= 0:
			_bail("the loop did not finish inside %d ticks (step %s)" % [PLAY_TICKS, _play.step])
			return
		_left -= 1
		_play.advance()
		if _play.failed != "":
			_bail("the demo loop failed: %s" % _play.failed)
			return
		if _play.finished:
			_notes.append("the loop finished: %s" % _play.outcome)
			print("  %s" % _play.outcome)
			_step = 3
			return
		if not _tick(_drain_asked()):
			return


## WHICH TWO BUILDINGS, AND WHERE THE SECOND ONE IS GOING. Read out of the sim, never off
## `AssayButtonPlay`'s own `_smelter_at` / `_drill_at`: those are what the loop ASKED for, and the
## only thing worth shooting is what the world says stands there.
func _plan() -> void:
	var smelter := _one_of("smelter")
	var machine := _one_of("machine")
	if smelter.is_empty() or machine.is_empty():
		_bail("the play left %d smelters and %d machines standing, so there is no pair to move"
				% [_count_of("smelter"), _count_of("machine")])
		return
	_smelter_id = int(smelter["id"])
	_machine_at = top_left_of(machine)
	# The anchor is the smelter's TOP-LEFT tile, which is what `Place` takes. East of a 1x1 machine
	# at M that is M + (1, 0); west is M + (-2, 0), because a 2x2 reaches one tile right and down.
	_anchor = _machine_at + (Vector2i(1, 0) if _side == "east" else Vector2i(-2, 0))
	var world: Vector2i = _screen._sim.size_tiles()
	for tile in _rect_tiles(_anchor, Vector2i(2, 2)):
		var at: Vector2i = tile
		if at.x < 0 or at.y < 0 or at.x >= world.x or at.y >= world.y:
			_bail("the %s anchor %s falls outside the world %s" % [_side, _anchor, world])
			return
	_stand = _stand_tile(smelter)
	if _stand == Vector2i(-1, -1):
		_bail("no free tile is within reach of both the smelter at %s and the anchor %s"
				% [top_left_of(smelter), _anchor])
		return
	print("  smelter %d at %s, machine at %s -> anchor %s, standing at %s"
			% [_smelter_id, top_left_of(smelter), _machine_at, _anchor, _stand])
	_step = 4


## A TILE THAT CAN REACH BOTH, chosen in a fixed order so the answer is a pure function of the
## world. Both commands are checked by the sim against `Building::distance_from`, which is Chebyshev
## to the footprint RECT (`building.rs:388`), so this uses the same measure and the same number -- a
## stand tile picked on a different metric would be refused and read as a design fact.
func _stand_tile(smelter: Dictionary) -> Vector2i:
	var world: Vector2i = _screen._sim.size_tiles()
	var smelter_rect := Rect2i(top_left_of(smelter), footprint_of(smelter))
	var anchor_rect := Rect2i(_anchor, Vector2i(2, 2))
	var machine_rect := Rect2i(_machine_at, Vector2i(1, 1))
	for dy in range(-REACH - 1, REACH + 2):
		for dx in range(-REACH - 1, REACH + 2):
			var at: Vector2i = _machine_at + Vector2i(dx, dy)
			if at.x < 0 or at.y < 0 or at.x >= world.x or at.y >= world.y:
				continue
			# Not inside anything that stands now, not inside where the smelter is going, and not
			# on the machine: a body cannot walk onto a building's tile.
			if _standing_on(at) or anchor_rect.has_point(at) or machine_rect.has_point(at):
				continue
			if _chebyshev_to(smelter_rect, at) > REACH:
				continue
			if _chebyshev_to(anchor_rect, at) > REACH:
				continue
			return at
	return Vector2i(-1, -1)


## WALK, AND READ THE ARRIVAL OFF THE SIM. `MoveTo` is a standing destination, so it is submitted
## once; counting ticks instead of checking `pos` is the mistake `window_shot.gd`'s north walk
## records one layer down -- a number of ticks is not a state.
func _walk() -> void:
	if not _walk_sent:
		_walk_sent = true
		if not _tick([_input(AssayActions.move_to(_stand))]):
			return
		return
	if _my_tile() == _stand:
		print("  stood on %s after %d ticks" % [_stand, _walked])
		_step = 5
		return
	_walked += 1
	if _walked > WALK_TICKS:
		_bail("walked %d ticks and never reached %s (still at %s)"
				% [WALK_TICKS, _stand, _my_tile()])
		return
	_tick([])


## PICK THE SMELTER UP, AND BELIEVE THE WORLD RATHER THAN THE COMMAND. A `Pickup` the sim refused
## leaves the building standing and the pack empty, which is a different picture from the one this
## tool is named for.
func _take() -> void:
	if not _tick([_input(AssayActions.pickup(_smelter_id))]):
		return
	if not _one_by_id(_smelter_id).is_empty():
		_bail("Pickup was refused: the smelter %d still stands at %s, so the player at %s is out of "
				% [_smelter_id, top_left_of(_one_by_id(_smelter_id)), _my_tile()]
				+ "reach or the command never arrived")
		return
	for entry in _screen._sim.inventory_of(_screen._client.player_id):
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) == "smelter":
			_smelter_item = AssayActions.item_of_stack(stack)
			break
	if _smelter_item.is_empty():
		_bail("the smelter came off the map and no smelter stack is in the pack")
		return
	_step = 6


## PUT IT BACK ON THE TILE BESIDE THE MACHINE, and fail on the sim's answer, not on the submission.
func _put() -> void:
	if not _tick([_input(AssayActions.place(_smelter_item, _anchor))]):
		return
	var placed := _one_of("smelter")
	if placed.is_empty():
		_bail("Place was refused: no smelter stands anywhere, and the pack still holds %s"
				% [_smelter_item])
		return
	if top_left_of(placed) != _anchor:
		_bail("a smelter stands at %s and the anchor asked for was %s"
				% [top_left_of(placed), _anchor])
		return
	_step = 10


## **PARK THE TARGET WHERE IT CANNOT BE IN THE PICTURE** (ASSA-355 box 1, Maren 02:23Z).
##
## The frame this tool shot for ASSA-326 carried the selection ring on the 1x1 machine, and Nacre's
## cold read turned on it: *"I would not have called it built if the white box had not been drawn on
## it… Without it I think I would have called the whole mass one thing."* That last clause is an
## INTROSPECTION. ASSA-355's first box is the observation — the same pair with the target on neither
## building — and until it exists, *"two abutting buildings read as one"* rests on a reader imagining
## a picture they were not shown.
##
## **THE RING IS A PLACEMENT RESIDUE, WHICH IS WHY THIS COSTS A CLICK AND NOT A FIXTURE** (Maren's
## amendment to her own exclusion 1). `main.gd:6208-6212` returns into the machine menu on either
## button over an occupied tile, **before** the one line that assigns `_target` — so a player cannot
## aim the ring at a standing building at all, and the one in the old frame was left behind by the
## play chain that planted the drill. Right-click anywhere empty and it moves.
##
## **IT GOES OUTSIDE THE DRAWN WINDOW, NOT MERELY OFF THE TWO BUILDINGS.** The box says "on NEITHER",
## and a ring parked on a visible empty tile would satisfy that wording while still putting the
## frame's brightest mark in front of the reader — a distractor in the exact channel the last read
## tripped on. Outside the window there is nothing to discount.
##
## **AND THE CLICK IS THE PLAYER'S PATH, NOT A FIELD ASSIGNMENT.** `point_of_tile` is the screen's
## own answer to where a tile is and `_unhandled_input` is the handler a mouse reaches, so this
## exercises the same return-into-the-menu branch a player would. Setting `_target` directly would
## park the ring and prove nothing about whether a player can.
func _aim_off_the_pair() -> void:
	_shut_the_panel()
	var view: Dictionary = _screen._world.view
	var window := AssayScene.visible_tiles(view["origin"], view["size"], view["world_tiles"])
	var away := _a_tile_off_the_window(window, view["world_tiles"])
	if away == Vector2i(-1, -1):
		_bail("no empty tile outside the drawn window %s to park the target on" % window)
		return
	if not _click_right(away):
		_bail("the screen has no cell size, so a tile cannot be turned into a click")
		return
	# THE OUTCOME, NOT THE GESTURE. A click that lands in the machine menu changes nothing here and
	# would leave the residue exactly where the play chain left it.
	if not _screen._targeted or _screen._target != away:
		_bail("aimed %s but the target is %s, so the residue is still where the play left it"
				% [away, _screen._target if _screen._targeted else "unset"])
		return
	_notes.append("the target was parked on %s, outside the drawn window %s, so this frame holds "
			% [away, window] + "no selection ring at all -- ASSA-355 box 1's baseline")
	print("  target parked on %s, outside the drawn window %s" % [away, window])
	_step = 9


## **PRESS ESC, BECAUSE THE CHAIN NOW ENDS WITH THE BUILD SCREEN STANDING OVER THE WORLD.**
##
## `_shoot_and_report`'s first check has caught it since #440: a played chain leaves `_build_verb`
## set, and nothing closes that screen except the Close button, Esc, opening a machine menu, or the
## sim stopping (`main.gd:1749 / 2138 / 4126 / 4453`). Building something does NOT close it, which
## is a reasonable product decision — you may want to build again — and it means a tool that plays
## and then photographs has to put the panel away itself.
##
## **THIS IS NOT MY CHANGE AND I CHECKED RATHER THAN ASSUMED.** The run that first hit it was the
## one with the aim step in, so the aim step was the suspect. A control on the same `origin/main`
## (a2ce195) with the aim step STASHED fails at exactly the same line, so the panel is main's and
## the click is innocent. The frame this tool shot on 10-08 at 19:00 predates tonight's build-screen
## work and got away with it.
##
## **ESC RATHER THAN THE CLOSE BUTTON**, because `_unhandled_key_input` documents it as the gesture
## every pop-up answers to and calls both closes unconditionally — *"each close is a no-op on a
## surface that is shut"* — so this cannot depend on which panel happens to be up. The outcome is
## read back off `_build_screen_open()`; a key event that reached nothing would otherwise look the
## same as one that worked.
func _shut_the_panel() -> void:
	if not _screen._build_screen_open():
		return
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_screen._unhandled_key_input(esc)
	if _screen._build_screen_open():
		_bail("Esc did not close the build screen, so this frame would be a picture of a panel")
		return
	_notes.append("the build screen was open when the chain finished and Esc closed it before the "
			+ "shot; nothing built it into the picture")
	print("  the build screen was open after the chain; Esc closed it")


## An EMPTY tile outside the drawn window, searched outward from the machine so the walk home is
## short and the answer is deterministic for a seed. Empty matters twice: an occupied tile opens a
## menu instead of moving the cursor, and a menu is a panel standing over the world.
func _a_tile_off_the_window(window: Rect2i, world_tiles: Vector2i) -> Vector2i:
	for radius in range(2, 48):
		for step in [Vector2i(0, radius), Vector2i(0, -radius), Vector2i(radius, 0),
				Vector2i(-radius, 0)]:
			var tile: Vector2i = _machine_at + step
			if tile.x < 0 or tile.y < 0 or tile.x >= world_tiles.x or tile.y >= world_tiles.y:
				continue
			if window.has_point(tile):
				continue
			if _screen._sim.tile_at(tile).get("building") != null:
				continue
			return tile
	return Vector2i(-1, -1)


## A RIGHT-CLICK ON A TILE, THROUGH THE HANDLER A MOUSE REACHES. Lifted from `button_play.gd::_click`
## including the reason for the view switch: a tile outside the close-up's window has no point on
## that view, so the press has to be made on the schematic, which is the whole reason the schematic
## exists. The view is put back before anything is photographed.
func _click_right(tile: Vector2i) -> bool:
	if _screen._cell <= 0.0:
		return false
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	var was: bool = _screen._close_up
	if was and not AssayHud.world_rect().has_point(_screen.point_of_tile(tile)):
		_screen._show_close_up(false)
	event.position = _screen.point_of_tile(tile)
	_screen._unhandled_input(event)
	if was != _screen._close_up:
		_screen._show_close_up(was)
	return true


## **WAIT FOR THE SCREEN TO STOP SAYING WHAT I JUST DID, AND IT IS NOT A TIDY-UP.** The first frame
## this tool wrote carried `Place 0 · submitted` in the toast over the world's bottom-left: a cold
## reader asked *"how many built things are in this picture"* would have been told by the picture
## that something was placed a moment ago. That is the panel-text leak Marlow declared himself on
## ASSA-273, except here I would have built it in -- ASSA-294's `blind` layout separates the key
## from the frames and can do nothing about a sentence INSIDE the frame.
##
## The toast is a `Say.JOINED` line, so it ages out after `SAYING_DWELL_TICKS` of the WORLD's clock
## (`main.gd:2783`) -- which is why this ticks rather than waits on frames. The deadline makes it a
## check and not a pause: a toast that never clears is reported in the key and in the run, so the
## reader's answer can be discounted instead of trusted.
func _quiet() -> void:
	if not _screen._says_toast.visible:
		_step = 7
		return
	_quiet_ticks += 1
	if _quiet_ticks > QUIET_TICKS:
		_notes.append("THE TOAST NEVER CLEARED in %d ticks: this frame still names a command, so a "
				% QUIET_TICKS + "cold read taken on it is primed and must be discounted")
		print("  the toast never cleared; shooting anyway and saying so")
		_step = 7
		return
	_tick([])


## THE SHOT, AND THE THREE THINGS THAT COULD MAKE IT A LIE.
##
## 1. **A PANEL STANDING OVER THE WORLD** (#432/#440). Every whole-world frame taken through a
##    played chain for two hours on 10-08 was a picture of the `make` screen, and nothing failed: the
##    chain printed FINISHED and the shot was of a full-screen panel. So the build screen is asked,
##    by its own one reader, before the picture is written.
## 2. **THE PAIR OUT OF FRAME.** The camera is on the body, so a machine four tiles away is normally
##    in shot -- but "normally" is not a check. `visible_tiles` is the painter's own window and both
##    footprints have to be inside it.
## 3. **A FLAT FRAME**, which is `window_shot.gd`'s own first check: a dummy driver or a dead
##    viewport reads back one colour and reports success.
func _shoot_and_report() -> void:
	if _screen._build_screen_open():
		_bail("the build screen is open, so this frame would be a picture of a panel")
		return
	var view: Dictionary = _screen._world.view
	var window := AssayScene.visible_tiles(view["origin"], view["size"], view["world_tiles"])
	_pair = []
	for entry in _screen._sim.buildings():
		var building: Dictionary = entry
		var rect := Rect2i(top_left_of(building), footprint_of(building))
		_pair.append({"id": int(building["id"]), "kind": String(building["kind"]),
				"name": String(building.get("name", "")), "pos": rect.position,
				"foot": rect.size, "in_frame": window.encloses(rect)})
		if not window.encloses(rect):
			_bail("the %s at %s is not inside the drawn window %s"
					% [String(building["kind"]), rect.position, window])
			return
	var image := root.get_texture().get_image()
	if image == null:
		_bail("no frame to read")
		return
	var seen := {}
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			seen[image.get_pixel(x, y).to_rgba32()] = true
	if seen.size() < 2:
		_bail("the frame is one flat colour, so nothing drew")
		return
	# **4. THE RING, COUNTED IN THE PICTURE RATHER THAN ARGUED FROM THE WINDOW.** `_aim_off_the_pair`
	# parks the target outside the drawn window and checks `_target`; that is a claim about state,
	# and what the cold reader gets is the FRAME. Maren found the old ring by counting this exact
	# paint — *"exactly 224 pixels of HOVER (242,242,242) exist in the whole 1280x720 frame… every
	# pure-white pixel in that picture is the selection ring and nothing else is"* — so the same
	# count is the check, read off the painter's own ink and never typed. Striding would be wrong
	# here where it is right above: 224 px is findable by a reader and missable by a stride of 4.
	var ring := AssayHud.mark_ink(&"target").to_rgba32()
	var ring_px := 0
	var ring_first := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).to_rgba32() == ring:
				ring_px += 1
				if ring_first == Vector2i(-1, -1):
					ring_first = Vector2i(x, y)
	if ring_px > 0:
		_bail(("%d px of the target's own ink are in this frame, first at %s, so it is not "
				% [ring_px, ring_first]) + "ASSA-355's baseline: a reader would see the mark that "
				+ "manufactured the boundary last time")
		return
	_notes.append("target ink in the frame: 0 px, counted exactly over all %d x %d"
			% [image.get_width(), image.get_height()])
	var name := blind_frame_name(1)
	if not _is_blind_name(name):
		_bail("the frame would be called %s, which is not a blind name" % name)
		return
	var path := _frames.path_join(name)
	if image.save_png(path) != OK:
		_bail("cannot write %s" % path)
		return
	var verdict := _adjacency()
	var lines := PackedStringArray()
	lines.append("ASSA-326 box 7: a close-up frame holding two ADJACENT built things.")
	lines.append("seed %s, side %s, tick %d, frame %s (%dx%d, %d colours)"
			% [_seed, _side, _screen._sim.tick(), name, image.get_width(), image.get_height(),
			seen.size()])
	lines.append("cell %d px, drawn window %s, camera origin %s"
			% [int(AssayScene.TILE_PX), window, view["origin"]])
	lines.append("player at %s" % _my_tile())
	for entry in _pair:
		var row: Dictionary = entry
		lines.append("  %-8s id %d  top-left %s  footprint %s  %s"
				% [row["kind"], row["id"], row["pos"], row["foot"], row["name"]])
	lines.append("how the two footprints stand to each other: %s" % verdict)
	lines.append("the toast that names commands, at the shot: %s"
			% ("VISIBLE, so this frame is PRIMED" if _screen._says_toast.visible else "absent"))
	for note in _notes:
		lines.append("note: %s" % note)
	var key := FileAccess.open(_key.path_join("what-is-in-the-frame.txt"), FileAccess.WRITE)
	if key == null:
		_bail("cannot write the key")
		return
	key.store_string("\n".join(lines) + "\n")
	key.close()
	print("")
	for line in lines:
		print(line)
	if verdict != "SHARING AN EDGE":
		_bail("the two footprints are %s, so this frame is not the pair box 7 asks for" % verdict)
		return
	print("ADJACENT SHOT OK")
	_finish(0)


## **A BLIND FRAME'S NAME IS A NUMBER AND NOTHING ELSE, AND I LEARNED THAT BY LOSING AN ANSWER.**
##
## This tool wrote `01-closeup-two-machines-east.png`. Nacre opened it for ASSA-326 box 7's cold
## read and declared the contamination before the first pixel: *"I read the path to open the file.
## The words 'two machines' were in my head before the first pixel was. Discount my Q1 number
## accordingly — it is the one answer you cannot trust from me."* The question was **how many built
## things are in this picture**, and the picture's own name answered it.
##
## ASSA-294's layout splits the key from the frames, and I defeated it from inside the frames
## directory. `window_shot.gd::_names_marks` would not have caught this either: it refuses `-key.`
## and `marks`, so a name that states the SUBJECT sails through the same way `09-whole-world-key.png`
## once sailed through an extension check. That hole is in a file that is not mine and is flagged on
## the item rather than edited here.
##
## **SO THE RULE IS NOT A BLACKLIST OF WORDS.** A blacklist is a guess about what the next frame will
## be about, and I would have had to guess "machines" before Nacre read it. A name that is two digits
## and an extension can carry nothing at all, whatever the picture turns out to hold. The key already
## says which number is which — it prints `seed`, `side`, the tick, both buildings and the frame's
## name — so nothing is lost but the leak.
static func blind_frame_name(index: int) -> String:
	return "%02d.png" % index


## The same rule as a predicate, so the tool refuses rather than trusting the line above it. A
## generator and its own check in one expression would assert nothing — this is read back off the
## string that is about to become a filename.
static func _is_blind_name(name: String) -> bool:
	if not name.ends_with(".png"):
		return false
	var stem := name.substr(0, name.length() - 4)
	if stem.length() != 2:
		return false
	return stem.is_valid_int()


## HOW THE TWO FOOTPRINTS STAND TO EACH OTHER, IN WORDS, and the first version of this got it wrong
## in the direction that matters: **IT CALLED A TRUE PAIR A MISS.**
##
## I wrote `Building::distance_from`'s Chebyshev-to-a-rect and compared it to 0. That measure is
## written for a POINT against a RECT, where 0 means inside -- so two rects that share an edge come
## out at **1**, and the run refused a frame in which the machine at (74, 36) and the smelter at
## (75, 36) really are side by side. A verdict function is a claim like any other, and this one was
## measured against a threshold borrowed from a different question.
##
## SO IT IS DONE PER AXIS, BECAUSE "ADJACENT" IS NOT ONE NUMBER. Two rects share an EDGE when they
## abut on one axis and OVERLAP on the other; abutting on both is a CORNER, which touches and shares
## no side. Returned as a sentence rather than an int for that reason: a single number cannot tell
## those two apart, and a corner pair is not the picture box 7 asks for.
func _adjacency() -> String:
	if _pair.size() != 2:
		return "%d buildings, not a pair" % _pair.size()
	var a := Rect2i(_pair[0]["pos"], _pair[0]["foot"])
	var b := Rect2i(_pair[1]["pos"], _pair[1]["foot"])
	var gap_x := _axis_gap(a.position.x, a.size.x, b.position.x, b.size.x)
	var gap_y := _axis_gap(a.position.y, a.size.y, b.position.y, b.size.y)
	if gap_x < 0 and gap_y < 0:
		return "OVERLAPPING, which the sim refuses, so this is a bug in this tool"
	if (gap_x == 0 and gap_y < 0) or (gap_y == 0 and gap_x < 0):
		return "SHARING AN EDGE"
	if gap_x == 0 and gap_y == 0:
		return "TOUCHING AT A CORNER ONLY"
	return "%d tile(s) apart on x and %d on y" % [maxi(gap_x, 0), maxi(gap_y, 0)]


## Empty tiles between two spans on one axis: 0 when they abut, NEGATIVE when they overlap. The sign
## carries the overlap, which is what lets an edge be told from a corner above.
func _axis_gap(a_at: int, a_len: int, b_at: int, b_len: int) -> int:
	if a_at <= b_at:
		return b_at - (a_at + a_len)
	return a_at - (b_at + b_len)


func _chebyshev_to(rect: Rect2i, at: Vector2i) -> int:
	var dx: int = maxi(maxi(rect.position.x - at.x, at.x - (rect.position.x + rect.size.x - 1)), 0)
	var dy: int = maxi(maxi(rect.position.y - at.y, at.y - (rect.position.y + rect.size.y - 1)), 0)
	return maxi(dx, dy)


func _rect_tiles(at: Vector2i, foot: Vector2i) -> Array:
	var tiles: Array = []
	for dy in range(foot.y):
		for dx in range(foot.x):
			tiles.append(at + Vector2i(dx, dy))
	return tiles


func _standing_on(at: Vector2i) -> bool:
	for entry in _screen._sim.buildings():
		var building: Dictionary = entry
		if Rect2i(top_left_of(building), footprint_of(building)).has_point(at):
			return true
	return false


## The top-left tile of any building, spelled once -- the tile `Place` takes and the tile
## `buildings()` reports. Cast rather than returned raw: a `Dictionary.get` is a `Variant`, and a
## typed return of one is the runtime error that reads as "the tool said nothing".
static func top_left_of(building: Dictionary) -> Vector2i:
	return building.get("pos", Vector2i(-1, -1)) as Vector2i


static func footprint_of(building: Dictionary) -> Vector2i:
	return building.get("footprint", Vector2i(1, 1)) as Vector2i


func _one_of(kind: String) -> Dictionary:
	for entry in _screen._sim.buildings():
		var building: Dictionary = entry
		if String(building.get("kind", "")) == kind:
			return building
	return {}


func _one_by_id(id: int) -> Dictionary:
	for entry in _screen._sim.buildings():
		var building: Dictionary = entry
		if int(building.get("id", -1)) == id:
			return building
	return {}


func _count_of(kind: String) -> int:
	var n := 0
	for entry in _screen._sim.buildings():
		if String((entry as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


func _my_tile() -> Vector2i:
	for entry in _screen._sim.players():
		var player: Dictionary = entry
		if int(player["id"]) == _screen._client.player_id:
			return player["pos"] as Vector2i
	return Vector2i(-1, -1)


func _drain_asked() -> Array:
	var inputs: Array = []
	for command in _asked:
		inputs.append(_input(command))
	_asked.clear()
	return inputs


func _input(command: Variant) -> Dictionary:
	return {"Player": {"player": _screen._client.player_id, "command": command}}


## ONE TICK, WITH THE REFUSAL CHECK `window_shot.gd` uses: a bundle the sim will not apply is a dead
## run, and a tool that kept stepping past one would be shooting a world nobody played.
func _tick(inputs: Array) -> bool:
	var at: int = _screen._sim.tick()
	var before: int = _screen._sim.applied
	_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
	if _screen._sim.applied == before:
		_bail("the sim refused the bundle for tick %d" % at)
		return false
	return true


func _settle_then(next: int) -> void:
	_settle += 1
	if _settle >= SETTLE_FRAMES:
		_settle = 0
		_step = next


func _bail(why: String) -> void:
	print("FAIL  %s" % why)
	_finish(1)


func _finish(code: int) -> void:
	_done = true
	quit(code)
