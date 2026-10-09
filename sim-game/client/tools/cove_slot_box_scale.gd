extends SceneTree

## **WHAT `_slot_box` ACTUALLY PUTS IN ITS 32x32 PLATE**, read off `AssaySprites.icon_for` and the
## shipped `manifest.json` rather than off the sentence in `main.gd`.
##
## `main.gd::_slot_box`'s doc says the plate is `ICON_PX` square because
## `STRETCH_KEEP_ASPECT_CENTERED` scales a **128x102 part cell** by `min(32/128, 32/102)` = 1/4, *"so
## the width is what binds and nothing is resampled"*. `_slot_box` calls `_icon_box(part, ...)`, which
## calls `icon_for`, which reads `SHEET_OF` -- and ASSA-121 moved all four part kinds there from
## `ASSEMBLY_SHEET_OF`. So this prints, per kind: the region the engine would actually draw, the scale
## that mode picks, which axis binds, and the drawn rect inside both candidate boxes.
##
## Run: $GODOT --headless --path sim-game/client --script res://tools/cove_slot_box_scale.gd
##
## CI: local -- it PRINTS a table and judges nothing, so a gate could only assert the numbers it
## prints, and those are already asserted where they belong:
## `test_a_part_in_a_square_slot_plate_binds_on_height_and_overruns_it` in tests/test_sprites.gd
## reads the same regions and the same main.gd constants and reddens on all three of them. A second
## reader of one quad is the thing `pack_icon_draw.py` exists to prevent.

const ICON_PX := 32.0
const ICON_BOX_PX := Vector2(32.0, 48.0)


func _fit(frame: Vector2, box: Vector2) -> Dictionary:
	# STRETCH_KEEP_ASPECT_CENTERED, written out: the smaller ratio, both axes.
	var sx := box.x / frame.x
	var sy := box.y / frame.y
	var s: float = min(sx, sy)
	return {
		"scale": s,
		"binds": "width" if sx <= sy else "height",
		"drawn": frame * s,
		"fill": (frame.x * s * frame.y * s) / (box.x * box.y) * 100.0,
	}


func _init() -> void:
	var kinds := ["handle", "head", "frame", "hopper", "ore", "refined", "smelter"]
	print("kind      sheet      region        scale  binds   drawn in 32x32      drawn in 32x48")
	for kind in kinds:
		var stack := {"kind": kind, "species": "Tonore", "grade": "A", "count": 1}
		var icon: AtlasTexture = AssaySprites.icon_for(stack)
		if icon == null:
			print("%-9s  (no icon)" % kind)
			continue
		var frame := icon.region.size
		var sheet := String(AssaySprites.SHEET_OF.get(kind, "?"))
		var sq := _fit(frame, Vector2(ICON_PX, ICON_PX))
		var pr := _fit(frame, ICON_BOX_PX)
		print("%-9s %-10s %4dx%-4d  %8.4f  %-6s  %5.1fx%-5.1f %4.1f%%   %5.1fx%-5.1f %4.1f%%" % [
			kind, sheet, frame.x, frame.y,
			sq["scale"], sq["binds"],
			(sq["drawn"] as Vector2).x, (sq["drawn"] as Vector2).y, sq["fill"],
			(pr["drawn"] as Vector2).x, (pr["drawn"] as Vector2).y, pr["fill"],
		])
	print("")
	print("THE SENTENCE'S OWN ARITHMETIC, for comparison: a 128x102 assembly cell in a 32x32 box")
	var a := _fit(Vector2(128, 102), Vector2(ICON_PX, ICON_PX))
	print("  scale %.4f, binds %s, drawn %.1fx%.1f, fill %.1f%%" % [
		a["scale"], a["binds"], (a["drawn"] as Vector2).x, (a["drawn"] as Vector2).y, a["fill"],
	])
	print("")
	print("ASSEMBLY_SHEET_OF, which is where a 128x102 cell still lives, and the manifest's frame_px:")
	var man := AssaySprites.manifest()
	for kind in ["handle", "head", "frame", "hopper"]:
		var sheet := String(AssaySprites.ASSEMBLY_SHEET_OF.get(kind, "?"))
		var spec: Dictionary = (man.get(sheet, {}) as Dictionary)
		print("  %-8s ASSEMBLY_SHEET_OF -> %-8s frame_px %s" % [
			kind, sheet, str(spec.get("frame_px", "(not in manifest)")),
		])
	var items_spec: Dictionary = (man.get("items", {}) as Dictionary)
	print("  items sheet frame_px %s" % str(items_spec.get("frame_px", "(not in manifest)")))
	quit()
