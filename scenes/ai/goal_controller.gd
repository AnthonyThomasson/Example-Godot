extends Node

## AI domain: a generic, goal-driven controller for a non-player character, driven by a Jev-style
## "System One" decision model (a local Von server). It satisfies the character's controller contract
## (`control(character, delta)`) and writes only the intent the player controller writes
## (`move_input`/`aim_point`) plus the same public actions (`select_slot`, `melee`, `shoot`,
## `interact_with`, `end_interaction`). The behaviour is pure DATA: `goal` is a plain-language
## sentence, plus a handful of generic primitives exported below — who counts as HOSTILE (on sight /
## on trespass / on attack, allies by faction), whether to actively pursue hostiles, whether to defend
## the house as territory, whether to flank (attack from the target's side/rear and spread allied
## attackers around it). A house defender and a house invader are the same code with different data;
## there is no per-goal or per-NPC-type code.
##
## The decision is ACT-centric. Von ranks distinct, verb-like options reliably but ranks many
## near-identical spatial points almost at random, so the controller asks it WHAT TO DO — engage a
## known hostile (shoot / punch), search for hostiles, hold, or use one of the known objects (Watch
## TV, Cook, …) — and then DERIVES the movement itself. (A small `move` menu of named places is
## consulted only when the act implies no movement, i.e. holding.) It adopts Von's TOP pick (argmax
## `choice`); the distributions are flat, so the top pick keeps the NPC decisive. Von is stateless and
## cannot sequence, so a COMMITMENT layer here supplies the memory: once it heads for an object,
## interaction or fight it sticks with it until it resolves (a safety cap aside) or a salient event
## fires (the set of known hostiles changes), which lets multi-step goals advance instead of
## oscillating. Movement is real pathfinding through a NavigationAgent2D. When the server is
## unreachable it holds a steady stance.
##
## The NPC is NOT omniscient. Each tick the perception's SEE pass runs every character through a
## tunable vision sense (agent_vision.gd — field of view, range, line of sight), deposits what is
## visible into the agent's memory, and categorizes each sighting with the hostility rules
## (agent_hostility.gd). The BUILD pass composes the decision from what the NPC currently sees AND
## remembers. So it acts on a hostile's last-KNOWN position, engages only a contact it can locate,
## and — once a sighting decays (`contact_memory_ttl`) — loses that contact. `familiar_with_house`
## pre-seeds the house's rooms/objects as already-known; an unfamiliar NPC must see them first.
## People are never pre-known.

const AgentPerception := preload("res://scenes/ai/agent_perception.gd")
const AgentMemory := preload("res://scenes/ai/agent_memory.gd")
const AgentVision := preload("res://scenes/ai/agent_vision.gd")
const AgentHostility := preload("res://scenes/ai/agent_hostility.gd")

## The behaviour to pursue, in plain language — what Von ranks the act menu against.
@export_multiline var goal: String = ("Deal with hostile characters: shoot them with your pistol. " +
	"Otherwise go about your business.")
## Pursuit primitive: when true this NPC actively hunts hostiles instead of doing chores. While no
## hostile is known it patrols the house to search (rather than settling into a passive interaction,
## which freezes its facing and blinds it); once one is known it ENGAGES rather than picking an
## unrelated interaction — the large object-interaction menu otherwise dilutes Von's choice. Turn off
## for an NPC whose goal is unrelated to fighting (e.g. "watch tv"). Like the other primitives, this
## is a controller policy Von (a single-shot ranker) can't apply itself.
@export var pursue_hostiles: bool = true
## Territory primitive: when true, while engaging a contact that is OUTSIDE the house the NPC returns
## fire from inside (fire/cover spots restricted to the house, no advancing out) instead of chasing it.
@export var defend_territory: bool = false
## The `/v1/systemone` endpoint to ask.
@export var server_url: String = "http://127.0.0.1:8000/v1/systemone"
## Model name sent with each request.
@export var model: String = "von-1.2.0"
## Minimum seconds between decisions (the re-decide cadence once free to change).
@export var decide_interval: float = 1.0
## Seconds to stay in a chosen interaction before ending it and re-deciding (covers Von's
## statelessness so multi-step goals advance).
@export var interaction_dwell: float = 3.0
## Safety cap (s) on committing to reach a chosen object, so a blocked path still re-decides.
@export var max_commit_time: float = 6.0
## Range (px) within which a chosen shot is fired instead of advancing on the engaged contact.
@export var shoot_range: float = 500.0
## Range (px) within which a chosen punch lands instead of advancing on the engaged contact.
@export var punch_range: float = 48.0
## Radius (px) of the ring of candidate fire/cover positions sampled during combat.
@export var combat_ring_radius: float = 80.0
## Number of candidate positions sampled on that ring.
@export var combat_ring_count: int = 12
## Seconds to stay behind cover between shots (the duck half of peek-and-cover).
@export var cover_time: float = 1.2
## Minimum seconds between shots/punches while engaging.
@export var fire_cooldown: float = 0.5
## Seconds a chosen fire/cover position is committed to before a new one may be picked. Prevents
## per-frame re-selection of the nearest spot (which makes the NPC vibrate).
@export var reposition_interval: float = 0.5
## Flanking primitive: when true, firing spots are chosen to attack from the target's side/rear and
## to spread allied attackers around it (a pincer), rather than always taking the nearest spot. It
## re-ranks the peek fire spots by angular openness — distance from the bearings the NPC should avoid
## (where a visible target is FACING, and where each nearby ally already stands) — traded against
## travel distance. Off, or with no such bearings to avoid, it reverts to nearest-spot (the old
## behaviour), so flanking is purely additive.
@export var flank: bool = true
## How far (px) the NPC will travel for a fully-open flanking angle: the px-value of going from the
## worst angle (right on an avoided bearing) to the best (opposite it). Higher = flanks harder.
@export var flank_weight: float = 140.0
## An ally within this distance (px) of the engaged target counts as holding an angle on it, so this
## NPC spreads to a different bearing instead of stacking alongside the ally.
@export var flank_ally_radius: float = 500.0
## Radius (px) within which a hit on something else still registers as gunfire near the NPC.
@export var hit_awareness_radius: float = 160.0
## Seconds an incoming/nearby hit keeps the NPC on "under fire" alert (reported to Von, which
## re-decides at once).
@export var under_fire_time: float = 3.0
## Seconds the NPC stays committed to a fight after the last shot it fired or took, before it
## re-asks Von. Stops it dropping out of combat between the once-a-cadence decisions.
@export var engage_dwell: float = 3.0
## Memory cleanup: hard cap on remembered events (oldest evicted past it); <= 0 = unlimited.
@export var memory_capacity: int = 64
## Memory cleanup: fallback lifetime (s) for remembered events given no explicit ttl; <= 0 = no age
## expiry (events then persist until evicted by capacity).
@export var memory_default_ttl: float = 0.0

