extends SceneTree
## CI: local -- builds real worlds from seeds to count what a letter's size says, no window needed
## **WHAT A SPECIES LETTER'S SIZE ACTUALLY DISTINGUISHES, OVER REAL WORLDS** (ASSA-293).
##
##   $GODOT --headless --path client --script res://tools/letter_size_spread.gd -- [seed ...]
##
## **WHY: THE RULING IS A CLAIM ABOUT A SPREAD AND THE SPREAD IS CHEAP TO COUNT.** Maren's ASSA-293
## ruling is that the letter's size means nothing and is held constant at the size that fits the
## smallest patch the sim can generate -- on the measurement that `glyph_size` is `floor(1.4 x r)`
## clamped to 32, so at the shipped cell of 9 a radius-3 and a radius-4 patch draw the IDENTICAL
## letter and 62.6% of deposits wear a size that distinguishes nothing. That number came off one
## frame's own key (ten seeds, by hand). This is the same count as a function of the seed, so the
## before and the after are the same instrument rather than two readings.
##
## **NO SCREEN AND NO SHOT.** `AssaySimHost.start` on a fresh welcome gives the real `worldgen`
## deposits, and the glyph's size is a pure function of `deposit.radius` and the map's cell, so
## nothing here needs a window. The one thing it therefore CANNOT see is the drawn letter: whether
## 25 px still reads at 1x is a window shot's question (ASSA-273's figures).
##
## It also prints the key panel's wanted width per row, because the ruling's new deposit row is
## claimed to *"cost no width"* and that is `AssayMapKey.wants`' to answer, not mine to assert.

const DEFAULT_SEEDS: PackedStringArray = ["63", "777042", "1", "7", "42", "100", "2026", "31337",
		"555", "90210"]


func _initialize() -> void:
	var seeds := _seeds()
	print("ASSA-293  what a letter's size distinguishes, over %d real worlds" % seeds.size())
	print("  glyph_size(r) = floor(1.4 x r) clamped to 32, 0 under 10px   (AssayHud.glyph_size)")
	# `AssaySimHost` is a `RefCounted`, not a node: it holds the world and needs no tree.
	var host := AssaySimHost.new()
	var radius_counts := {}
	var today_sizes := {}
	var held_sizes := {}
	var total := 0
	for text in seeds:
		var welcome := AssaySimHost.fresh_welcome_json(text, "cove")
		if welcome == "" or not host.start(welcome):
			print("  seed %s: no world (the GDExtension is not loaded?)" % text)
			continue
		var cell := AssayHud.map_cell(host.size_tiles())
		var per_seed := {}
		var deposits := host.deposits()
		for entry in deposits:
			var deposit: Dictionary = entry
			var radius := int(deposit.get("radius", 1))
			# EXACTLY `main.gd::_glyph_marks`' two lines, not a paraphrase of them.
			var drawn := maxf(cell, float(radius) * cell)
			var today := AssayHud.glyph_size(drawn)
			var held := AssayHud.glyph_size_held(cell)
			total += 1
			radius_counts[radius] = int(radius_counts.get(radius, 0)) + 1
			today_sizes[today] = int(today_sizes.get(today, 0)) + 1
			held_sizes[held] = int(held_sizes.get(held, 0)) + 1
			per_seed[today] = int(per_seed.get(today, 0)) + 1
		print("  seed %-8s cell %2.0f px, %2d deposits, letter sizes today %s"
				% [text, cell, deposits.size(), _tally(per_seed)])
	print("")
	print("  OVER ALL %d DEPOSITS" % total)
	print("    radii        %s" % _tally(radius_counts))
	print("    sizes today  %s" % _tally(today_sizes))
	print("    sizes held   %s   <- ASSA-293's ruling" % _tally(held_sizes))
	print("    %5.1f%% of deposits wear a letter a differently sized patch also wears"
			% _collapsed(radius_counts, today_sizes, total))
	_cell_floor()
	_key_rows()
	quit()


## **THE SHARE WHOSE SIZE DISTINGUISHES NOTHING.** A deposit is collapsed when some OTHER radius
## draws the same letter size, which is the reading a player cannot undo -- not "the sizes are few".
func _collapsed(radius_counts: Dictionary, today_sizes: Dictionary, total: int) -> float:
	var collapsed := 0
	for size: int in today_sizes:
		var radii := 0
		for radius: int in radius_counts:
			if AssayHud.glyph_size(maxf(1.0, float(radius)) * 9.0) == size:
				radii += 1
		if radii > 1:
			collapsed += int(today_sizes[size])
	return 100.0 * float(collapsed) / float(maxi(total, 1))


## **THE CONSEQUENCE THE RULING BUYS AND NOBODY HAS PRICED: A HELD LETTER CAN BE HELD BELOW THE
## FLOOR.** `glyph_size` refuses to draw under 10 px, and today a wide patch on a small cell still
## clears it while a narrow one does not. Held at the smallest patch, either every letter draws or
## none does, so this prints the cell where that flips and the world size that produces it.
func _cell_floor() -> void:
	print("")
	print("  THE FLOOR, now that one size decides for every letter")
	for cell: float in [2.0, 3.0, 4.0, 5.0, 9.0, 32.0]:
		print("    cell %2.0f px   held %2d px   widest patch today %2d px"
				% [cell, AssayHud.glyph_size_held(cell), AssayHud.glyph_size(4.0 * cell)])
	var rect := AssayHud.world_rect()
	print("    cell is floor(min(%.0f/w, %.0f/h)) over a world of w x h tiles, so a letter stops"
			% [rect.size.x, rect.size.y])
	print("    being drawn at all past about %d tiles wide (today's world is 96)"
			% int(rect.size.x / 4.0))


## **DOES THE NEW DEPOSIT ROW COST THE PANEL ANY WIDTH?** Maren's ruling asks for this number by
## name. `wants` takes the widest label, so only the widest row can move the panel.
func _key_rows() -> void:
	var font := ThemeDB.fallback_font
	var rows := AssayHud.map_key_rows()
	var wanted := AssayMapKey.wants(font, 13, rows)
	print("")
	print("  THE KEY PANEL, AssayMapKey.wants at font 13: %.0f x %.0f px" % [wanted.x, wanted.y])
	var widest := ""
	var widest_px := 0.0
	for row in rows:
		var label := String(row["label"])
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if width > widest_px:
			widest_px = width
			widest = label
		if label.begins_with("ore you can work"):
			print("    deposit row  %2d chars, %3.0f px  \"%s\"" % [label.length(), width, label])
	print("    widest row   %2d chars, %3.0f px  \"%s\"" % [widest.length(), widest_px, widest])


func _tally(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s x%d" % [key, int(counts[key])])
	return ", ".join(parts)


func _seeds() -> PackedStringArray:
	var args := OS.get_cmdline_user_args()
	return DEFAULT_SEEDS if args.is_empty() else PackedStringArray(args)
