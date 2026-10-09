extends SceneTree
## CI: gated
## **DOES A PRESS COVER A LIVE STALL NOTICE, OR DESTROY IT?** (ASSA-370, box 6)
##
##   godot --headless --path client --script res://tools/toast_cover_probe.gd -- [seed] [ticks]
##
## **THE BUG THIS MEASURES WAS FOUND WITH A CAMERA, NOT A TEST** (Nerite, taking ASSA-300's box 3).
## Every accepted command called `_say` with no building, which overwrote the live stall sentence AND
## the building it was a claim about; the replacement then aged out on its own 20-tick dwell. So the
## warning vanished within two seconds of the next press whatever the machine was doing: at tick 108
## of their run the toast was silent while the pinned count still read `1 of 1 buildings stopped`,
## with the fuel not yet inserted. ASSA-300's clearing mechanism was correct and almost never got to
## run, because players press buttons constantly.
##
## **WHY THIS IS A SECOND PROBE AND NOT A THIRD PHASE OF `toast_stall_probe.gd`.** That one's whole
## claim is that a condition ends when the condition does, and it buys that claim by FREEZING player 0
## the moment a stall is on the toast — the screen that is lied to is the screen that pressed nothing.
## This claim is the opposite: it needs player 0 to press something while the stall is live, which is
## the premise the other probe spends to get its own answer. One instrument, one claim; entangling
## them would have left both resting on a window where neither could fail honestly.
##
## **THE PRESS IS A REAL BUTTON, FOUND BY ITS LABEL AND GIVEN THE SIGNAL A MOUSE RAISES.** Not
## `_act()` directly: `_act` is the line in the root cause, so calling it would be the probe agreeing
## with my reading of the bug instead of pressing the thing a player presses. `Stop` is the button,
## for one reason — it is accepted by `submit` in every world state and changes nothing about the
## stalled smelter, so what happens to the toast is the client's own doing and not a rescue.
##
## ## THE SEQUENCE, AND EVERY PREMISE IS A FAILURE
##
##  1. Play the demo until a stall sentence is on the toast and the sim agrees that building is
##     stopped. Nobody arranges this: loading a smelter's input before mining its fuel is a step of
##     `AssayButtonPlay`, so `SmelterStall::NoFuel` is what the board's own demo performs. A run that
##     never got there says NO VERDICT and fails the gate rather than passing.
##  2. **FREEZE THE DEMO.** From here player 0's only input is the one press below, so nothing can
##     clear the smelter and the condition stays true for the whole measurement. The stall is never
##     fixed in this run, which is the point: the sentence has no honest reason to leave.
##  3. Press `Stop`. The receipt must appear on the toast (ASSA-245: for up to a third of a second it
##     is the only thing telling a player the game heard them), and it must COVER the notice rather
##     than being refused a place.
##  4. Step `SAYING_DWELL_TICKS + 1` ticks with no further input, checking on every tick that the sim
##     still calls that building stopped.
##  5. **THE VERDICT: the stall sentence is back on the toast.** Empty means the press destroyed it —
##     the bug, and what this run reddens on. Anything else means something unexpected took the line.
##
## **HEADLESS IS HONEST HERE** (ASSA-173's rule): every number is a string off `main.gd` plus two
## booleans off the sim. Nothing is read off the viewport, so this reads the same with and without a
## window.
##
## **THE VERDICT IS THE MARKER, NEVER THE EXIT CODE.** Godot exits 0 on a parse error, on a failed
## script and on a probe's own FAIL, so `TOAST COVER PROBE OK` is printed last and only on success,
## and that is the thing a gate greps. Exit 1 is a real finding, 2 is NO VERDICT.

## ONE TICK PER FRAME, for the same reason as `toast_stall_probe.gd`: `_age_the_saying` runs from
## `_refresh`, which `_on_tick_bundle` drives, so a frame carrying forty ticks would ask the ageing
## question once per forty and could step over the uncovering tick entirely.
const TICKS_PER_FRAME := 1