@export_group("Vision")
## Whether sight is gated at all. Off = the NPC is omniscient (pre-vision behaviour), for debugging.
@export var vision_enabled: bool = true
## Maximum distance (px) at which the NPC can see anything.
@export var view_distance: float = 2520.0
## Full angular width (degrees) of the forward view cone, centred on the NPC's facing (its aim).
@export var fov_degrees: float = 110.0
## Radius (px) of a 360° near-awareness bubble: things this close are sensed regardless of facing.
@export var awareness_radius: float = 48.0
## Whether this NPC starts already knowing the house (its rooms + objects). Off = it must see them
## first. People are never pre-known either way — they are known only once seen.
@export var familiar_with_house: bool = true
## Lifetime (s) of a character sighting — the window the NPC keeps acting on a last-seen position
## after losing sight before it forgets that contact.
@export var contact_memory_ttl: float = 4.0

@export_group("Hostility")
## Every non-allied character seen is hostile (e.g. an invader).
@export var hostile_on_sight: bool = false
## A non-allied character seen inside the house is hostile (e.g. a defender).
@export var hostile_on_trespass: bool = false
## A non-allied character that attacks this NPC — hits it, or shoots close to it — is hostile.
@export var hostile_on_attack: bool = true
## Lifetime (s) of a hostility verdict; <= 0 = permanent (a grudge never fades).
@export var hostility_ttl: float = 0.0
## Factions treated as allies besides the NPC's own (its character's `faction`); never hostile.
@export var allied_factions: Array[StringName] = []

@export_group("")
## How close (px) counts as "arrived" when steering straight-line (no nav agent).
@export var arrive_dist: float = 10.0
## NavigationAgent2D used for pathing (a sibling under the character); set in the NPC scene.
@export var nav_agent_path: NodePath
## How long (s) the NPC stays blocked against furniture before it shoves straight through as a last
## resort (when no route around exists, or it is wedged and barely moving).
@export var push_through_delay: float = 1.0
## Movement speed (px/s) under which the NPC counts as blocked while trying to follow a path.
@export var stuck_speed: float = 20.0

## World-space room rects (`{ key, type, rect }`) from Main — the sensor's map of the house.
var rooms: Array = []

