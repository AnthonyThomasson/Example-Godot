extends Node

## AI domain: perception/sensor for a goal-driven NPC. It has two halves. `observe()` is the SEE
## pass — run every tick, it tests what is currently visible (via the vision sense, agent_vision.gd),
## deposits sightings into the agent's memory (agent_memory.gd) — every other character
## (`saw_character`, with a smoothed movement track, its facing and raw hit-damage) and, for an NPC
## that must learn its surroundings, rooms and objects (`saw_room` / `saw_object`) — notes the rooms it
## has searched, and runs each character sighting through the hostility rules (agent_hostility.gd).
## `contacts()` is the resulting view: every character the agent knows of, hostile or not. `sense()`
## is the BUILD pass — run at the start of each decision, it gathers what the agent knows (contacts,
## callouts, learned house knowledge) and hands it to the SNAPSHOT AUTHOR (agent_snapshot.gd), which
## turns it into the SNAPSHOT the decision planner walks (facts / sections / option groups). The NPC
## knows only what it has perceived — sight, nearby hits, gunfire within earshot, and its allies' radio
## callouts — and that knowledge decays as the memory does.
##
## This is the PERCEPTION sub-domain's public face: it OWNS the sight sense (agent_vision.gd), the
## hostility rules (agent_hostility.gd), the event memory (agent_memory.gd), the combat geometry
## (agent_tactics.gd) and the snapshot author (agent_snapshot.gd) as internal modules, and surfaces
## knowledge only through its own methods. It holds NO policy: it never decides, gates by goal or
## picks — and the measured wording Von reads lives in the snapshot author, not here. The controller
## configures it (all tunables live on the GoalController, the single authoring surface) then calls
## `setup()` once.

## The internal modules this sub-domain owns (built in setup() from the config fields).
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentHostility := preload("res://scenes/ai/perception/agent_hostility.gd")
const AgentMemory := preload("res://scenes/ai/perception/agent_memory.gd")
const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
## The BUILD half: turns what the NPC knows + the combat geometry into the decision snapshot Von walks.
const AgentSnapshot := preload("res://scenes/ai/perception/agent_snapshot.gd")

## Lifetime (s) of a live contact: the window the NPC keeps acting on a last-seen position.
var contact_memory_ttl: float = 4.0
## Whether this NPC starts knowing the house (rooms + objects), else learns them by sight.
var familiar_with_house: bool = true
## The house entrance in world space (injected by Main for some NPCs), offered while outside.
var entry_point: Vector2 = Vector2.ZERO

# --- Config fields the controller copies from its exports before calling setup(). ---
# Vision (the sight sense).
var vision_enabled: bool = true
var view_distance: float = 2520.0
var fov_degrees: float = 110.0
var awareness_radius: float = 48.0
var see_over_coverage: float = 60.0
# Hostility (the categorization rules).
var hostile_on_sight: bool = false
var hostile_on_trespass: bool = false
var hostile_on_attack: bool = true
var hostility_ttl: float = 0.0
var allied_factions: Array[StringName] = []
# Memory (the event log) and how long each kind of knowledge lasts.
var memory_capacity: int = 128
var memory_default_ttl: float = 0.0
var lead_memory_ttl: float = 20.0
var search_memory_ttl: float = 60.0
# Combat awareness (how hits and gunfire are remembered — see process_hit()).
var hit_awareness_radius: float = 160.0
var hearing_radius: float = 900.0
var under_fire_time: float = 3.0
var engage_dwell: float = 3.0
# Context: how knowledge is worded and bounded for Von.
var shoot_range: float = 500.0
var punch_range: float = 48.0
var recency_bands: Vector2 = Vector2(2.0, 8.0)
var route_buckets: Vector2 = Vector2(400.0, 900.0)
var aim_cone: float = 20.0
var still_speed: float = 20.0
var track_smoothing: float = 0.3
var extrapolate_cap: float = 3.0
var investigate_distance: float = 300.0
var max_options_per_level: int = 4
var hurt_threshold: float = 15.0       ## Accumulated damage at/above which a character reads as hurt.
var critical_threshold: float = 35.0   ## Accumulated damage at/above which a character reads as badly wounded.
var max_contacts_in_state: int = 4     ## Most contacts described in the decision state (hostiles first).
# Tactics (the combat geometry).
var cover_min: float = 40.0            ## Surface coverage at/above which a blocking object counts as cover.
var flank_distance: float = 220.0
var flank_arc: float = 60.0
var flank_ally_radius: float = 500.0
var combat_ring_radius: float = 80.0
var combat_ring_count: int = 12
var route_clearance: float = 120.0
var watch_arc: float = 90.0
var fire_spot_distances: Array[float] = [200.0, 350.0]
# Callouts (allies' radio).
var callout_range: float = 1500.0
var callout_ttl: float = 6.0

