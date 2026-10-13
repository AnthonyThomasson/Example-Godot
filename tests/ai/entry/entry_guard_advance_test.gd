extends GameTest

## Desired (E9): closing in on a hostile in the next room is no excuse to skip the entry. The invader sees a household
## target through the kitchen's back door and is ordered to rush it; the straight route is through that doorway, so it
## stacks beside it and slices the pie first, and it does not run from the moment it turns to the door. The target can be
## killed (E14: nobody crosses while a hostile stands in view with a line of fire, so the invader shoots it from outside
## first and goes in once it is down).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(990, 190)    # in the back garden, in line with the door
const TARGET := Vector2(620, 190)   # in the kitchen, in line with the door


func describe() -> Dictionary:
	return {
		"name": "Entry guard on an advance order",
		"description": "Ordered to rush a target seen through the back door, the invader stacks and slices at the door before it crosses, and never runs once it turns to it.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "advance", "rush"])
	Entry.npc(s, &"inv", START, 0.4, {}, { "facing": Vector2.LEFT })
	Entry.target(s, &"tgt", TARGET, Vector2(0, 190), { "max_health": 30.0 })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var ran := [0.0]
	var in_kitchen := func():
		var claimed := Entry.first_call_time(t, "claim", &"inv", Entry.BACK["id"])
		if claimed < INF and t.time > claimed + 0.3 and inv.is_running():
			ran[0] += 1.0 / 60.0
		return Maps.HOUSE_KITCHEN.grow(-30).has_point(inv.global_position)
	var samples: Array = await Entry.watch(t, [&"inv"], Entry.BACK, 55.0, in_kitchen)
	if not t.require(in_kitchen.call(), "the invader reached the kitchen (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.asked(t, "rush"), "the order was a plain rush on the target, not ENTER")
	var died := t.events.filter(func(e): return e["topic"] == &"died" and e["data"].get("actor") == &"tgt")
	var going := Entry.first_call_time(t, "going_in", &"inv", Entry.BACK["id"])
	if t.check(not died.is_empty(), "the target was shot dead"):
		t.check(died[0]["time"] <= going, "the target was down (%.1f s) before the invader crossed (%.1f s)" % [died[0]["time"], going])
	var from_outside := func(e):
		return e["topic"] == &"shot" and e["data"].get("attacker") == inv and e["time"] < going and Entry.outward(Entry.BACK, e["data"]["position"]) > 0.0
	t.check(t.events.any(from_outside), "it shot at the target from outside the doorway before it went in")
	Entry.check_entered(t, samples, &"inv", Entry.BACK)
	t.check(ran[0] == 0.0, "it did not run once it had turned to the door (ran for %.2f s)" % ran[0])
