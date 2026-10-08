extends SceneTree
## CI: local -- a shot: --headless writes a blank frame and reports success
## A PICTURE OF THE REAL WINDOW, at 1:1, with no hands (ASSA-116 box 5).
##
##   godot --path . --script res://tools/window_shot.gd -- <out_dir> [seed] [ticks] [hoppers]
##
## `hoppers` is for ASSA-138 and is the one thing about the played world a caller may change: how
## many hoppers the loop MOUNTS on the drill it plants (default: every one it makes, which is what
## every other caller has always got). Three runs at 1, 2 and 4 are three real windows differing in
## one part count, which is what "a player can count the hoppers" has to be judged on.
##
## NOT `--headless`, AND THAT IS THE WHOLE POINT. Every other tool in here runs headless because it
## is asking what the client KNOWS. This one asks what the client LOOKS LIKE, and a dummy rendering
## driver answers that question with an empty image -- `--headless` reads back a blank frame and
## reports success, which is the most expensive kind of green there is.
##
## WHY IT EXISTS. Until now the only way to see this window was somebody's hands on this Mac
## (Decision #34, where the board had to open the app and describe it). So the look of the thing was
## the one part of the game nobody could iterate on: a change had to be exported, downloaded, opened
## and described back. Everything we have called a "1:1 render" (ASSA-83/99/105) was a drawing of a
## panel made beside the game, never the panel. This writes PNGs of the actual screen, so the Game
## Director can rule on a picture of what shipped.
##
## WHAT IT SHOOTS, and why these four:
##  - `01-join.png`   the first screen a stranger sees, before any press.
##  - `02-play.png`   mid-session, every panel carrying real content from a played world.
##  - `03-log.png`    the same screen with the event log open and the crafting menu folded away.
##  - `04-pack.png`   the fullest the pack and the crafting menu ever get in this play. NOT a state
##                    anyone asks for -- a moment the tool notices, for the reason below.
##
## THE LOG SHOT IS NOT OPTIONAL AND IT IS WHY `_shoot` REFUSES A REPEAT. The board's complaint is
## "logs are hard on the eyes", and the played session ENDS with the log hidden and the menu open --
## `AssayButtonPlay` presses those toggles itself on its way through the loop. So the first version
## of this script asked for a state the screen was already in, and wrote 02 and 03 as byte-identical
## files while reporting three shots taken. A set of pictures that silently contains the same picture
## twice is worse than a missing one: it reads as coverage.
##
## AND A SHOT CAN MISS ITS SUBJECT, WHICH IS THE SAME DEFECT ONE LAYER UP (Maren, ASSA-116/117).
## `03-log.png` is advertised as the screen with the log open, and for its whole life it contained no
## log: the section renders at y 1465..2134 of a 720px window, 745px below the bottom edge, with the
## toggle in the picture reading "hide the event log". Nothing was blank and nothing repeated, so
## every check here passed and the file read as coverage of the half the board complained about. So a
## shot now DECLARES THE SECTION IT IS NAMED FOR and the run does not finish OK if that section was
## ABSENT from the frame. The PNG is still written -- Maren's constraint, and the right one: the
## off-screen fact is the most useful thing this tool has ever told us, and refusing the capture
## would hide it.
##
## AND "ABSENT" IS NOT "CUT" (ASSA-149). A section the screen is deliberately clipping is reported
## and does not fail: ASSA-133 ruling 2 makes the crafting menu the section that gives way, so 04
## reported INCOMPLETE on a screen obeying the Game Director, which is a verdict nobody can use.
##
## WHY 04 EXISTS AND WHY IT IS A MOMENT, NOT A TICK. ASSA-117 asks for a populated pack row and a
## populated crafting row to be judged on a window. Limpet shot ticks 120, 250 and 481 looking for
## one and all three said "carrying nothing". Probed over the whole play, the cause is not the plan:
## 380 of 519 ticks are the SMELTING stretch with an empty pack, so a tick picked blind is 73% likely
## to be empty, and the fullest the two panels ever get (5 stacks + 5 offers) lasts about four ticks.
## A tick number is the wrong handle. So this re-takes 04 every time the two panels' row count rises,
## and the file left behind is the fullest moment of the run -- found by the play, not chosen by me.
## (Also measured, because it decides which seed a demo shot wants: the play lands with an EMPTY pack
## on the tool's own default seed 777042, and with 3 stacks and 5 offers on the pinned seed 14247.)
##
## THE WORLD IS OFFLINE AND PLAYED BY THE BUTTONS, borrowed whole from `tools/button_session.gd`:
## this script is the relay, and `AssayButtonPlay` presses the screen's own controls. So the panels
## are full of what a player's panels would hold, not of a fixture I typed. A shot of a world nobody
## played would flatter every panel that only looks wrong once it has rows in it.
##
## Prints `WINDOW SHOT OK` LAST and only when no shot was MISSING its subject, because Godot exits 0
## even on a compile error. A set missing a subject ends `WINDOW SHOT INCOMPLETE` and exits 1; a set
## whose subjects are all present but one is cut by the frame ends `WINDOW SHOT OK (cut, not missing
## -- ...)` and exits 0, naming what was cut and how much of it was in frame.

## Frames to let pass before reading the viewport back. One is not enough: the screen is built from
## containers, and a container lays its children out on the frame AFTER they are added, so a capture
## on frame 1 catches every row at position zero, stacked on the origin. Three is slack, not science.
const SETTLE_FRAMES := 3
## Offline ticks to allow, the same budget `button_session.gd` uses for the same chain.
const PLAY_TICKS := 4000
## Ticks played per frame while the world runs. The play used to happen inside ONE `_process` call,
## which cannot work now: 04 is read back mid-play, and a container that gained rows this tick has
## not laid them out until the next frame. So the loop yields, and this is how coarse that is.
const TICKS_PER_FRAME := 32
const DEFAULT_SEED := "777042"

