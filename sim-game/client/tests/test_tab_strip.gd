extends RefCounted
## THE TABBED SYSTEMS PANEL'S MECHANISM (ASSA-247), tested for the properties the rulings name.
##
## **NOT ONE PIXEL IS ASSERTED HERE, DELIBERATELY.** The suite runs inside `SceneTree._initialize`:
## `_ready` never fires, no frame is drawn and no container ever lays out, so every `position` and
## every `size.y` reads 0.0 and an assertion about them passes while meaning nothing. Everything
## below is about STATE a flag can hold — which body is visible, which button is pressed, what the
## strip refuses. The geometry of this panel is measured in a real window by
## `tools/nacre_tab_budget_probe.gd`, which is where that claim belongs.
##
## What the rulings ask of the mechanism, and so what is asserted:
##  - adding a tab is ONE entry and disturbs nothing already there (Rainy, via Wren)
##  - exactly one body is on screen at a time (Maren: "one system at a time")
##  - the strip is furniture: no ACCENT on any tab (Maren: ACCENT means "press this next")
##  - and the OPEN tab is marked by RANK, asked of the colour a Button resolves rather than of the
##    variation it names — the clause above passed for two days while the strip drew accent green
##  - a placeholder is visibly not-yet and cannot show fake content (Wren)
##  - no refusal is silent (repo `CLAUDE.md`)

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


func _strip_of(names: Array) -> AssayTabStrip:
	var strip := AssayTabStrip.new()
	for n in names:
		var body := Label.new()
		body.text = "body of %s" % n
		strip.add_tab(String(n), body)
	return strip


## HOW MANY BODIES A PLAYER CAN SEE AT ONCE. `visible` and not `is_visible_in_tree`, because nothing
## here is in a tree: the question is what this class set, which is the only thing it controls.
func _visible_bodies(strip: AssayTabStrip) -> PackedStringArray:
	var out := PackedStringArray()
	for n in strip.tab_names():
		var body := strip.body_of(String(n))
		if body != null and body.visible:
			out.append(String(n))
	return out


func test_one_system_is_on_screen_at_a_time() -> bool:
	var strip := _strip_of(["make", "bench", "rocks"])
	var seen := _visible_bodies(strip)
	if seen.size() != 1:
		return _fail("a fresh strip shows %d bodies, want exactly 1: %s"
				% [seen.size(), ", ".join(seen)])
	if strip.selected() != "make":
		return _fail("the first tab added should be the one on screen, got '%s'" % strip.selected())
	if not strip.select("rocks"):
		return _fail("selecting a real tab was refused")
	seen = _visible_bodies(strip)
	if seen.size() != 1 or seen[0] != "rocks":
		return _fail("after selecting rocks the visible bodies are: %s" % ", ".join(seen))
	return true


## **THE CONSTRAINT RAINY ASKED FOR, AS A TEST RATHER THAN AN INTENTION.** Adding a tab must be one
## entry and not a re-layout, so this adds a fourth to a settled strip and demands that NOTHING
## about the first three moved: same names, same order, same body objects, same selection.
##
## The body-identity check is the one that would catch a rebuild: an implementation that threw the
## content area away and re-added every body would keep the names and the order and fail here.
func test_adding_a_tab_disturbs_nothing_already_there() -> bool:
	var strip := _strip_of(["make", "bench", "rocks"])
	strip.select("bench")
	var before := strip.tab_names()
	var before_bodies := []
	for n in before:
		before_bodies.append(strip.body_of(String(n)))
	strip.add_tab("mineralogy", Label.new(), true)
	var after := strip.tab_names()
	if after.size() != before.size() + 1:
		return _fail("adding one tab changed the count from %d to %d" % [before.size(), after.size()])
	for i in range(before.size()):
		if after[i] != before[i]:
			return _fail("tab %d was '%s' and is now '%s': the order moved" % [i, before[i], after[i]])
		if strip.body_of(String(before[i])) != before_bodies[i]:
			return _fail("the body of '%s' is a different object after adding a tab" % before[i])
	if strip.selected() != "bench":
		return _fail("adding a tab changed the selection to '%s'" % strip.selected())
	var seen := _visible_bodies(strip)
	if seen.size() != 1 or seen[0] != "bench":
		return _fail("adding a tab left these bodies visible: %s" % ", ".join(seen))
	return true


