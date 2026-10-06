## **THE MINERALOGY TAB: ONE LINE ANSWERING THE QUESTION, THE TABLE AS EVIDENCE UNDER IT**
## (ASSA-254, the client leg of ASSA-241; the board's own idea, via Rainy).
##
## WHY A LINE AND NOT A GRID, in Maren's words: *"Rainy asked a QUESTION, not for a table; a tab
## opening on a six-row grid makes them do the collating again."* So the first thing in this body is
## the answer, and the species rows sit under it as the evidence for it.
##
## **THIS FILE COMPOSES AND DOES NOT COMPUTE. Every word in the headline is the sim's**, handed over
## by `AssaySim.proximity_answers` (`debug::proximity_headline`, verbatim). It carries the question
## it answers, the species, the grade, the distance and the heading -- and both empty answers, which
## are different news: a world where no patch can ever answer, and one where a species would answer
## from a richer patch. That is why box 5 ("a world where nothing burns shows the sim's plain
## sentence, not an empty tab") needs no branch here: the sentence is never empty.
##
## **THE ONE NUMBER THIS FILE TOUCHES IS A TILE, AND IT ONLY PASSES IT ON.** `go here` emits the
## tile the sim named and `main.gd` submits `MoveTo { target: tile }` with it. A distance and a
## compass word cannot get you there -- a walk across a gap that is neither straight nor diagonal
## changes heading partway, so "15 tiles south-east" is true of the first step and false of the
## destination. That is also why the binding sends the tile and NOT the distance and heading as
## separate fields: they are already in the sentence, and two vocabularies for one fact are free to
## disagree.
##
## **THE ONE OTHER FACT IT SENDS IS A BOOL, AND IT IS HERE BECAUSE THIS FILE SHIPPED A DEAD CONTROL
## WITHOUT IT** (ASSA-263). `tile` is set even when the answer is the tile you are standing on, so
## `go here` was live under a sentence reading "right where you are standing". `underfoot` is the
## binding's word for that case. It is a bool and not a heading for the same reason as above: a bool
## cannot be rendered as prose beside the sim's, it can only gate a control.
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

## The question this body asks. `AssaySim.proximity_answers` returns one answer per
## `sim::proximity::Question` in the sim's own order, and `Burns` is first -- it is the question
## Rainy asked ("what is nearby that's viable as fuel"). `HardEnough` exists in the sim so that the
## second question costs nothing; asking it is a design call nobody has made, so this body asks one.
const BURNS := 0

## The air between the answer and its evidence. The headline is a sentence and the rows are a table;
## without a gap the first row reads as the sentence's second line.
const EVIDENCE_AIR := 8

## WHAT THE SIM SAID, WORD FOR WORD. `Heading` weight, because it is the one thing in this body a
## player is meant to read first and the type scale says so (ASSA-224).
var headline := Label.new()

## WHERE THE SPECIES ROWS GO, filled by the caller with the `rocks` panel's own rows.
var evidence := VBoxContainer.new()

## WALK TO THE ROCK THE SENTENCE IS ABOUT. Hidden when there is no walk in the answer, because a
## button that can only refuse is worse than no button (Maren, ASSA-215). Two states hide it and they
## are different news: nothing answers at all, and **the answer is under your feet** -- on which the
## sim's own sentence reads "right where you are standing" and a live button would walk you nowhere
## (ASSA-263; Maren's ruling 5 on ASSA-241: absent, not greyed).
##
## **Quiet and sized to its words**, from Maren's amended ruling 5 — and the amendment came from her
## 344 px shot rather than from taste: with no size flags in a `VBoxContainer` this filled the whole
## HUD column, making a convenience verb the heaviest element on screen and out-weighing `Mine`, the
## screen's one primary, by area.
var go_here := Button.new()

## The tile the sim named, or `null` when nothing answers. Never a (0,0) sentinel -- that is a real
## corner of every world, so it would be a destination the sim never offered.
##
## **IT IS KEPT EVEN WHEN THERE IS NOWHERE TO WALK.** `tile` means "the tile this answer is about",
## not "somewhere to go" — conflating the two is what made the button dead (ASSA-263), and something
## later will want it to highlight the rock on the map.
var _tile: Variant = null

