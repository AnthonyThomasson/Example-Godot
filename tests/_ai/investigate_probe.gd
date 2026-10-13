extends RefCounted

## Shared helpers for the investigation tests (tests/ai/investigate/; not a test itself):
## the terrace house with one NPC in the hall, gunfire heard from a chosen spot, and reads of what the NPC's
## last decision walk offered. Observes the NPC through `debug_state()` only.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(420, 415)         # the middle of the hall, in line with the open front door
const OUTSIDE := Maps.GARDEN               # out in the garden beyond the front door
const INSIDE := Maps.KITCHEN_CENTRE        # inside the house, in the kitchen
const OUTSIDE_X := -25.0                   # west of this, an NPC has left the house by the front door


## The bare terrace house with one NPC (`kind`: `defender` / `invader`) in the hall. Trespass hostility and
## the radio are off so only the heard gunfire acts on it; Von is NOT scripted (the caller decides).
static func world(s: TestSetup, kind: StringName) -> void:
	Maps.house(s, false)
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"npc", kind, NPC_POS, { "facing": Vector2.LEFT })


## Gunfire from `at`, nobody the NPC knows: the shot lands there and the NPC hears it.
static func gunfire(at: Vector2) -> void:
	EventBus.post(&"hit", { "position": at, "direction": Vector2.LEFT, "damage": 10.0, "attacker": null, "victim": null })


## The levels of the NPC's last decision walk.
static func levels(brain: Node) -> Array:
	return brain.debug_state().get("decision", {}).get("levels", [])


## Whether the last walk offered INVESTIGATE at some level and Von was really asked there (not taken
## without asking because it was the lone option).
static func asked_about_investigating(brain: Node) -> bool:
	for l in levels(brain):
		if (l.get("offered", {}) as Dictionary).has("investigate") and not l.get("auto", false):
			return true
	return false
