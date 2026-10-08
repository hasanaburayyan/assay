extends SceneTree
## WHY IS THE DOOR PLATE NOT IN THE PICTURE (ASSA-292). A real window, a handful of frames, and the
## engine's own answer about the rectangle -- rather than another read of the layout chain, which is
## how I lost an evening on ASSA-198 to a tidy theory that was wrong.
##
## Needs a real window: `_front_door`'s children are window-derived sizes and read 0 headless.


func _initialize() -> void:
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var plate: ColorRect = screen._door_plate
	var door: Control = screen._front_door
	print("front door   visible=%s  pos=%s  size=%s" % [door.visible, door.position, door.size])
	print("plate        visible=%s  pos=%s  size=%s  colour=%s"
			% [plate.visible, plate.position, plate.size, plate.color])
	print("plate index in parent: %d of %d" % [plate.get_index(), screen.get_child_count()])
	print("world index:           %d" % screen._world.get_index())
	print("front door index:      %d" % door.get_index())
	print("--- children of _front_door ---")
	for child in door.get_children():
		var control := child as Control
		if control == null:
			print("  %s  NOT A CONTROL" % child.name)
			continue
		print("  %-22s visible=%-5s pos=%-18s size=%s"
				% [control.name, control.visible, control.position, control.size])
	quit()
