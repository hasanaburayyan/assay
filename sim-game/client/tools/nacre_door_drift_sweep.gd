extends SceneTree
## CI: local -- a real window plus 48 seconds of wall clock. Headless reads back a blank frame, and
## the whole subject here is what the picture looks like while the camera moves.
## **THE WORST FRAME OF THE DRIFT, WHICH IS THE HALF OF MAREN'S FLOOR 1 A SINGLE SHOT CANNOT GIVE**
## (ASSA-292 box 2: *"measured at the WORST frame of the drift and not frame 0, with the sample gap
## stated so the worst frame is findable rather than hoped for"*).
##
##   godot --path . --script res://tools/nacre_door_drift_sweep.gd -- <out_dir>
##
## WHAT IT DOES. It stands up the real first screen, leaves it alone at the door, and photographs the
## window `AssayScene.TITLE_DRIFT_SAMPLES` times across one whole `TITLE_DRIFT_PERIOD`. The PNGs are
## then read by `tools/nacre_door_contrast.py`, which is the instrument that already measures the
## surface the words stand on and already has a control (Maren's independently measured 14.0:1 and
## 7.79:1 on the flat field). **This tool measures nothing itself** -- a second implementation of the
## contrast arithmetic beside the first is how two numbers start disagreeing.
##
## **IT DOES NOT TOUCH THE CLOCK, AND THAT IS THE POINT.** `_door_view` takes its phase from
## `Time.get_ticks_msec()`. The cheap way to sweep a loop is a seam -- a settable `seconds` on the
## screen -- and a seam measures the arithmetic I already have three tests for, not the screen. So
## this waits out a real 48-second loop in a real window at the real frame rate, and what comes back
## is 64 pictures the game actually drew.
##
## **IT RECORDS THE PHASE IT GOT, NOT THE PHASE IT ASKED FOR.** The sampler fires on the frame after
## each due time, so a hitch can make two neighbours further apart than the published
## `title_drift_gap_px()`. The report prints the WORST OBSERVED gap and fails if it exceeds the
## published bound, because then the honest claim is "within <observed> px of the worst frame" and the
## bound would be a sentence this run did not earn.
##
## **AND THE FIRST RUN FAILED EXACTLY THERE, WHICH IS WHY `OVERSAMPLE` EXISTS.** 64 samples timed off
## a real 60 fps window came back with a worst step of **5.74 px against the published 5.50** --
## because `title_drift_gap_px()` is the chord at *exactly* `PERIOD / SAMPLES` seconds and a frame of
## lateness on the fast part of the ellipse is 0.2 px more than that. The tempting fix was to widen
## the tolerance by a frame; that would make the published bound mean "the bound, plus whatever this
## Mac did". Sampling twice as finely instead earns the published sentence with margin, and the sweep
## still costs one loop of wall clock because the cost is the 48 seconds, not the frames.
##
## THE CONTROLS, and every one of them exists because of a way this could pass while proving nothing:
##  - **A FROZEN CAMERA.** 64 photographs of one still screen is exactly the defect that hid inside
##    this item for a night, and it reads as a complete sweep. So the drift span is measured off the
##    recorded samples and must cover the ellipse: `2 * TITLE_DRIFT_TILES * TILE_PX` across, half that
##    down, computed from the constants rather than typed.
##  - **A REPEATED FRAME.** Every PNG's SHA-256 must be distinct. The camera is the only thing moving
##    on this screen, so two identical frames mean it did not move between them even if the numbers
##    say it did. `window_shot.gd` learned this the same way.
##  - **NO PLATE.** The surface being measured is the plate; if `_door_plate` is hidden there is no
##    surface and the run is about a screen nobody is shipping. Its rect goes in the report.
##  - **A SESSION.** If the screen came up with a world running this is not the door.

const PNG_PREFIX := "frame"
## HOW MANY TIMES THE PUBLISHED SAMPLE COUNT THIS TOOL ACTUALLY TAKES. See the docstring: a real
## window cannot hit `PERIOD / SAMPLES` seconds exactly, and the published bound has no room in it for
## a late frame. 2 is the smallest whole factor that leaves room, and it leaves a lot: the step
## becomes ~2.75 px against a 5.50 px bound, so a run would have to be 2x late to breach it.
const OVERSAMPLE := 2
## A whole loop plus a settle, times two. Generous: a loaded Mac halves the frame rate and the
## sampler is on the clock, not on frames, so the run length is the loop and not the frame count.
const RUN_CEILING := 240.0
## Frames to let the window lay out before the first sample. The plate is sized from laid-out
## children, so a sample before the first layout pass would photograph a screen with no plate.
const SETTLE_FRAMES := 12

