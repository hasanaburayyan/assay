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

## WHERE THE HUD COLUMN STARTS, AND IT IS NOT `MARGIN.y` (ASSA-133, Maren's 96px measurement).
##
## `MARGIN.y` is 96 because that is where the MAP starts: the header band above it carries the join
## row, the status line and the detail line. But that band spans the MAP's width, not the window's --
## its controls stop near x 620 and the column's x range is 936..1280 -- so the top-right 347 x 96 of
## the window was 33,312 px of one colour, in a window whose one state surface wants 1746px of a
## 566px clip. Maren measured the first non-background pixel in the column's x-range at y = 96
## exactly.
##
## NOTHING MOVES AND NOTHING IS REWORDED to buy this: the column simply starts where there is nothing
## in its way, which is +96px, about 17% more clip.
##
## IT IS NOT AN EMPTY STATE AND MUST NEVER GET A LABEL (Maren, answering Limpet's question on the
## item). "Every empty surface says which kind of empty it is" is about a surface that HAS a subject
## and nothing to show. This rectangle has no subject: a blank that no section owns is a layout that
## stopped short, and labelling it is the game apologising for its own margin.
const COLUMN_TOP := 8.0

## HOW MUCH OF THE PANEL THE LOG'S TOGGLE TAKES OFF THE TOP (ASSA-89).
##
## The control that shows and hides the event log is PINNED ABOVE THE SCROLL BOX rather than sitting
## in the column it controls. The column is scrolled, and with a full pack, a bench and six species
## rows it is taller than the window: a toggle inside it would be a "visible control" that a stranger
## has to scroll to find, which is the acceptance box read in a way that satisfies nobody.
const LOG_TOGGLE_H := 28.0

## What the map is drawn on. Here rather than in `main.gd` because `glyph_color` has to composite a
## deposit's colour against it to decide whether a letter on top should be dark or light.
const MAP_BG := Color(0.10, 0.11, 0.13)

## THE FOUR MARKS ON A MAP THAT ARE NOT A SPECIES, named, because until now they were six `Color(...)`
## literals inside `main.gd::_draw`.
##
## MAREN'S RULING-3 CORRECTION (ASSA-116, 2026-10-03) IS WHAT THESE ARE FOR, and her finding is worth
## restating because it is not the one she set out to make: there are 21 colour literals in
## `client/scripts/` and nobody chose them as a set. Two near-miss ambers, five cool greys with gaps
## you cannot see. The deliverable she asked for is a named small set and a client that stops holding
## literals. This is that for the map's half; `tools/build_theme.gd` is it for the panels'.
##
## `MINE` IS ONE MEANING AT SEVERAL WEIGHTS: you, and the line to where you are walking. That is the
## leg of her original ruling 3 that survived her own check -- the three yellows really were one
## meaning. What did NOT survive is the targeted tile being a thinner `MINE`: at 9 px a tile the
## weights are indistinguishable and it read as two of something. So `TARGET` is a SHAPE in `INK`'s
## neutral rather than a fifth colour -- corner brackets, drawn by `main.gd` -- and the hover outline
## keeps the thin full-tile box it has always had. Two marks, one hue, no new meaning for a colour.
const MINE := Color(0.95, 0.85, 0.45)
const THEIRS := Color(0.75, 0.78, 0.85)
const HOVER := Color(0.95, 0.95, 0.95)
const SPAWN_PAD := Color(0.35, 0.33, 0.20)

## HOW BIG A BUILDING'S MARK IS, in screen pixels, as a FLOOR under the footprint (Cove, ASSA-193).
##
## A machine is a 1x1 footprint, which is 9 px on the 96x64 world and 4.5 px on a world twice as wide:
## a mark that scales only with the tile disappears exactly as the world gets big enough to need a
## map. So the footprint sets the size and this is the floor.
##
## **16 IS THE SAME NUMBER AS `PLAYER_MARK_PX` AND THAT IS THE POINT, NOT A COINCIDENCE.** Cove's
## reason: a building and a person occupy the SAME BOX, so the SHAPE does all the telling -- and shape
## is the half that survives a greyscale copy, which is what Maren's box asks for. They rendered the
## alternatives: at 14 the diamond reads lighter than a player, at 20 it outweighs one
## (`shared/assay/cove-assa193/assa-193-diamond-sizes-1x.png`).
##
## **AND IT IS A FLOOR, NOT A FOOTPRINT READ.** On this world `_cell` is 9, so the rule gives 16 px
## for a 1x1 and 18 px for a 2x2 -- and Maren's own item says a 2 px difference is not a separation.
## It becomes a read only on a small world (`_cell` 18: 18 px against 36 px). Telling a smelter from a
## drill is not what this view is for.
##
## **I SHIPPED 12 HERE FIRST AND IT WAS NOT A JUDGEMENT CALL I WAS ENTITLED TO** (ASSA-203): I built
## ASSA-189 from my own placeholder and pushed it an hour after Maren settled this, without re-reading
## the item. The old constant argued the floor must stay BELOW the player's 16 "so a one-tile machine
## is not drawn bigger than a person", which is a real concern and is answered by equality, not by
## being smaller: the same box, two shapes.
const BUILDING_MARK_PX := 16.0

## THE KEYLINE ON A MAP MARK, in screen pixels, PERPENDICULAR to the edge it rims.
##
## **IT IS `MAP_BG` AND THAT IS NOT A NEW COLOUR**, which is the whole reason this mark spends no 22nd
## literal (Maren counted 21 on ASSA-116). A ring of the map's own ground colour separates a mark from
## whatever it is standing on, and over open ground it is correctly invisible, because it *is* the
## ground.
##
## **WHAT IT IS FOR IS A DEFECT A PIXEL COUNT COULD NOT SEE** (Cove, ASSA-193). A white mark on a disc
## with a white species letter FUSES INTO ONE BLOB -- the letter stops being a letter -- and the count
## said 63% of the glyph survived. Coverage is not legibility; the picture is what said so.
##
## **NOT `BUILDING_KEYLINE_PX`, WHICH IS WHAT COVE'S HAND-OFF CALLS IT, BECAUSE MAREN'S SECOND RULING
## GAVE IT TO THE PLAYER MARKS TOO** (ASSA-189, 17:40): `THEIRS` is a pale near-white with no keyline,
## so a partner standing on a light letter fuses with it exactly as the keyline-0 diamond did. Same
## thickness, same colour, same reason -- a building-specific name would now be a false one.
const MARK_KEYLINE_PX := 2.0

## THE DEAD-END HATCH'S DENSITY, IN STEPS OF THE `x + y` INDEX, NOT IN PIXELS (Cove, ASSA-187/199).
##
## `(x + y) % HATCH_PERIOD < HATCH_ON` is the rule the sheet Maren ruled on was rendered from, so it
## is the rule here and [hatch_segments] derives its pixel width from it rather than the other way
## round. It covers 2/7 = 28.6% of a disc on paper and Cove measured 22.2-27.1% on real hatched discs
## against 0.0% on solid ones -- the letter and the edge account for the difference.
##
## **RAISED FROM 1-IN-7, WHICH IS A RULING AND NOT A TUNING.** Maren: one line in seven was too quiet
## on a dark red disc. Two densities for two kinds of dead end was offered and REJECTED by Cove: this
## is one bit, and a hatch that came in two strengths would be read as a quantity.
const HATCH_ON := 2
const HATCH_PERIOD := 7

## HOW BIG A PLAYER'S MARK IS ON THE SCHEMATIC, IN SCREEN PIXELS AND NOT IN TILES (ASSA-119 box 6).
##
## It used to be two cells square, which on the 96x64 world is 18 px and on a 32x32 world would be 36.
## Maren measured the consequence on the real shot: the player was 324 px of an 864x576 view, 0.065%
## of it and smaller than all eleven deposits, with one deposit twelve times their size. A mark that
## scales with the tile gets SMALLER exactly as the world gets bigger and harder to find yourself in,
## which is backwards. So it is a constant: on any world, you are this big.
const PLAYER_MARK_PX := 16.0

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

