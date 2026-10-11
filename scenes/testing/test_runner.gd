extends Node2D

## Testing domain: runs game tests — a second composition root beside main.gd. Two modes:
##   interactive — plays the test the browser picked (`Engine` meta `test_selection`, or the first
##                 match of `-- --play <filter>`), shows the result banner and keeps the world
##                 running; Rerun rebuilds it, Back/Escape returns to the browser;
##   batch       — `godot --headless --fixed-fps 60 res://scenes/testing/test_runner.tscn --
##                 --run-tests [filter] [--include-von]` runs every matching test in turn, prints one
##                 line each plus a summary, writes `user://test_report.json` and exits 1 on any
##                 failure (or any error/warning logged outside a test). `--out=<dir>` puts the report
##                 and failure bundles in <dir> instead; started with `--log-file <dir>/godot.log` it
##                 also owns its engine log, so parallel runs and a running game never share files.
## Each test gets a fresh TestWorld child, freed between tests. The Von launcher is created only when
## a test needs it and then kept for the session, so a server it started isn't killed between tests.
## Every engine error/warning logged while a test is open fails it (log_watch.gd).

const TestCatalog = preload("res://scenes/testing/test_catalog.gd")
const TestWorldScript = preload("res://scenes/testing/test_world.gd")
const LogWatch = preload("res://scenes/testing/log_watch.gd")
const LAUNCHER = preload("res://scenes/ai/decision/decision_server_launcher.gd")
const RESULT_HUD = preload("res://scenes/ui/test_result_hud.gd")
const OVERLAY_TOGGLES = preload("res://scenes/ui/overlay_toggles.gd")
const BROWSER_SCENE := "res://scenes/testing/test_browser.tscn"
const REPORT_PATH := "user://test_report.json"
## Failed/timed-out tests write their event log, final state and traces here (one JSON per test id).
const BUNDLE_DIR := "user://test_failures"
## Engine metas shared with the browser: the test to play, and the last status per test id.
const META_SELECTION := "test_selection"
const META_RESULTS := "test_results"
## Frame rate a Von-dependent test is paced to in real time (matches the batch run's --fixed-fps 60).
const REALTIME_FPS := 60

@onready var _camera: Camera2D = $MainCamera

var _watch := LogWatch.new()
var _batch := false
## Where the report and failure bundles go; `--out=<dir>` moves them off the shared `user://` paths so
## concurrent runs (and a running game) never overwrite each other.
var _report_path := REPORT_PATH
var _bundle_dir := BUNDLE_DIR
## Batch: run requires_von tests (else they are skipped).
var _include_von := false
## `--require-von`: a Von test fails instead of skipping when no server is live.
var _require_von := false
## `--shots`: save screenshots of failed tests into the bundle dir (needs a rendering run, not headless).
var _shots := false
## The Von launcher, created by the first requires_von test, and its settled answer.
var _launcher: Node = null
var _von_live := false
## The open test: its descriptor, context and world (null between tests).
var _entry: Dictionary = {}
var _ctx: TestContext = null
var _world: Node2D = null
## Whether the open test's verdict has been taken (a later logged error then re-renders it).
var _concluded := false
## While true, each frame sleeps out the rest of 1/REALTIME_FPS of wall time (Engine.max_fps is not
## honoured under --fixed-fps headless).
var _realtime := false
var _last_frame_usec := 0
## Errors/warnings logged while no test was open.
var _stray_logs: Array = []
## Interactive only: the result banner and the overlay toggle bar.
var _hud: CanvasLayer = null
var _toggles: CanvasLayer = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# A run given `--out=<dir>` was also started with `--log-file <dir>/godot.log` (the engine consumes that
	# flag, so it is not visible here and does not update the project setting): follow the moved log.
	var out := _option(args, "--out", "")
	if out != "":
		_watch.path_override = out.path_join("godot.log")
	_watch.begin()
	if args.has("--play"):
		_select_from_cli(args)
	if args.has("--run-tests"):
		_batch = true
		_run_batch.call_deferred(args)
	elif Engine.has_meta(META_SELECTION):
		_hud = RESULT_HUD.new()
		_hud.name = "TestResultHUD"
		add_child(_hud)
		_hud.rerun_requested.connect(_on_rerun)
		_hud.back_requested.connect(_back_to_browser)
		_run_interactive.call_deferred(String(Engine.get_meta(META_SELECTION)))
	else:
		get_tree().change_scene_to_file.call_deferred(BROWSER_SCENE)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _realtime and _last_frame_usec > 0:
		var wait := 1000000 / REALTIME_FPS - (now - _last_frame_usec)
		if wait > 0:
			OS.delay_usec(wait)
			now = Time.get_ticks_usec()
	_last_frame_usec = now


