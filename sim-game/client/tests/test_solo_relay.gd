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


## **THE SHAPE MAREN RULED, CHECKED ON EVERY SENTENCE RATHER THAN ON ONE** (ASSA-113): what you
## cannot do now · why · the door that is still open. All five sentences I shipped in ASSA-106 had
## the first two parts and none had the third.
##
## THE WRONG DOOR IS ALSO A FAILURE, not just a missing one. Retry is honest for the deadline alone,
## because that is the only path that killed the process on its way out; offering it for a missing
## file would send a player pressing a button that cannot start working.
##
## AND `the relay` IS CHECKED ONLY ON OUR OWN CLAUSES -- the trailing quote is the relay's own words
## and we do not get to edit those.
func _check_shape(what: String, line: String, door: String) -> bool:
	var ours := line.split(" It said:")[0]
	if not line.begins_with(AssaySoloRelay.CANNOT):
		return _fail("%s does not open with what failed: %s" % [what, line])
	if not line.contains(door):
		return _fail("%s has no door that is still open: %s" % [what, line])
	var other: String = (AssaySoloRelay.SOLO_AGAIN if door == AssaySoloRelay.JOIN_INSTEAD
			else AssaySoloRelay.JOIN_INSTEAD)
	if line.contains(other):
		return _fail("%s offers both doors, so one of them is a lie: %s" % [what, line])
	if ours.to_lower().contains("the relay"):
		return _fail("%s calls it `the relay`, a word a solo player has never met: %s" % [what, line])
	# `sim-relay` IS ALLOWED, in the one clause that is about the file -- their folder really does
	# contain a file with that name. Anywhere else it is our internals made the player's problem.
	if ours.contains("sim-relay") and not ours.contains("file"):
		return _fail("%s names sim-relay outside a clause about the file: %s" % [what, line])
	return true


## A command that exists on this platform and exits immediately with nothing to say.
##
## IT HAS TO TOLERATE THE FLAGS `start` ADDS, which is why these are shells and not the bare tools.
## `/bin/sleep 30 --bind 127.0.0.1 --port 0` is a usage error, not a silent process, so the first
## version of this test measured a stand-in refusing arguments rather than the case it was named
## after. A shell takes the extra arguments as positional parameters and ignores them.
## A command that SAYS IT RAN, the way the relay does, and then dies.
##
## **THE `echo` IS NOT DECORATION, IT IS WHICH DEATH THIS IS** (ASSA-120). Since #167 the relay's
## first statement is `RELAY STARTED ...`, and `solo_relay.gd` now tells "it never ran" from "it ran
## and died" by whether that line arrived. A bare `exit 1` is a process that really ran and said
## nothing -- which is exactly the shape of a file the system refused to execute, and is now reported
## as one. So a stand-in for "the relay died" has to say the relay's own first line, or it is a
## stand-in for the other case. The bare version is still used, under its own name, below.
func _dies_at_once() -> Array:
	var said := "RELAY STARTED protocol 9 rules deadbeef"
	if OS.get_name() == "Windows":
		return ["C:/Windows/System32/cmd.exe",
				PackedStringArray(["/c", "echo %s& exit 1" % said])]
	return ["/bin/sh", PackedStringArray(["-c", "echo '%s'; exit 1" % said])]


## A command that dies having said NOTHING AT ALL -- the picture a refused exec leaves.
func _never_speaks_and_dies() -> Array:
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
	elif not _check_shape("a missing relay", solo.failure, AssaySoloRelay.JOIN_INSTEAD):
		ok = false
	# **AND THE PATHS COME AFTER THE OPEN DOOR** (Maren): consequence first, figures after. A stranger
	# reads the first sentence and a bug report reads the rest, so a list of four absolute paths must
	# not sit between the problem and the only clause that says what to do.
	elif solo.failure.find("Looked in:") < solo.failure.find(AssaySoloRelay.JOIN_INSTEAD):
		ok = _fail("the paths list is printed before the open door: %s" % solo.failure)
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
		# AND IT MUST NOT BE THE OTHER REPORT. This stand-in printed the relay's first line, so
		# claiming it never ran would be the confident wrong diagnosis ASSA-120 exists to prevent.
		elif solo.failure.contains("did not run"):
			ok = _fail("a relay that said it had started is reported as never having run: %s"
					% solo.failure)
		else:
			# JOIN A HOST, NOT RETRY: nothing killed this process, it died on its own, and it will
			# die the same way on a second press.
			ok = _check_shape("a relay that died", solo.failure, AssaySoloRelay.JOIN_INSTEAD)
	solo.stop()
	return ok


