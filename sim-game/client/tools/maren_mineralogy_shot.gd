extends SceneTree
## **THE MINERALOGY BODY AT THE HUD COLUMN'S REAL WIDTH, WHICH NOBODY HAS BEEN ABLE TO SEE** (Maren,
## ASSA-241 box 11 / ASSA-254).
##
##   godot --path client --script res://tools/maren_mineralogy_shot.gd -- <out_dir>
##   (A GUI RUN. Never --headless: a dummy rendering driver photographs a blank frame and exits 0.)
##
## **WHY THIS TOOL EXISTS.** Limpet refused to fake a 1x shot and was right to: Nacre's tab strip is
## not on main, so there is nowhere to open the tab, and adding it to the column as a panel of its
## own is the thing I ruled against. But the body is a `VBoxContainer` that "paints no surface, owns
## no position and spends no colour literal" (its own docstring), so it can be stood up at the width
## it will really have -- the HUD column is x 936..1280, **344 px** -- and photographed today.
##
## **WHAT THIS PICTURE IS, SAID BEFORE IT IS JUDGED.** It is the ANSWER HALF at the real width, not
## the whole tab: the evidence rows are `main.gd::_species_row`'s and arrive from the caller, and the
## strip's own chrome does not exist yet. So it cannot answer "does the tab fit". It answers the
## three things that are the body's own and are already fixed:
##
##   1. how many lines a 125-character sentence takes at 344 px, and therefore how much of Nacre's
##      313 px worst-case tab budget is gone before the evidence list starts;
##   2. whether the empty sentence reads as news rather than as a missing feature;
##   3. **whether `go here` is on screen in the case my ASSA-241 ruling 5 says it must be absent.**
##
## THREE STATES, AND THE MIDDLE ONE IS THE POINT. On seed 14247 the hard-enough answer is "right
## where you are standing" (`near.heading == None`), and `proximity_facts` still hands the client a
## `Some` tile -- the one under the player's feet. `mineralogy.gd` gates the button on `tile != null`,
## so the prediction this shot tests is that a live `go here` appears there. If it does, it is a
## button whose only effect is to walk you where you already are.
##
## Prints `MINERALOGY SHOT OK` LAST and only on success, because Godot exits 0 even on a compile
## error.

## The HUD column, x 936..1280 (ASSA-239). The body never sets its own width; this is the width the
## strip will give it, so it is the only width worth wrapping a sentence at.
const COLUMN := 344
const GAP := 24
const PAD := 12
## The played screen's panel background, stated and not sampled (ASSA-224).
const PANEL_BG := Color8(37, 40, 48)
const SETTLE_FRAMES := 6

const BURNS := 0
const HARD_ENOUGH := 1

var _out := ""
var _settle := 0
var _done := false
var _tabs: Array = []
var _notes := PackedStringArray()


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		push_error("usage: -- <out_dir>")
		quit(2)
		return
	_out = argv[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.theme = load("res://theme/assay.tres")
	var back := ColorRect.new()
	back.color = PANEL_BG
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var row := HBoxContainer.new()
	row.position = Vector2(PAD, PAD)
	row.add_theme_constant_override("separation", GAP)
	root.add_child(row)
	# THE THREE STATES, in the order a reader meets them: the question Rainy asked, the case my
	# ruling is about, and the honest nothing.
	_add(row, "14247 · burns", "14247", BURNS)
	_add(row, "14247 · hard enough", "14247", HARD_ENOUGH)
	_add(row, "seed 1 · nothing qualifies", "1", HARD_ENOUGH)


## One column: a caption, then the real body at the real width.
##
## The caption is `Quiet` and sits ABOVE the body rather than across it, for the same reason Cove's
## window pair draws its labels into a band: a caption over the thing being judged changes the thing
## being judged.
func _add(row: HBoxContainer, caption: String, seed_text: String, which: int) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(COLUMN, 0)
	col.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.theme_type_variation = &"Quiet"
	label.text = caption
	col.add_child(label)
	var tab := AssayMineralogy.new()
	tab.custom_minimum_size = Vector2(COLUMN, 0)
	col.add_child(tab)
	row.add_child(col)
	# A REAL WORLD THROUGH THE HOST THE CLIENT REALLY USES, never a dictionary I typed: the whole
	# claim of this tab is that the line is the sim's sentence with no client in between.
	var host := AssaySimHost.new()
	if not host.start(AssaySimHost.fresh_welcome_json(seed_text, "maren")):
		_notes.append("%s: could not stand a world up" % caption)
		return
	var players: Array = host.players()
	if players.is_empty():
		_notes.append("%s: the welcome carried no player" % caption)
		return
	var me := int((players[0] as Dictionary).get("id", -1))
	var answers := host.proximity_answers(me)
	tab.show_answer(answers, which)
	_tabs.append({"caption": caption, "tab": tab, "answers": answers, "which": which})


func _process(_delta: float) -> bool:
	if _done:
		return true
	_settle += 1
	if _settle < SETTLE_FRAMES:
		return false
	_done = true
	var image := root.get_texture().get_image()
	var path := _out.path_join("mineralogy-344px.png")
	if image.save_png(path) != OK:
		push_error("could not write %s" % path)
		quit(1)
		return true
	print("wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	_report()
	quit(0)
	return true


func _report() -> void:
	for note in _notes:
		print("NOTE: %s" % note)
	for entry in _tabs:
		var tab: AssayMineralogy = entry["tab"]
		var answer: Dictionary = (entry["answers"] as Array)[entry["which"]]
		var text := String(answer.get("headline", ""))
		var tile: Variant = answer.get("tile")
		print("")
		print("--- %s ---" % entry["caption"])
		print("  headline (%d chars): %s" % [text.length(), text])
		print("  tile from the binding: %s" % ("nil" if tile == null else str(tile)))
		print("  headline drawn: %d x %d px, %d line(s) at %d px wide"
				% [tab.headline.size.x, tab.headline.size.y,
						tab.headline.get_line_count(), COLUMN])
		print("  go here VISIBLE: %s   (ruling 5: absent when the answer has no heading)"
				% str(tab.go_here.visible))
		print("  go here variation: `%s`   (ruling 5 asks for `Quiet`)"
				% str(tab.go_here.theme_type_variation))
		print("  answer block height, before any evidence row: %d px" % tab.size.y)
	print("")
	print("MINERALOGY SHOT OK")
