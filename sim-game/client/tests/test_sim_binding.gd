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
	# The scripted demo session's two: the pair the world guarantees, and serde's own spelling of an
	# item, which is what the session's commands are checked against.
	"starter_pair", "item_json", "item_echo",
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
