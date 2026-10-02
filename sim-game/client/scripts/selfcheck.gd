class_name AssaySelfCheck
extends RefCounted
## DOES THE EXPORTED BUILD ACTUALLY WORK? `Assay --headless -- --selfcheck <file>` answers.
##
## CI exports Mac and Windows, and "the zip is not empty" is not evidence. An export can succeed and
## still ship a pack whose scripts will not load, and GODOT EXITS 0 ON A SCRIPT THAT FAILED TO
## COMPILE, so neither the exit code nor a file listing can be trusted on its own. This writes a
## marker as the LAST line of a file and CI greps for that line. No marker, no pass -- a run that
## died halfway cannot leave something that looks like a pass.
##
## This is also the only way the Windows artifact gets checked at all: nobody here has a Windows
## machine, but the Windows runner can run what it just built.
##
## IT CHECKS THIS CLIENT'S OWN WIRING -- framing, address parsing, the net node constructing, and
## that the `sim-godot` library loaded and can step the real sim. No game rule is evaluated HERE:
## rules live in the `sim` crate, this stays a view, and the hash it compares is computed by that
## crate at runtime and never written down in GDScript.

const MARKER := "CLIENT SELFCHECK OK"
const FAILED := "CLIENT SELFCHECK FAILED"
## Passed after a bare `--`, so the engine never sees an argument it would reject.
const FLAG := "--selfcheck"


## The file CI asked for, or "" on a normal run by a player.
static func requested_path() -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(FLAG)
	if at < 0 or at + 1 >= args.size():
		return ""
	return args[at + 1]


## Every check, then the marker file. Returns the process exit code: 0 only if everything passed.
static func run(path: String) -> int:
	var failures := check()
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("selfcheck could not write %s (error %d)" % [path, FileAccess.get_open_error()])
		return 1
	for reason in failures:
		out.store_line("FAIL: %s" % reason)
	out.store_line(MARKER if failures.is_empty() else FAILED)
	out.close()
	return 0 if failures.is_empty() else 1


## The checks themselves, so the suite can run them on the source tree too.
static func check() -> Array[String]:
	var failures: Array[String] = []

	# A Hello survives encode -> frame reader -> decode, fed in two pieces because that is the case
	# that bites on a real socket. Framing is the one part of this client that must be byte-exact
	# with Rust, so it is worth re-proving in the shipped build and not only in the source tree.
	var framed := AssayProtocol.encode(AssayProtocol.hello("selfcheck"))
	var reader := AssayFrameReader.new()
	reader.feed(framed.slice(0, 2))
	if reader.next_message() != null:
		failures.append("the frame reader answered a message from 2 bytes")
	reader.feed(framed.slice(2))
	var back: Variant = reader.next_message()
	if typeof(back) != TYPE_DICTIONARY:
		failures.append("a framed Hello came back as %s" % type_string(typeof(back)))
	else:
		var variant := AssayProtocol.variant_of(back)
		var body: Dictionary = variant[1] if typeof(variant[1]) == TYPE_DICTIONARY else {}
		if String(variant[0]) != "Hello":
			failures.append("a Hello came back tagged %s" % variant[0])
		if String(body.get("name", "")) != "selfcheck":
			failures.append("the name did not survive framing: %s" % body.get("name", "<missing>"))
		if int(body.get("protocol", -1)) != AssayProtocol.PROTOCOL_VERSION:
			failures.append("protocol came back as %s, not %d"
					% [body.get("protocol", "<missing>"), AssayProtocol.PROTOCOL_VERSION])
	if reader.error != "":
		failures.append("the frame reader errored: %s" % reader.error)

	# The front door. A tester who types a bare hostname has to reach the default port, or the
	# build is useless to the person it was built for.
	var bare := AssayProtocol.split_address("relay.example")
	if String(bare[0]) != "relay.example" or int(bare[1]) != AssayProtocol.DEFAULT_PORT:
		failures.append("a bare address parsed as %s, not the default port" % [bare])
	var explicit := AssayProtocol.split_address("relay.example:7000")
	if String(explicit[0]) != "relay.example" or int(explicit[1]) != 7000:
		failures.append("host:port parsed as %s" % [explicit])

	var client := AssayNetClient.new()
	if client == null:
		failures.append("AssayNetClient would not construct")
	else:
		client.free()

	failures.append_array(binding_failures())
	return failures


## DID THE SIM BINDING LOAD, AND DOES IT STEP THE REAL RULES?
##
## A `TickBundle` carries inputs, not state, so the world at tick N exists only once something runs
## `sim::step`. That something is the `sim-godot` cdylib (`sim.gdextension`), never GDScript. If the
## library is missing the client is a picture of a game: it can draw tick 0 and nothing after. So
## this is a failure, not a warning.
##
## Reached through `ClassDB` ON PURPOSE. Naming `AssaySim` as an identifier when the extension did
## not load is a PARSE error, which kills this whole script, and Godot exits 0 on that -- the run
## would leave no marker and no reason. This way a missing library prints which line it was.
static func binding_failures() -> Array[String]:
	var failures: Array[String] = []
	if not ClassDB.class_exists("AssaySim"):
		failures.append(
			"the sim binding did not load: no AssaySim class. Build it first -- "
			+ "`cargo build -p sim-godot --release` then copy the library into client/bin/ "
			+ "(see sim.gdextension). CI builds it per platform before every export."
		)
		return failures

	# TWO ROUTES TO ONE NUMBER. `binding_self_check` steps a small world through the binding's own
	# class; `binding_self_check_expected` calls `sim::step` directly with no class in the way. Both
	# compute it from the sim at runtime -- NOTHING HERE IS PINNED, because the golden hash moved
	# twice on 2026-10-01 and a constant in GDScript would have to be chased every time the rules
	# change. What this proves is the library loaded, registered, generated a world and stepped it.
	var got := String(ClassDB.class_call_static("AssaySim", "binding_self_check"))
	var want := String(ClassDB.class_call_static("AssaySim", "binding_self_check_expected"))
	if got != want:
		failures.append("the binding stepped to %s, the sim to %s" % [got, want])
	# A hash crosses as HEX TEXT and never as a number: Godot parses every JSON number as a double
	# and a u64 hash cannot be spelled in GDScript at all. An empty or zero string is what a failed
	# call looks like, so the shape is checked too rather than trusting the comparison above.
	if got.length() != 16 or not got.is_valid_hex_number():
		failures.append("the binding's hash is not 16 hex digits: '%s'" % got)
	# Built, not written out: a 16-hex-digit literal in a `.gd` file is what a pinned golden hash
	# looks like, and `test_sim_binding.gd` fails the suite on any of them, this one included.
	elif got == "0".repeat(16):
		failures.append("the binding returned a zero hash, which is not evidence")
	return failures
