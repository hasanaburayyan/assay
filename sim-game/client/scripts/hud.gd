class_name AssayHud
extends RefCounted
## THE HUD'S WORDS AND COLOURS, AND NOTHING ELSE.
##
## Every function here is static and pure: dictionaries the sim gave us in, text or a colour out. No
## state, no sim, no nodes. That is so the rules Maren has ruled on can be TESTED rather than
## promised -- `tests/test_hud.gd` asserts them directly, and the one about deposit colour already
## caught a shipped mistake of mine.
##
## WHAT THIS FILE MAY NOT DO: work anything out that the sim knows. No grade from a purity, no band
## from a number, no mass from a sheet. Those arrive already decided (`AssaySimHost.tile_at`,
## `species_sheets`) and this file arranges them on screen.

## Status-line states. Maren's ruling (ASSA-7, 2026-10-02): a failure must not LOOK like an
## instruction, so the words are not the only signal -- the colour carries the state.
enum Say { IDLE, CONNECTING, FAILED, JOINED }

## WHERE THINGS GO. Here rather than in `main.gd` so the one layout rule that matters can be tested:
## the HUD column sits BESIDE the map and never over it.
const VIEW := Vector2(1280.0, 720.0)
const MARGIN := Vector2(24.0, 96.0)
const PANEL := 320.0

## What the map is drawn on. Here rather than in `main.gd` because `glyph_color` has to composite a
## deposit's colour against it to decide whether a letter on top should be dark or light.
const MAP_BG := Color(0.10, 0.11, 0.13)

## THE SIX SPECIES TINTS, SLOT BY SLOT, AND THE CLIENT MAY NOT WORK THEM OUT.
##
## Decision #36 and Maren's ruling (ASSA-7, 2026-10-02). What I shipped first was Decision #35's
## option A -- `species / count` round the hue wheel -- and Cove MEASURED it: the closest pair is
## dE 5.7 for a protan viewer against a floor of 12, because even spacing optimises for normal
## vision and walks species straight along the red-green confusion axis. This table is derived
## (`art/species_probe.py`) and scores 18.3 for the worst observer, 15.8 at the darkest grade.
##
## DO NOT "IMPROVE" THE SPACING. Okabe-Ito's sky blue and blue are the same hue to a tenth of a
## degree and survive colour blindness precisely because they differ in lightness and saturation
## instead; hue distance in HSV is not perceptual distance, which is why Maren retired the old
## 30-degree bar along with my test of it.
##
## ONE TABLE, and there is no elegant home for it. The same six strings are in
## `art/species_tints.py`, which the Blender pipeline multiplies over the species-neutral ore
## sprite, and `art/check_species_tints.py` fails CI if the two ever differ or stop being as long
## as the sim's roster. A palette cannot live in `sim` (repo `CLAUDE.md` principle 1: the sim knows
## nothing of a renderer) and the client has no asset pipeline yet, so two files and a check is the
## honest version rather than the tidy one.
## (A plain typed Array, not a `PackedStringArray`: a packed array's constructor is not a constant
## expression, so `const` refuses it -- and refuses it as a PARSE ERROR, which takes the whole file
## and every file that references it down with it. Godot still exits 0 on that, so it is
## `test_main_screen.gd` loading the real scene that turns it into a failing test.)
const SPECIES_TINTS: Array[String] = ["#7A29CC", "#FF3333", "#FF80BF", "#FFFF33", "#3333FF",
		"#509BE6"]

## A glyph on a deposit is one of these two, never the tint's own colour at another brightness.
## Near-black and pure white, which is not fussiness: pushing either end inward costs contrast at the
## purity where that end is the one being chosen, and this pair is what makes the worst case over all
## six species and all 100 purities 4.52 (`art/check_glyph_contrast.py`).
##
## The old note here claimed a "crossover luminance of 0.221". There is no such crossover and the
## number came from a luminance that is not one -- see `glyph_color`.
const GLYPH_DARK := Color(0.02, 0.02, 0.03)
const GLYPH_LIGHT := Color(1.0, 1.0, 1.0)


