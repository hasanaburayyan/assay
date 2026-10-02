extends SceneTree
## WHAT DOES THE BOARD'S BENCH ACTUALLY HOLD? Join, read `designs_of`, print it, get out. (ASSA-83)
##
##   godot --headless --path client --script "$PWD/art/bench_read.gd" -- localhost:7803 hasanaburayyan
##
## Half of the instrument for Decision #38. `design_row_layout.gd` lays these designs out in the real
## screen and `design_row_sheet.py` draws that at 1:1; this is the part that has to touch the live
## world, so it is deliberately the smallest thing that can.
##
## THIS PROBE CHANGES NOTHING AND HOLDS THE ACCOUNT FOR SECONDS. Both are requirements, not manners:
##
##  - The board's demo world is INERT ON PURPOSE. `shared/assay-board-demo-world-2026-10-02.md`
##    records why: the first version of that bench was built with a probe that played the loop, and
##    5,600 ticks later the pick had worn to nothing and the bench was empty, because the relay owns
##    the clock and `Mine` repeats until something stops it. So this submits NO commands at all --
##    not even the `MoveTo` that `hud_probe.gd` uses to put a line in the event log. There is nothing
##    here that could wear a tool, consume ore or plant a design.
##  - THE RELAY REFUSES AN ACCOUNT THAT IS ALREADY CONNECTED. The bench's designs belong to
##    `hasanaburayyan`, so reading them means briefly being that account -- and while this is
##    connected, the board cannot join. It quits the moment it has what it came for.
##
## AND IT IS PORT 7803, NEVER 7777. 7777 is the founders' year-old ongoing test world and speaks an
## older protocol; it is not this bench and nothing here belongs in it.
##
## Prints `BENCH READ OK` LAST and only on success, because Godot exits 0 even on a compile error.

## Enough bundles to know the link is real and the snapshot applied. Designs come from the WELCOME
## snapshot, so this is not waiting for them to arrive -- it is refusing to report a world we have
## not actually stepped.
const WANT_BUNDLES := 2
const JOIN_TIMEOUT := 10.0
const RUN_TIMEOUT := 20.0

var _client: AssayNetClient
var _sim := AssaySimHost.new()
var _done := false
var _join_deadline := 0.0
var _run_deadline := 0.0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() < 2:
		print("FAIL  usage: -- host[:port] account")
		quit(1)
		return
	_client = AssayNetClient.new()
	_client.welcomed.connect(_on_welcomed)
	_client.tick_bundle.connect(_on_tick_bundle)
	_client.refused.connect(func(reason): _finish(false, "refused: %s" % reason))
	_client.link_failed.connect(func(reason): _finish(false, reason))
	_client.desynced.connect(func(tick): _finish(false, "desynced at tick %d" % tick))
	root.add_child(_client)
	var now := Time.get_unix_time_from_system()
	_join_deadline = now + JOIN_TIMEOUT
	_run_deadline = now + RUN_TIMEOUT
	_client.join(String(argv[0]), String(argv[1]))


func _process(_delta: float) -> bool:
	if _done:
		return true
	var now := Time.get_unix_time_from_system()
	if _client.stage != AssayNetClient.Stage.JOINED:
		if now >= _join_deadline:
			_finish(false, "no welcome within %ds (stage %d)" % [JOIN_TIMEOUT, _client.stage])
			return true
		return false
	if _sim.applied >= WANT_BUNDLES:
		_report()
		return true
	if now >= _run_deadline:
		_finish(false, "only %d of %d bundles applied before the deadline"
				% [_sim.applied, WANT_BUNDLES])
		return true
	return false


func _on_welcomed(_player: int, _world: Dictionary, raw: String) -> void:
	if not _sim.start(raw):
		_finish(false, _sim.fail_reason)


func _on_tick_bundle(_tick: int, _inputs: Array, raw: String) -> void:
	var before := _sim.applied
	var report := _sim.apply(raw)
	if _sim.applied == before:
		_finish(false, "a bundle for tick %d was refused at sim tick %d" % [_tick, _sim.tick()])
		return
	# The hash report is the relay's desync check and is not a world change. Sending it is how a peer
	# behaves; withholding it would make this probe a worse citizen, not a safer one.
	if report != "":
		_client.send_text(report)


## THE BENCH, IN THE SIM'S OWN WORDS. `designs_of` is the binding's readout and nothing here forms an
## opinion about it -- no verdict is computed, no mass compared to a budget. The layout half gets
## these dictionaries unaltered, so what ends up drawn is what the world says.
func _report() -> void:
	var designs := _sim.designs_of(_client.player_id)
	print("  tick %d, hash %s, %d designs on the bench"
			% [_sim.tick(), _sim.hash_hex(), designs.size()])
	for entry in designs:
		var design: Dictionary = entry
		print("  bench: [%s] %s · mass %s-%s of budget %s-%s"
				% [String(design.get("verdict", "?")),
					"in hand" if bool(design.get("in_hand", false)) else String(
							design.get("mount", "?")),
					design.get("mass_low", "?"), design.get("mass_high", "?"),
					design.get("budget_low", "?"), design.get("budget_high", "?")])
	print("DESIGNS_JSON ", JSON.stringify({
		"designs": designs,
		"tick": _sim.tick(),
		"hash": _sim.hash_hex(),
		"seed": _sim.seed_hex() if _sim.has_method("seed_hex") else "",
	}))
	print("BENCH READ OK")
	_done = true
	quit(0)


func _finish(ok: bool, why: String) -> void:
	if _done:
		return
	_done = true
	if ok:
		print("BENCH READ OK")
		quit(0)
		return
	print("FAIL  %s" % why)
	quit(1)
