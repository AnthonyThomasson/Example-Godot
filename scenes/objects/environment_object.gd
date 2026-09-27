extends StaticBody2D

@export var shape_type: String = "circle"  # "circle", "square", "rect"
@export var object_name: String = "Object"
@export var size: Vector2 = Vector2(60, 60)
@export var color: Color = Color.GRAY
@export var text_color: Color = Color.WHITE

func _ready() -> void:
	_build_collider()

func _build_collider() -> void:
	var col := CollisionShape2D.new()

	match shape_type:
		"circle":
			var circle := CircleShape2D.new()
			circle.radius = size.x / 2.0
			col.shape = circle

		"square":
			var rect := RectangleShape2D.new()
			rect.size = size
			col.shape = rect

		"rect":
			var rect := RectangleShape2D.new()
			rect.size = size
			col.shape = rect

	add_child(col)