var _perception: Node             ## Senses + builds the state + menu each decision.
var _vision: RefCounted           ## The sight sense (FOV/range/LoS); see agent_vision.gd.
var _hostility: RefCounted        ## The hostility rules; see agent_hostility.gd.
var _hostiles: Array = []         ## Known hostile contacts this tick (nearest first), from perception.
var _allies: Array = []           ## Known non-hostile contacts this tick — the bearings flanking spreads away from.
var _last_hostile_pos := Vector2.ZERO ## Where the nearest known hostile was last seen.
var _engage_id := 0               ## Instance id of the contact being engaged (0 = none).
var _engage_node: Node2D          ## That contact's body (excluded from line-of-fire rays).
var _engage_pos := Vector2.ZERO   ## That contact's last-KNOWN position (from memory).
var _engage_inside := false       ## Whether that contact was last seen inside the house.
var _engage_slot := 0             ## Item slot the current engagement uses.
var _patrol_point := Vector2.ZERO ## Current patrol/search destination while searching for hostiles.
var _patrol_active := false       ## Whether `_patrol_point` holds a live destination to walk to.
var _patrol_idx := 0              ## Round-robin index into `rooms` for the patrol tour (full coverage).
var _patrol_room_key := ""        ## Target room key; the leg is done once the NPC ENTERS it (""=a point).
var _patrol_timer := 0.0          ## Safety cap (s) to advance the tour if a leg can't be reached.
var _investigate_last_seen := false ## Head for the last-known hostile spot first after losing sight.
var _agent: NavigationAgent2D     ## Pathfinding agent, or null (falls back to straight-line).
var _safe_velocity := Vector2.ZERO ## Latest avoidance-adjusted velocity from the agent (RVO callback).
var _avoid_ready := false          ## Whether the agent's avoidance (max_speed) has been configured.
var _last_pos := Vector2.ZERO      ## Character position last path-move frame, for stuck detection.
var _stuck_time := 0.0             ## Seconds the NPC has been blocked while following a path.
var _push_through := false         ## True while shoving straight through a blocker (the last resort).
var _moves := {}                  ## This tick's move options by id (from the sensor).
var _acts := {}                   ## This tick's act options by id.
var _intent := "idle"             ## What the current act means to do: interact / combat / search / idle.
var _act_verb := "hold"           ## The chosen act's verb (shoot / punch / interact / search / hold).
var _target_obj: Node             ## The object to approach + use (interact intent), else null.
var _interact_id := ""            ## The interaction id to run on `_target_obj`.
var _move_point := Vector2.ZERO   ## Destination for an idle reposition.
var _has_move := false            ## Whether an idle move destination is set.
var _act_armed := false           ## Delays an interaction one frame so facing settles first.
var _combat_phase := "peek"       ## Peek-and-cover phase: "peek" (seek a shot) or "cover" (duck).
var _cover_timer := 0.0           ## Seconds left ducking behind cover before peeking again.
var _fire_timer := 0.0            ## Seconds left before the next shot/punch may be thrown.
var _combat_dest := Vector2.ZERO  ## Committed fire/cover position the NPC is steering toward.
var _combat_dest_timer := 0.0     ## Seconds left before a new combat position may be chosen.
var _hold_ground := false         ## Combat: return fire but stay inside the house (territory vs. an outsider).
var _move_id := ""                ## Chosen move id, for the decision log.
var _act_log := "hold"            ## Chosen act id, for the decision log.
# Commitment state (the memory Von lacks).
var _in_interaction := false      ## Committed to an active object interaction.
var _interaction_timer := 0.0     ## Seconds left before ending the current interaction.
var _commit_timer := 0.0          ## Seconds left on the current approach commitment (safety cap).
var _decide_timer := 0.0          ## Seconds until the next decision is allowed.
var _force := false               ## Force a decision now (task resolved or salient event).
var _salient_key := ""            ## Known-hostile set + engaged contact's inside state, for edge detection.
var _salient_init := false        ## Whether _salient_key has been seeded.
# Combat awareness (fed by EventBus &"hit" events, stored in _memory).
var _character: Node              ## The character this controller drives, captured on first control.
var _hit_queue: Array = []        ## Hit events awaiting processing once _character is known.
var _memory: RefCounted           ## Remembered events (under fire, engaged, …); see agent_memory.gd.
var _pending := false             ## True while a request is in flight.
var _http: HTTPRequest            ## Client for decision requests.


## Build the perception component, the HTTP client, and resolve the navigation agent.
func _ready() -> void:
	_perception = AgentPerception.new()
	_perception.contact_memory_ttl = contact_memory_ttl
	add_child(_perception)
	_vision = AgentVision.new()
	_vision.enabled = vision_enabled
	_vision.view_distance = view_distance
	_vision.fov_degrees = fov_degrees
	_vision.awareness_radius = awareness_radius
	_hostility = AgentHostility.new()
	_hostility.on_sight = hostile_on_sight
	_hostility.trespass = hostile_on_trespass
	_hostility.retaliate = hostile_on_attack
	_hostility.ttl = hostility_ttl
	_hostility.allies = allied_factions
	_memory = AgentMemory.new()
	_memory.capacity = memory_capacity
	_memory.default_ttl = memory_default_ttl
	_http = HTTPRequest.new()
	_http.timeout = 3.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	EventBus.posted.connect(_on_event)
	if nav_agent_path != NodePath():
		_agent = get_node_or_null(nav_agent_path) as NavigationAgent2D
	if _agent != null:
		# RVO avoidance steers the NPC around furniture (tagged with NavigationObstacle2D by the
		# Navigation domain); max_speed is set from the character on the first control() tick.
		_agent.avoidance_enabled = true
		_agent.velocity_computed.connect(_on_avoidance_velocity)


## Buffer a world hit event for processing on the next control() tick (the signal can fire before
## the controller knows which character it drives).
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic == &"hit":
		_hit_queue.append(data)


## Read-only: the act the NPC is currently carrying out (its last decision), for observers/HUD.
func current_act() -> String:
	return _act_log


## Read-only: a compact, human-readable summary of what the NPC is doing right now — for debug
## overlays/observers. Built from live state (never mutates), it reads more clearly than the raw
## `current_act()` id: the intent, the act verb + target/object, the combat phase, and any alert.
func debug_status() -> String:
	var line := ""
	match _intent:
		"combat":
			var who := str(_engage_node.name) if _engage_node != null and is_instance_valid(_engage_node) else "?"
			line = "COMBAT · %s %s · %s" % [_act_verb, who, _combat_phase]
		"interact":
			var what := str(_target_obj.name) if _target_obj != null and is_instance_valid(_target_obj) else _interact_id
			line = "INTERACT · %s" % what
		"search":
			line = "SEARCH"
		_:
			line = ("IDLE → %s" % _move_id) if _has_move else "IDLE"
	if _memory != null and _memory.is_fresh(&"under_fire"):
		line += "  ⚠ under fire"
	return line