var _vision: RefCounted          ## The sight sense (FOV/range/LoS); see agent_vision.gd.
var _hostility: RefCounted       ## The hostility rules; see agent_hostility.gd.
var _memory: RefCounted          ## The event memory; see agent_memory.gd.
var _tactics: RefCounted         ## The combat geometry; see agent_tactics.gd.
var _snapshot: RefCounted        ## The BUILD half: writes the decision snapshot; see agent_snapshot.gd.
var _post := Vector2.ZERO        ## The NPC's spawn position, captured on the first observe() call.
var _post_set := false           ## Whether _post has been captured yet.
var _interactables: Array = []   ## Cached world objects that advertise interactions (static furniture).
var _scanned := false            ## Whether the one-time interactable scan has run.
var _seeded := false             ## Whether the familiar-NPC house-knowledge seed has run.
var _visible_now := {}           ## Instance ids of characters visible on the latest observe() tick.
var _tracks := {}                ## Per-character movement track: id → { pos, vel, t } (last seen).


## Build the owned sensing modules. The controller calls this once in its _ready(); it then pushes the
## config fields into the modules with apply_config() (here, and again each decision so a runtime
## retune takes effect). Building and configuring are separate so apply_config() never rebuilds a
## module — that would wipe the event memory and the sight state.
func setup() -> void:
	_vision = AgentVision.new()
	_hostility = AgentHostility.new()
	_memory = AgentMemory.new()
	_tactics = AgentTactics.new()
	_tactics.vision = _vision
	_snapshot = AgentSnapshot.new()
	_snapshot.setup(_memory, _tactics)


## Push the current config fields into the owned modules. Idempotent and state-free (it only sets
## tunables, never the memory log or hostility faction), so the controller may call it every decision
## to keep the modules in step with exports retuned at runtime (e.g. by the dev command server).
func apply_config() -> void:
	_vision.enabled = vision_enabled
	_vision.view_distance = view_distance
	_vision.fov_degrees = fov_degrees
	_vision.awareness_radius = awareness_radius
	_vision.see_over_coverage = see_over_coverage
	_hostility.on_sight = hostile_on_sight
	_hostility.trespass = hostile_on_trespass
	_hostility.retaliate = hostile_on_attack
	_hostility.ttl = hostility_ttl
	_hostility.allies = allied_factions
	_memory.capacity = memory_capacity
	_memory.default_ttl = memory_default_ttl
	_tactics.cover_min = cover_min
	_tactics.flank_distance = flank_distance
	_tactics.flank_arc = flank_arc
	_tactics.flank_ally_radius = flank_ally_radius
	_tactics.shoot_range = shoot_range
	_tactics.combat_ring_radius = combat_ring_radius
	_tactics.combat_ring_count = combat_ring_count
	_tactics.still_speed = still_speed
	_tactics.route_clearance = route_clearance
	_tactics.watch_arc = watch_arc
	_tactics.fire_spot_distances = fire_spot_distances
	_snapshot.shoot_range = shoot_range
	_snapshot.punch_range = punch_range
	_snapshot.recency_bands = recency_bands
	_snapshot.route_buckets = route_buckets
	_snapshot.aim_cone = aim_cone
	_snapshot.still_speed = still_speed
	_snapshot.flank_ally_radius = flank_ally_radius
	_snapshot.investigate_distance = investigate_distance
	_snapshot.extrapolate_cap = extrapolate_cap
	_snapshot.max_options_per_level = max_options_per_level
	_snapshot.hurt_threshold = hurt_threshold
	_snapshot.critical_threshold = critical_threshold
	_snapshot.max_contacts_in_state = max_contacts_in_state
	_snapshot.search_memory_ttl = search_memory_ttl