## **THE DISC, CARRIED WITH THE LETTER** (ASSA-213): an outline this many px wide, in the deposit's
## own fill colour, painted under the glyph's strokes.
##
## WHY IT EXISTS. The letter is painted LAST now, over the building marks, because a 16 px diamond on
## a deposit's centre tile was erasing a 25 px letter whole (Maren's two 1x shots). Over its own disc
## that was the end of it; over a `HOVER` diamond it is not, because `glyph_color` picks the ink by
## contrast against the DISC, and `GLYPH_LIGHT` on a pale diamond is the same letter gone for the
## opposite reason. The bed was SPECIFIED to restore the exact surface the ink was measured against,
## locally, so Decision #36's 4.52 worst case would hold over a mark as well as over a rock.
##
## **IT DOES NOT RESTORE THAT SURFACE, AND NO ANTIALIASED BED CAN** (ASSA-218; Cove's arm-C lever
## found it, I re-measured it on main). Every copy of the bed is itself a `draw_string`, so a bed
## pixel gets the glyph's own partial coverage and comes out a BLEND of the fill and whatever is
## underneath -- never the fill. Measured on the real light-ink case (seed 777042, a machine on the
## M at (74,36), white ink on a near-white `HOVER` diamond), the bed as drawn, against the letter:
##
##   the disc's bare fill (41,41,204)   9.20:1   <- what `glyph_color` picked the ink against
##   bed as drawn, outline only         3.23:1   (0 of 47 bed px are the solid fill)
##   bed as drawn, + these 8 stamps     4.35:1   (5 of 63 are) <- shipped, and BELOW the 4.5 floor
##   the machine mark (242,242,242)     1.12:1   <- bare, which is the defect ASSA-218 was filed on
##
## **SO THE GUARANTEE THAT TRANSFERS UNDER A MARK IS AN EDGE, NOT A SURFACE, AND I CLAIMED THE WRONG
## ONE FOR SIX HOURS.** #301 replaced "the outline restores the surface" with "`GLYPH_BED_STAMPS` is
## what makes that claim true (81%)" -- but the 81% is a different bar (below), about whether the
## letter's boundary has a readable edge. It does not say the surface came back, and the table above
## says it did not. Decision #36's 4.52 is a disc-vs-ink number and it stops at the edge of a mark.
##
## What is true: the stamps take the letter's boundary inside a mark from a 4.5:1 edge on 13% of
## itself to 81%, median 3.42:1 -> 8.79:1. A reader gets a letter with an edge; `glyph_color`'s
## measured surround is gone for as long as the mark is over it. This constant is the soft outer rim.
##
## **ON AN UNOCCUPIED DISC IT IS INVISIBLE BY CONSTRUCTION** -- same colour as what is already there --
## so none of the 600 measured states change, and a hatched disc loses only a thin rim around the
## strokes it was already losing to the glyph itself: measured at **0.89-1.32% of a hatched disc's
## interior** against a bed-0 control, with the hatch's density outside the letter's own box unchanged
## to the digit (29.8 / 26.5 / 27.7%).
##
## 2.0 is the width of `MARK_KEYLINE_PX` for the same reason it is 2 there: it is the thinnest rim
## that survives at 1x on this map (Cove's keyline-0 finding, ASSA-193), and a wider one would start
## eating the diamond it sits on.
const GLYPH_BED_PX := 2.0

## **THE BED'S SOLID CORE: the letter stamped once per neighbouring pixel** (ASSA-218, and it is the
## fallback Maren named -- "the string drawn in the bed colour at 8 offsets" -- under the condition
## she set for it, "only if an outline cannot reach the bar").
##
## **THAT CONDITION IS MEASURED, NOT ASSUMED.** On the real light-ink case (seed 777042, a machine
## standing on Minyte at (74,36), white ink on a near-white `HOVER` diamond), the share of the
## letter's boundary inside the mark that has a 4.5:1 edge within 2 px:
##
##   outline 2 px (shipped)   13%   median 3.42:1   <- the defect
##   outline 4 px             81%   median 7.29:1
##   these 8 stamps           81%   median 8.79:1
##   the glyph drawn fatter   58%   median 8.12:1
##   a MAP_BG keyline, 2 px   45%   median 4.35:1   <- Maren's own first ruling, also short
##
## A 4 px outline reaches the same share with one call instead of eight, and it is rejected for the
## reason `MARK_KEYLINE_PX` is 2: a 4 px rim eats the 16 px diamond it sits on. The stamps buy the
## same coverage at a better median without growing the rim.
##
## **AND THESE EIGHT COVER THE DISTANCE-1 RING BY CONSTRUCTION, NOT BY LUCK.** A pixel at distance 1
## from the ink is `q + d` for an ink pixel `q` and a unit offset `d`; the copy displaced by `d`
## paints `{ink + d}`, which contains it. All eight, or a stroke's END keeps bare diagonals.
##
## THE PRICE, STATED: 8 extra `draw_string` calls per letter -- 104 on a 13-letter world, against
## ASSA-214's whole-map median of 42 draw calls. It is the largest thing on this map's bill.
##
## **THAT NEXT MOVE HAS BEEN MADE, TWICE, AND THIS IS WHERE IT LANDED** (ASSA-218 box 9). This said
## "stamp only the letters a mark actually laps", that shipped, and Maren then measured it and
## amended the rule: `main.gd::_glyph_marks` beds a letter that is **lapped OR hatched**, because
## `hatch_ink` and `glyph_ink` can be the same white and the stamps are worth more there (+1.16 to
## +2.43 ratio points) than on the lapped letter (+1.55). On seed 777042 that is 9 letters, **72
## calls of the 104**, and nobody has measured what 72 costs in frame time.
const GLYPH_BED_STAMPS: Array[Vector2] = [
	Vector2(-1.0, -1.0), Vector2(0.0, -1.0), Vector2(1.0, -1.0),
	Vector2(-1.0, 0.0), Vector2(1.0, 0.0),
	Vector2(-1.0, 1.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0),
]

## **EVERY MARK THE WHOLE-WORLD MAP CAN PUT ON SCREEN, IN THE TABLE THE DRAW LOOP ITSELF READS**
## (ASSA-206, Maren's ruling: "the key must be GENERATED from the same table the draw loop reads, so
## a mark cannot be added without appearing in it").
##
## WHY A TABLE AND NOT A LEGEND SOMEBODY TYPED, with the measurement in the item itself: the
## nine-row list in ASSA-206's body was read off `main.gd::_draw` at 9b15fe9 and was ALREADY WRONG a
## few hours later. It names a hollow circle for a dead end, which ASSA-199 replaced with Cove's
## hatch that evening, and it stops before the last two marks in the function -- the acted-on tile's
## brackets and the hover outline. Even the director, counting the draw calls on purpose, produced a
## key that drifted inside a day. A hand-written one is a second copy of the painter.
##
## HOW THE COUPLING IS ENFORCED, because a table that merely sits beside a painter is still two
## things: every colour `_draw` paints with comes through [mark_ink] or [mark_ink_of], and both
## refuse an `id` this table does not carry. `tests/test_map_key.gd` then reads that function's own
## source, paren-matches every `draw_*` call in it, and requires each call to name an entry --
## both ways round, so an entry nothing draws fails as loudly as a mark no entry names.
##
## `in_key` IS NOT AN ESCAPE HATCH, and that matters because it is the obvious way to cheat this.
## The four entries that are not rows of the panel are not marks a player reads: the ground the marks
## sit on, and three `keyed_by` variants (a partner's walk line, and the keylines under a person and
## under a building) whose meaning is another row's. Every entry is either a row or points at the row
## that speaks for it, and that is asserted too.
##
## THE LABELS ARE THIS CLIENT'S WORDS (ASSA-80/93: the sim's sentences stay the sim's). They name the
## FACT, not the shape -- "ore you can work", not "a filled circle" -- because a player reading a key
## has the shape in front of them and wants the other half.
const MAP_MARKS: Array[Dictionary] = [
	{"id": &"ground", "shape": &"ground", "ink": MAP_BG, "in_key": false,
			"label": "the world, out to its edge"},
	{"id": &"spawn", "shape": &"rect", "ink": SPAWN_PAD, "in_key": true,
			"label": "where a joining player appears"},
	{"id": &"deposit", "shape": &"disc", "ink": MAP_BG, "data_ink": true, "in_key": true,
			"label": "ore you can work"},
	# `data_ink` SINCE ASSA-209: the hatch is near-black on a light disc and WHITE on a dark one, so
	# the table's `MAP_BG` is an example and not the colour. `mark_ink_of` is what `_draw` calls.
	{"id": &"dead_end", "shape": &"hatch", "ink": MAP_BG, "data_ink": true, "in_key": true,
			"label": "hatched: nothing can get this ore out"},
	{"id": &"walk_mine", "shape": &"line", "ink": MINE, "alpha": 0.35, "in_key": true,
			"label": "where a player is walking to"},
	{"id": &"walk_theirs", "shape": &"line", "ink": THEIRS, "alpha": 0.25, "in_key": false,
			"keyed_by": &"walk_mine", "label": "where a player is walking to"},
	{"id": &"player_keyline", "shape": &"rect", "ink": MAP_BG, "in_key": false,
			"keyed_by": &"player_mine", "label": "the map's own ink, so a body never fuses with a letter"},
	{"id": &"player_mine", "shape": &"rect", "ink": MINE, "in_key": true, "label": "you"},
	{"id": &"player_theirs", "shape": &"rect", "ink": THEIRS, "in_key": true,
			"label": "another player"},
	{"id": &"mine_ring", "shape": &"ring", "ink": MINE, "in_key": true,
			"label": "the ring is on your own body"},
	{"id": &"building_keyline", "shape": &"diamond", "ink": MAP_BG, "in_key": false,
			"keyed_by": &"building", "label": "the map's own ink, under a machine's mark"},
	{"id": &"building", "shape": &"diamond", "ink": HOVER, "data_ink": true, "in_key": true,
			"label": "a machine someone built"},
	# **AFTER THE BUILDING, AND THE TABLE'S ORDER IS THE PAINT ORDER** (ASSA-213). The letter used to
	# sit between the hatch and the walk lines, which is where it was painted, which is why a machine
	# standing on a deposit erased it. `tests/test_map_key.gd` now holds this list against the order
	# `_draw`'s own calls appear in, so these two rows cannot drift back up without a red suite.
	{"id": &"species_bed", "shape": &"glyph", "ink": MAP_BG, "data_ink": true, "in_key": false,
			"keyed_by": &"species_glyph",
			"label": "the deposit's own colour, carried under its letter"},
	{"id": &"species_glyph", "shape": &"glyph", "ink": GLYPH_LIGHT, "data_ink": true, "in_key": true,
			"label": "the species, as its own letter"},
	{"id": &"target", "shape": &"brackets", "ink": HOVER, "in_key": true,
			"label": "the tile the buttons act on"},
	{"id": &"hover_tile", "shape": &"outline", "ink": HOVER, "alpha": 0.55, "in_key": true,
			"label": "the tile the readout is describing"},
]

