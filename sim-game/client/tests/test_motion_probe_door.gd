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


## A STAND-IN FOR `main.gd` HOLDING THE ONE FIELD THE CLICK SECTION READS OFF THE SCREEN.
## `_play_dragged` is `main.gd`'s (ASSA-212): frames the playout queue cap pulled the body forward in.
class FakeScreen:
	extends Node
	var _play_dragged := 0


## **THE CLICK SECTION IS ARITHMETIC AND THIS RUNS IT, which is why it is not another grep** (ASSA-212,
## carried into `scripts/` by the ASSA-211 merge). Marlow wrote FREEZE / JUMP / SPEED inside
## `tools/motion_speed_probe.gd`; `tools/*` is excluded from both export presets, so the one section
## written about what a player's HAND feels could never run on a player's build. Moving it was the
## merge resolution, and a move is exactly the kind of change a later merge drops silently.
##
## The fixture has a known answer, so a wrong pairing or a wrong trim fails rather than printing
## something plausible: 50 fps frames, a body that stands still for five of them after the click and
## then takes ONE frame worth three frames of travel before settling at exactly the true speed.
func test_the_click_section_computes_freeze_and_jump_from_a_known_series() -> bool:
	var probe := AssayMotionProbe.new()
	var screen := FakeScreen.new()
	probe._screen = screen
	probe._clicks.append(0.0)
	probe._click_what.append("synthetic: a fixture, not a run")
	var step := 0.02
	var per_frame := step * AssayMotionProbe.TRUE_SPEED * AssayScene.TILE_PX
	var x := 0.0
	for i in 60:
		probe._clock.append(0.01 + float(i) * step)
		probe._dt.append(step)
		# Frames 0-4 stand still; frame 5 moves three frames' worth; after that, true speed exactly.
		if i == 5:
			x += per_frame * 3.0
		elif i > 5:
			x += per_frame
		probe._drawn.append(Vector2(x, 0.0))
	probe._click_report()
	# **FREED THE FRAME IT STOPS BEING NEEDED, not at the end.** A `Node` built with `new()` and never
	# put in the tree is leaked unless something frees it, and every `_fail` below is an early return.
	screen.free()
	probe._screen = null
	var text := probe.report_text()
	# FREEZE: the click is at 0.0 and the rectangle first differs on the frame clocked at 0.11.
	if not text.contains("FREEZE   110 ms standing still (5 frames)"):
		return _fail(("the click section did not report a 110 ms / 5 frame freeze for a series built "
				+ "to have one. Report:\n%s") % [text])
	# JUMP: one frame of three frames' travel is 3.00x what a frame is worth, on either pairing, because
	# the fixture's deltas are constant. **A CONSTANT-DELTA FIXTURE CANNOT TELL THE TWO PAIRINGS APART**
	# and is not trying to: #284's phase is measured on real runs. What it does catch is a lost divisor.
	if not text.contains("3.00x what the frame is worth"):
		return _fail("the worst frame of the first 500 ms did not come out at 3.00x. Report:\n%s" % [text])
	# SPEED: every frame after the jump travels exactly one frame's worth, so none is outside +/-25%.
	if not text.contains("SPEED    0 of"):
		return _fail("frames moving at exactly the true speed were judged outside the band. Report:\n%s"
				% [text])
	if not text.contains("DRAGGED  0 frames"):
		return _fail("the dragged count is not read off the screen any more. Report:\n%s" % [text])
	return true


## **THE SECTION IS WHERE AN EXPORT CAN REACH IT, AND THE WAY IN IS NOT.** This one IS a source-text
## check and is worth exactly that: it cannot prove behaviour, only that the halves have not swapped
## sides again. The test above is the behavioural one.
func test_the_click_section_lives_in_the_packed_class_not_the_harness() -> bool:
	var packed := FileAccess.get_file_as_string(PROBE)
	var tool_text := FileAccess.get_file_as_string(TOOL)
	if not packed.contains("func _click_report()"):
		return _fail(("`_click_report` is not in %s. ASSA-212's FREEZE/JUMP/SPEED section must live "
				+ "inside the pack or no player's build can produce it.") % [PROBE])
	if not packed.contains("_click_report()\n"):
		return _fail("`_report` no longer calls `_click_report`, so the section is dead code")
	for owned in ["_still_since", "_moved_once", "_clicks.append"]:
		if not packed.contains(owned):
			return _fail("`%s` left %s: the second-walk arithmetic is back outside the pack" % [owned, PROBE])
	if tool_text.contains("_click_report") or tool_text.contains("_still_since"):
		return _fail(("%s has grown click arithmetic again. The harness owns the way in (argv[3] mode) "
				+ "and nothing else; `tools/*` is excluded from both export presets.") % [TOOL])
	# THE WAY IN IS STILL THERE AND STILL VALIDATED: a mistyped mode must refuse, not measure `steady`
	# and label it something else.
	if not tool_text.contains("mode must be `steady` or `start`"):
		return _fail("%s stopped refusing an unknown mode" % [TOOL])
	if not tool_text.contains("_probe.begin(screen, seconds, label, want_seed, mode)"):
		return _fail("%s parses a mode and does not pass it to the probe" % [TOOL])
	return true


