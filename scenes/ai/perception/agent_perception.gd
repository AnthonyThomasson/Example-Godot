extends Node

## AI domain: perception/sensor for a goal-driven NPC. It has two halves. `observe()` is the SEE
## pass — run every tick, it tests what is currently visible (via the vision sense, agent_vision.gd),
## deposits sightings into the agent's memory (agent_memory.gd) — every other character
## (`saw_character`, with a smoothed movement track, its facing and visible wounds) and, for an NPC
## that must learn its surroundings, rooms and objects (`saw_room` / `saw_object`) — notes the rooms it
## has searched, and runs each character sighting through the hostility rules (agent_hostility.gd).
## `contacts()` is the resulting view: every character the agent knows of, hostile or not. `sense()`
## is the BUILD pass — run at the start of each decision, it turns what the agent sees AND remembers
## into the SNAPSHOT the decision planner walks: named state `sections` Von reads, named boolean
## `facts` the tree gates on, and named option `groups` — places and things with the attributes a
## choice turns on (a flanking side, a firing spot, a room to search, a lead to check). The NPC knows
## only what it has perceived — sight, nearby hits, gunfire within earshot, and its allies' radio
## callouts — and that knowledge decays as the memory does.
##
## Everything Von reads is worded for a CLASSIFIER that picks the option whose text best matches the
## state and cannot do arithmetic: distances, routes and ages are BANDS ("in pistol range", "short
## route", "recently"); each option carries the facts that distinguish it from its siblings, in a
## fixed order; there are NO negations (an encoder reads "no cover" as "cover" — say "in the open",
## "line blocked", "free", "unsearched"); and the state uses the same canonical phrases the decision
## tree's situation descriptions are written in ("You have a clear shot at X from where you stand",
## "your line to them is blocked", "exposed to their fire", "being hit"), so a fact in the state
## lights up the option it argues for. Options are places and things, never verbs — the decision tree
## decides what to do at them.
##
## This is the PERCEPTION sub-domain's public face: it OWNS the sight sense (agent_vision.gd), the
## hostility rules (agent_hostility.gd), the event memory (agent_memory.gd) and the combat geometry
## (agent_tactics.gd) as internal modules, and surfaces knowledge only through its own methods. It
## holds NO policy: it never decides, gates by goal or picks. The controller configures it (all
## tunables live on the GoalController, the single authoring surface) then calls `setup()` once.

## Inventory slots of the combat items (ItemRegistry ids).
const PISTOL_SLOT := 3
const FISTS_SLOT := 2
## Compass names for an 8-wind direction, indexed clockwise from east (screen +y is south).
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
## How each flank side of a target is named to Von.
const SIDE_WORDS := { "left": "their left side", "right": "their right side", "rear": "behind them", "front": "their front" }

## The internal sensing modules this sub-domain owns (built in setup() from the config fields).
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentHostility := preload("res://scenes/ai/perception/agent_hostility.gd")
const AgentMemory := preload("res://scenes/ai/perception/agent_memory.gd")
const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")

## Surface coverage (0–100) at or above which a blocking object counts as usable cover.
@export var cover_min: float = 40.0
## Accumulated damage (see Character.damage_taken) at or above which a character is hurt.
@export var hurt_threshold: float = 15.0
## Accumulated damage at or above which a character is badly wounded.
@export var critical_threshold: float = 35.0
## Most contacts described in the decision state (hostiles first, then nearest).
@export var max_contacts_in_state: int = 4

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
# Tactics (the combat geometry).
var flank_distance: float = 220.0
var flank_arc: float = 60.0
var flank_ally_radius: float = 500.0
var combat_ring_radius: float = 80.0
var combat_ring_count: int = 12
# Callouts (allies' radio).
var callout_range: float = 1500.0
var callout_ttl: float = 6.0

var _vision: RefCounted          ## The sight sense (FOV/range/LoS); see agent_vision.gd.
var _hostility: RefCounted       ## The hostility rules; see agent_hostility.gd.
var _memory: RefCounted          ## The event memory; see agent_memory.gd.
var _tactics: RefCounted         ## The combat geometry; see agent_tactics.gd.
var _post := Vector2.ZERO        ## The NPC's spawn position, captured on the first observe() call.
var _post_set := false           ## Whether _post has been captured yet.
var _interactables: Array = []   ## Cached world objects that advertise interactions (static furniture).
var _scanned := false            ## Whether the one-time interactable scan has run.
var _seeded := false             ## Whether the familiar-NPC house-knowledge seed has run.
var _visible_now := {}           ## Instance ids of characters visible on the latest observe() tick.
var _tracks := {}                ## Per-character movement track: id → { pos, vel, t } (last seen).
var _rooms_cache: Array = []     ## The rooms list last seen by observe(), for room lookups in wording.


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


## Push the current config fields into the owned modules. Idempotent and state-free (it only sets
## tunables, never the memory log or hostility faction), so the controller may call it every decision
## to keep the modules in step with exports retuned at runtime (e.g. by the dev command server).
func apply_config() -> void:
	_vision.enabled = vision_enabled
	_vision.view_distance = view_distance
	_vision.fov_degrees = fov_degrees
	_vision.awareness_radius = awareness_radius
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
			"wound": _wound_band(other.damage_taken() if other.has_method("damage_taken") else 0.0),
			"inside": not room.is_empty(),
			"room": _room_name(room.get("type", "")) if not room.is_empty() else "",
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
	var out: Array = []
	for rec in _memory.recall_aged(&"saw_character"):
		if rec["age"] > contact_memory_ttl:
			continue
		var c := _live_sighting(rec)
		if not c.is_empty():
			out.append(c)
	out.sort_custom(func(a, b):
		if a["hostile"] != b["hostile"]:
			return a["hostile"]
		return (a["pos"] as Vector2).distance_squared_to(self_pos) < (b["pos"] as Vector2).distance_squared_to(self_pos))
	return out


