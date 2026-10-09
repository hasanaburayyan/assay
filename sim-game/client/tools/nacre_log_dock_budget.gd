extends SceneTree
## CI: local -- reads the SHIPPED theme's font metrics to price a region that does not exist yet
## **WHAT A DOCKED LOG WOULD COST THE COLUMN** (ASSA-378, ASSA-276 move 1).
##
##   godot --headless --path . --script res://tools/nacre_log_dock_budget.gd
##
## Maren ruled move 1 yes *"docked at 318 px ... floor ratcheted at today's value: at least 8 lines at
## 1280x720"*. `nacre_tab_budget_probe.gd` says what the column HAS; this says what 8 lines WANT. The
## two numbers together decide whether move 1 can be built before anything else leaves the column.
##
## **HEADLESS IS CORRECT HERE AND IS WRONG IN THE TAB PROBE, WHICH IS WORTH SAYING ONCE.** That probe
## measures laid-out containers, and a container that never drew answers 0.0 -- so it needs a real
## window. Everything here is a THEME read: `Font.get_height`, `StyleBox.get_margin`,
## `Font.get_multiline_string_size`. None of them wait for a layout pass, and all of them answer off
## the same `theme/assay.tres` the game ships. A font metric does not change because nobody looked.
##
## **IT ASKS THE SAME FOUR QUANTITIES `main.gd::_log_lines_that_fit` ASKS, IN THE SAME ORDER**, and
## then inverts `AssayHud.log_lines_that_fit` instead of re-deriving it: that function is
## `1 + floor((room - chrome - newest) / pitch)`, so the room 8 lines need is
## `chrome + newest + 7 * pitch`. Re-spelling the arithmetic would let this tool and the game disagree
## about the very thing being ruled on.
##
## **AND IT PRICES THE HALF OF THE RULING THE RULING DOES NOT MENTION: THE WRAP.** Today the log is the
## world's rectangle, so a line wraps at 912 px. Docked it wraps at 318. The same sentence is a
## different number of lines in the two places, so "8 lines" is not one quantity -- `newest` is
## measured at BOTH widths here and the difference is the finding, not a footnote.

## The log's own home today (`main.gd:1612`: `_log_region` takes `world.position`/`world.size`), and
## the width Maren ruled for the dock. **THESE ARE THE PANEL'S OUTER WIDTHS AND THE TEXT NEVER GETS
## THEM.** The game wraps at `world_rect().size.x - pad.x` (`_log_lines_that_fit`), `pad.x` being the
## log panel's own stylebox margins, and for a day this file passed both of these straight in under a
## docstring of mine claiming they were already "minus the panel's horizontal padding at the call
## site". They were not: that sentence described the game and was false of the constants, so every
## figure this tool published wrapped its text at a width the log never offers -- too WIDE, so it
## under-counted wrapping, so it was optimistic in the one direction that matters. `pad.x` is
## subtracted below, off the same stylebox the game asks.
const WIDE := 912.0
const DOCKED := 318.0
## Maren's floor, in lines.
const FLOOR_LINES := 8
## What `nacre_tab_budget_probe.gd` measured on main this run, so the verdict is arithmetic a reader
## can check rather than a second measurement taken here: the scroll box's height at its worst tick
## and at rest, and the deepest any tab's lowest button reached into it.
const CLIP_WORST := 390.0
const CLIP_REST := 510.0
const REACH_DEEPEST := 350.0

## **THE SENTENCES THIS IS FED DECIDE THE ANSWER, AND THE FIRST SET WAS MINE FROM MEMORY.** Five
## wordings I reconstructed stood here, all of them short; they fit 318 px on one line and the tool
## published a wrap cost of **0.0 px**. Maren's reading of a real frame is what killed that zero: two
## assembly lines **already end in an ellipsis at 912 px**, and `you made 1 x Tonore hopper (A)` is
## four of the eleven rows on screen. *"My five were the short ones."*
##
## **SO THESE ARE ASSA-242's CONSTRUCTED WORST CASES, VERBATIM FROM `maren-assa242-bar/
## candidates.txt`** -- Maren's own file, measured through `client/tools/line_width.gd` at the font
## `_note` really gives a log line, built the way Marlow built his: a 20-character species name (the
## rename rule's maximum), the longest real player name we have, 4-digit coordinates. Her published
## widths are beside each line so a reader can tell a wrap from a mis-transcription: **591 px** the
## widest ORDINARY line, **564** ore-mined, **434** the longest note row, **358** C4's common case,
## **1004** today's assembly row 1 -- the defect ASSA-242 is about, and still what the log draws.
##
## **NOTHING HERE IS A SENTENCE I WROTE.** That is the point: the floor this tool reports is Maren's
## *"seven cut rows plus the tallest newest entry the log can be asked to draw, at the dock's real
## text width"*, and "can be asked to draw" is the sim's worst case rather than the frame I happened
## to shoot.
const LINES := [
	# 1004 px -- today's assembly row 1, the one ASSA-242 exists about.
	"you assembled a machine: SAFE · mass 616 of 705 budget · holds 60 · speed 78 (bare hands 25)"
			+ " · frame(Tonore A 385) + head(Tonore A 77) + hopper(Tonore A 154)",
	# 591 px -- the widest ORDINARY line, which is the bar Maren set for the assembly family.
	"the Ttwentycharacters smelter smelted 3 Ttwentycharacters refined (A) (5 waiting to be taken)",
	# 564 px -- ore mined, worst case.
	"hasanaburayyan mined 3 Ttwentycharacters ore (A) (carrying 148, 1200 left in the deposit)",
	# 536 px -- C4's worst case, with a 14-character name.
	"hasanaburayyan assembled a machine: UNCERTAIN · mass 616-700 of 705-800 budget",
	# 434 px -- the sim's own second row (`verdict_note`), worst case. A ROW, cut separately.
	"assay Ttwentycharacters and Fourteencharsx and Ninechars to know",
	# 358 px -- C4's common case, the shape Maren approved.
	"you assembled a machine: SAFE · mass 616 of 705 budget",
]


