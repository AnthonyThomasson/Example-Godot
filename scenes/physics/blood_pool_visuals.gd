extends Node2D

## Draw layer for a blood pool: one lumpy filled blob per particle, in the shared blood color. Each
## blob is a polygon built from the drop's stored per-vertex shape, so it reads as an organic splat
## rather than a circle and no two blobs match; overlapping blobs merge into a single, ragged puddle.
## Sits at a negative z_index so the pool draws beneath the player and furniture (like spent
## casings). Reads the particle list from its parent control node (blood_pool.gd).

@onready var _pool := get_parent()  ## The blood pool (control node).


func _ready() -> void:
	z_index = BloodConfig.z_index


func _draw() -> void:
	var color: Color = BloodConfig.color
	for p in _pool.particles:
		var center: Vector2 = p["pos"]
		var radius: float = p["radius"]
		var shape: PackedFloat32Array = p["shape"]
		var verts := shape.size()
		var points := PackedVector2Array()
		for i in verts:
			var angle := TAU * i / verts
			points.append(center + Vector2(cos(angle), sin(angle)) * radius * shape[i])
		draw_colored_polygon(points, color)
