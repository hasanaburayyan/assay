extends SceneTree
## CI: local -- reads labelled emptiness off a saved shot, so it needs a frame somebody chose

## LABELLED EMPTINESS IN THE HUD COLUMN, MEASURED OFF A SHOT (ASSA-134).
##
##   godot --headless --path . --script res://tools/blank_runs.gd -- <shot.png> [more.png ...]
##
## WHY THIS EXISTS. Maren found 146px of labelled void on the first screen a stranger sees by
## scanning `01-join.png` for rows carrying no ink (ASSA-117 comment, 21:39Z). Two of those gaps had
## been on screen for days with every test green, because a blank gap is not a thing any assertion
## about text or geometry looks at: `cursor` was a heading over a Label nobody had written to, and
## the `make` heading sat 53px above its own toggle. Neither was findable by re-reading the code --
## she did it with a one-off scan, and this is that scan kept, so the next person does not have to
## rebuild it or trust my arithmetic.
##
## **IT IS NOT A JUDGE AND DELIBERATELY PRINTS RATHER THAN VERDICTS.** Some blank space is right:
## the column ends above the window edge, a hidden section leaves nothing behind (ASSA-89), and
## breathing room between sections is the theme's `separation` doing its job. Which runs are DEFECTS
## is a Game Director's call on a picture, so this reports and stops. The verdict that machines can
## hold lives in `test_main_screen.gd`, which asserts no visible heading stands over nothing -- the
## rule, rather than a pixel count.
##
## THE BACKGROUND IS TAKEN FROM THE PICTURE, NOT FROM THE THEME: the most common colour in the
## column IS the panel, so this scan does not have to agree with `tools/build_theme.gd` about
## anything, and it keeps working if the palette moves.
##
## THE COLUMN'S x RANGE IS THE ONE MAREN MEASURED IN and is the HUD panel's own 320px at 1280x720
## (`AssayHud.PANEL`, right-aligned). A shot of another size is reported and skipped rather than
## scanned at the wrong place, because a scan of the map would call the sky a void.

const WINDOW_W := 1280
const X0 := 936
const X1 := 1256
## Below this, a gap is the theme's separation and not a hole. 25px is Maren's threshold, kept so
## numbers printed here can be compared with hers.
const MIN_RUN := 25


## **A ONE-SHOT TOOL CAN RUN FOR EVER TOO, AND THIS IS THE HALF ASSA-182 DID NOT FIX FIRST TIME.**
## `SceneTree`'s own `_process` returns false, so a tool with no `_process` of its own does not end when
## `_initialize` returns -- it ends when something calls `quit()`. A runtime error inside `_initialize`
## skips that call and the engine spins with no output and no exit: measured 2026-10-04 with a scratch
## script, alive after 25 s. The looping tools got a wall-clock ceiling; this needs no clock, because
## there is nothing a one-shot tool legitimately waits for.
##
## `_quitting` is set beside every `quit()` in this file rather than at the end of `_initialize`, so a
## deliberate early exit -- a bad argument, a missing world -- stays deliberate, and only a
## fall-through reaches the sentence below.
var _quitting := false


func _process(_delta: float) -> bool:
	if not _quitting:
		print("FAIL  blank_runs.gd: _initialize ended without asking to quit -- see the error above")
		quit(1)
	return true


func _initialize() -> void:
	var shots := OS.get_cmdline_user_args()
	if shots.is_empty():
		print("blank_runs: give me one or more PNGs of the real window")
		_quitting = true
		quit(2)
		return
	for path in shots:
		_scan(path)
	_quitting = true
	quit()


func _scan(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		print("%s: cannot be read" % path)
		return
	if img.get_width() != WINDOW_W:
		print(("%s: %dx%d, not %dpx wide -- the column's x range would land somewhere else, so "
				+ "this is not scanned") % [path.get_file(), img.get_width(), img.get_height(),
				WINDOW_W])
		return
	var bg := _panel_colour(img)
	var runs := PackedStringArray()
	var total := 0
	var start := -1
	var height := img.get_height()
	for y in height + 1:
		# ONE PAST THE BOTTOM, AND THAT ROW COUNTS AS INK: a run that reaches the window edge is the
		# biggest kind (Maren's 113px `cursor` gap was one) and a loop that ends at the last row never
		# closes it. **THIS LINE SHIPPED WRONG ONCE**: the sentinel row read as BLANK, so an open run
		# was simply dropped and the tool silently reported 149px where a scratch script had found
		# 262px. A comment claiming the edge case and code not doing it is the defect class I keep a
		# rule about, and the only reason it was caught is that I had two numbers for one picture.
		var inked := y >= height or _row_has_ink(img, y, bg)
		if inked:
			if start >= 0 and y - start >= MIN_RUN:
				runs.append("y %4d..%-4d %4dpx" % [start, y, y - start])
				total += y - start
			start = -1
		elif start < 0:
			start = y
	print("%s  panel #%08x  column x %d..%d  %d blank runs >= %dpx, %dpx in all"
			% [path.get_file(), bg, X0, X1, runs.size(), MIN_RUN, total])
	for run in runs:
		print("    ", run)


## The commonest colour in the column, which is the panel it is drawn on.
func _panel_colour(img: Image) -> int:
	var counts := {}
	for y in img.get_height():
		for x in range(X0, mini(X1, img.get_width())):
			var key := img.get_pixel(x, y).to_rgba32()
			counts[key] = int(counts.get(key, 0)) + 1
	var best := 0
	var bg := 0
	for key in counts:
		if int(counts[key]) > best:
			best = int(counts[key])
			bg = int(key)
	return bg


func _row_has_ink(img: Image, y: int, bg: int) -> bool:
	for x in range(X0, mini(X1, img.get_width())):
		if img.get_pixel(x, y).to_rgba32() != bg:
			return true
	return false
