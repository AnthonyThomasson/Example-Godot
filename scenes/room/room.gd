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


func _ready() -> void:
	_build_walls()


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
	for seg in wall_segments():
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
