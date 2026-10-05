extends SceneTree
## **WHAT EACH CANDIDATE START RULE COSTS, SIDE BY SIDE** (ASSA-212).
##
##   godot --headless --path client --script res://tools/start_jump_table.gd
##
## The clock cannot start where the waiting body is drawn AND at the depth the loop settles to: the
## waiting body is drawn on `oldest`, which is `delay + LEAD` behind the newest position, and the
## steady state sits `delay` behind it. **That half tick is spent either in one frame (a jump the
## player sees once) or over time (a rate the player may see as speed).** This table is how that
## choice was made with numbers instead of an argument.
##
## It drives the REAL `AssayScene.playout_at` through `tests/test_scene_view.gd::_drive_playout` --
## the same instrument the suite's own bars are read from, instantiated rather than copied, because a
## copy of a loop is a second thing to keep right. **The two rules that no longer ship are driven
## from OUTSIDE the function** (`start_rule`), so this table stays runnable with nothing mutated: the
## start frame assigns `at` and returns without advancing, which a caller can do for it.
var _quitting := false


func _process(_delta: float) -> bool:
	if not _quitting:
		print("FAIL  start_jump_table.gd: _initialize ended without asking to quit")
		quit(1)
	return true


func _initialize() -> void:
	var harness: Object = load("res://tests/test_scene_view.gd").new()
	var rules := [
		[0, "WAS       wait depth>=delay, at=newest-delay"],
		[1, "ONE-LINE  wait depth>=delay, at=oldest"],
		[-1, "SHIPS     wait depth>=delay+LEAD-1, at=oldest"],
	]
	# THE TICK-RATE MISREAD IS THE PLATFORM'S, AND IT IS THE OTHER HALF OF EVERY RATIO HERE. `bias` is
	# how long the clock BELIEVES a tick is as a fraction of how long it is; 0.86 is what this Mac
	# measured against a real relay, and 1.14 is the same error the other way, which no test on this
	# item has ever judged a START against.
	for fps: float in [90.0, 30.0]:
		for bias: float in [0.86, 1.0, 1.14]:
			print("\n=== bias %.2f  fps %.0f  (a clock believing a tick is %.0f%% of true) ==="
					% [bias, fps, bias * 100.0])
			print("  rule                                        jump      freeze  depth"
					+ "   cold ratio     after 1s       starv drag  windD trim")
			for entry: Array in rules:
				var rule := int(entry[0])
				var cold: Dictionary = harness._drive_playout(bias, true, 12.0, 0.0, 1.0, fps, rule)
				var late: Dictionary = harness._drive_playout(bias, true, 12.0, 1.0, 1.0, fps, rule)
				var jump := float(cold["start_jump"])
				print(("  %-42s %5.3ft/%4.1fpx %5.0fms %4.2f  %.3f-%.3f  %.3f-%.3f  %3d  %3d"
						+ "  %5.2f %5.3f") % [String(entry[1]), jump, jump * AssayScene.TILE_PX,
						float(cold["freeze_s"]) * 1000.0, float(cold["start_depth"]),
						float(cold["ratio_min"]), float(cold["ratio_max"]),
						float(late["ratio_min"]), float(late["ratio_max"]),
						int(cold["starved"]), int(cold["dragged"]), float(cold["wind_depth"]),
						float(cold["trim"])])
	print("\njump is the distance the frame the clock STARTS on moves the body from the position it")
	print("was standing on while the buffer filled. cold ratio is drawn speed / true from the FIRST")
	print("running frame; after 1s is the same statistic with the first second dropped.")
	_quitting = true
	quit(0)