## **A CLICK THE BODY ANSWERS IMMEDIATELY, because the fixture above cannot see an off-by-one at the
## START of the freeze search.** Mutating `range(first + 1, ...)` to `first + 2` passed the whole
## suite: with five still frames to find, starting the scan one frame later still lands on frame five.
## The case it breaks is the good one -- a body that moves on the very first frame after the click
## would be reported as frozen for two, and FREEZE is the number this whole section exists for.
func test_a_click_with_no_freeze_reports_one_frame_not_two() -> bool:
	var probe := AssayMotionProbe.new()
	var screen := FakeScreen.new()
	probe._screen = screen
	probe._clicks.append(0.0)
	probe._click_what.append("synthetic: answered on the next frame")
	var step := 0.02
	var per_frame := step * AssayMotionProbe.TRUE_SPEED * AssayScene.TILE_PX
	for i in 60:
		probe._clock.append(0.01 + float(i) * step)
		probe._dt.append(step)
		probe._drawn.append(Vector2(per_frame * float(i), 0.0))
	probe._click_report()
	screen.free()
	probe._screen = null
	var text := probe.report_text()
	if not text.contains("FREEZE   30 ms standing still (1 frames)"):
		return _fail(("a body that moved on the first frame after the click was not reported as one "
				+ "frame of freeze. Report:\n%s") % [text])
	return true


## **`start` MODE'S SECOND WALK, which had no test of any kind and silently passed a mutation that
## disabled it** (ASSA-212, carried here by the ASSA-211 merge). Setting `_moved_once := false` for ever
## leaves the firing condition permanently false: `start` mode would then measure ONE click while its
## own report printed that two were ordered, and 320 tests saw nothing. Driving the real two functions,
## not asserting on their source.
func test_a_second_walk_is_due_only_after_the_body_has_moved_and_then_stopped() -> bool:
	var probe := AssayMotionProbe.new()
	probe._mode = "start"
	probe._clicks.append(0.0)
	# WALKING: three frames of real movement. Nothing is due while the body is still going.
	for i in 3:
		probe._drawn.append(Vector2(10.0 * float(i + 1), 0.0))
		probe._note_stillness(0.1 * float(i + 1))
		if probe._second_click_due(0.1 * float(i + 1)):
			return _fail("a second walk came due while the drawn body was still moving")
	# STOPPED: the same rectangle from here on. Due only once it has stood longer than the threshold.
	var stopped_at := 1.0
	probe._drawn.append(Vector2(30.0, 0.0))
	probe._note_stillness(stopped_at)
	if probe._second_click_due(stopped_at):
		return _fail("a second walk came due in the very frame the body stopped")
	if probe._second_click_due(stopped_at + AssayMotionProbe.SECOND_CLICK_STILL - 0.01):
		return _fail("a second walk came due before %.2f s of standing still"
				% [AssayMotionProbe.SECOND_CLICK_STILL])
	if not probe._second_click_due(stopped_at + AssayMotionProbe.SECOND_CLICK_STILL + 0.01):
		return _fail("a second walk never came due after the body stood still past the threshold")
	# ONCE ONLY: a report built from three clicks would pair frames with the wrong one.
	probe._clicks.append(stopped_at + 0.5)
	if probe._second_click_due(stopped_at + 1.0):
		return _fail("a THIRD walk came due; `start` mode orders exactly two")
	# **THE CONTROL THAT THE MUTATION BROKE: a body that has never moved is not standing still, it is
	# waiting for its first walk.** Without `_moved_once` the second click lands on the cold walk.
	var never := AssayMotionProbe.new()
	never._mode = "start"
	never._clicks.append(0.0)
	# **THE CLOCK STARTS ABOVE ZERO AND THAT IS NOT COSMETIC.** With `_note_stillness(0.0)` on the first
	# frame, `_still_since` becomes exactly 0.0 and the condition's own `_still_since > 0.0` rejects it --
	# so this control passed a mutation that DELETED the `_moved_once` guard, for a reason that had
	# nothing to do with the guard. `_now()` is `get_ticks_usec()`, which is never 0.0 in a real run.
	for i in 10:
		never._drawn.append(Vector2.ZERO)
		never._note_stillness(0.1 * float(i + 1))
	if never._second_click_due(5.0):
		return _fail("a second walk came due for a body that had never moved at all")
	# AND THE OTHER CONTROL: the shipped door leaves the mode `steady`, which must never fire this.
	var steady := AssayMotionProbe.new()
	steady._clicks.append(0.0)
	for i in 4:
		steady._drawn.append(Vector2(10.0 * float(i if i < 2 else 1), 0.0))
		steady._note_stillness(0.1 * float(i + 1))
	if steady._second_click_due(5.0):
		return _fail("`steady` mode ordered a second walk; a player's file must hold one cold click")
	return true