## A WALL-CLOCK CEILING, SET AS A MEMBER INITIALIZER (ASSA-182): a `SceneTree` whose `_initialize`
## dies still gets `_process` for ever, and an orphan holding an account file makes somebody else's
## run fail for a reason they will never find.
const RUN_CEILING := 300.0

## The button pressed over the live notice. Accepted in every world state, and it asks nothing of the
## stalled smelter.
const PRESS := "Stop"

enum Phase { PLAY, PRESSED, DONE }

var _screen: Node = null
var _play: Object = null
var _asked: Array = []
var _seed := "14247"
var _left := 1600
var _started := false
var _done := false
var _phase := Phase.PLAY
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

## The notice under test, as `{building, line, since}`, or empty until one is on the toast and true.
var _watch: Dictionary = {}
## The tick `PRESS` was pressed, or -1.
var _pressed_at := -1
## What the toast read on the tick after the press. The receipt, or the run has nothing to measure.
var _receipt := ""
## How many ticks of the measurement window the sim still called the building stopped.
var _still_stopped := 0
## The ticks of the window, in order, as `tick: <what the toast said>`. The report prints it whole:
## a verdict about one frame is worth more beside the frames either side of it.
var _window := PackedStringArray()
var _halted_ticks := 0
var _notices := PackedStringArray()


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "14247"
	_left = int(argv[1]) if argv.size() > 1 else 1600
	var saves := OS.get_user_data_dir().path_join("toast-cover-probe-saves")
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
			# PLAYER 0 PRESSES BUTTONS, the way the demo does. Their commands reach the wire through
			# the screen's own door.
			_play.advance()
			for command in _asked:
				inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
			_asked.clear()
		else:
			# **THE MEASUREMENT WINDOW: NOTHING IS PLAYED.** The one press below is the only input
			# player 0 makes, so the smelter is never fixed and the condition cannot end honestly.
			# Anything that happens to the toast from here is the client's own doing.
			for command in _asked:
				inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
			_asked.clear()
		_feed(inputs)
		_sample()
		if _phase == Phase.PRESSED and _pressed_at >= 0:
			var window: int = int(_screen.SAYING_DWELL_TICKS) + 1
			if _screen._sim.tick() - _pressed_at > window:
				_report("the dwell is spent")
				return true
		if _phase == Phase.PLAY and _play.finished:
			_report("the demo finished without a stall on the toast")
			return true
	return false


func _feed(inputs: Array) -> void:
	var at: int = _screen._sim.tick()
	_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))


## **WHAT THE SCREEN SAYS AND WHETHER THE MACHINE IS STILL STOPPED, ONE TICK AT A TIME.**
##
## `_shown_line()` is what the toast draws, over both stored sentences; `is_halted` is asked of the
## building the sim crossed with the notice, never of the sentence's words (ASSA-67).
func _sample() -> void:
	var sim: AssaySimHost = _screen._sim
	var at: int = sim.tick()
	var shown: String = _screen._shown_line()
	if not sim.halt_lines().is_empty():
		_halted_ticks += 1

	if _phase == Phase.PLAY:
		var about: int = _screen._standing_building
		if about == _screen.NOT_A_CONDITION or _screen._standing_line == "":
			return
		if _notices.find(_screen._standing_line) < 0:
			_notices.append(_screen._standing_line)
		# A STALL SENTENCE IS ON THE TOAST AND THE SIM AGREES. Both halves, or there is nothing to
		# press over: a notice already covered by the demo's own receipt would make step 3 a press
		# over a press.
		if shown != _screen._standing_line or not sim.is_halted(about):
			return
		_watch = {"building": about, "line": shown, "since": at}
		_phase = Phase.PRESSED
		_window.append("tick %d: `%s` is on the toast and building %d really is stopped"
				% [at, shown, about])
		if not _press(PRESS):
			# NOT A NO VERDICT. A missing button is this probe's instrument being broken, and it
			# reports as a failure rather than as a quiet run (ASSA-348's hazard: an instrument that
			# matches nothing must say so).
			print("FAIL  no `%s` button on this screen, so nothing could be pressed over a live "
					% PRESS + "notice. The probe is broken, not the client.")
			_finish(1)
			return
		_pressed_at = at
		return

	var building: int = _watch["building"]
	if sim.is_halted(building):
		_still_stopped += 1
	_window.append("tick %d: toast `%s`, building %d stopped: %s"
			% [at, shown, building, "yes" if sim.is_halted(building) else "NO"])
	if at == _pressed_at + 1:
		_receipt = shown


