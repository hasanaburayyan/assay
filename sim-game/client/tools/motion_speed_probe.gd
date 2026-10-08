extends SceneTree
## CI: gated
## **THE DEV HARNESS FOR `AssayMotionProbe`: it builds a window, the probe does the measuring.**
##
##   godot --path client --script res://tools/motion_speed_probe.gd -- <seed> [seconds] [label] [mode]
##   **NEVER `--headless`.** A headless run has no vsync and no compositor: frames come as fast as
##   the loop can spin, so `dt` is a tenth of a real frame's and the distribution is of a machine
##   nobody plays on. The board plays a window. This measures a window.
##
## **EVERY NUMBER AND EVERY WORD OF THE REPORT MOVED TO `scripts/motion_probe.gd` (ASSA-211)** and
## nothing here computes anything. The reason is packaging, not tidiness: `tools/*` is excluded from
## both export presets and `--script` is dropped by the official release templates, so for as long as
## the arithmetic lived in this file **no measurement could ever come from the build we hand people**
## -- only from the project on a developer's or a runner's machine. The same class is now driven by
## `scripts/main.gd` on `-- --motion-probe <file> [seconds]`, which an export does honour.
##
## So this file is the SceneTree half and only that: instantiate `main.tscn`, hand it to the probe,
## pump one frame at a time, exit with the probe's own code. The bar, the charging rule, the pairing
## and the statistics are documented where they live.
##
## Run ceiling is the probe's own member initializer (Limpet, ASSA-182): a runtime error in
## `_initialize` must not leave this holding a relay and a window for ever.

## **THE OUTER BACKSTOP, AND IT IS NOT BOOKKEEPING FOR A TEST** (ASSA-182, kept when the measuring
## moved to `scripts/` in ASSA-211). `AssayMotionProbe` holds the ceiling that ends a MEASURED run, and
## it can only fire from inside `step()`. This one ends the PROCESS, which is the case the inner one
## cannot see: a probe that never reaches `step()` at all -- a scene that would not instantiate, an
## error thrown in the `tick_bundle` lambda, a null `_probe` -- leaves this `SceneTree` spinning with
## nobody watching a clock, which is exactly the defect ASSA-182 was filed for. Five seconds later than
## the probe's own, so on a healthy run the inner ceiling always reports its own reason first and this
## line never speaks.
const RUN_CEILING := AssayMotionProbe.RUN_CEILING + 5.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

var _probe: AssayMotionProbe
## **READ BY `_process` ON ITS OWN FIRST LINE, because `quit()` inside `_initialize` does not stop
## `_process`.** Measured 2026-10-04: a refusal printed, `quit(2)` was requested, `_process` ran anyway
## against a null screen, crashed, printed a second unrelated FAIL -- and the process exited **0**, so
## the refusal reported success twice over.
var _refused := false


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var want_seed := String(argv[0]) if argv.size() > 0 else ""
	var seconds := float(argv[1]) if argv.size() > 1 else 8.0
	var label := String(argv[2]) if argv.size() > 2 else "run"
	# **`mode` IS MARLOW'S (ASSA-212) AND IT STAYS A DEV ARGUMENT.** `start` orders a SECOND walk from
	# a standstill with the playout clock long since running, which is a reproduction the shipped door
	# has no business offering a player: the board's one line is `-- --motion-probe <file> [seconds]`
	# and every token added to it is a token to get wrong. The arithmetic moved into
	# `AssayMotionProbe` with the rest in ASSA-211; only the way in is here.
	var mode := String(argv[3]) if argv.size() > 3 else "steady"
	if mode != "steady" and mode != "start":
		print("FAIL  mode must be `steady` or `start`, not %s" % mode)
		_refused = true
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		print("FAIL  headless: this probe measures frame pacing and there is none here")
		_refused = true
		quit(2)
		return
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	_probe = AssayMotionProbe.new()
	_probe.begin(screen, seconds, label, want_seed, mode)


func _process(delta: float) -> bool:
	if _refused:
		return true
	if _probe == null or Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  the harness ran past its %ds ceiling and the probe never ended the run itself"
				% int(RUN_CEILING))
		quit(1)
		return true
	if _probe.step(delta) == AssayMotionProbe.Status.RUNNING:
		return false
	quit(_probe.exit_code())
	return true
