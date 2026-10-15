extends GameTest

## R5 (ticket #61): wear and clutter are placed in the world per room, never baked into a repeating tile. In
## generated houses (the test's own house world plus more seeds, so several plans): each room has 0 to 3 wear
## clusters and 0 to 2 clutter pieces, no clutter kind twice in a room; clutter is non-solid decor (no collider on
## PhysicsLayers.SOLID, not carved into the nav map); every wear cluster and clutter piece sits by a wall, a corner or
## a piece of solid furniture of its room; the wear is drawn by a layer of its own per room; most rooms are worn and
## clutter shows up; and two rooms of the same type never get the same wear layout.
##
## It reads them through (interface 1, like `get_rooms` / `get_openings`):
## - `WorldGen.get_wear(house) -> Array` of `{ room, pos, layer }`: one entry per wear cluster, `room` its room's key,
##   `pos` its centre in world space, `layer` the node that draws that room's wear.
## - `WorldGen.get_clutter(house) -> Array` of `{ room, key, node }`: one entry per clutter piece, `key` its catalogue
##   key, `node` the placed piece.

const HOUSE_SEED := 2  ## The test world's own house.
const SEEDS := [3, 5, 8, 13, 21, 34, 55, 89, 144, 233]  ## More houses, built one at a time beside it.
const ELSEWHERE := Vector2(9000, 9000)  ## Where the extra houses go, clear of the world's own.
const MAX_WEAR := 3  ## Wear clusters per room, at most.
const MAX_CLUTTER := 2  ## Clutter pieces per room, at most.
const NEAR := 48.0  ## How far (px) a cluster's or piece's centre may lie from a wall line or a solid piece's footprint.
const MIN_WORN_SHARE := 0.5  ## The share of rooms that must carry some wear: the houses are run down.
const MIN_CLUTTERED_SHARE := 0.25  ## The share of rooms that must carry some clutter.


