extends RefCounted

## Character PUSH (Character domain): the one shove a character's walking body and its pressing legs give a pushable
## piece. The impulse lands at the point of contact, so the piece's own rigid-body torque turns it: a sofa pushed at
## one end slides and swings about a point near the far end, one pushed in the middle of a side just slides. The
## piece is carried rather than launched: the impulse is capped so the CONTACT POINT (the piece's linear velocity plus
## its spin about the centre) is never driven faster along the push than the pusher's pace x `push_carry_factor`. The
## cap is worked out with the piece's effective mass at that point (its mass and inertia together), so a turning end
## is held to the same pace as a sliding one. A piece with no `linear_velocity` (another character) takes the shove
## uncapped and ignores the point.


## Shove `piece` (a pushable: `apply_impulse(v, at)` + `get_mass()`) along unit `dir` with up to `impulse`, at world
## point `at_world`, carried at no more than `speed` (px/s, the pusher's pace along `dir`) x `push_carry_factor`.
static func shove(piece: Object, dir: Vector2, impulse: float, at_world: Vector2, speed: float) -> void:
	var at: Vector2 = at_world - (piece as Node2D).global_position
	if "linear_velocity" in piece:
		var spin: float = piece.angular_velocity
		var contact_velocity: Vector2 = piece.linear_velocity + Vector2(-at.y, at.x) * spin
		var gap := maxf(speed * CharacterConfig.push_carry_factor - contact_velocity.dot(dir), 0.0)
		# How fast one unit of impulse at `at` moves that point along `dir`: the slide plus the turn it causes.
		var lever := at.cross(dir)
		var give := 1.0 / maxf(piece.get_mass(), 0.001) + _inverse_inertia(piece) * lever * lever
		impulse = minf(impulse, gap / give)
	piece.apply_impulse(dir * impulse, at)


## The rigid body's inverse moment of inertia as the physics server holds it (computed from its shapes), or 0 when
## it has none to read (no turning is then counted).
static func _inverse_inertia(piece: Object) -> float:
	if not piece is CollisionObject2D:
		return 0.0
	var state := PhysicsServer2D.body_get_direct_state((piece as CollisionObject2D).get_rid())
	return state.inverse_inertia if state else 0.0
