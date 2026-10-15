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
## The regions a map has been given but may not have taken in yet (map RID -> Array of `{ region: RID, probe: Vector2 }`).
## A map synchronizes on a worker thread, a frame or more after a region joins it; until the region answers a query,
## `ready` is false (see there). An entry leaves when its region answers, or when the region leaves the tree.
static var _awaiting: Dictionary = {}
## The planning region `build` put on each world map (planning map RID -> region), for `planning_region`.
static var _planning_regions: Dictionary = {}
## The avoid maps made for each world navigation map (planning map RID -> key -> entry), see `avoid_map`. An entry is
## `{ map: RID, region: NavigationRegion2D, version: int, baking: bool, asked_ms: int }`.
static var _avoid_maps: Dictionary = {}
## Name of an avoid region, and the meta on the planning region that keeps its bake's source geometry (see `_remember_source`).
const AVOID_NAME := "NavAvoid"
const SOURCE_META := "nav_source"
## An avoid map nobody has asked for in this many ms (wall clock) is freed by the next ask for another set (`avoid_map`).
static var avoid_idle_ms: int = 20000
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
	var job := _source_for(house, rooms, agent_radius)
	if job.is_empty():
		return null
	var nav_poly := _bake_job(job, house.position)
	var region := NavigationRegion2D.new()
	region.name = "NavRegion"
	region.position = house.position
	region.navigation_polygon = nav_poly
	_remember_source(region, job)
	parent.add_child(region)
	if region.is_inside_tree():
		var planning_map := region.get_navigation_map()
		_planning_regions[planning_map] = region
		region.tree_exited.connect(func() -> void: _planning_regions.erase(planning_map), CONNECT_ONE_SHOT)
		_add_steering_region(region, house, rooms, agent_radius, nav_poly)
		var probe: Vector2 = (rooms[0]["rect"] as Rect2).get_center()
		_await_region(region.get_world_2d().navigation_map, region, probe)
		var steering := steering_region(region)
		if steering != null:
			_await_region(steering.get_navigation_map(), steering, probe)
	return region


## Re-bake `region`'s navigation polygon in place, re-carving the furniture holes at each piece's
## CURRENT position so paths route around furniture that has been shoved off its original spot. The
## region keeps its world offset; reassigning `navigation_polygon` re-registers the mesh with the
## NavigationServer2D. Call it only when furniture has actually moved — see `nav_updater.gd`.
static func rebake(region: NavigationRegion2D, house: Node2D, rooms: Array, agent_radius: float = 14.0) -> void:
	var job := _source_for(house, rooms, agent_radius)
	if job.is_empty():
		return
	region.navigation_polygon = _bake_job(job, house.position)
	_remember_source(region, job)


## Re-bake the steering region under `region` (the planning one `build` returned) with the furniture
## and the living characters at rest at their CURRENT positions. Call it when a character or a piece of
## furniture has moved — see `nav_updater.gd`. Does nothing when the region has no steering child.
static func rebake_steering(region: NavigationRegion2D, house: Node2D, rooms: Array, agent_radius: float = 14.0) -> void:
	var steering := steering_region(region)
	if steering == null:
		return
	var nav_poly := _bake_polygon(house, rooms, agent_radius, character_holes(house.get_parent()))
	if nav_poly != null:
		steering.navigation_polygon = nav_poly


## The steering region of `region` (the planning region `build` returned): the same house with the living
## characters carved out too, on its own navigation map. Null if it has none.
static func steering_region(region: NavigationRegion2D) -> NavigationRegion2D:
	return region.get_node_or_null(STEERING_NAME) as NavigationRegion2D


## The steering map that goes with the world's navigation map `planning_map`, the one a NavigationAgent2D
## should walk (`agent.set_navigation_map`): paths on it route around the characters at rest. Invalid
## (keep the planning map) when no steering region is on it, so an agent in a world that never baked one
## walks the plain map. Named from the moment `build` has added the steering region, before the map has synchronized
## (Main drops the NPCs in within that same frame; whether the map answers queries yet is `ready`).
static func steering_map(planning_map: RID) -> RID:
	if int(_steering_regions.get(planning_map, 0)) > 0:
		return _steering_maps.get(planning_map, RID())
	return RID()


