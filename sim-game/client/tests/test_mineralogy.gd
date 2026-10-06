extends RefCounted
## **THE MINERALOGY TAB SAYS WHAT THE SIM SAID AND NOTHING ELSE** (ASSA-254, the client leg of
## ASSA-241; its three gaps against Maren's rulings are ASSA-262).
##
## **DRIVEN BY A REAL SIM, NOT BY A DICTIONARY I TYPED.** A test that hands `show_answers` a literal
## `{"headline": "..."}` proves the Label is wired and nothing about the feature: the whole claim of
## this item is that the lines on screen are `debug::proximity_headline` with no client in between,
## so the fixture has to be the binding's real output on a real world. `AssaySimHost
## .fresh_welcome_json` is how every other suite here stands a world up.
##
## WHAT IS NOT TESTED HERE AND WHERE IT LIVES: that a headline is byte-identical to the sim's
## sentence, and that `walk_to` is absent for both of its reasons, are asserted in
## `sim-godot/src/lib.rs` (`the_tabs_headline_and_walk_are_the_sims_own_answer`), because that is
## the one crate where the sim's string and what the binding sends can both be reached. This file
## owns the half that is the client's: that the body renders every sentence verbatim, stacks them,
## puts the evidence under them, keeps every control above that evidence, and never invents a
## destination.

var runner = null


func set_runner(r) -> void:
	runner = r


## GUARDED, AND THE GUARD IS NOT DEFENSIVE PADDING. I wrote this without `set_runner` first, so
## `runner` was Nil, `_fail` aborted on a nonexistent method, and four of five tests passed only
## because they never failed. The one that did fail reported "returned false and said nothing".
func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A WORLD AND ITS LOCAL PLAYER, through the host the client really uses.
##
## `AssaySimHost`, not `AssaySim`: the binding class is abstract from GDScript's side and every
## surface in this client reaches the sim through the host wrapper. A fixture that went around it
## would be testing a path the game does not take.
func _world(seed_text: String) -> Array:
	var host := AssaySimHost.new()
	if not host.start(AssaySimHost.fresh_welcome_json(seed_text, "limpet")):
		return []
	return [host, host.players()]


## Every answer the sim gives the local player of `seed_text`, or an empty array if the world or the
## player could not be stood up.
func _answers(seed_text: String) -> Array:
	var made := _world(seed_text)
	if made.is_empty():
		return []
	var sim: AssaySimHost = made[0]
	var players: Array = made[1]
	if players.is_empty():
		return []
	return sim.proximity_answers(int((players[0] as Dictionary).get("id", -1)))


## **EVERY LINE IS THE SIM'S SENTENCE, CHARACTER FOR CHARACTER, AND BOTH QUESTIONS ARE ON SCREEN.**
##
## Not "contains", not "starts with": the body may not append a full stop, capitalise a species name
## or wrap a clause in prose of its own. The CLI prints these same strings, and a player who read
## both must not have to work out whether two phrasings mean one thing (the ASSA-135 rule).
##
## **THE STACKING IS THE OTHER HALF, AND IT IS ASSA-262's GAP 3** (Maren's ruling 3): the sim prints
## every `Question::ALL` entry and so does this body. It rendered exactly one until ASSA-262, so a
## test that only read line one was green over half the answer being missing.
func test_every_question_is_stacked_and_said_verbatim() -> bool:
	var answers := _answers("14247")
	if answers.size() < 2:
		return _fail(("seed 14247 answered %d questions; `Question::ALL` has had two since "
				+ "ASSA-248, so the stacking this test exists for cannot be reached")
				% answers.size())
	var tab := AssayMineralogy.new()
	tab.show_answers(answers)
	if tab.shown_count() != answers.size():
		tab.free()
		return _fail("the sim answered %d questions and the tab shows %d"
				% [answers.size(), tab.shown_count()])
	for index in answers.size():
		var expected := String((answers[index] as Dictionary).get("headline", ""))
		if expected == "":
			tab.free()
			return _fail("the binding sent an empty headline, which the sim never produces")
		if tab.headline_at(index).text != expected:
			tab.free()
			return _fail("answer %d reads `%s` and the sim said `%s`"
					% [index, tab.headline_at(index).text, expected])
	# AND THE ANSWERS ARE THE FIRST THING IN THE BODY, which is the ruling: a tab that opens on a
	# grid makes the player do the collating again. Asked of child order, not of a comment.
	if tab.get_child(0) != tab.answers_box:
		tab.free()
		return _fail("the answers are not the first thing in the body: child 0 is `%s`"
				% tab.get_child(0).name)
	if tab.headline_at(0).get_parent() != tab.answers_box:
		tab.free()
		return _fail("the first headline is not inside the answers box")
	tab.free()
	return true