## PRESS A BUTTON BY ITS LABEL, the same signal a mouse click raises, so the handler under test is
## the handler a player gets. The finder is `button_play.gd`'s, which is private to it.
func _press(label: String) -> bool:
	var button := _find_button(_screen, label)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _report(why: String) -> void:
	_done = true
	print("")
	print("TOAST COVER PROBE: seed %s, tick %d, %s" % [_seed, _screen._sim.tick(), why])
	print("  ticks with something stopped: %d" % _halted_ticks)
	print("  stall sentences that reached the toast: %d" % _notices.size())
	for line in _notices:
		print("    `%s`" % line)
	print("  pressed `%s` at tick %d" % [PRESS, _pressed_at])
	print("  the window, tick by tick:")
	for row in _window:
		print("    %s" % row)

	# **THE PREMISE IS A FAILURE, NOT A SKIP.** A run that never got a stall sentence onto the toast
	# measured nothing at all, and a probe that passes over that is the coverage ASSA-300 was found
	# underneath.
	if _watch.is_empty():
		print(("NO VERDICT  no stall sentence was on the toast and true in %d ticks on seed %s, so "
				+ "nothing was pressed over one. Something was stopped on %d ticks.")
				% [int(_screen._sim.tick()), _seed, _halted_ticks])
		_finish(2)
		return
	var notice: String = _watch["line"]
	var building: int = _watch["building"]
	# THE RECEIPT, which the Game Director refused to trade away: a press that gets no receipt while
	# anything is stalled makes the receipt channel unreliable exactly when the player is busy.
	if not _receipt.contains("submitted"):
		print(("FAIL  the tick after pressing `%s` the toast read `%s`, not an acceptance. Shape (a) "
				+ "was refused on ASSA-370 for this: a press during a stall still gets its receipt.")
				% [PRESS, _receipt])
		_finish(1)
		return
	if _receipt == notice:
		print(("NO VERDICT  the receipt never reached the toast, so the notice was never covered and "
				+ "this run proves nothing about uncovering it."))
		_finish(2)
		return
	# AND THE CONDITION HELD FOR THE WHOLE WINDOW, or the sentence had an honest reason to leave and
	# this run cannot tell "covered then given back" from "cleared".
	var window: int = int(_screen.SAYING_DWELL_TICKS) + 1
	if _still_stopped < window:
		print(("NO VERDICT  building %d was stopped on only %d of the window's %d ticks, so the "
				+ "notice had an honest reason to go and nothing is proved.")
				% [building, _still_stopped, window])
		_finish(2)
		return
	var shown: String = _screen._shown_line()
	if shown == "":
		print(("FAIL  %d ticks after a routine `%s` press the toast is EMPTY and the sim still calls "
				+ "building %d stopped. `%s` was destroyed by the receipt for an unrelated command, "
				+ "which is ASSA-370: the pinned count beside it still reads that a machine is "
				+ "stopped.") % [_screen._sim.tick() - _pressed_at, PRESS, building, notice])
		_finish(1)
		return
	if shown != notice:
		print(("FAIL  the toast reads `%s` where `%s` should have been uncovered, building %d still "
				+ "stopped.") % [shown, notice, building])
		_finish(1)
		return
	print("TOAST COVER PROBE OK")
	_finish(0)


func _finish(code: int) -> void:
	_done = true
	quit(code)
