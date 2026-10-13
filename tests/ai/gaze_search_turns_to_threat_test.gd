extends GameTest

## Desired (docs/gaze-and-fire.md W1, W2): a known hostile in view takes the NPC's eyes and gun whatever it is doing. An
## invader sent to search the living room covers it by sight once it arrives, turning its gaze to the nearest corner it
## has not seen and ignoring everything else for up to 8 s; a Von that answers slowly (each answer held back 1.5 s)
## leaves it in that coverage a good while after the defender in the corner came into view. It must keep its eyes on the
## defender and shoot it, not look away at the empty floor.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Gaze := preload("res://tests/_ai/gaze_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")

const DEFENDER_AT := Vector2(60, 60)


func describe() -> Dictionary:
	return {
		"name": "A searcher covering a room keeps its eyes and gun on a hostile",
		"description": "An invader covering the living room by sight, its next decision still in flight, faces and shoots the defender it can see in the corner.",
		"tags": ["ai", "gaze", "search", "scripted", "combat"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "room_living_room" }, { "pick": "engage" }], 90)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.switch(&"ai.entry", false)  # a plain walk in: the stack at the door is not what is tested here
	Entry.npc(s, &"inv", Maps.HALL_MIDDLE, 0.4, { "familiar_with_house": true })
	Entry.target(s, &"defender", DEFENDER_AT, Maps.LIVING_CENTRE)


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := t.controller(&"inv", &"debug_state")
	var covering := func():
		var d: Dictionary = brain.debug_state()
		return d.get("primitive") == "move" and d.get("arrived", false) and d.get("params", {}).get("look_around", false) \
			and int(d.get("hostiles_known", 0)) > 0
	if not t.require(await t.until(covering, 50.0), "the invader is covering the living room with the defender known (act %s)" % brain.debug_state().get("act")):
		return
	var from := t.time
	var samples := await Gaze.watch(t, [&"inv"], 1.5)
	var share := Gaze.share_facing(samples, &"inv", [DEFENDER_AT], 20.0)
	t.trace("facing_defender", share)
	t.check(brain.debug_state().get("primitive") == "move", "the coverage was still the running order (no new decision yet)")
	t.check(share >= 0.8, "it keeps its eyes on the defender at least 80%% of the time (%.0f%%)" % (share * 100.0))
	var shot := func(e): return e["topic"] == &"shot" and e["data"].get("attacker") == inv and e["time"] >= from
	t.check(t.events.any(shot), "it shoots the defender while it covers the room")
