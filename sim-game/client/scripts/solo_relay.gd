class_name AssaySoloRelay
extends RefCounted
## THE RELAY THAT SHIPPED BESIDE THIS CLIENT, STARTED ON LOOPBACK (ASSA-106).
##
## The board's ask was one sentence: "Is it possible to get the client starting relays? I want to be
## able to download and play solo". `sim-relay` is already in both zips, so nothing has to be built
## or fetched -- what was missing is that no `.gd` file ever launched a process.
##
## **ONE CODE PATH FOR SOLO AND CO-OP** (Wren's ruling 7). This does not run the sim in-process: it
## starts the same relay a friend would host and joins it as a lockstep peer over a socket. Solo is
## co-op with one player and a host on 127.0.0.1, so there is no second way for the client to be
## wrong.
##
## **THE RULES ID MATCHES BY CONSTRUCTION** (ruling 1), because the relay is the binary from the same
## zip as this client. That is the pairing rule's clause 1 without anybody checking a version file.
##
## **LOOPBACK ONLY** (ruling 2). `sim-relay`'s authenticator trusts any name it is given, so a solo
## world on `0.0.0.0` would sit open on the player's LAN. Marlow added `--bind` for this (ASSA-108)
## and left the default at `0.0.0.0`, so a hosted relay is unchanged; solo passes `127.0.0.1`.
##
## **THE PORT IS THE RELAY'S ANSWER, NOT OUR GUESS** (ruling 3). Picking a free port here would be a
## race: bind, close, hand the number over, and anything can take it in between. `--port 0` lets the
## OS choose and the relay prints what it actually got.
##
## **AND NOTHING HERE MAY BLOCK** (ruling 6). `FileAccess.get_line()` on a pipe blocks until a line
## arrives -- measured at 3044 ms against a child that slept three seconds -- so a relay that never
## speaks would freeze the whole window, which is the hang the ruling forbids.
##
## **SO THE PIPE IS ONLY READ WHEN IT ALREADY HAS BYTES IN IT.** `get_length()` on a pipe reports
## what is waiting (measured: 28 for two short lines), so `get_length() > get_position()` is the
## question "will a read return immediately", and the answer is checked before every read. There is
## no thread here. The first version used one, and it is worth saying why it went: it made the
## reader ask `OS.get_process_exit_code` off the main thread, which is not allowed, so a relay that
## had already died was never noticed and the WRONG sentence came back after the deadline. Not
## reading at all until a read is free removes the thread, the mutex and that whole class of bug.

## MARLOW'S CONTRACT, and the reason it is a prefix and not a sentence: `LISTENING <addr>:<port>`,
## printed once, after the socket is accepting and before the first tick. The prose around it is
## written for a person and will be reworded; this will not.
const LISTENING := "LISTENING "

## How long the relay gets to say it is listening. Generous on purpose: a cold start from a
## downloaded zip on a slow disk is the case that matters, and the cost of being wrong here is a
## sentence a player can retry rather than a wrong world.
const DEFAULT_DEADLINE_MS := 8000

## The seed solo plays by default (ruling 4): the friend seed, known playable from spawn.
const DEFAULT_SEED := "14247"

## **A SOLO REFUSAL IS THREE PARTS IN THIS ORDER** (Maren, ASSA-113): what you cannot do now · why
## (the file, the path, the seconds) · **the door that is still open**. All five sentences I shipped
## in ASSA-106 had the first two and none had the third, which is the only part that changes what a
## friend with no terminal does next.
##
## **AND THE PLAYER IS TOLD ABOUT A WORLD, NOT A RELAY.** "The relay" is a word a solo player has
## never met; the folder they unzipped really does contain a file called `sim-relay`, so that name
## appears only inside the clause that is about the file. Same family as ASSA-92: a refusal naming
## our internals makes the player do the translating.
##
## FIGURES COME AFTER THE OPEN DOOR, never before it -- a stranger reads the first sentence and a bug
## report reads the rest, so a paths list or the relay's last words must not sit between the problem
## and what to do about it.
const CANNOT := "Could not start your own world"

