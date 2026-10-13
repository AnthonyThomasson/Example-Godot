extends GameTest

## Desired (docs/gaze-and-fire.md W4): an NPC that was never given an aim looks where its body points, not at the world's
## origin. Outside the house there is no room and so no doorway to watch, which leaves a resting NPC's gaze as it is: an
## invader standing in the garden with every decision failing (server down), facing south, must still face south a second
## later, and not have swung round to the world's origin.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Gaze := preload("res://tests/_ai/gaze_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A fresh NPC outdoors keeps the way it faces",
		"description": "Server down, an invader in the garden with no aim set faces south; a second later it still does.",
		"tags": ["ai", "gaze", "scripted", "fallback"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.actor(&"npc", &"invader", Maps.GARDEN, { "facing": Vector2.DOWN })


func run(t: TestContext) -> void:
	await t.seconds(1.0)
	var npc := t.actor(&"npc")
	t.check(Gaze.off(npc, npc.global_position + Vector2.DOWN) < 10.0,
		"it still faces south (%.0f deg off)" % Gaze.off(npc, npc.global_position + Vector2.DOWN))
