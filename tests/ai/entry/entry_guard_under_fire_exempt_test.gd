extends GameTest

## Desired (E9, the exemption as amended by issue #51 R10): an NPC that is being shot at from anywhere but the room ahead does not stop
## to stack. The invader is ordered to rush a householder in the kitchen; a household shooter behind it in the back garden, out of its
## sight, fires on it. It may start to stack before the first round lands, but once it is hit it gives the entry up (radios abort) and
## goes straight through, never crossing as an entry. (Shot at from the kitchen itself, it goes in only by entry:
## `entry_guard_shot_from_room_ahead`.)
##
## Premises: both householders are puppets that cannot be killed, the one in the kitchen never shoots; the invader cannot be killed
## either; Von is scripted to the rush (`Entry.guard_rules`). The shooter stands behind the invader, farther than its awareness and
## outside its view cone, so the round comes from a stranger in the garden, not from the room it is ordered into.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(990, 190)
const TARGET := Vector2(620, 190)
const SHOOTER := Vector2(1260, 190)


func describe() -> Dictionary:
	return {
		"name": "Entry guard stands down under fire from elsewhere",
		"description": "Shot at from behind, in the garden, while ordered to rush the kitchen, the invader goes through the back door without stacking.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "advance", "rush"])
	Entry.npc(s, &"inv", START, 0.4, {}, { "facing": Vector2.LEFT })
	Entry.target(s, &"householder", TARGET, START, { "faction": &"household" })
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
	t.check(Entry.first_call_time(t, "going_in", &"inv") == INF, "it did not cross as an entry: under fire from elsewhere it does not stop at the door")