var _out := ""
var _screen: Node = null
var _settled := 0
var _taken := 0
var _t0 := 0.0
## One row per sample: index, the phase seconds the view was built from, the drift offset in tiles,
## the pixel step from the previous sample, and the frame's fingerprint.
var _rows: Array = []
var _hashes := {}
var _done := false
var _ceiling := Time.get_unix_time_from_system() + RUN_CEILING


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		_finish(false, "usage: -- <out_dir>")
		return
	_out = String(argv[0])
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_finish(false, "cannot write to %s" % _out)
		return
	_screen = load("res://scenes/main.tscn").instantiate()
	root.add_child(_screen)
	# `_ready` BY HAND: a `--script` run is inside `SceneTree._initialize`, before the root window is
	# in the tree, so the engine's own call comes too late. Same note as `window_shot.gd`.
	_screen._ready()
	if _screen._sim.running():
		_finish(false, "the screen came up with a session: this tool is about the door")
		return
	print("window %s, viewport %s, rules %s" % [DisplayServer.window_get_size(), root.size,
			AssayProtocol.rules_id()])
	print("sweeping %d samples (%dx the published %d) across %.1fs; published gap %.2f px"
			% [_want(), OVERSAMPLE, AssayScene.TITLE_DRIFT_SAMPLES,
			AssayScene.TITLE_DRIFT_PERIOD, AssayScene.title_drift_gap_px()])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_unix_time_from_system() > _ceiling:
		_finish(false, "ran past its %ds ceiling with %d of %d samples taken"
				% [int(RUN_CEILING), _taken, _want()])
		return true
	if _settled < SETTLE_FRAMES:
		_settled += 1
		if _settled == SETTLE_FRAMES:
			_t0 = float(Time.get_ticks_msec()) / 1000.0
		return false
	# ON THE CLOCK, NOT ON FRAMES. The drift is a function of seconds, so an evenly spaced set of
	# samples of the LOOP is an evenly spaced set of times. Sampling every Nth frame would bunch up
	# wherever the frame rate dipped and leave a hole in the ellipse without saying so.
	var step := AssayScene.TITLE_DRIFT_PERIOD / float(_want())
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now < _t0 + float(_taken) * step:
		return false
	if not _sample():
		return true
	if _taken >= _want():
		_report()
		return true
	return false


## ONE PHOTOGRAPH, AND THE PHASE THE SCREEN ITSELF USED TO DRAW IT.
##
## The phase is read out of `_world.view["seconds"]` rather than off this tool's own clock, because
## the view is what the frame was painted from. The texture read here is the frame rendered at the end
## of the previous engine frame -- the same ordering `window_shot.gd` has always shot on -- and the
## view carried in `_world` is that frame's too, so the pair belong together. The difference either
## way is one frame of drift, about 0.1 px against a 5.50 px step.
func _sample() -> bool:
	var view: Dictionary = _screen._world.view
	if view.is_empty():
		_finish(false, "sample %d: the door drew no world, so there is no drifting camera to sample"
				% _taken)
		return false
	var seconds := float(view.get("seconds", -1.0))
	if seconds < 0.0:
		_finish(false, "sample %d: the view carries no `seconds`, so its phase cannot be named"
				% _taken)
		return false
	var image := root.get_texture().get_image()
	if image == null:
		_finish(false, "sample %d: no frame to read" % _taken)
		return false
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(image.get_data())
	var fingerprint := hasher.finish().hex_encode()
	var name := "%s-%03d.png" % [PNG_PREFIX, _taken]
	if _hashes.has(fingerprint):
		_finish(false, ("%s is pixel-identical to %s, so the camera did not move between them: 64 "
				+ "photographs of one still screen read as a swept loop and are not one")
				% [name, _hashes[fingerprint]])
		return false
	_hashes[fingerprint] = name
	if image.save_png("%s/%s" % [_out, name]) != OK:
		_finish(false, "cannot write %s/%s" % [_out, name])
		return false
	var drift := AssayScene.title_drift(seconds)
	var gap := 0.0
	if not _rows.is_empty():
		var last: Vector2 = _rows[-1]["drift"]
		gap = (drift - last).length() * AssayScene.TILE_PX
	_rows.append({
		"name": name,
		"seconds": seconds,
		"drift": drift,
		"gap": gap,
		"hash": fingerprint.substr(0, 12),
	})
	_taken += 1
	return true


