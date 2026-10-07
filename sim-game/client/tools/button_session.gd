extends SceneTree
## CAN A PERSON AT THE WINDOW PLAY THE DEMO LOOP? Headless, one line of verdict.
##
##   godot --headless --path . --script res://tools/button_session.gd -- offline [seed] [rank] [job]
##   godot --headless --path . --script res://tools/button_session.gd -- localhost:7777 name [rank] [job]
##
## `lockstep_probe.gd --session` plays the same loop by calling `submit`, which proves the sim, the
## wire and lockstep. It cannot prove ASSA-37's claim, which is about REACHABILITY: every command can
## be perfectly correct and still have no click target, which is what this client was until today.
## So this presses the screen's own buttons and clicks its own map, and `AssayButtonPlay` holds the
## loop. If a button is missing, mislabelled, built over the map or wired to the wrong command, this
## stops on that step and says which.
##
## **AND TWO JOBS, WHICH IS A SEPARATE AXIS FROM THE MODE** (ASSA-140). `job` is `showcase`
## (default) or `break`, and it decides which drill the loop plants: the largest part count the sim
## calls SAFE, or the smallest it calls WILL BREAK. THEY CANNOT BE THE SAME RUN -- one ends with a
## machine standing and mining, the other with a design in pieces -- so the gate runs this twice on
## one seed and greps the suffix, not the prefix. Each run asserts only that the sim's own
## prediction came true; see `AssayButtonPlay._keep_the_promise`.
##
## TWO MODES, ONE STATE MACHINE.
##  - `offline`: no socket and no relay. This script is the clock: it takes the commands the buttons
##    asked for, writes the `TickBundle` a relay would have written, and feeds it back through the
##    real frame reader. Fast enough to run in a test, which is where ASSA-37's fifth box lives.
##  - a host address: the screen JOINS BY ITS OWN JOIN BUTTON and the relay owns the clock. Run three
##    of these at once and the relay's own hash check covers the sixth box; each prints its final
##    hash so the three can also be compared without taking the relay's word for it.
##
## Prints `BUTTON SESSION OK` LAST and only on success. A positive marker printed last is the only
## thing a grep can trust, because Godot exits 0 even when a script fails to compile.

## Offline ticks to allow. The chain is about 550 ticks on a fresh world (mine 22 ore, smelt 17 at 20
## ticks each, walk twice); this is generous because an underestimate turns a real failure into "ask
## for more ticks", which is the confusing way round.
const OFFLINE_TICKS := 4000
## Relay ticks to allow, at ten a second. The same chain over a real clock is about a minute.
const RELAY_TICKS := 1400
const JOIN_TIMEOUT := 10.0
const SECONDS_PER_TICK := 0.1

var _screen: Node
var _play: AssayButtonPlay
var _asked: Array = []
var _offline := false
var _done := false
var _join_deadline := 0.0
var _run_deadline := 0.0
var _desynced_at := -1
var _hashes: PackedStringArray = PackedStringArray()


## **A WALL-CLOCK CEILING, AND IT IS A MEMBER INITIALIZER** (ASSA-182). A `SceneTree` whose
## `_initialize` dies still gets `_process` every frame -- Godot exits 0 on a parse error and does not
## exit AT ALL on a runtime error in `_initialize` -- so a probe waiting for state that `_initialize`
## never set waits for ever. Measured on this machine: one typo held a headless Godot for 45 minutes,
## and an orphan that holds a port or an account makes somebody else's run fail for a reason they will
## never find. **Set at the end of `_initialize` it would be absent in exactly the case it is for**,
## which is the mistake the first version of this made (#242).
##
## 300 s is above every honest run these tools have: their own budgets are a 10 s join timeout plus a
## few hundred frames. The five with a budget of their own raise the ceiling from it -- two from the
## duration argument, three from the `_run_deadline` they already compute -- so this floor can
## never shorten a run somebody asked for.
const RUN_CEILING := 300.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

## **WHERE TO WRITE THE BENCH, WHEN SOMEBODY ASKS FOR IT** (`designs=<path>`, ASSA-173). Empty by
## default, and when it is empty **not one byte of this tool's output changes** -- `BUTTON SESSION OK`
## is a gate grep and this is not the night to move it.
##
## WHY IT IS HERE AND NOT A NEW TOOL. `art/design_rows.png` is drawn from `design_row_layout.gd`,
## which is fed by `art/bench_read.gd` -- which JOINS A LIVE RELAY WITH DESIGNS IN IT. There is no
## such relay: the standing bench on 7803 refuses every current client (ASSA-178), so the sheet is a
## picture of a world that exists nowhere and `check_review_layout.py` has to carry it as the one
## sheet that cannot declare itself. This loop already builds a world with designs in it, offline,
## headless and deterministically, and already reads `designs_of` eight lines below. The dump is the
## same shape `bench_read.gd` prints, so the layout half downstream is untouched.
var _designs_path := ""


