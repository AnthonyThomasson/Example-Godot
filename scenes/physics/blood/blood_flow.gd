class_name BloodFlow
extends RefCounted

## Physics System, blood: a liquid flood-fill for a dead body's bleed-out: blood claims grid cells outward from where it
## leaves the body, cheapest-first, so the puddle is one continuous shape. Noise makes some
## directions cheap and others dear (fingers and bays instead of a disc), and cells overlapping a
## wall or furniture collider are never filled, so the blood wraps around them and creeps into
## gaps. Positions are local to the owning pool. The draw layer reads `cells` and `fill()`.

## The eight grid neighbours a cell flows into.
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## Claimed cells: Vector2i -> the flow cost at which blood arrives there. They are all claimed up
## front (a few per frame); a front then sweeps through cost-space over time, so each cell's fill
## level rises continuously and the pool's edge moves smoothly instead of cells popping in.
var cells: Dictionary = {}
## Blood dragged out of the pool (BloodSmear): cell -> fill 0..1, for cells the flood-fill never claimed.
## Drawn with the pool, so a smear grows out of the pool's own outline.
var trail: Dictionary = {}
## Where the front has reached, in cost units.
var front := 0.0
## How far the sweep has run, 0..1 of the duration.
var _progress := 0.0
## The highest flow cost claimed so far; the front sweeps up to it.
var _last_cost := 0.0

## Side (px) of a grid cell.
var _size: float
## Unit direction the flow leans toward.
var _aim: Vector2
## Collider RIDs the blocked-cell queries ignore (the body the blood leaves).
var _exclude: Array
## Roughens the per-cell flow cost into lobes.
var _noise := FastNoiseLite.new()
## The square each blocked-cell query tests.
var _probe := RectangleShape2D.new()
## Cells known to be blocked (true) or open (false), so each is queried once.
var _blocked: Dictionary = {}
## Floor-texture flow multiplier per cell, looked up once each.
var _resist: Dictionary = {}
## Soak progress 0..1 of each claimed cell lying on a porous surface (carpet, a rug): 0 = fresh, 1 = sunk in.
var _soak: Dictionary = {}
## Frontier: Vector2i -> accumulated cost to reach it.
var _frontier: Dictionary = {}
## The cell blood leaves the body at.
var _origin: Vector2i


func _init(aim: Vector2, exclude: Array) -> void:
	_size = BloodConfig.flow_cell_size
	_aim = aim
	_exclude = exclude
	_noise.seed = randi()
	_noise.frequency = BloodConfig.flow_noise_frequency
	_probe.size = Vector2.ONE * _size * 0.8
	_origin = Vector2i.ZERO
	_frontier[_origin] = 0.0
	_blocked[_origin] = false


## True once nothing is left to flow into.
func done() -> bool:
	return _frontier.is_empty()


## Sweep the front outward: `delta` seconds of a `duration`-second spread, easing out like a
## liquid slowing as it thins. Call once all cells are claimed.
func advance(delta: float, duration: float) -> void:
	# Blood creeps slower over porous surface, in proportion to how much of the pool lies on it.
	var slow := 1.0
	if not _soak.is_empty() and not cells.is_empty():
		slow = lerpf(1.0, maxf(BloodConfig.porous_spread_slowdown, 1.0), float(_soak.size()) / cells.size())
	_progress = minf(_progress + delta / (maxf(duration, 0.001) * slow), 1.0)
	var eased := 1.0 - (1.0 - _progress) * (1.0 - _progress)
	front = (_last_cost + BloodConfig.flow_soft_edge) * eased


## True once the front has covered every cell.
func settled() -> bool:
	return _progress >= 1.0


## Fill level (0..1) of a cell: the flood-fill at the current front, or the dragged-out trail if more. Soaking
## into a porous surface changes how the blood looks and how wet it is, never how much of the floor it covers.
func fill(c: Vector2i) -> float:
	return maxf(_flood(c), trail.get(c, 0.0))


## How wet (0..1) the blood on cell `c` still is: its fill, less what has soaked into the surface.
func wetness(c: Vector2i) -> float:
	return fill(c) * (1.0 - _soak[c]) if _soak.has(c) else fill(c)


## How far (0..1) the blood on cell `c` has sunk in; 0 off a porous surface.
func soak_level(c: Vector2i) -> float:
	return _soak.get(c, 0.0)


## Whether any claimed cell lies on a porous surface.
func has_porous() -> bool:
	return not _soak.is_empty()


## Whether any blood on a porous surface has yet to finish sinking in.
func soaking() -> bool:
	for c in _soak:
		if _soak[c] < 1.0:
			return true
	return false


