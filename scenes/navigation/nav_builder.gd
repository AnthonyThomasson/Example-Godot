class_name NavBuilder
extends RefCounted

## Navigation domain (leaf): turns a generated house into a walkable navigation map for the
## global NavigationServer2D. It bakes one NavigationRegion2D whose walkable area is the house
## footprint minus the walls: the room rects give the footprint, and the house's STATIC colliders
## (the walls) are parsed as obstructions, so doorways — gaps in the walls — stay open. It also bakes
## each solid furniture footprint in as a hole (_add_furniture_holes), so paths route AROUND furniture
## and reroute through another doorway when the near one is blocked (and a piece sealing the only
## route leaves the far side unreachable). Any NavigationAgent2D pathfinds against this map
## automatically. Every living character at rest is carved out too (character_holes), so a path routes
## around a body standing in the way instead of into it. That is a second map: the default one (what the AI
## plans and measures with: routes, flank and entry geometry, snapping a point to open floor) holds the
## furniture only, and a STEERING map of its own, with a region baked with the characters as well, is
## what a NavigationAgent2D walks (see `steering_map`). Carving the characters into the one shared map
## would change every route the AI weighs against a hostile (the target's own hole bends it). Imports
## nothing from other domains — it reads a plain `rooms` array and a Node, and recognises furniture
## (RigidBody2D) and characters (CharacterBody2D) by engine type alone.

## Extra clearance (px) baked around walls, on top of the agent radius, so paths don't hug walls.
const WALL_MARGIN := 4.0
## Padding (px) added around the room-union footprint: a walkable outdoor ring around the house, so
## characters outside (e.g. an invader) can path around it to the front entrance.
const BOUNDS_PAD := 160.0
## Padding (px) grown around a furniture footprint before it is baked in as a hole, so paths clear it.
const OBSTACLE_MARGIN := 6.0
## A character slower than this (px/s) is at rest, and only a character at rest is a hole (see `character_holes`).
## A walking pace is 150; a character pressed against a wall or another body reads about 0.
const REST_SPEED := 10.0
## An outline vertex closer than this (px) to the line between its neighbours is dropped before the bake (`_simplified`).
const SIMPLIFY_TOLERANCE := 1.5
## Name of the steering region, the planning region's child (see `steering_region`).
const STEERING_NAME := "NavSteering"

## The steering map made for each world navigation map (planning map RID -> steering map RID), and how many
## steering regions stand on it. The map is freed with its last region.
static var _steering_maps: Dictionary = {}
static var _steering_regions: Dictionary = {}
## Baked polygons smaller than this (px^2) are slivers and are dropped (see `_drop_slivers`).
const MIN_POLYGON_AREA := 0.5
## Segment count approximating a circular furniture footprint as an obstruction polygon.
const CIRCLE_SEGMENTS := 10
## Slack (px) around an outline's box when deciding whether two outlines could overlap.
const BOUNDS_EPSILON := 0.5


## Build and add a NavigationRegion2D under `parent`, covering `rooms` (each `{ key, type, rect }`
## with a world-space `rect`, from WorldGen.get_rooms) minus `house`'s wall colliders. `agent_radius`
## is the pathing clearance (character body radius). Returns the region, or null if there are no rooms.
## The furniture holes baked in here are not permanent: `rebake` re-carves them at the furniture's
## live positions on an interval (driven by `nav_updater.gd`) so paths follow scattered pieces. The
## returned region is the PLANNING one, on the world's own navigation map; its child (`steering_region`)
## is baked with the living characters at rest too and sits on the steering map.
static func build(house: Node2D, rooms: Array, parent: Node, agent_radius: float = 14.0) -> NavigationRegion2D:
	var nav_poly := _bake_polygon(house, rooms, agent_radius)
	if nav_poly == null:
		return null
	var region := NavigationRegion2D.new()
	region.name = "NavRegion"
	region.position = house.position
	region.navigation_polygon = nav_poly
	parent.add_child(region)
	if region.is_inside_tree():
		_add_steering_region(region, house, rooms, agent_radius, nav_poly)
	return region


