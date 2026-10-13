extends GameTest

## Desired (B4): one flanker per side, and no more flankers than sides. Four invaders face one target across
## the warehouse: three take left, right and rear (one each, claimed over the radio), and the fourth finds
## every side taken and fights directly. Route safety is off (`route_clearance` 0) because the rear route
## runs straight through the target; the flank_rear_route_crosses_target test covers that rule.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const TARGET_POS := Vector2(620, 330)
const LOOK := Vector2(250, 400)


func describe() -> Dictionary:
	return {
		"name": "Four invaders exhaust the three flank sides",
		"description": "In the warehouse left, right and rear are each claimed by one invader; the fourth is offered no flank.",
		"tags": ["ai", "flank", "callout", "scripted"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	Flank.rules(s)
	var cadence := [0.4, 0.55, 0.7, 0.85]
	for i in cadence.size():
		var c: float = cadence[i]
		Flank.npc(s, StringName("npc%d" % i), Vector2(250, 320 + 60 * i),
				{ "route_clearance": 0.0, "max_commit_time": c, "tactic_interval": c, "decide_interval": c,
				# Held in place with the target in plain view they shoot all they can: a slow trigger keeps the magazines from
				# running dry, which would take flank off the menu.
				"fire_cooldown": 2.0 }, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, LOOK)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(LOOK)
	await t.seconds(6.0)
	var sides: Array = []
	var unflanked := 0
	for i in 4:
		var brain := t.controller(StringName("npc%d" % i), &"current_act")
		var side := Flank.side_of_act(brain)
		if side == "":
			unflanked += 1
		else:
			sides.append(side)
	sides.sort()
	t.expect_eq(sides, ["left", "rear", "right"], "three invaders hold three different sides")
	t.expect_eq(unflanked, 1, "one invader has no flank left")