## A TAB STRIP IS FURNITURE (Maren). ACCENT means "press this next" and nothing else, and a row of
## six accents would mean it nowhere. The screen's one primary is a verb like `Mine`, never a tab.
##
## **THIS TEST PASSED WHILE THE STRIP DREW THE ACCENT, AND THE LESSON IS THE QUESTION IT ASKED.** It
## asked for the VARIATION NAME. Maren then counted 172 accent-family pixels on a real 1x shot,
## exactly where `mineralogy` is drawn, core `(128,229,140)` — byte-identical to `Mine`'s. The green
## was honest: `Quiet` is the right variation and `Quiet` declares `font_pressed_color = ACCENT`
## itself, for lone toggles where pressed is occasional. A four-tab strip is the first group here
## where one member is always pressed. **The name of a variation is not the colour it draws**, which
## is the fourth defect this week where the declared property passed and the drawn one differed.
##
## So the clause below is kept — furniture is still a property worth holding — and the colour moved
## to its own test, which asks the RESOLVED value a Button will draw.
func test_no_tab_wears_the_accent() -> bool:
	var strip := _strip_of(["make", "bench", "rocks"])
	for n in strip.tab_names():
		var button := _button_for(strip, String(n))
		if button == null:
			return _fail("tab '%s' has no button in the strip" % n)
		if button.theme_type_variation != &"Quiet":
			return _fail("tab '%s' is themed '%s', want Quiet: a tab is furniture, not the primary"
					% [n, button.theme_type_variation])
	return true


func _button_for(strip: AssayTabStrip, tab_name: String) -> Button:
	for child in strip.names_box().get_children():
		var b := child as Button
		if b != null and b.text == tab_name:
			return b
	return null


