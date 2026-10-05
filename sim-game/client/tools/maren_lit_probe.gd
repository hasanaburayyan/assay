extends SceneTree
## MAREN'S PROBE, not a shipped tool: does `BuildingFacts.lit` EVER come back true during the
## demo's play? Cove (ASSA-137) shot ticks 160/280/300 and got false at all three, inside a
## stretch whose event log records a smelt completing every 20 ticks. This asks what the client
## KNOWS, every tick, so headless is correct.
##
##   godot --headless --path client --script res://tools/maren_lit_probe.gd -- <seed> [ticks]

const TICKS_PER_FRAME := 40

var _screen: Node
var _play: Object
var _asked: Array = []
var _seed := "14247"
var _left := 600
var _started := false
var _done := false
var _lit_ticks: Array[int] = []
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
		print("FAIL  maren_lit_probe.gd ran past its %ds ceiling (started=%s): nothing finished it"
				% [int(RUN_CEILING), _started])
		quit(1)
		return true
	if not _started:
		var welcome := AssaySimHost.fresh_welcome_json(_seed, "marlow")
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
	var buildings: Array = _screen._sim.buildings()
	for b in buildings:
		if String(b.get("kind", "")) != "smelter":
			continue
		var lit := bool(b.get("lit", false))
		if lit:
			_lit_ticks.append(at)
		_rows.append("%d\t%s\t%s" % [at, "LIT " if lit else "cold", String(b.get("status", ""))])


func _report() -> void:
	_done = true
	# Every tick where the status CHANGED, plus the lit census. A 519-line dump is not a finding.
	var last := ""
	for row in _rows:
		var parts := row.split("\t")
		if parts[1] + parts[2] != last:
			print(row)
			last = parts[1] + parts[2]
	print("--- COVE'S THREE TICKS (ASSA-137) ---")
	for row in _rows:
		var t := int(row.split("\t")[0])
		if t in [160, 161, 280, 300]:
			print(row)
	print("---")
	print("smelter samples: %d, LIT on %d of them" % [_rows.size(), _lit_ticks.size()])
	if not _lit_ticks.is_empty():
		print("first LIT tick %d, last LIT tick %d" % [_lit_ticks[0], _lit_ticks[-1]])
	print("PROBE OK")
