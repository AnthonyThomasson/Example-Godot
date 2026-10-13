extends GameTest

## Desired (E3 "what it sees from outside it engages from outside", docs/gaze-and-fire.md W2): an invader stacking at a
## doorway with a hostile in plain view through it shoots, whatever the phase. Rushing a target seen through the back door
## puts the invader into an entry detour (approach, stack, pie) with the order to fight stashed behind the stack; from the
## first claim on the radio until it goes in, it must fire from outside the doorway all the same.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(990, 190)    # in the back garden, in line with the door
const TARGET := Vector2(620, 190)   # in the kitchen, in line with the door


func describe() -> Dictionary:
	return {
		"name": "An invader at the stack fires at what it sees through the door",
		"description": "Ordered to rush a target seen through the back door, the invader shoots it from outside the doorway between its stack claim and going in.",
		"tags": ["ai", "gaze", "entry", "scripted", "combat"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "advance", "rush"])
	Entry.npc(s, &"inv", START, 0.4, {}, { "facing": Vector2.LEFT })
	Entry.target(s, &"tgt", TARGET, Vector2(0, 190))


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var through := func(): return Entry.first_call_time(t, "going_in", &"inv", Entry.BACK["id"]) < INF
	await Entry.watch(t, [&"inv"], Entry.BACK, 55.0, through)
	if not t.require(through.call(), "the invader went in by the back door (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var claimed := Entry.first_call_time(t, "claim", &"inv", Entry.BACK["id"])
	var going := Entry.first_call_time(t, "going_in", &"inv", Entry.BACK["id"])
	var shot_at_door := func(e):
		return e["topic"] == &"shot" and e["data"].get("attacker") == inv and e["time"] > claimed and e["time"] < going \
			and Entry.outward(Entry.BACK, e["data"]["position"]) > 0.0
	t.check(t.events.any(shot_at_door), "it fired from outside the doorway between its claim (%.1f s) and going in (%.1f s)" % [claimed, going])
