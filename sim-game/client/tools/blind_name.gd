class_name AssayBlindName
## CI: library
extends RefCounted
## WHAT A BLIND FRAME MAY BE CALLED -- AS A SHAPE, NEVER AS A LIST OF WORDS (ASSA-360).
##
## ASSA-294 split a blind shot's pictures (`frames/`) from everything that says what they hold
## (`key/`), and `window_shot.gd` refuses its own green line if the two ever mix. Cove then obeyed
## that split and defeated it from inside the frames directory, by calling one picture
## `01-closeup-two-machines-east.png`. Nacre opened it for ASSA-326 box 7 and declared the
## contamination before the first pixel: *"I read the path to open the file. The words 'two
## machines' were in my head before the first pixel was. Discount my Q1 number accordingly -- it is
## the one answer you cannot trust from me."* The question was HOW MANY BUILT THINGS ARE IN THIS
## PICTURE, and the filename answered it.
##
## **AND THE HOLE WAS WIDER THAN THE FILE IT WAS FOUND IN.** `window_shot.gd`'s guard asked for
## `-key.` or `marks`, so it passed that name without comment -- and it passed every name the tool
## writes ITSELF: `10-stopped` says a machine has stopped, `14-machine-menu` says a menu is open,
## `15-selection-2x2` gives away the mark AND its size. `blind` chose the DIRECTORY and never the
## NAME. A blacklist is a guess about what the next frame will be about, and nobody was going to
## guess "machines" in advance; adding words to it is the same mistake a third time, after the
## version that tested the file EXTENSION and let `09-whole-world-key.png` through.
##
## **SO THE RULE IS: TWO DIGITS AND AN EXTENSION, which can carry nothing whatever the picture holds.**
## Nothing is withheld -- `key/names.txt` maps every number back to the moment it photographs, one
## level up, which is the half of ASSA-294 that keeps the builder's own evidence intact.
##
## **WHY THIS IS A LIBRARY AND NOT A FOURTH COPY.** The shape already existed twice -- in
## `cove_assa326_adjacent.gd`, which invented it, and nowhere else it was needed. `blind_frames.py`
## holds the OLD word-list rule under a docstring promising it is *"the same rule `window_shot.gd`
## applies, held in one sentence rather than two places"*, which this change makes false: a rule
## copied into prose goes stale without a single test going red. Stated once here, the day somebody
## makes a frame name descriptive again, something fails.
##
## The ORDINAL IS THE FRAME'S OWN, not a counter. `blind_frame_name` reads the `NN-` every shot in
## this tool already carries, so `08` is `08` in every run and on every machine -- which is what lets
## two people compare the same moment across builds, and what lets the tool reload its own control
## frame by number. A sequential counter would renumber the set whenever a moment was added, skipped
## or routed to `key/`, and every past citation with it.

#: The only characters an ordinal may be made of. `is_valid_int()` is NOT this test: it accepts
#: `-1` and `+1`, so `-1.png` would have passed a predicate built on it. It names nothing, so it
#: was never a leak -- but a shape rule that accepts a string it cannot have produced is a shape
#: rule with a corner nobody has thought about, and this one is load-bearing for a cold read.
const DIGITS := "0123456789"

#: How many digits an ordinal is. Two, because sixteen moments fit and a three-digit set would
#: still be two digits of information plus one of padding.
const WIDTH := 2


## Every character of `text` is a digit, and there is at least one. Deliberately not a regex and
## deliberately not `is_valid_int`: see [constant DIGITS].
static func all_digits(text: String) -> bool:
	if text.is_empty():
		return false
	for index in text.length():
		if not DIGITS.contains(text[index]):
			return false
	return true


## The blind name for a frame this tool shoots, or `""` if the frame has no two-digit ordinal.
##
## **IT RETURNS `""` RATHER THAN FALLING BACK TO THE DESCRIPTIVE NAME, and the caller fails the run
## on it.** A rename that quietly declines to rename is the whole bug wearing the fix's clothes: the
## frame still lands in `frames/`, still names its subject, and now a green line says a shape rule
## is in force. Every shot in `window_shot.gd` is `NN-something.png`, so `""` means somebody added
## one that is not -- which is a sentence to read, not a case to absorb.
static func blind_frame_name(shot_name: String) -> String:
	if not shot_name.to_lower().ends_with(".png"):
		return ""
	var stem := shot_name.substr(0, shot_name.length() - 4)
	# `NN-` and not merely `NN`: a two-character stem is already a blind name and has no subject to
	# strip, and taking the first two characters of anything else would turn `099-x.png` into
	# `09.png` -- a DIFFERENT frame's number, silently.
	if stem.length() <= WIDTH or stem[WIDTH] != "-":
		return ""
	var ordinal := stem.substr(0, WIDTH)
	if not all_digits(ordinal):
		return ""
	return "%s.png" % ordinal


## The same rule read back off a finished string, so the generator is not trusted on its own say-so.
##
## A generator and its own check in one expression assert nothing. This is what the directory sweep
## asks, and what a test can point at the name that cost a real answer.
static func is_blind_name(name: String) -> bool:
	if not name.ends_with(".png"):
		return false
	var stem := name.substr(0, name.length() - 4)
	if stem.length() != WIDTH:
		return false
	return all_digits(stem)


## The moment already written under `shot_name`'s blind name, if it is a DIFFERENT moment; else "".
##
## **TWO MOMENTS MAY NOT SHARE AN ORDINAL -- AND A MOMENT RE-TAKEN IS NOT TWO MOMENTS.** The first
## version of this asked only `taken.has(blind)`, and the real blind run refused itself at the second
## frame: `04-pack.png` is shot repeatedly on purpose (`window_shot.gd` passes `guard_repeat := false`
## for it alone, because it is a high-water mark the tool NOTICES as the pack grows, and the last
## write is the answer). A guard that cannot tell a re-take from a clash stops the run it was added
## to protect. **535 green tests could not see that; the six-minute run saw it on frame two.**
##
## What it still catches is the thing worth catching: `08-whole-world.png` and `08-other.png` both
## becoming `08.png`, where the second silently replaces the first and the set comes back a picture
## short of what its own report lists.
static func collides_with(taken: Dictionary, shot_name: String) -> String:
	var blind := blind_frame_name(shot_name)
	if blind == "":
		return ""
	if taken.has(blind) and String(taken[blind]) != shot_name:
		return String(taken[blind])
	return ""


## Everything in `names` that may not sit in a blind `frames/` directory, sorted.
##
## **ONE QUESTION, ASKED OF A LIST, so a test can ask it without a disk.** The old sweep took the
## directory and the mode off the running tool, which made the only way to check it a full six-minute
## shot run -- and the only reading of it a green line, which cannot see a directory.
##
## This refuses a SUPERSET of what the word list refused, which is the point: a shot log
## (`not .png`), the map key (`09-whole-world-key.png`), a mark dump (`08-...-marks.json`) and
## `01-closeup-two-machines-east.png` all come back, and only `NN.png` does not.
static func offenders(names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in names:
		var name := String(raw)
		if not is_blind_name(name):
			out.append(name)
	out.sort()
	return out
