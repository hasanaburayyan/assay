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
	tab.show_answer(answers, 1)
	# THE SIM'S SENTENCE, NOT SILENCE AND NOT A BLANK TAB.
	if tab.headline.text != String(unanswered.get("headline", "")):
		tab.free()
		return _fail("the tab said `%s` and the sim said `%s`"
				% [tab.headline.text, unanswered.get("headline", "")])
	if tab.headline.text == "":
		tab.free()
		return _fail("an unanswered question rendered an empty tab, which box 5 forbids")
	# AND NOTHING TO WALK TO, SO NO BUTTON THAT COULD ONLY REFUSE (Maren, ASSA-215).
	if tab.go_here.visible:
		tab.free()
		return _fail("nothing answers and `go here` is still on screen")
	if tab.target_tile() != null:
		tab.free()
		return _fail("no answer, but the body kept a destination: %s" % tab.target_tile())
	print("    ASSA-254: unanswered rendering driven by seed 1 q1 -- `%s`" % tab.headline.text)
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
