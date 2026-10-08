extends SceneTree
## TWO PLAYERS IN ONE ASSAY WINDOW, PHOTOGRAPHED FOR THE FIRST TIME (Maren).
##
##   godot --path client --script res://tools/maren_coop_shot.gd \
##       -- <out_dir> [seed] [peer_name] [row] [col] [play]
##   (A GUI RUN. Never --headless: a headless viewport photographs nothing.)
##
## **THE MILESTONE IS CALLED "the minimal CO-OP demo" AND NOTHING HAS EVER PHOTOGRAPHED TWO PLAYERS.**
## `window_shot.gd` shoots five screens, `maren_whole_world_shot.gd` added a sixth, and every one of
## them is a world with exactly one person in it. So every claim any of us has made about co-op
## readability -- mine, the artist's, the ones written into these files' own docstrings -- is reasoned
## off code and has never been looked at.
##
## Three of those claims are in `scene_view.gd` and `main.gd` right now and this run is the first
## thing that can test them:
##
##   1. the close-up draws EVERY player, your partner at the same tint and the same sheet as you,
##      with the only distinction a translucent foot mark that is drawn for `me` alone;
##   2. `scene_view.gd:561` says in its own words "the camera does not tell two players apart";
##   3. the schematic gives you `MINE` plus a ring and your partner `THEIRS` and no ring.
##
## **THE PARTNER IS A REAL `sim-cli` PEER, not a second body faked into a snapshot.** It does a real
## handshake, the relay welcomes it with a real `Welcome`, and it walks because this tool types
## `goto` at its stdin -- the same command a person at a terminal types. A composed frame would prove
## the composition and nothing about the client.
##
## WHAT IT WRITES: `01-close-up-two.png` (the screen you play on), `02-whole-world-two.png` (the
## schematic, one V press away) and `03-whole-world-two-key.png` (the same frame with the key up),
## plus a verdict naming both players, which one the client thinks is mine, and how far apart they
## stand in tiles. **AND `04-marks-two.json`, THE POLYGONS THE TWO BODIES WERE PAINTED FROM**
## (ASSA-236) -- see `_write_marks_table` for why a name is not enough and what the control is.
##
## **AND `play` BUILDS A FACTORY FIRST, WHICH IS WHAT ASSA-206 BOX 3 ASKS FOR AND NOTHING COULD MAKE.**
## That box wants one frame holding a building, TWO players and a dead-end disc, judged at 1x. The two
## tools that could each make half of it could not make the other half: `window_shot.gd` plays the
## whole craft chain and plants machines but is a world with one person in it, and this tool had two
## real people and an empty map. QA's words on 2026-10-05: "I cannot make two players from the window
## tool". So `play` runs `AssayButtonPlay` -- the SAME class `button_session.gd` drives, pressing the
## screen's own buttons -- against this relay until the chain finishes, and then shoots.
##
## `advance()` IS CALLED ON `tick_bundle` AND NOT PER FRAME, copied from `button_session.gd` for its
## reason: the relay owns the clock, and the loop may only read a world that has been stepped.
##
## **THEN BOTH BODIES ARE WALKED CLEAR OF EVERY BUILDING, because the first version of the one-player
## shot photographed a 12px building diamond underneath a 16px player square** (`window_shot.gd`'s
## `PRESS_V` comment, measured there). A frame where the player mark covers the only building cannot
## answer a box that asks for both in it, so the walk-off target is CHOSEN against the building list
## and the distance it achieved is REPORTED -- for the partner's tile too, which is the one the
## original measurement did not have to think about.

const DEFAULT_SEED := "777042"
const DEFAULT_PEER := "rainy"

