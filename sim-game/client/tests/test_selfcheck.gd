extends RefCounted
## THE CHECK THAT GUARDS THE SHIPPED BUILD, checked here itself.
##
## `AssaySelfCheck` is what CI runs against the exported Mac and Windows builds, so if it could
## pass while writing nothing, or write the pass marker anywhere but the last line, the export jobs
## would be green on a broken client. Those two properties are what this file holds.
##
## It cannot prove the check catches a broken PACK -- that needs a real export, and the proof is a
## deliberate break of `protocol.gd` run through the exporter (recorded on ASSA-9).

var runner = null


func set_runner(r) -> void:
	runner = r


func _fail(reason: String) -> bool:
	if runner != null:
		runner.fail(reason)
	return false


## On a tree that works, nothing is wrong. (If this ever fails, the suite above it will too -- that
## is the point: the self-check must not have an opinion the suite does not share.)
func test_the_source_tree_passes_its_own_selfcheck() -> bool:
	var failures := AssaySelfCheck.check()
	if not failures.is_empty():
		return _fail("the source tree fails the shipped self-check: %s" % [failures])
	return true


## THE MARKER IS THE LAST LINE AND THE EXIT CODE IS 0. CI greps that line, so its position is the
## contract, not a detail of formatting.
func test_a_pass_writes_the_marker_last() -> bool:
	var path := "user://selfcheck-pass.txt"
	var code := AssaySelfCheck.run(path)
	if code != 0:
		return _fail("a passing self-check exited %d" % code)
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return _fail("a passing self-check wrote nothing to %s" % path)
	var lines := text.strip_edges().split("\n")
	if lines[lines.size() - 1] != AssaySelfCheck.MARKER:
		return _fail("the last line was %s, not the marker" % lines[lines.size() - 1])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


## An unwritable path must not report success. Silence is the failure mode that would matter: CI
## reads a file, and a self-check that cannot write one has proved nothing.
func test_a_path_it_cannot_write_fails() -> bool:
	var code := AssaySelfCheck.run("user://no-such-dir/deeper/selfcheck.txt")
	if code == 0:
		return _fail("a self-check that could not write its marker still exited 0")
	return true


## No flag, no path: a player double-clicking the app must never trip the CI branch in `main.gd`.
func test_a_normal_run_asks_for_no_selfcheck() -> bool:
	if AssaySelfCheck.requested_path() != "":
		return _fail("a run with no %s flag asked for a self-check" % AssaySelfCheck.FLAG)
	return true
