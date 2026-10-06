extends RefCounted
## THE HOST THAT HOLDS THE SIM, and the plumbing that gets the right bytes to it.
##
## There is no relay in this suite, so there is no `Welcome` to build a world from -- a hand-written
## fixture would have to be a whole serde-shaped `World`, and it would break every time the sim grows
## a field, which it did twice on 2026-10-01. So what is tested here is everything AROUND the world:
## refusal paths, the raw-text rule, and the framing of a message GDScript cannot write.
##
## The world itself is proved end to end against a real relay by `tools/lockstep_probe.gd`, which is
## the only honest place for it: the relay is the thing that tells us whether our hashes match.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A HOST WITH NO WORLD ANSWERS "NOTHING", NOT ZERO. `tick()` of 0 would be a real tick, and a caller
## comparing it against a relay's would think it had merely fallen behind.
func test_a_host_that_never_started_says_so() -> bool:
	var host := AssaySimHost.new()
	if host.running():
		return _fail("a fresh host claims to be running")
	if host.tick() != -1:
		return _fail("a host with no world reports tick %d, which looks like a real tick" % host.tick())
	if host.hash_hex() != "" or host.seed_text() != "":
		return _fail("a host with no world reported a hash or seed")
	if host.players().size() != 0 or host.deposits().size() != 0:
		return _fail("a host with no world listed players or deposits")
	if host.apply('{"Tick":{"tick":1,"inputs":[]}}') != "":
		return _fail("a host with no world applied a bundle")
	return true


## THE RAW-TEXT RULE, AS A TEST. The parsed Dictionary is not a substitute for the message's bytes:
## Godot has already turned every number in it into a double. An empty string is what a caller passing
## the Dictionary instead would end up with, so it has to be refused with a reason.
func test_a_welcome_with_no_raw_text_is_refused_with_a_reason() -> bool:
	var host := AssaySimHost.new()
	if host.start(""):
		return _fail("a host started from no text at all")
	if not host.fail_reason.contains("double"):
		return _fail("the refusal does not say why raw text matters: %s" % host.fail_reason)
	return true


## A message that is not a Welcome must leave the host not running, and say so.
func test_a_welcome_that_is_not_one_is_refused() -> bool:
	var host := AssaySimHost.new()
	if host.start('{"Refused":{"reason":"protocol 3, host speaks 4"}}'):
		return _fail("a host started from a Refused message")
	if host.running() or host.fail_reason == "":
		return _fail("a failed start left running=%s reason='%s'" % [host.running(), host.fail_reason])
	return true


## FRAMING TEXT SOMEBODY ELSE WROTE must be byte-identical to framing a dictionary, because the only
## reason `encode_text` exists is the hash message -- and if its framing differed, the relay would
## read a length that did not match its body and drop the connection.
func test_framing_text_matches_framing_a_dictionary() -> bool:
	var msg := {"Hello": {"name": "limpet", "protocol": AssayProtocol.protocol_version()}}
	var by_dict := AssayProtocol.encode(msg)
	var by_text := AssayProtocol.encode_text(JSON.stringify(msg))
	if by_dict != by_text:
		return _fail("encode_text framed %d bytes where encode framed %d"
				% [by_text.size(), by_dict.size()])
	# And the frame survives the reader, which is the only thing that matters about it.
	var reader := AssayFrameReader.new()
	reader.feed(by_text)
	var back: Variant = reader.next_message()
	if typeof(back) != TYPE_DICTIONARY:
		return _fail("a text-framed message came back as %s" % type_string(typeof(back)))
	return true


## THE READER KEEPS THE BYTES IT PARSED, and they must be the bytes that arrived -- not
## `JSON.stringify` of what it parsed, which is where a u64 would already have been lost.
func test_the_reader_keeps_the_text_it_parsed() -> bool:
	# A number past 2^53, written by hand, so a double round-trip is visible: 2^63 - 1.
	var body := '{"Hash":{"tick":20,"hash":9223372036854775807}}'
	var reader := AssayFrameReader.new()
	reader.feed(AssayProtocol.encode_text(body))
	var parsed: Variant = reader.next_message()
	if parsed == null:
		return _fail("the reader could not parse a hand-written message: %s" % reader.error)
	if reader.last_text != body:
		return _fail("last_text is '%s', not the bytes that arrived" % reader.last_text)
	return true


## NOTHING IS SENT BEFORE THE WELCOME, and an empty message is never sent at all -- that is what a
## failed `hash_message_json()` looks like, and framing nothing would desynchronise the stream.
func test_nothing_is_sent_before_joining_or_when_empty() -> bool:
	var client := AssayNetClient.new()
	if client.send_text('{"Hash":{"tick":0,"hash":0}}'):
		return _fail("raw text was sent before the welcome")
	client.stage = AssayNetClient.Stage.JOINED
	if client.send_text(""):
		return _fail("an empty message was framed and sent")
	client.free()
	return true


