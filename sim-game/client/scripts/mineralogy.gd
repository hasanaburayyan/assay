## **THE MINERALOGY TAB: THE SIM'S ANSWERS ON TOP, THE TABLE AS EVIDENCE UNDER THEM**
## (ASSA-254, the client leg of ASSA-241; the board's own idea, via Rainy. Gaps closed in ASSA-262.)
##
## WHY ANSWERS AND NOT A GRID, in Maren's words: *"Rainy asked a QUESTION, not for a table; a tab
## opening on a six-row grid makes them do the collating again."* So the first thing in this body is
## the answer, and the species rows sit under it as the evidence for it.
##
## **THIS FILE COMPOSES AND DOES NOT COMPUTE. Every word in the headlines is the sim's**, handed
## over by `AssaySim.proximity_answers` (`debug::proximity_headline`, verbatim). Each one carries the
## question it answers, the species, the grade, the distance and the heading -- and both empty
## answers, which are different news: a world where no patch can ever answer, and one where a
## species would answer from a richer patch. That is why box 5 ("a world where nothing qualifies
## shows the sim's plain sentence, not an empty tab") needs no branch here: the sentence is never
## empty.
##
## **BOTH QUESTIONS, STACKED, NO SELECTOR** (Maren's ruling 3, 18:45 UTC on ASSA-241). The sim
## prints every `Question::ALL` entry and so does this body, in the sim's own order. With exactly two
## a selector would hide half the answer behind a click and spend two controls on furniture; it earns
## its place at three. **This body asked one question until ASSA-262** under a comment claiming the
## second was "a design call nobody has made" -- it had been made four hours earlier, and a stale
## ruling in a docstring is how a defect gets rebuilt by the next reader in good faith.
##
## **THE ONE NUMBER THIS FILE TOUCHES IS A TILE, AND IT ONLY PASSES IT ON.** `go here` emits the
## tile the sim named and `main.gd` submits `MoveTo { target: tile }` with it. A distance and a
## compass word cannot get you there -- a walk across a gap that is neither straight nor diagonal
## changes heading partway, so "15 tiles south-east" is true of the first step and false of the
## destination. That is also why the binding sends the tile and NOT the distance and heading as
## separate fields: they are already in the sentence, and two vocabularies for one fact are free to
## disagree.
##
## **AND THE FIELD IT READS IS `walk_to`, NOT "the tile the answer is about" (ASSA-262's gap 1).**
## The sim answers *"right where you are standing"* when the nearest patch is underfoot, and the
## search still names a tile there -- the player's own. This body gated its button on that tile
## being present and so offered a walk to the ground under your feet: the dead control that looks
## live, which ASSA-247 box 6 forbids. The binding now crosses *whether there is a walk*, so the
## gate here is one field and this body still parses no sentence.
##
## **IT IS A BODY, NOT A PANEL** (Wren's routing, Maren's box: the tab lands inside ASSA-198's
## tabbed strip, never as a panel of its own). It paints no surface, owns no position and spends no
## colour literal: the caller puts it in whatever the strip gives it. So it can be built and tested
## before Nacre's strip exists, which is the only reason this item was startable.
##
## THE EVIDENCE ROWS ARE THE `rocks` PANEL'S OWN. `main.gd::_species_row` builds them and they
## arrive here already built, because the species table and this tab must be one surface at two
## places -- the same reason `sim-godot` compares its rows against `debug::species_table` byte for
## byte rather than rendering a second version of them.
class_name AssayMineralogy
extends VBoxContainer

## WHAT A TAB WITH NO WORLD BEHIND IT SAYS. The sim has a sentence for every state of a world, and
## none for not being in one: `proximity_answers` returns an empty array for no world and for a
## player who is not in it, and the sim's own "no such player" line is about a missing player and
## would read as a mineralogy answer in this slot.
const NO_WORLD := "no world yet — join one and what is near you is answered here"