## OPTIONAL: a ROW and a COLUMN to walk us both to before shooting, or -1 for "wherever we spawn".
##
## **I FIRST TOOK A ROW ALONE AND SAID THE COLUMN DOES NOT MATTER. THE FIRST SHOT REFUTED THAT, so
## the knob is here and the reason is written down rather than the claim.** The row decides whether
## the camera's VERTICAL clamp binds, which is what ASSA-194's open box names. But what the box is
## really asking is whether "mine is the one in the middle" survives — and at row 61, column 56, it
## half survives: measured on `01-close-up-two.png`, my body's x runs 467..491 around a map rect
## whose centre x is 477. **The south clamp takes one axis of the centring cue away and leaves the
## other.** Only a CORNER takes both, so only a corner is the case the item reasons about.
##
## **WHY IT MATTERS THAT WE BOTH MOVE.** The partner is placed at `PEER_OFFSET` from ME, so walking
## me is enough to put both bodies at the edge. The thing under test is that at a clamped edge the
## camera does NOT centre you, so "mine is the one in the middle" stops being available and the foot
## mark is all that is left.
const DEFAULT_ROW := -1
const DEFAULT_COL := -1
const LISTEN_DEADLINE := 10.0
const JOIN_DEADLINE := 12.0
const PEER_DEADLINE := 20.0
const WALK_DEADLINE := 60.0
const SETTLE_FRAMES := 4
## **A CEILING THAT A `play` RUN CAN REACH, and the no-play path is unaffected by the size of it.**
## `button_session.gd` allows 1400 relay ticks for the same chain, which is 140 s at ten a second, and
## this run pays a relay spawn, two joins and two walks on top. 180 s was this tool's ceiling while it
## only ever walked; it would have killed every `play` run mid-chain and printed a bail, which reads
## as a defect in the client rather than as a tool that was not given time.
const RUN_CEILING := 600.0
## How long the craft chain itself gets, counted from the frame it starts.
const PLAY_DEADLINE := 420.0
## **HOW FAR EITHER BODY MUST STAND FROM EVERY BUILDING, in tiles, for the schematic to be judgeable.**
## On the 96x64 world the whole-world view draws a tile at 9 px, a building diamond at
## `AssayHud.BUILDING_MARK_PX` and a player at `PLAYER_MARK_PX`; three tiles of clearance is already
## more than either mark is wide, and four leaves room for a 2x2 smelter's footprint to be measured
## from its top-left tile without the slack becoming a different question.
const CLEAR_TILES := 4
## How far out the walk-off search may look for a tile that clears every building. The map is 96x64,
## so this reaches any of it from anywhere; it is a bound, not a tuning knob.
const CLEAR_RADIUS := 40

## WHERE THE PARTNER IS PUT, relative to me, in tiles. The close-up is 32px/tile in an 864x576 map
## rect, so about 27x18 tiles: a partner four east and one north is comfortably on screen with me and
## far enough that the two bodies do not overlap. Nothing here is a design claim -- it is the
## framing, chosen so the picture contains the thing the picture is about.
const PEER_OFFSET := Vector2i(4, -1)

var _screen: Node = null
var _relay_binary := ""
var _cli_binary := ""
var _out := ""
var _seed := DEFAULT_SEED
var _peer_name := DEFAULT_PEER
var _row := DEFAULT_ROW
var _col := DEFAULT_COL
var _my_target := Vector2i.ZERO
var _address := ""
var _relay_pid := -1
var _relay_stdio: FileAccess = null
var _relay_said := PackedStringArray()
var _peer_pid := -1
var _peer_stdio: FileAccess = null
var _peer_welcomed := false

var _step := 0
var _until := 0.0
var _settle := 0
var _done := false
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING
var _peer_target := Vector2i.ZERO
var _said := PackedStringArray()

## THE CRAFT CHAIN, or null when this run was not asked for one. `AssayButtonPlay` is the class
## `button_session.gd` drives; nothing about the loop is re-spelled here.
var _play: AssayButtonPlay = null
var _play_on := false
var _play_until := 0.0
var _play_note := ""
var _clear_target := Vector2i.ZERO


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  need an output directory")
		quit(1)
		return
	_out = String(argv[0])
	if argv.size() > 1:
		_seed = String(argv[1])
	if argv.size() > 2:
		_peer_name = String(argv[2])
	if argv.size() > 3:
		_row = int(argv[3])
	if argv.size() > 4:
		_col = int(argv[4])
	# ANY NON-EMPTY, NON-ZERO WORD TURNS THE CHAIN ON, and the word it was given is printed. A flag
	# that silently read as false would hand back the empty-map picture under the name of the one
	# ASSA-206 box 3 asked for, which is the failure that looks like a result.
	if argv.size() > 5:
		var word := String(argv[5]).strip_edges().to_lower()
		_play_on = word != "" and word != "0" and word != "no" and word != "noplay"
		print("play argument '%s' -> %s" % [word, "PLAY THE CHAIN" if _play_on else "walk only"])
	DirAccess.make_dir_recursive_absolute(_out)
	_relay_binary = AssaySoloRelay.find_binary()
	if _relay_binary == "":
		print("FAIL  no sim-relay binary")
		quit(1)
		return
	# THE PEER IS THE REFERENCE CLIENT, found beside the relay rather than guessed: whatever built one
	# built the other. A run that silently photographed a one-player world because it could not find
	# `sim-cli` would be the worst failure available here -- it would look like a clean result.
	_cli_binary = _relay_binary.get_base_dir().path_join("sim-cli")
	if not FileAccess.file_exists(_cli_binary):
		print("FAIL  no sim-cli beside the relay at %s" % _cli_binary)
		quit(1)
		return
	var saves := OS.get_user_data_dir().path_join("maren-coop-shot-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	var dir := DirAccess.open(saves)
	if dir != null:
		for stale in dir.get_files():
			dir.remove(stale)
	OS.set_environment("R2TS_SAVES_DIR", saves)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.note.connect(func(l): _said.append("note: %s" % l))
	_screen._client.link_failed.connect(func(l): _said.append("failed: %s" % l))
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])
	if not _spawn_relay():
		return
	_step = 1
	_until = _now() + LISTEN_DEADLINE


