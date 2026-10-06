class_name DoorFactory

## Objects-domain factory: turns doorway geometry into a runtime Door entity (a frozen RigidBody2D
## that blocks movement, is hittable/destructible, and swings one way on command). World-Gen calls
## this with geometry only — the hinge world point, the direction the shut leaf points along the
## wall, the leaf length (doorway width), the wall thickness, and which way it opens.

const DoorScript = preload("res://scenes/objects/door/door.gd")
const DoorVisualsScript = preload("res://scenes/objects/door/door_visuals.gd")

static func spawn(hinge_world: Vector2, closed_dir: Vector2, length: float, thickness: float,
		swing_sign: float, parent: Node) -> Node:
	var door := RigidBody2D.new()
	door.name = "Door"
	door.position = hinge_world
	door.script = DoorScript

	door.leaf_length = length
	door.wall_thickness = thickness
	door.closed_dir = closed_dir.normalized()
	door.swing_sign = swing_sign

	var visuals := Node2D.new()
	visuals.name = "DoorVisuals"
	visuals.script = DoorVisualsScript
	door.add_child(visuals)

	parent.add_child(door)
	return door