## The door that is open in every case but one: somebody else's relay is reachable whatever this
## machine will not run.
const JOIN_INSTEAD := "You can still join a host someone else is running."

## **THE EXEC BIT, AND IT IS THE ONLY `IT WILL NOT RUN` SIGNAL I COULD MEASURE TWICE THE SAME WAY.**
## `FileAccess.get_unix_permissions` answers 420 (644) for a file written by `FileAccess`, 493 (755)
## for the real relay and for the client's own executable, and 0 with an engine error for a path that
## does not exist -- measured, which is why the 0 is read as "no answer" below and never as a refusal.
const EXEC_OWNER := FileAccess.UNIX_EXECUTE_OWNER

## **THE DEADLINE CASE GETS A BETTER DOOR, AND ONLY IT DOES** (Maren). Retrying is honest here
## precisely because `poll()` kills the process on the way out, so a second press starts from clean
## ground. Nowhere else: a missing file is still missing and a relay that died will die again.
const SOLO_AGAIN := "Press Play solo again to try once more."

var pid := -1
## `127.0.0.1:PORT` once the relay has said so, and "" until then.
var address := ""
## WHICH refusal, as a sentence for the join screen. Empty while nothing has gone wrong.
var failure := ""

var _stdio: FileAccess = null
var _stderr: FileAccess = null
## Prose the relay printed above its contract line, kept only so a failure can quote it.
var _heard := PackedStringArray()
var _deadline_ms := DEFAULT_DEADLINE_MS
var _started_at := 0
var _binary := ""


## WHERE A RELAY COULD BE, in the order a build is most likely to be run.
##
## DERIVED FROM THE TWO LAYOUTS CI ACTUALLY WRITES, not guessed: `build.yml` copies `sim-relay`
## BESIDE `Assay.exe` on Windows and beside `Assay.app` on macOS -- which from inside the bundle is
## three directories up from the executable, because the executable lives in
## `Assay.app/Contents/MacOS`. The last two are the dev checkout, where the client runs out of the
## editor and the relay is wherever cargo put it.
##
## RETURNED AS A LIST RATHER THAN A CHOICE so that a missing binary can name every place it looked.
## A player who unzipped into a folder where the helper got stripped is owed that, and so is whoever
## reads the bug report.
static func candidate_paths() -> PackedStringArray:
	var name := "sim-relay.exe" if OS.get_name() == "Windows" else "sim-relay"
	var beside := OS.get_executable_path().get_base_dir()
	var project := ProjectSettings.globalize_path("res://")
	var out := PackedStringArray()
	out.append(beside.path_join(name))
	out.append(beside.path_join("../../..").simplify_path().path_join(name))
	out.append(project.path_join("../target/release").simplify_path().path_join(name))
	out.append(project.path_join("../target/debug").simplify_path().path_join(name))
	return out


## The first candidate that exists, or "".
static func find_binary() -> String:
	for path in candidate_paths():
		if FileAccess.file_exists(path):
			return path
	return ""


## WHERE A SOLO WORLD IS SAVED (ruling 5): the user data directory, never inside the `.app` and
## never the folder a bench or the board's own relay on 7777 writes to.
##
## SET AS AN ENVIRONMENT VARIABLE RATHER THAN A FLAG, because `sim_net::saves_dir` already reads
## `R2TS_SAVES_DIR` and a child process inherits this one's environment -- measured, not assumed. So
## no relay change was needed for this, which matters: the relay's own default has to keep working
## for a hosted world.
static func saves_dir() -> String:
	return OS.get_user_data_dir().path_join("solo-saves")


