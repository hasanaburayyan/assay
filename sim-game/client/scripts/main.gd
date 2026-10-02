extends Node2D
## THE WHOLE CLIENT A PLAYER SEES, for now: a host address, a name, and the world you are in.
##
## Decision 1's test is "a friend with no terminal can download a build, enter a host address and
## play", so the address field is not a debug convenience -- it is the front door, and it is here on
## the first screen rather than behind a menu.
##
## WHAT IS DRAWN IS THE WORLD THE SIM STEPPED, not a guess at it. A tick bundle carries inputs, not
## state; turning inputs into a newer world is `sim::step`, which this client now runs through
## `AssaySimHost`. Nothing here predicts, interpolates or recomputes: a position on screen is a
## position the sim is actually on, and if the sim has not reached a tick yet then neither has the
## picture. Until the first `Welcome` there is nothing to draw at all.

## WHERE THINGS GO lives in `AssayHud` with the rest of the view's rules, so the one that matters can
## be tested: the HUD column sits BESIDE the map (Maren's ruling, ASSA-7), its width coming out of the
## map's own width term rather than covering it.
##
## AND THE COLUMN IS WHERE A PERSON ACTS (ASSA-37). Until now only the scripted probe could mine,
## craft, equip or plant; a human could walk, look and read. Every button below submits the SAME
## `PlayerCommand` `sim-cli` sends, built by `AssayActions` -- the one file that spells a command, so
## that the probe and the buttons cannot drift apart. No button predicts, none refuses, and none
## decides whether what it asked for was legal: `sim::step` validates on every peer, and the answer
## comes back in the event log a tick later.
const MARGIN := AssayHud.MARGIN
const VIEW := AssayHud.VIEW
const PANEL := AssayHud.PANEL
## Event lines kept on screen. A tick can produce several and they arrive ten times a second, so this
## is the last few seconds of the world, not a history.
const LOG_LINES := 14

var _client: AssayNetClient
var _sim := AssaySimHost.new()
var _host := LineEdit.new()
var _name := LineEdit.new()
var _status := Label.new()
var _detail := Label.new()
## THE PACK, AS ROWS YOU CAN ACT ON (ASSA-37). A container and not a Label any more: a stack's row
## carries the verbs that stack affords, which is what turns "3 × ore" from a readout into the start
## of the craft chain. The words are still `AssayHud.stack_line`'s, so the list reads the same.
var _carrying := VBoxContainer.new()
## WHAT YOU CAN DO WHERE YOU ARE: Mine, Stop, Assay, the tile every placement lands on, and the
## verbs of whatever building is on it.
var _actions := VBoxContainer.new()
var _cursor := Label.new()
var _log := Label.new()
## THE PART MENU'S HOME: one headline label plus one body label per design, rebuilt only when the
## list changes. Not a Label like the others, because the verdict is a WORD IN ITS OWN COLOUR above
## numbers in another (Maren's ruling) and one Label can only be one colour.
var _bench := VBoxContainer.new()
## What each section was last built from, so ten refreshes a second do not rebuild nodes that have
## not changed. The sim's own values are the signature: if they are identical, so is the panel. This
## matters more now than it did -- rebuilding a row ten times a second would destroy a button under
## the pointer -- and A BUTTON NEVER CAPTURES THE STATE IT ACTS ON. It reads the target tile and the
## sim when it is PRESSED, so choosing a tile after seeing the button works and costs no rebuild.
## NOT "" -- AN EMPTY PACK AND AN EMPTY BENCH HAVE AN EMPTY SHAPE, so starting these at "" made the
## first refresh a no-op and left the sections blank until something was mined. The suite caught it
## because `test_main_screen.gd` asserts the empty bench says which kind of empty it is; without that
## line the shipped client would have had two headings over nothing on its first screen.
const UNBUILT := "nothing built yet"
var _bench_showing := UNBUILT
var _pack_showing := UNBUILT
var _actions_showing := UNBUILT
## THE TILE EVERY PLACEMENT LANDS ON. `_targeted` false means "where you stand", which is not a
## placeholder: your own tile is the one tile every player has, and planting beside yourself is the
## common case. Right-click chooses another; left-click still walks, because walking is the thing a
## player does most.
var _target := Vector2i.ZERO
var _targeted := false
## THE PARTS CHOSEN FOR THE NEXT `Assemble`, as the SIM'S OWN STACKS so a row can be named on screen
## and sent as an item without this client inventing either. THE FIRST ONE IS THE FRAME, which is
## `sim-cli`'s rule (`assemble <frame> <part>...`) kept rather than invented.
var _building: Array = []
## The tile size the map is drawn at, so a click can be turned back into a tile. 0 means there is no
## world yet and a click means nothing.
##
## SET BY `_refresh`, NOT BY `_draw`, and that was a real bug rather than tidying. A click turning
## into a tile used to depend on a frame having already been painted: the first click after a Welcome
## could land before the first `_draw` and be silently dropped, and HEADLESS THERE IS NO `_draw` AT
## ALL -- so no test could ever press the map. It is `AssayHud.map_cell`'s pure answer either way.
var _cell := 0.0
## Hash reports actually put on the wire. See `_on_tick_bundle`.
var _hashes_sent := 0
## The tile under the mouse, and whether the mouse has ever been over the map. Not a Vector2i alone,
## because tile (0, 0) is a real tile and "no hover" is not it.
var _hover := Vector2i.ZERO
var _hovering := false
## The newest event lines, oldest first. View state: the sim keeps only the last tick's events, so
## anything older than that is remembered here or nowhere.
var _events := PackedStringArray()


