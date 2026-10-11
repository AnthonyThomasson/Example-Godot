class_name BloodFlow
extends RefCounted

## A liquid flood-fill for a dead body's bleed-out: blood claims grid cells outward from where it
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
	_progress = minf(_progress + delta / maxf(duration, 0.001), 1.0)
	var eased := 1.0 - (1.0 - _progress) * (1.0 - _progress)
	front = (_last_cost + BloodConfig.flow_soft_edge) * eased


## True once the front has covered every cell.
func settled() -> bool:
	return _progress >= 1.0


## Fill level (0..1) of a claimed cell at the current front.
func fill(c: Vector2i) -> float:
	var t := clampf((front - cells[c]) / maxf(BloodConfig.flow_soft_edge, 0.001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Local centre of a cell.
func _cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * _size


## Claim up to `count` more cells, cheapest first. `origin_global` is the pool's world position.
func step(count: int, space: PhysicsDirectSpaceState2D, origin_global: Vector2) -> void:
	for i in count:
		if _frontier.is_empty():
			return
		var c := _pop_cheapest()
		var cost: float = _frontier[c]
		_frontier.erase(c)
		cells[c] = cost
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