## **THE SENTENCE FOR A FILE THAT EXISTS AND THE SYSTEM WILL NOT RUN** -- the refusal the board is
## likeliest to meet, because macOS quarantine on an unsigned helper out of a downloaded zip refuses
## the exec and not the open.
##
## **WHERE I PART FROM MAREN'S RULING BY ONE CLAUSE, AND SAY SO RATHER THAN QUIETLY WIDEN IT.** She
## ruled this sentence says macOS refused it *because it was downloaded*. That cause is true on
## macOS. It is not true on Windows or Linux, where the same refusal means something else entirely,
## so printing it there would be a confident wrong diagnosis -- worse than the vaguer true one. The
## cause is given on macOS only, and the rest of the sentence is hers.
##
## **AND NO GESTURE IS INVENTED.** Nobody here has hands on a quarantined zip, so no sentence of ours
## gets to tell a player which click clears it: cause, open door, stop. If the board's press proves a
## gesture it goes in afterwards, in their words.
##
## `os_name` is an argument only so both branches can be driven from one machine in a test.
static func would_not_run(binary: String, os_name := "") -> String:
	var who := os_name if os_name != "" else OS.get_name()
	var why := ("macOS would not run the sim-relay file beside this client, because it was downloaded"
			if who == "macOS"
			else "the system would not run the sim-relay file beside this client")
	return "%s: %s. %s The file is %s" % [CANNOT, why, JOIN_INSTEAD, binary]


## **IS THIS FILE MARKED AS SOMETHING THE MACHINE MAY RUN**, asked before spawning rather than
## guessed at afterwards.
##
## **`0` IS "NO ANSWER" AND MUST NEVER BE A REFUSAL.** `get_unix_permissions` fails on Windows, where
## there is no such bit and a perfectly good `sim-relay.exe` would otherwise be refused -- which
## would break Play solo on the half of the audience I cannot test by hand. It also answers 0 for a
## path that does not exist, and that case already has its own sentence. So only a POSITIVE reading
## with the owner-execute bit clear is treated as a refusal.
static func is_runnable(binary: String) -> bool:
	var bits := FileAccess.get_unix_permissions(binary)
	return bits <= 0 or (bits & EXEC_OWNER) != 0


## **THE SENTENCE FOR A FILE THAT IS NOT MARKED EXECUTABLE**, which is a FACT about the file rather
## than a reading of how a child process died.
##
## IT DOES NOT CLAIM THE DOWNLOADED CAUSE, because that is not what this is: a downloaded file keeps
## its exec bit, and quarantine is a separate flag that refuses the exec of a file whose bit is set.
## Naming the wrong one of those two would send a player to clear something that was never set.
static func not_a_program(binary: String) -> String:
	return ("%s: the sim-relay file beside this client is not marked as a program this machine may "
			+ "run. %s The file is %s") % [CANNOT, JOIN_INSTEAD, binary]


