extends GameTest

## Interface 9: `NavBuilder.steering_map(planning_map)` names the steering map as soon as `build` has returned, before the
## map has synchronized. Main bakes a match's navmesh and drops the NPCs in within the same frame, and each NPC's
## locomotion asks for the steering map as it is set up; a map named only after its first sync left every NPC of a match
## on the plain map for good (issue #53: an AI stopped short of a body at rest it could have walked round, and waited).
## Until the map has synchronized `NavBuilder.ready` says so, and that is the only rule for "not yet".
##
## The house is built in a world of its own (a `SubViewport` with a fresh `World2D`), so its maps are new, as a match's are.


func describe() -> Dictionary:
	return {
		"name": "The steering map is named as soon as the navmesh is built",
		"description": "In a fresh world, NavBuilder.steering_map names the steering map right after build (not ready yet), and the map is ready a few frames later.",
		"tags": ["navigation", "bake", "character"],
		"timeout": 10.0,
	}


func run(t: TestContext) -> void:
	var viewport := SubViewport.new()
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.world.add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	var house := WorldGen.generate(5, "", Vector2.ZERO, world)
	var rooms := WorldGen.get_rooms(house)
	NavBuilder.build(house, rooms, world)
	var planning := world.get_world_2d().navigation_map
	var steering := NavBuilder.steering_map(planning)
	t.check(steering.is_valid(), "the steering map is named in the frame the navmesh is built")
	t.check(steering != planning, "and it is not the world's own map")
	t.check(not NavBuilder.ready(steering), "it is not ready before it has synchronized")
	t.check(await t.until(func(): return NavBuilder.ready(NavBuilder.steering_map(planning)), 3.0), "it is ready once it has synchronized")
	t.expect_eq(NavBuilder.steering_map(planning), steering, "the name does not change when the map synchronizes")
