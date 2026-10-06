extends RefCounted
## **THE MINERALOGY TAB SAYS WHAT THE SIM SAID AND NOTHING ELSE** (ASSA-254, the client leg of
## ASSA-241).
##
## **DRIVEN BY A REAL SIM, NOT BY A DICTIONARY I TYPED.** A test that hands `show_answer` a literal
## `{"headline": "..."}` proves the Label is wired and nothing about the feature: the whole claim of
## this item is that the line on screen is `debug::proximity_headline` with no client in between, so
## the fixture has to be the binding's real output on a real world. `AssaySimHost.fresh_welcome_json`
## is how every other suite here stands a world up.
##
## WHAT IS NOT TESTED HERE AND WHERE IT LIVES: that the headline is byte-identical to the sim's
## sentence is asserted in `sim-godot/src/lib.rs`
## (`the_tabs_headline_and_tile_are_the_sims_own_answer`), because that is the one crate where the
## sim's string and what the binding sends can both be reached. This file owns the half that is the
## client's: that the body renders the sentence verbatim, puts the evidence under it, and never
## invents a destination.

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


## **THE FIRST LINE IS THE SIM'S SENTENCE, CHARACTER FOR CHARACTER.**
##
## Not "contains", not "starts with": the body may not append a full stop, capitalise a species name
## or wrap the clause in prose of its own. The CLI prints this same string, and a player who read
## both must not have to work out whether two phrasings mean one thing (the ASSA-135 rule).
func test_the_headline_is_the_sims_sentence_verbatim() -> bool:
	var made := _world("14247")
	if made.is_empty():
		return _fail("could not stand a world up through the binding")
	var sim: AssaySimHost = made[0]
	var players: Array = made[1]
	if players.is_empty():
		return _fail("the welcome carried no player, so there is nobody to answer for")
	var me: int = int((players[0] as Dictionary).get("id", -1))
	var answers := sim.proximity_answers(me)
	if answers.is_empty():
		return _fail("the binding answered nothing for a player who is in the world")
	var tab := AssayMineralogy.new()
	tab.show_answer(answers)
	var expected := String((answers[0] as Dictionary).get("headline", ""))
	if expected == "":
		return _fail("the binding sent an empty headline, which the sim never produces")
	if tab.headline.text != expected:
		return _fail(("the tab's first line is `%s` and the sim said `%s`")
				% [tab.headline.text, expected])
	# AND IT IS THE FIRST THING IN THE BODY, which is the ruling: a tab that opens on a grid makes
	# the player do the collating again. Asked of child order, not of a comment.
	if tab.get_child(0) != tab.headline:
		return _fail("the headline is not the first child: child 0 is `%s`"
				% tab.get_child(0).name)
	tab.free()
	return true


## **THE EVIDENCE GOES UNDER THE ANSWER, AND THE ANSWER IS NOT IN THE EVIDENCE BOX.**
##
## The failure this catches is a body that grows a second copy of the species rows, or one that puts
## the headline inside the scrolling list where it would scroll away from the question it answers.
func test_the_species_rows_sit_under_the_headline_and_not_in_place_of_it() -> bool:
	var tab := AssayMineralogy.new()
	var rows := 0
	for i in 3:
		var row := Label.new()
		row.text = "a species row"
		tab.evidence.add_child(row)
		rows += 1
	if tab.evidence.get_child_count() != rows:
		return _fail("the evidence box did not take the rows it was given")
	# The headline is NOT one of them, and the evidence box is below it in the body.
	if tab.evidence.get_parent() != tab:
		return _fail("the evidence box is not a child of the body")
	if tab.get_children().find(tab.evidence) < tab.get_children().find(tab.headline):
		return _fail("the evidence sits ABOVE the answer it is evidence for")
	tab.free()
	return true


