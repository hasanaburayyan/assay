extends RefCounted
## A BLIND FRAME MAY NOT BE NAMED AFTER WHAT IS IN IT -- AND THE SHARED TOOL NAMED EVERY ONE OF ITS
## OWN THAT WAY (ASSA-360).
##
## ASSA-294 split a blind shot's pictures (`frames/`) from everything that says what they hold
## (`key/`), and `window_shot.gd` refuses its own green line if the two mix. Its guard asked for
## `-key.` or `marks`. Cove's `cove_assa326_adjacent.gd` wrote `01-closeup-two-machines-east.png`
## into `frames/` and sailed through it; Nacre opened that file for ASSA-326 box 7 and declared the
## contamination before the first pixel: *"the words 'two machines' were in my head before the first
## pixel was."* The question was HOW MANY BUILT THINGS ARE IN THIS PICTURE.
##
## **AND THE HOLE WAS NOT CONFINED TO SOMEBODY ELSE'S PROBE.** `blind` chose the DIRECTORY and never
## the NAME, so the shared tool handed cold readers `10-stopped` (a machine has stopped),
## `14-machine-menu` (a menu is open) and `15-selection-2x2` (the mark, and its size). The guard
## printed green on all of them because it knew two words.
##
## So these tests ask the shape, not a word list -- and
## [method test_every_frame_the_shared_tool_shoots_can_be_made_blind] reads the shot list out of
## `window_shot.gd` itself rather than carrying a copy, so the day somebody adds a seventeenth moment
## with a name this cannot strip, the suite says so in two minutes instead of a six-minute shot run.

const TOOL_SOURCE := "res://tools/window_shot.gd"

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


func test_the_generator_makes_a_name_its_own_check_accepts() -> bool:
	# A generator trusted on its own say-so asserts nothing; this reads the string back through the
	# predicate the directory sweep uses.
	for shot in ["01-join.png", "08-whole-world.png", "16-selection-1x1.png"]:
		var blind: String = AssayBlindName.blind_frame_name(shot)
		if not AssayBlindName.is_blind_name(blind):
			return _fail("%s became %s and the check refused it" % [shot, blind])
	if AssayBlindName.blind_frame_name("01-join.png") != "01.png":
		return _fail("01-join.png should become 01.png, not %s"
				% AssayBlindName.blind_frame_name("01-join.png"))
	# THE ORDINAL IS THE FRAME'S OWN AND NOT A COUNTER, which is what lets two people compare the
	# same moment across builds and lets the tool reload `08` to diff it.
	if AssayBlindName.blind_frame_name("13-whole-world-hover.png") != "13.png":
		return _fail("the ordinal must be the frame's own, not a position in the set")
	return true


func test_the_name_that_told_a_cold_reader_the_answer_is_refused() -> bool:
	# The real one, verbatim, so this test names the defect it exists for.
	if AssayBlindName.is_blind_name("01-closeup-two-machines-east.png"):
		return _fail("the name Nacre read off the path is still accepted")
	if not AssayBlindName.offenders(
			PackedStringArray(["01-closeup-two-machines-east.png"])).has(
			"01-closeup-two-machines-east.png"):
		return _fail("the sweep did not report the name that cost ASSA-326 box 7's Q1")
	return true


func test_a_word_list_would_not_have_caught_these_and_the_shape_does() -> bool:
	# `01-east.png` contains no word any blacklist would have held, and it still leaks a side.
	# The rest are this tool's OWN frames, which is the half of the hole the item was filed about:
	# a `_names_marks` built from "key" and "marks" passed every one of them.
	for name in ["01-east.png", "10-stopped.png", "14-machine-menu.png", "15-selection-2x2.png",
			"12-whole-world-walking.png", "11-make.png"]:
		if AssayBlindName.is_blind_name(name):
			return _fail("a frame named after its subject was accepted: %s" % name)
	return true