## Re-bake `region`'s navigation polygon in place, re-carving the furniture holes at each piece's
## CURRENT position so paths route around furniture that has been shoved off its original spot. The
## region keeps its world offset; reassigning `navigation_polygon` re-registers the mesh with the
## NavigationServer2D. Call it only when furniture has actually moved — see `nav_updater.gd`.
static func rebake(region: NavigationRegion2D, house: Node2D, rooms: Array, agent_radius: float = 14.0) -> void:
	var nav_poly := _bake_polygon(house, rooms, agent_radius)
	if nav_poly != null:
		region.navigation_polygon = nav_poly


## Re-bake the steering region under `region` (the planning one `build` returned) with the furniture
## and the living characters at rest at their CURRENT positions. Call it when a character or a piece of
## furniture has moved — see `nav_updater.gd`. Does nothing when the region has no steering child.
static func rebake_steering(region: NavigationRegion2D, house: Node2D, rooms: Array, agent_radius: float = 14.0) -> void:
	var steering := steering_region(region)
	if steering == null:
		return
	var nav_poly := _bake_polygon(house, rooms, agent_radius, character_holes(house.get_parent()), true)
	if nav_poly != null:
		steering.navigation_polygon = nav_poly


## The steering region of `region` (the planning region `build` returned): the same house with the living
## characters carved out too, on its own navigation map. Null if it has none.
static func steering_region(region: NavigationRegion2D) -> NavigationRegion2D:
	return region.get_node_or_null(STEERING_NAME) as NavigationRegion2D


## The steering map that goes with the world's navigation map `planning_map`, the one a NavigationAgent2D
## should walk (`agent.set_navigation_map`): paths on it route around the characters at rest. Invalid
## (keep the planning map) when no steering region is on it, so an agent in a world that never baked one
## walks the plain map.
static func steering_map(planning_map: RID) -> RID:
	var map: RID = _steering_maps.get(planning_map, RID())
	if map.is_valid() and not NavigationServer2D.map_get_regions(map).is_empty():
		return map
	return RID()


## Add the steering region as a child of the planning `region`, on the steering map of the world's map
## (created on first use, freed with its last region). With no character yet standing, its polygon is
## the planning one.
static func _add_steering_region(region: NavigationRegion2D, house: Node2D, rooms: Array, agent_radius: float, planning_poly: NavigationPolygon) -> void:
	var map := _steering_map_for(region.get_world_2d().navigation_map)
	var characters := character_holes(house.get_parent())
	var nav_poly := planning_poly if characters.is_empty() else _bake_polygon(house, rooms, agent_radius, characters, true)
	var steering := NavigationRegion2D.new()
	steering.name = STEERING_NAME
	steering.navigation_polygon = nav_poly
	steering.set_navigation_map(map)
	region.add_child(steering)
	var planning_map := region.get_world_2d().navigation_map
	_steering_regions[planning_map] = int(_steering_regions.get(planning_map, 0)) + 1
	steering.tree_exited.connect(_on_steering_region_exited.bind(planning_map))


## A steering region left the tree: free the steering map of `planning_map` once its last one has gone.
static func _on_steering_region_exited(planning_map: RID) -> void:
	var left := int(_steering_regions.get(planning_map, 1)) - 1
	if left > 0:
		_steering_regions[planning_map] = left
		return
	_steering_regions.erase(planning_map)
	if _steering_maps.has(planning_map):
		NavigationServer2D.free_rid(_steering_maps[planning_map])
		_steering_maps.erase(planning_map)


