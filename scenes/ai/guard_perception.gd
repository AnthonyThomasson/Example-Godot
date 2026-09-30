extends Node

## AI domain: perception/sensor for the guard NPC. Turns the raw world into (a) a compact text
## `state` for the Von decision model and (b) three fixed-shape candidate sets — where to move, where
## to aim, and what to do — each option annotated with the tactical facts (distance to the intruder,
## whether it sits behind cover, whether it is outside the house) that let defend-the-house behaviour
## emerge from Von's ranking. It holds no policy: it never decides, gates or picks; the controller does.
## Reads only published contracts (the character's public API, objects' `get_surface()`, the room rects
## Main injects), so it crosses no domain boundary.

## Radius (px) of the ring of local step-to positions offered as move options.
@export var ring_radius: float = 90.0
## Number of evenly spaced points on the local move ring.
@export var ring_count: int = 8
## Number of evenly spaced look-directions offered as aim options.
@export var aim_count: int = 8
## Surface coverage (0–100) at or above which a blocking object counts as usable cover.
@export var cover_min: float = 40.0

## Physics layer walls + solid furniture live on (matches CharacterInteraction.QUERY_MASK).
const QUERY_MASK := 1
## Compass names for an 8-wind direction, indexed clockwise from east (screen +y is south).
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

var _post := Vector2.ZERO   ## The NPC's spawn position, captured on the first sense() call.
var _post_set := false      ## Whether _post has been captured yet.


## Build this tick's decision context: `{ state_text, moves, aims, acts }`. `rooms` is Main's
## world-space room list (`{ key, type, rect }`); `target` is the player being defended against.
## `moves`/`aims`/`acts` map an option id to `{ desc, ... }` where `desc` is the text Von ranks and
## the rest (a `point`, a `dir`, or a `verb`/`slot`) is what the controller executes.
func sense(character, target: Node2D, rooms: Array) -> Dictionary:
	if not _post_set:
		_post = character.global_position
		_post_set = true

	var self_pos: Vector2 = character.global_position
	var intr_pos: Vector2 = target.global_position
	var to_intr := intr_pos - self_pos
	var inside := _point_in_rooms(intr_pos, rooms)
	var intr_room := _room_at(intr_pos, rooms)
	var self_room := _room_at(self_pos, rooms)
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	var exclude := [character.get_rid(), target.get_rid()]

	return {
		"state_text": _state_text(character, int(to_intr.length()), inside, intr_room, self_room, to_intr),
		"moves": _moves(space, exclude, self_pos, intr_pos, rooms),
		"aims": _aims(to_intr),
		"acts": _acts(),
	}


## The goal-first situation line: the rule, then whether the intruder is inside, their bearing, and
## what the guard holds. Kept short — Von middle-truncates long states.
func _state_text(character, dist: int, inside: bool, intr_room: Dictionary, self_room: Dictionary, to_intr: Vector2) -> String:
	var where := "INSIDE" if inside else "OUTSIDE"
	if inside and not intr_room.is_empty():
		where += ", in the %s" % intr_room.get("type", "house")
	var self_where: String = self_room.get("type", "the grounds") if not self_room.is_empty() else "the grounds"
	return ("You are a guard defending this house. Do not engage or attack unless the intruder is " +
		"INSIDE the house. The intruder is %s, ~%dpx to your %s. You are in the %s holding a %s.") % [
		where, dist, _compass(to_intr), self_where, character.current_item().display_name]


