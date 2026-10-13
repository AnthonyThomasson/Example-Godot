extends RefCounted

## Testing domain: finds every test (`res://tests/**/*_test.gd`) and describes it as a plain dict the
## browser and runner work from:
##   { id, path, name, domain, category, description, tags, timeout, requires_von, manual, internal, switches, world,
##     locked, error }
## `id` is the path under tests/ without the suffix (e.g. "projectile/pistol_shot_wounds"); `category` is the
## sub-folder between the domain and the file when there is one (`tests/ai/entry/…` -> "entry", else ""); `error` is
## set (and the rest defaulted) when the script fails to load. `configure()` is called on a scratch
## TestSetup to read which switches and world a test uses — it only records data.

const ROOT := "res://tests"
const SUFFIX := "_test.gd"
## Sandboxes (`res://sandboxes/**/*_sandbox.gd`, also `GameTest` scripts) are played by hand: a separate
## catalog that `discover()` never returns, so batch runs and the test list never include them.
const SANDBOX_ROOT := "res://sandboxes"
const SANDBOX_SUFFIX := "_sandbox.gd"
const DEFAULT_TIMEOUT := 10.0
## Engine metas shared by the browser and the runner: the test to play, and the last status per test id.
const META_SELECTION := "test_selection"
const META_RESULTS := "test_results"
## The ids ticked in the browser (kept across a round trip through a test), and the ordered script paths of
## the queued headed run the browser hands the runner.
const META_CHECKED := "test_checked"
const META_QUEUE := "test_queue"
static var _WORD: RegEx = null
## Whether `discover()` also returns harness self-tests (`internal: true`); the runner's `--self-test`.
static var show_internal := false


## Every test under `root`, sorted by id (so grouped by domain). Harness self-tests (`internal: true`
## in `describe()`) are left out unless `show_internal`. `domains` / `ids` (when non-empty) keep only
## tests of those domains / with those exact ids, decided from the path so the rest are never loaded; `skipped`
## domains are left out the same way.
static func discover(root := ROOT, domains: Array = [], ids: Array = [], skipped: Array = []) -> Array:
	var out: Array = []
	for path in _find(root):
		var rel: String = path.trim_prefix(root + "/").trim_suffix(SUFFIX)
		if not ids.is_empty() and not ids.has(rel):
			continue
		var domain := rel.get_slice("/", 0) if "/" in rel else "general"
		if not domains.is_empty() and not domains.has(domain):
			continue
		if skipped.has(domain):
			continue
		var entry := describe(path, root)
		if show_internal or not entry["internal"]:
			out.append(entry)
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


## Every sandbox under `root`, sorted by id; each is `manual` (no assertions, no timeout).
static func discover_sandboxes(root := SANDBOX_ROOT) -> Array:
	var out: Array = []
	for path in _find(root, SANDBOX_SUFFIX):
		out.append(describe(path, root))
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


## The descriptor for the test or sandbox script at `path`.
static func describe(path: String, root := "") -> Dictionary:
	var sandbox := path.begins_with(SANDBOX_ROOT + "/")
	if root == "":
		root = SANDBOX_ROOT if sandbox else ROOT
	var rel := path.trim_prefix(root + "/").trim_suffix(SANDBOX_SUFFIX if sandbox else SUFFIX)
	var parts := rel.split("/")
	var entry := {
		"id": rel, "path": path,
		"name": parts[parts.size() - 1].capitalize(),
		"domain": parts[0] if parts.size() > 1 else "general",
		"category": parts[1] if parts.size() > 2 else "",
		"description": "", "tags": [], "timeout": DEFAULT_TIMEOUT,
		"requires_von": false, "manual": sandbox, "internal": false, "switches": {}, "world": "", "locked": [], "error": "",
	}
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		entry["error"] = "failed to load (parse error?)"
		return entry
	var test: Variant = script.new()
	if not test is GameTest:
		entry["error"] = "does not extend GameTest"
		return entry
	var info: Dictionary = test.describe()
	for key in info:
		entry[key] = info[key]
	entry["manual"] = sandbox
	var setup := TestSetup.new()
	test.configure(setup)
	entry["switches"] = setup.switches
	entry["world"] = setup.resolved_world()["kind"]
	entry["locked"] = setup.locked
	return entry


