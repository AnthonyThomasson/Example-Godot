extends RefCounted

## AI domain: the HOSTILITY rules for a goal-driven NPC — which perceived characters it treats as
## hostile. Like the vision sense it is pure configuration plus a few queries; the perception feeds
## it each sighting and the controller feeds it each attack, and it records its verdicts in the
## agent's memory as `&"hostile"` events (`{ id, reason }`), so hostility persists and decays like any
## other knowledge. The same rules serve every NPC: a defender is "hostile on trespass + on attack", an
## invader "hostile on sight". Allies (same faction, or a listed one) are never hostile.

## Every non-allied character seen is hostile.
var on_sight: bool = false
## A non-allied character seen inside the house is hostile.
var trespass: bool = false
## A non-allied character that attacks this NPC (hits it or shoots close to it) is hostile.
var retaliate: bool = true
## Lifetime (s) of a hostility verdict; <= 0 = permanent (a grudge never fades).
var ttl: float = 0.0
## This NPC's own faction (read from its character).
var faction: StringName = &""
## Further factions this NPC treats as allies.
var allies: Array[StringName] = []


## Classify one sighting (`{ id, faction, inside, … }` from the perception) and remember a hostility
## verdict when a rule applies and the character is not already known to be hostile.
func classify(sighting: Dictionary, memory: RefCounted) -> void:
	if is_ally(sighting.get("faction", &"")) or is_hostile(sighting.get("id", 0), memory):
		return
	if on_sight:
		_mark(sighting["id"], "seen", memory)
	elif trespass and sighting.get("inside", false):
		_mark(sighting["id"], "trespassing", memory)


## Note that `attacker` (a character) attacked this NPC; marks it hostile under the retaliate rule.
func on_attacked(attacker: Node, memory: RefCounted) -> void:
	if not retaliate or attacker == null or not is_instance_valid(attacker):
		return
	var f = attacker.get("faction")
	if is_ally(f if f != null else &""):
		return
	var id := attacker.get_instance_id()
	# An empty reason (not yet hostile) also fails this test, so it covers the not-hostile case too.
	if reason(id, memory) != "attacked you":
		_mark(id, "attacked you", memory)


## Whether `f` is this NPC's faction or one of its allies.
func is_ally(f: StringName) -> bool:
	return f != &"" and (f == faction or allies.has(f))


## Whether character `id` is currently remembered as hostile.
func is_hostile(id: int, memory: RefCounted) -> bool:
	return not reason(id, memory).is_empty()


## Why character `id` is hostile (its freshest verdict), or "" when it isn't.
func reason(id: int, memory: RefCounted) -> String:
	for data in memory.recall_all(&"hostile"):
		if data.get("id") == id:
			return data.get("reason", "")
	return ""


## Remember character `id` as hostile for reason `why`.
func _mark(id: int, why: String, memory: RefCounted) -> void:
	memory.remember(&"hostile", { "id": id, "reason": why }, ttl)
