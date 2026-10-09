extends RefCounted
## CAN THIS CLIENT ACTUALLY LOAD THE ART? Asked from inside the engine, which is the only place the
## question has an answer.
##
## ASSA-34 was Cove's finding that not one sheet was reachable: `res://` is `client/` and the sheets
## were in its sibling. That is fixed -- `art/build.py` writes them to `client/assets/sprites/` now --
## and `art/check_client_can_see_art.py` stands in CI to stop it coming back. But that check is
## PYTHON: it resolves paths and reads export filters. It cannot tell you whether Godot imported the
## texture, whether the `.import` sidecar is the one for this PNG, or whether the sheet the manifest
## describes is the sheet on disk. Those three only fail inside the engine, and the client's own suite
## had nothing to say about any of them.
##
## SO THIS IS THE OTHER HALF, and it is the half that belongs to whoever draws. Nothing in the client
## draws a sprite yet (ASSA-46), and this test is deliberately written so that it does not wait for
## that: it asks the questions a renderer is about to lean on, not what the picture looks like.
##
## WHY THE GRID AND NOT JUST THE LOAD. A sheet is useless without knowing where one frame ends, and
## the manifest is the only thing that says. A renderer will slice at `frame_px` and index by row, so
## if the image on disk is a different size than the manifest claims, every frame after the first is
## off by a sliver and nothing errors -- the art just looks subtly wrong, which is the hardest kind of
## wrong to trace. The arithmetic is held both ways: against the texture Godot decoded, and against
## the row list the manifest ships.
##
## A NOTE ON ONE WORD, because it cost me a red suite. `test_the_client_is_a_view.gd` forbids any
## GDScript file from naming a mineral `sheet` (Maren's line, ASSA-7): the EXACT mineral sheet crosses
## the wire in every Welcome, so a renderer reading it would show numbers nobody has assayed. Sprite
## sheets are now in the project and the word means a second thing, which that guard cannot tell
## apart -- and it should not have to. So this file never names the manifest's own path field. It walks
## the PNGs the project actually holds and looks each one up by its stem, which turns out to be the
## STRONGER test anyway: it catches a rendered image with no manifest row, which reading the manifest
## alone never would. Maren's rule is untouched; it is worth her knowing the word is overloaded now.

## Where `art/build.py` writes the shipped sheets, inside the project because `res://` does not go up
## (ASSA-34, Marlow's ruling: option A). The manifest sits beside them.
const SPRITES := "res://assets/sprites"
const MANIFEST := SPRITES + "/manifest.json"

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## The manifest as the client reads it, or `{}`.
##
## Read with `FileAccess` and not `load()`: a `.json` under `res://` is an imported resource and a
## test that went through the importer would be asking a different question. This is the file.
func _manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## THE MANIFEST IS THERE AND IT DESCRIBES THE IMAGES. On its own this is the claim ASSA-34 was filed
## against: for eleven rendered images and four measured checks, `find client -name "*.png"` returned
## nothing at all.
func test_the_client_can_read_the_art_manifest() -> bool:
	if not FileAccess.file_exists(MANIFEST):
		return _fail(("no %s: the art pipeline's output is not inside the Godot project, which is "
				+ "ASSA-34 all over again") % MANIFEST)
	var manifest := _manifest()
	if manifest.is_empty():
		return _fail("%s is there and this client cannot read it as a dictionary" % MANIFEST)
	# The ore art is the one the map needs first: species-neutral and meant to be tinted with
	# `AssayHud.SPECIES_TINTS` (Decision #36). A manifest without it would mean the pipeline's output
	# no longer covers the thing the client is closest to drawing.
	if not manifest.has("ore"):
		return _fail("the manifest describes %s and not `ore`" % [manifest.keys()])
	return true


