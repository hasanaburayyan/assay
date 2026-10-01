extends RefCounted
## THE WIRE, HELD TO `sim-net/src/lib.rs` -- including by reading that file.
##
## Two different jobs here. One is ordinary: frame a message, get it back. The other is the one that
## actually bites, because it spans two languages: a client on the wrong `PROTOCOL_VERSION` is
## refused by the relay with a message that names both numbers and neither side's staleness, and the
## only way that number stays right is for a test to read the Rust constant rather than trust a copy.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## THE CONTROL FOR EVERYTHING ELSE: a message framed by this client is read back as the same message.
func test_a_message_survives_its_own_framing() -> bool:
	var msg := AssayProtocol.hello("ada")
	var reader := AssayFrameReader.new()
	reader.feed(AssayProtocol.encode(msg))
	var back: Variant = reader.next_message()
	if typeof(back) != TYPE_DICTIONARY:
		return _fail("a framed Hello came back as %s" % type_string(typeof(back)))
	var body: Dictionary = (back as Dictionary).get("Hello", {})
	if String(body.get("name", "")) != "ada":
		return _fail("the name did not survive: %s" % back)
	if int(body.get("protocol", -1)) != AssayProtocol.PROTOCOL_VERSION:
		return _fail("the protocol number did not survive: %s" % back)
	if reader.pending_bytes() != 0:
		return _fail("%d bytes left over after one message" % reader.pending_bytes())
	return true


## BIG-ENDIAN, AND THAT IS NOT GODOT'S DEFAULT. `encode_u32` writes little-endian, so a 4-byte body
## would announce itself as 67108864 and the relay would wait forever for 64 MB. Asserted on the
## bytes, because this is exactly the sort of mistake that looks fine until it is on a socket.
func test_the_length_prefix_is_big_endian() -> bool:
	var frame := AssayProtocol.encode({"Hash": {"tick": 1, "hash": "2"}})
	var body_size := frame.size() - 4
	var want := PackedByteArray([
		(body_size >> 24) & 0xff, (body_size >> 16) & 0xff, (body_size >> 8) & 0xff, body_size & 0xff])
	for i in 4:
		if frame[i] != want[i]:
			return _fail("length prefix is %s, big-endian would be %s" % [
					Array(frame.slice(0, 4)), Array(want)])
	if frame[0] != 0 or frame[1] != 0:
		return _fail("a short message's length should start with two zero bytes, got %s"
				% Array(frame.slice(0, 4)))
	return true


## A `Welcome` CARRIES A WHOLE WORLD AND WILL NOT ARRIVE IN ONE READ. Fed one byte at a time, which
## is the worst case the reader has to survive: no message until the last byte, then exactly one.
func test_a_message_split_anywhere_is_reassembled() -> bool:
	var frame := AssayProtocol.encode({"Tick": {"tick": 7, "inputs": []}})
	var reader := AssayFrameReader.new()
	for i in frame.size():
		var got: Variant = reader.next_message()
		if got != null:
			return _fail("a message appeared after %d of %d bytes" % [i, frame.size()])
		reader.feed(frame.slice(i, i + 1))
	var msg: Variant = reader.next_message()
	if typeof(msg) != TYPE_DICTIONARY:
		return _fail("the message did not appear once every byte was in")
	if int(((msg as Dictionary).get("Tick", {}) as Dictionary).get("tick", -1)) != 7:
		return _fail("reassembled into the wrong message: %s" % msg)
	if reader.next_message() != null or reader.error != "":
		return _fail("a second message appeared out of one message's bytes")
	return true


## TWO MESSAGES IN ONE READ, which is what `nodelay` plus a 10-tick clock produces.
func test_two_messages_in_one_read_come_out_in_order() -> bool:
	var reader := AssayFrameReader.new()
	var buf := AssayProtocol.encode({"Tick": {"tick": 1, "inputs": []}})
	buf.append_array(AssayProtocol.encode({"Tick": {"tick": 2, "inputs": []}}))
	reader.feed(buf)
	var ticks := []
	while true:
		var msg: Variant = reader.next_message()
		if msg == null:
			break
		ticks.append(int(((msg as Dictionary)["Tick"] as Dictionary)["tick"]))
	if ticks != [1, 2]:
		return _fail("read %s, expected ticks 1 then 2" % [ticks])
	return true


