extends SceneTree
## CI: local -- draws a picture for human eyes; it has no verdict a gate could fail on
## A PICTURE OF WHAT THE ENGINE REALLY COMPOSITES, for human eyes (ASSA-63).
##
## Cove's `shared/assay/part-contract-2026-10-02.png` shows what the rules are FOR, drawn in Python.
## This shows the same thing coming out of Godot's `Image`, through `AssaySprites`' real sheet lookup
## and `AssayAssembly`'s compositor -- which is the half Python cannot vouch for. The suite proves
## properties (a repeat gains real pixels, the shadow rule holds more back with every part); it cannot
## tell anyone whether a drill with four hoppers LOOKS like a drill with four hoppers.
##
## Two rows, both at authoring scale, one machine per column -- a frame and a head, then a hopper
## added each column:
##
##   row 1  by the contract: repeats offset by `repeat_offset_px`, shadows alpha-MAX
##   row 2  naively: same parts, no offset, shadows plain `over` -- Cove's defect, in the engine
##
## UNDER `tools/`, SO IT IS NOT IN THE EXPORT and no shipped script may name it (ASSA-51: `main.gd`
## naming a `tools/` class made the bundle hang, because the export excludes this folder and a missing
## class is a parse error only there).
##
##   godot --headless --script tools/compose_contact.gd -- <out.png>

const HOPPERS := 4
const PAD := 8


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
		print("FAIL  compose_contact.gd: _initialize ended without asking to quit -- see the error above")
		quit(1)
	return true


func _part(kind: String, grade: String, species: int) -> Dictionary:
	return {"kind": kind, "grade": grade, "species": species}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "/tmp/limpet-assay-composite.png" if args.is_empty() else String(args[0])
	var rules := AssayAssembly.contract()
	if rules.is_empty():
		push_error("no drawing contract at %s" % AssayAssembly.CONTRACT)
		_quitting = true
		quit(1)
		return
	var naive := rules.duplicate()
	naive["repeat_offset_px"] = Vector2i.ZERO
	naive["shadow_ceiling"] = 0
	var parts := [_part("frame", "B", 1), _part("head", "B", 1)]
	for _i in range(HOPPERS):
		parts.append(_part("hopper", "B", 1))

	var rows := []
	for layout in [rules, naive]:
		var images: Array[Image] = []
		for count in range(2, parts.size() + 1):
			var image := AssayAssembly.image_of(parts.slice(0, count), layout as Dictionary)
			if image == null:
				push_error("composing %d parts produced no image" % count)
				_quitting = true
				quit(1)
				return
			images.append(image)
		rows.append(images)

	# THE SHEET IS SIZED FROM THE PICTURES, not from numbers typed here: the contract's offset decides
	# how far a machine grows and this script must not hold a second opinion about that.
	var cell := Vector2i.ZERO
	for row in rows:
		for image: Image in row:
			cell.x = maxi(cell.x, image.get_width())
			cell.y = maxi(cell.y, image.get_height())
	var columns: int = (rows[0] as Array).size()
	var sheet := Image.create(columns * (cell.x + PAD) + PAD, rows.size() * (cell.y + PAD) + PAD,
			false, Image.FORMAT_RGBA8)
	# Mid-grey, because a contact shadow on transparent is invisible and on white it is a smudge.
	sheet.fill(Color(0.42, 0.42, 0.44, 1.0))
	for r in range(rows.size()):
		var row: Array = rows[r]
		for c in range(row.size()):
			var image: Image = row[c]
			image.convert(Image.FORMAT_RGBA8)
			# Bottom-aligned in its cell: these sprites stand on the ground, and a machine that grew
			# upward would look like it had moved if every column were drawn from the top.
			var at := Vector2i(PAD + c * (cell.x + PAD),
					PAD + r * (cell.y + PAD) + (cell.y - image.get_height()))
			sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
	if sheet.save_png(out_path) != OK:
		push_error("could not write %s" % out_path)
		_quitting = true
		quit(1)
		return
	print("wrote %s  (%d x %d)" % [out_path, sheet.get_width(), sheet.get_height()])
	print("row 1 by the contract, row 2 naive; columns are a frame and head, then +1 hopper each")
	_quitting = true
	quit(0)
