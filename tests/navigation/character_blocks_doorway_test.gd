extends GameTest

## A character standing in a doorway seals it in the steering map, like a piece of furniture does: the room
## beyond is unreachable until the character moves, which is the AI's cue to shove through rather than push
## at a body. The world's own map, which the AI plans with, keeps the doorway open.

const DOOR := Vector2(400, 150)
const FROM := Vector2(100, 150)
const TO := Vector2(700, 150)


func describe() -> Dictionary:
	return {
		"name": "A character in a doorway seals it in the nav map",
		"description": "Two rooms share one doorway with a puppet standing in it: a path through it stops short of the far room, then reaches it once the puppet has stepped aside.",
		"tags": ["navigation", "rebake", "character", "doorway"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(400, 0, 400, 300) },
	], [{ "pos": DOOR, "width": 70.0 }])
	s.switch(&"nav.rebake", true)
	s.actor(&"guard", &"puppet", DOOR)


func _reach(t: TestContext, steering := true) -> float:
	var map := t.world.get_world_2d().navigation_map
	if steering:
		map = NavBuilder.steering_map(map)
	var path := NavigationServer2D.map_get_path(map, FROM, TO, false)
	t.trace("path_end_x", path[path.size() - 1].x if not path.is_empty() else 0.0)
	return path[path.size() - 1].x if not path.is_empty() else 0.0


func run(t: TestContext) -> void:
	var sealed := func(): return _reach(t) > 0.0 and _reach(t) < DOOR.x
	var open := func(): return _reach(t) > TO.x - 20.0
	t.check(await t.until(sealed, 5.0), "the far room cannot be reached through the occupied doorway (path ends at x=%.0f)" % _reach(t))
	t.check(_reach(t, false) > TO.x - 20.0, "the planning map keeps the doorway open (path ends at x=%.0f)" % _reach(t, false))
	t.puppet(&"guard").walk_to(Vector2(200, 60))
	t.check(await t.until(open, 10.0), "the far room is reachable once the character has stepped aside (path ends at x=%.0f)" % _reach(t))
