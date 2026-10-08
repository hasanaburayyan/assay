extends SceneTree
## CI: local -- an instrument you point at a file of candidate log lines (ASSA-242). It
## answers a question somebody asks, not one a gate can ask on every push.
## **HOW WIDE IS THIS LINE IN THE LOG'S OWN FONT?** (ASSA-242's instrument.)
##
##   godot --headless --path . --script res://tools/line_width.gd -- <file-of-lines>
##
## One line of the file per measurement; blank lines and `#` lines are skipped so a file can be
## annotated. Prints each line's width in PIXELS at the font and size a log line really gets, and
## says whether it fits the log's two homes.
##
## **WHY PIXELS AND NOT CHARACTERS.** ASSA-242 is a length bug and the obvious instrument is
## `text.length()`, which is wrong twice over: the font is proportional, so `mass 111` and `mass 888`
## are different widths at the same character count, and a species name is 1-20 characters by the
## rename rule. Maren's box 1 says it in the acceptance: *measured on a real window, not on a string
## length*. This is the same quantity her shot measures, read off the font instead of off a picture --
## which is reproducible and which a test can assert. **It is NOT a substitute for her 1x judgement**:
## a number cannot say whether a sentence reads as one fact.
##
## **THE LABEL IS BUILT BY `main.gd::_note`, NOT BY THIS FILE.** A `Label.new()` here with a font I
## picked would measure my guess at the log's typography. The real screen is instantiated, `_note`
## makes the Label the log makes, and the font and size come off that node's own theme lookup -- so a
## theme change moves this instrument with it.
##
## **THE TWO HOMES, AND BOTH NUMBERS ARE MAREN'S, MEASURED ON A REAL 1280x720 WINDOW.** The log is a
## full-width overlay today and clips at ~888 px; under ASSA-276 move 1 it docks under the panel at
## 318 px. Quoted here rather than computed, because headless has no layout pass and a width this
## file computed would be an arithmetic claim about a window nobody opened.

const OVERLAY_PX := 888.0
const DOCKED_PX := 318.0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  usage: -- <file-of-lines>")
		quit(1)
		return
	var text := FileAccess.get_file_as_string(String(argv[0]))
	if text == "":
		print("FAIL  could not read %s (or it is empty)" % argv[0])
		quit(1)
		return

	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	var sample: Label = screen._note("x")
	var font: Font = sample.get_theme_font(&"font")
	var size: int = sample.get_theme_font_size(&"font_size")
	print("the log's font: %s at %d px (as `_note` gets it)" % [font.get_font_name(), size])
	print("fits: overlay %d px (today) · docked %d px (ASSA-276 move 1)"
			% [int(OVERLAY_PX), int(DOCKED_PX)])
	print("")

	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line == "" or line.begins_with("#"):
			if line.begins_with("#"):
				print(line)
			continue
		var wide: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		print("%5d px  %3d chars  overlay %-5s docked %-5s  %s"
				% [int(wide), line.length(), "fits" if wide <= OVERLAY_PX else "CLIPS",
				"fits" if wide <= DOCKED_PX else "CLIPS", line])
	screen.stop_solo_relay()
	screen.queue_free()
	quit(0)