## RULING 6, THIRD SENTENCE: a relay that runs and will not speak is a failure WITH A DEADLINE, and
## the process is killed rather than left holding a port.
##
## **THIS IS THE CASE THAT WOULD OTHERWISE HANG THE WINDOW.** `FileAccess.get_line()` on a pipe
## blocks -- measured at 3044ms against a child that slept three seconds -- so the pipe is read only
## when `get_length() > get_position()` says a read cannot block, and this is what proves the main
## side gives up on time. (It said "read on a thread" until ASSA-113; the thread went when it turned
## out to be calling `get_process_exit_code` off the main thread, and the comment outlived it.)
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
		elif not solo.failure.contains("ready"):
			ok = _fail("the sentence does not say what was waited for: %s" % solo.failure)
		# **THE ONE SENTENCE THAT MAY SAY `PRESS PLAY SOLO AGAIN`**, and the `stop()` four lines
		# below is what earns it: the process is gone, so a second press starts from clean ground.
		elif not _check_shape("a silent relay", solo.failure, AssaySoloRelay.SOLO_AGAIN):
			ok = false
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


## **A FILE THE MACHINE WILL NOT RUN IS REFUSED BEFORE IT IS SPAWNED, NOT DIAGNOSED AFTERWARDS.**
##
## THIS TEST USED TO SPAWN IT, AND IT WAS A COIN FLIP I GOT AWAY WITH ONCE. The old version let the
## process start and expected `poll()` to recognise the exec failure from the child's stderr. It
## passed on my run and then failed in a mutation harness with the DEADLINE sentence, so I measured
## the case ten times instead of twice: Godot's `Could not create child process` appeared 3 of 10
## times and 0 of the next 9, `libc++abi ... PAL_SEHException` the rest, and twice the child never
## exited at all. The test agreed with my code because both were written from one lucky sample.
##
## SO THE REFUSAL NOW RESTS ON THE EXEC BIT, which is a fact `FileAccess` will answer the same way
## every time, and this test is deterministic: no process, no deadline, no race.
##
## A `chmod 644` FILE IS NOT A QUARANTINED ONE and this does not claim to be -- quarantine sets a
## separate flag on a file whose exec bit is fine, and the board's click is still the only evidence
## for it. What is pinned here is that the one cause we CAN read is read, and worded.
func test_a_file_the_machine_will_not_run_is_refused_before_it_is_spawned() -> bool:
	if OS.get_name() == "Windows":
		return true  # No exec bit to withhold, and `is_runnable` deliberately answers true there.
	var path := OS.get_user_data_dir().path_join("limpet-not-executable")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _fail("could not write a stand-in at %s" % path)
	f.store_line("#!/bin/sh")
	f.close()
	var solo := AssaySoloRelay.new()
	var ok := true
	if solo.start(path, PackedStringArray(), 2000):
		ok = _fail("a file with no exec bit was spawned rather than refused (pid %d)" % solo.pid)
	elif solo.failure.contains("stopped"):
		ok = _fail("a file that was never run is reported as a world that stopped: %s" % solo.failure)
	elif not solo.failure.contains("not marked as a program"):
		ok = _fail("the sentence does not say what is wrong with the file: %s" % solo.failure)
	elif not solo.failure.contains(path):
		ok = _fail("the sentence does not name the file it refused: %s" % solo.failure)
	# AND IT MUST NOT BORROW THE DOWNLOADED CAUSE. A downloaded file keeps its exec bit, so blaming
	# the download here would send a player to clear a flag that was never set.
	elif solo.failure.contains("downloaded"):
		ok = _fail("a missing exec bit is blamed on the download: %s" % solo.failure)
	else:
		ok = _check_shape("a file that is not a program", solo.failure, AssaySoloRelay.JOIN_INSTEAD)
	solo.stop()
	DirAccess.remove_absolute(path)
	return ok