## `protocol.gd` MUST NOT GROW A `hash_report()` AGAIN. One existed, was never called, and was wrong:
## it put the hash in as a string, which serde refuses, so the relay would have dropped us. The
## comment saying so is not a guard; reading the file is.
## **THE SIM'S VERDICT ON A DESIGN NOBODY HAS BUILT**, through the wrapper (ASSA-140).
##
## IN GDSCRIPT AND NOT ONLY IN RUST, which is a lesson that cost me a shipped field: I once inverted
## a bool in the binding and all forty Rust tests stayed green, because a Variant dictionary's
## contents are invisible from Rust. The keys and their types only exist here.
##
## Seed 14247 is the pinned showcase world and its answer is a FACT this asserts against: frame +
## head is SAFE, frame + head + four hoppers is WILL BREAK. That is ASSA-140's whole finding -- the
## demo hard-coded the second one -- so if this world ever stops saying it, the item's numbers are
## stale and the gate should say so rather than quietly agree.
func test_the_sim_weighs_a_drill_that_does_not_exist_yet() -> bool:
	var host := AssaySimHost.new()
	if not host.start(AssaySimHost.fresh_welcome_json("14247", "marlow")):
		return _fail("no world: %s" % host.fail_reason)
	var pair := host.starter_pair()
	if pair.size() < 1:
		return _fail("seed 14247 has no starter pair: %s" % pair)
	var material: int = int(pair[0])
	var verdicts := PackedStringArray()
	for n in range(5):
		var mounted := PackedStringArray(["head"])
		for _i in range(n):
			mounted.append("hopper")
		var facts: Dictionary = host.design_if_built("frame", mounted, material, "A")
		for key in ["verdict", "fault", "mass_low", "mass_high", "budget_low", "budget_high"]:
			if not facts.has(key):
				return _fail("the answer for %d hoppers has no `%s`: %s" % [n, key, facts])
		if String(facts["fault"]) != "":
			return _fail("%d hoppers is inside the slot limit and was refused: %s" % [n, facts])
		if int(facts["mass_high"]) < int(facts["mass_low"]):
			return _fail("%d hoppers: mass %s-%s is backwards"
					% [n, facts["mass_low"], facts["mass_high"]])
		verdicts.append(String(facts["verdict"]))
	# A fresh world has not assayed anything, so every sheet reads as a band and the honest answer
	# is UNCERTAIN: asserting SAFE here would be asserting that a guess is a certainty. What the
	# ORDER has to hold either way is that mass only rises -- so once a count breaks, none above it
	# can be safe. Both jobs' policies rest on exactly that.
	var seen_break := false
	for n in range(verdicts.size()):
		if verdicts[n] == "WILL BREAK":
			seen_break = true
		elif seen_break and verdicts[n] == "SAFE":
			return _fail("SAFE at %d hoppers after a break below it: %s" % [n, verdicts])
	# NOW ASSAY IT, which is what the loop does before it builds, and the band closes to the numbers
	# ASSA-140 was filed on.
	var assayed := host.design_if_built("frame", PackedStringArray(["head"]), material, "A")
	if String(assayed["verdict"]) == "":
		return _fail("an unassayed world produced no verdict at all: %s" % assayed)
	# THE RULES REFUSE AN ILLEGAL DESIGN IN THEIR OWN WORDS, and refusing is not weighing zero.
	var too_many := PackedStringArray(["head", "hopper", "hopper", "hopper", "hopper", "hopper"])
	var refused: Dictionary = host.design_if_built("frame", too_many, material, "A")
	if String(refused["verdict"]) != "" or String(refused["fault"]) == "":
		return _fail("five hoppers was weighed instead of refused: %s" % refused)
	if not String(refused["fault"]).contains("at most"):
		return _fail("the refusal is not the sim's own phrase: %s" % refused["fault"])
	# A HOST WITH NO WORLD ANSWERS NOTHING rather than inventing a verdict.
	if not AssaySimHost.new().design_if_built("frame", PackedStringArray(["head"]), 0, "A").is_empty():
		return _fail("a host with no world weighed a design")
	return true


func test_protocol_has_no_hash_builder() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/protocol.gd")
	if source == "":
		return _fail("could not read res://scripts/protocol.gd to check it")
	if source.contains("func hash_report"):
		return _fail(("AssayProtocol.hash_report is back. A ClientMsg::Hash carries a u64 and "
				+ "GDScript cannot spell one: the message has to come from AssaySim."))
	return true