## The steering map for the world map `planning_map`, created on first use (regions come and go with each
## world, the way they do on the world's own map). It gets the project's
## 2D navigation defaults, which are what the world's own map is made with (a freshly made map has the
## 3D ones, and the server refuses a navmesh baked with another cell size).
static func _steering_map_for(planning_map: RID) -> RID:
	if _steering_maps.has(planning_map):
		return _steering_maps[planning_map]
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, float(ProjectSettings.get_setting("navigation/2d/default_cell_size", 1.0)))
	NavigationServer2D.map_set_edge_connection_margin(map, float(ProjectSettings.get_setting("navigation/2d/default_edge_connection_margin", 1.0)))
	NavigationServer2D.map_set_link_connection_radius(map, float(ProjectSettings.get_setting("navigation/2d/default_link_connection_radius", 4.0)))
	NavigationServer2D.map_set_use_edge_connections(map, bool(ProjectSettings.get_setting("navigation/2d/use_edge_connections", true)))
	NavigationServer2D.map_set_active(map, true)
	_steering_maps[planning_map] = map
	return map


## `rebake` with the bake itself on the NavigationServer's worker thread, so a frame never pays for it: the source
## geometry is gathered on the main thread now (the walls are read from the scene tree, the furniture from its live
## positions), the bake runs in the background, and the polygon is assigned to `region` once it is done, when `done`
## is called. A region freed meanwhile is left alone. `done` is called even when there is nothing to bake. The planning
## region only: the steering one is re-baked by `rebake_steering`.
static func rebake_async(region: NavigationRegion2D, house: Node2D, rooms: Array, agent_radius: float = 14.0,
		done: Callable = Callable()) -> void:
	var job := _source_for(house, rooms, agent_radius)
	if job.is_empty():
		if done.is_valid():
			done.call()
		return
	var nav_poly: NavigationPolygon = job["poly"]
	NavigationServer2D.bake_from_source_geometry_data_async(nav_poly, job["source"], func() -> void:
		_drop_slivers(nav_poly)
		if is_instance_valid(region):
			region.navigation_polygon = nav_poly
		if done.is_valid():
			done.call())


## Bake a NavigationPolygon for `house` over `rooms` at `agent_radius`: the house bounds minus the
## static wall colliders (doorways stay open) minus each solid furniture footprint (carved as a hole)
## and minus each of `characters` (footprints from `character_holes`; none = the planning bake). Returns
## null if there are no rooms. In the house's LOCAL frame — the region offsets it into world space.
## Shared by the initial `build` and every `rebake`, so both carve furniture holes identically. `weld` snaps the
## result to the 1 px grid (`_weld_vertices`), which a bake with characters needs.
static func _bake_polygon(house: Node2D, rooms: Array, agent_radius: float, characters: Array = [], weld := false) -> NavigationPolygon:
	var job := _source_for(house, rooms, agent_radius, characters)
	if job.is_empty():
		return null
	var nav_poly: NavigationPolygon = job["poly"]
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, job["source"])
	if weld:
		_weld_vertices(nav_poly, house.position)
	_drop_slivers(nav_poly)
	return nav_poly


## Everything a bake needs, gathered on the main thread: the polygon to bake into (`poly`, with the agent radius set)
## and its source geometry (`source`: the walls, the walkable footprint, the furniture holes and each of `characters`).
## {} with no rooms. `_bake_polygon` bakes it at once; `rebake_async` hands it to the server's worker thread.
static func _source_for(house: Node2D, rooms: Array, agent_radius: float, characters: Array = []) -> Dictionary:
	var bounds := _bounds(rooms)
	if bounds.size == Vector2.ZERO:
		return {}
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
	source.set_obstruction_outlines(_on_grid(source.get_obstruction_outlines()))
	# Walkable footprint: the whole house bounds. The parsed walls carve it, leaving the doorways.
	source.add_traversable_outline(_rect_outline(local_bounds))
	# Furniture holes: each solid piece's footprint, so the baked mesh routes paths around it. Added
	# after the footprint (both are outlines on the same source) and before the bake carves them in.
	_add_furniture_holes(source, house, characters)
	return { "poly": nav_poly, "source": source }


