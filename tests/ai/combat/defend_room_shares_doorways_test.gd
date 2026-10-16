extends GameTest

## LD8 / D2 (`docs/leadership.md`): the members ordered to defend a room share out its doorways. Each holds a spot back in
## the room, off its doorway's axis (out of the fatal funnel), with its gun on that doorway. Two defenders in the Terrace house's hall
## are ordered to defend the living room, which has two doorways (to the kitchen in its east wall, to the hall in its south wall): one
## takes each, each stands inside the room clear of its doorway's width and back from its wall, and each faces its own doorway.
##
## Scripted Von (the first option offered; the order level asks nothing). The doorways are the test's own copy of the map's.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## The living room's doorways: the id, the centre, the width, and the unit normal pointing into the living room.
const DOORS := {
	"door_480_150": { "pos": Maps.DOOR_LIVING_KITCHEN, "width": 90.0, "inward": Vector2.LEFT },
	"door_150_360": { "pos": Maps.DOOR_HALL_LIVING, "width": 80.0, "inward": Vector2.UP },
}
## How far (px) back from its doorway's wall a defend spot is: out of the funnel (half a wall plus a body and the funnel's depth).
const BACK_FROM_WALL := 40.0
## A body's radius (px): off the axis means clear of the doorway's width by a body.
const BODY := 14.0
## Facing within this of the doorway (dot of the facing with the direction to it) is the gun on it.
const ON_DOOR_DOT := 0.8


func describe() -> Dictionary:
	return {
		"name": "Defenders of a room share out its doorways",
		"description": "Two members ordered to defend the living room take one doorway each, hold a spot inside the room off that doorway's axis and back from its wall, and keep their guns on it (LD8, D2).",
		"tags": ["ai", "combat", "leadership", "order", "defend", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.actor(&"a", &"defender", Vector2(420, 415))
	s.actor(&"b", &"defender", Vector2(560, 415))
	s.actor(&"lead", &"puppet", Vector2(760, 430), { "faction": &"household" })


func run(t: TestContext) -> void:
	var squad := Order.squad(t, &"household", [t.actor(&"lead"), t.actor(&"a"), t.actor(&"b")], t.actor(&"lead"))
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.5)
	Order.issue(squad, { "kind": Order.DEFEND, "to": [t.actor(&"a"), t.actor(&"b")], "room": "living_room" })
	var ids := [&"a", &"b"]
	var defending := func(): return ids.all(func(id): return Order.primitive(Order.brain(t, id)) == "defend")
	if not t.require(await t.until(defending, 5.0), "both take the order to defend (primitives %s)" % str(ids.map(func(id): return Order.primitive(Order.brain(t, id))))):
		return
	var arrived := func(): return ids.all(func(id): return _at_spot(t, id))
	t.check(await t.until(arrived, 25.0), "both reach their defend spots")
	await t.seconds(1.5)

	var doors: Array = ids.map(func(id): return _door_id(Order.params(Order.brain(t, id)).get("door", "")))
	t.check(doors[0] != doors[1], "each takes a different doorway (%s)" % str(doors))
	for i in ids.size():
		var id: StringName = ids[i]
		var door: Dictionary = DOORS.get(doors[i], {})
		if not t.check(not door.is_empty(), "%s's doorway is one of the living room's (%s)" % [id, doors[i]]):
			continue
		var p: Vector2 = t.actor(id).global_position
		t.check(Maps.HOUSE_LIVING.has_point(p), "%s holds inside the living room (%s)" % [id, str(p.round())])
		var inward: Vector2 = door["inward"]
		var lateral := absf((p - (door["pos"] as Vector2)).dot(inward.orthogonal()))
		var back: float = (p - (door["pos"] as Vector2)).dot(inward)
		t.check(lateral >= float(door["width"]) * 0.5 + BODY, "%s stands off its doorway's axis (%.0f px along the wall from its centre)" % [id, lateral])
		t.check(back >= BACK_FROM_WALL, "%s stands back in the room, out of the funnel (%.0f px from the wall)" % [id, back])
		var share := await _share_on_door(t, id, door["pos"], 2.0)
		t.check(share >= 0.7, "%s keeps its gun on its doorway (%.0f%% of 2 s)" % [id, share * 100.0])


## The doorway a defend order's `door` param names, as an id of `DOORS`: the id itself, or the doorway nearest a point given as one.
func _door_id(door: Variant) -> String:
	if door is Array and (door as Array).size() >= 2:
		var p := Vector2(float(door[0]), float(door[1]))
		var best := ""
		for id in DOORS:
			if best == "" or p.distance_to(DOORS[id]["pos"]) < p.distance_to(DOORS[best]["pos"]):
				best = id
		return best if p.distance_to(DOORS[best]["pos"]) < 60.0 else str(door)
	return str(door)


## Whether actor `id` stands at (within 16 px of) the spot its running defend order names (`params.spot`), and is still.
func _at_spot(t: TestContext, id: StringName) -> bool:
	var spot = Order.params(Order.brain(t, id)).get("spot")
	if not spot is Array or (spot as Array).size() < 2:
		return false
	var c := t.actor(id)
	return c.global_position.distance_to(Vector2(spot[0], spot[1])) <= 16.0 and c.velocity.length() < 5.0


## The share of `duration` s that actor `id` faces `at` within `ON_DOOR_DOT`.
func _share_on_door(t: TestContext, id: StringName, at: Vector2, duration: float) -> float:
	var c := t.actor(id)
	var seen := 0
	var on := 0
	var end := t.time + duration
	while t.time < end:
		seen += 1
		if c.facing.normalized().dot((at - c.global_position).normalized()) >= ON_DOOR_DOT:
			on += 1
		await t.frames(1)
	return float(on) / float(maxi(seen, 1))
