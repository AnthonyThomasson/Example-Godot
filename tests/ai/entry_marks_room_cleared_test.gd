extends GameTest

## Desired (E8): once an invader has cleared the kitchen it radios it clear, and the room counts as searched, both for
## itself and for an ally that stayed outside and only heard the call.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry marks the room cleared",
		"description": "After clearing the kitchen the invader radios it clear; it and a listening ally regard it as searched.",
		"tags": ["ai", "entry", "scripted", "gap", "callout"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))
	# Listens on the radio from the garden, never enters.
	Entry.npc(s, &"ally", Vector2(980, 560), 0.4, { "entry_enabled": false }, { "speed": 0.0 })


func run(t: TestContext) -> void:
	var cleared := func(): return not Entry.calls(t, "clear", &"inv").is_empty()
	await Entry.watch(t, [&"inv"], Entry.BACK, 65.0, cleared)
	if not t.require(cleared.call(), "the invader radioed the room clear (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.expect_eq(String(Entry.calls(t, "clear", &"inv")[0].get("cleared_room", "")), "kitchen", "the call names the kitchen")
	await t.frames(2)
	var mine := Entry.room_status(t, &"inv", Maps.HOUSE_KITCHEN)
	t.check(mine in ["current", "searched"], "the invader regards the kitchen as searched (%s)" % mine)
	t.expect_eq(Entry.room_status(t, &"ally", Maps.HOUSE_KITCHEN), "searched", "the ally that heard the call does too")