## Merge the baked vertices that share a 1 px cell of the map (in world space: `origin` is the region's offset), the
## first one standing for them all, and drop the polygon corners that collapse. The baker's round joins and the cuts
## where a hole meets a wall leave vertices a fraction of a pixel apart, and the NavigationServer, which merges edges by
## 1 px cell, rejects an edge whose two ends share a cell ("navigation map synchronization error"). A character
## standing against a wall makes such cuts anywhere. Every other vertex keeps its exact place, so away from the cuts
## the mesh (and the paths along it) is the one the baker made.
static func _weld_vertices(nav_poly: NavigationPolygon, origin: Vector2) -> void:
	var verts := nav_poly.get_vertices()
	var welded := PackedVector2Array()
	var index_in_cell := {}  # cell -> the index in `welded` of the vertex that stands for it
	var stands_for := PackedInt32Array()
	stands_for.resize(verts.size())
	for i in verts.size():
		var cell := Vector2i((verts[i] + origin).floor())
		if not index_in_cell.has(cell):
			index_in_cell[cell] = welded.size()
			welded.append(verts[i])
		stands_for[i] = index_in_cell[cell]
	var rings: Array = []
	for i in nav_poly.get_polygon_count():
		var ring := PackedInt32Array()
		for index in nav_poly.get_polygon(i):
			var j := stands_for[index]
			if ring.is_empty() or ring[ring.size() - 1] != j:
				ring.append(j)
		if ring.size() > 1 and ring[0] == ring[ring.size() - 1]:
			ring.remove_at(ring.size() - 1)
		if ring.size() >= 3:
			rings.append(ring)
	nav_poly.clear_polygons()
	nav_poly.vertices = welded
	for ring in rings:
		nav_poly.add_polygon(ring)


## Remove the baked polygons with (almost) no area. Where furniture sits flush against a wall the
## bake can leave a zero-width sliver whose edges coincide with its neighbours'; it covers no
## walkable ground, and the NavigationServer rejects the map ("navigation map synchronization
## error") when it tries to merge those coincident edges.
static func _drop_slivers(nav_poly: NavigationPolygon) -> void:
	var verts := nav_poly.get_vertices()
	var kept: Array = []
	for i in nav_poly.get_polygon_count():
		var indices := nav_poly.get_polygon(i)
		var ring := PackedVector2Array()
		for index in indices:
			ring.append(verts[index])
		if absf(_signed_area(ring)) >= MIN_POLYGON_AREA:
			kept.append(indices)
	if kept.size() == nav_poly.get_polygon_count():
		return
	nav_poly.clear_polygons()
	for indices in kept:
		nav_poly.add_polygon(indices)


## Shoelace area of `ring` (positive when counter-clockwise).
static func _signed_area(ring: PackedVector2Array) -> float:
	var area := 0.0
	for i in ring.size():
		area += ring[i].cross(ring[(i + 1) % ring.size()])
	return area * 0.5


## The furniture footprint holes a bake of `house` carves, each a closed WORLD-space polygon — the
## same solid-furniture selection and grown footprints `_add_furniture_holes` feeds the baker, so a
## debug overlay drawing these shows exactly what was carved out. Re-measured from each collider's
## live `global_transform` on every call, so it reflects where the furniture stands NOW — `rebake`
## and `nav_updater.gd` rely on that to re-carve holes as pieces are shoved around in play. A damaged
## piece has its primitive collider rebuilt into several deformed ConvexPolygonShape2D pieces, so EACH
## of a body's collision shapes contributes to its footprint — otherwise a dented piece's hole would
## vanish. A body's footprint is the convex hull of those shapes: a dent's notches are far smaller than
## the agent, and baked in they leave sub-pixel navmesh edges the NavigationServer cannot merge
## ("navigation map synchronization error").
static func furniture_holes(house: Node2D) -> Array:
	var out: Array = []
	for node in _descendants(house):
		var body := node as RigidBody2D
		if body == null or body.freeze:
			continue
		var points := PackedVector2Array()
		for child in body.get_children():
			var col := child as CollisionShape2D
			if col == null or col.shape == null:
				continue
			points.append_array(_footprint_world(col))
		var hull := Geometry2D.convex_hull(points)
		if hull.size() > 1:
			hull.remove_at(hull.size() - 1)  # convex_hull closes the ring by repeating the first point
		if hull.size() >= 3:
			out.append(hull)
	return out


