extends RefCounted
## THE TWO RULES THAT TURN PARTS INTO A MACHINE, MEASURED ON THE PIXELS THIS CLIENT WOULD DRAW.
##
## Cove measured both defects before shipping the contract (ASSA-54): drawn naively, hoppers two,
## three and four gain +25/+17/+19 px -- antialiasing, not parts -- while capacity is a real number in
## the sim, and the darkest shadow's alpha climbs 128/145/181/205/221 so that the shadow reports how
## many parts a machine has.
##
## EVERY TEST HERE CARRIES ITS OWN LEVER, because a measurement that cannot come out wrong is not
## evidence. Both re-compose with the rule switched off through a doctored contract -- offset (0, 0)
## for rule 1, `shadow_ceiling` 0 for rule 2, which makes the alpha-MAX branch unreachable -- and
## require the defect to come back. If a rule ever stops being load-bearing, these go red.
##
## The expectations are PROPERTIES, not Cove's numbers: I cannot reproduce their harness, and a test
## tuned until it matched a number from someone else's measurement would be agreeing with itself. The
## numbers this run measured are on ASSA-63 beside Cove's for comparison -- they agree, which is
## corroboration and not an assertion.

## A pixel is part of the picture at all. Well above the alpha antialiasing leaves behind, which is
## what made +17 px look like a hopper in the naive row.
const SOLID := 0.5

## What one added repeat has to be worth to count as a part you can see. Cove's naive row gained 17 px
## at its worst and the rules row gained 108 at its worst, so anything in between separates them.
const REAL_GAIN := 60

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## THE GEOMETRY IS THE FILE'S, AND THE FILE IS PARSED TWICE ON PURPOSE. This reads
## `part_layout.json` itself instead of trusting `AssayAssembly.contract()`, so a client that grew its
## own copy of (14, -6) -- the thing ASSA-54 is about -- is caught here as a disagreement rather than
## drawing happily on top of itself.
##
## It also pins the CAST. Godot's JSON hands back 14.0 and 34.0 as doubles; `Vector2i` of a float
## truncates silently, so the one place that conversion happens is asserted rather than assumed.
func test_the_layout_rules_are_the_contract_files_own_numbers() -> bool:
	var text := FileAccess.get_file_as_string(AssayAssembly.CONTRACT)
	if text.is_empty():
		return _fail("no %s in the project, so the client has no drawing contract to follow"
				% AssayAssembly.CONTRACT)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _fail("%s is not JSON an engine can read: %s" % [AssayAssembly.CONTRACT, text])
	var raw: Dictionary = parsed
	if not raw.has("repeat_offset_px") or not raw.has("shadow_ceiling"):
		return _fail(("%s has keys %s. The client reads `repeat_offset_px` and `shadow_ceiling`; "
				+ "if the pipeline renamed them this is the place to find out.")
				% [AssayAssembly.CONTRACT, raw.keys()])
	var offset: Array = raw["repeat_offset_px"]
	var want := Vector2i(int(offset[0]), int(offset[1]))
	var rules := AssayAssembly.contract()
	if rules.get("repeat_offset_px") != want:
		return _fail("the client offsets repeats by %s and the contract says %s"
				% [rules.get("repeat_offset_px"), want])
	if rules.get("shadow_ceiling") != int(raw["shadow_ceiling"]):
		return _fail("the client's shadow ceiling is %s and the contract says %s"
				% [rules.get("shadow_ceiling"), int(raw["shadow_ceiling"])])
	if typeof(rules.get("shadow_ceiling")) != TYPE_INT:
		return _fail("the shadow ceiling came through as %s, so the JSON double was never cast"
				% type_string(typeof(rules.get("shadow_ceiling"))))
	return true


