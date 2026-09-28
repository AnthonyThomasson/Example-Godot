extends StaticBody2D

@export var shape_type: String = "circle"  # "circle", "square", "rect"
@export var object_name: String = "Object"
@export var size: Vector2 = Vector2(60, 60)
@export var color: Color = Color.GRAY
@export var text_color: Color = Color.WHITE
## Non-solid objects (rugs, mats) get no collider and draw beneath everything else.
@export var solid: bool = true
## Descriptive material tag (e.g. "wood", "fabric", "metal", "glass"). "wood"/"fabric"
## also drive the room-palette recolor; others are descriptive only. Named
## `object_material` to avoid colliding with CanvasItem's built-in `material`.
@export var object_material: String = ""
## Coverage rating 0–100, a height/cover proxy (flat decor 0 … tall storage 90+).
@export var coverage: float = 0.0
## Penetration value 0–100: resistance to being shot through (soft low, metal high).
@export var penetration: float = 0.0
## Object weight (mass) used for knockback: a hit's impulse is divided by this, so
## heavier objects are thrown back less. Set per-object from the catalog definition.
@export var weight: float = 10.0

## Knockback state (shove & settle). Driven manually because a StaticBody2D can't be
## pushed by the engine: apply_impact() adds velocity, _physics_process integrates it
## and damps back to rest, clamped so the object never slides too far from _origin.
var _velocity := Vector2.ZERO
var _angular := 0.0
var _origin: Vector2

## Recorded damage impacts (local space) that deform the drawn silhouette, and the total
## damage taken (drives fill darkening). Read by environment_object_visuals.gd.
var _impacts: Array = []
var _damage_total := 0.0

func _ready() -> void:
	if solid:
		_build_collider()
	else:
		z_index = -1
	_origin = position

## Shared mass for knockback math: `weight`, floored so featherweight decor still reacts.
func _mass() -> float:
	return maxf(weight, 0.5)

## Shove this object by `impulse` (px/s·mass). Called by the projectile on a hit;
## heavier objects (higher `weight`) gain less velocity. Also adds a little spin for juice.
func apply_impact(impulse: Vector2) -> void:
	var mass := _mass()
	_velocity += impulse / mass
	_angular += (impulse.length() / mass) * 0.002 * (1.0 if randf() > 0.5 else -1.0)

## Record a damage impact for visual deformation: a dent (and, for a hard hit, a carved
## missing piece) plus crack/hole marks at the contact. Stored in local space so it
## rides along as the object is shoved/spun. `world_pos`/`world_normal` come from the
## projectile's raycast; `amount` is the dealt damage.
func record_damage(world_pos: Vector2, world_normal: Vector2, amount: float) -> void:
	var xf := global_transform.affine_inverse()
	var local_pos := xf * world_pos
	var inward := xf.basis_xform(-world_normal).normalized()  # into the surface
	if inward.length() < 0.01:
		inward = -local_pos.normalized() if local_pos.length() > 0.01 else Vector2.DOWN
	var depth := minf(amount * Config.deform_depth_per_damage, Config.deform_max_depth)
	_impacts.append({
		"pos": local_pos, "inward": inward, "depth": depth,
		"chunk": amount >= Config.deform_chunk_damage, "seed": randi(),
	})
	if _impacts.size() > Config.deform_max_impacts:
		_impacts.pop_front()
	_damage_total += amount

	# Make the collider follow the new (deformed) silhouette. Deferred: record_damage is
	# called mid-physics (from the projectile), and swapping shapes then is disallowed.
	if solid and Config.deform_update_collider:
		call_deferred("_rebuild_collider")

## Rebuild the collider from the current deformed silhouette (convex-decomposed), so the
## object collides with what's drawn. Keeps the old collider if decomposition fails.
func _rebuild_collider() -> void:
	var poly := Deformation.shape_polygon(shape_type, size, _impacts)
	var shapes := Deformation.convex_shapes(poly)
	if shapes.is_empty():
		return
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()
	for shape in shapes:
		var col := CollisionShape2D.new()
		col.shape = shape
		add_child(col)

func _physics_process(delta: float) -> void:
	if _velocity.length_squared() < 1.0 and absf(_angular) < 0.01:
		return

	var motion := _velocity * delta
	if motion.length_squared() > 0.0:
		_move_and_collide(motion)

	rotation += _angular * delta
	var offset := position - _origin
	if Config.impact_max_slide > 0.0 and offset.length() > Config.impact_max_slide:
		position = _origin + offset.normalized() * Config.impact_max_slide
		_velocity = Vector2.ZERO
	_velocity = _velocity.move_toward(Vector2.ZERO, Config.impact_friction * delta)
	_angular = move_toward(_angular, 0.0, Config.impact_friction * 0.01 * delta)


## Advance `motion` this frame, stopping at (and transferring force into) whatever it
## would hit, instead of tunneling through walls/furniture like a raw position += did.
## Furniture sits close to walls (HouseSpawner.INTERIOR_MARGIN) and to neighbors
## (RoomFurnisher.PADDING) — both well inside a typical shove's travel — so this
## matters on nearly every hit, not just a rare edge case.
func _move_and_collide(motion: Vector2) -> void:
	var collision := KinematicCollision2D.new()
	if not test_move(global_transform, motion, collision):
		position += motion
		return

	# Snap to the last safe point along the sweep rather than the full requested
	# motion, so this object can never end up overlapping what it just hit.
	position += collision.get_travel()

	var collider: Object = collision.get_collider()
	if collider != null and collider.has_method("apply_impact"):
		var normal := collision.get_normal()
		# Speed this object was closing on the obstacle along the contact normal (the
		# normal points back toward this object, so "into it" is -normal).
		var closing_speed := _velocity.dot(-normal)
		if closing_speed > 0.0:
			var transfer := -normal * closing_speed * _mass() * Config.impact_transfer_scale
			collider.apply_impact(transfer)

	# Stop dead at the point of contact (walls have no apply_impact and are simply
	# immovable). No tangential slide — keeps this simple and impossible to tunnel.
	_velocity = Vector2.ZERO

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