func _process(_delta: float) -> bool:
	if _done:
		return true
	if _now() >= _ceiling:
		_bail("ran past its ceiling at step %d" % _step)
		return true
	match _step:
		1:
			_wait_then_join()
		2:
			_wait_for_the_world()
		3:
			_start_the_peer()
		4:
			_wait_for_the_peer()
		30:
			_playing()
		31:
			_walk_clear_of_every_building()
		32:
			_wait_for_the_clear_arrival()
		40:
			_walk_me_to_the_row()
		41:
			_wait_for_my_arrival()
		5:
			_send_the_peer_walking()
		6:
			_wait_for_the_peer_to_arrive()
		7:
			_settle_then(8)
		8:
			_shoot("01-close-up-two.png")
			_step = 9
		9:
			# THE PRESS ITSELF, not `_show_close_up` -- what a person's click does.
			_screen._view_toggle.emit_signal("pressed")
			_step = 10
		10:
			_settle_then(11)
		11:
			_shoot("02-whole-world-two.png")
			_write_marks_table()
			_step = 12
		12:
			# THE PRESS ITSELF AGAIN, and its VISIBILITY is recorded rather than assumed: a state a
			# player cannot reach is not worth photographing (`window_shot.gd`'s own words), and this
			# button is created hidden (`main.gd:592`) and only shown on the schematic.
			_play_note += "  key toggle visible=%s text='%s'\n" % [
					_screen._map_key_toggle.visible, _screen._map_key_toggle.text]
			_screen._map_key_toggle.emit_signal("pressed")
			_step = 13
		13:
			_settle_then(14)
		14:
			_shoot("03-whole-world-two-key.png")
			_report()
	return _done


## **THE CRAFT CHAIN, DRIVEN BY THE SCREEN'S OWN BUTTONS.** Connecting here rather than in
## `_initialize` is deliberate: `tick_bundle` fires from the moment we join, and `AssayButtonPlay`
## may only read a world it has a player in.
func _playing() -> void:
	_drain_relay()
	if _play == null:
		_play = AssayButtonPlay.new(_screen, 0)
		_screen._client.tick_bundle.connect(_after_bundle)
		_play_until = _now() + PLAY_DEADLINE
		print("  playing the craft chain against the relay (%ds allowed)" % int(PLAY_DEADLINE))
		return
	if _play.failed != "":
		# **NOT ALWAYS A BAIL, AND THE TEST IS WHETHER THE PICTURE CAN STILL BE TAKEN.** The box wants
		# a building in frame; one building is a building. A chain that planted a smelter and then
		# broke on the drill still produced the subject, so the run goes on and the failure is carried
		# into the verdict by name instead of being thrown away with the shot.
		_play_note += "  the chain FAILED on %s: %s\n" % [
				AssayButtonPlay.Step.keys()[_play.step], _play.failed]
		if _screen._sim.buildings().is_empty():
			_bail("the chain failed with no building standing: %s" % _play.failed)
			return
		print("  chain failed but %d building(s) stand; shooting anyway"
				% _screen._sim.buildings().size())
		_step = 31
		return
	if _play.finished:
		_play_note += "  the chain FINISHED at tick %d: %s\n" % [_screen._sim.tick(), _play.outcome]
		print("  chain finished at tick %d, %d building(s) standing"
				% [_screen._sim.tick(), _screen._sim.buildings().size()])
		_step = 31
		return
	if _now() >= _play_until:
		_play_note += "  the chain RAN OUT OF TIME on %s\n" % AssayButtonPlay.Step.keys()[_play.step]
		if _screen._sim.buildings().is_empty():
			_bail("the chain was still on %s at its deadline with nothing built"
					% AssayButtonPlay.Step.keys()[_play.step])
			return
		print("  chain out of time on %s but %d building(s) stand; shooting anyway"
				% [AssayButtonPlay.Step.keys()[_play.step], _screen._sim.buildings().size()])
		_step = 31


