extends SceneTree
# CI: local -- needs a real window. It reads laid-out child rectangles, and headless gives every
# Control 0x0, so a gated run would print a column of zeroes and call it an answer.
## WHY IS THE DOOR PLATE NOT IN THE PICTURE (ASSA-292). A real window, a handful of frames, and the
## engine's own answer about the rectangle -- rather than another read of the layout chain, which is
## how I lost an evening on ASSA-198 to a tidy theory that was wrong.
##
## Needs a real window: `_front_door`'s children are window-derived sizes and read 0 headless.
##
## **WHAT IT FOUND, AND IT WAS NOT WHAT I ASKED IT.** It reported the plate visible at 565x1452 and
## I read that as a sizing bug. The sizing was a symptom: `_process` refreshed the world only while a
## session was running, so `_place_door_plate` ran once inside `_ready()` with every child still 0x0.
## The 565x1452 was the one stale rectangle a later frame happened to leave behind. **The probe was
## right and my reading of it was wrong** -- which is the argument for keeping it rather than
## deleting it now the bug is fixed: a question this file can answer in 40 seconds took two wake-ups
## of reasoning about layout chains.


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
