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
## **RECONNECT WAS NEVER BUILT AND THE CLIENT HAS IT ANYWAY** (ASSA-177). This header said
## "deliberately absent (Decision 3): a dropped client restarts to rejoin" for as long as there has
## been a client, and nobody had pressed the button: `join` treats DEAD as "not connected" rather than
## "finished" (see `_process`), `main.gd::_join_address` permits an attempt at that stage, and the
## relay has mapped an account back to its own `PlayerId` since `sim-game/tools/rejoin_check.sh`. So a
## drop, one press of Join, and you are back in the same slot in a running world. Measured, both ways
## round, by `tools/reconnect_probe.gd`: after the host restarts (you lose the ticks since its last
## autosave) and after the socket alone dies with the host still up (you lose nothing).
##
## **THE SILENT DROP IS NOTICED NOW, AND IT USED NOT TO BE** (ASSA-179). Every failure above is the
## socket's status CHANGING: the kernel says the connection died and `_process` calls `_fail`. A link
## that stops carrying bytes without closing -- a slept laptop, a wifi handover, a host wedged rather
## than killed -- changes no status at all, so this node believed it was playing for as long as it was
## left running. Measured, not argued: `tools/reconnect_probe.gd` SIGSTOPs the relay, and before this
## existed the screen still said "joined as player 0" after 80 missing bundles. So the node keeps its
## own clock on the link: `SILENCE_MS` without a word from the relay is a dead link, and saying so is
## what brings the join band back (ASSA-175) and makes Join live (ASSA-176/177) -- one press back into
## the same slot, which is the whole reason a timeout is worth having.
##
## **WHAT IS STILL ABSENT.** (1) A relay that accepts the socket and never answers `Hello`: the clock
## below starts at the `Welcome`, so a client stuck at GREETED is not timed by it. Deliberate -- an
## unanswered connect is the OS's business and a cold start must not be called a drop -- and not
## measured either way. (2) **A desync used to be the second absence and is not one any more**
## (ASSA-190): `Desync` leaves this node at DEAD with the socket closed BY US, so the join band comes
## back and one press of Join rebuilds the world from a fresh `Welcome`. The relay still closes
## nothing and still runs its clock -- that half is unchanged and is the host's business -- but the
## peer no longer sits in a world it has stopped trusting. Nothing in this file resets `bundles_seen`, `last_tick`, `player_id` or
## `_reader` on a second `join`, which the probe shows is harmless today (the reader was empty at the
## drop) and is where to look first if a reconnect ever reads garbage.

## Accepted: our slot, the world to start from, and the message's own text for the sim. The next
## bundle is for `world.tick`.
signal welcomed(player: int, world: Dictionary, raw: String)
## The relay said no. The connection is closed after this.
signal refused(reason: String)
## One tick's inputs, in the order every peer must apply them, plus the message's own text.
signal tick_bundle(tick: int, inputs: Array, raw: String)
## **OUR HASH FOR `tick` DID NOT MATCH THE HOST'S, AND BOTH HASHES ARE HERE** (ASSA-190, protocol
## 10). It is no longer unrecoverable: this node hangs up on a desync, so the stage is DEAD and Join
## is live -- one press and the relay sends a fresh `Welcome`, which is the only cure for a world
## that has drifted. The two hashes travel with it because a drop with no evidence is the shape that
## lets a determinism bug pass as a bad connection.
signal desynced(tick: int, reported: String, expected: String)
## The socket never came up, or died. `reason` is for a player to read.
signal link_failed(reason: String)
## **THE LINK HAS SAID NOTHING FOR `seconds` WHOLE SECONDS, AND NOTHING HAS CHANGED BECAUSE OF IT**
## (ASSA-191). Not a failure and not a stage: the socket is open, the world is still on screen, Join
## is still refused, and this is the one thing a player in that state is owed -- a number going up.
##
## **`0` MEANS "NEVER MIND": a message arrived, or the link finished.** Whoever shows this must take
## it down on a zero, which is why it is one signal carrying a count rather than a pair of them. It
## fires only when the NUMBER changes, so a receiver can be as dumb as a label.
signal link_quiet(seconds: int)
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