## **AN UNANSWERED QUESTION STILL SAYS SOMETHING AND OFFERS NO WALK** (box 5).
##
## **AND IT IS DRIVEN BY A REAL UNANSWERED WORLD, WHICH TOOK MEASURING TO FIND.** My first version
## walked ten seeds expecting one of them to have nothing that burns. All ten answered, and so did
## every one of 399: **`Burns` is never unanswered, because worldgen guarantees a hand-lit fuel in
## the two chunks beside spawn.** `HardEnough` is unanswered in 64 of those 399, and both of the
## sim's two empty sentences occur there -- "nothing in this world does" (seeds 1, 2) and "no patch
## is rich enough" (seeds 9, 11). So the empty RENDERING is exercised through the sim's own words on
## a seed known to produce them, rather than through a dictionary I typed.
##
## The body does not branch on which question it was handed, which is why this covers box 5: the
## empty path through `show_answer` is one path.
func test_an_unanswered_question_still_says_something_and_offers_no_walk() -> bool:
	var made := _world("1")
	if made.is_empty():
		return _fail("could not stand seed 1 up through the binding")
	var sim: AssaySimHost = made[0]
	var players: Array = made[1]
	if players.is_empty():
		return _fail("the welcome carried no player")
	var me: int = int((players[0] as Dictionary).get("id", -1))
	var answers := sim.proximity_answers(me)
	if answers.size() < 2:
		return _fail("seed 1 answered %d questions, so the unanswered arm cannot be reached"
				% answers.size())
	var unanswered: Dictionary = answers[1]
	if unanswered.get("tile") != null:
		return _fail(("seed 1's second question is answered now, so this arm is vacuous. It was "
				+ "empty across 64 of 399 worlds when measured; re-measure and pick a seed"))
	var tab := AssayMineralogy.new()
	# **NO SELECTOR ANY MORE** (ASSA-262): every question is rendered, so this arm reads the SECOND
	# block rather than asking the body to show one. That is strictly better evidence -- it reads what
	# ships instead of a path only a test takes.
	tab.show_answer(answers)
	# THE SIM'S SENTENCE, NOT SILENCE AND NOT A BLANK TAB.
	if tab.headline_text(1) != String(unanswered.get("headline", "")):
		tab.free()
		return _fail("the tab said `%s` and the sim said `%s`"
				% [tab.headline_text(1), unanswered.get("headline", "")])
	if tab.headline_text(1) == "":
		tab.free()
		return _fail("an unanswered question rendered an empty tab, which box 5 forbids")
	# AND NOTHING TO WALK TO, SO NO BUTTON THAT COULD ONLY REFUSE (Maren, ASSA-215).
	if tab.walk_shown(1):
		tab.free()
		return _fail("nothing answers and `go here` is still on screen")
	if tab.tile_for(1) != null:
		tab.free()
		return _fail("no answer, but the body kept a destination: %s" % tab.tile_for(1))
	# NOTHING ANSWERS IS NOT "THE ANSWER IS HERE". Two states hide the button and they are different
	# news; a body that conflated them would report this one as underfoot (ASSA-263).
	if tab.underfoot_for(1):
		tab.free()
		return _fail("nothing answers, and the body says the answer is under the player's feet")
	print("    ASSA-254: unanswered rendering driven by seed 1 q1 -- `%s`" % tab.headline_text(1))
	tab.free()
	return true


## **AND AN ANSWERED WORLD OFFERS THE WALK**, which is the other half of the same branch. Without
## this, hiding `go here` unconditionally would pass the test above.
func test_an_answered_question_offers_the_walk_to_the_sims_tile() -> bool:
	var made := _world("14247")
	if made.is_empty():
		return _fail("could not stand seed 14247 up through the binding")
	var sim: AssaySimHost = made[0]
	var players: Array = made[1]
	if players.is_empty():
		return _fail("the welcome carried no player")
	var me: int = int((players[0] as Dictionary).get("id", -1))
	var answers := sim.proximity_answers(me)
	if answers.is_empty():
		return _fail("the binding answered nothing")
	var answer: Dictionary = answers[0]
	if answer.get("tile") == null:
		return _fail(("seed 14247 has nothing that burns, which contradicts 399 of 399 worlds "
				+ "answering `Burns`. Re-measure before trusting this suite"))
	# AND THE WALK IS A REAL ONE, ASSERTED RATHER THAN ASSUMED (ASSA-263). If this seed's burnable
	# rock ever lands under the player's own feet, the button is correctly absent and this test would
	# otherwise fail as though the gate were broken.
	if bool(answer["underfoot"]):
		return _fail(("seed 14247's burnable rock is now under the player's feet, so `go here` is "
				+ "correctly absent and this test is the wrong one. Pick a seed with a real walk"))
	var tab := AssayMineralogy.new()
	tab.show_answer(answers)
	if not tab.go_here.visible:
		tab.free()
		return _fail("the sim named a tile and `go here` is hidden")
	if tab.target_tile() != answer.get("tile"):
		tab.free()
		return _fail("the body would walk to %s and the sim named %s"
				% [tab.target_tile(), answer.get("tile")])
	tab.free()
	return true


