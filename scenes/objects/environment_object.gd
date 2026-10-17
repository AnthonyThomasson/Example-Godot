extends RigidBody2D

## An Objects-domain world object (furniture, decor). Owns its surface data (shape, size,
## color, cover/penetration ratings, material, mass) and composes three Physics components —
## a Knockback child (RigidBody2D adapter, how take_hit shoves it), a Deformable child (damage
## dents/chunks) and, on a solid piece, a BloodSmear child (drags blood out of a puddle). The engine integrates its motion, collisions and pivoting. It
## exposes the two contracts the rest of the game talks to it through, and nothing else:
##   • get_surface() / take_hit(HitInfo)  — the "hittable" contract (Projectile, melee)
##   • apply_impulse(Vector2, at) / get_mass() — the "pushable" contract (blasts, a character's push, legs, punch, kick)
##   • get_lights() — the lights it gives (object_lights.gd), which the Lighting domain reads duck-typed
## A solid piece also casts a shadow: a LightOccluder2D over its footprint (on General's `LightMasks`), a child
## so it follows a shove, built here like its collider.
## The force and deformation MATH lives in the Physics domain; this file only wires it up.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const ObjectLights = preload("res://scenes/objects/object_lights.gd")
## The sides of a round piece's shadow footprint.
const OCCLUDER_SIDES := 12

@export var shape_type: String = "circle"  ## "circle", "square", or "rect".
@export var object_name: String = "Object"  ## Label drawn on the object.
@export var size: Vector2 = Vector2(60, 60)  ## Footprint in px.
@export var color: Color = Color.GRAY        ## Fill color.
@export var text_color: Color = Color.WHITE  ## Label color.
## Non-solid objects (rugs, mats) get no collider and draw beneath everything else.
@export var solid: bool = true
## A solid piece that never moves (a streetlight's post): frozen static, so no shove, kick, round or blast moves or turns it;
## it is still struck, dented and throws debris. Ignored on a non-solid piece (decor is frozen anyway).
@export var anchored: bool = false
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
## Interactions this object offers, as plain data dicts (id, label, optional move_to /
## requires_item). Read by the Interaction domain via get_interactions(); empty means none.
@export var interactions: Array = []
## Pixel-art painter id ("sofa", "table", "chair"); "" draws the flat shape and its label.
@export var art: String = ""
## Per-piece painter overrides (see ObjectArtConfig), e.g. { "runner": true }.
@export var art_opts: Dictionary = {}
## Which way the piece's front faces, in its local frame (a cardinal direction). Visual only:
## it orients the art (a sofa's seat, a chair's seat away from its back rail).
@export var facing: Vector2 = Vector2.DOWN

## Physics components, created in _ready() (runtime-shape convention).
var _knockback: Knockback  ## RigidBody2D adapter; take_hit shoves the body through it.
var _deformable: Deformable  ## Damage dents/chunks; read by the visuals.
var _smear: BloodSmear  ## Drags blood out of a puddle as the piece slides through it (solid pieces only).
var _collider_rebuild_queued := false  ## A deferred `_rebuild_collider` is already waiting.
var _surface_id := -1  ## BloodSurface registration of a non-solid piece (a rug soaks blood up).
var _lights: Array = []  ## What `get_lights()` declares (worked out once its visuals are ready).


func _ready() -> void:
	_knockback = Knockback.new()
	_knockback.mass = weight
	add_child(_knockback)

	_deformable = Deformable.new()
	add_child(_deformable)
	_deformable.changed.connect(_on_deformable_changed)

	# The visuals (a child, ready first) have built their light-source overlay, which a light dims with.
	_lights = ObjectLights.of(self)
	if solid:
		_build_collider()
		_build_occluder()
		_smear = BloodSmear.new()
		add_child(_smear)
		_smear.set_footprint(Deformation.shape_polygon(shape_type, size, _deformable.impacts))
		if anchored:
			# Frozen static: the physics server gives it no inverse mass, so every impulse (a push, a kick, a blast) is
			# ignored and a body striking it stops as at a wall; queries and the hittable contract still find it.
			freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
			freeze = true
	else:
		# Non-solid decor never moves or collides: freeze it (a shapeless RigidBody2D would
		# be invalid) and draw it beneath everything else.
		freeze = true
		z_index = ObjectArtConfig.rug_z_index
		# Never moves, so its footprint is fixed: blood that reaches cloth (a rug, a mat) sinks in (Physics blood); it runs
		# past the rest of the walk-over decor (litter, cables, a puddle, a neon tube).
		if object_material == "fabric":
			_surface_id = BloodSurface.register(Rect2(global_position - size / 2.0, size), _no_groove, true)


func _exit_tree() -> void:
	BloodSurface.unregister(_surface_id)
	if _cut != null:
		_cut.cancel()


## A rug has no grooves (BloodSurface callback; a porous surface never asks).
func _no_groove(_at: Vector2, _half_width: float) -> float:
	return 0.0


# --- Hittable contract (read/hit by projectiles, melee, …) -----------------------------

