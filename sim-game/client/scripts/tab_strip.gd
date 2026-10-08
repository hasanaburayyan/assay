class_name AssayTabStrip
extends VBoxContainer
## ONE TABBED PANEL: a visible row of names, and one body on screen at a time (ASSA-247).
##
## **THE BOARD ASKED FOR THIS SHAPE BY NAME.** Rainy, via Wren's ruling on ASSA-198: *"a large
## dedicated space for the gameplay window, a tabbed panel with the various systems selectable at the
## top ... Then below that panel, the Log."*
##
## **WHY A TAB STRIP AND NOT A KEYBOARD SUMMON**, which is Maren's reason and worth keeping where the
## mechanism lives: *a tab strip is a VISIBLE affordance and a key is an invisible one.* Factorio can
## afford invisible summons because it has a hundred hours to teach them; our player has five
## minutes and cannot summon what they do not know exists. So nothing the demo loop needs goes
## behind a key, and the names of the systems are always on screen even when their bodies are not.
##
## **WHAT THIS DELIBERATELY DOES NOT DECIDE: WHICH SECTIONS ARE TABS.** That is an open ruling —
## Maren ruled *what you carry* always-on, Rainy named "Inventory" as a tab, and the measurement on
## ASSA-247 says the choice is worth 298 px. The tab list is a PARAMETER of this class, so the
## ruling can land either way without this file changing. Nothing is wired into `main.gd` yet.
##
## **"ADDING A TAB IS ONE ENTRY, NOT A RE-LAYOUT"** is Rainy's constraint ("so long as the scope is
## kept in mind") and it is the property `test_tab_strip.gd` actually asserts: `add_tab` appends and
## touches nothing that is already here, so a sixth tab is a call and not a redesign.
##
## **THE NAMES WRAP, AND THAT IS THE WHOLE REASON FOR `HFlowContainer`.** An `HBoxContainer` would
## make the fifth name shrink the other four, or push one off the edge of a 320 px panel — a tab you
## cannot read is worse than a tab that is on the second row. Wrapping is what makes "built to grow"
## true of the pixels and not only of the API, and MINERALOGY (ASSA-241) is a known future entry.

## The name of the tab whose body is on screen, or "" before anything is added.
var _selected := ""
## Tab name -> its body `Control`, in insertion order (a Dictionary keeps it in Godot 4).
var _bodies := {}
## Tab name -> its `Button` in the strip.
var _buttons := {}
## Names whose tab exists but whose system does not. Kept apart from `_bodies` so that "is this
## real" is a question about the strip's own state, never a guess from an empty body.
var _placeholders := {}

var _names: HFlowContainer = null
## THE ONE BOX THAT SCROLLS IN THIS COLUMN, and the names are deliberately NOT in it.
##
## **A TAB'S NAME IS A CONTROL AND ITS BODY IS CONTENT.** Wren's fold rule is about controls, so the
## strip is pinned exactly the way `_halt` and the log's toggle are pinned in `main.gd`: a player who
## scrolls a long list must not lose the way back to the other systems.
##
## **AND THE LIST THAT MAY SCROLL IS THE ONE INSIDE A TAB** (Wren, ratified by Maren): *"a list of
## forty rocks scrolling is a list; a cut Make button is a defect."* One box here rather than one per
## body, because a tab's body is only ever as tall as its own content and exactly one is visible --
## so this box's content height IS the open tab's height, and the scrollbar appears on the tabs that
## need it and on no others.
var _content: ScrollContainer = null
## The bodies' own parent inside the scroll box. A `ScrollContainer` lays every child at its origin,
## so the bodies go in a `VBoxContainer` child rather than in the box itself -- with one visible the
## VBox is exactly that body's height, which is the number the scroll box reads.
var _bodies_box: VBoxContainer = null

## Emitted after the visible body changes, with the newly selected name. `main.gd` has nothing to do
## on a tab change today; the signal exists so that a tab which must refresh on reveal can, without
## this class knowing what any of them contain.
signal tab_selected(name: String)