## WHAT A MARK IS PAINTED IN, FOR THE MARKS WHOSE COLOUR IS FIXED.
##
## The alpha is the TABLE'S, not the caller's, which is the point of the two weights on a walk line
## living here: `main.gd::_draw` used to build `Color(colour.r, colour.g, colour.b, 0.35)` inline,
## and a weight written at a draw call is a weight the key cannot draw its own sample at.
##
## **AN UNKNOWN `id` IS MAGENTA AND AN ERROR, NOT A CRASH AND NOT A DEFAULT.** A pushed error fails
## the suite, and if one ever reaches a build the mark is painted in a colour this game does not own,
## so it is visible in a screenshot rather than quietly plausible. Returning `MAP_BG` would hide the
## mark on the map's own ground, which is the one wrong answer that looks like nothing happened.
static func mark_ink(id: StringName) -> Color:
	var entry := mark_entry(id)
	if entry.is_empty():
		push_error("no map mark named '%s': add it to AssayHud.MAP_MARKS" % id)
		return Color.MAGENTA
	var ink: Color = entry["ink"]
	return Color(ink.r, ink.g, ink.b, float(entry.get("alpha", 1.0)))


## WHAT A MARK IS PAINTED IN WHEN THE COLOUR IS DATA: a deposit's species tint at its purity, the
## glyph ink `glyph_color` picked for that surface, a building mark's own colour out of
## [building_mark]. The decision stays where it was; this validates that the mark it is for has a row
## in the key and applies the table's alpha, so those marks cannot skip the table either.
static func mark_ink_of(id: StringName, colour: Color) -> Color:
	var entry := mark_entry(id)
	if entry.is_empty():
		push_error("no map mark named '%s': add it to AssayHud.MAP_MARKS" % id)
		return Color.MAGENTA
	return Color(colour.r, colour.g, colour.b, float(entry.get("alpha", 1.0)))


## One entry by `id`, or an empty dictionary. A linear scan over fifteen rows, once per draw call per
## frame: the alternative is a second const dictionary keyed by id, which is a copy of this table.
static func mark_entry(id: StringName) -> Dictionary:
	for entry in MAP_MARKS:
		if StringName(entry["id"]) == id:
			return entry
	return {}


## THE ROWS OF THE KEY PANEL, IN TABLE ORDER. Not a hand-written list and not a sort: the order a
## player reads the key in is the order `_draw` paints in, so the key reads bottom-of-the-stack
## first, which is also the order the marks cover each other in.
static func map_key_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in MAP_MARKS:
		if bool(entry.get("in_key", false)):
			rows.append(entry)
	return rows


## WHICH SPECIES SLOT THE KEY'S ORE SWATCHES BORROW THEIR HUE FROM.
##
## The key is the SHAPE key -- `_species` is the colour one (ASSA-73) and Maren's box 5 says this must
## not displace it -- but a disc has to be drawn in SOME colour, and the one it is drawn in must not
## make the hatch sample a lie. Slot 5 (`#509BE6`) is chosen on Maren's own species sweep (ASSA-209):
## the hatch-to-fill contrast runs 2.60..5.83 there, well clear of the two species where the
## near-black hatch nearly vanishes (purple 1.41, M blue 1.42). The label says what the colour means;
## the swatch only promises the shape. ASSA-209 is the open hole, and a sample drawn on the worst
## species would be reporting that hole as this panel's bug.
const KEY_SAMPLE_SPECIES := 5

## WHAT THE KEY DRAWS A ROW'S MARK IN. The table's ink for the fixed marks; for the three whose colour
## is data at the draw call (a deposit's tint at its purity, the glyph ink `glyph_color` picks for
## that surface, a building mark's own colour out of [building_mark]) an example this panel owns.
static func map_key_sample_ink(entry: Dictionary) -> Color:
	var id := StringName(entry["id"])
	if id == &"deposit":
		return species_tint(KEY_SAMPLE_SPECIES)
	if id == &"species_glyph":
		return glyph_color(species_tint(KEY_SAMPLE_SPECIES))
	# **THE DEAD-END ROW'S SWATCH USED TO COME BACK `MAP_BG` AND THAT MADE THE WHOLE SAMPLE INVISIBLE**
	# (Nerite, ASSA-206, 01:02 EDT: "a flat dark square with no stripe -- the key names a mark it does
	# not draw"). `map_key.gd` painted the swatch's DISC in this colour and then its strokes in the
	# same one, on a patch of `ground` which is also `MAP_BG`: three layers of one near-black, 1.00:1,
	# exactly nothing. The row is a hatch ON a disc, so its ink is the ink the map would use on the
	# sample disc -- which since ASSA-209 depends on that disc's colour.
	if id == &"dead_end":
		return hatch_ink(species_tint(KEY_SAMPLE_SPECIES))
	return mark_ink(id)


## WHAT THE KEY'S TOGGLE SAYS, naming its key like the log's, the crafting menu's and the view's.
static func map_key_toggle_text(shown: bool) -> String:
	return "hide the map key (K)" if shown else "show the map key (K)"


## **WHERE THE SPAWN PAD IS DRAWN, AND IT IS ONE TILE NOW** (ASSA-206 box 7, Maren's ruling on two
## real shots: "it STAYS -- `sim/src/step.rs:71` spawns every joining player on `spawn_tile`, so in a
## co-op demo it is the rendezvous, not trivia -- but it loses its size").
##
## It was `cell * 4` square, centred on the tile: 36x36 px on the 96x64 world, 1296 px, 5.1x the
## player mark and the largest non-deposit mark on the view, for a ONE-tile fact, at 2.22:1 against
## the ground. The biggest mark on the map was also its quietest.
##
## NEVER LARGER THAN A PERSON, which is the clause that makes this a rule rather than a number: a
## tile is 9 px on the test world and would be 18 px on a 32x32 one, where an unclamped tile-sized
## pad would again be bigger than the 16 px body standing on it. Centred on the tile's centre so the
## clamped version still names the same tile.
static func spawn_pad_rect(spawn: Vector2i, cell: float, origin: Vector2) -> Rect2:
	var span := minf(cell, PLAYER_MARK_PX)
	var middle := origin + (Vector2(spawn) + Vector2(0.5, 0.5)) * cell
	return Rect2(middle - Vector2(span, span) * 0.5, Vector2(span, span))


## The tile size the map is drawn at. THE PANEL'S WIDTH COMES OUT OF THE MAP'S WIDTH TERM, which is
## what makes the map shrink instead of hiding under the HUD (Maren's ruling, ASSA-7). Floored to a
## whole pixel so a tile boundary is where a click says it is, and never below 2px: a huge world drawn
## at less than that is unreadable, and at zero it would be undrawable.
static func map_cell(size: Vector2i) -> float:
	if size.x <= 0 or size.y <= 0:
		return 0.0
	var at := world_rect()
	return maxf(2.0, floorf(minf(at.size.x / float(size.x), at.size.y / float(size.y))))


## WHERE THE WORLD GOES: 912x600 at (24, 96), which is 13% / 63% / 24% of the window with the top
## strip and the HUD column (Maren's measurement, ASSA-116).
##
## FACTORED OUT FOR ASSA-119, because there are two views of the world now and they have to occupy
## exactly the same rectangle: the whole-world schematic `map_cell` sizes a tile for, and the scene at
## 32 px a tile that `AssayWorldLayer` clips to. Two copies of this arithmetic would be a scene
## whose click targets are a few pixels off its own picture.
static func world_rect() -> Rect2:
	return Rect2(MARGIN, Vector2(VIEW.x - MARGIN.x * 2.0 - PANEL, VIEW.y - MARGIN.y - 24.0))


## **THE SURFACE THE JOIN SCREEN GETS, WHICH IS ALL OF IT** (ASSA-231, Maren's Gap 5: "one screen,
## one primary action, the empty column not shown at all before a world exists").
##
## `world_rect` subtracts `PANEL` because the HUD column is standing there, and it subtracts the
## margins because a map wants a frame. Before a world exists NEITHER is true: the column is not
## drawn, and there is no map to frame. Centring the door on `world_rect` anyway is what the first
## version of this did, and the shot showed why it is wrong -- a 320 px band of bare window on the
## right where the column used to be, and the one composition on screen sitting off-centre beside
## it. The empty column was replaced by an empty margin.
##
## SO THIS IS THE WHOLE WINDOW, and the join composition is centred in the window a player is
## actually looking at. It is a separate function rather than a branch inside `world_rect` because
## `world_rect` answers "where is the map drawn", which this is not: nothing is drawn here but the
## door, and `visible_tiles` and `player_ceiling` must never see this number.
static func join_rect() -> Rect2:
	return Rect2(Vector2.ZERO, VIEW)


## WHAT THE VIEW'S CONTROL SAYS, naming its key like the log's and the crafting menu's.
##
## IT NAMES WHAT YOU WILL GET, not what you are looking at, which is the same way round as the other
## two toggles on this screen. The words are deliberately about SCALE rather than about a mechanism:
## one view is where you are, the other is the whole world.
static func view_toggle_text(close_up: bool) -> String:
	return "whole world (V)" if close_up else "back to where I am (V)"


