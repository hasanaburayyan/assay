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
## The sim IS bound in now (`AssaySimHost`), and that does not weaken this test, it sharpens it: the
## net client still may not apply a bundle, because the one place allowed to is the host, and the one
## thing allowed to do the applying is Rust. What changed is where the newest world comes from, not
## who is permitted to compute it.

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
	client.tick_bundle.connect(func(tick, inputs, _raw): seen.append([tick, inputs.size()]))
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


## NO GDSCRIPT FILE READS A SPECIES SHEET. Maren's line, ASSA-7 01:40, and it is sharper than it
## looks: `MineralSpecies.sheet` is `Serialize`, so the EXACT sheet crosses the wire in the Welcome
## whether the species has been assayed or not -- lockstep needs that, because every peer runs the real
## sim. So "hidden until assayed" is a display convention, not something the wire protects, and a
## renderer that read `joined_world["species"][n]["sheet"]` would quietly show numbers no player has
## paid 30 ticks for. The band rule lives in `sim::debug::reading` and arrives through the binding
## (`AssaySimHost.species_sheets`). She asked for a test rather than a habit; this is it.
func test_no_gdscript_file_reads_a_species_sheet() -> bool:
	var offenders := []
	# SPELT IN PIECES SO THIS LINE IS NOT ITS OWN FIRST OFFENDER. It was, on the first run.
	var word := "sh" + "eet"
	var key := RegEx.create_from_string('"%s"|\\.%s\\b' % [word, word])
	for folder in ["res://scripts", "res://tests", "res://tools"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for name in dir.get_files():
			var file := String(name).trim_suffix(".remap")
			if not file.ends_with(".gd"):
				continue
			for line in FileAccess.get_file_as_string("%s/%s" % [folder, file]).split("\n"):
				var code := String(line).strip_edges()
				if code.begins_with("#"):
					continue
				if key.search(code) != null:
					offenders.append("%s: %s" % [file, code])
	if not offenders.is_empty():
		return _fail(("a sheet is being read in GDScript: %s. The exact sheet is in the Welcome for "
				+ "every species, assayed or not, so reading it there shows numbers the player has "
				+ "not assayed. Go through the binding, which bands them.") % [offenders])
	return true


## Nothing may be submitted before the relay has stamped us a player.
func test_nothing_is_submitted_before_the_welcome() -> bool:
	var client := AssayNetClient.new()
	if client.submit({"Stop": {}}):
		return _fail("a command was submitted before joining")
	return true
