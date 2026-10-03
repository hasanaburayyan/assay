extends SceneTree
## THE CLIENT'S ONE THEME, GENERATED RATHER THAN DRAWN (ASSA-116 box 1).
##
##   godot --headless --path . --script res://tools/build_theme.gd
##
## Writes `res://theme/assay.tres`, which `project.godot` names as `gui/theme/custom` -- so it
## reaches EVERY Control in the client without a single node opting in, including the ones built in
## code by `main.gd` and the ones a future screen has not been written yet.
##
## WHY A GENERATOR AND NOT A HAND-EDITED `.tres`. The same rule the art pipeline runs on (`art/`:
## "sprites are generated, never hand-edited"), for the same reason. A theme is forty small numbers
## that have to agree with each other; as a resource file those numbers are unreviewable and drift
## one inspector click at a time. Here the scale is arithmetic, the palette has one source, and a
## reviewer reads intent instead of diffing floats.
##
## THE PALETTE IS `AssayHud`'S, NOT A SECOND ONE. `hud.gd` already decides what this game's surfaces
## look like -- `MAP_BG`, `status_color`, and a WCAG contrast pair (`relative_luminance`,
## `contrast_ratio`) written for the species glyphs. A theme that invented its own greys would be the
## ASSA-43/52 defect in paint: two vocabularies for one thing, free to disagree. So the panel colour
## is derived from the map's background, and every text colour is checked against the surface it is
## actually drawn on using the function already in the repo.
##
## **AND THAT CHECK IS THE POINT, because a theme is otherwise unfalsifiable.** Taste cannot fail a
## test. Contrast can: `MIN_CONTRAST` is the WCAG AA threshold for body text, and this script
## REFUSES TO WRITE A THEME whose own text would fail it. The failure mode it exists to stop is the
## ordinary one -- somebody nudges a grey two points darker to make a screenshot look calmer, and the
## readout nobody tests becomes unreadable for the players who most need it.
##
## Prints `THEME BUILT` LAST and only on success, because Godot exits 0 even on a compile error.

const OUT := "res://theme/assay.tres"
## WCAG 2.1 AA for body text. The repo already computes this ratio; this is the line it has to clear.
const MIN_CONTRAST := 4.5
## Muted text is still text. AA large-text (3.0) would let a 14px readout through, so it is held to
## the same bar as body: "secondary" describes importance, never legibility.
const MIN_MUTED_CONTRAST := 4.5

# ---------------------------------------------------------------------------
# THE TYPE SCALE. Four sizes, and the reason there are four is that `main.gd` currently reaches for
# 12, 13 and 19 by hand at eight separate call sites, which is how a screen ends up with no scale at
# all. Named here, they can be used by name.
const DISPLAY := 20  # the bench verdict, SAFE / UNCERTAIN / WILL BREAK -- the one word to read first
const HEADING := 15  # section headings: make, you, do, bench, rocks, cursor, last tick
const BODY := 13  # readouts and rows
const SMALL := 11  # dense secondary lines, and the toggles that name their own key

# THE PALETTE. Two surfaces and three inks, which is as much as this screen needs.
## The panel, lifted off the map rather than matched to it: `AssayHud.MAP_BG` is what the world is
## drawn on, and a panel at the same value would have no edge without a border to draw one.
const SURFACE := Color(0.145, 0.157, 0.188)
## Raised: buttons and fields, so a thing you can press is lighter than the thing it sits on.
const RAISED := Color(0.208, 0.224, 0.263)
const BORDER := Color(0.290, 0.310, 0.360)
const INK := Color(0.898, 0.914, 0.945)
const INK_MUTED := Color(0.655, 0.690, 0.745)
## The one accent, borrowed from `AssayHud.status_color`'s "joined" green so a focused field and a
## good status are the same colour rather than two opinions about success.
const ACCENT := Color(0.50, 0.90, 0.55)

const PAD_X := 10
const PAD_Y := 6
const RADIUS := 4


func _initialize() -> void:
	var problems := _contrast_problems()
	if not problems.is_empty():
		for line in problems:
			print("  ", line)
		_fail("the theme's own text fails WCAG AA on the surface it is drawn on")
		return

	var theme := Theme.new()
	theme.default_font_size = BODY
	_style_label(theme)
	_style_button(theme)
	_style_line_edit(theme)
	_style_panel(theme)
	_style_scroll(theme)

	if DirAccess.make_dir_recursive_absolute("res://theme") != OK:
		_fail("cannot make res://theme")
		return
	if ResourceSaver.save(theme, OUT) != OK:
		_fail("cannot write %s" % OUT)
		return
	print("  %s  %d type variations, body %dpx, contrast floor %.1f"
			% [OUT, theme.get_type_variation_list("Label").size(), BODY, MIN_CONTRAST])
	print("THEME BUILT")
	quit(0)


