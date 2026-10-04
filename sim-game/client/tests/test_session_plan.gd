extends RefCounted
## WHAT THE SESSION PROBE DECIDES, CHECKED WITHOUT A RELAY.
##
## `lockstep_probe.gd --session` is the only thing that can tick ASSA-7's "three or more clients and
## the relay keep matching hashes through a full demo session", and a probe that quietly picked a
## bad deposit would pass by doing nothing interesting. So the choosing is `AssaySessionPlan`, pure,
## and the interesting cases are here rather than discovered during a four-minute run.
##
## Nothing here is a game rule. `hand_minable` and `assayed` arrive already decided by the sim; these
## tests only check that the plan OBEYS them.

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## Six species, three of them minable by hand, one of those already assayed.
func _sheets() -> Array:
	return [
		{"id": 0, "name": "alpha", "hand_minable": true, "assayed": false},
		{"id": 1, "name": "beta", "hand_minable": false, "assayed": false},
		{"id": 2, "name": "gamma", "hand_minable": true, "assayed": true},
		{"id": 3, "name": "delta", "hand_minable": true, "assayed": false},
		{"id": 4, "name": "epsilon", "hand_minable": true, "assayed": false},
	]


func _deposits() -> Array:
	return [
		{"id": 0, "species": 0, "center": Vector2i(50, 40), "amount": 400, "purity": 60},
		{"id": 1, "species": 0, "center": Vector2i(46, 40), "amount": 400, "purity": 20},
		{"id": 2, "species": 1, "center": Vector2i(48, 41), "amount": 400, "purity": 90},
		{"id": 3, "species": 2, "center": Vector2i(48, 42), "amount": 400, "purity": 10},
		{"id": 4, "species": 3, "center": Vector2i(60, 50), "amount": 400, "purity": 70},
		{"id": 5, "species": 4, "center": Vector2i(10, 10), "amount": 0, "purity": 70},
	]


## THE SIM SAYS WHAT HANDS CAN MINE. A probe that walked to a hardness-80 deposit and submitted
## `Mine` would be refused, and the run would fail for a reason that is not lockstep.
func test_a_species_hands_cannot_mine_is_never_chosen() -> bool:
	for rank in range(6):
		var chosen := AssaySessionPlan.choose_species(_deposits(), _sheets(), rank)
		if chosen == 1:
			return _fail("rank %d chose species 1, which the sim says hands cannot mine" % rank)
	return true


## An already-assayed species would refuse the `Assay` half of the session with `AlreadyAssayed`.
func test_an_assayed_species_is_never_chosen() -> bool:
	for rank in range(6):
		var chosen := AssaySessionPlan.choose_species(_deposits(), _sheets(), rank)
		if chosen == 2:
			return _fail("rank %d chose species 2, which is already assayed" % rank)
	return true


## A depleted deposit is the whole of species 4 here, so the species has nothing to offer.
func test_a_species_with_only_empty_deposits_is_never_chosen() -> bool:
	var workable := AssaySessionPlan.workable_species(_deposits(), _sheets())
	if workable.has(4):
		return _fail("species 4 was offered, but its only deposit holds 0 ore")
	if Array(workable) != [0, 3]:
		return _fail("expected species [0, 3] to be workable, got %s" % [workable])
	return true


## THE POINT OF `rank`: three peers, three different species, so the second peer's assay is not
## refused as already done. They must also agree, since each computes it from the same world.
func test_different_peers_take_different_species() -> bool:
	var sheets := _sheets()
	sheets.append({"id": 5, "name": "zeta", "hand_minable": true, "assayed": false})
	var deposits := _deposits()
	deposits.append({"id": 6, "species": 5, "center": Vector2i(70, 30), "amount": 400, "purity": 50})
	var taken := {}
	for rank in range(3):
		var chosen := AssaySessionPlan.choose_species(deposits, sheets, rank)
		if taken.has(chosen):
			return _fail("ranks %s and %d both chose species %d" % [taken[chosen], rank, chosen])
		taken[chosen] = rank
	return true


## Fewer species than peers must still give every peer something to do. The refusal that causes is
## the probe's to report; silently idling would be worse.
func test_more_peers_than_species_wraps_rather_than_giving_up() -> bool:
	var chosen := AssaySessionPlan.choose_species(_deposits(), _sheets(), 7)
	if chosen != 0 and chosen != 3:
		return _fail("rank 7 got species %d; only 0 and 3 are workable here" % chosen)
	if AssaySessionPlan.choose_species([], _sheets(), 0) != -1:
		return _fail("a world with no deposits must give -1, not a species id")
	return true


## Nearest of that species, by the sim's own one-tile-per-tick movement, lowest id on a tie.
func test_the_nearest_deposit_of_the_chosen_species_wins() -> bool:
	var chosen := AssaySessionPlan.choose_deposit(_deposits(), _sheets(), Vector2i(44, 40), 0)
	if int(chosen.get("id", -1)) != 1:
		return _fail("from (44,40) deposit 1 is 2 tiles away and deposit 0 is 6; got %s" % [chosen])
	chosen = AssaySessionPlan.choose_deposit(_deposits(), _sheets(), Vector2i(52, 40), 0)
	if int(chosen.get("id", -1)) != 0:
		return _fail("from (52,40) deposit 0 is the near one; got %s" % [chosen])
	return true


