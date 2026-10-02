class_name AssaySessionPlan
extends RefCounted
## WHAT A PROBE SHOULD DO NEXT, AS PURE FUNCTIONS OF THE WORLD IT WAS HANDED.
##
## `lockstep_probe.gd --session` plays a scripted demo session: walk onto a deposit, mine it, assay
## it. Deciding WHICH deposit is the only part of that with any judgement in it, so it lives here,
## where a test can hand it a world and check the answer instead of a person watching a relay.
##
## NOTHING HERE IS A RULE. Hardness limits, grades, what mining yields -- all of that is the sim's
## and arrives already decided (`hand_minable` comes from `sim::tuning`, through the binding). These
## functions only pick between things the sim has already judged, which is the same line the rest of
## the client holds: READ THE SIM'S OPINION, NEVER FORM A SECOND ONE.
##
## WHY RANK, AND WHY SPECIES AND NOT DEPOSIT. Three peers run this at once against one relay. Two
## peers assaying the same SPECIES is not a lockstep failure but it is a useless test: the second
## one is refused with `AlreadyAssayed` and never exercises the system. So each peer passes its own
## `PlayerId` as `rank` and takes a different species. The ordering is by species id -- stable,
## and identical on every peer, because every peer is looking at the same stepped world.
##
## The ordering only drifts if a species is assayed BETWEEN two peers choosing, which is why the
## probe chooses within the first few bundles and an `AlreadyAssayed` refusal is a loud failure
## rather than something to retry around.


## How many of the nearest deposits of one species peers spread themselves over. Three, because
## three peers is the demo's shape; a fourth peer wraps onto the first deposit, which is a sharper
## test than a long walk.
const NEARBY_DEPOSITS := 3


## The deposit this peer should walk to, or `{}` when the world offers none.
##
## Candidate species: hand-minable (the sim's own verdict) and not yet assayed. Candidate deposits:
## that species, and not depleted. Nearest wins, lowest id breaks a tie, so the answer is a pure
## function of the world and not of dictionary order.
static func choose_deposit(deposits: Array, sheets: Array, from: Vector2i, rank: int) -> Dictionary:
	var species := choose_species(deposits, sheets, rank)
	if species < 0:
		return {}
	var best := {}
	var best_key := Vector2i(1 << 30, 1 << 30)
	for entry in deposits:
		var deposit: Dictionary = entry
		if int(deposit.get("species", -1)) != species or int(deposit.get("amount", 0)) <= 0:
			continue
		var key := Vector2i(walk_ticks(from, deposit.get("center", Vector2i.ZERO) as Vector2i),
				int(deposit.get("id", 0)))
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = deposit
	return best


## A DEPOSIT OF ONE NAMED SPECIES FOR THIS PEER: among the nearest few that still hold ore, the one
## this peer's rank picks. `{}` if the species has none left.
##
## The full demo loop has no choice of species -- it has to use the pair the sim guarantees can be
## mined and smelted (`starter_pair`) -- so the divergence between peers moves here instead, to WHICH
## DEPOSIT of that one species each stands on. Three peers on three nearby patches of the same
## material is the interesting case: the amount comes down from different deposits on interleaved
## ticks, and if two peers do land on one patch, its amount comes down from both on the same tick,
## which is the most ordering-sensitive thing the loop does.
##
## NEAREST FEW, not nearest: taking the nearest would put every peer on one deposit, and taking the
## rank-th of ALL of them would send peer three on a hundred-tile walk in a 96x64 world. Sorted by
## distance then id, so the answer is a pure function of the world and identical on every peer.
static func nearest_of_species(deposits: Array, species: int, from: Vector2i,
		rank: int) -> Dictionary:
	var candidates := []
	for entry in deposits:
		var deposit: Dictionary = entry
		if int(deposit.get("species", -1)) != species or int(deposit.get("amount", 0)) <= 0:
			continue
		candidates.append(deposit)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b):
		var da := walk_ticks(from, a.get("center", Vector2i.ZERO) as Vector2i)
		var db := walk_ticks(from, b.get("center", Vector2i.ZERO) as Vector2i)
		if da != db:
			return da < db
		return int(a.get("id", 0)) < int(b.get("id", 0)))
	var reachable: int = mini(NEARBY_DEPOSITS, candidates.size())
	return candidates[maxi(rank, 0) % reachable]


## The species id this peer should work on, or -1 if the world has none left for it.
##
## Wraps when there are fewer candidate species than peers: a collision is better than a peer with
## nothing to do, and the probe reports the refusal it causes rather than hiding it.
static func choose_species(deposits: Array, sheets: Array, rank: int) -> int:
	var candidates := workable_species(deposits, sheets)
	if candidates.is_empty():
		return -1
	return candidates[maxi(rank, 0) % candidates.size()]


## Species ids, in id order, that are worth a session: the sim says hands can mine them, they are
## not assayed yet, and at least one deposit of them still holds ore.
static func workable_species(deposits: Array, sheets: Array) -> PackedInt32Array:
	var has_ore := {}
	for entry in deposits:
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) > 0:
			has_ore[int(deposit.get("species", -1))] = true
	var out := PackedInt32Array()
	for entry in sheets:
		var species: Dictionary = entry
		var id := int(species.get("id", -1))
		if not bool(species.get("hand_minable", false)):
			continue
		if bool(species.get("assayed", false)):
			continue
		if not has_ore.has(id):
			continue
		out.append(id)
	out.sort()
	return out


## How many ore of one species this inventory holds, whatever the grade.
##
## Grades do not stack together, so a count means adding stacks up; `count` and `species` are the
## sim's, and this never looks at `name`, which is wording.
static func ore_held(stacks: Array, species: int) -> int:
	var total := 0
	for entry in stacks:
		var stack: Dictionary = entry
		if String(stack.get("kind", "")) == "ore" and int(stack.get("species", -1)) == species:
			total += int(stack.get("count", 0))
	return total


## Ticks the sim needs to walk between two tiles: one per tick, diagonals included, so it is the
## Chebyshev distance. Used to budget a run, never to predict a position -- where a player IS always
## comes out of the stepped world.
static func walk_ticks(from: Vector2i, to: Vector2i) -> int:
	return maxi(absi(to.x - from.x), absi(to.y - from.y))


## Is this species assayed, according to the sheets the binding handed us? `true` only when the sim
## says so: an unknown species is not assayed.
static func is_assayed(sheets: Array, species: int) -> bool:
	for entry in sheets:
		var sheet: Dictionary = entry
		if int(sheet.get("id", -1)) == species:
			return bool(sheet.get("assayed", false))
	return false


## The sim's own name for a species, for a sentence a person reads. "" when it has none.
static func species_name(sheets: Array, species: int) -> String:
	for entry in sheets:
		var sheet: Dictionary = entry
		if int(sheet.get("id", -1)) == species:
			return String(sheet.get("name", ""))
	return ""


## A tick budget big enough for the whole script, given where we start and the sim's own costs.
##
## Walk there, mine one cycle, assay, and slack for the ticks spent noticing each step finished.
## Returned so a run that is too short fails as "the budget was too small" rather than as a mystery.
static func ticks_needed(from: Vector2i, center: Vector2i, mine_ticks: int, assay_ticks: int) -> int:
	return walk_ticks(from, center) + mine_ticks + assay_ticks + 12
