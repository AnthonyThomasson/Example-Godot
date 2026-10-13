extends RefCounted

## Shared helpers for the tests of the bang entry's fallbacks (tests/ai/grenade/bang_fallback_*; not a test itself). The behaviour they assert is
## `docs/grenades.md` G18 / `docs/tactical-entry.md` E17: a stack in bang mode goes in quietly when no bang can be had. Scripted Von, so each test
## is one mechanism: a stack of two invaders at the Terrace house's back door, the kitchen behind it, Von picking SEARCH > STUN ENTRY > that doorway.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const IDS := [&"a", &"b"]
const A_AT := Vector2(960, 60)
const B_AT := Vector2(985, 110)


## Scripted Von for a stun entry through the back door, and the shared switches. Call it after the map.
static func rules(s: TestSetup) -> void:
	s.von_script([{ "pick": "search" }, { "pick": "stun_entry" }, { "pick": Entry.BACK["id"] }, { "pick": "engage" }])
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)


## The two invaders of the stack, outside the back door.
static func stack(s: TestSetup) -> void:
	s.actor(&"a", &"invader", A_AT)
	s.actor(&"b", &"invader", B_AT)


## Arm each invader of `ids` with one stun, the way Main arms a spawn (a test world keeps the default inventory).
static func arm(t: TestContext, ids: Array) -> bool:
	for id in ids:
		Probe.arm(t.actor(id), 1, 0)
	return ids.all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 1)


## A teammate that is a puppet (an invader that is not an AI) radios its part of the stack the way an AI member does: slot 2 at the back door on
## `side`, carrying one stun, in bang mode, at entry step `step`.
static func radio_mate(t: TestContext, who: StringName, side: int, step: String) -> void:
	var c := t.actor(who)
	EventBus.post(&"callout", {
		"speaker": c, "faction": c.faction, "position": c.global_position, "status": "", "path": "", "label": "", "target_id": 0, "point": Vector2.ZERO,
		"opening": Entry.BACK["id"], "slot": 2, "side": side, "entry_step": step, "bang": true, "stuns": 1,
	})


## Whether any of the acts collected in `seen` (per actor, see `note_acts`) has a path containing `needle`.
static func took(seen: Dictionary, needle: String) -> bool:
	return seen.values().any(func(acts): return acts.any(func(a): return a.contains(needle)))


## Collect the distinct act each actor of `seen` is carrying out into its list.
static func note_acts(t: TestContext, seen: Dictionary) -> void:
	for id in seen:
		var act := str(Entry.brain(t, id).current_act())
		if not seen[id].has(act):
			seen[id].append(act)
