extends SceneTree
## CI: gated
## **DOES A STALL SENTENCE COME DOWN WHEN THE STALL DOES?** (ASSA-300, box 4)
##
##   godot --headless --path client --script res://tools/toast_stall_probe.gd -- [seed] [ticks]
##
## **THE PATH THIS COVERS HAD NO PROBE, AND THE PROBE THAT LOOKS LIKE ITS PROBE CANNOT SEE IT.**
## `nacre_toast_shot.gd` photographs the toast healthy and dropped: join -> world -> wait for quiet ->
## shoot -> kill the relay -> shoot. It never stalls a machine and then clears the stall, so the one
## sentence that can outlive its own truth is the one it does not take. Its green also rests on
## nothing having failed: a `Say.FAILED` line could not go quiet before this item, so anything
## stalling before its third step would have hung it out at "never went quiet".
##
## **HEADLESS IS HONEST HERE** (ASSA-173's rule, applied rather than assumed): every number below is a
## STRING off `main.gd` plus two booleans off the sim. Nothing is measured off the viewport — no clip,
## no fold, no scroll share — so this reads the same with and without a window.
##
## ## THE TWO PHASES, AND WHY THE SECOND ONE NEEDS A SECOND PLAYER
##
## **PHASE 1, NOBODY ARRANGES IT.** `AssayButtonPlay` is the scripted demo play-out, and loading a
## smelter's input before mining its fuel is already a step of it: ore in, nothing to burn, which is
## `SmelterStall::NoFuel`. So the stall this watches is the one the board's own demo performs, and the
## notice sits on the toast for the twenty-odd ticks the player spends walking to the fuel.
##
## **PHASE 2 IS A CO-OP RESCUE, AND THAT IS NOT A CONVENIENCE — IT IS THE ONLY WAY THIS BUG IS
## REACHABLE.** Measured, by running the whole play-out first and reading what the screen said: in
## SOLO play the stall is always cleared by the player's own command, and `_act` echoes an acceptance
## for every press on the same tick — so the notice is covered by `Insert 12 into Fuel · submitted`
## before it can be caught being false. The first version of this probe passed with the fix REVERTED,
## for exactly that reason. The screen that is lied to is the screen that pressed nothing: in co-op
## your partner fixes the machine, no acceptance is said on your window, and nothing takes the
## sentence down. So phase 2 stops advancing player 0's play entirely, adds a second player on a tick
## bundle — which is exactly how another peer's inputs arrive — and has THEM clear the condition.
##
## **THE RESCUE IS A `Pickup`, FOR ONE REASON: IT IS THE ONLY CLEARING COMMAND A FRESH PLAYER CAN
## RUN.** `Insert` needs fuel in their inventory and `Take` only empties the OUTPUT slot
## (`step.rs:371`), which a `NoFuel` stall does not use. Pocketing the stalled smelter is a real co-op
## act, and it exercises the arm the toast depends on most sharply: a building that no longer exists
## is not halted, so its sentence has to go.
##
## ## WHAT IT ASSERTS, PREMISES INCLUDED
##
##  1. A stall sentence REACHED the toast carrying the building it is about. Without this the run
##     measured nothing and FAILS rather than passing over a quiet world.
##  2. It STAYED while the condition held. A "fix" that deleted stall notices passes 3 and fails here.
##  3. The tick the condition cleared, the toast was EMPTY — not replaced, empty, which is the only
##     outcome that proves `_age_the_saying` did it and not some later event. Before ASSA-300 this is
##     where the run reddens, with the sentence still on screen after the smelter was gone.
##  4. The toast and the pinned block never disagree about whether anything is stopped (box 6): a
##     condition on the toast with an empty `halt_lines()` is one screen contradicting itself.
##
## **THE VERDICT IS THE MARKER, NEVER THE EXIT CODE.** Godot exits 0 on a parse error, on a failed
## script and on a probe's own FAIL, so `TOAST STALL PROBE OK` is printed last and only on success,
## and that is the thing a gate greps. Exit 1 is a real finding, 2 is NO VERDICT.

## ONE TICK PER FRAME, and that is the measurement rather than a speed setting. `_age_the_saying` runs
## from `_refresh`, which `_on_tick_bundle` drives — so a frame carrying forty ticks would ask the
## ageing question once per forty and could step over a stall that came and went inside one frame. The
## claim is about what the screen says on the tick the condition clears.
const TICKS_PER_FRAME := 1

