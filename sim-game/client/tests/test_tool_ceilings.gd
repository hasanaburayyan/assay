extends RefCounted
## **NO INSTRUMENT THIS STUDIO RUNS MAY HOLD THE MACHINE FOR EVER** (ASSA-182).
##
## A `SceneTree` script whose `_initialize` dies still gets `_process` every frame. Godot exits 0 on a
## parse error and does not exit AT ALL on a runtime error in `_initialize`, so a tool waiting for
## state that `_initialize` never set waits for ever: measured on the studio Mac, where one typo in
## `reconnect_probe.gd` held a headless Godot for 45 minutes at nice priority. `run_tests.gd`'s own
## header records the same failure from the other side -- a test file with a parse error left this
## suite sitting in CI for the job's whole timeout.
##
## **THAT IS NOT TIDINESS. Several of us run probes on one Mac**, and an orphan holding a port or an
## account (the relay refuses an account that is already connected) makes somebody else's run fail for
## a reason they will never find.
##
## **THE SET IS MEASURED, NEVER WRITTEN DOWN.** Every `tools/*.gd` that extends `SceneTree` and has a
## `_process` loop is in scope, found by reading the files. A written list would have let the twelfth
## tool arrive without a ceiling and still pass -- which is this item's own history: ASSA-182 scoped
## itself to eleven files and said `window_shot.gd` "has something of the kind already", because a grep
## for "ceiling" matched `AssayScene.player_ceiling`, a layout number in pixels. A word matched and
## nothing was measured; `window_shot` and `maren_schematic_demo_shot` had no clock at all.
##
## **AND IT MUST BE A MEMBER INITIALIZER, which is the clause this test exists for.** The first version
## of the fix (#242) set the clock at the END of `_initialize` and skipped the check while it was zero
## -- a guard absent in exactly the case it was written for. Member initializers run when the object is
## built, so an error anywhere inside `_initialize` still leaves a clock running.

var runner = null

## **THE SECOND CLASS, AND IT IS COVERED NOW TOO.** A tool with no `_process` loop cannot sit in one,
## but it is not out of danger: `SceneTree`'s default `_process` returns false, so a one-shot tool ends
## when something calls `quit()` and not when `_initialize` returns. An error inside `_initialize` skips
## that call and the engine spins with no output and no exit -- measured 2026-10-04 with a scratch
## script, alive after 25 s. Those twelve tools get a `_process` that refuses to wait instead of a
## clock, because there is nothing a one-shot tool legitimately waits for.
const SCOPE := "extends SceneTree"
## Below this, something is wrong with the scan and not with the tools: a test whose set is empty
## passes for the absence of its data.
const FEWEST_TOOLS := 12
const FEWEST_ONE_SHOT := 12


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## `quit(<something that is not 0>)` on one line.
func _quits_non_zero(line: String) -> bool:
	if not line.begins_with("quit("):
		return false
	return not line.begins_with("quit()") and not line.begins_with("quit(0)")


## The name of a local helper called on its own on this line (`_bail("...")`, `_stop(1)`), or "".
func _called_helper(line: String) -> String:
	if not line.begins_with("_"):
		return ""
	var open := line.find("(")
	if open <= 0:
		return ""
	var name := line.substr(0, open)
	return name if name.is_valid_identifier() else ""


## Whether this call hands its helper a zero exit code -- written, or by the signature's own default.
func _asks_for_zero(source: String, name: String, call_line: String) -> bool:
	var open := call_line.find("(")
	var args := call_line.substr(open + 1).trim_suffix(")").strip_edges()
	if args == "0":
		return true
	if args != "":
		return false
	for raw in source.split("\n"):
		var line := String(raw)
		if not line.begins_with("func %s(" % name):
			continue
		# `func _stop(code: int = 0) -> void:` called as `_stop()` is `quit(0)` with extra steps.
		return line.contains("= 0)") or line.contains("= 0,") or line.contains("= 0 ")
	return false