## **NO SELECTOR** (Maren's ruling 3: *"with exactly two, a selector hides half the answer behind a
## click and spends two controls on furniture"*).
##
## Asked as a count of the body's own controls: one walk control per answer and nothing else. A
## dropdown, a tab bar or a pair of question buttons would all fail here, and all three are the
## shape this body had an argument for before the ruling landed.
func test_the_body_spends_no_control_on_choosing_a_question() -> bool:
	var answers := _answers("14247")
	if answers.size() < 2:
		return _fail("seed 14247 answered %d questions" % answers.size())
	var tab := AssayMineralogy.new()
	tab.show_answers(answers)
	var controls := _controls_under(tab)
	if controls.size() != answers.size():
		var names := []
		for control in controls:
			names.append("%s(%s)" % [control.get_class(), control.name])
		tab.free()
		return _fail(("the body holds %d controls for %d answers, so something is furniture: %s")
				% [controls.size(), answers.size(), ", ".join(names)])
	for control in controls:
		if not (control is Button):
			tab.free()
			return _fail("a control in this body is a `%s`" % control.get_class())
	tab.free()
	return true


## **EVERY CONTROL SITS ABOVE THE EVIDENCE LIST** (Maren's ruling 5, and the reason is a measurement
## of Nacre's: the list is ~651px against a 313px worst-case tab budget, so a control under it is
## below the fold and fails Wren's rule outright).
##
## Asked of the tree rather than of pixels, because this body owns no position and a layout pass
## would report zeros here: no control is a descendant of the evidence box, and the box that holds
## them all comes before it among the body's children.
func test_every_control_is_above_the_evidence_list() -> bool:
	var answers := _answers("14247")
	if answers.is_empty():
		return _fail("the binding answered nothing for a player who is in the world")
	var tab := AssayMineralogy.new()
	tab.show_answers(answers)
	# The evidence box gets rows, as the real caller gives it: a control hiding among them is the
	# failure this test is for.
	for i in 3:
		var row := Label.new()
		row.text = "a species row"
		tab.evidence.add_child(row)
	var below := _controls_under(tab.evidence)
	if not below.is_empty():
		tab.free()
		return _fail("%d control(s) sit inside the evidence list, which is below the fold"
				% below.size())
	var children := tab.get_children()
	if children.find(tab.answers_box) > children.find(tab.evidence):
		tab.free()
		return _fail("the answers and their controls sit below the evidence list")
	for control in _controls_under(tab):
		if control.get_parent() != tab.answers_box:
			tab.free()
			return _fail("control `%s` is not inside the answers box, so nothing keeps it above "
					% control.name + "the list")
	tab.free()
	return true


## **THE EVIDENCE GOES UNDER THE ANSWERS, AND AN ANSWER IS NOT IN THE EVIDENCE BOX.**
##
## The failure this catches is a body that grows a second copy of the species rows, or one that puts
## a headline inside the scrolling list where it would scroll away from the question it answers.
func test_the_species_rows_sit_under_the_headlines_and_not_in_place_of_them() -> bool:
	var tab := AssayMineralogy.new()
	var rows := 0
	for i in 3:
		var row := Label.new()
		row.text = "a species row"
		tab.evidence.add_child(row)
		rows += 1
	if tab.evidence.get_child_count() != rows:
		tab.free()
		return _fail("the evidence box did not take the rows it was given")
	# The headlines are NOT among them, and the evidence box is below them in the body.
	if tab.evidence.get_parent() != tab:
		tab.free()
		return _fail("the evidence box is not a child of the body")
	if tab.get_children().find(tab.evidence) < tab.get_children().find(tab.answers_box):
		tab.free()
		return _fail("the evidence sits ABOVE the answers it is evidence for")
	tab.free()
	return true


