extends Node

## AI BEHAVIOUR sub-domain. Turns the act Von chose into concrete movement + actions on the character,
## and holds the System-Two state Von (a stateless single-shot ranker) lacks: the engaged contact, the
## peek-and-cover combat cycle, the patrol tour, the interaction in progress, and the COMMITMENT timers
## that keep a multi-step goal advancing instead of oscillating. It owns a `Locomotion` child for all
## pathing. It reads the world only through the PERCEPTION sub-domain (known contacts, combat geometry,
## engagement memory) and drives the character only through its public controller contract
## (`move_input` / `aim_point`, `select_slot`, `shoot`, `melee`, `interact_with`, `end_interaction`).
##
## It applies the three controller POLICIES Von can't: pursuit (`pursue_hostiles` — hunt rather than do
## chores), territory (`defend_territory` — return fire from inside the house rather than chase out),
## and flanking (`flank` — attack from the target's side/rear and spread allied attackers around it).
## The orchestrator owns WHEN to re-decide; this owns WHAT the chosen act does. All tunables are set by
## the controller (the single authoring surface) before `setup()`.

const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")

# --- Config fields the controller copies from its exports before setup(). ---
var pursue_hostiles: bool = true
var defend_territory: bool = false
var interaction_dwell: float = 3.0
var max_commit_time: float = 6.0
var shoot_range: float = 500.0
var punch_range: float = 48.0
var combat_ring_radius: float = 80.0
var combat_ring_count: int = 12
var cover_time: float = 1.2
var fire_cooldown: float = 0.5
var reposition_interval: float = 0.5
var flank: bool = true
var flank_weight: float = 140.0
var flank_ally_radius: float = 500.0
# Locomotion config (forwarded to the Locomotion child in setup()).
var arrive_dist: float = 10.0
var push_through_delay: float = 1.0
var stuck_speed: float = 20.0
var door_open_reach: float = 40.0

## World-space room rects (`{ key, type, rect }`), set each tick by the controller from Main's inject.
var rooms: Array = []
## The house entrance in world space; the patrol heads here first while outside. Cleared after use.
var entry_point: Vector2 = Vector2.ZERO

var _perception: Node             ## The perception sub-domain (contacts, combat geometry, engagement memory).
var _loco: Node                   ## The Locomotion child (pathing).
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
var _in_interaction := false      ## Committed to an active object interaction.
var _interaction_timer := 0.0     ## Seconds left before ending the current interaction.
var _commit_timer := 0.0          ## Seconds left on the current approach commitment (safety cap).
var _resolved := false            ## A task just finished (interaction ended / idle destination reached) → re-decide.


## Build the Locomotion child and capture the perception sub-domain. The controller calls this once in
## its _ready() after copying its exports onto the fields above.
func setup(perception: Node, nav_agent: NavigationAgent2D) -> void:
	_perception = perception
	_loco = Locomotion.new()
	_loco.arrive_dist = arrive_dist
	_loco.push_through_delay = push_through_delay
	_loco.stuck_speed = stuck_speed
	_loco.door_open_reach = door_open_reach
	_loco.setup(nav_agent)
	add_child(_loco)


## Read-only: the act the NPC is currently carrying out (its last decision), for observers/HUD.
func current_act() -> String:
	return _act_log


## Read-only: the current intent mode (interact / combat / search / idle), for the controller's log
## and salient/decide logic.
func intent() -> String:
	return _intent


## Read-only: whether the NPC is currently in combat (so a fresh hit doesn't force a re-decision).
func in_combat() -> bool:
	return _intent == "combat"


## Read-only: the engaged contact's last-seen inside/outside state packed into the salient key — the
## controller re-decides when this (or the known-hostile set) changes.
func salient_key() -> String:
	var ids: Array = _hostiles.map(func(c): return c["id"])
	ids.sort()
	return "%s|%s" % [str(ids), str(_engage_inside) if _engage_id != 0 else "-"]


## Read-only: a compact, human-readable summary of what the NPC is doing right now — for debug
## overlays/observers. Built from live state (never mutates).
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
	if _perception != null and _perception.under_fire():
		line += "  ⚠ under fire"
	return line


