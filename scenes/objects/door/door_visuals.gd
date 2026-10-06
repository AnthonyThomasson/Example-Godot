extends Node2D

## Door DRAW layer (Objects domain). Draws the swinging leaf, matching the collider built by the
## control node (door.gd). As a child of the door body it inherits the body's rotation, so it draws
## the leaf along local +X (hinge at origin) and the parent's `rotation` orients the swing. Redraws
## are requested by door.gd whenever the angle changes or a dent is recorded.

@onready var _door := get_parent()  ## Door (RigidBody2D) — geometry + damage source.


func _draw() -> void:
	var a := Vector2.ZERO                       # hinge
	var b := Vector2(_door.leaf_length, 0.0)    # free end
	var impacts: Array = _door._deformable.impacts if _door._deformable else []
	Deformation.draw_wall(self, a, b, _door.wall_thickness, _door.color, impacts)
