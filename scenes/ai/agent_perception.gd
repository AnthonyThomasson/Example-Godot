extends Node

## AI domain: perception/sensor for a goal-driven NPC. It has two halves. `observe()` is the SEE
## pass — run every tick, it tests what is currently visible (via the vision sense, agent_vision.gd),
## deposits sightings into the agent's memory (agent_memory.gd) — every other character
## (`saw_character`, the player included) and, for an NPC that must learn its surroundings, rooms and
## objects (`saw_room` / `saw_object`) — and runs each character sighting through the hostility rules
## (agent_hostility.gd), which categorize it. `contacts()` is the resulting view: every character the
## agent knows of, hostile or not. `sense()` is the BUILD pass — run each decision, it turns what the
## agent currently sees AND remembers into (a) a compact text `state` for the Von decision model and
## (b) the candidate menu Von ranks. The NPC knows only what it has perceived, and that knowledge
## decays as the memory does.
##
## The decision is ACT-centric: the `act` menu is the real choice, built from generic primitives —
## engage (shoot / punch) each KNOWN HOSTILE contact, search for hostiles when none is known, hold,
## and use any action offered by a KNOWN interactable object. Movement is a consequence the
## controller derives from the chosen act. A small `move` menu of KNOWN named destinations is offered
## for when the act implies no movement. It also answers the controller's combat geometry queries
## (`has_line_to`, `combat_spots`) — pure sensing, not routed through Von. It holds NO policy and is
## behaviour-agnostic: it never decides, gates by goal or picks. Reads only published contracts (the
## character's public API, objects' get_interactions()/get_surface(), the room rects Main injects).

## Physics layer walls + solid furniture live on (matches CharacterInteraction.QUERY_MASK).
const QUERY_MASK := 1
## Inventory slots of the combat items (ItemRegistry ids) the engage acts select.
const PISTOL_SLOT := 3
const FISTS_SLOT := 2
## Compass names for an 8-wind direction, indexed clockwise from east (screen +y is south).
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

## Surface coverage (0–100) at or above which a blocking object counts as usable cover.
@export var cover_min: float = 40.0
## Accumulated damage (see Character.damage_taken) at or above which the NPC reports being hurt.
@export var hurt_threshold: float = 15.0
## Accumulated damage at or above which the NPC reports being badly wounded.
@export var critical_threshold: float = 35.0

## Most contacts described in the decision state (hostiles first, then nearest).
@export var max_contacts_in_state: int = 4

## Lifetime (s) of a character sighting in memory — the window the NPC keeps acting on a last-seen
## position after losing sight. Set by the controller from its matching export.
var contact_memory_ttl: float = 4.0

var _post := Vector2.ZERO        ## The NPC's spawn position, captured on the first observe() call.
var _post_set := false           ## Whether _post has been captured yet.
var _interactables: Array = []   ## Cached world objects that advertise interactions (static furniture).
var _scanned := false            ## Whether the one-time interactable scan has run.
var _seeded := false             ## Whether the familiar-NPC house-knowledge seed has run.
var _visible_now := {}           ## Instance ids of characters visible on the latest observe() tick.


## SEE pass — run every tick. Test what is visible via `vision` and remember it, so the agent's
## knowledge stays fresh while it can see and decays once it can't; each character sighting is also
## categorized by `hostility`. `familiar` (used on the first call only) pre-seeds the house's rooms +
## objects into memory as already-known. People are never seeded — they are known only once seen.
func observe(character, rooms: Array, vision: RefCounted, hostility: RefCounted, memory: RefCounted, familiar: bool) -> void:
	if not _post_set:
		_post = character.global_position
		_post_set = true
	_ensure_interactables(character)
	_seed_house(rooms, memory, familiar)

	var self_pos: Vector2 = character.global_position
	var facing: Vector2 = character.facing
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	var exclude := [character.get_rid()]

	# Every other character (the player included): remember a sighting whenever currently visible.
	_visible_now.clear()
	for other in _other_characters(character):
		if not vision.can_see_node(other, self_pos, facing, space, exclude):
			continue
		var pos: Vector2 = other.global_position
		var room := _room_at(pos, rooms)
		var item = other.current_item()
		var f = other.get("faction")
		var sighting := {
			"id": other.get_instance_id(),
			"node": other,
			"name": str(other.name),
			"faction": f if f != null else &"",
			"pos": pos,
			"inside": not room.is_empty(),
			"room": room.get("type", "") if not room.is_empty() else "",
			"item": item.display_name if item != null else "nothing",
		}
		_visible_now[sighting["id"]] = true
		memory.remember(&"saw_character", sighting, contact_memory_ttl)
		hostility.classify(sighting, memory)

	# An unfamiliar NPC learns rooms and objects by seeing them (permanent once learned).
	if not familiar:
		for room in rooms:
			var rect: Rect2 = room["rect"]
			if rect.has_point(self_pos) or vision.can_see(self_pos, facing, rect.position + rect.size * 0.5, space, exclude):
				_learn_room(room, memory)
		for obj in _interactables:
			if is_instance_valid(obj) and vision.can_see_node(obj, self_pos, facing, space, exclude):
				_learn_object(obj, memory)


