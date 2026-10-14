extends RefCounted

## Character KICK (Character domain, animate layer): a leg kick, independent of the held item, always with the right
## leg (side `LEG`, as the hands' side 0). `start()` begins one, `update()` runs it each physics frame: the foot is thrown out along the
## facing (STRIKE), then drawn back (RECOVER); no new kick starts until it is done. The rig draws the foot at
## `amount()` of the way out (`character.leg_kick_amount(i)`), and during the strike a shape query at the foot
## reports every body it reaches, once each per kick: it shoves a pushable (`apply_impulse`) and damages whatever takes
## damage (`take_damage`), then emits `kicked`. Like a punch it never deforms what it hits. Tuning: CharacterConfig.kick_*.

## A body was struck: the damage it was dealt (a kick is always full strength).
signal kicked(body: Node, damage: float)

enum Phase { IDLE, STRIKE, RECOVER }

## Physics layer a kick meets: walls, solid furniture and living characters (the hands' mask).
const MASK := PhysicsLayers.SOLID
## The leg that kicks: side 0, the character's right as drawn.
const LEG := 0

var _phase := Phase.IDLE  ## Where the kick is: not kicking, throwing the foot out, or drawing it back.
var _time := 0.0           ## Seconds into the current phase.
var _hit_bodies := {}      ## Bodies already struck this kick (dedup).
var _shape := CircleShape2D.new()  ## The foot's strike circle (radius set per query).


## Begin a kick with the right leg; false while one is still under way.
func start() -> bool:
	if _phase != Phase.IDLE:
		return false
	_phase = Phase.STRIKE
	_time = 0.0
	_hit_bodies.clear()
	return true


## Whether a kick is under way (striking or drawing back).
func is_active() -> bool:
	return _phase != Phase.IDLE


## How far out the kicking foot is, 0 (at rest) .. 1 (fully thrown).
func amount() -> float:
	match _phase:
		Phase.STRIKE:
			return clampf(_time / CharacterConfig.kick_strike_time, 0.0, 1.0)
		Phase.RECOVER:
			return 1.0 - clampf(_time / CharacterConfig.kick_recover_time, 0.0, 1.0)
	return 0.0


## Drop any kick under way (an interaction took over, or the character died).
func clear() -> void:
	_phase = Phase.IDLE
	_time = 0.0
	_hit_bodies.clear()


## Advance the kick by `delta` and strike what the foot reaches while it is thrown.
func update(character, delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	_time += delta
	if _phase == Phase.STRIKE:
		_strike(character)
		if _time >= CharacterConfig.kick_strike_time:
			_phase = Phase.RECOVER
			_time = 0.0
	elif _time >= CharacterConfig.kick_recover_time:
		clear()


## Where the foot is, in the world: out along the facing by the throw so far.
func foot_world(character) -> Vector2:
	return character.global_position + character.facing * (CharacterConfig.kick_reach * amount())


## Shove and damage every body the foot overlaps that this kick has not struck yet.
func _strike(character) -> void:
	_shape.radius = CharacterConfig.kick_radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _shape
	params.collision_mask = MASK
	params.exclude = [character.get_rid()]
	var foot: Vector2 = foot_world(character)
	params.transform = Transform2D(0.0, foot)
	for result in character.get_world_2d().direct_space_state.intersect_shape(params, 8):
		var body: Node = result.collider
		if body == character or _hit_bodies.has(body):
			continue
		_hit_bodies[body] = true
		var impulse: Vector2 = character.facing * CharacterConfig.kick_impulse
		var pushed := body.has_method("apply_impulse")
		if pushed:
			# At the foot, so a piece struck off-centre turns.
			body.apply_impulse(impulse, foot - (body as Node2D).global_position)
		var damage := CharacterConfig.kick_damage
		GameLog.say("Kick hit %s for %.1f damage, push %.0f (%s)" % [
			body.name, damage, impulse.length(), "pushable" if pushed else "fixed"])
		kicked.emit(body, damage)
		if body.has_method("take_damage"):
			body.take_damage(damage)
		return
