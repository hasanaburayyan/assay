extends SceneTree
## CI: local -- a shot: --headless writes a BLANK frame and reports success, the worst kind of green
## **A PICTURE OF THE OPEN BUILD SCREEN, AND THE ONE MEASUREMENT ARITHMETIC CANNOT GIVE** (ASSA-328).
##
##   godot --path . --script res://tools/limpet_build_screen_shot.gd -- <out_dir> [seed] [ticks] [mode]
##
## **`mode` IS `make` (THE DEFAULT), `assemble` OR `refuse`, AND THEY ARE DIFFERENT PICTURES OF ONE
## SCREEN.** `make` presses a crafting row's launcher after a short play. `assemble` plays the WHOLE
## demo loop until the parts are in the pack, presses a pack row's `Frame`, and shoots the screen
## TWICE: once with every slot empty and once with the design as full as the frame allows.
## `refuse` (ASSA-373) plays the same loop, fills only the OPTIONAL boxes so the design stays
## `unfinished`, and shoots before and after one press of `Build` -- a pair whose two pictures are
## identical when the client is right and differ by every mounted part when it is not.
##
## **TWO SHOTS BECAUSE ASSA-341 BOX 9 IS A CLAIM ABOUT TWO STATES.** *"`Build`'s y does not move
## between a one-row and a six-row sentence"* cannot be held by one render, and the Game Director
## ruled (02:18Z) that asserting the two FLAGS that make it true is the mechanism and not the
## behaviour. So the behaviour is measured here, in a laid-out window, on both states of one run.
##
## **WHY IT IS NOT A STATE IN `window_shot.gd`.** That tool shoots seven fixed moments of a played
## world and every one of them is about the HUD column. This is about a surface that only exists
## after a press, and it carries a second job no shot tool has: it REPORTS the overlap.
##
## **THE JOB ARITHMETIC CANNOT DO.** `AssayHud.build_screen_rect` keeps the screen clear of the
## world's own control band -- the status toast and `whole world (V)`, which live inside the world
## rect and are not the world (Maren's §0). Headless, the band's top comes from
## `AssayHud.WORLD_CONTROLS_BAND`, a constant measured off a screenshot, and **a constant for a
## laid-out height is the shape of defect that goes stale in silence** (my own ASSA-320: a number
## written in prose beside asserted facts reads as fact). So this asks the three real controls where
## they ACTUALLY are in a laid-out window and intersects them with where the screen ACTUALLY is.
##
## **NOT `--headless`, for `window_shot`'s reason doubled.** A dummy driver writes a blank PNG and
## reports success, AND it lays nothing out -- so every rect in the report would read `(0,0,0,0)` and
## every overlap would be empty. **This tool would pass perfectly while measuring nothing**, which is
## the exact failure I wrote down after generalising from the one configuration I had measured.

## The seed Maren's mock was built on, so the picture is comparable to it (`assay-build-screen` §0).
const DEFAULT_SEED := "14247"

## Enough of the loop to have a pack worth making something out of. The session's own budget is far
## longer; a shot only needs the catalogue to have rows.
const DEFAULT_TICKS := 60

## The two pictures this tool takes. **AN UNKNOWN MODE IS REFUSED RATHER THAN DEFAULTED TO `make`**:
## an argument that silently means something else is how a run comes back green about a screen
## nobody asked for -- the shape of defect I have now written down six times.
const MODE_MAKE := "make"
const MODE_ASSEMBLE := "assemble"
## **ASSA-373's PAIR: THE SAME UNFINISHED DESIGN BEFORE AND AFTER A `Build` PRESS.** It mounts only
## the OPTIONAL boxes, so the frame's required slot stays empty and the bar is already saying so,
## then presses the one accent on the screen and shoots again. On `origin/main` the two pictures
## differ -- every mounted part is gone from the second -- and that difference IS the defect.
const MODE_REFUSE := "refuse"

## **THE ASSEMBLY PICTURE NEEDS THE WHOLE DEMO LOOP, SO THE TICKS ARE A CEILING AND A STATE IS THE
## STOP.** `AssayButtonPlay` mines, smelts and crafts `handle, head x2, frame, hopper x4` and only
## then plants them; the pack holds all of it for exactly one step, `PICK`. Stopping on a tick COUNT
## would be a number that goes stale the day the loop's pace changes, and it would stop in the
## middle of smelting with an empty pack and still write a PNG.
const ASSEMBLE_TICK_CEILING := 2000

## **FRAMES HANDED BACK BEFORE ANYTHING IS MEASURED, AND WHY IT IS MORE THAN ONE.** A container's
## minimum is recalculated DEFERRED (ASSA-341: a growth check reads `0.0 against 90.0` for ever),
## and every mount refreshes this screen -- so a rect read on the frame of the press is the rect
## before it. Three is not a tuning: it is one frame for the press, one for the deferred minimum and
## one for the layout that follows it. **MEASURED, NOT ASSUMED: a run at 30 gave byte-identical
## rects** (864x729, both overlaps, box 8's 5 px), which is how the overflow below was cleared of
## being my instrument reading a half-laid tree rather than a defect.
const SETTLE_FRAMES := 3

## **HER BAR ON BOX 8**, quoted rather than chosen: ruling 4 is `|Build.centre_y - row1.centre_y|
## <= 2`, and 2 px is where she put it.
const BOX_8_TOLERANCE := 2.0

## Ticks between handing the frame back, so containers lay out before anything is measured.
const TICKS_PER_FRAME := 10

