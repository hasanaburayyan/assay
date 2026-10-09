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
## the width Maren ruled for the dock. Both minus the panel's horizontal padding at the call site.
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

## **THESE ARE RECONSTRUCTED FROM THE LOG'S WORDINGS, NOT CAPTURED FROM A RUN, AND THE DIFFERENCE
## MATTERS BECAUSE OF WHAT THEY ANSWERED.** I wrote them expecting the dock to cost a wrap, and **all
## five fit 318 px on one line, so the predicted cost is 0.0 px.** That is the instrument refusing my
## hypothesis, and it is only worth anything if the provenance is honest: a sentence long enough to
## wrap costs `pitch` per extra line, and one exists -- ASSA-242 is that the assembly sentence is too
## long for either home it already has. **So the wrap cost here is a measured zero for these five
## sentences and an OPEN question for the log as a whole**, and the honest next version of this tool
## captures the sentences off a real play instead of taking them from my memory of the format.
const LINES := [
	"Mine - submitted at tick 514",
	"mined 2 ore of Tonore at grade B",
	"the smelter at (59, 61) has stopped: its fire is out",
	"placed a Tonore smelter at (59, 61)",
	"discovered Tonore - you may name it",
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

	# CHROME, THE SAME FOUR PARTS `_log_lines_that_fit` ADDS UP: the panel's vertical padding, one
	# separation, the heading's font height, and the air the Heading stylebox puts above it. The last
	# one is the part a font metric cannot see (ASSA-224).
	var chrome := separation + head_font.get_height(head_size)
	var air: StyleBox = head.get_theme_stylebox(&"normal", &"Heading")
	var air_y := 0.0
	if air != null:
		air_y = air.get_margin(SIDE_TOP) + air.get_margin(SIDE_BOTTOM)
	chrome += air_y

	print("THE LOG'S OWN NUMBERS, off the shipped theme")
	print("  pitch   %.1f px  (Label %d px font height %.1f + VBox separation %.1f)"
			% [pitch, size, font.get_height(size), separation])
	print("  chrome  %.1f px  (separation %.1f + Heading %d px height %.1f + its air %.1f)"
			% [chrome, separation, head_size, head_font.get_height(head_size), air_y])

	print("\nTHE NEWEST LINE, WRAPPED, AT BOTH WIDTHS -- the half the ruling does not mention")
	var worst_wide := 0.0
	var worst_dock := 0.0
	for text in LINES:
		var wide := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, WIDE, size).y
		var dock := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, DOCKED, size).y
		worst_wide = maxf(worst_wide, wide)
		worst_dock = maxf(worst_dock, dock)
		print("  %5.1f -> %5.1f px   %s" % [wide, dock, text])
	print("  WORST  %.1f px wide (%.0f px), %.1f px docked (%.0f px): the dock costs %.1f px before a "
			% [worst_wide, WIDE, worst_dock, DOCKED, worst_dock - worst_wide]
			+ "single line of history is kept")

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
