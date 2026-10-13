extends GameTest

## Desired (E9, the exemption): a retreat does not stop to stack. The invader, in the hall, sees a defender in the living
## room through its door and falls back to the kitchen, by whichever way is shorter (through the hall's door or through the
## living room). None of those rooms is cleared, but a retreating NPC has no time to stack, so it crosses with no entry.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(150, 440)    # in the hall, south of the living room's door
const TARGET := Vector2(150, 200)   # in the living room, in line with that door


func describe() -> Dictionary:
	return {
		"name": "Entry guard stands down for a retreat",
		"description": "Falling back from a defender seen through the living room door, the invader reaches the unsearched kitchen without stacking at any door.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "retreat", "fall_kitchen"])
	Entry.npc(s, &"inv", START, 0.4, {}, { "facing": Vector2.UP })
	s.set_props(&"inv", "GoalController", { "familiar_with_house": true })
	Entry.target(s, &"tgt", TARGET, Vector2(150, 0))


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var in_kitchen := func(): return Maps.HOUSE_KITCHEN.grow(-30).has_point(inv.global_position)
	if not t.require(await t.until(in_kitchen, 30.0), "the invader fell back into the kitchen (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.asked(t, "fall_kitchen"), "the order was a plain retreat to the kitchen")
	t.check(Entry.first_call_time(t, "claim", &"inv") == INF, "it claimed no stack at any doorway on the way")