## Resolve what the NPC currently knows from the perception's contact list (hostiles/allies, the
## engaged contact's last-known body/position/inside state), advancing the commitment timer. If the
## engaged contact is no longer known (its sighting decayed) or no longer hostile, a fight retargets to
## the nearest other known hostile, else `_engage_id` drops to 0 — and when that empties an active
## fight it drops to idle and returns true so the controller re-decides. All acting reads these rather
## than true positions, so the NPC only ever acts on what it has perceived.
func update_known(character, known: Array, delta: float) -> bool:
	_loco.ensure_max_speed(character)
	_commit_timer -= delta
	var was_known := not _hostiles.is_empty()
	_hostiles = known.filter(func(c): return c["hostile"])
	_allies = known.filter(func(c): return not c["hostile"])  ## For flanking: bearings to spread away from.
	if was_known and _hostiles.is_empty():
		# Only investigate the last-known spot when a contact was lost (sighting decayed). Skip it when
		# the engaged contact was just killed — their corpse is already there and adds no information.
		var engaged_killed: bool = is_instance_valid(_engage_node) and _engage_node.get("is_dead") == true
		if not engaged_killed:
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
	# Lost every hostile mid-fight (the sightings decayed): drop combat so the controller reconsiders,
	# rather than keep peeking at a target we can no longer locate.
	if _intent == "combat" and _engage_id == 0:
		_intent = "idle"
		return true
	return false


## Advance an active interaction: hold it until its dwell runs out, the character leaves it, or the
## controller forces a rethink (`force`); then end it and flag the task resolved. Returns true while the
## NPC is STILL interacting (the controller should do nothing more this tick).
func service_interaction(character, delta: float, force: bool) -> bool:
	if not _in_interaction:
		return false
	_interaction_timer -= delta
	if force or not character.is_busy() or _interaction_timer <= 0.0:
		character.end_interaction()
		_in_interaction = false
		_resolved = true  # Pick the next step right away rather than wait out the cadence.
		return false
	return true


## Whether a committed task just finished (interaction ended / idle destination reached). Clears the
## flag; the controller forces a re-decision when it returns true.
func take_resolved() -> bool:
	var r := _resolved
	_resolved = false
	return r


## Whether the NPC wants a new decision now, given its commitment: a fight re-decides once the
## `engaged` memory lapses; an approach holds until its safety cap; a pursuing search never re-decides
## on cadence (only a salient event does); an idle move holds until it arrives; otherwise the cadence
## (`decide_timer_elapsed`) governs.
func wants_decision(character, decide_timer_elapsed: bool) -> bool:
	if _intent == "combat":
		return not _perception.engaged_fresh()
	if _intent == "interact":
		return _commit_timer <= 0.0
	if _searching() and pursue_hostiles:
		return false  # Patrolling the house to search; only a salient event re-decides.
	if _intent == "idle" and _has_move and _commit_timer > 0.0 and not _loco.reached(character, _move_point):
		return false
	return decide_timer_elapsed


## Whether the NPC is (or should be) searching for hostiles: it chose to search, or it pursues
## hostiles and holds with none known.
func _searching() -> bool:
	return _intent == "search" or (_intent == "idle" and pursue_hostiles and _hostiles.is_empty())


## Carry out the current act. Movement and aim are both derived from what the NPC chose to do.
func apply(character, delta: float) -> void:
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
		_loco.move_to(character, _target_obj.global_position)
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
		_loco.move_to(character, _combat_dest)
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
	_loco.move_to(character, _combat_dest)


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
			_loco.move_to(character, _engage_pos)
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
	_perception.note_engaged()
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
	if _has_move and not _loco.reached(character, _move_point):
		_loco.move_to(character, _move_point)
		return
	if _has_move:
		_has_move = false
		_resolved = true  # Arrived; pick the next step.
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
		arrived = _loco.reached(character, _patrol_point)  # a non-room point (the last-seen spot)
	if arrived or _patrol_timer <= 0.0:  # timeout guards against a leg that can't be reached
		_patrol_point = _loco.reachable(_next_patrol_point(character))
		_patrol_active = true
		_patrol_timer = max_commit_time
	_loco.move_to(character, _patrol_point)
	if character.move_input != Vector2.ZERO:
		character.aim_point = character.global_position + character.move_input * 100.0