## Tell the hostility rules this NPC's own faction (so allies are never hostile). The controller
## calls this once it knows which character it drives.
func set_faction(faction: StringName) -> void:
	_hostility.faction = faction


# --- Event intake ----------------------------------------------------------------------------

## Classify one world `&"hit"` event (interface 10) against this NPC and fold it into memory. A hit ON
## the NPC, or any hit within `hit_awareness_radius` of it, counts as being attacked: the incoming
## direction (and whether it actually hit) is remembered (`under_fire`), the engagement is refreshed
## (`engaged`), and the attacker is handed to the hostility rules. A hit farther off but within
## `hearing_radius` is gunfire heard (`heard_gunfire`) — an investigation lead — but ONLY from a shooter
## the NPC doesn't already know is hostile: gunfire from a character it is fighting (or any other known
## hostile) is no mystery, already covered by COMBAT or that contact's last-seen lead, so it is not a lead
## to chase. The NPC's own hits are ignored. Returns true when it was a relevant attack, so the controller
## can kick off a fight.
func process_hit(character, data: Dictionary) -> bool:
	var attacker = data.get("attacker")
	if attacker == character:
		return false  # Our own shot or punch.
	var self_pos: Vector2 = character.global_position
	var pos: Vector2 = data.get("position", self_pos)
	var from: Vector2 = -(data.get("direction", Vector2.RIGHT) as Vector2)
	var hit_me: bool = data.get("victim") == character
	if not hit_me and self_pos.distance_to(pos) > hit_awareness_radius:
		var known_shooter: bool = attacker is Node and is_instance_valid(attacker) \
			and _hostility.is_hostile(attacker.get_instance_id(), _memory)
		if self_pos.distance_to(pos) <= hearing_radius and not known_shooter:
			var cell := "%d,%d" % [floori(pos.x / 200.0), floori(pos.y / 200.0)]
			_memory.remember(&"heard_gunfire", { "pos": pos, "from": from }, lead_memory_ttl, cell)
		return false
	_memory.remember(&"under_fire", { "from": from, "hit": hit_me }, under_fire_time, "latest")
	_memory.remember(&"engaged", {}, engage_dwell, "latest")
	if attacker is Node and is_instance_valid(attacker):
		_hostility.on_attacked(attacker, _memory)
	return true


## Fold one ally radio `&"callout"` (interface 10) into memory: what an ally says it is doing — its
## tactic, target and destination. Ignores its own, non-allies, dead speakers, and anything beyond
## `callout_range` (<= 0 = unlimited). Each speaker's latest callout supersedes its earlier one.
func process_callout(character, data: Dictionary) -> void:
	var speaker = data.get("speaker")
	if speaker == character or not speaker is Node or not is_instance_valid(speaker) or speaker.get("is_dead") == true:
		return
	if not _hostility.is_ally(data.get("faction", &"")):
		return
	var at: Vector2 = data.get("position", character.global_position)
	if callout_range > 0.0 and character.global_position.distance_to(at) > callout_range:
		return
	_memory.remember(&"heard_callout", data, callout_ttl, str(speaker.get_instance_id()))


## Refresh the combat engagement (called by the behaviour when it fires or adopts a fight), so an
## active firefight stays committed between decisions.
func note_engaged() -> void:
	_memory.remember(&"engaged", {}, engage_dwell, "latest")


## Whether the NPC is still committed to a fight (an `engaged` event is fresh).
func engaged_fresh() -> bool:
	return _memory.is_fresh(&"engaged")


## Whether the NPC is currently under fire (a recent incoming/nearby hit).
func under_fire() -> bool:
	return _memory.is_fresh(&"under_fire")


## Whether the NPC was actually hit (not just shot at) within the under-fire window.
func hit_recently() -> bool:
	return under_fire() and _memory.recall(&"under_fire").get("hit", false)


