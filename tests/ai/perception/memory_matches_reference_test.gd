extends GameTest

## The AI event memory answers exactly as a plain, ordered log of events would: the same events survive a keyed write, an age
## expiry and a volume eviction, and every reader (`recall`, `recall_all`, `recall_aged`, `age_of`, `is_fresh`, `fresh`, `size`)
## returns the same events in the same order. The plain log below is the oracle; a few hundred random writes with mixed
## topics, keys and lifetimes (permanent, long, default and short) run through both, with a pause that expires every short
## event at once so no expiry sits on a clock boundary.

const AgentMemory := preload("res://scenes/ai/perception/agent_memory.gd")
const TOPICS: Array[StringName] = [&"saw_character", &"visited_room", &"hostile", &"heard_gunfire", &"saw_room", &"engaged"]
const KEYS: Array[String] = ["", "a", "b", "c", "d"]
const LIFETIMES: Array[float] = [0.0, -1.0, 600.0, 0.05, 0.05]
const ROUNDS := 24
const WRITES_PER_ROUND := 14
const AGE_TOLERANCE_S := 0.05


func describe() -> Dictionary:
	return {
		"name": "The event memory matches a plain ordered log",
		"description": "Random writes through the real memory and a naive reference log give the same events from every reader.",
		"tags": ["ai", "memory", "scripted"],
		"timeout": 20.0,
	}


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var real := AgentMemory.new()
	var plain := PlainLog.new()
	for m in [real, plain]:
		m.capacity = 18
	var mismatches := 0
	var checked := 0
	for batch in ROUNDS:
		for w in WRITES_PER_ROUND:
			var topic: StringName = TOPICS[rng.randi() % TOPICS.size()]
			var key: String = KEYS[rng.randi() % KEYS.size()]
			var ttl: float = LIFETIMES[rng.randi() % LIFETIMES.size()]
			var data := { "v": batch * 100 + w, "id": rng.randi() % 4 }
			real.remember(topic, data, ttl, key)
			plain.remember(topic, data, ttl, key)
			if rng.randf() < 0.3:
				var mid := _compare(real, plain, rng)
				checked += 1
				if mid != "":
					mismatches += 1
					t.check(false, "batch %d write %d: %s" % [batch, w, mid])
		if batch % 4 == 3:
			await t.frames(5)  # 83 ms of game time: every 0.05 s event written so far has expired; nothing is near its deadline.
		var after := _compare(real, plain, rng)
		checked += 1
		if after != "":
			mismatches += 1
			t.check(false, "end of batch %d: %s" % [batch, after])
		if mismatches > 3:
			break
	t.check(checked > 100 and mismatches == 0, "%d comparisons, %d mismatches" % [checked, mismatches])
	t.check(real.size() == plain.size(), "the same number of events are stored (%d, reference %d)" % [real.size(), plain.size()])


## Every reader of both memories on a random topic, field and value; "" when they agree, else what differed.
func _compare(real: RefCounted, plain: RefCounted, rng: RandomNumberGenerator) -> String:
	if real.size() != plain.size():
		return "size %d vs %d" % [real.size(), plain.size()]
	for topic in TOPICS:
		if real.is_fresh(topic) != plain.is_fresh(topic):
			return "is_fresh(%s)" % topic
		if real.recall(topic) != plain.recall(topic):
			return "recall(%s)" % topic
		var a: Array = real.recall_all(topic)
		var b: Array = plain.recall_all(topic)
		if a != b:
			return "recall_all(%s): %s vs %s" % [topic, a, b]
		var aged_real: Array = real.recall_aged(topic)
		var aged_plain: Array = plain.recall_aged(topic)
		if aged_real.size() != aged_plain.size():
			return "recall_aged(%s) size %d vs %d" % [topic, aged_real.size(), aged_plain.size()]
		for i in aged_real.size():
			if aged_real[i]["data"] != aged_plain[i]["data"] or absf(aged_real[i]["age"] - aged_plain[i]["age"]) > AGE_TOLERANCE_S:
				return "recall_aged(%s)[%d]" % [topic, i]
		var id := rng.randi() % 4
		var age_real: float = real.age_of(topic, "id", id)
		var age_plain: float = plain.age_of(topic, "id", id)
		if is_inf(age_real) != is_inf(age_plain) or (not is_inf(age_real) and absf(age_real - age_plain) > AGE_TOLERANCE_S):
			return "age_of(%s, id, %d): %s vs %s" % [topic, id, age_real, age_plain]
	var fresh_real: Array = real.fresh()
	var fresh_plain: Array = plain.fresh()
	if fresh_real.size() != fresh_plain.size():
		return "fresh() size %d vs %d" % [fresh_real.size(), fresh_plain.size()]
	for i in fresh_real.size():
		if fresh_real[i]["data"] != fresh_plain[i]["data"] or fresh_real[i]["topic"] != fresh_plain[i]["topic"]:
			return "fresh()[%d]" % i
	return ""


