extends GameTest

## E17 extended (issue #51, R8): once its own or a teammate's stun or frag bursts in a room, the entry into it skips the pie and
## crosses at once (and E14's hold is lifted for `BANG_WINDOW`, 3 s). A householder holds the kitchen's back doorway from 110 px inside it,
## facing out, in the line of fire of an invader in the garden (the scene of `grenade_door_holder`, where Von takes GRENADE against a defender
## barricaded in a room, G17 / R7); the invader carries a stun, takes GRENADE and stuns it, then goes in after it (G17: a blinded hostile is
## the moment to close in). The entry it goes in by never slices the pie: from its slot it crosses at once. The whole pipeline runs with real
## Von; `require`s that the invader took GRENADE, that its own stun went off in the kitchen and that it then went in by the back door come
## first, so a fight kept up from outside reads as a set-up finding.
##
## Premises: the householder is a puppet that cannot be killed and never shoots (a defender that stands its ground in the doorway whatever
## is fired at it); the invader is armed with one stun at the start of `run`, the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const INVADER_AT := Vector2(980, 80)
const HOSTILE_AT := Vector2(730, 190)
## From the stack slot to the crossing: "at once" is under this many seconds.
const AT_ONCE := 1.0


func describe() -> Dictionary:
	return {
		"name": "After a burst in the room the entry crosses at once, without the pie",
		"description": "An invader stuns a householder holding the kitchen's back doorway, then goes in by the back door: its entry skips the pie and crosses from its slot at once.",
		"tags": ["ai", "grenade", "entry", "stun", "von"],
		"requires_von": true,
		"timeout": 100.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"i", &"invader", INVADER_AT, { "facing": (HOSTILE_AT - INVADER_AT).normalized() })
	Probe.hostile(s, &"h", HOSTILE_AT, Maps.DOOR_BACK + Vector2(200, 0))


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 0)
	if not t.require(Probe.count(inv, Probe.STUN) == 1, "the invader carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(inv, Probe.STUN)):
		return
	var brain := Entry.brain(t, &"i")
	var seen: Array = []
	var phases: Array = []
	var went_in := func() -> bool:
		var act := str(brain.current_act())
		if not seen.has(act):
			seen.append(act)
		phases.append([t.time, str(Entry.entry(brain).get("phase", ""))])
		var stuns := Probe.booms(t, &"stun")
		var burst := float(stuns[0]["time"]) if not stuns.is_empty() else INF
		var crossed := Entry.first_call_time(t, "going_in", &"i", door["id"])
		return burst < INF and crossed > burst and crossed < INF
	await t.until(went_in, 80.0)
	if not t.require(seen.any(func(a): return str(a).contains("/grenade/")), "the invader took GRENADE (acts %s)" % str(seen)):
		return
	var booms := Probe.booms(t, &"stun").filter(func(b): return b["data"].get("attacker") == inv)
	if not t.require(not booms.is_empty() and Maps.HOUSE_KITCHEN.has_point(booms[0]["data"]["position"]), "the invader's own stun went off in the kitchen (acts %s)" % str(seen)):
		return
	var boom := float(booms[0]["time"])
	var going := INF
	for c in Probe.raw(t, &"callout", func(d): return d.get("speaker") == inv and String(d.get("entry_step", "")) == "going_in" and String(d.get("opening", "")) == door["id"]):
		if float(c["time"]) > boom:
			going = float(c["time"])
			break
	if not t.require(going < INF, "after the burst it went in by the back door (acts %s)" % str(seen)):
		return
	var between := phases.filter(func(p): return float(p[0]) >= boom and float(p[0]) <= going)
	t.check(not between.any(func(p): return p[1] == "pie"), "its entry after the burst never sliced the pie (phases %s)" % str(_runs(between)))
	var slot_at := INF
	for p in between:
		if p[1] == "stack" or p[1] == "pie" or p[1] == "cross":
			slot_at = float(p[0])
			break
	t.check(going - slot_at < AT_ONCE, "it crossed from its slot at once (%.2f s from the slot to going_in, the burst at %.2f s)" % [going - slot_at, boom])


## The runs of `[time, phase]` samples as `[phase, from]` pairs, for messages.
func _runs(samples: Array) -> Array:
	var out: Array = []
	for p in samples:
		if out.is_empty() or out.back()[0] != p[1]:
			out.append([p[1], snappedf(float(p[0]), 0.1)])
	return out
