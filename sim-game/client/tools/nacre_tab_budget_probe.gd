extends SceneTree
## **DOES ONE TAB FIT?** The number I promised Maren on ASSA-198 BEFORE building the tabbed panel.
##
##   godot --path . --script res://tools/nacre_tab_budget_probe.gd -- [seed]
##
## NOT `--headless`, and this is the whole reason the measurement lives in a tool instead of a test:
## `tests/run_tests.gd` works inside `SceneTree._initialize`, so no frame is drawn and no container
## ever lays out -- every `position` and every `size.y` in the HUD column reads 0.0. A headless
## assertion about section heights is an assertion about zero, and it passes.
##
## **WHAT IS BEING DECIDED.** Wren's ruling on ASSA-198: *"a panel that needs scrolling to reach its
## own last section fails"*, and Maren's: *"what the panel must do instead is STOP SCROLLING"*. Tabs
## are the proposed fix -- `you` and `do` always on, then ONE of `make` / `bench` / `rocks` visible at
## a time. That fix is only a fix if the TALLEST single tab fits in what the column leaves. If `rocks`
## alone overflows, tabs have moved the defect rather than removed it, and the answer is a different
## split (or a scrolling tab, which is the defect with extra steps). I am not building the panel on a
## premise I have not measured.
##
## **HIGH WATER, NOT A TICK SOMEBODY PICKED.** A budget has to hold the worst moment of a play, not an
## average one: `rocks` grows as species are discovered, `bench` as buildings are planted, `make` as
## the pack fills (Maren measured `make` growing +198px across one craft session). So every section is
## measured on EVERY TICK of a real offline play -- not on sampled ticks, and not on a high-water
## trigger, for the reason written over `_play_a_frame` -- and the tallest reading wins, with the tick
## it happened on. A single-tick measurement here would be an honest number about an irrelevant
## moment.
##
## **HEIGHTS ARE SUMMED FROM VISIBLE CHILDREN, NOT TAKEN AS A SPAN.** A `VBoxContainer` skips hidden
## children when it lays out, so a hidden control keeps whatever rect it last had -- taking
## `last.end.y - heading.position.y` would fold a stale rect into the answer the first time anything
## is folded away (`_make` is, by its own toggle). Summing `size.y` over the visible children plus one
## separation between each is exact for a VBox, and the report prints the parts so the total can be
## checked by arithmetic rather than believed.

const DEFAULT_SEED := "14247"
## **GENEROUS ON PURPOSE.** Measuring every tick costs three frames a tick, and macOS throttles the
## frame rate of a window that is not focused -- so the same 519-tick play takes well under a minute
## with the window in front and several minutes behind another app. A ceiling tuned to the focused
## case turns "nobody clicked on it" into a failed measurement.
##
## **RAISED FROM 900 AFTER 900 WAS NOT ENOUGH**, and the reason is worth keeping: a `_bail` prints
## `FAIL` and NO NUMBERS, so a run that overruns does not give a partial answer -- it gives nothing,
## after fifteen minutes. The probe is driven from a terminal, so its window is never the focused one
## and the throttled path is the ONLY path it ever takes here. Tuning this to the unfocused case is
## tuning it to reality.
const RUN_CEILING := 2400.0
## Frames between a tick and its reading. Two, not three: the rows change inside `_refresh_*` on the
## frame the bundle lands and the container lays out on the next one, so the second frame is already
## settled. The third was belt and braces at a 33% cost in wall-clock on the slow path.
const SETTLE_FRAMES := 2
## The play's own length, in ticks. `button_play.gd` finishes well inside this; the cap is here so a
## loop that stalls ends the run instead of hanging it.
const TICK_BUDGET := 1200
## **HOW OFTEN THE RUN SAYS IT IS ALIVE, AND IT IS NOT DECORATION.** The first attempt at this
## measurement printed nothing for fifteen minutes and then `FAIL ran past its 900s ceiling in phase
## 1`, and from that output I could not tell a slow run from a wedged one -- the play's last line was
## 400 ticks behind the clock. A probe whose only two states are "silent" and "failed" cannot be
## debugged, and the instrument being mute was my defect, not the machine being slow.
const PROGRESS_EVERY := 50

enum Phase { PLAY, SETTLE, MEASURE, REPORT, OVER }