## **AN UNANSWERED QUESTION STILL SAYS SOMETHING AND OFFERS NO WALK** (box 5).
##
## **AND IT IS DRIVEN BY A REAL UNANSWERED WORLD, WHICH TOOK MEASURING TO FIND.** My first version
## walked ten seeds expecting one of them to have nothing that burns. All ten answered, and so did
## every one of 399: **`Burns` is never unanswered, because worldgen guarantees a hand-lit fuel in
## the two chunks beside spawn** and rerolls the roster until the starter ladder holds. `HardEnough`
## is unanswered in 64 of those 399, and both of the sim's two empty sentences occur there --
## "nothing in this world does" (seeds 1, 2) and "no patch is rich enough" (seeds 9, 11). So the
## empty RENDERING is exercised through the sim's own words on a seed known to produce them, rather
## than through a dictionary I typed.
##
## **WHAT THAT MEASUREMENT MEANS FOR WHOEVER BUILDS HERE NEXT, in Maren's words:** a new player is
## never told "nothing here burns", because the starter ladder is an onboarding guarantee. So this
## tab must not be built around an empty fuel headline it will never reach; the empty state is real
## and belongs to the other question.
##
## The body does not branch on which question it was handed, which is why this covers box 5: the
## empty path through `show_answers` is one path.
func test_an_unanswered_question_still_says_something_and_offers_no_walk() -> bool:
	var answers := _answers("1")
	if answers.size() < 2:
		return _fail("seed 1 answered %d questions, so the unanswered arm cannot be reached"
				% answers.size())
	var unanswered: Dictionary = answers[1]
	if unanswered.get("walk_to") != null:
		return _fail(("seed 1's second question is answered now, so this arm is vacuous. It was "
				+ "empty across 64 of 399 worlds when measured; re-measure and pick a seed"))
	var tab := AssayMineralogy.new()
	tab.show_answers(answers)
	# THE SIM'S SENTENCE, NOT SILENCE AND NOT A BLANK TAB.
	if tab.headline_at(1).text != String(unanswered.get("headline", "")):
		tab.free()
		return _fail("the tab said `%s` and the sim said `%s`"
				% [tab.headline_at(1).text, unanswered.get("headline", "")])
	if tab.headline_at(1).text == "":
		tab.free()
		return _fail("an unanswered question rendered an empty line, which box 5 forbids")
	# AND NOTHING TO WALK TO, SO NO BUTTON THAT COULD ONLY REFUSE (Maren, ASSA-215).
	if tab.walk_control_at(1).visible:
		tab.free()
		return _fail("nothing answers and `go here` is still on screen")
	if tab.walk_target_at(1) != null:
		tab.free()
		return _fail("no answer, but the body kept a destination: %s" % tab.walk_target_at(1))
	print("    ASSA-254: unanswered rendering driven by seed 1 q1 -- `%s`" % tab.headline_at(1).text)
	tab.free()
	return true


