extends SceneTree
## CI: local -- it needs a laid-out window: headless gives every field a rect of (0,0,0,0)
## **DOES THE ADDRESS A FRIEND IS HANDED FIT THE BOX THEY TYPE IT INTO?** (ASSA-318.)
##
##   godot --path . --script res://tools/limpet_host_fit.gd
##
## **THE QUESTION IS DECISION #40's AND IT IS ABOUT THE FAILURE PATH.** The board's words: *"a friend
## with no terminal downloads, enters a host address, plays."* Tailscale hands that friend a MagicDNS
## name, and when a join fails the only check they can make without a terminal is *does this string
## match the one I was sent*, character for character. **A `LineEdit` scrolls rather than truncates,
## so nothing is lost except the ability to SEE what you typed** -- which is the whole of that check.
##
## **WHY A TOOL AND NOT ARITHMETIC.** Maren filed ASSA-318 off a shipped frame at **6.29 px/char**
## and said in the item that the number is an optimistic bound, because it came from
## `localhost:7777` -- `l`, `:` and `1` are the font's thinnest glyphs. A MagicDNS name full of `m`,
## `w` and `b` is wider per character, so the real capacity is BELOW her 34.7 and the 31-character
## row she marked *fits* may not. Her box 1 asks for exactly this: the widest plausible address laid
## out and its width read off a real window, in the field's own font.
##
## **EVERY NUMBER COMES OFF THE LIVE FIELD**, never off a font I picked: the rect from the laid-out
## `LineEdit`, the usable width from its own `normal` stylebox's content margins, and the string
## widths from the font and size that node resolves through the project theme. So a theme change
## moves this instrument with it, which is `line_width.gd`'s rule applied to another surface.
##
## **IT JUDGES NOTHING.** It prints px and `fits` / `CLIPS` against the field's own usable width, and
## which option to take is Maren's ruling on the item (give the host the room, grow both, echo the
## overflow, or do nothing).

## **THE WALL CLOCK THIS RUN MAY NOT OUTLIVE** (ASSA-182's guard, `tests/test_tool_ceilings.gd`).
## 60 s is twenty times the longest this has taken: it opens a window, waits for a layout pass and
## measures. Reaching it means something stopped advancing.
const RUN_CEILING := 60.0

## Frames to let containers settle before anything is measured. A `Control`'s rect is `(0,0,0,0)`
## until the engine has sorted it, and reading one too early is the defect this file exists to avoid.
const SETTLE_FRAMES := 6

## **WHAT A FRIEND IS ACTUALLY HANDED.** The first four are Maren's own rows (ASSA-318), kept
## verbatim so her table and this one can be compared line for line. The rest are the same shapes in
## the font's WIDE glyphs -- `m`, `w`, `b` -- because her point is that a px/char ratio taken off
## `localhost:7777` is the narrowest the font gets and the real answer is below it.
const CANDIDATES := [
	# **THE ONE THE WIDTH IS SIZED TO** (ASSA-318, Maren's rewritten box 3). Read from `AssayHud` and
	# not copied, so this instrument measures the string the client is built around rather than my
	# memory of it -- the two agreeing by construction is the point.
	AssayHud.LONGEST_HOSTNAME,
	"localhost:7777",
	"192.168.1.42:7777",
	"100.101.102.103:7777",
	"hasans-mac.tail9a3f.ts.net:7777",
	"hasans-macbook-pro.tail9a3f.ts.net:7777",
	"mombo-macbook.tailwwmb.ts.net:7777",
	"wombwomb-macbook-pro.tailmmbw.ts.net:7777",
]

## **AND WHAT THE NAME FIELD IS HANDED**, which Maren's box 4 says nobody has looked at: the shipped
## default fills 86% of it before anyone types. `USER` is this machine's, so it is read at runtime
## rather than written here; these are the other plausible lengths.
const NAMES := [
	"ada",
	"hasanaburayyan",
	"hasan-abu-rayyan",
	"wombmachine-player",
]

var _screen: Node = null
var _left := SETTLE_FRAMES
var _done := false
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING


