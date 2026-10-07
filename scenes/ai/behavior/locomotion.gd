extends Node

## AI BEHAVIOUR sub-domain — LOCOMOTION. Owns the NavigationAgent2D and turns a target point into
## steering on the character: `move_to()` writes `character.move_input` to follow a navigated path
## around walls and furniture and through doorways. The navmesh (baked by the Navigation domain)
## carves out furniture and rings the house with a walkable outdoor strip, so paths route around a
## piece and reroute through another doorway when one is blocked; RVO avoidance (fed each frame,
## applied from the previous frame's safe velocity) smooths steering around a piece just shoved.
##
## When no route exists at all, or the NPC stays wedged for `push_through_delay`, it shoves straight
## through the blocker as a last resort, using the character's own push physics — except that a shut
## door within `door_open_reach` is deliberately OPENED instead (doorways stay walkable in the navmesh,
## so the NPC paths up to the door and opens it). It is behaviour's movement tool only — it holds no
## decision or combat state. Falls back to straight-line steering when there is no nav agent.

## How close (px) counts as "arrived" when steering straight-line (no nav agent).
var arrive_dist: float = 10.0
## How long (s) the NPC stays blocked before it shoves straight through the blocker.
var push_through_delay: float = 1.0
## Speed (px/s) under which the NPC counts as blocked while trying to follow a path.
var stuck_speed: float = 20.0
## How close (px) a shut door must be, while blocked, to be opened instead of shoved through. 0 = off.
var door_open_reach: float = 40.0

var _agent: NavigationAgent2D     ## Pathfinding agent, or null (falls back to straight-line).
var _safe_velocity := Vector2.ZERO ## Latest avoidance-adjusted velocity from the agent (RVO callback).
var _avoid_ready := false          ## Whether the agent's avoidance (max_speed) has been configured.
var _last_pos := Vector2.ZERO      ## Character position last path-move frame, for stuck detection.
var _stuck_time := 0.0             ## Seconds the NPC has been blocked while following a path.
var _push_through := false         ## True while shoving straight through a blocker (the last resort).


## Resolve + wire the navigation agent. `agent` may be null (then everything falls back to straight
## line steering). RVO avoidance steers the NPC around furniture (tagged with NavigationObstacle2D by
## the Navigation domain); max_speed is set from the character on the first ensure_max_speed() call.
func setup(agent: NavigationAgent2D) -> void:
	_agent = agent
	if _agent != null:
		_agent.avoidance_enabled = true
		_agent.velocity_computed.connect(_on_avoidance_velocity)


## Configure the agent's max_speed from the character on the first tick (avoidance needs it).
func ensure_max_speed(character) -> void:
	if _agent != null and not _avoid_ready:
		_agent.max_speed = character.speed
		_avoid_ready = true


## Snap a world point onto the navigation mesh so it is actually reachable — a room's geometric
## centre is often inside furniture (off the navmesh), which would make the nav agent treat it as
## unreachable and wedge the NPC trying to shove toward it. Returns `p` unchanged with no nav agent.
func reachable(p: Vector2) -> Vector2:
	if _agent == null:
		return p
	var map: RID = _agent.get_navigation_map()
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return p  # Nav map not synchronized yet (very first frames); snap once it is baked.
	return NavigationServer2D.map_get_closest_point(map, p)


## Whether the NPC has reached `point` (nav path finished, or within arrive_dist straight-line).
func reached(character, point: Vector2) -> bool:
	if _agent != null:
		_agent.target_position = point
		return _agent.is_navigation_finished()
	return character.global_position.distance_to(point) < arrive_dist


## Steer `character.move_input` toward `dest` along a navigated path (around walls and furniture,
## through doorways). When no route exists at all (`is_target_reachable()` false) or the NPC stays
## wedged for `push_through_delay`, it shoves straight through the blocker as a last resort, using the
## character's own push physics. Falls back to plain straight-line steering when there is no agent.
func move_to(character, dest: Vector2) -> void:
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
	_open_blocking_door(character)
	if _push_through:
		# No route around (or wedged): drive straight at the blocker so the character shoves it.
		var aim: Vector2 = dest if not _agent.is_target_reachable() else next
		character.move_input = (aim - character.global_position).normalized()
	elif character.speed > 0.0:
		character.move_input = _safe_velocity / character.speed  # Length <= 1 (push-strength scaling).
	else:
		character.move_input = desired


## Store the agent's avoidance-adjusted velocity; `move_to` applies it the next frame (writing
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


## While blocked on a path, deliberately open a shut door within `door_open_reach` instead of
## shoving through it: the doorway is walkable in the navmesh, so the NPC simply walks up to the
## closed door and opens it. Generic over every NPC — the invader opening the front door and the
## defender opening interior doors as it searches are the same code. A closed door still blocks
## movement and line-of-fire until opened (or shot out).
func _open_blocking_door(character) -> void:
	if door_open_reach <= 0.0 or _stuck_time <= 0.0:
		return
	for door in get_tree().get_nodes_in_group("doors"):
		if not is_instance_valid(door) or door.is_open():
			continue
		if door.operate_distance(character.global_position) <= door_open_reach:
			door.open()
			return
