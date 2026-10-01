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
## reports bundles and keeps count; whoever holds the sim applies them. Until that binding exists
## the client can show the joined snapshot and nothing newer, and `tick_bundle` is where the sim
## gets wired in, not where a second rules engine grows.
##
## Reconnect is deliberately absent (Decision 3): a dropped client restarts to rejoin.

## Accepted: our slot, and the world to start from. The next bundle is for `world.tick`.
signal welcomed(player: int, world: Dictionary)
## The relay said no. The connection is closed after this.
signal refused(reason: String)
## One tick's inputs, in the order every peer must apply them.
signal tick_bundle(tick: int, inputs: Array)
## Our hash for `tick` did not match the host's. Unrecoverable in the demo: restart to rejoin.
signal desynced(tick: int)
## The socket never came up, or died. `reason` is for a player to read.
signal link_failed(reason: String)
## Narration for the console / a probe's stdout.
signal note(line: String)

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


func _ready() -> void:
	set_process(true)


## Start joining. `address` is "host", "host:port" or "[v6]:port"; a bare address takes 7777.
func join(address: String, player_name: String) -> void:
	_name = player_name
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
	if stage != Stage.JOINED:
		note.emit("not joined, so nothing was submitted")
		return false
	return _write(AssayProtocol.submit(command))


func _process(_delta: float) -> void:
	if stage == Stage.IDLE or stage == Stage.DEAD:
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
		note.emit("said hello on protocol %d" % AssayProtocol.PROTOCOL_VERSION)

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
	match kind:
		"Welcome":
			var world: Dictionary = (body as Dictionary).get("world", {})
			player_id = int((body as Dictionary).get("player", -1))
			joined_world = world
			last_tick = int(world.get("tick", -1))
			stage = Stage.JOINED
			welcomed.emit(player_id, world)
		"Refused":
			var reason := String((body as Dictionary).get("reason", "no reason given"))
			stage = Stage.DEAD
			_socket.disconnect_from_host()
			refused.emit(reason)
		"Tick":
			var bundle: Dictionary = body as Dictionary
			bundles_seen += 1
			last_tick = int(bundle.get("tick", last_tick))
			tick_bundle.emit(last_tick, bundle.get("inputs", []))
		"Desync":
			desynced.emit(int((body as Dictionary).get("tick", -1)))
		_:
			# A message we do not know is a protocol mismatch, not noise to skip: the relay and this
			# client disagree about what the wire looks like, and pretending otherwise desyncs.
			_fail("%s sent a message this client does not know: %s" % [_where, kind])


func _write(msg: Dictionary) -> bool:
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
