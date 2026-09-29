extends Node2D

## Draw layer for a blood pool: one filled circle per particle, in the shared blood color.
## Overlapping circles merge into a single puddle. Sits at a negative z_index so the pool
## draws beneath the player and furniture (like spent casings). Reads the particle list from
## its parent control node (blood_pool.gd).

@onready var _pool := get_parent()  ## The blood pool (control node).


func _ready() -> void:
	z_index = BloodConfig.z_index


func _draw() -> void:
	var color: Color = BloodConfig.color
	for p in _pool.particles:
		draw_circle(p["pos"], p["radius"], color)