## A WALL-CLOCK CEILING, SET AS A MEMBER INITIALIZER (ASSA-182, the same reason as every other tool
## here): a `SceneTree` whose `_initialize` dies still gets `_process` for ever, and an orphan holding
## an account file makes somebody else's run fail for a reason they will never find.
const RUN_CEILING := 300.0

## `sim::tuning::REACH`. Copied rather than asked because the binding does not publish it; if the sim
## ever shortens reach, the rescuer below waits out its budget one tile short and the run says NO
## VERDICT rather than passing.
const REACH := 3

enum Phase { PLAY, RESCUE, DONE }

var _screen: Node = null
var _play: Object = null
var _asked: Array = []
var _seed := "14247"
var _left := 1600
var _started := false
var _done := false
var _phase := Phase.PLAY
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

## The condition the toast is carrying, as `{building, line, since}`, or empty.
var _watch: Dictionary = {}
## The most ticks a condition spent on the toast while it was still true. Claim 2.
var _held_for := 0
## `{building, line, said_at, cleared_at}` for every stall taken down BY AGEING — the toast empty on
## the tick the sim stopped reporting it. Claim 3.
var _aged: Array[Dictionary] = []
## Every tick the toast named a condition the sim no longer reported. **The bug.**
var _outlived: Array[String] = []
## Clearings where some other sentence had already taken the line. Not a failure and not a pass:
## nothing was proved, and a run with only these says so.
var _replaced: Array[String] = []
## Ticks the toast named a condition while `halt_lines()` was empty. Box 6.
var _disagreed: Array[String] = []
var _notices := PackedStringArray()
var _halted_ticks := 0

## The rescue, step by step, so each one is visible in the report.
var _rescuer := -1
var _rescue_step := ""
var _rescue_log := PackedStringArray()
var _target := Vector2i.ZERO
var _picked := false
var _rescue_left := 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "14247"
	_left = int(argv[1]) if argv.size() > 1 else 1600
	var saves := OS.get_user_data_dir().path_join("toast-stall-probe-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	OS.set_environment("R2TS_SAVES_DIR", saves)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("NO VERDICT  ran past its %ds ceiling in phase %d" % [int(RUN_CEILING), _phase])
		_finish(2)
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "marlow")
		if welcome == "":
			print("NO VERDICT  no world on seed %s" % _seed)
			_finish(2)
			return true
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		_started = true
	for _i in range(TICKS_PER_FRAME):
		if _left <= 0:
			_report("tick budget spent")
			return true
		_left -= 1
		var inputs := []
		if _phase == Phase.PLAY:
			# PLAYER 0 PRESSES BUTTONS. Their own commands reach the wire the way the demo's do.
			_play.advance()
			for command in _asked:
				inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
			_asked.clear()
		else:
			# PHASE 2: PLAYER 0 PRESSES NOTHING. Anything that happens to the toast from here is the
			# client's own doing, which is the whole claim.
			inputs = _rescue_inputs()
			_rescue_left -= 1
			if _rescue_left <= 0:
				_feed(inputs)
				_sample()
				_report("the rescue ran out of ticks")
				return true
		_feed(inputs)
		_sample()
		if _phase == Phase.PLAY and _play.finished:
			_report("the play-out finished before anything stalled")
			return true
	return false


func _feed(inputs: Array) -> void:
	var at: int = _screen._sim.tick()
	_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))


## **THE CO-OP PARTNER'S NEXT INPUT**, one command per tick at most, in the order a person would:
## join, walk, pocket the dead smelter. Returns `[]` on the ticks it is only waiting.
func _rescue_inputs() -> Array:
	if _picked or _watch.is_empty():
		return []
	var building: int = _watch["building"]
	if _rescuer < 0:
		_rescuer = _screen._sim.players().size()
		_note("tick %d: + player %d joins" % [_screen._sim.tick(), _rescuer])
		return [{"System": {"AddPlayer": {"name": "nerite"}}}]
	var me: Dictionary = _player(_rescuer)
	if me.is_empty():
		return []
	if _target == Vector2i.ZERO:
		var b := _building(building)
		if b.is_empty():
			return []
		# BESIDE IT AND NOT ON IT: a smelter's own two-by-two is not somewhere to stand, and the
		# sim's reach is measured to the footprint, so one tile clear of it is close enough.
		#
		# **AND INSIDE THE WORLD, WHICH THE FIRST VERSION WAS NOT.** It walked to `pos.y + height +
		# 1`, and the demo's smelter sits two tiles from the south edge of a 96x64 world, so the one
		# `MoveTo` this rescue depends on was refused `OutOfWorld` and the probe sat out 800 ticks
		# saying nothing. Worth keeping as a comment: that refusal belongs to player 1, so it never
		# reached player 0's toast — which is the audience filter working, read off a real run.
		_target = _a_tile_beside(b)
		if _target == Vector2i.ZERO:
			return []
		_note("tick %d: walking to %s from %s" % [_screen._sim.tick(), _target, me["pos"]])
		return [{"Player": {"player": _rescuer, "command": AssayActions.move_to(_target)}}]
	var reach := _reach_of(me["pos"], building)
	if reach < 0:
		return []
	if reach <= REACH:
		_picked = true
		_note("tick %d: within %d tiles, picking up building %d"
				% [_screen._sim.tick(), reach, building])
		return [{"Player": {"player": _rescuer, "command": AssayActions.pickup(building)}}]
	return []


