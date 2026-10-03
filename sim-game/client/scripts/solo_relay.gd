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
		failure = ("no sim-relay next to this client, so there is nothing to play against. Looked in: "
				+ ", ".join(candidate_paths()))
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
		# A FILE THAT EXISTS AND WILL NOT RUN IS ITS OWN REFUSAL, and it is the one the board is most
		# likely to meet: macOS quarantine on an unsigned helper out of a downloaded zip refuses the
		# EXEC, not the open. Saying "missing" here would send them looking for a file that is there.
		failure = "found %s but the system would not run it" % binary
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
		failure = ("the relay stopped before it said it was listening"
				if said == "" else "the relay stopped and said: %s" % said)
		return false
	if Time.get_ticks_msec() - _started_at > _deadline_ms:
		# A RUNNING PROCESS THAT WILL NOT SPEAK IS STILL A FAILURE, and it is the one a deadline
		# exists for. Killed rather than left behind: an orphan relay holding a port is worse than
		# the refusal, and the player is about to be told to try again.
		failure = ("the relay started but has not said it is listening after %d seconds"
				% int(_deadline_ms / 1000.0))
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
