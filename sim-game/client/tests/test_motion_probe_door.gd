extends RefCounted
## **THE ONE ARGUMENT THAT LETS A SHIPPED BUILD MEASURE ITSELF** (ASSA-211).
##
## Before this door existed, every motion number the studio owned was taken on a developer's or a
## runner's PROJECT, never on the `Assay.exe` a player downloads -- because `tools/*` is excluded from
## both export presets, and because the official release templates DROP `--script` (measured, with a
## bogus script path as the control). So "the board's machine is jumpy" could never be answered with a
## number from the board's machine.
##
## What this file holds: the flag parses the way the packaging README tells a player to type it; the
## measuring half lives where an export can reach it and the driving half does not; the export still
## does not ship `tools/`; and `main.gd` still wires the door it claims to.
##
## **IT CANNOT PROVE THE EXPORTED BINARY HONOURS THE FLAG** -- that needs a real export, and the proof
## is the CI step that runs the zip's own binary and greps the file it wrote (recorded on ASSA-211).

const PROBE := "res://scripts/motion_probe.gd"
const TOOL := "res://tools/motion_speed_probe.gd"
const MAIN := "res://scripts/main.gd"

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## THE SHAPE THE README TELLS A PLAYER TO TYPE, and the shapes a mistyped one must not be read as.
func test_the_flag_parses_a_path_and_optional_seconds() -> bool:
	# **ONE ARGV ELEMENT PER ENTRY, NEVER A STRING SPLIT ON SPACES.** The engine hands over an array the
	# shell has already word-split, so a player's `C:\Users\Sam\My Documents\assay.txt` arrives as ONE
	# element -- and a test that splits its own fixture on spaces cannot express that case at all. My
	# first version did, and failed itself on exactly the path a Windows player is most likely to type.
	var cases: Array = [
		[PackedStringArray(["--motion-probe", "out.txt"]), "out.txt", 8.0],
		[PackedStringArray(["--motion-probe", "out.txt", "12"]), "out.txt", 12.0],
		[PackedStringArray(["--motion-probe", "C:\\Users\\Sam\\My Docs\\a.txt", "2.5"]),
				"C:\\Users\\Sam\\My Docs\\a.txt", 2.5],
		# A trailing flag is not a duration. Reading "--loud" as 0.0 would measure nothing and report it.
		[PackedStringArray(["--motion-probe", "out.txt", "--loud"]), "out.txt", 8.0],
		# The selfcheck door is a different door and must not answer for this one.
		[PackedStringArray(["--selfcheck", "out.txt"]), "", 8.0],
		# The flag with nothing after it is a typo, not a request to write to "".
		[PackedStringArray(["--motion-probe"]), "", 8.0],
		[PackedStringArray([]), "", 8.0],
	]
	for case in cases:
		var args: PackedStringArray = case[0]
		var got_path := AssayMotionProbe.path_in(args)
		if got_path != String(case[1]):
			return _fail("%s parsed a path of '%s', not '%s'" % [args, got_path, case[1]])
		var got_seconds := AssayMotionProbe.seconds_in(args)
		if not is_equal_approx(got_seconds, float(case[2])):
			return _fail("%s parsed %f seconds, not %f" % [args, got_seconds, case[2]])
	return true


## **THE MEASURING IS INSIDE THE PACK AND THE DRIVING IS NOT, which is the entire fix.** A report
## generator that drifts back into `tools/` would leave the exported client with a flag and nothing to
## run, so this pins the side of the fence each half is on.
func test_the_measuring_half_is_packed_and_the_harness_is_not() -> bool:
	if not FileAccess.file_exists(PROBE):
		return _fail("%s is gone: the exported client has no measuring code to reach" % PROBE)
	var probe := FileAccess.get_file_as_string(PROBE)
	if not probe.contains("class_name AssayMotionProbe"):
		return _fail("%s does not declare class_name AssayMotionProbe" % PROBE)
	# THE ARITHMETIC, NOT MERELY A FILE. These are the lines the verdict is made of; if they are not
	# here they are somewhere an export cannot load.
	for needed in ["func report_text()", "VERDICT:", "const TOLERANCE :=", "func _report()"]:
		if not probe.contains(needed):
			return _fail("%s no longer contains `%s`, so the shipped build cannot produce a verdict"
					% [PROBE, needed])
	var tool_source := FileAccess.get_file_as_string(TOOL)
	if tool_source == "":
		return _fail("%s is gone: the dev harness is how this is run on a checkout" % TOOL)
	# The harness may DRIVE the probe; it may not compute. A `_report` or a bar of its own here is the
	# duplication this item removed, and two copies of a verdict diverge silently.
	for forbidden in ["func _report(", "const TOLERANCE :=", "func _sample("]:
		if tool_source.contains(forbidden):
			return _fail(("%s contains `%s` again: the measuring belongs in %s, which is the half an "
					+ "export can load") % [TOOL, forbidden, PROBE])
	return true


