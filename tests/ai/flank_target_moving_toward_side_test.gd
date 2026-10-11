extends GameTest

## Desired (B7): do not step into the side the target is walking toward. The target strides north across a
## warehouse; the NPC to the west is told its north side is 'moving toward that side' (it would be walking
## into the target's path) and is not offered it, while the side the target is moving away from is.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_START := Vector2(620, 500)


func describe() -> Dictionary:
	return {
		"name": "A flank side the target is walking toward is not offered",
		"description": "The target walks north across the warehouse; its north side reads 'they are moving toward that side' and is not offered, while the east side is.",
		"tags": ["ai", "flank", "scripted", "gap"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s, false)
	s.object(&"shelf_nw", "shelving", Vector2(200, 150))     # cover away from the walk
	s.object(&"bench_sw", "workbench", Vector2(200, 610))
	s.object(&"island_e", "island", Vector2(900, 400))
	s.object(&"pillar_w", Maps.PILLAR, Vector2(330, 330))
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_START)
	Flank.target(s, &"target", TARGET_START, NPC_POS, { "speed": 70.0 })


func run(t: TestContext) -> void:
	var target := t.puppet(&"target")
	target.aim_at(NPC_POS)   # keeps facing the NPC, so north stays its right side as it walks
	target.walk(Vector2.UP)
	var brain := t.controller(&"npc", &"current_act")
	var heading := func():
		var z := Flank.zones(brain)
		return z.has("right") and String(z["right"]["desc"]).contains("moving toward that side")
	if not t.require(await t.until(heading, 8.0), "the NPC notices the target walking toward its north side (%s)" % Flank.dump(brain)):
		return
	await t.seconds(1.0)   # a full decision after the flag is up
	var zones := Flank.zones(brain)
	var sides := Flank.offered_sides(brain)
	t.check(zones.has("right") and String(zones["right"]["desc"]).contains("moving toward that side"), "the north side is still flagged (%s)" % Flank.dump(brain))
	t.check(not sides.has("right"), "the side the target is walking into is not offered (%s)" % [sides])
	t.check(sides.has("left"), "the south side, behind the target's path, is (%s)" % [sides])
