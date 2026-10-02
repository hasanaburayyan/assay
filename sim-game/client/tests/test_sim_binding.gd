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