## Hostiles the NPC has lost track of — last seen longer ago than `contact_memory_ttl` but within
## `lead_memory_ttl` — newest first: where to investigate.
func lost_hostiles() -> Array:
	var out: Array = []
	for rec in _memory.recall_aged(&"saw_character"):
		if rec["age"] <= contact_memory_ttl:
			continue
		var c := _live_sighting(rec)
		if not c.is_empty() and c["hostile"]:
			out.append(c)
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


# --- BUILD -----------------------------------------------------------------------------------

## BUILD pass — run at the start of each decision. Assemble the snapshot the decision planner walks,
## from what the agent currently sees and remembers (NOT from ground truth): `goal` is the behaviour
## string Von ranks against; `activity` is the behaviour's line for what the NPC is doing now.
## Returns { facts, sections, sections_per_target, options } — see the class note.
func sense(character, rooms: Array, goal: String, activity: String) -> Dictionary:
	var self_pos: Vector2 = character.global_position
	var known := contacts(self_pos)
	var hostiles: Array = known.filter(func(c): return c["hostile"])
	var allies: Array = known.filter(func(c): return c["ally"] and not c["hostile"])
	var ctx := {
		"space": character.get_world_2d().direct_space_state,
		"map": character.get_world_2d().navigation_map,
		"self_pos": self_pos,
		"exclude": [character.get_rid()],
		"hostiles": hostiles,
		"allies": allies,
		"callouts": _callouts(),
	}
	var known_rooms: Array = _known_rooms(rooms)

	# Per known hostile: the combat geometry, the option groups and the sections that follow from it.
	var per_target := {}
	var per_sections := {}
	var analyses := {}
	for t in hostiles.slice(0, max_options_per_level):
		var a := _analyze(ctx, t)
		analyses[t["id"]] = a
		per_target[t["id"]] = {
			"fire_positions": _fire_group(ctx, t, a),
			"flank_sides": _flank_group(t, a, rooms),
			"advance_positions": _advance_group(ctx, t, a),
			"melee": { "summary": "they are %s and hold a %s" % [_dist_band(self_pos.distance_to(t["pos"])), t.get("item", "nothing")] },
		}
		per_sections[t["id"]] = {
			"exposure": _exposure_text(ctx, t, a),
			"flanks": _flanks_text(t, a),
			"allies": _allies_text(ctx, t, a),
		}

	var primary: Dictionary = hostiles[0] if not hostiles.is_empty() else {}
	var line: Dictionary = analyses[primary["id"]]["line"] if not primary.is_empty() else {}
	var leads := _lead_group(ctx, hostiles)
	var dmg: float = character.damage_taken()
	var facts := {
		"hostile_known": not hostiles.is_empty(),
		"hostile_visible": hostiles.any(func(c): return c["visible"]),
		"threat_known": not hostiles.is_empty() or under_fire(),
		"has_pistol": character.has_item(PISTOL_SLOT),
		"under_fire": under_fire(),
		"hit_recently": hit_recently(),
		"engaged": engaged_fresh(),
		"leads": not leads["options"].is_empty(),
		"hurt": dmg >= hurt_threshold,
		"critical": dmg >= critical_threshold,
		"inside": not _room_at(self_pos, rooms).is_empty(),
		"exposed": line.get("clear", false) or (primary.is_empty() and under_fire()),
		"in_cover": line.get("cover", "") != "",
	}
	var sections := {
		"goal": goal,
		"situation": _situation_text(character, rooms),
		"current": ("Current activity: %s." % activity) if activity != "" else "",
		"odds": _odds_text(hostiles, allies, ctx["callouts"], not leads["options"].is_empty()),
		"contacts": _contacts_text(self_pos, known),
		"exposure": per_sections[primary["id"]]["exposure"] if not primary.is_empty() else _unseen_fire_text(),
		"allies": per_sections[primary["id"]]["allies"] if not primary.is_empty() else _allies_text(ctx, {}, {}),
		"flanks": per_sections[primary["id"]]["flanks"] if not primary.is_empty() else "",
		"awareness": _awareness_text(self_pos, not hostiles.is_empty()),
	}
	var options := {
		"per_target": per_target,
		"threat": { "summary": _threat_summary(self_pos, hostiles) },
		"hostiles": _hostile_group(ctx, hostiles, analyses),
		"retreat_positions": _retreat_group(ctx, hostiles, known_rooms, dmg),
		"leads": leads,
		"shooter": _shooter_group(ctx, hostiles),
		"search_rooms": _search_group(ctx, known_rooms, rooms),
		"explore": _explore_group(ctx, rooms),
		"interactions": _interaction_group(character, self_pos, rooms),
		"rooms": _room_group(ctx, known_rooms, rooms),
	}
	return { "facts": facts, "sections": sections, "sections_per_target": per_sections, "options": options }


## The combat geometry around hostile `t`: its frame (front bearing), the line between the NPC and it,
## and the candidate fire / flank / advance positions.
func _analyze(ctx: Dictionary, t: Dictionary) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var front: float = _tactics.front_angle(t, self_pos, t["visible"] or t["age"] <= recency_bands.y)
	var ex: Array = ctx["exclude"] + _tactics.body_rid(t)
	var obj = _tactics.blocker(ctx["space"], self_pos, t["pos"], ex)
	return {
		"front": front,
		"own_side": _tactics.side_of(t["pos"], front, self_pos),
		"line": {
			"clear": obj == null,
			"in_range": self_pos.distance_to(t["pos"]) <= shoot_range,
			"cover": _tactics.object_label(obj) if _tactics.is_cover(obj) else "",
			"blocker": _tactics.object_label(obj),
		},
		"fire": _tactics.fire_positions(ctx, t),
		"flanks": _tactics.flank_sides(ctx, t, front),
		"advance": _tactics.advance_positions(ctx, t),
	}


# --- Sections: the state text Von reads ------------------------------------------------------