func _initialize() -> void:
	# `designs=` IS PULLED OUT BEFORE THE POSITIONALS, so it can be passed in either mode without
	# becoming a fifth positional that the host form would have to count past.
	var argv := PackedStringArray()
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("designs="):
			_designs_path = arg.substr("designs=".length())
		else:
			argv.append(arg)
	if argv.is_empty():
		print("FAIL  usage: -- offline [seed] [rank] [job] | host[:port] name [rank] [job] [designs=P]")
		quit(1)
		return
	_offline = String(argv[0]) == "offline"
	var seed_text := String(argv[1]) if argv.size() > 1 else "777042"
	var rank := int(argv[2]) if argv.size() > 2 else 0
	var job := String(argv[3]) if argv.size() > 3 else AssayDemoPlan.JOB_SHOWCASE
	if job != AssayDemoPlan.JOB_SHOWCASE and job != AssayDemoPlan.JOB_BREAK:
		print("FAIL  job must be `%s` or `%s`, not `%s`"
				% [AssayDemoPlan.JOB_SHOWCASE, AssayDemoPlan.JOB_BREAK, job])
		quit(1)
		return

	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, for the same reason `tests/test_main_screen.gd` does it: a script run with
	# `--script` works inside `SceneTree._initialize`, before the root window is in the tree, so the
	# engine's own call comes too late to be useful. The screen is built once however often it runs.
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_screen._client.desynced.connect(func(tick: int) -> void: _desynced_at = tick)
	_screen._client.refused.connect(func(reason: String) -> void:
		_finish(false, "the relay refused us: %s" % reason))
	_screen._client.link_failed.connect(func(reason: String) -> void: _finish(false, reason))
	_play = AssayButtonPlay.new(_screen, rank)
	_play.job = job

	if _offline:
		_run_offline(seed_text)
		return
	# THE JOIN BUTTON, not `join()`. The front door is a button too, and a session that reached past
	# it would leave the one control every player uses first untested.
	_screen._host.text = String(argv[0])
	_screen._name.text = seed_text
	if not _press("Join"):
		_finish(false, "no Join button on the screen")
		return
	var now := Time.get_unix_time_from_system()
	_join_deadline = now + JOIN_TIMEOUT
	_run_deadline = now + JOIN_TIMEOUT + float(RELAY_TICKS) * SECONDS_PER_TICK
	# RAISED FROM THIS TOOL'S OWN BUDGET rather than from a number I picked: 1400 relay ticks is a
	# 150 s session before anything goes slowly. The floor above still covers the case where
	# `_initialize` dies before this line runs at all (ASSA-182).
	_ceiling = maxf(_ceiling, _run_deadline + 60.0)
	_screen._client.tick_bundle.connect(_after_bundle)


