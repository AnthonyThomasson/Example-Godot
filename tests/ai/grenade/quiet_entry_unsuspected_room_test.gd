extends GameTest

## G18, the control: the same stack of two invaders, both carrying a stun, at the same back door, but nothing says anyone is in the
## kitchen (no gunfire, nobody there). The quiet ENTER is the pick, the stack goes in without a bang and no grenade is thrown. The whole
## pipeline runs with real Von; a `require` that the AI took ENTER comes first.
##
## Premise: both invaders are armed with a stun here because the test world keeps the default inventory, the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const IDS := [&"a", &"b"]


func describe() -> Dictionary:
	return {
		"name": "A stack with a stun enters quietly where nothing is suspected",
		"description": "Two invaders with a stun at the kitchen's back door and no reason to suspect the room take ENTER, go in and clear it without throwing anything.",
		"tags": ["ai", "grenade", "entry", "von"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(985, 110))


func run(t: TestContext) -> void:
	for id in IDS:
		Probe.arm(t.actor(id), 1, 0)
	if not t.require(IDS.all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 1), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	var seen := { &"a": [], &"b": [] }
	var end := t.time + 100.0
	while t.time < end and Entry.calls(t, "clear").is_empty():
		for id in IDS:
			var act := str(Entry.brain(t, id).current_act())
			if not seen[id].has(act):
				seen[id].append(act)
		await t.frames(1)
	var entered := IDS.any(func(id): return seen[id].any(func(a): return a.contains("enter")))
	if not t.require(entered, "the AI took the quiet ENTER (acts: %s)" % str(seen)):
		return
	t.check(not IDS.any(func(id): return seen[id].any(func(a): return a.contains("stun_entry"))), "and never STUN ENTRY (acts: %s)" % str(seen))
	t.check(not Entry.calls(t, "going_in").is_empty(), "the stack went in")
	t.check(Entry.calls(t, "bang").is_empty(), "with no bang on the radio")
	t.check(not t.happened(&"throw") and Probe.booms(t).is_empty(), "and nothing was thrown")
