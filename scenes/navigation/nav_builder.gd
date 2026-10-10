class_name NavBuilder
extends RefCounted

## Navigation domain (leaf): turns a generated house into a walkable navigation map for the
## global NavigationServer2D. It bakes one NavigationRegion2D whose walkable area is the house
## footprint minus the walls: the room rects give the footprint, and the house's STATIC colliders
## (the walls) are parsed as obstructions, so doorways — gaps in the walls — stay open. It also bakes
## each solid furniture footprint in as a hole (_add_furniture_holes), so paths route AROUND furniture
## and reroute through another doorway when the near one is blocked (and a piece sealing the only
## route leaves the far side unreachable). Any NavigationAgent2D pathfinds against this map
## automatically. Imports nothing from other domains — it reads a plain `rooms` array and a Node, and
## recognises furniture by engine type (RigidBody2D) alone.

## Extra clearance (px) baked around walls, on top of the agent radius, so paths don't hug walls.
const WALL_MARGIN := 4.0
## Padding (px) added around the room-union footprint: a walkable outdoor ring around the house, so
## characters outside (e.g. an invader) can path around it to the front entrance.
const BOUNDS_PAD := 160.0
## Padding (px) grown around a furniture footprint before it is baked in as a hole, so paths clear it.
const OBSTACLE_MARGIN := 6.0
## Segment count approximating a circular furniture footprint as an obstruction polygon.
const CIRCLE_SEGMENTS := 10


## Build and add a NavigationRegion2D under `parent`, covering `rooms` (each `{ key, type, rect }`
## with a world-space `rect`, from WorldGen.get_rooms) minus `house`'s wall colliders. `agent_radius`
## is the pathing clearance (character body radius). Returns the region, or null if there are no rooms.
## The furniture holes baked in here are not permanent: `rebake` re-carves them at the furniture's
## live positions on an interval (driven by `nav_updater.gd`) so paths follow scattered pieces.
static func build(house: Node2D, rooms: Array, parent: Node, agent_radius: float = 14.0) -> NavigationRegion2D:
	var nav_poly := _bake_polygon(house, rooms, agent_radius)
	if nav_poly == null:
		return null
	var region := NavigationRegion2D.new()
	region.name = "NavRegion"
	region.position = house.position
	region.navigation_polygon = nav_poly
	parent.add_child(region)
	return region


## Re-bake `region`'s navigation polygon in place, re-carving the furniture holes at each piece's
## CURRENT position so paths route around furniture that has been shoved off its original spot. The
## region keeps its world offset; reassigning `navigation_polygon` re-registers the mesh with the
## NavigationServer2D. Call it only when furniture has actually moved — see `nav_updater.gd`.
static func rebake(region: NavigationRegion2D, house: Node2D, rooms: Array, agent_radius: float = 14.0) -> void:
	var nav_poly := _bake_polygon(house, rooms, agent_radius)
	if nav_poly != null:
		region.navigation_polygon = nav_poly


## Bake a NavigationPolygon for `house` over `rooms` at `agent_radius`: the house bounds minus the
## static wall colliders (doorways stay open) minus each solid furniture footprint (carved as a hole).
## Returns null if there are no rooms. In the house's LOCAL frame — the region offsets it into world
## space. Shared by the initial `build` and every `rebake`, so both carve furniture holes identically.
static func _bake_polygon(house: Node2D, rooms: Array, agent_radius: float) -> NavigationPolygon:
	var bounds := _bounds(rooms)
	if bounds.size == Vector2.ZERO:
		return null
	bounds = bounds.grow(BOUNDS_PAD)
	# parse_source_geometry_data returns the wall colliders in `house`'s LOCAL frame, so the
	# footprint and the baked mesh live in that frame too; the region is then offset by the house's
	# position to place the whole map back in world space. Mixing world and local here is what
	# silently misaligns the walls and seals the doorways.
	var local_bounds := Rect2(bounds.position - house.position, bounds.size)

	var nav_poly := NavigationPolygon.new()
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_poly.agent_radius = agent_radius + WALL_MARGIN

	var source := NavigationMeshSourceGeometryData2D.new()
	# Obstructions: the house's static colliders (walls). RigidBody2D furniture is not static, so it
	# is not parsed — only the walls become holes. Parsing resets the source data, so it must run
	# before the traversable footprint is added.
	NavigationServer2D.parse_source_geometry_data(nav_poly, source, house)
	# Walkable footprint: the whole house bounds. The parsed walls carve it, leaving the doorways.
	source.add_traversable_outline(_rect_outline(local_bounds))
	# Furniture holes: each solid piece's footprint, so the baked mesh routes paths around it. Added
	# after the footprint (both are outlines on the same source) and before the bake carves them in.
	_add_furniture_holes(source, house)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source)
	return nav_poly