## **AN ANSWER UNDERFOOT SAYS SO AND OFFERS NO WALK EITHER -- ASSA-262's GAP 1.**
##
## This is the state that shipped broken, and it is not the empty state: the sim's search DOES name
## a tile, and it is the one the player is standing on (`NearestDeposit.heading == None`, which
## `proximity_headline` renders as *"right where you are standing"*). The merged body gated its
## button on that tile being present, so on seed 14247's hard-enough answer the player got a button
## that walked them to their own feet -- the dead control that looks live, which ASSA-247 box 6
## forbids. Maren found it by reading the file against her ruling; nothing here could, because the
## suite had two arms where the feature has three.
##
## **THE SEED IS FOUND BY THE SIM'S OWN WORDS, NOT ASSUMED.** A test may read the sentence -- the
## BODY may not -- so the fixture is the first answer in a scanned range whose sentence says the
## player has arrived. If none does, this fails loudly rather than passing over an arm that never
## ran.
func test_an_answer_underfoot_says_so_and_offers_no_walk() -> bool:
	const ARRIVED := "right where you are standing"
	var scanned := ["14247", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
	for seed_text in scanned:
		var answers := _answers(seed_text)
		for index in answers.size():
			var answer: Dictionary = answers[index]
			if not String(answer.get("headline", "")).contains(ARRIVED):
				continue
			# THE BINDING'S HALF: the sim named a tile and still offers no walk.
			if answer.get("walk_to") != null:
				return _fail(("seed %s q%d says the player has arrived and the binding still sent "
						+ "a walk to %s: ASSA-262's gap is back in `proximity_facts`")
						% [seed_text, index, answer.get("walk_to")])
			var tab := AssayMineralogy.new()
			tab.show_answers(answers)
			# THE BODY'S HALF: the sentence is rendered, and the control is absent, not greyed.
			if tab.headline_at(index).text != String(answer.get("headline", "")):
				tab.free()
				return _fail("the underfoot answer reads `%s` and the sim said `%s`"
						% [tab.headline_at(index).text, answer.get("headline", "")])
			if not tab.headline_at(index).visible:
				tab.free()
				return _fail("the underfoot answer is not on screen at all")
			if tab.walk_control_at(index).visible:
				tab.free()
				return _fail(("seed %s q%d: the answer is underfoot and `go here` is on screen, "
						+ "which would walk the player to the tile they stand on")
						% [seed_text, index])
			if tab.walk_control_at(index).disabled:
				tab.free()
				return _fail("the walk control is greyed rather than absent, which Maren ruled "
						+ "against: a dead control that looks live")
			if tab.walk_target_at(index) != null:
				tab.free()
				return _fail("the body kept a destination for an answer underfoot: %s"
						% tab.walk_target_at(index))
			print("    ASSA-262: underfoot arm driven by seed %s q%d -- `%s`"
					% [seed_text, index, tab.headline_at(index).text])
			tab.free()
			return true
	return _fail(("no answer across %d seeds says `%s`, so the arm ASSA-262 exists for never ran. "
			+ "Spawning on an answering patch was measurable on seed 14247 when this was written; "
			+ "re-measure and widen the scan rather than deleting this test")
			% [scanned.size(), ARRIVED])


## **AND AN ANSWER SOMEWHERE ELSE OFFERS THE WALK**, which is the third arm of the same branch.
## Without this, hiding `go here` unconditionally would pass both tests above.
func test_an_answer_elsewhere_offers_the_walk_to_the_sims_tile() -> bool:
	var answers := _answers("14247")
	if answers.is_empty():
		return _fail("the binding answered nothing")
	var answer: Dictionary = answers[0]
	if answer.get("walk_to") == null:
		return _fail(("seed 14247's fuel answer offers no walk, which contradicts 399 of 399 "
				+ "worlds answering `Burns`. Re-measure before trusting this suite"))
	var tab := AssayMineralogy.new()
	tab.show_answers(answers)
	if not tab.walk_control_at(0).visible:
		tab.free()
		return _fail("the sim named a walk and `go here` is hidden")
	if tab.walk_target_at(0) != answer.get("walk_to"):
		tab.free()
		return _fail("the body would walk to %s and the sim named %s"
				% [tab.walk_target_at(0), answer.get("walk_to")])
	tab.free()
	return true


## **THE WALK CONTROL IS QUIET** (ASSA-262's gap 2; Maren's ruling 5, `theme/assay.tres:383-393`).
##
## It was the default Button, which satisfies *never ACCENT* and not *Quiet*: at 13px INK it was the
## second-loudest control in the HUD column after `Mine`, in a body whose job is to be read. Asked
## of the control, because the comment claiming it was quiet is what shipped.
func test_the_walk_control_is_the_quiet_weight() -> bool:
	var answers := _answers("14247")
	if answers.is_empty():
		return _fail("the binding answered nothing")
	var tab := AssayMineralogy.new()
	tab.show_answers(answers)
	var go_here := tab.walk_control_at(0)
	if go_here.theme_type_variation != &"Quiet":
		tab.free()
		return _fail("`go here` is the `%s` weight, not Quiet" % go_here.theme_type_variation)
	tab.free()
	return true


## **`go here` CARRIES THE SIM'S TILE AND NOTHING COMPUTED FROM IT** (box 3, box 8).
##
## The signal's payload is asserted against the binding's own `walk_to`, so a body that offset it by
## a tile to "stand beside the rock" would fail here. That offset is exactly the kind of helpfulness
## this item forbids: the sim chose the tile of the deposit nearest the player, and a client that
## adjusts it is doing arithmetic the sim already did.
func test_go_here_emits_the_sims_tile_unchanged() -> bool:
	var answers := _answers("14247")
	if answers.is_empty():
		return _fail("the binding answered nothing")
	var answer: Dictionary = answers[0]
	if answer.get("walk_to") == null:
		return _fail("seed 14247's fuel answer offers no walk, so this arm is vacuous")
	var tab := AssayMineralogy.new()
	tab.show_answers(answers)
	var heard: Array = []
	tab.go_here_pressed.connect(func(tile: Vector2i) -> void: heard.append(tile))
	tab.walk_control_at(0).pressed.emit()
	if heard.size() != 1:
		tab.free()
		return _fail("pressing `go here` emitted %d tiles, not 1" % heard.size())
	if heard[0] != answer.get("walk_to"):
		tab.free()
		return _fail("`go here` would walk to %s and the sim named %s"
				% [heard[0], answer.get("walk_to")])
	tab.free()
	return true


## **A BODY WITH NO WORLD BEHIND IT SAYS ONE SENTENCE AND OFFERS NO WALK.** `proximity_answers`
## returns an empty array for no world and for a player who is not in one, and the sim's own "no
## such player" line is about a missing player and would read as a mineralogy answer in this slot.
func test_with_no_world_the_tab_says_one_sentence_and_offers_no_walk() -> bool:
	var tab := AssayMineralogy.new()
	tab.show_answers([])
	if tab.shown_count() != 1:
		tab.free()
		return _fail("with no world the tab shows %d lines, not 1" % tab.shown_count())
	if tab.headline_at(0).text != AssayMineralogy.NO_WORLD:
		tab.free()
		return _fail("the no-world line reads `%s`" % tab.headline_at(0).text)
	if tab.walk_control_at(0).visible:
		tab.free()
		return _fail("there is no world and `go here` is on screen")
	tab.free()
	return true


## **AN ANSWER THE SIM STOPS GIVING LEAVES THE SCREEN, AND SO DOES ITS GAP.** Rows are reused across
## refreshes, so the failure this catches is a second answer left on screen after the world ends --
## a sentence about a world that is gone, under a live button.
func test_a_row_the_sim_stops_answering_leaves_the_screen() -> bool:
	var answers := _answers("14247")
	if answers.size() < 2:
		return _fail("seed 14247 answered %d questions" % answers.size())
	var tab := AssayMineralogy.new()
	tab.show_answers(answers)
	if tab.shown_count() != answers.size():
		tab.free()
		return _fail("the tab shows %d of %d answers" % [tab.shown_count(), answers.size()])
	tab.show_answers([])
	if tab.shown_count() != 1:
		tab.free()
		return _fail("after the world ended the tab still shows %d lines" % tab.shown_count())
	if tab.walk_control_at(1).visible or tab.walk_target_at(1) != null:
		tab.free()
		return _fail("the second answer's walk survived the world it was about")
	tab.free()
	return true


## **THE BODY SPENDS NO COLOUR AND SETS NO POSITION**, because it is a tab body and the strip it
## lands in owns both (ASSA-247's "adding a tab is one entry, not a re-layout").
##
## A source scan rather than a property read: a `position` written in code is overwritten by the
## first layout pass and would read as zero here, so the thing to catch is the LINE, not its effect.
## The same reason `test_map_key.gd` scans `_draw` instead of photographing a canvas.
func test_the_tab_body_owns_no_colour_and_no_position() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/mineralogy.gd")
	if source == "":
		return _fail("could not read scripts/mineralogy.gd to scan it")
	var bare := ""
	for line in source.split("\n"):
		var text := String(line).strip_edges()
		if text.begins_with("#"):
			continue
		bare += text + "\n"
	for forbidden in ["Color(", "modulate", "set_position", "position =", "add_theme_color"]:
		if bare.contains(forbidden):
			return _fail(("the tab body contains `%s`: a tab body owns neither its colour nor its "
					+ "place, the strip does (ASSA-247)") % forbidden)
	return true


## Every `Control` under `node` that a player can operate -- buttons, dropdowns, tab bars, sliders.
## Labels and spacers are not controls in this sense: the ruling is about things you click.
func _controls_under(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is BaseButton or child is OptionButton or child is TabBar or child is Range:
			found.append(child)
		found.append_array(_controls_under(child))
	return found