## Diagonals cost one tick, so the budget must be the Chebyshev distance and not the sum.
func test_walk_ticks_counts_diagonals_as_one() -> bool:
	if AssaySessionPlan.walk_ticks(Vector2i(0, 0), Vector2i(5, 5)) != 5:
		return _fail("a 5x5 diagonal is 5 ticks, not %d"
				% AssaySessionPlan.walk_ticks(Vector2i(0, 0), Vector2i(5, 5)))
	if AssaySessionPlan.walk_ticks(Vector2i(10, 2), Vector2i(3, 9)) != 7:
		return _fail("expected 7 ticks for (10,2)->(3,9)")
	return true


## Grades do not stack together, so one species can be several stacks; a count that read only the
## first would call a mining run a failure.
func test_ore_held_adds_every_grade_of_one_species() -> bool:
	var stacks := [
		{"kind": "ore", "species": 0, "grade": "C", "count": 3},
		{"kind": "ore", "species": 0, "grade": "B", "count": 4},
		{"kind": "ore", "species": 1, "grade": "B", "count": 9},
		{"kind": "refined", "species": 0, "grade": "B", "count": 5},
	]
	if AssaySessionPlan.ore_held(stacks, 0) != 7:
		return _fail("two ore stacks of species 0 are 7, got %d"
				% AssaySessionPlan.ore_held(stacks, 0))
	if AssaySessionPlan.ore_held(stacks, 2) != 0:
		return _fail("species 2 is not in this inventory and must count 0")
	return true


## The budget has to cover the walk AND the sim's own costs, or a passing run proves only that the
## probe gave up early.
func test_the_tick_budget_covers_the_whole_script() -> bool:
	var needed := AssaySessionPlan.ticks_needed(Vector2i(48, 40), Vector2i(60, 50), 4, 30)
	if needed < 10 + 4 + 30:
		return _fail("budget %d is under walk 10 + mine 4 + assay 30" % needed)
	return true


## "Assayed" is the sim's word. An unknown species must read as not assayed rather than crash the
## run, and the name must come from the sheet rather than being invented here.
func test_assayed_and_name_come_from_the_sheets() -> bool:
	if not AssaySessionPlan.is_assayed(_sheets(), 2):
		return _fail("species 2 is marked assayed in the sheets")
	if AssaySessionPlan.is_assayed(_sheets(), 99):
		return _fail("a species the world does not have must not read as assayed")
	if AssaySessionPlan.species_name(_sheets(), 3) != "delta":
		return _fail("species 3 is named delta in the sheets")
	return true


## Deposits carrying the sim's `starter` flag: two patches of species 0, the GUARANTEED one further
## away and poorer-looking, so "nearest" and "guaranteed" are different answers and a test cannot
## pass by accident. Purity is on them only to make the fixture readable; nothing here reads it.
func _flagged_deposits() -> Array:
	return [
		{"id": 0, "species": 0, "center": Vector2i(46, 40), "amount": 400, "purity": 20,
			"starter": false},
		{"id": 1, "species": 0, "center": Vector2i(70, 40), "amount": 400, "purity": 55,
			"starter": true},
		{"id": 2, "species": 3, "center": Vector2i(60, 50), "amount": 400, "purity": 70,
			"starter": true},
		{"id": 3, "species": 4, "center": Vector2i(10, 10), "amount": 0, "purity": 90,
			"starter": true},
	]


## THE FUEL COMES OFF THE PATCH THE SIM GUARANTEES, NOT THE NEAREST ONE OF THE RIGHT SPECIES
## (ASSA-139). Grade scales reactivity, so the nearer patch is a fire that may be too cool to melt
## its own ore -- 1.5% of worlds, measured, and the loop stalled forever with the sim correct.
func test_the_guaranteed_deposit_is_not_the_nearest_one() -> bool:
	var from := Vector2i(44, 40)
	var guaranteed := AssaySessionPlan.guaranteed_of_species(_flagged_deposits(), 0)
	if int(guaranteed.get("id", -1)) != 1:
		return _fail("deposit 1 carries the sim's starter flag; got %s" % [guaranteed])
	# The premise: the two answers really differ on this fixture, or the test proves nothing.
	var nearest := AssaySessionPlan.nearest_of_species(_flagged_deposits(), 0, from, 0)
	if int(nearest.get("id", -1)) != 0:
		return _fail("fixture broken: nearest should be deposit 0, got %s" % [nearest])
	return true


## An empty guaranteed patch is not a guarantee. The caller falls back to the nearest rather than
## stopping the loop, which is why this must report `{}` and not the depleted patch.
func test_a_depleted_guaranteed_deposit_is_not_offered() -> bool:
	var chosen := AssaySessionPlan.guaranteed_of_species(_flagged_deposits(), 4)
	if not chosen.is_empty():
		return _fail("deposit 3 holds no ore and must not be offered; got %s" % [chosen])
	return true


## A species with no guaranteed patch at all reports nothing rather than guessing one.
func test_a_species_with_no_guaranteed_patch_reports_nothing() -> bool:
	var chosen := AssaySessionPlan.guaranteed_of_species(_flagged_deposits(), 1)
	if not chosen.is_empty():
		return _fail("species 1 has no starter patch; got %s" % [chosen])
	return true