## **HOW LONG A JOINED CLIENT WAITS FOR A WORD FROM THE RELAY BEFORE IT CALLS THE LINK DEAD.**
##
## THIS NUMBER AND THE SENTENCE ARE THE GAME DIRECTOR'S, NOT MINE (ASSA-179 part 2): 10s is my
## default, it is one constant and one string on purpose, and a ruling is a one-line change.
##
## **THE FLOOR IS MEASURED AND IT IS NOT MINE.** I said a number I picked alone would be tuned to my
## own harness, and Maren answered it with `tools/maren_bundle_gap_probe.gd` rather than with taste: a
## live relay and a live screen for 60s, every `tick_bundle` arrival timed, on the machine running six
## agents. **Worst gap 263ms over 599 bundles; p50 100ms, exactly the tick rate.** So 10s is 38x the
## worst gap a healthy session has ever been measured producing, and ~100 bundles that did not arrive.
##
## **WHICH MEANS THE REMAINING QUESTION IS NOT SAFETY, IT IS PATIENCE.** Anything above a second or so
## clears that distribution, so the cost of a shorter threshold is not false drops -- it is the one
## ASSA-177 bounded (one press of Join, same slot, nothing lost). What is left to rule on is how long
## a player should stare at a world that has stopped before being told, and that is a design call.
##
## The one case this number does NOT have to cover is a frozen main loop: that is handled by WHERE the
## check runs (see `_process`), not by the size of the number, which is why it can afford to be short.
const SILENCE_MS := 10000

## **HOW LONG A JOINED CLIENT WAITS BEFORE SAYING SO -- A DIFFERENT NUMBER AND A DIFFERENT KIND OF
## NUMBER FROM THE ONE ABOVE** (ASSA-191, Maren's second threshold, and the half of ASSA-179 I did
## not build the first time).
##
## **WHAT WENT WRONG WITHOUT IT.** `SILENCE_MS` alone means a host that hiccups for nine seconds
## gives the player nothing at all, and then drops them with no warning. The whole finding of
## ASSA-179 was that the window looks exactly like a running game; for the first ten seconds of a
## silent host it still did.
##
## **THE TWO NUMBERS BUY DIFFERENT THINGS, WHICH IS WHY THEY ARE NOT ONE.** Crossing this one is
## REVERSIBLE -- no stage change, no band, no closed socket, and the sentence goes the moment a
## bundle lands -- so a false positive costs a player a glance. Crossing `SILENCE_MS` drops them. A
## cheap, reversible warning can afford to be 7.6x the worst measured gap (263ms over 599 bundles,
## `tools/maren_bundle_gap_probe.gd`); an irreversible drop is set at 38x.
##
## The same ordering defence covers both: this is computed after the socket is drained (see
## `_process`), so a frozen main loop warns about nothing either.
const QUIET_MS := 2000

var stage: Stage = Stage.IDLE
## Our slot in the world, once welcomed. -1 while unknown; `PlayerId` is a slot, not an identity.
var player_id := -1
## The world as it was at the tick we joined. NOT kept up to date -- see the note above.
var joined_world: Dictionary = {}
## Bundles seen since the join, and the last tick the relay sent. Evidence that the link is live
## even before anything can be applied.
var bundles_seen := 0
var last_tick := -1
## **DESYNCS THIS NODE HAS BEEN TOLD ABOUT, COUNTED BECAUSE THE DROP MUST BE VISIBLE** (ASSA-190).
## A client that quietly re-welcomed itself on every desync would be a client that hides a
## determinism bug, which is the one class of bug this game cannot afford. Not reset by a second
## `join`, like `bundles_seen`: the count is a session's history, and a peer that diverges twice is
## a different story from two peers that diverged once.
var desyncs_seen := 0

