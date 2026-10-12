extends Node2D

## Testing domain: runs game tests — a second composition root beside main.gd. Two modes:
##   interactive — plays the test the browser picked (`Engine` meta `test_selection`, or the first
##                 match of `-- --play <filter>`), shows the result banner and keeps the world
##                 running; Rerun rebuilds it, Back/Escape returns to the browser;
##   queued      — the browser's "Run N checked" (`Engine` meta `test_queue`, ordered paths): interactive,
##                 but plays each test in turn, pausing on its verdict then freeing it and starting the
##                 next; Back/Escape cancels the rest;
##   batch       — `godot --headless --fixed-fps 60 res://scenes/testing/test_runner.tscn --
##                 --run-tests [filter] [--domain=a,b] [--id=a,b] [--failed=<report>] [--shard=I/N]
##                 [--fail-fast] [--summary] [--include-von]` runs every matching test (`--domain` / `--id`
##                 keep only those exact domains / ids, unlike the prefix-matching filter; `--shard` takes
##                 one balanced slice of the run) in turn, prints one
##                 line each (just the non-passing ones with `--summary`) plus a summary, writes `user://test_report.json` and exits 1 on any
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
const RESULT_HUD = preload("res://scenes/ui/testing/test_result_hud.gd")
const OVERLAY_TOGGLES = preload("res://scenes/ui/overlays/overlay_toggles.gd")
const OVERLAY_REGISTRY = preload("res://scenes/ui/overlays/overlay_registry.gd")
const PERFORMANCE_OVERLAY = preload("res://scenes/ui/overlays/performance_overlay.gd")
const BROWSER_SCENE := "res://scenes/testing/test_browser.tscn"
const REPORT_PATH := "user://test_report.json"
## Failed/timed-out tests write their event log, final state and traces here (one JSON per test id).
const BUNDLE_DIR := "user://test_failures"
## Frame rate a Von-dependent test is paced to in real time (matches the batch run's --fixed-fps 60).
const REALTIME_FPS := 60
## Seconds a queued run holds each verdict before the next test starts (the HUD's Next skips it).
const QUEUE_PAUSE := 2.0

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
## `--fail-fast`: stop after the first FAIL / TIMEOUT. `--summary`: print only non-passing tests and the totals.
var _fail_fast := false
var _stopped := false  ## A `--fail-fast` failure has ended the run.
var _compact := false  ## `--summary` is on.
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
var _perf: CanvasLayer = null
## Whether the open test has a human-driven player (Space is then its INTERACT, not pause).
var _has_player := false
## The open test's locked interactions (`TestSetup.lock_interaction`).
var _locked: Array = []
## A queued run is going (false once it was cancelled, so a loop parked on a wait stops).
var _queue_active := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# A run given `--out=<dir>` was also started with `--log-file <dir>/godot.log` (the engine consumes that
	# flag, so it is not visible here and does not update the project setting): follow the moved log.
	var out := _option(args, "--out", "")
	if out != "":
		_watch.path_override = out.path_join("godot.log")
	_watch.begin(args.has("--run-tests") and out != "")  # a batch run owns a fresh log: startup errors count too
	if args.has("--play"):
		_select_from_cli(args)
	if args.has("--run-tests"):
		_batch = true
		_run_batch.call_deferred(args)
	elif Engine.has_meta(TestCatalog.META_QUEUE) or Engine.has_meta(TestCatalog.META_SELECTION):
		_hud = RESULT_HUD.new()
		_hud.name = "TestResultHUD"
		add_child(_hud)
		_hud.rerun_requested.connect(_on_rerun)
		_hud.back_requested.connect(_back_to_browser)
		_hud.pause_requested.connect(func(): _set_paused(not get_tree().paused))
		# The runner keeps processing while paused (Esc / Space still work); each test's world is made
		# pausable in `_start`, and the test clock below stops with the tree.
		process_mode = Node.PROCESS_MODE_ALWAYS
		if Engine.has_meta(TestCatalog.META_QUEUE):
			var paths: Array = Engine.get_meta(TestCatalog.META_QUEUE)
			Engine.remove_meta(TestCatalog.META_QUEUE)  # consumed: a later visit to the runner plays a single test
			_queue_active = true
			_run_queue.call_deferred(paths)
		else:
			_run_interactive.call_deferred(String(Engine.get_meta(TestCatalog.META_SELECTION)))
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
	if get_tree().paused:
		return  # the test clock (and so its timeout and waits) stops with the world
	if _ctx != null and not _ctx.is_finished:
		_ctx.time += delta
		if not _entry.get("manual", false) and _ctx.time >= float(_entry.get("timeout", TestCatalog.DEFAULT_TIMEOUT)):
			_ctx.reason = "timed out after %.1fs" % float(_entry["timeout"])
			_ctx.finish("TIMEOUT")


