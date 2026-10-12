extends GameTest

## Desired (docs/gaze-and-fire.md W5): a walk that has arrived stops, even with the next decision still in flight (a slow
## Von): it neither keeps walking on into the wall ahead nor stares along its travel vector. Sent to the hall from the
## kitchen with every answer held back 1 s, the defender must stand still once it is in the hall and not face a wall.

const Gaze := preload("res://tests/_ai/gaze_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "A walk that has arrived stops moving",
		"description": "Scripted GO to the hall with each Von answer held back 60 frames: once the move has arrived the defender stands still and is not nose-to-wall while the next decision is in flight.",
		"tags": ["ai", "gaze", "scripted", "move"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "idle" }, { "pick": "go" }, { "pick": "room_hall" }], 60)
	s.switch(&"projectile.flyover", false)
	s.actor(&"npc", &"defender", Vector2(700, 250))
	s.set_props(&"npc", "GoalController", { "pursue_hostiles": false })  # IDLE > GO is only offered to an NPC at rest


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"debug_state")
	var arrived := func():
		var d: Dictionary = brain.debug_state()
		return d.get("primitive") == "move" and d.get("arrived", false)
	if not t.require(await t.until(arrived, 30.0), "the defender walked into the hall (act %s)" % brain.debug_state().get("act")):
		return
	await t.seconds(0.3)  # let it brake
	var settled: Vector2 = npc.global_position
	var top_speed := 0.0
	var wall_frames := 0
	for i in 60:
		await t.frames(1)
		top_speed = maxf(top_speed, (npc.get_real_velocity() as Vector2).length())
		if Gaze.wall_ahead(npc):
			wall_frames += 1
	t.trace("drift", npc.global_position.distance_to(settled))
	t.check(brain.debug_state().get("primitive") == "move", "the next decision was still in flight (the arrived move is still the order)")
	t.check(top_speed < 10.0, "it stands still once it has arrived (%.0f px/s)" % top_speed)
	t.check(npc.global_position.distance_to(settled) < 15.0, "it does not drift on (%.0f px)" % npc.global_position.distance_to(settled))
	t.check(wall_frames == 0, "it is not facing a wall at arm's length (%d frames)" % wall_frames)