## BUILD pass — run each decision. Assemble this tick's decision context `{ state_text, moves, acts }`
## from what the agent currently sees and remembers (NOT from ground truth). `goal` is the behaviour
## string Von ranks the menu against; `rooms` is Main's world-space room list; `memory` is the agent's
## event memory (sightings + hostility verdicts included).
func sense(character, rooms: Array, goal: String, memory: RefCounted, hostility: RefCounted) -> Dictionary:
	var self_pos: Vector2 = character.global_position
	var self_room := _room_at(self_pos, rooms)
	var known := contacts(self_pos, memory, hostility)
	return {
		"state_text": _state_text(character, self_room, goal, memory, known),
		"moves": _moves(rooms, memory, known),
		"acts": _acts(character, self_pos, rooms, memory, known),
	}


## Every character the agent currently knows of — the freshest sighting per character, with
## `hostile` / `reason` from the hostility verdicts and `visible` (seen on the latest tick) added.
## Hostiles first, then nearest to `self_pos`. Entries whose character no longer exists are dropped.
func contacts(self_pos: Vector2, memory: RefCounted, hostility: RefCounted) -> Array:
	var out: Array = []
	var seen := {}
	for data in memory.recall_all(&"saw_character"):  # Newest first: the first per id is the freshest.
		var id: int = data.get("id", 0)
		var n: Variant = data.get("node")
		if seen.has(id) or not is_instance_valid(n) or (n as Node).get("is_dead") == true:
			continue
		seen[id] = true
		var c: Dictionary = data.duplicate()
		c["reason"] = hostility.reason(id, memory)
		c["hostile"] = c["reason"] != ""
		c["visible"] = _visible_now.has(id)
		out.append(c)
	out.sort_custom(func(a, b):
		if a["hostile"] != b["hostile"]:
			return a["hostile"]
		return (a["pos"] as Vector2).distance_squared_to(self_pos) < (b["pos"] as Vector2).distance_squared_to(self_pos))
	return out


## The state: the goal verbatim, then the situation line (where the NPC is, what it holds, whether it
## is mid-interaction), one line per known contact, then any combat-awareness lines (under fire / own
## injury). Kept short — Von middle-truncates long states.
func _state_text(character, self_room: Dictionary, goal: String, memory: RefCounted, known: Array) -> String:
	var self_where: String = self_room.get("type", "the grounds") if not self_room.is_empty() else "the grounds"
	var activity := ("busy: %s" % character.interaction_label()) if character.is_busy() else "free to act"
	var lines: Array = ["%s\nYou are in the %s, %s, holding a %s." % [
		goal, self_where, activity, character.current_item().display_name]]
	lines.append_array(_contact_lines(character.global_position, memory, known))
	lines.append_array(_awareness_lines(character, memory))
	return "\n".join(lines)