func _report() -> void:
	var lines := PackedStringArray()
	lines.append("THE DOOR'S DRIFT, SWEPT IN A REAL WINDOW (ASSA-292 box 2)")
	lines.append("rules %s · window %s · %d samples (%dx the published %d) across %.1fs"
			% [AssayProtocol.rules_id(), DisplayServer.window_get_size(), _want(), OVERSAMPLE,
			AssayScene.TITLE_DRIFT_SAMPLES, AssayScene.TITLE_DRIFT_PERIOD])
	var plate: ColorRect = _screen._door_plate
	if not plate.visible:
		_finish(false, "the door plate is hidden, so there is no surface under the words to measure")
		return
	lines.append("plate %s at %s, %s" % [plate.size, plate.position, plate.color])
	var worst_gap := 0.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for row in _rows:
		var drift: Vector2 = row["drift"]
		lo = Vector2(min(lo.x, drift.x), min(lo.y, drift.y))
		hi = Vector2(max(hi.x, drift.x), max(hi.y, drift.y))
		worst_gap = max(worst_gap, float(row["gap"]))
		lines.append("  %s  t=%8.3fs  drift (%+6.3f,%+6.3f) tiles  step %5.2f px  %s"
				% [row["name"], row["seconds"], drift.x, drift.y, row["gap"], row["hash"]])
	# THE SPAN CONTROL, COMPUTED FROM THE CONSTANTS. A frozen camera is the failure this whole item
	# was built on top of for a night, and it leaves 64 files behind that look like a sweep.
	var span := (hi - lo) * AssayScene.TILE_PX
	var want := Vector2(2.0, 1.0) * AssayScene.TITLE_DRIFT_TILES * AssayScene.TILE_PX
	lines.append("drift span %.1f x %.1f px, the ellipse is %.1f x %.1f px"
			% [span.x, span.y, want.x, want.y])
	lines.append("worst observed step %.2f px, published bound %.2f px"
			% [worst_gap, AssayScene.title_drift_gap_px()])
	lines.append("%d distinct frames of %d" % [_hashes.size(), _rows.size()])
	var text := "\n".join(lines) + "\n"
	print(text)
	var handle := FileAccess.open("%s/sweep.txt" % _out, FileAccess.WRITE)
	if handle == null:
		_finish(false, "cannot write %s/sweep.txt" % _out)
		return
	handle.store_string(text)
	handle.close()
	# TWO PX OF TOLERANCE AND NOT A PERCENTAGE: 64 samples of a cosine never land on its extremes, so
	# the widest sample is `cos(PI/64)` of the half-axis -- 0.3 px short of 112. Anything beyond that
	# is the `camera_origin` clamp eating the drift, which is a finding and not a tolerance.
	if span.x < want.x - 2.0 or span.y < want.y - 2.0:
		_finish(false, ("the samples cover %.1f x %.1f px of a %.1f x %.1f px ellipse: the camera did "
				+ "not go where the arithmetic says it does, so this is not a swept loop")
				% [span.x, span.y, want.x, want.y])
		return
	if worst_gap > AssayScene.title_drift_gap_px():
		_finish(false, ("two neighbouring samples are %.2f px apart against a published bound of "
				+ "%.2f: this run sampled the loop more coarsely than the bound claims, so a "
				+ "worst-frame number off it is only good to %.2f px")
				% [worst_gap, AssayScene.title_drift_gap_px(), worst_gap])
		return
	_finish(true, "%d frames in %s, every one distinct" % [_rows.size(), _out])


## HOW MANY SAMPLES THIS RUN TAKES, derived from the published count so the two can never drift
## apart. Nothing here may type a sample count: `TITLE_DRIFT_SAMPLES` is the number the claim is made
## with and `title_drift_gap_px()` is derived from it, so a literal on this side would be a second
## opinion about the same promise.
func _want() -> int:
	return AssayScene.TITLE_DRIFT_SAMPLES * OVERSAMPLE


func _finish(ok: bool, why: String) -> void:
	_done = true
	print("%s  %s" % ["OK  " if ok else "FAIL", why])
	quit(0 if ok else 1)