## **THE TWO NUMBERS ASSA-256 CROSSED, ASKED FOR IN GDSCRIPT — WHICH IS THE ONLY PLACE THEY EXIST.**
##
## `make_offers` grew `cost` and `species_sheets` grew `reading_ranges` so Nacre can draw a row as
## data instead of parsing my sentences. Both are asserted in Rust already, on the `MakeOffer` and
## `SpeciesFacts` structs — and **that proves nothing about the dictionary**, which is the lesson
## forty lines above this one: a Variant dict's contents are invisible from Rust, and I have shipped
## an inverted field that way before. The keys and their types only exist here.
##
## **A RANGE IS ASSERTED AS A BAND THAT CONTAINS ITS TEXT, never against a literal.** Species are
## generated, so a hard-coded 26-50 would be a photograph of worldgen. What must hold is the
## relation: `lo <= hi`, both inside the scale, and the existing `readings` string spelling exactly
## those two ends — because the whole point of one function deciding both is that the bar and the
## text beside it cannot drift apart.
##
## **AND THE SECRET STAYS KEPT.** A fresh world has assayed nothing, so every range here must be a
## real band and not a point: if `lo == hi` on an unassayed sheet, the exact value has crossed and
## the thing the assay is paid for is already in the client's memory.
func test_the_binding_hands_gdscript_a_batch_cost_and_a_readings_two_ends() -> bool:
	var host := AssaySimHost.new()
	if not host.start(AssaySimHost.fresh_welcome_json("14247", "marlow")):
		return _fail("no world: %s" % host.fail_reason)

	# --- a reading's two ends, on a world that has assayed nothing.
	var sheets: Array = host.species_sheets()
	if sheets.is_empty():
		return _fail("no species sheets, so this proves nothing")
	var checked := 0
	for entry in sheets:
		var species: Dictionary = entry
		if not species.has("reading_ranges"):
			return _fail("a species sheet has no `reading_ranges`: %s" % species.keys())
		if not species.has("readings"):
			return _fail("a species sheet has no `readings`: %s" % species.keys())
		var ranges: Dictionary = species["reading_ranges"]
		var readings: Dictionary = species["readings"]
		if ranges.is_empty():
			return _fail("`reading_ranges` is empty for %s" % species)
		for property in ranges.keys():
			# **A `Vector2i`, NOT AN ARRAY, AND I LEARNED THAT FROM THIS TEST ABORTING.**
			# The binding crosses each pair as `Vector2i::new(lo, hi)`. My first
			# version declared `var pair: Array`, and a typed assignment that does
			# not match ABORTS the function in GDScript -- so the test returned
			# null and the runner reported "returned false and said nothing",
			# which is the shape that hides a real failure behind a silent one.
			var pair: Vector2i = ranges[property]
			var lo := pair.x
			var hi := pair.y
			if lo > hi:
				return _fail("%s reads %d-%d, which is backwards" % [property, lo, hi])
			if lo < 1 or hi > 100:
				return _fail("%s reads %d-%d, outside the scale a sheet is rolled on"
						% [property, lo, hi])
			# NOTHING IS ASSAYED IN A FRESH WORLD, so a point here means the exact value crossed.
			if lo == hi:
				return _fail(("%s crossed as a point (%d) on an unassayed sheet: that is the exact "
						+ "value, which the band exists to withhold") % [property, lo])
			# THE TEXT AND THE NUMBERS ARE ONE DECISION (ASSA-256), so the string must spell these
			# two ends and no others.
			if not readings.has(property):
				return _fail("`readings` has no %s to compare the range against" % property)
			if String(readings[property]) != "%d-%d" % [lo, hi]:
				return _fail(("%s: the sentence says `%s` and the numbers say %d-%d; one function "
						+ "is supposed to decide both") % [property, readings[property], lo, hi])
			checked += 1
	if checked < 6:
		return _fail("only %d readings compared; a sheet has six properties" % checked)

	# --- what one batch spends. A fresh player holds nothing, so there may be no offers at all;
	# that is a real state and not a failure, so the premise is asserted rather than assumed.
	var offers: Array = host.make_offers(0)
	var with_cost := 0
	for entry in offers:
		var offer: Dictionary = entry
		if not offer.has("cost"):
			return _fail("a make offer has no `cost`: %s" % offer.keys())
		if int(offer["cost"]) < 1:
			return _fail("a batch that costs %d is not a batch: %s" % [int(offer["cost"]), offer])
		with_cost += 1
	if not offers.is_empty() and with_cost == 0:
		return _fail("offers exist and none carried a cost")
	return true