## **A SELECTED TAB IS A STATE, NOT A VERB** (Maren, 2026-10-06 18:34), asked of the colour a Button
## RESOLVES rather than of the variation it names — which is the whole reason this is a second test
## and not another clause in the one above.
##
## Three things, and the third is what stops this from being a check that cannot fail.
##
## 1. **THE OPEN TAB DOES NOT DRAW THE ACCENT.** `ACCENT` is read as the colour this theme FILLS its
##    one primary with, never typed: a literal here would pass the day somebody retuned the token.
## 2. **IT DRAWS THE ORDINARY INK, AND THE RANK IS REAL.** Selection is marked by `INK` over the
##    other tabs' `INK_MUTED`, so the test asks for the luminance ORDER as well as the two values —
##    equal colours would satisfy "not the accent" and mark nothing at all.
## 3. **THE COINCIDENCE IS DECLARED** (the pattern `test_main_screen.gd` uses for the theme poke).
##    Today `Quiet` declares `font_pressed_color = ACCENT`, so the override is load-bearing and that
##    is asserted. **ASSA-267 takes the literal out of the theme**, and on the day it lands this
##    clause flips to the other branch by itself instead of going red for a fix: either the variation
##    still declares the accent (so the override must differ from it) or it no longer does (so there
##    is nothing left to override and the strip may inherit). A test that has to be edited by the
##    person fixing the thing it guards gets edited into agreement.
func test_the_open_tab_is_marked_by_rank_and_not_by_the_accent() -> bool:
	var theme: Theme = load("res://theme/assay.tres")
	if theme == null:
		return _fail("no theme/assay.tres to read declared values from")
	var primary := theme.get_stylebox(&"normal", &"Primary") as StyleBoxFlat
	if primary == null:
		return _fail("the theme declares no flat `normal` box for `Primary`, so this test cannot "
				+ "name the accent without typing a literal, which is what it refuses to do")
	var accent := primary.bg_color
	var ink := theme.get_color(&"font_color", &"Button")
	var muted := theme.get_color(&"font_color", &"Quiet")
	var strip := _strip_of(["make", "inventory", "bench", "mineralogy"])
	var ok := true
	for n in strip.tab_names():
		var button := _button_for(strip, String(n))
		if button == null:
			return _fail("tab '%s' has no button in the strip" % n)
		# **THE READ WITH NO TYPE ARGUMENT, WHICH IS THE ONE THE ENGINE ITSELF MAKES WHEN IT DRAWS.**
		# An override is consulted FIRST on this path and bypasses the type chain entirely, so this
		# is an honest read of the colour the label will take even in a harness with no layout pass.
		#
		# **AND IT HAS TO BE THIS ONE, NOT A READ WITH A TYPE.** Godot compares the `theme_type`
		# argument against the node's own CLASS before building the type list, so
		# `get_theme_color(&"font_color", &"Button")` on a `Quiet` Button resolves the VARIATION and
		# returns `INK_MUTED`. That is the bug this test caught in my first fix: the strip marked its
		# open tab in the same colour as its closed ones, and "no accent" was perfectly true of it.
		for state in [&"font_pressed_color", &"font_hover_pressed_color"]:
			var drawn: Color = button.get_theme_color(state)
			if drawn.is_equal_approx(accent):
				ok = _fail(("the open tab '%s' draws %s for `%s`, the colour `Primary` is filled "
						+ "with. ACCENT means `press this next` and a tab already open cannot mean "
						+ "that (Maren, ASSA-247)") % [n, drawn, state])
			if not drawn.is_equal_approx(ink):
				ok = _fail(("the open tab '%s' draws %s for `%s`, want the theme's ordinary button "
						+ "ink %s: selection is marked by RANK, and a third colour is a token "
						+ "nobody chose") % [n, drawn, state, ink])
		# A CLOSED TAB IS THE VARIATION'S BUSINESS AND NOT THIS CLASS'S. Restating `INK_MUTED` here
		# would be a second place to retune the strip, and `Quiet` is already the place.
		if button.has_theme_color_override(&"font_color"):
			ok = _fail(("tab '%s' overrides its resting ink. A closed tab keeps `Quiet`'s %s; this "
					+ "class states the SELECTED colour only, because that is the only one the "
					+ "variation gets wrong") % [n, muted])
	# THE RANK ITSELF. Two tabs inked the same colour would pass every clause above and tell a player
	# nothing about where they are.
	var separation := AssayHud.relative_luminance(ink) - AssayHud.relative_luminance(muted)
	if separation <= 0.0:
		ok = _fail(("the open tab's ink %s is not brighter than a closed tab's %s, so selection is "
				+ "marked by nothing a player can see") % [ink, muted])
	# CLAUSE 3: the declared coincidence, which is ASSA-267's to end.
	var declared := theme.get_color(&"font_pressed_color", &"Quiet")
	if declared.is_equal_approx(accent):
		var probe := _button_for(strip, "make")
		if probe.get_theme_color(&"font_pressed_color").is_equal_approx(declared):
			ok = _fail(("`Quiet` still declares the accent for its pressed state and the strip is "
					+ "not overriding it: a tab inherits %s. If ASSA-267 has landed, the theme is "
					+ "what changed and this clause goes quiet on its own.") % declared)
	return ok