func _physics_process(delta: float) -> void:
	for entry in _watch.poll():
		_route_log(entry)
	if _ctx != null and not _ctx.is_finished:
		_ctx.time += delta
		if not _entry.get("manual", false) and _ctx.time >= float(_entry.get("timeout", TestCatalog.DEFAULT_TIMEOUT)):
			_ctx.reason = "timed out after %.1fs" % float(_entry["timeout"])
			_ctx.finish("TIMEOUT")


func _exit_tree() -> void:
	if _ctx != null:
		_ctx.free()
		_ctx = null


func _unhandled_input(event: InputEvent) -> void:
	if not _batch and event.is_action_pressed(Keybinds.MENU) and not event.is_echo():
		_back_to_browser()


# --- Running one test -----------------------------------------------------------------------

## Build and run the test `entry`, leaving its world open. Returns once it has ended.
func _start(entry: Dictionary) -> void:
	_entry = entry
	_concluded = false
	var skip_reason := ""
	if entry["requires_von"]:
		if _batch and not _include_von and not _require_von:
			skip_reason = "needs the Von decision server (pass --include-von)"
		else:
			# Von answers in real time: a batch run's `--fixed-fps` sim outpaces it (game-time timers like
			# the HTTP timeout expire early), so pace this test in real time.
			_realtime = true
			if not await _await_von():
				skip_reason = "the Von decision server is not live"
				if _require_von:
					_ctx = TestContext.new(get_tree(), entry)
					_ctx.check(false, "The Von decision server is not live (--require-von)")
					_ctx.finish("FAIL")
					return
	_ctx = TestContext.new(get_tree(), entry)
	if _shots:
		_ctx.shot_prefix = "%s/%s" % [_bundle_dir, String(entry["id"]).replace("/", "__")]
	if entry["error"] != "":
		_ctx.check(false, "Test script " + String(entry["error"]))
		_ctx.finish("FAIL")
		return
	if skip_reason != "":
		_ctx.skip(skip_reason)
		return
	var test: GameTest = load(entry["path"]).new()
	var setup := TestSetup.new()
	test.configure(setup)
	_world = TestWorldScript.new()
	_world.name = "TestWorld"
	add_child(_world)
	_world.child_entered_tree.connect(func(n: Node): _on_event(&"spawned", { "node": n, "name": String(n.name) }))
	_world.child_exiting_tree.connect(func(n: Node): _on_event(&"removed", { "node": n, "name": String(n.name) }))
	EventBus.posted.connect(_on_event)
	_world.build(setup)
	_ctx.bind(_world, _world.actors, _world.objects, _world.rooms)
	for id in _world.actors:
		_observe_actor(id, _world.actors[id])
	_frame_camera(setup)
	if not _batch:
		_build_toggles()
	_drive(test, _ctx)
	if not _ctx.is_finished:
		await _ctx.finished


## Run the test coroutine; returning normally ends the test (verdict decided in `conclude`).
func _drive(test: GameTest, ctx: TestContext) -> void:
	await test.run(ctx)
	ctx.finish("")


