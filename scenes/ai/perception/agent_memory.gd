extends RefCounted

## AI domain: a generic, behaviour-agnostic memory for a non-player agent. It is an event log — an
## ordered list of remembered events, each a `topic` (what happened) with free-form `data` and a
## lifetime. Many events coexist, including many of the same topic; nothing is capped per topic.
## Behaviours (the controller) write events with `remember()` and read them back by topic to drive
## decisions; the perception renders fresh events into the decision state. It holds NO policy — it
## does not know what any topic means.
##
## Cleanup is a configurable policy, not a per-topic limit: `capacity` caps the total stored. Eviction
## runs on every write: age-expired events are dropped first, then, if still over capacity, the
## oldest EXPIRABLE event (one with a positive ttl). Permanent events (ttl <= 0 — long-term facts
## like learned house knowledge) never age out and are never volume-evicted. So memory self-cleans
## its volatile events by age and by volume, both tunable per NPC, while keeping what it has learned.
##
## A write may name a `key` (the event's SUBJECT — a character id, a room key): it then supersedes
## the live event with the same topic + key instead of piling up beside it. Something re-observed every
## tick (a visible character) stays one entry per subject rather than flooding the log and volume-
## evicting every other expirable event. Unkeyed writes always append.
##
## The log is kept as one list per topic, each in the order its events were written, and every event carries
## its write order across topics (`seq`). A write or a read touches only the lists of the topic it names, not
## every event stored, and the order the log promises (newest first, oldest evicted first) is the `seq` order.

## Hard cap on total stored events; the oldest are evicted past it. <= 0 = unlimited.
var capacity: int = 64

## The stored events by topic, each list oldest first. An entry is `{ topic, key, data, at, ttl, seq }` (`at` in msec,
## `ttl` in s, `seq` the write order across all topics).
var _by_topic: Dictionary = {}
## How many events are stored in all, live or awaiting cleanup.
var _count := 0
## The `seq` the next write takes.
var _next_seq := 0
## Milliseconds (`Time.get_ticks_msec`) before which no stored event can have outlived its ttl (a little early,
## never late), so `_prune` can skip its scan until then. INF = nothing stored expires.
var _earliest_expiry := INF


## Record that something happened: append an event under `topic` with `data`. `ttl` is its lifetime in seconds
## (<= 0 = permanent). A non-empty `key` supersedes any earlier event with the same topic + key (see the class
## note). Evicts expired/overflow events afterward.
func remember(topic: StringName, data: Dictionary, ttl: float, key: String = "") -> void:
	var list: Array = _by_topic.get(topic, [])
	if list.is_empty():
		_by_topic[topic] = list
	if key != "":
		for i in range(list.size() - 1, -1, -1):  # Drop the superseded events in place, order kept.
			if list[i]["key"] == key:
				list.remove_at(i)
				_count -= 1
	var at := Time.get_ticks_msec()
	var life: float = ttl
	list.append({
		"topic": topic,
		"key": key,
		"data": data,
		"at": at,
		"ttl": life,
		"seq": _next_seq,
	})
	_next_seq += 1
	_count += 1
	if life > 0.0:
		_earliest_expiry = minf(_earliest_expiry, at + life * 1000.0 - 1.0)
	_prune()


## Seconds since the freshest live `topic` event whose data field `field` equals `value` was written
## (INF when none is remembered) — how long ago something was last observed.
func age_of(topic: StringName, field: String, value: Variant) -> float:
	var list: Array = _by_topic.get(topic, [])
	var now := Time.get_ticks_msec()
	for i in range(list.size() - 1, -1, -1):
		var entry: Dictionary = list[i]
		if not _expired(entry, now) and entry["data"].get(field) == value:
			return (now - entry["at"]) / 1000.0
	return INF