func describe() -> Dictionary:
	return {
		"name": "Wear and clutter are placed per room, by walls and furniture",
		"description": "In generated houses each room has 0-3 wear clusters and 0-2 clutter pieces (no kind twice), clutter is non-solid and not carved into the nav map, both sit by a wall, corner or furniture, each room's wear has its own layer, and rooms of one type differ.",
		"tags": ["worldgen", "house", "wear", "clutter", "restyle"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.house(HOUSE_SEED)


## The solid furniture of `house` standing in `rect`: [{ node, rect }], each footprint in world space.
func _solid_pieces(house: Node2D, rect: Rect2) -> Array:
	var out: Array = []
	for node in house.find_children("*", "RigidBody2D", true, false):
		if not ("solid" in node and "size" in node) or not node.solid:
			continue
		var at: Vector2 = node.global_position
		if rect.has_point(at):
			var size: Vector2 = node.size
			out.append({ "node": node, "rect": Rect2(at - size * 0.5, size) })
	return out


## The distance from `p` to the nearest wall line of `room` (its rect runs along the walls' centre lines).
func _to_wall(p: Vector2, room: Rect2) -> float:
	return minf(minf(p.x - room.position.x, room.end.x - p.x), minf(p.y - room.position.y, room.end.y - p.y))


## The distance from `p` to `rect` (0 inside it).
func _to_rect(p: Vector2, rect: Rect2) -> float:
	var dx := maxf(0.0, maxf(rect.position.x - p.x, p.x - rect.end.x))
	var dy := maxf(0.0, maxf(rect.position.y - p.y, p.y - rect.end.y))
	return Vector2(dx, dy).length()


## The distance from `p` to the nearest wall of `room` or solid piece in `pieces`.
func _to_anchor(p: Vector2, room: Rect2, pieces: Array, skip: Node = null) -> float:
	var best := _to_wall(p, room)
	for piece: Dictionary in pieces:
		if piece["node"] != skip:
			best = minf(best, _to_rect(p, piece["rect"]))
	return best


## Whether `body` has a collision shape on PhysicsLayers.SOLID.
func _collides_solid(body: Node) -> bool:
	if not (body is CollisionObject2D) or ((body as CollisionObject2D).collision_layer & PhysicsLayers.SOLID) == 0:
		return false
	for child in body.get_children():
		if (child is CollisionShape2D and child.shape != null) or (child is CollisionPolygon2D and not child.polygon.is_empty()):
			return true
	return false


## Checks one house; adds its rooms' wear layouts to `layouts` (type -> [{ label, layout }]) and its counts to `tally`.
func _check_house(t: TestContext, house: Node2D, label: String, layouts: Dictionary, tally: Dictionary) -> void:
	var rooms := WorldGen.get_rooms(house)
	var wear := WorldGen.get_wear(house)
	var clutter := WorldGen.get_clutter(house)
	var room_of := {}
	for room: Dictionary in rooms:
		room_of[room["key"]] = room

	var layer_of := {}  # room key -> the layer drawing its wear
	for entry: Dictionary in wear:
		var key: String = entry.get("room", "")
		if not t.check(room_of.has(key), "%s: a wear cluster names a room of the house (%s)" % [label, key]):
			continue
		var layer: Variant = entry.get("layer")
		t.check(layer is CanvasItem and house.is_ancestor_of(layer), "%s: the %s's wear is drawn by a layer in the house" % [label, key])
		if layer is Node:
			if layer_of.has(key):
				t.check(layer_of[key] == layer, "%s: the %s's wear is one layer" % [label, key])
			else:
				t.check(not layer_of.values().has(layer), "%s: the %s's wear has a layer of its own, not another room's" % [label, key])
				layer_of[key] = layer

	for entry: Dictionary in clutter:
		t.check(room_of.has(entry.get("room", "")), "%s: a clutter piece names a room of the house (%s)" % [label, entry.get("room", "")])

	for room: Dictionary in rooms:
		var key: String = room["key"]
		var rect: Rect2 = room["rect"]
		var where := "%s: the %s (%s)" % [label, key, room["type"]]
		var pieces := _solid_pieces(house, rect)

		var clusters := wear.filter(func(e: Dictionary) -> bool: return e.get("room", "") == key)
		t.check(clusters.size() <= MAX_WEAR, "%s has %d wear clusters, at most %d" % [where, clusters.size(), MAX_WEAR])
		var layout: Array = []
		for c: Dictionary in clusters:
			var p: Vector2 = c["pos"]
			t.check(rect.has_point(p), "%s: a wear cluster at %s lies in the room" % [where, p])
			var gap := _to_anchor(p, rect, pieces)
			t.check(gap <= NEAR, "%s: the wear at %s is by a wall, corner or furniture (%.0f px away, at most %.0f)" % [where, p, gap, NEAR])
			layout.append(Vector2i((p - rect.position).round()))
		layout.sort()
		if not layout.is_empty():
			tally["worn"] += 1
			if not layouts.has(room["type"]):
				layouts[room["type"]] = []
			layouts[room["type"]].append({ "label": where, "layout": layout })

		var placed := clutter.filter(func(e: Dictionary) -> bool: return e.get("room", "") == key)
		t.check(placed.size() <= MAX_CLUTTER, "%s has %d clutter pieces, at most %d" % [where, placed.size(), MAX_CLUTTER])
		if not placed.is_empty():
			tally["cluttered"] += 1
		var kinds: Array = []
		for c: Dictionary in placed:
			var kind: String = c.get("key", "")
			t.check(not kinds.has(kind), "%s has the clutter %s only once" % [where, kind])
			kinds.append(kind)
			var def := WorldGen.object_definition(kind)
			t.check(not def.is_empty() and not def.get("solid", true), "%s: the clutter %s is non-solid catalogue decor" % [where, kind])
			var node: Variant = c.get("node")
			if not t.check(node is Node2D and house.is_ancestor_of(node), "%s: the clutter %s is placed in the house" % [where, kind]):
				continue
			t.check(not ("solid" in node) or not node.solid, "%s: the placed %s is not solid" % [where, kind])
			t.check(not _collides_solid(node), "%s: the placed %s has no collider on the SOLID layer" % [where, kind])
			var p: Vector2 = node.global_position
			t.check(rect.has_point(p), "%s: the %s at %s lies in the room" % [where, kind, p])
			var gap := _to_anchor(p, rect, pieces, node)
			t.check(gap <= NEAR, "%s: the %s at %s is by a wall, corner or furniture (%.0f px away, at most %.0f)" % [where, kind, p, gap, NEAR])
		tally["rooms"] += 1

	# Clutter is never carved into the nav map: taking it out of the house leaves the furniture holes as they were.
	var holes := NavBuilder.furniture_holes(house).size()
	var lifted: Array = []
	for c: Dictionary in clutter:
		var node: Variant = c.get("node")
		if node is Node and node.get_parent() != null:
			lifted.append([node, node.get_parent()])
			node.get_parent().remove_child(node)
	t.expect_eq(NavBuilder.furniture_holes(house).size(), holes, "%s: no clutter piece is a nav hole" % label)
	for pair: Array in lifted:
		pair[1].add_child(pair[0])


func run(t: TestContext) -> void:
	var layouts := {}
	var tally := { "rooms": 0, "worn": 0, "cluttered": 0 }
	_check_house(t, t.world.house, "house seed %d" % HOUSE_SEED, layouts, tally)
	for house_seed: int in SEEDS:
		var house := WorldGen.generate(house_seed, "", ELSEWHERE, t.world)
		_check_house(t, house, "house seed %d" % house_seed, layouts, tally)
		house.free()
		await t.frames(1)

	t.check(tally["worn"] >= MIN_WORN_SHARE * tally["rooms"],
		"most rooms are worn (%d of %d have wear, at least %.0f%%)" % [tally["worn"], tally["rooms"], 100.0 * MIN_WORN_SHARE])
	t.check(tally["cluttered"] >= MIN_CLUTTERED_SHARE * tally["rooms"],
		"clutter shows up (%d of %d rooms have some, at least %.0f%%)" % [tally["cluttered"], tally["rooms"], 100.0 * MIN_CLUTTERED_SHARE])

	# The wear is seeded per room: two rooms of one type never share a layout.
	for room_type: String in layouts:
		var same: Array = layouts[room_type]
		for i in same.size():
			for j in range(i + 1, same.size()):
				t.check(same[i]["layout"] != same[j]["layout"],
					"%s and %s have different wear (%s)" % [same[i]["label"], same[j]["label"], same[i]["layout"]])
