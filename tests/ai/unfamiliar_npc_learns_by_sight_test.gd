extends GameTest

## An NPC that does not know the house (the invader preset) learns the rooms and furniture it can see, and only
## those: the room and the sofa in view through an open doorway become known, the room and the sofa behind a solid wall
## stay unknown. Von is down, so the NPC holds its post and keeps looking east while every decision still builds its snapshot.

const NPC_AT := Vector2(150, 150)
const SEEN_ROOM_AT := Vector2(600, 150)
const HIDDEN_ROOM_AT := Vector2(1000, 150)
const SEEN_SOFA := Vector2(620, 170)
const HIDDEN_SOFA := Vector2(1000, 170)


func describe() -> Dictionary:
	return {
		"name": "An unfamiliar NPC learns what it sees",
		"description": "A room and a sofa in view through a doorway are learned; those behind a solid wall are not.",
		"tags": ["ai", "vision", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "middle", "type": "kitchen", "rect": Rect2(400, 0, 400, 300) },
		{ "key": "east", "type": "entry_hall", "rect": Rect2(800, 0, 400, 300) },
	], [{ "pos": Vector2(400, 150), "width": 90.0 }])
	s.von_down()
	s.object(&"seen_sofa", "sofa", SEEN_SOFA)
	s.object(&"hidden_sofa", "sofa", HIDDEN_SOFA)
	s.actor(&"inv", &"invader", NPC_AT, { "speed": 0.0, "facing": Vector2.RIGHT })
	s.set_props(&"inv", "GoalController", { "decide_interval": 0.3 })


func run(t: TestContext) -> void:
	var brain := t.controller(&"inv", &"debug_room_zones")
	await t.seconds(2.0)
	t.check(_status_at(brain, NPC_AT) == &"current", "the room it stands in is known")
	t.check(_status_at(brain, SEEN_ROOM_AT) != &"unknown", "the room in view through the doorway is learned (%s)" % _status_at(brain, SEEN_ROOM_AT))
	t.check(_status_at(brain, HIDDEN_ROOM_AT) == &"unknown", "the room behind a solid wall stays unknown (%s)" % _status_at(brain, HIDDEN_ROOM_AT))
	var zones: Array = brain.debug_zones()
	t.check(_offers_interaction_near(zones, SEEN_SOFA), "the sofa in view is offered as furniture to use")
	t.check(not _offers_interaction_near(zones, HIDDEN_SOFA), "the sofa behind the wall is not")


## How the NPC regards the room containing `point`: current / searched / unsearched / unknown.
func _status_at(brain: Node, point: Vector2) -> StringName:
	for zone in brain.debug_room_zones():
		if (zone["rect"] as Rect2).has_point(point):
			return zone["status"]
	return &"missing"


## Whether the last snapshot offered an interaction on a piece within a few px of `point`.
func _offers_interaction_near(zones: Array, point: Vector2) -> bool:
	for zone in zones:
		if zone["category"] == &"interaction" and (zone["point"] as Vector2).distance_to(point) < 8.0:
			return true
	return false
