extends RefCounted
## A COLD READER'S FRAME MAY NOT BE NAMED AFTER WHAT IS IN IT.
##
## ASSA-294 split a blind shot's pictures (`frames/`) from everything that says what they hold
## (`key/`). `tools/cove_assa326_adjacent.gd` obeyed that split and then defeated it from inside the
## frames directory, by calling its one picture `01-closeup-two-machines-east.png`.
##
## Nacre opened that file for ASSA-326 box 7 and declared the contamination before the first pixel:
## *"I read the path to open the file. The words 'two machines' were in my head before the first
## pixel was. Discount my Q1 number accordingly -- it is the one answer you cannot trust from me."*
## The question was HOW MANY BUILT THINGS ARE IN THIS PICTURE. The filename answered it.
##
## **WHY THE RULE IS A SHAPE AND NOT A WORD LIST.** `window_shot.gd::_names_marks` already refuses
## `-key.` and `marks`, and it would have passed this name without comment -- a blacklist is a guess
## about what the next frame will be about, and nobody was going to guess "machines" in advance.
## **A name that is two digits and an extension can carry nothing, whatever the picture holds.**
## The key says which number is which; it prints the seed, the side, the tick and both buildings.
##
## These run against the tool's own statics rather than a copy of the rule, so the day somebody
## makes the name descriptive again this reddens instead of agreeing with them.

const TOOL := preload("res://tools/cove_assa326_adjacent.gd")

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


func test_the_generator_makes_a_name_its_own_check_accepts() -> bool:
	# A generator trusted on its own say-so asserts nothing; this reads the string back.
	for index in [1, 2, 9, 10, 42]:
		var name: String = TOOL.blind_frame_name(index)
		if not TOOL._is_blind_name(name):
			return _fail("blind_frame_name(%d) made %s and the check refused it" % [index, name])
	if TOOL.blind_frame_name(1) != "01.png":
		return _fail("the first frame should be 01.png, not %s" % TOOL.blind_frame_name(1))
	return true


func test_the_name_that_told_a_cold_reader_the_answer_is_refused() -> bool:
	# The real one, verbatim, so this test names the defect it exists for.
	if TOOL._is_blind_name("01-closeup-two-machines-east.png"):
		return _fail("the name Nacre read off the path is still accepted")
	return true


func test_a_word_list_would_not_have_caught_these_and_the_shape_does() -> bool:
	# `01-east.png` holds no word any blacklist would have contained, and it still leaks a side.
	# `01-key.png` is the one `_names_marks` DOES catch, kept here so the two rules are comparable.
	for name in ["01-two-machines.png", "01-east.png", "01-key.png", "frame.png"]:
		if TOOL._is_blind_name(name):
			return _fail("a descriptive frame name was accepted: %s" % name)
	return true


func test_the_shape_is_exactly_two_digits_and_png() -> bool:
	# Not "starts with a digit" and not "is a png": both of those pass something that talks.
	for name in ["1.png", "001.png", "ab.png", "01.txt", "01", ".png", "01.png.txt"]:
		if TOOL._is_blind_name(name):
			return _fail("%s is not two digits and an extension, but was accepted" % name)
	if not TOOL._is_blind_name("07.png"):
		return _fail("07.png is the shape this rule is for and was refused")
	return true
