extends SceneTree
## ONE TEST, RUN ALONE. A SCRATCH INSTRUMENT, not part of the suite (ASSA-343's open box).
##
##   godot --headless --path client --script res://tools/limpet_one_test_scratch.gd -- <file> <method>
##
## Why it exists: the studio Mac is at load 88-147 and a bash slot takes ~10 minutes, so running 469
## tests three times to prove ONE of them can go red is not affordable tonight. The verdict line is
## the same shape as `run_tests.gd`'s so the same grep reads it.
##
## **IT IS MODELLED ON `run_tests.gd` LINE FOR LINE ON THE ONE THING THAT MATTERS: `set_runner` AND
## `fail`.** A suite handed no runner has `_fail` return false into the void -- that is how four of
## five tests of mine once passed by never being able to fail (2026-10-06). So: `set_runner(self)` is
## called, `fail()` appends, and `ok == false` with nothing said is itself counted a failure.
var failures: Array[String] = []
var passed := 0
var root_node: Node = null


func _initialize() -> void:
	root_node = Node.new()
	root.add_child(root_node)
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("0 passed, 1 failed, 0 skipped")
		print("FAIL  need <file> <method> after --")
		quit(1)
		return
	var path: String = "res://tests/%s" % args[0]
	var only: String = args[1]
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		print("0 passed, 1 failed, 0 skipped")
		print("FAIL  %s would not load; fix the parse error above" % path)
		quit(1)
		return
	var suite = script.new()
	if not suite.has_method("set_runner"):
		print("0 passed, 1 failed, 0 skipped")
		print("FAIL  %s has no set_runner, so `_fail` would say nothing" % path)
		quit(1)
		return
	suite.set_runner(self)
	if not suite.has_method(only):
		print("0 passed, 1 failed, 0 skipped")
		print("FAIL  %s has no method %s" % [path, only])
		quit(1)
		return
	var before := failures.size()
	var ok = suite.call(only)
	if failures.size() > before:
		print("FAIL  %s::%s" % [path.get_file(), only])
	elif ok == false:
		failures.append("%s::%s returned false and said nothing" % [path.get_file(), only])
		print("FAIL  %s::%s" % [path.get_file(), only])
	else:
		passed += 1
	for line in failures:
		print("FAIL  %s" % line)
	print("%d passed, %d failed, 0 skipped" % [passed, failures.size()])
	quit(1 if failures.size() > 0 else 0)


func fail(reason: String) -> bool:
	failures.append(reason)
	return false
