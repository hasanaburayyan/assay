## **THE MINERALOGY TAB: ONE LINE ANSWERING THE QUESTION, THE TABLE AS EVIDENCE UNDER IT**
## (ASSA-254, the client leg of ASSA-241; the board's own idea, via Rainy).
##
## WHY A LINE AND NOT A GRID, in Maren's words: *"Rainy asked a QUESTION, not for a table; a tab
## opening on a six-row grid makes them do the collating again."* So the first thing in this body is
## the answer, and the species rows sit under it as the evidence for it.
##
## **THIS FILE COMPOSES AND DOES NOT COMPUTE. Every word in the headline is the sim's**, handed over
## by `AssaySim.proximity_answers` (`debug::proximity_headlines`, verbatim). It carries the question
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

## **BOTH QUESTIONS, STACKED, IN THE SIM'S OWN ORDER — AND THIS BODY USED TO ASK ONE** (ASSA-262,
## Maren's ruling 3 on ASSA-241).
##
## **THE COMMENT THAT STOOD HERE MISQUOTED HER TWICE AND IS WHY THE DEFECT LOOKED LIKE A DECISION.**
## It said *"Maren's ruling is that the headline is a selector rather than a fuel string"* — that was
## about `asked` living in the SIM's sentence, never about this UI — and it called the second question
## *"a design call nobody has made"* when she had made it at 18:45 UTC. A stale ruling in a docstring
## is how a defect gets rebuilt by the next reader in good faith, so it is corrected in the same
## change as the code rather than left for someone to trust.
##
## **THERE IS NO SELECTOR.** `AssaySim.proximity_answers` returns the sim's ANSWERS and every one of
## them is rendered, in the order the sim gave them. `Burns` is first because the sim puts it first —
## it is the question Rainy asked ("what is nearby that's viable as fuel"). Nothing here picks.
##
## **AND THERE IS NOT ONE ANSWER PER QUESTION** (ASSA-272). This said there was, which stopped being
## true the day the sim learned to merge: when one patch is the nearest answer to BOTH questions it
## is said once, under a label naming both, because 17 of 40 worlds at spawn and 28 of 40 in play
## were printing one fact as two near-identical paragraphs. **So the count is the sim's and this body
## may not assume it** — `_fit_blocks(answers.size())` is load-bearing, and a body that drew one
## block per question would draw an empty one on seven worlds in ten.
##
## **AND MAREN'S WORLDGEN FINDING, written where the next builder reads it rather than in an item
## nobody opens:** `Burns` is unanswered in **0 of 399 worlds**, because worldgen always puts the
## starter material and a hand-lit fuel in the two chunks beside spawn and rerolls the roster until
## the starter ladder holds. **So a new player is never told "nothing here burns", and this tab must
## not be built around an empty fuel headline it will never reach.** The empty state is real and
## belongs to the other question: `HardEnough` is unanswered in 64 of those 399. Do not go seed-
## hunting for an empty `Burns` — there is no 400th seed.
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

## **EVERY QUESTION'S BLOCK, THE FIRST ONE BEING `headline` AND `go_here` THEMSELVES** (ASSA-262).
##
## One entry per answer the sim sends: `{headline: Label, walk: Button, tile: Variant,
## underfoot: bool}`. Question 0 reuses the nodes above rather than getting a copy, because the strip
## and the suite both wire to `headline` / `go_here` / `target_tile()` and Wren's routing is that this
## body's public surface does not move while Nacre's `add_tab` is in flight.
##
## **BUILT ONCE PER COUNT, NOT PER REFRESH.** `show_answer` runs from Nacre's `_refresh_mineralogy`
## every tick, and rebuilding nodes there would destroy a button under the pointer — the defect this
## file's own neighbours name twice. So blocks are added only when the sim's question count changes,
## which in practice is once.
var _blocks: Array[Dictionary] = []