## **THE GUARD MUST NOT REFUSE A GOOD RELAY, AND THAT IS THE EXPENSIVE WAY FOR IT TO BE WRONG.**
##
## `FileAccess.get_unix_permissions` FAILS ON WINDOWS, where there is no such bit -- so a guard that
## read its answer as "no exec bit, refuse" would break Play solo for every Windows player while
## every test I can run here stayed green. That is the asymmetry: the failure mode I cannot reach by
## hand is the one that matters, so the no-answer case is pinned rather than assumed.
##
## A PATH THAT DOES NOT EXIST ANSWERS 0 TOO (measured, with an engine error printed), which is the
## same "no answer" and must likewise not be a refusal: a missing file has its own sentence and gets
## to keep it.
func test_the_exec_bit_guard_refuses_nothing_it_cannot_read() -> bool:
	var relay := AssaySoloRelay.find_binary()
	if relay != "" and not AssaySoloRelay.is_runnable(relay):
		return _fail("the real relay at %s was judged unrunnable" % relay)
	# NO ANSWER IS NOT A NO. Both of these read 0: a path that does not exist anywhere, and every
	# path on Windows.
	if not AssaySoloRelay.is_runnable(OS.get_user_data_dir().path_join("limpet-no-such-file")):
		return _fail("a path with no permissions to read was treated as a refusal")
	if not AssaySoloRelay.is_runnable(""):
		return _fail("the empty path was treated as a refusal, which belongs to the missing sentence")
	return true


## **THE DOWNLOADED CAUSE IS CLAIMED ON MACOS AND NOWHERE ELSE**, which is the one clause where I
## overruled Maren rather than widened her ruling quietly. On macOS quarantine really is why an
## unsigned helper out of a downloaded zip will not exec; on Windows the same empty exec means
## something else, and a confident wrong diagnosis is worse than a vaguer true one.
##
## AND NEITHER SENTENCE INVENTS A GESTURE. Nobody here has hands on a quarantined zip, so no words of
## ours get to tell a player which click clears it.
func test_the_downloaded_cause_is_claimed_on_macos_and_no_gesture_is_invented() -> bool:
	var mac := AssaySoloRelay.would_not_run("/Users/x/assay-macos/sim-relay", "macOS")
	var win := AssaySoloRelay.would_not_run("C:/x/assay-windows/sim-relay.exe", "Windows")
	if not mac.contains("downloaded"):
		return _fail("the macOS sentence does not give the cause: %s" % mac)
	if win.contains("downloaded"):
		return _fail("the Windows sentence claims a macOS cause: %s" % win)
	for gesture in ["right-click", "Open Anyway", "System Settings", "xattr", "Privacy & Security"]:
		if mac.contains(gesture) or win.contains(gesture):
			return _fail("a refusal invents the gesture `%s`, which nobody here has tested: %s / %s"
					% [gesture, mac, win])
	if not win.contains("C:/x/assay-windows/sim-relay.exe"):
		return _fail("the sentence does not name the file it tried: %s" % win)
	return _check_shape("the macOS exec refusal", mac, AssaySoloRelay.JOIN_INSTEAD) \
			and _check_shape("the Windows exec refusal", win, AssaySoloRelay.JOIN_INSTEAD)


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


## **A CHILD THAT DIED WITHOUT SAYING IT RAN IS REPORTED AS A FILE THAT DID NOT RUN** (ASSA-120 box
## 4, now that #167 makes it a fact rather than a reading).
##
## WHY THIS WAS NOT POSSIBLE BEFORE. `OS.execute_with_pipe` hands back a live pid for a missing path,
## for a non-executable file and for a healthy relay alike, and the debris a dead child leaves is not
## a signal: measured on this machine, Godot's own `Could not create child process` appeared 3 of 10
## attempts and 0 of the next 9, from a mono build CI does not ship, and `/bin/sh -c "exit 1"` -- a
## process that really ran -- leaves exactly as much behind. So the client said only "it stopped" for
## both, and ASSA-106's version, which did claim a cause, was a coin flip I got away with once.
##
## THE RELAY'S FIRST LINE IS PRINTED BEFORE ARGUMENT PARSING, THE SAVE AND THE SOCKET, so its absence
## is the fact. The pair of tests is the whole claim: this one dies silent and must be told it never
## ran; `test_a_relay_that_dies_at_once...` says the line first and must NOT be.
func test_a_child_that_never_said_it_started_is_reported_as_never_having_run() -> bool:
	var solo := AssaySoloRelay.new()
	var ok := true
	var stand_in: Array = _never_speaks_and_dies()
	if not solo.start(String(stand_in[0]), stand_in[1], 2000):
		ok = _fail("could not even start the stand-in: %s" % solo.failure)
	else:
		var waited := 0
		while waited < 4000:
			if solo.poll() or solo.failure != "":
				break
			OS.delay_msec(20)
			waited += 20
		if solo.address != "":
			ok = _fail("a process that printed nothing was reported as listening")
		elif solo.failure == "":
			ok = _fail("waited %dms for a silent dead child and nothing was reported" % waited)
		elif not solo.failure.contains("did not run"):
			ok = _fail("the sentence does not say it never ran: %s" % solo.failure)
		# THE BINARY IS NAMED BY ITS FILE NAME, which is the thing in the folder the player unzipped.
		elif not solo.failure.contains("sh"):
			ok = _fail("the sentence does not name what did not run: %s" % solo.failure)
		# **THE CAUSE IS OFFERED WHERE IT IS TRUE AND NOWHERE ELSE.** A Windows or Linux player told
		# about `xattr` is being sent to a command that does not exist on their machine.
		elif OS.get_name() == "macOS" and not solo.failure.contains("quarantine"):
			ok = _fail("macOS and no quarantine clause: %s" % solo.failure)
		elif OS.get_name() != "macOS" and solo.failure.contains("quarantine"):
			ok = _fail("%s and a macOS-only clause: %s" % [OS.get_name(), solo.failure])
		else:
			ok = _check_shape("a child that never ran", solo.failure, AssaySoloRelay.JOIN_INSTEAD)
	solo.stop()
	return ok