var _screen: Node = null
var _play: AssayButtonPlay = null
var _seed := DEFAULT_SEED
var _phase := Phase.PLAY
var _started := false
var _left := TICK_BUDGET
var _waited := 0
var _asked: Array = []
var _done := false
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING
## How many ticks were measured. Printed, because "every tick" is a claim with a number behind it.
var _ticks_measured := 0
## section name -> {"h", "body", "head": float, "tick", "n": int, "parts": String}, the tallest
## reading of that section seen so far.
var _best := {}
## section name -> {"must_fit": float, "buttons": int, "tick": int}: the deepest its lowest button
## ever reached below its own body top. Wren's fold rule is judged on THIS, not on the body.
var _reach := {}
## **THE SMALLEST THE CLIP EVER GETS, AND THE LAST ONE, BECAUSE THEY ARE NOT THE SAME NUMBER.**
## `_running_box` and `_halt_box` sit ABOVE the scroll inside `chrome` and appear and disappear with
## the world: a stopped machine grows the halt block and the scroll gets whatever is left. So the
## clip a tab must survive is the SMALLEST one the play ever produced, not the roomy one a settled
## world ends on. Taking the last reading would have set the budget on the best moment of the play.
var _clip_min := INF
var _clip_min_tick := 0
var _clip_last := 0.0
## The tallest `you` + `do` block measured on ONE tick, which is not the sum of their two separate
## high waters. See `_measure`.
var _always_on_max := 0.0
var _always_on_tick := 0
## HOW FAR THE OPEN TAB'S LOWEST BUTTON REACHED PAST THE CLIP, per tab, worst reading of the run.
## This is Wren's rule as a number, and zero everywhere is the only passing answer.
var _over_fold := {}
## How far a tab's HIGHEST button was carried above the top of the box that clips it. The other edge
## of `_over_fold`, and zero is the rule kept on both.
var _off_top := {}
var _off_top_tick := {}
var _over_tick := {}
## **THE OTHER AXIS** (Maren's ruling, box 2 is read as EITHER edge). How far a tab's worst Button
## was drawn outside the PAINTED column left or right, the worst reading of the run, with the name
## and the x range of the control that did it. Zero everywhere is the only passing answer, same as
## `_over_fold` -- and until 2026-10-06 nothing we owned asked it, while five `Make` buttons sat
## 614 px off the right of the window.
var _off_side := {}
var _off_side_tick := {}
var _off_side_who := {}
## THE PAINTED COLUMN'S OWN WIDTH, printed so the verdicts above can be checked by arithmetic. It is
## `AssayHud.PANEL` and it is read, never assumed: the whole point of the reference is that it is a
## `Panel` and not a `Container`, so if it ever became one this number would move and say so.
var _paint_w := 0.0
## HOW MANY TICKS EACH TAB WAS THE OPEN ONE. Printed, because "every tick" is not true per tab any
## more and a report that implied it would be overstating its own instrument.
var _tabs_measured := {}
## WHICH TAB THE NEXT TICK OPENS. See `_measure`: one tab per tick, so every reading is laid out.
var _tab_cycle := 0
var _tab_strip_h := 0.0
var _separation := 0
var _final_tick := 0
var _play_said := ""
## Set once the loop is over, so `_measure` knows its next reading is the last one.
var _last_pass := false


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if not argv.is_empty():
		_seed = String(argv[0])
	var saves := OS.get_user_data_dir().path_join("nacre-tab-budget-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	OS.set_environment("R2TS_SAVES_DIR", saves)
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	# THE COMMANDS THE PLAY PRESSES, CAUGHT THE WAY `window_shot.gd` CATCHES THEM: offline, this
	# script is the relay, so a pressed button has to come back as an input on the next bundle.
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)
	print("window %s, viewport %s, seed %s" % [DisplayServer.window_get_size(), root.size, _seed])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		_bail("ran past its %ds ceiling in phase %d" % [int(RUN_CEILING), _phase])
		return true
	match _phase:
		Phase.PLAY:
			_play_a_frame()
		Phase.SETTLE:
			# A LAYOUT PASS BETWEEN THE TICK AND THE TAPE MEASURE. The rows change inside
			# `_refresh_*` on the frame the bundle lands; the container that holds them lays out on
			# the NEXT frame, so measuring in the same frame measures the state before the change.
			_waited += 1
			if _waited >= SETTLE_FRAMES:
				_waited = 0
				_phase = Phase.MEASURE
		Phase.MEASURE:
			_measure()
			# **ONLY BACK TO PLAY IF `_measure` DID NOT ASK FOR THE REPORT, AND THIS LINE IS WHY TWO
			# RUNS DIED WITHOUT A NUMBER.** It used to assign `Phase.PLAY` unconditionally, one line
			# after `_measure()` had set `Phase.REPORT` on the last pass -- so the ask was overwritten
			# every time it was made. The run then span: PLAY saw `_play.finished`, `_end_play` set
			# SETTLE and `_last_pass` again, MEASURE asked for REPORT again, and this line threw it
			# away again, until the wall-clock ceiling killed it with `FAIL ... in phase 1` and no
			# measurement at all. The play itself was finishing in 75 seconds the whole time.
			if _phase == Phase.MEASURE:
				_phase = Phase.PLAY
		Phase.REPORT:
			_report()
	return _done


## ONE TICK, THEN A SETTLE, THEN A MEASUREMENT -- FOR EVERY TICK OF THE PLAY.
##
## **THE FIRST VERSION OF THIS ONLY MEASURED WHEN THE PACK OR THE OFFER LIST GREW**, copying
## `window_shot.gd`'s high-water trigger, and that trigger is wrong for this question. It is a proxy
## for the height of `you` and `make`, and those are not the sections at risk: `rocks` grows when a
## SPECIES IS DISCOVERED and `bench` when a BUILDING IS PLANTED, neither of which moves a row count.
## So the one section most likely to overflow could have had its tallest moment sampled by nothing.
##
## Measuring every tick costs four frames a tick -- about 35 seconds of real time for a 519-tick play
## -- and buys a claim with no sampling hole in it: every state this loop passes through is measured,
## with a layout pass between the tick and the tape measure.
func _play_a_frame() -> void:
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "nacre")
		if welcome == "":
			_bail("could not make a world on seed %s" % _seed)
			return
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		if not _screen._sim.running():
			_bail("offline welcome did not start a sim: %s" % _screen._sim.fail_reason)
			return
		_started = true
		_phase = Phase.SETTLE
		return
	if _left <= 0 or _play.finished:
		_end_play()
		return
	_left -= 1
	_play.advance()
	if _play.finished:
		_end_play()
		return
	var inputs := []
	for command in _asked:
		inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
	_asked.clear()
	var at: int = _screen._sim.tick()
	var before: int = _screen._sim.applied
	_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
	if _screen._sim.applied == before:
		_bail("the sim refused the bundle for tick %d" % at)
		return
	_ticks_measured += 1
	# ALIVE, WITH THE TWO NUMBERS THAT TELL SLOW FROM STUCK: how far the play has got, and how much
	# of the ceiling it has spent getting there. Rate is the useful one -- it says whether the run
	# will finish inside the ceiling long before the ceiling arrives.
	if _ticks_measured % PROGRESS_EVERY == 0:
		var spent := RUN_CEILING - (_ceiling - Time.get_unix_time_from_system())
		print("  ... %d ticks measured, sim at tick %d, %ds of %ds spent (%.1f ticks/s)"
				% [_ticks_measured, _screen._sim.tick(), int(spent), int(RUN_CEILING),
				float(_ticks_measured) / maxf(spent, 0.001)])
	_phase = Phase.SETTLE


## THE PLAY IS OVER: take ONE more reading at rest, then report.
##
## The last reading is not a formality. The loop's final act can grow a section on the very frame it
## finishes, and that frame has had no layout pass yet -- so without this the tallest `bench` of the
## play could be the one state never measured.
func _end_play() -> void:
	_play_said = "tick %d, step %s" % [_screen._sim.tick(),
			AssayButtonPlay.Step.keys()[_play.step]]
	if _play.failed != "":
		_bail("the loop stopped: %s" % _play.failed)
		return
	_final_tick = _screen._sim.tick()
	_last_pass = true
	_left = 0
	_phase = Phase.SETTLE


