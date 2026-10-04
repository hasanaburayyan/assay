extends SceneTree
## WHAT THE EVENT LOG SAYS ON THE JOIN SCREEN, BEFORE THERE IS A WORLD (Maren).
##
##   godot --path client --script res://tools/maren_join_log_shot.gd -- <out_dir>
##   (A GUI RUN. Never --headless.)
##
## Nerite saw that `show the event log (L)` is drawn live before any join and said they could not
## tell from a picture whether it is dead, because they did not press it. Neither could I, so this
## presses it: no relay, no join, the first screen a stranger sees, with the log open.
##
## It is a question about a SENTENCE, so it also prints the log's children verbatim -- the picture
## answers "how does this read", the text answers "which string is it".

func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("FAIL  need an output directory")
		quit(1)
		return
	var out := String(argv[0])
	DirAccess.make_dir_recursive_absolute(out)
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	print("stage before anything: %d (IDLE=%d)"
			% [screen._client.stage, AssayNetClient.Stage.IDLE])
	print("log toggle text: %s   disabled: %s"
			% [screen._log_toggle.text, screen._log_toggle.disabled])
	print("log shown at build: %s" % screen._log_shown)
	# THE PRESS ITSELF, through the button's own signal rather than `_show_log`, so this measures
	# what a person's click does and not what I think it is wired to.
	screen._log_toggle.emit_signal("pressed")
	screen._rebuild_log()
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	print("after the press, toggle reads: %s" % screen._log_toggle.text)
	var said := PackedStringArray()
	for child in screen._log.get_children():
		if child is Label:
			said.append((child as Label).text)
	print("the log's own lines: %s" % str(said))
	print("rocks section says: %s" % _first_label(screen._species))
	var image := root.get_texture().get_image()
	var path := out.path_join("join-log-open.png")
	if image.save_png(path) != OK:
		print("FAIL  could not write %s" % path)
		quit(1)
		return
	print("  wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	print("WINDOW SHOT OK")
	quit(0)


func _first_label(node: Node) -> String:
	for child in node.get_children():
		if child is Label:
			return (child as Label).text
	return "(none)"