## **A PLACEHOLDER IS VISIBLY NOT-YET AND CANNOT BE PRESSED INTO SHOWING NOTHING** (Wren: "no fake
## content, no dead button that looks live"). Two halves, and the second is the one that matters:
## a disabled-looking button that still selected an empty body would be the fake content the rule
## forbids, reached a different way.
func test_a_placeholder_tab_is_not_yet_and_shows_no_fake_content() -> bool:
	var strip := AssayTabStrip.new()
	strip.add_tab("make", Label.new())
	strip.add_tab("mineralogy", Label.new(), true)
	if not strip.is_placeholder("mineralogy"):
		return _fail("a tab added as a placeholder does not report itself as one")
	var button: Button = null
	for child in strip.get_child(0).get_children():
		var b := child as Button
		if b != null and b.text == "mineralogy":
			button = b
	if button == null:
		return _fail("the placeholder has no button")
	if not button.disabled:
		return _fail("the placeholder's button is enabled: a dead button that looks live")
	if strip.select("mineralogy"):
		return _fail("a placeholder was selectable, so the panel can show an empty body")
	if strip.selected() != "make":
		return _fail("a refused placeholder changed the selection to '%s'" % strip.selected())
	var seen := _visible_bodies(strip)
	if seen.size() != 1 or seen[0] != "make":
		return _fail("a refused placeholder left these visible: %s" % ", ".join(seen))
	return true


## A STRIP WHOSE FIRST TAB IS A PLACEHOLDER MUST NOT OPEN ON IT. Caught by writing the test: a
## naive "select the first tab added" would open the panel on a system that does not exist.
func test_a_strip_does_not_open_on_a_placeholder() -> bool:
	var strip := AssayTabStrip.new()
	strip.add_tab("mineralogy", Label.new(), true)
	if strip.selected() != "":
		return _fail("a strip of only placeholders selected '%s'" % strip.selected())
	if _visible_bodies(strip).size() != 0:
		return _fail("a strip of only placeholders put a body on screen")
	strip.add_tab("make", Label.new())
	if strip.selected() != "make":
		return _fail("the first REAL tab should open the panel, got '%s'" % strip.selected())
	return true


## NO REFUSAL IS SILENT, and no refusal half-happens. A name that is not a tab must leave the panel
## exactly as it was rather than blanking it.
##
## **AND "NOTHING" INCLUDES THE SCROLL OFFSET**, which this test did not look at while claiming the
## whole word. `select()` returns before it touches the box, so the property holds today; the point
## of asserting it is that the reset below is now a thing someone might move, and the move that put
## it ABOVE the two refusals would be silent in every other assertion here.
func test_selecting_a_tab_that_does_not_exist_changes_nothing() -> bool:
	var strip := _strip_of(["make", "bench"])
	strip.select("bench")
	var box := strip.scroll_box()
	var offset := _scroll_to(box, 240)
	if offset == 0:
		return _fail("the fixture could not hold a scroll offset, so the clause about it asks nothing")
	if strip.select("rocks"):
		return _fail("selecting a tab that does not exist reported success")
	if strip.selected() != "bench":
		return _fail("a refused selection moved the panel to '%s'" % strip.selected())
	if box.scroll_vertical != offset:
		return _fail("a refused selection moved the scroll from %d to %d: the refusal had a side "
				% [offset, box.scroll_vertical] + "effect the player can see")
	var seen := _visible_bodies(strip)
	if seen.size() != 1 or seen[0] != "bench":
		return _fail("a refused selection left these visible: %s" % ", ".join(seen))
	return true


