extends RefCounted

## AI domain: a generic, behaviour-agnostic memory for a non-player agent. It is an event log — an
## ordered list of remembered events, each a `topic` (what happened) with free-form `data` and a
## lifetime. Many events coexist, including many of the same topic; nothing is capped per topic.
## Behaviours (the controller) write events with `remember()` and read them back by topic to drive
## decisions; the perception renders fresh events into the decision state. It holds NO policy — it
## does not know what any topic means.
##
## Cleanup is a configurable policy, not a per-topic limit. `default_ttl` sets a fallback lifetime
## for events remembered without an explicit one, and `capacity` caps the total stored. Eviction
## runs on every write: age-expired events are dropped first, then, if still over capacity, the
## oldest EXPIRABLE event (one with a positive ttl). Permanent events (ttl <= 0 — long-term facts
## like learned house knowledge) never age out and are never volume-evicted. So memory self-cleans
## its volatile events by age and by volume, both tunable per NPC, while keeping what it has learned.

## Fallback lifetime (seconds) for events remembered without an explicit ttl; <= 0 = no age expiry.
var default_ttl: float = 0.0
## Hard cap on total stored events; the oldest are evicted past it. <= 0 = unlimited.
var capacity: int = 64

## The event log, oldest first. Each entry is `{ topic, data, at, ttl }` (`at` in msec, `ttl` in s).
var _entries: Array = []


## Record that something happened: append an event under `topic` with optional `data` (which may
## carry a `note` string for the decision state). `ttl` is its lifetime in seconds; a negative ttl
## falls back to `default_ttl`. Evicts expired/overflow events afterward.
func remember(topic: StringName, data: Dictionary = {}, ttl: float = -1.0) -> void:
	_entries.append({
		"topic": topic,
		"data": data,
		"at": Time.get_ticks_msec(),
		"ttl": ttl if ttl >= 0.0 else default_ttl,
	})
	prune()


## Whether any non-expired event of `topic` is remembered.
func is_fresh(topic: StringName) -> bool:
	for entry in _entries:
		if entry["topic"] == topic and not _expired(entry):
			return true
	return false


## The freshest non-expired event's `data` for `topic`, or an empty dict when none is remembered.
func recall(topic: StringName) -> Dictionary:
	for i in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[i]
		if entry["topic"] == topic and not _expired(entry):
			return entry["data"]
	return {}


## Every non-expired event's `data` for `topic`, newest first.
func recall_all(topic: StringName) -> Array:
	var out: Array = []
	for i in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[i]
		if entry["topic"] == topic and not _expired(entry):
			out.append(entry["data"])
	return out


## Seconds since the freshest non-expired event of `topic` was remembered, or INF when none is.
func age(topic: StringName) -> float:
	for i in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[i]
		if entry["topic"] == topic and not _expired(entry):
			return (Time.get_ticks_msec() - entry["at"]) / 1000.0
	return INF


## Every non-expired event (full entries), newest first — for rendering what the agent remembers.
func fresh() -> Array:
	var out: Array = []
	for i in range(_entries.size() - 1, -1, -1):
		if not _expired(_entries[i]):
			out.append(_entries[i])
	return out


## Drop all events of `topic`.
func forget(topic: StringName) -> void:
	_entries = _entries.filter(func(entry): return entry["topic"] != topic)


## Apply the cleanup policy: drop age-expired events, then, while over `capacity`, drop the oldest
## EXPIRABLE events (positive ttl). Permanent events (ttl <= 0) are long-term facts and are never
## volume-evicted — they persist until explicitly forgotten.
func prune() -> void:
	_entries = _entries.filter(func(entry): return not _expired(entry))
	if capacity <= 0 or _entries.size() <= capacity:
		return
	var over: int = _entries.size() - capacity
	var kept: Array = []
	for entry in _entries:  # Oldest first, so this evicts the oldest expirable events.
		if over > 0 and entry["ttl"] > 0.0:
			over -= 1
			continue
		kept.append(entry)
	_entries = kept


## Whether an event has outlived its ttl (ttl <= 0 never expires on age).
func _expired(entry: Dictionary) -> bool:
	var ttl: float = entry["ttl"]
	if ttl <= 0.0:
		return false
	return (Time.get_ticks_msec() - entry["at"]) / 1000.0 > ttl