## Called each physics frame by the character. Advances timers, honours the current commitment, asks
## for a new decision only when free to, then carries out the current act.
func control(character, delta: float) -> void:
	if character.is_dead:
		return
	if _character == null:
		_character = character
		_hostility.faction = character.faction
	if _agent != null and not _avoid_ready:
		_agent.max_speed = character.speed
		_avoid_ready = true
	_decide_timer -= delta
	_commit_timer -= delta
	_process_hits(character)
	_perception.observe(character, rooms, _vision, _hostility, _memory, familiar_with_house)
	_update_known(character)
	_check_salient()

	# Lost every hostile mid-fight (the sightings decayed): drop combat and reconsider now, rather
	# than keep peeking at a target we can no longer locate.
	if _intent == "combat" and _engage_id == 0:
		_intent = "idle"
		_force = true

	# An active interaction is held until its dwell runs out, the character leaves it, or a salient
	# event forces a rethink; then it ends and we fall through to decide.
	if _in_interaction:
		_interaction_timer -= delta
		if _force or not character.is_busy() or _interaction_timer <= 0.0:
			character.end_interaction()
			_in_interaction = false
			_force = true  # Pick the next step right away rather than wait out the cadence.
		else:
			return

	if _should_decide(character):
		_force = false
		_decide_timer = decide_interval
		_request_decision(character)

	_apply(character, delta)


## Whether a new decision may be issued now: never while one is in flight; always when forced; held
## back while committed to reaching a chosen object, to an idle destination (until the safety cap),
## or to a fight (while the `engaged` memory is fresh, so it keeps fighting rather than re-rolling a
## flat shoot/hold choice every cadence — peek-and-cover keeps tracking the contact meanwhile).
func _should_decide(character) -> bool:
	if _pending:
		return false
	if _force:
		return true
	if _intent == "combat":
		return not _memory.is_fresh(&"engaged")
	if _intent == "interact":
		return _commit_timer <= 0.0
	if _searching() and pursue_hostiles:
		return false  # Patrolling the house to search; only a salient event (via _force, above) re-decides.
	if _intent == "idle" and _has_move and _commit_timer > 0.0 and not _reached(character, _move_point):
		return false
	return _decide_timer <= 0.0


## Classify buffered hit events against the character and remember them: a hit on the NPC itself, or
## a hit on anything within `hit_awareness_radius` (a shot landing close — being shot at and missed),
## both count as being attacked: the incoming direction is remembered, the attacker is handed to the
## hostility rules, and the combat engagement is refreshed so sustained fire keeps the NPC fighting.
## The NPC's own hits are ignored. A hit forces an immediate re-decision only when it is NOT already
## in combat (to kick off a fight); while fighting it just refreshes the engagement, so a firefight
## doesn't re-ask Von every frame.
func _process_hits(character) -> void:
	if _hit_queue.is_empty():
		return
	var self_pos: Vector2 = character.global_position
	for data in _hit_queue:
		var attacker = data.get("attacker")
		if attacker == character:
			continue  # Our own shot or punch.
		var hit_me: bool = data.get("victim") == character
		if not hit_me and self_pos.distance_to(data.get("position", self_pos)) > hit_awareness_radius:
			continue  # A hit too far away to notice.
		var from: Vector2 = -(data.get("direction", Vector2.RIGHT) as Vector2)
		_memory.remember(&"under_fire", {"from": from}, under_fire_time)
		_memory.remember(&"engaged", {}, engage_dwell)
		if attacker is Node and is_instance_valid(attacker):
			_hostility.on_attacked(attacker, _memory)
		if _intent != "combat":
			_force = true
	_hit_queue.clear()


## Resolve what the NPC currently knows from its perception: the known hostile contacts (nearest
## first) and the engaged contact's last-known body/position/inside state. If the engaged contact is
## no longer known (its sighting decayed) or no longer hostile, a fight retargets to the nearest
## other known hostile, else `_engage_id` drops to 0. All acting reads these rather than true
## positions, so the NPC only ever acts on what it has perceived.
func _update_known(character) -> void:
	var known: Array = _perception.contacts(character.global_position, _memory, _hostility)
	var was_known := not _hostiles.is_empty()
	_hostiles = known.filter(func(c): return c["hostile"])
	_allies = known.filter(func(c): return not c["hostile"])  ## For flanking: bearings to spread away from.
	if was_known and _hostiles.is_empty():
		# Just lost every hostile: have the patrol investigate the last-known spot before sweeping rooms.
		_investigate_last_seen = true
		_patrol_active = false
	if not _hostiles.is_empty():
		_last_hostile_pos = _hostiles[0]["pos"]
	var engaged: Dictionary = {}
	for c in _hostiles:
		if c["id"] == _engage_id:
			engaged = c
	if engaged.is_empty() and _engage_id != 0:
		engaged = _hostiles[0] if not _hostiles.is_empty() else {}
		_engage_id = engaged.get("id", 0)
	if not engaged.is_empty():
		_engage_node = engaged["node"]
		_engage_pos = engaged["pos"]
		_engage_inside = engaged.get("inside", false)