## THE COLUMN'S SECTIONS, READ OFF THE TREE RATHER THAN FROM A LIST I KEEP IN STEP BY HAND.
##
## `main.gd` builds the column as a flat run of children -- a `Heading` Label, then that section's
## bodies, then the next heading -- so a heading is where a section starts and the next one is where
## it ends. Walking the tree means a seventh section added tomorrow is measured without this file
## being touched; a hardcoded list would silently keep reporting six.
## **THE SECTIONS ARE TAB BODIES NOW, AND ONLY THE OPEN ONE CAN BE MEASURED** (ASSA-247 is built;
## this probe measured the column it was built out of).
##
## It used to walk one scroll box's children and cut them at every `Heading` Label. There is no such
## column any more: `do` is pinned in the chrome, the four systems are tab bodies, and three of the
## four are HIDDEN at any moment.
##
## **A HIDDEN BODY READS 0 px AND WOULD PASS EVERY RULE**, which is this repo's blank-frame trap in a
## new costume -- the same reason a layout fact may never be asserted headless. So this returns the
## OPEN tab only, and `_measure` cycles which tab that is, one per tick: a body revealed this frame
## has not been laid out yet, so measuring all four in one frame would read three stale rects.
## Reported honestly as "N ticks each, round-robin" rather than "every tick".
func _column_sections() -> Array:
	var out: Array = []
	if _screen._tabs == null:
		return out
	# TYPED EXPLICITLY, not inferred: `_screen` is a plain `Node` here, so anything off it crosses as
	# an untyped Variant and `:=` has nothing to infer from (the parse error that caught this).
	var open_tab: String = _screen._tabs.selected()
	if open_tab != "":
		var body: Control = _screen._tabs.body_of(open_tab)
		if body != null:
			out.append({"name": open_tab, "top": body, "controls": _parts_of(body)})
	# THE ALWAYS-ON BLOCK, which is `do` and its heading -- the one section Wren left above the tabs.
	# Its heading is a sibling in the chrome rather than a child of anything, so it is named here
	# rather than found: `_actions`' previous sibling is that Label by construction.
	var actions: Control = _screen._actions
	var head: Control = null
	var chrome: Node = actions.get_parent()
	var idx: int = actions.get_index()
	if idx > 0:
		head = chrome.get_child(idx - 1) as Label
	out.append({"name": "do", "top": head if head != null else actions,
			"controls": [head, actions] as Array})
	# AND THE FOOTER, which is the cursor readout: in the scrolled area, under whichever tab is open,
	# carrying no control. Measured so its cost is a number rather than my claim that it is free.
	out.append({"name": "cursor", "top": _screen._cursor,
			"controls": [_screen._cursor] as Array})
	return out


## A tab body's own parts: its children, so `make` is [assembling, toggle, rows] exactly as the old
## column's section-cut produced.
func _parts_of(body: Control) -> Array:
	var out: Array = []
	for child in body.get_children():
		var control := child as Control
		if control != null:
			out.append(control)
	return out


## **HOW MUCH OF A SECTION IS WRAP.** Maren's Gap 3 says the column is prose where it should be
## data, and the tab budget turned that from a style note into the binding constraint. This is the
## lever, measured per section instead of estimated once for `make`.
##
## A section's rows live in the LIST -- the tallest body control that is a container with more than
## one visible child (`_carrying`, `_make`, `_species` are each a VBox of rows). A themed Button is
## the yardstick for one line, because it is the shortest thing in this column that a row can be and
## still carry a control. A row measurably taller than that is a row the 320 px column has wrapped.
##
## **WHAT THIS CANNOT TELL ANYONE, so the report does not pretend otherwise:** it measures how tall
## rows ARE, not how tall they COULD be. "One-line rows would be N px" is arithmetic on a yardstick,
## not a measurement of a thing that exists, and the report labels it as such.
func _row_stats(controls: Array) -> Dictionary:
	var best: Control = null
	var best_rows := 0
	for i in range(controls.size()):
		var control := controls[i] as Control
		if control == null or i == 0 or not control.is_visible_in_tree():
			continue
		var rows := 0
		for child in control.get_children():
			var row := child as Control
			if row != null and row.is_visible_in_tree():
				rows += 1
		if rows > best_rows:
			best_rows = rows
			best = control
	if best == null or best_rows == 0:
		return {"rows": 0, "tallest": 0.0, "total": 0.0}
	var tallest := 0.0
	var total := 0.0
	for child in best.get_children():
		var row := child as Control
		if row == null or not row.is_visible_in_tree():
			continue
		total += row.size.y
		if row.size.y > tallest:
			tallest = row.size.y
	return {"rows": best_rows, "tallest": tallest, "total": total}


## HOW TALL A SECTION IS AS DRAWN: its visible children's heights plus one separation between each.
##
## **THE HEADING IS MEASURED SEPARATELY, AND IT IS NOT A DETAIL.** In a tabbed panel the TAB BUTTON
## is what names the section, so the in-panel `make` heading is exactly the thing a tab strip
## replaces -- counting it against the tab's own budget would charge the design twice for the same
## word. `h` is the section as it stands in the column today (the before number); `body` is what
## would actually have to fit inside a tab (the after number). Both are reported, because the
## difference is the honest cost of the strip and not a rounding error.
##
## `Array` and not `Array[Control]`: the list arrives out of a Dictionary, so it crosses as an
## untyped Variant and a typed parameter refuses it at runtime.
## **`has_heading` IS EXPLICIT SINCE THE TABS LANDED, and it was an index before.** A tab's body has
## no heading in it -- the tab's own name is that heading, which is where the height went -- so
## subtracting its first child as "the heading" would report a `make` body one assembling-box short
## and flatter the design by exactly the number this probe exists to check.
func _drawn_height(controls: Array, has_heading := true) -> Dictionary:
	var parts := PackedStringArray()
	var total := 0.0
	var head := 0.0
	var seen := 0
	for item in controls:
		var control := item as Control
		if control == null or not control.visible:
			continue
		if seen > 0:
			total += float(_separation)
		total += control.size.y
		if seen == 0 and has_heading:
			head = control.size.y
		seen += 1
		parts.append("%d" % int(round(control.size.y)))
	# The heading plus the separation under it: what the section stops paying once a tab names it.
	var body := total - head - (float(_separation) if seen > 1 and has_heading else 0.0)
	return {"h": total, "body": maxf(body, 0.0), "head": head, "n": seen,
			"parts": "+".join(parts)}