## The object's ballistic surface: how much it covers, how hard it is to shoot through,
## its material tag and its color (for debris styling: the colour its art is drawn in). Read by the Projectile System.
func get_surface() -> Dictionary:
	return { "coverage": coverage, "penetration": penetration, "material": object_material,
		"color": ObjectArt.drawn_color(color) if art != "" else color }


## The hit marks on this object (dicts with `pos`, `depth`, `blood`, …), oldest first.
func hit_marks() -> Array:
	return _deformable.impacts


## Take a hit: shove along the impact at the contact point (so an off-center hit spins the
## object; an anchored piece is not shoved), record the deformation, and spray debris. The striker fills in a HitInfo.
func take_hit(hit: HitInfo) -> void:
	if not anchored:
		_knockback.apply_impulse(Physics.impact_impulse(hit), hit.position)
	_deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())


# --- Lights (read duck-typed by the Lighting domain) -----------------------------------

## The lights this piece gives, as plain dicts in its own frame (`offset`, `turn`, `colour`, `energy`, `radius`, `shape`,
## `rhythm`, `room_light`, `street`, `height`, `glow`: see object_lights.gd); empty for a piece that gives none.
func get_lights() -> Array:
	return _lights


# --- Interactable contract (read by the Interaction domain) ----------------------------

## The interactions this object offers (plain data dicts; see the Interaction domain). The
## object holds no interaction logic — it only advertises the actions. Empty if none.
func get_interactions() -> Array:
	return interactions


# --- Pushable contract (interface 5: blasts, a character's walking push, legs, punch, kick) ---
# Both halves are served by RigidBody2D's native methods: apply_impulse(v, at) (`at` the contact offset from the
# origin, so a shove off the centre turns the piece; omitted = a central shove) and get_mass() (returns `mass`,
# which Knockback sets from `weight`). Nothing to add: an anchored piece is frozen static, which the engine never moves.


# --- Collider (built in code; rebuilt to follow the deformed silhouette) ---------------

## Rebuild the collider when the silhouette deforms. Deferred: record() runs mid-physics
## (from the projectile), when swapping shapes is disallowed.
## Hits that land before the deferred call runs share it: it rebuilds from the impacts as they stand then.
## Cutting the dented silhouette into convex pieces is the costly part of a rebuild, and a blast dents a room's worth of furniture
## at once: the cut is queued with the rebuild (`ColliderCuts`), and the first rebuild of the batch cuts the others on worker
## threads beside its own. The collider changes in its deferred rebuild, into the pieces a cut there would make.
func _on_deformable_changed() -> void:
	if solid and PhysicsConfig.deform_update_collider and not _collider_rebuild_queued:
		_collider_rebuild_queued = true
		_cut = ColliderCuts.queue(_prepare_cut)
		call_deferred("_rebuild_collider")


## The cut queued with the rebuild, null when none waits.
var _cut: ColliderCuts = null


## The cut of this piece's silhouette as its dents stand now (on the main thread): a pure job on a copy of them.
func _prepare_cut() -> Callable:
	var shape := shape_type
	var footprint := size
	var dents: Array = _deformable.impacts.duplicate(true)
	return func() -> Array: return Deformation.cut_shape(shape, footprint, dents)


## The convex pieces of `poly`, this piece's silhouette now: the queued cut's, or cut here should it be of another silhouette.
func _pieces_of(poly: PackedVector2Array) -> Array:
	var cut := _cut
	_cut = null
	if cut != null:
		var made := cut.take()
		if not made.is_empty() and made[0] == poly:
			return made[1]
	return Deformation.convex_pieces(poly)


## Replace the collider(s) with convex pieces of the current deformed polygon.
func _rebuild_collider() -> void:
	_collider_rebuild_queued = false
	var poly := Deformation.shape_polygon(shape_type, size, _deformable.impacts)
	var shapes := Deformation.shapes_of(_pieces_of(poly))
	if shapes.is_empty():
		return
	_smear.set_footprint(poly)
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()
	for shape in shapes:
		var col := CollisionShape2D.new()
		col.shape = shape
		add_child(col)


## The piece's shadow: an occluder over its undented footprint (its rect, or a circle as a `OCCLUDER_SIDES`-gon: a shadow
## needs no more, and every edge is drawn into each light's shadow map; dents are too small to show in one). A piece that
## gives light is on `LightMasks.EMITTER`, so its own light, sitting inside it, is never shut in; one as tall as
## `LightMasks.TALL_COVERAGE` on `TALL` (it shadows the low lights too); the rest on `FURNITURE`.
## None while `LightMasks.shadows` is off.
func _build_occluder() -> void:
	var poly := PackedVector2Array()
	if shape_type == "circle":
		for k in OCCLUDER_SIDES:
			poly.append(Vector2.RIGHT.rotated(TAU * k / OCCLUDER_SIDES) * size.x * 0.5)
	else:
		var h := size * 0.5
		poly = PackedVector2Array([-h, Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
	var bit := LightMasks.FURNITURE
	if not _lights.is_empty():
		bit = LightMasks.EMITTER
	elif coverage >= LightMasks.TALL_COVERAGE:
		bit = LightMasks.TALL
	var occ := LightMasks.occluder(poly, bit)
	if occ != null:
		add_child(occ)


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