## RULE 1: EVERY HOPPER YOU ADD IS A HOPPER YOU CAN SEE.
##
## Capacity is a real number in the sim, so a drill wearing four hoppers must not look like a drill
## wearing one. Measured as solid pixels gained per added part, which is the thing Cove's naive row
## failed: +25/+17/+19 is antialiasing around an identical picture.
##
## THE LEVER: the same four assemblies composed with the offset taken away. The gains have to collapse
## -- if they do not, this test is not measuring the offset and nobody should trust it.
func test_each_added_repeat_is_a_part_you_can_see() -> bool:
	var parts := _drill_parts(4)
	if parts.is_empty():
		return _fail("no art for a frame, a head or a hopper, so nothing can be composed")
	var rules := AssayAssembly.contract()
	# A REPEAT IS THE nTH OF A KIND, NOT THE nTH PART. A head is not a second frame: both sit where
	# the contract puts a 0th, so a frame and a head together occupy ONE frame's box and the image
	# does not grow. Counting repeats across the whole assembly instead would offset the head off its
	# own frame -- and I only wrote this down because mutating the count to a global one left every
	# other measurement in this file green. Every part would still be somewhere different, so
	# footprints still grow and shadows still flatten; the picture would just be wrong.
	var lone := AssayAssembly.image_of([parts[0] as Dictionary], rules)
	var pair := AssayAssembly.image_of(parts.slice(0, 2), rules)
	if lone == null or pair == null:
		return _fail("composing a frame, or a frame and a head, produced no image")
	if pair.get_size() != lone.get_size():
		return _fail(("a frame and a head need %s where a frame alone needs %s. Two parts of "
				+ "DIFFERENT kinds are each the 0th of their kind and belong in the same box; only "
				+ "repeats are offset.") % [pair.get_size(), lone.get_size()])
	var footprints := _footprints(parts, rules)
	if footprints.is_empty():
		return _fail("composing a drill with the real contract produced no image")
	var gains := _gains(footprints)
	for i in range(gains.size()):
		if int(gains[i]) < REAL_GAIN:
			return _fail(("hopper %d added %d solid px (want >= %d). Footprints %s. That is "
					+ "antialiasing, not a part, and the sim's capacity went up anyway.")
					% [i + 2, int(gains[i]), REAL_GAIN, footprints])
	# THE LEVER. Offset (0, 0) is the naive drawing, and the gains must collapse -- otherwise the
	# measurement above would pass with the rule switched off.
	#
	# FROM THE SECOND REPEAT ON, and the first time I wrote this I had it wrong and this lever told me
	# so: with the offset taken away the FIRST hopper still gained 468 px. Of course it did. The first
	# hopper of a machine is the 0th of its kind, `0 * offset` is nowhere either way, and no offset
	# rule can change where it lands. The contract governs the SECOND and later repeats. Cove's own
	# table says the same thing -- naive +131 against rules +117 on the first, and the rows only part
	# company afterwards (+25/+17/+19 against +108/+155/+192).
	var flat := _footprints(parts, {"repeat_offset_px": Vector2i.ZERO,
			"shadow_ceiling": rules.get("shadow_ceiling", 0)})
	var flat_gains := _gains(flat)
	if flat_gains.size() < 2:
		return _fail("only %d repeats measured; the lever needs a second one to say anything"
				% flat_gains.size())
	for i in range(1, flat_gains.size()):
		if int(flat_gains[i]) >= REAL_GAIN:
			return _fail(("with the offset taken away, hopper %d still gained %d px (%s), so this "
					+ "test does not measure the offset and its pass means nothing.")
					% [i + 2, int(flat_gains[i]), flat])
	return true


## RULE 2: A MACHINE'S SHADOW DOES NOT REPORT HOW MANY PARTS IT HAS.
##
## Each part sprite carries its own contact shadow. Under plain `over` those alphas accumulate, so the
## shadow deepens with every part -- a gradient a player would read as something about the machine.
## Alpha MAX below the ceiling keeps it the shadow of one part.
##
## MEASURED PIXEL AGAINST PIXEL, THE SAME MACHINE COMPOSED BOTH WAYS -- which took me two wrong
## statistics to arrive at, and both failures are worth leaving written down:
##
## 1. "The most opaque shadow pixel must not climb" READ 255 EVERYWHERE, rule on or off. The part
##    sheets carry an opaque near-black OUTLINE, and an outline is under `shadow_ceiling` too, so the
##    maximum was pinned at fully opaque before any shadow was composited. A statistic that is
##    saturated in every world is not a measurement.
## 2. Any AGGREGATE over shadow-classified pixels (count, mean, total ink) climbs with part count for
##    an honest reason: four hoppers have four outlines. So growth there says nothing about shadows
##    accumulating.
##
## What survives both: compose the SAME parts at the SAME offsets with the rule on and with
## `shadow_ceiling` 0 (which makes the alpha-MAX branch unreachable -- plain `over`, Cove's naive
## row), and compare the two images pixel by pixel. Identical geometry, identical outlines; the only
## difference is accumulation.
##
## `held_back` is where the rule kept a shadow lighter than `over` would have. It has to GROW with
## every part added, because that growth IS the defect Cove named: a shadow that deepens with each
## part is a gradient reporting part count. And nothing may come out DEEPER than plain `over` -- that
## direction is arithmetic (max(a, b) <= a + b(1-a)), asserted because it is cheap and names which way
## the rule is meant to point.
func test_the_shadow_rule_holds_back_more_as_a_machine_gains_parts() -> bool:
	var parts := _drill_parts(4)
	if parts.is_empty():
		return _fail("no art for a frame, a head or a hopper, so nothing can be composed")
	var rules := AssayAssembly.contract()
	var naive := rules.duplicate()
	naive["shadow_ceiling"] = 0
	var held := []
	var gaps := []
	for count in range(2, parts.size() + 1):
		var ruled := AssayAssembly.image_of(parts.slice(0, count), rules)
		var plain := AssayAssembly.image_of(parts.slice(0, count), naive)
		if ruled == null or plain == null:
			return _fail("composing %d parts produced no image" % count)
		if ruled.get_size() != plain.get_size():
			return _fail("the two composites are %s and %s, so they cannot be compared pixelwise"
					% [ruled.get_size(), plain.get_size()])
		var lighter := 0
		var deeper := 0
		var worst := 0.0
		for y in range(ruled.get_height()):
			for x in range(ruled.get_width()):
				var a := ruled.get_pixel(x, y).a
				var b := plain.get_pixel(x, y).a
				if a < b - 0.004:
					lighter += 1
					worst = maxf(worst, b - a)
				elif a > b + 0.004:
					deeper += 1
		if deeper > 0:
			return _fail(("%d pixels came out MORE opaque than plain `over` at %d parts, which the "
					+ "arithmetic forbids: alpha MAX can only hold a shadow back.") % [deeper, count])
		held.append(lighter)
		gaps.append(worst)
	if int(held[0]) <= 0:
		return _fail(("the rule changed NOT ONE pixel of a frame and a head, so either the sheets "
				+ "have no contact shadow under `shadow_ceiling` %d or the ceiling is not being read. "
				+ "Nothing below this would mean anything.") % int(rules.get("shadow_ceiling", 0)))
	for i in range(1, held.size()):
		if int(held[i]) < int(held[i - 1]):
			return _fail(("hopper %d made the rule hold back FEWER pixels (%s), so the shadows it "
					+ "prevents are not the ones a machine gains with its parts.") % [i + 1, held])
	if int(held[held.size() - 1]) <= int(held[0]):
		return _fail(("four hoppers accumulate no more shadow than a bare frame and head (%s), so "
				+ "this would pass with the rule doing nothing on every part after the first.")
				% [held])
	if float(gaps[gaps.size() - 1]) <= float(gaps[0]):
		return _fail(("the deepest shadow the rule held back did not grow with the parts (%s). "
				+ "Cove measured the naive darkest going 128 -> 221 of 255 over four parts.") % [gaps])
	return true