## OFFLINE: THIS SCRIPT IS THE RELAY. Welcome ourselves into a fresh world, then for every tick take
## whatever the buttons asked for and hand it back as the bundle a relay would have sent.
##
## A BUNDLE IS NUMBERED WITH THE TICK WE ARE AT, not the one it produces -- the relay builds
## `TickBundle { tick: world.tick }` and only then steps. I had that backwards once and every bundle
## a real relay sent was refused.
func _run_offline(seed_text: String) -> void:
	var welcome := AssaySimHost.fresh_welcome_json(seed_text, "limpet")
	if welcome == "":
		_finish(false, "could not make a world on seed %s" % seed_text)
		return
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		_finish(false, "offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return
	print("  offline on seed %s, world %dx%d, player %d at tick %d"
			% [seed_text, _screen._sim.size_tiles().x, _screen._sim.size_tiles().y,
			_screen._client.player_id, _screen._sim.tick()])
	for _i in range(OFFLINE_TICKS):
		_play.advance()
		if _play.finished:
			break
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		var before: int = _screen._sim.applied
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		if _screen._sim.applied == before:
			_finish(false, "the sim refused the bundle for tick %d" % at)
			return
	_report()


## RELAY: the relay owns the clock, so one step of the loop happens per bundle. Connected AFTER the
## screen's own handler, so by the time this runs the world has already been stepped -- which is the
## only state the loop may read.
func _after_bundle(_tick: int, _inputs: Array, _raw: String) -> void:
	if _done:
		return
	if _screen._sim.tick() % 20 == 0:
		_hashes.append("HASH tick=%d %s" % [_screen._sim.tick(), _screen._sim.hash_hex()])
	_play.advance()


func _process(_delta: float) -> bool:
	if _done or _offline:
		return _done
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  button_session.gd ran past its %ds ceiling: nothing finished it" % int(RUN_CEILING))
		quit(1)
		return true
	var now := Time.get_unix_time_from_system()
	if _screen._client.stage != AssayNetClient.Stage.JOINED:
		if now >= _join_deadline:
			_finish(false, "no welcome within %ds (stage %d)"
					% [JOIN_TIMEOUT, _screen._client.stage])
		return _done
	if _desynced_at >= 0:
		_finish(false, "the relay called us desynced at tick %d" % _desynced_at)
		return _done
	if _play.finished:
		_report()
		return _done
	if now >= _run_deadline:
		_finish(false, "the loop was still on %s at the deadline"
				% AssayButtonPlay.Step.keys()[_play.step])
		return _done
	return false


func _press(label: String) -> bool:
	var button := _find(_screen, label)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _find(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child
		var found := _find(child, label)
		if found != null:
			return found
	return null


## THE REPORT, and what it is allowed to claim. Every line is read out of the stepped world or out of
## the list of buttons actually pressed; the only verdict about a design is the sim's own word.
## **THE BENCH AS A FILE, in exactly the shape `art/bench_read.gd` prints** (ASSA-173) -- `designs`,
## `tick`, `hash`, `seed` -- so `art/design_row_layout.gd` reads it without knowing which of the two
## made it. The point is not the file: it is that the world behind it is one a SEED reproduces rather
## than one relay that happened to be standing, so the sheet downstream can be re-asked.
##
## **A FAILED WRITE FAILS THE RUN.** A tool asked for a file and silently not writing one is the shape
## I keep catching in my own instruments: the caller greps `BUTTON SESSION OK`, sees green, and draws
## a sheet from whatever stale file was already at that path.
func _write_designs(designs: Array) -> bool:
	var file := FileAccess.open(_designs_path, FileAccess.WRITE)
	if file == null:
		_finish(false, "could not write the bench to %s (error %d)"
				% [_designs_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify({
		"designs": designs,
		"tick": _screen._sim.tick(),
		"hash": _screen._sim.hash_hex(),
		"seed": _screen._sim.seed_hex() if _screen._sim.has_method("seed_hex") else "",
	}))
	file.close()
	print("  wrote %d design(s) to %s" % [designs.size(), _designs_path])
	return true


func _report() -> void:
	if _play.failed != "":
		_finish(false, _play.failed)
		return
	if _play.outcome == "":
		_finish(false, "the loop finished with nothing to say about the design it planted")
		return
	print("  pressed %d buttons and clicked the map %d times"
			% [_play.pressed.size(), _play.clicks.size()])
	for line in _play.pressed:
		print("    press %s" % line)
	for line in _play.clicks:
		print("    click %s" % line)
	for line in _hashes:
		print("  %s" % line)
	print("  the sim's verdict on the design before planting: %s" % _play.planted_verdict)
	# EVERY DESIGN THIS PLAYER ENDS UP HOLDING, in the sim's own words. This is the bench readout a
	# person sees, printed so a seed can be CHOSEN by what the board would read rather than by what I
	# expect a sheet to do. Mass and budget come along because a verdict alone hides its margin: the
	# seed this demo was built on showed WILL BREAK at mass 198 against a 192 budget, six units of
	# room, and a worldgen change tipped it to SAFE without anyone touching the demo (ASSA-45/#38).
	#
	# READ, NEVER DERIVED. `verdict` is the sim's word; this prints it beside the numbers rather than
	# comparing them here -- two renderers forming that opinion is the one disagreement the binding
	# is specifically forbidden to have (`designs_of`, ADR 0003 A8).
	# TYPED, NOT INFERRED: `_screen` is an untyped Node, so the binding's return has no static type
	# here and `:=` is a parse error. `check_every_script.sh` is the only thing that sees it -- the
	# suite never loads `tools/`, and Godot exits 0 on a parse error.
	var designs: Array = _screen._sim.designs_of(_screen._client.player_id)
	for entry in designs:
		var design: Dictionary = entry
		print("  bench: [%s] %s · mass %s-%s of budget %s-%s"
				% [String(design.get("verdict", "?")),
					"in hand" if bool(design.get("in_hand", false)) else String(
							design.get("mount", "?")),
					design.get("mass_low", "?"), design.get("mass_high", "?"),
					design.get("budget_low", "?"), design.get("budget_high", "?")])
	if _designs_path != "" and not _write_designs(designs):
		return
	print("  %s" % _play.outcome)
	print("  final: tick %d, hash %s, %d bundles applied"
			% [_screen._sim.tick(), _screen._sim.hash_hex(), _screen._sim.applied])
	# THE MARKER NAMES THE OUTCOME, and that is the whole of ASSA-140's last box. This printed one
	# `BUTTON SESSION OK` whether the loop ended with a machine mining, a machine standing there
	# stopped, or a design that came apart -- so a demo that paid off in 0% of worlds read green for
	# weeks, and the Game Director had to shoot a window to find out. Nothing here forms an opinion
	# about whether a break was correct: `outcome_kind` is read from the sim's own status string and
	# from whether the design survived, exactly as before, and all three are still a successful RUN.
	# What the marker stops doing is calling them the same RESULT.
	#
	# `BUTTON SESSION OK` is still the prefix and still the last line, so every existing grep keeps
	# working; a grep that cares which way it went now has something to match.
	# **AND THE RUNNING BINDING IS ASKED WHAT A REAL BUILDING CARRIES** (ASSA-183, which is ASSA-141's
	# box 4 -- the half I did not get then and named rather than left silent).
	#
	# WHY HERE AND NOT IN THE SUITE. `AssayScene.SIM_FACTS` declares the sim facts the scene draws,
	# and ASSA-141's two guards compare that list to the READS in `scene_view.gd`: source against
	# source. Neither asks the binding what it actually sends, so a key the binding stops sending is
	# caught at draw time and never by a gate. The suite version of this exists and works for one
	# dictionary -- `test_hud.gd::test_the_tile_fixture_still_matches_a_real_tile` caught a
	# seven-minute-stale dylib in under a minute when #231 added `ground_note` -- and `buildings` is
	# the dict the original defect was in (`lit`, absent before #184) and the one with no such test.
	#
	# It cannot go beside the tile one, because **a fresh world has tiles immediately and no
	# buildings**: a smelter needs the loop played, and there is no `give` command (validating
	# commands inside `step` is what makes cheating self-defeating). This script has already played
	# to a placed, mining machine by the time it gets here, headless and deterministic, in CI, for
	# nothing. Three other shapes were considered and are on the item with the reason each lost: play
	# 500 ticks inside the suite (complete, duplicates this script's job), a Rust-side guard reading
	# the .gd (cheap, still source-against-source, so **blind to a stale dylib** -- the whole point),
	# and a checked-in welcome fixture holding a smelter (pins SAVE 12's shape in a file that rots).
	var contract: Array = AssayScene.SIM_FACTS["building"]
	var sample: Array = _screen._sim.buildings()
	if sample.is_empty():
		_finish(false, ("the loop ended with no building in the world, so the binding's building "
				+ "contract was never asked (ASSA-183). Outcome was `%s`") % _play.outcome_kind)
		return
	for entry in sample:
		var building: Dictionary = entry
		for key in contract:
			if not building.has(key):
				_finish(false, ("`AssayScene.SIM_FACTS[\"building\"]` needs `%s` and the RUNNING "
						+ "binding does not send it. A real building carries: %s. This is the "
						+ "stale-dylib shape: the scene draws a fact the library stopped "
						+ "providing, and nothing but a frame could say so (ASSA-183).")
						% [String(key), str(building.keys())])
				return
	print("  binding contract: all %d building(s) carry every one of SIM_FACTS[\"building\"] (%s)"
			% [sample.size(), ", ".join(contract)])
	var suffix: String = String({
		"mining": "MACHINE MINING",
		"stopped": "MACHINE STOPPED",
		"broke": "DESIGN BROKE",
		"no_such_design": "NO SUCH DESIGN IN THIS WORLD",
	}.get(_play.outcome_kind, "OUTCOME UNNAMED"))
	print("  %s" % _play.job_note)
	print("BUTTON SESSION OK · %s" % suffix)
	_done = true
	quit(0)


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if ok:
		print("BUTTON SESSION OK")
		quit(0)
		return
	print("FAIL  %s" % why)
	if _play != null:
		print("  stopped on %s after %d presses and %d clicks"
				% [AssayButtonPlay.Step.keys()[_play.step], _play.pressed.size(),
				_play.clicks.size()])
		for line in _play.pressed:
			print("    press %s" % line)
		for line in _play.clicks:
			print("    click %s" % line)
	if _screen != null and _screen._sim.running():
		print("  world at tick %d, hash %s; pack %s"
				% [_screen._sim.tick(), _screen._sim.hash_hex(),
				_screen._sim.inventory_of(_screen._client.player_id)])
	quit(1)
