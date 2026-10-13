extends GameTest

## Desired (E9, the exemption): an NPC that is being shot at does not stop to stack. A household shooter fires on the
## invader from the kitchen through the back door while it is ordered to rush it. It may start to stack before the first
## round lands, but once it is hit it gives the entry up (radios abort) and goes straight through, never crossing as an
## entry.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(990, 190)
const SHOOTER := Vector2(620, 190)


func describe() -> Dictionary:
	return {
		"name": "Entry guard stands down under fire",
		"description": "Shot at from the kitchen while ordered to rush it, the invader goes through the back door without stacking.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "advance", "rush"])
	Entry.npc(s, &"inv", START, 0.4, {}, { "facing": Vector2.LEFT })
	Entry.target(s, &"shooter", SHOOTER, START, { "start_slot": 3, "faction": &"household" })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var shooter := t.puppet(&"shooter")
	var in_kitchen := func():
		shooter.aim_at(inv)
		shooter.shoot()
		return Maps.HOUSE_KITCHEN.grow(-30).has_point(inv.global_position)
	if not t.require(await t.until(in_kitchen, 30.0), "the invader reached the kitchen (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(inv.damage_taken() > 0.0, "it was under fire on the way")
	t.check(Entry.first_call_time(t, "going_in", &"inv") == INF, "it did not cross as an entry: under fire it does not stop at the door")
	if Entry.first_call_time(t, "claim", &"inv") < INF:
		t.check(Entry.first_call_time(t, "abort", &"inv") < INF, "an entry it began was given up when it came under fire")