## Where the NPC is, whether it is free, what it holds and how hurt it is.
func _situation_text(character, rooms: Array) -> String:
	var room := _room_at(character.global_position, rooms)
	var where := ("in the %s, inside the house" % _room_name(room["type"])) if not room.is_empty() else "outside the house"
	var busy := (" You are busy: %s." % character.interaction_label()) if character.is_busy() else ""
	return "You are %s, holding a %s.%s You are %s." % [
		where, character.current_item().display_name, busy, _health_band(character.damage_taken())]


## How many hostiles the NPC knows of against which allies it has. With none known it says whether
## it is quiet or there is trouble out of sight (`trouble`: there are leads to investigate) — "All
## quiet" must not be said while gunfire is fresh, since the SEARCH situation echoes it.
func _odds_text(hostiles: Array, allies: Array, callouts: Array, trouble: bool) -> String:
	var names: Array = allies.map(func(a): return a["name"])
	for c in callouts:
		if not names.has(c["name"]):
			names.append(c["name"])
	var ally_text := ", ".join(names) if not names.is_empty() else "none"
	if hostiles.is_empty():
		var lead := "All quiet so far."
		if under_fire():
			lead = "Someone you cannot see is shooting at you."
		elif trouble:
			lead = "There is trouble nearby, out of your sight."
		return "%s Allies near you: %s." % [lead, ally_text]
	var in_sight := hostiles.filter(func(c): return c["visible"]).size()
	return "Known hostiles: %d (%d in sight). Allies near you: %s." % [hostiles.size(), in_sight, ally_text]


## One line per known non-ally contact (hostiles first, up to `max_contacts_in_state`).
func _contacts_text(self_pos: Vector2, known: Array) -> String:
	var others: Array = known.filter(func(c): return not c["ally"] or c["hostile"])
	if others.is_empty():
		return "Nobody else is in sight or known."
	var lines: Array = []
	for c in others.slice(0, max_contacts_in_state):
		lines.append(_contact_line(c, self_pos, known))
	return "\n".join(lines)


## A contact as Von reads it: who, hostility, sight, distance band + bearing + place, movement, aim,
## weapon and visible wounds.
func _contact_line(c: Dictionary, self_pos: Vector2, everyone: Array) -> String:
	var parts: Array = [
		"%s — %s" % [c["name"], ("HOSTILE (%s)" % c["reason"]) if c["hostile"] else "neutral"],
		"in sight" if c["visible"] else "last seen %s" % _recency(c["age"]),
		"%s, %s of you, %s" % [_dist_band(self_pos.distance_to(c["pos"])), _compass(c["pos"] - self_pos), _where(c)],
		_move_text(c, self_pos),
	]
	var aim := _aim_text(c, self_pos, everyone)
	if aim != "":
		parts.append(aim)
	parts.append("holding a %s" % c.get("item", "nothing"))
	if c.get("wound", "") != "":
		parts.append(c["wound"])
	return " — ".join(parts) + "."


## The line between the NPC and hostile `t`: whether each can shoot the other, what blocks it, and
## which other hostiles can see the NPC here.
func _exposure_text(ctx: Dictionary, t: Dictionary, a: Dictionary) -> String:
	var line: Dictionary = a["line"]
	var text := ""
	if line["clear"] and line["in_range"]:
		text = "You have a clear shot at %s from where you stand. You are exposed to their fire." % t["name"]
	elif line["clear"]:
		text = "%s is too far to shoot. They can see you." % t["name"]
	elif line["cover"] != "":
		text = "You are behind cover from %s (the %s): your line to them is blocked." % [t["name"], line["cover"]]
	else:
		text = "A %s is between you and %s: your line to them is blocked." % [line["blocker"], t["name"]]
	if t["visible"] and _aim_text(t, ctx["self_pos"], []) == "aiming at you":
		text += " They are aiming at you."
	var others: Array = _tactics.exposed_to(ctx["space"], ctx["self_pos"], ctx["hostiles"], t["id"], ctx["exclude"])
	if not others.is_empty():
		text += " You are also exposed to the fire of %s." % ", ".join(others)
	return text


## Exposure when under fire from someone the NPC cannot see.
func _unseen_fire_text() -> String:
	if not under_fire():
		return ""
	return "You are being shot at by someone you cannot see, from the %s; you are exposed to their fire." % _compass(_memory.recall(&"under_fire").get("from", Vector2.ZERO))


## The NPC's allies: where each perceived ally is — and which side of hostile `t` it holds, in `t`'s
## frame — plus what each ally last said on the radio. Empty when it knows of no ally.
func _allies_text(ctx: Dictionary, t: Dictionary, a: Dictionary) -> String:
	var self_pos: Vector2 = ctx["self_pos"]
	var lines: Array = []
	for ally in ctx["allies"]:
		var parts: Array = [
			"%s (ally)" % ally["name"],
			"in sight" if ally["visible"] else "last seen %s" % _recency(ally["age"]),
			"%s of you, %s" % [_compass(ally["pos"] - self_pos), _where(ally)],
		]
		if not t.is_empty():
			var tpos: Vector2 = t["pos"]
			if (ally["pos"] as Vector2).distance_to(tpos) <= flank_ally_radius:
				parts.append("on %s's %s" % [t["name"], SIDE_WORDS[_tactics.side_of(tpos, a["front"], ally["pos"])].trim_prefix("their ")])
			else:
				parts.append("far from %s" % t["name"])
		parts.append(_move_text(ally, self_pos))
		if ally.get("wound", "") != "":
			parts.append(ally["wound"])
		lines.append(" — ".join(parts) + ".")
	for c in ctx["callouts"]:
		var status: String = c.get("status", "")
		lines.append("%s (radio, %s): %s%s." % [c["name"], _recency(c["age"]), c.get("label", "?"), ("; " + status) if status != "" else ""])
	return "\n".join(lines)