## **WREN'S FOLD RULE, MEASURED** (ASSA-198, 19:40 EDT): *"NO CONTROL IS EVER BELOW THE FOLD. A
## tab's buttons are reachable at 1280x720 without scrolling. A tab's LIST may scroll inside its own
## tab if the data is unbounded (rocks, later mineralogy): a list of forty rocks scrolling is a list;
## a cut Make button is a defect."*
##
## **THIS IS THE REFINEMENT THAT CHANGES THE QUESTION, AND IT MAY RESCUE THE DESIGN.** My own
## deciding number was the tallest tab's whole body against the budget, which charges `rocks` -- six
## species of read-only prose -- for height it is allowed to scroll. What a tab must actually fit is
## the distance from the top of its body to the BOTTOM OF ITS LOWEST BUTTON. For `rocks` that is
## zero, because it has no buttons at all. For `make` it is very nearly the whole list, because every
## row carries a Make.
##
## Buttons are found by walking DESCENDANTS, not children: a make row is an HBox with the label and
## the Button inside it, so a child-only sweep would find no buttons anywhere in the section and
## report a comfortable zero for the one section this rule exists to protect.
##
## `is_visible_in_tree`, not `visible`: a Make button inside a folded `_make` is `visible` with
## nothing on screen, and counting it would measure a control no player can reach.
## **AND THE RULE IS NOW MEASURED AGAINST THE CLIP ITSELF, NOT AGAINST A BUDGET** (ASSA-247 is
## built). Before the panel existed the only way to ask this question was arithmetic: take the clip,
## subtract the always-on block and the strip, call what is left a budget, and compare the tallest
## section's reach to it. Wren's own words on that: *"one-line rows ~304 is arithmetic on a
## yardstick, not a build: measure the build."*
##
## The build exists, so `over_fold` is the whole verdict: how far the LOWEST visible Button of the
## open tab reaches past the bottom of the box it is clipped by. Zero is the rule being kept. The
## budget arithmetic stays in the report beside it because a ruling was made on it and the two
## should be seen to agree -- but it is no longer what decides anything.
##
## `top_control` rather than an index: a tab's body has no heading to skip, and `reach` is still
## reported because it is the number the old run was judged on.
##
## **AND THE FOLD HAS A THIRD EDGE, WHICH THIS PROBE SAID NOTHING ABOUT WHILE IT WAS BROKEN**
## (Maren's ruling, 2026-10-06 19:50: *"box 2 is read as EITHER axis"*). On the build before
## `252fdb6` every one of the make tab's five `Make` buttons was drawn at **x 1894..1944** — 614 px
## past the right edge of a 1280 px window, the crafting menu the board asked for by name with not
## one pressable control in it — and this function reported `over_fold 0` and was telling the truth.
## A column laid out wider than the window falls off a second edge, and every instrument we owned
## watched the vertical one. **She found it by pressing a control nobody had pressed; no number we
## had could have.**
##
## **`paint` IS A SEPARATE ARGUMENT FROM `frame` AND THAT IS THE ENTIRE CARE IN THIS CHANGE.** The
## obvious build is to reuse `frame` — it is a Rect2, it already bounds x. It would be a check that
## cannot fail: `frame` is the intersection of the clipping ancestors, and the defect is those very
## ancestors being CLAMPED UP to a 998 px child, so the frame grows exactly as much as the overflow
## and the arithmetic reads zero forever. The reference has to be something the defect cannot move:
## `main.gd`'s `COLUMN_SURFACE` is a plain `Panel`, not a `Container`, so it keeps the 320 px it was
## given no matter what its neighbours demand. That is the rect Maren's ruling names, and it is the
## one honest answer available in-process.
func _button_reach(top_control: Control, controls: Array, frame: Rect2, paint: Rect2) -> Dictionary:
	var top := INF
	if top_control != null and top_control.is_visible_in_tree():
		top = top_control.get_global_rect().position.y
	var lowest := -INF
	# **THE HIGHEST BUTTON'S TOP, BECAUSE A SCROLL BOX HAS TWO EDGES AND I WAS ONLY WATCHING ONE.**
	# `over_fold` asks how far the lowest button fell past the BOTTOM of the clip. A control scrolled
	# off the TOP of the same box is exactly as unreachable and scored zero -- `maxf(lowest - end.y, 0)`
	# is literally true and completely wrong about it. Found by looking at a real shot: with the box
	# scrolled to put the species list at the frame top, Mineralogy's `go here` was off the top of the
	# panel and this function still called the tab ABOVE THE FOLD.
	var highest := INF
	var count := 0
	# THE HORIZONTAL HIGH WATER, AND THE NAME OF THE CONTROL THAT SET IT. A count of pixels says a
	# tab is broken; the name says which control to press, which is what cost Maren a shot and me a
	# wake-up to find out by hand.
	var off_right := 0.0
	var off_left := 0.0
	var worst := ""
	for item in controls:
		var control := item as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control.get_global_rect().position.y < top:
			top = control.get_global_rect().position.y
		for node in _descendants(control):
			var button := node as Button
			if button == null or not button.is_visible_in_tree():
				continue
			count += 1
			var rect := button.get_global_rect()
			if rect.end.y > lowest:
				lowest = rect.end.y
			if rect.position.y < highest:
				highest = rect.position.y
			# THE WHOLE RECT, NOT ITS ORIGIN: a Button that starts inside the paint and ends outside
			# it is a control with its label cut, which is the `go here` slab Maren photographed --
			# a full-width rounded rectangle with no text in it, because a Button centres its label
			# and the centre was 120 px past the window.
			var out_right := maxf(rect.end.x - paint.end.x, 0.0)
			var out_left := maxf(paint.position.x - rect.position.x, 0.0)
			if maxf(out_right, out_left) > maxf(off_right, off_left):
				worst = "%s `%s` x %d..%d" % [button.name, button.text,
						int(rect.position.x), int(rect.end.x)]
			off_right = maxf(off_right, out_right)
			off_left = maxf(off_left, out_left)
	if count == 0 or top == INF:
		return {"must_fit": 0.0, "buttons": 0, "over_fold": 0.0, "off_top": 0.0,
				"off_right": 0.0, "off_left": 0.0, "worst": ""}
	return {"must_fit": maxf(lowest - top, 0.0), "buttons": count,
			"over_fold": maxf(lowest - frame.end.y, 0.0),
			"off_top": maxf(frame.position.y - highest, 0.0),
			"off_right": off_right, "off_left": off_left, "worst": worst}


## Every Control at or under `from`, itself included, so a Button nested in a row is found.
func _descendants(from: Control) -> Array:
	var out: Array = [from]
	var stack: Array = [from]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			out.append(child)
			stack.append(child)
	return out


