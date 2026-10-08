class_name AssayDemoPlan
## CI: library
extends RefCounted
## THE DEMO LOOP AS DATA: the commands it sends and the quantities it needs, as pure functions.
##
## `lockstep_probe.gd --session` plays the whole loop now -- mine, assay, craft a smelter, light it,
## smelt, make parts, assemble, equip and plant -- against a real relay with other peers changing the
## same world. `session_plan.gd` decides WHICH deposit; this decides WHAT TO SEND. Both are here
## rather than in the probe so a test can hand them a world and check the answer, instead of a person
## reading a relay log and hoping.
##
## NOTHING HERE DECIDES A RULE, and one thing is worth saying out loud: AN ITEM IS ALWAYS ECHOED,
## NEVER INVENTED. Every command takes its item from a stack the sim named in `inventory_of` (`kind`,
## `species`, `grade` come straight back), or from `starter_pair()`. The client never works out what
## it is carrying.
##
## THE COMMAND SHAPES THEMSELVES MOVED OUT (ASSA-37) and now live in `scripts/actions.gd`, with the
## item and part-kind tags that go in them. The reason is that the client grew BUTTONS: this file was
## the only place that knew how to spell a command while the probe was the only thing that could act,
## and two spellings of one command is the single disagreement nobody would notice -- the probe would
## keep passing while a button was dropped by the relay in silence. What is left here is the demo
## loop's QUANTITIES AND GEOMETRY, which is what a plan is.
##
## THE NUMBERS BELOW ARE `sim::tuning`'s, REPEATED ONLY TO SIZE QUANTITIES AND A DEADLINE, the same
## licence `lockstep_probe.gd` already takes for `HAND_MINE_TICKS`. No outcome is decided with them:
## whether the ore arrived, whether the smelter smelted, whether a design breaks -- every one of
## those is read back out of the stepped world or taken from the sim's own verdict. If one drifts, the
## probe asks for the wrong amount of ore and fails LOUDLY on a condition that never comes true,
## which is the failure mode to want.

## 5 ore of any species makes one smelter (`RecipeId::Smelter`).
const SMELTER_ORE := 5
## `PART_SPECS` sizes, in refined material of the part's own species and grade.
const HEAD_SIZE := 1
const HANDLE_SIZE := 2
const FRAME_SIZE := 5
## Enough fuel to keep a fire going through every unit we smelt, with room to spare: fuel burns two
## ticks per point of effective reactivity, so even a weak fuel gives tens of ticks a unit. The
## reference play-throughs insert 6.
const FUEL_ORE := 6
## `RecipeId::Refine`: one ore becomes one refined, 20 ticks inside a hot enough smelter.
const SMELT_TICKS_PER_ORE := 20
## `RecipeId::Smelter`'s own craft time.
const CRAFT_TICKS := 20
## `tuning::REACH`. Used to keep a smelter spot inside it; the sim still decides.
const REACH := 3

## A pick is a handle with a head on it; a drill is a planted frame with a head on it. Both parts of
## a design are made of the SAME species and grade here, which is not a rule -- it is the simplest
## thing to script, and a mixed design is what `designs_of`'s `unassayed` list exists for.
const PICK_PARTS := ["handle", "head"]
const DRILL_PARTS := ["frame", "head"]


## HOW MUCH MATERIAL ORE THE WHOLE CHAIN NEEDS: five for the smelter, plus one ore per refined unit
## every part costs. Nothing is smelted that is not spent.
static func material_ore_needed() -> int:
	return SMELTER_ORE + refined_needed()


## HOW MUCH REFINED MATERIAL THE PARTS COST, which is also how many ore have to go through the fire.
static func refined_needed() -> int:
	return HANDLE_SIZE + HEAD_SIZE + FRAME_SIZE + HEAD_SIZE


## The size, in refined material, of one part kind. 0 for a kind the demo does not make.
static func part_size(kind: String) -> int:
	match kind:
		"head":
			return HEAD_SIZE
		"handle":
			return HANDLE_SIZE
		"frame":
			return FRAME_SIZE
		_:
			return 0


## How many of one kind, species and grade a player is carrying, out of `inventory_of`. Grade is
## optional: "" counts every grade, which is what matters when ore of two grades is the same input.
##
## THE BODY MOVED TO `AssayInventory.held` AND THIS IS NOW A FORWARD, because `main.gd` needs the
## same count and a shipped script may not reference a class under `tools/` -- the export excludes it,
## so the reference is a parse error in the bundle and nowhere else (ASSA-51). The forward stays so the
## probes keep their own vocabulary and there is still exactly one implementation.
static func held(stacks: Array, kind: String, species: int, grade: String = "") -> int:
	return AssayInventory.held(stacks, kind, species, grade)