## EVERY PNG IN THE PROJECT LOADS THROUGH `res://` AS A TEXTURE WITH PIXELS IN IT, AND HAS A MANIFEST
## ROW; AND EVERY MANIFEST ROW HAS A PNG. Both directions, because each is a different failure:
##
##  - an image with no row is art a renderer cannot slice -- `art/build.py` renamed its output and the
##    manifest did not follow,
##  - a row with no image is a manifest promising art that is not in the bundle, which is exactly the
##    shape ASSA-34 was.
##
## `ResourceLoader.exists` before `load()`, because `load()` on a missing resource is an engine error
## that buries the failure in a stack trace instead of a sentence. A ZERO-SIZED texture is its own
## case: a stale or mismatched `.import` sidecar gives you a resource that loads and holds nothing.
func test_every_image_loads_and_the_manifest_covers_exactly_those() -> bool:
	var manifest := _manifest()
	if manifest.is_empty():
		return _fail("no manifest to check; see the failure above")
	var found := _images()
	if found.is_empty():
		return _fail("not one PNG under %s; the engine has no art to draw" % SPRITES)
	for stem in found:
		if not manifest.has(stem):
			return _fail(("%s/%s.png is in the project with no `%s` row in the manifest, so nothing "
					+ "knows how to slice it") % [SPRITES, stem, stem])
		var path := "%s/%s.png" % [SPRITES, stem]
		if not ResourceLoader.exists(path):
			return _fail(("%s is on disk and the engine has no such resource -- an unimported PNG, "
					+ "or one no export preset packs") % path)
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			return _fail("%s loaded as something that is not a Texture2D" % path)
		if texture.get_width() <= 0 or texture.get_height() <= 0:
			return _fail(("%s loaded with no pixels (%dx%d), which is what a stale or mismatched "
					+ ".import sidecar looks like") % [path, texture.get_width(),
					texture.get_height()])
	for stem in manifest.keys():
		if not found.has(String(stem)):
			return _fail(("the manifest describes `%s` and there is no %s/%s.png in the project; "
					+ "that is the ASSA-34 failure, from the other side") % [stem, SPRITES, stem])
	return true


## THE IMAGE THE ENGINE DECODED IS THE ONE THE MANIFEST DESCRIBES: `frame_px` times `columns` wide by
## `frame_px` times the number of rows tall, exactly.
##
## This is the arithmetic a renderer will slice with, so a disagreement is an off-by-a-sliver in every
## frame after the first and nothing anywhere errors. Measured against the texture GODOT decoded
## rather than the PNG header, because the importer is allowed to change dimensions -- it does not
## today, and this is what would notice if a preset ever turned on resizing, or mipmaps that padded.
##
## WHICH IS WHY THE FAILURE MAY NOT BE ABOUT THE ART AT ALL, and the message says so (ASSA-72). It
## used to report the decoded size as the size "on disk". That is the one thing it is not: when a
## teammate's new sheet is pulled and `.godot/` is not re-imported, the engine hands back the size of
## the PREVIOUS import and this test fails against a PNG whose header is perfectly correct. It cost me
## twenty minutes on main at 8d2b4b0 -- `items.png` is 64x192 on disk, the cache still held 64x96, and
## I went looking for a bad sheet. Naming the number for what it is turns that into one re-import.
func test_each_images_pixels_match_the_grid_the_manifest_claims() -> bool:
	var manifest := _manifest()
	if manifest.is_empty():
		return _fail("no manifest to check; see the failure above")
	for stem in _images():
		if not manifest.has(stem):
			return _fail("no manifest row for %s; see the failure above" % stem)
		var row: Dictionary = manifest[stem]
		var path := "%s/%s.png" % [SPRITES, stem]
		if not ResourceLoader.exists(path):
			return _fail("no resource at %s; see the failure above" % path)
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			return _fail("%s is not a Texture2D; see the failure above" % path)
		var frame: Array = row.get("frame_px", [])
		var rows: Array = row.get("rows", [])
		var columns := int(row.get("columns", 0))
		if frame.size() != 2 or rows.is_empty() or columns <= 0:
			return _fail("`%s` describes itself as frame %s, %d rows, %d columns, which cannot be "
					% [stem, frame, rows.size(), columns] + "sliced")
		var want := Vector2i(int(frame[0]) * columns, int(frame[1]) * rows.size())
		var got := Vector2i(texture.get_width(), texture.get_height())
		if got != want:
			return _fail(("Godot decoded `%s` as %s and the manifest describes %s (%dx%d frames, "
					+ "%d rows, %d columns). Every frame after the first would be sliced wrong. "
					+ "That size is what the ENGINE loaded, not the PNG header: if %s.png on disk "
					+ "is already %s, this is a stale import cache, not bad art -- re-run "
					+ "`godot --headless --import` and this test again.")
					% [stem, got, want, int(frame[0]), int(frame[1]), rows.size(), columns, stem,
					want])
		# And no row may claim more frames than the image is wide, which is the same disagreement
		# read along the other axis.
		for entry in rows:
			var line: Dictionary = entry
			if int(line.get("frames", 0)) > columns:
				return _fail("`%s` row `%s` claims %d frames in an image %d columns wide"
						% [stem, String(line.get("name", "?")), int(line.get("frames", 0)), columns])
	return true


