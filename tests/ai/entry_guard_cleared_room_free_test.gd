extends GameTest

## Desired (E9): a room that is already cleared needs no entry. An ally radios the kitchen clear, so an invader sent from
## the back garden to the living room walks through the back door and the kitchen as it likes, and only stacks at the
## kitchen's door into the living room, which nobody has cleared.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(990, 600)   # far south-east in the garden: the radio call is long since heard when it nears a door


func describe() -> Dictionary:
	return {
		"name": "Entry guard leaves a cleared room alone",
		"description": "With the kitchen radioed clear, the invader sent to the living room crosses the back door with no entry and enters the living room by entry.",
		"tags": ["ai", "entry", "guard", "scripted", "callout"],
		"timeout": 110.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["room_living_room"])
	Entry.npc(s, &"inv", START)
	s.set_props(&"inv", "GoalController", { "familiar_with_house": true })
	# An ally beside it that has cleared the kitchen; it plays no part otherwise.
	Entry.npc(s, &"ally", START + Vector2(30, 0), 0.4, { "entry_enabled": false }, { "speed": 0.0 })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var ally := t.actor(&"ally")
	EventBus.post(&"callout", {
		"speaker": ally, "faction": ally.faction, "position": ally.global_position, "status": "", "path": "",
		"label": "", "target_id": 0, "point": ally.global_position, "entry_step": "clear", "opening": Entry.BACK["id"],
		"cleared_room": "kitchen",
	})
	var in_goal := func(): return Maps.HOUSE_LIVING.grow(-30).has_point(inv.global_position)
	var samples: Array = await Entry.watch(t, [&"inv"], Entry.KITCHEN_LIVING, 100.0, in_goal)
	if not t.require(in_goal.call(), "the invader reached the living room (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.first_call_time(t, "claim", &"inv", Entry.BACK["id"]) == INF, "it claimed no stack at the back door: the kitchen is cleared")
	Entry.check_entered(t, samples, &"inv", Entry.KITCHEN_LIVING)
