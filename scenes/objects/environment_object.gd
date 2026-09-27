extends StaticBody2D

@export var shape_type: String = "circle"  # "circle", "square", "rect"
@export var object_name: String = "Object"
@export var size: Vector2 = Vector2(60, 60)
@export var color: Color = Color.GRAY
@export var text_color: Color = Color.WHITE
## Non-solid objects (rugs, mats) get no collider and draw beneath everything else.
@export var solid: bool = true

func _ready() -> void:
	if solid:
		_build_collider()
	else:
		z_index = -1

func _build_collider() -> void:
	var col := CollisionShape2D.new()

	match shape_type:
		"circle":
			var circle := CircleShape2D.new()
			circle.radius = size.x / 2.0
			col.shape = circle

		"square", "rect":
			var rect := RectangleShape2D.new()
			rect.size = size
			col.shape = rect

	add_child(col)
