extends RefCounted
## THE DEMO LOOP'S PLAN, AS TESTS. `AssayDemoPlan` is what `lockstep_probe.gd --session` sends and how
## much of everything it needs; this checks the parts of that which can be wrong without a relay.
##
## The one thing NOT checked here is the most important: that the item dictionaries below are the
## shape serde reads. That needs the sim, so it lives in `test_sim_binding.gd`, where the same
## dictionaries are held against `AssaySim.item_json` -- serde writing them itself. A test of these
## shapes written from my own reading of the protocol would agree with my own misreading of it, which
## is exactly how I got the bundle tick convention backwards on 2026-10-01.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## A stack as `inventory_of` hands one over.
func _stack(kind: String, species: int, grade: String, count: int) -> Dictionary:
	return {"kind": kind, "species": species, "species_name": "korvite", "grade": grade,
			"count": count, "name": "%s:korvite:%s" % [kind, grade.to_lower()]}


## WHAT THE LOOP NEEDS TO MINE IS WHAT IT SPENDS, and nothing is smelted that is not spent. If these
## drift the probe asks for the wrong amount of ore and then waits for a condition that never comes
## true, which is a confusing way to read a real failure.
func test_the_ore_it_mines_is_the_ore_it_spends() -> bool:
	var parts := AssayDemoPlan.part_size("handle") + AssayDemoPlan.part_size("head") \
			+ AssayDemoPlan.part_size("frame") + AssayDemoPlan.part_size("head")
	if AssayDemoPlan.refined_needed() != parts:
		return _fail("the loop smelts %d refined and the four parts cost %d"
				% [AssayDemoPlan.refined_needed(), parts])
	if AssayDemoPlan.material_ore_needed() != AssayDemoPlan.SMELTER_ORE + parts:
		return _fail("mines %d ore for a %d-ore smelter plus %d refined"
				% [AssayDemoPlan.material_ore_needed(), AssayDemoPlan.SMELTER_ORE, parts])
	if AssayDemoPlan.part_size("gear") != 0:
		return _fail("a kind the loop does not make should cost 0, not a guess")
	return true


## AN ITEM IS ECHOED, NEVER INVENTED: the kind, species and grade come straight back out of the stack
## the sim described. A client that re-derived any of them would eventually name an item it is not
## carrying, and the command would be refused for the wrong reason.
func test_an_item_is_echoed_out_of_the_stack_the_sim_named() -> bool:
	var stack := _stack("refined", 4, "B", 9)
	var item := AssayDemoPlan.item_of_stack(stack)
	if item != AssayDemoPlan.item("refined", 4, "B"):
		return _fail("a stack of refined became %s" % [item])
	if int(item["species"]) != 4 or String(item["grade"]) != "B":
		return _fail("the species or grade did not survive: %s" % [item])
	# A lower-case grade off the wire is still a grade; serde spells them upper.
	if AssayDemoPlan.item("ore", 1, "c") != AssayDemoPlan.item("ore", 1, "C"):
		return _fail("grade case changed the item")
	# An unknown kind is passed through UNCHANGED rather than guessed at, so the sim refuses it by
	# name instead of the client quietly turning it into some other item.
	if AssayDemoPlan.item("widget", 1, "C")["kind"] != "widget":
		return _fail("an unknown kind was guessed at: %s" % [AssayDemoPlan.item("widget", 1, "C")])
	return true


## ONE SOURCE FOR WHAT A HANDLE IS. `MakePart` names a PART kind and `Assemble` names an ITEM, so the
## same thing is spelled two ways on the wire -- and if they ever disagree, a client would make a
## handle and then assemble something that is not one.
func test_a_part_item_and_a_part_kind_agree_about_what_a_handle_is() -> bool:
	for kind in ["head", "handle", "frame", "hopper"]:
		var item: Variant = AssayDemoPlan.item(kind, 2, "C")["kind"]
		if typeof(item) != TYPE_DICTIONARY or not (item as Dictionary).has("Part"):
			return _fail("a %s item is not tagged as a part: %s" % [kind, item])
		if (item as Dictionary)["Part"] != AssayDemoPlan.part_kind_tag(kind):
			return _fail("a %s item says %s and MakePart says %s"
					% [kind, (item as Dictionary)["Part"], AssayDemoPlan.part_kind_tag(kind)])
	# A handle and a frame are ONE kind with two mounts, which is the catalogue's design.
	if AssayDemoPlan.part_kind_tag("handle") == AssayDemoPlan.part_kind_tag("frame"):
		return _fail("a handle and a planted frame must not be the same tag")
	return true


func test_counting_what_we_hold_filters_on_all_three_fields() -> bool:
	var stacks := [_stack("ore", 1, "C", 5), _stack("ore", 1, "B", 2), _stack("ore", 2, "C", 7),
			_stack("refined", 1, "C", 3)]
	if AssayDemoPlan.held(stacks, "ore", 1) != 7:
		return _fail("ore of species 1 at any grade is 5 + 2, got %d"
				% AssayDemoPlan.held(stacks, "ore", 1))
	if AssayDemoPlan.held(stacks, "ore", 1, "B") != 2:
		return _fail("ore of species 1 at grade B is 2")
	if AssayDemoPlan.held(stacks, "ore", 9) != 0:
		return _fail("a species we hold nothing of must be 0, not a guess")
	if AssayDemoPlan.held(stacks, "handle", 1) != 0:
		return _fail("a kind we hold nothing of must be 0")
	return true


