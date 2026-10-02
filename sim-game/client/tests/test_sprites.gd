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


## THE IMAGE ON DISK IS THE ONE THE MANIFEST DESCRIBES: `frame_px` times `columns` wide by `frame_px`
## times the number of rows tall, exactly.
##
## This is the arithmetic a renderer will slice with, so a disagreement is an off-by-a-sliver in every
## frame after the first and nothing anywhere errors. Measured against the texture GODOT decoded
## rather than the PNG header, because the importer is allowed to change dimensions -- it does not
## today, and this is what would notice if a preset ever turned on resizing, or mipmaps that padded.
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
			return _fail(("`%s` is %s on disk and the manifest describes %s (%dx%d frames, %d rows, "
					+ "%d columns). Every frame after the first would be sliced wrong.")
					% [stem, got, want, int(frame[0]), int(frame[1]), rows.size(), columns])
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
