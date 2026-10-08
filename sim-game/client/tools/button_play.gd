class_name AssayButtonPlay
## CI: library
extends RefCounted
## THE WHOLE DEMO LOOP, PLAYED BY PRESSING THE SCREEN'S OWN BUTTONS AND CLICKING ITS OWN MAP.
##
## `lockstep_probe.gd --session` plays the same loop by calling `submit` directly, which proves the
## sim, the wire and lockstep. It cannot prove what ASSA-37 is about: that A PERSON AT THE WINDOW can
## do it. The difference is not cosmetic -- a command can be perfectly correct and unreachable, which
## is exactly what the client was until today.
##
## So this drives the real thing and nothing else:
##   - it finds a `Button` by its label in `main.tscn`'s own HUD and emits `pressed`, the same signal
##     a mouse would,
##   - it walks and chooses tiles by handing `_unhandled_input` real `InputEventMouseButton`s at real
##     screen positions,
##   - it reads every answer back out of the STEPPED WORLD, never out of what it just pressed.
## If a button is missing, mislabelled, built over the map or wired to the wrong command, this stops.
##
## IT DECIDES NOTHING THE SIM DECIDES. Which deposit (`AssaySessionPlan`), how much of everything
## (`AssayDemoPlan`), where a building fits (`AssayDemoPlan.smelter_spot`) -- and every verdict,
## including whether the design it plants comes apart, is read back from the sim.
##
## **TWO JOBS, TWO RUNS, AND `job` SAYS WHICH** (ASSA-140, the Game Director's ruling).
##
## This used to mount four hoppers on every world -- as many as the frame takes -- because ASSA-37's
## last box wants a WILL BREAK design PLANTED and the hopper is the designed dial for mass. The
## reason was right and the result was a coin flip in both directions: four hoppers is SAFE in 55.1%
## of worlds, so the break it exists to exercise did not happen in the majority of them, and on the
## pinned showcase seed it went the other way -- WILL BREAK, 1078 mass against a 705 budget, so the
## loop's last beat never happened at all. `button_session` printed one OK line for both.
##
## So the hopper count now comes from THE SIM'S OWN VERDICT PER COUNT, asked before anything is
## mined for (`AssaySimHost.design_if_built`), and `AssayDemoPlan.hoppers_for_job` picks the end of
## that list the job wants: the largest SAFE for `JOB_SHOWCASE`, the smallest WILL BREAK for
## `JOB_BREAK`.
##
## NOTHING HERE ASSERTS A VERDICT, which was the right half of the old reasoning and is kept: a
## session claiming WILL BREAK would be this client holding an opinion about a rule. What each run
## asserts is that **WHAT THE SIM SAID WOULD HAPPEN DID HAPPEN** -- a SAFE design that came apart,
## or a WILL BREAK design still standing, is a real defect whichever way round it is, and before
## this nothing could see either.

## Where the loop is. One step, one decision, read off the world each tick.
enum Step { WALK_TO_MATERIAL, MINING, CRAFTING, WALK_TO_FUEL, PLACING, LOADING_ORE, MINING_FUEL,
		LOADING_FUEL, SMELTING, MAKING, PICK, DRILL, PLANTING, DONE }

## Fuel ore to mine. More than `AssayDemoPlan.FUEL_ORE` because this loop smelts twice what the
## probe's does (a frame plus four hoppers), and a fire that goes out mid-stack fails as a timeout
## rather than as a sentence about fuel.
const FUEL_ORE := 12
## Every part this loop makes, and how many. Order matters only in that the frame is expensive and
## wants to be asked for while there is plenty of material.
const PARTS := [["handle", 1], ["head", 2], ["frame", 1], ["hopper", 4]]

