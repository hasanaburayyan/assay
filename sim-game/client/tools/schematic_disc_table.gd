extends SceneTree
## EVERY DISC THE WHOLE-WORLD SCHEMATIC DRAWS, AS NUMBERS, SO A SHOT CAN BE MEASURED RATHER THAN
## EYEBALLED (ASSA-187).
##
##   godot --headless --path client --script res://tools/schematic_disc_table.gd -- <seed> [json_out]
##
## **IT PRINTS THE GEOMETRY THE PAINTER ITSELF USED, NOT A RE-DERIVATION OF IT.** `main.gd::_draw`
## places a disc at `MARGIN + center * _cell` with radius `max(_cell, radius * _cell)`, and this
## reads `_cell` off a real screen that has joined a real world rather than recomputing the fit. Cove's
## rule from ASSA-181, learned the hard way on an alpha mask: prefer the rect the frame came from over
## any measurement of the frame. The row also carries `filled`, which is `AssayHud.deposit_disc`'s
## answer -- so the python that measures the PNG never has to decide what the picture should show.
##
## **HEADLESS IS CORRECT HERE AND ONLY HERE.** This prints numbers; it photographs nothing. The shot
## it describes has to come from a GUI run (`maren_whole_world_shot.gd`), because a headless viewport
## photographs an empty rectangle. Keeping the two apart is why this tool is 60 lines.
##
## No `_process` loop and no deadline: everything happens in `_initialize` and it quits. There is
## nothing here for ASSA-182's run ceiling to protect.

func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  need a seed")
		quit(1)
		return
	var seed_text := String(argv[0])
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	var welcome := AssaySimHost.fresh_welcome_json(seed_text, "marlow")
	if welcome == "":
		print("FAIL  no world for seed %s" % seed_text)
		quit(1)
		return
	screen._client.play_offline()
	screen._client.feed_offline(welcome)
	screen._refresh()
	screen._show_close_up(false)
	if not screen._sim.running() or screen._close_up or screen._cell <= 0.0:
		print("FAIL  running %s, close_up %s, cell %f: no schematic to describe"
				% [screen._sim.running(), screen._close_up, screen._cell])
		quit(1)
		return
	var margin: Vector2 = screen.MARGIN
	var cell: float = screen._cell
	var rows := []
	for entry in screen._sim.deposits():
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) <= 0:
			continue
		var at := margin + Vector2(deposit["center"] as Vector2i) * cell
		var radius := maxf(cell, float(int(deposit["radius"])) * cell)
		var disc := AssayHud.deposit_disc(deposit, radius)
		rows.append({"symbol": String(deposit["symbol"]), "species": int(deposit["species"]),
				"purity": int(deposit["purity"]), "minable": bool(deposit["hand_minable"]),
				"filled": bool(disc["filled"]), "stroke": float(disc["stroke"]),
				"x": at.x, "y": at.y, "r": radius,
				"colour": [disc["colour"].r, disc["colour"].g, disc["colour"].b]})
	var table := {"seed": seed_text, "cell": cell, "margin": [margin.x, margin.y],
			"map_bg": [AssayHud.MAP_BG.r, AssayHud.MAP_BG.g, AssayHud.MAP_BG.b], "discs": rows}
	var text := JSON.stringify(table, "  ")
	if argv.size() > 1:
		var file := FileAccess.open(String(argv[1]), FileAccess.WRITE)
		if file == null:
			print("FAIL  cannot write %s" % argv[1])
			quit(1)
			return
		file.store_string(text)
		file.close()
		print("wrote %s" % argv[1])
	print(text)
	quit(0)