## One line per known contact (up to `max_contacts_in_state`): who, whether hostile and why, where
## (live bearing if visible, else last-seen bearing + age), and what they hold. Reports when no one
## is known at all.
func _contact_lines(self_pos: Vector2, memory: RefCounted, known: Array) -> Array:
	if known.is_empty():
		return ["You don't see anyone and don't know where anyone is."]
	var out: Array = []
	for c in known.slice(0, max_contacts_in_state):
		var to: Vector2 = (c["pos"] as Vector2) - self_pos
		var where := "inside the house" if c.get("inside", false) else "outside the house"
		if c.get("inside", false) and c.get("room", "") != "":
			where += " (in the %s)" % c["room"]
		var status := "HOSTILE (%s)" % c["reason"] if c["hostile"] else "not hostile"
		var sight := "You can see %s" % c["name"] if c["visible"] else \
			"You last saw %s %.0fs ago" % [c["name"], _sighting_age(memory, c["id"])]
		out.append("%s — %s — %s, ~%dpx to your %s, holding a %s." % [
			sight, status, where, int(to.length()), _compass(to), c.get("item", "nothing")])
	return out


## Seconds since character `id` was last seen (INF if not remembered).
func _sighting_age(memory: RefCounted, id: int) -> float:
	for entry in memory.fresh():  # Newest first.
		if entry["topic"] == &"saw_character" and entry["data"].get("id") == id:
			return (Time.get_ticks_msec() - entry["at"]) / 1000.0
	return INF


## The awareness lines drawn from memory + current condition: being under fire (hit or shot at, with
## the incoming direction when known), any other remembered event carrying a `note` (freshest per
## topic), and the NPC's own injury level. Empty when nothing is remembered and it is unharmed.
func _awareness_lines(character, memory: RefCounted) -> Array:
	var out: Array = []
	if memory.is_fresh(&"under_fire"):
		var from: Vector2 = memory.recall(&"under_fire").get("from", Vector2.ZERO)
		if from != Vector2.ZERO:
			out.append("You are under fire from the %s!" % _compass(from))
		else:
			out.append("You are under fire — shots are striking close to you!")
	# Surface any other remembered event that carries a note, newest-per-topic (the log may hold many).
	var seen := {&"under_fire": true}
	for entry in memory.fresh():
		var topic = entry["topic"]
		if seen.has(topic):
			continue
		seen[topic] = true
		var note = entry["data"].get("note", "")
		if note != "":
			out.append(note)
	var dmg: float = character.damage_taken()
	if dmg >= critical_threshold:
		out.append("You are badly wounded.")
	elif dmg >= hurt_threshold:
		out.append("You are hurt.")
	return out


## The move options: one named destination per KNOWN room, where each known hostile was last seen,
## and the NPC's starting position. Described by place (no step-ring/distance spam — those make Von
## pick randomly). Consulted by the controller only when the chosen act implies no movement of its own.
func _moves(rooms: Array, memory: RefCounted, known: Array) -> Dictionary:
	var out := {}
	var known_rooms := _known_room_keys(memory)
	for room in rooms:
		if not known_rooms.has(room["key"]):
			continue
		var rect: Rect2 = room["rect"]
		out["room_%s" % room["key"]] = {
			"desc": "the %s" % room.get("type", "room"),
			"point": rect.position + rect.size * 0.5,
		}
	for c in known:
		if c["hostile"]:
			out["last_seen_%d" % c["id"]] = { "desc": "where you last saw %s" % c["name"], "point": c["pos"] }
	out["post"] = { "desc": "your starting position", "point": _post }
	return out


## The act options — the real decision, built from generic primitives: engage (shoot, if carrying the
## pistol, or punch) each KNOWN HOSTILE contact; search for hostiles when none is known; hold; and one
## "interact" option per DISTINCT action offered by a KNOWN object (each pointing at the nearest known
## object that offers it). Deduping by label keeps the options distinct and the menu bounded.
## Item-gated. Engage options carry the contact's `target` id.
func _acts(character, self_pos: Vector2, rooms: Array, memory: RefCounted, known: Array) -> Dictionary:
	var out := { "hold": { "desc": "wait and do nothing", "verb": "hold" } }
	var any_hostile := false
	for c in known:
		if not c["hostile"]:
			continue
		any_hostile = true
		if character.has_item(PISTOL_SLOT):
			out["shoot_%d" % c["id"]] = { "desc": "fire your pistol at %s (hostile: %s)" % [c["name"], c["reason"]],
				"verb": "shoot", "slot": PISTOL_SLOT, "target": c["id"] }
		out["punch_%d" % c["id"]] = { "desc": "punch %s (hostile: %s)" % [c["name"], c["reason"]],
			"verb": "punch", "slot": FISTS_SLOT, "target": c["id"] }
	if not any_hostile:
		out["search"] = { "desc": "search the house for hostiles", "verb": "search" }
	var known_objs := _known_object_ids(memory)
	var nearest := {}  # action label -> nearest known object + its spec (+ squared distance).
	for obj in _interactables:
		if not is_instance_valid(obj) or not known_objs.has(obj.get_instance_id()):
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