var screen: Node
var rank := 0
## HOW MANY HOPPERS GET MOUNTED, and the only knob on this loop.
##
## -1 is the loop's own answer and the default: every hopper `PARTS` makes, which is ASSA-37's
## WILL-BREAK case and what every existing caller still gets. A caller sets this to compare DRILLS
## -- ASSA-138 asks whether a player can count 1 against 2 against 4 bars on a planted machine, and
## that comparison needs worlds that differ in nothing else.
##
## IT CHANGES WHAT IS MOUNTED, NOT WHAT IS MADE. The loop still crafts the full `PARTS` order, so
## the mining, the smelting and the fuel are the same run either way and the spare hoppers stay in
## the pack. Making fewer would move the pack, the fire and the tick count too, and then the
## pictures would differ in more than the one thing they are being compared on.
var hoppers := -1
## WHICH JOB THIS RUN IS DOING: `AssayDemoPlan.JOB_SHOWCASE` or `JOB_BREAK`.
##
## SHOWCASE IS THE DEFAULT because every window shot, every picture the board has been shown and the
## milestone's demo are showcases, and planting a design the sim has already condemned is the wrong
## advertisement. The break test is asked for by name.
##
## `hoppers` above still wins when it is set, and the two do not fight: an explicit count is
## ASSA-138's comparison, which needs worlds differing in nothing but the bar count, and this run
## then says `job` only as a label.
var job := AssayDemoPlan.JOB_SHOWCASE
## **NEVER PRESS `Assay`, so the design is read off a ROUGH sheet** (ASSA-173, `hold-assay`).
##
## The loop's own docstrings say twice that UNCERTAIN "should not appear, the loop assays its
## material" -- true of every run until this flag, and it is exactly why the design-row sheet has
## never been able to show the state every design starts in. `assembly.rs` hands UNCERTAIN to a
## design whose species is still a 25-wide band, so holding one button back reaches it with no
## fixture: the world, the walk, the mining and the parts are the ordinary showcase run.
##
## WHAT IT CHANGES, and nothing else: `_mining` neither presses `Assay` nor waits for the sheet to
## sharpen, and `_keep_the_promise` has no job promise to keep, because a run that was asked to
## guess cannot be held to what the sim would have said if it knew. It is NOT a second job: the job
## still picks the hopper count, and with every count UNCERTAIN the loop ends `no_such_design`,
## which `hoppers_for_job` already calls an answer rather than a failure.
var hold_assay := false
## The count the sim's verdicts chose for `job`, or -1 before it has been asked.
var job_hoppers := -1
## WHY THAT COUNT, in one line for the report: the job, the count, the sim's word for it, and the
## whole list it was chosen out of. Evidence that the choice was the sim's.
var job_note := ""
var step: Step = Step.WALK_TO_MATERIAL
## Why it stopped, or "" while it is still going.
var failed := ""
var finished := false
## The sim's own verdict on the design this loop plants, read BEFORE it is planted, because that
## verdict is the promise the placement has to keep.
var planted_verdict := ""
## What the placement actually did: a machine on the map, or a design that came apart.
var outcome := ""
## WHICH OUTCOME, in one word the report can branch on: "mining", "stopped", "broke" or
## "no_such_design" (this world holds no drill that does `job`, which is the world's answer and not
## a failure -- see `_resolve_hopper_count`).
## `outcome` is prose for a person; this is so `button_session` can stop printing one OK line
## for a machine that works and a design that came apart (ASSA-140). Read from the sim, never
## parsed back out of the sentence above.
var outcome_kind := ""
## True when no reachable tile held ore, so the drill had to be planted off it.
var _off_ore := false
## Every button pressed and every tile clicked, in order. The evidence that this was a person's path
## through the client and not a script's path around it.
var pressed := PackedStringArray()
var clicks := PackedStringArray()

var _material := -1
var _fuel := -1
var _stand := Vector2i.ZERO
var _fuel_stand := Vector2i.ZERO
var _smelter_at := Vector2i(-1, -1)
var _drill_at := Vector2i(-1, -1)
var _building := -1
var _done: Dictionary = {}
var _made: Dictionary = {}
var _quiet := 0
var _last_report := ""


func _init(main_screen: Node, peer_rank := 0) -> void:
	screen = main_screen
	rank = peer_rank


## ONE TICK'S WORTH OF PLAYING, called after the world has stepped. Presses at most one button, so a
## wrong world state shows up as a step that stops advancing rather than as a burst of commands.
func advance() -> void:
	if finished:
		return
	if not _world().running():
		return
	if _material < 0 and not _choose_species():
		return
	# TICKS SINCE ANYTHING HAPPENED. Reset by a step change AND by every press and click, because a
	# command only takes effect on the NEXT tick: a counter that ignored the press would call a stage
	# a timeout on the very tick it acted. That is what it did to `Take`, after 340 honest ticks of
	# waiting for a fire to go out.
	if Step.keys()[step] != _last_report:
		_last_report = Step.keys()[step]
		_quiet = 0
	else:
		_quiet += 1
	match step:
		Step.WALK_TO_MATERIAL:
			_walk_to(_stand, Step.MINING)
		Step.MINING:
			_mining()
		Step.CRAFTING:
			_crafting()
		Step.WALK_TO_FUEL:
			_walk_to(_fuel_stand, Step.PLACING)
		Step.PLACING:
			_placing()
		Step.LOADING_ORE:
			_loading_ore()
		Step.MINING_FUEL:
			_mining_fuel()
		Step.LOADING_FUEL:
			_loading_fuel()
		Step.SMELTING:
			_smelting()
		Step.MAKING:
			_making()
		Step.PICK:
			_pick()
		Step.DRILL:
			_drill()
		Step.PLANTING:
			_planting()
		Step.DONE:
			_stop(true, "")