## **A REFUSED JOIN NAMES THE STATE THE PLAYER IS ACTUALLY IN** (ASSA-176, Maren's ruling: "a
## sentence claiming a state the player is not in is the class I keep ruling against", as in
## ASSA-129's "5 of your 3").
##
## Both refusal sites in `main.gd` gated on "not IDLE and not DEAD" and said *already joining* for
## all four remaining stages. CONNECTING and GREETED are the two that sentence is about. A player who
## has been in a world for ten minutes was told they were joining -- and after ASSA-175 hides the
## rest of the band, `Join` is the only control left there, so that was about to be the sentence this
## screen says most often.
##
## **THE FIRST CLAUSE IS THE STATE, THE SECOND IS THE WAY OUT, AND THE CALLER OWNS THE WAY OUT.** The
## two sites have different remedies (start a world of your own / change host) and the same two
## states, so the state is the part worth having in one place where `test_hud.gd` can see both
## halves at once.
##
## THE REMEDIES CAME ACROSS UNTOUCHED, INCLUDING "no reconnect in the demo" -- which I said out loud
## I believed and had not measured. **IT WAS FALSE** (ASSA-177): `tools/reconnect_probe.gd` presses
## Join after a real drop and gets back into the same slot in a running world, so that clause is gone
## from `_join_address` and what is left ("restart the client to change host") is true in both stages
## this sentence can reach. Worth keeping in view: the clause survived two items BECAUSE it read like
## a settled fact, and the only reason it was ever checked is that I wrote down that it was not one.
static func join_refusal(joined: bool, remedy: String) -> String:
	return "%s; %s" % ["already in a world" if joined else "already joining", remedy]


## **A HOST THAT WENT QUIET WITHOUT CLOSING THE SOCKET** (ASSA-179). Three parts, like every refusal
## on this screen: what stopped, the measurement behind the claim, and the door that is open.
##
## **THE WORDS AND THE NUMBER ARE THE GAME DIRECTOR'S** (ASSA-179 part 2, not ruled when this shipped).
## They are here rather than inline in `net_client.gd` with that file's four other failure sentences
## for one reason: a sentence with no test is how ASSA-176 happened, and this file exists so a wording
## ruling is a one-line change with `test_hud.gd` holding it. The inconsistency with those four is
## real and deliberate -- they are untouched, and this is not an argument for moving them.
##
## "went quiet" and not "disconnected": the socket is still open, which is the entire reason this case
## needed a clock of its own. `seconds` is the threshold that elapsed, not a guess at when the host
## died -- the honest claim is about what this client waited, and it cannot know the other.
##
## THE SECOND SENTENCE IS THE PART THAT MATTERS AND IT IS TRUE ONLY SINCE ASSA-177: pressing Join at
## this point rejoins the same `PlayerId` in the running world, measured both ways round by
## `tools/reconnect_probe.gd`. Without it a player reads that the link is dead and has no reason to
## believe the one visible control does anything.
static func silent_host_line(where: String, seconds: int) -> String:
	return ("%s went quiet: nothing from it for %ds. Press Join to get back into the same slot."
			% [where, seconds])


## **THE WORD AT TWO SECONDS, WHICH IS NOT THE SENTENCE AT TEN** (ASSA-191). Maren's wording,
## verbatim, and the differences from `silent_host_line` above are all hers and all deliberate.
##
## **IT NAMES NO ADDRESS AND NO CONTROL, and both omissions are the point.** This is reversible: no
## stage change, no band, Join still refused, and the line goes the moment a bundle lands. So it must
## not read like news -- a sentence naming a host and a button is a sentence about a decision this
## client has not made yet. "the host" and a number going up is all a player can act on anyway: they
## cannot check "the network", but they can see that the count is climbing and know it is not them.
##
## WHOLE SECONDS, and the count is the gap rather than the threshold -- see
## `AssayNetClient.quiet_seconds` for why a 2900ms gap must read as "2s".
static func quiet_host_line(seconds: int) -> String:
	return "the host has gone quiet — nothing for %ds" % seconds


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


## **WHAT ONE SCHEMATIC DISC IS, INCLUDING WHETHER THE ROCK IS WORTH THE WALK** (ASSA-187, Maren's
## ruling: "a deposit you cannot work must be distinguishable from one you can, on the schematic
## itself, and not by colour"). 25.4% of deposits over 16 seeds are rock nothing can mine, and they
## were drawn exactly like the ones that pay.
##
## **A HATCH, AND THE DISC STAYS SOLID** (Maren's ruling on Cove's sheet, ASSA-199 box 2; it replaces
## the hollow disc ASSA-187 shipped in #259). Colour is the species slot, brightness is purity, radius
## is the deposit's radius -- Decision #36 and ASSA-119 box 6 spend those three between them -- so the
## fourth fact gets GEOMETRY, which is the half of the ruling no dimming or re-tinting could keep.
##
## **WHY NOT THE OUTLINE #259 SHIPPED, WHICH WAS MINE AND WAS NOT WRONG SO MUCH AS EXPENSIVE.** An
## outline spends the fill, and the fill is carrying two channels already: a hue at a few per cent
## coverage reads as grey, and brightness IS the purity channel. The hatch repaints a share of the
## interior and leaves radius and purity at full strength. Maren judged both at 1x on
## `shared/assay/cove-assa187/assa-187-hatch-2026-10-04.png` and ruled the hatch, with the density
## raised from 1-in-7, which was too quiet on a dark red disc.
##
## **THE INK IS THE MAP'S OWN GROUND AND THAT IS NOT A NEW COLOUR**, the same argument as the building
## mark's keyline one function down: a mark made of the surface a disc sits on cannot be read as a
## sixth species.
##
## **`reach_note` AND NOT `hand_minable`, WHICH IS MARLOW'S CORRECTION OF HIS OWN ITEM.**
## `hand_minable` catches only "too hard to mine" and marks 6 of 13 discs on 777042; there are 8 dead
## ends, because a rock can be minable and still unsmeltable, and those two drew exactly like good ore
## -- ASSA-187's defect surviving its own fix. `sim-godot`'s own comment says the two "are no longer
## opposites". Maren's rate over 30 seeds and 423 deposits: 38.8% too hard, 16.3% minable-but-dead,
## **55.1% dead**. The mark landing on the majority is fine because a hatch is SUBTRACTIVE -- the
## clean disc becomes the signal -- and it is still one bit, so Cove's two-density rejection stands.
##
## `reach_note` IS READ WITHOUT A DEFAULT (ASSA-141). A binding that stopped sending it must empty the
## frame rather than draw every dead end as a patch worth a 40-tile walk; `test_sim_binding.gd` is
## what notices first. It is the sim's own wording, from `debug::deposit_dead_end_note`, and empty
## means the rock pays -- this reads whether there IS a note and never what it says, because the
## sentence is `sim::debug`'s to word and the map's job is one bit.
static func deposit_disc(deposit: Dictionary, drawn_radius: float) -> Dictionary:
	var colour := deposit_color(int(deposit["species"]), int(deposit["purity"]))
	var dead_end := not String(deposit["reach_note"]).is_empty()
	# **THE LETTER IS JUDGED ON THE FILL, AND ASSA-213 IS WHY THAT IS TRUE AGAIN.** I had this asking
	# `glyph_color` about `hatched_surface(colour, ink)` -- the fill mixed 28.6% toward the hatch --
	# on the reasoning that a hatched disc is not the surface the ink was picked against. Cove measured
	# exactly that on ASSA-199's box 6 (a `MAP_BG` hatch costs a dark letter 30-36%) and it lifted the
	# worst letter over 600 states from 2.94:1 to 4.51:1.
	#
	# **IT WAS REPLACED, because #293 landed a bed while this branch was open** -- every letter carries
	# `GLYPH_BED_PX` of its own DISC COLOUR plus `GLYPH_BED_STAMPS` under its strokes, painted last.
	# The reasoning for dropping the relight was that the bed restores the bare fill, so relighting
	# would pick an ink for a surround the letter no longer has.
	#
	# **THAT PREMISE IS MEASURED FALSE AND THE DROP IS THEREFORE UNJUSTIFIED AS WRITTEN** (Cove,
	# ASSA-199, re-measured by me on main: `shared/assay/marlow-assa218-bedclaim/`). A bed copy is
	# itself an antialiased `draw_string`, so a bed pixel is a BLEND of the fill and what is under it.
	# On this seed's eight hatched discs the bed closes about a QUARTER of the gap to an unhatched
	# disc at distance 1 and nothing at distance 2, and the worst letter:surround is 2.33:1 -- the
	# relight's own 4.51:1 was measured against the bare fill, which is not what gets drawn.
	#
	# **WHAT IS NOT DECIDED HERE, ON PURPOSE.** Whether the relight comes back is a design call with
	# a price (it re-picks ink per disc, so a letter can change colour when a rock turns out dead) and
	# it is Maren's, on ASSA-199. This comment is only corrected to stop asserting the premise.
	# **The ASSA-209 residual it claimed to retire is NOT retired on the same arithmetic**: the hatch
	# and the letter can be the same white, and the bed between them is a blend, not a separator.
	return {"colour": colour, "filled": true, "ink": glyph_color(colour),
			"hatch": dead_end, "hatch_ink": hatch_ink(colour),
			"hatch_width": float(HATCH_ON) / sqrt(2.0),
			"stroke": clampf(drawn_radius * 0.2, 2.0, 6.0)}


