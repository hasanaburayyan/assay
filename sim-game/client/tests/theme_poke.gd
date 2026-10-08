extends RefCounted
## **THE ONE PLACE THIS SUITE POKES A CONTROL BEFORE READING A THEME VALUE** (ASSA-312).
##
## Our theme is a PROJECT theme (`project.godot` `gui/theme/custom`). A `Control` that gets its
## theme that way keeps resolving the **plain type's** entries -- `Label`, `Button` -- and ignores
## its own `theme_type_variation` until it receives `NOTIFICATION_THEME_CHANGED`. **Running
## `_process` frames does not deliver it.** The real window is fine: it arrives on tree entry and
## first draw. **Only headless reads are affected, which is to say only this suite** (ASSA-246).
##
## **WHY THIS IS A FILE AND NOT A FUNCTION IN ONE TEST.** ASSA-246 wrote down "a shared helper
## rather than call sites each remembering" and left it, correctly: one site is not worth a module.
## ASSA-267 made it two, and made it concrete in the worst way. `test_tab_strip.gd` read a colour
## with no type argument, and its own comment explained why that was honest -- *an override is
## consulted FIRST and bypasses the type chain entirely*. True, and it was the ONLY thing propping
## up that read. ASSA-267 moved the rule into the theme and removed the override, and **12
## assertions went red against a theme that was already correct**, every tab reporting plain
## `Button`'s `ACCENT` for pressed and `WHITE` for hover-pressed.
##
## So the failure to design against is not "the code broke". It is **"the thing propping up a read
## went away and nothing said so"** -- and a third test file has no way to learn that except by
## someone remembering on the wake-up they are tired.
##
## **A PRELOADED SCRIPT, DELIBERATELY NOT A `class_name`.** A new global class is invisible until
## `godot --headless --import` has run twice (the first run after `.godot/` is gone crashes on exit
## having written a complete cache -- a Godot bug CI works around). A test helper is not worth
## making the suite's first run a two-step.
##
##     const Poke := preload("res://tests/theme_poke.gd")
##     var ink := Poke.drawn_color(label)
##
## `client/tools/check_one_theme_poke.py` fails if any `notification(NOTIFICATION_THEME_CHANGED)`
## appears in `tests/` outside this file, so the count is a check and not a habit.


## Deliver the notification the engine would have delivered, and hand the control back so a caller
## can chain. The ONE call site in the suite.
static func poke(control: Control) -> Control:
	control.notification(Control.NOTIFICATION_THEME_CHANGED)
	return control


## The colour a label DRAWS, which is not what a headless read reports until it is poked.
##
## `modulate` is multiplied in because it scales whatever the theme chose, and a correct literal
## behind a `modulate` is the ASSA-251 defect: the declared property is right and the drawn one
## differs.
static func drawn_color(label: Label) -> Color:
	poke(label)
	var c := label.get_theme_color(&"font_color")
	var m := label.modulate
	return Color(c.r * m.r, c.g * m.g, c.b * m.b, c.a * m.a)


## The font size a label DRAWS. **THIS IS THE READ THAT GIVES THE POKE A LEVER** (ASSA-252):
## `Heading` declares 15 and plain `Label` 13, so an un-poked `Heading` is off by 2px and deleting
## the `notification` above reddens by name with nothing retuned and no new colour. Every Label
## variation's INK coincides with plain `Label`'s, so no colour assertion can catch it -- which is
## what ASSA-246 disclosed and ASSA-252 fixed.
static func drawn_font_size(label: Label) -> int:
	poke(label)
	return label.get_theme_font_size(&"font_size")
