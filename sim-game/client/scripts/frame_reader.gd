class_name AssayFrameReader
extends RefCounted
## BYTES ARRIVE IN WHATEVER SIZES THE NETWORK FELT LIKE, and a message is only a message once all
## of it is here. This holds the half-arrived one.
##
## `read_msg` in `sim-net` can block on a socket until the rest turns up; a Godot client polls, so
## the same job becomes a buffer: feed it whatever `get_partial_data` returned, then ask for
## messages until it says there are none. A `Welcome` carries a whole `World` and will not arrive
## in one read.
##
## NO SOCKET AND NO RULES IN HERE EITHER, so a test can drive it with a byte array -- including the
## case that matters, a message split at an awkward place.

## Everything fed in that is not a complete message yet.
var _buffer := PackedByteArray()
## THE EXACT TEXT OF THE MESSAGE `next_message` JUST RETURNED, which is what the Rust sim has to be
## given. Not a convenience: by the time you are holding the parsed Dictionary, GODOT HAS ALREADY
## TURNED EVERY NUMBER INTO A DOUBLE, so a `u64` world seed or a hash in it is already wrong and
## re-serialising the Dictionary would hand the sim that damage as if it were the host's. The sim is
## fed this string instead, and the Dictionary is only ever used for drawing.
var last_text := ""
## Set when the stream is no longer trustworthy: a length past `MAX_MESSAGE_BYTES`, or JSON that
## will not parse. Both mean "stop reading this connection", not "skip this message".
var error := ""


func feed(bytes: PackedByteArray) -> void:
	if bytes.size() > 0:
		_buffer.append_array(bytes)


## The next complete message, or `null` if the rest of it has not arrived. Check `error` after a
## `null`: a fatal stream problem also answers `null`.
func next_message() -> Variant:
	if error != "":
		return null
	if _buffer.size() < 4:
		return null
	# Big-endian, matching `u32::to_be_bytes`.
	var length: int = (int(_buffer[0]) << 24) | (int(_buffer[1]) << 16) \
			| (int(_buffer[2]) << 8) | int(_buffer[3])
	if length > AssayProtocol.MAX_MESSAGE_BYTES:
		error = ("the host announced a %d-byte message, past sim-net's %d-byte limit: this is not "
				+ "a relay on protocol %d") % [length, AssayProtocol.MAX_MESSAGE_BYTES,
				AssayProtocol.PROTOCOL_VERSION]
		return null
	if _buffer.size() < 4 + length:
		return null
	var body := _buffer.slice(4, 4 + length)
	_buffer = _buffer.slice(4 + length)
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		# A ServerMsg is never literally `null`, so this is a parse failure and the stream is lost:
		# we cannot know where the next length prefix starts if this body was not what it claimed.
		error = "the host sent %d bytes that are not JSON" % length
		return null
	last_text = text
	return parsed


## How many bytes are waiting for the rest of their message. For a probe's own report, and for the
## test that proves a split message is reassembled rather than dropped.
func pending_bytes() -> int:
	return _buffer.size()