## **WHAT A DEAD-END HATCH IS PAINTED IN: NEAR-BLACK OR WHITE, WHICHEVER THE DISC CAN SHOW** (ASSA-209).
##
## **IT WAS ONE FIXED `MAP_BG` AND THE MARK'S LEGIBILITY WAS THEREFORE A PROPERTY OF THE DISC, WHICH
## THE MARK DOES NOT CHOOSE.** Maren found it while judging ASSA-199 and ruled the bar: the worst
## species pair, never the shipped seed. Measured out of this file by `tools/hatch_ink_sweep.gd` over
## all 6 x 100 states:
##
## ```
##                             worst hatch:fill   worst letter:surround
## one fixed MAP_BG (shipped)        1.42:1               2.94:1
## this, MAP_BG or GLYPH_LIGHT       4.13:1               4.51:1
## ```
##
## At 1.42:1 a dark-on-dark hatch is not subtle, it is ABSENT, and the disc then says "good ore" to a
## player who cannot mine or smelt it -- the exact defect ASSA-187 and ASSA-199 exist to kill. Purple
## and M-blue are 51.4% and 54.5% dead across 400 worlds and **79% of worlds hold at least one**
## (Maren's sweep), so it is the common case and not an edge.
##
## **`MAP_BG` AND NOT `GLYPH_DARK` AS THE DARK HALF, so the mark still spends no new literal** (Maren
## counted 21 colours on ASSA-116). It also keeps every disc that reads today reading exactly as it
## does: on the four bright species the pick is unchanged from the shipped ink at most purities.
##
## **THE ONE THING IT COULD HAVE COST, AND WHY IT DOES NOT.** Where the hatch goes white the letter
## often wants to be white too -- both are "the brightest thing available on a dark disc" -- so
## hatch-against-letter is **1.00:1**, the same ink, on purple at purity 1. I filed that as this
## item's residual and then #293 (ASSA-213) retired it from the other side: a letter carries
## `GLYPH_BED_PX` of its own disc colour under its strokes, so there is fill between the mark and the
## letter whatever the two inks are. Two marks of one colour that never touch do not fuse.
static func hatch_ink(fill: Color) -> Color:
	return MAP_BG if contrast_ratio(fill, MAP_BG) >= contrast_ratio(fill, GLYPH_LIGHT) \
			else GLYPH_LIGHT