## The footprint holes of the living characters AT REST under `root` (the node the nav region lives under, which
## is also the house's parent), each a closed WORLD-space polygon, like `furniture_holes`. A character is a
## CharacterBody2D with a collision layer (death clears the layer: a corpse is walked over) that moves slower than
## `REST_SPEED`. Only the ones at rest: a hole sits where a body stands in the way until it moves, and one that
## walks leaves none, because every character is inside its own hole and a walker's would seal or split the passage
## around itself (the hall, a doorway) and lead its own path the long way round. A character that stands still is
## carved, and so is one pushing against a wall or another body without getting anywhere; when it sets off its hole
## goes at the next re-bake and, until then, whoever stands inside a hole walks the character-free map (see
## `Locomotion`). Re-measured on every call from the live collider transform, so `rebake` and `nav_updater.gd` follow
## the characters as they stop, set off, appear and die.
static func character_holes(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for node in root.get_children():
		var body := node as CharacterBody2D
		if body == null or body.collision_layer == 0 or body.get_real_velocity().length() >= REST_SPEED:
			continue
		var points := PackedVector2Array()
		for child in body.get_children():
			var col := child as CollisionShape2D
			if col == null or col.shape == null:
				continue
			points.append_array(_footprint_world(col))
		var hull := Geometry2D.convex_hull(points)
		if hull.size() > 1:
			hull.remove_at(hull.size() - 1)  # convex_hull closes the ring by repeating the first point
		if hull.size() >= 3:
			out.append(hull)
	return out


## Add each solid footprint to `source` as an obstruction outline, so the baked navmesh has a hole there
## and paths route AROUND it: furniture (rerouting through another doorway when the near one is blocked,
## or leaving it unreachable when a piece seals the only route) and the `characters` footprints. They are
## converted into the house-local frame the bake runs in (world minus the house position). Solid
## furniture is a non-frozen RigidBody2D (non-solid decor freezes itself) with a CollisionShape2D; walls
## are StaticBody2D and already parsed. They are fused together before they go in, so a character against
## a piece of furniture or against another character is one outline.
static func _add_furniture_holes(source: NavigationMeshSourceGeometryData2D, house: Node2D, characters: Array = []) -> void:
	var outlines: Array = []
	for outline in furniture_holes(house) + characters:
		var local := PackedVector2Array()
		for p in outline:
			local.append(p - house.position)
		outlines.append(local)
	for outline in _on_grid(_union_outlines(outlines)):
		source.add_obstruction_outline(_simplified(outline))


## `outlines` with every vertex snapped to the map's 1 px cell grid.
static func _on_grid(outlines: Array) -> Array:
	var out: Array = []
	for outline in outlines:
		var snapped_outline := PackedVector2Array()
		for p in outline:
			var q: Vector2 = p.round()
			if snapped_outline.is_empty() or snapped_outline[snapped_outline.size() - 1] != q:
				snapped_outline.append(q)
		if snapped_outline.size() > 1 and snapped_outline[0] == snapped_outline[snapped_outline.size() - 1]:
			snapped_outline.remove_at(snapped_outline.size() - 1)
		if snapped_outline.size() >= 3:
			out.append(snapped_outline)
	return out


## `outline` without the vertices that sit within `SIMPLIFY_TOLERANCE` of the line between their neighbours (the
## nearest to that line first, never below a triangle). A shot-up piece's hull has many such vertices (a shallow
## curve), and snapping them to the 1 px grid leaves a run of steps and notches a pixel deep. The baker's offset and
## its convex partition cannot always make a mesh of that, and then log "polygon convex partition failed" and bake
## NO navmesh at all (every path in the house is gone until the next re-bake). Dropping the vertices moves the edge
## by under the tolerance, far less than the margin around the piece.
static func _simplified(outline: PackedVector2Array) -> PackedVector2Array:
	var points := outline.duplicate()
	while points.size() > 3:
		var drop := -1
		var nearest := SIMPLIFY_TOLERANCE
		for i in points.size():
			var line_from: Vector2 = points[(i - 1 + points.size()) % points.size()]
			var line_to: Vector2 = points[(i + 1) % points.size()]
			var gap: float = points[i].distance_to(Geometry2D.get_closest_point_to_segment(points[i], line_from, line_to))
			if gap < nearest:
				nearest = gap
				drop = i
		if drop < 0:
			break
		points.remove_at(drop)
	return points


## `outlines` with every overlapping set fused into one polygon. A dented piece is several convex
## pieces and furniture can rest against furniture, so the raw footprints overlap. Baked as separate
## obstructions at fractional coordinates they can leave the navmesh with edges the NavigationServer
## can't merge ("navigation map synchronization error"), so `_add_furniture_holes` fuses them and
## snaps the result to the map's 1 px cell grid. An enclosed gap in a union is filled in.
static func _union_outlines(outlines: Array) -> Array:
	var out: Array = []
	var bounds: Array = []  # out[k]'s bounding box, kept in step with `out`
	for outline in outlines:
		var cur: PackedVector2Array = outline
		var cur_bounds := _outline_bounds(cur)
		var k := 0
		while k < out.size():
			# Separate outlines (boxes apart) cannot fuse: the union would hand back both, as below, so skip the merge.
			if not cur_bounds.intersects(bounds[k]):
				k += 1
				continue
			var fused := Geometry2D.merge_polygons(cur, out[k])
			var outer: Array = fused.filter(func(poly: PackedVector2Array) -> bool: return not Geometry2D.is_polygon_clockwise(poly))
			if outer.size() == 1:
				cur = outer[0]
				cur_bounds = _outline_bounds(cur)
				out.remove_at(k)
				bounds.remove_at(k)
				k = 0  # the grown polygon may now touch ones already passed
			else:
				k += 1
		out.append(cur)
		bounds.append(cur_bounds)
	return out


## The box around `outline`, a hair larger than the polygon so outlines that merely touch still count as overlapping.
static func _outline_bounds(outline: PackedVector2Array) -> Rect2:
	var box := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		box = box.expand(p)
	return box.grow(BOUNDS_EPSILON)


## Every descendant node of `root`, depth-first (so furniture nested under room containers is found).
static func _descendants(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


## The collider's footprint as a closed polygon in WORLD space, grown by `margin`. Reads only
## the generic Shape2D — the intact primitives (RectangleShape2D / CircleShape2D) and the
## ConvexPolygonShape2D a damaged piece's collider is rebuilt into (its points inflated by the margin
## via Geometry2D.offset_polygon) — mapped through the collider's global transform so an offset or
## rotated collider still lines up. Empty for an unsupported shape.
static func _footprint_world(col: CollisionShape2D, margin: float = OBSTACLE_MARGIN) -> PackedVector2Array:
	var shape := col.shape
	var local := PackedVector2Array()
	if shape is RectangleShape2D:
		var h := (shape as RectangleShape2D).size * 0.5 + Vector2(margin, margin)
		local = PackedVector2Array([
			Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
		])
	elif shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius + margin
		for i in CIRCLE_SEGMENTS:
			var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
			local.append(Vector2(cos(a), sin(a)) * r)
	elif shape is ConvexPolygonShape2D:
		# A deformed piece: inflate its silhouette by the margin. offset_polygon returns the grown
		# ring(s); take the largest (a convex grow yields one), falling back to the raw points.
		var grown := Geometry2D.offset_polygon((shape as ConvexPolygonShape2D).points, margin)
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
