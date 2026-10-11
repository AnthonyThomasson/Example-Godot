class_name TestContext extends Object

## Testing domain: what a running test sees — handed to `GameTest.run(t)`. Waiting (in sim time),
## looking up what the setup placed, the event log of what happened, and the assertions.
##
## Once the test has ended (a failed `require`, a logged error, a timeout, `skip`), every wait
## suspends until the runner frees this context (an Object, so freeing it discards the parked
## coroutines), so a test coroutine never runs on into a torn-down world. Code between a failed
## `require` and the next wait still runs, so guard it: `if not t.require(...): return`.

## Emitted once when the test ends, for whatever reason.
signal finished

## The built world (a TestWorld node) and its rooms (`{ key, type, rect }`, world-space).
var world: Node2D
var rooms: Array = []
## Sim seconds since the test started (advanced by the runner each physics frame).
var time := 0.0
## Assertion records: `{ ok, message, time }`.
var checks: Array = []
## Unexpected logged errors/warnings: `{ severity, message, location }`.
var logs: Array = []
## Everything observed, in order: `{ topic, data, time }`. Topics: every EventBus topic (`&"hit"`,
## `&"callout"`, …), plus `&"died"` / `&"hit_landed"` per actor (`data.actor` = its id) and
## `&"spawned"` / `&"removed"` for nodes entering/leaving the world root (`data.node`, `data.name`).
var events: Array = []
## Sampled series from `trace()`: name → Array of `[time, value]`.
var traces: Dictionary = {}
## Where `screenshot()` saves PNGs, as a path prefix ("" = screenshots off; the runner's `--shots` sets it
## on a rendering run). `shots` lists the files written.
var shot_prefix := ""
var shots: Array = []
## "PASS" | "FAIL" | "SKIPPED" | "TIMEOUT" once ended ("" while running).
var status := ""
## Why it was skipped / timed out.
var reason := ""
var is_finished := false

var _actors: Dictionary = {}
var _objects: Dictionary = {}
var _tree: SceneTree
## Outstanding expected log lines: `{ pattern, count }`.
var _expected_logs: Array = []
var _allowed_logs: Array = []
var _fail_on_errors := true
var _fail_on_warnings := true
var _concluded := false
## Never emitted: waits park on it once the test has ended.
signal _never


func _init(tree: SceneTree, description: Dictionary) -> void:
	_tree = tree
	_allowed_logs = description.get("allowed_logs", [])
	_fail_on_errors = description.get("fail_on_errors", true)
	_fail_on_warnings = description.get("fail_on_warnings", true)


# --- Lookup -------------------------------------------------------------------------------

## The character placed as `id` (null if unknown or freed).
func actor(id: StringName) -> Node:
	var n: Node = _actors.get(id)
	return n if is_instance_valid(n) else null


## The puppet controller of actor `id` (null when it isn't a puppet).
func puppet(id: StringName) -> Node:
	var a := actor(id)
	if a == null:
		return null
	for child in a.get_children():
		if child.has_method("walk_to"):
			return child
	return null


## The object placed as `id` (null if unknown or freed).
func object(id: StringName) -> Node:
	var n: Node = _objects.get(id)
	return n if is_instance_valid(n) else null


## A child controller of actor `id` that has `method` (e.g. an NPC's `current_act`), or null.
func controller(id: StringName, method := &"control") -> Node:
	var a := actor(id)
	if a == null:
		return null
	for child in a.get_children():
		if child.has_method(method):
			return child
	return null


# --- Waiting (sim time) ---------------------------------------------------------------------

## Wait `duration` seconds of simulated time.
func seconds(duration: float) -> void:
	var until_time := time + duration
	while time < until_time and not is_finished:
		await _tree.physics_frame
	if is_finished:
		await _never


## Wait `count` physics frames.
func frames(count: int) -> void:
	for i in count:
		await _tree.physics_frame
		if is_finished:
			break
	if is_finished:
		await _never


## Wait until `condition` returns true or `timeout` sim seconds pass. Returns whether it came true.
## With a `message`, a timeout also records a failed check.
func until(condition: Callable, timeout: float, message := "") -> bool:
	var deadline := time + timeout
	while not is_finished:
		if condition.call():
			return true
		if time >= deadline:
			if message != "":
				check(false, message + " (waited %.1fs)" % timeout)
			return false
		await _tree.physics_frame
	await _never
	return false


# --- Event log ------------------------------------------------------------------------------

## Logged events with `topic`, optionally filtered by `filter(data) -> bool`.
func events_of(topic: StringName, filter := Callable()) -> Array:
	var out: Array = []
	for e in events:
		if e["topic"] == topic and (not filter.is_valid() or filter.call(e["data"])):
			out.append(e["data"])
	return out


## Whether any event with `topic` (passing `filter`) has happened.
func happened(topic: StringName, filter := Callable()) -> bool:
	return not events_of(topic, filter).is_empty()


## Nodes that entered the world root whose name contains `name_part` (e.g. "BloodPool").
func spawned(name_part: String) -> Array:
	var out: Array = []
	for data in events_of(&"spawned"):
		if String(data["name"]).contains(name_part):
			out.append(data["node"])
	return out


## Record `value` (a number) under `name` at the current time, e.g. a distance a threshold check later
## misses. Failed runs print each series' range and last value and keep it in the failure bundle.
func trace(trace_name: String, value: float) -> void:
	var series: Array = traces.get(trace_name, [])
	series.append([snappedf(time, 0.01), snappedf(value, 0.001)])
	traces[trace_name] = series


## What the scripted Von (`TestSetup.von_script`) was asked: `{ state, question, options: Array, pick }`
## per ask, in order.
func von_requests() -> Array:
	return DecisionStub.requests


