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
## IT CHECKS THIS CLIENT'S OWN WIRING ONLY -- framing, address parsing, the net node constructing.
## No game rule is evaluated: rules live in the `sim` crate and this stays a view.

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

	return failures
