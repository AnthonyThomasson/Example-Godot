extends Node

## AI domain: perception/sensor for a goal-driven NPC. Turns the raw world into (a) a compact text
## `state` for the Von decision model (the goal first, then the situation) and (b) the candidate
## menu Von ranks. The decision is ACT-centric: the `act` menu is the real choice — the two combat
## verbs, holding, and an "interact" option for every action offered by the nearby interactable
## objects (whether or not it is in reach), each described in plain language. Movement is then a
## consequence the controller derives from the chosen act (walk to the object you chose to use,
## close on the player you chose to shoot), because Von ranks these distinct, verb-like options
## reliably but ranks many near-identical spatial points almost at random. A small `move` menu of
## named destinations (each room, the player, the post) is offered only for when the act implies no
## movement of its own. It also answers the controller's combat geometry queries (`has_shot`,
## `combat_spots`) used to position tactically — still pure sensing, not routed through Von. It
## holds NO policy and is behaviour-agnostic: it never decides, gates by goal or picks. Reads only
## published contracts (the character's public API, objects' get_interactions()/get_surface(), the
## room rects Main injects).

## Physics layer walls + solid furniture live on (matches CharacterInteraction.QUERY_MASK).
const QUERY_MASK := 1
## Compass names for an 8-wind direction, indexed clockwise from east (screen +y is south).
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

## Surface coverage (0–100) at or above which a blocking object counts as usable cover.
@export var cover_min: float = 40.0

var _post := Vector2.ZERO        ## The NPC's spawn position, captured on the first sense() call.
var _post_set := false           ## Whether _post has been captured yet.
var _interactables: Array = []   ## Cached world objects that advertise interactions (static furniture).
var _scanned := false            ## Whether the one-time interactable scan has run.


## Build this tick's decision context: `{ state_text, moves, acts }`. `goal` is the behaviour string
## Von ranks the menu against; `rooms` is Main's world-space room list (`{ key, type, rect }`);
## `target` is the player. `moves` maps an id to `{ desc, point }`; `acts` maps an id to
## `{ desc, verb, ... }` where `verb` is shoot/punch/hold/interact and an interact also carries its
## `object` + `id`.
func sense(character, target: Node2D, rooms: Array, goal: String) -> Dictionary:
	if not _post_set:
		_post = character.global_position
		_post_set = true
	_ensure_interactables(character)

	var self_pos: Vector2 = character.global_position
	var tgt_pos: Vector2 = target.global_position
	var to_tgt := tgt_pos - self_pos
	var inside := _point_in_rooms(tgt_pos, rooms)
	var tgt_room := _room_at(tgt_pos, rooms)
	var self_room := _room_at(self_pos, rooms)

	return {
		"state_text": _state_text(character, int(to_tgt.length()), inside, tgt_room, self_room, to_tgt, goal),
		"moves": _moves(tgt_pos, rooms),
		"acts": _acts(character, self_pos, rooms),
	}


## The state: the goal verbatim, then the situation line (where the NPC is, what it holds, whether
## it is mid-interaction, and the player's position relative to the house). Kept short — Von
## middle-truncates long states.
func _state_text(character, dist: int, inside: bool, tgt_room: Dictionary, self_room: Dictionary, to_tgt: Vector2, goal: String) -> String:
	var where := "inside the house" if inside else "outside the house"
	if inside and not tgt_room.is_empty():
		where += " (in the %s)" % tgt_room.get("type", "house")
	var self_where: String = self_room.get("type", "the grounds") if not self_room.is_empty() else "the grounds"
	var activity := ("busy: %s" % character.interaction_label()) if character.is_busy() else "free to act"
	return ("%s\nYou are in the %s, %s, holding a %s. The player is %s, ~%dpx to your %s.") % [
		goal, self_where, activity, character.current_item().display_name, where, dist, _compass(to_tgt)]


## The move options: one named destination per room, "where the player is", and the NPC's post.
## Described by place (no local step-ring and no distance spam — those make Von pick near-randomly).
## Consulted by the controller only when the chosen act implies no movement of its own.
func _moves(tgt_pos: Vector2, rooms: Array) -> Dictionary:
	var out := {}
	for room in rooms:
		var rect: Rect2 = room["rect"]
		out["room_%s" % room["key"]] = {
			"desc": "the %s" % room.get("type", "room"),
			"point": rect.position + rect.size * 0.5,
		}
	out["toward_player"] = { "desc": "where the player is", "point": tgt_pos }
	out["post"] = { "desc": "your guard post", "point": _post }
	return out