## The tile size the map is drawn at. THE PANEL'S WIDTH COMES OUT OF THE MAP'S WIDTH TERM, which is
## what makes the map shrink instead of hiding under the HUD (Maren's ruling, ASSA-7). Floored to a
## whole pixel so a tile boundary is where a click says it is, and never below 2px: a huge world drawn
## at less than that is unreadable, and at zero it would be undrawable.
static func map_cell(size: Vector2i) -> float:
	if size.x <= 0 or size.y <= 0:
		return 0.0
	return maxf(2.0, floorf(minf((VIEW.x - MARGIN.x * 2.0 - PANEL) / float(size.x),
			(VIEW.y - MARGIN.y - 24.0) / float(size.y))))


## A DEPOSIT'S COLOUR: THE SPECIES' SLOT, DIMMED BY PURITY. Purity may never move the hue.
##
## Second correction of this function, and the first one is worth keeping in view. Version one rode
## purity on R and G, which swung the hue 130 degrees across the purity range and collapsed
## saturation in the middle, so a mid-purity patch was the hardest thing on the map to see. Version
## two fixed that with evenly spaced hues, which is the scheme Cove then measured and rejected. Both
## times the mistake was the same shape: I decided what a colour should be instead of asking what a
## player could see. The slot comes from `SPECIES_TINTS` now and nothing here computes a hue.
##
## PURITY IS A MULTIPLIER ON THE SLOT'S OWN VALUE, 0.62 to 1.0. Scaling R, G and B together cannot
## move hue or saturation, so the ruling holds by construction rather than by my care.
##
## THE DIM END AND THE ALPHA ARE ONE MEASUREMENT, AND THE OPEN QUESTION ABOVE IS NOW ANSWERED -- NO.
## I left it open ("whether the dim end still clears the floor is a question for their probe") and
## the answer was that it did not. `art/species_probe.py` reads these two constants out of this
## function, composites the disc as it is actually drawn, and sweeps purity 1..100. What shipped
## first -- base 0.5, alpha 0.85 -- bottomed out at dE(a*b*) 10.8 at PURITY 6 against a floor of 12,
## species 0 against species 5 for a deutan player. Three things in that are worth keeping:
##   - the worst case is NOT the dimmest disc. The closest PAIR moves with brightness, so sampling
##     the ends misses the minimum. That is why the probe sweeps.
##   - the alpha was carrying the failure. 15% of near-black mixes into every disc and costs 1-2 dE
##     of chroma; the earlier measurement that said "fine" had modelled the disc as opaque.
##   - neither constant alone fixes it: alpha 1.0 alone scores 12.5, base 0.65 alone 12.9, and 8-bit
##     rounding jitters this score by about a point, so a margin under 1.0 is noise, not headroom.
##     I checked that from the other side too, since it is the claim the ruling rests on: the probe's
##     new `MAP_ALPHA=0.85` lever puts THIS base back on the OLD alpha and scores 11.8 -- under the
##     floor outright. Base 0.60 was never a fix on its own; it is a fix because the disc is opaque.
## Maren's ruling (ASSA-7, 2026-10-02) is therefore BOTH: alpha 1.0 and base 0.60, measured at 14.0
## -- two clear points. 0.60 is the knee of the sweep at alpha 1.0 (0.55 -> 13.6, 0.65 -> 15.0) and
## keeps 84% of the purity ladder, where 0.65 would spend 26% of it to buy a point nobody needs.
##
## WHAT IT COSTS, SAID PLAINLY: the brightness range narrows from 1.90:1 to 1.67:1, so purity is a
## little harder to read at a glance -- on the axis that already does double duty, because the
## table's slots do not share one value (purple sits at 0.80, yellow at 1.0) and so brightness
## carries purity AND a little species. Within one species it reads cleanly; across two species it
## is the GRADE WORD that compares, never the brightness (Maren's ruling 17, same as the ore tile).
##
## AND NOT THE OTHER FIX I OFFERED: letting the glyph carry the dim end was refused, correctly. The
## letter is redundant BY DESIGN (ruling 16), and a redundant cue promoted to the only cue is no
## longer redundant -- it is also only decodable beside the menu row that names the species, and
## `glyph_size` draws nothing at all under 10px. Below about 7px of radius COLOUR IS THE ONLY MAP
## READ, so the colour has to stand on its own at every purity. The fix belongs on the composite.
## A SPECIES' OWN SLOT, UNDIMMED -- the identity colour, before any purity is folded in.
##
## FACTORED OUT SO THERE IS ONE LOOKUP (ASSA-73). The species panel is the map's LEGEND, and a legend
## drawn from a second copy of this table would be a key that can stop matching its own map. Maren's
## ruling is explicit: the panel borrows the map's vocabulary, never a tint it computes for itself.
## `deposit_color` dims this by purity; the legend does not, because a species' identity is not a
## property of whichever patch of it you are looking at.
static func species_tint(species: int) -> Color:
	# The TABLE bounds the index, not the roster: a species id past the end wraps rather than
	# crashing a frame. `test_sim_binding.gd` is where the sim's roster size and this table's length
	# are held to each other, so the wrap is a seatbelt and never the normal case.
	return Color(SPECIES_TINTS[posmod(species, SPECIES_TINTS.size())])