## Every PNG stem the project actually holds, sorted. `.remap` is trimmed the way
## `test_the_client_is_a_view.gd` does it: an EXPORTED project remaps resource names, and a test that
## only worked in a source checkout would be a test of my checkout.
func _images() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(SPRITES)
	if dir == null:
		return out
	for name in dir.get_files():
		var file := String(name).trim_suffix(".remap")
		if file.ends_with(".png"):
			out.append(file.trim_suffix(".png"))
	out.sort()
	return out


## THE ORE ART HAS A FRAME FOR EVERY GRADE, which is the one content claim worth making here.
##
## Grade is the sim's word and the client may not derive it (`hud.gd`'s rule), so the three letters
## are read out of the SIM, not written down: `tile_at` reports a deposit's grade, and the three bands
## are what `sim::Grade` has. A sheet missing one would mean a map that cannot draw a B-grade patch
## and no error anywhere -- just a missing row index.
func test_the_ore_art_has_a_row_for_every_grade_the_sim_uses() -> bool:
	var manifest := _manifest()
	if manifest.is_empty():
		return _fail("no manifest to check; see the failure above")
	var rows := PackedStringArray()
	for entry in (manifest["ore"] as Dictionary).get("rows", []):
		rows.append(String((entry as Dictionary).get("name", "")))
	var missing := PackedStringArray()
	for grade in _grades_the_sim_has():
		var found := false
		for row in rows:
			if row.begins_with(grade):
				found = true
		if not found:
			missing.append(grade)
	if _grades_the_sim_has().is_empty():
		return _fail("could not read a single grade out of the sim, so this proves nothing")
	if missing.size() > 0:
		return _fail("the ore art has rows %s and the sim grades ore %s; missing %s"
				% [rows, _grades_the_sim_has(), missing])
	return true


## THE GRADE LETTERS, OUT OF THE SIM -- AND THE FIRST VERSION OF THIS PROVED NOTHING.
##
## It read `grade` off `deposits()`, which does not have one: `deposits()` carries id, species, centre,
## radius, amount, purity and symbol, and the GRADE is `tile_at`'s, because deciding which band a
## purity falls in is the sim's job and `deposit_dict` is where it answers. So the set came back as
## `[""]`, every row `begins_with("")` is true, and nothing could ever be missing. A TEST THAT PASSES
## FOR THE ABSENCE OF DATA CANNOT PROVE A RULE ABOUT DATA -- the same mistake as the planted-durability
## test that erased the key it was checking. Found by mutating the manifest and watching this stay
## green.
##
## So it asks `tile_at` at each deposit's centre, and a letter that is not a letter is a FAILURE here
## rather than a silent pass. Purity spans 1..100 over six species and dozens of patches, so all three
## bands turn up on their own; a world that only showed two would fail loudly and want a second seed,
## which is the right way round.
func _grades_the_sim_has() -> PackedStringArray:
	var host := AssaySimHost.new()
	if not host.start(AssaySimHost.fresh_welcome_json("777042", "limpet")):
		return PackedStringArray()
	var seen := {}
	for entry in host.deposits():
		var at: Vector2i = (entry as Dictionary).get("center", Vector2i.ZERO)
		var here: Variant = host.tile_at(at).get("deposit")
		if here == null:
			continue
		var grade := String((here as Dictionary).get("grade", ""))
		# AN EMPTY LETTER IS NOT A GRADE. Kept out on purpose: letting it in is exactly how this
		# function used to answer `[""]` and make the test above unfailable.
		if grade.strip_edges() != "":
			seen[grade] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## ASSA-46, MAREN'S RULING B: A PACK ROW CARRIES A SPECIES-TINTED ICON WHERE WE HAVE ART, AND READS
