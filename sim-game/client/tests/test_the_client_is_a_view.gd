extends RefCounted
## PRINCIPLE 1, AS A TEST: a tick bundle may not change this client's idea of the world.
##
## A bundle carries INPUTS. Turning inputs into state is `sim::step`, which lives in Rust and is the
## one thing no line of GDScript may reimplement -- the moment it does, three clients and the relay
## stop agreeing and the desync is the SECOND symptom, after a wrong-looking screen nobody can
## explain. So the guard is behavioural rather than a promise in a comment: feed the client a bundle
## that plainly says "this player walked", and assert the client recorded the bundle and moved
## nobody.
##
## It also pins the reason the client cannot draw tick N yet: with no sim bound in, the newest thing
## it can honestly show is the snapshot it joined on.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


func _joined_client() -> AssayNetClient:
	var client := AssayNetClient.new()
	client._handle({"Welcome": {"player": 1, "world": {
		"tick": 5,
		"seed": 42,
		"width_chunks": 6,
		"height_chunks": 4,
		"spawn": {"x": 3, "y": 2},
		"species": [{"name": "kuri"}],
		"deposits": [{"id": 0, "species": 0, "center": {"x": 10, "y": 9}, "radius": 3,
				"amount": 40, "purity": 55}],
		"players": [{"id": 0, "name": "ada", "pos": {"x": 48, "y": 32}, "target": null},
				{"id": 1, "name": "limpet", "pos": {"x": 49, "y": 32}, "target": null}],
		"buildings": [],
	}}})
	return client


func test_a_welcome_is_taken_whole() -> bool:
	var client := _joined_client()
	if client.stage != AssayNetClient.Stage.JOINED:
		return _fail("a Welcome left the client at stage %d" % client.stage)
	if client.player_id != 1:
		return _fail("the client thinks it is player %d, the relay said 1" % client.player_id)
	if int(client.joined_world.get("tick", -1)) != 5:
		return _fail("the joined world's tick is %s" % client.joined_world.get("tick"))
	if client.last_tick != 5:
		return _fail("last_tick is %d after joining at 5" % client.last_tick)
	return true


## THE ONE THAT MATTERS. A bundle that says a player walked must move nobody here.
func test_a_tick_bundle_moves_nobody() -> bool:
	var client := _joined_client()
	var before := JSON.stringify(client.joined_world)
	var seen := []
	client.tick_bundle.connect(func(tick, inputs): seen.append([tick, inputs.size()]))
	client._handle({"Tick": {"tick": 6, "inputs": [
		{"Player": {"player": 1, "command": {"MoveTo": {"target": {"x": 60, "y": 40}}}}},
	]}})
	if JSON.stringify(client.joined_world) != before:
		return _fail(("a tick bundle changed the client's world. Applying inputs is `sim::step`'s "
				+ "job, in Rust; a GDScript copy of it desyncs every peer."))
	if client.bundles_seen != 1 or client.last_tick != 6:
		return _fail("the bundle was not recorded: %d bundles, last tick %d"
				% [client.bundles_seen, client.last_tick])
	if seen != [[6, 1]]:
		return _fail("the tick_bundle signal reported %s, expected one bundle of one input" % [seen])
	return true


## A refusal is final and says why, because the next thing a player does is read it.
func test_a_refusal_closes_the_link_with_its_reason() -> bool:
	var client := AssayNetClient.new()
	var said := []
	client.refused.connect(func(reason): said.append(reason))
	client._handle({"Refused": {"reason": "protocol 3, host speaks 4"}})
	if client.stage != AssayNetClient.Stage.DEAD:
		return _fail("a refusal left the client at stage %d" % client.stage)
	if said != ["protocol 3, host speaks 4"]:
		return _fail("the reason did not reach the player: %s" % [said])
	return true


## A message this client does not know means the two sides disagree about the wire. Guessing which
## variant was meant is how a desync starts quietly.
func test_an_unknown_message_is_a_failure_not_noise() -> bool:
	var client := _joined_client()
	var failures := []
	client.link_failed.connect(func(reason): failures.append(reason))
	client._handle({"Shipment": {"crates": 3}})
	if client.stage != AssayNetClient.Stage.DEAD:
		return _fail("an unknown message was ignored; the client is still at stage %d" % client.stage)
	if failures.is_empty() or not String(failures[0]).contains("Shipment"):
		return _fail("the failure did not name the message: %s" % [failures])
	return true


## Nothing may be submitted before the relay has stamped us a player.
func test_nothing_is_submitted_before_the_welcome() -> bool:
	var client := AssayNetClient.new()
	if client.submit({"Stop": {}}):
		return _fail("a command was submitted before joining")
	return true
