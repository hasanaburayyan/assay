extends RefCounted
## THE SIM BINDING, FROM THE GDSCRIPT SIDE. Rust tests cover what the binding computes; nothing in
## Rust can tell you whether the library actually loaded into a Godot process, which is the half
## that breaks in a shipped build.
##
## WHY THE BINDING EXISTS AT ALL: a `TickBundle` carries inputs, not state, so the world at tick N
## exists only once something runs `sim::step`. GDScript must not be that something -- a second
## implementation of the rules is a second set of rules, and the first disagreement would show up as
## a wrong-looking screen long before it showed up as a desync. So the client runs the same Rust
## `sim` every other peer runs, through `sim-godot`.
##
## EVERYTHING HERE READS THE HASH FROM THE SIM AT RUNTIME. No expected value is written down in this
## file: the golden hash moved twice on 2026-10-01 and moved again with the assembly model. A pinned
## constant in GDScript would be a second source of truth, and the test below enforces that by
## reading the source.

var runner = null

## What the client cannot work without. Renaming one of these in Rust is a silent break -- GDScript
## resolves `#[func]` names at call time, so the failure would first appear in a shipped build.
const REQUIRED_METHODS := [
	"from_welcome_json", "apply_bundle_json", "tick", "hash_hex", "seed_hex",
	"width_tiles", "height_tiles", "player_count", "last_events",
	# The HUD's reads. All four are called every frame, so a rename that only showed up at runtime
	# would show up as an empty panel in a shipped build.
	"event_lines", "inventory_of", "tile_at", "species_sheets",
	# WHICH LINES A HIDDEN LOG MAY NOT SWALLOW (ASSA-89). The log is hidden by default now, so this
	# is the only route a refusal has to the screen: a rename here would not empty a panel, it would
	# make the client silent about the one thing it must say, which looks like nothing at all.
	"attention_lines",
	# The wire's own number, so no GDScript file has to keep a copy of it.
	"protocol_version",
	# The roster size, so the client's species colour table is checked against the sim's own count.
	"species_per_world",
	# THE LONGEST NAME A SPECIES CAN CARRY, so the machine menu's width bound is measured against
	# the sim's own cap. A rename here does not empty a panel: `test_buttons.gd`'s worst case would
	# fall back to a shorter string, stay green, and stop bounding the row it exists to bound.
	"species_name_max",
	# The scripted demo session's two: the pair the world guarantees, and serde's own spelling of an
	# item, which is what the session's commands are checked against.
	"starter_pair", "item_json", "item_echo",
	# WHETHER A PART PRESS IS ALREADY DOOMED (ASSA-102, for Maren's ASSA-86 ruling 2). A rename here
	# fails open in the worst direction: the window would go back to confirming a press the sim
	# refuses, in the positive colour, with the refusal arriving at `Assemble`.
	"part_press_refusal",
	# WHETHER ANYTHING THE FACTORY OWNS HAS STOPPED (ASSA-94). A rename here fails silently in the
	# worst way this surface can: the panel that exists to say "something has stopped" would say
	# nothing, which is indistinguishable from a factory that is working.
	"halt_lines",
]


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## THE LOAD CHECK, which is also what CI runs against the exported Mac and Windows builds.
func test_the_binding_loaded_and_steps_the_real_sim() -> bool:
	var failures := AssaySelfCheck.binding_failures()
	if not failures.is_empty():
		return _fail("the sim binding is not usable: %s" % [failures])
	return true


func test_every_method_the_client_calls_exists() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var have := []
	for entry in ClassDB.class_get_method_list("AssaySim", true):
		have.append(String(entry["name"]))
	var missing := []
	for wanted in REQUIRED_METHODS:
		if not have.has(wanted):
			missing.append(wanted)
	if not missing.is_empty():
		return _fail("the binding is missing %s; it has %s" % [missing, have])
	return true


## THE SPECIES COLOUR TABLE IS AS LONG AS THE SIM'S ROSTER, and the sim is the one that says so.
##
## `AssayHud.SPECIES_TINTS` is one slot per species, derived by `art/species_probe.py` for exactly
## this many species. A roster longer than the table does not crash -- `deposit_color` wraps -- it
## quietly gives two species the same colour, which is the failure that hurts the player who cannot
## use colour anyway and shows up on no screen as wrong. So the number is asked of the sim here
## instead of being written down a third time. (`art/check_species_tints.py` holds the Python half
## of the table to the same constant, from the other side.)
func test_the_species_colour_table_is_as_long_as_the_sims_roster() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var roster: Variant = ClassDB.class_call_static("AssaySim", "species_per_world")
	if typeof(roster) != TYPE_INT:
		return _fail("species_per_world is a %s, not an int" % typeof(roster))
	if int(roster) != AssayHud.SPECIES_TINTS.size():
		return _fail(("the sim rolls %d species and the client has %d tints. Rerun "
				+ "art/species_probe.py for %d slots; do not pad the table by hand.")
				% [roster, AssayHud.SPECIES_TINTS.size(), roster])
	return true


