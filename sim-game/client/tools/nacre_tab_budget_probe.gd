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
func _column_sections() -> Array:
	var out: Array = []
	if _screen._scroll == null or _screen._scroll.get_child_count() == 0:
		return out
	# TYPED EXPLICITLY, not inferred: `_screen` is a plain `Node` here, so `_screen._scroll` crosses
	# as an untyped Variant and `:=` has nothing to infer from (the parse error that caught this).
	var column: Node = _screen._scroll.get_child(0)
	var current := {}
	for child in column.get_children():
		var control := child as Control
		if control == null:
			continue
		var label := control as Label
		if label != null and label.theme_type_variation == &"Heading":
			if not current.is_empty():
				out.append(current)
			current = {"name": label.text, "controls": [control] as Array[Control]}
			continue
		if current.is_empty():
			continue
		(current["controls"] as Array[Control]).append(control)
	if not current.is_empty():
		out.append(current)
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
func _drawn_height(controls: Array) -> Dictionary:
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
		if seen == 0:
			head = control.size.y
		seen += 1
		parts.append("%d" % int(round(control.size.y)))
	# The heading plus the separation under it: what the section stops paying once a tab names it.
	var body := total - head - (float(_separation) if seen > 1 else 0.0)
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
func _button_reach(controls: Array) -> Dictionary:
	var top := INF
	var lowest := -INF
	var count := 0
	for i in range(controls.size()):
		var control := controls[i] as Control
		if control == null or not control.is_visible_in_tree():
			continue
		# INDEX 0 IS THE SECTION'S HEADING and a tab replaces it, so the reach is measured from the
		# top of the BODY. Including the heading would charge every tab one heading of height that
		# the tab strip is already paying for.
		if i > 0 and control.get_global_rect().position.y < top:
			top = control.get_global_rect().position.y
		for node in _descendants(control):
			var button := node as Button
			if button == null or not button.is_visible_in_tree():
				continue
			count += 1
			var bottom := button.get_global_rect().end.y
			if bottom > lowest:
				lowest = bottom
	if count == 0 or top == INF:
		return {"must_fit": 0.0, "buttons": 0}
	return {"must_fit": maxf(lowest - top, 0.0), "buttons": count}


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
	var column := _screen._scroll.get_child(0) as VBoxContainer
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
	# A TAB STRIP'S OWN HEIGHT, MEASURED OFF A THEMED BUTTON THAT IS ALREADY ON SCREEN rather than
	# guessed. `_log_toggle` is a `Quiet` Button in this very column, so its height is what the theme
	# makes a one-row strip of buttons -- the same mistake `LOG_TOGGLE_H` was (ASSA-239: "a fifth
	# number that was a guess at how tall a themed Button is"). Named a FLOOR in the report, because a
	# tab strip may choose padding this does not have.
	_tab_strip_h = _screen._log_toggle.size.y
	var tick: int = _screen._sim.tick()
	var now := {}
	for section in _column_sections():
		var which := String(section["name"])
		var drawn := _drawn_height(section["controls"])
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
		var reach := _button_reach(section["controls"])
		var must_fit := float(reach["must_fit"])
		if not _reach.has(which) or must_fit > float((_reach[which] as Dictionary)["must_fit"]):
			_reach[which] = {"must_fit": must_fit, "buttons": int(reach["buttons"]),
					"tick": tick}
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
	if now.has("you") and now.has("do"):
		var together: float = float((now["you"] as Dictionary)["h"]) + float(_separation) \
				+ float((now["do"] as Dictionary)["h"])
		if together > _always_on_max:
			_always_on_max = together
			_always_on_tick = tick
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
	print("  SECTION AT ITS HIGH WATER (every frame of the play, tallest reading wins)")
	var every := ["you", "do", "make", "bench", "rocks", "cursor"]
	var missing := PackedStringArray()
	for which in every:
		if not _best.has(which):
			print("  %-8s NOT FOUND IN THE COLUMN" % which)
			missing.append(which)
			continue
		var best: Dictionary = _best[which]
		print("  %-8s %4d px  (body %4d, heading %2d)  at tick %-4d  (%d children: %s)"
				% [which, int(round(float(best["h"]))), int(round(float(best["body"]))),
				int(round(float(best["head"]))), int(best["tick"]), int(best["n"]),
				String(best["parts"])])
	if missing.size() > 0:
		_bail("sections never measured: %s" % ", ".join(missing))
		return
	# THE TALLEST TAB IS COMPARED ON ITS `body`, because the tab strip has already said its name.
	var tallest := ""
	var tallest_h := -1.0
	for which in ["make", "bench", "rocks"]:
		var h := float((_best[which] as Dictionary)["body"])
		if h > tallest_h:
			tallest_h = h
			tallest = which
	# THE ARITHMETIC, SPELLED OUT, because this is the number a ruling gets made on.
	var you_h := float((_best["you"] as Dictionary)["h"])
	var do_h := float((_best["do"] as Dictionary)["h"])
	var bound := you_h + do_h + float(_separation)
	var always_on := _always_on_max
	var spent := always_on + _tab_strip_h + float(_separation) * 2.0
	var budget := _clip_min - spent
	print("")
	print("  THE SPLIT ON ASSA-198: `you` + `do` always on, one of make/bench/rocks in a tab")
	print("    always on    %d px  at tick %d -- the tallest you+do the play ACTUALLY drew"
			% [int(round(always_on)), _always_on_tick])
	print("                 (their two separate high waters add to %d px, a state that may never"
			% int(round(bound)))
	print("                  have existed; the verdict uses the %d px one that did.)"
			% int(round(always_on)))
	print("    + tab strip  %d px  + 2 separations %d px" % [int(round(_tab_strip_h)),
			_separation * 2])
	print("    = spent      %d px of the worst clip's %d px" % [int(round(spent)),
			int(round(_clip_min))])
	print("    BUDGET FOR ONE TAB   %d px" % int(round(budget)))
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
	for which in ["you", "make", "bench", "rocks"]:
		var best: Dictionary = _best[which]
		var rows := int(best.get("rows", 0))
		if rows == 0:
			print("    %-8s no row list found" % which)
			continue
		var total := float(best.get("row_total", 0.0))
		var per := total / float(rows)
		# ARITHMETIC, NOT A MEASUREMENT, and said so: nobody has built a one-line row yet.
		var dense := float(rows) * one_line
		print("    %-8s %2d rows, %5.1f px each (tallest %d) = %d px; at one line each ~%d px"
				% [which, rows, per, int(round(float(best.get("row_tallest", 0.0)))),
				int(round(total)), int(round(dense))])
	print("    (the one-line figures are arithmetic on the yardstick, not a measured build)")
	print("")
	print("  WREN'S FOLD RULE: every button above the fold; an unbounded LIST may scroll in its tab")
	var worst := ""
	var worst_reach := -1.0
	for which in ["make", "bench", "rocks", "cursor"]:
		var reach: Dictionary = _reach.get(which, {"must_fit": 0.0, "buttons": 0, "tick": 0})
		var must_fit := float(reach["must_fit"])
		var buttons := int(reach["buttons"])
		var verdict := ""
		if buttons == 0:
			verdict = "no buttons -- a list, free to scroll in its own tab"
		elif must_fit <= budget:
			verdict = "FITS, %d px spare" % int(round(budget - must_fit))
		else:
			verdict = "OVERFLOWS by %d px" % int(round(must_fit - budget))
		print("    %-8s reach %4d px, %2d buttons (tick %-4d)  %s"
				% [which, int(round(must_fit)), buttons, int(reach["tick"]), verdict])
		if buttons > 0 and must_fit > worst_reach:
			worst_reach = must_fit
			worst = which
	print("")
	if worst == "":
		print("  VERDICT  no tab has a button at all, which cannot be right -- check the probe")
	elif worst_reach <= budget:
		print("  VERDICT  TABS WORK. The deepest button of any tab is `%s` at %d px, inside the"
				% [worst, int(round(worst_reach))])
		print("           %d px budget with %d px spare. No control is below the fold."
				% [int(round(budget)), int(round(budget - worst_reach))])
	else:
		print("  VERDICT  TABS DO NOT FIX IT AS SPLIT. `%s` needs %d px of reachable button and the"
				% [worst, int(round(worst_reach))])
		print("           budget is %d px: %d px short. Wren asked to be told BEFORE building, so"
				% [int(round(budget)), int(round(worst_reach - budget))])
		print("           this is that. The tab's LAYOUT changes, not the rule.")
	# THE VARIANT MAREN HAS NOT RULED ON. `cursor` is derived from the TILE, not from the pack, so it
	# reads as a hover readout rather than as a system -- a candidate for the always-on block instead
	# of for a tab. It is the one section my ASSA-198 proposal did not place, so the cost of placing it
	# either way is measured here rather than argued later.
	# Its FULL height here, heading included: in the always-on block it keeps its own label, because
	# nothing else up there says what the line is about.
	var cursor_h := float((_best["cursor"] as Dictionary)["h"])
	var budget_with_cursor_on := budget - cursor_h - float(_separation)
	print("")
	print("  IF `cursor` JOINS THE ALWAYS-ON BLOCK (not ruled; it is derived from the tile)")
	print("    budget for one tab   %d px   tallest `%s` %d px   %s"
			% [int(round(budget_with_cursor_on)), tallest, int(round(tallest_h)),
			"fits" if tallest_h <= budget_with_cursor_on
			else "OVERFLOWS by %d px" % int(round(tallest_h - budget_with_cursor_on))])
	# **THE TWO CLIPS, BECAUSE THE VERDICT ABOVE COMMITS THE ERROR I WROTE A DOCSTRING AGAINST.**
	# `_always_on_max` is careful to use a you+do that CO-OCCURRED rather than adding two separate
	# maxima -- and then the budget subtracts it from `_clip_min`, which is a different tick (the worst
	# clip is tick 89, a stopped smelter; the tallest always-on block is tick 500, a full pack). So the
	# headline budget is still built from two maxima that may never have met. It is the right bound for
	# a rule that says a button must NEVER be cut, and it is the wrong number for "how much room is
	# there really". Both are printed so a ruling is made on a pair, not on whichever flatters me.
	var budget_at_rest := _clip_last - spent
	print("")
	print("  THE SAME SPLIT AGAINST THE CLIP AT REST, not the worst clip")
	print("    budget for one tab   %d px at rest (clip %d) vs %d px at worst (clip %d)"
			% [int(round(budget_at_rest)), int(round(_clip_last)), int(round(budget)),
			int(round(_clip_min))])
	print("    `make` reach %d px %s even at rest"
			% [int(round(worst_reach)), "fits" if worst_reach <= budget_at_rest
			else "OVERFLOWS by %d px" % int(round(worst_reach - budget_at_rest))])
	# **THE VARIANT THE BOARD'S OWN WORDS ASK FOR, AND THE ONE I RECOMMEND IF THE ABOVE FAILS.** Rainy
	# named the tabs: *"tabs such as Crafting, Inventory, Research"*. INVENTORY IS A TAB IN THE BOARD'S
	# SHAPE -- and `you` is the inventory. Maren ruled "always-on = what you carry and what you can do
	# HERE", which puts the pack always-on instead; the two readings differ and the arithmetic is what
	# decides whether that difference matters. It does: `you` alone is the biggest block up there.
	var do_only := do_h + _tab_strip_h + float(_separation)
	var budget_do_only := _clip_min - do_only
	var budget_do_only_rest := _clip_last - do_only
	print("")
	print("  IF `you` BECOMES THE INVENTORY TAB and only `do` stays always on (Rainy named Inventory")
	print("  as a tab; Maren ruled the pack always-on. This is the cost of the difference.)")
	print("    always on    %d px (`do` alone) + tab strip %d + 1 separation %d = %d px"
			% [int(round(do_h)), int(round(_tab_strip_h)), _separation, int(round(do_only))])
	print("    budget for one tab   %d px at worst, %d px at rest"
			% [int(round(budget_do_only)), int(round(budget_do_only_rest))])
	for which in ["make", "bench", "you"]:
		var r: Dictionary = _reach.get(which, {"must_fit": 0.0, "buttons": 0})
		var mf := float(r["must_fit"])
		if int(r["buttons"]) == 0:
			print("    %-8s no buttons -- free to scroll in its own tab" % which)
			continue
		print("    %-8s reach %4d px  %s at worst, %s at rest"
				% [which, int(round(mf)),
				"fits" if mf <= budget_do_only else "OVER by %d" % int(round(mf - budget_do_only)),
				"fits" if mf <= budget_do_only_rest
				else "OVER by %d" % int(round(mf - budget_do_only_rest))])
	# WHAT A DENSE ROW WOULD BUY, and it is the other half of the answer: `make` spends 500 px on 8
	# buttons, which is 62 px a button for a control the theme draws in 28. The gap is prose -- every
	# offer row repeats the material and wraps to two lines. This is not a proposal to build, it is the
	# size of the prize, so the ruling knows whether density alone can close the gap.
	var make_reach := float((_reach["make"] as Dictionary)["must_fit"])
	var make_buttons := int((_reach["make"] as Dictionary)["buttons"])
	if make_buttons > 0:
		var per := make_reach / float(make_buttons)
		var dense := float(make_buttons) * (_tab_strip_h + float(_separation))
		print("")
		print("  WHAT ROW DENSITY WOULD BUY IN `make` (its rows are two-line prose today)")
		print("    today   %d px for %d buttons = %.1f px a button (a themed Button is %d px)"
				% [int(round(make_reach)), make_buttons, per, int(round(_tab_strip_h))])
		print("    one-line rows would be about %d px, which %s the %d px at-rest budget above"
				% [int(round(dense)), "fits inside" if dense <= budget_do_only_rest else "still overflows",
				int(round(budget_do_only_rest))])
	print("")
	print("TAB BUDGET OK")
	_finish(0)


func _bail(why: String) -> void:
	print("FAIL  %s" % why)
	_finish(1)


func _finish(code: int) -> void:
	_done = true
	_phase = Phase.OVER
	quit(code)