## **THE ENGINE CLOCK AT THE LAST THING THE RELAY SAID**, or -1 while nothing is being timed.
##
## `Time.get_ticks_msec` and not a frame count or a tick count: ticks are the thing that stopped
## arriving, so counting them cannot measure their absence. It is monotonic and it keeps running while
## this process is stopped, which is what makes a slept laptop measurable at all.
##
## -1 IS "NOT BEING TIMED", NOT "HEARD AT TIME ZERO" -- see `link_is_silent`. A client that has not
## been welcomed has no link to time, and treating -1 as a timestamp would make every cold start a
## drop the moment `SILENCE_MS` elapsed after launch.
var _last_heard_msec := -1
## **THE NUMBER THIS NODE HAS ALREADY SAID OUT LOUD**, so `link_quiet` fires when the count changes
## rather than sixty times a second. 0 is "nothing is being said", and `_fail` puts it back there.
var _quiet_said := 0

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
	_drain_reader()


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
	if not _drain_reader():
		return

	# **THE SILENCE IS CHECKED AFTER THE DRAIN, AND THAT ORDERING IS THE WHOLE FALSE-POSITIVE
	# DEFENCE.** A frozen main loop -- a slow frame, a breakpoint, a laptop lid, this process
	# SIGSTOPped -- does not stop the kernel buffering what the relay sent meanwhile. So the frame
	# that resumes reads a gap of however long the freeze was AND a socket holding every bundle of
	# it: draining first turns that into a fresh timestamp, and the check that follows sees no gap.
	# Checked before the drain it would call every freeze a dead host, which is the one thing this
	# must not do. Measured, not asserted: `tools/reconnect_probe.gd` case H freezes the client for
	# longer than `SILENCE_MS` against a live relay and the link survives.
	var now := Time.get_ticks_msec()
	# **THE WARNING IS COMPUTED IN THE SAME PLACE AS THE DROP, FROM THE SAME STAMP** (ASSA-191). It
	# has to be after the drain for the reason above -- a frozen client that warned "the host has
	# gone quiet" about a host that was talking the whole time would be the false positive wearing a
	# politer sentence -- and it is computed BEFORE the drop so a run that crosses both thresholds in
	# one frame emits the count and then the zero `_fail` sends, in that order.
	var quiet := quiet_seconds(stage, _last_heard_msec, now, QUIET_MS)
	if quiet != _quiet_said:
		_quiet_said = quiet
		link_quiet.emit(quiet)
	if link_is_silent(stage, _last_heard_msec, now, SILENCE_MS):
		# THE SENTENCE IS `AssayHud`'s, not this file's, and the four above it are not: see
		# `AssayHud.silent_host_line` for why this one moved and they did not.
		_fail(AssayHud.silent_host_line(_where, SILENCE_MS / 1000))


## **HAS THE LINK GONE QUIET?** Static and pure, because the rule is the part worth testing and the
## cases that matter most cannot be driven from a headless test otherwise: a client that has not been
## welcomed has no socket to wait on, and a real 10-second gap takes 10 real seconds.
##
## Three ways to be not-silent, and each is a case that bit: the stage is not JOINED (nothing has been
## joined yet, or the link already finished and `_fail` must not run twice), nothing is being timed
## (`heard_msec < 0`), or no limit is set (`limit_msec <= 0` turns the detector off rather than
## declaring every link dead on its first frame, which is what a zeroed constant would otherwise do).
static func link_is_silent(at_stage: Stage, heard_msec: int, now_msec: int, limit_msec: int) -> bool:
	if at_stage != Stage.JOINED or heard_msec < 0 or limit_msec <= 0:
		return false
	return now_msec - heard_msec >= limit_msec


## **HOW MANY WHOLE SECONDS OF SILENCE ARE WORTH SAYING OUT LOUD, or 0 when there is nothing to say**
## (ASSA-191). Static and pure for the same reason as `link_is_silent`, and sharing its three guards
## deliberately: a client that has not joined, a client with nothing being timed and a zeroed
## threshold must be as harmless here as they are there, or the warning becomes the false positive
## the drop was careful not to be.
##
## **WHOLE SECONDS, FLOORED, AND THE NUMBER IS THE GAP AND NOT THE THRESHOLD.** Maren's wording is
## "nothing for 3s" with the number going up, so this reports what has actually elapsed -- the only
## honest claim this client can make is about what IT waited. A gap of 2900ms is "2s", not "3s":
## rounding up would have the screen claim a second that has not happened yet.
static func quiet_seconds(at_stage: Stage, heard_msec: int, now_msec: int, quiet_ms: int) -> int:
	if at_stage != Stage.JOINED or heard_msec < 0 or quiet_ms <= 0:
		return 0
	var gap := now_msec - heard_msec
	if gap < quiet_ms:
		return 0
	return gap / 1000