## THE HATCH'S LINES FOR ONE DISC: flat pairs of points, each pair one 45-degree stroke.
##
## **THE RULED DENSITY IS `HATCH_ON` IN `HATCH_PERIOD` ALONG `x + y`, AND COVE'S PROSE AND COVE'S
## SHEET DISAGREE ABOUT WHAT THAT IS IN PIXELS.** Their hand-off says "45 degrees, 2px wide, every 7px
## along x+y". Those are two different widths: the sheet Maren actually ruled was rendered by
## `cove_187_hatch.py` from the PIXEL rule `(x + y) % 7 < 2`, which covers exactly 2/7 = 28.6% of a
## disc, and they measured 22.2-27.1% on real hatched discs. A stroke 2px wide PERPENDICULAR, spaced
## 7/sqrt(2) = 4.95px apart, would cover 40% -- half again as much ink as the picture she approved.
## **So the rule here is the sheet's and the width is derived from it**: a band of `HATCH_ON` steps in
## the `x + y` index is `HATCH_ON / sqrt(2)` px across, because that index advances by sqrt(2) for
## every pixel of perpendicular travel. The measurement is the arbiter -- `assa187_measure.py` on a
## real shot has to land in Cove's band, and 40% would not.
##
## **THE CHORD IS CUT AT `radius - halfwidth`, NOT AT `radius`.** Godot's `draw_line` is a quad, so a
## stroke ending exactly on the circle pokes its corners outside it, and Cove's constraint is that the
## hatch only ever repaints pixels already inside the disc -- which is what leaves the antialiased
## edge and the species letter alone BY CONSTRUCTION rather than by a clip nobody can see in a test.
static func hatch_segments(at: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var half_width := float(HATCH_ON) / sqrt(2.0) * 0.5
	var inner := maxf(0.0, radius - half_width)
	# `x + y` at the centre, and how far it ranges over the disc: the index moves sqrt(2) per pixel.
	var sum := at.x + at.y
	var reach := radius * sqrt(2.0)
	var normal := Vector2(1.0, 1.0).normalized()
	var along := Vector2(1.0, -1.0).normalized()
	for step in range(int(floorf((sum - reach) / float(HATCH_PERIOD))),
			int(ceilf((sum + reach) / float(HATCH_PERIOD))) + 1):
		# The BAND's middle, not its first line: `(x + y) % P < ON` covers [m*P, m*P + ON).
		var band := float(step * HATCH_PERIOD) + float(HATCH_ON) * 0.5
		var offset := (band - sum) / sqrt(2.0)
		if absf(offset) >= inner:
			continue
		var reach_along := sqrt(inner * inner - offset * offset)
		var foot := at + normal * offset
		out.append(foot - along * reach_along)
		out.append(foot + along * reach_along)
	return out


## **WHAT ONE BUILDING IS ON THE SCHEMATIC** (ASSA-189, Maren's P1: "the whole-world view draws no
## factories, so in a co-op automation game neither player can see what either has built").
##
## `_sim.buildings()` occurred exactly once in `main.gd` and it was inside the close-up's view
## dictionary, so the schematic was never handed a building to draw. It is the view you cross 96x64
## tiles on and the view that carries a player you are nowhere near, which makes it the one surface
## co-op needs: you could not find your own base and you could not see your partner's.
##
## **A DIAMOND, BECAUSE MAREN RULED OUT BOTH SHAPES THIS MAP ALREADY USES.** Her own first direction
## here was `draw_rect` and she counted it out: `_draw` uses a rect for the background, the spawn pad,
## a player's body, your ring and the hovered tile, and `draw_circle` for a deposit. At 9 px a tile a
## 2x2 building to scale is 18 px against the player's 16 px mark, so a filled rect would be **the
## player's shape at the player's size separated only by hue** -- on the one view co-op exists for,
## and against her own rule that the distinction is SHAPE and must survive a greyscale copy. A
## diamond's points are at the footprint's edge midpoints and its corners are empty, so it is neither
## of the two: half the bounding box's area, where a rect is all of it and an inscribed circle 78.5%,
## and the 45-degree point a circle contains is OUTSIDE it. `tests/test_hud.gd` asserts both of those
## as geometry rather than as taste.
##
## **THE COLOUR AND THE SIZE ARE COVE'S AND APPROVED, AND MINE WERE NEITHER** (ASSA-193, approved by
## Maren at 1x on `assa-193-building-mark-proof.png`; the conformance bill is ASSA-203). `HOVER` with a
## `MARK_KEYLINE_PX` rim of `MAP_BG`, at `BUILDING_MARK_PX` or the footprint, whichever is bigger. What
## I shipped first was a green of my own at a 12 px floor with a 1.08 px polyline -- a 22nd colour
## literal on a map whose named set exists precisely to stop that, when the shape Cove picked needs no
## new hue at all. The rim is what makes the white affordable: a drill is planted ON a deposit, so this
## mark is drawn over a bright species tint as often as over the background.
##
## **THE KEYLINE IS A PERPENDICULAR THICKNESS AND THE ARITHMETIC IS NOT THE OBVIOUS ONE.** A diamond's
## edge sits `h/sqrt(2)` from its centre, so growing the DIAGONAL by `2t*sqrt(2)` grows the rim by `t`:
## Cove's note, and a "2 px keyline" written as `span + 4.0` would really be 1.41 px. It is a SECOND
## POLYGON under the first, not a stroke on the first, because a stroke straddles the edge it is given
## and would eat a pixel of the mark to pay for a pixel of rim.
##
## **`pos` AND `footprint` ARE READ WITHOUT A DEFAULT** (ASSA-141's rule, and ASSA-196's bill for
## breaking it on players): `pos` is the TOP-LEFT of the footprint and a binding that stopped sending
## either must empty the frame rather than draw every factory in the world on top of each other at
## the corner. `tests/test_main_screen.gd` is what notices. Cove's hand-off sketches these with
## `get(..., Vector2i.ONE)`; that is the one line of it I did not take, and the reason is that rule.
static func building_mark(building: Dictionary, cell: float, origin: Vector2) -> Dictionary:
	var pos: Vector2i = building["pos"]
	var foot: Vector2i = building["footprint"]
	# SQUARE, off the LONGER side, and not per-axis: Cove's rule is one `s`. A per-axis floor turns a
	# footprint that is not square into a rhombus, which states a facing the sim does not have -- the
	# reason their chevron candidate lost.
	var span := maxf(float(maxi(foot.x, foot.y)) * cell, BUILDING_MARK_PX)
	# The footprint's CENTRE, from its top-left corner tile plus half its extent in tiles, so a 2x2
	# sits on the join of its four tiles and a 1x1 in the middle of its one.
	var at := origin + (Vector2(pos) + Vector2(foot) * 0.5) * cell
	return {
		"points": diamond(at, span),
		"colour": HOVER,
		"keyline_points": diamond(at, span + 2.0 * MARK_KEYLINE_PX * sqrt(2.0)),
		"keyline": MAP_BG,
		"at": at,
		"span": Vector2(span, span),
	}


## A diamond of diagonal [param span] about [param at]: points at the edge midpoints, corners empty.
##
## Here rather than in `main.gd::_draw` for [deposit_disc]'s reason -- nothing in a headless suite can
## read a `draw_colored_polygon` back off a canvas, so geometry computed inside the paint loop is
## checkable only by a human looking at a PNG, which is how the schematic went a month with no
## factories on it.
static func diamond(at: Vector2, span: float) -> PackedVector2Array:
	var h := span * 0.5
	return PackedVector2Array([at + Vector2(0.0, -h), at + Vector2(h, 0.0),
			at + Vector2(0.0, h), at + Vector2(-h, 0.0)])


## The area of [param points] by shoelace, so a mark that grew a fifth point is measured and not assumed.
static func polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var sum := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5


## **WHICH MACHINES STAND ON THE TILE A SPECIES LETTER NAMES** (ASSA-213 box 2: "the case is in a shot:
## a building placed on a deposit CENTRE, not on its edge -- today's shots cannot report this absent").
##
## **THIS IS THE SIM'S QUESTION AND [method letter_occlusions] IS THE PAINTER'S, AND A SHOT NEEDS BOTH.**
## Pixels alone cannot tell "no machine was on a rock today" from "a machine was on a rock and the map
## did not mark it" -- the first is a world the play loop did not reach and the second is ASSA-189
## exactly. Asking the sim for the case and the painter's own marks for the collision separates them,
## and that separation is the whole of box 2: a shot can now report the case ABSENT.
##
## `pos`, `footprint` and `tile` ARE READ WITHOUT A DEFAULT (ASSA-141), like [method building_mark]:
## a binding that stopped sending a footprint must empty the frame rather than quietly answer "no
## machine is on a letter" for every world, which is the answer that reads as good news.
##
## [param letter_marks] is `main.gd::_glyph_marks`' own list, so the tile compared here is the tile the
## letter is actually drawn on rather than a deposit this function picked out of the sim for itself.
static func machines_on_letters(buildings: Array, letter_marks: Array) -> Array:
	var out := []
	for i in buildings.size():
		var building: Dictionary = buildings[i]
		# INCLUSIVE OF `pos`, EXCLUSIVE OF `pos + footprint`, which is `Rect2i.has_point` -- a 2x2 at
		# (56,58) holds (56,58)..(57,59) and a letter at (57,59) is INSIDE it. That corner is the case
		# Cove's enumeration found worst (24.9-56.2% of the letter's ink), so an off-by-one here would
		# report the worst placement in the game as not-in-frame.
		var foot := Rect2i(building["pos"] as Vector2i, building["footprint"] as Vector2i)
		for j in letter_marks.size():
			var letter: Dictionary = letter_marks[j]
			var tile: Vector2i = letter["tile"]
			if foot.has_point(tile):
				out.append({"building": i, "letter": j, "tile": tile,
						"symbol": String(letter["symbol"]), "kind": String(building["kind"])})
	return out


## **HOW MUCH OF EACH SPECIES LETTER A MACHINE'S MARK LANDS ON**, in the frame's own geometry (ASSA-213).
##
## IT REPORTS A COLLISION AND NEVER A VERDICT. Since this item the letter is painted LAST, so an
## overlap is no longer an erasure -- it is the STATE the fix exists for, and a shot containing one is
## a shot that can be judged. Whether the letter survived is a pixel question about a PNG (Maren's box
## 1 and her control), and nothing in here may be read as answering it.
##
## THE BOX IS THE CAP BOX. `_glyph_marks` leaves the descent out on purpose -- `symbol` is one capital
## -- because a box reserving room for a descender says a mark lands on the letter when it lands under
## it. My first premise for this item measured the share of the letter's BOX the diamond covered (9.3%)
## and called the case absent; the diamond's own share was 99.3%. **Both are reported here**, named,
## for that reason: `share_of_box` is how much of the letter is at risk, `share_of_mark` is how much of
## the mark is spent on it, and only the first is a number about the letter.
static func letter_occlusions(building_marks: Array, letter_marks: Array) -> Array:
	var out := []
	for i in building_marks.size():
		var mark: Dictionary = building_marks[i]
		var points: PackedVector2Array = mark["points"]
		var mark_area := polygon_area(points)
		for j in letter_marks.size():
			var letter: Dictionary = letter_marks[j]
			var box: Rect2 = letter["box"]
			var box_area := box.size.x * box.size.y
			if box_area <= 0.0 or mark_area <= 0.0:
				continue
			var covered := 0.0
			for piece in Geometry2D.intersect_polygons(points, PackedVector2Array([box.position,
					Vector2(box.end.x, box.position.y), box.end,
					Vector2(box.position.x, box.end.y)])):
				covered += polygon_area(piece as PackedVector2Array)
			if covered <= 0.0:
				continue
			out.append({"building": i, "letter": j, "symbol": String(letter["symbol"]),
					"covered_px": covered, "share_of_box": covered / box_area,
					"share_of_mark": covered / mark_area})
	return out


## The `MAP_BG` keyline behind an axis-aligned mark: [param body] grown by `MARK_KEYLINE_PX` all round.
##
## **MAREN'S SECOND RULING ON ASSA-189, AND IT IS A DEFECT THAT SHIPS TODAY, NOT A POLISH ITEM.**
## `THEIRS` is a pale near-white and a player's body carries no rim, so a partner standing on a deposit
## with a light species letter FUSES WITH THAT LETTER INTO ONE BLOB -- the same failure Cove's
## keyline-0 diamond made before they added the rim, found while they were hunting for a control
## (`shared/assay/cove-assa193/assa-193-player-vs-mark-on-a-letter-3x.png`, panel 3).
##
## **IT GROWS OUTWARDS, SO THE BODY IS UNTOUCHED IN PIXELS.** `PLAYER_MARK_PX` stays 16 and the mark
## occupies 20; the alternative is a rim paid for out of the body, which would quietly re-tune a size
## Maren set from a measurement (ASSA-119 box 6). Your own 1.6x hollow ring sits at 12.8 px from the
## centre and so is clear of the rim's 10 px at every tile size.
static func mark_keyline_rect(body: Rect2) -> Rect2:
	return body.grow(MARK_KEYLINE_PX)


## The status line's colour for a state. Neutral idle, amber connecting, red failed, quiet joined.
##
## **`JOINED` WAS THE ACCENT GREEN AND IS NOT ANY MORE** (ASSA-233, Maren's ruling 3). Since ASSA-224
## the accent means ONE thing -- *press this* -- and it is spent on the single `Primary` control on
## the screen. A green `Play solo` and a green `· submitted at tick 514` in the same frame is one
## colour doing opposite work, which is the two-vocabularies defect her own direction doc condemns.
## Her words: "it is a readout, not an action, and nothing is lost -- the line already says the word
## submitted".
##
## **IT IS SEVEN READOUTS, NOT THE ONE SHE NAMED, and that is deliberate.** `Say.JOINED` also paints
## "joined as player N", "acting on x, y", "walking to x, y" and the link's own notes. Her ruling is
## stated as a rule -- *no accent outside a button* -- so fixing only the clause in the shot would
## leave the rule false everywhere else in the same screen, and the next readout added would be
## green again. `test_no_status_colour_is_the_themes_accent` is what holds it.
##
## **THE VALUE IS `build_theme.gd`'s `INK_MUTED`, PINNED BY A TEST RATHER THAN BY THIS COMMENT.**
## This file cannot import the theme generator -- the generator imports THIS file for
## `contrast_ratio` -- so the number is typed here and asserted equal there, which is the arrangement
## `SURFACE` and the old `ACCENT` already had.
static func status_color(level: int) -> Color:
	match level:
		Say.CONNECTING:
			return Color(0.95, 0.75, 0.35)
		Say.FAILED:
			return Color(0.95, 0.40, 0.35)
		Say.JOINED:
			return Color(0.655, 0.690, 0.745)
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


## What the event log says before the world has said anything (ASSA-117). A blank section reads as a
## game with nothing to say, which is not the same news as a world that has not spoken yet -- the
## same distinction `halted_table` makes between "nothing has stopped" and "you have built nothing".
##
## THIS IS NOT ONE OF THE SIM'S SENTENCES AND IT IS NOT DESCRIBING AN EVENT. It is what the section
## says in the absence of events, so there is no wording of the sim's for it to be a second copy of.
##
## **AND THERE ARE TWO KINDS OF EMPTY HERE, NOT ONE** (ASSA-186, Maren's wording). "Nothing has
## happened yet" is true in a world that has not spoken; on the join screen it is an answer about a
## world that does not exist, and the section is the first thing a stranger presses (L) on. The
## no-world half mirrors `do`, the one section that was already right, rather than adding a sixth
## literal "no world yet" to a screen `main.gd` says already carries five.
##
## `in_world` IS A REQUIRED ARGUMENT AND THAT IS THE POINT. The three sections that got this wrong
## had one wording each and a caller with nothing to decide, so nobody could notice the state was
## missing; a caller that cannot compile without answering "which kind of empty" is the only shape
## that stops the next section shipping the same defect.
static func quiet_log_line(in_world: bool) -> String:
	if not in_world:
		return "join a world and what happens is listed here"
	return "nothing has happened yet"


## WHAT THE `cursor` SECTION SAYS BEFORE THERE IS A WORLD (Maren's ruling, ASSA-134; she measured it
## at 93px of labelled void on the first screen a stranger sees, the largest in the column).
##
## `_note`'s own rule, which five sections honoured and this one did not: a heading with nothing under
## it reads as a bug. `cursor` needed it most, because it is the one heading whose NAME does not tell
## a stranger what it would ever contain -- `you`, `bench` and `rocks` all do.
##
## THE WORDS ARE MAREN'S OWN SUGGESTION, kept rather than improved: it is the shape `rocks` already
## uses ("no world yet — ...") and the second clause answers the question the heading raises.
static func quiet_cursor_line() -> String:
	return "no world yet — this reads the tile under your mouse"


## WHAT THE MAP ITSELF SAYS BEFORE THERE IS A WORLD (Maren's ruling 1, ASSA-127).
##
## **THE RULE WAS KEPT EVERYWHERE IT WAS CHEAP AND DROPPED WHERE IT WAS BIG.** Six surfaces in the
## HUD column name which kind of empty they are, [quiet_cursor_line] among them. The seventh is
## **59% of the window**, measured twice at 543,180 px of one colour, and said nothing at all -- and
## it is the only one a stranger looks at first. A dark rectangle filling a freshly downloaded window
## is also what a failed launch looks like: two engineers here each spent a wake-up believing this
## window never opened.
##
## **THE WORDS ARE THE ONES THAT WERE ALREADY ON SCREEN**, per her "keep the existing words". They
## were in the status line at (24,54) -- ~1.5% of the window, above the thing being explained. This
## is one sentence in one place, and that place is where a stranger is already looking.
##
## IT IS NOT A HEADING'S NOTE, so it carries both doors rather than the shape the six use: there is
## nothing above it to name what it would contain.
static func empty_map_line() -> String:
	return "Press Play solo to start your own world, or enter a host address to join someone."


## EVERY VERB A STACK AFFORDS, as descriptors for the row's buttons: `{label, verb, ...}`.
##
## **WHAT YOU HAVE AND WHERE IT CAN GO -- NEVER WHAT IT MAKES** (ASSA-86, Maren's ruling). A row
## keeps the verbs that MOVE an item: Fuel, Smelt, Place, Frame/Mount. Two or three, never seven.
## Everything that MAKES something is in the crafting menu (ASSA-88), because a make-verb belongs to
## a RECIPE and a stack cannot say which species a shared label would make.
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
## **IT NO LONGER TAKES THE SCREEN'S STATE, AND THAT IS THE FIX** (ASSA-103). It used to take
## `building` -- whether an assembly was part-way built -- and turn one word on it, which made every
## part row's verb a claim about the player's progress instead of about the item. A kind's word comes
## from `is_frame` now, so the argument is gone rather than ignored: a parameter nobody reads is an
## invitation to start reading it again.
## `footprint` is `AssaySimHost.footprint_of_item`, so "is this placeable" is also the sim's answer.
static func stack_verbs(stack: Dictionary, recipes: Array, part_kinds: Array,
		footprint: Vector2i) -> Array:
	var kind := String(stack.get("kind", ""))
	var verbs := []
	for entry in recipes:
		var recipe: Dictionary = entry
		if String(recipe.get("input", "")) != kind:
			continue
		# A HAND RECIPE IS NOT THIS ROW'S BUSINESS ANY MORE (ASSA-86, Maren's ruling). `Craft <name>`
		# used to be appended here, which is how an ore row grew four verbs and a refined row seven
		# inside a 320px column -- and worse, how a pack holding two species drew TWO buttons both
		# labelled exactly `Craft smelter`, building smelters with different walls. A make-verb
		# belongs to a RECIPE, so putting it on a stack duplicates it per species and the label
		# cannot say which. It lives in the crafting menu now (ASSA-88), where a row names what it
		# makes by species and grade.
		#
		# THE LOOP STAYS, because the NON-hand half of it is how this file knows a smelter eats this
		# kind of item at all. That is a sheet reading and only the sim has it.
		if bool(recipe.get("hand", false)):
			continue
		if not _has_verb(verbs, "insert"):
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
		# `Make <kind>` USED TO BE HERE AND IS NOW IN THE CRAFTING MENU (ASSA-86/88, Maren's
		# ruling): the pack is what you HAVE and where it can GO; everything that MAKES something
		# left it. One `Make` per part kind on every refined row is four of the seven verbs that
		# made the worst row in the game the one a player lives in.
		#
		# And the row for a part itself offers the way into an `Assemble`. The first part added is
		# the frame, so the word changes rather than the button.
		if String(part.get("name", "")) == kind:
			# **THE WORD BELONGS TO THE KIND, NOT TO WHERE THE PLAYER HAS GOT TO** (Maren, ASSA-103).
			# This read `"Mount" if building else "Frame"`, so a head said `Frame` until something was
			# chosen and `Mount` afterwards -- and both were refused, because a head is never a frame
			# and a frame is never mounted. Cove's `pack_rows.png` showed it as a swap: in each state
			# exactly two of four rows are pressable and never the same two.
			#
			# `is_frame` IS THE SIM'S FIELD (ASSA-102), so this derives nothing and a fifth part kind
			# labels itself. It is carried into the descriptor as well, because the button's tooltip
			# makes the same claim in a longer sentence and two renderings of one fact must not be
			# free to disagree.
			var is_frame := bool(part.get("is_frame", false))
			verbs.append({"label": "Frame" if is_frame else "Mount", "verb": "build",
					"is_frame": is_frame})
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
		# **`clear ground`, NOT `empty ground`** (Maren's ruling, ASSA-146 comment of 15:07Z). This
		# line and the sim's `ground_note` are two subjects -- where a BUTTON will act, and what the
		# ROCK is -- so they must not merge, and they may not share words either. `empty ground` is
		# the exact phrase ASSA-146 deleted from the sim for carrying two facts, and it sat here on
		# the same screen as its own replacement: a player reading `cursor > no deposit here` in one
		# section and `acting on (76, 38) · where you stand · empty ground` in another cannot tell
		# whether those describe the same tile state, and the more definite-sounding one is the one we
		# removed for being ambiguous. It was not FALSE here -- the building is tested first in the
		# same expression -- which is why it survived the item that killed the phrase.
		#
		# `clear` keeps what this line is for: Place lands there, Insert and Take do not.
		what = "clear ground" if tile_facts.get("deposit") == null else "on a deposit"
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
	else:
		# THE GROUND IS THE SIM'S WORD, NOT THIS FILE'S (Maren, ASSA-146). This block spelled out
		# `spawn` / `empty ground` itself, and so did sim-cli's `at` and the inspector's tile panel
		# -- three copies of one sentence, and the bare one was WRONG here: it called the tile empty
		# on the line directly above the smelter standing on it, because the building below is
		# appended by a block that does not know this one ran. `ground_note` is about ROCK and only
		# rock ("no deposit here"), so it has nothing left to contradict. Same contract as
		# `reach_note` above: EMPTY means the sim has nothing to say, and an empty line in a readout
		# of four is a line a player has to account for.
		var ground := String(tile.get("ground_note", ""))
		if ground != "":
			lines.append(ground)

	# A BUILDING IS NAMED THE WAY EVERY OTHER OBJECT IS (Maren, ASSA-136): `Tonore smelter (A)`,
	# not `smelter`. The words are the sim's -- `debug::building_name`, the same call the halted
	# table and sim-cli's tile line make -- because the species in that name is the one that caps
	# the fire and the one that comes back in your pack, and two surfaces spelling it apart is how
	# ASSA-43 and ASSA-52 happened. `kind` is still in the dict for anything that must BRANCH on
	# it; it is not what a player is shown.
	var building: Variant = tile.get("building")
	if building != null:
		var b: Dictionary = building
		var named := String(b.get("name", ""))
		if named == "":
			named = String(b.get("kind", "?"))
		lines.append("%s %d · %s" % [named, int(b.get("id", -1)),
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


## HOW MANY LOG LINES FIT IN `room` PIXELS (ASSA-156), AND THE NEWEST ONE ALWAYS DOES.
##
## Never 0 and never more than `limit`. `room <= 0` means nobody has a bound to offer, and the answer
## is then `limit` -- a missing measurement must not silently shrink the log to one line.
##
## WHY THIS IS ARITHMETIC AND NOT A LOOP ASKING THE PANEL ITS OWN MINIMUM HEIGHT, which is what I
## wrote first: `Control.update_minimum_size` is DEFERRED. Measured in `tools/log_room_probe.gd` --
## with fourteen 18px lines in it, `_log_box.get_combined_minimum_size()` returns 12.0, the
## stylebox's margins and nothing else, until an idle frame has gone by. A drop-until-it-fits loop
## reads that 12 and keeps every line, and the test for it passes for the same reason. So the parts
## come from the engine (`Font.get_height`, the theme's separations, the stylebox's margins) and the
## one sum that is mine is here, where a test can see it.
##
## `newest` IS ITS OWN TERM BECAUSE THE NEWEST LINE IS THE ONE THAT WRAPS (ASSA-117 box 8: age 0
## keeps its wrapping, every older line is cut to one row). Same probe: a 272-character line is 36px
## at the panel's width and the Label's own minimum height still says 18, so a sum that treated every
## line alike would draw a panel a row taller than it measured -- back onto the head of the player
## this item is about, by exactly the margin nobody would look for.
static func log_lines_that_fit(room: float, chrome: float, newest: float, pitch: float,
		limit: int) -> int:
	if room <= 0.0 or pitch <= 0.0:
		return limit
	return clampi(1 + int(floorf((room - chrome - newest) / pitch)), 1, limit)


## HOW OLD A LOG LINE LOOKS (ASSA-117). `age` 0 is the newest line and gets `ink`; the oldest gets
## `muted`; everything between is on the straight line from one to the other.
##
## THE TWO INKS ARE ARGUMENTS AND THAT IS THE POINT. There is no colour written down here, because
## Maren's corrected ruling 3 on ASSA-116 is that the client stops holding `Color` literals -- she
## counted 21 of them. The caller reads these out of the theme that is actually in force
## (`get_theme_color`), so a palette change in `tools/build_theme.gd` moves this ramp with it and a
## comment claiming they are "derived" is not the thing holding it true.
##
## AND IT IS WHY "NO LINE IS UNREADABLE" IS PROVABLE RATHER THAN EYEBALLED. Relative luminance is
## monotonic in each channel, so every colour on the segment between two inks has a luminance between
## theirs -- and therefore a contrast ratio against a DARKER panel between theirs. `build_theme.gd`
## already refuses to write a theme whose `INK` or `INK_MUTED` misses WCAG AA on its own surface. So
## if the endpoints pass, every step passes, for any ramp length. `test_hud.gd` asserts that against
## the shipped `theme/assay.tres` rather than against the numbers I happen to have read today.
##
## ONE LINE IS THE NEWEST LINE. A ramp over a single entry has no oldest end to reach, and dividing
## by `count - 1` there is a division by zero that GDScript answers with `inf` rather than a crash --
## so the one-line case is answered first and explicitly.
static func log_line_color(age: int, count: int, ink: Color, muted: Color) -> Color:
	if count <= 1 or age <= 0:
		return ink
	return ink.lerp(muted, clampf(float(age) / float(count - 1), 0.0, 1.0))


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
	# THE SPECIES SYMBOL IS GONE FROM THIS ROW, AND THE COMMENT THAT PUT IT HERE IS THE FINDING
	# (ASSA-180, Maren's ruling). It used to read `handle · V Valium B · mass 148` and this comment
	# used to justify the `V`: "the letter stamped on a deposit is only decodable if something,
	# somewhere, says which name it stands for, and this row is the only place a player sees both."
	#
	# THAT WAS TRUE WHEN IT WAS WRITTEN AND IS NOT TRUE NOW. The species panel is in the SAME column,
	# a scroll below, and `main.gd:1419-1425` draws the map's own disc there with
	# `sim::debug::species_symbol`, `AssayHud.species_tint` and `glyph_color`: the actual mark, in the
	# actual colour, beside the name. A bare letter in a text run is a weaker copy of a lesson
	# already on screen -- and at 1x it read as a stutter, not a cue. It was also the only row in the
	# column spelled this way: the pack reads `1 × Valium hopper (B)` and the crafting menu reads
	# `Minyte gear (B) — 2 Minyte refined (B), you have 6`, neither carrying a symbol.
	#
	# **KEPT AS A CORRECTION RATHER THAN DELETED, because the expiry is the thing worth recording.**
	# A justification in a comment is a claim about the rest of the screen, and the rest of the
	# screen moved under it. The grade letter stays: that is ruled and right (GAME.md §3, "grade is
	# never read off a part in the world -- it is a letter on the bench and the cursor").
	for entry in design.get("parts", []):
		var part: Dictionary = entry
		lines.append("  %s · %s %s · mass %s" % [String(part.get("kind", "?")),
				String(part.get("species_name", "?")), String(part.get("grade", "?")),
				span(int(part.get("mass_low", 0)), int(part.get("mass_high", 0)))])
	return lines


## WHAT THE PANEL SAYS WHEN THERE IS NOTHING TO SHOW, which is every player until the craft chain
## runs. A heading over an empty space reads as a bug; this says which it is.
##
## **TWO KINDS OF EMPTY, AND THE IN-WORLD ONE WAS BEING SHOWN TO A STRANGER WITH NO WORLD**
## (ASSA-186). "Mine, smelt and make parts first" is a route a player in a world can walk; on the
## join screen it is three instructions none of which can be acted on. See [quiet_log_line] for why
## `in_world` is an argument rather than a second function.
static func no_designs_line(in_world: bool) -> String:
	if not in_world:
		return "join a world and the machines you build appear here"
	return "nothing built yet — mine, smelt and make parts first"


## THE TWO FACTS A SPECIES ROW CARRIES AS STATE, NOT AS PROSE (ASSA-73, Maren's ruling 1).
##
## `hand_minable` and `hand_lit_fuel` are booleans the sim already sends, and they must render as
## LABELLED STATE -- a tag -- never as a sentence this client composed. Two describers for one
## condition is how hosts drift apart, which is the same argument `command_line` and ASSA-58 make.
## So these are short tags on a row, and the SENTENCES about those conditions stay where the sim
## writes them (`reach_note`, the stall line).
##
## MINING IS THREE STATES AND USED TO RENDER AS ONE BIT (ASSA-135) -- the same defect ASSA-93 fixed
## one axis over, found by the Game Director on the board's own demo seed. `hand_minable` is a bool
## and `sim::debug::mining` holds a three-state answer, so this row said "hand-minable" or said
## NOTHING: two of the six rocks on seed 14247 can never be mined by anything, they are the first two
## rows the board reads, and the only way this panel had of saying so was to leave a word out. The
## middle state ("hand-minable, but not smeltable", 13.6% of deposits) rendered as the bare promise
## ruling ASSA-52 refuses. The sim sends its own sentence in `mining` and this file picks none of the
## words; it must never re-derive the state from hardness.
##
## WHICH RETIRES A RULING OF THE GAME DIRECTOR'S, BY THEIR OWN WORD (ASSA-135). The comment that
## stood here said "ABSENT RATHER THAN NEGATED: a row says what a rock CAN do, and 'not hand-minable'
## would be the client ranking the roster". That objection was about WHO decides, and it was right
## only while the sim had no word for it -- `debug.rs` writes the sentence now, so rendering it ranks
## nothing. The rule still stands wherever the sim IS silent, which is why `lighting` below is absent
## rather than negated on a rock the sim does not call fuel.
## LIGHTING IS THREE STATES AND USED TO RENDER AS ONE BIT (ASSA-93). `hand_lit_fuel` is true only
## for the first of them, so a fuel NOTHING in the world can light rendered exactly like a rock that
## is not fuel at all -- and the board loaded 50 units of the first kind into a smelter that then sat
## cold with no reason given. The sim already holds the answer (`ladder::lighting`) and now sends its
## own short label in `lighting`; this file picks none of the words and must never re-derive the
## state from heat tolerance.
##
## ABSENT RATHER THAN NEGATED SURVIVES, which is why the key is missing rather than empty on a rock
## the sim does not call fuel: those rows still say nothing about lighting, so no row is ranked.
##
## `TAG_HAND_MINABLE` WAS HERE AND IS GONE (ASSA-135). It was this file's own word for one of three
## states, and a client holding a word for an axis the sim words is how the middle state got lost.
## There is deliberately no constant to put back: the string arrives.

## The tags a species row shows, in a fixed order so six rows read as a column rather than a jumble.
##
## `mining` LEADS, because it is the question a player is asking of six rows at once -- can I get
## anything out of this, and does what I get go anywhere. `fuel` follows, then lighting: both only
## matter once the answer to the first is yes, and on rock nothing can mine the sim withholds the
## lighting (ASSA-68) while the fuel clause carries its own "if you could mine it".
##
## THE FUEL TAG NAMES THE GRADE AND THIS FILE DOES NOT KNOW WHAT A GRADE IS (ASSA-143). The row used
## to show `[hand-minable] [lights from cold]` for a rock whose grade-C deposits will not burn: the
## binding called `fuel_grade` and kept `.is_some()`, so the threshold was computed and dropped. On
## 18.8% of the rows this panel tags as fuel the cheapest grade that burns is not C. `sim::debug::
## fuel_tag` words the whole clause and it is rendered verbatim -- never assembled here from
## `readings`, which are a 25-wide band until the species is assayed anyway.
static func species_tags(species: Dictionary) -> PackedStringArray:
	var tags := PackedStringArray()
	# NO DEFAULT WORD AND NO FALLBACK. If `mining` ever stopped arriving this row would be one tag
	# short and `test_a_species_row_carries_the_sims_own_mining_sentence` fails; a `"hand-minable"`
	# here would make a binding regression render as a confident lie instead.
	var mining := String(species.get("mining", ""))
	if mining != "":
		tags.append(mining)
	# ABSENT RATHER THAN NEGATED, like `lighting`: a rock the sim does not call fuel says nothing
	# about fuel, so no row is ranked by this panel. There is deliberately no bare `"fuel"` word in
	# this file to fall back to -- a grade-less fuel tag is the defect ASSA-143 is about, and if the
	# key stopped arriving the row must lose the claim rather than make it without its condition.
	var fuel := String(species.get("fuel", ""))
	if fuel != "":
		tags.append(fuel)
	var lighting := String(species.get("lighting", ""))
	if lighting != "":
		tags.append(lighting)
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


## WHAT THE CRAFTING MENU'S CONTROL SAYS, and it names its key (ASSA-88). The same shape as the event
## log's toggle, for the same reason: the key is the half of a toggle a stranger cannot discover.
static func make_toggle_text(shown: bool) -> String:
	return "hide what I can make (M)" if shown else "show what I can make (M)"


## What the crafting menu says when there is nothing in it. A heading over nothing reads as a bug, so
## every empty section says WHICH kind of empty it is -- and this one has a cause a player can act on:
## a pair of hands works on what you are carrying, so an empty menu means an empty pack.
##
## **WITH NO WORLD THE CAUSE IS A DIFFERENT ONE AND SO IS THE SENTENCE** (ASSA-186): an empty pack is
## not why the menu is empty on the join screen, and "mine some rock first" is an instruction the one
## stranger who reads it cannot follow. See [quiet_log_line] for why `in_world` is an argument.
static func nothing_to_make_line(in_world: bool) -> String:
	if not in_world:
		return "join a world and what you can make is listed here"
	return "nothing you are carrying can be worked by hand — mine some rock first"


## THE ONE WORD ON EVERY ROW'S BUTTON, and it is the same word on every row ON PURPOSE (ASSA-88,
## Maren's ruling). The bug she measured was two buttons both labelled exactly `Craft smelter` making
## smelters with different walls: a LABEL that was the only read, and ambiguous. So the identity of a
## row lives in the sim's sentence beside the button, never in the button, and this returns one word
## however many catalogues a row can come from.
static func make_button_text() -> String:
	return "Make"