## The cheap facts the controller needs between decisions (e.g. to see whether a new situation should
## interrupt the decision in flight), without building the whole snapshot.
func quick_facts(character) -> Dictionary:
	var hostile_known := contacts(character.global_position).any(func(c): return c["hostile"])
	return {
		"under_fire": under_fire(),
		"engaged": engaged_fresh(),
		"hostile_known": hostile_known,
		"threat_known": hostile_known or under_fire(),
	}


## The NPC reached investigation lead `lead_id` (its option carried the id in `params.lead`): remember
## it as checked, so it isn't offered again until something newer happens there.
func check_lead(lead_id: String) -> void:
	_memory.remember(&"checked_lead", { "id": lead_id }, lead_memory_ttl, lead_id)


## Number of events in memory, for the debug snapshot.
func memory_size() -> int:
	return _memory.size()


## Debug read: every room tagged by how this NPC regards it right now — the one it stands in
## (`current`), a room it has seen and searched recently (`searched`) or seen but not searched
## (`unsearched`), or one it has not yet seen at all (`unknown`). This is the room reasoning the
## search/room/flank options are placed against, exposed for the tactics debug overlay to draw as
## zones. A pure read of knowledge + the visited-room memory; never perturbs it.
func room_status(rooms: Array, self_pos: Vector2) -> Array:
	var known := _known_room_keys()
	var here := _room_at(self_pos, rooms)
	var out: Array = []
	for room in rooms:
		var status: StringName
		if not here.is_empty() and room["key"] == here["key"]:
			status = &"current"
		elif not known.has(room["key"]):
			status = &"unknown"
		elif _memory.age_of(&"visited_room", "key", room["key"]) > search_memory_ttl:
			status = &"unsearched"
		else:
			status = &"searched"
		out.append({ "rect": room["rect"], "type": str(room["type"]).replace("_", " "), "status": status })
	return out


# --- SEE -------------------------------------------------------------------------------------

## SEE pass — run every tick. Test what is visible via `vision` and remember it, so the agent's
## knowledge stays fresh while it can see and decays once it can't; each character sighting is also
## categorized by `hostility`. A familiar NPC's house knowledge is seeded on the first call. People
## are never seeded — they are known only once seen.
func observe(character, rooms: Array) -> void:
	if not _post_set:
		_post = character.global_position
		_post_set = true
	_ensure_interactables(character)
	_seed_house(rooms)

	var self_pos: Vector2 = character.global_position
	var facing: Vector2 = character.facing
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	var exclude := [character.get_rid()]
	var now := Time.get_ticks_msec()

	# Every other character (the player included): one sighting per character, superseded while it
	# stays visible. Dead characters are skipped — corpses add no tactical information.
	_visible_now.clear()
	for other in _other_characters(character):
		if other.get("is_dead") == true:
			continue
		if not _vision.can_see_node(other, self_pos, facing, space, exclude):
			continue
		var id: int = other.get_instance_id()
		var pos: Vector2 = other.global_position
		var room := _room_at(pos, rooms)
		var item = other.current_item()
		var f = other.get("faction")
		var sighting := {
			"id": id,
			"node": other,
			"name": str(other.name),
			"faction": f if f != null else &"",
			"ally": _hostility.is_ally(f if f != null else &""),
			"pos": pos,
			"vel": _track(id, pos, now),
			"facing": other.get("facing") if other.get("facing") is Vector2 else Vector2.ZERO,
			"wound_dmg": other.damage_taken() if other.has_method("damage_taken") else 0.0,
			"inside": not room.is_empty(),
			"room_type": room.get("type", "") if not room.is_empty() else "",
			"item": item.display_name if item != null else "nothing",
		}
		_visible_now[id] = true
		_memory.remember(&"saw_character", sighting, maxf(contact_memory_ttl, lead_memory_ttl), str(id))
		_hostility.classify(sighting, _memory)

	# The room the NPC stands in counts as searched (superseded while it stays there).
	var here := _room_at(self_pos, rooms)
	if not here.is_empty():
		_memory.remember(&"visited_room", { "key": here["key"] }, search_memory_ttl, str(here["key"]))

	# An unfamiliar NPC learns rooms and objects by seeing them (permanent once learned).
	if not familiar_with_house:
		for room in rooms:
			var rect: Rect2 = room["rect"]
			if rect.has_point(self_pos) or _vision.can_see(self_pos, facing, rect.position + rect.size * 0.5, space, exclude):
				_learn_room(room)
		for obj in _interactables:
			if is_instance_valid(obj) and _vision.can_see_node(obj, self_pos, facing, space, exclude):
				_learn_object(obj)


