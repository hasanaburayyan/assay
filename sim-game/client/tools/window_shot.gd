extends SceneTree
## A PICTURE OF THE REAL WINDOW, at 1:1, with no hands (ASSA-116 box 5).
##
##   godot --path . --script res://tools/window_shot.gd -- <out_dir> [seed] [ticks]
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
## not in the frame. The PNG is still written -- Maren's constraint, and the right one: the off-screen
## fact is the most useful thing this tool has ever told us, and refusing the capture would hide it.
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
## Prints `WINDOW SHOT OK` LAST and only when every shot contained its subject, because Godot exits 0
## even on a compile error. A set written but missing a subject ends `WINDOW SHOT INCOMPLETE`.

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
		SETTLE_MENUS, SHOOT_MENUS, DONE }
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
## Set only by `_report`, so a dead run and a complete-but-blind set never wear each other's word.
var _incomplete := false
var _started := false
var _left := 0
## High-water mark of pack rows + crafting rows, and the tick it was reached on. See `04-pack.png`.
var _rows_best := 0
var _rows_tick := -1
var _done := false


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
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])


func _process(_delta: float) -> bool:
	if _done:
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
			_screen._show_make(false)
			_screen._show_log(true)
			_phase = Phase.SETTLE_MENUS
		Phase.SETTLE_MENUS:
			_settle(Phase.SHOOT_MENUS)
		Phase.SHOOT_MENUS:
			_shoot("03-log.png", PackedStringArray(["event log"]))
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
	print("  played seed %s to tick %d, step %s"
			% [_seed, _screen._sim.tick(), AssayButtonPlay.Step.keys()[_play.step]])
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
	for subject in subjects:
		var control := _section(subject)
		if control == null:
			_finish(false, "%s names the section %s, which this screen does not have"
					% [name, subject])
			return
		var where := _standing(control)
		_shots.append("    subject %-14s y %5d..%-5d  %s"
				% [subject, control.get_global_rect().position.y,
				control.get_global_rect().end.y, where])
		if where != "on screen":
			var said: PackedStringArray = _missing.get(name, PackedStringArray())
			said.append("its %s is %s" % [subject, where])
			_missing[name] = said


## THE SECTIONS OF THE HUD COLUMN, by the name a person would use for them. One list, because the
## fold report and the subject check have to be asking about the same thing.
func _sections() -> Array:
	return [["crafting menu", _screen._make], ["you", _screen._carrying], ["do", _screen._actions],
			["bench", _screen._bench], ["rocks", _screen._species], ["cursor", _screen._cursor],
			["event log", _screen._log]]


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
## own edge -- which is exactly what the first log line does once the reveal scrolls to it. A
## `ScrollContainer` clips by definition, so it counts whatever its `clip_contents` flag says.
func _frame_for(control: Control) -> Rect2:
	var frame := Rect2(Vector2.ZERO, root.size)
	var node: Node = control.get_parent()
	while node != null:
		var ancestor := node as Control
		if ancestor != null and (ancestor.clip_contents or ancestor is ScrollContainer):
			frame = frame.intersection(ancestor.get_global_rect())
		node = node.get_parent()
	return frame


## `visible`, `in the window` and `a person can see it` are three questions. This is the third.
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


func _report() -> void:
	for line in _shots:
		print("  ", line)
	_fold_report()
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
		print("WINDOW SHOT OK")
	elif not _incomplete:
		print("FAIL  %s" % why)
	else:
		# THE SHOTS ARE ON DISK. Maren's constraint: a picture that cannot contain its subject still
		# gets written, because the off-screen fact is the finding. What does not happen is a green
		# last line over a set that does not show what it is named for.
		print("WINDOW SHOT INCOMPLETE  %s" % why)
	quit(0 if ok else 1)