## THE PAIR THE WORLD GUARANTEES CAN BE MINED AND SMELTED, and where to stand on each. Not a choice:
## before an assay every sheet is a 25-wide band, so choosing a fuel would be guessing and calling it
## a plan. `starter_pair` is `sim::ladder`'s answer and worldgen rerolls the roster to keep it true.
func _choose_species() -> bool:
	var pair := _world().starter_pair()
	if pair.size() < 2:
		_stop(false, "this world has no starter pair, so nothing is guaranteed smeltable")
		return false
	_material = pair[0]
	_fuel = pair[1]
	var me := _my_pos()
	var deposit := AssaySessionPlan.nearest_of_species(_world().deposits(), _material, me, rank)
	if deposit.is_empty():
		_stop(false, "no deposit of the starter material %d holds ore" % _material)
		return false
	_stand = _on_deposit(deposit)
	# THE FUEL COMES OFF THE GUARANTEED PATCH AND THE MATERIAL DOES NOT, and the asymmetry is a rule
	# rather than an oversight (ASSA-139). Grade scales REACTIVITY, so a poorer patch of the right
	# fuel is a fire too cool to melt its own ore -- 1.5% of worlds, and the loop stalls forever with
	# nothing in the sim at fault. Grade never scales HEAT TOLERANCE, so the material's own patch can
	# be any grade and still smelt, which is why that one keeps `nearest_of_species` and with it the
	# peer divergence this plan exists to create. (The material's grade does move a part's strength
	# and so the frame budget; that is ASSA-140's question, not this one.)
	var fuel_deposit := AssaySessionPlan.guaranteed_of_species(_world().deposits(), _fuel)
	if fuel_deposit.is_empty():
		fuel_deposit = AssaySessionPlan.nearest_of_species(_world().deposits(), _fuel, me, rank)
	if fuel_deposit.is_empty():
		_stop(false, "no deposit of the starter fuel %d holds ore" % _fuel)
		return false
	_fuel_stand = _on_deposit(fuel_deposit)
	return true


## A tile of a deposit this peer should stand on. The SIM says which tiles the deposit covers.
func _on_deposit(deposit: Dictionary) -> Vector2i:
	var centre: Vector2i = deposit.get("center", Vector2i.ZERO)
	var cover := {}
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var tile := centre + Vector2i(dx, dy)
			cover[tile] = _world().tile_at(tile).get("deposit") != null
	return AssayDemoPlan.stand_tile(centre, rank, cover)


## LEFT-CLICK THE MAP AND WAIT TO ARRIVE. The movement system walks one tile per tick; nothing here
## predicts a position, it reads the one the sim stepped to.
func _walk_to(tile: Vector2i, then: Step) -> void:
	if _my_pos() == tile:
		step = then
		return
	var key := "walk %s" % tile
	if _done.has(key):
		if _quiet > 240:
			_stop(false, "walked toward %s for 240 ticks and got to %s" % [tile, _my_pos()])
		return
	_done[key] = true
	if not _click(tile, MOUSE_BUTTON_LEFT):
		_stop(false, "the map would not take a left click on %s" % tile)


## MINE AND ASSAY AT ONCE, both from the `do` section. Two systems, both running every tick, so the
## ore arrives while the sheet sharpens -- and an exact sheet is what turns the design's verdict from
## a band into a number.
func _mining() -> void:
	_press_once("Mine", "Mine")
	if not hold_assay and not AssaySessionPlan.is_assayed(_world().species_sheets(), _material):
		_press_once("Assay", "Assay")
	var held := AssaySessionPlan.ore_held(_world().inventory_of(_me()), _material)
	if held < _ore_wanted():
		if _deposit_under_me_is_empty():
			_stop(false, ("the deposit under %s ran dry with %d of %d ore mined; this loop needs a "
					+ "richer patch") % [_my_pos(), held, _ore_wanted()])
		elif _quiet > 1200:
			_stop(false, "mined for 1200 ticks and hold %d of %d ore" % [held, _ore_wanted()])
		return
	# THE SECOND GATE IS THE ONE THAT MATTERS: the press above can be skipped and this would still
	# wait here for ever, because nothing else in the loop ever sharpens a sheet. `hold_assay` has
	# to be read in both places or the flag is a stall with a nicer name.
	if not hold_assay and not AssaySessionPlan.is_assayed(_world().species_sheets(), _material):
		return
	_press_once("Stop", "Stop")
	step = Step.CRAFTING


## ALL THE ORE THE CHAIN SPENDS: five for the smelter, plus one ore per refined unit every part
## costs. Read out of the sim's own catalogue, so a part growing more expensive in Rust changes this
## number rather than breaking the run twenty commands later.
func _ore_wanted() -> int:
	var refined := 0
	for order in PARTS:
		refined += _part_cost(String(order[0])) * int(order[1])
	return AssayDemoPlan.SMELTER_ORE + refined


func _part_cost(kind: String) -> int:
	for entry in AssaySimHost.part_kinds():
		var row: Dictionary = entry
		if String(row.get("name", "")) == kind:
			return int(row.get("size", 0))
	return 0


## PRESSED ONCE, AND THE REASON IS A SIM RULE I LEARNED BY BREAKING IT. A second `Craft` while one is
## in progress REFUNDS the batch and starts over (`sim::step`), so a loop that pressed every tick
## reset the progress bar forever: the ore came back and went again, the pack read the same number for
## sixty ticks, and no smelter ever appeared. Every stage below that submits a command presses once
## and then waits for the stepped world to show it happened.
func _crafting() -> void:
	if _held("smelter", _material) > 0:
		step = Step.WALK_TO_FUEL if _fuel != _material else Step.PLACING
		return
	_press_on_offer_once("craft smelter", "craft", "Smelter", _material)
	if _quiet > 200:
		_stop(false, "pressed Craft smelter and no smelter arrived in 200 ticks")