## Force a re-decision when the NPC's BELIEF about hostiles changes: one is spotted, lost or newly
## categorized hostile, or the engaged contact crosses the house boundary (per its last sighting).
## These are the events worth interrupting a commitment for. Seeded on the first call so the initial
## state isn't a "change".
func _check_salient() -> void:
	var ids: Array = _hostiles.map(func(c): return c["id"])
	ids.sort()
	var key := "%s|%s" % [str(ids), str(_engage_inside) if _engage_id != 0 else "-"]
	if not _salient_init:
		_salient_key = key
		_salient_init = true
		return
	if key != _salient_key:
		_salient_key = key
		_force = true


## Whether the NPC is (or should be) searching for hostiles: it chose to search, or it pursues
## hostiles and holds with none known.
func _searching() -> bool:
	return _intent == "search" or (_intent == "idle" and pursue_hostiles and _hostiles.is_empty())


## Whether a world point lies within any of the house's rooms (the "inside the house" test).
func _inside_house(p: Vector2) -> bool:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return true
	return false


## Carry out the current act. Movement and aim are both derived from what the NPC chose to do.
func _apply(character, delta: float) -> void:
	match _intent:
		"interact":
			_apply_interact(character)
		"combat":
			_apply_combat(character, delta)
		_:
			_apply_idle(character)


## Interact intent: walk to the chosen object facing it (or a known hostile, to keep eyes on them);
## once its action is in reach, face it, run it and hold the interaction. Drops to idle if the object
## is gone or the action can't start.
func _apply_interact(character) -> void:
	if _target_obj == null or not is_instance_valid(_target_obj):
		_intent = "idle"
		character.move_input = Vector2.ZERO
		return
	if not _interaction_in_reach(character):
		character.aim_point = _last_hostile_pos if not _hostiles.is_empty() else _target_obj.global_position
		_path_move(character, _target_obj.global_position)
		return
	character.move_input = Vector2.ZERO
	character.aim_point = _target_obj.global_position  # face the object to perform the interaction
	if not _act_armed:
		_act_armed = true  # Let facing settle before acting.
		return
	if character.interact_with(_target_obj, _interact_id):
		_in_interaction = true
		_interaction_timer = interaction_dwell
	else:
		_intent = "idle"


## Combat intent: always face where the engaged contact was last seen, then fight tactically. A punch
## just closes and swings; a shot runs the peek-and-cover cycle below. Firing is gated on a clear line
## to the contact's last-known position (so the NPC never shoots through walls) and paced by
## `fire_cooldown`. With `defend_territory`, a contact outside the house is fought from inside rather
## than chased out.
func _apply_combat(character, delta: float) -> void:
	character.aim_point = _engage_pos  # Aim at where we last saw them, not their true position.
	_fire_timer -= delta
	_hold_ground = defend_territory and not _engage_inside
	if _act_verb == "punch":
		_apply_melee(character)
		return
	_apply_peek_cover(character, delta)


## Peek-and-cover shooting: in the PEEK phase, move to a spot with a clear shot and fire, then duck;
## in the COVER phase, hold behind a shielding object for `cover_time` before peeking again. The
## fire/cover destination is committed for `reposition_interval` rather than re-picked every frame,
## so the NPC steers smoothly instead of vibrating between near-equal candidates.
func _apply_peek_cover(character, delta: float) -> void:
	var dist: float = character.global_position.distance_to(_engage_pos)
	_combat_dest_timer -= delta
	if _combat_phase == "cover":
		_cover_timer -= delta
		if _combat_dest_timer <= 0.0:
			_combat_dest = _choose_combat_dest(character, "cover")
			_combat_dest_timer = reposition_interval
		_path_move(character, _combat_dest)
		if _cover_timer <= 0.0:
			_combat_phase = "peek"
			_combat_dest_timer = 0.0  # Re-pick a firing spot immediately on peeking out.
		return
	# PEEK: take the shot if a clear line to the known position is in range, else reposition to get one.
	if dist <= shoot_range and _perception.has_line_to(character, _engage_node, _engage_pos):
		character.move_input = Vector2.ZERO
		if _fire_timer <= 0.0:
			_fire(character)
			_fire_timer = fire_cooldown
			_combat_phase = "cover"
			_cover_timer = cover_time
			_combat_dest_timer = 0.0  # Pick a cover spot immediately after shooting.
		return
	if _combat_dest_timer <= 0.0:
		_combat_dest = _choose_combat_dest(character, "peek")
		_combat_dest_timer = reposition_interval
	_path_move(character, _combat_dest)


## The committed destination for the current phase: a spot with a clear shot (peek) or the nearest
## shielded spot (cover); falls back to closing on the contact (peek) or holding (cover) when no
## suitable spot exists this sample. The peek spot is the nearest clear one, unless `flank` is on, in
## which case `_flank_pick` re-ranks for the best flanking angle. While holding ground (an outside
## contact under `defend_territory`), spots are restricted to inside the house and the peek fallback
## holds position instead of advancing out, so the NPC returns fire from inside rather than pursuing it.
func _choose_combat_dest(character, phase: String) -> Vector2:
	var spots: Dictionary = _perception.combat_spots(character, _engage_node, _engage_pos, combat_ring_radius, combat_ring_count)
	var fire: Array = spots["fire"]
	var cover: Array = spots["cover"]
	if _hold_ground:
		fire = fire.filter(func(p): return _inside_house(p))
		cover = cover.filter(func(p): return _inside_house(p))
	if phase == "cover":
		return cover[0] if not cover.is_empty() else character.global_position
	if not fire.is_empty():
		return _flank_pick(character, fire) if flank else fire[0]
	return character.global_position if _hold_ground else _engage_pos