func _init() -> void:
	_names = HFlowContainer.new()
	_names.name = "TabNames"
	add_child(_names)
	# A `ScrollContainer`, NOT a `PanelContainer`: the column this lives in already paints its own
	# surface (`main.gd`'s `COLUMN_SURFACE`), and a second panel inside it would draw a box inside a
	# box. Same reasoning as the column's own `pad`.
	#
	# HORIZONTAL SCROLLING OFF, which is ASSA-98's lesson one level up: this box is ~308px wide and a
	# row told to be 320 is clipped rather than reachable. Everything in here derives its width.
	_content = ScrollContainer.new()
	_content.name = "TabContent"
	_content.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_bodies_box = VBoxContainer.new()
	_bodies_box.name = "TabBodies"
	# EXPAND_FILL so a body gets the box's width rather than its own minimum (ASSA-98 again).
	_bodies_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_bodies_box)


## ADD ONE TAB. The whole of "adding a tab" — there is no second place to register it, which is the
## point of the constraint this is built to.
##
## `body` is reparented into the content area and hidden unless it is the first tab, so a caller
## cannot leave two bodies visible by forgetting to select one. The first tab added is selected,
## because a strip that opens on nothing is a labelled empty gap (ASSA-134's defect, one layer up).
##
## **QUIET, BECAUSE A TAB STRIP IS FURNITURE** (Maren: ACCENT means "press this next" and nothing
## else). The strip names where things are; it is never the thing to press next, and a screen has
## one primary — on the play screen that is `Mine`, not a tab.
func add_tab(tab_name: String, body: Control, placeholder := false) -> Button:
	if tab_name == "":
		push_error("AssayTabStrip.add_tab: a tab with no name cannot be selected or read.")
		return null
	if _bodies.has(tab_name):
		push_error("AssayTabStrip.add_tab: '%s' is already a tab; names are how tabs are selected."
				% tab_name)
		return null
	var button := Button.new()
	button.text = tab_name
	button.theme_type_variation = &"Quiet"
	button.toggle_mode = true
	# **A PLACEHOLDER IS VISIBLY NOT-YET** (Wren, correcting his own "build nothing"): *"no fake
	# content, no dead button that looks live."* Disabled is the honest state — the name is there so
	# the shape of the game is legible, and the control refuses to look pressable.
	button.disabled = placeholder
	if placeholder:
		_placeholders[tab_name] = true
	button.pressed.connect(func() -> void: select(tab_name))
	_names.add_child(button)
	_buttons[tab_name] = button
	body.visible = false
	_bodies_box.add_child(body)
	_bodies[tab_name] = body
	if _selected == "" and not placeholder:
		select(tab_name)
	else:
		_sync_pressed()
	return button


## **A SELECTED TAB IS A STATE, NOT A VERB** (Maren's ruling, 2026-10-06 18:34). `ACCENT` means
## *press this next*; a tab that is already open cannot mean that, so selection is marked by RANK --
## `INK` for the open tab against the other three at `INK_MUTED`, the 1.80:1 the palette already owns.
##
## **THIS CLASS USED TO STATE THAT ITSELF AND NO LONGER DOES (ASSA-267).** `_mark_selection_by_rank`
## lived here and wrote `font_pressed_color` and `font_hover_pressed_color` onto every tab button,
## because `Quiet` declared `ACCENT` for its pressed state and a four-tab strip is the first control
## group in this client where exactly one member is ALWAYS pressed. That was the local half of the
## fix, taken hours before a gate, and it said in its own comment that the literal belonged to the
## theme. **The literal is now out of the theme**, so the override would be a second place to retune
## a strip and a surface obeying a screen rule by hand.
##
## **WHAT REPLACED IT IS NOT NOTHING, AND THAT IS THE PART WORTH CHECKING.** `Quiet` now declares
## `font_pressed_color = INK` and `font_hover_pressed_color = INK`, so a selected tab draws the rank
## by inheritance. The guard is no longer a `push_error` in this file: it is
## `test_tab_strip.gd::test_the_open_tab_is_marked_by_rank_and_not_by_the_accent`, which asks each
## button for the colour it will actually draw -- with no type argument, the read the engine itself
## makes -- and fails if it is the accent, if it is not the ordinary button ink, or if the open and
## closed inks do not differ in luminance. Nacre wrote that test to flip to this branch on the day
## this item landed rather than go red for a fix, and it did.


