extends RefCounted

## Composition-root helper (`main.gd`): where and how a match's NPCs are placed. Defenders go to a clear spot in a random room,
## invaders spread around the outside of the house; each NPC is added under the match's `World` node, handed the house's rooms and
## recorded in `combatants` (the spectator camera, the match HUD and the overlays observe that list). Like `main.gd` it knows the
## NPC scenes and the Navigation domain's `furniture_holes`; the placement rules live here so the root only wires domains.

## The house defender, dropped into one of the generated rooms.
const DEFENDER_SCENE := preload("res://scenes/ai/npc_defender.tscn")
## The house invader, dropped just outside the house. Same AI, different data.
const INVADER_SCENE := preload("res://scenes/ai/npc_invader.tscn")
## Random points tried in a room, after its centre, before `clear_spot` gives up.
const SPAWN_TRIES := 32

## The match's `World` node the NPCs are added under.
var world: Node2D = null
## Minimum clearance (px) from solid furniture a character is dropped with (twice that from another combatant).
var spawn_clearance: float = 20.0
## How far outside the house's bounding box (px) invaders are dropped.
var invader_margin: float = 80.0
## Every NPC placed so far, in spawn order.
var combatants: Array = []
## The house's doorways (`WorldGen.get_openings`), handed to every NPC it binds alongside the rooms.
var openings: Array = []


## Drop defender number `index` at a clear spot (`clear_spot`) in a random room. `rng` is seeded from
## `house_seed` so a pinned layout also pins the NPCs. Added after the house, so it draws above it. `rooms`
## is WorldGen.get_rooms(house), already fetched by the caller.
func spawn_defender(rooms: Array, rng: RandomNumberGenerator, index: int) -> void:
	if rooms.is_empty():
		return
	var room: Dictionary = rooms[rng.randi() % rooms.size()]
	add_npc(DEFENDER_SCENE, npc_name("Defender", index), clear_spot(room["rect"], rng), rooms)


## Where a character can be dropped in room `rect`: its centre when clear, else the first clear point of
## SPAWN_TRIES drawn from `rng` (inset from the walls). Clear = at least `spawn_clearance` from every solid
## furniture footprint (Navigation's `furniture_holes`, read off the shapes, so it is right on the frame the
## house is built) and twice that from every combatant already placed. The centre when nothing is clear.
func clear_spot(rect: Rect2, rng: RandomNumberGenerator) -> Vector2:
	var holes := NavBuilder.furniture_holes(world)
	var taken: Array = []
	for c in combatants:
		if is_instance_valid(c):
			taken.append((c as Node2D).global_position)
	var centre := rect.get_center()
	if is_clear(centre, holes, taken):
		return centre
	var inner := rect.grow(-spawn_clearance * 2.0)
	if inner.size.x > 0.0 and inner.size.y > 0.0:
		for i in SPAWN_TRIES:
			var p := inner.position + Vector2(rng.randf(), rng.randf()) * inner.size
			if is_clear(p, holes, taken):
				return p
	GameLog.say("No clear spawn spot in the room at %s; using its centre" % centre)
	return centre


## Whether `p` keeps `spawn_clearance` from every footprint in `holes` and twice that from every point in `taken`.
func is_clear(p: Vector2, holes: Array, taken: Array) -> bool:
	for q in taken:
		if p.distance_to(q) < spawn_clearance * 2.0:
			return false
	for poly: PackedVector2Array in holes:
		if Geometry2D.is_point_in_polygon(p, poly):
			return false
		for i in poly.size():
			if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p) < spawn_clearance:
				return false
	return true


## Drop invader number `index` (of `count`) just outside the house (the rooms' bounding box),
## `invader_margin` px out. Invaders are spread evenly around the perimeter (one even fraction per
## index, plus a little jitter) so several attackers start on different sides and flank a shared
## target rather than stacking on one side. `front_entranceworld` is injected so the controller heads
## straight for the entrance rather than circling.
func spawn_invader(rooms: Array, rng: RandomNumberGenerator, index: int, count: int, front_entranceworld: Vector2) -> void:
	if rooms.is_empty():
		return
	var bounds: Rect2 = rooms[0]["rect"]
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	bounds = bounds.grow(invader_margin)
	var frac := fposmod((index + 0.5) / maxi(count, 1) + rng.randf_range(-0.05, 0.05), 1.0)
	add_npc(INVADER_SCENE, npc_name("Invader", index), perimeter_point(bounds, frac), rooms, front_entranceworld)


## A point at fraction `frac` (0..1, clockwise from the top-left) around the perimeter of `rect`.
func perimeter_point(rect: Rect2, frac: float) -> Vector2:
	var d := frac * 4.0  # Four equal sides.
	if d < 1.0:
		return Vector2(lerpf(rect.position.x, rect.end.x, d), rect.position.y)          # top
	elif d < 2.0:
		return Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, d - 1.0))         # right
	elif d < 3.0:
		return Vector2(lerpf(rect.end.x, rect.position.x, d - 2.0), rect.end.y)         # bottom
	return Vector2(rect.position.x, lerpf(rect.end.y, rect.position.y, d - 3.0))        # left


## The node name for NPC `index` of a kind: the plain base for the first (so existing tooling that
## addresses "Defender"/"Invader" keeps working), then "<base> 2", "<base> 3", … for the rest.
func npc_name(base: String, index: int) -> String:
	return base if index == 0 else "%s %d" % [base, index + 1]


## Instance an NPC scene named `node_name` at `pos`, hand its controller the house's rooms and optional
## entry point, and record it as a combatant (for the spectator camera + match HUD). It joins the `World`
## node; `_arm_characters` gives it its weapon afterwards. It is positioned BEFORE it joins the tree: a body
## added at the world origin and moved afterwards overlaps whatever stands there for a moment, and the
## physics launches that piece (or the NPC) across the map.
func add_npc(scene: PackedScene, node_name: String, pos: Vector2, rooms: Array, entry_point: Vector2 = Vector2.ZERO) -> void:
	var npc := scene.instantiate()
	npc.name = node_name
	npc.position = world.to_local(pos)
	world.add_child(npc)
	bind_npc(npc, rooms, entry_point)
	combatants.append(npc)


## Wire an NPC's controller to the world: hand it the house's `rooms` (world-space rects), its `openings`
## (the doorways, for tactical entry) and, when given, an `entry_point` the NPC heads for first while
## outside all rooms. Found by the same
## `control` duck-type the character uses to pick its controller — so Main doesn't depend on the
## controller's node name. This keeps the World-Gen boundary in Main: the AI never calls WorldGen.
func bind_npc(npc: Node, rooms: Array, entry_point: Vector2 = Vector2.ZERO) -> void:
	for child in npc.get_children():
		if child.has_method("control"):
			if "rooms" in child:
				child.rooms = rooms
			if "openings" in child:
				child.openings = openings
			if "entry_point" in child and entry_point != Vector2.ZERO:
				child.entry_point = entry_point
			return
