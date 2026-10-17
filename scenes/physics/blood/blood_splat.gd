extends Node2D

## Physics System, blood: one splatter of blood where a drop (or a spray droplet) hit the floor: an irregular core with
## tapered crown spikes radiating from it, some ending in a tail droplet, and small satellite droplets scattered around.
## Built once by `setup`, then static; colliderless and Despawner-tracked. The outline is stretched and flung along the
## drop's travel by `energy` (a still drop leaves a round crown, a fast one an elongated, forward-thrown splat).
## Satellites and spike tips are clipped by walls and furniture, so blood never lands across them. All shapes are merged
## into opaque outlines before drawing, so overlaps don't darken; the splat then dries from `BloodConfig.color` to
## `dried_color`. Draws at `BloodConfig.z_index` (`DrawLayers.BLOOD`): over the floor and rugs, under what lies there (a
## body, casings) and the standing world.

## Vertices in the core blob's outline.
const CORE_VERTS := 16
## Vertices in a droplet's outline.
const DROPLET_VERTS := 10

## The splat's merged outline polygons (local space), drawn in `BloodConfig.color`. Public so the draw
## step and tests can read them.
var shapes: Array[PackedVector2Array] = []
var _boxes: Array[Rect2] = []  ## `shapes[i]`'s bounding box while the splat is being built (see `_merge_in`).

## Core radius (px) and the heading (radians) its local +x runs along.
var _radius := 3.0
var _heading := 0.0
## Collider RIDs the clipping rays ignore (the body the blood came from).
var _exclude: Array = []
var _space: PhysicsDirectSpaceState2D  ## The space the wall rays query.
## The worker task merging a begun splat (-1 when none), and where it leaves the outlines (see `begin`).
var _task := -1
var _built: Array = [null]


func _ready() -> void:
	z_index = BloodConfig.z_index


## Build the splat: core radius `radius` (px), thrown toward `direction` (zero = no preferred way) with
## `energy` 0..1. Call after the node is in the tree and placed, so wall clipping can query the world.
func setup(radius: float, direction: Vector2, energy: float, exclude: Array = []) -> void:
	for poly in _throw(radius, direction, energy, exclude):
		_merge_in(poly)
	_finish(_drawable_all(shapes))


## `setup` in two halves, so the splats of one spray are merged side by side: `begin` throws the splat here (its random
## shapes and their wall rays, in the same order as `setup`) and merges its outlines on a worker thread (the same fold,
## `_fold`); `finish` waits for them and completes the splat as `setup` does. The caller finishes it before anything else
## can see it (`BloodWound.record`, before it returns).
func begin(radius: float, direction: Vector2, energy: float, exclude: Array = []) -> void:
	var polys := _throw(radius, direction, energy, exclude)
	var built: Array = [null]
	_built = built
	_task = WorkerThreadPool.add_task(func() -> void:
		var outlines: Array[PackedVector2Array] = []
		var boxes: Array[Rect2] = []
		for poly in polys:
			_fold(outlines, boxes, poly)
		built[0] = _drawable_all(outlines), true, "blood splat")


## Complete a splat `begin` started: wait for its merged outlines, then register, highlight and dry it as `setup` does.
func finish() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_finish(_built[0])


func _exit_tree() -> void:
	if _task >= 0:  # a begun splat leaving unfinished: its worker task must still be waited for
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## The splat's random shapes (core, spikes, satellites), clipped by the walls: its first half, on the main thread.
func _throw(radius: float, direction: Vector2, energy: float, exclude: Array) -> Array[PackedVector2Array]:
	_radius = radius
	_exclude = exclude
	_space = get_world_2d().direct_space_state
	var e := clampf(energy, 0.0, 1.0)
	_heading = direction.angle() if direction.length() > 0.001 else randf() * TAU

	var polys: Array[PackedVector2Array] = [_core(e)]
	for spike in _spikes(e):
		polys.append(spike)
	for droplet in _satellites(e):
		polys.append(droplet)
	return polys


