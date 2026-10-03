class_name AssayButtonPlay
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
## WHY FOUR HOPPERS. ASSA-37's last box wants a WILL BREAK design PLANTED, and the designed dial for
## mass is the hopper: `PART_SPECS` says of the planted frame's hopper slot "generous on purpose:
## mass is what stops you stacking hoppers, not a slot count". So the drill is built with as many
## hoppers as the frame takes, and then THE SIM'S OWN VERDICT IS REPORTED -- never asserted. Whether
## a given world's material can be made over budget depends on its density against its strength, and
## a session that claimed WILL BREAK would be this client holding an opinion about a rule.

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
var step: Step = Step.WALK_TO_MATERIAL
## Why it stopped, or "" while it is still going.
var failed := ""
var finished := false
## The sim's own verdict on the design this loop plants, read BEFORE it is planted, because that
## verdict is the promise the placement has to keep.
var planted_verdict := ""
## What the placement actually did: a machine on the map, or a design that came apart.
var outcome := ""
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
	var fuel_deposit := AssaySessionPlan.nearest_of_species(_world().deposits(), _fuel, me, rank)
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
	if not AssaySessionPlan.is_assayed(_world().species_sheets(), _material):
		_press_once("Assay", "Assay")
	var held := AssaySessionPlan.ore_held(_world().inventory_of(_me()), _material)
	if held < _ore_wanted():
		if _deposit_under_me_is_empty():
			_stop(false, ("the deposit under %s ran dry with %d of %d ore mined; this loop needs a "
					+ "richer patch") % [_my_pos(), held, _ore_wanted()])
		elif _quiet > 1200:
			_stop(false, "mined for 1200 ticks and hold %d of %d ore" % [held, _ore_wanted()])
		return
	if not AssaySessionPlan.is_assayed(_world().species_sheets(), _material):
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
	for order in PARTS:
		if String(order[0]) == "hopper":
			return int(order[1])
	return 0


## PLANT IT, AND READ WHAT HAPPENED OUT OF THE WORLD. Either a machine stands on that tile or the
## design is gone from the built list -- the sim decides which, and `outcome` says which it was.
## PLACE WAS NEVER DISABLED AND NEVER REFUSED ON THIS SIDE, whatever the verdict above says.
func _planting() -> void:
	if _world().tile_at(_drill_at).get("building") != null if _drill_at.x >= 0 else false:
		outcome = "planted: a machine stands at %s" % _drill_at
		step = Step.DONE
		return
	if _done.has("planted"):
		if _planted_design().is_empty():
			outcome = ("broke: the %s design came apart at %s and the parts came back"
					% [planted_verdict, _drill_at])
			step = Step.DONE
			return
		if _quiet > 200:
			_stop(false, "pressed Place on the drill and it is neither on the map nor gone")
		return
	var me := _my_pos()
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


## CLICK THE MAP where a tile actually is, through `_unhandled_input`. The centre of the tile, so a
## floor() of the position cannot land on its neighbour.
func _click(tile: Vector2i, button: int) -> bool:
	var cell: float = screen._cell
	if cell <= 0.0:
		return false
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = AssayHud.MARGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * cell
	screen._unhandled_input(event)
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