## **WHAT THE SCREEN SAYS AND WHETHER IT IS TRUE, ONE TICK AT A TIME.**
##
## Asked of `_standing_building` and `is_halted`, never of the sentence's words: the pinned list says
## `smelter 3 at (12, 7) … stalled: the fuel will not light` where the toast says `the Tonore smelter
## (A) stopped: no fuel`, so a probe that matched text would agree with a client that could never
## clear anything (ASSA-67).
##
## **AND WHAT THE TOAST SAYS IS `_shown_line()`, NOT `_base_line`** (ASSA-370). The client holds two
## sentences and draws one: a standing condition notice, and the transient line a receipt or a refusal
## draws over it. `_base_line` is the transient alone, so a probe reading it would call a COVERED
## notice gone and the covering is legal. `tools/toast_cover_probe.gd` is the instrument for the cover
## and the uncovering; this one is about a condition ending.
func _sample() -> void:
	var sim: AssaySimHost = _screen._sim
	var at: int = sim.tick()
	var shown: String = _screen._shown_line()
	var stopped: PackedStringArray = sim.halt_lines()
	if not stopped.is_empty():
		_halted_ticks += 1

	# IS THE WATCHED CONDITION STILL TRUE? Asked before the toast is re-read, so the tick a stall
	# clears is judged against this tick's world.
	if not _watch.is_empty():
		var building: int = _watch["building"]
		var line: String = _watch["line"]
		var since: int = _watch["since"]
		if not sim.is_halted(building):
			if shown == line:
				# **THE BUG.** The sim has stopped reporting the stall and the sentence is still on
				# screen, beside a pinned count that has already dropped to zero.
				_outlived.append(("tick %d: `%s` outlived its condition by %d ticks "
						+ "(building %d, said at tick %d)")
						% [at, line, at - since, building, since])
			elif shown == "":
				_aged.append({
					"building": building, "line": line, "said_at": since, "cleared_at": at,
				})
				_watch = {}
			else:
				_replaced.append(("tick %d: the condition cleared but the toast already read `%s`, "
						+ "so nothing was proved about `%s`")
						% [at, shown, line])
				_watch = {}
		else:
			_held_for = maxi(_held_for, at - since)
			# A REAL STALL IS ON THE TOAST AND TRUE: freeze player 0 and let the partner fix it.
			if _phase == Phase.PLAY:
				_phase = Phase.RESCUE
				_rescue_left = maxi(_left, 1)
				_note("tick %d: `%s` is on the toast and building %d really is stopped"
						% [at, line, building])

	var about: int = _screen._standing_building
	if about == _screen.NOT_A_CONDITION or _screen._standing_line == "":
		return
	# **COVERED IS NOT GONE, AND IT IS NOT A FINDING** (ASSA-370). A transient of this player's own is
	# drawn over the notice; this frame claims nothing about the condition, so the checks below would
	# be reading a receipt. The cover and the uncovering are `tools/toast_cover_probe.gd`.
	if shown != _screen._standing_line:
		return
	# THE TOAST IS CARRYING A CONDITION. Every claim about that state is checked here.
	if _screen._standing_level != AssayHud.Say.FAILED:
		_disagreed.append("tick %d: a condition is on the toast at level %d, not FAILED"
				% [at, _screen._standing_level])
	if stopped.is_empty():
		_disagreed.append(("tick %d: the toast says `%s` and `halt_lines()` is EMPTY, so the pinned "
				+ "count reads nothing stopped on the same frame") % [at, shown])
	if _notices.find(shown) < 0:
		_notices.append(shown)
	if _watch.is_empty() or _watch["line"] != shown:
		_watch = {"building": about, "line": shown, "since": at}