## Seed a familiar NPC's house knowledge once: remember every room and interactable as already-known
## (permanent ttl). An unfamiliar NPC skips this and learns by sight in observe(). Needs the rooms
## list, so it runs on the first observe() (not _ready).
func _seed_house(rooms: Array, memory: RefCounted, familiar: bool) -> void:
	if _seeded or not familiar:
		return
	_seeded = true
	for room in rooms:
		_learn_room(room, memory)
	for obj in _interactables:
		if is_instance_valid(obj):
			_learn_object(obj, memory)


## Remember a room as known (permanent). Idempotent-enough: duplicates are harmless and capped by the
## memory's capacity policy (which never volume-evicts permanent events).
func _learn_room(room: Dictionary, memory: RefCounted) -> void:
	if not _known_room_keys(memory).has(room["key"]):
		memory.remember(&"saw_room", { "key": room["key"] }, 0.0)


## Remember an interactable object as known (permanent), keyed by instance id.
func _learn_object(obj: Object, memory: RefCounted) -> void:
	if not _known_object_ids(memory).has(obj.get_instance_id()):
		memory.remember(&"saw_object", { "id": obj.get_instance_id() }, 0.0)


## The set of room keys the NPC currently knows (from `saw_room` memory), as a lookup dict.
func _known_room_keys(memory: RefCounted) -> Dictionary:
	var out := {}
	for data in memory.recall_all(&"saw_room"):
		out[data.get("key")] = true
	return out


## The set of interactable instance ids the NPC currently knows (from `saw_object` memory).
func _known_object_ids(memory: RefCounted) -> Dictionary:
	var out := {}
	for data in memory.recall_all(&"saw_object"):
		out[data.get("id")] = true
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


## Every other character in the world (a node with a current_item method, excluding the NPC itself),
## found by scanning from the shared world root. Used by observe() to test each for visibility.
func _other_characters(character) -> Array:
	var out: Array = []
	var root: Node = character.world_root()
	if root != null:
		_collect_characters(root, character, out)
	return out


## Recursively gather descendants that expose current_item() (characters), excluding `self_char`.
func _collect_characters(node: Node, self_char, out: Array) -> void:
	for child in node.get_children():
		if child != self_char and child.has_method("current_item"):
			out.append(child)
		_collect_characters(child, self_char, out)


## Whether character `id` was visible (in cone/range with a clear line) on the latest observe() tick.
func contact_visible(id: int) -> bool:
	return _visible_now.has(id)


## Whether the NPC has a clear line (no wall or solid furniture between) to a world `point` — the
## engaged contact's last-known position. The controller gates FIRING on this: once a contact is known,
## the NPC shoots when it has a clear line to where it knows they are (peeking around cover),
## independent of its view cone. Vision gates whether it KNOWS a contact; this gates whether it can hit
## them. Both the NPC and `target` (the contact's body) are excluded, so the target at `point` doesn't
## count as a block.
func has_line_to(character, target: Node2D, point: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	var exclude := [character.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	return not _blocked(space, character.global_position, point, exclude)


## Candidate standing points on a ring around the NPC, classified for peek-and-cover against the
## engaged contact's KNOWN position `tgt_pos` (last-seen, so the NPC maneuvers to regain a line on
## where it thinks they are): `fire` points have a clear line to it; `cover` points are shielded from it
## by a high-coverage solid object. Points the NPC can't reach in a straight line (a wall between)
## are dropped. Both lists are nearest-first, for the controller to pick from. The NPC and `target`
## are excluded from the rays so neither body counts as a wall.
func combat_spots(character, target: Node2D, tgt_pos: Vector2, radius: float, count: int) -> Dictionary:
	var self_pos: Vector2 = character.global_position
	var exclude := [character.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
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
