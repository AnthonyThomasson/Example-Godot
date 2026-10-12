extends Node

## AI BEHAVIOUR sub-domain — LOCOMOTION. Owns the NavigationAgent2D and turns a target point into
## steering on the character: `move_to()` writes `character.move_input` to follow a navigated path
## around walls and furniture and through doorways. The navmesh (baked by the Navigation domain)
## carves out furniture and rings the house with a walkable outdoor strip, so paths route around a
## piece and reroute through another doorway when one is blocked.
##
## The agent walks the navigation domain's steering map, which has the characters at rest carved out too, only for a
## walk that goes round a body standing in the way (see `_choose_map`); any other walk, including one that map cannot
## finish (a body seals the doorway, or the NPC itself stands in a hole), is walked by the plain map and shoves through,
## as before.
##
## Steering always aims at the next navmesh waypoint, so the character's own push physics bulldoze
## furniture sitting on the route without ever tunnelling a wall. It is behaviour's movement tool
## only — it holds no decision or combat state. Falls back to straight-line steering when there is
## no nav agent. It also knows the house's rooms (set each tick by `Behavior`), so the behaviour modules can ask which
## room, if any, a point lies in.

## How close (px) counts as "arrived" when steering straight-line (no nav agent).
var arrive_dist: float = 10.0

## World-space room rects (`{ key, type, rect }`) of the house, set each tick by `Behavior` from the controller's inject.
var rooms: Array = []

## Stuck-sensing window (s): displacement is compared over this span while the NPC is trying to move.
const STALL_WINDOW := 0.75
## Speed (px/s) below which an NPC that is trying to move counts as not progressing.
const STALL_SPEED := 8.0
## Seconds between recorded trail points, and the most points kept (a short recent-position trail).
const TRAIL_STEP := 0.25
const TRAIL_MAX := 24
## How far (px) off the steering mesh a point may be, and still count as on it, before it is "in a hole". The maps are
## baked on a 1 px grid, so a point on open floor is within a pixel or two of the closest mesh point.
const IN_HOLE_DISTANCE := 2.0
## How far (px) the steering map's route may end short of the point it was asked for before a body is taken to seal the
## way (see `_choose_map`).
const BLOCKED_DISTANCE := 24.0
## A body at rest is worth a walk around it, not a trek: a steering route longer than the plain one by more than this
## factor plus `DETOUR_SLACK` px (say, out of the house and in by another door because a body sits in the one that
## leads on) is not taken; the NPC goes the plain way and shoves through instead.
const DETOUR_RATIO := 1.5
const DETOUR_SLACK := 100.0
## How much (px) longer than the plain walk the steering route must be to count as going round a body.
const MIN_DETOUR := 1.0

var _agent: NavigationAgent2D     ## Pathfinding agent, or null (falls back to straight-line).
var _plan_map: RID                ## The world's navigation map: furniture only, what points are snapped and tested on.
var _steering_map: RID            ## The map with the living characters carved out too, or invalid when the world has none.
var _around_bodies := false       ## The last walk is on the steering map: it goes round a body at rest.
var _stall_pos := Vector2.ZERO    ## Position at the start of the current stall-sensing window.
var _stall_clock := 0.0           ## Seconds into the current window.
var _stall_speed := 0.0           ## Speed (px/s) measured over the last full window.
var _stalled_for := 0.0           ## Seconds the NPC has been trying to move without progressing.
var _trail_clock := 0.0           ## Seconds since the last trail point.
var _trail: Array = []            ## Recent world positions, oldest first.


## The key of the room containing world point `p`, or "" when `p` is in no room.
func room_key_at(p: Vector2) -> String:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return str(room["key"])
	return ""


## Whether a world point lies within any of the house's rooms (the "inside the house" test).
func inside_house(p: Vector2) -> bool:
	return room_key_at(p) != ""


## Resolve + wire the navigation agent. `agent` may be null (then everything falls back to straight
## line steering). The agent starts on the world's own map (`_plan_map`: furniture only, which points are snapped to
## and tested on); `_choose_map` moves it to the steering map for a walk that goes round a body at rest.
func setup(agent: NavigationAgent2D) -> void:
	_agent = agent
	if agent == null:
		return
	# The agent has not picked its map yet (its own _ready comes after the controller's), so read it off the world
	# its character stands in.
	var body := agent.get_parent() as Node2D
	if body != null and body.is_inside_tree():
		_plan_map = body.get_world_2d().navigation_map
	_steering_map = NavBuilder.steering_map(_plan_map)