## THE ITEM DICTIONARIES THE DEMO SENDS ARE THE SHAPE SERDE READS, AND THIS IS THE ONE TEST OF THAT
## WHICH CANNOT AGREE WITH MY OWN MISREADING.
##
## `AssayActions.item` builds the JSON by hand -- it has to, because parsing would turn every number
## into a double and serde will not take `3.0` for a `u8` -- and `Item` is three nested enums and a
## newtype. `{"kind":{"Part":{"Frame":"Held"}},"species":3,"grade":"C"}` is a shape nothing on this
## side would notice getting wrong: a malformed command is dropped before `step` ever sees it, so the
## probe would fail as "the parts never arrived" and I would go looking in the wrong place. On
## 2026-10-01 I wrote both a protocol convention and its test from the same wrong assumption and they
## agreed with each other; `AssaySim.item_json` is serde writing the same item, so this cannot.
##
## Compared as PARSED values, not as text: both sides go through the same `JSON.parse_string`, so key
## order, whitespace and Godot's doubles cannot make an agreement look like a difference.
func test_every_item_the_demo_sends_is_the_shape_serde_reads() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	for kind in ["ore", "refined", "smelter", "head", "handle", "frame", "hopper"]:
		for species in [0, 3, 5]:
			for grade in ["C", "B", "A"]:
				var serdes := AssaySimHost.item_json(kind, species, grade)
				if serdes == "":
					return _fail("the sim will not spell %s:%d:%s at all" % [kind, species, grade])
				var mine := JSON.stringify(AssayActions.item(kind, species, grade))
				# SERDE'S OWN VERDICT ON THE CLIENT'S OWN TEXT, not a comparison of two parsed
				# values. Comparing parsed values is what I wrote first, and a planted mutation
				# walked straight through it: sending `species` as `3.0` passed, because Godot
				# parses `3` and `3.0` back to the same double, while serde refuses a float where a
				# `u8` belongs and the relay would have dropped the command. The echo is the
				# deserialiser that will actually read it.
				var echoed := AssaySimHost.item_echo(mine)
				if echoed != serdes:
					return _fail(("%s:%d:%s -- the client builds %s, and serde reads that as %s "
							+ "where it writes %s") % [kind, species, grade, mine,
							echoed if echoed != "" else "NOTHING AT ALL (refused)", serdes])
	# And a kind the sim does not know is refused on BOTH sides rather than quietly becoming an item.
	if AssaySimHost.item_json("widget", 1, "C") != "":
		return _fail("the sim spelled an item for a kind that does not exist")
	return true


## A HASH CROSSES AS HEX TEXT, NEVER AS A NUMBER. Godot's JSON parses every number as a double and
## GDScript's ints are signed, so a `u64` hash cannot be spelled here at all -- not merely rounded.
## This asserts the type, because a well-meaning "simplification" to an int would pass a comparison
## of two equally-wrong numbers.
func test_the_hash_crosses_as_text() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var hash_value: Variant = ClassDB.class_call_static("AssaySim", "binding_self_check")
	if typeof(hash_value) != TYPE_STRING:
		return _fail("the hash came back as %s, not a String" % type_string(typeof(hash_value)))
	return true


## A message that is not a Welcome must yield null, not a half-built world. A client that accepted
## one would desync later and blame the network.
##
## THIS TEST PRINTS THREE `ERROR: sim-godot: could not read the Welcome snapshot` LINES WHEN IT
## PASSES. That is the binding saying out loud that it refused something, which is the behaviour
## under test -- do not silence it. The suite's verdict is the count on the last line.
func test_a_message_that_is_not_a_welcome_yields_nothing() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	for text in ['{"Refused":{"reason":"protocol 3, host speaks 4"}}', "not json at all", "{}"]:
		var got: Variant = ClassDB.class_call_static("AssaySim", "from_welcome_json", text)
		if got != null:
			return _fail("from_welcome_json accepted %s and returned %s" % [text, got])
	return true


