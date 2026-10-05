extends SceneTree
## **EVERY SPECIES x THE WHOLE PURITY RANGE AGAINST THE HATCH INK, WHICH IS ASSA-209's BOX 1.**
##
##   godot --headless --path client --script res://tools/hatch_ink_sweep.gd -- [out.txt]
##
## Maren ruled the bar and explicitly did NOT rule the fix: "the builder should measure before
## choosing". So this chooses nothing. It asks `AssayHud`'s own functions -- `deposit_color`,
## `glyph_color`, `contrast_ratio` -- for all 600 states a disc can be in, under each candidate ink.
## **Her numbers were computed outside the engine; these come out of the shipped painter**, which is
## the difference between agreeing with her and confirming her.
##
## THREE COLUMNS, AND THE THIRD IS THE ONE THAT KILLS THE OBVIOUS FIX:
##   HATCH:FILL     the mark's own legibility, the defect. `MAP_BG` on a dim purple reads 1.42:1.
##   LETTER:AROUND  the species letter against the surface it actually sits on. Painting a hatch
##                  CHANGES that surface, which is Cove's ASSA-199 control measured on pictures: a
##                  `MAP_BG` hatch cost dark letters 30-36% and gained white ones 40-46%.
##   HATCH:LETTER   whether the mark and the letter are the same ink. Cove measured the consequence on
##                  ASSA-193 -- a white mark on a disc with a white letter fuses into one blob and a
##                  pixel count called it 63% survived.
##
## **THE THIRD COLUMN WAS `is_equal_approx` IN MY FIRST VERSION AND THAT IS NOT A MEASUREMENT.**
## `MAP_BG` is #1a1c21 and `GLYPH_DARK` is #050508, so identity reported "0 of 600 fuse" for the
## shipped ink while the two are a 1.26:1 pair -- a dark letter sitting in a dark hatch, which is
## precisely the thing Cove's 3.24:1 worst case is about. It is a ratio now.

const PURITIES := 100

## HOW MUCH OF A HATCHED DISC IS HATCH, used to composite the surface a letter really sits on.
## It is `HATCH_ON / HATCH_PERIOD` and not a number of mine: the ruled density, read off the painter.
var _ink_share := float(AssayHud.HATCH_ON) / float(AssayHud.HATCH_PERIOD)


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var out_path := String(argv[0]) if argv.size() > 0 else ""
	var lines := PackedStringArray()
	lines.append("ASSA-209 HATCH INK SWEEP, out of the shipped painter (AssayHud's own functions)")
	lines.append("species slots %d x purity 1..%d = %d states"
			% [AssayHud.SPECIES_TINTS.size(), PURITIES, AssayHud.SPECIES_TINTS.size() * PURITIES])
	lines.append("ruled density %d in %d along x+y = %.1f%% of a disc, so a hatched surface is"
			% [AssayHud.HATCH_ON, AssayHud.HATCH_PERIOD, 100.0 * _ink_share])
	lines.append("modelled as the fill mixed %.1f%% toward the hatch ink" % [100.0 * _ink_share])
	lines.append("")

	# A: what ships. One fixed near-black, and the letter picked against the FILL as today.
	_sweep(lines, "A. SHIPPED: one fixed ink, MAP_BG %s" % [AssayHud.MAP_BG.to_html(false)],
			func(_fill: Color) -> Color: return AssayHud.MAP_BG, false)

	# B: the shape Maren pointed at -- `glyph_color`'s own two-value pick, same two inks.
	_sweep(lines, "B. TWO-VALUE, the glyph's own pick (GLYPH_DARK or GLYPH_LIGHT)",
			func(fill: Color) -> Color: return AssayHud.glyph_color(fill), false)

	# C: two-value between MAP_BG and GLYPH_LIGHT, keeping the map's own ground colour as the dark
	# half so the mark still spends no new literal (Maren counted 21 on ASSA-116).
	_sweep(lines, "C. TWO-VALUE between MAP_BG and GLYPH_LIGHT (no new literal)",
			_two_value, false)

	# D: C, AND the letter re-picked against the surface it ends up on rather than the bare fill.
	# This is what Cove's control implies: `glyph_color` is asked about the FILL and never sees the
	# hatch, so the letter's ink is chosen for a surface that is not the one it is drawn on.
	_sweep(lines, "D. C, PLUS the letter picked against the HATCHED surface, not the bare fill",
			_two_value, true)

	var text := "\n".join(lines) + "\n"
	print(text)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			print("FAIL  cannot write %s: %d" % [out_path, FileAccess.get_open_error()])
			quit(1)
			return
		f.store_string(text)
		f.close()
		print("written to %s" % out_path)
	quit(0)


