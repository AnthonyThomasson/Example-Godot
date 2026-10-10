class_name DroppedItem extends Node2D

## An item let go into the world: a dead character's weapon. It falls from hand height, bounces,
## then skids across the floor with a fading spin until it stops, glancing off walls and solid
## furniture (layer 1). Drawn by the item's own draw_dropped() over a shadow that closes in as it
## lands. Visual only: nothing picks it up, and it is never despawned.

## Physics layers it glances off (walls + solid furniture).
const WALL_MASK := 1

@export var gravity: float = 610.0          ## Fall acceleration (px/s²), as a falling body's.
@export var start_height: float = 50.0      ## Height it is let go from (px): about hand height.
@export var bounce: float = 0.35            ## Share of its fall speed each bounce keeps.
@export var friction: float = 520.0         ## Skid deceleration on the floor (px/s²).
@export var wall_bounce: float = 0.45       ## Share of its speed kept glancing off a wall.
@export var spin_friction: float = 14.0     ## Spin deceleration on the floor (rad/s²).
@export var radius: float = 3.0             ## Its size against walls (px).
@export var shadow_per_height: float = 0.06 ## Shadow shift per px of height.

## The item lying here (draws itself).
var item: Item

var _velocity := Vector2.ZERO  ## Across the floor (px/s).
var _height := 0.0             ## Above the floor (px).
var _rise := 0.0               ## Vertical speed (px/s, up).
var _angle := 0.0              ## Which way the item's art points (rad).
var _spin := 0.0               ## Spin (rad/s).
var _query: PhysicsShapeQueryParameters2D  ## Reused wall sweep (a circle of `radius`).


## Let `dropped` go at world point `at`, pointing along `angle`, flying off at `velocity`, into
## `parent`. `held_from` is a clear point it was held from (the hand): if `at` lies inside a wall,
## the item starts where the way from there first meets it instead.
static func spawn(dropped: Item, at: Vector2, angle: float, velocity: Vector2, parent: Node,
		held_from: Vector2) -> DroppedItem:
	var node := DroppedItem.new()
	node.name = "Dropped%s" % dropped.display_name
	node.item = dropped
	node._angle = angle
	node._velocity = velocity
	node._spin = randf_range(6.0, 14.0) * (1.0 if randf() < 0.5 else -1.0)
	parent.add_child(node)
	node.global_position = held_from
	node._slide(at - held_from, false)
	return node


func _ready() -> void:
	z_index = -1  # Beneath the living, like a fallen body.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_height = start_height
	var circle := CircleShape2D.new()
	circle.radius = radius
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = circle
	_query.collision_mask = WALL_MASK


func _physics_process(delta: float) -> void:
	_rise -= gravity * delta
	_height += _rise * delta
	var grounded := _height <= 0.0
	if grounded:
		_height = 0.0
		_rise = -_rise * bounce if _rise < -40.0 else 0.0
		_velocity = _velocity.move_toward(Vector2.ZERO, friction * delta)
		_spin = move_toward(_spin, 0.0, spin_friction * delta)
	_slide(_velocity * delta)
	_angle += _spin * delta
	queue_redraw()
	if grounded and _rise == 0.0 and _velocity.length_squared() < 1.0 and absf(_spin) < 0.05:
		set_physics_process(false)  # At rest for good.


## Move by `motion`, stopping at a wall or solid furniture and (with `glance`) glancing off it.
func _slide(motion: Vector2, glance: bool = true) -> void:
	if motion.length_squared() < 0.000001:
		return
	var space := get_world_2d().direct_space_state
	_query.transform = Transform2D(0.0, global_position)
	_query.motion = motion
	var res := space.cast_motion(_query)
	if res[0] >= 1.0:
		global_position += motion
		return
	global_position += motion * res[0]
	if not glance:
		return
	_query.transform = Transform2D(0.0, global_position + motion * (res[1] - res[0]))
	_query.motion = Vector2.ZERO
	var info := space.get_rest_info(_query)
	var normal: Vector2 = info["normal"] if info.has("normal") else -motion.normalized()
	_velocity = _velocity.bounce(normal) * wall_bounce
	_spin *= -0.5


func _draw() -> void:
	if item == null:
		return
	var away := global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized()
	item.draw_dropped(self, away * (0.5 + _height * shadow_per_height), _angle,
		Color(0.0, 0.0, 0.0, ArtConfig.drop_shadow_alpha))
	item.draw_dropped(self, Vector2.ZERO, _angle)
