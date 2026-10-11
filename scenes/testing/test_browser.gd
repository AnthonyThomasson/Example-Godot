extends Node

## Testing domain: the test browser scene — reached from the setup window's Tests button. Hosts the UI
## domain's browser window over the discovered tests; Play stores the pick and opens the runner, Back
## returns to the main scene. The search text and last results live in Engine metas, so they survive
## the round trip through a test. Run all, or a domain's ▶, spawns a separate headless run (its own `--out`
## dir and engine log, so it never shares files with this game or another run; a domain run passes
## `--domain=<name>`) and folds its report into the marks.

const TestCatalog = preload("res://scenes/testing/test_catalog.gd")
const BROWSER_WINDOW := preload("res://scenes/ui/test_browser_window.gd")
const RUNNER_SCENE := "res://scenes/testing/test_runner.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const META_FILTER := "test_filter"

var _window: CanvasLayer
## The headless run's process id (-1 when none), its output dir and start time (msec).
var _pid := -1
var _out_dir := ""
var _started_msec := 0
## What the run covers, for the status text: "all" or a domain name.
var _run_label := ""


func _ready() -> void:
	set_process(false)
	var window: CanvasLayer = BROWSER_WINDOW.new()
	_window = window
	window.name = "TestBrowserWindow"
	add_child(window)
	window.play_requested.connect(_on_play)
	window.back_requested.connect(_on_back)
	window.run_requested.connect(_on_run)
	window.filter_changed.connect(func(t: String): Engine.set_meta(META_FILTER, t))
	window.open(TestCatalog.discover(), TestCatalog.discover_sandboxes(), Engine.get_meta(TestCatalog.META_RESULTS, {}), TestCatalog.matches,
		String(Engine.get_meta(META_FILTER, "")), String(Engine.get_meta(TestCatalog.META_SELECTION, "")))


## Play: remember the pick and open the runner.
func _on_play(path: String) -> void:
	Engine.set_meta(TestCatalog.META_SELECTION, path)
	get_tree().change_scene_to_file(RUNNER_SCENE)


## Back: return to the main scene (its setup window).
func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


## Run: start a headless run of every test, or only `domain`'s when it is not "" (Von tests included), in a
## fresh output dir and watch it from `_process`.
func _on_run(domain: String) -> void:
	if _pid != -1:
		return
	_out_dir = ProjectSettings.globalize_path("user://test_runs/%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var args := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60",
		"--log-file", _out_dir.path_join("godot.log"),
		"res://scenes/testing/test_runner.tscn", "--", "--run-tests", "--include-von", "--out=" + _out_dir])
	if domain != "":
		args.append("--domain=" + domain)
	_pid = OS.create_process(OS.get_executable_path(), args)
	if _pid == -1:
		_window.set_run_status("Could not start the test run")
		return
	_run_label = domain if domain != "" else "all"
	_started_msec = Time.get_ticks_msec()
	_window.set_run_status("Running %s tests…" % _run_label, true)
	set_process(true)


## While a run is going: show elapsed time, and fold in its report when the process ends.
func _process(_delta: float) -> void:
	if OS.is_process_running(_pid):
		_window.set_run_status("Running %s tests… %d s" % [_run_label, (Time.get_ticks_msec() - _started_msec) / 1000], true)
		return
	set_process(false)
	_pid = -1
	_finish_run()


## Read the finished run's report into the marks and say how it went.
func _finish_run() -> void:
	var report := FileAccess.get_file_as_string(_out_dir.path_join("report.json"))
	var parsed: Variant = JSON.parse_string(report) if report != "" else null
	if not parsed is Dictionary:
		_window.set_run_status("Test run produced no report (see %s)" % _out_dir.path_join("godot.log"))
		return
	var results: Dictionary = Engine.get_meta(TestCatalog.META_RESULTS, {})
	var counts := {}
	for r in parsed["results"]:
		results[r["id"]] = r["status"]
		counts[r["status"]] = counts.get(r["status"], 0) + 1
	Engine.set_meta(TestCatalog.META_RESULTS, results)
	var bad: int = counts.get("FAIL", 0) + counts.get("TIMEOUT", 0)
	var summary := "%s: %d passed, %d failed, %d timed out, %d skipped" % [_run_label, counts.get("PASS", 0),
		counts.get("FAIL", 0), counts.get("TIMEOUT", 0), counts.get("SKIPPED", 0)]
	if not (parsed.get("stray_logs", []) as Array).is_empty():
		summary += ", %d stray log line(s)" % (parsed["stray_logs"] as Array).size()
	_window.set_results(results)
	_window.set_run_status(summary + ("  (details: %s)" % _out_dir if bad > 0 else ""))


## Don't leave a headless run behind when the browser closes.
func _exit_tree() -> void:
	if _pid != -1 and OS.is_process_running(_pid):
		OS.kill(_pid)