## The oracle: the memory as a single ordered array scanned in full on every call.
class PlainLog:
	extends RefCounted

	var capacity: int = 64
	var _entries: Array = []
	var _earliest_expiry := INF

	func remember(topic: StringName, data: Dictionary, ttl: float, key: String = "") -> void:
		if key != "":
			for i in range(_entries.size() - 1, -1, -1):
				var old: Dictionary = _entries[i]
				if old["topic"] == topic and old["key"] == key:
					_entries.remove_at(i)
		var at := GameClock.msec()
		var life: float = ttl
		_entries.append({ "topic": topic, "key": key, "data": data, "at": at, "ttl": life })
		if life > 0.0:
			_earliest_expiry = minf(_earliest_expiry, at + life * 1000.0 - 1.0)
		_prune()

	func age_of(topic: StringName, field: String, value: Variant) -> float:
		var now := GameClock.msec()
		for i in range(_entries.size() - 1, -1, -1):
			var entry: Dictionary = _entries[i]
			if entry["topic"] == topic and not _expired(entry, now) and entry["data"].get(field) == value:
				return (now - entry["at"]) / 1000.0
		return INF

	func recall_aged(topic: StringName) -> Array:
		var out: Array = []
		var now := GameClock.msec()
		for i in range(_entries.size() - 1, -1, -1):
			var entry: Dictionary = _entries[i]
			if entry["topic"] == topic and not _expired(entry, now):
				out.append({ "data": entry["data"], "age": (now - entry["at"]) / 1000.0 })
		return out

	func size() -> int:
		return _entries.size()

	func is_fresh(topic: StringName) -> bool:
		var now := GameClock.msec()
		for entry in _entries:
			if entry["topic"] == topic and not _expired(entry, now):
				return true
		return false

	func recall(topic: StringName) -> Dictionary:
		var now := GameClock.msec()
		for i in range(_entries.size() - 1, -1, -1):
			var entry: Dictionary = _entries[i]
			if entry["topic"] == topic and not _expired(entry, now):
				return entry["data"]
		return {}

	func recall_all(topic: StringName) -> Array:
		var out: Array = []
		var now := GameClock.msec()
		for i in range(_entries.size() - 1, -1, -1):
			var entry: Dictionary = _entries[i]
			if entry["topic"] == topic and not _expired(entry, now):
				out.append(entry["data"])
		return out

	func fresh() -> Array:
		var out: Array = []
		var now := GameClock.msec()
		for i in range(_entries.size() - 1, -1, -1):
			if not _expired(_entries[i], now):
				out.append(_entries[i])
		return out

	func _prune() -> void:
		var now := GameClock.msec()
		if now >= _earliest_expiry:
			var live: Array = []
			var earliest := INF
			for entry in _entries:
				if _expired(entry, now):
					continue
				live.append(entry)
				var ttl: float = entry["ttl"]
				if ttl > 0.0:
					earliest = minf(earliest, entry["at"] + ttl * 1000.0 - 1.0)
			_entries = live
			_earliest_expiry = earliest
		if capacity <= 0 or _entries.size() <= capacity:
			return
		var over: int = _entries.size() - capacity
		var kept: Array = []
		for entry in _entries:
			if over > 0 and entry["ttl"] > 0.0:
				over -= 1
				continue
			kept.append(entry)
		_entries = kept

	func _expired(entry: Dictionary, now: int) -> bool:
		var ttl: float = entry["ttl"]
		if ttl <= 0.0:
			return false
		return (now - entry["at"]) / 1000.0 > ttl