## EVERY PART ROW IS TOLD WHETHER ITS KIND IS A FRAME (ASSA-102, for Maren's ASSA-86 ruling 1: the
## `Frame`/`Mount` word is a property of the KIND, not of the client's buffer state).
##
## THIS TEST EXISTS BECAUSE NOTHING IN RUST CAN SEE IT. `is_frame` crosses as a Variant, so a Rust
## test cannot read the dictionary the client is handed -- I inverted the field on purpose and all 40
## sim-godot tests stayed green. The value is only checkable from this side.
##
## AND IT DERIVES "IS A FRAME" A DIFFERENT WAY ON PURPOSE. Asking `is_frame` whether it agrees with
## itself proves nothing, so the expectation comes from the TAG's shape: `PartKind::Frame(Mount)` is
## an enum inside an enum, so serde spells it as a Dictionary (`{"Frame": "Held"}`), while `Head` and
## `Hopper` are bare strings. That is documented behaviour of `part_kinds` and it moves only if the
## catalogue's shape moves.
func test_a_part_rows_frame_word_comes_from_the_sim() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var catalogue: Array = AssaySimHost.part_kinds()
	if catalogue.is_empty():
		return _fail("the part catalogue is empty, so this test proves nothing")
	var frames := 0
	for entry in catalogue:
		var row: Dictionary = entry
		if not row.has("is_frame"):
			return _fail(("a part row does not say whether its kind is a frame, so the client "
					+ "cannot label it without guessing: %s") % [row])
		# Serde spells a frame as a Dictionary because it carries a Mount; everything else is a
		# bare string. An independent reading of the same fact.
		var looks_like_a_frame: bool = typeof(row["tag"]) == TYPE_DICTIONARY
		if bool(row["is_frame"]) != looks_like_a_frame:
			return _fail(("%s says is_frame=%s but its tag is %s, which disagrees about whether "
					+ "it is a frame") % [row.get("name"), row["is_frame"], row["tag"]])
		if looks_like_a_frame:
			frames += 1
	# NON-VACUITY AS AN EQUALITY: the catalogue has exactly two frames, a handle and a frame. A
	# roster where none were frames would pass every check above.
	if frames != 2:
		return _fail(("expected exactly two frame kinds (a handle to hold and a frame to plant), "
				+ "found %d in %d rows") % [frames, catalogue.size()])
	return true


## A PRESS THE SIM WOULD REFUSE COMES BACK WITH THE SIM'S SENTENCE, THROUGH THE REAL BINDING.
##
## Maren's measured case: pressing the part button on a head row with nothing chosen is
## `FrameIsNotAFrame`, which no later press can rescue. The client used to confirm it in the positive
## colour. Nothing is asserted about the wording here -- that is the sim's and it may be reworded --
## only that a doomed press says something and a legal one says nothing.
func test_a_doomed_part_press_is_refused_before_it_is_confirmed() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var refused: String = ClassDB.class_call_static(
			"AssaySim", "part_press_refusal", PackedStringArray(), "head")
	if refused == "":
		return _fail("a head as the first part is FrameIsNotAFrame and must not be confirmed")
	var allowed: String = ClassDB.class_call_static(
			"AssaySim", "part_press_refusal", PackedStringArray(), "handle")
	if allowed != "":
		return _fail(("a handle as the first part is a legal start that is merely unfinished, and "
				+ "was refused with: %s") % [allowed])
	# A hopper on a handle has no slot at all, which is the case a single-argument check would miss.
	var no_slot: String = ClassDB.class_call_static(
			"AssaySim", "part_press_refusal", PackedStringArray(["handle"]), "hopper")
	if no_slot == "":
		return _fail("a held frame offers no hopper slot, so that press must be refused")
	return true