## The move options: a local step-to ring (wall-blocked points dropped) plus key destinations — each
## room's centre, the intruder's own position, and the guard's post. Every `desc` carries the tactical
## annotation so cover/guarding emerges from Von preferring the right point.
func _moves(space, exclude: Array, self_pos: Vector2, intr_pos: Vector2, rooms: Array) -> Dictionary:
	var out := {}
	for i in ring_count:
		var dir := Vector2.RIGHT.rotated(TAU * i / ring_count)
		var point := self_pos + dir * ring_radius
		if _ray_blocked(space, exclude, self_pos, point):
			continue
		out["step_%s" % _compass(dir)] = {
			"desc": "step %s — %s" % [_compass(dir), _annotate(space, exclude, point, intr_pos, rooms)],
			"point": point,
		}
	for room in rooms:
		var rect: Rect2 = room["rect"]
		var centre := rect.position + rect.size * 0.5
		out["room_%s" % room["key"]] = {
			"desc": "move into the %s — %s" % [room.get("type", "room"), _annotate(space, exclude, centre, intr_pos, rooms)],
			"point": centre,
		}
	out["toward_intruder"] = {
		"desc": "close in on the intruder — %s" % _annotate(space, exclude, intr_pos, intr_pos, rooms),
		"point": intr_pos,
	}
	out["post"] = {
		"desc": "return to your post — %s" % _annotate(space, exclude, _post, intr_pos, rooms),
		"point": _post,
	}
	return out


## The aim options: an even ring of look-directions plus aiming straight at the intruder (which is
## what lets a shot connect). Each `dir` is a unit vector the controller projects into an aim point.
func _aims(to_intr: Vector2) -> Dictionary:
	var out := {}
	for i in aim_count:
		var dir := Vector2.RIGHT.rotated(TAU * i / aim_count)
		out["look_%s" % _compass(dir)] = { "desc": "look %s" % _compass(dir), "dir": dir }
	if to_intr.length() > 0.001:
		out["at_intruder"] = { "desc": "aim straight at the intruder", "dir": to_intr.normalized() }
	return out


## The act options — offered every tick, never gated. Whether firing is appropriate is Von's call
## from the goal + the stated intruder position.
func _acts() -> Dictionary:
	return {
		"shoot": { "desc": "fire your pistol at the intruder", "verb": "shoot", "slot": 3 },
		"punch": { "desc": "punch the intruder", "verb": "punch", "slot": 2 },
		"hold": { "desc": "hold position and keep watch", "verb": "hold" },
	}


## Tactical facts for a candidate point, as one comma-joined phrase: range to the intruder, whether a
## high-coverage object breaks line of sight to them from there, and whether the point is outside.
func _annotate(space, exclude: Array, point: Vector2, intr_pos: Vector2, rooms: Array) -> String:
	var parts := PackedStringArray()
	parts.append("~%dpx from the intruder" % int(point.distance_to(intr_pos)))
	if _ray_cover(space, exclude, point, intr_pos):
		parts.append("behind cover from the intruder")
	if not _point_in_rooms(point, rooms):
		parts.append("outside the house")
	return ", ".join(parts)


## Whether the straight path `from`→`to` hits a wall or solid object (used to drop unreachable ring
## points).
func _ray_blocked(space, exclude: Array, from: Vector2, to: Vector2) -> bool:
	var p := PhysicsRayQueryParameters2D.create(from, to)
	p.collision_mask = QUERY_MASK
	p.exclude = exclude
	return not space.intersect_ray(p).is_empty()


## Whether the first object on `from`→`to` is high-coverage enough to count as cover (a wall or bulky
## furniture between the point and the intruder).
func _ray_cover(space, exclude: Array, from: Vector2, to: Vector2) -> bool:
	var p := PhysicsRayQueryParameters2D.create(from, to)
	p.collision_mask = QUERY_MASK
	p.exclude = exclude
	var hit: Dictionary = space.intersect_ray(p)
	if hit.is_empty():
		return false
	var obj = hit["collider"]
	return obj != null and obj.has_method("get_surface") and float(obj.get_surface().get("coverage", 0.0)) >= cover_min


## Whether world point `p` lies inside any room rect (the "inside the house" test).
func _point_in_rooms(p: Vector2, rooms: Array) -> bool:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return true
	return false


## The room dict whose rect contains `p`, or empty when `p` is outside every room.
func _room_at(p: Vector2, rooms: Array) -> Dictionary:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return room
	return {}


## The 8-wind compass name for a direction vector (screen space, +y down = south).
func _compass(v: Vector2) -> String:
	var idx := int(round(atan2(v.y, v.x) / (TAU / 8.0))) % 8
	return COMPASS[idx + 8 if idx < 0 else idx]