## The bearings (radians, measured FROM the engaged target) that flanking should steer AWAY from:
## where the target is FACING when it is currently visible (so the NPC attacks its side/rear, not its
## front), and the bearing to each known ally within `flank_ally_radius` of the target (so allied
## attackers spread around it instead of bunching). An unseen target yields no facing bearing — the
## NPC never reads an omniscient facing it hasn't perceived.
func _flank_anchors() -> Array:
	var anchors: Array = []
	if _engage_node != null and is_instance_valid(_engage_node) and "facing" in _engage_node \
			and _perception.contact_visible(_engage_id):
		anchors.append((_engage_node.facing as Vector2).angle())
	for ally in _allies:
		var pos: Vector2 = ally["pos"]
		if pos.distance_to(_engage_pos) <= flank_ally_radius:
			anchors.append((pos - _engage_pos).angle())
	return anchors


## Pick the flanking fire spot: the one whose bearing from the target is furthest from every avoided
## bearing (openness), traded against how far the NPC must travel to it. With no bearings to avoid it
## returns the nearest spot, so flanking collapses to the old nearest-spot behaviour.
func _flank_pick(character, fire: Array) -> Vector2:
	var anchors: Array = _flank_anchors()
	if anchors.is_empty() or fire.is_empty():
		return fire[0]
	var self_pos: Vector2 = character.global_position
	var best: Vector2 = fire[0]
	var best_score := -INF
	for p in fire:
		var bearing: float = ((p as Vector2) - _engage_pos).angle()
		var sep := PI
		for a in anchors:
			sep = minf(sep, absf(angle_difference(bearing, a)))
		var score := (sep / PI) * flank_weight - self_pos.distance_to(p)
		if score > best_score:
			best_score = score
			best = p
	return best


## Melee combat: close to punch range and swing on the fire cooldown (no cover cycle for fists).
## While holding ground it won't chase a contact out of the house — it only swings if one is
## already in reach.
func _apply_melee(character) -> void:
	if character.global_position.distance_to(_engage_pos) > punch_range:
		if not _hold_ground:
			_path_move(character, _engage_pos)
		else:
			character.move_input = Vector2.ZERO
		return
	character.move_input = Vector2.ZERO
	if _fire_timer <= 0.0:
		_fire(character)
		_fire_timer = fire_cooldown


## Equip the act's slot and throw one shot/punch, refreshing the combat engagement so an active
## fight stays committed.
func _fire(character) -> void:
	_memory.remember(&"engaged", {}, engage_dwell)
	if _engage_slot > 0:
		character.select_slot(_engage_slot)
	if _act_verb == "shoot":
		character.shoot()
	else:
		character.melee()


## Idle / search intent. A searching NPC (chose to search, or pursues hostiles and knows none) patrols
## the house, walking room to room and looking where it goes. Otherwise it watches the nearest known
## hostile and/or moves to a chosen named destination if there is one.
func _apply_idle(character) -> void:
	if _searching():
		_patrol(character)
		return
	if not _hostiles.is_empty():
		character.aim_point = _last_hostile_pos
	if _has_move and not _reached(character, _move_point):
		_path_move(character, _move_point)
		return
	if _has_move:
		_has_move = false
		_force = true  # Arrived; pick the next step.
	character.move_input = Vector2.ZERO


## Patrol the house searching for hostiles: walk to the current patrol destination and face
## the direction of travel so the view cone leads the way (no in-place spin). The destination is the
## last-known hostile spot right after losing sight (investigate there first), then a cycle through
## the rooms, re-picked each time the current one is reached. Acquisition happens via the vision sense;
## the instant a hostile is known, a salient event re-decides and pursuit converts this to combat.
func _patrol(character) -> void:
	_patrol_timer -= get_physics_process_delta_time()
	var arrived := not _patrol_active
	if _patrol_active and _patrol_room_key != "":
		arrived = _room_key_at(character.global_position) == _patrol_room_key  # entered the room
	elif _patrol_active:
		arrived = _reached(character, _patrol_point)  # a non-room point (the last-seen spot)
	if arrived or _patrol_timer <= 0.0:  # timeout guards against a leg that can't be reached
		_patrol_point = _reachable(_next_patrol_point(character))
		_patrol_active = true
		_patrol_timer = max_commit_time
	_path_move(character, _patrol_point)
	if character.move_input != Vector2.ZERO:
		character.aim_point = character.global_position + character.move_input * 100.0


