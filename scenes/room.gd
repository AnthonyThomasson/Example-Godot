extends StaticBody2D

## A basic square room drawn as placeholder lines. Wall thickness matches half the
## character's width (the character radius), and static collision walls sit on the lines.
## One side can carry a centered opening (a doorway) via `opening_side`.

enum Side { NONE, TOP, BOTTOM, LEFT, RIGHT }

@export var size: float = 600.0        ## Side length of the square (centerline of the walls).
@export var wall_thickness: float = 24.0  ## Half the character's width.
@export var line_color: Color = Color(0.7, 0.7, 0.7)
## Which wall has the doorway (None = closed room). Values line up with `Side`.
@export_enum("None", "Top", "Bottom", "Left", "Right") var opening_side: int = Side.BOTTOM
@export var opening_width: float = 120.0      ## Width of the centered gap on that wall.


func _ready() -> void:
	_build_walls()


## Centerline segments (start/end points) for every wall, with the opening removed.
func _wall_segments() -> Array[PackedVector2Array]:
	var s := size
	# Each edge as an ordered pair of corner points.
	var edges := {
		Side.TOP: [Vector2(0.0, 0.0), Vector2(s, 0.0)],
		Side.RIGHT: [Vector2(s, 0.0), Vector2(s, s)],
		Side.BOTTOM: [Vector2(0.0, s), Vector2(s, s)],
		Side.LEFT: [Vector2(0.0, 0.0), Vector2(0.0, s)],
	}
	var segments: Array[PackedVector2Array] = []
	for side in edges:
		var a: Vector2 = edges[side][0]
		var b: Vector2 = edges[side][1]
		if side == opening_side and opening_width > 0.0:
			# Split into two segments, leaving a centered gap.
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			var half_gap := opening_width * 0.5
			segments.append(PackedVector2Array([a, mid - dir * half_gap]))
			segments.append(PackedVector2Array([mid + dir * half_gap, b]))
		else:
			segments.append(PackedVector2Array([a, b]))
	return segments


func _build_walls() -> void:
	var t := wall_thickness
	for seg in _wall_segments():
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


func _draw() -> void:
	# Placeholder walls drawn with the wall thickness, matching the colliders.
	for seg in _wall_segments():
		if not seg[0].is_equal_approx(seg[1]):
			draw_line(seg[0], seg[1], line_color, wall_thickness)