func _report(why: String) -> void:
	_done = true
	print("")
	print("TOAST STALL PROBE: seed %s, tick %d, %s" % [_seed, _screen._sim.tick(), why])
	print("  ticks with something stopped: %d" % _halted_ticks)
	print("  stall sentences that reached the toast: %d" % _notices.size())
	for line in _notices:
		print("    `%s`" % line)
	print("  longest a condition sat on the toast while true: %d ticks" % _held_for)
	for row in _rescue_log:
		print("  rescue: %s" % row)
	print("  taken down by ageing when the condition cleared: %d" % _aged.size())
	for r in _aged:
		print("    building %d: `%s` said at tick %d, toast empty at tick %d"
				% [int(r["building"]), String(r["line"]), int(r["said_at"]), int(r["cleared_at"])])
	print("  outlived its condition: %d" % _outlived.size())
	for row in _outlived:
		print("    %s" % row)
	print("  cleared while another sentence held the line: %d" % _replaced.size())
	for row in _replaced:
		print("    %s" % row)
	print("  toast and pinned count disagreed: %d" % _disagreed.size())
	for row in _disagreed:
		print("    %s" % row)

	# **THE PREMISE IS A FAILURE, NOT A SKIP.** A run in which nothing stalled measured nothing at
	# all, and a probe that passes over that is the coverage this item was found underneath.
	if _notices.is_empty():
		print(("NO VERDICT  no stall sentence reached the toast in %d ticks on seed %s, so this run "
				+ "says nothing about taking one down. Something was stopped on %d ticks.")
				% [int(_screen._sim.tick()), _seed, _halted_ticks])
		_finish(2)
		return
	if _held_for <= 0:
		print("FAIL  no stall sentence survived one tick while its condition held. A client that "
				+ "simply deleted stall notices would read exactly like this.")
		_finish(1)
		return
	if not _outlived.is_empty():
		print(("FAIL  %d stall sentence(s) outlived the stall. This is ASSA-300: the screen says a "
				+ "machine is stopped while the pinned count beside it says nothing is.")
				% _outlived.size())
		_finish(1)
		return
	if not _disagreed.is_empty():
		print("FAIL  %d frame(s) where the toast and the pinned count disagreed" % _disagreed.size())
		_finish(1)
		return
	if _aged.is_empty():
		print(("NO VERDICT  no condition was ever taken down by ageing: %d cleared under another "
				+ "sentence and the rescue reached `%s`. Nothing here proves `_age_the_saying` runs.")
				% [_replaced.size(), _rescue_step])
		_finish(2)
		return
	print("TOAST STALL PROBE OK")
	_finish(0)


func _note(row: String) -> void:
	_rescue_step = row
	_rescue_log.append(row)


## The first tile touching a building's footprint that is inside the world, or `Vector2i.ZERO` if
## somehow none is. Four candidates, one per side.
func _a_tile_beside(b: Dictionary) -> Vector2i:
	var pos: Vector2i = b["pos"]
	var foot: Vector2i = b["footprint"]
	var size: Vector2i = _screen._sim.size_tiles()
	for candidate in [Vector2i(pos.x - 1, pos.y), Vector2i(pos.x + foot.x, pos.y),
			Vector2i(pos.x, pos.y - 1), Vector2i(pos.x, pos.y + foot.y)]:
		var at: Vector2i = candidate
		if at.x >= 0 and at.y >= 0 and at.x < size.x and at.y < size.y:
			return at
	return Vector2i.ZERO


func _player(id: int) -> Dictionary:
	for p in _screen._sim.players():
		var player: Dictionary = p
		if int(player["id"]) == id:
			return player
	return {}


func _building(id: int) -> Dictionary:
	for b in _screen._sim.buildings():
		var building: Dictionary = b
		if int(building["id"]) == id:
			return building
	return {}


## Chebyshev distance to the nearest tile of a building's footprint, or -1 if it is gone. The sim's
## `Building::distance_from` measures to the footprint, not to its corner, which is why this does too.
func _reach_of(from: Vector2i, id: int) -> int:
	var b := _building(id)
	if b.is_empty():
		return -1
	var pos: Vector2i = b["pos"]
	var size: Vector2i = b["footprint"]
	var dx: int = maxi(maxi(pos.x - from.x, from.x - (pos.x + size.x - 1)), 0)
	var dy: int = maxi(maxi(pos.y - from.y, from.y - (pos.y + size.y - 1)), 0)
	return maxi(dx, dy)


func _finish(code: int) -> void:
	_done = true
	quit(code)