## Start the relay and return false with `failure` set if it could not even be launched.
##
## `binary` and `deadline_ms` are arguments so the three refusals in ruling 6 can each be driven in a
## test with a stand-in process. Nothing about them is for production: `start_solo` fills them in.
func start(binary: String, extra: PackedStringArray, deadline_ms := DEFAULT_DEADLINE_MS) -> bool:
	_binary = binary
	_deadline_ms = deadline_ms
	address = ""
	failure = ""
	if binary == "":
		failure = ("%s: there is no sim-relay file next to this client. %s Looked in: %s"
				% [CANNOT, JOIN_INSTEAD, ", ".join(candidate_paths())])
		return false
	# **ASKED BEFORE SPAWNING, BECAUSE AFTERWARDS IT CANNOT BE KNOWN.** A file whose exec bit is clear
	# is a refusal with a cause the filesystem can be held to; the same case detected after a spawn is
	# a child that died, which is indistinguishable from a relay that ran and crashed. See `poll()`.
	if not is_runnable(binary):
		failure = not_a_program(binary)
		return false
	# THE SEED FIRST AND THE FLAGS AFTER, which is the relay's own documented order
	# (`sim-relay [seed] [--port N] [--tps N] [--fresh] [--bind ADDR]`) rather than a shape I chose.
	# It also keeps a stand-in process usable in a test: prepending flags made `/bin/sh -c ...`
	# reject `--bind` before it ever ran the script, so the only thing I could drive was the real
	# relay -- and ruling 6's sentences are exactly the cases the real relay will not produce.
	var args := extra.duplicate()
	args.append_array(PackedStringArray(["--bind", "127.0.0.1", "--port", "0"]))
	var pipe := OS.execute_with_pipe(binary, args)
	if pipe.is_empty() or int(pipe.get("pid", -1)) <= 0:
		# **THE ENGINE ITSELF SAYING IT COULD NOT START THE PROCESS, WHICH ON MACOS IT NEVER DOES.**
		# Measured: `execute_with_pipe` hands back a live pid for a non-executable file and for a path
		# that does not exist alike, so nothing reaches here on this platform. Kept because `pid <= 0`
		# is a real refusal if another platform does report one, and no refusal may be silent -- and
		# this is the one place where "the system would not run it" is the engine's own verdict rather
		# than my reading of a dead child. A missing exec bit is caught above instead, where it is a
		# fact; the quarantine case cannot be told apart from a crash at all (see `poll()`).
		failure = would_not_run(binary)
		return false
	pid = int(pipe["pid"])
	_stdio = pipe["stdio"]
	_stderr = pipe.get("stderr")
	_heard = PackedStringArray()
	_started_at = Time.get_ticks_msec()
	return true


## Start the relay solo would use: loopback, a free port, the friend seed, and its own save.
##
## NEVER `--fresh` (ruling 4). A second launch RESUMES, because a button that silently wiped the
## world you played yesterday is worse than one that cannot make a new one. A "New world" choice
## comes later and has to say what it destroys.
func start_solo(seed_text := DEFAULT_SEED, deadline_ms := DEFAULT_DEADLINE_MS) -> bool:
	DirAccess.make_dir_recursive_absolute(saves_dir())
	OS.set_environment("R2TS_SAVES_DIR", saves_dir())
	return start(find_binary(), PackedStringArray([seed_text]), deadline_ms)