## **THE WALL CLOCK THIS RUN MAY NOT OUTLIVE** (ASSA-182's guard, `tests/test_tool_ceilings.gd`).
##
## **I SHIPPED THIS TOOL WITHOUT ONE AND CI CAUGHT IT, which is the guard doing exactly its job.**
## A looping `_process` that dies on a runtime error inside `_initialize` never reaches `_finish`,
## so it holds the machine until a person notices -- and the night this Mac hit load 151 is what
## that costs. 120 s is four times the longest this has taken (the play is 60 ticks and the shot is
## one frame), so reaching it means something stopped advancing rather than that the world was slow.
const RUN_CEILING := 120.0

## **THE ASSEMBLY RUN'S OWN BUDGET, WHICH WIDENS `RUN_CEILING` RATHER THAN REPLACING IT.** The 120 s
## is armed at declaration for the reason this file gives two paragraphs up -- a ceiling set at the
## end of `_initialize` is absent in exactly the case it is for -- and `assemble` raises it once the
## mode is parsed. Widening an armed guard is safe; arming one late is not. The whole demo loop is
## ~1400 ticks of real sim with a HUD rebuild on every one of them, `button_session.gd` gives that
## same work a 300 s floor, and this Mac at load 80 is the case the number is for.
const ASSEMBLE_RUN_CEILING := 300.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING

