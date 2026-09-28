class_name CasingSpawner

const Casing = preload("res://scenes/projectile/casing.gd")
const CasingVisuals = preload("res://scenes/projectile/casing_visuals.gd")

## Spawn a spent casing at `position`, ejected out to a random side of the firing
## `direction` (with a slight backward kick), parented to `parent` (the world /
## Main). The casing tweens itself out and rests there — it is NOT time-limited;
## it persists until the general Despawner frees the oldest past Config.max_scene_objects.
static func spawn(position: Vector2, direction: Vector2, parent: Node) -> Node:
	var casing := Node2D.new()
	casing.name = "Casing"
	casing.script = Casing
	casing.position = position

	var visuals := Node2D.new()
	visuals.name = "CasingVisuals"
	visuals.script = CasingVisuals
	casing.add_child(visuals)

	parent.add_child(casing)

	# Track it so the general despawner frees the oldest once the scene holds more
	# than Config.max_scene_objects casings.
	Despawner.track(casing)

	# Eject sideways (random side) plus a small backward component.
	var side := 1.0 if randf() > 0.5 else -1.0
	var eject_dir := direction.orthogonal() * side - direction * 0.3
	casing.start(eject_dir)
	return casing
