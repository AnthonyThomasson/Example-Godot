extends StaticBody2D

## An Objects-domain world object (furniture, decor). Owns its surface data (shape, size,
## color, cover/penetration ratings, material, mass) and composes two Physics components —
## a Knockback child (shove & settle) and a Deformable child (damage dents/chunks). It
## exposes the two contracts the rest of the game talks to it through, and nothing else:
##   • get_surface() / take_hit(HitInfo)  — the "hittable" contract (Projectile, melee)
##   • apply_impulse(Vector2) / get_mass() — the "pushable" contract (Knockback, character)
## The force and deformation MATH lives in the Physics domain; this file only wires it up.

@export var shape_type: String = "circle"  ## "circle", "square", or "rect".
@export var object_name: String = "Object"  ## Label drawn on the object.
@export var size: Vector2 = Vector2(60, 60)  ## Footprint in px.
@export var color: Color = Color.GRAY        ## Fill color.
@export var text_color: Color = Color.WHITE  ## Label color.
## Non-solid objects (rugs, mats) get no collider and draw beneath everything else.
@export var solid: bool = true
## Descriptive material tag (e.g. "wood", "fabric", "metal", "glass"). "wood"/"fabric"
## also drive the room-palette recolor. Named `object_material` to avoid colliding with
## CanvasItem's built-in `material`.
@export var object_material: String = ""
## Coverage rating 0–100, a height/cover proxy (flat decor 0 … tall storage 90+).
@export var coverage: float = 0.0
## Penetration value 0–100: resistance to being shot through (soft low, metal high).
@export var penetration: float = 0.0
## Mass used for knockback: a shove's impulse is divided by this. Set from the catalog.
@export var weight: float = 10.0

## Physics components, created in _ready() (runtime-shape convention).
var _knockback: Knockback  ## Shove & settle.
var _deformable: Deformable  ## Damage dents/chunks; read by the visuals.


func _ready() -> void:
	_knockback = Knockback.new()
	_knockback.mass = weight
	add_child(_knockback)

	_deformable = Deformable.new()
	add_child(_deformable)
	_deformable.changed.connect(_on_deformable_changed)

	if solid:
		_build_collider()
	else:
		z_index = -1


# --- Hittable contract (read/hit by projectiles, melee, …) -----------------------------

## The object's ballistic surface: how much it covers, how hard it is to shoot through,
## its material tag and its color (for debris styling). Read by the Projectile System.
func get_surface() -> Dictionary:
	return { "coverage": coverage, "penetration": penetration, "material": object_material, "color": color }


## Take a hit: shove along the impact (via the Physics impulse + our Knockback), record
## the deformation, and spray debris. The striker just fills in a HitInfo and calls this.
func take_hit(hit: HitInfo) -> void:
	_knockback.apply_impulse(Physics.impact_impulse(hit))
	_deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())


# --- Pushable contract (shoved by Knockback transfers and the walking character) -------

## Take a shove.
func apply_impulse(impulse: Vector2) -> void:
	_knockback.apply_impulse(impulse)


## The object's mass, used by pushers to scale their shove.
func get_mass() -> float:
	return _knockback.effective_mass()


# --- Collider (built in code; rebuilt to follow the deformed silhouette) ---------------

## Rebuild the collider when the silhouette deforms. Deferred: record() runs mid-physics
## (from the projectile), when swapping shapes is disallowed.
func _on_deformable_changed() -> void:
	if solid and PhysicsConfig.deform_update_collider:
		call_deferred("_rebuild_collider")


## Replace the collider(s) with convex pieces of the current deformed polygon.
func _rebuild_collider() -> void:
	var poly := Deformation.shape_polygon(shape_type, size, _deformable.impacts)
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


## Build the initial collider from the object's primitive shape.
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