## Whether `func <name>` in this source reaches a non-zero `quit()`, following the helpers it calls.
##
## **TWO HOPS ARE NORMAL IN THIS TREE AND ONE HOP WAS NOT ENOUGH**: the shot tools bail through
## `_bail(why)`, which prints the reason and calls `_finish(1)`, which quits. A one-hop version of this
## function called five healthy tools defective, which is the shape of mistake this whole file is about
## -- an instrument that reports a finding where there is only a style it did not know.
##
## `quit(code)` is accepted without knowing the value: a static scan cannot see a runtime argument, and
## a tool whose own convention is `_finish(1)` on failure has said what it means.
func _quits_non_zero_somewhere(source: String, name: String, depth: int = 3) -> bool:
	if depth <= 0:
		return false
	var lines: PackedStringArray = source.split("\n")
	var inside := false
	var calls := PackedStringArray()
	for raw in lines:
		var line := String(raw)
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if not inside:
			continue
		var text := line.strip_edges()
		if _quits_non_zero(text):
			return true
		var called := _called_helper(text)
		if called != "" and called != name:
			calls.append(called)
	for called in calls:
		if _quits_non_zero_somewhere(source, String(called), depth - 1):
			return true
	return false


## Every `tools/*.gd` that extends `SceneTree` and has NO `_process` of its own, as `{path: source}`.
func _one_shot_tools() -> Dictionary:
	var out := {}
	for name in DirAccess.get_files_at("res://tools"):
		if not String(name).ends_with(".gd"):
			continue
		var path := "res://tools/%s" % name
		var source := FileAccess.get_file_as_string(path)
		if source == "" or not source.contains(SCOPE):
			continue
		# **CLASSIFIED BY THE REFUSAL AND NOT BY "HAS NO `_process`", because the fix GIVES them one.**
		# My first version of this split read "no `func _process`", which was true of these twelve
		# until the moment they were fixed -- and then all twelve moved into the looping set and were
		# failed for having no wall-clock ceiling, which is not what a tool with nothing to wait for
		# needs. A new one-shot tool with neither pattern still fails: it lands in the looping set and
		# is named there.
		if not source.contains("\n\tif not _quitting:"):
			continue
		out[path] = source
	return out


## **A ONE-SHOT TOOL THAT FELL OUT OF `_initialize` MUST END, AND SAY SO.** No clock: the `_process`
## these get returns true on its first frame, which is the only honest thing a tool with nothing to
## wait for can do. The flag is what tells a deliberate early exit (a bad argument, a missing world)
## from a fall-through, and it is set beside every `quit()` rather than at the end of `_initialize`,
## because the end is the line an error never reaches.
func test_every_one_shot_tool_refuses_to_wait() -> bool:
	var tools := _one_shot_tools()
	if tools.size() < FEWEST_ONE_SHOT:
		return _fail(("only %d one-shot tools were found under res://tools and there are at least %d; "
				+ "the scan is broken, so this test is about nothing") % [tools.size(), FEWEST_ONE_SHOT])
	# **THERE IS NO "HAS NO REFUSAL" LEG HERE AND THAT IS DELIBERATE.** The set is selected BY the
	# refusal, so such a leg could never fire -- a check that cannot fail is not evidence. A one-shot
	# tool without the pattern falls into `_looping_tools` and is named by the clause above instead.
	var unmarked := PackedStringArray()
	for path in tools:
		var source: String = tools[path]
		# EVERY `quit()` IS MARKED, not just the last one. A tool whose bad-argument path quits without
		# setting the flag would print a FAIL about a run that did exactly what it meant to. The
		# refusal's own `quit(1)` is skipped: it is the line the flag exists to reach.
		for line in source.split("\n"):
			var text := String(line).strip_edges()
			if not text.begins_with("quit(") or text.begins_with("quit(1)"):
				continue
			if not source.contains("_quitting = true\n%s" % line):
				unmarked.append("%s: %s" % [String(path).get_file(), text])
	if not unmarked.is_empty():
		return _fail(("%d deliberate `quit()` call(s) are not marked with `_quitting = true`, so a "
				+ "tool that exited on purpose would be reported as a fall-through: %s")
				% [unmarked.size(), String(" | ").join(unmarked)])
	return true


## Every `tools/*.gd` that could sit in a `_process` loop, as `{path: source}`.
func _looping_tools() -> Dictionary:
	var out := {}
	for name in DirAccess.get_files_at("res://tools"):
		if not String(name).ends_with(".gd"):
			continue
		var path := "res://tools/%s" % name
		var source := FileAccess.get_file_as_string(path)
		if source == "" or not source.contains(SCOPE):
			continue
		if not source.contains("\nfunc _process("):
			continue
		# A one-shot tool's `_process` exists to end the run, not to wait in it; it is held to the
		# clause below rather than to a clock.
		if source.contains("\n\tif not _quitting:"):
			continue
		out[path] = source
	return out