## The air between the last answer and its evidence. The headlines are sentences and the rows are a
## table; without a gap the first row reads as the sentence's next line.
const EVIDENCE_AIR := 8

## The air between two stacked answers, for the same reason one step down: each headline is a
## wrapping paragraph of ~120 characters, so at the body's 4px separation two answers would read as
## one block of prose with a button in the middle of it. **My call, not a ruling** -- Maren ruled
## that they stack, not what sits between them.
const ANSWER_AIR := 8

## WHERE EVERY CONTROL LIVES, and that is structural rather than tidy. Maren's ruling 5: the
## evidence list is ~651px against a 313px tab budget, so a control below it is below the fold and
## fails Wren's rule -- *every* control goes above the list. Holding the answers in their own box
## makes that a property of the tree ("no control is a descendant of anything after `evidence`")
## instead of an index comparison the next edit can quietly break.
var answers_box := VBoxContainer.new()

## WHERE THE SPECIES ROWS GO, filled by the caller with the `rocks` panel's own rows.
var evidence := VBoxContainer.new()

## ONE PER ANSWER ON SCREEN: `air`, `headline`, `go_here` and the `walk_to` that button carries.
## Rows are built once and reused, because the caller refreshes this body on tick bundles and
## rebuilding labels every tick would throw away focus and churn nodes for a sentence that rarely
## changes. `Question::ALL` has two entries today and this grows with it.
var _rows: Array = []

signal go_here_pressed(tile: Vector2i)


func _init() -> void:
	name = "Mineralogy"
	add_theme_constant_override("separation", 4)
	answers_box.add_theme_constant_override("separation", 4)
	answers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(answers_box)
	var air := Control.new()
	air.custom_minimum_size = Vector2(0.0, EVIDENCE_AIR)
	add_child(air)
	evidence.add_theme_constant_override("separation", 2)
	evidence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(evidence)


## SHOW EVERY ANSWER, AS THE SIM GAVE THEM.
##
## `answers` is `AssaySim.proximity_answers` straight through: one entry per `sim::proximity::
## Question`, in the sim's order, each with the `headline` it printed and the `walk_to` it named.
## An empty array is the no-world and no-such-player case and gets the one sentence this file owns.
##
## **THE EMPTY-ANSWER RENDERING IS NOT REACHED THROUGH THE FUEL QUESTION, and that is worldgen
## keeping a promise.** Measured through this binding over seeds 1..399, both questions: `Burns` is
## unanswered in **0** of 399 worlds, because the two chunks beside spawn always hold the starter
## material and a hand-lit fuel and the roster is rerolled until the starter ladder holds.
## `HardEnough` is unanswered in 64. So **a new player is never told "nothing here burns"** -- the
## starter ladder is an onboarding guarantee, and Maren's finding off that measurement is that this
## tab must not be built around an empty fuel headline it will never reach. The empty state is real
## and belongs to the other question.
func show_answers(answers: Array) -> void:
	if answers.is_empty():
		_render([{"headline": NO_WORLD}])
		return
	_render(answers)


## How many answers are on screen. The rows behind them are reused, so this is the count a reader
## sees and not `_rows.size()`.
func shown_count() -> int:
	var shown := 0
	for row in _rows:
		if (row as Dictionary)["headline"].visible:
			shown += 1
	return shown


## The `i`th answer's sentence, for a test that wants to compare it with the sim's.
func headline_at(index: int) -> Label:
	return (_rows[index] as Dictionary)["headline"]


## The `i`th answer's walk control. Present as a node whether or not it is on screen: the ruling is
## that it is ABSENT when there is nowhere to walk, which is `visible`, and a test asking "is there
## a live button here" must be able to ask the control itself.
func walk_control_at(index: int) -> Button:
	return (_rows[index] as Dictionary)["go_here"]


