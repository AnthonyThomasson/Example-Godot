extends StaticBody2D

## Room CONTROL layer. Computes the wall centerline segments (with any doorways cut
## out) and builds the static collision walls. Drawing lives in room_visuals.gd,
## which reads `wall_segments()` and `wall_thickness` from this node.

enum Side { NONE, TOP, BOTTOM, LEFT, RIGHT }

@export var size: Vector2 = Vector2(600.0, 600.0)  ## Room extents (centerline of the walls).
@export var wall_thickness: float = 24.0  ## Half the character's width.
## Doorways: `{ side: Side, offset: float, width: float }`. `offset` is the gap center
## measured along the wall from its start corner (top/bottom walls start at the left,
## left/right walls start at the top).
@export var openings: Array = []

## Damage impacts per wall-segment index (into wall_segments()), in room-local space.
## Read by room_visuals.gd to deform the struck segments. See record_damage().
var _seg_impacts := {}
## Segment index -> Array of that segment's CollisionShape2D nodes, so a damaged segment's
## collider can be rebuilt to follow the deformed shape. Filled in _build_walls().
var _seg_colliders := {}

@onready var _visuals := get_node_or_null("RoomVisuals")


func _ready() -> void:
	_build_walls()


## Record a projectile impact on the nearest wall segment so it deforms (dents, cracks,
## missing pieces) — caving INTO the wall along the contact normal. Redraws the wall
## visuals and, if enabled, rebuilds that segment's collider to match.
func record_damage(world_pos: Vector2, world_normal: Vector2, amount: float) -> void:
	var local_pos := to_local(world_pos)
	var segs := wall_segments()
	var best_i := -1
	var best_d := INF
	var best_proj := Vector2.ZERO
	for i in segs.size():
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		if a.is_equal_approx(b):
			continue
		var proj := Geometry2D.get_closest_point_to_segment(local_pos, a, b)
		var d := local_pos.distance_to(proj)
		if d < best_d:
			best_d = d
			best_i = i
			best_proj = proj
	if best_i < 0:
		return

	# Dent INTO the wall: the contact normal points out of the surface (toward the shot),
	# so into the surface is its negation. Fallback (degenerate normal) = away from the
	# room center, i.e. into the wall — never toward the room.
	var out_normal := to_local(world_pos + world_normal) - local_pos
	var inward := (-out_normal).normalized()
	if inward.length() < 0.5:
		var seg: PackedVector2Array = segs[best_i]
		var perp := (seg[1] - seg[0]).normalized().orthogonal()
		inward = perp if perp.dot(local_pos - size * 0.5) > 0.0 else -perp
	var depth := minf(amount * Config.deform_depth_per_damage, Config.deform_max_depth)
	var arr: Array = _seg_impacts.get(best_i, [])
	arr.append({
		"pos": local_pos, "inward": inward, "depth": depth,
		"chunk": amount >= Config.deform_chunk_damage, "seed": randi(),
	})
	if arr.size() > Config.deform_max_impacts:
		arr.pop_front()
	_seg_impacts[best_i] = arr
	if _visuals:
		_visuals.queue_redraw()
	# Rebuild the segment collider to follow the deformed shape (deferred — record_damage
	# runs mid-physics from the projectile, when swapping shapes is disallowed).
	if Config.deform_update_collider:
		call_deferred("_rebuild_segment", best_i)


## Centerline segments (start/end points) for every wall, with the openings removed.
func wall_segments() -> Array[PackedVector2Array]:
	var w := size.x
	var h := size.y
	# Each edge as an ordered pair of corner points.
	var edges := {
		Side.TOP: [Vector2(0.0, 0.0), Vector2(w, 0.0)],
		Side.RIGHT: [Vector2(w, 0.0), Vector2(w, h)],
		Side.BOTTOM: [Vector2(0.0, h), Vector2(w, h)],
		Side.LEFT: [Vector2(0.0, 0.0), Vector2(0.0, h)],
	}
	var segments: Array[PackedVector2Array] = []
	for side in edges:
		var a: Vector2 = edges[side][0]
		var b: Vector2 = edges[side][1]
		var length := a.distance_to(b)
		var dir := (b - a) / length

		var gaps: Array = openings.filter(func(o: Dictionary) -> bool: return o.side == side)
		gaps.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.offset < y.offset)

		# Walk along the wall, emitting the solid pieces between gaps.
		var cursor := 0.0
		for gap in gaps:
			var gap_start := clampf(gap.offset - gap.width * 0.5, 0.0, length)
			var gap_end := clampf(gap.offset + gap.width * 0.5, 0.0, length)
			if gap_start > cursor:
				segments.append(PackedVector2Array([a + dir * cursor, a + dir * gap_start]))
			cursor = maxf(cursor, gap_end)
		if cursor < length:
			segments.append(PackedVector2Array([a + dir * cursor, b]))
	return segments


func _build_walls() -> void:
	var t := wall_thickness
	var segs := wall_segments()
	for i in segs.size():
		var seg: PackedVector2Array = segs[i]
		var a := seg[0]
		var b := seg[1]
		if a.is_equal_approx(b):
			continue
		# Extend the ends by half the thickness so corners overlap cleanly. (Opening
		# edges also get extended slightly, which just rounds the doorway jamb a touch.)
		var dir := (b - a).normalized()
		var start := a - dir * (t * 0.5)
		var end := b + dir * (t * 0.5)
		var mid := (start + end) * 0.5
		var length := start.distance_to(end)

		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		# Horizontal segment -> width along x; vertical segment -> width along y.
		if absf(dir.x) > absf(dir.y):
			rect.size = Vector2(length, t)
		else:
			rect.size = Vector2(t, length)
		col.shape = rect
		col.position = mid
		add_child(col)
		_seg_colliders[i] = [col]  # keyed by wall_segments() index for later rebuilds


## Rebuild a damaged wall segment's collider(s) from its deformed polygon, so the wall
## collides with what's drawn. Keeps the old collider if convex decomposition fails.
func _rebuild_segment(i: int) -> void:
	var segs := wall_segments()
	if i < 0 or i >= segs.size():
		return
	var seg: PackedVector2Array = segs[i]
	var poly := Deformation.wall_polygon(seg[0], seg[1], wall_thickness, _seg_impacts.get(i, []))
	var shapes := Deformation.convex_shapes(poly)
	if shapes.is_empty():
		return
	for old in _seg_colliders.get(i, []):
		if is_instance_valid(old):
			old.queue_free()
	var cols: Array = []
	for shape in shapes:
		var col := CollisionShape2D.new()
		col.shape = shape  # polygon points are already in room-local space
		add_child(col)
		cols.append(col)
	_seg_colliders[i] = cols