enum Phase { SETTLE_JOIN, SHOOT_JOIN, PLAY, SETTLE_PACK, SHOOT_PACK, SETTLE_PLAY, SHOOT_PLAY,
		SETTLE_FOLD, MEASURE_CONTROLS, SETTLE_MENUS, SHOOT_MENUS, SCROLL_ROCKS, SETTLE_ROCKS,
		SHOOT_ROCKS, PRESS_V, SETTLE_V, SHOOT_WHOLE_WORLD, DONE }
## What `_play_frames` did with its last tick.
enum Ticked { AGAIN, OVER, DEAD }

var _screen: Node
var _play: AssayButtonPlay
var _asked: Array = []
var _out := ""
var _seed := DEFAULT_SEED
var _ticks := PLAY_TICKS
var _phase: Phase = Phase.SETTLE_JOIN
var _waited := 0
var _shots := PackedStringArray()
## Fingerprint of every frame already written, to the name it was written under. See `_shoot`.
var _taken := {}
## Shot name -> what its own subjects were doing instead of being on screen. Keyed by name and
## rewritten on a re-take, because `04-pack.png` is taken several times and only the LAST one is the
## file on disk: a complaint about a version that was overwritten would be a lie about the set.
var _missing := {}
## Shot name -> which of its subjects the screen is CUTTING rather than omitting (ASSA-149). Same
## keying and same re-take rule as `_missing`; the difference is that this one does not fail the
## run, it is carried into the final line so a reader is told rather than left to find out.
var _clipped := {}
## Set only by `_report`, so a dead run and a complete-but-blind set never wear each other's word.
var _incomplete := false
var _started := false
var _left := 0
## High-water mark of pack rows + crafting rows, and the tick it was reached on. See `04-pack.png`.
var _rows_best := 0
var _rows_tick := -1
## WHERE EVERY CONTROL STOOD BEFORE THE LOG WAS OPENED (ASSA-147). Keyed by node path so two buttons
## reading "Craft" cannot be mistaken for one, and taken with the crafting menu already folded so the
## only difference between this and the after reading is the log. See `_controls_report`.
var _controls_before := {}
## AND WHERE THEY STOOD THE FRAME THE LOG WAS OPEN, taken at the shot rather than read live in
## `_report` (ASSA-143). The claim is about the moment after the log opened, so the reading has to be
## from that moment: reading the screen at report time was only ever right because nothing touched
## the screen afterwards, and the roster shot does -- it scrolls the column, which moved all eight
## buttons and made the log look like it had evicted them. A baseline that is correct by luck is one
## phase away from a confident false report, which is the same shape as measuring a log section
## against the window when a scroll box 100px smaller is what clips it (ASSA-117).
var _controls_after := {}
var _done := false