## SOMETHING THAT SITS UNDER WHICHEVER TAB IS OPEN, inside the scrolled area and after every body.
##
## **ONE CALLER AND ONE REASON, so this does not become a second way to add content.** The cursor
## readout is not a system and has no control in it: it is what the tile under the pointer says. A
## tab would make a hover readout that does nothing while you hover, and the always-on block cannot
## afford its 207 px. Last inside the scroll, it cannot push a control below the fold, which is the
## only property Wren's rule asks of it.
##
## Always visible, deliberately: `select` hides bodies, and a footer that disappeared with a tab
## would be a readout that comes and goes with a choice that has nothing to do with it.
## **IT WRAPS, AND LEAVING THAT OUT PUSHED THE WHOLE COLUMN OFF THE SCREEN** (found 2026-10-06 by
## measuring a 1x shot, not by reading this file). A `Label` that does not wrap has a minimum width
## of its longest line -- the cursor readout measured **434 px** against a 320 px panel. A
## `ScrollContainer` with horizontal scrolling DISABLED adds its content's minimum width to its own,
## and a container sizes its child to `max(available, minimum)`, so that one Label pushed the scroll
## box to 438 px and every ancestor with it. The damage was not in the tab at all: `_log_toggle` sits
## in the chrome above this strip and was dragged out to the same width, so the column's ink ran to
## the window's last pixel on 77 rows.
##
## A tab's BODY got this in `main.gd`'s build loop and the footer did not, because the footer does not
## go through `add_tab`. Set here rather than at the caller so the strip's one footer slot cannot be
## given an unwrapped Label by a later caller who did not read this comment.
func add_footer(body: Control) -> void:
	var label := body as Label
	if label != null:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bodies_box.add_child(body)


## SHOW ONE TAB'S BODY AND HIDE THE REST. Returns false and SAYS SO on a name that is not a tab:
## this repo's standing rule is that no refusal is silent, and a mistyped tab name that quietly did
## nothing would read on screen as a tab that does not work.
func select(tab_name: String) -> bool:
	if not _bodies.has(tab_name):
		push_error("AssayTabStrip.select: '%s' is not a tab. Have: %s"
				% [tab_name, ", ".join(tab_names())])
		return false
	if _placeholders.has(tab_name):
		push_error("AssayTabStrip.select: '%s' is a placeholder; it has no system behind it yet."
				% tab_name)
		return false
	_selected = tab_name
	for name_of in _bodies:
		(_bodies[name_of] as Control).visible = name_of == tab_name
	# **BACK TO THE TOP, BECAUSE THE SCROLL POSITION BELONGS TO THE LIST THAT WAS SCROLLED.** Leave it
	# and scrolling to the fortieth rock, then pressing Make, opens the make tab at the offset the
	# rocks list left behind -- which on a short body the engine clamps to 0 but on a tall one shows
	# its middle, with the first row off the top. A tab opens at its own beginning.
	_content.scroll_vertical = 0
	_sync_pressed()
	tab_selected.emit(tab_name)
	return true


## WHICH TAB IS ON SCREEN. "" only before the first real tab is added.
func selected() -> String:
	return _selected


## Every tab's name, in the order they were added — which is the order they are drawn.
func tab_names() -> PackedStringArray:
	var out := PackedStringArray()
	for name_of in _bodies:
		out.append(String(name_of))
	return out


## Is this name a tab whose system does not exist yet?
func is_placeholder(tab_name: String) -> bool:
	return _placeholders.has(tab_name)


## The body a tab shows, or null. For tests and for a caller that must refresh one tab's contents.
func body_of(tab_name: String) -> Control:
	return _bodies.get(tab_name, null) as Control


## THE BOX A TAB'S BODY SCROLLS IN. Held out for `window_shot.gd`'s clip report and for the tests
## that hold "a tall list cannot hide a button" -- both ask the question about a named node rather
## than counting children, and `main.gd`'s `_scroll` is this box now.
func scroll_box() -> ScrollContainer:
	return _content


## THE ROW OF NAMES. For the test that holds the strip OUTSIDE the scroll box: the property is that
## a player who scrolls a list keeps the way back to the other systems.
func names_box() -> HFlowContainer:
	return _names


## THE STRIP'S OWN BUTTONS AGREE WITH THE BODY ON SCREEN. `toggle_mode` buttons hold their own
## `button_pressed`, so a tab selected in code rather than by a click would leave the previous name
## looking current — the strip would be lying about where you are.
func _sync_pressed() -> void:
	for name_of in _buttons:
		(_buttons[name_of] as Button).button_pressed = name_of == _selected