func _two_value(fill: Color) -> Color:
	return AssayHud.MAP_BG if AssayHud.contrast_ratio(fill, AssayHud.MAP_BG) \
			>= AssayHud.contrast_ratio(fill, AssayHud.GLYPH_LIGHT) else AssayHud.GLYPH_LIGHT


## THE SURFACE A LETTER IS REALLY ON once a hatch is painted over the fill: the fill mixed toward the
## hatch ink by the ruled density. **A MODEL, AND SAID TO BE ONE.** A letter sits on a particular set
## of pixels, some hatch and some fill, so no single colour is the truth; this is the area-weighted
## average, which is what a WCAG ratio against a patterned ground can mean at all. Cove's pictures are
## the real instrument and this is how the shape of their result is reproduced without a window.
func _hatched_surface(fill: Color, ink: Color) -> Color:
	return fill.lerp(ink, _ink_share)


## ONE CANDIDATE, ALL 600 STATES, worst case per species and then over the palette -- which is the bar
## Maren ruled ("the worst case, not the shipped seed").
func _sweep(lines: PackedStringArray, title: String, ink_for: Callable, relight: bool) -> void:
	lines.append(title)
	lines.append("   species  tint      hatch:fill   letter:around   hatch:letter   white hatch")
	var worst_mark := 999.0
	var worst_mark_at := ""
	var worst_letter := 999.0
	var worst_letter_at := ""
	var worst_fuse := 999.0
	var worst_fuse_at := ""
	for s in AssayHud.SPECIES_TINTS.size():
		var mark := 999.0
		var mark_at := 0
		var letter := 999.0
		var letter_at := 0
		var fuse := 999.0
		var fuse_at := 0
		var white := 0
		for p in range(1, PURITIES + 1):
			var fill := AssayHud.deposit_color(s, p)
			var ink: Color = ink_for.call(fill)
			var around := _hatched_surface(fill, ink)
			var glyph := AssayHud.glyph_color(around if relight else fill)
			if ink.is_equal_approx(AssayHud.GLYPH_LIGHT):
				white += 1
			var r_mark := AssayHud.contrast_ratio(fill, ink)
			var r_letter := AssayHud.contrast_ratio(around, glyph)
			var r_fuse := AssayHud.contrast_ratio(ink, glyph)
			if r_mark < mark:
				mark = r_mark
				mark_at = p
			if r_letter < letter:
				letter = r_letter
				letter_at = p
			if r_fuse < fuse:
				fuse = r_fuse
				fuse_at = p
		if mark < worst_mark:
			worst_mark = mark
			worst_mark_at = "slot %d %s purity %d" % [s, AssayHud.SPECIES_TINTS[s], mark_at]
		if letter < worst_letter:
			worst_letter = letter
			worst_letter_at = "slot %d %s purity %d" % [s, AssayHud.SPECIES_TINTS[s], letter_at]
		if fuse < worst_fuse:
			worst_fuse = fuse
			worst_fuse_at = "slot %d %s purity %d" % [s, AssayHud.SPECIES_TINTS[s], fuse_at]
		lines.append("   slot %d   %s  %6.2f:1 @%3d  %6.2f:1 @%3d   %6.2f:1 @%3d   %3d/%d"
				% [s, AssayHud.SPECIES_TINTS[s], mark, mark_at, letter, letter_at, fuse, fuse_at,
				white, PURITIES])
	lines.append("   WORST MARK   %6.2f:1  %s" % [worst_mark, worst_mark_at])
	lines.append("   WORST LETTER %6.2f:1  %s" % [worst_letter, worst_letter_at])
	lines.append("   WORST FUSE   %6.2f:1  %s" % [worst_fuse, worst_fuse_at])
	lines.append("")