func _ready() -> void:
	# CI, not a player: prove the build it just exported works, then leave. Before any UI, because
	# a self-check that needed the window would not run on a build server.
	var selfcheck := AssaySelfCheck.requested_path()
	if selfcheck != "":
		get_tree().quit(AssaySelfCheck.run(selfcheck))
		return
	# THE WHOLE SCREEN IS BUILT ONCE, AND THE LINK IS PART OF THE SCREEN. The guard used to sit in
	# `_build_ui`, which covered the HUD and nothing else -- so a second `_ready` built a SECOND
	# `AssayNetClient` and left `_client` pointing at it. The first one stayed connected to every
	# handler here, so the world kept stepping while `_client.stage` read IDLE and
	# `_client.player_id` read -1: the HUD showed somebody else's empty inventory of a world that was
	# plainly moving. Found by `tools/button_session.gd` against a real relay, where it looked like a
	# join that never happened; the suite could not see it because nothing in it joins.
	if _built:
		return
	_built = true
	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.refused.connect(func(reason): _say("refused: %s" % reason, AssayHud.Say.FAILED))
	_client.link_failed.connect(func(reason): _say(reason, AssayHud.Say.FAILED))
	_client.tick_bundle.connect(_on_tick_bundle)
	_client.desynced.connect(func(tick): _say(
			"desync at tick %d. Restart the client to rejoin (Decision 3: no reconnect)." % tick,
			AssayHud.Say.FAILED))
	# A note is narration, so its state is whatever the link's state already is.
	_client.note.connect(func(line): _say(line, AssayHud.Say.JOINED
			if _client.stage == AssayNetClient.Stage.JOINED else AssayHud.Say.CONNECTING))
	add_child(_client)
	_build_ui()
	_say("enter a host address and join", AssayHud.Say.IDLE)