## The one stack of a kind and species a player holds, or `{}`. Highest grade first, so a chain that
## smelted some of its ore up a grade still finds material to work with and is never handed an empty
## answer because it asked for the grade it started with.
static func best_stack(stacks: Array, kind: String, species: int) -> Dictionary:
	var best := {}
	for entry in stacks:
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) != kind or int(stack.get("species", -1)) != species:
			continue
		if best.is_empty() or _grade_rank(String(stack.get("grade", "C"))) \
				> _grade_rank(String(best.get("grade", "C"))):
			best = stack
	return best


static func _grade_rank(grade: String) -> int:
	match grade.to_upper():
		"B":
			return 1
		"A":
			return 2
		_:
			return 0


## THE TWO JOBS A SCRIPTED RUN CAN BE DOING, and they cannot be the same run (ASSA-140, the Game
## Director's ruling). The demo was doing both at once and said which only by accident:
##
##  - `JOB_SHOWCASE` is what every window shot, every board-facing picture and the milestone's demo
##    actually are. Its last beat is a machine standing on the map and mining, so it plants the
##    LARGEST part count the sim calls SAFE.
##  - `JOB_BREAK` is ASSA-37's last box, a test of the break rule. It plants the SMALLEST count the
##    sim calls WILL BREAK and the run fails if that design stood.
##
## NEITHER ASSERTS A VERDICT. Each asserts that WHAT THE SIM SAID WOULD HAPPEN DID HAPPEN, which is
## the honest version of the same test: a session claiming WILL BREAK would be this client holding an
## opinion about a rule, and a session that reports "SAFE" and then watches the thing come apart has
## found a real defect either way.
const JOB_SHOWCASE := "showcase"
const JOB_BREAK := "break"

## The sim's three verdict words, as `sim::assembly::BreakVerdict::label` spells them. Here so the
## policy below compares against one copy and a typo is a parse error rather than a run that quietly
## never matches.
const VERDICT_SAFE := "SAFE"
const VERDICT_WILL_BREAK := "WILL BREAK"


## HOW MANY HOPPERS A JOB WANTS, out of the sim's verdict for each count. -1 when this world holds no
## design that does the job, WHICH IS AN ANSWER AND NOT A FAILURE: measured over 2000 worlds through
## the same projection, 81.2% hold a SAFE drill for the starter material and only 44.9% hold a
## breaking one, because `MAX_HOPPER_SLOTS` is 4 and mass is the only dial. THE CALLER MUST SAY SO
## rather than fall back to a count that does the other job.
##
## `verdicts[n]` is the sim's word for n hoppers, so index IS the count. Mass rises with every hopper
## and the budget does not move, so SAFE can never follow WILL BREAK -- "the largest SAFE" and "the
## smallest WILL BREAK" are therefore the two ends of one ordered list, not a search.
##
## UNCERTAIN IS NEITHER JOB. The loop assays its material before it builds, so it should not appear;
## if it does, a run that planted it would be demonstrating a guess.
static func hoppers_for_job(job: String, verdicts: PackedStringArray) -> int:
	match job:
		JOB_SHOWCASE:
			for n in range(verdicts.size() - 1, -1, -1):
				if verdicts[n] == VERDICT_SAFE:
					return n
			return -1
		JOB_BREAK:
			for n in range(verdicts.size()):
				if verdicts[n] == VERDICT_WILL_BREAK:
					return n
			return -1
		_:
			return -1


## WHERE TO PUT THE SMELTER: the first 2x2 spot beside us that is in bounds, inside reach and holds
## no building. `blocked` is the tiles the SIM says already have one, so this picks between facts
## rather than predicting them -- and three peers crafting at once do not fight over one tile.
##
## Vector2i(-1, -1) when nothing fits, which the probe reports as a failure instead of placing
## somewhere the sim would refuse.
static func smelter_spot(at: Vector2i, size: Vector2i, blocked: Array) -> Vector2i:
	# Diagonals first and in a fixed order, so the answer is a pure function of the world: a smelter
	# off the corner leaves the four tiles around us walkable.
	for offset: Vector2i in [Vector2i(2, 2), Vector2i(-3, 2), Vector2i(2, -3), Vector2i(-3, -3),
			Vector2i(2, 0), Vector2i(-3, 0), Vector2i(0, 2), Vector2i(0, -3)]:
		var pos: Vector2i = at + offset
		var fits := true
		for dx: int in [0, 1]:
			for dy: int in [0, 1]:
				var tile: Vector2i = pos + Vector2i(dx, dy)
				if tile.x < 0 or tile.y < 0 or tile.x >= size.x or tile.y >= size.y:
					fits = false
				if blocked.has(tile):
					fits = false
		if fits:
			return pos
	return Vector2i(-1, -1)


