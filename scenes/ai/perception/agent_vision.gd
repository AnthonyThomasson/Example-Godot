extends RefCounted

## AI domain: the SIGHT sense for a goal-driven NPC. Pure, stateless geometry — "can this agent see
## that point right now?" — governed by tunable parameters (field of view, range, a close-range
## 360° awareness bubble, and line of sight). It holds NO policy: it never decides, remembers or
## picks. The perception runs each visible thing through it and deposits what is seen into the
## agent's memory (agent_memory.gd), so the "remember" half lives there; this is only the "see" half.
##
## A point is visible when it is (a) within `view_distance`, AND (b) either within `awareness_radius`
## of the agent — a near bubble you sense regardless of which way you face — or inside the forward
## cone of half-angle `fov_degrees / 2` around the agent's facing, AND (c) reachable by a clear
## straight line on the physics query layer. For SIGHT that line is forgiving: a standing agent looks
## OVER low furniture (a collider whose `coverage` is at or below `see_over_coverage` — tables, beds,
## islands, counters), so only walls and tall furniture (cabinets, wardrobes, fridges) break the line.
## Set `enabled` to false to make everything visible (omniscient), restoring the pre-vision behaviour.
##
## This "look over low cover" rule is SIGHT-only: `blocked()` / `raycast()` below stay fully physical
## (every solid collider counts) because they serve line-of-fire and cover, where a bullet is still
## stopped by a table even though an agent can see across it.

## Physics layer walls + solid furniture live on (General's `PhysicsLayers.SOLID`, also used by
## CharacterInteraction). This module is the sub-domain's single owner of the solid-geometry ray
## query: the perception runs its line-of-fire and cover tests through `blocked()` / `raycast()`
## below rather than repeating it.
const QUERY_MASK := PhysicsLayers.SOLID

## Whether vision is gated at all; false = the agent sees everything (omniscient fallback).
var enabled: bool = true
## Maximum distance (px) at which anything can be seen.
var view_distance: float = 2520.0
## Full angular width (degrees) of the forward view cone, centred on the agent's facing.
var fov_degrees: float = 110.0
## Radius (px) of the 360° near-awareness bubble: things this close are sensed regardless of facing.
var awareness_radius: float = 48.0
## Coverage rating (0–100 height proxy) at or below which furniture is low enough to see OVER: sight
## passes through it. Above this it blocks the line like a wall (which rates 100). Sight-only; cover
## and line-of-fire ignore it.
var see_over_coverage: float = 60.0


## Whether `point` is visible to an agent at `from_pos` facing `facing`, given a physics space state
## and the rids to exclude from the sight raycast (typically the agent itself). See the class note
## for the full rule. `space` may be null (treated as an unobstructed line) for geometry-only tests.
func can_see(from_pos: Vector2, facing: Vector2, point: Vector2, space, exclude: Array) -> bool:
	if not enabled:
		return true
	var to := point - from_pos
	var dist := to.length()
	if dist > view_distance:
		return false
	if dist > awareness_radius:
		# Outside the near bubble: must fall within the forward cone.
		if facing == Vector2.ZERO:
			return false
		if absf(facing.angle_to(to)) > deg_to_rad(fov_degrees) * 0.5:
			return false
	return space == null or not _sight_blocked(space, from_pos, point, exclude)


## Whether `node` (a Node2D) is visible — convenience wrapper over can_see using its global position.
## The node itself is excluded from the sight ray (it is the endpoint, so its own collider must not
## count as something blocking the line to it); the line is clear when nothing ELSE is between.
func can_see_node(node: Node2D, from_pos: Vector2, facing: Vector2, space, exclude: Array) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var ex: Array = exclude.duplicate()
	if node.has_method("get_rid"):
		ex.append(node.get_rid())
	return can_see(from_pos, facing, node.global_position, space, ex)


## Whether the straight line `from`→`to` is broken for SIGHT. Unlike `blocked()` (physical: any solid
## collider stops it), this looks OVER low cover — it walks the line, skipping each collider whose
## coverage is at or below `see_over_coverage` and casting again past it, until it reaches `to` (clear)
## or hits something tall enough to block (a wall or tall furniture). A collider with no readable
## coverage is treated as a full blocker. The exclude list grows by one skipped collider each pass, so
## the walk always terminates (there are finitely many colliders on the line).
func _sight_blocked(space, from: Vector2, to: Vector2, exclude: Array) -> bool:
	var ex := exclude
	while true:
		var hit := raycast(space, from, to, ex)
		if hit.is_empty():
			return false  # reached the target: nothing tall in the way
		if _hit_coverage(hit.get("collider")) > see_over_coverage:
			return true  # too tall to see over
		# Low cover: look over it and keep going past it.
		if ex == exclude:
			ex = exclude.duplicate()  # don't mutate the caller's list
		ex.append(hit.get("rid"))
	return true  # unreachable; satisfies the parser


## The coverage (0–100 height proxy) of a ray-hit collider, read through the hittable contract. An
## unknown collider (no get_surface) is treated as fully blocking so sight never leaks past it.
func _hit_coverage(collider) -> float:
	if collider != null and collider.has_method("get_surface"):
		return float(collider.get_surface().get("coverage", 100.0))
	return 100.0


## Whether the straight segment `from`→`to` hits a wall or solid object on the query layer. A pure
## geometry test — it ignores `enabled`, so line-of-fire and cover stay physical even when sight is
## disabled (vision gates what the agent KNOWS; this gates what a straight line can reach).
func blocked(space, from: Vector2, to: Vector2, exclude: Array) -> bool:
	return not raycast(space, from, to, exclude).is_empty()


## The first solid hit along `from`→`to` on the query layer, or an empty dict when the line is clear.
## Callers that need the blocking collider itself (e.g. a cover test) use this instead of `blocked()`.
func raycast(space, from: Vector2, to: Vector2, exclude: Array) -> Dictionary:
	var p := PhysicsRayQueryParameters2D.create(from, to)
	p.collision_mask = QUERY_MASK
	p.exclude = exclude
	return space.intersect_ray(p)
