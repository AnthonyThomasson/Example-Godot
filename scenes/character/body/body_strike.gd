extends RefCounted

## Character BODY sub-domain: the melee strike a punch (character_hands.gd) and a kick (character_kick.gd) share. A
## circle is queried at the striking point on the solid layer; each body in it not struck yet this swing is shoved through
## the pushable contract at the contact (`apply_impulse(impulse, at)`, so a piece struck off-centre turns), logged,
## reported to `on_hit(body, damage)` and dealt the damage (`take_damage`). A strike never deforms; a wall (no
## `apply_impulse`) takes the damage without moving. Stateless.

## Physics layer a strike meets: walls, solid furniture and living characters.
const MASK := PhysicsLayers.SOLID


## Strike every body a circle of `radius` at world `at` overlaps, but `character` itself and those already in `struck`
## (each one struck is added to it), shoving it by `impulse` and dealing it `damage`. `what` names the strike in the log
## line and `note` ends its bracket. With `first_only` it stops after the first body.
static func strike(character: CollisionObject2D, at: Vector2, radius: float, impulse: Vector2, damage: float,
		struck: Dictionary, first_only: bool, on_hit: Callable, what: String, note := "") -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = MASK
	params.exclude = [character.get_rid()]
	params.transform = Transform2D(0.0, at)
	for result in character.get_world_2d().direct_space_state.intersect_shape(params, 8):
		var body: Node = result.collider
		if body == character or struck.has(body):
			continue
		struck[body] = true
		var pushed := body.has_method("apply_impulse")
		if pushed:
			body.apply_impulse(impulse, at - (body as Node2D).global_position)
		GameLog.say("%s hit %s for %.1f damage, push %.0f (%s%s)" % [
			what, body.name, damage, impulse.length(), "pushable" if pushed else "fixed", note])
		on_hit.call(body, damage)
		if body.has_method("take_damage"):
			body.take_damage(damage)
		if first_only:
			return
