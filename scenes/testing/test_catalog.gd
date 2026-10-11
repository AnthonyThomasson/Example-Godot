extends RefCounted

## Testing domain: finds every test (`res://tests/**/*_test.gd`) and describes it as a plain dict the
## browser and runner work from:
##   { id, path, name, domain, description, tags, timeout, requires_von, manual, internal, switches, world,
##     error }
## `id` is the path under tests/ without the suffix (e.g. "projectile/pistol_shot_wounds"); `error` is
## set (and the rest defaulted) when the script fails to load. `configure()` is called on a scratch
## TestSetup to read which switches and world a test uses — it only records data.

const ROOT := "res://tests"
const SUFFIX := "_test.gd"
const DEFAULT_TIMEOUT := 10.0
## Engine metas shared by the browser and the runner: the test to play, and the last status per test id.
const META_SELECTION := "test_selection"
const META_RESULTS := "test_results"
static var _WORD: RegEx = null
## Whether `discover()` also returns harness self-tests (`internal: true`); the runner's `--self-test`.
static var show_internal := false


## Every test under `root`, sorted by id (so grouped by domain). Harness self-tests (`internal: true`
## in `describe()`) are left out unless `show_internal`. `domains` / `ids` (when non-empty) keep only
## tests of those domains / with those exact ids, decided from the path so the rest are never loaded.
static func discover(root := ROOT, domains: Array = [], ids: Array = []) -> Array:
	var out: Array = []
	for path in _find(root):
		var rel: String = path.trim_prefix(root + "/").trim_suffix(SUFFIX)
		if not ids.is_empty() and not ids.has(rel):
			continue
		if not domains.is_empty() and not domains.has(rel.get_slice("/", 0) if "/" in rel else "general"):
			continue
		var entry := describe(path, root)
		if show_internal or not entry["internal"]:
			out.append(entry)
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


## The descriptor for the test script at `path`.
static func describe(path: String, root := ROOT) -> Dictionary:
	var rel := path.trim_prefix(root + "/").trim_suffix(SUFFIX)
	var parts := rel.split("/")
	var entry := {
		"id": rel, "path": path,
		"name": parts[parts.size() - 1].capitalize(),
		"domain": parts[0] if parts.size() > 1 else "general",
		"description": "", "tags": [], "timeout": DEFAULT_TIMEOUT,
		"requires_von": false, "manual": false, "internal": false, "switches": {}, "world": "", "error": "",
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
	var setup := TestSetup.new()
	test.configure(setup)
	entry["switches"] = setup.switches
	entry["world"] = setup.resolved_world()["kind"]
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


## Test file paths under `dir_path`, found recursively.
static func _find(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find(dir_path + "/" + sub))
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if f.ends_with(SUFFIX):
			out.append(dir_path + "/" + f)
	return out


## The non-empty items of a comma-separated list.
static func csv(text: String) -> Array:
	var out: Array = []
	for item in text.split(",", false):
		out.append(item.strip_edges())
	return out


## Shard `spec` ("I/N", I from 0) of `entries`. Every shard computes the same split: tests that need Von
## all go to shard 0 (they are paced in real time and share one launcher); the rest, longest `timeout`
## first, each go to the shard with the least timeout so far, so the shards finish at about the same time.
static func shard(entries: Array, spec: String) -> Array:
	var parts := spec.split("/")
	var count := maxi(1, int(parts[1])) if parts.size() == 2 else 1
	var index := clampi(int(parts[0]), 0, count - 1)
	var load: Array = []
	load.resize(count)
	load.fill(0.0)
	var rest: Array = []
	for e in entries:
		if e["requires_von"]:
			load[0] += float(e.get("timeout", 1.0))
		else:
			rest.append(e)
	var order := rest.duplicate()
	order.sort_custom(func(a, b):
		var ta := float(a.get("timeout", 1.0))
		var tb := float(b.get("timeout", 1.0))
		return a["id"] < b["id"] if ta == tb else ta > tb)  # ties by id: sort_custom is not stable
	var mine: Array = []
	for e in order:
		var lightest := 0
		for k in count:
			if load[k] < load[lightest]:
				lightest = k
		load[lightest] += float(e.get("timeout", 1.0))
		if lightest == index:
			mine.append(e)
	var out: Array = []
	for e in entries:
		if mine.has(e) or (e["requires_von"] and index == 0):
			out.append(e)
	return out