## Every live `topic` event as `{ data, age }` (age in seconds), newest first — for readers that grade
## knowledge by how fresh it is (a sighting is a live contact, then an investigation lead).
func recall_aged(topic: StringName) -> Array:
	var out: Array = []
	var list: Array = _by_topic.get(topic, [])
	var now := Time.get_ticks_msec()
	for i in range(list.size() - 1, -1, -1):
		var entry: Dictionary = list[i]
		if not _expired(entry, now):
			out.append({ "data": entry["data"], "age": (now - entry["at"]) / 1000.0 })
	return out


## Number of stored events (live or awaiting cleanup) — for the debug snapshot.
func size() -> int:
	return _count


## Whether any non-expired event of `topic` is remembered.
func is_fresh(topic: StringName) -> bool:
	var now := Time.get_ticks_msec()
	for entry in _by_topic.get(topic, []):
		if not _expired(entry, now):
			return true
	return false


## The freshest non-expired event's `data` for `topic`, or an empty dict when none is remembered.
func recall(topic: StringName) -> Dictionary:
	var list: Array = _by_topic.get(topic, [])
	var now := Time.get_ticks_msec()
	for i in range(list.size() - 1, -1, -1):
		var entry: Dictionary = list[i]
		if not _expired(entry, now):
			return entry["data"]
	return {}


## Every non-expired event's `data` for `topic`, newest first.
func recall_all(topic: StringName) -> Array:
	var out: Array = []
	var list: Array = _by_topic.get(topic, [])
	var now := Time.get_ticks_msec()
	for i in range(list.size() - 1, -1, -1):
		var entry: Dictionary = list[i]
		if not _expired(entry, now):
			out.append(entry["data"])
	return out


## Every non-expired event (full entries), newest first — for rendering what the agent remembers.
func fresh() -> Array:
	var out: Array = []
	var now := Time.get_ticks_msec()
	for list: Array in _by_topic.values():
		for entry: Dictionary in list:
			if not _expired(entry, now):
				out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["seq"] > b["seq"])
	return out


## Apply the cleanup policy: drop age-expired events, then, while over `capacity`, drop the oldest
## EXPIRABLE events (positive ttl). Permanent events (ttl <= 0) are long-term facts and are never
## volume-evicted — they persist for the agent's lifetime.
func _prune() -> void:
	var now := Time.get_ticks_msec()
	if now >= _earliest_expiry:  # Otherwise nothing has outlived its ttl yet: skip the scan.
		var earliest := INF
		for topic in _by_topic.keys():
			var list: Array = _by_topic[topic]
			var live: Array = []
			for entry: Dictionary in list:
				if _expired(entry, now):
					continue
				live.append(entry)
				var ttl: float = entry["ttl"]
				if ttl > 0.0:
					earliest = minf(earliest, entry["at"] + ttl * 1000.0 - 1.0)
			_count -= list.size() - live.size()
			_by_topic[topic] = live
		_earliest_expiry = earliest
	if capacity <= 0 or _count <= capacity:
		return
	var over: int = _count - capacity
	while over > 0 and _evict_oldest_expirable():
		over -= 1


## Drop the oldest event (lowest `seq`) that has a positive ttl, across every topic. False when every stored event is permanent.
func _evict_oldest_expirable() -> bool:
	var oldest_list: Array = []
	var oldest_index := -1
	var oldest_seq := -1
	for list: Array in _by_topic.values():
		for i in list.size():  # A list is oldest first, so its first expirable event is its oldest.
			var entry: Dictionary = list[i]
			if entry["ttl"] > 0.0:
				if oldest_index < 0 or entry["seq"] < oldest_seq:
					oldest_list = list
					oldest_index = i
					oldest_seq = entry["seq"]
				break
	if oldest_index < 0:
		return false
	oldest_list.remove_at(oldest_index)
	_count -= 1
	return true


## Whether an event has outlived its ttl at `now` (`Time.get_ticks_msec`; ttl <= 0 never expires on age).
func _expired(entry: Dictionary, now: int) -> bool:
	var ttl: float = entry["ttl"]
	if ttl <= 0.0:
		return false
	return (now - entry["at"]) / 1000.0 > ttl