## Add the steering region as a child of the planning `region`, on the steering map of the world's map
## (created on first use, freed with its last region). With no character yet standing, its polygon is
## the planning one.
static func _add_steering_region(region: NavigationRegion2D, house: Node2D, rooms: Array, agent_radius: float, planning_poly: NavigationPolygon) -> void:
	var map := _steering_map_for(region.get_world_2d().navigation_map)
	var characters := character_holes(house.get_parent())
	var nav_poly := planning_poly if characters.is_empty() else _bake_polygon(house, rooms, agent_radius, characters)
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
	var map := _new_map()
	_steering_maps[planning_map] = map
	return map


## A new active map with the project's 2D navigation defaults (what the world's own map is made with: a freshly made map has the
## 3D ones, and the server refuses a navmesh baked with another cell size).
static func _new_map() -> RID:
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, float(ProjectSettings.get_setting("navigation/2d/default_cell_size", 1.0)))
	NavigationServer2D.map_set_edge_connection_margin(map, float(ProjectSettings.get_setting("navigation/2d/default_edge_connection_margin", 1.0)))
	NavigationServer2D.map_set_link_connection_radius(map, float(ProjectSettings.get_setting("navigation/2d/default_link_connection_radius", 4.0)))
	NavigationServer2D.map_set_use_edge_connections(map, bool(ProjectSettings.get_setting("navigation/2d/use_edge_connections", true)))
	NavigationServer2D.map_set_active(map, true)
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
	var origin := house.position
	_remember_source(region, job)
	# Held weakly: a lambda that captures a node freed before it runs logs an engine error (a world torn down mid-bake).
	var region_ref: WeakRef = weakref(region)
	NavigationServer2D.bake_from_source_geometry_data_async(nav_poly, job["source"], func() -> void:
		_weld_vertices(nav_poly, origin)
		_drop_slivers(nav_poly)
		var target := region_ref.get_ref() as NavigationRegion2D
		if target != null:
			target.navigation_polygon = nav_poly
		if done.is_valid():
			done.call())


## Bake a NavigationPolygon for `house` over `rooms` at `agent_radius`: the house bounds minus the
## static wall colliders (doorways stay open) minus each solid furniture footprint (carved as a hole)
## and minus each of `characters` (footprints from `character_holes`; none = the planning bake). Returns
## null if there are no rooms. In the house's LOCAL frame — the region offsets it into world space.
## Shared by the initial `build` and every `rebake`, so both carve furniture holes identically. The result is welded
## to the 1 px grid (`_weld_vertices`): every hole that meets a wall, a character's and a piece of furniture's, needs it.
static func _bake_polygon(house: Node2D, rooms: Array, agent_radius: float, characters: Array = []) -> NavigationPolygon:
	var job := _source_for(house, rooms, agent_radius, characters)
	if job.is_empty():
		return null
	return _bake_job(job, house.position)


## Bake a gathered job (`_source_for`) at once, welded and without slivers; `origin` is the region's offset.
static func _bake_job(job: Dictionary, origin: Vector2) -> NavigationPolygon:
	var nav_poly: NavigationPolygon = job["poly"]
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, job["source"])
	_weld_vertices(nav_poly, origin)
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

	var nav_poly := _new_polygon(agent_radius)

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


## An empty polygon to bake into, with the bake's agent radius (plus the wall margin).
static func _new_polygon(agent_radius: float) -> NavigationPolygon:
	var nav_poly := NavigationPolygon.new()
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_poly.agent_radius = agent_radius + WALL_MARGIN
	return nav_poly


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
		var hull := _body_hull(body)
		if not hull.is_empty():
			out.append(hull)
	return out


