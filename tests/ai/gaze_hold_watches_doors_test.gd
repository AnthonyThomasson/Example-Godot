extends GameTest

## Desired (docs/gaze-and-fire.md W4): an NPC standing with no threat known watches the doors of its room, rotating among
## them, instead of keeping whatever way it last happened to face (a wall, or the world origin on a fresh NPC). With
## every decision failing (server down) the defender sits in the steady hold; spawned looking at the kitchen's north
## wall it must come round to the kitchen's doorways and keep to them.

const Gaze := preload("res://tests/_ai/gaze_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")

## The kitchen's three doorways (back garden, hall, living room), on the wall centrelines.
const DOORS := [Maps.DOOR_BACK, Maps.DOOR_HALL_KITCHEN, Maps.DOOR_LIVING_KITCHEN]
const START := Vector2(700, 250)


func describe() -> Dictionary:
	return {
		"name": "A standing NPC watches the doors, not a wall",
		"description": "Server down, a defender alone in the kitchen starts facing the north wall: it turns to the doorways and rotates among them for the next 10 s.",
		"tags": ["ai", "gaze", "scripted", "fallback"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"projectile.flyover", false)
	s.actor(&"npc", &"defender", START, { "facing": Vector2.UP, "aim_point": Vector2(START.x, 0.0) })


func run(t: TestContext) -> void:
	var samples := await Gaze.watch(t, [&"npc"], 10.0)
	var share := Gaze.share_facing(samples, &"npc", DOORS, 25.0, 1.5)
	t.trace("door_share", share)
	t.check(share >= 0.8, "after 1.5 s it faces a doorway at least 80%% of the time (%.0f%%)" % (share * 100.0))
	var faced := Gaze.points_faced(samples, &"npc", DOORS, 25.0, 1.5)
	t.check(faced.size() >= 2, "it rotates among the doorways (faced %d distinct)" % faced.size())