## NO PINNED HASH ANYWHERE IN THIS CLIENT. A comment saying "never pin the hash" is not a guard; the
## guard is reading the source. Any 16-hex-digit literal in a `.gd` file is either a pinned state
## hash or looks exactly like one, and both are worth a failing test.
func test_no_gdscript_file_pins_a_hash() -> bool:
	var offenders := []
	for folder in ["res://scripts", "res://tests", "res://tools"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for name in dir.get_files():
			var file := String(name).trim_suffix(".remap")
			if not file.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string("%s/%s" % [folder, file])
			for word in text.replace('"', " ").replace("'", " ").split(" ", false):
				var token := String(word).strip_edges()
				if token.length() == 16 and token.is_valid_hex_number():
					offenders.append("%s: %s" % [file, token])
	if not offenders.is_empty():
		return _fail(("a state hash looks pinned in GDScript: %s. Read it from the sim at runtime "
				+ "instead -- the golden hash changes whenever the rules do.") % [offenders])
	return true


## NOTHING HAS STOPPED IN A WORLD WITH NOTHING IN IT (ASSA-94), asked from the side that can see it.
##
## The Rust half proves the lines come from `World::halted` and that an idle smelter is absent. What
## it cannot prove is any of this: that `halt_lines` survived as a `#[func]` under that name, that it
## crosses as a `PackedStringArray` rather than an Array of something, and that a host which draws
## `size()` lines draws none on a healthy factory. A `PackedStringArray` cannot even be constructed
## in a Rust unit test -- godot-ffi panics with "Godot engine not available" -- so this side is the
## only side.
##
## AND THE EMPTY CASE IS THE ONE WORTH PINNING. The Game Director ruled that a count of zero is never
## drawn, because a surface announcing health cries wolf by the same mechanism `idle: nothing to
## refine` would. The client renders `size()` lines, so "draws nothing" and "the array is empty" are
## the same claim, and this is where it is checked.
## **EVERY DEPOSIT THE MAP DRAWS CARRIES THE SIM'S VERDICT ON WORKING IT** (ASSA-187), and this side
## is the only side that can say so: **a Variant field is invisible from Rust.** I inverted a bool in
## this binding once and all forty Rust tests stayed green, because a `vdict!` entry is not a type
## anything over there checks. A missing key here is worse than a wrong value -- `AssayHud.
## deposit_disc` reads it without a default on purpose, so the schematic would abort its whole frame.
##
## **CHECKED AGAINST THE OTHER PAYLOAD RATHER THAN AGAINST A NUMBER.** `species_sheets()` carries
## `hand_minable` per species and `deposits()` now carries it per deposit; both are supposed to be
## `sim::ladder::hand_minable` on the same roster, so disagreement means one of the two is a second
## opinion about a rule -- which is the defect ASSA-43 is named for. A hardness threshold written here
## would be a third.
##
## THE PREMISE IS THAT THIS WORLD HAS BOTH KINDS. On 777042 six of thirteen deposits are rock nothing
## can mine (the Game Director counted them against `sim-cli deposits`), so a world where every
## deposit answers the same way means worldgen moved under this test and it is proving nothing.
func test_every_deposit_carries_the_sims_own_verdict_on_mining_it() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var sim := AssaySimHost.new()
	if not sim.start(AssaySimHost.fresh_welcome_json("777042", "marlow")):
		return _fail("could not make a world to ask: %s" % sim.fail_reason)
	var by_species := {}
	for entry in sim.species_sheets():
		var species: Dictionary = entry
		by_species[int(species["id"])] = bool(species["hand_minable"])
	var minable := 0
	var dead := 0
	for entry in sim.deposits():
		var deposit: Dictionary = entry
		if not deposit.has("hand_minable"):
			return _fail(("a deposit crossed without `hand_minable`: %s. The schematic reads it "
					+ "with no default, so this is a blank map rather than a wrong one.")
					% [deposit.keys()])
		if typeof(deposit["hand_minable"]) != TYPE_BOOL:
			return _fail("`hand_minable` crossed as %s, not a bool"
					% type_string(typeof(deposit["hand_minable"])))
		var id := int(deposit["species"])
		if not by_species.has(id):
			return _fail("a deposit names species %d, which the roster does not have" % id)
		if bool(deposit["hand_minable"]) != bool(by_species[id]):
			return _fail(("deposit of species %d says minable %s and that species' own sheet says "
					+ "%s. Two surfaces, one rule: one of them is a second opinion.")
					% [id, deposit["hand_minable"], by_species[id]])
		if bool(deposit["hand_minable"]):
			minable += 1
		else:
			dead += 1
	if minable == 0 or dead == 0:
		return _fail(("premise: seed 777042 gave %d minable and %d unminable deposits, so this "
				+ "world cannot tell the two states apart and neither can the assertions above")
				% [minable, dead])
	print("    seed 777042: %d deposits you can work, %d nothing can mine" % [minable, dead])
	return true


func test_a_world_with_nothing_built_reports_nothing_stopped() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var sim := AssaySimHost.new()
	if not sim.start(AssaySimHost.fresh_welcome_json("777042", "marlow")):
		return _fail("could not make a world to ask: %s" % sim.fail_reason)
	var stopped: Variant = sim.halt_lines()
	if typeof(stopped) != TYPE_PACKED_STRING_ARRAY:
		return _fail(("halt_lines crossed as %s, not a PackedStringArray; a host rendering it "
				+ "verbatim would draw something else") % type_string(typeof(stopped)))
	if not (stopped as PackedStringArray).is_empty():
		return _fail(("a world with nothing built reports %s stopped: %s. A surface that speaks "
				+ "when the factory is healthy is the cry-wolf failure one step removed.")
				% [(stopped as PackedStringArray).size(), stopped])
	return true


## **WHAT A REAL PLAYER DICT CARRIES, ASKED OF THE RUNNING BINDING** (ASSA-196).
##
## Marlow found the defect in `main.gd`: five reads of `player.get("id")` / `player.get("pos")` with
## silent defaults, on dicts that come straight out of `AssaySim.players()`. A binding that stopped
## sending `pos` draws every player on the world's corner and nothing anywhere says so -- not the
## renderer's boundary check (by then `at` is composed and present), not a test, not the screen.
##
## **THE RUNNING BINDING AND NOT A FIXTURE, which is the whole point.** A fixture I typed would agree
## with my assumption; a Rust-side guard would pass against a stale `.dylib`, which is the failure
## that has bitten Marlow and me twice this week. This asks the library that is actually loaded.
func test_a_real_player_dict_carries_every_fact_the_client_reads() -> bool:
	if not ClassDB.class_exists("AssaySim"):
		return _fail("no AssaySim class; see the failure above")
	var sim := AssaySimHost.new()
	if not sim.start(AssaySimHost.fresh_welcome_json("777042", "limpet")):
		return _fail("could not make a world to ask: %s" % sim.fail_reason)
	var players: Array = sim.players()
	# A WORLD WITH NO PLAYERS WOULD PASS EVERY LOOP BELOW, so it fails here instead: a fresh welcome
	# carries the joiner, and an empty list means this test measured nothing at all.
	if players.is_empty():
		return _fail("a fresh welcome produced no players, so this test would pass over an empty list")
	var missing := PackedStringArray()
	for i in players.size():
		var player: Dictionary = players[i]
		for fact in AssaySimHost.PLAYER_FACTS:
			if not player.has(fact):
				# NAMED THE WAY `AssayScene.missing_sim_facts` NAMES ITS OWN, so one habit covers both
				# layers: `player[0 of 2].pos` is a thing a reader can act on.
				missing.append("player[%d of %d].%s" % [i, players.size(), String(fact)])
	if not missing.is_empty():
		return _fail(("the binding's player dict is missing %s. `main.gd` reads those with silent "
				+ "defaults, so the window would draw every player on tile (0, 0) and say nothing. "
				+ "The dict it did send: %s") % [", ".join(missing), (players[0] as Dictionary).keys()])
	return true


## **AND THE LIST IS HELD AGAINST THE READER'S SOURCE, so it cannot go stale quietly** (ASSA-196,
## the shape of Marlow's fix for ASSA-141 and of my own CO-6 note).
##
## The test above walks `PLAYER_FACTS`, so a key deleted from `PLAYER_FACTS` is a key it stops asking
## about: the list would be both the subject and the oracle, and dropping `pos` from it would turn the
## guard green over exactly the defect it exists to catch. So this reads the other direction -- every
## `player.get("x")` in `main.gd` must be DECLARED -- and the two together are what make either worth
## running.
##
## A PLAIN SCAN OF THE SOURCE, blunt on purpose (the same reason `test_shipped_scripts.gd` greps for a
## class name): it cannot be fooled by a read made through a variable, and the cost of being blunt is
## that a reader renaming the loop variable escapes it. That is the next hole and it is a cheaper one
## than the hole this closes.
func test_every_player_fact_main_reads_is_declared() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	if source == "":
		return _fail("could not read res://scripts/main.gd, so nothing was scanned")
	var reads := RegEx.new()
	reads.compile("player\\.get\\(\"([a-z_]+)\"")
	var found := PackedStringArray()
	var undeclared := PackedStringArray()
	for hit in reads.search_all(source):
		var key := hit.get_string(1)
		if not found.has(key):
			found.append(key)
		if not AssaySimHost.PLAYER_FACTS.has(key) and not undeclared.has(key):
			undeclared.append(key)
	# THE SCAN ITSELF HAS TO HAVE WORKED. Zero reads found means the regex or the file moved, and an
	# empty set satisfies the check below about nothing -- the quietest green in this file.
	if found.is_empty():
		return _fail(("no player.get(\"...\") reads found in main.gd at all, so this scan proves "
				+ "nothing. The reads moved or the pattern did."))
	if not undeclared.is_empty():
		return _fail(("main.gd reads %s off a player dict and AssaySimHost.PLAYER_FACTS does not "
				+ "declare them, so nothing asks the binding whether they are there: %s is declared, "
				+ "%s is read.") % [", ".join(undeclared), AssaySimHost.PLAYER_FACTS, found])
	return true
