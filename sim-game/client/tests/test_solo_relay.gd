extends RefCounted
## STARTING THE RELAY THAT SHIPPED BESIDE US (ASSA-106), AND EVERY WAY IT CAN REFUSE.
##
## **EACH REFUSAL IS DRIVEN BY A STAND-IN PROCESS, WHICH IS THE WHOLE REASON THE BINARY PATH IS AN
## ARGUMENT.** A test that could only use the real `sim-relay` could prove the happy path and nothing
## else -- and ruling 6's three sentences are precisely the cases a player meets when the happy path
## is unavailable. `/bin/false` dies at once; `sleep` runs and says nothing; a path that is not there
## is not there. All three are reachable in CI on both platforms the bundles target, except where
## noted on Windows.
##
## WHAT THESE DO NOT PROVE, said here rather than left to be assumed: that macOS will let an unsigned
## `Assay.app` out of a downloaded zip spawn an unsigned `sim-relay`. Quarantine refuses the EXEC,
## and nothing headless on a developer's own checkout is quarantined. That is the board's click and
## it is named on the item.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	runner.fail(reason)
	return false


## A command that exists on this platform and exits immediately with nothing to say.
##
## IT HAS TO TOLERATE THE FLAGS `start` ADDS, which is why these are shells and not the bare tools.
## `/bin/sleep 30 --bind 127.0.0.1 --port 0` is a usage error, not a silent process, so the first
## version of this test measured a stand-in refusing arguments rather than the case it was named
## after. A shell takes the extra arguments as positional parameters and ignores them.
func _dies_at_once() -> Array:
	if OS.get_name() == "Windows":
		return ["C:/Windows/System32/cmd.exe", PackedStringArray(["/c", "exit 1"])]
	return ["/bin/sh", PackedStringArray(["-c", "exit 1"])]


## A command that runs for longer than any deadline a test sets, and prints nothing.
func _runs_silently() -> Array:
	if OS.get_name() == "Windows":
		return ["C:/Windows/System32/cmd.exe", PackedStringArray(["/c", "timeout /t 30 /nobreak"])]
	return ["/bin/sh", PackedStringArray(["-c", "sleep 30"])]


## RULING 6, FIRST SENTENCE: a missing binary names every place it looked.
##
## NOT "file not found": a player who unzipped into a folder where the helper was stripped, or who
## moved `Assay.app` on its own, is owed the paths. So is whoever reads their bug report.
func test_a_missing_relay_names_where_it_looked() -> bool:
	var solo := AssaySoloRelay.new()
	var ok := true
	if solo.start("", PackedStringArray(), 100):
		ok = _fail("start() claimed success with no binary at all")
	elif solo.failure == "":
		ok = _fail("a missing relay refused in silence, which is the one thing ruling 6 forbids")
	elif not solo.failure.contains("sim-relay"):
		ok = _fail("the sentence does not name what is missing: %s" % solo.failure)
	else:
		for path in AssaySoloRelay.candidate_paths():
			if not solo.failure.contains(path):
				ok = _fail("the sentence does not name the path %s: %s" % [path, solo.failure])
				break
	solo.stop()
	return ok


## AND THE PLACES IT LOOKS ARE THE TWO LAYOUTS CI WRITES, derived rather than typed.
##
## `build.yml` puts `sim-relay` BESIDE `Assay.exe` on Windows and beside `Assay.app` on macOS, which
## from inside the bundle is three directories above the executable. Both have to be in the list or
## the shipped build cannot find its own helper -- and that failure would only ever appear in a zip,
## which is the slowest possible place to learn it.
func test_it_looks_beside_the_executable_and_three_up_for_the_app_bundle() -> bool:
	var paths := AssaySoloRelay.candidate_paths()
	var ok := true
	var beside := OS.get_executable_path().get_base_dir()
	var name := "sim-relay.exe" if OS.get_name() == "Windows" else "sim-relay"
	if paths.size() < 2:
		ok = _fail("only %d candidate paths; a bundle has two layouts" % paths.size())
	elif paths[0] != beside.path_join(name):
		ok = _fail("the first place looked is not beside the executable: %s" % paths[0])
	elif not paths[1].ends_with(name):
		ok = _fail("the second candidate does not name the binary: %s" % paths[1])
	elif paths[1].contains("Contents"):
		ok = _fail(("the app-bundle candidate still sits inside the bundle (%s); CI copies the "
				+ "relay beside Assay.app, not into it") % paths[1])
	# AND NOT ONE OF THEM IS A `res://` PATH. A packed export has no filesystem under `res://`, so a
	# candidate there would be unopenable in exactly the build this feature exists for.
	for path in paths:
		if path.begins_with("res://") or path.begins_with("user://"):
			ok = _fail("candidate %s is an engine path, which a spawned process cannot run" % path)
			break
	return ok