## THE CLOCK IS BUILT WITH THE OBJECT, not at the end of `_initialize`.
func test_every_looping_tool_carries_a_wall_clock_ceiling() -> bool:
	var tools := _looping_tools()
	if tools.size() < FEWEST_TOOLS:
		return _fail(("only %d looping tools were found under res://tools and there are at least %d; "
				+ "the scan is broken, so this test is about nothing") % [tools.size(), FEWEST_TOOLS])
	var naked := PackedStringArray()
	var late := PackedStringArray()
	for path in tools:
		var source: String = tools[path]
		if not source.contains("\nconst RUN_CEILING :="):
			naked.append(String(path).get_file())
			continue
		# **THE MEMBER INITIALIZER ITSELF.** A `var _ceiling` assigned inside a function is the defect
		# this clause is named for, and it reads exactly like a fix from a diff.
		if not source.contains("\nvar _ceiling := Time.get_unix_time_from_system()"):
			late.append(String(path).get_file())
	if not naked.is_empty():
		return _fail(("%d looping tool(s) have no RUN_CEILING, so a runtime error in `_initialize` "
				+ "leaves them holding this machine until somebody notices: %s. A tool with nothing "
				+ "to wait for wants the one-shot refusal instead -- see the clause above.")
				% [naked.size(), String(", ").join(naked)])
	if not late.is_empty():
		return _fail(("%d tool(s) declare RUN_CEILING but do not build the clock with the object "
				+ "(`var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING`), so the guard is "
				+ "absent in the case it exists for: %s") % [late.size(), String(", ").join(late)])
	return true


## AND THE CLOCK IS READ, AND READING IT ENDS THE RUN LOUDLY. A ceiling nobody compares against is a
## constant; a bail that exits 0 is a run CI will call a pass.
func test_every_ceiling_is_read_and_bails_non_zero() -> bool:
	var tools := _looping_tools()
	if tools.size() < FEWEST_TOOLS:
		return _fail("only %d looping tools found; the scan is broken" % tools.size())
	var unread := PackedStringArray()
	var quiet := PackedStringArray()
	for path in tools:
		var lines: PackedStringArray = String(tools[path]).split("\n")
		var at := -1
		for i in lines.size():
			var line := String(lines[i]).strip_edges()
			if line.begins_with("#"):
				continue
			# Both idioms in the tree: `Time.get_unix_time_from_system() > _ceiling` and `_now() >=
			# _ceiling`, which is the same question asked through a tool's own helper.
			if line.contains("> _ceiling") or line.contains(">= _ceiling"):
				at = i
				break
		if at < 0:
			unread.append(String(path).get_file())
			continue
		# THE BAIL, WITHIN SIGHT OF THE COMPARISON, AND NON-ZERO: `quit()` and `quit(0)` would hand CI
		# a green run over a tool that gave up.
		#
		# **THROUGH A HELPER COUNTS, and my first version of this clause called six tools defective for
		# having one.** Most of the tree bails through `_bail(why)`, which kills the relay, prints the
		# reason and quits 1 -- better than an inline quit, not worse. So a call on the bail path is
		# followed into that function's own body. The one tool this clause was actually right about
		# called `_stop()`, whose `quit(0)` reported success for a probe that had given up.
		var bails := false
		for i in range(at, mini(at + 8, lines.size())):
			var line := String(lines[i]).strip_edges()
			if _quits_non_zero(line):
				bails = true
				break
			var called := _called_helper(line)
			if called == "":
				continue
			# **A HELPER ASKED FOR A ZERO IS NOT A BAIL, and a mutation is why this clause exists.**
			# Reverting the fix below to `_stop(code: int = 0)` left the bail path calling `_stop()`,
			# whose quit the scan can only see as `quit(code)` -- so the test passed over exactly the
			# defect it had just found. The call site's own argument closes it: an explicit `0`, or
			# nothing where the signature defaults to 0, is a run that gave up and reported success.
			if _asks_for_zero(String(tools[path]), called, line):
				continue
			if _quits_non_zero_somewhere(String(tools[path]), called):
				bails = true
				break
		if not bails:
			quiet.append(String(path).get_file())
	if not unread.is_empty():
		return _fail(("%d tool(s) declare a ceiling and never compare anything to it, so the clock "
				+ "runs and nothing reads it: %s") % [unread.size(), String(", ").join(unread)])
	if not quiet.is_empty():
		return _fail(("%d tool(s) reach their ceiling without quitting non-zero within 8 lines, so a "
				+ "tool that gave up reports success: %s") % [quiet.size(), String(", ").join(quiet)])
	return true
