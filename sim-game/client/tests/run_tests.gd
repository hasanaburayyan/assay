extends SceneTree
## THE CLIENT'S OWN SUITE, headless and with no relay running.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Every `test_*` method on every `tests/test_*.gd` file. A test returns `true` or calls `fail()`
## with a sentence a person can act on. Prints `N passed, M failed` LAST, which is the line CI
## greps -- Godot exits 0 on a compile error, so a count printed last is the only honest verdict.
##
## `cargo test` covers the sim and the protocol's Rust side; this covers the GDScript that talks to
## it. Neither replaces the other, and nothing here may test a game rule: rules live in `sim`.

var failures: Array[String] = []
var passed := 0
var root_node: Node = null


func _initialize() -> void:
	root_node = Node.new()
	root.add_child(root_node)
	var names := _test_files()
	if names.is_empty():
		print("0 passed, 1 failed, 0 skipped")
		print("FAIL  no test files found under res://tests/")
		quit(1)
		return
	for path in names:
		var script: GDScript = load(path)
		# A TEST FILE WITH A PARSE ERROR LOADS AS A NON-NULL, UNUSABLE SCRIPT. Calling `new()` on it
		# raises an error that leaves `_initialize` without ever reaching `quit()`, and a headless
		# Godot with nothing to do then SITS THERE FOREVER -- in CI that is the job's whole timeout
		# spent on a typo, with no count printed and no reason given. Measured 2026-10-01 on a bad
		# `tests/test_sim_host.gd`. So the file is checked before it is used, and a broken one is a
		# failure like any other.
		if script == null or not script.can_instantiate():
			failures.append("%s would not load; fix the parse error above" % path)
			print("FAIL  %s would not load" % path.get_file())
			continue
		var suite = script.new()
		if suite.has_method("set_runner"):
			suite.set_runner(self)
		var ran := 0
		for entry in script.get_script_method_list():
			var mname: String = entry["name"]
			if not mname.begins_with("test_"):
				continue
			ran += 1
			var before := failures.size()
			var ok = suite.call(mname)
			if failures.size() > before:
				print("FAIL  %s::%s" % [path.get_file(), mname])
			elif ok == false:
				failures.append("%s::%s returned false and said nothing" % [path.get_file(), mname])
				print("FAIL  %s::%s" % [path.get_file(), mname])
			else:
				passed += 1
		if ran == 0:
			failures.append("%s has no test_* methods" % path.get_file())
	for line in failures:
		print("FAIL  %s" % line)
	print("%d passed, %d failed, 0 skipped" % [passed, failures.size()])
	quit(1 if failures.size() > 0 else 0)


func fail(reason: String) -> bool:
	failures.append(reason)
	return false


func _test_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		return out
	for name in dir.get_files():
		var file := name.trim_suffix(".remap")
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append("res://tests/%s" % file)
	out.sort()
	return out