## The furniture footprint holes a bake of `house` carves, each a closed WORLD-space polygon — the
## same solid-furniture selection and grown footprints `_add_furniture_holes` feeds the baker, so a
## debug overlay drawing these shows exactly what was carved out. Re-measured from each collider's
## live `global_transform` on every call, so it reflects where the furniture stands NOW — `rebake`
## and `nav_updater.gd` rely on that to re-carve holes as pieces are shoved around in play. A damaged
## piece has its primitive collider rebuilt into several deformed ConvexPolygonShape2D pieces, so EACH
## of a body's collision shapes contributes a footprint — otherwise a dented piece's hole would vanish.
static func furniture_holes(house: Node2D) -> Array:
	var out: Array = []
	for node in _descendants(house):
		var body := node as RigidBody2D
		if body == null or body.freeze:
			continue
		for child in body.get_children():
			var col := child as CollisionShape2D
			if col == null or col.shape == null:
				continue
			var outline := _footprint_world(col)
			if outline.size() >= 3:
				out.append(outline)
	return out


## Add each solid furniture footprint to `source` as an obstruction outline, so the baked navmesh has
## a hole there and paths route AROUND the piece (rerouting through another doorway when the near one
## is blocked, or leaving it unreachable when a piece seals the only route). Footprints are converted
## into the house-local frame the bake runs in (world minus the house position). Solid furniture is a
## non-frozen RigidBody2D (non-solid decor freezes itself) with a CollisionShape2D; walls are
## StaticBody2D and already parsed.
static func _add_furniture_holes(source: NavigationMeshSourceGeometryData2D, house: Node2D) -> void:
	for outline in furniture_holes(house):
		var local := PackedVector2Array()
		for p in outline:
			local.append(p - house.position)
		source.add_obstruction_outline(local)


## Every descendant node of `root`, depth-first (so furniture nested under room containers is found).
static func _descendants(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


## The furniture footprint as a closed polygon in WORLD space, grown by OBSTACLE_MARGIN. Reads only
## the generic Shape2D — the intact primitives (RectangleShape2D / CircleShape2D) and the
## ConvexPolygonShape2D a damaged piece's collider is rebuilt into (its points inflated by the margin
## via Geometry2D.offset_polygon) — mapped through the collider's global transform so an offset or
## rotated collider still lines up. Empty for an unsupported shape.
static func _footprint_world(col: CollisionShape2D) -> PackedVector2Array:
	var shape := col.shape
	var local := PackedVector2Array()
	if shape is RectangleShape2D:
		var h := (shape as RectangleShape2D).size * 0.5 + Vector2(OBSTACLE_MARGIN, OBSTACLE_MARGIN)
		local = PackedVector2Array([
			Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
		])
	elif shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius + OBSTACLE_MARGIN
		for i in CIRCLE_SEGMENTS:
			var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
			local.append(Vector2(cos(a), sin(a)) * r)
	elif shape is ConvexPolygonShape2D:
		# A deformed piece: inflate its silhouette by the margin. offset_polygon returns the grown
		# ring(s); take the largest (a convex grow yields one), falling back to the raw points.
		var grown := Geometry2D.offset_polygon((shape as ConvexPolygonShape2D).points, OBSTACLE_MARGIN)
		local = _largest_polygon(grown, (shape as ConvexPolygonShape2D).points)
	var xform := col.global_transform
	var out := PackedVector2Array()
	for p in local:
		out.append(xform * p)
	return out


## The polygon with the most points from `polys` (Geometry2D.offset_polygon's output), or `fallback`
## when it is empty.
static func _largest_polygon(polys: Array, fallback: PackedVector2Array) -> PackedVector2Array:
	var best := fallback
	for poly in polys:
		if (poly as PackedVector2Array).size() > best.size():
			best = poly
	return best


## The union of every room's world-space rect (zero-size Rect2 if `rooms` is empty).
static func _bounds(rooms: Array) -> Rect2:
	var bounds := Rect2()
	var first := true
	for room in rooms:
		var rect: Rect2 = room["rect"]
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	return bounds


## The four corners of `rect` as a closed outline, for the navigation baker.
static func _rect_outline(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	])