## The next place to search: the last-known hostile position once, right after losing sight; then,
## when outside all rooms and given an entry_point (e.g. the front door), head there directly; then a
## round-robin tour through every room (skipping the one the NPC is standing in), so the patrol covers
## the whole house. Also sets `_patrol_room_key` (the leg's target room, or "" for a point leg).
## Holds position when there are no rooms.
func _next_patrol_point(character) -> Vector2:
	if _investigate_last_seen:
		_investigate_last_seen = false
		_patrol_room_key = ""
		return _last_hostile_pos
	if rooms.is_empty():
		_patrol_room_key = ""
		return character.global_position
	var here := _room_key_at(character.global_position)
	if here == "":
		_patrol_room_key = ""
		if entry_point != Vector2.ZERO:
			# Familiar NPC: go directly to the known entrance. Cleared after use so the NPC
			# switches to room patrol once past the door.
			var dest := entry_point
			entry_point = Vector2.ZERO
			return dest
		# Unfamiliar NPC outside: aim at the house centroid — the NPC can see the building and
		# heads toward it; the nav agent routes naturally through the entrance to get there.
		return _house_centroid()
	for _n in rooms.size():  # advance through the list, skipping the current room
		_patrol_idx = (_patrol_idx + 1) % rooms.size()
		if rooms[_patrol_idx]["key"] != here:
			break
	var rect: Rect2 = rooms[_patrol_idx]["rect"]
	_patrol_room_key = rooms[_patrol_idx]["key"]
	return rect.position + rect.size * 0.5


## The centre of the bounding box that encloses all rooms — used as the "head toward the building"
## target for an NPC that is outside and doesn't know the entrance location.
func _house_centroid() -> Vector2:
	var bounds := (rooms[0]["rect"] as Rect2)
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	return bounds.position + bounds.size * 0.5


## Whether a world point lies within any of the house's rooms (the "inside the house" test).
func _inside_house(p: Vector2) -> bool:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return true
	return false


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


## Adopt the chosen act: resolve its verb into an intent (interact / combat / search / idle), capture
## the object + id for an interaction or the contact for an engagement, commit, and re-arm the
## one-frame action delay. The pursuit primitive and the engaged backstop override Von's pick first.
func set_act(id: String, acts: Dictionary) -> void:
	var verb: String = acts.get(id, {}).get("verb", "hold")
	if pursue_hostiles and not _hostiles.is_empty() and verb in ["interact", "hold", "search"]:
		# Pursuing with a known hostile: engage the nearest rather than do a chore or stand idle. The
		# large interaction menu otherwise dilutes Von's ranking and lets it pick e.g. "sit".
		id = _engage_act_for(_hostiles[0]["id"], id, acts)
	elif pursue_hostiles and _hostiles.is_empty() and verb == "interact":
		# Searching: don't park in a passive interaction (it freezes the NPC facing one way and
		# blinds it). Search the house instead.
		id = "search"
	elif _perception.engaged_fresh() and verb == "interact" and not _hostiles.is_empty():
		# Backstop for a non-pursuing NPC dragged into a fight: once engaged, a re-decision must not
		# peel it off to sit/use furniture mid-combat.
		id = _engage_act_for(_hostiles[0]["id"], id, acts)
	var opt: Dictionary = acts.get(id, {})
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
			_perception.note_engaged()  # Commit to the fight (refreshed by firing).
		"search":
			_intent = "search"
			_target_obj = null
		_:
			_intent = "idle"
			_target_obj = null


## The engage act id for contact `contact_id`: shoot when offered, else punch; `fallback_id` if neither.
func _engage_act_for(contact_id: int, fallback_id: String, acts: Dictionary) -> String:
	for verb in ["shoot", "punch"]:
		var act := "%s_%d" % [verb, contact_id]
		if acts.has(act):
			return act
	return fallback_id


## Adopt the chosen idle destination (used only when the act is "hold").
func set_move(id: String, moves: Dictionary) -> void:
	_move_id = id
	_has_move = id != "" and moves.has(id)
	if _has_move:
		_move_point = moves[id]["point"]
		if _intent == "idle":
			_commit_timer = max_commit_time


## A steady, non-chaotic stance for when Von is unreachable (server-down path): stop and watch any
## known hostile rather than thrash between random options.
func fallback() -> void:
	_intent = "idle"
	_target_obj = null
	_has_move = false
	_act_verb = "hold"
	_act_log = "hold"
	_move_id = ""