func _exit_tree() -> void:
	get_tree().paused = false
	if _ctx != null:
		_ctx.free()
		_ctx = null


## While a test locks the camera, drop the user's own camera events (wheel, trackpad, camera keys) before any
## camera sees them; the ones the test injects itself carry `TestContext.INJECTED_META` and pass.
func _input(event: InputEvent) -> void:
	if _locked.has(&"camera") and not event.has_meta(TestContext.INJECTED_META) \
			and (event is InputEventPanGesture or event.is_action(Keybinds.ZOOM_IN) or event.is_action(Keybinds.ZOOM_OUT)
			or event.is_action(Keybinds.CAMERA_LEFT) or event.is_action(Keybinds.CAMERA_RIGHT)
			or event.is_action(Keybinds.CAMERA_UP) or event.is_action(Keybinds.CAMERA_DOWN)):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _batch or event.is_echo():
		return
	if event.is_action_pressed(Keybinds.MENU):
		_back_to_browser()
	elif event.is_action_pressed(Keybinds.PAUSE) and not _has_player and not _locked.has(&"pause"):
		_set_paused(not get_tree().paused)


## Freeze or resume the open test's world (the banner, overlay bar and this runner keep running).
func _set_paused(on: bool) -> void:
	get_tree().paused = on
	if _hud != null:
		_hud.set_paused(on)


# --- Running one test -----------------------------------------------------------------------

## Build and run the test `entry`, leaving its world open. Returns once it has ended.
func _start(entry: Dictionary) -> void:
	_set_paused(false)
	_entry = entry
	_locked = []
	if _hud != null:
		_hud.set_pause_enabled(true)
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
	_locked = setup.locked
	if _hud != null:
		_hud.set_pause_enabled(not _locked.has(&"pause"))
	_world = TestWorldScript.new()
	_world.name = "TestWorld"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE  # not inherited from the always-on runner
	_has_player = setup.actors.any(func(a): return a["kind"] == &"player")
	add_child(_world)
	_world.child_entered_tree.connect(func(n: Node): _on_event(&"spawned", { "node": n, "name": String(n.name) }))
	_world.child_exiting_tree.connect(func(n: Node): _on_event(&"removed", { "node": n, "name": String(n.name) }))
	EventBus.posted.connect(_on_event)
	await _world.build(setup)
	if not is_instance_valid(_world):
		return
	_ctx.bind(_world, _world.actors, _world.objects, _world.rooms)
	for id in _world.actors:
		_observe_actor(id, _world.actors[id])
	_frame_camera(setup)
	if not _batch and not _locked.has(&"overlays"):
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
	if is_instance_valid(_perf):
		_perf.queue_free()
	_perf = null
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
			var flipped := _result()  # a late error flips a shown verdict
			_print_result(flipped)
			_hud.show_result(flipped)
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
## A world with a human-driven player keeps WASD for walking, so the camera's hand-pan is off there.
func _frame_camera(setup: TestSetup) -> void:
	_camera.set("pan_enabled", not _has_player and not _locked.has(&"camera"))
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
	TestCatalog.show_internal = true  # a named test is played even when it is a harness self-test
	var found := TestCatalog.discover() + TestCatalog.discover_sandboxes()
	TestCatalog.show_internal = false
	for e in found:
		if TestCatalog.matches(e, filter):
			Engine.set_meta(TestCatalog.META_SELECTION, e["path"])
			return
	print("No test matches '%s'" % filter)


## Play the test at `path` with the result banner, leaving its world running afterwards.
func _run_interactive(path: String) -> void:
	var entry := TestCatalog.describe(path)
	_hud.show_running(entry)
	_warn_if_unwatched()
	await _start(entry)
	var result := _result()
	_remember(result)
	_print_result(result)
	_hud.show_result(result)