## RIGHT-CLICK A FREE 2x2, THEN PRESS PLACE. Two separate acts on purpose: the tile is chosen on the
## map and the verb is pressed in the panel, which is the rule the whole client follows now.
func _placing() -> void:
	if _building >= 0:
		step = Step.LOADING_ORE
		return
	var building: Variant = _world().tile_at(_smelter_at).get("building") \
			if _smelter_at.x >= 0 else null
	if building != null:
		_building = int((building as Dictionary).get("id", -1))
		step = Step.LOADING_ORE
		return
	if _done.has("place smelter"):
		if _quiet > 120:
			_stop(false, "pressed Place for the smelter at %s and nothing stands there"
					% _smelter_at)
		return
	var me := _my_pos()
	_smelter_at = AssayDemoPlan.smelter_spot(me, _world().size_tiles(), _buildings_near(me))
	if _smelter_at.x < 0:
		_stop(false, "no free 2x2 within reach of %s for a smelter" % me)
		return
	if not _click(_smelter_at, MOUSE_BUTTON_RIGHT):
		_stop(false, "the map would not take a right click on %s" % _smelter_at)
		return
	_done["place smelter"] = true
	if not _press_on_stack("smelter", _material, "Place"):
		_stop(false, "no Place button on the smelter in the pack")


## THE MATERIAL ORE GOES IN FIRST, WHICH IS NOT THE PROBE'S ORDER, AND THE REASON IS A BUTTON.
##
## `Smelt` and `Fuel` each put in the WHOLE stack, because a button cannot ask for a quantity without
## growing a field and picking a smaller number for the player would be this client deciding how much
## fuel a fire wants. When the starter material and the starter fuel are THE SAME SPECIES -- which
## nothing in the sim forbids -- that is one stack, so inserting fuel first would leave nothing to
## refine. Loading the ore first only costs a stalled fire until the fuel lands, which is slower and
## not wrong, and it works whether the two species are the same or not.
func _loading_ore() -> void:
	if _smelter_holds_input():
		step = Step.MINING_FUEL
		return
	_press_on_stack_once("ore in", "ore", _material, "Smelt")
	if _quiet > 200:
		_stop(false, "pressed Smelt on the ore and the smelter's input slot is still empty")


func _mining_fuel() -> void:
	if _fuel != _material and _my_pos() != _fuel_stand:
		_walk_to(_fuel_stand, Step.MINING_FUEL)
		return
	_press_once("Mine fuel", "Mine")
	var held := AssaySessionPlan.ore_held(_world().inventory_of(_me()), _fuel)
	if held < FUEL_ORE:
		if _quiet > 1200:
			_stop(false, "mined fuel for 1200 ticks and hold %d of %d" % [held, FUEL_ORE])
		return
	_press_once("Stop mining fuel", "Stop")
	step = Step.LOADING_FUEL


func _loading_fuel() -> void:
	_press_on_stack_once("fuel in", "ore", _fuel, "Fuel")
	step = Step.SMELTING


## WAIT FOR THE FIRE TO GO OUT, THEN TAKE. The smelter's OWN SENTENCE says when it is done
## (`sim::debug::building_status`), so this counts nothing of its own; if that wording ever changes
## this stage times out with the status printed beside the failure.
func _smelting() -> void:
	if _held("refined", _material) >= _ore_wanted() - AssayDemoPlan.SMELTER_ORE:
		step = Step.MAKING
		return
	if not _smelter_is_idle():
		if _quiet > 2000:
			_stop(false, "the smelter has been busy for 2000 ticks: %s" % _smelter_status())
		return
	# Right-click the smelter so Take acts on it, then press Take in the `do` section.
	if not _done.has("target smelter"):
		_done["target smelter"] = true
		if not _click(_smelter_at, MOUSE_BUTTON_RIGHT):
			_stop(false, "the map would not take a right click on the smelter at %s" % _smelter_at)
			return
	_press_once("take", "Take")
	if _held("refined", _material) < 1 and _quiet > 200:
		_stop(false, "took from the smelter and hold no refined material: %s" % _smelter_status())


## ONE `Make` PRESS PER PART, from the refined row. Each press is one part, so this is a person
## pressing a button four times and not a command with a count field.
func _making() -> void:
	for order in PARTS:
		var kind := String(order[0])
		var want := int(order[1])
		if _held(kind, _material) >= want:
			continue
		var asked := int(_made.get(kind, 0))
		if asked > _held(kind, _material) + 2:
			_stop(false, "asked for %d %s and hold %d" % [asked, kind, _held(kind, _material)])
			return
		if asked >= want:
			return  # waiting for the ones already asked for
		if not _press_on_offer("make", AssayActions.part_kind_tag(kind), _material):
			_stop(false, "no `Make %s` row in the crafting menu for this material" % kind)
			return
		_made[kind] = asked + 1
		return
	step = Step.PICK


## A PICK, AND THE ONE THING ONLY A HELD DESIGN CAN DO: `Equip`. Chosen part by part from the pack --
## the first press is the FRAME, which is why the button's own label changes to `Mount` after it.
func _pick() -> void:
	for entry in _world().designs_of(_me()):
		if bool((entry as Dictionary).get("in_hand", false)):
			step = Step.DRILL
			return
	if _done.has("assembled pick"):
		for i in range(_world().designs_of(_me()).size()):
			var design: Dictionary = _world().designs_of(_me())[i]
			if String(design.get("mount", "")) == "held":
				if _press_on_design(i, "Equip"):
					return
		if _quiet > 200:
			_stop(false, "assembled a pick and no held design appeared to equip")
		return
	if not _done.has("pick frame"):
		if not _press_on_stack("handle", _material, "Frame"):
			_stop(false, "no `Frame` button on the handle")
			return
		_done["pick frame"] = true
		return
	if not _done.has("pick head"):
		if not _press_on_stack("head", _material, "Mount"):
			_stop(false, "no `Mount` button on a head after choosing a frame")
			return
		_done["pick head"] = true
		return
	if not _press("Assemble"):
		_stop(false, "no Assemble button after choosing a frame and a head")
		return
	_done["assembled pick"] = true