## The next place to search: the last-known hostile position once, right after losing sight, then a
## round-robin tour through every room (skipping the one the NPC is standing in), so the patrol covers
## the whole house rather than circling one corner. Also sets `_patrol_room_key` (the leg's target
## room, or "" for the last-seen point). Holds position when there are no rooms.
func _next_patrol_point(character) -> Vector2:
	if _investigate_last_seen:
		_investigate_last_seen = false
		_patrol_room_key = ""
		return _last_hostile_pos
	if rooms.is_empty():
		_patrol_room_key = ""
		return character.global_position
	var here := _room_key_at(character.global_position)
	for _n in rooms.size():  # advance through the list, skipping the current room
		_patrol_idx = (_patrol_idx + 1) % rooms.size()
		if rooms[_patrol_idx]["key"] != here:
			break
	var rect: Rect2 = rooms[_patrol_idx]["rect"]
	_patrol_room_key = rooms[_patrol_idx]["key"]
	return rect.position + rect.size * 0.5


## Snap a world point onto the navigation mesh so it is actually reachable — a room's geometric
## centre is often inside furniture (off the navmesh), which would make the nav agent treat it as
## unreachable and wedge the NPC trying to shove toward it. Returns `p` unchanged with no nav agent.
func _reachable(p: Vector2) -> Vector2:
	if _agent == null:
		return p
	var map: RID = _agent.get_navigation_map()
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return p  # Nav map not synchronized yet (very first frames); snap once it is baked.
	return NavigationServer2D.map_get_closest_point(map, p)


## The key of the room containing world point `p`, or "" when `p` is in no room.
func _room_key_at(p: Vector2) -> String:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return room["key"]
	return ""


## Whether the chosen interaction on `_target_obj` is currently reachable (lets the approach stop and
## the action begin).
func _interaction_in_reach(character) -> bool:
	for entry in character.interactions_in_reach():
		if entry["object"] != _target_obj:
			continue
		for spec in entry["specs"]:
			if spec.get("id", "") == _interact_id:
				return true
	return false


## Whether the NPC has reached `point` (nav path finished, or within arrive_dist straight-line).
func _reached(character, point: Vector2) -> bool:
	if _agent != null:
		_agent.target_position = point
		return _agent.is_navigation_finished()
	return character.global_position.distance_to(point) < arrive_dist


## Steer `character.move_input` toward `dest` along a navigated path (around walls and furniture,
## through doorways). The navmesh carves out furniture, so the path routes around a piece and reroutes
## through another doorway when one is blocked; RVO avoidance (fed each frame, applied from the
## previous frame's safe velocity) smooths steering around a piece just shoved. When no route exists
## at all (`is_target_reachable()` false) or the NPC stays wedged for `push_through_delay`, it shoves
## straight through the blocker as a last resort, using the character's own push physics.
## Falls back to plain straight-line steering when there is no navigation agent.
func _path_move(character, dest: Vector2) -> void:
	if _agent == null:
		var straight: Vector2 = dest - character.global_position
		character.move_input = Vector2.ZERO if straight.length() < arrive_dist else straight.normalized()
		return
	_agent.target_position = dest
	if _agent.is_navigation_finished():
		character.move_input = Vector2.ZERO
		_reset_stuck(character)
		return
	var next := _agent.get_next_path_position()
	var desired: Vector2 = next - character.global_position
	desired = desired.normalized() if desired.length() > 0.001 else Vector2.ZERO
	_agent.velocity = desired * character.speed  # Request this frame's avoidance-safe velocity.
	_update_stuck(character)
	if _push_through:
		# No route around (or wedged): drive straight at the blocker so the character shoves it.
		var aim: Vector2 = dest if not _agent.is_target_reachable() else next
		character.move_input = (aim - character.global_position).normalized()
	elif character.speed > 0.0:
		character.move_input = _safe_velocity / character.speed  # Length <= 1 (push-strength scaling).
	else:
		character.move_input = desired


## Store the agent's avoidance-adjusted velocity; `_path_move` applies it the next frame (writing
## move_input synchronously there, like every other act, rather than from this async callback).
func _on_avoidance_velocity(safe_velocity: Vector2) -> void:
	_safe_velocity = safe_velocity


## Track whether the NPC is blocked while pathing and flip `_push_through` once it has been blocked
## for `push_through_delay`. Blocked = the target is unreachable (furniture seals every route) or the
## character advanced less than `stuck_speed` this frame.
func _update_stuck(character) -> void:
	var step := get_physics_process_delta_time()
	var moved: float = character.global_position.distance_to(_last_pos)
	_last_pos = character.global_position
	if not _agent.is_target_reachable() or moved < stuck_speed * step:
		_stuck_time += step
	else:
		_stuck_time = 0.0
	_push_through = _stuck_time >= push_through_delay


## Clear stuck/push-through state when the NPC arrives or stops pathing.
func _reset_stuck(character) -> void:
	_stuck_time = 0.0
	_push_through = false
	_last_pos = character.global_position