## Save the current frame as a PNG named after `label` and return its absolute path, or "" when
## screenshots are off (`--shots` not given) or there is no rendering (headless). Failed runs under
## `--shots` also get one automatically.
func screenshot(label: String) -> String:
	if shot_prefix == "" or DisplayServer.get_name() == "headless":
		return ""
	var image := _tree.root.get_texture().get_image()
	if image == null:
		return ""
	var path := "%s__%s.png" % [shot_prefix, label.validate_filename()]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		return ""
	var absolute := ProjectSettings.globalize_path(path)
	shots.append(absolute)
	return absolute


# --- Assertions -----------------------------------------------------------------------------

## Record `condition` as a check; returns it. A failure fails the test but lets it continue.
func check(condition: bool, message: String) -> bool:
	checks.append({ "ok": condition, "message": message, "time": time })
	return condition


## Like `check`, but a failure also ends the test. Returns `condition`.
func require(condition: bool, message: String) -> bool:
	check(condition, message)
	if not condition:
		finish("FAIL")
	return condition


## Check `actual == expected`.
func expect_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (got %s, expected %s)" % [message, actual, expected])


## Check `|actual - expected| <= tolerance`.
func expect_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
		"%s (got %.3f, expected %.3f ± %.3f)" % [message, actual, expected, tolerance])


## Declare that this test means to log a line matching `pattern` (regex) `count` times: those lines
## don't fail it, and the test fails if they never appear.
func expect_log(pattern: String, count := 1) -> void:
	_expected_logs.append({ "pattern": pattern, "count": count })


## End the test as SKIPPED.
func skip(why: String) -> void:
	reason = why
	finish("SKIPPED")


# --- Runner-facing --------------------------------------------------------------------------

## End the test with `result` (first call wins). Waits park; `finished` fires.
func finish(result: String) -> void:
	if is_finished:
		return
	is_finished = true
	status = result
	finished.emit()


## Handle one logged entry from LogWatch: allowed or expected lines pass, anything else fails.
func on_log(entry: Dictionary) -> void:
	if entry["severity"] == "error" and not _fail_on_errors:
		return
	if entry["severity"] == "warning" and not _fail_on_warnings:
		return
	var LogWatch := preload("res://scenes/testing/log_watch.gd")
	for e in _expected_logs:
		if e["count"] > 0 and LogWatch.matches_any(entry, [e["pattern"]]):
			e["count"] -= 1
			return
	if LogWatch.matches_any(entry, _allowed_logs):
		return
	logs.append(entry)
	var where: String = entry["location"]
	check(false, "Logged %s: %s%s" % [entry["severity"], entry["message"], "" if where == "" else " (at %s)" % where])
	finish("FAIL")


## Final verdict once the run is over: fails unmet expected logs, and a non-manual test that
## asserted nothing. Safe to call again (a late logged error re-decides it). Returns the status.
func conclude(manual: bool) -> String:
	if not _concluded:
		_concluded = true
		for e in _expected_logs:
			if e["count"] > 0:
				check(false, "Expected log never appeared: /%s/ (%d more)" % [e["pattern"], e["count"]])
		if checks.is_empty() and not manual and status != "SKIPPED":
			check(false, "The test made no assertions")
	if status == "SKIPPED" or status == "TIMEOUT":
		return status
	status = "FAIL" if checks.any(func(c): return not c["ok"]) else "PASS"
	return status


## Register what the world placed (called by the runner after the build).
func bind(built_world: Node2D, actors: Dictionary, objects: Dictionary, world_rooms: Array) -> void:
	world = built_world
	_actors = actors
	_objects = objects
	rooms = world_rooms


## The state of every placed actor and object right now, as plain data for a failure bundle: position,
## health/death, held item, and an NPC brain's decision path (duck-typed through the public API).
## Freed nodes are skipped, so take it before the world is torn down.
func snapshot() -> Dictionary:
	var out := { "actors": {}, "objects": {} }
	for id in _actors:
		var a: Node = actor(id)
		if a == null:
			continue
		var s := { "position": _vec(a.global_position) if a is Node2D else "" }
		for prop in ["health", "max_health", "is_dead", "faction", "move_input"]:
			if prop in a:
				s[prop] = _plain(a.get(prop))
		for child in a.get_children():
			if child.has_method("current_act"):
				var act: Variant = child.current_act()
				s["act"] = "/".join(PackedStringArray(act.map(func(x): return str(x)))) if act is Array else str(act)
			if child.has_method("debug_status"):
				s["status"] = str(child.debug_status())
		out["actors"][String(id)] = s
	for id in _objects:
		var o: Node = object(id)
		if o is Node2D:
			out["objects"][String(id)] = { "position": _vec(o.global_position) }
	return out


## The event log as JSON-safe rows `{ topic, time, data }` (nodes become their names).
func plain_events() -> Array:
	return events.map(func(e): return { "topic": String(e["topic"]), "time": snappedf(e["time"], 0.01), "data": _plain(e["data"]) })


static func _vec(v: Vector2) -> String:
	return "(%.0f, %.0f)" % [v.x, v.y]


## `v` reduced to JSON-safe values: nodes → their names, vectors → text, containers recursed.
static func _plain(v: Variant) -> Variant:
	if typeof(v) == TYPE_OBJECT:
		if not is_instance_valid(v):
			return "<freed>"
		return String(v.name) if v is Node else str(v)
	if v is Vector2:
		return _vec(v)
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _plain(v[k])
		return d
	if v is Array:
		return v.map(func(x): return _plain(x))
	if v is StringName:
		return String(v)
	if v == null or v is bool or v is int or v is float or v is String:
		return v
	return str(v)


## Append an observed event.
func record(topic: StringName, data: Dictionary) -> void:
	events.append({ "topic": topic, "data": data, "time": time })