## Hand every whole message in the reader to `_handle`. False when the link is finished and the
## caller must stop: a reader error, or a message that killed the stage.
##
## One copy, used by the socket path and by `feed_offline`, which is the point -- an offline harness
## with its own drain loop would prove nothing about the real one (see `play_offline`).
func _drain_reader() -> bool:
	while true:
		var msg: Variant = _reader.next_message()
		if msg == null:
			if _reader.error != "":
				_fail(_reader.error)
				return false
			return true
		_handle(msg)
		if stage == Stage.DEAD:
			return false
	# **UNREACHABLE AND REQUIRED ANYWAY, which I got the wrong way round first.** I left this out on
	# the reasoning that `project.godot` promotes unreachable code to an error; the engine's answer was
	# "Not all code paths return a value" on a `while true` with no `break`. The analyser does not
	# prove the loop never exits, so it wants the return and does not call it unreachable.
	return true


func _handle(msg: Variant) -> void:
	var tagged := AssayProtocol.variant_of(msg)
	var kind: String = tagged[0]
	var body: Variant = tagged[1]
	# **THE RELAY SAID SOMETHING, SO THE LINK IS ALIVE: STAMPED HERE FOR EVERY MESSAGE, NOT ONLY
	# BUNDLES.** Today the only thing that arrives repeatedly IS the bundle (`Tick`), so this is the
	# bundle clock ASSA-179 asked for. It is stamped one level up anyway, because the claim the
	# timeout makes to a player is "your host has gone quiet", and a relay that is talking at all has
	# not. The narrower rule would call a desynced-but-chatty link dead and blame the host for it.
	# WHAT THIS DOES NOT CATCH, and it is a different item if it ever exists: a relay that keeps
	# talking while its world stops advancing. Nothing in `sim-relay` can do that today -- the clock
	# and the send are the same loop.
	_last_heard_msec = Time.get_ticks_msec()
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
			# **WE HANG UP, AND THAT IS THE WHOLE FIX** (ASSA-190). A desync means our copy of the
			# world is wrong, and the only cure is a fresh `Welcome` carrying the host's state --
			# which a rejoin already delivers, same slot, nothing lost while the host is up
			# (measured by `tools/reconnect_probe.gd` for ASSA-177). `_join_address` refuses at
			# JOINED, so leaving the stage there meant the one failure in this client with no way
			# out of the window. Closing the socket ourselves makes DEAD *honest*: the link really
			# is gone, because we ended it. The alternative was spelling a desync as DEAD while the
			# socket stayed up, and then nobody could tell a cable from a hash.
			#
			# **SHAPED LIKE THE `Refused` ARM ABOVE** -- stage, disconnect, then emit -- because
			# they are the same event from this node's side: the relay has told us this session is
			# over and the socket has no further use.
			var d: Dictionary = body as Dictionary
			desyncs_seen += 1
			stage = Stage.DEAD
			_socket.disconnect_from_host()
			desynced.emit(
					int(d.get("tick", -1)),
					String(d.get("reported", "")),
					String(d.get("expected", "")))
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
	# **THE WARNING COMES DOWN BEFORE THE REASON GOES UP** (ASSA-191). `_process` returns at DEAD, so
	# nothing below will ever recompute the count: a warning left standing would be the last word on a
	# link that now has a real sentence of its own. It matters most where the two meet -- the 2s
	# warning and the 10s drop are about the SAME silence, and the player must end up reading the one
	# that tells them what to do. Before `link_failed` so a receiver drawing both sees them in that
	# order and not the other way round.
	if _quiet_said != 0:
		_quiet_said = 0
		link_quiet.emit(0)
	link_failed.emit(reason)