## sim-net refuses a length past its own limit rather than allocating it; so does this.
func test_an_impossible_length_kills_the_stream() -> bool:
	var reader := AssayFrameReader.new()
	var huge := AssayProtocol.MAX_MESSAGE_BYTES + 1
	reader.feed(PackedByteArray([(huge >> 24) & 0xff, (huge >> 16) & 0xff, (huge >> 8) & 0xff,
			huge & 0xff]))
	reader.feed("{}".to_utf8_buffer())
	if reader.next_message() != null:
		return _fail("a 64 MB+ message was accepted")
	if reader.error == "":
		return _fail("an impossible length left no error, so the client would keep reading garbage")
	return true


## Garbage in a body is not a message to skip: the next length prefix cannot be found, so the stream
## is over. Reported rather than silently resynced.
func test_a_body_that_is_not_json_kills_the_stream() -> bool:
	var reader := AssayFrameReader.new()
	var body := "not json".to_utf8_buffer()
	reader.feed(PackedByteArray([0, 0, 0, body.size()]))
	reader.feed(body)
	if reader.next_message() != null:
		return _fail("non-JSON was accepted as a message")
	if reader.error == "":
		return _fail("a non-JSON body left no error")
	return true


## THE CROSS-LANGUAGE GUARD, AND THE REASON THIS FILE EXISTS. `PROTOCOL_VERSION` is declared in
## Rust; this client keeps a copy because GDScript cannot read a Rust const at runtime. A copy
## without a test is a copy that goes stale, and the failure it causes is a refused join whose
## message blames neither side.
func test_the_protocol_number_is_the_one_rust_declares() -> bool:
	var path := "res://%s" % AssayProtocol.RUST_PROTOCOL_PATH
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		# Not a skip: if the client moves relative to the Rust crate, this guard stops working and
		# that is the thing to report.
		return _fail(("cannot read %s, so the protocol number is unchecked -- if the client moved, "
				+ "fix AssayProtocol.RUST_PROTOCOL_PATH") % path)
	var src := file.get_as_text()
	file.close()
	var re := RegEx.create_from_string("PROTOCOL_VERSION\\s*:\\s*u32\\s*=\\s*([0-9]+)")
	var m := re.search(src)
	if m == null:
		return _fail("no `PROTOCOL_VERSION: u32 = N` in %s: this guard is measuring nothing" % path)
	var rust := int(m.get_string(1))
	if rust != AssayProtocol.PROTOCOL_VERSION:
		return _fail(("sim-net declares PROTOCOL_VERSION %d and this client sends %d. The relay "
				+ "refuses mismatched clients, so this is a join that fails with no useful error.")
				% [rust, AssayProtocol.PROTOCOL_VERSION])
	# And the limit, for the same reason: it decides which lengths this client calls garbage.
	var limit := RegEx.create_from_string("MAX_MESSAGE_BYTES\\s*:\\s*u32\\s*=\\s*([0-9*\\s]+);")
	var lm := limit.search(src)
	if lm == null:
		return _fail("no MAX_MESSAGE_BYTES in %s" % path)
	var expr := lm.get_string(1).strip_edges()
	var product := 1
	for bit in expr.split("*"):
		product *= int(bit.strip_edges())
	if product != AssayProtocol.MAX_MESSAGE_BYTES:
		return _fail("sim-net's message limit is %d and this client uses %d"
				% [product, AssayProtocol.MAX_MESSAGE_BYTES])
	return true


## A bare host takes 7777, the way `sim-cli` does it.
func test_an_address_without_a_port_takes_the_default() -> bool:
	for pair in [["localhost", "localhost", AssayProtocol.DEFAULT_PORT],
			["10.0.0.4:9000", "10.0.0.4", 9000],
			["  host.lan  ", "host.lan", AssayProtocol.DEFAULT_PORT],
			["[::1]:9", "::1", 9],
			["[fe80::1]", "fe80::1", AssayProtocol.DEFAULT_PORT]]:
		var got := AssayProtocol.split_address(String(pair[0]))
		if String(got[0]) != String(pair[1]) or int(got[1]) != int(pair[2]):
			return _fail("%s split to %s, expected [%s, %d]" % [pair[0], got, pair[1], pair[2]])
	return true


## A serde enum is a one-key object. Anything else is a protocol mismatch, and the client must say
## so rather than guess which variant was meant.
func test_only_a_one_key_object_is_a_message() -> bool:
	var ok := AssayProtocol.variant_of({"Tick": {"tick": 3, "inputs": []}})
	if String(ok[0]) != "Tick" or int((ok[1] as Dictionary)["tick"]) != 3:
		return _fail("a Tick bundle did not read as one: %s" % [ok])
	for bad in [{"Tick": {}, "Desync": {}}, {}, [], "Tick", 4, null]:
		var got := AssayProtocol.variant_of(bad)
		if String(got[0]) != "":
			return _fail("%s was read as the message %s" % [bad, got[0]])
	return true