## Soak `delta` seconds further into every porous cell the flood has mostly reached.
func tick(delta: float) -> void:
	for c in _soak:
		if _soak[c] < 1.0 and _flood(c) >= 0.5:
			_soak[c] = minf(_soak[c] + delta / maxf(BloodConfig.soak_time, 0.001), 1.0)


## The flood-fill level (0..1) of cell `c` at the current front, before anything soaks in.
func _flood(c: Vector2i) -> float:
	if not cells.has(c):
		return 0.0
	var t := clampf((front - cells[c]) / maxf(BloodConfig.flow_soft_edge, 0.001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Whether blood of any kind (flooded or dragged out) lies on cell `c`.
func covers(c: Vector2i) -> bool:
	return cells.has(c) or trail.has(c)


## Drag blood out onto cell `c` and the ring around it: raise them to `level` (the centre) and a little
## less (the ring), never lowering one. The level tapers linearly to nothing at
## `BloodConfig.pool_trail_length` px from the flooded cells, and stops growing at `BloodConfig.pool_trail_max`
## trail cells.
func add_trail(c: Vector2i, level: float) -> void:
	level *= 1.0 - clampf(_rim_distance(c) / maxf(BloodConfig.pool_trail_length, 0.001), 0.0, 1.0)
	if level <= 0.0:
		return
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if not trail.has(n) and trail.size() >= BloodConfig.pool_trail_max:
				continue
			var l := level if dx == 0 and dy == 0 else level * 0.75
			trail[n] = maxf(trail.get(n, 0.0), clampf(l, 0.0, 1.0))


## Distance (px) from cell `c` to the nearest flooded cell (0 inside the pool), searched no farther than
## `BloodConfig.pool_trail_length`; beyond that it returns the limit.
func _rim_distance(c: Vector2i) -> float:
	if cells.has(c):
		return 0.0
	var reach := ceili(BloodConfig.pool_trail_length / _size)
	var best := float(reach)
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			if cells.has(c + Vector2i(dx, dy)):
				best = minf(best, Vector2(dx, dy).length())
	return best * _size


## Local centre of a cell.
func _cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * _size


## How much of the bleed-out cell budget the claimed cells have used: a cell on porous surface costs
## `BloodConfig.porous_cell_weight`, so a pool on carpet covers less ground.
func budget_used() -> float:
	return cells.size() + _soak.size() * (maxf(BloodConfig.porous_cell_weight, 1.0) - 1.0)


## Claim up to `count` more cells, cheapest first, stopping once `budget` is used (see `budget_used`).
## `origin_global` is the pool's world position.
func step(count: int, space: PhysicsDirectSpaceState2D, origin_global: Vector2, budget := INF) -> void:
	for i in count:
		if _frontier.is_empty() or budget_used() >= budget:
			return
		var c := _pop_cheapest()
		var cost: float = _frontier[c]
		_frontier.erase(c)
		cells[c] = cost
		if BloodSurface.is_porous(origin_global + _cell_center(c)):
			_soak[c] = 0.0
		_last_cost = maxf(_last_cost, cost)
		for d in NEIGHBORS:
			var n: Vector2i = c + d
			if cells.has(n) or _is_blocked(n, space, origin_global):
				continue
			var dir := Vector2(d).normalized()
			var rough := 1.0 + _noise.get_noise_2d(n.x, n.y) * BloodConfig.flow_noise_strength
			var lean := 1.0 - BloodConfig.flow_aim_bias * dir.dot(_aim)
			var next := cost + Vector2(d).length() * maxf(rough, 0.15) * maxf(lean, 0.2) \
					* _surface_resist(n, origin_global)
			if not _frontier.has(n) or next < _frontier[n]:
				_frontier[n] = next


## The frontier cell cheapest to reach (the caller removes it).
func _pop_cheapest() -> Vector2i:
	var best := Vector2i.ZERO
	var best_cost := INF
	for c in _frontier:
		if _frontier[c] < best_cost:
			best_cost = _frontier[c]
			best = c
	return best


## Floor-texture flow multiplier for cell `c` (cached per cell; see BloodSurface).
func _surface_resist(c: Vector2i, origin_global: Vector2) -> float:
	if not _resist.has(c):
		_resist[c] = BloodSurface.resistance(origin_global + _cell_center(c))
	return _resist[c]


## Whether a wall or furniture collider overlaps cell `c` (cached per cell).
func _is_blocked(c: Vector2i, space: PhysicsDirectSpaceState2D, origin_global: Vector2) -> bool:
	if _blocked.has(c):
		return _blocked[c]
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _probe
	params.collision_mask = PhysicsConfig.wall_mask
	params.exclude = _exclude
	params.transform = Transform2D(0.0, origin_global + _cell_center(c))
	params.collide_with_bodies = true
	var blocked := not space.intersect_shape(params, 1).is_empty()
	_blocked[c] = blocked
	return blocked