## THE DRILL: a planted frame, its one head, and every hopper the frame will take. Its verdict is the
## sim's and it is read before anything is planted.
func _drill() -> void:
	if hoppers < 0 and job_hoppers < 0 and not _resolve_hopper_count():
		return
	var planted := _planted_design()
	if not planted.is_empty():
		planted_verdict = String(planted.get("verdict", "?"))
		step = Step.PLANTING
		return
	if _done.has("assembled drill"):
		if _quiet > 200:
			_stop(false, "assembled a drill and no planted design appeared")
		return
	if not _done.has("drill frame"):
		if not _press_on_stack("frame", _material, "Frame"):
			_stop(false, "no `Frame` button on the planted frame")
			return
		_done["drill frame"] = true
		return
	if not _done.has("drill head"):
		if not _press_on_stack("head", _material, "Mount"):
			_stop(false, "no `Mount` button on a head for the drill")
			return
		_done["drill head"] = true
		return
	var mounted := int(_done.get("hoppers", 0))
	if mounted < _hoppers_wanted():
		if not _press_on_stack("hopper", _material, "Mount"):
			_stop(false, "no `Mount` button on a hopper")
			return
		_done["hoppers"] = mounted + 1
		return
	if not _press("Assemble"):
		_stop(false, "no Assemble button after choosing the drill's parts")
		return
	_done["assembled drill"] = true


func _hoppers_wanted() -> int:
	if hoppers >= 0:
		return hoppers
	return job_hoppers


## **ASK THE SIM WHICH DRILL THIS WORLD CARRIES**, once, before the first part is chosen.
##
## The grade is the one the `Frame` press is about to act on (`best_stack` is highest grade first, so
## it is the same stack), and THE FRAME'S GRADE IS THE WHOLE ANSWER: mass is size times density and
## density never scales with grade, while only a frame row contributes budget. So a head or hopper
## that came out of the fire a grade lower weighs and carries exactly what this asked about. Pinned
## in Rust (`only_the_frames_grade_moves_a_single_species_drill`) rather than assumed here.
##
## THE UPPER BOUND IS WHAT THIS LOOP MADE, not `MAX_HOPPER_SLOTS` retyped: if the two ever disagree
## the sim refuses the ask and says so in its own phrase, which is the failure to want. `PARTS` is
## still what gets made, so the mining, the smelting and the tick count do not move with the job --
## the spare hoppers stay in the pack, the same licence an explicit `hoppers` takes.
##
## False and stopped on any failure, so the caller returns without pressing.
func _resolve_hopper_count() -> bool:
	var frame_stack := AssayDemoPlan.best_stack(_world().inventory_of(_me()), "frame", _material)
	if frame_stack.is_empty():
		_stop(false, "no frame in the pack to size the drill against")
		return false
	if not frame_stack.has("grade"):
		_stop(false, "the pack's frame stack has no `grade`: %s" % frame_stack)
		return false
	var grade: String = String(frame_stack["grade"])
	var made: int = _held("hopper", _material)
	var verdicts := PackedStringArray()
	for n in range(made + 1):
		var mounted := PackedStringArray(["head"])
		for _i in range(n):
			mounted.append("hopper")
		var facts: Dictionary = _world().design_if_built("frame", mounted, _material, grade)
		# ASSERT THE KEY, NEVER DEFAULT IT (ASSA-141). A missing `verdict` read as "" would match no
		# job and this run would report "no such design" about a world that had one.
		for key in ["verdict", "fault"]:
			if not facts.has(key):
				_stop(false, "the sim's answer for %d hoppers has no `%s`: %s" % [n, key, facts])
				return false
		var fault: String = String(facts["fault"])
		if fault != "":
			_stop(false, ("the sim refuses a drill with %d hoppers, which this loop made %d of: %s"
					% [n, made, fault]))
			return false
		verdicts.append(String(facts["verdict"]))
	var want: int = AssayDemoPlan.hoppers_for_job(job, verdicts)
	job_note = "job `%s`: %d of %d hoppers · the sim says %s" % [job, want, made, verdicts]
	if want < 0:
		# AN ANSWER, NOT A FAILURE, and the loop stops here rather than planting the other job's
		# design: 18.8% of worlds hold no SAFE drill for the starter material and 55.1% hold no
		# breaking one. The run is still a successful pass through every button; what it has is no
		# subject, and `button_session` names that outcome instead of printing a bare OK.
		outcome_kind = "no_such_design"
		outcome = ("no drill in this world does the `%s` job · the sim says %s for 0..%d hoppers"
				% [job, verdicts, made])
		step = Step.DONE
		return false
	job_hoppers = want
	return true