## **THE EXPORT STILL DOES NOT SHIP `tools/`.** The item's own constraint: this door exists so that
## lifting the exclusion is never the fix. `tools/*.gd` assume a dev checkout and a relay on disk.
func test_both_presets_still_exclude_tests_and_tools() -> bool:
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	if presets == "":
		return _fail("export_presets.cfg could not be read, so this test is about nothing")
	var filters := 0
	for line in presets.split("\n"):
		var text := String(line).strip_edges()
		if not text.begins_with("exclude_filter="):
			continue
		filters += 1
		for folder in ["tests/*", "tools/*"]:
			if not text.contains(folder):
				return _fail(("an export preset stopped excluding `%s` (%s). The motion probe reaches "
						+ "the shipped build through `--motion-probe`, never by packing tools/")
						% [folder, text])
	# Two presets, macOS and Windows. A scan that found none would pass the loop above silently.
	if filters < 2:
		return _fail("found %d exclude_filter lines and expected at least 2 (macOS, Windows)" % filters)
	return true


## **`main.gd` STILL OPENS THE DOOR, AND STILL STEPS THE PROBE BEFORE IT PUBLISHES THE RECTANGLE.**
## The order is the measurement, not style: `_refresh_world` publishes the rect the probe reads, so
## stepping after it would hand the client's run a rect from this frame where the harness reads one
## from the previous frame, and #284's verdict divides by the previous frame's delta because of exactly
## that one-frame phase. Sampling in the other phase would invert the fix without failing anything.
func test_main_opens_the_door_and_steps_before_publishing() -> bool:
	var main := FileAccess.get_file_as_string(MAIN)
	if main == "":
		return _fail("%s could not be read" % MAIN)
	for needed in ["AssayMotionProbe.requested_path()", "func _step_motion_probe(",
			"_motion_probe.report_text()"]:
		if not main.contains(needed):
			return _fail(("%s no longer contains `%s`, so an exported build asked to measure itself "
					+ "would do nothing or write nothing") % [MAIN, needed])
	var lines := main.split("\n")
	var at_step := -1
	var at_publish := -1
	var in_process := false
	for i in lines.size():
		var text := String(lines[i])
		if text.begins_with("func _process("):
			in_process = true
			continue
		if in_process and text.begins_with("func ") :
			break
		if not in_process or text.strip_edges().begins_with("#"):
			continue
		if at_step < 0 and text.contains("_step_motion_probe("):
			at_step = i
		if at_publish < 0 and text.contains("_refresh_world("):
			at_publish = i
	if at_step < 0:
		return _fail("`_process` does not step the motion probe, so the door is wired to nothing")
	if at_publish < 0:
		return _fail("`_process` no longer calls `_refresh_world`; this test's ordering is about nothing")
	if at_step > at_publish:
		return _fail(("`_process` steps the probe at line %d, AFTER publishing the drawn rect at line "
				+ "%d. The probe would then read this frame's rectangle against this frame's delta, "
				+ "while the verdict divides by the PREVIOUS frame's delta (ASSA-197 #284), so every "
				+ "in-client number would be out by one frame of phase.") % [at_step + 1, at_publish + 1])
	return true


## A FAILED RUN STILL WRITES A FILE, and it still exits non-zero. The ask is "send me the text file";
## a run that joined nothing and saved nothing leaves a player with nothing to send and no reason.
func test_a_report_carries_the_machine_before_anything_can_fail() -> bool:
	var line := AssayMotionProbe.machine_line()
	for needed in [OS.get_name(), "Godot", "cores"]:
		if not line.contains(needed):
			return _fail("the machine line does not name `%s`: %s" % [needed, line])
	# **THE PROJECT MUST NOT BE ABLE TO PASS AS A ZIP.** This is the distinction the whole item is
	# about: a number from a checkout is not a number from the build we hand people.
	var exported := OS.has_feature("template")
	var says_exported := line.contains("EXPORTED")
	if exported != says_exported:
		return _fail("the machine line says %s on a build whose `template` feature is %s"
				% ["EXPORTED" if says_exported else "the project", exported])
	return true