## Free the open world (restoring statics), let any logs from the teardown land on the test, then
## close it. Returns its verdict record ({} when nothing was open).
func _close() -> Dictionary:
	var snapshot := _ctx.snapshot() if _ctx != null and is_instance_valid(_world) else {}
	if _shots and _ctx != null and is_instance_valid(_world):
		var verdict := _ctx.conclude(_entry.get("manual", false))
		if verdict == "FAIL" or verdict == "TIMEOUT":
			_ctx.screenshot("fail")
	if EventBus.posted.is_connected(_on_event):
		EventBus.posted.disconnect(_on_event)
	if is_instance_valid(_toggles):
		_toggles.queue_free()
	_toggles = null
	if is_instance_valid(_world):
		_world.restore()
		_world.queue_free()
		_world = null
		await get_tree().physics_frame
		await get_tree().physics_frame
	for entry in _watch.poll(true):
		_route_log(entry)
	_realtime = false
	var result := _result(snapshot) if _ctx != null else {}
	if _ctx != null:
		_ctx.free()  # discards any test coroutine still parked on it
	_ctx = null
	return result


## The verdict + record for the open test.
## A failed or timed-out result also carries `events`, `snapshot` (final actor/object state, taken
## before teardown when `snapshot` is passed) and `traces`, so the cause can be read without a rerun.
func _result(snapshot := {}) -> Dictionary:
	_ctx.conclude(_entry.get("manual", false))
	_concluded = true
	var result := {
		"id": _entry["id"], "name": _entry["name"], "domain": _entry["domain"],
		"status": _ctx.status, "reason": _ctx.reason, "time": snappedf(_ctx.time, 0.01),
		"checks": _ctx.checks.duplicate(), "logs": _ctx.logs.duplicate(),
		"manual": _entry.get("manual", false),
	}
	if _ctx.status == "FAIL" or _ctx.status == "TIMEOUT":
		result["events"] = _ctx.plain_events()
		result["snapshot"] = snapshot if not snapshot.is_empty() else _ctx.snapshot()
		result["traces"] = _ctx.traces.duplicate(true)
		result["shots"] = _ctx.shots.duplicate()
	return result


## Send a logged line to the open test, or keep it as a stray (batch-level) line.
func _route_log(entry: Dictionary) -> void:
	if _ctx != null:
		var before := _ctx.checks.size()
		_ctx.on_log(entry)
		if _concluded and _ctx.checks.size() != before and _hud != null:
			_hud.show_result(_result())  # a late error flips a shown verdict
	elif not LogWatch.matches_any(entry, []):
		_stray_logs.append(entry)


## Log an observed event on the open test (dropped between tests).
func _on_event(topic: StringName, data: Dictionary) -> void:
	if _ctx != null:
		_ctx.record(topic, data)


## Log an actor's `died` / `hit_landed` signals under its test id.
func _observe_actor(id: StringName, actor: Node) -> void:
	if actor == null:
		return
	if actor.has_signal("died"):
		actor.died.connect(func(): _on_event(&"died", { "actor": id, "node": actor }))
	if actor.has_signal("hit_landed"):
		actor.hit_landed.connect(func(body: Node, damage: float, hand: int):
			_on_event(&"hit_landed", { "actor": id, "body": body, "damage": damage, "hand": hand }))


## Frame the setup's camera targets (default: every actor; an empty world frames its first room).
func _frame_camera(setup: TestSetup) -> void:
	var targets: Array = []
	for id in (setup.camera_targets if not setup.camera_targets.is_empty() else _world.actors.keys()):
		var a: Node = _world.actors.get(id)
		if a is Node2D:
			targets.append(a)
	if targets.is_empty() and not _world.rooms.is_empty():
		var anchor := Node2D.new()
		anchor.name = "CameraAnchor"
		_world.add_child(anchor)
		anchor.global_position = (_world.rooms[0]["rect"] as Rect2).get_center()
		targets.append(anchor)
	_camera.frame(targets)


## Ensure the Von launcher exists and has settled; returns whether a server is live.
func _await_von() -> bool:
	if _launcher == null:
		_launcher = LAUNCHER.new()
		_launcher.name = "DecisionServerLauncher"
		_launcher.resolved.connect(func(live: bool): _von_live = live)
		add_child(_launcher)
	if not _launcher.is_resolved():
		if _hud != null:
			_hud.show_status("Waiting for the decision server…")
		await _launcher.resolved
	return _von_live


# --- Interactive ----------------------------------------------------------------------------