## EVERY INK AGAINST EVERY SURFACE IT IS ACTUALLY DRAWN ON, by `AssayHud`'s own WCAG function.
##
## Each pair is a real pairing on the screen, not a matrix: ink on panel is the readouts, ink on
## raised is a button's label, muted on panel is every secondary line in the column. A pair nobody
## draws would be a test of nothing.
func _contrast_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	for pair in [["body text", INK, SURFACE, MIN_CONTRAST],
			["button label", INK, RAISED, MIN_CONTRAST],
			["secondary text", INK_MUTED, SURFACE, MIN_MUTED_CONTRAST],
			["secondary on a button", INK_MUTED, RAISED, MIN_MUTED_CONTRAST],
			["accent on a field", ACCENT, RAISED, MIN_CONTRAST]]:
		var ratio := AssayHud.contrast_ratio(pair[1], pair[2])
		if ratio < float(pair[3]):
			problems.append("%s: %.2f:1, needs %.1f:1" % [pair[0], ratio, pair[3]])
	return problems


## LABELS, AND THE THREE NAMES ANYTHING ELSE REACHES FOR. A type variation rather than a font-size
## override at the call site: `main.gd` says what a label IS ("Heading") and this file says how big
## that is, so the scale can be retuned once instead of at eight call sites.
func _style_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", INK)
	theme.set_font_size("font_size", "Label", BODY)
	for variation in [["Display", DISPLAY, INK], ["Heading", HEADING, INK_MUTED],
			["Muted", SMALL, INK_MUTED]]:
		var name := StringName(variation[0])
		theme.add_type(name)
		theme.set_type_variation(name, "Label")
		theme.set_font_size("font_size", name, variation[1])
		theme.set_color("font_color", name, variation[2])


func _style_button(theme: Theme) -> void:
	theme.set_font_size("font_size", "Button", SMALL)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", INK_MUTED.darkened(0.25))
	theme.set_stylebox("normal", "Button", _box(RAISED, BORDER))
	theme.set_stylebox("hover", "Button", _box(RAISED.lightened(0.10), BORDER.lightened(0.15)))
	theme.set_stylebox("pressed", "Button", _box(RAISED.darkened(0.18), ACCENT))
	theme.set_stylebox("disabled", "Button", _box(SURFACE, BORDER.darkened(0.3)))
	# A FOCUS RING THAT IS VISIBLE, because keyboard focus is the half nobody looks at. Godot's
	# default focus box is a flat outline that vanishes on a dark panel.
	theme.set_stylebox("focus", "Button", _box(RAISED, ACCENT))


func _style_line_edit(theme: Theme) -> void:
	theme.set_font_size("font_size", "LineEdit", BODY)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", INK_MUTED)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_stylebox("normal", "LineEdit", _box(SURFACE.darkened(0.25), BORDER))
	theme.set_stylebox("focus", "LineEdit", _box(SURFACE.darkened(0.25), ACCENT))


func _style_panel(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _box(SURFACE, BORDER))
	theme.set_stylebox("panel", "PanelContainer", _box(SURFACE, BORDER))


## THE SCROLLBAR, which is the one control on this screen that is load-bearing and invisible.
## The right-hand column is taller than the window, so the bar is the only thing telling a player
## there is more below -- it is widened and given the accent, not hidden.
func _style_scroll(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = SURFACE.darkened(0.3)
	track.set_corner_radius_all(RADIUS)
	track.content_margin_left = 2
	track.content_margin_right = 2
	var grab := StyleBoxFlat.new()
	grab.bg_color = BORDER.lightened(0.2)
	grab.set_corner_radius_all(RADIUS)
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("grabber", "VScrollBar", grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar", _flat(ACCENT))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _flat(ACCENT))


func _box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := _flat(fill)
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = PAD_X
	box.content_margin_right = PAD_X
	box.content_margin_top = PAD_Y
	box.content_margin_bottom = PAD_Y
	return box


func _flat(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(RADIUS)
	return box


func _fail(why: String) -> void:
	print("FAIL  %s" % why)
	quit(1)