## Whether the sim's answer is the tile the player is already standing on. The binding's own
## `underfoot`, never derived here: this file may not parse the sentence, and `_tile != null` cannot
## tell "a rock to walk to" from "you are on it".
var _underfoot := false

signal go_here_pressed(tile: Vector2i)


func _init() -> void:
	name = "Mineralogy"
	add_theme_constant_override("separation", 4)
	headline.theme_type_variation = &"Heading"
	# THE SENTENCE WRAPS AND THE ROWS DO NOT. It is prose of a length the sim chooses -- a species
	# name is player-renameable up to 20 characters -- so a single line would clip the clause that
	# says where to go.
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(headline)
	go_here.text = "go here"
	go_here.theme_type_variation = &"Quiet"
	# SIZED TO ITS WORDS, LEFT UNDER THE SENTENCE IT ACTS ON. A verb stretched to the panel reads as
	# the panel's purpose.
	go_here.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	go_here.pressed.connect(_pressed)
	add_child(go_here)
	var air := Control.new()
	air.custom_minimum_size = Vector2(0.0, EVIDENCE_AIR)
	add_child(air)
	evidence.add_theme_constant_override("separation", 2)
	evidence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(evidence)


## SHOW ONE ANSWER, AS THE SIM GAVE IT.
##
## `answers` is `AssaySim.proximity_answers` straight through. An empty array is the no-world and
## no-such-player case, and it gets the one sentence this file owns -- the sim's own "no such player"
## line is about a missing player and would read as a mineralogy answer in this slot.
## `which` IS THE QUESTION SELECTOR, NOT A TEST HOOK. `Question::ALL` exists in the sim so that the
## second question costs nothing, and Maren's ruling is that the headline is a selector rather than a
## fuel string. The tab asks `BURNS` today because that is the question Rainy asked. It is also the
## only way to render the EMPTY answer against real sim data: measured over 399 worlds, `Burns` is
## never unanswered -- worldgen guarantees a hand-lit fuel beside spawn -- while `HardEnough` is
## unanswered in 64 of them. See the note on ASSA-254.
func show_answer(answers: Array, which: int = BURNS) -> void:
	if answers.size() <= which:
		headline.text = "no world yet — join one and what is near you is answered here"
		_tile = null
		_underfoot = false
		go_here.visible = false
		return
	var answer: Dictionary = answers[which]
	# VERBATIM. No formatting, no capitalisation, no appended full stop: the CLI prints this same
	# string and a player who read both must not have to work out whether two phrasings mean one
	# thing (the ASSA-135 rule, one surface at two widths).
	#
	# INDEXED, NOT `get(key, default)`: a sim fact that failed to cross should abort this function
	# loudly, not render a default nobody chose.
	headline.text = String(answer["headline"])
	# ABSENT, NOT (0,0). `tile` is nil in the binding whenever nothing answers.
	var target: Variant = answer["tile"]
	_tile = target
	_underfoot = bool(answer["underfoot"])
	# **TWO FACTS, TWO REASONS THERE IS NO WALK** (ASSA-263). `target == null` is "nothing answers";
	# `_underfoot` is "the answer is here, and the sentence above already says so". The second one
	# ships a live button that walks you to your own feet if it is left out — which it was.
	go_here.visible = target != null and not _underfoot


## The tile the answer is about, for a test that wants to assert the button's payload without
## pressing it and for whatever highlights the rock on the map later. `null` when nothing answers --
## but NOT null when the answer is underfoot: the answer is not withheld, only the walk.
func target_tile() -> Variant:
	return _tile


## Whether the sim said the answer is the tile the player is already on, so there is no walk to
## offer. Exposed for the test that asserts the button is absent for the right reason rather than
## absent by luck.
func answer_is_underfoot() -> bool:
	return _underfoot


func _pressed() -> void:
	# NO ARITHMETIC, AND NO GUESS AT A DESTINATION. If there is no walk in the answer the button is
	# not on screen; this guard is for the frame between a world ending and a refresh. It repeats the
	# visibility rule rather than trusting it, because a `MoveTo` to the tile you are standing on is
	# a command on the wire that does nothing.
	if _tile == null or _underfoot:
		return
	go_here_pressed.emit(_tile as Vector2i)