## **A TAB OPENS AT ITS OWN BEGINNING, AND NOTHING HELD IT TO THAT UNTIL NOW** (ASSA-277, and the
## idea is Limpet's rather than mine).
##
## `select()` writes `scroll_box().scroll_vertical = 0`. `tools/nacre_tab_budget_probe.gd` prints an
## `off top` column that is zero on every one of 516 ticks BECAUSE OF THAT LINE — the probe selects
## every tick, so the zero was guaranteed before the first tick ran, and I quoted it as evidence for
## a day before withdrawing it. Limpet's reading is the better half: the reset is a real promise —
## *selecting a tab shows you the top of it* — and this file had nine tests and no mention of
## `scroll`. If the reset ever went, a player would open `make` at whatever offset Mineralogy's
## 826 px index was left on and meet the middle of a list. The column now rests on this rather than
## on an accident.
##
## **THE GUARD IN THE MIDDLE IS THE WHOLE TEST.** A `ScrollContainer` that never laid out has a
## scrollbar whose `max_value` is 0, so `scroll_vertical = 240` CLAMPS STRAIGHT BACK TO 0 and the
## last assertion would read `0 == 0` and pass with the reset deleted. `_scroll_to` gives the bar a
## range and returns what actually stuck, and a 0 here fails the test instead of flattering it.
func test_selecting_a_tab_shows_you_the_top_of_it() -> bool:
	var strip := _strip_of(["make", "bench", "rocks"])
	var box := strip.scroll_box()
	var offset := _scroll_to(box, 240)
	if offset == 0:
		return _fail("the fixture could not hold a scroll offset (scroll_vertical stayed 0 after "
				+ "being set to 240), so this test would pass with the reset deleted. It asks nothing.")
	if not strip.select("rocks"):
		return _fail("selecting a real tab was refused")
	if box.scroll_vertical != 0:
		return _fail("the box was scrolled to %d and opening another tab left it at %d: a tab opens "
				% [offset, box.scroll_vertical] + "at the offset the last list was left on")
	# AND AGAIN FOR THE TAB ALREADY OPEN, which is the case a `return` on `tab_name == _selected`
	# would quietly break: pressing the name you are on is how a player gets back to the top.
	offset = _scroll_to(box, 180)
	if offset == 0:
		return _fail("the fixture would not hold the second offset, so the re-select clause is mute")
	if not strip.select("rocks"):
		return _fail("re-selecting the open tab was refused")
	if box.scroll_vertical != 0:
		return _fail("pressing the open tab's own name left the box at %d" % box.scroll_vertical)
	return true


## SCROLL A BOX THAT HAS NEVER LAID OUT, and report what actually stuck rather than what was asked
## for. Without the bar's range, `ScrollContainer` clamps every write to 0 and any test built on it
## asserts nothing — see the test above, which fails on a 0 from here instead of passing.
func _scroll_to(box: ScrollContainer, want: int) -> int:
	var bar := box.get_v_scroll_bar()
	bar.max_value = 1000.0
	bar.page = 400.0
	box.scroll_vertical = want
	return box.scroll_vertical


## THE STRIP'S BUTTONS AGREE WITH WHAT IS ON SCREEN. `toggle_mode` buttons keep their own pressed
## state, so a tab chosen in code rather than by a click can leave the old name looking current --
## the strip telling the player they are somewhere they are not.
func test_the_pressed_name_is_the_body_on_screen() -> bool:
	var strip := _strip_of(["make", "bench", "rocks"])
	strip.select("rocks")
	var pressed := PackedStringArray()
	for child in strip.get_child(0).get_children():
		var b := child as Button
		if b != null and b.button_pressed:
			pressed.append(b.text)
	if pressed.size() != 1:
		return _fail("%d tab buttons look pressed, want 1: %s" % [pressed.size(), ", ".join(pressed)])
	if pressed[0] != "rocks":
		return _fail("'%s' looks current while 'rocks' is on screen" % pressed[0])
	return true


## A TAB MUST BE NAMEABLE AND UNIQUE, because the name is the only handle `select` has.
func test_a_nameless_or_repeated_tab_is_refused() -> bool:
	var strip := AssayTabStrip.new()
	if strip.add_tab("", Label.new()) != null:
		return _fail("a tab with no name was accepted; it could never be selected")
	strip.add_tab("make", Label.new())
	if strip.add_tab("make", Label.new()) != null:
		return _fail("a repeated tab name was accepted; select() would be ambiguous")
	if strip.tab_names().size() != 1:
		return _fail("refused tabs still landed: %s" % ", ".join(strip.tab_names()))
	return true