## The tile the `i`th answer's `go here` would walk to, for a test that wants the payload without
## pressing it. `null` when the sim offered no walk.
func walk_target_at(index: int) -> Variant:
	return (_rows[index] as Dictionary).get("walk_to")


func _render(answers: Array) -> void:
	while _rows.size() < answers.size():
		_rows.append(_build_row())
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var headline: Label = row["headline"]
		var go_here: Button = row["go_here"]
		var air: Control = row["air"]
		# A ROW WITH NO ANSWER BEHIND IT LEAVES THE SCREEN ENTIRELY, including its gap: a hidden
		# control is skipped by the container, so nothing is left holding air for an answer the sim
		# stopped giving (a world ending, or a question leaving `Question::ALL`).
		if index >= answers.size():
			headline.visible = false
			go_here.visible = false
			air.visible = false
			row["walk_to"] = null
			continue
		var answer: Dictionary = answers[index]
		headline.visible = true
		# VERBATIM. No formatting, no capitalisation, no appended full stop: the CLI prints this same
		# string and a player who read both must not have to work out whether two phrasings mean one
		# thing (the ASSA-135 rule, one surface at two widths).
		headline.text = String(answer.get("headline", ""))
		# ABSENT, NOT (0,0) AND NOT GREYED. `walk_to` is nil in the binding whenever there is no walk
		# to offer -- nothing answered, or the answer is the ground this player is standing on.
		var walk: Variant = answer.get("walk_to")
		row["walk_to"] = walk
		go_here.visible = walk != null
		# THE GAP BELONGS TO THE ANSWER BELOW IT, so the first answer sits flush against the top of
		# whatever the strip gives this body.
		air.visible = index > 0


## THE AIR ABOVE, THE SENTENCE, THEN THE VERB THAT ACTS ON IT (Maren's ruling 5: *"the verb belongs
## against the claim it acts on"*). Both of this row's controls are inside `answers_box`, which is
## what keeps them above the evidence list.
func _build_row() -> Dictionary:
	var air := Control.new()
	air.custom_minimum_size = Vector2(0.0, ANSWER_AIR)
	answers_box.add_child(air)
	var headline := Label.new()
	# `Heading` weight, because it is the thing in this body a player is meant to read first and the
	# type scale says so (ASSA-224).
	headline.theme_type_variation = &"Heading"
	# THE SENTENCES WRAP AND THE ROWS DO NOT. They are prose of a length the sim chooses -- a species
	# name is player-renameable up to 20 characters -- so a single line would clip the clause that
	# says where to go.
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answers_box.add_child(headline)
	var go_here := Button.new()
	go_here.text = "go here"
	# **QUIET** (Maren's ruling 5, `theme/assay.tres:383-393`), and her own argument for it: left
	# click on the whole-world view already walks you anywhere, so this is a convenience in a tab
	# whose job is to be READ. On the default Button it was the second-loudest control in the HUD
	# column after `Mine`, in a body that is a sentence and a table. Never ACCENT: `Mine` is the
	# screen's one primary.
	go_here.theme_type_variation = &"Quiet"
	# AND LEFT, which is what the column's other two quiet controls do (`_log_toggle`,
	# `_make_toggle`, ASSA-233): centred under its own sentence a dim label reads as that sentence's
	# caption rather than as a control.
	go_here.alignment = HORIZONTAL_ALIGNMENT_LEFT
	answers_box.add_child(go_here)
	var row := {"air": air, "headline": headline, "go_here": go_here, "walk_to": null}
	go_here.pressed.connect(func() -> void: _pressed(row))
	return row


func _pressed(row: Dictionary) -> void:
	# NO ARITHMETIC, AND NO GUESS AT A DESTINATION. If the sim offered no walk the button is not on
	# screen; this guard is for the frame between a world ending and a refresh.
	var walk: Variant = row.get("walk_to")
	if walk == null:
		return
	go_here_pressed.emit(walk as Vector2i)
