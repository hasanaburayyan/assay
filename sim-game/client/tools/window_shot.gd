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
## WHAT IT SHOOTS, and why these three:
##  - `01-join.png`   the first screen a stranger sees, before any press.
##  - `02-play.png`   mid-session, every panel carrying real content from a played world.
##  - `03-log.png`    the same screen with the event log open and the crafting menu folded away.
##
## THE LOG SHOT IS NOT OPTIONAL AND IT IS WHY `_shoot` REFUSES A REPEAT. The board's complaint is
## "logs are hard on the eyes", and the played session ENDS with the log hidden and the menu open --
## `AssayButtonPlay` presses those toggles itself on its way through the loop. So the first version
## of this script asked for a state the screen was already in, and wrote 02 and 03 as byte-identical
## files while reporting three shots taken. A set of pictures that silently contains the same picture
## twice is worse than a missing one: it reads as coverage.
##
## THE WORLD IS OFFLINE AND PLAYED BY THE BUTTONS, borrowed whole from `tools/button_session.gd`:
## this script is the relay, and `AssayButtonPlay` presses the screen's own controls. So the panels
## are full of what a player's panels would hold, not of a fixture I typed. A shot of a world nobody
## played would flatter every panel that only looks wrong once it has rows in it.
##
## Prints `WINDOW SHOT OK` LAST and only on success, because Godot exits 0 even on a compile error.

## Frames to let pass before reading the viewport back. One is not enough: the screen is built from
## containers, and a container lays its children out on the frame AFTER they are added, so a capture
## on frame 1 catches every row at position zero, stacked on the origin. Three is slack, not science.
const SETTLE_FRAMES := 3
## Offline ticks to allow, the same budget `button_session.gd` uses for the same chain.
const PLAY_TICKS := 4000
const DEFAULT_SEED := "777042"

