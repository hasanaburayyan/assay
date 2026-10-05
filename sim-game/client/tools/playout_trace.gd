extends SceneTree
## ONE LINE PER TICK OF A REAL WALK: where the playout clock is, how deep its buffer is, and what the
## body is being drawn between (ASSA-197).
##
##   godot --headless --path client --script res://tools/playout_trace.gd
##   TRACE_MS=100 TRACE_WARM=4 godot --headless ...   # tick period, and ticks fed before the click
##
## HEADLESS AND SO NOT THE SCREEN, which is the whole caveat and it is a big one: this feeds one
## `_refresh_world` per tick, so it is a 10 fps client with nothing to interpolate, where the real
## window refreshes ~60 times a second against a 10 tps relay. Numbers from here are about the
## CLOCK's arithmetic, never about how the walk looks -- `motion_speed_probe.gd` in a real window is
## the instrument for that, and the bar on this item is measured there.
##
## WHAT IT FOUND, which no test of mine could see: `playout_at` initialised the clock with
## `maxf(newest - delay, oldest)`, so with a single position held it started AT the newest with zero
## buffer, and `PLAYOUT_NUDGE` (10% of rate) needs 25 ticks to win 2.5 back. 4 of the first 12 ticks
## of a walk came back `starved` -- `_pending` drained to one entry, `from == to`, a frame where the
## body holds still. Maren's bar for this item is ZERO dry frames. The clock now waits for `delay`
## ticks of history before it starts.

var _asked := []

## **A ONE-SHOT TOOL CAN RUN FOR EVER TOO, AND THIS IS THE HALF ASSA-182 DID NOT FIX FIRST TIME.**
## `SceneTree`'s own `_process` returns false, so a tool with no `_process` of its own does not end when
## `_initialize` returns -- it ends when something calls `quit()`. A runtime error inside `_initialize`
## skips that call and the engine spins with no output and no exit: measured 2026-10-04 with a scratch
## script, alive after 25 s. The looping tools got a wall-clock ceiling; this needs no clock, because
## there is nothing a one-shot tool legitimately waits for.
##
## `_quitting` is set beside every `quit()` in this file rather than at the end of `_initialize`, so a
## deliberate early exit -- a bad argument, a missing world -- stays deliberate, and only a
## fall-through reaches the sentence below.
var _quitting := false


func _process(_delta: float) -> bool:
	if not _quitting:
		print("FAIL  playout_trace.gd: _initialize ended without asking to quit -- see the error above")
		quit(1)
	return true


func _initialize() -> void:
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	screen._client.asked.connect(func(c: Variant) -> void: _asked.append(c))
	var welcome := AssaySimHost.fresh_welcome_json("777042", "marlow")
	screen._client.play_offline()
	screen._client.feed_offline(welcome)
	if not screen._sim.running():
		print("no world: %s" % screen._sim.fail_reason)
		_quitting = true
		quit(1)
		return
	screen._show_close_up(true)
	var from: Vector2i = screen._my_tile()
	var warm := int(OS.get_environment("TRACE_WARM")) if OS.has_environment("TRACE_WARM") else 0
	var pre := int(OS.get_environment("TRACE_MS")) if OS.has_environment("TRACE_MS") else 100
	for _w in range(warm):
		screen._client.feed_offline(JSON.stringify(
				{"Tick": {"tick": screen._sim.tick(), "inputs": []}}))
		OS.delay_msec(pre)
		screen._refresh_world()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen.point_of_tile(from + Vector2i(6, 4))
	screen._unhandled_input(event)
	var delay := int(OS.get_environment("TRACE_MS")) if OS.has_environment("TRACE_MS") else 100
	print("delay %d ms, start tile %s, asked %s" % [delay, from, _asked])
	var steps := 0
	for i in range(12):
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": screen._client.player_id, "command": command}})
		_asked.clear()
		screen._client.feed_offline(JSON.stringify(
				{"Tick": {"tick": screen._sim.tick(), "inputs": inputs}}))
		OS.delay_msec(delay)
		screen._refresh_world()
		var ticks := []
		for e in screen._pending:
			ticks.append(int((e as Dictionary)["tick"]))
		var was: Vector2i = screen._was.get(screen._client.player_id, from)
		var now: Vector2i = screen._seen.get(screen._client.player_id, from)
		if was != now:
			steps += 1
		var at: Variant = screen._world.view.get("players", [{}])[0].get("at", null)
		print(("%2d sim %3d  play_tick %7.3f  gap %6.4f  pending %s  was %s now %s  at %s"
				+ "  starved %s") % [i, screen._sim.tick(), screen._play_tick, screen._tick_gap,
				ticks, was, now, at, screen._starved])
	print("steps %d" % steps)
	_quitting = true
	quit(0)
