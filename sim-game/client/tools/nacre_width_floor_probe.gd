extends SceneTree
## **WHAT IN THE HUD COLUMN ASKS FOR MORE WIDTH THAN THE COLUMN HAS** (ASSA-247).
##
## **THE DEFECT THIS EXISTS FOR, MEASURED OFF A PICTURE FIRST.** On a 1x shot of the built panel the
## column's ink reaches **x=1279 on 77 rows** -- the window's last column -- where the painted surface
## ends at 1256. `tools/measure_right_edge`-style pixel counting put the content at **344 px in a
## 320 px panel**, and 344 is exactly `PANEL + MARGIN.x`. The same overflow hits `_log_toggle`, which
## is in the chrome and not in any tab, so it is the whole column that is too wide and not my strip.
##
## **WHY A MINIMUM AND NOT A POSITION, which is why this can run headless.** Godot sizes a container's
## child to `max(available, minimum)`, so one node with an oversized `get_combined_minimum_size().x`
## pushes every ancestor out and overflows the panel -- and a `ScrollContainer` with horizontal
## scrolling DISABLED adds its content's minimum width to its own. Minimum size is computed from a
## node's content and does NOT need a layout pass, unlike `position`/`size`, which read 0.0 in this
## harness (the standing rule in this repo). So the chain can be read honestly without a window.
##
## It prints every Control at or under the column whose minimum width exceeds the panel, innermost
## first, with its path -- the offender is the deepest one, because every ancestor above it is only
## reporting what it was asked for.
const WANT := 320.0


func _initialize() -> void:
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(screen)
	screen._ready()
	# A WORLD, so the tab bodies hold real rows rather than their empty notes: an empty list cannot
	# ask for too much width, and the defect is in what a filled one asks for.
	var welcome := AssaySimHost.fresh_welcome_json("14247", "nacre")
	if welcome != "":
		screen._client.play_offline()
		screen._client.feed_offline(welcome)
		screen._refresh()
	print("WIDTH FLOOR PROBE -- panel is %d px" % int(WANT))
	print("  world running: %s" % screen._sim.running())
	var over: Array = []
	_walk(screen, "", over)
	if over.is_empty():
		print("  nothing asks for more than %d px. The overflow is not a minimum-width floor." % int(WANT))
	else:
		# DEEPEST FIRST: an ancestor is only passing on what a child demanded, so the longest path is
		# the one to fix and everything above it is a symptom.
		over.sort_custom(func(a, b): return int(a["depth"]) > int(b["depth"]))
		print("  %d control(s) ask for more than the panel:" % over.size())
		for entry in over:
			print("    %7.1f px  %s  (%s)" % [float(entry["w"]), entry["path"], entry["kind"]])
	quit(0)


func _walk(node: Node, path: String, over: Array, depth: int = 0) -> void:
	var control := node as Control
	if control != null:
		var w := control.get_combined_minimum_size().x
		if w > WANT:
			over.append({"w": w, "path": path, "kind": control.get_class(), "depth": depth})
	for child in node.get_children():
		_walk(child, "%s/%s" % [path, child.name], over, depth + 1)