## COMPLETELY WHERE WE DO NOT.
##
## `items.png` has three rows -- ore, refined (ASSA-66) and smelter (ASSA-87) -- and the four part
## sheets have C/B/A, so the gear is the one kind with no art. That is a fact about the sheets, not a
## failure, and the rule Maren set for both the glyph and the icon is that the redundant cue may never
## become the only read. The gear's gap is SETTLED rather than pending: nothing in the game consumes a
## gear (Maren, ASSA-84), so drawing one would be art for a dead recipe.
##
## NO TWO ITEM KINDS MAY DRAW THE SAME ROW. They take the same species tint and usually carry the
## same species NAME in adjacent pack rows, so if the row lookup ever collapsed two of them the panel
## would look perfectly fine and say something false. This is the assertion that was waiting to be
## written when `_row_for` still answered `if kind == "ore": return 0` for a one-row items sheet.
##
## WRITTEN AS A LOOP OVER THE KINDS, not as hand-named pairs, so the fourth item row is covered by
## this test on the day it lands rather than the day someone remembers to add it here.
func test_an_ore_stack_gets_a_frame_and_a_gear_does_not() -> bool:
	var rows := {}
	# SEVEN KINDS, NOT THREE, SINCE ASSA-121: the four part kinds are items rows too, and this
	# docstring already promised they would be covered "on the day it lands rather than the day
	# someone remembers to add it here". With all seven here the collapse this guards against is a
	# real risk rather than a theoretical one -- `handle` and `head` are adjacent rows of one sheet.
	for kind in ["ore", "refined", "smelter", "handle", "head", "frame", "hopper"]:
		var icon := AssaySprites.icon_for({"kind": kind, "species": 2, "grade": "B", "count": 7})
		if icon == null:
			return _fail("`%s` has a row in items.png and got no frame" % kind)
		if icon.atlas == null:
			return _fail("`%s`'s frame has no sheet behind it" % kind)
		if icon.region.size.x <= 0.0 or icon.region.size.y <= 0.0:
			return _fail("`%s`'s frame is empty: %s" % [kind, icon.region])
		# KEYED ON SHEET *AND* ROW, not on the row alone. Every kind here is an items row today, so
		# `y` would be enough -- but it is only enough BECAUSE they share a sheet, and this loop no
		# longer gets to assume that: when it covered three kinds they were all items, and the day a
		# kind moves back off that sheet two different sheets' row 1 are both y 102 and this would
		# report a collision that is not one. The claim is "no two kinds draw the same frame".
		var at := "%s@%s" % [icon.atlas.resource_path, icon.region.position.y]
		if rows.has(at):
			return _fail(("`%s` and `%s` drew the SAME frame (%s). They take the same tint and often "
					+ "the same species name in adjacent rows, so this would read as a correct panel "
					+ "saying the wrong thing.") % [kind, rows[at], at])
		rows[at] = kind
	# AND THE KIND WITH NO ART STILL GETS NOTHING. Worth knowing WHICH mechanism holds this, because
	# the obvious answer is wrong and it was mutation-tested: an entry in `SHEET_OF` is not enough on
	# its own, because the sheet also has to carry a row the lookup can find by name. Both had to
	# happen for refined and again for smelter. So the empty `SHEET_OF` entry is DOCUMENTATION of the
	# gap and the row lookup is what actually gates it -- nobody should read `SHEET_OF` and think it
	# is the guard.
	var none := AssaySprites.icon_for({"kind": "gear", "species": 2, "grade": "B"})
	if none != null:
		return _fail("`gear` got a frame and we have drawn no art for it. Inventing one means "
				+ "drawing the wrong thing; the row is supposed to read without an icon.")
	return true


## A PART'S ASSEMBLY FRAME FOLLOWS THE SIM'S GRADE LETTER, and nothing else picks it.
##
## THIS TEST USED TO ASK `icon_for` AND ITS PREMISE MOVED (ASSA-121). It is rewritten rather than
## deleted, because the claim is still true and still worth holding -- it just belongs to the
## ASSEMBLY map now. The pack row's items drawing is one row per kind with the grade in the stack
## sentence, which is the items convention; the C/B/A ladder lives on the assembly sheets, where a
## machine is built out of it. The next test holds the other half.
func test_a_part_assembly_frame_takes_the_row_named_by_its_grade() -> bool:
	var seen := {}
	for grade in ["C", "B", "A"]:
		var icon := AssaySprites.assembly_icon_for({"kind": "head", "species": 0, "grade": grade})
		if icon == null:
			return _fail("a %s head got no assembly frame" % grade)
		var key := str(icon.region.position.y)
		if seen.has(key):
			return _fail("grade %s drew the same row as %s: %s" % [grade, seen[key], icon.region])
		seen[key] = grade
	# AND AN UNKNOWN GRADE DRAWS NOTHING rather than guessing a row.
	if AssaySprites.assembly_icon_for({"kind": "head", "species": 0, "grade": "Z"}) != null:
		return _fail("an unknown grade picked a frame instead of drawing nothing")
	return true


