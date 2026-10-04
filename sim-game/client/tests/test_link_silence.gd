extends RefCounted
## **A HOST THAT STOPS SENDING WITHOUT CLOSING THE SOCKET** (ASSA-179).
##
## Every other way this client's link dies is the kernel's news: the status changes, `_process` reads
## it, `_fail` runs. A relay that is stopped rather than killed -- a slept laptop, a wifi handover, a
## wedged process -- keeps the connection ESTABLISHED and simply stops answering, and for as long as
## there has been a client the screen went on saying "joined as player 0" over a world that had
## stopped. So the client keeps its own clock on the link.
##
## **WHAT THIS FILE CAN AND CANNOT HOLD, because the division is the interesting part.** The RULE is
## `AssayNetClient.link_is_silent`, static and pure, so every edge of it is tested here -- including
## the two that need no socket and could not be driven any other way (nothing joined yet, nothing
## being timed yet). The ORDER is not here and cannot be: whether the clock is read before or after
## the socket is drained is the whole false-positive defence, and proving it needs a real freeze
## against a real relay, which is `tools/reconnect_probe.gd` case H. A unit test of the ordering would
## have to fake the clock, which is to say fake the bug.
##
## **AND THE WARNING BEFORE THE DROP** (ASSA-191, `quiet_seconds`), which is the same clock read for a
## different purpose: 2s says something and changes nothing, 10s drops you. Its edges are here for the
## same reason; what it does to the SCREEN is `tests/test_main_screen.gd`, because that is a question
## about a label and not about a rule.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A client holding a world, reached the way production reaches it: a real `Welcome` through `_handle`.
func _joined_client() -> AssayNetClient:
	var client := AssayNetClient.new()
	client._handle({"Welcome": {"player": 0, "world": {"tick": 12, "seed": 7}}})
	return client


## THE RULE, AT THE STAGE IT IS ABOUT. A gap only means something to a client that is in a world: the
## stages before JOINED are a cold start (the OS owns a connect that never completes) and DEAD is a
## link that already finished, where firing again would overwrite the real reason with this one.
func test_only_a_joined_client_can_be_silent() -> bool:
	var long_gap := AssayNetClient.SILENCE_MS + 1000
	if not AssayNetClient.link_is_silent(AssayNetClient.Stage.JOINED, 0, long_gap,
			AssayNetClient.SILENCE_MS):
		return _fail("a joined client that heard nothing for %dms was not called silent" % long_gap)
	for stage in [AssayNetClient.Stage.IDLE, AssayNetClient.Stage.CONNECTING,
			AssayNetClient.Stage.GREETED, AssayNetClient.Stage.DEAD]:
		if AssayNetClient.link_is_silent(stage, 0, long_gap, AssayNetClient.SILENCE_MS):
			return _fail(("stage %d was called a silent host after %dms. Only a JOINED client has a "
					+ "link to go quiet; the rest is a cold start or an already-dead link.")
					% [stage, long_gap])
	return true


## **-1 IS "NOTHING IS BEING TIMED", NOT "HEARD AT TIME ZERO".** The trap is that the engine clock
## counts from launch, so reading -1 as a timestamp makes every client that never joined a dead host
## the moment the threshold elapses after startup -- a window that has done nothing wrong declaring a
## relay it never reached to be quiet.
func test_a_client_that_was_never_welcomed_is_never_silent() -> bool:
	var an_hour := 3600 * 1000
	if AssayNetClient.link_is_silent(AssayNetClient.Stage.JOINED, -1, an_hour,
			AssayNetClient.SILENCE_MS):
		return _fail(("a client with no last-heard stamp was called silent an hour into the process. "
				+ "-1 means nothing is being timed, not heard at time zero."))
	return true


## THE BOUNDARY, BOTH SIDES, because a threshold is the one number worth being exact about: the gap
## must REACH the limit, and a gap one millisecond short is a live link.
func test_a_gap_shorter_than_the_threshold_is_not_a_drop() -> bool:
	var limit := AssayNetClient.SILENCE_MS
	if AssayNetClient.link_is_silent(AssayNetClient.Stage.JOINED, 5000, 5000 + limit - 1, limit):
		return _fail("a gap of %dms tripped a %dms threshold" % [limit - 1, limit])
	if not AssayNetClient.link_is_silent(AssayNetClient.Stage.JOINED, 5000, 5000 + limit, limit):
		return _fail("a gap of exactly %dms did not trip a %dms threshold" % [limit, limit])
	return true


## A ZEROED THRESHOLD TURNS THE DETECTOR OFF; it does not kill every link on its first frame. This is
## the lever the probe's baseline run uses (`SILENCE_MS` 0 reproduces the defect ASSA-179 was filed
## for), so the off state has to be the harmless one -- and `now - heard >= 0` is true on every frame,
## which is exactly the shape a missing guard here would take.
func test_no_threshold_means_no_detector() -> bool:
	for limit in [0, -1]:
		if AssayNetClient.link_is_silent(AssayNetClient.Stage.JOINED, 0, 60000, limit):
			return _fail(("a threshold of %d called a live link dead. Zero must turn the detector "
					+ "off, not fire on every frame.") % limit)
	return true


