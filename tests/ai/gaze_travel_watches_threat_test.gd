extends GameTest

## Desired (docs/gaze-and-fire.md W1): an NPC that walks somewhere with a hostile known does not turn its back on it. An
## invader sent off to the living room by a door at its back keeps facing the hostile at the far end of the hall as it
## walks. The hostile is out of shooting range, so this is gaze, not gunnery.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Gaze := preload("res://tests/_ai/gaze_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")

const START := Vector2(260, 440)
const HOSTILE_AT := Vector2(800, 415)


func describe() -> Dictionary:
	return {
		"name": "A walking NPC keeps facing a known hostile",
		"description": "An invader sent to the living room through a door behind it keeps facing the defender at the far end of the hall (beyond shooting range) while it walks.",
		"tags": ["ai", "gaze", "scripted", "move"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "idle" }, { "pick": "go" }, { "pick": "room_living_room" }])
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.switch(&"ai.entry", false)  # a plain walk to the door: no stack at it
	Entry.npc(s, &"inv", START, 0.4, { "familiar_with_house": true, "pursue_hostiles": false }, { "facing": Vector2.RIGHT, "aim_point": HOSTILE_AT })
	Entry.target(s, &"defender", HOSTILE_AT, START)


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := t.controller(&"inv", &"debug_state")
	var walking := func():
		var d: Dictionary = brain.debug_state()
		return d.get("primitive") == "move" and (inv.get_real_velocity() as Vector2).length() > 50.0 and int(d.get("hostiles_known", 0)) > 0
	if not t.require(await t.until(walking, 10.0), "the invader is walking with the defender known (act %s)" % brain.debug_state().get("act")):
		return
	var samples := await Gaze.watch(t, [&"inv"], 0.8)
	var share := Gaze.share_facing(samples, &"inv", [HOSTILE_AT], 25.0)
	t.trace("facing_hostile", share)
	t.check(share >= 0.8, "it keeps facing the defender while it walks off (%.0f%% of the time)" % (share * 100.0))
