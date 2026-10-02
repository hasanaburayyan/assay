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
## Near-black and pure white, which is not fussiness: the crossover luminance where they are equally
## readable is 0.221, and at that point this pair still clears a contrast ratio of 3.8 while
## (0.08, 0.97) would fall to 2.8 -- under the 3.0 that large text has to make.
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
## PURITY IS A MULTIPLIER ON THE SLOT'S OWN VALUE, 0.51 to 1.0 -- a touch under a 2:1 range, where
## the hue-wheel version spanned 2.7:1. Scaling R, G and B together cannot move hue or saturation,
## so the ruling holds by construction rather than by my care.
##
## THE HONEST LIMIT, AND IT IS OPEN WITH COVE: the table's slots do not share one value (purple sits
## at 0.80, yellow at 1.0) because the derivation needed that room, so brightness now carries purity
## AND a little species. Within one species it reads cleanly; comparing the purity of two patches of
## DIFFERENT species by brightness alone it does not. Cove measured the table at full brightness,
## and the map draws it from 0.51 up, so whether the dim end still clears the floor is a question for
## their probe, not for a number I invent here.
static func deposit_color(species: int, purity: int) -> Color:
	# The TABLE bounds the index, not the roster: a species id past the end wraps rather than
	# crashing a frame. `test_sim_binding.gd` is where the sim's roster size and this table's length
	# are held to each other, so the wrap is a seatbelt and never the normal case.
	var tint := Color(SPECIES_TINTS[posmod(species, SPECIES_TINTS.size())])
	# Clamped 0.05 low so a purity-1 patch is still visible, 1.0 high because purity stops at 100.
	var purity_part := clampf(float(purity) / 100.0, 0.05, 1.0)
	var dimmed := 0.5 + 0.5 * purity_part
	return Color(tint.r * dimmed, tint.g * dimmed, tint.b * dimmed, 0.85)


## THE LETTER ON A DEPOSIT: DARK OR LIGHT, whichever the patch underneath can be read against.
##
## Takes the deposit's colour, composites it over the map so the decision is made against what is
## actually on screen (the patch is 85% opaque over a near-black map, and a purity-1 patch of a dark
## species ends up darker than its tint suggests), then picks on luminance. 0.221 is where the two
## glyph colours are equally readable, so it is the only threshold that does not favour one.
static func glyph_color(on: Color) -> Color:
	var lit := MAP_BG.lerp(Color(on.r, on.g, on.b), on.a)
	return GLYPH_DARK if lit.get_luminance() > 0.221 else GLYPH_LIGHT


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
		lines.append("carrying nothing")
		return lines
	for entry in stacks:
		var stack: Dictionary = entry
		lines.append("%d × %s" % [int(stack.get("count", 0)), String(stack.get("name", "?"))])
	return lines


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
		# THE UNASSAYED CUE IS A SENTENCE FOR NOW, on purpose. Grade is the sim's word; whether a
		# rough sheet gets a visual language of its own is Maren's call and I have asked. Until then
		# the honest version is saying what would settle it, because every number about this species
		# is still a 25-wide band.
		lines.append("purity %d (grade %s) · %s" % [int(d.get("purity", 0)),
				String(d.get("grade", "?")),
				"assayed: its sheet is exact" if bool(d.get("assayed", false))
						else "sheet is rough — stand here and assay to be sure"])
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
## Maren's ruling (ASSA-7): UNCERTAIN MUST NOT LOOK LIKE A WARNING. It is exactly half of all designs
## at grade B and it is the advertisement for assaying, so it gets an informational COOL colour, not
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
	# THE ONLY AD ASSAYING GETS. An UNCERTAIN design that could only say "assay something" would read
	# as danger; naming the material turns the doubt into the next thing to do.
	var unassayed := design.get("unassayed", PackedStringArray()) as PackedStringArray
	if unassayed.size() > 0:
		lines.append("assay %s to know" % " and ".join(unassayed))
	# ABSENT, not blank: a planted machine has no durability key, because drill wear is parked and a
	# number that never moves teaches a mechanic that does not exist.
	if design.has("durability"):
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
