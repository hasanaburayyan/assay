extends SceneTree
## CI: local -- dumps the scatter plan as text for someone to check by eye

## **THE SCATTER LAYER'S PLAN, AS TEXT, SO SOMEONE ELSE CAN CHECK IT.**
##
## `AssayScene.scatter_at` decides what the second ground layer draws from a tile coordinate and
## nothing else (ASSA-202/210). The claim that it is deterministic and reproducible OUTSIDE the engine
## was carried by a scratch script in `/tmp` and a Python twin in
## `shared/assay/cove-assa202/proof.py`, which is why Nerite's QA on PR #280 had to write "I did NOT
## reproduce the determinism diff against proof.py, so those boxes stay Cove's on Cove's evidence".
## A control only QA cannot run is not a control. This is that script, committed.
##
## USAGE, from `client/`:
##
##     $GODOT --headless --script tools/scatter_plan_dump.gd -- [x0 y0 x1 y1]
##
## and the same range out of the Python twin, then `diff`. Default range is (-40,-40)..(119,119) =
## 25,600 tiles, which is 50 screens and deliberately includes the NEGATIVE QUADRANT: `_scatter_field`
## uses `floori`/`posmod` exactly because truncating division folds negative tiles onto the wrong
## cell, and that bug moves 2,222 of the props in this range while leaving every positive tile alone.
##
## EVERY NUMBER IS PRINTED AT FULL PRECISION AND THE OFFSET IS NOT ROUNDED. The offsets are sub-tile
## floats on purpose (ASSA-197); a dump that rounded them would agree with a floored implementation,
## which is the one thing this is here to catch.
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var box := [-40, -40, 120, 120]
	if args.size() == 4:
		for i in range(4):
			box[i] = int(args[i])
	var props := 0
	for y in range(box[1], box[3]):
		for x in range(box[0], box[2]):
			for prop in AssayScene.scatter_at(Vector2i(x, y)):
				var off: Vector2 = prop[1]
				print("%d %d %s %.6f %.6f" % [x, y, String(prop[0]), off.x, off.y])
				props += 1
	printerr("%d props over %d tiles" % [props, (box[2] - box[0]) * (box[3] - box[1])])
	quit(0)