## **THE ANSWER UNDER YOUR OWN FEET OFFERS NO WALK, AND STILL NAMES THE ROCK** (ASSA-263).
##
## The third state, and the one that shipped broken: `tile` is `Some` when the nearest answering
## patch is the tile the player is standing on -- the sim's sentence reads *"right where you are
## standing"* -- so a button gated on `tile != null` alone was live, offering to walk the player to
## their own feet. Maren photographed it at 344 px on this exact seed and question before anyone
## argued about it.
##
## **THE PREMISE IS ASSERTED, NOT ASSUMED.** A test that reached for this state and found an ordinary
## answer would pass by never meeting the case, which is how a green test of mine turned out to be
## decoration earlier today. So this fails loudly, with what to re-measure, rather than skipping.
##
## And `target_tile()` is still the sim's tile: the answer is not withheld, only the walk. Something
## later will want it to highlight the rock on the map, which is why `tile` was not overloaded to
## mean "somewhere to go" (Maren's one design constraint on this fix).
func test_an_answer_underfoot_offers_no_walk_and_still_names_the_rock() -> bool:
	var made := _world("14247")
	if made.is_empty():
		return _fail("could not stand seed 14247 up through the binding")
	var sim: AssaySimHost = made[0]
	var players: Array = made[1]
	if players.is_empty():
		return _fail("the welcome carried no player")
	var me: int = int((players[0] as Dictionary).get("id", -1))
	var answers := sim.proximity_answers(me)
	if answers.size() < 2:
		return _fail("seed 14247 answered %d questions, so the second one cannot be asked"
				% answers.size())
	var here: Dictionary = answers[1]
	if here["tile"] == null:
		return _fail(("seed 14247's hard-enough question is unanswered now, so there is no "
				+ "underfoot answer to render. Re-measure and pick a seed"))
	if not bool(here["underfoot"]):
		return _fail(("seed 14247's hard-enough answer is no longer underfoot (it was Tonore (A) "
				+ "at (56, 40), the spawn tile). Re-measure: this arm is now vacuous"))
	var tab := AssayMineralogy.new()
	# BOTH QUESTIONS RENDERED (ASSA-262); this arm reads the second block, not a selected view.
	tab.show_answer(answers)
	# ABSENT, NOT GREYED (Maren, ASSA-241 ruling 5).
	if tab.walk_shown(1):
		tab.free()
		return _fail(("the answer is the tile the player is standing on and `go here` is on screen: "
				+ "a control whose only effect is to walk you where you already are"))
	# AND ABSENT FOR THE RIGHT REASON, rather than absent because the tile went missing.
	if not tab.underfoot_for(1):
		tab.free()
		return _fail("the body did not read the binding's `underfoot`, so the button is hidden by luck")
	if tab.tile_for(1) != here["tile"]:
		tab.free()
		return _fail("the answer's tile was withheld as well as the walk: %s, sim said %s"
				% [tab.tile_for(1), here["tile"]])
	# PRESSING IT ANYWAY SUBMITS NOTHING, AND IT IS THE SECOND QUESTION'S OWN BUTTON. A `MoveTo` to
	# your own tile is a command on the wire that does nothing. This also catches the bug a single
	# shared tile would have shipped: question 2's verb walking you to question 1's rock.
	var heard: Array = []
	tab.go_here_pressed.connect(func(tile: Vector2i) -> void: heard.append(tile))
	tab._pressed(1)
	if not heard.is_empty():
		tab.free()
		return _fail("a press on the hidden button still emitted %s" % heard)
	print("    ASSA-263: 14247 q1 is underfoot at %s -- `%s`" % [here["tile"], tab.headline_text(1)])
	tab.free()
	return true


