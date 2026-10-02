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
const PROTOCOL_VERSION := 5
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
## echoed through GDScript. When the Rust sim is bound into this client, hashes must come from the
## binding as text or as its own u64 type and never through a parsed JSON number.


## One message, framed. `msg` is the already-tagged dictionary, e.g. `{"Hello": {...}}`.
static func encode(msg: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(msg).to_utf8_buffer()
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


## "After running up to `tick`, my world hashes to `hash`."
##
## UNUSABLE UNTIL THE SIM ITSELF IS IN THE CLIENT, and that is a fact about this client rather
## than about the message: a hash is `sim::hash`'s answer over a world this client stepped, so
## there is nothing honest to put here until the Rust sim is bound in. Worse, `hash` is a u64 and
## GDScript integers are signed 64-bit, so a hash above 2^63 cannot even be spelled here. When the
## binding lands, the number must come out of the sim as text or as the binding's own u64 -- never
## through a GDScript int. Left in so the shape is recorded in one place, with the trap named.
static func hash_report(tick: int, hash_text: String) -> Dictionary:
	return {"Hash": {"tick": tick, "hash": hash_text}}


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
