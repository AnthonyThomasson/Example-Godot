extends GameTest

## Desired (E8, E7): alone, once the invader has cleared the kitchen it does not walk off at once: from inside the kitchen
## it points its gun through each of the kitchen's doorways on into rooms nobody has cleared, the living room's and the
## hall's, before it moves on to its next entry.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Solo entry looks through the doorways on",
		"description": "Alone, after clearing the kitchen the invader looks through the living room and the hall doorways before it moves on.",
		"tags": ["ai", "entry", "scripted"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))


## The sim time of the first entry claim actor `id` radioed after `after` for a doorway other than `except`, or INF.
func _next_claim(t: TestContext, id: StringName, after: float, except: String) -> float:
	var who := t.actor(id)
	for e in t.events:
		if e["topic"] == &"callout" and e["time"] > after and e["data"].get("speaker") == who \
				and String(e["data"].get("entry_step", "")) == "claim" and String(e["data"].get("opening", "")) != except:
			return e["time"]
	return INF


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var cleared := func(): return not Entry.calls(t, "clear", &"inv").is_empty()
	await Entry.watch(t, [&"inv"], door, 60.0, cleared)
	if not t.require(cleared.call(), "the invader cleared the kitchen (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var cleared_at := Entry.first_call_time(t, "clear", &"inv")
	var samples := await Entry.watch(t, [&"inv"], door, 12.0, func(): return _next_claim(t, &"inv", cleared_at, door["id"]) < INF)
	var moved_on := _next_claim(t, &"inv", cleared_at, door["id"])
	t.check(moved_on < INF, "it moved on to its next entry (act %s)" % Entry.brain(t, &"inv").current_act())
	var before := samples.filter(func(sample): return sample["t"] < moved_on)
	var in_kitchen := func(p: Vector2): return Maps.HOUSE_KITCHEN.has_point(p)
	for d in [Entry.KITCHEN_LIVING, Entry.KITCHEN_HALL]:
		var held := Entry.time_facing_through(before, &"inv", d, in_kitchen)
		t.check(held >= 0.5, "before moving on it pointed its gun through %s from the kitchen (%.2f s)" % [d["id"], held])