## THE LOOP'S ONLY TICK, on `button_session.gd`'s reasoning: the relay owns the clock, `main.gd` has
## already stepped the world by the time this runs, and a stepped world is the only state the loop
## may read.
func _after_bundle(_tick: int, _inputs: Array, _raw: String) -> void:
	if _done or _play == null or _play.finished or _play.failed != "":
		return
	_play.advance()


## **WALK ME TO A TILE THAT CLEARS EVERY BUILDING, AND THE PARTNER'S TILE TOO.**
##
## The chain plants on the tile you stand on, so after it the body and the machine are the same tile
## and the 12px diamond disappears inside the 16px square -- measured in `window_shot.gd`, which is
## why that tool walks off before it presses V. The partner is placed at `PEER_OFFSET` from wherever I
## stop, so MY tile decides BOTH marks and the search has to satisfy both at once.
##
## A SPIRAL OUT FROM WHERE I STAND and not a jump to a corner: the schematic is the whole map, so any
## clear tile answers the box, and the nearest one keeps the factory and the two people in the same
## part of the picture, which is the thing a player would actually be looking at.
func _walk_clear_of_every_building() -> void:
	var found: Variant = _tile_of(true)
	if found == null:
		if _now() >= _ceiling:
			_bail("the sim never reported my own player")
		return
	var me := Vector2i(int((found as Vector2).x), int((found as Vector2).y))
	var size: Vector2i = _screen._sim.size_tiles()
	var pick: Variant = null
	for radius in range(0, CLEAR_RADIUS + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := me + Vector2i(dx, dy)
				if tile.x < 0 or tile.y < 0 or tile.x >= size.x or tile.y >= size.y:
					continue
				var mate := Vector2i(clampi(tile.x + PEER_OFFSET.x, 0, size.x - 1),
						clampi(tile.y + PEER_OFFSET.y, 0, size.y - 1))
				if _clear_of_buildings(tile) and _clear_of_buildings(mate):
					pick = tile
					break
			if pick != null:
				break
		if pick != null:
			break
	if pick == null:
		_bail("no tile within %d of %s clears every building for both bodies"
				% [CLEAR_RADIUS, me])
		return
	_clear_target = pick
	if _clear_target == me:
		print("  already clear of every building at %s" % me)
		_step = 5
		return
	if not _screen._client.submit(AssayActions.move_to(_clear_target)):
		_bail("the client refused a MoveTo to %s" % _clear_target)
		return
	print("  walking clear of the factory: %s -> %s" % [me, _clear_target])
	_step = 32
	_until = _now() + WALK_DEADLINE


func _wait_for_the_clear_arrival() -> void:
	_drain_relay()
	var found: Variant = _tile_of(true)
	if found != null:
		var me := Vector2i(int((found as Vector2).x), int((found as Vector2).y))
		if me == _clear_target:
			_step = 5
			return
	if _now() >= _until:
		# A BAIL, unlike the partner's walk. The partner's framing is cosmetic; this walk is what
		# makes the building and the player separable at all, and a shot taken half way there could
		# have the diamond under the square again while reading as the answer to box 3.
		_bail("never reached the clear tile %s in %ds" % [_clear_target, int(WALK_DEADLINE)])


## TRUE when no building's footprint comes within `CLEAR_TILES` of this tile, measured in Chebyshev
## tiles because that is how the marks overlap on a square grid.
##
## `pos` IS THE TOP-LEFT OF THE FOOTPRINT (`sim_host.gd:140`) AND A SMELTER IS 2x2, so every CELL of
## the footprint is measured and not the one tile the sim names -- and the footprint is taken from the
## sim's own `Vector2i` (`sim-godot/src/lib.rs:1219`) rather than from a 2 typed here, so a building
## kind with a different shape cannot quietly go unmeasured.
## CHEBYSHEV TILES TO THE NEAREST FOOTPRINT CELL, or -1 when nothing is built. -1 AND NOT A BIG
## NUMBER: "no building" and "very far from a building" are different answers and the verdict says
## which, because box 3 wants a building in the frame at all.
func _distance_to_a_building(tile: Vector2i) -> int:
	var best := -1
	for entry in _screen._sim.buildings():
		var b: Dictionary = entry
		var at: Vector2i = b.get("pos", Vector2i.ZERO) as Vector2i
		var span: Vector2i = b.get("footprint", Vector2i.ONE) as Vector2i
		for fy in range(maxi(1, span.y)):
			for fx in range(maxi(1, span.x)):
				var cell := at + Vector2i(fx, fy)
				var d := maxi(absi(cell.x - tile.x), absi(cell.y - tile.y))
				if best < 0 or d < best:
					best = d
	return best


func _clear_of_buildings(tile: Vector2i) -> bool:
	for entry in _screen._sim.buildings():
		var b: Dictionary = entry
		var at: Vector2i = b.get("pos", Vector2i.ZERO) as Vector2i
		var span: Vector2i = b.get("footprint", Vector2i.ONE) as Vector2i
		for fy in range(maxi(1, span.y)):
			for fx in range(maxi(1, span.x)):
				var cell := at + Vector2i(fx, fy)
				if maxi(absi(cell.x - tile.x), absi(cell.y - tile.y)) < CLEAR_TILES:
					return false
	return true


func _wait_then_join() -> void:
	_drain_relay()
	if _address == "":
		if _now() >= _until:
			_bail("relay never said LISTENING: %s" % " / ".join(_relay_said))
		return
	_screen._host.text = _address
	_screen._on_join()
	_step = 2
	_until = _now() + JOIN_DEADLINE


func _wait_for_the_world() -> void:
	if _screen._client.stage == AssayNetClient.Stage.JOINED and _screen._sim.running() \
			and _screen._client.bundles_seen > 0:
		_step = 3
		return
	if _now() >= _until:
		_bail("no world within %ds (stage %d)" % [int(JOIN_DEADLINE), _screen._client.stage])


func _start_the_peer() -> void:
	var pipe := OS.execute_with_pipe(_cli_binary, PackedStringArray(["--connect", _address,
			"--name", _peer_name, "--plain"]))
	if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
		_bail("could not start the peer %s" % _cli_binary)
		return
	_peer_pid = int(pipe["pid"])
	_peer_stdio = pipe["stdio"]
	print("  peer '%s' pid %d joining %s" % [_peer_name, _peer_pid, _address])
	_step = 4
	_until = _now() + PEER_DEADLINE


## THE RELAY'S OWN RECEIPT, and the SIM's count, and both are required. A peer that only completed a
## TCP connect would otherwise leave this run photographing one person while reporting two.
func _wait_for_the_peer() -> void:
	_drain_relay()
	if _peer_welcomed and _screen._sim.players().size() >= 2:
		# THE WALK IS MINE AND IT HAPPENS BEFORE THE PARTNER IS PLACED, because the partner is placed
		# relative to where I end up. Walking after would frame the pair around my spawn.
		#
		# AND THE CHAIN COMES BEFORE EITHER, for the same reason one step further back: it walks me
		# across the map to a deposit, so a row reached before it would not survive it.
		if _play_on:
			_step = 30
			return
		_step = 40 if _row >= 0 else 5
		return
	if _now() >= _until:
		_bail("the peer never appeared: welcomed=%s, players=%d"
				% [_peer_welcomed, _screen._sim.players().size()])


## WALK ME TO THE ASKED-FOR ROW, by the same submit path a person's left click takes.
##
## `AssayActions.move_to` is what `main.gd::_on_map_click` sends, so this is the shipped command and
## not a teleport into the snapshot. One hop and not the zig-zag `maren_north_shot.gd` uses: that
## script hops to FILL THE LOG, because its subject is the log panel's height. This one's subject is
## two bodies and a camera, and neither cares how many lines are in the log.
func _walk_me_to_the_row() -> void:
	var found: Variant = _tile_of(true)
	if found == null:
		if _now() >= _ceiling:
			_bail("the sim never reported my own player")
		return
	var me: Vector2 = found
	var size: Vector2i = _screen._sim.size_tiles()
	# THE PARTNER IS PLACED AT `PEER_OFFSET` FROM ME AND THAT OFFSET POINTS EAST, so a column near the
	# WEST edge keeps both of us on screen while a column near the east edge would push them off it.
	# Said here rather than clamped silently: a tool that quietly moved the partner would answer a
	# different question than the one the caller asked.
	_my_target = Vector2i(
			clampi(_col, 0, size.x - 1) if _col >= 0 else int(me.x),
			clampi(_row, 0, size.y - 1))
	if not _screen._client.submit(AssayActions.move_to(_my_target)):
		_bail("the client refused a MoveTo to %s" % _my_target)
		return
	print("  walking myself to %s (from %s)" % [_my_target, me])
	_step = 41
	_until = _now() + WALK_DEADLINE


## **A SHORT WALK IS NOT A REASON TO BAIL, BUT THE WRONG ROW IS.**
##
## `_wait_for_the_peer_to_arrive` deliberately shoots where the partner stands if it is slow, because
## two bodies anywhere still answers "are two people on one screen". This one may NOT do that: the
## whole question is what the camera does at a CLAMPED row, and a shot taken half way there is a shot
## of an unclamped camera that would read as an answer.
func _wait_for_my_arrival() -> void:
	_drain_relay()
	var found: Variant = _tile_of(true)
	if found != null:
		var me: Vector2 = found
		if Vector2i(int(me.x), int(me.y)) == _my_target:
			print("  arrived at %s (row %d)" % [me, _my_target.y])
			_step = 5
			return
	if _now() >= _until:
		_bail("never reached row %d in %ds" % [_my_target.y, int(WALK_DEADLINE)])


## TYPED AT ITS STDIN, which is the same thing a person at a terminal does. `goto x y` is the command
## `sim-cli` prints in its own welcome line, so this drives the shipped client rather than a harness.
func _send_the_peer_walking() -> void:
	var found: Variant = _tile_of(true)
	if found == null:
		return
	var me: Vector2 = found
	var size: Vector2i = _screen._sim.size_tiles()
	_peer_target = Vector2i(clampi(int(me.x) + PEER_OFFSET.x, 0, size.x - 1),
			clampi(int(me.y) + PEER_OFFSET.y, 0, size.y - 1))
	_peer_stdio.store_line("goto %d %d" % [_peer_target.x, _peer_target.y])
	_peer_stdio.flush()
	print("  told '%s' to walk to %s (I am at %s)" % [_peer_name, _peer_target, me])
	_step = 6
	_until = _now() + WALK_DEADLINE


func _wait_for_the_peer_to_arrive() -> void:
	_drain_relay()
	var them: Variant = _tile_of(false)
	if them != null and Vector2i(int((them as Vector2).x), int((them as Vector2).y)) == _peer_target:
		print("  '%s' arrived at %s" % [_peer_name, them])
		_step = 7
		return
	if _now() >= _until:
		# NOT A BAIL. The picture is about two bodies on one screen, and two bodies anywhere on it is
		# still that picture -- only the framing is worse. A run that threw the shot away because a
		# walk was slow would be refusing to answer the question it was written for.
		print("  '%s' did not reach %s in %ds, shooting where it stands"
				% [_peer_name, _peer_target, int(WALK_DEADLINE)])
		_step = 7


## A PLAYER'S TILE, as the screen already finds it, or `null` when there is no such player.
##
## NULL AND NOT `Vector2.ZERO`, because (0,0) is a real tile on this map and a sentinel that is also
## an answer is how a caller ends up waiting for an arrival at the corner of the world.
func _tile_of(mine: bool) -> Variant:
	for entry in _screen._sim.players():
		var p: Dictionary = entry
		if (int(p.get("id", -1)) == int(_screen._client.player_id)) == mine:
			return Vector2(p.get("pos", Vector2i.ZERO) as Vector2i)
	return null


func _is_empty_pair() -> bool:
	return _screen._sim.players().size() < 2


## MORE THAN ONE FRAME. The screen is built from deferred layout, so the first frame after a toggle
## photographs the state before it.
func _settle_then(next: int) -> void:
	_settle += 1
	if _settle >= SETTLE_FRAMES:
		_settle = 0
		_step = next


func _shoot(name: String) -> void:
	var image := root.get_texture().get_image()
	var path := _out.path_join(name)
	if image.save_png(path) != OK:
		_bail("could not write %s" % path)
		return
	print("  wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _report() -> void:
	print("")
	print("CO-OP SHOT: seed %s, %d players in the sim, my id %d"
			% [_seed, _screen._sim.players().size(), _screen._client.player_id])
	for entry in _screen._sim.players():
		var p: Dictionary = entry
		print("  player %d at %s%s" % [int(p.get("id", -1)), p.get("pos", Vector2i.ZERO),
				"  <- the client calls this one MINE" if int(p.get("id", -1))
				== int(_screen._client.player_id) else ""])
	var mine: Variant = _tile_of(true)
	var theirs: Variant = _tile_of(false)
	if mine != null and theirs != null:
		var apart := ((mine as Vector2) - (theirs as Vector2)).abs()
		print("  %.0f tiles apart in x, %.0f in y" % [apart.x, apart.y])
	print("  toggle reads: %s, close_up=%s" % [_screen._view_toggle.text, _screen._close_up])
	_report_the_subject(mine, theirs)
	print("  said: %s" % " | ".join(_said))
	if _is_empty_pair():
		print("CO-OP SHOT FAILED: fewer than two players, so neither picture is about co-op")
		_finish(1)
		return
	print("CO-OP SHOT OK")
	_finish(0)


## **WHAT ASSA-206 BOX 3 ASKED TO BE IN THE FRAME, COUNTED IN THE FRAME THAT WAS WRITTEN.**
##
## A building, two players and a dead-end disc. Presence is not enough for the first two -- the whole
## reason this walks off is that a building under a body is a building nobody can see -- so the
## CLEARANCE IS PRINTED AS A NUMBER for each body against the nearest footprint cell, and whether a
## mark reads at 9 px is still judged on the picture at 1x, which is the box's own wording and not
## something a tool may tick for itself.
func _report_the_subject(mine: Variant, theirs: Variant) -> void:
	if _play_note != "":
		print(_play_note.strip_edges())
	var buildings: Array = _screen._sim.buildings()
	print("  %d building(s) in the sim:" % buildings.size())
	for entry in buildings:
		var b: Dictionary = entry
		print("    %s at %s footprint %s status %s" % [b.get("kind", "?"), b.get("pos", "?"),
				b.get("footprint", "?"), b.get("status", "?")])
	print("  %d mark(s) the schematic painted for them (main.gd::_building_marks)"
			% _screen._building_marks(buildings).size())
	# THE SIM'S OWN WORD ON A DEAD END and not a reading of the picture: `reach_note` is what
	# `hud.gd:583` hatches on, so this counts the discs the frame was told to stripe.
	var dead := 0
	var live := 0
	for entry in _screen._sim.deposits():
		var d: Dictionary = entry
		if String(d.get("reach_note", "")) != "":
			dead += 1
		elif int(d.get("amount", 0)) > 0:
			live += 1
	print("  deposits: %d hatched dead ends, %d workable" % [dead, live])
	for pair in [["me", mine], [_peer_name, theirs]]:
		var who: String = pair[0]
		var at: Variant = pair[1]
		if at == null:
			print("  %s: the sim did not report this player" % who)
			continue
		var tile := Vector2i(int((at as Vector2).x), int((at as Vector2).y))
		print("  %s at %s: %d tiles from the nearest building cell%s"
				% [who, tile, _distance_to_a_building(tile),
				"" if _clear_of_buildings(tile) else "  <- UNDER %d, THE MARKS OVERLAP"
				% CLEAR_TILES])


## **THE GEOMETRY THE TWO BODIES AND THE MACHINES WERE PAINTED FROM, BESIDE THE SHOT** (ASSA-236
## box 3: "you and your partner are told apart by SHAPE or form at 1x, not by hue alone plus a ring").
##
## `window_shot.gd::_write_marks_table` does this for the one-player screens and its own docstring
## says why: measure the polygon the painter used, never a lump of bright pixels in an image. **But
## that tool plays SOLO, so the one mark this box is about -- a partner -- has never been in any file
## it wrote.** Every number anyone has published about telling two bodies apart, mine included, came
## off a Python replica of this geometry.
##
## **IT CARRIES THE WHOLE POLYGON AND NOT JUST THE SHAPE'S NAME**, which is the one way this is more
## than a copy of the solo version: a name can be compared to a name, and what box 3 asks is whether
## the INK in the frame has the form the table claims. With the points here, a measurement can
## rasterise `points` against the real PNG and ask how much of the ink is inside -- and, as a control
## in the same frame, how much of it a RECT of the same box would have claimed, which is the shape
## both bodies were before this item.
##
## Straight off `AssayHud.player_mark` and `main.gd::_building_marks`: the SAME calls `_draw` makes
## (main.gd:3941, 3999), so nothing here can drift from the painter without the painter moving.
func _write_marks_table() -> void:
	var people := []
	for entry in _screen._sim.players():
		var player: Dictionary = entry
		var mine := int(player.get("id", -1)) == int(_screen._client.player_id)
		var at: Vector2 = _screen.point_of_tile(player.get("pos", Vector2i.ZERO) as Vector2i)
		var mark: Dictionary = AssayHud.player_mark(at, mine)
		var row := {"id": int(player.get("id", -1)), "mine": mine,
				"who": "me" if mine else _peer_name,
				"tile": [int((player.get("pos", Vector2i.ZERO) as Vector2i).x),
						int((player.get("pos", Vector2i.ZERO) as Vector2i).y)],
				"x": at.x, "y": at.y,
				"w": (mark["span"] as Vector2).x, "h": (mark["span"] as Vector2).y,
				"shape": String(mark["shape"]), "points": _flat(mark["points"]),
				"keyline_points": _flat(mark["keyline_points"]),
				"colour": _rgb(mark["colour"] as Color)}
		# THE RING ONLY EXISTS ON ONE BODY, so the key is ABSENT on the other rather than empty: "this
		# player has no ring" and "I did not look" are different answers, and box 3 is partly about
		# whether the ring is still doing all the work.
		if mark.has("ring_points"):
			row["ring_points"] = _flat(mark["ring_points"])
		people.append(row)
	var machines := []
	var buildings: Array = _screen._sim.buildings()
	var marks: Array = _screen._building_marks(buildings)
	for i in marks.size():
		var mark: Dictionary = marks[i]
		var building: Dictionary = buildings[i] if i < buildings.size() else {}
		machines.append({"kind": String(building.get("kind", "?")),
				"x": (mark["at"] as Vector2).x, "y": (mark["at"] as Vector2).y,
				"w": (mark["span"] as Vector2).x, "h": (mark["span"] as Vector2).y,
				"shape": String(AssayHud.mark_entry(&"building")["shape"]),
				"points": _flat(mark["points"]), "hole_points": _flat(mark["hole_points"]),
				"stroke": float(mark["stroke"])})
	var table := {"seed": _seed, "cell": _screen._cell,
			"map": [_screen.MARGIN.x, _screen.MARGIN.y,
					(Vector2(_screen._sim.size_tiles()) * _screen._cell).x,
					(Vector2(_screen._sim.size_tiles()) * _screen._cell).y],
			"my_id": int(_screen._client.player_id), "people": people, "machines": machines}
	var path := _out.path_join("04-marks-two.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_bail("could not write %s" % path)
		return
	file.store_string(JSON.stringify(table, "  "))
	file.close()
	print("  wrote %s (%d people, %d machine(s))" % [path, people.size(), machines.size()])


## A polygon as a flat `[x, y, x, y, ...]`, because `JSON.stringify` turns a `Vector2` into the string
## `"(1, 2)"` and a measurement would then be parsing Godot's `print` format.
func _flat(points: Variant) -> Array:
	var out := []
	for p in points as PackedVector2Array:
		out.append((p as Vector2).x)
		out.append((p as Vector2).y)
	return out


func _rgb(colour: Color) -> Array:
	return [colour.r, colour.g, colour.b]


func _spawn_relay() -> bool:
	var pipe := OS.execute_with_pipe(_relay_binary, PackedStringArray([_seed, "--bind", "127.0.0.1",
			"--port", "0"]))
	if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
		_bail("could not start %s" % _relay_binary)
		return false
	_relay_pid = int(pipe["pid"])
	_relay_stdio = pipe["stdio"]
	return true


func _drain_relay() -> void:
	while _relay_stdio != null and _relay_stdio.get_length() > _relay_stdio.get_position():
		var line := _relay_stdio.get_line()
		if line.begins_with(AssaySoloRelay.LISTENING):
			_address = line.substr(AssaySoloRelay.LISTENING.length()).strip_edges()
			continue
		# Matched on the peer's NAME, so our own welcome line can never be counted as the partner's.
		if line.contains("joined as player") and line.contains(_peer_name):
			_peer_welcomed = true
			print("  relay: %s" % line.strip_edges())
			continue
		if line.strip_edges() != "":
			_relay_said.append(line.strip_edges())


func _bail(why: String) -> void:
	print("FAIL  %s" % why)
	_finish(1)


func _finish(code: int) -> void:
	if _peer_pid > 0 and OS.get_process_exit_code(_peer_pid) == -1:
		OS.kill(_peer_pid)
	if _relay_pid > 0 and OS.get_process_exit_code(_relay_pid) == -1:
		OS.kill(_relay_pid)
	_relay_stdio = null
	_peer_stdio = null
	_done = true
	quit(code)


func _now() -> float:
	return Time.get_unix_time_from_system()