## PLANT IT, AND READ WHAT HAPPENED OUT OF THE WORLD. Either a machine stands on that tile or the
## design is gone from the built list -- the sim decides which, and `outcome` says which it was.
## PLACE WAS NEVER DISABLED AND NEVER REFUSED ON THIS SIDE, whatever the verdict above says.
func _planting() -> void:
	if _world().tile_at(_drill_at).get("building") != null if _drill_at.x >= 0 else false:
		# WHETHER IT IS WORKING IS THE SIM'S WORD, not "a building exists here" (ASSA-140). A machine
		# that stands and does nothing was reported as a success for weeks, and `button_session`
		# printed the same OK line for that as for a design that came apart.
		var status := _planted_status()
		outcome_kind = "stopped" if _planted_is_stopped() else "mining"
		outcome = ("planted: a machine stands at %s and the sim says: %s"
				% [_drill_at, status if status != "" else "nothing"])
		step = Step.DONE
		_keep_the_promise()
		return
	if _done.has("planted"):
		if _planted_design().is_empty():
			outcome_kind = "broke"
			outcome = ("broke: the %s design came apart at %s and the parts came back"
					% [planted_verdict, _drill_at])
			step = Step.DONE
			_keep_the_promise()
			return
		if _quiet > 200:
			_stop(false, "pressed Place on the drill and it is neither on the map nor gone")
		return
	var me := _my_pos()
	# A DRILL GOES ON ORE AND A SMELTER DOES NOT (ASSA-140). This used `smelter_spot`, so the demo's
	# own payoff landed off the deposit in three worlds out of four and was stopped on arrival with
	# `idle: no deposit underneath`. The fallback is kept so the loop still reaches an end on a world
	# with no reachable ore, but `_off_ore` records that it happened and the outcome says so: a
	# stopped machine is a different result from a working one and must not read as the same.
	_drill_at = AssayDemoPlan.drill_spot(me, _world().size_tiles(), _buildings_near(me),
			_ore_under(me))
	_off_ore = _drill_at.x < 0
	if _off_ore:
		_drill_at = AssayDemoPlan.smelter_spot(me, _world().size_tiles(), _buildings_near(me))
	if _drill_at.x < 0:
		_stop(false, "no free tile within reach of %s to plant a drill on" % me)
		return
	if not _click(_drill_at, MOUSE_BUTTON_RIGHT):
		_stop(false, "the map would not take a right click on %s" % _drill_at)
		return
	var designs := _world().designs_of(_me())
	for i in range(designs.size()):
		if String((designs[i] as Dictionary).get("mount", "")) != "planted":
			continue
		if not _press_on_design(i, "Place"):
			_stop(false, "NO PLACE BUTTON ON A PLANTED DESIGN, whose verdict is %s. Place must "
					+ "never be hidden or disabled (Maren's ruling, ASSA-5/7)." % planted_verdict)
			return
		_done["planted"] = true
		return
	_stop(false, "nothing planted to place")


## **WHAT THE SIM SAID WOULD HAPPEN HAD BETTER HAVE HAPPENED.** The only assertion either run makes
## about a break (ASSA-140), and the reason the two-runs split is honest rather than this client
## grading a rule: the verdict was read off the design BEFORE the press, so the placement has a
## promise to keep and nothing here decides what the promise should have been.
##
## SAFE that comes apart and WILL BREAK that stands are both real defects, in the sim or in the
## projection the run sized itself with, and before this nothing could see either -- `button_session`
## printed one OK line for every ending. UNCERTAIN promises nothing and is left alone; the loop
## assays its material, so it should not appear.
##
## AND THE JOB'S OWN PROMISE, which is the half Wren's bar is about: a showcase run's last beat is a
## machine MINING, not one standing idle. `_off_ore` is excused because the world, not the run, chose
## that -- no reachable tile held ore -- and the outcome already says so. An explicit `hoppers` is
## excused too: that caller asked for a count, not for a job.
func _keep_the_promise() -> void:
	if planted_verdict == AssayDemoPlan.VERDICT_SAFE and outcome_kind == "broke":
		_stop(false, ("THE SIM SAID SAFE AND THE DESIGN CAME APART at %s · %s"
				% [_drill_at, job_note]))
		return
	if planted_verdict == AssayDemoPlan.VERDICT_WILL_BREAK and outcome_kind != "broke":
		_stop(false, ("THE SIM SAID WILL BREAK AND THE MACHINE IS STANDING at %s · %s · %s"
				% [_drill_at, job_note, outcome]))
		return
	if hoppers >= 0:
		return
	# A RUN ASKED TO GUESS CANNOT BE HELD TO WHAT THE SIM WOULD HAVE SAID IF IT KNEW (ASSA-173).
	# With a rough sheet every count is UNCERTAIN, so there is no SAFE drill to plant and no job to
	# keep -- the two checks below would fail every `hold-assay` run on the one thing it was asked
	# to do. The two promises ABOVE still bind: a verdict read before the press is still a promise,
	# whatever sharpened the sheet.
	if hold_assay:
		return
	if job == AssayDemoPlan.JOB_SHOWCASE and outcome_kind != "mining" and not _off_ore:
		_stop(false, ("A SHOWCASE RUN MUST END WITH A MACHINE MINING and this one did not · %s · %s"
				% [job_note, outcome]))
		return
	if job == AssayDemoPlan.JOB_BREAK and outcome_kind != "broke":
		_stop(false, ("A BREAK RUN MUST END WITH THE DESIGN COMING APART and this one did "
				+ "not · %s · %s") % [job_note, outcome])