## **`said_it_ran` IS SET BY THE LINE AND NOT BY THE PROCESS SURVIVING.** The flag is the whole
## mechanism, and a version that set it on any output at all -- or on the `LISTENING` line, which
## arrives later -- would pass the pair above and still be wrong about a relay that printed prose and
## died. So this drives a child that prints a line of the relay's OWN prose and nothing else.
func test_prose_is_not_mistaken_for_the_relay_saying_it_started() -> bool:
	if OS.get_name() == "Windows":
		return true  # `echo` is a shell builtin there; the pair above covers the rule.
	var solo := AssaySoloRelay.new()
	var ok := true
	# THE RELAY'S REAL PROSE, which used to be the first thing it printed. A reader keyed on "some
	# output arrived" cannot tell this from the contract line.
	if not solo.start("/bin/sh", PackedStringArray(["-c",
			"echo 'Hosting world 14247 at tick 1 on port 7777'; exit 1"]), 2000):
		ok = _fail("could not start the stand-in: %s" % solo.failure)
	else:
		var waited := 0
		while waited < 4000:
			if solo.poll() or solo.failure != "":
				break
			OS.delay_msec(20)
			waited += 20
		if solo.said_it_ran:
			ok = _fail("a line of prose was taken for the relay's first line")
		elif not solo.failure.contains("did not run"):
			ok = _fail("prose and no marker should still be `did not run`: %s" % solo.failure)
	solo.stop()
	return ok