## TWO ASSEMBLIES ARE THE SAME PICTURE WHEN THEIR PARTS ARE, AND NOT WHEN A NUMBER BESIDE THEM MOVED.
##
## `key_of` is what a caller caches by, and a cache key that folds in mass would rebuild the image
## every time an unassayed range narrowed -- while a key that ignored grade would show a grade-A head
## with grade-C pixels. Part ORDER counts: the sim's order is the drawing order.
func test_the_cache_key_is_the_parts_and_only_the_parts() -> bool:
	var a := [_part("frame", "B", 1), _part("hopper", "B", 1)]
	var b := [_part("frame", "B", 1), _part("hopper", "B", 1)]
	if AssayAssembly.key_of(a) != AssayAssembly.key_of(b):
		return _fail("two identical part lists keyed differently: %s vs %s"
				% [AssayAssembly.key_of(a), AssayAssembly.key_of(b)])
	b[1]["mass_low"] = 999
	b[1]["mass_high"] = 1000
	if AssayAssembly.key_of(a) != AssayAssembly.key_of(b):
		return _fail("a mass that moved changed the picture's key, so every narrowing range would "
				+ "rebuild the image: %s" % AssayAssembly.key_of(b))
	for change in [["grade", "A"], ["species", 7], ["kind", "head"]]:
		var c := [_part("frame", "B", 1), _part("hopper", "B", 1)]
		(c[1] as Dictionary)[String(change[0])] = change[1]
		if AssayAssembly.key_of(a) == AssayAssembly.key_of(c):
			return _fail("a different %s keyed the same, so a cache would serve the wrong picture"
					% String(change[0]))
	var swapped := [_part("hopper", "B", 1), _part("frame", "B", 1)]
	if AssayAssembly.key_of(swapped) == AssayAssembly.key_of(a):
		return _fail("the sim's part order is the drawing order, and these two keyed the same: %s"
				% AssayAssembly.key_of(swapped))
	return true


## A FRAME, A HEAD AND `hoppers` HOPPERS, in the sim's order (frame first), all one species and grade
## so that nothing here depends on a world. Empty if the pipeline has no art for one of them, which
## the callers report rather than papering over.
func _drill_parts(hoppers: int) -> Array:
	var parts := [_part("frame", "B", 1), _part("head", "B", 1)]
	for _i in range(hoppers):
		parts.append(_part("hopper", "B", 1))
	for part in parts:
		if AssaySprites.icon_for(part as Dictionary) == null:
			return []
	return parts


func _part(kind: String, grade: String, species: int) -> Dictionary:
	return {"kind": kind, "grade": grade, "species": species, "species_name": "test",
			"symbol": "T", "mass_low": 1, "mass_high": 1}


## HOW MUCH PICTURE THERE IS, as each hopper is added. Entry 0 is the frame and the head -- two parts
## of different kinds, which the contract puts in the SAME place -- then one entry per hopper.
func _footprints(parts: Array, rules: Dictionary) -> Array:
	var out := []
	for count in range(2, parts.size() + 1):
		var image := AssayAssembly.image_of(parts.slice(0, count), rules)
		if image == null:
			return []
		var solid := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a >= SOLID:
					solid += 1
		out.append(solid)
	return out


func _gains(series: Array) -> Array:
	var out := []
	for i in range(1, series.size()):
		out.append(int(series[i]) - int(series[i - 1]))
	return out
