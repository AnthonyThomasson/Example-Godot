extends GameTest

## Desired (E4): nothing stops an entrant in the threshold, not even a decision the planner had already started walking
## before the crossing began. Such a decision arrives while the invader is crossing; it waits (the entry ends in a
## re-decision of its own) instead of replacing the entry, so the invader is not left standing in the doorway.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "A decision in flight does not stop a crossing",
		"description": "A decision handed to the controller while the invader crosses the back door is ignored; it is through, in its corner, and radioed no abort.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := Entry.brain(t, &"inv")
	if not t.require(await t.until(func(): return String(Entry.entry(brain).get("phase", "")) == "cross", 35.0), "the invader began to cross (act %s)" % brain.current_act()):
		return
	# What a planner walk started before the crossing would hand over now: a plain hold.
	brain._on_decided({ "primitive": &"hold", "params": {}, "path": ["idle"], "labels": ["IDLE"] })
	var through := func(): return not Entry.calls(t, "in", &"inv").is_empty()
	if not t.require(await t.until(through, 5.0), "it carried on through the doorway (act %s)" % brain.current_act()):
		return
	t.check(Entry.in_room(Entry.BACK, inv.global_position) or String(Entry.entry(brain).get("phase", "")) != "", "it is in the room, still entering")
	t.expect_eq(Entry.calls(t, "abort", &"inv").size(), 0, "the entry was not given up")
