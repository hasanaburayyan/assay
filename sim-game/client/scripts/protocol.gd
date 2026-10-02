class_name AssayProtocol
extends RefCounted
## THE WIRE, AND NOTHING ELSE: framing and message shapes, no socket and no rules.
##
## `sim-net/src/lib.rs` is the authority for every line in this file. Framing is a 4-byte
## BIG-ENDIAN length followed by that many bytes of JSON, and the messages are Rust enums
## serialised by serde in its default externally-tagged form -- a variant becomes a one-key object:
##
##   ClientMsg::Hello { name, protocol }  ->  {"Hello": {"name": "ada", "protocol": 4}}
##   ClientMsg::Submit { command }        ->  {"Submit": {"command": {...}}}
##   ClientMsg::Hash { tick, hash }       ->  {"Hash": {"tick": 20, "hash": 123}}
##   ServerMsg::Welcome { player, world } ->  {"Welcome": {"player": 0, "world": {...}}}
##   ServerMsg::Refused { reason }        ->  {"Refused": {"reason": "..."}}
##   ServerMsg::Tick(TickBundle)          ->  {"Tick": {"tick": 7, "inputs": [...]}}
##   ServerMsg::Desync { tick }           ->  {"Desync": {"tick": 5}}
##
## `PlayerId(0)` is a newtype struct, so it is the bare number `0` and not `{"0": ...}`.
##
## NO SOCKET IN HERE ON PURPOSE. Bytes in, dictionaries out, so the whole protocol is testable
## headless with no relay running -- which is how `tests/test_protocol.gd` holds it.
const PROTOCOL_VERSION := 4
const DEFAULT_PORT := 7777
## `sim_net::MAX_MESSAGE_BYTES`. A length past this is garbage or a hostile peer, never a world.
const MAX_MESSAGE_BYTES := 64 * 1024 * 1024
## Where the number above is written down in Rust. The test reads this file rather than trusting
## the constant: a client on the wrong protocol is refused by the relay, and the error a player
## would see ("refused: protocol 4 != 5") says nothing about which side is stale.
const RUST_PROTOCOL_PATH := "../sim-net/src/lib.rs"


## GODOT'S JSON PARSES EVERY NUMBER AS A DOUBLE, AND THE SIM SPEAKS u64. Measured, not feared: a
## world hosted on seed 777001 arrives here as `777001.0`. Inside 2^53 that is lossless and `int()`
## is enough, which covers ticks, tile positions, amounts and purities. Outside it -- a full-width
## u64 seed, and every state hash -- a double silently rounds, so neither may be read, compared or
## echoed through GDScript. The sim is bound in now, so the rule has somewhere to point: a hash
## reaches this side only as HEX TEXT (`AssaySim.hash_hex()`) and leaves it only inside a message
## Rust wrote (`AssaySim.hash_message_json()`, framed by `encode_text` below). THE RAW TEXT OF AN
## INCOMING MESSAGE IS WHAT THE SIM IS FED, never a re-serialised Dictionary: the Dictionary has
## already been through a double by the time anyone here can see it.


## One message, framed. `msg` is the already-tagged dictionary, e.g. `{"Hello": {...}}`.
static func encode(msg: Dictionary) -> PackedByteArray:
	return encode_text(JSON.stringify(msg))


## The same framing around JSON TEXT SOMEONE ELSE WROTE.
##
## For the one message GDScript cannot build: `ClientMsg::Hash` carries a `u64`, GDScript's integers
## are signed, and `JSON.stringify` would print whatever a double made of it. So the sim binding
## serialises that message in Rust and this frames the result without reading it. Framing is the
## same job either way; only the authorship of the body differs.
static func encode_text(json_text: String) -> PackedByteArray:
	var body := json_text.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(4)
	# BIG-ENDIAN, which is not Godot's default for `encode_u32`: the length is written by
	# `u32::to_be_bytes` on the Rust side, so a little-endian 4 would arrive as 67108864.
	out.encode_u32(0, body.size())
	out.reverse()
	out.append_array(body)
	return out


static func hello(player_name: String) -> Dictionary:
	return {"Hello": {"name": player_name, "protocol": PROTOCOL_VERSION}}


## A command the player is asking for. The relay stamps WHO sent it -- there is deliberately no
## player field here and no way to send a `SystemCommand` (sim-net's own note).
static func submit(command: Variant) -> Dictionary:
	return {"Submit": {"command": command}}


## THERE IS DELIBERATELY NO `hash_report()` HERE, and that is the interesting part of this file.
##
## `ClientMsg::Hash { tick: u64, hash: u64 }` is the one message this client sends that GDScript
## cannot build. The relay compares `hash` for equality against its own, and GDScript's integers are
## signed 64-bit: a hash with the top bit set cannot be spelled here at all, and `JSON.stringify`
## would print whatever a double made of it. A string in that field is not the answer either -- serde
## would refuse it, so the relay would drop the connection.
##
## So the sim binding writes the whole message in Rust (`AssaySim.hash_message_json()`) and
## `encode_text()` above frames it. An earlier version of this file had a `hash_report(tick,
## hash_text)` helper that produced `{"Hash": {"hash": "95f4..."}}`; it was never called, and it was
## wrong -- recorded here so nobody adds it back out of symmetry with `hello` and `submit`.


## "host", "host:port" or an IPv6 literal in brackets -> [address, port]. Mirrors `sim-cli`'s rule:
## a bare address takes the default port.
static func split_address(raw: String) -> Array:
	var text := raw.strip_edges()
	if text.begins_with("["):
		var close := text.find("]")
		if close > 0:
			var host := text.substr(1, close - 1)
			var rest := text.substr(close + 1)
			if rest.begins_with(":") and rest.length() > 1:
				return [host, int(rest.substr(1))]
			return [host, DEFAULT_PORT]
	var bits := text.split(":")
	if bits.size() == 2 and bits[1] != "":
		return [bits[0], int(bits[1])]
	return [text, DEFAULT_PORT]


## WHICH VARIANT IS THIS, and its payload. Returns `["", null]` for anything that is not a
## one-key object, because that is the only shape serde produces and a message of another shape is
## a protocol mismatch we should report rather than guess at.
static func variant_of(msg: Variant) -> Array:
	if typeof(msg) != TYPE_DICTIONARY:
		return ["", null]
	var keys: Array = (msg as Dictionary).keys()
	if keys.size() != 1:
		return ["", null]
	return [String(keys[0]), (msg as Dictionary)[keys[0]]]