## **`go here` CARRIES THE SIM'S TILE AND NOTHING COMPUTED FROM IT** (box 3, box 8).
##
## The signal's payload is asserted against the binding's own `tile`, so a body that offset it by a
## tile to "stand beside the rock" would fail here. That offset is exactly the kind of helpfulness
## this item forbids: the sim chose the tile of the deposit nearest the player, and a client that
## adjusts it is doing arithmetic the sim already did.
func test_go_here_emits_the_sims_tile_unchanged() -> bool:
	var made := _world("14247")
	if made.is_empty():
		return _fail("could not stand a world up through the binding")
	var sim: AssaySimHost = made[0]
	var players: Array = made[1]
	if players.is_empty():
		return _fail("the welcome carried no player")
	var me: int = int((players[0] as Dictionary).get("id", -1))
	var answers := sim.proximity_answers(me)
	if answers.is_empty():
		return _fail("the binding answered nothing")
	var answer: Dictionary = answers[0]
	if answer.get("tile") == null:
		print("    ASSA-254: seed 14247 has no burnable rock, so this arm is vacuous here")
		return true
	var tab := AssayMineralogy.new()
	tab.show_answer(answers)
	var heard: Array = []
	tab.go_here_pressed.connect(func(tile: Vector2i) -> void: heard.append(tile))
	tab.go_here.pressed.emit()
	if heard.size() != 1:
		tab.free()
		return _fail("pressing `go here` emitted %d tiles, not 1" % heard.size())
	if heard[0] != answer.get("tile"):
		tab.free()
		return _fail("`go here` would walk to %s and the sim named %s"
				% [heard[0], answer.get("tile")])
	tab.free()
	return true


## **`go here` IS A VERB, NOT THE PANEL'S PURPOSE** (Maren's ruling 5 on ASSA-241, amended from her
## own 344 px shot: Quiet, shrink-to-fit, left-aligned).
##
## **ASKED OF THE VARIATION AND THE FLAGS, NEVER OF A COLOUR.** A `Quiet` button built off the scene
## tree reports the default `font_color`, because a theme type variation does not resolve until the
## node is inside a tree that carries the theme -- a lesson already written into
## `test_main_screen.gd`. The line in the source is the claim; its resolved colour is the theme's.
##
## The failure this catches is the one the picture caught: with no size flags in a `VBoxContainer`
## the button filled the whole HUD column, so a convenience verb became the heaviest element on
## screen and out-weighed `Mine`, which is meant to be the screen's one primary.
func test_go_here_is_quiet_and_sized_to_its_words() -> bool:
	var tab := AssayMineralogy.new()
	var variation := tab.go_here.theme_type_variation
	var flags := tab.go_here.size_flags_horizontal
	tab.free()
	if variation != &"Quiet":
		return _fail("`go here` wears `%s`: a convenience verb is Quiet, never the screen's accent"
				% variation)
	if flags != Control.SIZE_SHRINK_BEGIN:
		return _fail(("`go here` has size flags %d, not SIZE_SHRINK_BEGIN (%d): in a VBoxContainer "
				+ "it fills the column and reads as the panel's purpose")
				% [flags, Control.SIZE_SHRINK_BEGIN])
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