## Whether `entry` matches a search `text` (case-insensitive): every word must start a word of its
## id, name, domain, description or tags ("pist" finds "pistol"; "ai" finds the ai domain, not
## "chair"). Blank matches everything.
static func matches(entry: Dictionary, text: String) -> bool:
	var hay := " ".join([entry["id"], entry["name"], entry["domain"], entry["description"], " ".join(entry["tags"])]).to_lower()
	var words := PackedStringArray()
	if _WORD == null:
		_WORD = RegEx.new()
		_WORD.compile("[a-z0-9]+")
	for w in _WORD.search_all(hay):
		words.append(w.get_string())
	for query in text.to_lower().split(" ", false):
		if not Array(words).any(func(w: String): return w.begins_with(query)):
			return false
	return true


## Script paths ending in `suffix` under `dir_path`, found recursively.
static func _find(dir_path: String, suffix := SUFFIX) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find(dir_path + "/" + sub, suffix))
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if f.ends_with(suffix):
			out.append(dir_path + "/" + f)
	return out


## The non-empty items of a comma-separated list.
static func csv(text: String) -> Array:
	var out: Array = []
	for item in text.split(",", false):
		out.append(item.strip_edges())
	return out


## Shard `spec` ("I/N", I from 0) of `entries`. Every shard computes the same split: tests that need Von
## all go to shard 0 (they are paced in real time and share one launcher); the rest, costliest first, each
## go to the shard with the least cost so far, so the shards finish at about the same time.
## A test's cost is its wall-clock milliseconds in `costs` (id -> ms, measured by an earlier run; an id it
## lacks costs the median of those it has). With no `costs` the declared `timeout` stands in, which orders
## tests but says little about how long they really take. `von_runs` is whether the Von tests are going to
## run: when they are skipped they cost shard 0 nothing.
static func shard(entries: Array, spec: String, costs := {}, von_runs := true) -> Array:
	var parts := spec.split("/")
	var count := maxi(1, int(parts[1])) if parts.size() == 2 else 1
	var index := clampi(int(parts[0]), 0, count - 1)
	var fallback := _median(costs.values())
	var cost_of := func(e: Dictionary) -> float:
		if costs.is_empty():
			return float(e.get("timeout", 1.0))
		return float(costs[e["id"]]) if costs.has(e["id"]) else fallback
	var loads: Array = []
	loads.resize(count)
	loads.fill(0.0)
	var rest: Array = []
	for e in entries:
		if e["requires_von"]:
			if von_runs:
				loads[0] += cost_of.call(e)
		else:
			rest.append(e)
	var order := rest.duplicate()
	order.sort_custom(func(a, b):
		var ca: float = cost_of.call(a)
		var cb: float = cost_of.call(b)
		return a["id"] < b["id"] if ca == cb else ca > cb)  # ties by id: sort_custom is not stable
	var mine: Array = []
	for e in order:
		var lightest := 0
		for k in count:
			if loads[k] < loads[lightest]:
				lightest = k
		loads[lightest] += cost_of.call(e)
		if lightest == index:
			mine.append(e)
	var out: Array = []
	for e in entries:
		if mine.has(e) or (e["requires_von"] and index == 0):
			out.append(e)
	return out


## The per-test wall-clock costs (id -> ms) in the JSON file at `path` (what `shard` balances by); empty when
## it is missing or unreadable, which makes `shard` fall back to the declared timeouts.
static func load_costs(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	var out := {}
	if data is Dictionary:
		for id in data:
			if data[id] is float or data[id] is int:
				out[str(id)] = float(data[id])
	return out


## The middle value of `values` (numbers), 0 for none.
static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[int(sorted.size() / 2.0)])