func _measure() -> void:
	# THE SEPARATION IS A TAB BODY'S NOW, not the old column's: that is the constant between the
	# controls inside one system, which is what every height below is summed with.
	var column := _screen._tabs.body_of(_screen._tabs.selected()) as VBoxContainer
	if column == null:
		_bail("no tab is open, so there is nothing laid out to measure")
		return
	_separation = column.get_theme_constant(&"separation")
	# WHAT THE SCROLL BOX LEAVES, not what the window leaves. `window_shot.gd::_frame_for` is the
	# reference for this: the column lives in a `ScrollContainer` whose box ends above the window's
	# bottom edge, so measuring against the window would credit the budget with pixels no section can
	# ever be seen in.
	var frame := Rect2(Vector2.ZERO, root.size)
	var node: Node = _screen._carrying.get_parent()
	while node != null:
		var ancestor := node as Control
		if ancestor != null and (ancestor.clip_contents or ancestor is ScrollContainer):
			frame = frame.intersection(ancestor.get_global_rect())
		node = node.get_parent()
	_clip_last = frame.size.y
	if _clip_last < _clip_min:
		_clip_min = _clip_last
		_clip_min_tick = _screen._sim.tick()
	# **THE RECT THE DEFECT CANNOT MOVE** -- see `_button_reach`. `COLUMN_SURFACE` is a plain `Panel`,
	# so it keeps its 320 px however wide its neighbours are clamped, which is the only reason this
	# can be asked honestly from inside the process that is laying the column out wrong.
	var paint := (_screen._column as Control).get_global_rect()
	_paint_w = paint.size.x
	# A TAB STRIP'S OWN HEIGHT, MEASURED OFF A THEMED BUTTON THAT IS ALREADY ON SCREEN rather than
	# guessed. `_log_toggle` is a `Quiet` Button in this very column, so its height is what the theme
	# makes a one-row strip of buttons -- the same mistake `LOG_TOGGLE_H` was (ASSA-239: "a fifth
	# number that was a guess at how tall a themed Button is"). Named a FLOOR in the report, because a
	# tab strip may choose padding this does not have.
	#
	# **AND IT IS NO LONGER A FLOOR OFF A PROXY BUTTON: THE STRIP EXISTS, SO IT IS MEASURED.** This
	# read `_log_toggle.size.y` because there was no strip to ask; the real row of names can wrap to
	# a second line once there are five, which is exactly the number a floor would have missed.
	_tab_strip_h = _screen._tabs.names_box().size.y
	var tick: int = _screen._sim.tick()
	var now := {}
	for section in _column_sections():
		var which := String(section["name"])
		# ONLY `do` STILL HAS A HEADING OF ITS OWN. A tab's name is its heading, and the cursor
		# readout is a bare footer Label with nothing above it, so both are measured whole.
		var drawn := _drawn_height(section["controls"], which == "do")
		now[which] = drawn
		var height := float(drawn["h"])
		if not _best.has(which) or height > float((_best[which] as Dictionary)["h"]):
			_best[which] = {"h": height, "body": float(drawn["body"]),
					"head": float(drawn["head"]), "tick": tick,
					"parts": String(drawn["parts"]), "n": int(drawn["n"])}
		# **THE REACH IS ITS OWN HIGH WATER, tracked separately from the body's.** They do not peak
		# together: `make` grows a row of prose that wraps to two lines without adding a button, so
		# the tallest body and the deepest button are different ticks. Tracking one and reporting the
		# other would be the same error as adding two separate maxima together.
		var reach := _button_reach(section["top"] as Control, section["controls"], frame, paint)
		var must_fit := float(reach["must_fit"])
		if not _reach.has(which) or must_fit > float((_reach[which] as Dictionary)["must_fit"]):
			_reach[which] = {"must_fit": must_fit, "buttons": int(reach["buttons"]),
					"tick": tick}
		# **THE FOLD ITSELF, TRACKED AS ITS OWN HIGH WATER.** It does not peak with the reach: the
		# clip shrinks when a machine stalls, so a tab whose content never grew can cross the fold on
		# a tick where its own reach is unchanged. Anything above zero here is a cut control.
		var over := float(reach["over_fold"])
		var seen_over: float = float(_over_fold.get(which, -1.0))
		if over > seen_over:
			_over_fold[which] = over
			_over_tick[which] = tick
		# AND THE SAME HIGH WATER FOR THE TOP EDGE, for the reason in `_button_reach`: a control carried
		# off the top of the scroll box is as unreachable as one cut off the bottom, and watching one
		# edge of a two-edged box is the kind of green that checks nothing.
		var off_top := float(reach["off_top"])
		if off_top > float(_off_top.get(which, -1.0)):
			_off_top[which] = off_top
			_off_top_tick[which] = tick
		# **AND THE THIRD AND FOURTH EDGES, ON MAREN'S RULING THAT BOX 2 IS EITHER AXIS.** Its own
		# high water for the same reason as the other two: the widest row and the tallest list are
		# different ticks, and a horizontal overflow read only at the moment the column was tallest
		# would be a number about a coincidence.
		var off_side := maxf(float(reach["off_right"]), float(reach["off_left"]))
		if off_side > float(_off_side.get(which, -1.0)):
			_off_side[which] = off_side
			_off_side_tick[which] = tick
			_off_side_who[which] = String(reach["worst"])
		_tabs_measured[which] = int(_tabs_measured.get(which, 0)) + 1
		# ROW DENSITY AT THE TICK THE SECTION WAS TALLEST, not at its own separate peak. The lever is
		# "what does this section's worst moment cost per row", so it has to be read off that moment.
		if float(drawn["h"]) >= float((_best[which] as Dictionary)["h"]):
			var rows := _row_stats(section["controls"])
			(_best[which] as Dictionary)["rows"] = int(rows["rows"])
			(_best[which] as Dictionary)["row_tallest"] = float(rows["tallest"])
			(_best[which] as Dictionary)["row_total"] = float(rows["total"])
	# **THE ALWAYS-ON BLOCK MEASURED AS ONE THING, ON ONE TICK.** Adding the high water of `you` to the
	# high water of `do` is an upper bound on a state that may never have existed -- the two peak at
	# different moments, and a budget built from two maxima that never co-occur is pessimistic by an
	# amount nobody can name. This is the real worst block the play actually drew. The report prints
	# both and says which one the verdict used.
	# **THE ALWAYS-ON BLOCK IS `do` ALONE NOW** (Wren's ruling), so this is no longer the delicate
	# two-maxima problem the old version was careful about: one section, one reading, one tick. The
	# care is kept in the shape of the code because the block grows again the day anything rejoins it.
	if now.has("do"):
		var together: float = float((now["do"] as Dictionary)["h"])
		if together > _always_on_max:
			_always_on_max = together
			_always_on_tick = tick
	# **AND THE NEXT TAB IS OPENED LAST, so the frame after this one has it laid out.** Round-robin
	# rather than "measure all four now": a body revealed this frame has stale rects, and reading
	# those would be the blank-frame trap with a plausible number attached.
	var names: PackedStringArray = _screen._tabs.tab_names()
	if names.size() > 0:
		_tab_cycle = (_tab_cycle + 1) % names.size()
		_screen._tabs.select(names[_tab_cycle])
	if _last_pass:
		_phase = Phase.REPORT