## `--play <filter>`: pick the first test matching the words after it.
func _select_from_cli(args: PackedStringArray) -> void:
	var words := PackedStringArray()
	for a in args.slice(args.find("--play") + 1):
		if a.begins_with("--"):
			break
		words.append(a)
	var filter := " ".join(words)
	for e in TestCatalog.discover():
		if TestCatalog.matches(e, filter):
			Engine.set_meta(META_SELECTION, e["path"])
			return
	print("No test matches '%s'" % filter)


## Play the test at `path` with the result banner, leaving its world running afterwards.
func _run_interactive(path: String) -> void:
	var entry := TestCatalog.describe(path)
	_hud.show_running(entry)
	await _start(entry)
	var result := _result()
	_remember(result)
	_hud.show_result(result)


## Rerun: tear the world down and play the same test again.
func _on_rerun() -> void:
	var path: String = _entry.get("path", "")
	await _close()
	_run_interactive(path)


## Back / Escape: restore statics and return to the browser (the scene change frees the world).
func _back_to_browser() -> void:
	if is_instance_valid(_world):
		_world.restore()
	get_tree().change_scene_to_file(BROWSER_SCENE)


## In-game overlay toggle bar (UI) for the actors' debug overlays, as in a match.
func _build_toggles() -> void:
	_toggles = OVERLAY_TOGGLES.new()
	_toggles.name = "OverlayToggles"
	add_child(_toggles)
	_toggles.setup(_world.overlay_flags())
	_toggles.overlay_toggled.connect(func(flag: String, on: bool):
		if is_instance_valid(_world):
			_world.set_overlay(flag, on))


## Record the verdict per test id for the browser's marks.
func _remember(result: Dictionary) -> void:
	var results: Dictionary = Engine.get_meta(META_RESULTS, {})
	results[result["id"]] = result["status"]
	Engine.set_meta(META_RESULTS, results)


# --- Batch ----------------------------------------------------------------------------------

## Batch: run every test matching the non-flag args in turn, print, report, and quit with 0 / 1.
func _run_batch(args: PackedStringArray) -> void:
	var words := PackedStringArray()
	for a in args:
		if not a.begins_with("--"):
			words.append(a)
	var filter := " ".join(words)
	_include_von = args.has("--include-von")
	_require_von = args.has("--require-von")
	_shots = args.has("--shots")
	if _shots and DisplayServer.get_name() == "headless":
		print("NOTE  --shots needs a rendering run; tools/run_tests.sh --shots drops --headless")
	var out := _option(args, "--out", "")
	if out != "":
		_report_path = out.path_join("report.json")
		_bundle_dir = out.path_join("failures")
	var repeat := maxi(1, int(_option(args, "--repeat", "1")))
	TestSetup.seed_override = int(_option(args, "--seed", "0"))
	var self_test := args.has("--self-test")
	TestCatalog.show_internal = self_test
	var picked := TestCatalog.discover().filter(func(e): return (e["internal"] or not self_test) and TestCatalog.matches(e, filter))
	if args.has("--list"):
		_print_list(picked)
		get_tree().quit(0)
		return
	if not _watch.available():
		print("NOTE  log file not found — errors/warnings cannot fail tests this run")
	print("Godot %s  fixed-fps %d  Von tests: %s%s%s" % [Engine.get_version_info()["string"], Engine.physics_ticks_per_second,
		"required" if _require_von else ("included" if _include_von else "skipped"),
		"" if repeat == 1 else "  repeat x%d" % repeat,
		"" if TestSetup.seed_override == 0 else "  seed %d" % TestSetup.seed_override])
	print("Running %d test(s)%s" % [picked.size(), "" if filter == "" else " matching '%s'" % filter])
	var results: Array = []
	for entry in picked:
		for run in repeat:
			var result: Dictionary
			if entry["manual"]:
				result = { "id": entry["id"], "name": entry["name"], "domain": entry["domain"], "status": "SKIPPED",
					"reason": "manual sandbox", "time": 0.0, "checks": [], "logs": [], "manual": true }
			else:
				await _start(entry)
				result = await _close()
			results.append(result)
			_print_result(result)
			if result["status"] == "SKIPPED":
				break  # a skip repeats identically
	for entry in _watch.poll(true):
		_route_log(entry)
	var code := _summarize(results, repeat)
	_write_report(results)
	if args.has("--json"):
		print("JSON: " + JSON.stringify({ "results": results, "stray_logs": _stray_logs }))
	get_tree().quit(code)