## Update character `id`'s movement track with a sighting at `pos` and return its smoothed velocity.
## A sighting after a long gap restarts the track (no velocity across the gap).
func _track(id: int, pos: Vector2, now: int) -> Vector2:
	var vel := Vector2.ZERO
	var tr = _tracks.get(id)
	if tr != null:
		var dt: float = (now - tr["t"]) / 1000.0
		if dt > 0.0 and dt < 0.5:
			vel = (tr["vel"] as Vector2).lerp((pos - tr["pos"]) / dt, track_smoothing)
		elif dt == 0.0:
			vel = tr["vel"]
	_tracks[id] = { "pos": pos, "vel": vel, "t": now }
	return vel


## Every character the agent currently knows of (seen within `contact_memory_ttl`) — the latest
## sighting per character, with `hostile` / `reason`, `visible` (seen on the latest tick) and `age`.
## Hostiles first, then nearest to `self_pos`. Dead or freed characters are dropped.
func contacts(self_pos: Vector2) -> Array:
	return _sightings(self_pos, contact_memory_ttl)


## Every character in memory regardless of contact_memory_ttl — all non-expired sightings (up to
## lead_memory_ttl, typically 20 s). Same dict shape as contacts() but covers stale sightings too,
## so external observers (e.g. the spectator inspector) can see the NPC's full knowledge window.
func all_seen_characters(self_pos: Vector2) -> Array:
	return _sightings(self_pos)


## Hostiles the NPC has lost track of — last seen longer ago than `contact_memory_ttl` but within
## `lead_memory_ttl` — newest first: where to investigate.
func lost_hostiles() -> Array:
	return _sightings(null, INF, contact_memory_ttl, true)


## The live character sightings in memory as contact dicts — the one source behind contacts(),
## all_seen_characters() and lost_hostiles(). Keeps sightings with age in (`min_age`, `max_age`];
## `hostile_only` drops non-hostiles; dead or freed characters are always dropped. Given a
## `self_pos` (a Vector2) the result is sorted hostiles-first then nearest to it, else it keeps the
## memory's newest-first order.
func _sightings(self_pos, max_age := INF, min_age := -1.0, hostile_only := false) -> Array:
	var out: Array = []
	for rec in _memory.recall_aged(&"saw_character"):
		if rec["age"] > max_age or rec["age"] <= min_age:
			continue
		var c := _live_sighting(rec)
		if c.is_empty() or (hostile_only and not c["hostile"]):
			continue
		out.append(c)
	if self_pos is Vector2:
		out.sort_custom(func(a, b):
			if a["hostile"] != b["hostile"]:
				return a["hostile"]
			return (a["pos"] as Vector2).distance_squared_to(self_pos) < (b["pos"] as Vector2).distance_squared_to(self_pos))
	return out


## A remembered sighting (`{ data, age }`) as a contact dict, or empty when its character is gone.
func _live_sighting(rec: Dictionary) -> Dictionary:
	var data: Dictionary = rec["data"]
	var n = data.get("node")
	if not is_instance_valid(n) or (n as Node).get("is_dead") == true:
		return {}
	var c := data.duplicate()
	c["age"] = rec["age"]
	c["reason"] = _hostility.reason(c["id"], _memory)
	c["hostile"] = c["reason"] != ""
	c["visible"] = _visible_now.has(c["id"])
	return c


## Live ally callouts heard (latest per speaker), with `age`, `name` and the speaker's `id`.
func _callouts() -> Array:
	var out: Array = []
	for rec in _memory.recall_aged(&"heard_callout"):
		var speaker = rec["data"].get("speaker")
		if not is_instance_valid(speaker) or (speaker as Node).get("is_dead") == true:
			continue
		var c: Dictionary = rec["data"].duplicate()
		c["age"] = rec["age"]
		c["id"] = speaker.get_instance_id()
		c["name"] = str(speaker.name)
		out.append(c)
	return out