## **THE WELCOME STARTS THE CLOCK.** Before this, a joined client had no stamp and the first bundle set
## it -- which on a relay that welcomes you and then says nothing is a silence that is never timed.
func test_the_welcome_starts_the_clock() -> bool:
	var client := _joined_client()
	if client.stage != AssayNetClient.Stage.JOINED:
		return _fail("the welcome did not join: stage %d" % client.stage)
	if client._last_heard_msec < 0:
		return _fail(("the welcome left nothing being timed (%d), so a relay that welcomes a player "
				+ "and then goes quiet would never be noticed") % client._last_heard_msec)
	return true


## **AND EVERY BUNDLE RESETS IT.** A real delay rather than a written one: the stamp is the engine's
## monotonic clock, so the only honest way to show it moved forward is to let real time pass. 5ms,
## because the clock has millisecond resolution and a same-frame pair of reads can be equal.
func test_every_bundle_resets_the_clock() -> bool:
	var client := _joined_client()
	var at_welcome := client._last_heard_msec
	OS.delay_msec(5)
	client._handle({"Tick": {"tick": 13, "inputs": []}})
	if client._last_heard_msec <= at_welcome:
		return _fail(("a tick bundle did not move the last-heard stamp on (%d at the welcome, %d "
				+ "after the bundle): a link carrying bundles would time out anyway")
				% [at_welcome, client._last_heard_msec])
	if client.bundles_seen != 1:
		return _fail("the bundle was not recorded: %d" % client.bundles_seen)
	return true


## **THE SENTENCE A PLAYER READS, and the second half is the half that matters.** A timeout that only
## says the link is dead leaves them where ASSA-179 left them: the join band is back (ASSA-175) and
## Join is live (ASSA-176), and nothing on screen says that pressing it rejoins their own slot in the
## running world. Checked as three facts rather than a literal, because the wording is Maren's.
func test_the_silent_host_sentence_names_the_host_the_wait_and_the_way_back() -> bool:
	# THE HOST CARRIES NO DIGITS ON PURPOSE. My first version passed "10.0.0.4:7777" and 10 seconds,
	# so the test for "does it say how long" was satisfied by the address -- a check that could not
	# fail, in the file I wrote to stop exactly that.
	var line := AssayHud.silent_host_line("quiet-host:seven", 14)
	if not line.contains("quiet-host:seven"):
		return _fail("the sentence does not name the host that went quiet: \"%s\"" % line)
	if not line.contains("14"):
		return _fail("the sentence does not say how long was waited: \"%s\"" % line)
	if not line.to_lower().contains("join"):
		return _fail(("the sentence does not name the control that gets the player back in: \"%s\". "
				+ "The door being open is the point of noticing at all.") % line)
	return true


# ------------------------------------------------------- the warning before the drop (ASSA-191)


## **TWO SECONDS IS A FLOOR AND IT IS NOT THE SAME FLOOR AS THE DROP'S.** A gap one millisecond short
## of it is a link nobody should be told about: the worst gap a healthy session has been measured
## producing is 263ms (`tools/maren_bundle_gap_probe.gd`), so anything that fires under this number is
## the client narrating its own frame rate.
func test_a_gap_too_short_to_mention_says_nothing() -> bool:
	var quiet := AssayNetClient.QUIET_MS
	var said := AssayNetClient.quiet_seconds(AssayNetClient.Stage.JOINED, 5000, 5000 + quiet - 1,
			quiet)
	if said != 0:
		return _fail("a gap of %dms was worth saying \"%ds\" about on a %dms threshold"
				% [quiet - 1, said, quiet])
	var at_the_floor := AssayNetClient.quiet_seconds(AssayNetClient.Stage.JOINED, 5000,
			5000 + quiet, quiet)
	if at_the_floor != quiet / 1000:
		return _fail("a gap of exactly %dms read as \"%ds\"" % [quiet, at_the_floor])
	return true


## **THE NUMBER IS THE GAP, FLOORED, AND NOT THE THRESHOLD THAT LET IT SPEAK.** Maren ruled whole
## seconds with the count going up, so the screen says what this client has actually waited. Rounding
## up would have it claim a second that has not happened; reporting the threshold would freeze the
## number at 2 and lose the only thing a player can read off it -- that it is still climbing.
##
## THE FIXTURE GAPS SHARE NO DIGITS WITH THE THRESHOLD on purpose: 2000ms would be satisfied by a
## function that returned `quiet_ms / 1000` and ignored the clock entirely.
func test_the_number_a_player_reads_is_whole_seconds_of_the_real_gap() -> bool:
	var cases := [[2900, 2], [3000, 3], [7400, 7], [9999, 9], [61000, 61]]
	for case in cases:
		var gap: int = case[0]
		var want: int = case[1]
		var got := AssayNetClient.quiet_seconds(AssayNetClient.Stage.JOINED, 1234, 1234 + gap,
				AssayNetClient.QUIET_MS)
		if got != want:
			return _fail("a gap of %dms read as \"%ds\" and should have read \"%ds\""
					% [gap, got, want])
	return true