func _planted_design() -> Dictionary:
	for entry in _world().designs_of(_me()):
		var design: Dictionary = entry
		if String(design.get("mount", "")) == "planted" and not bool(design.get("in_hand", false)):
			return design
	return {}


# ---------------------------------------------------------------------------------------------
# PRESSING AND CLICKING. Nothing below reaches past the screen's own widgets and input handler.
# ---------------------------------------------------------------------------------------------


## PRESS A BUTTON BY ITS LABEL, anywhere in the HUD. `pressed.emit()` is the same signal a mouse
## click raises, so the handler under test is the handler a player gets.
func _press(label: String) -> bool:
	var button := _find_button(screen, label)
	if button == null:
		return false
	pressed.append("%s @%d" % [label, _world().tick()])
	_quiet = 0
	button.pressed.emit()
	return true


## Press a button on the PACK ROW of one item, found by the sim's own name for that item. A row is
## the stack it describes, so this cannot press Place on the wrong thing.
func _press_on_stack(kind: String, species: int, label: String) -> bool:
	var stack := AssayDemoPlan.best_stack(_world().inventory_of(_me()), kind, species)
	if stack.is_empty():
		return false
	var wanted := AssayHud.stack_line(stack)
	for row in screen._carrying.get_children():
		# BY NAME, NOT BY POSITION, and the name is READ FROM `main.gd` rather than retyped here.
		# A pack row is [icon?][VBox: sentence, verbs] since ASSA-46 (#81), so child 0 is a
		# TextureRect on a row with art and a VBoxContainer on one without. This read
		# `get_child(0) as Label`, matched nothing on any row, and every press on a pack row failed
		# silently -- the whole loop stopped at `Craft smelter` (ASSA-62). `tests/test_buttons.gd`
		# was fixed in the same PR and this copy was not, which is exactly why the suite could not
		# see it: that file has its own row finder, so the two can disagree.
		var line: Label = row.find_child(screen.STACK_LINE, true, false) as Label
		if line == null or line.text != wanted:
			continue
		var button := _find_button(row, label)
		if button == null:
			return false
		pressed.append("%s on `%s` @%d" % [label, wanted, _world().tick()])
		_quiet = 0
		button.pressed.emit()
		return true
	return false


## PRESS A ROW OF THE CRAFTING MENU, found by what the SIM says it makes (ASSA-86/88).
##
## The make-verbs left the pack rows, so this is where `Craft smelter` and `Make head` are pressed
## now -- and a menu row is found by its SENTENCE rather than by a button label, because every
## button in that menu says the same word on purpose: the bug Maren measured was two buttons both
## labelled exactly `Craft smelter` making smelters with different walls.
##
## `verb` and `tag` are the sim's own (`make_offers`), so this matches the catalogue row rather than
## any text: `("craft", "Smelter")` or `("make", "Head")`. The species is the input stack's, which is
## what makes "the smelter I asked for is made of MY material" a thing this tool can assert.
func _press_on_offer(verb: String, tag: Variant, species: int) -> bool:
	var offers: Array = _world().make_offers(_me())
	for i in range(offers.size()):
		var offer: Dictionary = offers[i]
		if String(offer.get("verb", "")) != verb:
			continue
		if JSON.stringify(offer.get("tag")) != JSON.stringify(tag):
			continue
		if int(offer.get("species", -1)) != species:
			continue
		if i >= screen._make.get_child_count():
			return false
		var row: Node = screen._make.get_child(i)
		var button := _find_button(row, AssayHud.make_button_text())
		if button == null:
			return false
		pressed.append("%s on `%s` @%d" % [AssayHud.make_button_text(),
				String(offer.get("line", "?")), _world().tick()])
		_quiet = 0
		button.pressed.emit()
		return true
	return false


## Once, by key, like `_press_on_stack_once` -- and it reports the menu it was looking at, because a
## row that is not there is the sim saying you cannot make that from what you carry.
func _press_on_offer_once(key: String, verb: String, tag: Variant, species: int) -> void:
	if _done.has(key):
		return
	if _press_on_offer(verb, tag, species):
		_done[key] = true
		return
	if _quiet > 60:
		_stop(false, "no `%s %s` row in the crafting menu after 60 ticks of looking"
				% [verb, JSON.stringify(tag)])


## Press a button on the bench's Nth row. The ROW INDEX, because that is what a player clicks; the
## design's own `index` is what the command carries and `main.gd` is the one that maps between them.
func _press_on_design(row_index: int, label: String) -> bool:
	if row_index < 0 or row_index >= screen._bench.get_child_count():
		return false
	var button := _find_button(screen._bench.get_child(row_index), label)
	if button == null:
		return false
	pressed.append("%s on bench row %d @%d" % [label, row_index, _world().tick()])
	_quiet = 0
	button.pressed.emit()
	return true


