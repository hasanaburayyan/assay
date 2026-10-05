extends SceneTree

func _abs(c: Control) -> Rect2:
	var p := Vector2.ZERO
	var n: Node = c
	while n != null and n is Control:
		p += (n as Control).position
		n = n.get_parent()
	return Rect2(p, c.size)

func _initialize() -> void:
	var screen: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(screen)
	screen._ready()
	for i in 3:
		screen._process(0.016)
	for pair in [["log_toggle", screen._log_toggle], ["make_toggle", screen._make_toggle]]:
		var c: Control = pair[1]
		c.notification(Control.NOTIFICATION_THEME_CHANGED)
		var r := _abs(c)
		print("%s rect=%s text=%s ink=%s size=%d" % [pair[0], r, (c as Button).text,
				c.get_theme_color(&"font_color"), c.get_theme_font_size(&"font_size")])
	print("DONE")
	quit()