## WHETHER `_ready` HAS ALREADY RUN. `tests/test_main_screen.gd` and `tools/button_session.gd` both
## call `_ready()` by hand (a `--script` run works inside `SceneTree._initialize`, before the root
## window is in the tree, so the engine's own call comes too late to be useful) AND put the node in
## the tree, so the engine calls it again.
##
## The first thing that caught was the HUD column being built twice, with every label reparented into
## the second one: harmless on screen, but it filled the suite's output with `Can't add child ...
## already has a parent`, and error spam nobody reads is where a real error goes to hide. The second
## was worse and is why this guard moved up to `_ready` -- see the note there.
var _built := false


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(24.0, 20.0)
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var host_label := Label.new()
	host_label.text = "host"
	row.add_child(host_label)
	_host.text = "localhost:%d" % AssayProtocol.DEFAULT_PORT
	_host.custom_minimum_size = Vector2(240.0, 0.0)
	_host.tooltip_text = "host, host:port, or [v6]:port. A bare address uses 7777."
	row.add_child(_host)

	var name_label := Label.new()
	name_label.text = "name"
	row.add_child(name_label)
	_name.text = OS.get_environment("USER")
	_name.custom_minimum_size = Vector2(140.0, 0.0)
	row.add_child(_name)

	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(_on_join)
	row.add_child(join)

	_status.position = Vector2(24.0, 54.0)
	add_child(_status)
	_detail.position = Vector2(24.0, 74.0)
	add_child(_detail)

	# THE HUD COLUMN, beside the map. Each section is the plainest thing that answers one question:
	# what am I carrying, what can I do here, what have I built, what is under the cursor, what just
	# happened.
	#
	# SCROLLED, SINCE THE ROWS GREW BUTTONS. A full pack plus a bench is taller than 720px, and a
	# button pushed off the bottom of the window is worse than a disabled one -- it looks available
	# and cannot be pressed. The scroll box is what carries the position now; the inner column sits at
	# the origin inside it.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(VIEW.x - PANEL - MARGIN.x, MARGIN.y)
	scroll.custom_minimum_size = Vector2(PANEL, VIEW.y - MARGIN.y - 24.0)
	scroll.size = scroll.custom_minimum_size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(PANEL, 0.0)
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	for part in [["you", _carrying], ["do", _actions], ["bench", _bench], ["cursor", _cursor],
			["last tick", _log]]:
		var heading := Label.new()
		heading.text = String(part[0])
		heading.modulate = Color(0.60, 0.64, 0.70)
		column.add_child(heading)
		var body: Control = part[1]
		body.custom_minimum_size = Vector2(PANEL, 0.0)
		if body is Label:
			(body as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(body)
	_refresh_pack()
	_refresh_actions()
	_refresh_bench()


func _on_join() -> void:
	if _client.stage != AssayNetClient.Stage.IDLE and _client.stage != AssayNetClient.Stage.DEAD:
		_say("already joining; restart the client to change host (no reconnect in the demo)",
				AssayHud.Say.FAILED)
		return
	# SAID BEFORE THE CALL, not after it: `join` does reach a socket, and a button that shows nothing
	# until the answer comes back reads as a dead button. Maren's ruling, and she had the premise
	# slightly wrong -- `join` already emits a "connecting to ..." note of its own -- but only on the
	# path where `connect_to_host` succeeds, so this is the line that is true either way.
	_say("connecting to %s…" % _host.text, AssayHud.Say.CONNECTING)
	_client.join(_host.text, _name.text if _name.text != "" else "player")


## THE RAW TEXT GOES TO THE SIM, the dictionary does not. By the time a `Welcome` is a Godot
## Dictionary its numbers have been through a double, so the world is built from the bytes.
func _on_welcomed(player: int, _world: Dictionary, raw: String) -> void:
	if not _sim.start(raw):
		_say("joined as player %d, but cannot simulate: %s" % [player, _sim.fail_reason],
				AssayHud.Say.FAILED)
		_refresh()
		return
	_say("joined as player %d" % player, AssayHud.Say.JOINED)
	_refresh()
	queue_redraw()


## One tick: step the world, then report a hash if one is owed.
##
## The hash is the whole point of being a lockstep peer -- it is how the relay tells us our world has
## drifted instead of letting us play a different game quietly. The message is written in Rust
## because its `hash` is a `u64`; see `protocol.gd`.
func _on_tick_bundle(_tick: int, _inputs: Array, raw: String) -> void:
	var report := _sim.apply(raw)
	# Counted on the SEND, not on the produce: a report that never left is a report the relay never
	# checked, and the status line would be claiming a check that did not happen.
	if report != "" and _client.send_text(report):
		_hashes_sent += 1
	_remember_events()
	_refresh()
	queue_redraw()


## What the tick we just applied did, kept where it can be read. The sim holds only the newest tick's
## events, so a line not copied out here is gone a tenth of a second later.
func _remember_events() -> void:
	var tick := _sim.tick()
	for line in _sim.event_lines(_client.player_id):
		_events.append("%d · %s" % [tick, line])
	_events = AssayHud.trimmed_log(_events, LOG_LINES)


func _say(line: String, level: int) -> void:
	_status.text = line
	_status.modulate = AssayHud.status_color(level)
	print(line)


func _refresh() -> void:
	if not _sim.running():
		var joined: Dictionary = _client.joined_world
		if joined.is_empty():
			return
		_detail.text = ("joined at tick %d, but no world is being simulated: %s"
				% [int(joined.get("tick", -1)), _sim.fail_reason])
		return
	# The tile under the mouse, or your own tile until the mouse has been over the map. Which one it
	# is has to be on screen: a readout that silently changed subject would be unreadable.
	var at := _hover
	var source := "under the mouse"
	if not _hovering:
		at = _my_tile()
		source = "where you stand"
	_cursor.text = "%s\n%s" % [source, "\n".join(AssayHud.tile_lines(_sim.tile_at(at)))]
	_log.text = "\n".join(_events)
	# WHICH WORLD, WHICH TICK, WHICH HASH. The seed and the hash are TEXT, because a u64 cannot
	# survive a GDScript number -- that is not caution, it is measured. The bundle and hash counts are
	# here because a client that has stopped applying bundles looks exactly like one that is idle.
	var size := _sim.size_tiles()
	# WHERE A CLICK LANDS, WORKED OUT WITHOUT PAINTING ANYTHING. See `_cell`.
	_cell = AssayHud.map_cell(size)
	_detail.text = ("world seed %s, %d x %d tiles, %d species, %d players · tick %d, hash %s · "
			+ "%d bundles applied, %d hashes reported") % [
			_sim.seed_text(), size.x, size.y, _sim.species_names().size(), _sim.players().size(),
			_sim.tick(), _sim.hash_hex(), _sim.applied, _hashes_sent]
	_refresh_pack()
	_refresh_actions()
	_refresh_bench()


## THE PART MENU: every design you hold, verdict first, with the one verb that design affords.
##
## Maren's ruling, and the reason this is nodes rather than one Label: THE VERDICT IS THE HEADLINE
## AND THE NUMBERS ARE THE SMALL PRINT. A player predicting a break should read one word, not
## compare two integers -- so the word is its own label, in the verdict's own colour and larger,
## with the spans under it in grey.
##
## NOTHING HERE DECIDES ANYTHING. The verdict, the spans, the durability wording and the list of
## species still reading rough all arrive from `sim` through the binding. The one thing this client
## adds is the arrangement -- and now the button, whose command is `AssayActions`' and whose legality
## is `sim::step`'s. PLACE IS ON EVERY PLANTED ROW WHATEVER THE VERDICT SAYS: an over-budget design
## breaks at placement, which is where the sim tests mass, and hiding the button would turn a
## mechanic into an error message (Maren's ruling, ASSA-5/7).
##
## THE STRUCTURE IS THE SIGNATURE, NOT THE WHOLE LIST, and that is not an optimisation. Durability
## moves every swing, so rebuilding on any change at all would free the Place button under the
## pointer four times a second while the player is mining. The rows stay; the numbers in them are
## rewritten.
func _refresh_bench() -> void:
	var designs := _sim.designs_of(_client.player_id) if _client != null else []
	var signature := _bench_shape(designs)
	if signature != _bench_showing:
		_bench_showing = signature
		_rebuild_bench(designs)
		return
	for i in range(designs.size()):
		_write_design(_bench.get_child(i), designs[i] as Dictionary)


## What a bench LOOKS like, ignoring every number that moves on its own: which designs, in which
## order, on which mount, and which verb each one offers.
func _bench_shape(designs: Array) -> String:
	var shape := PackedStringArray()
	for entry in designs:
		var design: Dictionary = entry
		shape.append("%d/%s/%s" % [int(design.get("index", -1)),
				"hand" if bool(design.get("in_hand", false)) else "bench",
				String(design.get("mount", "?"))])
	return "|".join(shape)


func _rebuild_bench(designs: Array) -> void:
	_clear(_bench)
	if designs.is_empty():
		_bench.add_child(_note(AssayHud.no_designs_line()))
		return
	for entry in designs:
		var design: Dictionary = entry
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var verdict := Label.new()
		verdict.add_theme_font_size_override("font_size", 19)
		row.add_child(verdict)
		var body := Label.new()
		body.modulate = Color(0.78, 0.80, 0.85)
		body.add_theme_font_size_override("font_size", 13)
		body.custom_minimum_size = Vector2(PANEL, 0.0)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(body)
		row.add_child(_verb_row(AssayHud.design_verbs(design),
				func(descriptor: Dictionary) -> Button: return _design_button(descriptor, design)))
		_bench.add_child(row)
		_write_design(row, design)


## The numbers in one row, rewritten. The verdict is a WORD IN ITS OWN COLOUR, and it can change
## under a static row -- an assay turns UNCERTAIN into SAFE or WILL BREAK without the design moving.
func _write_design(row: Node, design: Dictionary) -> void:
	var verdict: Label = row.get_child(0) as Label
	var body: Label = row.get_child(1) as Label
	if verdict == null or body == null:
		return
	verdict.text = String(design.get("verdict", "?"))
	verdict.modulate = AssayHud.verdict_color(verdict.text)
	body.text = "\n".join(AssayHud.design_lines(design))


## One verb on one design row. `index` is the sim's, NOT the row's position: the tool in hand is a
## row with no index of its own (`designs_of` reports -1 for it), so counting rows would equip the
## wrong design the moment anything was in hand.
func _design_button(descriptor: Dictionary, design: Dictionary) -> Button:
	var label := String(descriptor.get("label", "?"))
	var index := int(design.get("index", -1))
	match String(descriptor.get("verb", "")):
		"equip":
			return _button(label, func() -> void: _act(label, AssayActions.equip(index)),
					"take this design into your hands")
		"unequip":
			return _button(label, func() -> void: _act(label, AssayActions.unequip()),
					"put the tool in your hands back on the bench")
		"place_assembly":
			# NEVER DISABLED AND NEVER CHECKED FIRST. Over budget is not this client's verdict to act
			# on: the sim breaks the design at placement and hands the parts back.
			return _button(label, func() -> void: _act("%s %d" % [label, index],
					AssayActions.place_assembly(index, _target_tile())),
					"plant this design on the tile you are acting on")
		_:
			return _button(label, func() -> void: _say(
					"no command for %s" % label, AssayHud.Say.FAILED))


## THE PACK, AS ROWS YOU CAN ACT ON. The words are `AssayHud.stack_line`'s and the verbs are
## `AssayHud.stack_verbs`', which reads them out of the sim's own recipe table and part catalogue --
## so a Craft button exists because some hand recipe eats this kind of item, and for no other reason.
##
## SAME SIGNATURE RULE AS THE BENCH: a count climbs every mining cycle, so only the shape of the pack
## rebuilds the rows.
func _refresh_pack() -> void:
	var stacks := _sim.inventory_of(_client.player_id) if _client != null else []
	var signature := "%s@%d" % [_pack_shape(stacks), _building.size()]
	if signature != _pack_showing:
		_pack_showing = signature
		_rebuild_pack(stacks)
		return
	for i in range(stacks.size()):
		var label: Label = _carrying.get_child(i).get_child(0) as Label
		if label != null:
			label.text = AssayHud.stack_line(stacks[i] as Dictionary)


## What a pack LOOKS like: which items, in which order. Not how many of each, which climbs on its
## own every mining cycle.
func _pack_shape(stacks: Array) -> String:
	var shape := PackedStringArray()
	for entry in stacks:
		var stack: Dictionary = entry
		shape.append("%s/%d/%s" % [String(stack.get("kind", "?")), int(stack.get("species", -1)),
				String(stack.get("grade", "?"))])
	return "|".join(shape)


func _rebuild_pack(stacks: Array) -> void:
	_clear(_carrying)
	if stacks.is_empty():
		_carrying.add_child(_note(AssayHud.nothing_carried_line()))
		return
	var recipes := AssaySimHost.recipes()
	var part_kinds := AssaySimHost.part_kinds()
	for entry in stacks:
		var stack: Dictionary = entry
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		label.custom_minimum_size = Vector2(PANEL, 0.0)
		row.add_child(label)
		# WHETHER AN ITEM CAN BE PLACED IS THE SIM'S ANSWER TOO, by footprint: 2x2 for a smelter, 0x0
		# for a thing that is not a building.
		var footprint := AssaySimHost.footprint_of_item(String(stack.get("kind", "")),
				int(stack.get("species", -1)), String(stack.get("grade", "C")))
		var verbs := AssayHud.stack_verbs(stack, recipes, part_kinds, footprint,
				not _building.is_empty())
		if not verbs.is_empty():
			row.add_child(_verb_row(verbs, func(descriptor: Dictionary) -> Button:
					return _stack_button(descriptor, stack, footprint)))
		_carrying.add_child(row)
		label.text = AssayHud.stack_line(stack)


## One verb on one stack. EVERY ITEM SENT IS THE ONE THE SIM NAMED: `item_of_stack` rearranges the
## three fields out of `inventory_of` and this client never works out what it is carrying.
func _stack_button(descriptor: Dictionary, stack: Dictionary, footprint: Vector2i) -> Button:
	var label := String(descriptor.get("label", "?"))
	var count := int(stack.get("count", 0))
	var what := AssayHud.stack_line(stack)
	match String(descriptor.get("verb", "")):
		"craft":
			var recipe: Variant = descriptor.get("recipe")
			return _button(label, func() -> void: _act(label,
					AssayActions.craft(recipe, AssayActions.item_of_stack(stack), 1)),
					"one batch, from %s" % what)
		"insert":
			# THE WHOLE STACK. A button cannot ask for a quantity without growing a field, and
			# picking a smaller number for the player would be this client deciding how much fuel a
			# fire wants -- which is a sheet reading it does not have. `Pick up` gives a building and
			# its contents back, so nothing is spent for good.
			#
			# AND "THE WHOLE STACK" IS COUNTED WHEN THE BUTTON IS PRESSED, NOT WHEN IT WAS BUILT.
			# This is the rule at the top of the file and I broke it here first: the row only
			# rebuilds when the pack's SHAPE changes, so a count captured in the closure froze at
			# whatever was in hand the moment the row appeared. The button-driven session caught it
			# -- it pressed `Fuel` on a row reading 12 and inserted 2, and the fire went out
			# mid-stack. A tooltip with a number in it would go stale the same way, so it has none.
			var slot := String(descriptor.get("slot", ""))
			return _button(label, func() -> void: _insert(stack, slot),
					"put everything you are carrying of this into the %s slot of the building you "
							% slot + "are acting on")
		"place":
			return _button(label, func() -> void: _act(label,
					AssayActions.place(AssayActions.item_of_stack(stack), _target_tile())),
					"stand it on the %d x %d tiles from the one you are acting on"
							% [footprint.x, footprint.y])
		"make":
			var kind: Variant = descriptor.get("kind")
			var part := String(descriptor.get("part", "?"))
			return _button(label, func() -> void: _act(label,
					AssayActions.make_part(kind, AssayActions.item_of_stack(stack), 1)),
					"one %s, out of this material" % part)
		"build":
			return _button(label, func() -> void: _choose_part(stack),
					"use as the frame of the next machine" if _building.is_empty()
							else "mount on the frame you chose")
		_:
			return _button(label, func() -> void: _say(
					"no command for %s" % label, AssayHud.Say.FAILED))


## WHAT YOU CAN DO WHERE YOU ARE: the three actions that need no item, the tile every placement lands
## on, the verbs of whatever building is on it, and the assembly you are part-way through.
##
## THE SIGNATURE HOLDS ONLY THE BUILDING'S ID, never its status. A smelter's status sentence changes
## every tick while it burns, and rebuilding on that would free the Take button four times a second.
func _refresh_actions() -> void:
	var target := _target_tile()
	var facts := _sim.tile_at(target) if _sim.running() else {}
	var building: Variant = facts.get("building")
	var at := -1 if building == null else int((building as Dictionary).get("id", -1))
	var signature := "%s/%s/%d/%s" % [target, _targeted, at, _building]
	if signature == _actions_showing:
		return
	_actions_showing = signature
	_clear(_actions)
	if not _sim.running():
		# Before a Welcome there is no tile to act on and no player to act as. A row of buttons that
		# could only report "not joined" would be the Join button's answer in a worse place.
		_actions.add_child(_note("join a world and these become the things you can do"))
		return

	var here := HBoxContainer.new()
	here.add_theme_constant_override("separation", 4)
	here.add_child(_button("Mine", func() -> void: _act("Mine", AssayActions.mine()),
			"hand-mine the deposit under you. Keeps swinging until you Stop."))
	here.add_child(_button("Stop", func() -> void: _act("Stop", AssayActions.stop()),
			"stop walking, mining, crafting and assaying"))
	here.add_child(_button("Assay", func() -> void: _act("Assay", AssayActions.assay()),
			"study the deposit under you until its sheet reads exact instead of in bands"))
	_actions.add_child(here)
	_actions.add_child(_note(AssayHud.target_line(target, _targeted, facts)))

	if building != null:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(_button("Take", func() -> void: _act("Take", AssayActions.take(at)),
				"empty the output slot into your pack"))
		row.add_child(_button("Pick up", func() -> void: _act("Pick up", AssayActions.pickup(at)),
				"take the building back, with whatever is inside it"))
		_actions.add_child(row)

	if not _building.is_empty():
		_actions.add_child(_note(AssayHud.building_line(_building)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(_button("Assemble", _assemble,
				"build the machine from the parts you chose"))
		row.add_child(_button("Clear", _clear_build, "put the chosen parts back"))
		_actions.add_child(row)


## ONE DOOR FOR EVERY BUTTON ON THIS SCREEN, and the only place any of them reaches the wire.
##
## It says what it sent, because a button that shows nothing reads as a dead button (Maren's ruling
## on Join, and the same argument applies here). It does not predict: the world changes when a bundle
## carrying this command comes back around and the sim steps, which for the player's own action is
## about a tick later.
func _act(what: String, command: Variant) -> void:
	if _client.submit(command):
		_say("%s · submitted at tick %d" % [what, _sim.tick()], AssayHud.Say.JOINED)
		return
	_say("%s · not submitted; join a world first" % what, AssayHud.Say.FAILED)


## Insert needs a building, and there may not be one. THIS IS NOT A REFUSAL -- with no building there
## is no `BuildingId` to put in the command at all, so there is nothing to send and saying so is the
## only honest answer. Maren's "never refuse" is about commands the sim should judge.
func _insert(stack: Dictionary, slot: String) -> void:
	var target := _target_tile()
	var building: Variant = _sim.tile_at(target).get("building")
	if building == null:
		_say("nothing to insert into at %d, %d — right-click a building first"
				% [target.x, target.y], AssayHud.Say.FAILED)
		return
	# HOW MANY WE ARE ACTUALLY CARRYING, ASKED NOW. Grade is part of the question: two grades of one
	# ore are two stacks and two rows, and inserting the other row's count would be a number from a
	# different row.
	var count := AssayDemoPlan.held(_sim.inventory_of(_client.player_id),
			String(stack.get("kind", "")), int(stack.get("species", -1)),
			String(stack.get("grade", "")))
	if count <= 0:
		_say("you are not carrying any %s any more" % String(stack.get("name", "?")),
				AssayHud.Say.FAILED)
		return
	_act("Insert %d into %s" % [count, slot], AssayActions.insert(
			int((building as Dictionary).get("id", -1)), slot,
			AssayActions.item_of_stack(stack), count))


## Choose a part for the next `Assemble`. The first one is the FRAME, which is `sim-cli`'s rule kept
## rather than invented, and the row's button says which it is about to be.
func _choose_part(stack: Dictionary) -> void:
	_building.append(stack)
	_say("%s %s" % ["frame:" if _building.size() == 1 else "mounting", AssayHud.stack_line(stack)],
			AssayHud.Say.JOINED)
	_refresh_pack()
	_refresh_actions()


## Build the machine. REJECTED ONLY FOR PARTS THAT DO NOT FIT, never for weight -- mass is tested at
## placement (sim decision 11). The choice is cleared either way: the event log carries the sim's
## reason, and a half-chosen assembly left on screen after a refusal reads as a stuck button.
func _assemble() -> void:
	if _building.is_empty():
		return
	var mounted := []
	for stack in _building.slice(1):
		mounted.append(AssayActions.item_of_stack(stack as Dictionary))
	_act("Assemble", AssayActions.assemble(
			AssayActions.item_of_stack(_building[0] as Dictionary), mounted))
	_clear_build()


func _clear_build() -> void:
	_building.clear()
	_refresh_pack()
	_refresh_actions()


## THE TILE EVERY PLACEMENT LANDS ON: the one you chose, or the one you stand on until you choose.
func _target_tile() -> Vector2i:
	return _target if _targeted else _my_tile()


## A ROW OF VERB BUTTONS THAT WRAPS. An `HFlowContainer`, not an `HBoxContainer`, and that is not a
## style choice: a refined stack offers six buttons (Fuel, Smelt and one Make per part kind) and an
## HBox would run them off the right edge of a 320px panel. The column only scrolls vertically, so a
## button pushed sideways is a button that cannot be pressed -- which is the exact failure the scroll
## box was added to avoid.
func _verb_row(verbs: Array, make_button: Callable) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 2)
	row.custom_minimum_size = Vector2(PANEL, 0.0)
	for descriptor in verbs:
		row.add_child(make_button.call(descriptor as Dictionary))
	return row


func _button(label: String, on_press: Callable, hint := "") -> Button:
	var button := Button.new()
	button.text = label
	button.tooltip_text = hint
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(on_press)
	return button


## A line of small grey print: a heading with nothing under it reads as a bug, so every empty section
## says which kind of empty it is.
func _note(line: String) -> Label:
	var label := Label.new()
	label.text = line
	label.modulate = Color(0.55, 0.58, 0.64)
	label.add_theme_font_size_override("font_size", 13)
	label.custom_minimum_size = Vector2(PANEL, 0.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear(box: Node) -> void:
	for child in box.get_children():
		child.queue_free()
		box.remove_child(child)


## The tile my own player is on, as the sim has them. Spawn before there is a player of mine to find:
## it is the one tile every world has and it is where I am about to be.
func _my_tile() -> Vector2i:
	for entry in _sim.players():
		var player: Dictionary = entry
		if int(player.get("id", -1)) == _client.player_id:
			return player.get("pos", Vector2i.ZERO) as Vector2i
	return _sim.spawn_tile()


## TWO THINGS A MOUSE DOES ON THE MAP, and which is which matters.
##
## LEFT CLICK WALKS. The command is the same `PlayerCommand::MoveTo` `sim-cli` sends; the sim decides
## whether it is legal and the movement system walks us one tile per tick. NOTHING MOVES HERE -- the
## player on screen moves when a bundle carrying this command comes back around.
##
## RIGHT CLICK CHOOSES THE TILE THE BUTTONS ACT ON (ASSA-37). Place, Insert and Take all need a tile,
## and ONE mechanism serving all three is what keeps the rule explainable: a placement is never a
## second click on a button, and a click never means two things at once. Walking kept the left button
## because it is the thing a player does most.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_track_hover(event.position)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var at: Variant = _tile_under(event.position)
	if at == null:
		return
	var tile: Vector2i = at
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_target = tile
		_targeted = true
		_say("acting on %d, %d" % [tile.x, tile.y], AssayHud.Say.JOINED)
		_refresh()
		queue_redraw()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _client.submit(AssayActions.move_to(tile)):
		_say("walking to %d, %d" % [tile.x, tile.y], AssayHud.Say.JOINED)


## Which tile a screen position is on, or null for anywhere that is not a tile. ONE PLACE DOES THIS,
## because a hover readout that disagreed with where a click goes would be worse than no readout.
func _tile_under(at: Vector2) -> Variant:
	if not _sim.running() or _cell <= 0.0:
		return null
	var tile := ((at - MARGIN) / _cell).floor()
	var size := _sim.size_tiles()
	if tile.x < 0.0 or tile.y < 0.0 or tile.x >= float(size.x) or tile.y >= float(size.y):
		return null
	return Vector2i(int(tile.x), int(tile.y))


func _track_hover(at: Vector2) -> void:
	var tile: Variant = _tile_under(at)
	var now_on: bool = tile != null
	# Off the map, the readout goes back to your own tile rather than freezing on the last tile the
	# mouse crossed, which would be a stale answer that looks live.
	if not now_on:
		if _hovering:
			_hovering = false
			_refresh()
			queue_redraw()
		return
	var found: Vector2i = tile
	if _hovering and found == _hover:
		return
	_hover = found
	_hovering = true
	_refresh()
	queue_redraw()


## The world as the sim has it: bounds, every deposit, every player, and spawn.
##
## NO SPRITES HERE YET, AND THE REASON IS A PATH, NOT THE ART. This comment used to say the art was
## the problem -- that `assets/sprites` was drawn for the old named ores while the species in a world
## are generated. That stopped being true at ASSA-19/20: the ore sprite is species-neutral and meant to
## be tinted, the `_edge` variant is gone (ASSA-26), and the tint table is already in this client
## (`AssayHud.SPECIES_TINTS`). A tinted ore tile is `modulate` with that slot over `ore.png`.
##
## The actual blocker is ASSA-34, Cove's finding: `res://` is the project folder, which is `client/`,
## and the sheets live in its SIBLING `assets/sprites`, so the engine cannot see them, there is not one
## `.import` file for them, and neither export preset would pack them. The layout call is Marlow's.
## Shapes and colours from the sim's own numbers are the honest picture until that path is settled --
## but nobody should read this and go looking at the art.
func _draw() -> void:
	# A self-check run returns out of `_ready` before there is a client, and the engine still calls
	# `_draw` once. In the editor that is a caught script error; in an EXPORTED RELEASE BUILD it
	# segfaulted on exit (measured: exit 139 after the marker was already written). Nothing to draw
	# without a client is also just true.
	if _client == null or not _sim.running():
		return
	var size := _sim.size_tiles()
	if size.x <= 0 or size.y <= 0 or _cell <= 0.0:
		return
	draw_rect(Rect2(MARGIN, Vector2(size) * _cell), AssayHud.MAP_BG, true)

	var spawn := _sim.spawn_tile()
	draw_rect(Rect2(MARGIN + Vector2(spawn) * _cell - Vector2(_cell, _cell) * 2.0,
			Vector2(_cell, _cell) * 4.0), Color(0.35, 0.33, 0.20), true)

	# SPECIES IS A DESIGNED SLOT, PURITY IS BRIGHTNESS, and the rule plus the two versions of this I
	# got wrong are in `AssayHud.deposit_color`. Grade bands (C < 40, B 40-69, A >= 70) are the
	# sim's, not invented.
	#
	# AND COLOUR IS NOT THE ONLY READ: the species' letter goes on the patch, once per deposit
	# (Decision #36). The tints clear the colour-blindness floor by single digits, so for the ~8% of
	# men with a red-green deficiency the glyph is the read and the colour is the hint. `symbol`
	# comes from the sim -- a generated name's initial, distinct per world -- never from the first
	# character of a name a player may have renamed.
	var font := ThemeDB.fallback_font
	for entry in _sim.deposits():
		var deposit: Dictionary = entry
		if int(deposit.get("amount", 0)) <= 0:
			continue
		var at := MARGIN + Vector2(deposit.get("center", Vector2i.ZERO) as Vector2i) * _cell
		var radius := maxf(_cell, float(int(deposit.get("radius", 1))) * _cell)
		var colour := AssayHud.deposit_color(int(deposit.get("species", 0)),
				int(deposit.get("purity", 1)))
		draw_circle(at, radius, colour)
		var symbol := String(deposit.get("symbol", ""))
		var glyph := AssayHud.glyph_size(radius)
		if glyph > 0 and not symbol.is_empty() and font != null:
			# Centred by measurement, not by a guessed offset: the width is the font's and the
			# vertical nudge is the usual "half the cap height" for a baseline-drawn capital.
			var wide := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph).x
			draw_string(font, at + Vector2(-wide * 0.5, float(glyph) * 0.36), symbol,
					HORIZONTAL_ALIGNMENT_LEFT, -1, glyph, AssayHud.glyph_color(colour))

	for entry in _sim.players():
		var player: Dictionary = entry
		var at := MARGIN + Vector2(player.get("pos", Vector2i.ZERO) as Vector2i) * _cell
		var mine := int(player.get("id", -1)) == _client.player_id
		# Where the sim is walking them, drawn as a line to there. Not a tween: the sim owns the
		# position and this is its intention, not a frame of motion we invented.
		var target: Variant = player.get("target")
		if target != null:
			draw_line(at, MARGIN + Vector2(target as Vector2i) * _cell,
					Color(0.95, 0.85, 0.45, 0.35) if mine else Color(0.75, 0.78, 0.85, 0.25), 1.0)
		draw_rect(Rect2(at - Vector2(_cell, _cell), Vector2(_cell, _cell) * 2.0),
				Color(0.95, 0.85, 0.45) if mine else Color(0.75, 0.78, 0.85), true)

	# THE TILE THE BUTTONS ACT ON, if one has been chosen. Drawn before the hover outline and in its
	# own colour, because the two mean different things -- this one is where a placement lands and it
	# stays put, where the hover outline follows the mouse and vanishes with it. Thicker, so the two
	# are still telling apart on top of each other.
	if _targeted:
		draw_rect(Rect2(MARGIN + Vector2(_target) * _cell, Vector2(_cell, _cell)),
				Color(0.95, 0.85, 0.45, 0.85), false, 2.0)

	# The tile the readout is talking about, outlined. Drawn last so it is never buried, and only
	# while the mouse is actually over the map -- an outline left behind would point at an answer the
	# panel is no longer giving.
	if _hovering:
		draw_rect(Rect2(MARGIN + Vector2(_hover) * _cell, Vector2(_cell, _cell)),
				Color(0.95, 0.95, 0.95, 0.55), false, 1.0)