## WHERE TO PUT THE DRILL, WHICH IS NOT WHERE TO PUT A SMELTER (ASSA-140). A smelter is fed by hand
## and works anywhere; a drill mines the ground under it and is stopped the moment it lands anywhere
## else. `_planting` used `smelter_spot` for both, so of the worlds where the demo's design was SAFE
## and a machine really stood, three in four read `idle: no deposit underneath` -- the loop's whole
## payoff, standing there doing nothing, with a panel naming it (Game Director's measurement).
##
## Same offsets and same clearance rule as `smelter_spot`, so a spot this returns is one the sim
## would have accepted before; the only added requirement is that the anchor tile holds ore.
## `on_deposit` is the SIM's answer per tile (`tile_at(...).deposit`), never a radius computed here:
## what a deposit covers is sim state and a client that guessed it would plant on its own arithmetic.
##
## Vector2i(-1, -1) when no reachable tile holds ore. THE CALLER MUST SAY SO RATHER THAN FALL BACK
## SILENTLY: a drill planted off ore is a demo whose last beat is a stopped machine, and that is
## worth reporting as the outcome it is.
static func drill_spot(at: Vector2i, size: Vector2i, blocked: Array,
		on_deposit: Dictionary) -> Vector2i:
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
			Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
			Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2), Vector2i(2, 2),
			Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2)]:
		var pos: Vector2i = at + offset
		if pos.x < 0 or pos.y < 0 or pos.x >= size.x or pos.y >= size.y:
			continue
		if blocked.has(pos):
			continue
		if not bool(on_deposit.get(pos, false)):
			continue
		return pos
	return Vector2i(-1, -1)


## The tiles a 2x2 building at `pos` would stand on. The probe asks the sim about each one.
static func footprint(pos: Vector2i) -> Array:
	return [pos, pos + Vector2i(1, 0), pos + Vector2i(0, 1), pos + Vector2i(1, 1)]


## WHERE THIS PEER STANDS ON THE DEPOSIT. Three peers mining one deposit is the point -- the amount
## comes down interleaved across their ticks, which is the most ordering-sensitive thing in the loop
## -- but they should not all stand on the same tile and then try to place a smelter in the same
## place. `on_deposit` is the sim's answer for each candidate (`tile_at(...).deposit`), so this never
## decides what a deposit covers.
static func stand_tile(center: Vector2i, rank: int, on_deposit: Dictionary) -> Vector2i:
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
			Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]
	var start: int = posmod(rank, offsets.size())
	for i in range(offsets.size()):
		var tile: Vector2i = center + offsets[(start + i) % offsets.size()]
		if bool(on_deposit.get(tile, false)):
			return tile
	return center


## THE WHOLE CHAIN'S TICK COST, roughly, so a run that cannot finish says so at the start instead of
## failing as a timeout twenty commands in. Deliberately generous: an underestimate turns a real
## failure into "ask for more ticks", which is the confusing way round.
static func ticks_needed(walk_to_material: int, walk_to_fuel: int, ore_per_cycle: int,
		hand_mine_ticks: int, assay_ticks: int) -> int:
	var per_cycle: int = maxi(1, ore_per_cycle)
	var mine_material := int(ceil(float(material_ore_needed()) / float(per_cycle))) * hand_mine_ticks
	var mine_fuel := int(ceil(float(FUEL_ORE) / float(per_cycle))) * hand_mine_ticks
	var smelt := refined_needed() * SMELT_TICKS_PER_ORE
	# Assaying overlaps mining, so it is not added twice; the parts, the assembly and the placement
	# are a tick each and are covered by the slack.
	var slack := 40
	return (walk_to_material + maxi(mine_material, assay_ticks) + CRAFT_TICKS + walk_to_fuel
			+ mine_fuel + smelt + slack)