## The value of a `--name=value` argument, or `fallback`.
func _option(args: PackedStringArray, name: String, fallback: String) -> String:
	for a in args:
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return fallback


## `--list`: one line per test (id, flags, tags, name).
func _print_list(entries: Array) -> void:
	for e in entries:
		var flags := PackedStringArray()
		if e["requires_von"]:
			flags.append("von")
		if e["manual"]:
			flags.append("manual")
		print("%-45s %-12s [%s]  %s" % [e["id"], ",".join(flags), ", ".join(PackedStringArray(e["tags"])), e["name"]])
	print("%d test(s)" % entries.size())


## One result line, plus each failed check indented.
func _print_result(r: Dictionary) -> void:
	var tail: String = "" if r["reason"] == "" else "  — " + String(r["reason"])
	print("%-7s %s  (%.1fs)%s" % [r["status"], r["id"], r["time"], tail])
	for c in r["checks"]:
		if not c["ok"]:
			print("        ✗ %s" % c["message"])
	if r.has("snapshot"):
		for id in r["snapshot"]["actors"]:
			var a: Dictionary = r["snapshot"]["actors"][id]
			print("        · %s at %s  health %s%s%s" % [id, a.get("position", ""), a.get("health", "?"),
				"  DEAD" if a.get("is_dead", false) else "", "  act " + a["act"] if a.has("act") else ""])
		for name in r["traces"]:
			var series: Array = r["traces"][name]
			var values := series.map(func(p): return p[1])
			print("        ~ %s: min %s  max %s  last %s  (%d samples)" % [name, values.min(), values.max(), values.back(), series.size()])
		print("        bundle: %s" % _write_bundle(r))
		for shot in r.get("shots", []):
			print("        shot:   %s" % shot)


## Write a failed result (events, snapshot, traces included) to the bundle dir; returns the file's path.
func _write_bundle(r: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(_bundle_dir)
	var path := "%s/%s.json" % [_bundle_dir, String(r["id"]).replace("/", "__")]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(r, "  "))
	return ProjectSettings.globalize_path(path)


## Print stray logs and the totals; returns the exit code. With `repeat` > 1 also names flaky tests.
func _summarize(results: Array, repeat := 1) -> int:
	var counts := { "PASS": 0, "FAIL": 0, "TIMEOUT": 0, "SKIPPED": 0 }
	for r in results:
		counts[r["status"]] = counts.get(r["status"], 0) + 1
	if not _stray_logs.is_empty():
		print("Logged outside any test (%d):" % _stray_logs.size())
		for e in _stray_logs:
			print("        ✗ %s: %s %s" % [e["severity"], e["message"], e["location"]])
	if repeat > 1:
		var tally := {}
		for r in results:
			if r["status"] == "SKIPPED":
				continue
			var t: Array = tally.get(r["id"], [0, 0])
			t[0] += 1 if r["status"] == "PASS" else 0
			t[1] += 1
			tally[r["id"]] = t
		for id in tally:
			if tally[id][0] != tally[id][1]:
				print("%s  %d/%d passed%s" % ["FLAKY  " if tally[id][0] > 0 else "FAILING", tally[id][0], tally[id][1], "  " + id])
	print("%d passed, %d failed, %d timed out, %d skipped" % [counts["PASS"], counts["FAIL"], counts["TIMEOUT"], counts["SKIPPED"]])
	var bad: int = counts["FAIL"] + counts["TIMEOUT"] + (1 if not _stray_logs.is_empty() else 0)
	return 1 if bad > 0 else 0


## Write the JSON report (results + stray logs) to the report path.
func _write_report(results: Array) -> void:
	var f := FileAccess.open(_report_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({ "results": results, "stray_logs": _stray_logs }, "  "))
	print("Report: %s" % ProjectSettings.globalize_path(_report_path))