## Sense the situation and POST it with the `move` and `act` `choice` questions. Falls back to a
## steady stance if the request can't even be started.
func _request_decision(character) -> void:
	var ctx: Dictionary = _perception.sense(character, rooms, goal, _memory, _hostility)
	_moves = ctx["moves"]
	_acts = ctx["acts"]
	var body := {
		"model": model,
		"state": ctx["state_text"],
		"questions": {
			"act": _question("What should you do right now?", _acts),
			"move": _question("If you are just holding, which place should you go to?", _moves),
		},
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _http.request(server_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		_pending = true
	else:
		_fallback()
		print("%s (Von) request failed to start — holding steady" % _npc_name())


## A `choice` question whose criteria map each option id to its human-readable description.
func _question(instructions: String, options: Dictionary) -> Dictionary:
	var criteria := {}
	for id in options:
		criteria[id] = options[id]["desc"]
	return { "type": "choice", "instructions": instructions, "criteria": criteria }


## Read the answers and adopt Von's top pick for each; fall back to a steady stance on failure.
func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fallback()
		print("%s (Von) server unreachable (result %d, HTTP %d) — holding steady" % [_npc_name(), result, code])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("answers") is Dictionary:
		_fallback()
		print("%s (Von) malformed response — holding steady" % _npc_name())
		return
	var answers: Dictionary = data["answers"]
	_set_act(_pick(answers, "act", _acts))
	_set_move(_pick(answers, "move", _moves))
	print("%s (Von) act=%s move=%s intent=%s" % [_npc_name(), _act_log, _move_id, _intent])


## The driven character's name, for log lines.
func _npc_name() -> String:
	return str(_character.name) if _character != null else "NPC"


## The offered option id Von ranks highest for question `key`: its argmax `choice` when that is one of
## this tick's options, else the highest-probability offered id. Von's distributions over these
## options are flat (low confidence), so taking the top pick — rather than sampling — keeps the NPC
## decisive and goal-coherent instead of jittering. Empty when no offered option has any probability.
func _pick(answers: Dictionary, key: String, options: Dictionary) -> String:
	var answer = answers.get(key)
	if not answer is Dictionary:
		return ""
	var choice = answer.get("choice")
	if choice is String and options.has(choice):
		return choice
	return _argmax(answer, options)


## The offered id with the greatest probability in `answer.probabilities` (ignoring ids not offered
## this tick, so a stale or foreign id can never be chosen); empty if none are present.
func _argmax(answer: Dictionary, options: Dictionary) -> String:
	if not answer.get("probabilities") is Dictionary:
		return ""
	var best := ""
	var best_p := -1.0
	for id in answer["probabilities"]:
		if options.has(id) and float(answer["probabilities"][id]) > best_p:
			best_p = float(answer["probabilities"][id])
			best = id
	return best


## Adopt the chosen act: resolve its verb into an intent (interact / combat / search / idle), capture
## the object + id for an interaction or the contact for an engagement, commit, and re-arm the
## one-frame action delay. The pursuit primitive and the engaged backstop override Von's pick first.
func _set_act(id: String) -> void:
	var verb: String = _acts.get(id, {}).get("verb", "hold")
	if pursue_hostiles and not _hostiles.is_empty() and verb in ["interact", "hold", "search"]:
		# Pursuing with a known hostile: engage the nearest rather than do a chore or stand idle. The
		# large interaction menu otherwise dilutes Von's ranking and lets it pick e.g. "sit".
		id = _engage_act_for(_hostiles[0]["id"], id)
	elif pursue_hostiles and _hostiles.is_empty() and verb == "interact":
		# Searching: don't park in a passive interaction (it freezes the NPC facing one way and
		# blinds it). Search the house instead.
		id = "search"
	elif _memory.is_fresh(&"engaged") and verb == "interact" and not _hostiles.is_empty():
		# Backstop for a non-pursuing NPC dragged into a fight: once engaged, a re-decision must not
		# peel it off to sit/use furniture mid-combat.
		id = _engage_act_for(_hostiles[0]["id"], id)
	var opt: Dictionary = _acts.get(id, {})
	_act_verb = opt.get("verb", "search" if id == "search" else "hold")
	_act_log = id if id != "" else "hold"
	_act_armed = false
	match _act_verb:
		"interact":
			_intent = "interact"
			_target_obj = opt.get("object")
			_interact_id = opt.get("id", "")
			_commit_timer = max_commit_time
		"shoot", "punch":
			_intent = "combat"
			_target_obj = null
			_engage_id = opt.get("target", 0)
			_engage_slot = opt.get("slot", 0)
			for c in _hostiles:
				if c["id"] == _engage_id:
					_engage_node = c["node"]
					_engage_pos = c["pos"]
					_engage_inside = c.get("inside", false)
			_memory.remember(&"engaged", {}, engage_dwell)  # Commit to the fight (refreshed by firing).
		"search":
			_intent = "search"
			_target_obj = null
		_:
			_intent = "idle"
			_target_obj = null


## The engage act id for contact `contact_id`: shoot when offered, else punch; `fallback` if neither.
func _engage_act_for(contact_id: int, fallback: String) -> String:
	for verb in ["shoot", "punch"]:
		var act := "%s_%d" % [verb, contact_id]
		if _acts.has(act):
			return act
	return fallback


## Adopt the chosen idle destination (used only when the act is "hold").
func _set_move(id: String) -> void:
	_move_id = id
	_has_move = id != "" and _moves.has(id)
	if _has_move:
		_move_point = _moves[id]["point"]
		if _intent == "idle":
			_commit_timer = max_commit_time


## A steady, non-chaotic stance for when Von is unreachable (server-down path): stop and watch any
## known hostile rather than thrash between random options.
func _fallback() -> void:
	_intent = "idle"
	_target_obj = null
	_has_move = false
	_act_verb = "hold"
	_act_log = "hold"
	_move_id = ""
