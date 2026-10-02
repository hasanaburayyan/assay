class_name AssayNetClient
extends Node
## THE LINK TO A RELAY: connect, say hello, be welcomed, then hand every tick bundle onward.
##
## The same handshake `sim-cli/src/net.rs` does, in one polled node instead of two threads: connect,
## write `Hello`, and the first message back is `Welcome` (take the world) or `Refused` (say why).
##
## WHAT THIS NODE DOES NOT DO, AND MUST NEVER DO: apply a tick bundle. A bundle carries INPUTS, not
## state, so the only way to know the world at tick N is to run the sim over them -- and the sim is
## the Rust `sim` crate, which no line of GDScript may reimplement (principle 1). So this node
## reports bundles and keeps count; `AssaySimHost` holds the sim and applies them.
##
## EVERY SIGNAL CARRIES THE RAW TEXT OF THE MESSAGE AS WELL AS THE PARSED DICTIONARY, and the two are
## not interchangeable. The sim is fed the TEXT, because Godot's JSON has already turned every number
## into a double by the time the Dictionary exists -- a `u64` seed in it is already wrong. The
## Dictionary is for showing things to a person.
##
## Reconnect is deliberately absent (Decision 3): a dropped client restarts to rejoin.

## Accepted: our slot, the world to start from, and the message's own text for the sim. The next
## bundle is for `world.tick`.
signal welcomed(player: int, world: Dictionary, raw: String)
## The relay said no. The connection is closed after this.
signal refused(reason: String)
## One tick's inputs, in the order every peer must apply them, plus the message's own text.
signal tick_bundle(tick: int, inputs: Array, raw: String)
## Our hash for `tick` did not match the host's. Unrecoverable in the demo: restart to rejoin.
signal desynced(tick: int)
## The socket never came up, or died. `reason` is for a player to read.
signal link_failed(reason: String)
## Narration for the console / a probe's stdout.
signal note(line: String)
## EVERY COMMAND THE UI ASKED THIS CLIENT TO SUBMIT, whether or not it reached a socket.
##
## Emitted before the stage check on purpose, and for two reasons. A test can press a REAL button and
## see what it would send with no relay in the room, which is the only way ASSA-37's "no client-only
## command path" is checkable at all. And a command the UI asked for but could not send is itself the
## thing worth seeing: it is a button that looked like it worked.
signal asked(command: Variant)

enum Stage { IDLE, CONNECTING, GREETED, JOINED, DEAD }

var stage: Stage = Stage.IDLE
## Our slot in the world, once welcomed. -1 while unknown; `PlayerId` is a slot, not an identity.
var player_id := -1
## The world as it was at the tick we joined. NOT kept up to date -- see the note above.
var joined_world: Dictionary = {}
## Bundles seen since the join, and the last tick the relay sent. Evidence that the link is live
## even before anything can be applied.
var bundles_seen := 0
var last_tick := -1

var _socket := StreamPeerTCP.new()
var _reader := AssayFrameReader.new()
var _name := ""
var _where := ""
## No socket: see `play_offline`.
var _offline := false


func _ready() -> void:
	set_process(true)


## Start joining. `address` is "host", "host:port" or "[v6]:port"; a bare address takes 7777.
func join(address: String, player_name: String) -> void:
	_name = player_name
	# THE WIRE'S NUMBER COMES FROM RUST, so a client that cannot ask does not join. Saying hello with
	# an invented protocol number gets refused by the relay with a message that blames neither side,
	# and this client could not have simulated a tick anyway -- the same missing library is why.
	if AssayProtocol.protocol_version() == AssayProtocol.UNKNOWN_PROTOCOL:
		_fail(("the sim binding did not load, so this client does not know which protocol it speaks "
				+ "or how to run a tick. Build it with `make client-lib`."))
		return
	var split := AssayProtocol.split_address(address)
	var host: String = split[0]
	var port: int = split[1]
	_where = "%s:%d" % [host, port]
	if host == "":
		_fail("no host address given")
		return
	var err := _socket.connect_to_host(host, port)
	if err != OK:
		_fail("could not reach %s: %s" % [_where, error_string(err)])
		return
	stage = Stage.CONNECTING
	note.emit("connecting to %s as %s" % [_where, _name])


## Ask the relay to schedule a command. Safe to call only once joined; a command sent before the
## welcome would reach a relay that has not stamped us a player yet.
func submit(command: Variant) -> bool:
	asked.emit(command)
	if stage != Stage.JOINED:
		note.emit("not joined, so nothing was submitted")
		return false
	return _write(AssayProtocol.submit(command))


## Send a message somebody else already wrote as JSON.
##
## For `ClientMsg::Hash`, which the sim binding serialises because GDScript cannot spell a `u64` (see
## `protocol.gd`). This frames the text and writes it; it does not look inside.
func send_text(json_text: String) -> bool:
	if stage != Stage.JOINED:
		note.emit("not joined, so nothing was sent")
		return false
	if json_text == "":
		note.emit("refusing to send an empty message")
		return false
	# OFFLINE THIS IS FALSE, AND THAT IS THE HONEST ANSWER, unlike `submit` above. A command submitted
	# offline does take effect -- the caller delivers it in its own bundle -- but a hash report
	# offline has no recipient and nothing compares it to anything, so "0 hashes reported" is what the
	# HUD should say.
	if _offline:
		note.emit("offline, so no hash report was sent")
		return false
	var frame := AssayProtocol.encode_text(json_text)
	var err := _socket.put_data(frame)
	if err != OK:
		_fail("could not send to %s: %s" % [_where, error_string(err)])
		return false
	return true