## Say so on the banner (and the console) when the engine log cannot be read: errors and warnings would then
## not fail the test, which must never pass silently.
func _warn_if_unwatched() -> void:
	if not _watch.available():
		var text := "NOTE: engine log not found - errors and warnings will NOT fail this test"
		print(text)
		if _hud != null:
			_hud.show_status(text)


## Play `paths` one after another: each runs to its verdict, which is held for QUEUE_PAUSE (or until Next), then
## its world is freed and the next starts. A failure does not stop the queue; the last test's world stays up
## under a summary.
func _run_queue(paths: Array) -> void:
	var counts := {}
	for i in paths.size():
		var entry := TestCatalog.describe(paths[i])
		_hud.show_queue(i + 1, paths.size())
		_hud.show_running(entry)
		_warn_if_unwatched()
		await _start(entry)
		if not _queue_active:
			return
		var result := _result()
		_remember(result)
		_print_result(result)
		counts[result["status"]] = counts.get(result["status"], 0) + 1
		_hud.show_result(result)
		if i < paths.size() - 1:
			_hud.set_next_ready(true)
			await _queue_pause()
			if not _queue_active:
				return
			await _close()
	_hud.show_queue_done("%d passed, %d failed, %d timed out, %d skipped" % [counts.get("PASS", 0),
		counts.get("FAIL", 0), counts.get("TIMEOUT", 0), counts.get("SKIPPED", 0)])


## Hold the shown verdict for QUEUE_PAUSE seconds of wall time, or until the HUD's Next is pressed.
func _queue_pause() -> void:
	var timer := get_tree().create_timer(QUEUE_PAUSE, false)  # not always-on: pausing holds the verdict
	var skip := func(): timer.time_left = 0.0
	_hud.next_requested.connect(skip, CONNECT_ONE_SHOT)
	await timer.timeout
	if is_instance_valid(_hud) and _hud.next_requested.is_connected(skip):
		_hud.next_requested.disconnect(skip)


## Rerun: tear the world down and play the same test again.
func _on_rerun() -> void:
	var path: String = _entry.get("path", "")
	await _close()
	_run_interactive(path)


## Back / Escape: restore statics and return to the browser (the scene change frees the world).
func _back_to_browser() -> void:
	_queue_active = false  # cancels the rest of a queued run
	get_tree().paused = false
	if is_instance_valid(_world):
		_world.restore()
	get_tree().change_scene_to_file(BROWSER_SCENE)


## In-game overlay toggle bar (UI) for the actors' debug overlays, as in a match.
func _build_toggles() -> void:
	_toggles = OVERLAY_TOGGLES.new()
	_toggles.name = "OverlayToggles"
	add_child(_toggles)
	_toggles.setup(_world.overlay_flags())
	# The performance panel is the runner's own (it needs no world); the rest go to the world.
	_perf = PERFORMANCE_OVERLAY.new()
	_perf.name = "PerformanceOverlay"
	add_child(_perf)
	_perf.set_shown(_world.overlay_flags().get(OVERLAY_REGISTRY.PERF, false))
	_toggles.overlay_toggled.connect(func(flag: String, on: bool):
		if flag == OVERLAY_REGISTRY.PERF:
			if is_instance_valid(_perf):
				_perf.set_shown(on)
		elif is_instance_valid(_world):
			_world.set_overlay(flag, on))


## Record the verdict per test id for the browser's marks.
func _remember(result: Dictionary) -> void:
	var results: Dictionary = Engine.get_meta(TestCatalog.META_RESULTS, {})
	results[result["id"]] = result["status"]
	Engine.set_meta(TestCatalog.META_RESULTS, results)


# --- Batch ----------------------------------------------------------------------------------