static func deposit_color(species: int, purity: int) -> Color:
	var tint := species_tint(species)
	# Clamped 0.05 low so a purity-1 patch is still visible, 1.0 high because purity stops at 100.
	# The clamp is why the dimmest disc is 0.62 and not 0.60.
	var purity_part := clampf(float(purity) / 100.0, 0.05, 1.0)
	var dimmed := 0.60 + 0.40 * purity_part
	# OPAQUE, and that is half the fix above: nothing is ever drawn under a deposit on this map, so
	# translucency bought atmosphere and paid for it out of the one read the map exists for.
	return Color(tint.r * dimmed, tint.g * dimmed, tint.b * dimmed, 1.0)


## RELATIVE LUMINANCE, WCAG 2.1: linearise each channel, then weight. `Color.get_luminance()` applies
## those same weights to the sRGB-ENCODED channels and skips the linearisation, which is why it must
## never be used to compare readability. Measured rather than taken from the docs: Godot's
## `srgb_to_linear()` agrees with the piecewise formula to 1.3e-7 across 1001 samples, so the engine
## call is the exact transfer function and not an approximation of it.
static func relative_luminance(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b


## WCAG CONTRAST RATIO between two opaque colours, 1.0 (identical) to 21.0 (black on white).
static func contrast_ratio(a: Color, b: Color) -> float:
	var x := relative_luminance(a) + 0.05
	var y := relative_luminance(b) + 0.05
	return x / y if x > y else y / x


## THE LETTER ON A DEPOSIT: DARK OR LIGHT, WHICHEVER IS ACTUALLY EASIER TO READ ON THAT PATCH.
##
## It computes both contrast ratios and keeps the better one. There is no threshold, which is the
## point: Decision #36 (option A on this item, Maren's ruling) picks the measurement over a constant
## precisely because a constant is tuned to the six tints that happen to ship today, and the tints have
## already moved twice this week.
##
## WHAT WAS WRONG, because it is worth knowing how confident a wrong comment can sound. This picked
## `GLYPH_DARK` when `lit.get_luminance() > 0.221`, and said 0.221 was "where the two glyph colours are
## equally readable". `Color.get_luminance()` weights the sRGB-ENCODED channels without linearising
## them, so it is not a perceptual luminance and that crossover does not exist. Cove swept all six
## tints x purity 1..100 and found **226 of 600 states were given the glyph with LESS contrast than the
## other option would have had** -- worst, the purple species at purity 52, which took 2.22 where 9.18
## was on the table. I reproduced that in the engine before changing anything: `get_luminance()` there
## reads 0.22177 while the true relative luminance is 0.0643, a factor of 3.4 apart.
##
## THE INVARIANT THIS NOW HOLDS, and why there is no floor in the test: picking the better of two is
## optimal by construction, so the right assertion is "the chosen glyph is the higher-ratio one at
## every state", not "every state clears 3.0". 4.5152 (species 2, purity 24) is the worst case of the
## best possible picker -- the ceiling of this two-colour family, not a target to be met. A floor would
## rot the moment a tint moves; the invariant cannot. That is Maren's sharpening of acceptance 2.
##
## `deposit_color` returns alpha 1.0 now, so for a deposit this composite is the identity and the lerp
## costs nothing. IT STAYS ANYWAY: this function's contract is "whatever is drawn there", and it was
## the only place in the client that had the compositing right while the probe measuring the same disc
## had it wrong. A function that reads the alpha it is given cannot be made wrong by someone changing
## that alpha back.
static func glyph_color(on: Color) -> Color:
	var lit := MAP_BG.lerp(Color(on.r, on.g, on.b), on.a)
	return GLYPH_DARK if contrast_ratio(lit, GLYPH_DARK) >= contrast_ratio(lit, GLYPH_LIGHT) \
			else GLYPH_LIGHT


## HOW BIG THE LETTER IS, or 0 FOR DON'T DRAW IT. A glyph that does not fit inside its own patch is
## worse than no glyph: it reads as a label for the tile next door. 1.4 x radius keeps a capital
## inside the circle with margin, 10px is the floor where a letter is still a letter rather than a
## smudge, and 32 stops a huge deposit from being mostly typography.
static func glyph_size(drawn_radius: float) -> int:
	var size := int(floorf(drawn_radius * 1.4))
	return 0 if size < 10 else mini(size, 32)


## The status line's colour for a state. Neutral idle, amber connecting, red failed, green joined.
static func status_color(level: int) -> Color:
	match level:
		Say.CONNECTING:
			return Color(0.95, 0.75, 0.35)
		Say.FAILED:
			return Color(0.95, 0.40, 0.35)
		Say.JOINED:
			return Color(0.50, 0.90, 0.55)
		_:
			return Color(0.80, 0.82, 0.86)


## YOUR OWN STACKS, one line each. The sim's own `name` for the item carries kind, species and grade
## together, so there is one wording for an item in the client and the CLI rather than two.
static func inventory_lines(stacks: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	if stacks.is_empty():
		lines.append(nothing_carried_line())
		return lines
	for entry in stacks:
		lines.append(stack_line(entry as Dictionary))
	return lines


## ONE STACK, as its row's words. Split out of `inventory_lines` when the pack became rows with
## buttons on them (ASSA-37): one wording, whether it is read as a list or pressed.
static func stack_line(stack: Dictionary) -> String:
	return "%d × %s" % [int(stack.get("count", 0)), String(stack.get("name", "?"))]


## What the pack says when it is empty, which is every player for their first few ticks.
static func nothing_carried_line() -> String:
	return "carrying nothing"


## EVERY VERB A STACK AFFORDS, as descriptors for the row's buttons: `{label, verb, ...}`.
##
## WHAT A PLAYER CAN DO WITH A THING IS THE SIM'S LIST, NOT MINE. `recipes` and `part_kinds` are
## `AssaySim`'s own catalogues, so a Craft button exists because some hand recipe eats this kind of
## item and for no other reason. The alternative was four kind names written into this client, which
## would make it the one file that still had to be edited when `PART_SPECS` or `RECIPES` grew -- and
## ADR 0003's whole point is that a new part kind needs no new code.
##
## THIS DECIDES NOTHING ABOUT LEGALITY. Not whether the batch is affordable, not whether the species
## is hard enough, not whether a smelter is in reach. `sim::step` validates every command on every
## peer; a button missing here would be this client holding an opinion the other peers do not have.
## A verb is offered when the COMMAND CAN BE BUILT AT ALL, and then the sim answers.
##
## `building` is whether an assembly is part-way built, which changes one word: the first part you add
## is the FRAME (`sim-cli`'s `assemble <frame> <part>...` rule, kept rather than invented).
## `footprint` is `AssaySimHost.footprint_of_item`, so "is this placeable" is also the sim's answer.
static func stack_verbs(stack: Dictionary, recipes: Array, part_kinds: Array,
		footprint: Vector2i, building: bool) -> Array:
	var kind := String(stack.get("kind", ""))
	var verbs := []
	for entry in recipes:
		var recipe: Dictionary = entry
		if String(recipe.get("input", "")) != kind:
			continue
		if bool(recipe.get("hand", false)):
			# `dead_end` RIDES ALONG UNREAD. It is the sim's own clause -- empty unless nothing in
			# the game consumes this recipe's output -- and this file neither writes it nor asks
			# what it is about. Carrying it is how a BUTTON can warn what only a CLI table warned
			# before (ASSA-84); deciding when to warn would be a second describer.
			verbs.append({"label": "Craft %s" % String(recipe.get("name", "?")), "verb": "craft",
					"recipe": recipe.get("tag"),
					"dead_end": String(recipe.get("dead_end", ""))})
		elif not _has_verb(verbs, "insert"):
			# A recipe that is NOT hand-work happens inside a building, so this kind is something a
			# smelter eats -- both slots, because which one a species is good for (hot enough fuel, or
			# ore that melts) is a sheet reading and only the sim has it.
			# SHORT LABELS, DETAIL IN THE TOOLTIP. Two buttons and a stack line have to fit a 320px
			# panel, and "Insert all 12 into the Fuel slot" is a sentence, not a label. `main.gd`
			# composes that sentence as the hint, with the count in it.
			verbs.append({"label": "Fuel", "verb": "insert", "slot": AssayActions.SLOT_FUEL})
			verbs.append({"label": "Smelt", "verb": "insert", "slot": AssayActions.SLOT_INPUT})
	if footprint.x > 0 and footprint.y > 0:
		verbs.append({"label": "Place", "verb": "place"})
	for entry in part_kinds:
		var part: Dictionary = entry
		# ONE `Make` PER PART KIND THE CATALOGUE HOLDS, on the row whose item is the material a part
		# is made of. `material` is the sim's answer (`step.rs`: "a part is made of refined material
		# and nothing else"), so a row only grows these buttons because the sim would accept them --
		# and a FIFTH part kind appears here with no change to this client.
		if String(part.get("material", "")) == kind:
			verbs.append({"label": "Make %s" % String(part.get("name", "?")), "verb": "make",
					"kind": part.get("tag"), "part": String(part.get("name", "?"))})
		# And the row for a part itself offers the way into an `Assemble`. The first part added is
		# the frame, so the word changes rather than the button.
		if String(part.get("name", "")) == kind:
			verbs.append({"label": "Mount" if building else "Frame", "verb": "build"})
	return verbs


## EVERY VERB A DESIGN ROW AFFORDS. Three cases and no fourth: the tool in your hands can go back on
## the bench, a held design can go into your hands, a planted one can go on the map.
##
## PLACE IS HERE WHATEVER THE VERDICT SAYS (Maren's ruling, ASSA-5/7). An over-budget design BREAKS
## at placement -- that is where the sim tests mass, by decision 11 -- and breaking is a soft reset
## that hands the parts back. A client that hid the button would be turning a mechanic into an error
## message, and WILL BREAK would stop being a prediction a player can choose to test.
static func design_verbs(design: Dictionary) -> Array:
	if bool(design.get("in_hand", false)):
		return [{"label": "Unequip", "verb": "unequip"}]
	if String(design.get("mount", "")) == "planted":
		return [{"label": "Place", "verb": "place_assembly"}]
	return [{"label": "Equip", "verb": "equip"}]


static func _has_verb(verbs: Array, verb: String) -> bool:
	for entry in verbs:
		if String((entry as Dictionary).get("verb", "")) == verb:
			return true
	return false


## WHERE A BUTTON ACTS, said out loud. A target that is only drawn is a target a player has to infer,
## and Place, Insert and Take all land on it -- so the one sentence names the tile and what is on it.
##
## "where you stand" until the map is right-clicked, which is not a placeholder: your own tile is the
## one tile every player has, and planting beside yourself is the common case.
static func target_line(tile: Vector2i, chosen: bool, tile_facts: Dictionary) -> String:
	var what := "right-click the map to choose a tile"
	var building: Variant = tile_facts.get("building")
	if building != null:
		what = "%s %d" % [String((building as Dictionary).get("kind", "?")),
				int((building as Dictionary).get("id", -1))]
	elif bool(tile_facts.get("in_bounds", false)):
		what = "empty ground" if tile_facts.get("deposit") == null else "on a deposit"
	return "acting on (%d, %d) · %s · %s" % [tile.x, tile.y,
			"chosen" if chosen else "where you stand", what]


## THE PARTS WAITING TO BE ASSEMBLED, as one line. Empty while nothing is chosen, because a heading
## over a blank reads as a bug.
static func building_line(parts: Array) -> String:
	if parts.is_empty():
		return ""
	var names := PackedStringArray()
	for entry in parts:
		names.append(String((entry as Dictionary).get("name", "?")))
	return "assembling: %s on a %s" % [", ".join(names.slice(1)) if names.size() > 1 else "nothing",
			names[0]]


## WHAT IS UNDER THE CURSOR, as lines. A tile off the map says so: the cursor is off the map most of
## the time and a readout that quietly showed tile (0, 0) instead would be lying.
static func tile_lines(tile: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if tile.is_empty():
		return lines
	var at: Vector2i = tile.get("pos", Vector2i.ZERO)
	if not bool(tile.get("in_bounds", false)):
		lines.append("(%d, %d) is off the map" % [at.x, at.y])
		return lines
	var chunk: Vector2i = tile.get("chunk", Vector2i.ZERO)
	lines.append("(%d, %d) · chunk (%d, %d) · %d from spawn"
			% [at.x, at.y, chunk.x, chunk.y, int(tile.get("chunks_from_spawn", 0))])

	var deposit: Variant = tile.get("deposit")
	if deposit != null:
		var d: Dictionary = deposit
		lines.append("deposit %d · %s · %d ore left%s" % [int(d.get("id", -1)),
				String(d.get("species_name", "?")), int(d.get("amount", 0)),
				" · DEPLETED" if bool(d.get("depleted", false)) else ""])
		# REACH COMES BEFORE THE INVITATION (ASSA-47, Marlow's ask). `reach_note` is the SIM's
		# sentence and is EMPTY when the rock yields, so this line appears only when it has something
		# to say -- the same shape as a building's `status` two blocks down.
		var reach := String(d.get("reach_note", ""))
		if reach != "":
			lines.append(reach)
		# AND THEN NO INVITATION AT ALL IF NOTHING CAN MINE IT. `Assay` is not gated on the rock being
		# workable, so a player can spend the 30 ticks, succeed, and learn a sheet they can never use:
		# you cannot build with ore you cannot get out. Maren measured 40.7% of deposits like that.
		# A SOFTENED CUE WOULD STILL BE A CUE, which is why this drops the clause rather than greying
		# it: "you could" is the bug.
		#
		# The purity and grade stay either way, because they are facts about the rock rather than an
		# offer, and the ASSAYED sentence stays too -- it reports something already done. Only the
		# invitation is conditional, and when the rock yields this line is byte-for-byte what it was
		# before ASSA-47 (`test_the_in_reach_tile_line_is_unchanged` holds that).
		#
		# NOTHING HERE DECIDES WHETHER IT YIELDS. `hand_minable` arrives decided, from the same
		# `sim::ladder` function `step` itself asks; this file may not work out what the sim knows.
		var cue := ""
		if bool(d.get("assayed", false)):
			cue = "assayed: its sheet is exact"
		elif bool(d.get("hand_minable", false)):
			cue = "sheet is rough — stand here and assay to be sure"
		else:
			cue = "sheet is rough"
		lines.append("purity %d (grade %s) · %s"
				% [int(d.get("purity", 0)), String(d.get("grade", "?")), cue])
	elif bool(tile.get("is_spawn", false)):
		lines.append("spawn")
	else:
		lines.append("empty ground")

	var building: Variant = tile.get("building")
	if building != null:
		var b: Dictionary = building
		lines.append("%s %d · %s" % [String(b.get("kind", "?")), int(b.get("id", -1)),
				String(b.get("status", ""))])

	var here: PackedStringArray = tile.get("players_here", PackedStringArray())
	if not here.is_empty():
		lines.append("players here: %s" % ", ".join(here))
	return lines


## The newest `limit` lines of the event log. THE NEWEST: a log that dropped the line that just
## arrived would be the exact opposite of a log.
static func trimmed_log(lines: PackedStringArray, limit: int) -> PackedStringArray:
	if limit <= 0 or lines.size() <= limit:
		return lines
	return lines.slice(lines.size() - limit)


## A SPAN THE SIM GAVE US, as words: "26-50" while a species reads rough, "38" once it is assayed.
##
## Formatting, not arithmetic. Both ends are the sim's (`Assembly::stat_range`,
## `Assembly::part_mass_range`); this file may not average them, round them or pick one.
static func span(low: int, high: int) -> String:
	return str(low) if low == high else "%d-%d" % [low, high]


## THE VERDICT'S COLOUR. Three states, and the interesting one is UNCERTAIN.
##
## Maren's ruling (ASSA-7): UNCERTAIN MUST NOT LOOK LIKE A WARNING. It is 36.9% of every design a
## player can build -- NOT half; the half in ADR 0003 A8 is what an UNCERTAIN design does when you
## place it, not how many designs are UNCERTAIN, and this line had the two confused. Measured over
## 2000 worlds, unassayed, counting only the grades a world's deposits can actually reach, against
## A8's predicted 37.5%. It is still the advertisement for assaying, so it gets an informational
## COOL colour, not
## the amber a client reaches for by habit. WILL BREAK is warm but not alarm red -- the charter's
## feel is "calm, never punishing", and a break is a soft reset that hands parts back.
static func verdict_color(verdict: String) -> Color:
	match verdict:
		"SAFE":
			return Color(0.55, 0.82, 0.60)
		"UNCERTAIN":
			return Color(0.52, 0.74, 0.92)
		"WILL BREAK":
			return Color(0.93, 0.63, 0.42)
		_:
			return Color(0.80, 0.82, 0.86)


## ONE DESIGN, UNDER ITS VERDICT: what it weighs against its budget, what resolves the doubt, what
## it is made of. The verdict word itself is NOT here -- it is its own label in its own colour, and
## these are the small print under it (Maren's ruling: the verdict is the headline, the numbers are
## the small print).
##
## NOTHING IS DERIVED. The verdict, both spans, the durability string and the rough-species list all
## arrive decided by the sim through `designs_of`; a client comparing mass to budget itself would be
## a second opinion about whether a machine breaks.
static func design_lines(design: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var mass := span(int(design.get("mass_low", 0)), int(design.get("mass_high", 0)))
	var budget := span(int(design.get("budget_low", 0)), int(design.get("budget_high", 0)))
	var mount := String(design.get("mount", "?"))
	lines.append("%s · mass %s of %s budget" % [
			"in hand" if bool(design.get("in_hand", false)) else mount, mass, budget])
	# THE SMALL PRINT IS THE SIM'S SENTENCE, NOT ONE THIS FILE WRITES (ASSA-90). This used to compose
	# "assay %s to know" from the raw `unassayed` list and append it WHENEVER THAT LIST WAS NON-EMPTY,
	# which is a field printed because it is non-empty rather than because it means anything here:
	# - on WILL BREAK it offered an assay instead of saying the design would break, and an assay
	#   cannot move that verdict -- its mass and budget spans are already disjoint, and an assay only
	#   collapses a band to a point inside itself;
	# - on SAFE it handed a settled design a to-do.
	# The sim now words all three (`sim::debug::verdict_note`) and the key is ABSENT on SAFE, so there
	# is nothing here to get wrong. The ad assaying gets is still the one that names the material --
	# that wording won and moved into the sim, it did not go away.
	var note := String(design.get("note", ""))
	if note != "":
		lines.append(note)
	# ABSENT, not blank: a planted machine has no durability key, because drill wear is parked and a
	# number that never moves teaches a mechanic that does not exist.
	# KEEPING THE "durability" LABEL, which Marlow offered to let me drop now that the sim's string
	# reads "20 of 144 swings used" and the line is a touch redundant. Two reasons not to. It is a row
	# in a list of rows, so without the label "20 of 144 swings used" has to be guessed at from
	# position; and `sim-cli` prints the same label, so dropping mine would make the two hosts say
	# different things about one number for a cosmetic gain. If the wording wants improving it should
	# improve in both, and the sentence after the label is the sim's to choose, never this file's.
	# AND IT IS GATED ON `in_hand`, NOT ONLY ON THE KEY BEING THERE. The docstring under this function
	# has always claimed the panel must not print the word "anyway" -- i.e. on top of the binding
	# leaving the key out. It did not: it printed whatever key it was handed. I found that by mutating
	# this condition to `if true:` and watching the suite stay green at 81/0, because the planted test
	# erases the key and so could never catch a panel that had stopped checking. Two sim facts read
	# (`durability`, `in_hand`), nothing derived, and the rule now holds even if the binding regresses.
	if design.has("durability") and bool(design.get("in_hand", false)):
		lines.append("durability %s" % String(design["durability"]))
	# THE LETTER IS HERE TO TEACH THE MAP, not to carry the row. The row already names its species in
	# words, which is a stronger non-colour read than a glyph -- so on its own I would have left this
	# out. Maren's ruling is right for a reason I missed: the letter stamped on a deposit is only
	# decodable if something, somewhere, says which name it stands for, and this row is the only place
	# a player sees both. Once per deposit, once per row, never once per tile.
	for entry in design.get("parts", []):
		var part: Dictionary = entry
		lines.append("  %s · %s %s %s · mass %s" % [String(part.get("kind", "?")),
				String(part.get("symbol", "?")), String(part.get("species_name", "?")),
				String(part.get("grade", "?")),
				span(int(part.get("mass_low", 0)), int(part.get("mass_high", 0)))])
	return lines


## WHAT THE PANEL SAYS WHEN THERE IS NOTHING TO SHOW, which is every player until the craft chain
## runs. A heading over an empty space reads as a bug; this says which it is.
static func no_designs_line() -> String:
	return "nothing built yet — mine, smelt and make parts first"


## THE TWO FACTS A SPECIES ROW CARRIES AS STATE, NOT AS PROSE (ASSA-73, Maren's ruling 1).
##
## `hand_minable` and `hand_lit_fuel` are booleans the sim already sends, and they must render as
## LABELLED STATE -- a tag -- never as a sentence this client composed. Two describers for one
## condition is how hosts drift apart, which is the same argument `command_line` and ASSA-58 make.
## So these are short tags on a row, and the SENTENCES about those conditions stay where the sim
## writes them (`reach_note`, the stall line).
##
## ABSENT RATHER THAN NEGATED. A row says what a rock CAN do; "not hand-minable" would be the client
## ranking the roster, which ruling 4 refuses. The player compares six rows and decides.
const TAG_HAND_MINABLE := "hand-minable"
const TAG_HAND_LIT_FUEL := "lights from cold"

## The tags a species row shows, in a fixed order so six rows read as a column rather than a jumble.
static func species_tags(species: Dictionary) -> PackedStringArray:
	var tags := PackedStringArray()
	if bool(species.get("hand_minable", false)):
		tags.append(TAG_HAND_MINABLE)
	if bool(species.get("hand_lit_fuel", false)):
		tags.append(TAG_HAND_LIT_FUEL)
	return tags


## Whether the sheet is exact yet, as the one word the tile line already uses for it.
static func species_sheet_state(species: Dictionary) -> String:
	return "exact" if bool(species.get("assayed", false)) else "rough"


## THE SIX READINGS, IN THE SIM'S OWN ORDER AND THE SIM'S OWN STRINGS (ruling 3).
##
## Each reading is already text: a 25-wide band like "26-50" until the species is assayed, an exact
## number after. This client never parses one, never narrows one, and never sorts the properties --
## the order is whatever `Property::ALL` handed over, so a seventh property appears here with no
## change to this file.
static func species_readings_line(species: Dictionary) -> String:
	var readings: Dictionary = species.get("readings", {})
	var parts := PackedStringArray()
	for property in readings:
		parts.append("%s %s" % [String(property), String(readings[property])])
	return " · ".join(parts)
