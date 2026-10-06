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
func test_no_tab_wears_the_accent() -> bool:
	var strip := _strip_of(["make", "bench", "rocks"])
	for n in strip.tab_names():
		var button: Button = null
		for child in strip.get_child(0).get_children():
			var b := child as Button
			if b != null and b.text == String(n):
				button = b
		if button == null:
			return _fail("tab '%s' has no button in the strip" % n)
		if button.theme_type_variation != &"Quiet":
			return _fail("tab '%s' is themed '%s', want Quiet: a tab is furniture, not the primary"
					% [n, button.theme_type_variation])
	return true


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
func test_selecting_a_tab_that_does_not_exist_changes_nothing() -> bool:
	var strip := _strip_of(["make", "bench"])
	strip.select("bench")
	if strip.select("rocks"):
		return _fail("selecting a tab that does not exist reported success")
	if strip.selected() != "bench":
		return _fail("a refused selection moved the panel to '%s'" % strip.selected())
	var seen := _visible_bodies(strip)
	if seen.size() != 1 or seen[0] != "bench":
		return _fail("a refused selection left these visible: %s" % ", ".join(seen))
	return true


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