## Batch: run every test matching the non-flag args in turn, print, report, and quit with 0 / 1.
func _run_batch(args: PackedStringArray) -> void:
	var words := PackedStringArray()
	for a in args:
		if not a.begins_with("--"):
			words.append(a)
	var filter := " ".join(words)
	GameLog.enabled = args.has("--verbose")  # a batch run shows verdicts only unless asked
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
	var domain := _option(args, "--domain", "")
	var domains := TestCatalog.csv(domain)
	var ids := TestCatalog.csv(_option(args, "--id", ""))
	var failed_from := _option(args, "--failed", "")
	if failed_from != "":
		ids.append_array(_failed_ids(failed_from))
		if ids.is_empty():
			ids.append("<no failed test in the last report>")  # selects nothing, rather than everything
	_fail_fast = args.has("--fail-fast")
	_compact = args.has("--summary")
	var self_test := args.has("--self-test")
	TestCatalog.show_internal = self_test
	var picked := TestCatalog.discover(TestCatalog.ROOT, domains, ids).filter(func(e): return (e["internal"] or not self_test) \
		and TestCatalog.matches(e, filter))
	var shard := _option(args, "--shard", "")
	if shard != "":
		picked = TestCatalog.shard(picked, shard)
	if args.has("--list"):
		_print_list(picked)
		get_tree().quit(0)
		return
	if not _watch.available():
		print("NOTE  log file not found — errors/warnings cannot fail tests this run")
	if not _compact:
		print("Godot %s  fixed-fps %d  Von tests: %s%s%s" % [Engine.get_version_info()["string"], Engine.physics_ticks_per_second,
			"required" if _require_von else ("included" if _include_von else "skipped"),
			"" if repeat == 1 else "  repeat x%d" % repeat,
			"" if TestSetup.seed_override == 0 else "  seed %d" % TestSetup.seed_override])
	if not _compact:
		print("Running %d test(s)%s%s%s" % [picked.size(), "" if domain == "" else " in domain '%s'" % domain,
			"" if filter == "" else " matching '%s'" % filter, "" if shard == "" else "  shard " + shard])
	var results: Array = []
	for entry in picked:
		if _stopped:
			break
		for run in repeat:
			var started := Time.get_ticks_msec()
			await _start(entry)
			var result: Dictionary = await _close()
			result["wall_ms"] = Time.get_ticks_msec() - started
			results.append(result)
			_print_result(result)
			if _fail_fast and (result["status"] == "FAIL" or result["status"] == "TIMEOUT"):
				_stopped = true
				break
			if result["status"] == "SKIPPED":
				break  # a skip repeats identically
	for entry in _watch.poll(true):
		_route_log(entry)
	var code := _summarize(results, repeat)
	_write_report(results)
	if args.has("--json"):
		print("JSON: " + JSON.stringify({ "results": results, "stray_logs": _stray_logs }))
	get_tree().quit(code)


## The ids that FAILED or TIMED OUT in the report at `path` (empty when it is missing or unreadable).
func _failed_ids(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for r in data.get("results", []):
			if r["status"] == "FAIL" or r["status"] == "TIMEOUT":
				out.append(r["id"])
	return out


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
		print("%-45s %-12s [%s]  %s" % [e["id"], ",".join(flags), ", ".join(PackedStringArray(e["tags"])), e["name"]])
	print("%d test(s)" % entries.size())


## One result line, plus each failed check indented.
func _print_result(r: Dictionary) -> void:
	if _compact and (r["status"] == "PASS" or r["status"] == "SKIPPED"):
		return
	var tail: String = "" if r["reason"] == "" else "  — " + String(r["reason"])
	print("%-7s %s  (%.1fs sim, %d ms)%s" % [r["status"], r["id"], r["time"], r.get("wall_ms", 0), tail])
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
	if not _compact:
		var timed := results.filter(func(r): return r["status"] != "SKIPPED" and r.has("wall_ms"))
		timed.sort_custom(func(a, b): return a["wall_ms"] > b["wall_ms"])
		if timed.size() > 1:
			print("Slowest: " + ", ".join(timed.slice(0, 5).map(func(r): return "%s %d ms" % [r["id"], r["wall_ms"]])))
	print("%d passed, %d failed, %d timed out, %d skipped" % [counts["PASS"], counts["FAIL"], counts["TIMEOUT"], counts["SKIPPED"]])
	var bad: int = counts["FAIL"] + counts["TIMEOUT"] + (1 if not _stray_logs.is_empty() else 0)
	return 1 if bad > 0 else 0


## Write the JSON report (results + stray logs) to the report path.
func _write_report(results: Array) -> void:
	var f := FileAccess.open(_report_path, FileAccess.WRITE)
	if f == null:
		return
	# `log_end`: how much of the engine log this run has judged; what the engine writes after it (shutdown) is
	# checked by tools/run_tests.sh through tools/scan_godot_log.py.
	f.store_string(JSON.stringify({ "results": results, "stray_logs": _stray_logs, "log_end": _watch.consumed() }, "  "))
	print("Report: %s" % ProjectSettings.globalize_path(_report_path))