# --- BUILD (delegated to the snapshot author) ------------------------------------------------

## BUILD pass — run at the start of each decision. Gather what the NPC currently knows (contacts,
## allies' callouts, learned house knowledge, lost hostiles) and hand it, with the goal and the
## behaviour's current-activity line, to the snapshot author (agent_snapshot.gd), which turns it into
## the decision snapshot the planner walks: { facts, sections, sections_per_target, options }. The
## author reads this knowledge and the combat geometry only — it writes no memory and holds no policy.
func sense(character, rooms: Array, goal: String, activity: String) -> Dictionary:
	var self_pos: Vector2 = character.global_position
	var knowledge := {
		"known_rooms": _known_rooms(rooms),
		"known_room_keys": _known_room_keys(),
		"known_object_ids": _known_object_ids(),
		"interactables": _interactables,
		"post": _post,
		"entry_point": entry_point,
		"lost": lost_hostiles(),
	}
	return _snapshot.build(character, rooms, goal, activity, contacts(self_pos), _callouts(), knowledge)


# --- House knowledge -------------------------------------------------------------------------

## Seed a familiar NPC's house knowledge once: remember every room and interactable as already-known
## (permanent ttl). An unfamiliar NPC skips this and learns by sight in observe(). Needs the rooms
## list, so it runs on the first observe() (not _ready).
func _seed_house(rooms: Array) -> void:
	if _seeded or not familiar_with_house:
		return
	_seeded = true
	for room in rooms:
		_learn_room(room)
	for obj in _interactables:
		if is_instance_valid(obj):
			_learn_object(obj)


## Remember a room as known (permanent).
func _learn_room(room: Dictionary) -> void:
	if not _known_room_keys().has(room["key"]):
		_memory.remember(&"saw_room", { "key": room["key"] }, 0.0, str(room["key"]))


## Remember an interactable object as known (permanent), keyed by instance id.
func _learn_object(obj: Object) -> void:
	if not _known_object_ids().has(obj.get_instance_id()):
		_memory.remember(&"saw_object", { "id": obj.get_instance_id() }, 0.0, str(obj.get_instance_id()))


## The rooms the NPC knows (all of `rooms` whose key it has learned), in `rooms` order.
func _known_rooms(rooms: Array) -> Array:
	var known := _known_room_keys()
	return rooms.filter(func(r): return known.has(r["key"]))


## The set of room keys the NPC currently knows (from `saw_room` memory), as a lookup dict.
func _known_room_keys() -> Dictionary:
	var out := {}
	for data in _memory.recall_all(&"saw_room"):
		out[data.get("key")] = true
	return out


## The set of interactable instance ids the NPC currently knows (from `saw_object` memory).
func _known_object_ids() -> Dictionary:
	var out := {}
	for data in _memory.recall_all(&"saw_object"):
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


# --- Combat geometry for the behaviour -------------------------------------------------------

## Whether the NPC has a clear line (no wall or solid furniture between) to a world `point` — the
## engaged contact's last-known position. The behaviour gates FIRING on this: once a contact is known,
## the NPC shoots when it has a clear line to where it knows they are, independent of its view cone.
## Both the NPC and `target` (the contact's body) are excluded, so the target doesn't block itself.
func has_line_to(character, target: Node2D, point: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	var exclude := [character.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	return not _tactics.blocked(space, character.global_position, point, exclude)


## Candidate standing points on a ring around the NPC, classified for peek-and-cover against the
## engaged contact's KNOWN position `tgt_pos`: `fire` points have a clear line to it; `cover` points
## are shielded from it by a high-coverage solid. Both nearest-first (see agent_tactics.gd).
func combat_spots(character, target: Node2D, tgt_pos: Vector2, radius: float, count: int) -> Dictionary:
	var exclude := [character.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	return _tactics.combat_spots(space, character.global_position, tgt_pos, exclude, radius, count)


## The room dict whose rect contains `p`, or empty when `p` is outside every room.
func _room_at(p: Vector2, rooms: Array) -> Dictionary:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return room
	return {}