## The merged outlines that can be drawn (`drawable`, empties dropped).
static func _drawable_all(outlines: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var kept: Array[PackedVector2Array] = []
	for outline in outlines:
		var ok := drawable(outline)
		if not ok.is_empty():
			kept.append(ok)
	return kept


## The built splat's last half, on the main thread: its outlines `kept`, registered, highlighted and set drying.
func _finish(kept: Array[PackedVector2Array]) -> void:
	shapes = kept
	_boxes.clear()
	BloodField.add_splat(self, shapes)
	_add_highlight()
	_dry()
	queue_redraw()


func _draw() -> void:
	var color: Color = BloodConfig.color
	if not FillBatch.batching:  # the headless display: each outline by its own command costs the least
		for poly in shapes:
			draw_colored_polygon(poly, color)
		return
	var batch := FillBatch.new(self)  # One command for every outline, the same triangles (General's FillBatch).
	for poly in shapes:
		batch.fill(poly, color)
	batch.flush()


## The core: a lumpy blob, longer along the heading and narrower across it as energy grows.
func _core(e: float) -> PackedVector2Array:
	var raw := PackedFloat32Array()
	for i in CORE_VERTS:
		raw.append(1.0 + randf_range(-BloodConfig.splat_wobble, BloodConfig.splat_wobble))
	var rx := _radius * (1.0 + BloodConfig.splat_stretch * e)
	var ry := _radius * (1.0 - 0.25 * e)
	var points := PackedVector2Array()
	for i in CORE_VERTS:
		var lump := (raw[(i - 1 + CORE_VERTS) % CORE_VERTS] + raw[i] * 2.0 + raw[(i + 1) % CORE_VERTS]) / 4.0
		var a := TAU * i / CORE_VERTS
		points.append(_at(Vector2(cos(a) * rx, sin(a) * ry) * lump))
	return points


## Crown spikes: tapered, slightly waisted arms out of the core. Forward ones (along the heading) run
## longer with energy and backward ones shorter; a long spike may throw a tail droplet past its tip.
## A spike whose tip would cross a wall is shortened to stop short of it.
func _spikes(e: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var count := randi_range(BloodConfig.splat_spikes_min, BloodConfig.splat_spikes_max)
	var offset := randf() * TAU
	for i in count:
		var a := offset + TAU * (i + randf_range(-0.35, 0.35)) / count
		var fwd := cos(a)
		var length := lerpf(BloodConfig.splat_spike_length_min, BloodConfig.splat_spike_length_max, pow(randf(), 1.5))
		length *= 1.0 + e * 0.9 * maxf(fwd, 0.0)
		length *= 1.0 - 0.35 * e * maxf(-fwd, 0.0)
		var dir := Vector2.from_angle(a)
		var base_r := _radius * 0.7 * (1.0 + BloodConfig.splat_stretch * e * absf(fwd))
		var tip_r := base_r + length * _radius
		var free := _free_fraction(dir * tip_r)
		if free < 1.0:
			tip_r *= free * 0.9
		if tip_r <= base_r * 1.15:
			continue
		var half := _radius * randf_range(0.16, 0.36)
		var side := Vector2(-dir.y, dir.x)
		var mid_r := lerpf(base_r, tip_r, 0.5)
		out.append(PackedVector2Array([
			_at(dir * base_r + side * half),
			_at(dir * mid_r + side * half * 0.5),
			_at(dir * tip_r),
			_at(dir * mid_r - side * half * 0.5),
			_at(dir * base_r - side * half),
		]))
		if free >= 1.0 and length > 1.0 and randf() < 0.55:
			var gap := _radius * randf_range(0.2, 0.45)
			out.append(_droplet(dir * (tip_r + gap), dir, half * randf_range(0.5, 0.8), 1.0 + e * 0.6))
	return out


## Satellite droplets scattered around the core, farther and more forward with energy, smaller the
## farther they land, elongated outward. Any whose path from the core is blocked are dropped.
func _satellites(e: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var count := randi_range(BloodConfig.splat_satellites_min, BloodConfig.splat_satellites_max)
	for i in count:
		var a := randf() * TAU
		var fwd := cos(a)
		var reach := randf_range(BloodConfig.splat_satellite_reach_min, BloodConfig.splat_satellite_reach_max)
		reach *= 1.0 + e * 0.8 * maxf(fwd, 0.0)
		var dir := Vector2.from_angle(a)
		var at := dir * reach * _radius
		if _free_fraction(at) < 1.0:
			continue
		var t := inverse_lerp(BloodConfig.splat_satellite_reach_min, BloodConfig.splat_satellite_reach_max * 1.8, reach)
		var size := _radius * (0.08 + pow(randf(), 2.0) * 0.22) * lerpf(1.0, 0.6, clampf(t, 0.0, 1.0))
		out.append(_droplet(at, dir, size, 1.0 + e * 0.8))
	return out


## A small ellipse at `at` (forward-frame local), `size` px across its short axis and `elong` times that
## along `dir`.
func _droplet(at: Vector2, dir: Vector2, size: float, elong: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var side := Vector2(-dir.y, dir.x)
	for i in DROPLET_VERTS:
		var a := TAU * i / DROPLET_VERTS
		points.append(_at(at + dir * cos(a) * size * elong + side * sin(a) * size))
	return points


## `poly` if the engine can triangulate it, else its convex hull, else empty. A union of random blobs
## occasionally comes out self-touching (about 1 splat in 100,000), and drawing that logs "Invalid
## polygon data, triangulation failed".
static func drawable(poly: PackedVector2Array) -> PackedVector2Array:
	if Deformation.is_valid_polygon(poly):
		return poly
	var hull := Geometry2D.convex_hull(poly)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	return hull if Deformation.is_valid_polygon(hull) else PackedVector2Array()


## Fold `poly` into the merged outlines: union it with any outline it touches (so overlapping parts
## become one opaque shape), else keep it separate. Holes the union may leave are ignored.
func _merge_in(poly: PackedVector2Array) -> void:
	_fold(shapes, _boxes, poly)


## `_merge_in` on given outlines and their boxes (pure, so a worker thread may run it).
static func _fold(outlines: Array[PackedVector2Array], boxes: Array[Rect2], poly: PackedVector2Array) -> void:
	var current := poly
	var current_box := _box_of(current)
	var i := 0
	while i < outlines.size():
		# Outlines whose boxes are apart cannot touch: the union would keep them as two, so skip the merge.
		if not current_box.intersects(boxes[i]):
			i += 1
			continue
		var merged := Geometry2D.merge_polygons(outlines[i], current)
		var outer: Array[PackedVector2Array] = []
		for m in merged:
			if not Geometry2D.is_polygon_clockwise(m):
				outer.append(m)
		if outer.size() == 1:
			current = outer[0]
			current_box = _box_of(current)
			outlines.remove_at(i)
			boxes.remove_at(i)
			i = 0
		else:
			i += 1
	outlines.append(current)
	boxes.append(current_box)


## The box around `poly`, a hair larger so outlines that merely touch still count as overlapping.
static func _box_of(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	return box.grow(0.1)


## A lighter fleck on the core so fresh blood reads wet; it fades as the splat dries.
func _add_highlight() -> void:
	var glint: Color = BloodConfig.splat_highlight
	if glint.a <= 0.0 or _radius < 2.0:
		return
	var fleck := Polygon2D.new()
	fleck.name = "Highlight"
	fleck.color = glint
	var points := PackedVector2Array()
	var r := _radius * 0.32
	for i in DROPLET_VERTS:
		var a := TAU * i / DROPLET_VERTS
		points.append(Vector2(-0.3, -0.35) * _radius + Vector2(cos(a), sin(a)) * r)
	fleck.polygon = points
	add_child(fleck)


## Dry from the wet color to the dried one over `splat_dry_time`; the highlight fades out with it.
func _dry() -> void:
	var seconds := BloodConfig.splat_dry_time
	if seconds <= 0.0:
		return
	var wet: Color = BloodConfig.color
	var dried: Color = BloodConfig.dried_color
	var ratio := Color(dried.r / maxf(wet.r, 0.001), dried.g / maxf(wet.g, 0.001), dried.b / maxf(wet.b, 0.001), dried.a / maxf(wet.a, 0.001))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "self_modulate", ratio, seconds)
	var fleck := get_node_or_null("Highlight")
	if fleck:
		tween.tween_property(fleck, "modulate:a", 0.0, seconds)


## A point in the splat's forward frame (+x along the throw) turned into local space.
func _at(p: Vector2) -> Vector2:
	return p.rotated(_heading)


## How much of the way from the core to `p` (forward-frame local) is open floor: 1 if nothing blocks it,
## else the fraction at which a wall or furniture collider (`PhysicsConfig.wall_mask`) is struck.
func _free_fraction(p: Vector2) -> float:
	var local := _at(p)
	if local.length_squared() < 0.0001:
		return 1.0
	var ray := PhysicsRayQueryParameters2D.create(global_position, global_position + local, PhysicsConfig.wall_mask)
	ray.exclude = _exclude
	var hit := _space.intersect_ray(ray)
	if hit.is_empty():
		return 1.0
	return (hit.position as Vector2).distance_to(global_position) / local.length()
