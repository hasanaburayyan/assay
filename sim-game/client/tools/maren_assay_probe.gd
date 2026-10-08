extends SceneTree
## CI: local -- answered one design question for Maren on ASSA-95 and is kept for re-asking it
## MAREN'S PROBE, not a shipped tool: which ticks of the demo's play have an ASSAY in the running
## block? Marlow (ASSA-95) ticked box 1 on the mechanism and said so: mining and crafting are driven
## by a test, assaying reaches the block through the same array but no shot has ever caught it. A
## window shot needs a tick number, and a tick picked blind is the wrong handle (window_shot.gd says
## so in its own words about the pack). So ask what the client KNOWS, every tick, headless.
##
##   godot --headless --path client --script res://tools/maren_assay_probe.gd -- <seed> [ticks]
##
## Prints every tick where the set of running activities CHANGES, then the assay's first and last
## tick, then the midpoint, which is the tick to shoot.

const TICKS_PER_FRAME := 40

var _screen: Node
var _play: Object
var _asked: Array = []
var _seed := "14247"
var _left := 600
var _started := false
var _done := false
var _assay_ticks: Array[int] = []
var _rows: Array[String] = []


## **A WALL-CLOCK CEILING, AND IT IS A MEMBER INITIALIZER** (ASSA-182). A `SceneTree` whose
## `_initialize` dies still gets `_process` every frame -- Godot exits 0 on a parse error and does not
## exit AT ALL on a runtime error in `_initialize` -- so a probe waiting for state that `_initialize`
## never set waits for ever. Measured on this machine: one typo held a headless Godot for 45 minutes,
## and an orphan that holds a port or an account makes somebody else's run fail for a reason they will
## never find. **Set at the end of `_initialize` it would be absent in exactly the case it is for**,
## which is the mistake the first version of this made (#242).
##
## 300 s is above every honest run these tools have: their own budgets are a 10 s join timeout plus a
## few hundred frames. The five with a budget of their own raise the ceiling from it -- two from the
## duration argument, three from the `_run_deadline` they already compute -- so this floor can
## never shorten a run somebody asked for.
const RUN_CEILING := 300.0
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = String(argv[0]) if argv.size() > 0 else "14247"
	_left = int(argv[1]) if argv.size() > 1 else 600
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	_screen._ready()
	_screen._client.asked.connect(func(command: Variant) -> void: _asked.append(command))
	_play = AssayButtonPlay.new(_screen, 0)


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		print("FAIL  maren_assay_probe.gd ran past its %ds ceiling (started=%s): nothing finished it"
				% [int(RUN_CEILING), _started])
		quit(1)
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "maren")
		if welcome == "":
			print("PROBE DEAD: no world on seed %s" % _seed)
			_done = true
			return true
		_screen._client.play_offline()
		_screen._client.feed_offline(welcome)
		_started = true
	for _i in range(TICKS_PER_FRAME):
		if _left <= 0:
			_report()
			return true
		_left -= 1
		_play.advance()
		if _play.finished:
			_report()
			return true
		var inputs := []
		for command in _asked:
			inputs.append({"Player": {"player": _screen._client.player_id, "command": command}})
		_asked.clear()
		var at: int = _screen._sim.tick()
		_screen._client.feed_offline(JSON.stringify({"Tick": {"tick": at, "inputs": inputs}}))
		_sample(at)
	return false


func _sample(at: int) -> void:
	var me: int = _screen._client.player_id
	# `_screen._sim` is the AssaySimHost; `_screen._host` is a LineEdit. Same trap main.gd's own
	# readers hit: the member named `_host` is not the host.
	var lines: PackedStringArray = _screen._sim.activity_lines(me)
	var joined := " | ".join(lines)
	for line in lines:
		if line.to_lower().contains("assay"):
			_assay_ticks.append(at)
			break
	_rows.append("%d\t%s" % [at, joined])


func _report() -> void:
	_done = true
	var last := "\u0000"
	for row in _rows:
		var parts := row.split("\t", true, 1)
		var body: String = parts[1] if parts.size() > 1 else ""
		if body != last:
			print("%s\t%s" % [parts[0], "(nothing running)" if body == "" else body])
			last = body
	print("---")
	print("samples %d, assay running on %d of them" % [_rows.size(), _assay_ticks.size()])
	if not _assay_ticks.is_empty():
		print("assay first tick %d, last tick %d, MIDPOINT %d"
				% [_assay_ticks[0], _assay_ticks[-1],
				_assay_ticks[int(_assay_ticks.size() / 2.0)]])
	print("PROBE OK")