func test_the_sweep_still_catches_everything_the_word_list_caught() -> bool:
	# A SUPERSET AND NOT A REPLACEMENT. Narrowing to a shape would be a regression if it let the map
	# key or a mark dump through -- those are what ASSA-294's guard was built for, and one of them is
	# a picture, which is the mistake that preceded the word list.
	var given := PackedStringArray(["09-whole-world-key.png", "08-whole-world-marks.json",
			"shot.log", "13-whole-world-hover.json", "00-art-provenance.txt", "01.png", "16.png"])
	var got := AssayBlindName.offenders(given)
	var want := PackedStringArray(["00-art-provenance.txt", "08-whole-world-marks.json",
			"09-whole-world-key.png", "13-whole-world-hover.json", "shot.log"])
	if got != want:
		return _fail("the sweep returned %s, wanted %s" % [got, want])
	return true


func test_the_shape_is_exactly_two_digits_and_png() -> bool:
	# Not "starts with a digit" and not "is a png": both of those pass something that talks.
	# `-1.png` and `+1.png` are here because `is_valid_int()` accepts them, so a predicate built on
	# it has a corner this one does not.
	for name in ["1.png", "001.png", "ab.png", "01.txt", "01", ".png", "01.png.txt", "-1.png",
			"+1.png", "0 .png"]:
		if AssayBlindName.is_blind_name(name):
			return _fail("%s is not two digits and an extension, but was accepted" % name)
	if not AssayBlindName.is_blind_name("07.png"):
		return _fail("07.png is the shape this rule is for and was refused")
	return true


func test_a_name_with_no_ordinal_is_refused_rather_than_passed_through() -> bool:
	# **THE FALLBACK IS THE BUG WEARING THE FIX'S CLOTHES.** If `blind_frame_name` returned the
	# descriptive name when it could not find an ordinal, the frame would land in `frames/` naming
	# its subject while a green line said a shape rule was in force. `window_shot.gd::_write_path`
	# fails the run on "".
	for name in ["frame.png", "closeup.png", "two-machines.png", "1-join.png", "join-01.png",
			"01join.png", "01-join.jpg"]:
		if AssayBlindName.blind_frame_name(name) != "":
			return _fail("%s has no two-digit ordinal and was given the blind name %s"
					% [name, AssayBlindName.blind_frame_name(name)])
	# A name that is ALREADY blind has no subject to strip and no `-`, so it too comes back "" --
	# and that is right: `_write_path` only asks about names the tool declares, all of which are
	# `NN-something`. A frame already called `01.png` reaching it would mean the list changed shape.
	if AssayBlindName.blind_frame_name("01.png") != "":
		return _fail("a two-character stem has no name to strip and must not be re-derived")
	return true


func test_every_frame_the_shared_tool_shoots_can_be_made_blind() -> bool:
	# **THE ONE THAT WOULD HAVE CAUGHT THE REAL BUG**, and the only one here that cannot go stale:
	# it reads the shot list out of `window_shot.gd` rather than carrying a copy of it. A unit test
	# holding sixteen names agrees with whoever wrote them; this one disagrees with the seventeenth.
	var file := FileAccess.open(TOOL_SOURCE, FileAccess.READ)
	if file == null:
		return _fail("cannot read %s, so the shot list could not be checked" % TOOL_SOURCE)
	var source := file.get_as_text()
	file.close()
	var finder := RegEx.new()
	# The call, not a docstring: `_shoot("` with the opening quote attached.
	if finder.compile('_shoot\\("([^"]+)"') != OK:
		return _fail("the shot-list pattern would not compile")
	var found := finder.search_all(source)
	# A PATTERN THAT MATCHES NOTHING IS A GREEN TEST ABOUT AN EMPTY SET. If a refactor renames
	# `_shoot`, this must red rather than quietly pass over no frames at all.
	if found.size() < 10:
		return _fail("found only %d _shoot calls in %s; the pattern has stopped matching"
				% [found.size(), TOOL_SOURCE])
	for match in found:
		var shot: String = match.get_string(1)
		var blind: String = AssayBlindName.blind_frame_name(shot)
		if blind == "" or not AssayBlindName.is_blind_name(blind):
			return _fail(("%s shoots %s, which cannot be made blind, so a blind run would either "
					+ "fail or hand a cold reader its name") % [TOOL_SOURCE, shot])
	return true