func _initialize() -> void:
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND, the reason every tool here gives: a `--script` run works inside
	# `SceneTree._initialize`, before the root window is in the tree.
	_screen._ready()
	print("window %s, viewport %s" % [DisplayServer.window_get_size(), root.size])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  limpet_host_fit.gd ran past its %ds ceiling: nothing advanced it"
				% int(RUN_CEILING))
		quit(1)
		return true
	if _left > 0:
		_left -= 1
		return false
	_measure()
	_done = true
	quit(0)
	return true


## **ONE FIELD: ITS ROOM, ITS FONT, AND WHAT THE STRINGS DO IN IT.**
##
## **USABLE IS THE RECT LESS THE STYLEBOX'S OWN MARGINS**, asked of the stylebox rather than guessed:
## a `LineEdit` draws its text inside `normal`'s content margins, so the field's width is not the
## width a string has to fit. Maren read 238 px of well and 218 px usable off a picture; this asks
## the node.
func _field(named: String, box: LineEdit, strings: Array) -> void:
	var rect := Rect2(box.global_position, box.size)
	var style := box.get_theme_stylebox(&"normal")
	var pad := 0.0
	if style != null:
		pad = style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)
	var usable := rect.size.x - pad
	var font := box.get_theme_font(&"font")
	var size := box.get_theme_font_size(&"font_size")
	print("")
	print("%s  rect %s  (%.0f x %.0f), stylebox margins %.0f, usable %.0f px, font size %d"
			% [named, rect, rect.size.x, rect.size.y, pad, usable, size])
	if rect.size.x <= 0.0:
		print("    NOT MEASURED: the field has no size, so this window never laid out")
		return
	if font == null:
		print("    NOT MEASURED: the field resolved no font")
		return
	print("    %-44s %7s %9s %10s" % ["string", "chars", "px", "px/char"])
	for entry in strings:
		var text := String(entry)
		var wide: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		print("    %-44s %7d %9.1f %10.2f  %s" % [text, text.length(), wide,
				wide / maxf(1.0, float(text.length())),
				"fits" if wide <= usable else "CLIPS by %.0f px" % (wide - usable)])
	# **THE CAPACITY IS REPORTED AS A RANGE, NOT A NUMBER** -- which is Maren's own caution made into
	# output. The widest and narrowest strings above give the font's spread, and a "how many
	# characters fit" taken from either end is wrong for the other.
	var narrow := 0.0
	var broad := 0.0
	for entry in strings:
		var text := String(entry)
		var each: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x \
				/ maxf(1.0, float(text.length()))
		narrow = each if narrow == 0.0 else minf(narrow, each)
		broad = maxf(broad, each)
	print("    CAPACITY %.0f px of room: %.0f characters of the narrowest string above, %.0f of the "
			% [usable, usable / maxf(0.01, narrow), usable / maxf(0.01, broad)]
			+ "widest (%.2f..%.2f px/char)" % [narrow, broad])


func _measure() -> void:
	var host := _screen._host as LineEdit
	var name_box := _screen._name as LineEdit
	if host == null or name_box == null:
		print("FAIL  the screen has no host or name field to measure")
		return
	# **THE VIEWPORT AT MEASURE TIME, NOT AT STARTUP** (ASSA-319's finding, in my own tool): a
	# `--script` run begins with a 100x100 root and the engine resizes it on the first frame, so the
	# number printed in `_initialize` is not the one these rects were laid out in.
	print("viewport at measure time %s, window %s" % [root.size, DisplayServer.window_get_size()])
	print("HOST FIELD, and what Decision #40 hands a friend to type into it")
	_field("host", host, CANDIDATES)
	var names := NAMES.duplicate()
	var shipped := String(name_box.text)
	if shipped != "" and not names.has(shipped):
		names.append(shipped)
	print("")
	print("NAME FIELD, shipped default `%s` (ASSA-318 box 4)" % shipped)
	_field("name", name_box, names)
	print("")
	print("HOST FIT MEASURED · no verdict here; the option is Maren's ruling on ASSA-318")