## **A WALL-CLOCK CEILING, AND IT IS A MEMBER INITIALIZER** (ASSA-182). A `SceneTree` whose
## `_initialize` dies still gets `_process` every frame -- Godot exits 0 on a parse error and does not
## exit AT ALL on a runtime error in `_initialize` -- so a tool waiting on a phase that `_initialize`
## never set up waits for ever, holding a window, a relay and a port. Set at the end of `_initialize`
## it would be absent in exactly the case it is for.
##
## **ASSA-182's OWN SCOPE WAS WRONG ABOUT THIS FILE**: it said window_shot "has something of the kind
## already", because a grep for "ceiling" matched `AssayScene.player_ceiling`, which is a layout number
## in pixels and has nothing to do with time. A word matched; nothing was measured.
##
## 600 s, double the probes', because this tool joins a world, walks a body and settles a dozen phases
## before it writes its last PNG; a shot run of 90-120 s is normal and a loaded Mac triples it.
const RUN_CEILING := 600.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_finish(false, "usage: -- <out_dir> [seed] [ticks]")
		return
	_out = String(argv[0])
	_seed = String(argv[1]) if argv.size() > 1 else DEFAULT_SEED
	_ticks = int(argv[2]) if argv.size() > 2 else PLAY_TICKS
	_left = _ticks
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_finish(false, "cannot write to %s" % _out)
		return

	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, for the reason `tools/button_session.gd` and `tests/test_main_screen.gd`
	# both give: a `--script` run works inside `SceneTree._initialize`, before the root window is in
	# the tree, so the engine's own call comes too late. The screen is built once however often.
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)
	if argv.size() > 3:
		_play.hoppers = int(argv[3])
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])
	# **WHAT THIS PICTURE IS EVIDENCE ABOUT** (ASSA-141 box 3, Maren's ruling).
	#
	# Until now this report named the window size, the shots and the fold verdict, and nothing about
	# the RULES the shot was taken on -- so a screenshot could be filed, argued over and acted on
	# without anyone able to say which build drew it. `client/bin` is git-ignored, so the
	# `libsim_godot` each of us runs is whatever we last built and no commit pins it. On ASSA-137
	# that cost a wake-up and nearly cost a design reversal: three honest screenshots on a correct
	# branch showed a fire state that is LIT for 379 of 435 ticks on main.
	#
	# IT COST ME ONE TODAY TOO, and that is why this line is one `print` and not a discussion. My own
	# dylib predated the merge of #231 by seven minutes; the client suite came back red on a key the
	# binding had just started sending, and for a minute I had a red `main` and a message half
	# written to the person who merged it. `test_hud.gd::test_the_tile_fixture_still_matches_a_real_
	# tile` is what caught it -- a test that asks the BINDING what a tile looks like instead of
	# trusting a fixture. That is the shape ASSA-141 box 4 asks for, and it already exists.
	#
	# BOTH NUMBERS COME FROM THE BINDING, never from a constant on this side (`protocol.gd`'s own
	# rule): a provenance line that could be stale would be worse than none, because it would make a
	# stale shot look pinned.
	print("rules %s, protocol %d, godot %s" % [AssayProtocol.rules_id(),
			AssayProtocol.protocol_version(), Engine.get_version_info()["string"]])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  maren_schematic_demo_shot.gd ran past its %ds ceiling in phase %d: nothing advanced it"
				% [int(RUN_CEILING), _phase])
		quit(1)
		return true
	match _phase:
		Phase.SETTLE_JOIN:
			_settle(Phase.SHOOT_JOIN)
		Phase.SHOOT_JOIN:
			# NO SUBJECT. This shot is named for a state, not for a section: it is the whole first
			# screen, and every section in it is part of the claim.
			_shoot("01-join.png", PackedStringArray())
			_phase = Phase.PLAY
		Phase.PLAY:
			_play_frames()
		Phase.SETTLE_PACK:
			_settle(Phase.SHOOT_PACK)
		Phase.SHOOT_PACK:
			# THE SUBJECTS ARE THE TWO PANELS THE ROWS ARE IN, which is the whole point of the shot:
			# a fullest-pack picture whose pack is below the fold is worth nothing to ASSA-117.
			_shoot("04-pack.png", PackedStringArray(["you", "crafting menu"]), false)
			_phase = Phase.PLAY
		Phase.SETTLE_PLAY:
			_settle(Phase.SHOOT_PLAY)
		Phase.SHOOT_PLAY:
			_shoot("02-play.png", PackedStringArray())
			# THE OTHER STATE, and it has to be the OPPOSITE of whatever the loop left behind.
			# `AssayButtonPlay` folds the log away and opens the menu as it plays, so asking for
			# that state again photographs the same screen twice.
			#
			# **THE TWO PRESSES ARE NO LONGER ONE STEP, AND THAT IS ASSA-147'S VERDICT NEEDING AN
			# HONEST BASELINE.** Folding the crafting menu legitimately moves every control below it;
			# opening the log must move none. Pressed together, the only measurement available would
			# be the sum of the two, which would read as a moved control whatever the log did. So the
			# menu folds here, the controls are measured once that has settled, and only then does the
			# log open.
			_screen._show_make(false)
			_phase = Phase.SETTLE_FOLD
		Phase.SETTLE_FOLD:
			_settle(Phase.MEASURE_CONTROLS)
		Phase.MEASURE_CONTROLS:
			_controls_before = _controls_now()
			_screen._show_log(true)
			_phase = Phase.SETTLE_MENUS
		Phase.SETTLE_MENUS:
			_settle(Phase.SHOOT_MENUS)
		Phase.SHOOT_MENUS:
			_shoot("03-log.png", PackedStringArray(["event log"]))
			# THE AFTER READING IS TAKEN HERE, in the settled frame the log is open and nothing else
			# has moved. See `_controls_after`.
			_controls_after = _controls_now()
			_phase = Phase.SCROLL_ROCKS
		Phase.SCROLL_ROCKS:
			# THE LOG PANEL COMES BACK DOWN FIRST. It sits over the map, not over the column, so it
			# does not clip the rocks -- but a picture of the roster with a log panel across the
			# middle of it is a picture of two things, and the one being judged is the rows.
			_screen._show_log(false)
			_scroll_to_rocks()
			_phase = Phase.SETTLE_ROCKS
		Phase.SETTLE_ROCKS:
			_settle(Phase.SHOOT_ROCKS)
		Phase.SHOOT_ROCKS:
			# NO SUBJECT, AND NOT BECAUSE THE CLAIM IS WEAKER. `rocks` is 713px in a 654px box, so
			# `_standing` can only ever call it CLIPPED and a subject check here would be a box that
			# cannot go green -- the opposite failure to 03-log's, which was green over an empty
			# frame. `_rocks_report` guards it instead, and asks for MORE: two whole ROWS in the
			# frame, which is the least a picture needs to show that two rocks differ.
			_shoot("05-rocks.png", PackedStringArray())
			_phase = Phase.PRESS_V
		Phase.PRESS_V:
			# THE SECOND VIEW OF THE WORLD, WHICH THIS SCRIPT HAS NEVER PHOTOGRAPHED (ASSA-188).
			# The press itself, not `_show_close_up`, so this is what a person's click does.
			_screen._view_toggle.emit_signal("pressed")
			_phase = Phase.SETTLE_V
		Phase.SETTLE_V:
			_settle(Phase.SHOOT_WHOLE_WORLD)
		Phase.SHOOT_WHOLE_WORLD:
			# NO SUBJECT: the schematic has no named section, it is the whole map rect.
			_shoot("06-whole-world.png", PackedStringArray())
			print("close_up=%s  toggle=%s  buildings in sim=%d"
					% [_screen._close_up, _screen._view_toggle.text, _screen._sim.buildings().size()])
			_phase = Phase.DONE
		Phase.DONE:
			_report()
	return _done


## Let the layout catch up, then move on. Counted in frames because that is what a container needs.
func _settle(then: Phase) -> void:
	_waited += 1
	if _waited >= SETTLE_FRAMES:
		_waited = 0
		_phase = then