## HAS IT SAID IT IS LISTENING YET. True once `address` is set; `failure` is set instead when the
## relay died or ran out of time. Called every frame; it reads a flag and a clock and nothing else.
func poll() -> bool:
	if address != "" or failure != "":
		return address != ""
	# THE WAITING BYTES FIRST, AND ONLY THEN THE PROCESS'S STATE. A relay that printed its address
	# and then died has still told us where it is, and joining it is the right answer; checking
	# liveness first would throw that away for no reason.
	while _stdio != null and _stdio.get_length() > _stdio.get_position():
		var line := _stdio.get_line()
		if line.begins_with(LISTENING):
			address = line.substr(LISTENING.length()).strip_edges()
			return true
		# EVERYTHING ELSE IS PROSE FOR A PERSON and is skipped rather than parsed. `main.rs` prints
		# "Hosting world N at tick ... on port ..." ABOVE the contract line, so a reader that took
		# the first line would have handed the join screen a sentence instead of an address -- which
		# is what my own test caught when it put the prose first on purpose.
		_heard.append(line)
	if has_exited():
		# ITS LAST WORDS IF IT HAD ANY. "It stopped" with no reason is the report nobody can act on,
		# and a relay that cannot bind says so on stderr before exiting.
		var said := _last_words()
		# **THERE IS NO HONEST WAY TO TELL A REFUSED EXEC FROM A RELAY THAT RAN AND DIED, HERE.** I
		# shipped one in ASSA-106 and it was a coin flip. `OS.execute_with_pipe` reports neither: it
		# hands back a live pid for a non-executable file AND for a path that does not exist, so the
		# `pid <= 0` guard in `start()` never fires on macOS -- the fork succeeds and the exec fails
		# inside the child. What the child leaves behind, measured twice on the same machine and
		# binary: Godot's own `Could not create child process` on 3 of 10 attempts and 0 of the next
		# 9; `libc++abi ... PAL_SEHException` (the .NET runtime in the forked child) on the rest;
		# exit code 6 where it exited at all; and twice a child that never exited inside 20 seconds.
		# CI exports with the plain Godot build, not the mono one I measure with, so that text is not
		# even the text a player's client would produce.
		#
		# AND THE SILENCE IS NOT A SIGNAL EITHER: `/bin/sh -c "exit 1"` -- a process that really did
		# run -- dies saying exactly as much as a failed exec does. So nothing here claims a cause.
		# The two causes that ARE facts are read before the spawn instead (`binary == ""` and
		# `is_runnable`), and the sentence below says only what was observed.
		#
		# WHAT WOULD MAKE IT PROVABLE, and it is one line in a file I do not own: if `sim-relay`
		# printed a marker as its FIRST action -- the way it prints `LISTENING` as its last -- then a
		# child that died without it never reached the relay's own code, and "the system would not run
		# it" would be a fact rather than a reading. Filed for Marlow rather than guessed at here.
		# THE OPEN DOOR COMES BEFORE THE QUOTE, not after it (Maren): the relay's last words are a
		# figure for a bug report, and a paragraph of them between the problem and what to do about
		# it buries the only clause a stranger acts on. Retry is NOT offered here -- a relay that
		# died on its own will die the same way on a second press.
		failure = "%s: it stopped before it was ready to join. %s" % [CANNOT, JOIN_INSTEAD]
		if said != "":
			failure += " It said: %s" % said
		return false
	if Time.get_ticks_msec() - _started_at > _deadline_ms:
		# A RUNNING PROCESS THAT WILL NOT SPEAK IS STILL A FAILURE, and it is the one a deadline
		# exists for. Killed rather than left behind: an orphan relay holding a port is worse than
		# the refusal, and the player is about to be told to try again.
		# AND THIS IS THE ONE CASE WHERE RETRY IS HONEST, because the `stop()` below is what makes it
		# so: the process is gone, so a second press starts from clean ground rather than fighting a
		# relay that is still holding a port.
		failure = ("%s: it did not say it was ready within %d seconds, so it has been stopped. %s"
				% [CANNOT, int(_deadline_ms / 1000.0), SOLO_AGAIN])
		stop()
		return false
	return false


## HAS THE RELAY EXITED. **`OS.get_process_exit_code` AND NOT `OS.is_process_running`, AND THE
## DIFFERENCE IS A ZOMBIE.**
##
## This process holds the child's pipe and does not wait on it, so an exited child can stay in the
## table and `is_process_running` answer TRUE for it -- measured: a `/bin/false` gone for 800ms still
## reported running on every poll, so "the relay died" was never noticed and the deadline fired with
## the wrong sentence. `get_process_exit_code` answers -1 while the child lives and the code once it
## is gone, and reaping it is also what lets the pipe stop blocking.
func has_exited() -> bool:
	return pid > 0 and OS.get_process_exit_code(pid) != -1


## Whatever the relay said before it stopped: its own stderr first, then any prose from stdout.
##
## STDERR FIRST because that is where `main.rs` puts the one failure a player can act on -- "Could
## not listen on 127.0.0.1:0" -- while stdout carries the greeting.
func _last_words() -> String:
	var said := PackedStringArray()
	if _stderr != null:
		while _stderr.get_length() > _stderr.get_position():
			var line := _stderr.get_line().strip_edges()
			if line != "":
				said.append(line)
	if said.is_empty():
		for line in _heard:
			var text := String(line).strip_edges()
			if text != "":
				said.append(text)
	return " / ".join(said)


## Stop the relay this client started, and leave nothing behind.
##
## THE THREAD IS WAITED ON, not abandoned. Killing the process closes the pipe, which is what ends
## the blocking `get_line` -- so the order matters: kill, then join.
func stop() -> void:
	if pid > 0 and not has_exited():
		OS.kill(pid)
	_stdio = null
	_stderr = null
	pid = -1