enum Phase { SETTLE_JOIN, SHOOT_JOIN, PLAY, SETTLE_PLAY, SHOOT_PLAY, SETTLE_MENUS, SHOOT_MENUS, DONE }

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
var _done := false


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_finish(false, "usage: -- <out_dir> [seed] [ticks]")
		return
	_out = String(argv[0])
	_seed = String(argv[1]) if argv.size() > 1 else DEFAULT_SEED
	_ticks = int(argv[2]) if argv.size() > 2 else PLAY_TICKS
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
			_shoot("01-join.png")
			_phase = Phase.PLAY
		Phase.PLAY:
			_run_offline()
		Phase.SETTLE_PLAY:
			_settle(Phase.SHOOT_PLAY)
		Phase.SHOOT_PLAY:
			_shoot("02-play.png")
			# THE OTHER STATE, and it has to be the OPPOSITE of whatever the loop left behind.
			# `AssayButtonPlay` folds the log away and opens the menu as it plays, so asking for
			# that state again photographs the same screen twice.
			_screen._show_make(false)
			_screen._show_log(true)
			_phase = Phase.SETTLE_MENUS
		Phase.SETTLE_MENUS:
			_settle(Phase.SHOOT_MENUS)
		Phase.SHOOT_MENUS:
			_shoot("03-log.png")
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
func _run_offline() -> void:
	var welcome := AssaySimHost.fresh_welcome_json(_seed, "marlow")
	if welcome == "":
		_finish(false, "could not make a world on seed %s" % _seed)
		return
	_screen._client.play_offline()
	_screen._client.feed_offline(welcome)
	if not _screen._sim.running():
		_finish(false, "offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
		return
	for _i in range(_ticks):
		_play.advance()
		if _play.finished:
			break
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		var before: int = _screen._sim.applied
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		if _screen._sim.applied == before:
			_finish(false, "the sim refused the bundle for tick %d" % at)
			return
	if _play.failed != "":
		_finish(false, "the loop stopped: %s" % _play.failed)
		return
	print("  played seed %s to tick %d, step %s"
			% [_seed, _screen._sim.tick(), AssayButtonPlay.Step.keys()[_play.step]])
	_phase = Phase.SETTLE_PLAY


## READ THE FRAME BACK AND WRITE IT OUT, refusing a blank one and refusing a repeat.
##
## TWO WAYS A SET OF SHOTS LIES, and both have already happened to me here.
##
## BLANK: a render that produced an empty image. That is exactly what `--headless` does, and a PNG
## of nothing is indistinguishable from a PNG of a screen until somebody opens it. So a frame has to
## carry more than one colour before this calls it a shot.
##
## REPEAT: the screen was asked for a state it was already in, so two named shots are the same
## picture. Nothing is blank, every count looks healthy, and the set reads as covering two states
## while covering one. Comparing the bytes is the only thing that catches it, and it is cheap.
func _shoot(name: String) -> void:
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
	if _taken.has(fingerprint):
		_finish(false, "%s is pixel-identical to %s: the screen was asked for a state it was "
				% [name, _taken[fingerprint]] + "already in, so this pair shows one state, not two")
		return
	_taken[fingerprint] = name
	var path := "%s/%s" % [_out, name]
	if image.save_png(path) != OK:
		_finish(false, "cannot write %s" % path)
		return
	_shots.append("%s  %dx%d  %d colours  %s"
			% [name, image.get_width(), image.get_height(), seen.size(), fingerprint.substr(0, 12)])


## WHAT IS ACTUALLY ON SCREEN, as a number rather than as my reading of a picture.
##
## A shot shows what is visible; it cannot show what is MISSING, and the two look the same. The
## first set of shots here caught the event log being nowhere on screen with its own toggle reading
## "hide the event log" -- `_log.visible` was true and the section was simply below the bottom of a
## scrolling column that overflows a 720px window. That is invisible to every test we have, because
## every one of them asks the node and the node answers honestly.
##
## So each named section reports its rect against the window. `visible` and `on screen` are
## different questions and this is the one nobody was asking.
##
## **AND THE WINDOW IS NOT WHAT CLIPS THESE SECTIONS (Limpet, ASSA-117).** Every one of them lives
## inside `_scroll`, whose viewport is the chrome column minus the toggle, minus the stopped block and
## minus the horizontal scrollbar -- a box roughly 100px shorter than the window and starting ~96px
## down. Measured against the window, a section whose top is scrolled up under the toggle reads
## `on screen` while its first line is clipped in half, which is what `looks-2026-10-03-after-14247`
## showed me and this report denied. A section is now judged against the box that actually clips it,
## and the box is printed so the numbers can be checked rather than believed.
func _fold_report() -> void:
	var window := Rect2(Vector2.ZERO, root.size)
	var scroll: ScrollContainer = _screen._scroll as ScrollContainer
	var clip := window
	if scroll != null:
		clip = scroll.get_global_rect().intersection(window)
		print("  scroll viewport y %d..%d (the window is y %d..%d)"
				% [clip.position.y, clip.end.y, window.position.y, window.end.y])
	for part in [["crafting menu", _screen._make], ["you", _screen._carrying],
			["do", _screen._actions], ["bench", _screen._bench], ["rocks", _screen._species],
			["cursor", _screen._cursor], ["event log", _screen._log]]:
		var control: Control = part[1]
		var rect := control.get_global_rect()
		var box := clip if scroll != null and scroll.is_ancestor_of(control) else window
		var where := "on screen"
		if not control.visible:
			where = "hidden"
		elif not box.intersects(rect):
			where = "OFF SCREEN"
		elif not box.encloses(rect):
			where = "CLIPPED"
		print("  section %-14s y %5d..%-5d  %s" % [part[0], rect.position.y, rect.end.y, where])


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
func _reveal_report() -> bool:
	var scroll: ScrollContainer = _screen._scroll as ScrollContainer
	var heading: Label = _screen._log_heading as Label
	if scroll == null or heading == null:
		_finish(false, "no scroll box or no log heading on the screen, so the reveal cannot be judged")
		return false
	var clip := scroll.get_global_rect().intersection(Rect2(Vector2.ZERO, root.size))
	var bar := scroll.get_v_scroll_bar()
	var head := heading.get_global_rect()
	var body := (_screen._log as Control).get_global_rect()
	print("  reveal: scrolled to %d of %d; heading y %d..%d; body top y %d"
			% [scroll.scroll_vertical, int(bar.max_value - bar.page), head.position.y, head.end.y,
			body.position.y])
	if not clip.encloses(head):
		_finish(false, ("the log's own heading is at y %d..%d, outside the scroll viewport y %d..%d: "
				+ "pressing 'show the event log' left you somewhere without saying where")
				% [head.position.y, head.end.y, clip.position.y, clip.end.y])
		return false
	if body.position.y < clip.position.y - 0.5:
		_finish(false, ("the log's first line starts at y %d, above the scroll viewport's y %d, so the "
				+ "NEWEST line is the one clipped in half") % [body.position.y, clip.position.y])
		return false
	return true


func _report() -> void:
	for line in _shots:
		print("  ", line)
	_fold_report()
	if not _reveal_report():
		return
	_finish(true, "")


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_screen) and _screen.has_method("stop_solo_relay"):
		_screen.stop_solo_relay()
	print("WINDOW SHOT OK" if ok else "FAIL  %s" % why)
	quit(0 if ok else 1)