func _initialize() -> void:
	var theme: Theme = load("res://theme/assay.tres")
	if theme == null:
		print("FAIL could not load res://theme/assay.tres")
		quit(1)
		return
	# THE NODES EXIST ONLY SO THE THEME LOOKUP HAS A TREE TO WALK. Nothing is laid out and nothing is
	# drawn; `get_theme_*` resolves through the parent chain, so a themed root is the whole fixture.
	var root := Control.new()
	root.theme = theme
	get_root().add_child(root)
	var body := Label.new()
	root.add_child(body)
	var head := Label.new()
	head.theme_type_variation = &"Heading"
	root.add_child(head)
	var box := VBoxContainer.new()
	root.add_child(box)
	# **THE PANEL THE LOG SITS IN, SO ITS PADDING CAN BE ASKED FOR RATHER THAN ASSUMED.** `_log_box`
	# is a plain `PanelContainer` (`main.gd:1668`) and the game reads `get_theme_stylebox(&"panel")`
	# off it, which resolves to `panel`/`PanelContainer` in the shipped theme. Same node kind, same
	# lookup, so this cannot drift from the thing it is measuring.
	var plate := PanelContainer.new()
	root.add_child(plate)

	var font: Font = body.get_theme_font(&"font", &"Label")
	var size := body.get_theme_font_size(&"font_size", &"Label")
	var head_font: Font = head.get_theme_font(&"font", &"Heading")
	var head_size := head.get_theme_font_size(&"font_size", &"Heading")
	if font == null or head_font == null:
		print("FAIL the theme answered no font for Label or Heading")
		quit(1)
		return
	var separation := float(box.get_theme_constant(&"separation"))
	var pitch := font.get_height(size) + separation

	# **THE PANEL'S OWN PADDING, BOTH WAYS.** `pad.x` comes off the wrap width and `pad.y` is the
	# first of the four parts of chrome -- and this file added three of them. The comment below has
	# named "the panel's vertical padding" since the tool was written while the arithmetic went
	# straight to `separation`, so the chrome was short by `pad.y` in the same optimistic direction as
	# the wrap width. Two defects, one instrument, both found by Maren asking what the padding was.
	var pad := Vector2.ZERO
	var plate_style: StyleBox = plate.get_theme_stylebox(&"panel")
	if plate_style != null:
		pad = Vector2(plate_style.get_margin(SIDE_LEFT) + plate_style.get_margin(SIDE_RIGHT),
				plate_style.get_margin(SIDE_TOP) + plate_style.get_margin(SIDE_BOTTOM))
	# CHROME, THE SAME FOUR PARTS `_log_lines_that_fit` ADDS UP: the panel's vertical padding, one
	# separation, the heading's font height, and the air the Heading stylebox puts above it. The last
	# one is the part a font metric cannot see (ASSA-224).
	var chrome := pad.y + separation + head_font.get_height(head_size)
	var air: StyleBox = head.get_theme_stylebox(&"normal", &"Heading")
	var air_y := 0.0
	if air != null:
		air_y = air.get_margin(SIDE_TOP) + air.get_margin(SIDE_BOTTOM)
	chrome += air_y

	print("THE LOG'S OWN NUMBERS, off the shipped theme")
	print("  pitch   %.1f px  (Label %d px font height %.1f + VBox separation %.1f)"
			% [pitch, size, font.get_height(size), separation])
	print("  chrome  %.1f px  (panel pad.y %.1f + separation %.1f + Heading %d px height %.1f + its "
			% [chrome, pad.y, separation, head_size, head_font.get_height(head_size)]
			+ "air %.1f)" % air_y)
	print("  panel   pad %.1f x %.1f, so the TEXT gets %.0f px wide and %.0f px docked"
			% [pad.x, pad.y, WIDE - pad.x, DOCKED - pad.x])

	print("\nTHE NEWEST LINE, WRAPPED, AT BOTH TEXT WIDTHS -- the half the ruling does not mention")
	# ONE ROW AT THIS FONT AND THIS WIDTH, measured the same way the lines are, so the row counts
	# below are a ratio of two numbers from one call and not a division by a font metric that wraps
	# differently. A string with no space in it cannot wrap at any width worth measuring.
	var one_row := font.get_multiline_string_size("Mg", HORIZONTAL_ALIGNMENT_LEFT,
			DOCKED - pad.x, size).y
	var worst_wide := 0.0
	var worst_dock := 0.0
	var worst_rows := 0.0
	for text in LINES:
		var wide := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				WIDE - pad.x, size).y
		var dock := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				DOCKED - pad.x, size).y
		worst_wide = maxf(worst_wide, wide)
		worst_dock = maxf(worst_dock, dock)
		worst_rows = maxf(worst_rows, dock / one_row)
		# **AND THE FLOOR THIS ONE LINE WOULD SET, PER LINE.** Maren's floor is *seven cut rows plus
		# the tallest newest entry the log can be asked to draw*, so which sentence is the tallest
		# decides it -- and that changes when ASSA-242 cuts the assembly line. Printing the floor
		# beside every candidate means the number after the cut is this tool's answer rather than
		# arithmetic either of us did in a comment.
		print("  %5.1f px (%.1f rows) -> %5.1f px (%.1f rows)  floor %5.1f px   %s"
				% [wide, wide / one_row, dock, dock / one_row,
				chrome + dock + float(FLOOR_LINES - 1) * pitch, text])
	print("  WORST  %.1f px wide (text %.0f px), %.1f px docked (text %.0f px) = %.1f rows: the dock "
			% [worst_wide, WIDE - pad.x, worst_dock, DOCKED - pad.x, worst_rows]
			+ "costs %.1f px before a single line of history is kept" % (worst_dock - worst_wide))

	print("\nWHAT %d LINES WANT, inverting AssayHud.log_lines_that_fit" % FLOOR_LINES)
	var want := chrome + worst_dock + float(FLOOR_LINES - 1) * pitch
	print("  room = chrome %.1f + newest %.1f + %d x pitch %.1f = %.1f px"
			% [chrome, worst_dock, FLOOR_LINES - 1, pitch, want])
	# THE CHECK THAT THE INVERSION IS THE SAME ARITHMETIC THE GAME RUNS, and not my algebra: hand the
	# answer back to the shipped function and it must say exactly the floor.
	var back := AssayHud.log_lines_that_fit(want, chrome, worst_dock, pitch, 14)
	if back != FLOOR_LINES:
		print("FAIL the inversion disagrees with AssayHud.log_lines_that_fit: it says %d lines for "
				% back + "%.1f px, not %d. The algebra here is wrong, not the game."
				% [want, FLOOR_LINES])
		quit(1)
		return
	var one_less := AssayHud.log_lines_that_fit(want - 1.0, chrome, worst_dock, pitch, 14)
	if one_less >= FLOOR_LINES:
		print("FAIL the inversion is not tight: a pixel less still answers %d lines, so this is a "
				% one_less + "bound on nothing")
		quit(1)
		return
	print("  CHECKED both ways: %.1f px answers %d lines and %.1f px answers %d, so the number is the "
			% [want, back, want - 1.0, one_less] + "floor and not a ceiling I rounded to")

	print("\nTHE VERDICT, against what the column HAS (nacre_tab_budget_probe.gd, same main)")
	print("  worst clip %.0f px, deepest reach %.0f px -> %.0f px of headroom at the worst tick"
			% [CLIP_WORST, REACH_DEEPEST, CLIP_WORST - REACH_DEEPEST])
	print("  at rest    %.0f px, deepest reach %.0f px -> %.0f px of headroom at rest"
			% [CLIP_REST, REACH_DEEPEST, CLIP_REST - REACH_DEEPEST])
	var fits_worst := (CLIP_WORST - REACH_DEEPEST) >= want
	var fits_rest := (CLIP_REST - REACH_DEEPEST) >= want
	print("  %d lines want %.0f px: worst tick %s, at rest %s"
			% [FLOOR_LINES, want, "FITS" if fits_worst else "DOES NOT FIT",
					"FITS" if fits_rest else "DOES NOT FIT"])
	if fits_worst:
		print("\nLOG DOCK BUDGET OK -- the floor fits on every tick measured; move 1 can be built as "
				+ "ruled")
	else:
		# NOT A FAILURE OF THE TOOL. The tool answered; the answer is no.
		var spare := CLIP_WORST - REACH_DEEPEST
		print("\nLOG DOCK BUDGET: THE FLOOR DOES NOT FIT. %.0f px of headroom at the worst tick "
				% spare + "holds %d line(s), and Maren's floor is %d. Something else leaves the "
				% [AssayHud.log_lines_that_fit(spare, chrome, worst_dock, pitch, 14), FLOOR_LINES]
				+ "column first; %.0f px short." % (want - spare))
	quit(0)
