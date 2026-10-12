class_name BloodField

## Where wet blood lies on the floor, for anything that walks or slides through it (BloodFootprints,
## BloodSmear). Splatters and pools register themselves; `wetness_at` answers 0..1 at a world point:
## a splatter is a thin film (`splat_wetness`) that dries to nothing over `splat_dry_time`, a pool is its
## flow fill, wet for `pool_wet_time`. Dried blood returns 0, so it leaves no prints. Ages run on physics
## frames so they follow game time. Entries drop out when their node leaves the tree.

## Side (px) of a spatial-hash cell for splatters.
const CELL := 64.0

## Splatters: id -> { node, rect (world bounds), born (physics frame) }.
static var _splats: Dictionary = {}
## Spatial hash of the splatters: Vector2i cell -> Array of ids.
static var _grid: Dictionary = {}
## Pools: id -> { node, born }.
static var _pools: Dictionary = {}


## Register a built BloodSplat (call after `shapes` is final).
static func add_splat(node: Node2D, shapes: Array[PackedVector2Array]) -> void:
	var bounds := Rect2()
	var first := true
	for poly in shapes:
		for p in poly:
			bounds = Rect2(p, Vector2.ZERO) if first else bounds.expand(p)
			first = false
	if first:
		return
	var id := node.get_instance_id()
	var rect := Rect2(bounds.position + node.global_position, bounds.size)
	_splats[id] = { "node": node, "rect": rect, "born": Engine.get_physics_frames() }
	for c in _cells_of(rect):
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(id)
	node.tree_exited.connect(_remove_splat.bind(id), CONNECT_ONE_SHOT)


## Register a BloodPool (its `flow` may still be filling).
static func add_pool(node: Node2D) -> void:
	var id := node.get_instance_id()
	_pools[id] = { "node": node, "born": Engine.get_physics_frames() }
	node.tree_exited.connect(_remove_pool.bind(id), CONNECT_ONE_SHOT)


## Wetness 0..1 of the blood at world `pos` (0 = bare floor or dried).
static func wetness_at(pos: Vector2) -> float:
	var best := 0.0
	var ids: Array = _grid.get(_cell_of(pos), [])
	for id in ids:
		var s: Dictionary = _splats[id]
		if not (s["rect"] as Rect2).has_point(pos):
			continue
		var obj = s["node"]
		if not is_instance_valid(obj):
			continue
		var node := obj as Node2D
		var wet := _wet(s["born"], BloodConfig.splat_dry_time) * BloodConfig.splat_wetness
		if wet <= best:
			continue
		var local := pos - node.global_position
		for poly in node.get("shapes"):
			if Geometry2D.is_point_in_polygon(local, poly):
				best = wet
				break
	for id in _pools.keys():
		var p: Dictionary = _pools[id]
		var obj = p["node"]
		if not is_instance_valid(obj):
			_pools.erase(id)
			continue
		var pool := obj as Node2D
		var flow = pool.get("flow")
		if flow == null:
			continue
		var cell := Vector2i(((pos - pool.global_position) / BloodConfig.flow_cell_size).floor())
		if flow.covers(cell):
			best = maxf(best, flow.fill(cell) * _wet(p["born"], BloodConfig.pool_wet_time))
	return best


## The first pool with blood within `radius` px of world `pos` (flooded or dragged out), or null.
static func pool_near(pos: Vector2, radius: float) -> Node2D:
	for id in _pools.keys():
		var obj = _pools[id]["node"]
		if not is_instance_valid(obj):
			continue
		var flow = obj.get("flow")
		if flow == null:
			continue
		var size := BloodConfig.flow_cell_size
		var centre := Vector2i(((pos - (obj as Node2D).global_position) / size).floor())
		var reach := ceili(radius / size)
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				if flow.covers(centre + Vector2i(dx, dy)):
					return obj
	return null


## Forget everything (a fresh world).
static func clear() -> void:
	_splats.clear()
	_grid.clear()
	_pools.clear()


## 1 when new, falling linearly to 0 over `seconds` (<= 0 = never dries).
static func _wet(born: int, seconds: float) -> float:
	if seconds <= 0.0:
		return 1.0
	var age := float(Engine.get_physics_frames() - born) / float(Engine.physics_ticks_per_second)
	return clampf(1.0 - age / seconds, 0.0, 1.0)


## The spatial-hash cell containing world `pos`.
static func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL).floor())


## Every spatial-hash cell `rect` overlaps.
static func _cells_of(rect: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := _cell_of(rect.position)
	var hi := _cell_of(rect.end)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			out.append(Vector2i(x, y))
	return out


## Drop splatter `id` from the registry and the hash.
static func _remove_splat(id: int) -> void:
	var s: Dictionary = _splats.get(id, {})
	if s.is_empty():
		return
	for c in _cells_of(s["rect"]):
		var ids: Array = _grid.get(c, [])
		ids.erase(id)
		if ids.is_empty():
			_grid.erase(c)
	_splats.erase(id)


## Drop pool `id` from the registry.
static func _remove_pool(id: int) -> void:
	_pools.erase(id)