func _report() -> void:
	print("")
	print("TAB BUDGET, seed %s, played to %s" % [_seed, _play_said])
	print("  measured     %d ticks, every one of them, with a layout pass before each reading"
			% _ticks_measured)
	print("  column       %d px tall (VIEW.y - COLUMN_TOP - 24)" % int(AssayHud.VIEW.y
			- AssayHud.COLUMN_TOP - 24.0))
	print("  clip         %d px at its WORST (tick %d), %d px at rest  <- what the scroll box leaves"
			% [int(round(_clip_min)), _clip_min_tick, int(round(_clip_last))])
	print("               the budget below uses the WORST, because that is the clip a tab has to")
	print("               survive: the `stopped` block grows above the scroll and takes it.")
	print("  separation   %d px between every child of the column" % _separation)
	print("  tab strip    %d px floor (a themed Quiet Button's own height, measured)"
			% int(round(_tab_strip_h)))
	print("")
	print("  SECTION AT ITS HIGH WATER (tallest reading of the ticks that section was open)")
	var every := ["do", "make", "inventory", "bench", "mineralogy", "cursor"]
	var missing := PackedStringArray()
	for which in every:
		if not _best.has(which):
			print("  %-10s NOT FOUND IN THE COLUMN" % which)
			missing.append(which)
			continue
		var best: Dictionary = _best[which]
		print("  %-10s %4d px  (body %4d, heading %2d)  at tick %-4d  (%d children: %s)"
				% [which, int(round(float(best["h"]))), int(round(float(best["body"]))),
				int(round(float(best["head"]))), int(best["tick"]), int(best["n"]),
				String(best["parts"])])
	if missing.size() > 0:
		_bail("sections never measured: %s" % ", ".join(missing))
		return
	print("")
	print("  TICKS EACH TAB WAS OPEN (round-robin, one tab a tick, every reading laid out)")
	var counted := PackedStringArray()
	for which in ["make", "inventory", "bench", "mineralogy"]:
		counted.append("%s %d" % [which, int(_tabs_measured.get(which, 0))])
	print("    %s" % "  ".join(counted))
	# THE TALLEST TAB IS COMPARED ON ITS `body`, because the tab strip has already said its name.
	var tallest := ""
	var tallest_h := -1.0
	for which in ["make", "inventory", "bench", "mineralogy"]:
		var h := float((_best[which] as Dictionary)["body"])
		if h > tallest_h:
			tallest_h = h
			tallest = which
	# **THE ARITHMETIC DISAGREED WITH THE MEASUREMENT AND THE ARITHMETIC WAS WRONG. CORRECTED HERE, AND
	# THE OLD LINE IS NOT KEPT, BECAUSE IT WAS A WRONG NUMBER PRINTED BESIDE A RIGHT ONE.**
	#
	# What it used to print: `budget = clip - (always_on + strip + 2 separations)`, which on the built
	# panel came out at 184 px -- next to a measured `make` reach of 334 px that the fold check says is
	# ABOVE THE FOLD on every tick of the run. Both cannot be true, and my own note here said the
	# measured one is right and this one has a term missing. It did. **The term is not missing, it is
	# SPURIOUS: `do`, the tab strip and those two separations are OUTSIDE the scroll box, and `_clip_min`
	# is the scroll box's own rect** (`_measure` intersects the clipping ancestors of `_carrying`). So the
	# clip has already had them taken out of it, and subtracting them again charged this panel 174 px
	# twice.
	#
	# **WHY IT WAS RIGHT BEFORE AND IS WRONG NOW, which is the whole lesson:** the pre-build column had
	# ONE scroll box around all six sections, so `you` and `do` were INSIDE the clip and subtracting them
	# to find what was left for the rest was correct. Wren's ruling pinned `do` outside the box. The
	# structure changed under the formula and the formula did not notice -- it is exactly the stale
	# constant this repo's `CLAUDE.md` warns about, in a tool rather than in prose.
	#
	# **SO THE BUDGET FOR ONE TAB IS THE CLIP ITSELF.** No subtraction: the box a tab's body is clipped
	# by is the room a tab's body has.
	var budget := _clip_min
	print("")
	print("  THE BUDGET FOR ONE TAB IS THE SCROLL BOX ITSELF -- no subtraction, and this line was")
	print("  WRONG until 2026-10-06: it subtracted `do` + strip + separations from a clip that")
	print("  already excludes them, charging the panel %d px twice."
			% int(round(_always_on_max + _tab_strip_h + float(_separation) * 2.0)))
	print("    outside the box   %d px -- `do` %d at tick %d, strip %d, 2 separations %d (NOT charged"
			% [int(round(_always_on_max + _tab_strip_h + float(_separation) * 2.0)),
			int(round(_always_on_max)), _always_on_tick, int(round(_tab_strip_h)), _separation * 2])
	print("                      to a tab, because the clip below is measured inside the box)")
	print("    BUDGET FOR ONE TAB   %d px  (the worst clip, tick %d)"
			% [int(round(budget)), _clip_min_tick])
	print("    TALLEST TAB  `%s` body at %d px (its heading is the tab button now)"
			% [tallest, int(round(tallest_h))])
	var slack := budget - tallest_h
	print("    (on the WHOLE BODY that is %s by %d px -- but the body is not the rule)"
			% ["inside" if slack >= 0.0 else "OVER", int(round(absf(slack)))])
	# **WREN'S RULE IS THE VERDICT, 19:40 EDT ON ASSA-198.** Not the body: *"a list of forty rocks
	# scrolling is a list; a cut Make button is a defect"*. So each candidate is judged on how far its
	# LOWEST BUTTON reaches below its own body top, and a section with no buttons cannot fail.
	# THE DENSITY LEVER, PER SECTION. Gap 3 is the only thing that moves these numbers without
	# anyone overruling anyone, so it is worth knowing which sections it actually pays off in.
	print("")
	print("  ROW DENSITY -- how much of each section is WRAP (Maren's Gap 3)")
	print("    a themed Button is %d px: that is one line carrying a control"
			% int(round(_tab_strip_h)))
	var one_line := _tab_strip_h + float(_separation)
	for which in ["inventory", "make", "bench", "mineralogy"]:
		var best: Dictionary = _best[which]
		var rows := int(best.get("rows", 0))
		if rows == 0:
			print("    %-10s no row list found" % which)
			continue
		var total := float(best.get("row_total", 0.0))
		var per := total / float(rows)
		# ARITHMETIC, NOT A MEASUREMENT, and said so: nobody has built a one-line row yet.
		var dense := float(rows) * one_line
		print("    %-10s %2d rows, %5.1f px each (tallest %d) = %d px; at one line each ~%d px"
				% [which, rows, per, int(round(float(best.get("row_tallest", 0.0)))),
				int(round(total)), int(round(dense))])
	print("    (the one-line figures are arithmetic on the yardstick, not a measured build)")
	print("")
	print("  WREN'S FOLD RULE, MEASURED ON THE BUILD: no control below the fold, ever")
	print("    `over fold` is how far a tab's LOWEST button reached past the bottom of the box that")
	print("    clips it, worst reading of every tick that tab was open. Zero is the rule kept.")
	print("    `off top` is the SAME QUESTION AT THE OTHER EDGE -- how far its HIGHEST button was")
	print("    carried above the top of that box. A control scrolled off the top is exactly as")
	print("    unreachable, and until 2026-10-06 this probe did not look at that edge at all.")
	# **AND IT CANNOT FAIL IN THIS RUN, WHICH IS A WORSE STATE THAN NOT HAVING IT.** Found by looking
	# at `05-rocks.png` on 7447cbe and noticing Mineralogy's two `go here` buttons were not in a frame
	# this probe had just called REACHABLE. They were above it, because that shot scrolls and this
	# probe never does: `AssayTabStrip.select` sets `scroll_vertical = 0` and the round-robin selects
	# a tab every tick, so every reading below is taken at the top of the box. The defect that made
	# me add this edge was real and was found in a SCROLLED state, so the number is not meaningless
	# -- it is simply not being asked.
	#
	# **AND I AM WITHDRAWING THE FIX I OWED FOR IT, HAVING THOUGHT ABOUT WHAT IT WOULD ASSERT.** My
	# first note here promised a second reading per tab with the scroll clamped to its maximum. That
	# would measure a state the rulings EXPLICITLY PERMIT: Wren's rule is that no control is below the
	# fold, and Maren's is that the list may scroll BECAUSE it holds no controls. Scroll Mineralogy's
	# 826 px of index to the bottom and `go here` is of course above the frame -- the player did that,
	# and one scroll back undoes it. The rule is about whether a control is reachable WITHOUT
	# scrolling, which is the unscrolled reading this probe already takes.
	#
	# So building it would have produced large non-zero numbers that mean nothing, under a heading
	# that says "unreachable", which is how a measurement becomes a false alarm. What this column
	# honestly is: a TRIPWIRE for a control positioned above the viewport in the DEFAULT state, which
	# cannot happen while `select` resets the scroll. Zero is the correct answer and a non-zero would
	# mean that invariant had changed. Kept, reported, and no longer cited as independent evidence.
	print("    **`off top` IS STRUCTURALLY ZERO HERE AND IS A TRIPWIRE, NOT EVIDENCE.** `select`")
	print("    resets the scroll and this probe selects a tab every tick, so every reading is taken at")
	print("    the top of the box and nothing can ever be above it. Measuring a SCROLLED state instead")
	print("    would assert a state the rulings permit -- a list may scroll because it holds no")
	print("    controls -- so zero is the right answer and a non-zero would mean that changed.")
	# **AND THE INVARIANT IT RESTS ON IS NOW A TEST** (ASSA-277, Limpet's reading). It used to rest on
	# a line in `select` that nothing checked, so this column's zero was an accident rather than a
	# promise; delete the reset and every reading here stayed 0 while the screen got worse. Now the
	# mutation reddens one named test instead of nothing.
	print("    The reset it depends on is held by")
	print("    `test_tab_strip.gd::test_selecting_a_tab_shows_you_the_top_of_it`; before ASSA-277 that")
	print("    invariant was untested, so this zero was an accident. A tripwire whose wire is checked.")
	# **BOX 2 IS READ AS EITHER AXIS** (Maren, 19:50). Both columns above are vertical, and a column
	# laid out wider than the window falls off a third edge that every instrument we owned was blind
	# to. The reference is the PAINTED panel and not the clip rect, for the reason in `_button_reach`:
	# the clip grows with the defect, the paint cannot.
	print("    `off side` is THE OTHER AXIS -- how far a tab's worst Button was drawn outside the")
	print("    PAINTED column (%d px wide, x %d..%d), left or right. On the build before 252fdb6"
			% [int(round(_paint_w)),
			int(round((_screen._column as Control).get_global_rect().position.x)),
			int(round((_screen._column as Control).get_global_rect().end.x))])
	print("    every `Make` button was drawn at x 1894..1944 -- 614 px past a 1280 px window -- and")
	print("    the two columns above both read a comfortable zero. Measured against the paint and")
	print("    not against the clip: the clip is clamped UP by the offending child, so it would grow")
	print("    exactly as fast as the overflow and the check could never fail.")
	var cut := ""
	var cut_px := 0.0
	var cut_edge := "past the bottom of the box that clips it"
	var cut_who := ""
	for which in ["make", "inventory", "bench", "mineralogy"]:
		var reach: Dictionary = _reach.get(which, {"must_fit": 0.0, "buttons": 0, "tick": 0})
		var must_fit := float(reach["must_fit"])
		var buttons := int(reach["buttons"])
		var over := float(_over_fold.get(which, 0.0))
		var off_top := float(_off_top.get(which, 0.0))
		var off_side := float(_off_side.get(which, 0.0))
		var verdict := ""
		if buttons == 0:
			verdict = "no buttons -- a list, free to scroll in its own tab"
		elif over > 0.0:
			verdict = "BELOW THE FOLD by %d px (tick %d)" % [int(round(over)),
					int(_over_tick.get(which, 0))]
		elif off_top > 0.0:
			verdict = "OFF THE TOP by %d px (tick %d)" % [int(round(off_top)),
					int(_off_top_tick.get(which, 0))]
		elif off_side > 0.0:
			verdict = "OUTSIDE THE PAINT by %d px (tick %d): %s" % [int(round(off_side)),
					int(_off_side_tick.get(which, 0)), String(_off_side_who.get(which, ""))]
		else:
			verdict = "REACHABLE"
		print("    %-9s reach %4d px, %2d buttons, over fold %3d px, off top %3d px, off side %4d px  %s"
				% [which, int(round(must_fit)), buttons, int(round(over)), int(round(off_top)),
				int(round(off_side)), verdict])
		if buttons > 0 and over > cut_px:
			cut_px = over
			cut = which
		# OFF THE TOP COUNTS AS UNREACHABLE TOO, and it is named separately in the verdict so the
		# report says which edge lost it rather than just that something did.
		if buttons > 0 and off_top > cut_px:
			cut_px = off_top
			cut = which
			cut_edge = "off the top of the box that clips it"
		# AND SO DOES OFF THE SIDE, which is the edge that actually had a defect on it today: a
		# button 614 px to the right of the window is not reachable by any amount of scrolling,
		# because the one box that scrolls has horizontal scrolling DISABLED by design.
		if buttons > 0 and off_side > cut_px:
			cut_px = off_side
			cut = which
			cut_edge = "outside the painted column"
			cut_who = String(_off_side_who.get(which, ""))
	print("")
	if cut != "":
		print("  VERDICT  A CONTROL IS UNREACHABLE. `%s` has a button %d px %s at its"
				% [cut, int(round(cut_px)), cut_edge])
		print("           worst. That is a cut control, which is the defect this item is about,")
		print("           and it is not something a list is allowed to do. Report it, say what gives.")
		if cut_who != "":
			print("           THE CONTROL IS %s -- press that one." % cut_who)
	else:
		var deepest := ""
		var deepest_px := -1.0
		for which in ["make", "inventory", "bench", "mineralogy"]:
			var reach: Dictionary = _reach.get(which, {"must_fit": 0.0, "buttons": 0})
			if int(reach["buttons"]) > 0 and float(reach["must_fit"]) > deepest_px:
				deepest_px = float(reach["must_fit"])
				deepest = which
		if deepest == "":
			print("  VERDICT  no tab has a button at all, which cannot be right -- check the probe")
		else:
			print("  VERDICT  THE PANEL KEEPS THE RULE ON BOTH AXES. Not one button of any tab, on any")
			print("           tick of this play, was drawn past the bottom or the top of the box that")
			print("           clips it, or outside the %d px of column that is actually painted."
					% int(round(_paint_w)))
			# **THE TWO HIGH WATERS ARE FROM DIFFERENT TICKS AND THIS USED TO PRINT THEM AS IF THEY
			# MET** (Limpet, on seed 19: deepest reach 358 at t513, worst clip 337 at t146 -- 21 px the
			# wrong way, inside a sentence that said the rule was kept). Per tick the verdict is true
			# and the measured columns above are what it rests on. The sentence was the part that
			# overclaimed: a reader takes "deepest reach X, worst clip Y" as a comparison, and these two
			# numbers were never observed together.
			#
			# **SO THE GAP IS NAMED AND ITS SIGN IS STATED**, rather than leaving two figures side by
			# side for the reader to subtract. Nothing couples "a machine stalled" to "the make list is
			# short", so their not meeting is luck on this seed, not a property of the panel -- which is
			# exactly why the per-tick columns stay the verdict and this stays a note.
			var unmet := _clip_min - deepest_px
			print("           Deepest reach `%s` %d px (tick %d); worst clip %d px (tick %d) -- "
					% [deepest, int(round(deepest_px)), int(_reach[deepest]["tick"]),
					int(round(_clip_min)), _clip_min_tick])
			if unmet >= 0.0:
				print("           DIFFERENT TICKS, so this is not a measurement of them meeting. Had")
				print("           they met the reach would still fit by %d px." % int(round(unmet)))
			else:
				print("           DIFFERENT TICKS, and had they met the reach would NOT have fit, by")
				print("           %d px. Nothing couples them, so this is luck on this seed and not a"
						% int(round(-unmet)))
				print("           property: hold a tab open through the worst clip before trusting it.")
	# **THE FOOTER'S COST, BECAUSE I PLACED IT AND NOBODY RULED IT.** The cursor readout is derived
	# from the TILE, not from a system, so it is not a tab; it sits last in the scrolled area, under
	# whichever tab is open. The claim I made in `main.gd` is that this costs the tab budget nothing,
	# and a claim of mine about pixels belongs in a measurement rather than in a comment.
	var cursor_h := float((_best["cursor"] as Dictionary)["h"])
	print("")
	print("  THE CURSOR FOOTER (my placement, not a ruling -- Maren judges it on the 1x shot)")
	print("    %d px at its high water, last in the scrolled area, 0 buttons." % int(round(cursor_h)))
	print("    It is BELOW every tab's content, so it cannot push a control off: what it can do is")
	print("    be scrolled to, which is what the rule permits of a readout. If it were always-on")
	print("    instead it would take %d px of the %d px budget." % [int(round(cursor_h)),
			int(round(budget))])
	# **THE CLIP AT REST BESIDE THE WORST CLIP, because one of them is the rule and the other is the
	# room.** The verdict above is judged on the worst clip the play actually drew -- a tick with a
	# machine stalled -- because "no control is EVER below the fold" is a claim about the worst
	# moment. At rest there is more room, and reporting only the generous number is how a panel
	# passes a review and cuts a button in play.
	print("")
	print("  THE CLIP, BOTH WAYS")
	print("    worst %d px (tick %d)   at rest %d px   difference %d px"
			% [int(round(_clip_min)), _clip_min_tick, int(round(_clip_last)),
			int(round(_clip_last - _clip_min))])
	print("    the difference is what the `running` and `stopped` blocks take from every tab on the")
	print("    tick a machine stalls. Maren's 17:22 ruling moved the stalled MACHINES into `bench`,")
	print("    so what is left pinned is the sim's one-line count.")
	print("")
	# **THIS LINE WAS UNCONDITIONAL AND EXIT 0 WAS TOO, OVER THIS TOOL'S OWN RED VERDICT.** Found by
	# mutation-testing the `off side` check added today: I took the footer's autowrap back out, the
	# probe correctly reported a control 688 px outside the painted column, and then printed
	# `TAB BUDGET OK` and exited 0 underneath it. **`TAB BUDGET OK` is the line I grep as my gate** —
	# it is in my own notes as the gate line — so every run of this probe since it was written has
	# been capable of passing a cut control. `window_shot.gd` learned exactly this on ASSA-149 ("the
	# green line carries the cuts") and this tool never got the lesson.
	#
	# The verdict and the last line are now one decision, and the exit code is that decision.
	if cut != "":
		print("TAB BUDGET FAIL  `%s` has a control %d px %s" % [cut, int(round(cut_px)), cut_edge])
		_finish(1)
		return
	print("TAB BUDGET OK")
	_finish(0)


func _bail(why: String) -> void:
	print("FAIL  %s" % why)
	_finish(1)


func _finish(code: int) -> void:
	_done = true
	_phase = Phase.OVER
	quit(code)