## Snap a world point onto the navigation mesh so it is actually reachable — a room's geometric
## centre is often inside furniture (off the navmesh), which would make the nav agent treat it as
## unreachable and wedge the NPC trying to shove toward it. Returns `p` unchanged with no nav agent.
func reachable(p: Vector2) -> Vector2:
	if _agent == null:
		return p
	var map: RID = _plan_map
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
	var map: RID = _plan_map
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
		"around_bodies": _around_bodies,
		"target": _point(_agent.target_position),
		"reachable": _agent.is_target_reachable(),
		"finished": _agent.is_navigation_finished(),
		"next": _point(path[idx]) if idx < path.size() else [],
		"path_points": path.size(),
		"path_index": idx,
	}


## The walk the nav agent is following: `{ path: PackedVector2Array, index: int }` (the waypoints and the one it is heading
## for), or {} with no agent or no path. Read after `move_to`, so it is the walk that was just steered.
func path_ahead() -> Dictionary:
	if _agent == null:
		return {}
	var path: PackedVector2Array = _agent.get_current_navigation_path()
	if path.size() < 2:
		return {}
	return { "path": path, "index": _agent.get_current_navigation_path_index() }


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


## The length (px) of a path.
func _length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## A world point as a JSON-safe [x, y] int pair.
func _point(p: Vector2) -> Array:
	return [int(p.x), int(p.y)]


## Whether the NPC has reached `point` (nav path finished, or within arrive_dist straight-line).
func reached(character, point: Vector2) -> bool:
	if _agent != null:
		_choose_map(character, point)
		_agent.target_position = point
		return _agent.is_navigation_finished()
	return character.global_position.distance_to(point) < arrive_dist


## Put the agent on the map the walk from `character` to `dest` should follow: the plain map (furniture only) unless a
## body at rest stands on that walk and the steering map, which has the characters at rest carved out, goes round it.
## So the steering map takes over only when it costs a detour, and everywhere else a walk is the one it always was. It
## does not take it over when
## - the NPC stands in a hole (its own while it is at rest, or a body it is jammed against): the steering map would
##   lead it the wrong way round, or nowhere if the hole seals a doorway, so it walks out on the plain map;
## - `dest` is in a hole (a body at rest, e.g. the one it is closing in on, or the stack slot behind an ally): the
##   steering route would stop at the hole's rim, short of it;
## - the steering route ends short of `dest`, or is a trek next to the plain one (`DETOUR_RATIO`): a body at rest seals
##   the way, and the NPC shoves through it rather than wait at the rim for a gap that is not coming.
## Nothing to choose in a world with no steering map, or before both maps have synchronized.
func _choose_map(character, dest: Vector2) -> void:
	if not _steering_map.is_valid() or not _plan_map.is_valid():
		return
	_around_bodies = false
	if NavigationServer2D.map_get_iteration_id(_steering_map) > 0 and NavigationServer2D.map_get_iteration_id(_plan_map) > 0:
		var from: Vector2 = character.global_position
		var plain_dest := NavigationServer2D.map_get_closest_point(_plan_map, dest)
		var plain_from := NavigationServer2D.map_get_closest_point(_plan_map, from)
		var in_hole := NavigationServer2D.map_get_closest_point(_steering_map, from).distance_to(plain_from) > IN_HOLE_DISTANCE \
				or NavigationServer2D.map_get_closest_point(_steering_map, dest).distance_to(plain_dest) > IN_HOLE_DISTANCE
		if not in_hole:
			var path := NavigationServer2D.map_get_path(_steering_map, from, dest, true)
			var plain_length := _length(NavigationServer2D.map_get_path(_plan_map, from, dest, true))
			var length := _length(path)
			_around_bodies = not path.is_empty() and path[path.size() - 1].distance_to(plain_dest) <= BLOCKED_DISTANCE \
					and length > plain_length + MIN_DETOUR and length <= plain_length * DETOUR_RATIO + DETOUR_SLACK
	var want := _steering_map if _around_bodies else _plan_map
	if _agent.get_navigation_map() != want:
		_agent.set_navigation_map(want)


## Steer `character.move_input` toward `dest` along a navigated path (around walls and furniture,
## through doorways) by heading for the next navmesh waypoint each frame. Furniture physically on the
## route is shoved aside by the character's own push physics as it walks into it. Falls back to plain
## straight-line steering when there is no agent.
func move_to(character, dest: Vector2) -> void:
	if _agent == null:
		var straight: Vector2 = dest - character.global_position
		character.move_input = Vector2.ZERO if straight.length() < arrive_dist else straight.normalized()
		return
	_choose_map(character, dest)
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