## PLAY WITH NO SOCKET: the same client, fed by hand.
##
## For the headless suite and `tools/button_session.gd`. NOT A SINGLE-PLAYER MODE and not a second
## way to act: there is no clock behind it, so whoever turns this on has to write the tick bundles
## itself, which is precisely the relay's job and precisely what makes this a harness.
##
## WHAT STAYS REAL IS EVERYTHING BUT THE SOCKET. `feed_offline` pushes a message through the actual
## frame reader and the actual `_handle`, so the framing, the Welcome and every bundle run the code a
## joined client runs; `submit` is the same `submit`, down to the `asked` signal. Only `_write` has
## nowhere to go. That matters because the whole point of the button tests is that there is ONE
## command path, and a harness with its own would prove nothing about the real one.
func play_offline() -> void:
	_offline = true
	_where = "offline"
	note.emit("playing offline: no socket, and the caller owns the clock")


## One message, as if it had arrived off the wire. Framed first so the reader does its real work.
func feed_offline(json_text: String) -> void:
	if not _offline:
		push_error("feed_offline on a client that is not offline; call play_offline() first")
		return
	_reader.feed(AssayProtocol.encode_text(json_text))
	while true:
		var msg: Variant = _reader.next_message()
		if msg == null:
			if _reader.error != "":
				_fail(_reader.error)
			return
		_handle(msg)
		if stage == Stage.DEAD:
			return


func _process(_delta: float) -> void:
	if _offline or stage == Stage.IDLE or stage == Stage.DEAD:
		return
	_socket.poll()
	var status := _socket.get_status()
	if status == StreamPeerTCP.STATUS_ERROR:
		_fail("the connection to %s failed" % _where)
		return
	if status == StreamPeerTCP.STATUS_NONE:
		_fail("%s closed the connection" % _where)
		return
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	if stage == Stage.CONNECTING:
		# CONNECTED, so greet. `set_no_delay` for the same reason `sim-cli` sets `nodelay`: a
		# lockstep peer sends tiny messages and Nagle would sit on them for a tick.
		_socket.set_no_delay(true)
		if not _write(AssayProtocol.hello(_name)):
			return
		stage = Stage.GREETED
		note.emit("said hello on protocol %d" % AssayProtocol.protocol_version())

	var available := _socket.get_available_bytes()
	if available > 0:
		var chunk: Array = _socket.get_partial_data(available)
		if chunk[0] != OK:
			_fail("lost the connection to %s while reading" % _where)
			return
		_reader.feed(chunk[1])
	while true:
		var msg: Variant = _reader.next_message()
		if msg == null:
			if _reader.error != "":
				_fail(_reader.error)
			return
		_handle(msg)
		if stage == Stage.DEAD:
			return


func _handle(msg: Variant) -> void:
	var tagged := AssayProtocol.variant_of(msg)
	var kind: String = tagged[0]
	var body: Variant = tagged[1]
	# The bytes this message arrived as. Taken before anything else, because `_handle` may be given a
	# dictionary directly by a test, in which case there is no text and the sim is not involved.
	var raw := _reader.last_text
	match kind:
		"Welcome":
			var world: Dictionary = (body as Dictionary).get("world", {})
			player_id = int((body as Dictionary).get("player", -1))
			joined_world = world
			last_tick = int(world.get("tick", -1))
			stage = Stage.JOINED
			welcomed.emit(player_id, world, raw)
		"Refused":
			var reason := String((body as Dictionary).get("reason", "no reason given"))
			stage = Stage.DEAD
			_socket.disconnect_from_host()
			refused.emit(reason)
		"Tick":
			var bundle: Dictionary = body as Dictionary
			bundles_seen += 1
			last_tick = int(bundle.get("tick", last_tick))
			tick_bundle.emit(last_tick, bundle.get("inputs", []), raw)
		"Desync":
			desynced.emit(int((body as Dictionary).get("tick", -1)))
		_:
			# A message we do not know is a protocol mismatch, not noise to skip: the relay and this
			# client disagree about what the wire looks like, and pretending otherwise desyncs.
			_fail("%s sent a message this client does not know: %s" % [_where, kind])


func _write(msg: Dictionary) -> bool:
	# OFFLINE THE COMMAND STILL HAPPENS: the caller is going to deliver it in a bundle of its own, so
	# reporting success here is true. See `play_offline`, and `send_text` for the case where it is not.
	if _offline:
		return true
	var frame := AssayProtocol.encode(msg)
	var err := _socket.put_data(frame)
	if err != OK:
		_fail("could not send to %s: %s" % [_where, error_string(err)])
		return false
	return true


func _fail(reason: String) -> void:
	if stage == Stage.DEAD:
		return
	stage = Stage.DEAD
	_socket.disconnect_from_host()
	link_failed.emit(reason)