## The act options — the real decision. The two combat verbs, holding, and one "interact" option per
## DISTINCT action available anywhere in the house (each pointing at the nearest object that offers
## it), so a far-off target is still choosable and the controller walks to it. Deduping by label (not
## by nearest object) keeps the options distinct and the menu bounded — Von ranks distinct, verb-like
## options sharply, so a goal ("watch tv", "make food") reliably picks the matching one. Item-gated.
func _acts(character, self_pos: Vector2, rooms: Array) -> Dictionary:
	var out := {
		"shoot": { "desc": "fire your pistol at the player", "verb": "shoot", "slot": 3 },
		"punch": { "desc": "punch the player", "verb": "punch", "slot": 2 },
		"hold": { "desc": "wait and do nothing", "verb": "hold" },
	}
	var nearest := {}  # action label -> nearest object + its spec (+ squared distance).
	for obj in _interactables:
		if not is_instance_valid(obj):
			continue
		var d: float = obj.global_position.distance_squared_to(self_pos)
		for spec in obj.get_interactions():
			var needed: int = spec.get("requires_item", 0)
			if needed != 0 and not character.has_item(needed):
				continue
			var label: String = spec.get("label", spec.get("id", ""))
			if not nearest.has(label) or d < nearest[label]["d"]:
				nearest[label] = { "obj": obj, "id": spec.get("id", ""), "d": d }
	for label in nearest:
		var obj = nearest[label]["obj"]
		var room := _room_at(obj.global_position, rooms)
		var place: String = " (in the %s)" % room["type"] if not room.is_empty() else ""
		out["do_%d_%s" % [obj.get_instance_id(), nearest[label]["id"]]] = {
			"desc": "%s%s" % [label, place],
			"verb": "interact", "object": obj, "id": nearest[label]["id"],
		}
	return out


## Scan the world once for objects that advertise interactions (static furniture), caching the refs.
## Positions are read live each tick; the set itself doesn't change during a run.
func _ensure_interactables(character) -> void:
	if _scanned:
		return
	_scanned = true
	_interactables.clear()
	var root: Node = character.world_root()
	if root != null:
		_collect(root)


## Recursively gather descendants whose get_interactions() is non-empty into `_interactables`.
func _collect(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("get_interactions") and not (child.get_interactions() as Array).is_empty():
			_interactables.append(child)
		_collect(child)


## Whether the NPC currently has a clear line of fire to the player (no wall or solid furniture in
## the way). The controller gates firing on this so the guard never shoots through walls.
func has_shot(character, target: Node2D) -> bool:
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	var exclude := [character.get_rid(), target.get_rid()]
	return not _blocked(space, character.global_position, target.global_position, exclude)


## Candidate standing points on a ring around the NPC, classified for peek-and-cover: `fire` points
## have a clear line to the player (a shot can be taken from there); `cover` points are shielded from
## the player by a high-coverage solid object. Points the NPC can't reach in a straight line (a wall
## between) are dropped. Both lists are nearest-first, for the controller to pick from.
func combat_spots(character, target: Node2D, radius: float, count: int) -> Dictionary:
	var self_pos: Vector2 = character.global_position
	var tgt_pos: Vector2 = target.global_position
	var exclude := [character.get_rid(), target.get_rid()]
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	var fire: Array = []
	var cover: Array = []
	for i in count:
		var p := self_pos + Vector2.RIGHT.rotated(TAU * i / count) * radius
		if _blocked(space, self_pos, p, exclude):
			continue  # Can't step there — a wall is in the way.
		if _blocked(space, p, tgt_pos, exclude):
			if _is_cover(space, p, tgt_pos, exclude):
				cover.append(p)
		else:
			fire.append(p)
	fire.sort_custom(func(a, b): return a.distance_squared_to(self_pos) < b.distance_squared_to(self_pos))
	cover.sort_custom(func(a, b): return a.distance_squared_to(self_pos) < b.distance_squared_to(self_pos))
	return { "fire": fire, "cover": cover }


## Whether the straight segment `from`→`to` hits a wall or solid object on the query layer.
func _blocked(space, from: Vector2, to: Vector2, exclude: Array) -> bool:
	var p := PhysicsRayQueryParameters2D.create(from, to)
	p.collision_mask = QUERY_MASK
	p.exclude = exclude
	return not space.intersect_ray(p).is_empty()


## Whether the first object blocking `from`→`to` is high-coverage enough to count as cover.
func _is_cover(space, from: Vector2, to: Vector2, exclude: Array) -> bool:
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
