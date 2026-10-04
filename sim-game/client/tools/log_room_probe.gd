extends SceneTree
## ASSA-156: HOW TALL IS A LOG LINE, AND DOES THE ENGINE KNOW BEFORE LAYOUT RUNS?
##
## The fix caps the log panel to the room above the player, and the mechanism I want is to drop the
## OLDEST lines until `_log_box.get_combined_minimum_size().y` fits. That only works if a Label's
## minimum height is honest before the container has laid anything out -- and the newest line is the
## one line with `AUTOWRAP_WORD_SMART` on, whose shaped height depends on a width it does not have
## yet. Over-reporting is safe (we drop a line we did not need to); UNDER-reporting is the defect,
## because then the panel draws taller than it measured and lands back on the player's head.
##
## So: ask, do not reason.
##
##   godot --headless --path client --script res://tools/log_room_probe.gd

const LONG := ("512 · machine 2 is a Tonore drill (A) with four hoppers, frame strength 180 of a"
		+ " budget of 240, heat tolerance 60 of 60, and it will run until its hoppers are full or"
		+ " the deposit under it is empty, whichever comes first, which on this grade is about"
		+ " eleven minutes of play")


func _initialize() -> void:
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	var map := AssayHud.world_rect()
	var manifest: Dictionary = AssaySprites.manifest()
	print("map rect ", map)
	print("player ceiling (map-local px) ", AssayScene.player_ceiling(manifest, map.size))
	for label in ["short", "long"]:
		var lines := PackedStringArray()
		for i in 14:
			lines.append("%d · you mined 20 of Tonore ore (A) at (74, 36)" % (400 + i))
		if label == "long":
			lines[13] = LONG
		screen._events = lines
		screen._rebuild_log()
		var box: Control = screen._log_box
		var rows: Array = []
		for child in screen._log.get_children():
			rows.append(snappedf((child as Control).get_combined_minimum_size().y, 0.01))
		print("[%s] newest=%s" % [label, (screen._log.get_child(0) as Label).text.substr(0, 24)])
		print("[%s] box min %s  region min %s" % [label, box.get_combined_minimum_size(),
				(screen._log_region as Control).get_combined_minimum_size()])
		print("[%s] %d rows, heights %s" % [label, rows.size(), rows])
		print("[%s] fits %d of %d, implied panel height %.1f (room %.1f)" % [label,
				screen._log_lines_that_fit(), lines.size(),
				38.0 + rows[0] + float(rows.size() - 1) * 22.0, screen._log_room])
	# THE PARTS, since the container's cached minimum is DEFERRED and reads 12 for a 304px log.
	var inside: Control = screen._log_box.get_child(0)
	var panel_style: StyleBox = screen._log_box.get_theme_stylebox(&"panel")
	var margins := 0.0
	if panel_style != null:
		margins = (panel_style.get_margin(SIDE_TOP) + panel_style.get_margin(SIDE_BOTTOM))
	print("panel style ", panel_style, " margins ", margins)
	print("inside sep ", inside.get_theme_constant(&"separation"),
			"  log sep ", screen._log.get_theme_constant(&"separation"))
	print("heading min ", (screen._log_heading as Control).get_combined_minimum_size())
	var font: Font = screen._log.get_child(0).get_theme_font(&"font")
	var fsize: int = screen._log.get_child(0).get_theme_font_size(&"font_size")
	print("font ", font, " size ", fsize, " row ", font.get_height(fsize))
	for text in ["413 · you mined 20 of Tonore ore (A) at (74, 36)", LONG]:
		print("multiline at 888: ", font.get_multiline_string_size(text,
				HORIZONTAL_ALIGNMENT_LEFT, 888.0, fsize), " for ", text.length(), " chars")
	print("style LR ", panel_style.get_margin(SIDE_LEFT), " ",
			panel_style.get_margin(SIDE_RIGHT), " TB ", panel_style.get_margin(SIDE_TOP), " ",
			panel_style.get_margin(SIDE_BOTTOM))
	var head_size: int = (screen._log_heading as Control).get_theme_font_size(&"font_size")
	var head_font: Font = (screen._log_heading as Control).get_theme_font(&"font")
	print("heading font size ", head_size, " height ", head_font.get_height(head_size))
	var off_tree_font: Font = screen._log.get_theme_font(&"font", &"Label")
	print("log's own font lookup same object: ", off_tree_font == font,
			" size ", screen._log.get_theme_font_size(&"font_size", &"Label"))
	print("heading EXPLICIT type: size ",
			(screen._log_heading as Control).get_theme_font_size(&"font_size", &"Heading"),
			" height ", (screen._log_heading as Control).get_theme_font(&"font",
			&"Heading").get_height((screen._log_heading as Control).get_theme_font_size(
			&"font_size", &"Heading")),
			"  variation is ", (screen._log_heading as Control).theme_type_variation,
			"  in tree ", (screen._log_heading as Control).is_inside_tree())
	screen.queue_free()
	quit(0)