## THE THREE GUARDS THE DROP HAS, HELD HERE TOO. A warning that fired on a client which had not
## joined, or had nothing being timed, or had its detector turned off, would be the false positive the
## drop was careful not to be -- cheaper, but on screen all the same.
func test_nothing_but_a_joined_client_with_a_clock_is_called_quiet() -> bool:
	var an_hour := 3600 * 1000
	for stage in [AssayNetClient.Stage.IDLE, AssayNetClient.Stage.CONNECTING,
			AssayNetClient.Stage.GREETED, AssayNetClient.Stage.DEAD]:
		if AssayNetClient.quiet_seconds(stage, 0, an_hour, AssayNetClient.QUIET_MS) != 0:
			return _fail(("stage %d was told its host had gone quiet. Only a JOINED client has a "
					+ "link to go quiet; the rest is a cold start or a link that already ended.")
					% stage)
	if AssayNetClient.quiet_seconds(AssayNetClient.Stage.JOINED, -1, an_hour,
			AssayNetClient.QUIET_MS) != 0:
		return _fail("a client with no last-heard stamp was called quiet an hour into the process")
	for off in [0, -1]:
		if AssayNetClient.quiet_seconds(AssayNetClient.Stage.JOINED, 0, an_hour, off) != 0:
			return _fail("a threshold of %d still warned: zero must turn the warning off" % off)
	return true


## **THE WORDS, AND WHAT THEY MUST NOT SAY.** Maren's sentence is `the host has gone quiet -- nothing
## for 3s`, and the two omissions are hers: no address and no control. This line is REVERSIBLE -- it
## comes down the moment a bundle lands -- so a sentence that named the Join button would be advice
## about a decision this client has not made, and `silent_host_line` is where that advice belongs.
##
## THE DURATION FIXTURE CARRIES A DIGIT THE REST OF THE SENTENCE CANNOT: my first silent-host test
## passed "10.0.0.4:7777" and 10 seconds, so "does it say how long" was satisfied by the address.
func test_the_quiet_warning_names_the_host_and_the_wait_and_promises_nothing() -> bool:
	var line := AssayHud.quiet_host_line(47)
	if not line.to_lower().contains("host"):
		return _fail(("the warning does not name the host: \"%s\". A player cannot check \"the "
				+ "network\", so what it blames is the whole of what they can act on.") % line)
	if not line.contains("47"):
		return _fail("the warning does not say how long has been waited: \"%s\"" % line)
	if line.to_lower().contains("join"):
		return _fail(("the warning names the Join button: \"%s\". Nothing has been dropped yet, so "
				+ "that is advice about a decision this client has not made -- and Join is refused "
				+ "while the stage is still JOINED (ASSA-176).") % line)
	if line.to_lower().contains("disconnect"):
		return _fail(("the warning says the player is disconnected: \"%s\". The socket is open and "
				+ "this line takes itself back down when a bundle lands.") % line)
	return true


## **THE DROP TAKES THE WARNING DOWN BEFORE IT GIVES ITS REASON.** The 2s warning and the 10s drop are
## about the SAME silence, and `_process` returns at DEAD -- so nothing recomputes the count after the
## drop and a warning left standing would be the last word on a link that has a real sentence of its
## own. The ORDER is the assertion: a receiver drawing both must not be handed the reason first and
## then be told to clear something.
##
## `_quiet_said` IS SET BY HAND and that is the honest way round: the real emit comes from `_process`,
## which on a client with no socket calls `_fail` for a dead connection on its first frame, so driving
## it there would test the wrong failure.
func test_the_drop_takes_the_warning_down_before_it_gives_its_reason() -> bool:
	var client := _joined_client()
	client._quiet_said = 4
	var order := PackedStringArray()
	client.link_quiet.connect(func(seconds: int) -> void: order.append("quiet %d" % seconds))
	client.link_failed.connect(func(_reason: String) -> void: order.append("failed"))
	client._fail("the host stopped answering")
	var got := ", ".join(order)
	if got != "quiet 0, failed":
		return _fail(("a drop on a warned client emitted \"%s\"; it must clear the warning and then "
				+ "give the reason (\"quiet 0, failed\"). Anything else leaves \"nothing for 9s\" on "
				+ "screen under a link that has ended.") % got)
	if client._quiet_said != 0:
		return _fail("the drop left the warning's count at %d" % client._quiet_said)
	return true