## A one-line digest of hostile `t`'s flanks: which side the NPC is on and, per other side, whether it
## is open, has a shot and cover, and how long and exposed the route is.
func _flanks_text(t: Dictionary, a: Dictionary) -> String:
	if a["flanks"].is_empty():
		return "Every side of %s is out of reach." % t["name"]
	var parts: Array = []
	for s in a["flanks"]:
		parts.append("%s — %s, %s, %s, %s route" % [SIDE_WORDS[s["side"]],
			("taken by %s" % s["held_by"]) if s["held_by"] != "" else "free",
			"clear shot" if s["clear_shot"] else "line blocked",
			"cover" if s["cover"] != "" else "in the open",
			_route_text(s["route_len"], s["route_exposed"])])
	return "Flanks on %s (you are on %s): %s." % [t["name"], SIDE_WORDS[a["own_side"]], "; ".join(parts)]


## Being shot at or hit (and from where), gunfire heard nearby (only while no hostile is known — in a
## fight it is just the fight), and any remembered event with a note.
func _awareness_text(self_pos: Vector2, fighting: bool) -> String:
	var out: Array = []
	if under_fire():
		var uf: Dictionary = _memory.recall(&"under_fire")
		var dir := _compass(uf.get("from", Vector2.ZERO))
		out.append(("You are being hit, from the %s!" if uf.get("hit", false) else "You are under fire: shots are landing near you, from the %s!") % dir)
	for rec in _memory.recall_aged(&"heard_gunfire"):
		if not fighting and rec["age"] <= recency_bands.y:
			out.append("Gunfire heard to the %s, %s." % [_compass(rec["data"]["pos"] - self_pos), _recency(rec["age"])])
			break
	var seen := { &"under_fire": true }
	for entry in _memory.fresh():
		var topic = entry["topic"]
		if seen.has(topic):
			continue
		seen[topic] = true
		var note = entry["data"].get("note", "")
		if note != "":
			out.append(note)
	return "\n".join(out)


# --- Option groups: what Von picks from ------------------------------------------------------

## The COMBAT branch summary: the threat in one line.
func _threat_summary(self_pos: Vector2, hostiles: Array) -> String:
	if hostiles.is_empty():
		if under_fire():
			return "shots from the %s" % _compass(_memory.recall(&"under_fire").get("from", Vector2.ZERO))
		return ""
	var t: Dictionary = hostiles[0]
	var desc := "%s, %s" % ["in sight" if t["visible"] else "last seen %s" % _recency(t["age"]), _dist_band(self_pos.distance_to(t["pos"]))]
	var aim := _aim_text(t, self_pos, [])
	if aim != "":
		desc += ", " + aim
	if hostiles.size() == 1:
		return "%s: %s, holding a %s" % [t["name"], desc, t.get("item", "nothing")]
	return "%d hostiles; nearest %s: %s" % [hostiles.size(), t["name"], desc]


## Which hostile to fight: one option per known hostile, with what makes it urgent or easy.
func _hostile_group(ctx: Dictionary, hostiles: Array, analyses: Dictionary) -> Dictionary:
	var options: Array = []
	var self_pos: Vector2 = ctx["self_pos"]
	for t in hostiles.slice(0, max_options_per_level):
		var a: Dictionary = analyses[t["id"]]
		# Only what tells the hostiles apart — common facts ("hostile", the usual pistol) blur the match.
		var parts: Array = [
			t["name"],
			"in sight" if t["visible"] else "last seen %s" % _recency(t["age"]),
			"%s, %s of you" % [_dist_band(self_pos.distance_to(t["pos"])), _compass(t["pos"] - self_pos)],
		]
		if (t.get("vel", Vector2.ZERO) as Vector2).length() >= still_speed:
			parts.append(_move_text(t, self_pos))
		var aim := _aim_text(t, self_pos, ctx["allies"])
		if aim != "":
			parts.append(aim)
		if t.get("item", "") != "Pistol":
			parts.append("holding a %s" % t.get("item", "nothing"))
		if t["reason"] == "attacked you":
			parts.append("they attacked you")
		if t.get("wound", "") != "":
			parts.append(t["wound"])
		parts.append("you have a clear shot at them" if a["line"]["clear"] and a["line"]["in_range"] else "your line to them is blocked")
		var fighting := _allies_on(ctx, t)
		if fighting != "":
			parts.append("%s is already on them" % fighting)
		options.append({
			"id": "t_%d" % t["id"], "label": t["name"], "desc": " — ".join(parts),
			"bind": { "target": t["name"], "target_id": t["id"] },
		})
	return { "summary": "", "options": options }


## Where to fight hostile `t` from: this spot, nearby spots with a clear shot, and an ambush in cover.
func _fire_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var f: Dictionary = a["fire"]
	var self_pos: Vector2 = ctx["self_pos"]
	var options: Array = []
	if not f["here"].is_empty():
		options.append(_spot_option("fire_here", "where you stand", "fire from where you stand", f["here"], &"peek_cover"))
	for s in f["spots"]:
		if options.size() >= max_options_per_level - (0 if f["ambush"].is_empty() else 1):
			break
		var dir := _compass(s["point"] - self_pos)
		options.append(_spot_option("fire_" + dir.replace("-", "_"), "a step %s" % dir, "step %s" % dir, s, &"peek_cover"))
	if not f["ambush"].is_empty():
		var amb: Dictionary = f["ambush"]
		var cover: String = amb["cover"] if amb["cover"] != "" else "cover"
		var desc := "wait in ambush behind the %s — you shoot when they show — %s" % [cover, _coming_text(t, self_pos)]
		if not amb["exposed_to"].is_empty():
			desc += " — also exposed to %s" % ", ".join(amb["exposed_to"])
		options.append({ "id": "ambush", "label": "ambush behind the %s" % cover, "desc": desc,
			"params": { "point": amb["point"], "style": &"ambush" }, "tags": { "inside": _is_inside(amb["point"]) } })
	var summary := ""
	if not f["here"].is_empty():
		summary = "from where you stand"
	elif not f["spots"].is_empty():
		summary = "one step away"
	elif not f["ambush"].is_empty():
		summary = "once they show, from an ambush behind cover"
	if summary != "" and t.get("wound", "") != "":
		summary += "; they %s" % str(t["wound"]).replace("looks", "look")
	return { "summary": summary, "options": options }