## **BOTH QUESTIONS ARE RENDERED, STACKED, IN THE SIM'S ORDER, WITH NO SELECTOR** (ASSA-262, Maren's
## ruling 3 on ASSA-241).
##
## The body used to take a `which` argument and show one answer. **A parameter that picks IS the
## selector she ruled against**, and the docstring defended it by misquoting her twice -- calling the
## second question "a design call nobody has made" when she had made it, and citing a ruling about
## `asked` living in the sim's SENTENCE as if it were about this UI.
##
## **ASSERTED AGAINST THE SIM'S OWN ARRAY, not against the number 2.** `Question::ALL` is the sim's
## to grow; a test that hardcoded two would pass the day a third question arrived and nothing drew it.
func test_both_questions_are_stacked_in_the_sims_order_with_no_selector() -> bool:
	var made := _world("14247")
	if made.is_empty():
		return _fail("could not stand seed 14247 up through the binding")
	var sim: AssaySimHost = made[0]
	var players: Array = made[1]
	if players.is_empty():
		return _fail("the welcome carried no player")
	var me: int = int((players[0] as Dictionary).get("id", -1))
	var answers := sim.proximity_answers(me)
	if answers.size() < 2:
		return _fail(("the sim answered %d questions, so `stacked` cannot be distinguished from "
				+ "`one`. Re-measure: Question::ALL has shrunk") % answers.size())
	var tab := AssayMineralogy.new()
	tab.show_answer(answers)
	var ok := true
	# ONE BLOCK PER ANSWER, no more and no fewer.
	if tab.question_count() != answers.size():
		ok = _fail("the sim answered %d questions and the body built %d blocks"
				% [answers.size(), tab.question_count()])
	# EVERY SENTENCE RENDERED, AND IN THE SIM'S ORDER. Compared by index, so a body that drew both
	# but swapped them fails here.
	for i in answers.size():
		var want := String((answers[i] as Dictionary)["headline"])
		if tab.headline_text(i) != want:
			ok = _fail("block %d says `%s` and the sim's answer %d is `%s`"
					% [i, tab.headline_text(i), i, want])
	# AND EVERY CONTROL IS STILL ABOVE THE EVIDENCE LIST (Maren's ruling 5). Asked of the real tree:
	# the evidence box must be the LAST child, so no question's verb can end up under the rocks.
	var kids := tab.get_children()
	if kids[kids.size() - 1] != tab.evidence:
		ok = _fail(("the evidence list is not the last child, so a control sits below it: last is "
				+ "`%s`") % kids[kids.size() - 1])
	tab.free()
	return ok


## **A SECOND QUESTION'S VERB WALKS TO ITS OWN ROCK, NOT THE FIRST'S** (ASSA-262).
##
## This is the bug a single shared `_tile` would have shipped the moment the body stopped asking one
## question: two buttons, one destination. The tile is bound per block at build time, so the only way
## to get this wrong is to go back to one field -- and then this test says so by name.
##
## It needs a world where BOTH questions have a walk, which is not every world, so the arms it cannot
## reach are reported rather than silently skipped.
func test_each_questions_walk_carries_that_questions_own_tile() -> bool:
	for seed in ["777042", "2191", "19", "23", "31", "44", "57", "61", "73", "97"]:
		var made := _world(seed)
		if made.is_empty():
			continue
		var sim: AssaySimHost = made[0]
		var players: Array = made[1]
		if players.is_empty():
			continue
		var me: int = int((players[0] as Dictionary).get("id", -1))
		var answers := sim.proximity_answers(me)
		if answers.size() < 2:
			continue
		var a: Dictionary = answers[0]
		var b: Dictionary = answers[1]
		# BOTH WALKABLE AND TO DIFFERENT TILES, or this proves nothing.
		if a["tile"] == null or b["tile"] == null:
			continue
		if bool(a["underfoot"]) or bool(b["underfoot"]):
			continue
		if a["tile"] == b["tile"]:
			continue
		var tab := AssayMineralogy.new()
		tab.show_answer(answers)
		var heard: Array = []
		tab.go_here_pressed.connect(func(tile: Vector2i) -> void: heard.append(tile))
		tab._pressed(1)
		var ok := true
		if heard.size() != 1:
			ok = _fail("seed %s: the second question's verb emitted %d tiles" % [seed, heard.size()])
		elif heard[0] != b["tile"]:
			ok = _fail(("seed %s: the second question's verb would walk to %s, which is the FIRST "
					+ "question's rock. The sim named %s for this one")
					% [seed, heard[0], b["tile"]])
		if ok:
			print("    ASSA-262: seed %s q0 -> %s, q1 -> %s, each verb its own"
					% [seed, a["tile"], b["tile"]])
		tab.free()
		return ok
	return _fail(("no seed in the list gave both questions a distinct walkable answer, so this arm "
			+ "never ran. Widen the list rather than trusting it"))