var _screen: Node = null
var _play: RefCounted = null
var _asked: Array = []
var _out := ""
var _seed := DEFAULT_SEED
var _left := DEFAULT_TICKS
var _started := false
var _shot := false
var _done := false
var _faults: Array = []
var _mode := MODE_MAKE
## The tick count as ASKED FOR, kept because `_left` is spent and a timeout has to name the budget
## it blew rather than report 0.
var _ticks_asked := 0
## Frames still owed to the layout before the next measurement; see `SETTLE_FRAMES`.
var _settle := 0
## True between the empty shot and the full one, while one part is mounted per frame.
var _mounting := false
## `refuse` mode's stage: filling the optional boxes.
var _refusing := false
## The shot armed by `_arm`, taken once `_settle` has run out. `""` when none is waiting.
var _pending := ""
## What the design and the bar said BEFORE the press, so `_report_press` compares two readings of the
## same screen rather than one reading and a memory of the other.
var _before_parts := PackedStringArray()
var _before_said := ""
## How far down `_faults` the phase labels have been written; see `_end_phase`.
var _phase_from := 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_finish(false, "usage: -- <out_dir> [seed] [ticks] [%s|%s]" % [MODE_MAKE, MODE_ASSEMBLE])
		return
	_out = String(argv[0])
	_seed = String(argv[1]) if argv.size() > 1 else DEFAULT_SEED
	_mode = String(argv[3]) if argv.size() > 3 else MODE_MAKE
	if not [MODE_MAKE, MODE_ASSEMBLE, MODE_REFUSE].has(_mode):
		_finish(false, "mode is one of %s, not `%s`"
				% [[MODE_MAKE, MODE_ASSEMBLE, MODE_REFUSE], _mode])
		return
	var budget := ASSEMBLE_TICK_CEILING if _needs_pack() else DEFAULT_TICKS
	_left = int(argv[2]) if argv.size() > 2 else budget
	_ticks_asked = _left
	if _needs_pack():
		_ceiling = maxf(_ceiling, Time.get_unix_time_from_system() + ASSEMBLE_RUN_CEILING)
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_finish(false, "cannot write to %s" % _out)
		return
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, the reason `button_session.gd` and `window_shot.gd` both give: a `--script`
	# run works inside `SceneTree._initialize`, before the root window is in the tree.
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  limpet_build_screen_shot.gd ran past its %ds ceiling: nothing advanced it"
				% int(RUN_CEILING))
		quit(1)
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "limpet")
		if welcome == "":
			_finish(false, "could not make a world on seed %s" % _seed)
			return true
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		if not _screen._sim.running():
			_finish(false, "offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
			return true
		_started = true
		return false
	if not _played():
		return _done
	if not _shot:
		_shot = true
		_open_and_settle()
		_settle = SETTLE_FRAMES
		return false
	if _settle > 0:
		_settle -= 1
		return false
	# **EVERY SHOT IS TAKEN A SETTLE AFTER THE LAST THING THAT COULD MOVE THE TREE** (ASSA-373). The
	# stages below only ever ARM a shot; `_pending` is fired here, after `_settle` has run out above.
	# **I ADDED THE QUIET TICKS AND MEASURED IN THE SAME FRAME FIRST, AND IT READ A SCREEN 212 px PAST
	# ITS RECT WITH A 570 px COMMIT BAR -- while the PNG beside it was correct.** A tick refreshes the
	# screen, which invalidates every container minimum, and those are recalculated DEFERRED; reading
	# a rect before that lands measures the growth and never the shrink back. The picture disagreeing
	# with the numbers is what caught it, and the numbers were mine.
	if _pending != "":
		var firing := _pending
		_pending = ""
		match firing:
			"slots-full":
				_shoot("slots-full", "THE ASSEMBLY PATH, every box the frame has filled from the pack")
				_stop()
				return _done
			"before-press":
				_shoot("before-press",
						"ASSA-373: AN UNFINISHED DESIGN, OPTIONAL BOXES FILLED, `Build` UNPRESSED")
				_report_before_press()
				# **PRESSED THROUGH THE BUTTON, NOT THROUGH `_send_build`.** What the board would do is
				# press the accent, and a gate wired to a function nothing calls would pass a test of
				# the function.
				_asked.clear()
				_screen._build_act.pressed.emit()
				_arm("after-press")
				return false
			"after-press":
				_shoot("after-press", "ASSA-373: THE SAME DESIGN AFTER ONE PRESS OF `Build`")
				_report_press()
				_stop()
				return _done
			"slots-empty":
				_shoot("slots-empty", "THE ASSEMBLY PATH, frame chosen and nothing mounted yet")
				_mounting = true
				return false
			"make":
				_shoot("", "THE MAKE PATH, opened by a crafting row's launcher")
				_stop()
				return _done
		_faults.append("armed an unknown shot `%s`" % firing)
		_stop()
		return _done
	if _mounting:
		# ONE PART PER FRAME, so each mount lays out before the next empty box is chosen.
		if _mount_one():
			_settle = SETTLE_FRAMES
			return false
		_mounting = false
		_arm("slots-full")
		return false
	if _refusing:
		if _mount_one_optional():
			_settle = SETTLE_FRAMES
			return false
		_refusing = false
		_arm("before-press")
		return false
	if _mode == MODE_MAKE:
		_arm("make")
		return false
	if _mode == MODE_REFUSE:
		# NO `slots-empty` SHOT IN THIS MODE, so the directory holds exactly the pair the item asks
		# for and nothing a reader has to be told to ignore.
		_refusing = true
		return false
	_arm("slots-empty")
	return false


## **WHAT STOPS THE PLAY, WHICH IS A DIFFERENT QUESTION IN THE TWO MODES.** `make` needs a catalogue
## with rows in it, and a duration gives that. `assemble` needs PARTS IN THE PACK, which is a state
## and not a duration -- so it waits for `AssayButtonPlay`'s own step to reach `PICK` (everything
## crafted, nothing planted yet) and treats the tick count as a ceiling it may not pass in silence.
##
## **A LOOP THAT STOPPED EARLY IS A FAULT AND NOT A SHORTER RUN.** `_play.failed` and a blown tick
## budget both mean the pack never held the parts this picture is of, and the PNG written then would
## be a build screen saying *you are not carrying a frame to build on* -- a perfectly plausible
## screenshot of the wrong thing, which is the one outcome worse than a red run.
func _played() -> bool:
	if _mode == MODE_MAKE:
		if _left <= 0:
			return true
		_tick_some()
		return false
	if _pack_can_fill_a_frame():
		return true
	if String(_play.failed) != "":
		_finish(false, "the demo loop stopped before the parts were made: %s" % _play.failed)
		return false
	if _left <= 0:
		_finish(false, ("the loop reached %s in %d ticks and the pack never held a frame it could "
				+ "fill, so no pack ever held the design this picture is of")
				% [AssayButtonPlay.Step.keys()[_play.step], _ticks_asked])
		return false
	_tick_some()
	return false


## `TICKS_PER_FRAME` of the loop, pressing the screen's own buttons and feeding the sim's own answer
## back. Lifted out of `_process` unchanged when the stop condition became a state.
func _tick_some() -> void:
	for _i in range(TICKS_PER_FRAME):
		if _left <= 0:
			break
		# **THE STOP IS CHECKED EVERY TICK, NOT ONCE A FRAME.** Ten ticks pass per frame and the state
		# this picture needs lasts a handful of them, so a check between frames steps over it: the
		# first version of this stopped on `AssayButtonPlay.Step.PICK` and came back *"reached DONE and
		# never reached PICK"* -- true, and about a pack that HAD held the parts and then spent them on
		# the loop's own pick and drill. Checked BEFORE `advance()`, so the tick that would spend them
		# is never taken.
		if _needs_pack() and _pack_can_fill_a_frame():
			return
		_left -= 1
		_play.advance()
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id,
					"command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))


## **ARM A SHOT: TICK THE WORLD, THEN WAIT A SETTLE, THEN TAKE IT.** The two halves are one call
## because they are one rule -- a shot must be of a tree that has stopped moving, and a tick is the
## thing that moves it. Splitting them is how the first version of this measured mid-layout.
func _arm(what: String) -> void:
	_tick_quiet(TICKS_PER_FRAME)
	_settle = SETTLE_FRAMES
	_pending = what


## **TICKS WITH NOTHING IN THEM, SO THE SCREEN REFRESHES WITHOUT THE DEMO LOOP TOUCHING THE DESIGN.**
## `_tick_some` advances `AssayButtonPlay`, which at this step plants the parts -- it would spend the
## very design the picture is of. This feeds the sim the empty bundle a relay sends when nobody
## pressed anything, which is what a player staring at an open screen actually generates.
func _tick_quiet(count: int) -> void:
	for _i in range(count):
		var at: int = _screen._sim.tick()
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": []}}))


## Measure, write, and label every fault this shot found with which shot found it.
func _shoot(suffix: String, about: String) -> void:
	print("")
	print("=== %s ===" % about)
	_measure()
	_write(suffix)
	_end_phase(suffix if suffix != "" else _mode)


## **WHICH OF THE TWO SHOTS A FAULT IS ABOUT.** Both shots measure the same screen into one list, so
## an unlabelled fault sends a reader to the wrong picture.
func _end_phase(named: String) -> void:
	for i in range(_phase_from, _faults.size()):
		_faults[i] = "[%s] %s" % [named, _faults[i]]
	_phase_from = _faults.size()


func _stop() -> void:
	_finish(_faults.is_empty(), "\n".join(PackedStringArray(_faults)))


## **PRESS THE ROW A PLAYER WOULD PRESS.** Not `_open_build_screen`: the launcher opening nothing is
## one of the two defects this picture is evidence against, and calling the open function directly
## would take the row's one control out of the test.
func _open_and_settle() -> void:
	if _needs_pack():
		_open_assembly()
		return
	for row in _screen._make.get_children():
		var button := _find(row, AssayHud.make_launch_text())
		if button != null:
			button.pressed.emit()
			return
	_faults.append("no make row carried a `%s` control at all" % AssayHud.make_launch_text())


## **THE STATE THIS PICTURE IS OF, TESTED DIRECTLY RATHER THAN INFERRED FROM THE LOOP'S PACE.**
## Maren's §5.4 worst case is a frame with every box filled, so that is literally the stop: a frame
## in the pack whose every box can be filled from the same pack.
func _pack_can_fill_a_frame() -> bool:
	var frame := _fillable_frame(false)
	if frame.is_empty():
		return false
	return _room_of(frame) >= _worst_case_room()


## **THE MOST ROOM ANY FRAME IN THE CATALOGUE HAS, WHICH IS WHAT MAKES THE STOP THE WORST CASE
## RATHER THAN THE FIRST CASE.** The pack holds a handle -- one box -- long before it holds the frame
## with six, and `_fillable_frame` honestly answered the handle: the first run of this shot specced a
## six-box screen and PHOTOGRAPHED A ONE-BOX ONE, green, with `CHOSEN 1 x Tonore handle (A)` in the
## report as the only tell. **The ceiling is the catalogue's, so nothing here picks a number**, and
## the day a frame with more slots is added the stop follows it.
func _worst_case_room() -> int:
	var most := 0
	for entry in AssaySimHost.part_kinds():
		var part: Dictionary = entry
		if not bool(part.get("is_frame", false)):
			continue
		var room := 0
		for slot in part.get("slots", []):
			room += int((slot as Dictionary).get("max", 0))
		most = maxi(most, room)
	return most


## How many parts one frame STACK can take, by its kind's `slots`. 0 for anything that is not a frame.
func _room_of(stack: Dictionary) -> int:
	var part := AssayHud.part_kind_of(stack, AssaySimHost.part_kinds())
	if part.is_empty() or not bool(part.get("is_frame", false)):
		return 0
	var room := 0
	for slot in part.get("slots", []):
		room += int((slot as Dictionary).get("max", 0))
	return room


## **THE FRAME WITH THE MOST ROOM THAT THE PACK CAN COMPLETELY FILL**, or `{}`. One function answers
## both "may we stop playing" and "which frame do we open", because two functions would be free to
## disagree -- a stop that certified one frame and a launcher that opened another would shoot a
## half-empty screen and call it the worst case.
##
## **WHICH FRAME IS THE SIM'S ANSWER AND NOT THIS TOOL'S TASTE.** The pack holds a handle AND a
## frame and BOTH are frames by `is_frame` -- a pick is a handle with a head on it -- so the choice
## is `slots`' summed room, and with `report` it PRINTS every candidate and what it was short of.
## A tool that quietly picked the handle would shoot a two-box screen as the worst case.
func _fillable_frame(report: bool) -> Dictionary:
	var kinds := AssaySimHost.part_kinds()
	var held: Array = _screen._sim.inventory_of(_screen._client.player_id)
	var pack := {}
	for entry in held:
		var stack: Dictionary = entry
		var kind := String(stack.get("kind", ""))
		pack[kind] = int(pack.get(kind, 0)) + int(stack.get("count", 0))
	var best := {}
	var most := -1
	for entry in held:
		var stack: Dictionary = entry
		var part := AssayHud.part_kind_of(stack, kinds)
		if part.is_empty() or not bool(part.get("is_frame", false)):
			continue
		var want := {}
		var room := 0
		for box in AssayHud.slot_boxes(part.get("slots", [])):
			var named := String((box as Dictionary).get("name", ""))
			want[named] = int(want.get(named, 0)) + 1
			room += 1
		var missing := PackedStringArray()
		for named in want:
			if int(pack.get(named, 0)) < int(want[named]):
				missing.append("%s (want %d, hold %d)"
						% [named, int(want[named]), int(pack.get(named, 0))])
		if report:
			print("FRAME    %-22s room for %-2d of the catalogue's %-2d  %s"
					% [AssayHud.stack_line(stack), room, _worst_case_room(),
					"fillable" if missing.is_empty() else "short of " + ", ".join(missing)])
		if not missing.is_empty() or room <= 0:
			continue
		if room > most:
			most = room
			best = stack
	return best


## **OPEN THE ASSEMBLY PATH THE WAY A PLAYER DOES: a pack row's `Frame`** (ASSA-317 slice 2b, where
## a frame row became the launcher and a mount row kept mounting). Not `_open_assembly_screen`, for
## the reason `_open_and_settle` gives about the make launcher: the row's control is half of what
## this picture is evidence about.
##
## **WHICH FRAME IS THE SIM'S ANSWER AND NOT THIS TOOL'S TASTE.** At `PICK` the pack holds a handle
## AND a frame and BOTH are frames by `is_frame` -- a pick is a handle with a head on it. The
## picture the Game Director needs is §5.4's worst case, so this takes the frame with the most room
## (`slots`' summed `max`) and PRINTS every candidate with its room, because a tool that quietly
## picked the handle would shoot a two-box screen and report it as the worst case.
##
## **AND THE WORD ON THE BUTTON IS READ, NEVER SPELLED.** `AssayHud.stack_verbs` is where `Frame`
## comes from; a literal here would be this tool's copy of a label, free to agree with the screen
## until somebody renames it. The footprint argument only shapes the Place verb's tooltip, so ONE
## is safe and says so.
func _open_assembly() -> void:
	var kinds := AssaySimHost.part_kinds()
	var best := _fillable_frame(true)
	if best.is_empty():
		_faults.append("the pack holds no frame it can fill, so there is no worst case to open")
		return
	var word := ""
	for descriptor in AssayHud.stack_verbs(best, kinds, Vector2i.ONE):
		if bool((descriptor as Dictionary).get("is_frame", false)):
			word = String((descriptor as Dictionary).get("label", ""))
	if word == "":
		_faults.append("`stack_verbs` offers no frame verb on %s" % AssayHud.stack_line(best))
		return
	var line := AssayHud.stack_line(best)
	print("CHOSEN   %s, opened with `%s`" % [line, word])
	for row in _screen._carrying.get_children():
		var named: Array = row.find_children("*", "Label", true, false)
		var matched := false
		for child in named:
			if (child as Label).text == line:
				matched = true
		if not matched:
			continue
		var button := _find(row, word)
		if button != null:
			button.pressed.emit()
			return
	_faults.append("no pack row for %s carried a `%s` control" % [line, word])


## **MOUNT ONE PART INTO THE FIRST EMPTY BOX, CHOSEN BY THE SIM'S OWN JOIN.** Returns false when
## nothing is left to mount, which is what ends the mounting phase.
##
## **THE BOX IS PICKED BY `slot_fill`, THE SAME FUNCTION THE SCREEN DRAWS FROM** (ASSA-317 slice 2).
## Pressing mount rows blindly until the sim refuses would spend presses on a second head the frame
## has no box for, and the refusal sentence would then be in the picture -- a true refusal about a
## press no player would make. Asking which box is empty first is what a player reads off the shape.
##
## **AND THE PRESS IS THE ROW'S OWN CONTROL, FOUND BY THE LABEL THE SCREEN GAVE IT.** The rows are
## rebuilt after every mount, so a button held from a previous frame is freed; this looks it up again
## each time.
func _mount_one() -> bool:
	var frame: Dictionary = _screen._design_frame()
	if frame.is_empty():
		_faults.append("no frame is chosen after pressing the launcher, so nothing can be mounted")
		return false
	var kinds := AssaySimHost.part_kinds()
	var part := AssayHud.part_kind_of(frame, kinds)
	var fill := AssayHud.slot_fill(part.get("slots", []), _screen._design_mounted())
	for box in fill.get("boxes", []):
		var entry: Dictionary = box
		if not (entry.get("part", {}) as Dictionary).is_empty():
			continue
		var want := String(entry.get("name", ""))
		for held in _screen._sim.inventory_of(_screen._client.player_id):
			var stack: Dictionary = held
			if String(stack.get("kind", "")) != want:
				continue
			var button := _find(_screen._build_mounts, AssayHud.stack_line(stack))
			if button == null:
				continue
			print("MOUNT    %s into an empty `%s` box" % [AssayHud.stack_line(stack), want])
			button.pressed.emit()
			return true
	return false


## **WHETHER THIS MODE NEEDS PARTS IN THE PACK**, which is what decides the tick budget, the wall
## ceiling, the stop condition and which launcher is pressed. One predicate rather than four
## `_mode == MODE_ASSEMBLE` tests: adding `refuse` to three of four is the shape of defect where a
## new mode plays the whole loop and then presses a crafting row.
func _needs_pack() -> bool:
	return _mode != MODE_MAKE


## **FILL ONE *OPTIONAL* BOX, LEAVING EVERY REQUIRED ONE EMPTY** (ASSA-373). `_mount_one`'s body with
## one clause added, and the clause is the whole point of the mode: a design missing a required part
## is what the sim calls `unfinished`, and it is the state the bar is already describing.
##
## **`required` IS READ OFF THE BOX, NOT OFF THE SLOT'S NAME.** `slot_boxes` marks the first `min` of
## a kind's boxes required, so a `1-4` slot is one required box and three optional ones -- keying off
## the kind would skip all four and mount nothing at all.
func _mount_one_optional() -> bool:
	var frame: Dictionary = _screen._design_frame()
	if frame.is_empty():
		_faults.append("no frame is chosen after pressing the launcher, so nothing can be mounted")
		return false
	var part := AssayHud.part_kind_of(frame, AssaySimHost.part_kinds())
	var fill := AssayHud.slot_fill(part.get("slots", []), _screen._design_mounted())
	for box in fill.get("boxes", []):
		var entry: Dictionary = box
		if bool(entry.get("required", false)):
			continue
		if not (entry.get("part", {}) as Dictionary).is_empty():
			continue
		var want := String(entry.get("name", ""))
		for held in _screen._sim.inventory_of(_screen._client.player_id):
			var stack: Dictionary = held
			if String(stack.get("kind", "")) != want:
				continue
			var button := _find(_screen._build_mounts, AssayHud.stack_line(stack))
			if button == null:
				continue
			print("MOUNT    %s into an empty OPTIONAL `%s` box" % [AssayHud.stack_line(stack), want])
			button.pressed.emit()
			return true
	return false


## **THE STATE THE FIRST PICTURE IS OF, ASSERTED RATHER THAN HOPED FOR.** A run that mounted nothing,
## or whose design the sim does not call unfinished, would write two identical PNGs and a reader
## would see a passing pair where there was no test.
func _report_before_press() -> void:
	_before_parts = _parts_now()
	_before_said = _screen._status.text
	var readout: Dictionary = _screen._design_readout()
	print("DESIGN   %s" % [_before_parts])
	print("BAR      unfinished %s · fault `%s` · verdict `%s`"
			% [readout.get("unfinished", false), readout.get("fault", ""),
			readout.get("verdict", "")])
	if _before_parts.size() < 2:
		_faults.append("nothing optional was mounted, so the press cannot cost any work")
	if not bool(readout.get("unfinished", false)):
		_faults.append("the sim does not call this design unfinished (%s), so this is not ASSA-373's state"
				% [readout])


## **WHAT THE PRESS COST, AS TWO READINGS OF ONE SCREEN.** The verdict is the design surviving; the
## sentence and the wire are reported beside it because a design kept by a silent button, or kept and
## then submitted anyway, are both wrong in ways the pixels do not show.
func _report_press() -> void:
	var after := _parts_now()
	print("DESIGN   before %s" % [_before_parts])
	print("DESIGN   after  %s" % [after])
	print("SAID     before `%s`" % _before_said)
	print("SAID     after  `%s`" % _screen._status.text)
	print("WIRE     %d command(s) submitted by the press: %s" % [_asked.size(), _asked])
	print("BUILD    disabled %s · variation `%s`"
			% [_screen._build_act.disabled, _screen._build_act.theme_type_variation])
	if after != _before_parts:
		_faults.append("the press changed the design from %s to %s; a refusal may cost a press and "
				% [_before_parts, after] + "never your work")
	if not _asked.is_empty():
		_faults.append("the press submitted %s for a design the sim calls unfinished" % [_asked])


## The kinds in the design right now, frame first, in the order they were pressed.
func _parts_now() -> PackedStringArray:
	var kinds := PackedStringArray()
	for entry in _screen._building:
		kinds.append(String((entry as Dictionary).get("kind", "")))
	return kinds


## **THE OVERLAP, IN PIXELS, AGAINST THE THREE CONTROLS MAREN'S §1 PROTECTS.**
##
## **A ZERO-SIZED CONTROL IS REPORTED AND NOT SKIPPED HERE**, which is the opposite of what
## `main.gd::_place_build_screen` does with one -- and deliberately. There, a zero size means
## "nothing has laid out" and the constant has to answer. Here, a laid-out window that reports a
## control with no size is itself the finding: it means this tool measured nothing and must not say
## so in green.
func _measure() -> void:
	if not _screen._build_box.visible:
		_faults.append("the screen is not visible after pressing a row's launcher")
		return
	var screen_rect := Rect2(_screen._build_box.global_position, _screen._build_box.size)
	print("SCREEN   %s  (%.0f x %.0f)" % [screen_rect, screen_rect.size.x, screen_rect.size.y])
	# **WHAT THE SCREEN WAS ASKED TO BE, BESIDE WHAT IT IS** (ASSA-332). A `Control` cannot be smaller
	# than its combined minimum, so a box whose content demands more height than
	# `build_screen_rect` allows GROWS -- and grows down, over the band Maren's §1 protects. The rect
	# is arithmetic the suite already holds; this is the only place the two can be compared.
	var room := AssayHud.world_rect()
	var reached := room.end.y
	for control in [_screen._view_toggle, _screen._map_key_toggle, _screen._says_toast]:
		var node := control as Control
		if node != null and node.visible and node.size.y > 0.0:
			reached = minf(reached, node.global_position.y)
	var asked := AssayHud.build_screen_rect(room, reached)
	print("ASKED    %s  (%.0f x %.0f); the box's own minimum is %s"
			% [asked, asked.size.x, asked.size.y, _screen._build_box.get_combined_minimum_size()])
	print("VIEWPORT root %s, window %s" % [root.size, DisplayServer.window_get_size()])
	# **AND IF THE BOX IS NOT THE SIZE IT WAS ASKED FOR, WHERE THE HEIGHT CAME FROM** -- the chain of
	# minimums from each named part up to the box, because the answer is a sum and only the chain
	# shows which node is paying it. Printed ONLY when there is something to explain: this found a
	# 450 px overshoot (ASSA-332) and would be five lines of noise on every other run.
	if screen_rect.size.y > asked.size.y + 1.0 or screen_rect.size.x > asked.size.x + 1.0:
		_faults.append("the box is %.0f x %.0f and `build_screen_rect` asked for %.0f x %.0f"
				% [screen_rect.size.x, screen_rect.size.y, asked.size.x, asked.size.y])
		# **THE ASSEMBLY PATH'S OWN TWO BLOCKS ARE IN THIS LIST AS OF ASSA-317 SLICE 2b.** It held the
		# five leaves the make path has, so the first run that overflowed named every block EXCEPT the
		# slots and the mount list -- the two that only exist on the path that overflowed. A chain that
		# cannot reach the node paying for the height reports the overshoot and hides its cause.
		for leaf in [_screen._build_picker, _screen._build_materials, _screen._build_detail,
				_screen._build_cost, _screen._build_said, _screen._build_slots,
				_screen._build_mounts]:
			var node := leaf as Control
			var trail := PackedStringArray()
			while node != null and node != _screen._build_box:
				trail.append("%s min %.0fx%.0f size %.0fx%.0f" % [node.name,
						node.get_combined_minimum_size().x, node.get_combined_minimum_size().y,
						node.size.x, node.size.y])
				node = node.get_parent() as Control
			print("    %s" % " <- ".join(trail))
	var column := AssayHud.VIEW.x - AssayHud.PANEL
	if screen_rect.end.x > column:
		_faults.append("the screen reaches x %.0f and the HUD column starts at %.0f"
				% [screen_rect.end.x, column])
	var watched := {
		"whole world (V)": _screen._view_toggle,
		"show the map key (K)": _screen._map_key_toggle,
		"the status toast": _screen._says_toast,
	}
	for named in watched:
		var node := watched[named] as Control
		var rect := Rect2(node.global_position, node.size)
		var over := screen_rect.intersection(rect)
		print("%-22s %s  visible=%s  overlap=%s" % [named, rect, node.visible, over.size])
		if not node.visible:
			# **AN INVISIBLE CONTROL IS NOT A PASS AND NOT A FAIL.** The toast is drawn only while the
			# client has something to say (ASSA-239), so it is legitimately absent here -- and that
			# means this run did NOT measure the screen against it. Said out loud, because a silent
			# skip is how "measured" comes to mean "assumed".
			print("    NOT MEASURED: this control is hidden in this frame, so nothing was compared")
			continue
		if rect.size.y <= 0.0:
			_faults.append("%s reports no size in a laid-out window, so nothing was measured"
					% named)
		elif over.size.x > 0.0 and over.size.y > 0.0:
			_faults.append("the screen covers %s by %.0f x %.0f px"
					% [named, over.size.x, over.size.y])
	# **AND THE CONSTANT IS COMPARED TO THE MEASUREMENT, which is the whole reason this tool exists.**
	# The band's real top is the highest of the visible controls; `WORLD_CONTROLS_BAND` is what the
	# headless suite believes. A drift is not a failure -- the constant is deliberately generous -- but
	# an unreported drift is how it rots, so the number is printed either way.
	var world := AssayHud.world_rect()
	var top := world.end.y
	for named in watched:
		var node := watched[named] as Control
		if node.visible and node.size.y > 0.0:
			top = minf(top, node.global_position.y)
	print("BAND     measured top %.0f, world bottom %.0f, so the band is %.0f px tall"
			% [top, world.end.y, world.end.y - top])
	print("         WORLD_CONTROLS_BAND says %.0f; %s"
			% [AssayHud.WORLD_CONTROLS_BAND,
			"generous by %.0f px" % (AssayHud.WORLD_CONTROLS_BAND - (world.end.y - top))
			if AssayHud.WORLD_CONTROLS_BAND >= world.end.y - top
			else "SHORT by %.0f px" % ((world.end.y - top) - AssayHud.WORLD_CONTROLS_BAND)])
	if AssayHud.WORLD_CONTROLS_BAND < world.end.y - top:
		_faults.append(("WORLD_CONTROLS_BAND is %.0f and the real band is %.0f px tall, so the "
				+ "headless answer would put the screen over a control")
				% [AssayHud.WORLD_CONTROLS_BAND, world.end.y - top])
	_measure_commit_bar(screen_rect)


## **THE COMMIT BAR, IN A LAID-OUT WINDOW** (ASSA-332; Maren's §5.4 ruling 3: *"the COMMIT BAR,
## 863 x 112 at y 529..641"*, `Build` ≤ 160 px, the sentence ≥ 687, blocks 2/4/6 ending at y 513).
##
## **EVERY ABSOLUTE NUMBER IS PRINTED AND NONE OF THEM IS A FAULT, which is deliberate.** Her rects
## are measured on a 1280x720 window whose control band is where it was the day she measured it; the
## screen's own top and bottom come from `build_screen_rect` reading the LIVE band, so a toast that is
## one pixel taller moves all four numbers and none of that is a defect. **So the numbers go to her
## and the RELATIONS are the faults**: the bar is her height, `Build` is inside her ceiling and at the
## bar's right end, and the sentence gets at least the width the wrap was measured at. That is the
## rule I keep writing down -- hand over the picture and the numbers, never the verdict.
func _measure_commit_bar(screen_rect: Rect2) -> void:
	var bar := _screen._build_bar as Control
	var act := _screen._build_act as Control
	var said := _screen._build_said as Control
	if bar == null or act == null or said == null:
		_faults.append("the screen has no commit bar, sentence or `Build` to measure")
		return
	var bar_rect := Rect2(bar.global_position, bar.size)
	var act_rect := Rect2(act.global_position, act.size)
	var said_rect := Rect2(said.global_position, said.size)
	print("BAR      %s  (%.0f x %.0f)  y %.0f..%.0f"
			% [bar_rect, bar_rect.size.x, bar_rect.size.y, bar_rect.position.y, bar_rect.end.y])
	print("         her rect is 863 x 112 at y 529..641, on the band she measured")
	print("BUILD    %s  width %.0f  right edge %.0f (bar's is %.0f)"
			% [act_rect, act_rect.size.x, act_rect.end.x, bar_rect.end.x])
	var owed := AssayHud.commit_sentence_width(bar_rect.size.x, float(_screen.BUILD_GUTTER))
	print("SENTENCE %s  width %.0f, floor %.0f (bar %.0f - Build's %.0f ceiling - gutter %d)"
			% [said_rect, said_rect.size.x, owed, bar_rect.size.x, AssayHud.BUILD_ACT_WIDTH,
			_screen.BUILD_GUTTER])
	# **THE SENTENCE'S OWN ROW STRUCTURE, WHICH IS THE NUMBER ASSA-341 BOX 9 IS ABOUT.** The bar is
	# ruled at 114 = six 18 px rows plus the 6 px inset, so *how many rows* is the question a reader
	# of these shots has to be able to answer. **IT IS NOT THE LABEL COUNT:** the make path draws one
	# Label per clause and each clause then WRAPS, while the assembly path draws exactly one Label
	# that may wrap by itself (`_said_about_design`). So both numbers are printed, and the rows are
	# the engine's own `get_line_count` rather than a division I did on the heights.
	var rows := 0
	var row_one := Rect2()
	var row_one_height := 0.0
	for child in said.get_children():
		var text := child as Label
		if text == null:
			continue
		if rows == 0:
			row_one = Rect2(text.global_position, text.size)
			row_one_height = float(text.get_line_height())
		rows += text.get_line_count()
		print("    %d row(s)  %-10s  %s" % [text.get_line_count(),
				str(text.theme_type_variation) if str(text.theme_type_variation) != "" else "BODY",
				text.text])
	print("SAID     %d label(s), %d row(s) in total, row 1 is %.0f px tall"
			% [said.get_child_count(), rows, row_one_height])
	# **BOX 9's TWO RELATIONS, PRINTED ON BOTH SHOTS SO NEITHER HAS TO BE TRUSTED ALONE.** `Build`'s y
	# against the BAR'S TOP is the mechanism -- a control at a container's top cannot be moved by a
	# sibling below it -- and `Build`'s centre against ROW 1's centre is the alignment ruling 4 asked
	# for. **A VERDICT IS NOT PRINTED HERE AND THAT IS DELIBERATE:** whether these two shots show the
	# behaviour is the Game Director's judgement on the pair, not this tool's on one.
	print("BOX 9    Build y %.0f, bar top %.0f, delta %.0f" % [act_rect.position.y,
			bar_rect.position.y, act_rect.position.y - bar_rect.position.y])
	var row_one_centre := row_one.position.y + row_one_height / 2.0
	var act_centre := act_rect.position.y + act_rect.size.y / 2.0
	print("BOX 8    row 1 centre %.0f, Build centre %.0f, apart %.0f"
			% [row_one_centre, act_centre, absf(row_one_centre - act_centre)])
	# **AND BOX 8's RELATION IS A FAULT AND NOT JUST A NUMBER, WHICH IS THE RULE THIS FILE ALREADY
	# STATES: the numbers go to her and the RELATIONS are the faults.** Her ruling 4 is
	# `|Build.centre - row 1.centre| <= 2`, so a tool that printed 5 and exited 0 would be green about
	# a ruling it had just measured broken -- the exact shape of defect every other check here exists
	# to refuse. **THIS IS THE CHECK THAT FOUND ASSA-363**: the inset was the constant
	# `BUILD_SENTENCE_INSET`, 6, derived from a `BODY` row, so the assembly path's `Display` row 1 came
	# out 5 px low -- `(28 - 18) / 2`, printed here as a fault on the slots-full shot while the
	# slots-empty shot beside it read 0. It is now `AssayHud.commit_inset` off the heights this window
	# laid out, and the inset is printed below so the pair can be read without re-deriving it.
	var inset := 0
	var inset_box := _screen._build_said_inset as Control
	if inset_box != null:
		inset = inset_box.get_theme_constant(&"margin_top")
	print("INSET    sentence inset %d px  (Build %.0f, row 1 %.0f -> commit_inset %.1f)"
			% [inset, act_rect.size.y, row_one_height,
			AssayHud.commit_inset(act_rect.size.y, row_one_height)])
	if row_one_height > 0.0 and absf(row_one_centre - act_centre) > BOX_8_TOLERANCE:
		_faults.append(("`Build`'s centre is %.0f and row 1's is %.0f, %.0f px apart against her %.0f "
				+ "px bar: row 1 measures %.0f px against `Build`'s %.0f, and the sentence is inset %d")
				% [act_centre, row_one_centre, absf(row_one_centre - act_centre), BOX_8_TOLERANCE,
				row_one_height, act_rect.size.y, inset])
	var block6 := (_screen._build_cost as Control).get_parent() as Control
	if block6 != null:
		print("BLOCK 6  bottom %.0f, bar top %.0f, gap %.0f (her blocks end at y 513)"
				% [block6.global_position.y + block6.size.y, bar_rect.position.y,
				bar_rect.position.y - (block6.global_position.y + block6.size.y)])
	if absf(bar_rect.size.y - AssayHud.BUILD_COMMIT_BAR) > 1.0:
		_faults.append("the bar is %.0f px tall and `BUILD_COMMIT_BAR` asks for %.0f"
				% [bar_rect.size.y, AssayHud.BUILD_COMMIT_BAR])
	if act_rect.size.x > AssayHud.BUILD_ACT_WIDTH:
		_faults.append(("`Build` is %.0f px wide and her ceiling is %.0f, so the sentence is below "
				+ "the width the wrap was measured at")
				% [act_rect.size.x, AssayHud.BUILD_ACT_WIDTH])
	if absf(act_rect.end.x - bar_rect.end.x) > 1.0:
		_faults.append("`Build` ends at x %.0f and the bar ends at x %.0f: it is not right-aligned"
				% [act_rect.end.x, bar_rect.end.x])
	if said_rect.size.x + 1.0 < owed:
		_faults.append("the sentence gets %.0f px of the bar and is owed %.0f"
				% [said_rect.size.x, owed])
	# **AND THE BAR IS INSIDE THE SCREEN IT IS A BLOCK OF**, which is the one absolute that IS a fault:
	# a 112 px bar on a screen too short for it would hang past the world's control band, and the whole
	# of `build_screen_rect` is about not covering that.
	if bar_rect.end.y > screen_rect.end.y + 1.0:
		_faults.append("the bar's bottom is %.0f and the screen ends at %.0f"
				% [bar_rect.end.y, screen_rect.end.y])


## **THE MAKE PATH'S FILENAME IS UNCHANGED** (`build-screen-<seed>.png`): three pieces of evidence
## on ASSA-332, ASSA-341 and ASSA-343 point at that name, and moving an artefact somebody else's
## comment cites is a silent break. The assembly shots take a suffix because there are two of them.
func _write(suffix: String) -> void:
	var image := root.get_texture().get_image()
	var named := ("build-screen-%s.png" % _seed if suffix == ""
			else "build-screen-%s-%s.png" % [_seed, suffix])
	var path := "%s/%s" % [_out, named]
	if image.save_png(path) != OK:
		_faults.append("could not write %s" % path)
		return
	print("  %s  %dx%d" % [path, image.get_width(), image.get_height()])


func _find(node: Node, label: String) -> Button:
	for child in node.find_children("*", "Button", true, false):
		if (child as Button).text == label:
			return child as Button
	return null


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_screen) and _screen.has_method("stop_solo_relay"):
		_screen.stop_solo_relay()
	if ok:
		print("BUILD SCREEN SHOT OK · nothing covered")
	else:
		print("FAIL  %s" % why)
	quit(0 if ok else 1)