## Where blocks after the first live, so every control still sits ABOVE the evidence list (Maren's
## ruling 5). A container rather than loose children: `air` and `evidence` are already added, and
## inserting between siblings by index is the kind of arithmetic that goes wrong when someone adds a
## row later.
var _more := VBoxContainer.new()

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
	go_here.pressed.connect(_pressed.bind(0))
	add_child(go_here)
	# EVERY LATER QUESTION GOES HERE, above the air and the evidence.
	_more.add_theme_constant_override("separation", 4)
	_more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_more)
	_blocks.append({"headline": headline, "walk": go_here, "tile": null, "underfoot": false})
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
## **EVERY QUESTION THE SIM ANSWERED, STACKED, NO SELECTOR** (ASSA-262, Maren's ruling 3). This took a
## `which` argument and rendered one; the argument is gone, because a parameter that picks IS the
## selector she ruled against.
func show_answer(answers: Array) -> void:
	if answers.is_empty():
		# NO WORLD. One sentence in the first block and the rest stood down -- the sim's own "no such
		# player" line is about a missing player and would read as a mineralogy answer in this slot.
		headline.text = "no world yet — join one and what is near you is answered here"
		_tile = null
		_underfoot = false
		go_here.visible = false
		for i in range(1, _blocks.size()):
			(_blocks[i]["headline"] as Label).text = ""
			(_blocks[i]["walk"] as Button).visible = false
		return
	_fit_blocks(answers.size())
	for i in answers.size():
		var answer: Dictionary = answers[i]
		var block: Dictionary = _blocks[i]
		# VERBATIM. No formatting, no capitalisation, no appended full stop: the CLI prints this same
		# string and a player who read both must not have to work out whether two phrasings mean one
		# thing (the ASSA-135 rule, one surface at two widths).
		#
		# INDEXED, NOT `get(key, default)`: a sim fact that failed to cross should abort this function
		# loudly, not render a default nobody chose.
		(block["headline"] as Label).text = String(answer["headline"])
		# ABSENT, NOT (0,0). `tile` is nil in the binding whenever nothing answers.
		var target: Variant = answer["tile"]
		var underfoot := bool(answer["underfoot"])
		block["tile"] = target
		block["underfoot"] = underfoot
		# **TWO FACTS, TWO REASONS THERE IS NO WALK** (ASSA-263). `target == null` is "nothing
		# answers"; `underfoot` is "the answer is here, and the sentence above already says so". The
		# second one ships a live button that walks you to your own feet if it is left out — which it
		# was.
		(block["walk"] as Button).visible = target != null and not underfoot
		if i == BURNS:
			# THE FIRST QUESTION'S FACTS STAY ON THE OLD FIELDS, because `target_tile()` and
			# `answer_is_underfoot()` are the surface the strip and the suite already read.
			_tile = target
			_underfoot = underfoot
	# **THE SURPLUS BLOCKS ARE STOOD DOWN, AND IT WAS A LIVE DEFECT UNTIL THIS LOOP EXISTED**
	# (ASSA-272). `_fit_blocks` only ever GREW, which was enough while the count was always two and
	# stopped being enough the day the sim learned to merge: a player walks onto their own ore, the
	# two answers become one, and the block that is no longer answered keeps its sentence AND a live
	# walk button pointing at a tile the current answer never named. Measured rather than imagined --
	# the tab held `what near me is hard enough: nothing in this world does` under a merged answer
	# until this ran (`test_a_merge_stands_down_the_block_it_no_longer_needs`, red before, green now).
	#
	# The empty-answers path at the top of this body has always done this; only the answered path did
	# not, because its count could not shrink.
	for i in range(answers.size(), _blocks.size()):
		(_blocks[i]["headline"] as Label).text = ""
		(_blocks[i]["walk"] as Button).visible = false
		# AND THE PAYLOAD GOES WITH THE BUTTON. A hidden button whose tile is still set is one
		# `visible = true` away from walking a player to a rock nobody asked about.
		_blocks[i]["tile"] = null
		_blocks[i]["underfoot"] = false


## ONE BLOCK PER ANSWER, ADDED ONLY WHEN THE COUNT GROWS.
##
## **THE COUNT IS THE SIM'S AND IT MOVES WITH THE PLAYER** (ASSA-272). This said the count was
## `Question::ALL` and "runs once in practice", which was true until one patch answering both
## questions became one answer: walking onto your own ore drops it from two to one and walking away
## puts it back. Growing is still all this function does -- a button is never rebuilt under the
## player's pointer, which is why it is a function rather than a loop in `show_answer` -- and
## `show_answer` stands the surplus down rather than destroying it, for the same reason.
##
## A LATER QUESTION'S CONTROLS LOOK EXACTLY LIKE THE FIRST'S: same `Heading` headline, same `Quiet`
## verb sized to its words. Nothing distinguishes question 2 but the sim's own sentence, which already
## names which question it answers ("what near me is hard enough: ...").
func _fit_blocks(want: int) -> void:
	while _blocks.size() < want:
		var head := Label.new()
		head.theme_type_variation = &"Heading"
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_more.add_child(head)
		var walk := Button.new()
		walk.text = go_here.text
		walk.theme_type_variation = &"Quiet"
		walk.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		walk.pressed.connect(_pressed.bind(_blocks.size()))
		_more.add_child(walk)
		_blocks.append({"headline": head, "walk": walk, "tile": null, "underfoot": false})


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


## HOW MANY ANSWER BLOCKS THIS BODY IS CURRENTLY SHOWING, for a test that asserts every answer is
## rendered rather than trusting that the loop ran.
##
## **IT COUNTS ANSWERS AND WAS CALLED `question_count` UNTIL ASSA-272**, when the two stopped being
## the same number: one patch answering both questions is one block. A name that says "question"
## about a count of answers is the kind of prose that gets a defect rebuilt by the next reader.
func answer_count() -> int:
	return _blocks.size()


## ONE QUESTION'S RENDERED SENTENCE, its walk visibility, its tile and its underfoot bit. Read off the
## real controls so a test cannot pass against a field the screen does not use.
func headline_text(which: int) -> String:
	return "" if which >= _blocks.size() else (_blocks[which]["headline"] as Label).text


func walk_shown(which: int) -> bool:
	return false if which >= _blocks.size() else (_blocks[which]["walk"] as Button).visible


func tile_for(which: int) -> Variant:
	return null if which >= _blocks.size() else _blocks[which]["tile"]


func underfoot_for(which: int) -> bool:
	return false if which >= _blocks.size() else bool(_blocks[which]["underfoot"])


## **THE BUTTON THAT WAS PRESSED CARRIES ITS OWN QUESTION'S TILE** (ASSA-262). Bound at build time, so
## a second question's verb cannot walk you to the first question's rock -- which is the bug a single
## shared `_tile` would have shipped the moment the body stopped asking one question.
func _pressed(which: int) -> void:
	# NO ARITHMETIC, AND NO GUESS AT A DESTINATION. If there is no walk in the answer the button is
	# not on screen; this guard is for the frame between a world ending and a refresh. It repeats the
	# visibility rule rather than trusting it, because a `MoveTo` to the tile you are standing on is
	# a command on the wire that does nothing.
	if which >= _blocks.size():
		return
	var target: Variant = _blocks[which]["tile"]
	if target == null or bool(_blocks[which]["underfoot"]):
		return
	go_here_pressed.emit(target as Vector2i)
