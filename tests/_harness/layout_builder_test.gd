extends GameTest

## Harness self-test: `TestSetup.layout` lays out walled rooms joined by doorways. The world is live (walls
## solid, navmesh baked) when the test starts, the rooms and openings metas are set, a wall stops a straight
## line between rooms, the navmesh routes through the doorway (and only through it), and a piece of
## furniture is carved out of the walkable area.

const WEST := Rect2(0, 0, 300, 300)
const EAST := Rect2(300, 0, 300, 300)
const DOOR := Vector2(300, 220)


func describe() -> Dictionary:
	return { "name": "Layout builder rooms, doors and nav", "tags": ["harness", "layout", "world"], "internal": true, "timeout": 5.0 }


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "west", "type": "living_room", "rect": WEST }, { "key": "east", "type": "kitchen", "rect": EAST }],
		[{ "pos": DOOR, "width": 80.0 }])
	s.object(&"crate", "coffee_table", Vector2(150, 150))


func run(t: TestContext) -> void:
	# The world is stepped before the test starts, so its walls are already solid and its navmesh live.
	var first := t.world.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(200, 60), Vector2(400, 60)))
	t.check(not first.is_empty(), "the shared wall is solid on the test's first frame")
	t.check(NavigationServer2D.map_get_iteration_id(t.world.get_world_2d().navigation_map) > 0, "and the navmesh is live")
	await t.seconds(0.5)
	t.expect_eq(t.rooms.size(), 2, "both rooms are registered")
	var openings := WorldGen.get_openings(t.world.house)
	if t.require(openings.size() == 1, "the doorway is registered"):
		t.expect_eq(openings[0]["rooms"].size(), 2, "it joins the two rooms")
		t.expect_eq(openings[0]["front"], false, "and is not an entrance")

	var space := t.world.get_world_2d().direct_space_state
	var wall_hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(200, 60), Vector2(400, 60)))
	t.check(not wall_hit.is_empty(), "the shared wall stops a line between the rooms")
	var door_hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(200, DOOR.y), Vector2(400, DOOR.y)))
	t.check(door_hit.is_empty(), "the doorway lets the same line through")

	var map := t.world.get_world_2d().navigation_map
	var from := Vector2(100, 60)
	var to := Vector2(500, 60)
	var path := NavigationServer2D.map_get_path(map, from, to, true)
	t.check(path.size() >= 3, "a path between the rooms exists (%d points)" % path.size())
	var passes_door := false
	for i in range(1, path.size()):
		if absf(path[i - 1].x - 300.0) < 40.0 or (path[i - 1].x < 300.0) != (path[i].x < 300.0):
			var crossing_y: float = path[i].y if absf(path[i].x - 300.0) < 40.0 else path[i - 1].y
			passes_door = passes_door or absf(crossing_y - DOOR.y) <= 50.0
	t.check(passes_door, "that path crosses the shared wall at the doorway")

	var around := NavigationServer2D.map_get_path(map, Vector2(60, 150), Vector2(240, 150), true)
	var length := 0.0
	for i in range(1, around.size()):
		length += around[i - 1].distance_to(around[i])
	t.check(length > 200.0, "the table is a hole in the navmesh: the path round it is longer than the straight 180 px (%.0f)" % length)