## The world-space footprint of `body`, the convex hull of its collision shapes as an open ring (the closing point
## dropped), or empty when fewer than three points come out of it.
static func _body_hull(body: Node2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for child in body.get_children():
		var col := child as CollisionShape2D
		if col == null or col.shape == null:
			continue
		points.append_array(_footprint_world(col))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1:
		hull.remove_at(hull.size() - 1)  # convex_hull closes the ring by repeating the first point
	return hull if hull.size() >= 3 else PackedVector2Array()


## The footprint holes of the living characters AT REST under `root` (the node the nav region lives under, which
## is also the house's parent), each a closed WORLD-space polygon, like `furniture_holes`. A character is a
## CharacterBody2D with a collision layer (death clears the layer: a corpse is walked over) that moves slower than
## `REST_SPEED`. Only the ones at rest: a hole sits where a body stands in the way until it moves, and one that
## walks leaves none, because every character is inside its own hole and a walker's would seal or split the passage
## around itself (the hall, a doorway) and lead its own path the long way round. A character that stands still is
## carved, and so is one pushing against a wall or another body without getting anywhere; when it sets off its hole
## goes at the next re-bake. Every body at rest is carved, seen or not: which of them a walk accounts for is up to the
## walker (the AI's `Locomotion` goes round by this map only for a body it knows of). Re-measured on every call from the
## live collider transform, so `rebake` and `nav_updater.gd` follow the characters as they stop, set off, appear and die.
static func character_holes(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for node in root.get_children():
		var body := node as CharacterBody2D
		if body == null or body.collision_layer == 0 or body.get_real_velocity().length() >= REST_SPEED:
			continue
		var hull := _body_hull(body)
		if not hull.is_empty():
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


# --- Avoid maps ------------------------------------------------------------------------------------

## The planning region `build` put on world map `planning_map`, or null when none stands there (or it has left the tree).
static func planning_region(planning_map: RID) -> NavigationRegion2D:
	var region := _planning_regions.get(planning_map) as NavigationRegion2D
	if region == null or not is_instance_valid(region) or not region.is_inside_tree():
		return null
	return region


## A map of its own that holds the planning bake (the furniture) and the extra `holes` too, each a closed WORLD-space polygon:
## where the AI plans a walk that keeps out of some stretch of floor (a doorway's view). Made for `region`, the planning region
## `build` returned, and named by `key` (the same holes, the same key): the first ask makes the map and bakes it on the
## NavigationServer's worker thread, so a frame never pays for it, and `ready` tells when it answers queries, as for any map;
## the map is kept for the key and re-baked (the old mesh answers meanwhile) when the planning bake has been redone since. One nobody
## has asked for in `avoid_idle_ms` (20 s) is freed by the next ask for another key on the same planning map, and every one is freed
## with its region (its world). Invalid when the region has no bake to start from.
static func avoid_map(region: NavigationRegion2D, key: String, holes: Array) -> RID:
	if region == null or not region.has_meta(SOURCE_META):
		return RID()
	var planning_map := region.get_navigation_map()
	var entries: Dictionary = _avoid_maps.get(planning_map, {})
	_avoid_maps[planning_map] = entries
	var now := Time.get_ticks_msec()
	for k in entries.keys():
		var old: Dictionary = entries[k]
		if k != key and now - int(old["asked_ms"]) > avoid_idle_ms and is_instance_valid(old["region"]):
			(old["region"] as Node).queue_free()  # Its tree exit frees the map.
	var stored: Dictionary = region.get_meta(SOURCE_META)
	if entries.has(key):
		var kept: Dictionary = entries[key]
		kept["asked_ms"] = now
		if not bool(kept["baking"]) and int(kept["version"]) != int(stored["version"]):
			_bake_avoid(region, kept, holes)
		return kept["map"]
	var map := _new_map()
	var avoid_region := NavigationRegion2D.new()
	avoid_region.name = AVOID_NAME
	avoid_region.set_navigation_map(map)
	var entry := { "map": map, "region": avoid_region, "version": -1, "baking": false, "asked_ms": now }
	entries[key] = entry
	region.add_child(avoid_region)
	_await_region(map, avoid_region, region.global_position)
	avoid_region.tree_exited.connect(_on_avoid_region_exited.bind(planning_map, key, map))
	_bake_avoid(region, entry, holes)
	return map


## An avoid region left the tree (freed for being idle, or with its world): free its map and forget it.
static func _on_avoid_region_exited(planning_map: RID, key: String, map: RID) -> void:
	var entries: Dictionary = _avoid_maps.get(planning_map, {})
	if entries.has(key) and entries[key]["map"] == map:
		entries.erase(key)
	if entries.is_empty():
		_avoid_maps.erase(planning_map)
	NavigationServer2D.free_rid(map)


## Bake `entry`'s avoid region on the worker thread: the planning source geometry kept by `_remember_source`, with `holes` (world
## space) added as obstructions, fused and snapped like the furniture's. The polygon is assigned when the bake lands.
static func _bake_avoid(region: NavigationRegion2D, entry: Dictionary, holes: Array) -> void:
	var stored: Dictionary = region.get_meta(SOURCE_META)
	var origin := region.global_position
	var source := NavigationMeshSourceGeometryData2D.new()
	source.set_traversable_outlines(stored["traversable"])
	source.set_obstruction_outlines(stored["obstructions"])
	var outlines: Array = []
	for hole in holes:
		var local := PackedVector2Array()
		for p in (hole as PackedVector2Array):
			local.append(p - origin)
		outlines.append(local)
	for outline in _on_grid(_union_outlines(outlines)):
		source.add_obstruction_outline(_simplified(outline))
	var nav_poly := _new_polygon(float(stored["agent_radius"]))
	var region_id: int = (entry["region"] as Node).get_instance_id()  # Not the node: a region freed while its bake runs must not be captured.
	entry["baking"] = true
	entry["version"] = int(stored["version"])
	NavigationServer2D.bake_from_source_geometry_data_async(nav_poly, source, func() -> void:
		_weld_vertices(nav_poly, origin)
		_drop_slivers(nav_poly)
		entry["baking"] = false
		var avoid_region := instance_from_id(region_id) as NavigationRegion2D
		if avoid_region != null:
			avoid_region.navigation_polygon = nav_poly)


## Keep what the planning bake was made from (its walkable outline, its obstructions and the agent radius) on `region`, with a
## version that counts the bakes, so an avoid map can be baked from it with more holes and knows when the furniture has moved.
static func _remember_source(region: NavigationRegion2D, job: Dictionary) -> void:
	var source: NavigationMeshSourceGeometryData2D = job["source"]
	var poly: NavigationPolygon = job["poly"]
	var version := 0
	if region.has_meta(SOURCE_META):
		version = int((region.get_meta(SOURCE_META) as Dictionary)["version"]) + 1
	region.set_meta(SOURCE_META, {
		"traversable": source.get_traversable_outlines(),
		"obstructions": source.get_obstruction_outlines(),
		"agent_radius": poly.agent_radius - WALL_MARGIN,
		"version": version,
	})


# --- Map queries ---------------------------------------------------------------------------------
# What the AI asks of a baked map (interface 9) when it weighs a point or a route: one home for the
# "is the map baked yet" guard, so every caller treats the first frames before the bake the same way.

## Whether `map` is a baked map: valid, synchronized at least once, and has taken in every region `build` put on it.
## The last part matters at the start of a match: the world's map is already live with the previous navmesh (the menu's,
## the last match's), and it takes the new house in only a frame or so later. Until then a query still answers from the
## old mesh (a point snapped onto it lies nowhere near the house), so the callers treat the map as unbaked, the way they
## do before the first bake, and read the plain point and a straight route instead.
static func ready(map: RID) -> bool:
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return false
	var waiting: Array = _awaiting.get(map, [])
	for entry in waiting.duplicate():
		# Asked only after the map's first sync: before it the query is an engine error.
		if NavigationServer2D.map_get_closest_point_owner(map, entry["probe"]) == entry["region"]:
			waiting.erase(entry)
	if waiting.is_empty():
		_awaiting.erase(map)
		return true
	return false


## Note that `region`, just added to `map`, is not in the map's queries until one at `probe` (a world point on the region)
## is answered by it. Forgotten when the region leaves the tree.
static func _await_region(map: RID, region: NavigationRegion2D, probe: Vector2) -> void:
	var entry := { "region": region.get_rid(), "probe": probe }
	var waiting: Array = _awaiting.get(map, [])
	waiting.append(entry)
	_awaiting[map] = waiting
	region.tree_exited.connect(_forget_region.bind(map, entry), CONNECT_ONE_SHOT)


## Drop `entry` from `map`'s awaited regions (its region left the tree).
static func _forget_region(map: RID, entry: Dictionary) -> void:
	var waiting: Array = _awaiting.get(map, [])
	waiting.erase(entry)
	if waiting.is_empty():
		_awaiting.erase(map)


## `p` snapped onto the navmesh (a room's geometric centre is often inside furniture); unchanged before the map is baked.
static func snap(map: RID, p: Vector2) -> Vector2:
	if not ready(map):
		return p
	return NavigationServer2D.map_get_closest_point(map, p)


## The navigated route `from` → `to` as its waypoints; a straight segment before the map is baked or when no path exists.
static func route(map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	if not ready(map):
		return PackedVector2Array([from, to])
	var path := NavigationServer2D.map_get_path(map, from, to, true)
	return path if path.size() >= 2 else PackedVector2Array([from, to])


## The length (px) of a path.
static func path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total