## OFFLINE: THIS SCRIPT IS THE RELAY. Lifted from `button_session.gd::_run_offline`, which is the
## reference for this handshake; the one difference is that a failure here is a dead shot rather
## than a failed claim about the loop, so it says which step it died on.
func _begin_offline() -> bool:
	var welcome := AssaySimHost.fresh_welcome_json(_seed, "marlow")
	if welcome == "":
		_finish(false, "could not make a world on seed %s" % _seed)
		return false
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		_finish(false, "offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return false
	return true


## PLAY A SLICE OF THE WORLD, then hand the frame back so containers can lay out. Returns to the
## engine either because the slice is spent, because the pack just got fuller (04), or because the
## loop is over.
func _play_frames() -> void:
	if not _started:
		if not _begin_offline():
			return
		_started = true
	for _i in range(TICKS_PER_FRAME):
		if _left <= 0:
			_end_play()
			return
		_left -= 1
		match _tick_once():
			Ticked.DEAD:
				return
			Ticked.OVER:
				_end_play()
				return
		# THE HIGH-WATER MARK, read off the SIM and not off the labels. A panel's own text is what
		# this shot is evidence about, so asking the panel whether it has rows would be asking the
		# thing under test. `inventory_of` + `make_offers` are what `_refresh_pack` and
		# `_refresh_make` draw from, so this counts the rows the screen is about to have.
		var rows := _rows_now()
		if rows > _rows_best:
			_rows_best = rows
			_rows_tick = _screen._sim.tick()
			_phase = Phase.SETTLE_PACK
			return


## One tick: let the loop press at most one button, send what it pressed, step, feed it back.
func _tick_once() -> Ticked:
	_play.advance()
	if _play.finished:
		return Ticked.OVER
	var inputs := []
	for command in _asked:
		inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
	_asked.clear()
	var at: int = _screen._sim.tick()
	var before: int = _screen._sim.applied
	_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
	if _screen._sim.applied == before:
		_finish(false, "the sim refused the bundle for tick %d" % at)
		return Ticked.DEAD
	return Ticked.AGAIN


func _rows_now() -> int:
	if _screen._client == null:
		return 0
	var stacks: Array = _screen._sim.inventory_of(_screen._client.player_id)
	var offers: Array = _screen._sim.make_offers(_screen._client.player_id)
	return stacks.size() + offers.size()


func _end_play() -> void:
	if _play.failed != "":
		_finish(false, "the loop stopped: %s" % _play.failed)
		return
	# WHAT THE PLAY DID WITH THE DRILL, IN THE SIM'S OWN WORDS. `step DONE` is not the same news as
	# "a machine is standing there": the loop plants whatever it built and the SIM decides whether
	# the design survives its own mass. A run whose drill came apart has an empty map and a perfectly
	# healthy-looking final line, which is how I nearly reported an invisible machine as a drawing
	# bug when the sim had simply refused to keep it (ASSA-138).
	print("  played seed %s to tick %d, step %s; verdict %s; %s"
			% [_seed, _screen._sim.tick(), AssayButtonPlay.Step.keys()[_play.step],
			_play.planted_verdict if _play.planted_verdict != "" else "(none read)",
			_play.outcome if _play.outcome != "" else "(no outcome)"])
	_phase = Phase.SETTLE_PLAY


## READ THE FRAME BACK AND WRITE IT OUT, refusing a blank one, refusing a repeat, and saying when
## the picture cannot contain what it is named for.
##
## THREE WAYS A SET OF SHOTS LIES, and all three have already happened to me here.
##
## BLANK: a render that produced an empty image. That is exactly what `--headless` does, and a PNG
## of nothing is indistinguishable from a PNG of a screen until somebody opens it. So a frame has to
## carry more than one colour before this calls it a shot.
##
## REPEAT: the screen was asked for a state it was already in, so two named shots are the same
## picture. Nothing is blank, every count looks healthy, and the set reads as covering two states
## while covering one. Comparing the bytes is the only thing that catches it, and it is cheap.
##
## SUBJECT MISSING: the state was reached, the picture is different, and the section the file is
## NAMED for is off the bottom of the window. Every other check passes. `03-log.png` was this for its
## whole life. The shot is still written; the run does not end OK.
##
## SUBJECT CUT is the third of those and not a softer second (ASSA-149): the section IS in the frame
## and the frame does not hold all of it. Reported with the share in frame, and the run still ends
## OK -- see `_shoot` for why the crafting menu makes that the only honest reading.
##
## `guard_repeat` is false for `04-pack.png` alone, and not as a favour to it: 04 is a moment the
## tool NOTICES, re-taken whenever the pack grows, so a duplicate frame there is a fact about the
## play (the fullest pack was also the final state) and not a state asked for twice. The repeat
## guard answers "was the screen asked for something it was already showing", which 04 never asks.
func _shoot(name: String, subjects: PackedStringArray, guard_repeat := true) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		_finish(false, "%s: no frame to read" % name)
		return
	var seen := {}
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			seen[image.get_pixel(x, y).to_rgba32()] = true
	if seen.size() < 2:
		_finish(false, "%s: the frame is one flat colour, so nothing drew" % name)
		return
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(image.get_data())
	var fingerprint := hasher.finish().hex_encode()
	if guard_repeat:
		if _taken.has(fingerprint):
			_finish(false, "%s is pixel-identical to %s: the screen was asked for a state it was "
					% [name, _taken[fingerprint]] + "already in, so this pair shows one state, "
					+ "not two")
			return
		_taken[fingerprint] = name
	var path := "%s/%s" % [_out, name]
	if image.save_png(path) != OK:
		_finish(false, "cannot write %s" % path)
		return
	var line := "%s  %dx%d  %d colours  %s" % [name, image.get_width(), image.get_height(),
			seen.size(), fingerprint.substr(0, 12)]
	if name == "04-pack.png":
		line += "  %d rows at tick %d" % [_rows_best, _rows_tick]
	_shots.append(line)
	# THE SUBJECT CHECK, at the moment of the shot, because the geometry is only true then: 04 is
	# taken mid-play and the column it photographs is a different height by the end.
	_missing.erase(name)
	_clipped.erase(name)
	for subject in subjects:
		var control := _section(subject)
		if control == null:
			_finish(false, "%s names the section %s, which this screen does not have"
					% [name, subject])
			return
		var where := _standing(control)
		var rect := control.get_global_rect()
		# HOW MUCH OF IT THE FRAME ACTUALLY HOLDS, printed on the clipped rows, because "CLIPPED"
		# covers everything from one cut pixel to one visible one and those are not the same news.
		var share := ""
		if where == "CLIPPED":
			var held := _frame_for(control).intersection(rect)
			var whole := maxf(1.0, rect.size.x * rect.size.y)
			share = "  (%d%% of it in frame)" % int(round(100.0 * held.size.x * held.size.y / whole))
		_shots.append("    subject %-14s y %5d..%-5d  %s%s"
				% [subject, rect.position.y, rect.end.y, where, share])
		# **THREE VERDICTS, NOT TWO** (ASSA-149; Maren's second option, which Marlow would also have
		# built). `CLIPPED` and `OFF SCREEN` were one failure, and they are different facts:
		#
		#  - ABSENT -- `hidden`, or no intersection at all -- is the rule that earned this check its
		#    keep, and it is UNCHANGED. `03-log.png` was advertised as the screen with the log open
		#    and contained no log for its whole life: the section sat at y 1465..2134 of a 720px
		#    window, 745px BELOW the bottom edge. No intersection, so that case is OFF SCREEN and
		#    still fails today. Nothing here relaxes it to "the file was written".
		#
		#  - CLIPPED is a section the screen is deliberately cutting. ASSA-133 ruling 2 says the
		#    crafting menu is the section that gives way, because `make_offers` grows faster than
		#    the pack -- so `04-pack.png`, the shot this tool goes out of its way to find, reported
		#    INCOMPLETE on a screen obeying the Game Director. **A verdict that is red whenever the
		#    pack is full is red on most interesting runs, and a check that cries wolf gets
		#    regenerated blind** (Cove, ASSA-132).
		#
		# So a cut section is REPORTED and does not fail. The information is kept, which is the
		# whole difference between this and dropping the crafting menu as a subject -- that would
		# have bought the green by spending the fact.
		if where == "CLIPPED":
			var cut: PackedStringArray = _clipped.get(name, PackedStringArray())
			cut.append("its %s is cut, %s" % [subject, share.strip_edges().trim_prefix("(").trim_suffix(")")])
			_clipped[name] = cut
		elif where != "on screen":
			var said: PackedStringArray = _missing.get(name, PackedStringArray())
			said.append("its %s is %s" % [subject, where])
			_missing[name] = said


## THE SECTIONS OF THE SCREEN, by the name a person would use for them. One list, because the fold
## report and the subject check have to be asking about the same thing.
##
## SIX OF THEM ARE THE HUD COLUMN AND THE SEVENTH IS NOT ANY MORE (ASSA-147): `event log` is
## `_log_box`, the panel over the map, and it is named here as the SURFACE rather than as the lines
## inside it. That is the node a player sees and the node `_show_log` raises, so "the log is on
## screen" is a question about it. Asking `_log` instead would be asking a child whose own rect is
## honest about a panel that may not be up.
func _sections() -> Array:
	return [["crafting menu", _screen._make], ["you", _screen._carrying], ["do", _screen._actions],
			["bench", _screen._bench], ["mineralogy", _screen._species], ["cursor", _screen._cursor],
			["event log", _screen._log_box]]


func _section(named: String) -> Control:
	for part in _sections():
		if String(part[0]) == named:
			return part[1] as Control
	return null


## THE RECT A CONTROL CAN ACTUALLY BE SEEN IN: the window, narrowed by every ancestor that clips.
##
## MEASURING AGAINST THE WINDOW ALONE IS THE NARROWER QUESTION, and it let a true answer hide a
## defect (Limpet, ASSA-117): the HUD column lives in a `ScrollContainer` whose box ends well above
## the bottom of the window, so a section can sit inside the window and still be cut by the scroll's
## own edge -- which is exactly what the first log line does once the reveal scrolls to it.
##
## The `ScrollContainer` clause is belt and braces and MEASURED TO BE REDUNDANT TODAY: the engine
## sets `clip_contents` on a `ScrollContainer` itself, and dropping the clause leaves the clip rect
## at exactly y 124..696. It stays because a scroll box clips whatever a flag says, and a flag
## somebody turns off should not quietly widen this measure back to the window.
func _frame_for(control: Control) -> Rect2:
	var frame := Rect2(Vector2.ZERO, root.size)
	var node: Node = control.get_parent()
	while node != null:
		var ancestor := node as Control
		if ancestor != null and (ancestor.clip_contents or ancestor is ScrollContainer):
			frame = frame.intersection(ancestor.get_global_rect())
		node = node.get_parent()
	return frame


## WHERE A CONTROL STANDS: `hidden`, `OFF SCREEN`, `CLIPPED` or `on screen`.
##
## **IT ASKS THE NODE'S OWN `visible` FLAG, NOT `is_visible_in_tree`, AND THE DIFFERENCE MATTERS FOR
## EXACTLY ONE READER.** Every section this reports on is a direct child of the column or of the
## screen, so its own flag and its tree visibility agree. The controls INSIDE a folded container do
## not -- a Craft button in a hidden crafting menu is `visible` with nothing on screen -- so
## `_controls_now` asks the stronger question for itself rather than widening this one, which three
## verdicts in this file already depend on. The docstring used to claim this answered "a person can
## see it"; it answers "is this node's rect inside the rect it could be seen in".
func _standing(control: Control) -> String:
	if not control.visible:
		return "hidden"
	var frame := _frame_for(control)
	var rect := control.get_global_rect()
	if not frame.intersects(rect):
		return "OFF SCREEN"
	if not frame.encloses(rect):
		return "CLIPPED"
	return "on screen"


## WHAT IS ACTUALLY ON SCREEN, as a number rather than as my reading of a picture.
##
## A shot shows what is visible; it cannot show what is MISSING, and the two look the same. The
## first set of shots here caught the event log being nowhere on screen with its own toggle reading
## "hide the event log" -- `_log.visible` was true and the section was simply below the bottom of a
## scrolling column that overflows a 720px window. That is invisible to every test we have, because
## every one of them asks the node and the node answers honestly.
##
## So each named section reports its rect against the rect it can be seen in. Where that is smaller
## than the window, the line says so, because "the window cut it" and "the scroll box cut it" are
## different defects with different fixes.
func _fold_report() -> void:
	var window := Rect2(Vector2.ZERO, root.size)
	# THE TWO RECTS EVERY LINE BELOW IS JUDGED AGAINST, printed so the verdicts can be checked by
	# arithmetic rather than believed.
	var clip := _frame_for(_screen._carrying)
	print("  window         y %5d..%-5d  clip (what the scroll box leaves) y %5d..%-5d"
			% [window.position.y, window.end.y, clip.position.y, clip.end.y])
	for part in _sections():
		var control: Control = part[1]
		var rect := control.get_global_rect()
		var where := _standing(control)
		var why := ""
		if (where == "CLIPPED" or where == "OFF SCREEN") and window.encloses(rect):
			why = "  (by the scroll box, not the window edge)"
		print("  section %-14s y %5d..%-5d  %s%s"
				% [part[0], rect.position.y, rect.end.y, where, why])


## **DID PRESSING "SHOW THE EVENT LOG" LEAVE THE LOG WHERE A STRANGER CAN READ IT** (Limpet,
## ASSA-117; Maren's ruling 1 on that item, in the shape she asked for it: *proved by reading the
## scroll offset back*, not by asserting `visible`).
##
## THIS IS THE LEVER THE CLIENT SUITE CANNOT HOLD. `tests/run_tests.gd` works inside
## `SceneTree._initialize`, so `_ready` never fires, no frame is ever drawn and no container ever lays
## out -- a headless test can ask a node whether it is visible and gets an honest yes about a section
## 745px below the bottom edge. When I mutated the reveal away, every one of 191 tests stayed green.
## A real window is the only thing that can fail here, so the verdict lives in the tool that has one.
##
## TWO PROPERTIES, AND THE SECOND IS THE ONE THAT CAUGHT ME. The heading has to be inside the
## viewport, or you have arrived somewhere without being told where. And the TOP of the body has to be
## inside it too: the log is newest-first, so a body whose top is clipped is a log whose NEWEST line
## is the one torn in half -- the single line the player pressed the button to read.
##
## IT ASKS `_frame_for` AND NOT THE SCROLL BOX. Marlow and I wrote the same clip-rect fix within the
## hour (ASSA-123, #165); theirs walks every clipping ancestor instead of naming one node, so a second
## clipping container one day is already covered and this verdict inherits that for free.
##
## **SINCE ASSA-147 THE LOG IS NOT IN THE SCROLL BOX AT ALL**, so there is no scroll offset to read
## back and the heading cannot be scrolled anywhere. The two properties survive unchanged -- the
## heading has to be on screen, and the newest line has to be whole -- and a third is added, because
## the log is now a panel over the map and a panel that outgrew its region would cover the HUD column
## or run off the top of the window. That bound is measured here rather than written into a constant.
func _reveal_report() -> bool:
	var heading: Label = _screen._log_heading as Label
	var box: Control = _screen._log_box as Control
	if box == null or heading == null:
		_finish(false, "no log panel or no log heading on the screen, so the reveal cannot be judged")
		return false
	var clip := _frame_for(heading)
	var head := heading.get_global_rect()
	var body := (_screen._log as Control).get_global_rect()
	var panel := box.get_global_rect()
	var map := AssayHud.world_rect()
	print("  reveal: panel %s %s in the map's %s %s; seen-in y %d..%d; heading y %d..%d; body top y %d"
			% [panel.position, panel.size, map.position, map.size, clip.position.y, clip.end.y,
			head.position.y, head.end.y, body.position.y])
	if not clip.encloses(head):
		_finish(false, ("the log's own heading is at y %d..%d, outside the rect it can be seen in "
				+ "(y %d..%d): pressing 'show the event log' left you somewhere without saying where")
				% [head.position.y, head.end.y, clip.position.y, clip.end.y])
		return false
	if body.position.y < clip.position.y - 0.5:
		_finish(false, ("the log's first line starts at y %d, above the y %d it can be seen from, so "
				+ "the NEWEST line is the one clipped in half") % [body.position.y, clip.position.y])
		return false
	# THE PANEL'S OWN BOUND, GROWN FROM ITS CONTENT AND THEREFORE NOT GUARANTEED BY ARITHMETIC. The
	# height is whatever fourteen lines need at this font and width -- 350-odd px of the 600 the map
	# gives it when it was measured -- so a bigger font, a longer line or a higher `LOG_LINES` is what
	# would push it out, and this is the line that would say so instead of a reader noticing.
	if not map.grow(1.0).encloses(panel):
		_finish(false, ("the log's panel is %s %s, outside the map's %s %s: it has outgrown the "
				+ "surface it is drawn over, so it is covering the HUD column or the window's edge")
				% [panel.position, panel.size, map.position, map.size])
		return false
	# **AND IT MAY NOT REACH YOUR OWN BODY (ASSA-156).** The panel is inside the map and was still
	# covering the one tile the camera guarantees you are standing on: Maren shot seed 777042 and
	# counted ZERO player pixels anywhere in the map with the log open, against 199 with it closed.
	#
	# THIS IS THE ONLY PLACE THE CLAIM CAN BE CHECKED AGAINST A LAID-OUT PANEL. `_log_box`'s height
	# is the engine's answer to its content and `Control.update_minimum_size` is deferred, so in the
	# suite -- inside `SceneTree._initialize`, no idle frame -- the box reports 12px for a 342px
	# panel. Every headless test about this bound is a test of the arithmetic that chose the line
	# count; this is the rectangle the player gets.
	var ceiling := AssayScene.player_ceiling(AssaySprites.manifest(), map.size)
	if ceiling > 0.0 and panel.end.y > map.position.y + ceiling + 0.5:
		_finish(false, ("the log's panel ends at y %d, below the y %d your own body is drawn from "
				+ "at an unclamped camera: the log is covering the tile you are standing on, which "
				+ "is the tile its newest line is usually about (ASSA-156)")
				% [panel.end.y, map.position.y + ceiling])
		return false
	return true


## **DOES OPENING THE EVENT LOG TAKE A CONTROL OFF THE SCREEN** (ASSA-147, Maren's box 4 in the shape
## she wrote it: *a test fails if any control leaves the screen when the log is toggled*).
##
## WHAT IT IS ABOUT, measured on this tool before the fix: at seed 14247 tick 519 with the log open,
## `you` was at y -1046..-894, `do` (Mine, Stop, Assay) at y -852..-802 and `bench` at y -690..-549.
## The log was the last section of a 2023px column in a 650px scroll box, so revealing it scrolled
## 1120px to the bottom and took every control with it.
##
## TWO FAILURES, AND THE SECOND IS THE STRICTER ONE ON PURPOSE. A control whose standing gets WORSE
## is Maren's defect exactly. A control that merely MOVED is the mechanism of it: on this seed the
## column happens to be long enough that a scroll carries the controls clean off, but on a shorter one
## the same bug would move them a little and read as green. So a move fails too, and the sentence says
## which of the two it is -- a deliberate future design that moves a control on this toggle should
## have to come and change this line.
##
## IT CANNOT PASS VACUOUSLY: an empty before-set is a failure, because a run that found no controls
## would otherwise be the quietest green in this file.
## THE ROSTER DOES NOT FIT IN THE COLUMN AND NEVER WILL, so a picture of it is a SCROLLED picture
## (ASSA-143). Measured on seed 152: `rocks` is y 541..1254, a 713px section in a 654px scroll box,
## so the unscrolled shots show about one row of six. A player scrolls to read the rest; so does
## this.
##
## THE OFFSET IS ASKED OF THE ENGINE, NOT COMPUTED FROM WHAT I THINK THE LAYOUT IS: the section's
## current top minus the box's top is how far it has to travel, added to where the box already is.
## `ensure_control_visible` is deliberately NOT used -- it does the MINIMUM scroll, which for a
## section TALLER than the box parks its BOTTOM at the bottom edge and cuts the first row off, and
## the first row is as much a part of the roster as any other (I was bitten by exactly this
## minimum-scroll behaviour on the log heading, ASSA-117).
func _scroll_to_rocks() -> void:
	var rocks: Control = _screen._species
	var box: ScrollContainer = null
	var node: Node = rocks.get_parent()
	while node != null:
		if node is ScrollContainer:
			box = node as ScrollContainer
			break
		node = node.get_parent()
	if box == null:
		print("  rocks: no scroll box above the roster, so nothing was scrolled")
		return
	var was := box.scroll_vertical
	box.scroll_vertical = was + int(rocks.get_global_rect().position.y
			- box.get_global_rect().position.y)
	print("  rocks: scrolled the column from %d to %d to bring the roster to the top of the box"
			% [was, box.scroll_vertical])


## WHAT THE WINDOW SAYS ABOUT EACH ROCK, IN ITS OWN LABELS, and how much of each row is in the frame
## (ASSA-143 box 2: the window and `sim-cli` must say the same thing about a fuel-at-B and a
## fuel-at-A species, shown rather than described).
##
## THE TEXT IS READ OFF THE LABELS RATHER THAN OFF THE BINDING, which is the only reading that can
## contradict the binding. Asking `species_sheets()` again would print what the client was handed
## and call it what the player sees -- the same mistake as a byte-identity check between two
## surfaces that both compose from one wrong source (Marlow, ASSA-135).
##
## THE VERDICT IS "AT LEAST TWO ROWS WHOLE", not "the section is on screen", because the section
## cannot be: it is taller than the box. Two is the smallest number that can show the thing a roster
## panel exists for -- that two rocks are described differently. A guard of "one" would pass on a
## picture that cannot answer any comparison, and a guard of "all six" could never pass at all.
func _rocks_report() -> bool:
	var rocks: Control = _screen._species
	var frame := _frame_for(rocks)
	var whole := 0
	var rows := 0
	for child in rocks.get_children():
		var row := child as Control
		if row == null:
			continue
		var titles := row.find_children("SpeciesLine", "Label", true, false)
		if titles.is_empty():
			continue
		rows += 1
		var said := PackedStringArray()
		for label in row.find_children("*", "Label", true, false):
			var text := String((label as Label).text)
			if text != "":
				said.append(text)
		var rect := row.get_global_rect()
		var standing := "whole"
		if not frame.encloses(rect):
			standing = "CUT" if frame.intersects(rect) else "OFF SCREEN"
		else:
			whole += 1
		print("    row %-5s y %5d..%-5d  %s" % [standing, rect.position.y, rect.end.y,
				" ".join(said)])
	print("  rocks: %d rows, %d whole in the frame y %d..%d" % [rows, whole, frame.position.y,
			frame.end.y])
	if whole < 2:
		_finish(false, ("the roster shot shows %d whole rows of %d, so no two rocks in it can be "
				+ "compared") % [whole, rows])
		return false
	return true


func _controls_report() -> bool:
	var after := _controls_after
	print("  controls: %d before the log opened, %d after" % [_controls_before.size(), after.size()])
	if after.is_empty():
		_finish(false, "no controls were measured while the log was open, so 'the log moves no "
				+ "control' is a claim about nothing")
		return false
	if _controls_before.is_empty():
		_finish(false, "no controls were measured before the log opened, so 'the log moves no "
				+ "control' is a claim about nothing")
		return false
	var worse := PackedStringArray()
	var moved := PackedStringArray()
	for key in _controls_before:
		var was: Dictionary = _controls_before[key]
		if not after.has(key):
			worse.append("%s is gone from the screen entirely" % was["said"])
			continue
		var now: Dictionary = after[key]
		if was["where"] == "on screen" and now["where"] != "on screen":
			worse.append("%s was on screen and is now %s (y %d..%d, was y %d..%d)"
					% [was["said"], now["where"], (now["rect"] as Rect2).position.y,
					(now["rect"] as Rect2).end.y, (was["rect"] as Rect2).position.y,
					(was["rect"] as Rect2).end.y])
		elif not (was["rect"] as Rect2).is_equal_approx(now["rect"]):
			moved.append("%s moved from y %d to y %d" % [was["said"],
					(was["rect"] as Rect2).position.y, (now["rect"] as Rect2).position.y])
	for key in _controls_before:
		var was: Dictionary = _controls_before[key]
		print("    %-28s y %5d..%-5d  %s" % [was["said"], (was["rect"] as Rect2).position.y,
				(was["rect"] as Rect2).end.y, was["where"]])
	if not worse.is_empty():
		_finish(false, "opening the event log took controls off the screen: %s"
				% "; ".join(worse))
		return false
	if not moved.is_empty():
		_finish(false, "opening the event log moved controls that stayed on screen: %s. They are "
				% "; ".join(moved) + "reachable, but the log is not allowed to move them at all")
		return false
	return true


## EVERY CONTROL ON THE SCREEN, WHERE IT STANDS, AND A NAME A PERSON CAN READ.
##
## `find_children` RATHER THAN A WALK OF MY OWN OR A LIST OF THE ONES I REMEMBER: the buttons are
## built in four different places (the chrome, the `do` section, the bench rows, the crafting rows)
## and a hand-written list would be a check that stops covering whatever is added next.
##
## KEYED BY PATH, LABELLED BY TEXT. Several rows read "Craft" and two read "Take", so the text cannot
## be the key; the path cannot be the label, because `@VBoxContainer@31/@Button@47` tells a reader
## nothing about which button left the screen.
func _controls_now() -> Dictionary:
	var found := {}
	for node in _screen.find_children("*", "Button", true, false):
		var button := node as Button
		var key := String(_screen.get_path_to(button))
		# THE STRONGER QUESTION THAN `_standing`'S, and this is the one reader that needs it: a
		# button in a FOLDED container carries `visible` true over a container nobody can see, so its
		# own flag would call a hidden row "on screen". `is_visible_in_tree` is only meaningful
		# because this tool has a real window -- under `tests/run_tests.gd` it is false for
		# everything, which is half of why this verdict cannot live in the suite.
		var where := "hidden" if not button.is_visible_in_tree() else _standing(button)
		found[key] = {
			"said": "\"%s\"" % button.text if button.text != "" else "a button at %s" % key,
			"rect": button.get_global_rect(),
			"where": where,
		}
	return found


## WHAT WAS DRAWN FOR EACH BUILDING, AND WHERE (ASSA-138).
##
## THE SAME DEFECT AS A SHOT THAT MISSES ITS SUBJECT, one layer down. A machine drew NOTHING on this
## view until ASSA-138, and no check here could have seen that: every one of them asks about the HUD
## column, the map is just pixels to them, and a building that is absent looks exactly like one that
## is behind you.
##
## **AND IT IS WHY THE LINE ABOVE PRINTS THE VERDICT.** I assumed this tool's shots had been quietly
## full of an invisible 4-hopper drill, and they had not: on the pinned seed that design is WILL
## BREAK, the sim takes it apart on placement, and the map was empty for a reason that has nothing to
## do with drawing. Two different causes of "no machine in the picture", and only one of them is a
## bug -- so this says which, instead of letting a reader pick.
##
## So each building the sim has is printed beside the placement the scene made for it: its rectangle
## in view pixels, or `NOT DRAWN`. Read off `AssayScene.placements` -- the same call `_draw` makes --
## rather than off the image, because a rectangle is checkable arithmetic and a dark lump in a PNG is
## not. It reports; it does not fail the run. Whether a kind SHOULD have a picture is the Game
## Director's question, and a tool that answered it would be holding her opinion.
func _machine_report() -> void:
	if _screen._world == null or (_screen._world.view as Dictionary).is_empty():
		return
	var drawn := []
	for place in AssayScene.placements(_screen._world.view):
		if bool((place as Dictionary).get("composite", false)):
			drawn.append(place)
	var world := Rect2(Vector2.ZERO, _screen._world.size)
	for entry in _screen._sim.buildings():
		var building: Dictionary = entry
		var parts: Array = building.get("parts", [])
		var kinds := PackedStringArray()
		for part in parts:
			kinds.append(String((part as Dictionary).get("kind", "?")))
		var key := AssayAssembly.key_of(parts)
		var where := "NOT DRAWN"
		for place in drawn:
			if String((place as Dictionary).get("key", "")) == key:
				var dest: Rect2 = (place as Dictionary)["dest"]
				where = "%s %s  %s" % [dest.position.round(), dest.size.round(),
						"on the view" if world.intersects(dest) else "OFF THE VIEW"]
				break
		if parts.is_empty():
			where = "(a sheet, not a composite)"
		print("  building %-9s at %-10s %d parts %-28s %s"
				% [String(building.get("kind", "?")), building.get("pos", Vector2i.ZERO),
				parts.size(), "[%s]" % ", ".join(kinds), where])


func _report() -> void:
	for line in _shots:
		print("  ", line)
	_machine_report()
	_fold_report()
	# THE REVEAL VERDICT GOES FIRST, and the order is not taste. The incomplete check below ends the
	# run, so with it first a shot that could not contain its subject also silently skipped the only
	# measurement of whether the reveal worked -- two different questions, and the second one never
	# asked on exactly the runs where it matters most.
	if not _reveal_report():
		return
	# AND THE CONTROLS, for the same reason the reveal verdict goes before the incomplete check: a
	# shot that could not contain its subject would otherwise skip the only measurement of whether
	# reading the log costs you your buttons.
	if not _controls_report():
		return
	# AND THE ROSTER, before the incomplete check and for the third time for the same reason: today
	# 04-pack.png is legitimately CLIPPED (ASSA-133 ruling 2 says the crafting menu is the section
	# that gives way, and ASSA-149 is the item for the tool calling that a failure), so EVERY run
	# ends INCOMPLETE and anything behind that check is measured on no run at all.
	if not _rocks_report():
		return
	if not _missing.is_empty():
		_incomplete = true
		var said := PackedStringArray()
		for name in _missing:
			said.append("%s: %s" % [name, ", ".join(_missing[name] as PackedStringArray)])
		_finish(false, "; ".join(said))
		return
	_finish(true, "")


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_screen) and _screen.has_method("stop_solo_relay"):
		_screen.stop_solo_relay()
	if ok:
		# **THE GREEN LINE CARRIES THE CUTS** (ASSA-149). A reader who sees `WINDOW SHOT OK` must
		# not have to go back up the output to learn that a subject was only partly in frame. This
		# is the half that stops "clipped no longer fails" from becoming "clipped is no longer
		# said" -- which is the version of this change that would have been worth refusing.
		var cut := PackedStringArray()
		for shot_name in _clipped:
			cut.append("%s: %s" % [shot_name, ", ".join(_clipped[shot_name] as PackedStringArray)])
		if cut.is_empty():
			print("WINDOW SHOT OK")
		else:
			print("WINDOW SHOT OK  (cut, not missing — %s)" % "; ".join(cut))
	elif not _incomplete:
		print("FAIL  %s" % why)
	else:
		# THE SHOTS ARE ON DISK. Maren's constraint: a picture that cannot contain its subject still
		# gets written, because the off-screen fact is the finding. What does not happen is a green
		# last line over a set that does not show what it is named for.
		print("WINDOW SHOT INCOMPLETE  %s" % why)
	quit(0 if ok else 1)
