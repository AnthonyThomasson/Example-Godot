extends GameTest

## Desired (docs/gaze-and-fire.md W4): a walking NPC with nothing to fear looks where it is going, along its path, not at the
## wall the next navmesh waypoint happens to line up with. Steering at the immediate waypoint points the gaze at the door
## jamb and the wall beside a doorway as it turns the corner; it should look a few paces down the path instead, through
## the door. Walking from the hall's middle into the living room through its door, the invader must never have a wall at
## arm's length dead ahead and must keep where it is going inside its own view cone (55 deg either side of its facing,
## the vision default): the spot it will reach 0.7 s later.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Gaze := preload("res://tests/_ai/gaze_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")

const LOOK_AHEAD := 0.7
const MOVING := 100.0
## Half the vision cone (`AgentVision.fov_degrees` / 2): where it is going must stay in view.
const HALF_CONE := 55.0


func describe() -> Dictionary:
	return {
		"name": "A walking NPC looks down its path, not at the wall beside it",
		"description": "An invader walking from the hall into the living room keeps where it will be 0.7 s later inside its view cone and never has a wall dead ahead at 70 px.",
		"tags": ["ai", "gaze", "scripted", "move"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "room_living_room" }])
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"ai.entry", false)  # a plain walk through the door: no stack at it
	Entry.npc(s, &"inv", Maps.HALL_MIDDLE, 0.4, { "familiar_with_house": true }, { "facing": Vector2.LEFT, "aim_point": Maps.HALL_MIDDLE + Vector2.LEFT * 100.0 })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var in_goal := func(): return Maps.HOUSE_LIVING.grow(-60).has_point(inv.global_position)
	var samples := await Gaze.watch(t, [&"inv"], 30.0, in_goal)
	if not t.require(in_goal.call(), "the invader walked into the living room (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var offs: Array = []
	var wall_frames := 0
	for i in samples.size():
		var s: Dictionary = samples[i]
		if float(s["speed"][&"inv"]) < MOVING:
			continue
		if Gaze.wall_ahead(inv, 70.0, s["pos"][&"inv"], s["facing"][&"inv"]):
			wall_frames += 1
		# The test's own copy of "where it will be": the sample LOOK_AHEAD s on.
		for j in range(i, samples.size()):
			if float(samples[j]["t"]) >= float(s["t"]) + LOOK_AHEAD:
				var ahead: Vector2 = samples[j]["pos"][&"inv"]
				offs.append(rad_to_deg(absf((s["facing"][&"inv"] as Vector2).angle_to(ahead - (s["pos"][&"inv"] as Vector2)))))
				break
	if not t.require(offs.size() > 30, "it walked far enough to judge (%d samples)" % offs.size()):
		return
	offs.sort()
	var p95: float = offs[int(offs.size() * 0.95)]
	t.trace("off_p95_deg", p95)
	t.trace("off_max_deg", offs[-1])
	t.check(p95 <= HALF_CONE, "19 frames in 20 it has where it will be %.1f s later inside its view cone (p95 %.0f deg, limit %.0f)" % [LOOK_AHEAD, p95, HALF_CONE])
	t.expect_eq(wall_frames, 0, "no wall dead ahead at 70 px while it walks")