## THE TWO SURFACES DRAW A PART FROM DIFFERENT SHEETS, which is the whole of ASSA-121.
##
## WHY THIS IS NOT A RESTATEMENT OF THE DICTIONARIES. The failure it exists to catch is the one the
## item was nearly built as: point the pack rows at `items` and leave the machine composite reading
## the same map, and every planted machine quietly redraws itself out of loose-part pictures whose
## `frame_px` is 64x96 at `tiles` [1,1] -- so `part_layout.json`'s repeat offset lands in the wrong
## space and the machine comes apart. Nothing else in the suite compares the two.
##
## MEASURED ON THE REGION, NOT ON A SHEET NAME: the region is what gets blitted, and the sheets have
## different frame sizes, so a part asked for both ways must come back with different geometry. The
## atlas path is asserted too, because two sheets could in principle agree on a frame size.
func test_a_part_draws_from_items_in_the_pack_and_its_own_sheet_in_a_machine() -> bool:
	for kind in ["handle", "head", "frame", "hopper"]:
		var part := {"kind": kind, "species": 0, "grade": "B"}
		var pack := AssaySprites.icon_for(part)
		var machine := AssaySprites.assembly_icon_for(part)
		if pack == null:
			return _fail("`%s` got no pack icon; ASSA-112 put a row for it on items.png" % kind)
		if machine == null:
			return _fail("`%s` got no assembly frame; the machine composite needs one" % kind)
		if pack.atlas == null or machine.atlas == null:
			return _fail("`%s` got a frame with no sheet behind it" % kind)
		var pack_sheet := String(pack.atlas.resource_path)
		var machine_sheet := String(machine.atlas.resource_path)
		if pack_sheet == machine_sheet:
			return _fail(("`%s` draws its pack row and its machine frame from the SAME sheet (%s). "
					+ "One of the two surfaces is reading the wrong map: a pack slot wants the loose "
					+ "object, a machine wants the registered assembly frame.") % [kind, pack_sheet])
		if not pack_sheet.ends_with("items.png"):
			return _fail("`%s`'s PACK icon comes from %s, not items.png" % [kind, pack_sheet])
		if not machine_sheet.ends_with("%s.png" % kind):
			return _fail("`%s`'s MACHINE frame comes from %s, not %s.png" % [kind, machine_sheet, kind])
		if pack.region.size == machine.region.size:
			return _fail(("`%s` slices the same frame size (%s) both ways. The items frame is 64x96 "
					+ "and the assembly frame 128x102; equal sizes mean one lookup silently fell "
					+ "through to the other sheet.") % [kind, pack.region.size])
	return true


