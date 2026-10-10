extends Node

## AI BEHAVIOUR sub-domain — LOCOMOTION. Owns the NavigationAgent2D and turns a target point into
## steering on the character: `move_to()` writes `character.move_input` to follow a navigated path
## around walls and furniture and through doorways. The navmesh (baked by the Navigation domain)
## carves out furniture and rings the house with a walkable outdoor strip, so paths route around a
## piece and reroute through another doorway when one is blocked.
##
## Steering always aims at the next navmesh waypoint, so the character's own push physics bulldoze
## furniture sitting on the route without ever tunnelling a wall. It is behaviour's movement tool
## only — it holds no decision or combat state. Falls back to straight-line steering when there is
## no nav agent.

## How close (px) counts as "arrived" when steering straight-line (no nav agent).
var arrive_dist: float = 10.0

## Stuck-sensing window (s): displacement is compared over this span while the NPC is trying to move.
const STALL_WINDOW := 0.75
## Speed (px/s) below which an NPC that is trying to move counts as not progressing.
const STALL_SPEED := 8.0
## Seconds between recorded trail points, and the most points kept (a short recent-position trail).
const TRAIL_STEP := 0.25
const TRAIL_MAX := 24

var _agent: NavigationAgent2D     ## Pathfinding agent, or null (falls back to straight-line).
var _stall_pos := Vector2.ZERO    ## Position at the start of the current stall-sensing window.
var _stall_clock := 0.0           ## Seconds into the current window.
var _stall_speed := 0.0           ## Speed (px/s) measured over the last full window.
var _stalled_for := 0.0           ## Seconds the NPC has been trying to move without progressing.
var _trail_clock := 0.0           ## Seconds since the last trail point.
var _trail: Array = []            ## Recent world positions, oldest first.


## Resolve + wire the navigation agent. `agent` may be null (then everything falls back to straight
## line steering).
func setup(agent: NavigationAgent2D) -> void:
	_agent = agent


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


## Whether world point `p` lies ON the baked navmesh — i.e. walkable floor, not inside a carved
## furniture hole or outside the walkable area — true when the closest navmesh point is within `tol`
## px of `p`. Returns true when there is no agent or the map isn't baked yet (nothing to test against),
## so callers don't over-filter during the first frames. Used to keep search-coverage points off
## furniture.
func on_navmesh(p: Vector2, tol: float = 8.0) -> bool:
	if _agent == null:
		return true
	var map: RID = _agent.get_navigation_map()
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return true
	return NavigationServer2D.map_get_closest_point(map, p).distance_to(p) <= tol


## Read-only: the pathing state behind the current move, for the AI's `debug_state()` snapshot. Uses
## only side-effect-free agent reads — notably NOT `get_next_path_position()`, which advances the
## agent's path index and so would perturb movement if called out of band by an observer. `next` is
## therefore read off the path array at the live index instead.
func debug_state() -> Dictionary:
	if _agent == null:
		return { "agent": false }
	var path: PackedVector2Array = _agent.get_current_navigation_path()
	var idx: int = _agent.get_current_navigation_path_index()
	# Points go out as [x, y] int pairs: JSON (how an observer serializes this) has no Vector2, and
	# pixel precision is ample for diagnosis.
	return {
		"agent": true,
		"target": _point(_agent.target_position),
		"reachable": _agent.is_target_reachable(),
		"finished": _agent.is_navigation_finished(),
		"next": _point(path[idx]) if idx < path.size() else [],
		"path_points": path.size(),
		"path_index": idx,
	}


## Observation only: sample the character's progress each tick. While it is trying to move
## (`move_input` set) it compares displacement over `STALL_WINDOW`; a speed under `STALL_SPEED` grows
## `_stalled_for`. Nothing reacts to it — `debug_progress()` exposes it to the stuck overlay.
func sample(character, delta: float) -> void:
	var pos: Vector2 = character.global_position
	_trail_clock += delta
	if _trail_clock >= TRAIL_STEP:
		_trail_clock = 0.0
		_trail.append(pos)
		if _trail.size() > TRAIL_MAX:
			_trail.pop_front()
	if (character.move_input as Vector2).length() < 0.1:
		_stall_clock = 0.0
		_stall_pos = pos
		_stalled_for = 0.0
		_stall_speed = 0.0
		return
	_stall_clock += delta
	if _stall_clock >= STALL_WINDOW:
		_stall_speed = pos.distance_to(_stall_pos) / _stall_clock
		_stalled_for = _stalled_for + _stall_clock if _stall_speed < STALL_SPEED else 0.0
		_stall_pos = pos
		_stall_clock = 0.0


## Read-only: the movement-progress state sampled by `sample()`, for the stuck debug overlay.
func debug_progress() -> Dictionary:
	return { "speed": _stall_speed, "stalled_for": _stalled_for, "stall_window": STALL_WINDOW, "trail": _trail }


## A world point as a JSON-safe [x, y] int pair.
func _point(p: Vector2) -> Array:
	return [int(p.x), int(p.y)]


## Whether the NPC has reached `point` (nav path finished, or within arrive_dist straight-line).
func reached(character, point: Vector2) -> bool:
	if _agent != null:
		_agent.target_position = point
		return _agent.is_navigation_finished()
	return character.global_position.distance_to(point) < arrive_dist


## Steer `character.move_input` toward `dest` along a navigated path (around walls and furniture,
## through doorways) by heading for the next navmesh waypoint each frame. Furniture physically on the
## route is shoved aside by the character's own push physics as it walks into it. Falls back to plain
## straight-line steering when there is no agent.
func move_to(character, dest: Vector2) -> void:
	if _agent == null:
		var straight: Vector2 = dest - character.global_position
		character.move_input = Vector2.ZERO if straight.length() < arrive_dist else straight.normalized()
		return
	_agent.target_position = dest
	if _agent.is_navigation_finished():
		character.move_input = Vector2.ZERO
		return
	var next := _agent.get_next_path_position()
	var desired: Vector2 = next - character.global_position
	desired = desired.normalized() if desired.length() > 0.001 else Vector2.ZERO
	# Always steer toward the next navmesh waypoint — never the raw destination, which can lie across a
	# wall. `next` is wall-safe, and for an unreachable target it steps toward the closest reachable
	# point, so the character's own push physics bulldoze furniture on the route without tunnelling walls.
	character.move_input = desired