## **A SOLO WORLD THAT NOBODY LISTENS TO STOPS TICKING, AND IT USED TO STOP FOR GOOD** (ASSA-219,
## found by Nerite). The P0 in the build the board was asked to play.
##
## `sim-relay`'s `log()` is a `println!` on every submitted command, join, leave, refusal and desync.
## Rust line-buffers stdout, so a full pipe blocks that write INSIDE `run_tick` and the host stops;
## nothing drained it, so it never came back. The cure was quitting the game.
##
## **THE CONTROL IS INSIDE THIS TEST, AND IT IS NOT DECORATION.** The drained arm on its own would
## pass just as happily against a flood that FITS in the pipe, which would make this a test of
## nothing -- the exact way three instruments of mine have passed this week for reasons they could
## not see. So the undrained arm must FAIL to finish, and if it ever finishes this test fails and
## says the flood is too small rather than quietly going green.
##
## **AND THE UNDRAINED ARM IS TIMED OFF THE DRAINED ONE RATHER THAN OFF A NUMBER I PICKED.** A fixed
## wait is a guess about the slowest CI runner, and the arm where it is too short is the arm that
## reports "blocked" about a child that was merely slow. Three times whatever the drained arm just
## needed, on this machine, this run.
##
## Measured here on macOS 14 / Godot 4.6.1: undrained, the child stops after 2149 lines of 31 bytes
## (~66 KB, one pipe buffer) with its process still alive. The CI log carries the Linux number.
func test_the_relays_log_is_drained_for_a_whole_session_and_never_blocks_its_host() -> bool:
	if OS.get_name() == "Windows":
		# No `/bin/sh` to flood with, and `cmd`'s `for /l` is a different enough animal that a
		# stand-in written in it would be its own thing to debug. The mechanism is the engine's pipe
		# and the fix is platform-independent; what is NOT covered here is the Windows pipe's
		# CAPACITY, which is smaller (anonymous pipes there can be 4 KB) and therefore fills SOONER.
		# Said on the item as not measured rather than carried across from this machine.
		return true
	const LINES := 4000
	var progress := OS.get_user_data_dir().path_join("limpet-assa219-flood.txt")
	# **THE REDIRECT TARGET IS QUOTED, AND THE FIRST VERSION OF THIS TEST WAS NOT.** Godot's user data
	# directory is under `Application Support` on macOS, so an unquoted `> $progress` word-splits: the
	# child wrote no progress file at all and printed a shell error PER LINE instead -- 4000 of them,
	# down STDERR. Both arms still behaved as this test expected, which is the point: the undrained arm
	# blocked on the wrong pipe and the drained arm was being saved by `_drain_stderr`. The reported
	# line was `<no file>` and that blank is the only reason I looked.
	var flood := ("echo 'RELAY STARTED protocol 9 rules deadbeef'; echo 'LISTENING 127.0.0.1:54321'; "
			+ "i=0; while [ $i -lt " + str(LINES) + " ]; do i=$((i+1)); "
			+ "echo \"[tick $i] Limpet: walk north\"; echo $i > '" + progress + "'; done; "
			+ "echo FLOODED > '" + progress + "'")
	var ok := true
	if FileAccess.file_exists(progress):
		DirAccess.remove_absolute(progress)

	# ARM ONE: DRAINED, which is what the client does now. The child must get all of it out and exit.
	var drained := AssaySoloRelay.new()
	var drained_ms := -1
	if not drained.start("/bin/sh", PackedStringArray(["-c", flood]), 4000):
		drained.stop()
		return _fail("could not start the flooding stand-in: %s" % drained.failure)
	var begun := Time.get_ticks_msec()
	while drained.address == "" and drained.failure == "" and Time.get_ticks_msec() - begun < 4000:
		drained.poll()
		OS.delay_msec(5)
	if drained.address == "":
		drained.stop()
		return _fail("the flooding stand-in never said it was listening: %s" % drained.failure)
	# EXACTLY WHAT `main.gd` NOW DOES EVERY FRAME, and nothing else.
	begun = Time.get_ticks_msec()
	while not drained.has_exited() and Time.get_ticks_msec() - begun < 20000:
		drained.pump()
		OS.delay_msec(5)
	drained_ms = Time.get_ticks_msec() - begun
	if not drained.has_exited():
		ok = _fail(("a pumped relay printing %d lines was still blocked after %d ms, so the drain is "
				+ "not keeping up") % [LINES, drained_ms])
	drained.stop()
	if not ok:
		return false

	# ARM TWO, THE CONTROL: the same flood with nobody reading, given THREE TIMES the time arm one
	# needed. It must still be unfinished -- otherwise the pipe swallowed the whole flood and arm one
	# proved nothing about draining.
	var undrained := AssaySoloRelay.new()
	if not undrained.start("/bin/sh", PackedStringArray(["-c", flood]), 4000):
		undrained.stop()
		return _fail("could not start the flooding stand-in a second time: %s" % undrained.failure)
	begun = Time.get_ticks_msec()
	while undrained.address == "" and undrained.failure == "" and Time.get_ticks_msec() - begun < 4000:
		undrained.poll()
		OS.delay_msec(5)
	if undrained.address == "":
		undrained.stop()
		return _fail("the control stand-in never said it was listening: %s" % undrained.failure)
	var patience: int = maxi(3 * drained_ms, 1500)
	begun = Time.get_ticks_msec()
	while Time.get_ticks_msec() - begun < patience:
		# NOT A SINGLE `poll()` OR `pump()` HERE. This is the shipped client before the fix.
		OS.delay_msec(5)
	var control_finished := undrained.has_exited()
	undrained.stop()
	# **A PRECONDITION, CHECKED BEFORE THE VERDICT, BECAUSE A BLANK HERE IS NOT A RESULT.** If the
	# child could not write its progress file then it was not doing what this test says it does, and
	# every number below is about some other experiment. Refuse and say what to look at.
	if not FileAccess.file_exists(progress):
		return _fail(("the flooding stand-in never wrote %s, so it was not flooding the way this test "
				+ "claims -- check the shell quoting, not the drain") % progress)
	var reached := FileAccess.get_file_as_string(progress).strip_edges()
	if not reached.is_valid_int():
		return _fail(("the undrained child reached `%s`, not a line number: it finished the flood, so "
				+ "the pipe swallowed all %d lines and arm one proved nothing") % [reached, LINES])
	if control_finished:
		return _fail(("THIS TEST IS MEASURING NOTHING: %d lines fit in the pipe with nobody reading, "
				+ "so arm one could pass without draining. Raise LINES.") % LINES)
	print(("    ASSA-219: undrained, the child stopped at line %s of %d (~%d KB) on %s; drained, all "
			+ "%d in %d ms") % [reached, LINES, int(reached) * 31 / 1024, OS.get_name(), LINES,
			drained_ms])
	return ok