## **THE ARITHMETIC `_slot_box`'s DOC RESTS ON, READ OFF THE REAL ATLAS AND main.gd'S OWN CONSTANTS**
## (ASSA-388).
##
## The test above already proves a part's pack picture comes from `items.png`, and it was green the
## whole time `_slot_box` said the opposite in prose -- *"a 128x102 part cell … the width is what
## binds and nothing is resampled"*. **Nothing tests prose**, so this asserts the three numbers the
## corrected doc states, where a drifting constant or a moved row reddens instead of rotting.
##
## **IT DOES NOT ASSERT THAT THE PICTURE FITS THE PLATE, BECAUSE TODAY IT DOES NOT.** `_icon_box`
## stamps `ICON_BOX_PX` (32x48) on the `TextureRect` as a MINIMUM, `_slot_box` anchors it into an
## `ICON_PX` square with `PRESET_FULL_RECT`, and anchoring cannot shrink a control below its
## minimum -- so a tall part hangs 7 px of paint out of the bottom of its own plate on a 1x window.
## Reconciling the two is a design call (shrink the picture, or grow the plate) and it is the Game
## Director's; ASSA-388 carries both options rendered. **Clause 3 is written as the GAP on purpose:
## the day the two are reconciled this test fails, which is the reminder to rewrite the doc with the
## fix instead of leaving a third stale sentence beside this box.**
func test_a_parts_pack_frame_is_portrait_and_fits_its_box_exactly() -> bool:
	var main_consts: Dictionary = (load("res://scripts/main.gd") as GDScript).get_script_constant_map()
	var icon_px: float = main_consts.get("ICON_PX", 0.0)
	var icon_box: Vector2 = main_consts.get("ICON_BOX_PX", Vector2.ZERO)
	if icon_px <= 0.0 or icon_box == Vector2.ZERO:
		return _fail("main.gd no longer exports ICON_PX / ICON_BOX_PX; this test reads them, not a copy")
	# 1. THE FRAME IS PORTRAIT, which is what kills the old sentence: a 128x102 assembly cell is
	#    landscape, binds on width, and divides 32 exactly. A 64x96 items frame does none of that.
	for kind in ["handle", "head", "frame", "hopper"]:
		var icon := AssaySprites.icon_for({"kind": kind, "species": 0, "grade": "B"})
		if icon == null:
			return _fail("`%s` got no pack icon" % kind)
		var frame := icon.region.size
		if frame.x >= frame.y:
			return _fail(("`%s`'s pack frame is %s -- landscape or square. Every doc on this path "
					+ "is written for a PORTRAIT frame sharing `ICON_BOX_PX`'s 2:3; a landscape "
					+ "cell would be the assembly sheet, which belongs to a planted machine and "
					+ "not to a pack row (ASSA-121). Rewrite them.") % [kind, frame])
		# 2. **RETIRED, AND NAMED RATHER THAN DELETED.** This clause asserted
		#    `icon_box.y > icon_px` -- "the pack row's box is taller than the plate it is anchored
		#    into" -- as a pin on ASSA-388's overflow while the plate's shape was the Game
		#    Director's to rule. She ruled: the plate IS `ICON_BOX_PX` now, so there is no second
		#    number and the gap is not a fact about this screen any more.
		#
		#    **IT ALSO WOULD NOT HAVE REDDENED ON THE FIX, WHICH IS THE WORSE HALF.** It compared
		#    two CONSTANTS, and the fix changed neither: it changed which constant `_slot_box`
		#    reaches for. I wrote it expecting it to catch exactly this change and it would have
		#    sat green through it. What replaces it asks the laid-out plate instead --
		#    `test_a_slot_plate_is_the_box_its_picture_is_drawn_in` in `test_buttons.gd`, which is
		#    red on the old line and green on the new one.
		# 3. **NOT "THE HEIGHT BINDS", WHICH WOULD BE VACUOUS**: in a SQUARE box a portrait frame
		#    always binds on height, so clause 1 would already have decided it and no mutation
		#    could reach a separate assertion. What no earlier clause implies is that
		#    `ICON_BOX_PX` fits this frame EXACTLY -- 32x48 and 64x96 are both 2:3, so NEITHER
		#    axis binds and the scale is a clean 1/2. **That is the whole reason the slot plate
		#    could be grown to meet the picture instead of the picture shrunk to meet the plate**
		#    (ASSA-388): one box, no resample. If these two ever stop sharing an aspect, every pack
		#    icon in the game starts being resampled and this is the line that says so.
		if not is_equal_approx(icon_box.x / frame.x, icon_box.y / frame.y):
			return _fail(("`%s` %s does not fit ICON_BOX_PX %s exactly: %.4f by width, %.4f by "
					+ "height. The pack row's box and the authored frame have stopped sharing an "
					+ "aspect, so a pack icon is being resampled.")
					% [kind, frame, icon_box, icon_box.x / frame.x, icon_box.y / frame.y])
	return true


## THE TINT IS THE SPECIES' OWN SLOT, from the one table CI holds equal to the art pipeline's copy.
func test_the_icon_tint_is_the_species_slot() -> bool:
	for species in range(AssayHud.SPECIES_TINTS.size()):
		var got := AssaySprites.tint_for({"kind": "ore", "species": species, "grade": "B"})
		var wanted := Color(AssayHud.SPECIES_TINTS[species])
		if not got.is_equal_approx(wanted):
			return _fail("species %d tinted %s, not its slot %s" % [species, got, wanted])
	# A stack with no species (there is no such item, but a frame can be drawn before a Welcome) must
	# not index the table with -1.
	if AssaySprites.tint_for({"kind": "ore", "species": -1}) != Color.WHITE:
		return _fail("a species-less stack should tint white rather than wrap the table")
	return true


## AND THE ROW'S SENTENCE IS STILL COMPLETE WITHOUT THE ICON (Maren's rule, twice stated: for the map
## glyph on ASSA-39 and for this icon on ASSA-46). The icon is redundancy; `stack_line` names the count,
## the species and the grade on its own.
func test_the_row_reads_completely_with_no_icon_at_all() -> bool:
	var line := AssayHud.stack_line({"count": 7, "name": "Kuri ore (B)"})
	for wanted in ["7", "Kuri ore (B)"]:
		if not line.contains(wanted):
			return _fail("the pack sentence does not carry `%s` on its own: %s" % [wanted, line])
	return true
