extends RefCounted
## WHAT IS IN THE BUNDLE IS NOT WHAT IS IN THE PROJECT, AND THE SUITE CANNOT SEE THE DIFFERENCE.
##
## `export_presets.cfg` excludes `tests/*` and `tools/*`. Every other test here runs with those folders
## present, so a `scripts/` file that calls into one of them passes everything and then fails to PARSE
## in the shipped build -- which takes the whole file down, because a GDScript parse error is not a
## runtime error you can catch.
##
## THAT IS NOT HYPOTHETICAL; IT IS ASSA-51 AND IT WAS MINE. `main.gd` called `AssayDemoPlan.held` after
## PR #64. `AssayDemoPlan` lives in `tools/`, so the exported client could not load `main.gd` at all,
## `_ready` never ran, the self-check never fired, nothing ever called `quit()`, and the GUI binary sat
## in the platform event loop. Every main Build for three merges hung for 45 minutes at "The exported
## client runs" and billed macOS runner minutes at 10x until somebody noticed. The suite was green for
## all of it, and so was `tools/check_every_script.sh`, because both compile the project as it sits on
## disk WITH `tools/` in it.
##
## So this test reads the real exclusion list out of the real preset file and holds the shipped scripts
## to it. It is cheap, it runs in the normal suite, and it fails in seconds where the bundle fails in
## three quarters of an hour.


var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## Every `class_name` declared under a path the export throws away.
func _excluded_classes() -> Dictionary:
	var found := {}
	for dir in _excluded_dirs():
		for file in _gd_files(dir):
			var text := FileAccess.get_file_as_string(file)
			for line in text.split("\n"):
				var trimmed := String(line).strip_edges()
				if trimmed.begins_with("class_name "):
					found[trimmed.substr(11).strip_edges()] = file
					break
	return found


## The excluded folders, READ FROM THE PRESET rather than written down here. If someone narrows or
## widens the filter, this test follows them; a copy of the list would be the same class of bug the
## test exists to catch.
func _excluded_dirs() -> PackedStringArray:
	var out := PackedStringArray()
	var text := FileAccess.get_file_as_string("res://export_presets.cfg")
	for line in text.split("\n"):
		var trimmed := String(line).strip_edges()
		if not trimmed.begins_with("exclude_filter="):
			continue
		var value := trimmed.substr(15).strip_edges().trim_prefix("\"").trim_suffix("\"")
		for pattern in value.split(","):
			var dir := String(pattern).strip_edges().trim_suffix("*").trim_suffix("/")
			if dir != "":
				out.append("res://%s" % dir)
	return out


func _gd_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_files_at(dir):
		if String(name).ends_with(".gd"):
			out.append("%s/%s" % [dir, name])
	return out


## NO SHIPPED SCRIPT MAY NAME A CLASS THE EXPORT LEAVES BEHIND.
##
## The check is a plain substring search for the class name as a word. That is blunt on purpose: it
## cannot be fooled by a call made through a variable, and the cost of being blunt is that a shipped
## file may not even MENTION one of these names in running code. Comments are allowed, because this
## file and `actions.gd` both have to explain the bug by name -- so the search ignores `#` lines, which
## is the one concession and the only one.
func test_no_shipped_script_references_an_excluded_class() -> bool:
	var excluded := _excluded_classes()
	if excluded.is_empty():
		return _fail(("found no class_name under %s, so this test is not checking anything. Either the "
				+ "preset's exclude_filter changed shape or the folders moved.") % [_excluded_dirs()])
	var shipped := _gd_files("res://scripts")
	if shipped.size() < 2:
		return _fail("found %d script(s) under res://scripts, which cannot be right" % shipped.size())
	for file in shipped:
		var text := FileAccess.get_file_as_string(file)
		var number := 0
		for line in text.split("\n"):
			number += 1
			var code := String(line)
			var hash_at := code.find("#")
			if hash_at >= 0:
				code = code.substr(0, hash_at)
			for name: String in excluded:
				if not code.contains(name):
					continue
				return _fail(("%s:%d names `%s`, which is declared in %s -- a path "
						+ "`export_presets.cfg` EXCLUDES. The shipped bundle has no such class, so this "
						+ "file will not parse there, and a GDScript parse error takes the whole file "
						+ "with it. If the exported client's main script is the one that fails, nothing "
						+ "calls quit() and the process hangs instead of failing. That was ASSA-51. Move "
						+ "what you need into res://scripts and have the tool call it.")
						% [file, number, name, excluded[name]])
	return true


## AND THE PRESET STILL EXCLUDES THE TWO FOLDERS THE REST OF THIS FILE ASSUMES.
##
## Without this, deleting the exclusion would make the test above vacuously green -- there would be no
## excluded classes to find, which `test_no_shipped_script_references_an_excluded_class` reports as a
## failure, so this is belt and braces. It is here for the opposite case: someone adds a THIRD excluded
## folder full of classes and nobody notices the scripts are now allowed to reference the first two.
func test_the_export_still_excludes_tests_and_tools() -> bool:
	var dirs := Array(_excluded_dirs())
	for wanted in ["res://tests", "res://tools"]:
		if not dirs.has(wanted):
			return _fail(("export_presets.cfg no longer excludes %s (it excludes %s). If that is "
					+ "deliberate, the bundle now ships test and probe code to players; if it is not, "
					+ "the shipped scripts have lost a guard.") % [wanted, dirs])
	return true