## The same one-shot rule for a button on a pack row. A stage that has already pressed is waiting,
## not idle, so pressing again is never the right answer.
func _press_on_stack_once(key: String, kind: String, species: int, label: String) -> void:
	if _done.has(key):
		return
	if _press_on_stack(kind, species, label):
		_done[key] = true
		return
	if _quiet > 60:
		_stop(false, "no `%s` button on a %s row after 60 ticks of looking" % [label, kind])


func _press_once(key: String, label: String) -> void:
	if _done.has(key):
		return
	if _press(label):
		_done[key] = true
		return
	_stop(false, "no `%s` button on the screen" % label)


## CLICK THE WORLD where a tile actually is, through `_unhandled_input`. The centre of the tile, so a
## floor() of the position cannot land on its neighbour.
##
## THE SCREEN SAYS WHERE THAT IS, not this file (`point_of_tile`). There are two views of the world
## since ASSA-119 and they put a tile in different places; a loop that pressed the schematic's
## coordinates while the close-up was up would walk somewhere else and report the sim had refused.
func _click(tile: Vector2i, button: int) -> bool:
	if screen._cell <= 0.0:
		return false
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	# AND FROM WHICHEVER VIEW SHOWS IT. A tile 26 away is off the close-up's 28x18 window, which is
	# why the schematic exists; see the longer note on `tests/test_buttons.gd::_click`.
	var was: bool = screen._close_up
	if was and not AssayHud.world_rect().has_point(screen.point_of_tile(tile)):
		screen._show_close_up(false)
	event.position = screen.point_of_tile(tile)
	screen._unhandled_input(event)
	if was != screen._close_up:
		screen._show_close_up(was)
	clicks.append("%s %s @%d" % ["right" if button == MOUSE_BUTTON_RIGHT else "left", tile,
			_world().tick()])
	_quiet = 0
	return true


func _find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == label:
			return child
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------------------------
# READING THE WORLD. Every answer here is the sim's.
# ---------------------------------------------------------------------------------------------


## THE WORLD, TYPED. `screen` is a plain `Node` to this file, so every read through it comes back as
## a Variant and `:=` cannot infer a thing -- which is a parse error, and Godot exits 0 on those.
func _world() -> AssaySimHost:
	return screen._sim


func _me() -> int:
	return int(screen._client.player_id)


func _my_pos() -> Vector2i:
	for entry in _world().players():
		var player: Dictionary = entry
		if int(player.get("id", -1)) == _me():
			return player.get("pos", Vector2i.ZERO) as Vector2i
	return _world().spawn_tile()


func _held(kind: String, species: int) -> int:
	return AssayDemoPlan.held(_world().inventory_of(_me()), kind, species)


func _deposit_under_me_is_empty() -> bool:
	var deposit: Variant = _world().tile_at(_my_pos()).get("deposit")
	if deposit == null:
		return true
	return int((deposit as Dictionary).get("amount", 0)) <= 0


func _smelter_status() -> String:
	var building: Variant = _world().tile_at(_smelter_at).get("building")
	return "" if building == null else String((building as Dictionary).get("status", ""))


func _smelter_is_idle() -> bool:
	return _smelter_status().contains("idle: nothing to refine")


func _smelter_holds_input() -> bool:
	var status := _smelter_status()
	return status != "" and not status.contains("idle: nothing to refine")


## THE SIM'S OWN WORD ON THE PLANTED MACHINE, the same `status` string the HUD shows.
func _planted_status() -> String:
	var building: Variant = _world().tile_at(_drill_at).get("building")
	return "" if building == null else String((building as Dictionary).get("status", ""))


## HAS THE PLANTED MACHINE STOPPED — the SIM's bool (`building_state(b).halted()`), not a guess at
## the shape of its status sentence. I wrote `status.begins_with("mining")` first and it called every
## working drill stopped, because the sentence reads `holding 0 of 210 · mining Minyte · …`. A client
## that branches on prose is deriving a rule from a rendering; `stopped` is the fact.
##
## No default: a dict with no `stopped` key is a stale dylib and says so (Maren's ASSA-141 ruling).
func _planted_is_stopped() -> bool:
	var building: Variant = _world().tile_at(_drill_at).get("building")
	if building == null:
		return true
	var facts: Dictionary = building
	assert(facts.has("stopped"),
		"the building dict carries no `stopped` key: rebuild libsim_godot (`make client-lib`)")
	return bool(facts["stopped"])


## WHICH TILES NEAR `at` HOLD ORE, as the sim reports them. The same shape `stand_tile` takes,
## and for the same reason: what a deposit covers is sim state, not a radius computed here.
func _ore_under(at: Vector2i) -> Dictionary:
	var cover := {}
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var tile := at + Vector2i(dx, dy)
			var deposit: Variant = _world().tile_at(tile).get("deposit")
			cover[tile] = deposit != null and int((deposit as Dictionary).get("amount", 0)) > 0
	return cover


func _buildings_near(at: Vector2i) -> Array:
	var taken := []
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var tile := at + Vector2i(dx, dy)
			if _world().tile_at(tile).get("building") != null:
				taken.append(tile)
	return taken


func _stop(ok: bool, why: String) -> void:
	finished = true
	step = Step.DONE
	if not ok:
		failed = why
