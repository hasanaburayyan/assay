extends SceneTree
## TWO PLAYERS IN ONE ASSAY WINDOW, PHOTOGRAPHED FOR THE FIRST TIME (Maren).
##
##   godot --path client --script res://tools/maren_coop_shot.gd -- <out_dir> [seed] [peer_name]
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
## WHAT IT WRITES: `01-close-up-two.png` (the screen you play on) and `02-whole-world-two.png` (the
## schematic, one V press away), plus a verdict naming both players, which one the client thinks is
## mine, and how far apart they stand in tiles.

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
const RUN_CEILING := 180.0

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
			_report()
	return _done


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
	print("  said: %s" % " | ".join(_said))
	if _is_empty_pair():
		print("CO-OP SHOT FAILED: fewer than two players, so neither picture is about co-op")
		_finish(1)
		return
	print("CO-OP SHOT OK")
	_finish(0)


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