## RULING 6, SECOND SENTENCE: a relay that dies before speaking says so, and does not hang.
##
## THE FAILURE IS REPORTED BY `poll`, NOT BY `start`, and that split is the point: the process started
## fine. What a player needs to know is that it did not survive, which is only knowable later.
func test_a_relay_that_dies_at_once_is_reported_and_not_waited_for() -> bool:
	var solo := AssaySoloRelay.new()
	var ok := true
	var stand_in: Array = _dies_at_once()
	if not solo.start(String(stand_in[0]), stand_in[1], 2000):
		ok = _fail("could not even start the stand-in: %s" % solo.failure)
	else:
		var listening := false
		var waited := 0
		# POLLED THE WAY THE SCREEN POLLS IT, with a bound of its own so a bug here cannot hang the
		# whole suite. The deadline passed to `start` is 2000ms and this gives up at 4000.
		while waited < 4000:
			if solo.poll():
				listening = true
				break
			if solo.failure != "":
				break
			OS.delay_msec(20)
			waited += 20
		if listening:
			ok = _fail("a process that exited immediately was reported as listening")
		elif solo.failure == "":
			ok = _fail("waited %dms for a dead relay and nothing was ever reported" % waited)
		elif not solo.failure.contains("stopped"):
			ok = _fail("the sentence does not say it stopped: %s" % solo.failure)
	solo.stop()
	return ok


## RULING 6, THIRD SENTENCE: a relay that runs and will not speak is a failure WITH A DEADLINE, and
## the process is killed rather than left holding a port.
##
## **THIS IS THE CASE THAT WOULD OTHERWISE HANG THE WINDOW.** `FileAccess.get_line()` on a pipe
## blocks -- measured at 3044ms against a child that slept three seconds -- so the line is read on a
## thread and this is what proves the main side gives up on time.
func test_a_silent_relay_times_out_says_so_and_is_not_left_running() -> bool:
	var solo := AssaySoloRelay.new()
	var ok := true
	var stand_in: Array = _runs_silently()
	if not solo.start(String(stand_in[0]), stand_in[1], 300):
		ok = _fail("could not start the silent stand-in: %s" % solo.failure)
	else:
		var pid: int = solo.pid
		var started := Time.get_ticks_msec()
		while Time.get_ticks_msec() - started < 4000:
			if solo.poll() or solo.failure != "":
				break
			OS.delay_msec(20)
		var took := Time.get_ticks_msec() - started
		if solo.address != "":
			ok = _fail("a silent process was reported as listening on %s" % solo.address)
		elif solo.failure == "":
			ok = _fail("a silent relay never timed out; the window would hang here")
		elif not solo.failure.contains("listening"):
			ok = _fail("the sentence does not say what was waited for: %s" % solo.failure)
		elif took > 3000:
			ok = _fail("the deadline was 300ms and it took %dms to give up" % took)
		# THE PID CAPTURED BEFORE THE TIMEOUT, because `poll` calls `stop()` on the deadline and
		# `stop()` zeroes the field -- so asking the object would be asking about nothing. And the
		# exit code rather than `is_process_running`, because a killed child is a zombie until
		# something reaps it and `is_process_running` answers TRUE for a zombie for as long as this
		# process lives. That is the same measurement that fixed the class.
		elif OS.get_process_exit_code(pid) == -1:
			ok = _fail("the timed-out relay is still running, holding whatever port it took")
	solo.stop()
	return ok


## THE LINE IT WAITS FOR IS MARLOW'S CONTRACT AND NOTHING ELSE.
##
## `LISTENING <addr>:<port>`, printed once by the relay after the socket accepts. Driven here with
## `echo` rather than the relay, because what is being tested is the PARSE -- that the address comes
## out of the line and not out of a guess, and that the prose a person reads around it is ignored.
## The real relay is driven end to end in `test_a_real_relay_is_started_and_joined`.
func test_the_address_comes_out_of_the_listening_line() -> bool:
	if OS.get_name() == "Windows":
		return true  # `echo` is a shell builtin there; the contract is covered by the live test.
	var solo := AssaySoloRelay.new()
	var ok := true
	# PROSE FIRST, ON PURPOSE, because the relay prints "Hosting world ... on port ..." above its
	# contract line. A reader that took line one would pass against a stand-in that printed only the
	# contract line, and fail in the zip.
	if not solo.start("/bin/sh", PackedStringArray(["-c",
			"echo 'Hosting world 14247 at tick 1'; echo 'LISTENING 127.0.0.1:54321'; sleep 5"]),
			2000):
		ok = _fail("could not start the stand-in: %s" % solo.failure)
	else:
		var started := Time.get_ticks_msec()
		while Time.get_ticks_msec() - started < 3000:
			if solo.poll() or solo.failure != "":
				break
			OS.delay_msec(20)
		# THE FIRST LINE IS NOT THE CONTRACT LINE HERE, ON PURPOSE: the relay prints prose too, and
		# a reader that took line one would have taken the save path for an address.
		if solo.failure != "":
			ok = _fail("refused a stand-in that did print a listening line: %s" % solo.failure)
		elif solo.address != "127.0.0.1:54321":
			ok = _fail("read the address as `%s`" % solo.address)
	solo.stop()
	return ok


## THE SOLO SAVE IS IN THE USER DATA DIRECTORY (ruling 5), never inside the bundle and never a folder
## a bench or the board's own relay writes to.
func test_the_solo_save_is_in_the_user_data_directory() -> bool:
	var dir := AssaySoloRelay.saves_dir()
	var ok := true
	if not dir.begins_with(OS.get_user_data_dir()):
		ok = _fail("the solo save at %s is outside the user data dir %s"
				% [dir, OS.get_user_data_dir()])
	elif dir.contains(".app/"):
		ok = _fail("the solo save is inside the app bundle: %s" % dir)
	elif dir == OS.get_user_data_dir():
		ok = _fail("the solo save shares the user data dir root rather than a folder of its own")
	return ok