## THE BEST STACK IS THE BEST GRADE. The loop smelts some of its own ore, and refining raises grade --
## so asking for "the refined I started with" would find nothing and the probe would die on an empty
## item descriptor instead of using what it has.
func test_the_best_stack_is_the_highest_grade_of_that_kind() -> bool:
	var stacks := [_stack("refined", 1, "C", 4), _stack("refined", 1, "A", 1),
			_stack("refined", 1, "B", 2), _stack("refined", 2, "A", 9)]
	var best := AssayDemoPlan.best_stack(stacks, "refined", 1)
	if String(best.get("grade", "")) != "A" or int(best.get("species", -1)) != 1:
		return _fail("picked %s" % [best])
	if not AssayDemoPlan.best_stack(stacks, "ore", 1).is_empty():
		return _fail("a kind we hold nothing of must give {}, so the caller can say so")
	return true


## A SMELTER GOES WHERE THE SIM SAYS THERE IS ROOM, and every spot it picks is inside reach -- so a
## placement is never refused for something this function could have known.
func test_a_smelter_spot_is_free_in_bounds_and_within_reach() -> bool:
	var size := Vector2i(96, 64)
	var spot := AssayDemoPlan.smelter_spot(Vector2i(48, 32), size, [])
	if spot.x < 0:
		return _fail("an empty world offered nowhere to put a smelter")
	for tile in AssayDemoPlan.footprint(spot):
		var away: int = maxi(absi((tile as Vector2i).x - 48), absi((tile as Vector2i).y - 32))
		if away > AssayDemoPlan.REACH:
			return _fail("spot %s has a tile %s, %d away, outside reach %d"
					% [spot, tile, away, AssayDemoPlan.REACH])
	# Blocked tiles are skipped, not placed on: this is what stops three peers crafting at once from
	# being refused TileOccupied in turn.
	var blocked := AssayDemoPlan.footprint(spot)
	var second := AssayDemoPlan.smelter_spot(Vector2i(48, 32), size, blocked)
	if second == spot:
		return _fail("the same spot was offered twice with its tiles blocked")
	for tile in AssayDemoPlan.footprint(second):
		if blocked.has(tile):
			return _fail("spot %s overlaps the blocked tiles %s" % [second, blocked])
	# A corner of a one-tile world fits nothing, and saying so beats placing out of bounds.
	if AssayDemoPlan.smelter_spot(Vector2i(0, 0), Vector2i(2, 2), []) != Vector2i(-1, -1):
		return _fail("a 2x2 world has no room for a smelter beside the player")
	return true


## WHERE A PEER STANDS IS STILL ON THE DEPOSIT, whatever its rank. Standing one tile off would make
## every `Mine` a `NotOnDeposit` refusal, and the deposit's shape is a circle only the sim knows.
func test_the_stand_tile_is_always_one_the_sim_says_is_on_the_deposit() -> bool:
	var center := Vector2i(20, 20)
	var cover := {}
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			cover[center + Vector2i(dx, dy)] = absi(dx) + absi(dy) <= 1
	var seen := {}
	for rank in range(4):
		var tile := AssayDemoPlan.stand_tile(center, rank, cover)
		if not bool(cover.get(tile, false)):
			return _fail("rank %d was sent to %s, which the sim says is off the deposit"
					% [rank, tile])
		seen[tile] = true
	if seen.size() < 2:
		return _fail("every rank stood on the same tile: %s" % [seen.keys()])
	# A deposit the sim covers nowhere (a stale read) falls back to its centre rather than wandering.
	if AssayDemoPlan.stand_tile(center, 3, {}) != center:
		return _fail("with no cover at all the fallback must be the centre")
	return true


## THE BUDGET GROWS WITH THE WALK AND WITH THE SMELTING, and it is never under the smelting alone --
## an underestimate turns a real failure into "ask for more ticks", which is the confusing way round.
func test_the_tick_budget_covers_the_parts_it_is_made_of() -> bool:
	var near := AssayDemoPlan.ticks_needed(10, 10, 1, 4, 30)
	var far := AssayDemoPlan.ticks_needed(40, 40, 1, 4, 30)
	if far <= near:
		return _fail("a longer walk did not cost more: %d then %d" % [near, far])
	var smelting := AssayDemoPlan.refined_needed() * AssayDemoPlan.SMELT_TICKS_PER_ORE
	if near <= smelting:
		return _fail("the budget %d does not even cover %d ticks of smelting" % [near, smelting])
	# A richer deposit means fewer mining cycles, so the budget comes down.
	if AssayDemoPlan.ticks_needed(10, 10, 3, 4, 30) > near:
		return _fail("mining three ore a cycle cost more than mining one")
	# Zero ore a cycle would divide by zero; it is clamped rather than crashing a probe at startup.
	if AssayDemoPlan.ticks_needed(10, 10, 0, 4, 30) <= 0:
		return _fail("a zero yield must not produce a nonsense budget")
	return true