## One fighting-spot option: its clear shot, cover, other exposure and place.
func _spot_option(id: String, label: String, lead: String, s: Dictionary, style: StringName) -> Dictionary:
	var parts: Array = [lead + _room_suffix(s["point"])]
	parts.append("clear shot" if s["clear_shot"] else "line blocked")
	parts.append(("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open")
	if not s["exposed_to"].is_empty():
		parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
	return { "id": id, "label": label, "desc": " — ".join(parts),
		"params": { "point": s["point"], "style": style }, "tags": { "inside": _is_inside(s["point"]) } }


## Which side to flank hostile `t` from: one option per reachable side other than the NPC's own.
func _flank_group(t: Dictionary, a: Dictionary, rooms: Array) -> Dictionary:
	var tpos: Vector2 = t["pos"]
	var options: Array = []
	var open: Array = []
	for s in a["flanks"]:
		var room := _room_at(s["point"], rooms)
		var place: String = ("in the %s" % _room_name(room["type"])) if not room.is_empty() else "outside the house"
		var parts: Array = [
			"%s — %s of them, %s" % [SIDE_WORDS[s["side"]], _compass(s["point"] - tpos), place],
			("taken by %s" % s["held_by"]) if s["held_by"] != "" else "free",
			"clear shot from there" if s["clear_shot"] else "line blocked from there",
			("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open",
			_route_text(s["route_len"], s["route_exposed"]) + " route",
		]
		if s["heading_toward"]:
			parts.append("they are moving toward that side")
		if not s["exposed_to"].is_empty():
			parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
		if s["ally_lane"] != "":
			parts.append("in %s's line of fire" % s["ally_lane"])
		options.append({
			"id": "side_" + s["side"],
			"label": "%s (%s)" % [SIDE_WORDS[s["side"]], _room_name(room["type"]) if not room.is_empty() else "outside"],
			"desc": " — ".join(parts),
			"params": { "point": s["point"] },
			"tags": { "inside": not room.is_empty(), "held": s["held_by"] != "" },
		})
		if s["held_by"] == "":
			open.append(s)
	var inside_open: Array = open.filter(func(s): return not _room_at(s["point"], rooms).is_empty())
	var shot_here: bool = a["line"]["clear"] and a["line"]["in_range"]
	return {
		"summary": _flank_summary(t, a["flanks"], open, rooms, shot_here),
		"summary_inside": _flank_summary(t, a["flanks"], inside_open, rooms, shot_here),
		"options": options,
	}


## The FLANK branch summary over the `open` sides: how many, the best at a glance (Von still makes
## the pick), and whether the NPC already has a shot without moving.
func _flank_summary(t: Dictionary, flanks: Array, open: Array, rooms: Array, shot_here: bool) -> String:
	if flanks.is_empty():
		return ""
	var text := ""
	if open.is_empty():
		text = "every side is taken or out of reach"
	else:
		open.sort_custom(func(x, y): return _flank_rank(x) > _flank_rank(y))
		var best: Dictionary = open[0]
		var best_room := _room_at(best["point"], rooms)
		text = "%d free side%s; best: %s%s, %s route, %s" % [open.size(), "" if open.size() == 1 else "s",
			SIDE_WORDS[best["side"]], (" via the %s" % _room_name(best_room["type"])) if not best_room.is_empty() else " outside",
			_route_text(best["route_len"], best["route_exposed"]), "cover" if best["cover"] != "" else "in the open"]
	return text


## How good an open flank looks at a glance (for the summary's "best" only — Von makes the pick).
func _flank_rank(s: Dictionary) -> int:
	return int(s["clear_shot"]) * 4 + int(s["cover"] != "") * 2 + int(not s["route_exposed"]) + int(s["route_len"] <= route_buckets.x)


## How to close in on hostile `t`: part-way along the route (with cover if any) or a straight rush.
func _advance_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var options: Array = []
	for s in a["advance"]:
		var parts: Array = []
		var id := ""
		var label := ""
		if s.get("rush", false):
			id = "rush"
			label = "rush them"
			parts.append("rush straight at where they are" + _room_suffix(s["point"]))
			parts.append(_route_text(s["route_len"], s["route_exposed"]) + " route")
			parts.append("they hold a %s" % t.get("item", "nothing"))
		else:
			id = "advance_half" if s["fraction"] < 0.6 else "advance_close"
			label = "halfway to them" if id == "advance_half" else "close to them"
			parts.append(("advance halfway to them" if id == "advance_half" else "advance most of the way to them") + _room_suffix(s["point"]))
			parts.append(("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open")
			parts.append("clear shot from there" if s["clear_shot"] else "line blocked from there")
		if not s["exposed_to"].is_empty():
			parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
		options.append({ "id": id, "label": label, "desc": " — ".join(parts),
			"params": { "point": s["point"] }, "tags": { "inside": _is_inside(s["point"]) } })
	var summary := "they are %s, %s, holding a %s" % [
		_dist_band((ctx["self_pos"] as Vector2).distance_to(t["pos"])), _move_text(t, ctx["self_pos"]), t.get("item", "nothing")]
	if t.get("wound", "") != "":
		summary += ", %s" % t["wound"]
	return { "summary": summary, "options": options }


## Where to fall back to: out of sight of every known threat first, then farther away; with cover,
## route and the ally a spot lies toward. Threats are the known hostiles, else where fire came from.
func _retreat_group(ctx: Dictionary, hostiles: Array, known_rooms: Array, dmg: float) -> Dictionary:
	var threats: Array = hostiles.map(func(h): return h["pos"])
	if threats.is_empty() and under_fire():
		var from: Vector2 = _memory.recall(&"under_fire").get("from", Vector2.ZERO)
		threats.append((ctx["self_pos"] as Vector2) + from.normalized() * investigate_distance)
	if threats.is_empty():
		return { "summary": "", "options": [] }
	var spots: Array = _tactics.retreat_positions(ctx, threats, known_rooms)
	spots.sort_custom(func(x, y):
		if x["hidden"] != y["hidden"]:
			return x["hidden"]
		if (x["cover"] != "") != (y["cover"] != ""):
			return x["cover"] != ""
		return x["route_len"] < y["route_len"])
	var options: Array = []
	for s in spots:
		if options.size() >= max_options_per_level:
			break
		var id := ""
		var lead := ""
		if s.get("ally", "") != "":
			id = "fall_ally_" + str(s["ally"]).to_lower()
			lead = "fall back to %s" % s["ally"]
		elif s.get("room", "") != "":
			id = "fall_" + str(s["room"]).to_lower().replace(" ", "_")
			lead = "fall back to the %s" % s["room"]
		else:
			id = "fall_cover"
			lead = "back off behind the %s close by" % (s["cover"] if s["cover"] != "" else "cover")
		if options.any(func(o): return o["id"] == id):
			continue
		var parts: Array = [lead,
			"out of every hostile's sight" if s["hidden"] else "farther from them, still in their sight",
			("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open",
			_route_text(s["route_len"], s["route_exposed"]) + " route"]
		options.append({ "id": id, "label": lead.trim_prefix("fall back to ").trim_prefix("back off "), "desc": " — ".join(parts),
			"params": { "point": s["point"] }, "tags": { "inside": _is_inside(s["point"]), "hidden": s["hidden"] } })
	var inside: Array = options.filter(func(o): return o["tags"]["inside"])
	return {
		"summary": _retreat_summary(options, dmg),
		"summary_inside": _retreat_summary(inside, dmg),
		"options": options,
	}


## The RETREAT branch summary over `options` (best first): whether anywhere hides the NPC, the best
## spot, and how hurt it is.
func _retreat_summary(options: Array, dmg: float) -> String:
	if options.is_empty():
		return ""
	var best: Dictionary = options[0]
	return "best: %s, %s; you are %s" % [best["label"],
		"out of their sight" if best["tags"]["hidden"] else "farther from them, still in their sight", _health_band(dmg)]


## What to investigate: lost hostiles (where last seen, and where they were heading), gunfire heard,
## where unseen shots came from, and allies' radio calls for support — freshest first.
func _lead_group(ctx: Dictionary, hostiles: Array) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var leads: Array = []
	for c in lost_hostiles():
		var moving: bool = (c["vel"] as Vector2).length() >= still_speed
		leads.append({ "age": c["age"], "id": "lead_seen_%d" % c["id"], "label": "where you last saw %s" % c["name"],
			"desc": "where you last saw %s — %s, %s — %s route%s" % [c["name"], _recency(c["age"]), _where(c),
				_route_band(_route_len(ctx, c["pos"])), ("; they were moving %s" % _compass(c["vel"])) if moving else ""],
			"point": c["pos"] })
		if moving:
			var ahead: Vector2 = _tactics.snap(ctx["map"], c["pos"] + c["vel"] * minf(c["age"], extrapolate_cap))
			leads.append({ "age": c["age"] + 0.01, "id": "lead_heading_%d" % c["id"], "label": "where %s was heading" % c["name"],
				"desc": "where %s was heading — %s of where you last saw them%s — %s route" % [c["name"], _compass(c["vel"]),
					_room_suffix(ahead), _route_band(_route_len(ctx, ahead))],
				"point": ahead })
	for rec in _memory.recall_aged(&"heard_gunfire"):
		var pos: Vector2 = rec["data"]["pos"]
		leads.append({ "age": rec["age"], "id": "lead_gunfire_%d_%d" % [floori(pos.x / 200.0), floori(pos.y / 200.0)],
			"label": "gunfire to the %s" % _compass(pos - self_pos),
			"desc": "gunfire heard to the %s — %s%s — %s route" % [_compass(pos - self_pos), _recency(rec["age"]),
				_room_suffix(pos), _route_band(_route_len(ctx, pos))],
			"point": _tactics.snap(ctx["map"], pos) })
	if under_fire() and hostiles.is_empty():
		var from: Vector2 = _memory.recall(&"under_fire").get("from", Vector2.ZERO)
		var origin: Vector2 = _tactics.snap(ctx["map"], self_pos + from.normalized() * investigate_distance)
		leads.append({ "age": 0.0, "id": "lead_shooter", "label": "where the shots came from",
			"desc": "where the shots at you came from — the %s, just now" % _compass(from), "point": origin })
	for c in ctx["callouts"]:
		if not str(c.get("path", "")).begins_with("combat"):
			continue
		var at: Vector2 = c.get("position", self_pos)
		var status: String = c.get("status", "")
		leads.append({ "age": c["age"], "id": "lead_ally_%d" % c["id"], "label": "support %s" % c["name"],
			"desc": "support %s — %s, %s of you%s — radio %s%s" % [c["name"], c.get("label", "fighting"), _compass(at - self_pos),
				_room_suffix(at), _recency(c["age"]), ("; " + status) if status != "" else ""],
			"point": _tactics.snap(ctx["map"], at) })
	# A lead checked more recently than the event behind it is spent (fresh news there is offered again).
	leads = leads.filter(func(l): return not _memory.age_of(&"checked_lead", "id", l["id"]) < l["age"])
	leads.sort_custom(func(x, y): return x["age"] < y["age"])
	var options: Array = []
	for l in leads.slice(0, max_options_per_level):
		options.append({ "id": l["id"], "label": l["label"], "desc": l["desc"],
			"params": { "point": l["point"], "lead": l["id"] }, "tags": { "inside": _is_inside(l["point"]) } })
	var summary := ""
	if not options.is_empty():
		summary = "%d lead%s (freshest: %s)" % [leads.size(), "" if leads.size() == 1 else "s", options[0]["desc"].get_slice(" — ", 0)]
	return { "summary": summary, "options": options }


## Under fire from someone the NPC cannot see: the one way to find them — toward where the shots came
## from. Empty unless under fire with no hostile known.
func _shooter_group(ctx: Dictionary, hostiles: Array) -> Dictionary:
	if not under_fire() or not hostiles.is_empty():
		return { "summary": "", "options": [] }
	var from: Vector2 = _memory.recall(&"under_fire").get("from", Vector2.ZERO)
	var origin: Vector2 = _tactics.snap(ctx["map"], (ctx["self_pos"] as Vector2) + from.normalized() * investigate_distance)
	var dir := _compass(from)
	return { "summary": "the shots came from the %s" % dir, "options": [{
		"id": "toward_shots", "label": "toward the shots",
		"desc": "move toward where the shots came from — the %s%s — %s route" % [dir, _room_suffix(origin), _route_band(_route_len(ctx, origin))],
		"params": { "point": origin }, "tags": { "inside": _is_inside(origin) } }] }


## Which known room to search next: not-recently-searched first, then nearest; plus the entrance or
## the house itself while outside.
func _search_group(ctx: Dictionary, known_rooms: Array, rooms: Array) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var here := _room_at(self_pos, rooms)
	var candidates: Array = []
	var unsearched := 0
	for room in known_rooms:
		if not here.is_empty() and room["key"] == here["key"]:
			continue
		var age: float = _memory.age_of(&"visited_room", "key", room["key"])
		var point: Vector2 = _tactics.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		var stale := age > search_memory_ttl
		if stale:
			unsearched += 1
		candidates.append({ "room": room, "age": age, "stale": stale, "point": point, "len": _route_len(ctx, point) })
	candidates.sort_custom(func(x, y):
		if x["stale"] != y["stale"]:
			return x["stale"]
		return x["len"] < y["len"])
	var options: Array = []
	if here.is_empty():
		if entry_point != Vector2.ZERO:
			options.append({ "id": "entrance", "label": "the front entrance",
				"desc": "the front entrance — %s route" % _route_band(_route_len(ctx, entry_point)),
				"params": { "point": entry_point }, "tags": { "inside": false } })
		elif known_rooms.is_empty() and not rooms.is_empty():
			var centre := _house_centre(rooms)
			options.append({ "id": "approach", "label": "the house",
				"desc": "head for the house and find a way in — %s route" % _route_band(_route_len(ctx, centre)),
				"params": { "point": _tactics.snap(ctx["map"], centre) }, "tags": { "inside": false } })
	for c in candidates:
		if options.size() >= max_options_per_level:
			break
		var room: Dictionary = c["room"]
		options.append({ "id": "room_%s" % room["key"], "label": "the %s" % _room_name(room["type"]),
			"desc": "the %s — %s — %s route" % [_room_name(room["type"]),
				"unsearched" if c["stale"] else "searched %s" % _recency(c["age"]), _route_band(c["len"])],
			"params": { "point": c["point"], "look_around": true }, "tags": { "inside": true } })
	var summary := "%d of %d known rooms unsearched" % [unsearched, known_rooms.size()]
	if known_rooms.is_empty():
		summary = "find your way into the house and explore it"
	return { "summary": summary, "options": options }


## Unexplored parts of the house (rooms not yet seen), named by direction only — the NPC doesn't know
## what they are. One per compass direction, nearest first, at most two.
func _explore_group(ctx: Dictionary, rooms: Array) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var known := _known_room_keys()
	var by_dir := {}
	for room in rooms:
		if known.has(room["key"]):
			continue
		var point: Vector2 = _tactics.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		var dir := _compass(point - self_pos)
		var dist := self_pos.distance_to(point)
		if not by_dir.has(dir) or dist < by_dir[dir]["dist"]:
			by_dir[dir] = { "room": room, "point": point, "dist": dist }
	var picks: Array = by_dir.values()
	picks.sort_custom(func(x, y): return x["dist"] < y["dist"])
	var options: Array = []
	for p in picks.slice(0, 2):
		var dir := _compass(p["point"] - self_pos)
		options.append({ "id": "explore_" + dir.replace("-", "_"), "label": "unexplored %s" % dir,
			"desc": "an unexplored part of the house to the %s — %s route" % [dir, _route_band(_route_len(ctx, p["point"]))],
			"params": { "point": p["point"], "look_around": true }, "tags": { "inside": true } })
	return { "summary": "explore the house", "options": options }


## The object interactions the NPC knows of: one option per DISTINCT action label, pointing at the
## nearest known object offering it (item-gated). Not capped — Von ranks them against the goal.
func _interaction_group(character, self_pos: Vector2, rooms: Array) -> Dictionary:
	var known_objs := _known_object_ids()
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
	var options: Array = []
	for label in nearest:
		var obj = nearest[label]["obj"]
		options.append({ "id": "do_%d_%s" % [obj.get_instance_id(), nearest[label]["id"]], "label": label,
			"desc": "%s%s" % [label, _room_suffix(obj.global_position)],
			"params": { "object": obj, "id": nearest[label]["id"] }, "tags": { "inside": _is_inside(obj.global_position) } })
	var labels: Array = nearest.keys()
	var summary := "use furniture: %s%s" % [", ".join(labels.slice(0, 4)).to_lower(), ", …" if labels.size() > 4 else ""]
	return { "summary": summary if not labels.is_empty() else "", "options": options }


## Named places to go: each known room (except this one) and the NPC's starting position.
func _room_group(ctx: Dictionary, known_rooms: Array, rooms: Array) -> Dictionary:
	var here := _room_at(ctx["self_pos"], rooms)
	var options: Array = []
	for room in known_rooms:
		if not here.is_empty() and room["key"] == here["key"]:
			continue
		var point: Vector2 = _tactics.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		options.append({ "id": "room_%s" % room["key"], "label": "the %s" % _room_name(room["type"]), "desc": "the %s" % _room_name(room["type"]),
			"params": { "point": point, "arrive_room": room["key"] }, "tags": { "inside": true } })
	options.append({ "id": "post", "label": "your starting position", "desc": "your starting position",
		"params": { "point": _post }, "tags": { "inside": _is_inside(_post) } })
	return { "summary": "", "options": options }


# --- Wording helpers (the bands Von reads) ---------------------------------------------------

## A room type as Von reads it ("kitchen_living" → "kitchen living").
func _room_name(kind) -> String:
	return str(kind).replace("_", " ")


## A distance as a combat band, from the NPC's own reach.
func _dist_band(d: float) -> String:
	if d <= punch_range * 1.5:
		return "point-blank"
	if d <= shoot_range * 0.5:
		return "close, in pistol range"
	if d <= shoot_range:
		return "in pistol range"
	return "too far to shoot"


## How long ago, as a band.
func _recency(age: float) -> String:
	if age <= recency_bands.x:
		return "just now"
	if age <= recency_bands.y:
		return "recently"
	return "a while ago"


## A route length as a band.
func _route_band(length: float) -> String:
	if length <= route_buckets.x:
		return "short"
	if length <= route_buckets.y:
		return "medium"
	return "long"


## A route as Von reads it: "short hidden" / "long exposed".
func _route_text(length: float, exposed: bool) -> String:
	return "%s %s" % [_route_band(length), "exposed" if exposed else "hidden"]


## The navigated route length (px) from the NPC to `p`.
func _route_len(ctx: Dictionary, p: Vector2) -> float:
	return _tactics.path_length(_tactics.route(ctx["map"], ctx["self_pos"], p))


## How a contact is moving, relative to the NPC ("moving west, toward you" / "standing still").
func _move_text(c: Dictionary, self_pos: Vector2) -> String:
	var vel: Vector2 = c.get("vel", Vector2.ZERO)
	var prefix := "" if c.get("visible", false) else "was "
	if vel.length() < still_speed:
		return prefix + "standing still"
	var rel := ""
	var a := absf(vel.angle_to(self_pos - (c["pos"] as Vector2)))
	if a < PI * 0.25:
		rel = ", toward you"
	elif a > PI * 0.75:
		rel = ", away from you"
	return "%smoving %s%s" % [prefix, _compass(vel), rel]


## Whether contact `c` (seen this tick) is coming toward the NPC, for an ambush.
func _coming_text(c: Dictionary, self_pos: Vector2) -> String:
	var vel: Vector2 = c.get("vel", Vector2.ZERO)
	if vel.length() < still_speed:
		return "they are standing still"
	if absf(vel.angle_to(self_pos - (c["pos"] as Vector2))) < PI * 0.25:
		return "they are coming this way"
	return "they are moving elsewhere"


## Who a VISIBLE contact is aiming at — the NPC, or another known character within `aim_cone` of its
## facing — or that it faces away from the NPC. Empty when unknown or unremarkable.
func _aim_text(c: Dictionary, self_pos: Vector2, others: Array) -> String:
	var facing: Vector2 = c.get("facing", Vector2.ZERO)
	if not c.get("visible", false) or facing == Vector2.ZERO:
		return ""
	var cone := deg_to_rad(aim_cone)
	var to_me: Vector2 = self_pos - (c["pos"] as Vector2)
	if absf(facing.angle_to(to_me)) <= cone:
		return "aiming at you"
	for o in others:
		if o["id"] != c["id"] and absf(facing.angle_to((o["pos"] as Vector2) - (c["pos"] as Vector2))) <= cone:
			return "aiming at %s" % o["name"]
	if absf(facing.angle_to(to_me)) >= PI * 0.66:
		return "facing away from you"
	return ""


## The ally (perceived near the target, or calling it on the radio) already fighting hostile `t`.
func _allies_on(ctx: Dictionary, t: Dictionary) -> String:
	for c in ctx["callouts"]:
		if c.get("target_id", 0) == t["id"]:
			return c["name"]
	for a in ctx["allies"]:
		if (a["pos"] as Vector2).distance_to(t["pos"]) <= flank_ally_radius * 0.5:
			return a["name"]
	return ""


## Where a contact is: "in the kitchen, inside the house" / "outside the house".
func _where(c: Dictionary) -> String:
	if not c.get("inside", false):
		return "outside the house"
	return ("in the %s" % c["room"]) if c.get("room", "") != "" else "inside the house"


## " (in the kitchen)" for a point inside a room, " (outside)" otherwise.
func _room_suffix(p: Vector2) -> String:
	var room := _room_at(p, _rooms_cache)
	return (" (in the %s)" % _room_name(room["type"])) if not room.is_empty() else " (outside)"


## Accumulated damage as a band of how hurt a character is.
func _health_band(dmg: float) -> String:
	if dmg >= critical_threshold:
		return "badly wounded"
	if dmg >= hurt_threshold:
		return "hurt"
	return "unhurt"


## A seen character's visible wound band ("looks hurt"), or "" when unharmed.
func _wound_band(dmg: float) -> String:
	if dmg >= critical_threshold:
		return "looks badly wounded"
	if dmg >= hurt_threshold:
		return "looks hurt"
	return ""


## The 8-wind compass name for a direction vector (screen space, +y down = south).
func _compass(v: Vector2) -> String:
	var idx := int(round(atan2(v.y, v.x) / (TAU / 8.0))) % 8
	return COMPASS[idx + 8 if idx < 0 else idx]


# --- House knowledge -------------------------------------------------------------------------

## Seed a familiar NPC's house knowledge once: remember every room and interactable as already-known
## (permanent ttl). An unfamiliar NPC skips this and learns by sight in observe(). Needs the rooms
## list, so it runs on the first observe() (not _ready).
func _seed_house(rooms: Array) -> void:
	_rooms_cache = rooms
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

## Whether character `id` was visible (in cone/range with a clear line) on the latest observe() tick.
func contact_visible(id: int) -> bool:
	return _visible_now.has(id)


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


## Whether a world point lies inside the house (within any room).
func _is_inside(p: Vector2) -> bool:
	return not _room_at(p, _rooms_cache).is_empty()


## The centre of the bounding box enclosing all rooms — "the house" for an NPC that knows no room.
func _house_centre(rooms: Array) -> Vector2:
	var bounds := (rooms[0]["rect"] as Rect2)
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	return bounds.get_center()

