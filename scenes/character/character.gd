extends CharacterBody2D

## A generic top-down character. It owns the body, movement, aim-based "facing", the item
## inventory, and the knockback it takes from shoves. It reads its intent from a pluggable
## controller child (any node with a `control(character, delta)` method): the controller
## writes `move_input` / `aim_point` and calls `melee/shoot/select_slot`. Drawing
## is in character_visuals.gd, the hand/punch/fist geometry in character_hands.gd, the living
## motion of head, shoulders, hips and hands in character_pose.gd (stepped here each physics frame),
## the standing skeleton the limbs are drawn from in character_rig.gd, and the body's fall on death
## in character_ragdoll.gd (stepped here once dead).

## Radius of the placeholder circle. Matches chair size (28x28 → 14 radius).
@export var radius: float = 14.0  ## Body circle radius (px).
@export var speed: float = 150.0  ## Move speed (px/s).
## Slot the character starts holding.
@export var start_slot: int = 1
## Allegiance tag, read by AI perception to tell allies from potential hostiles.
@export var faction: StringName = &"player"
## Maximum health. Characters start at this value; configurable per character in the inspector.
@export var max_health: float = 50.0

## Emitted once when health drops to zero.
signal died

## Current health, initialised to max_health. Read-only outside this script.
var health: float
## True once the character has died; gates all movement and action permanently.
var is_dead: bool = false

## Unit vector from the character toward its aim point; read by the hands and visuals.
var facing := Vector2.RIGHT
## The body's living motion (head, shoulders, hips and hands chasing `facing`); read by the hands,
## rig and visuals.
var pose: CharacterPose = CharacterPose.new()
## The falling body once dead (null while alive): stepped here, drawn by the visuals.
var ragdoll: CharacterRagdoll
## True once the dead body has come to rest and started bleeding out.
var _bled_out := false

## Intent, written each frame by the controller.
var move_input := Vector2.ZERO   ## Desired move direction (already 0–1 length).
var aim_point := Vector2.ZERO    ## World point to face.
var run_input := false           ## Wants to run; honoured only while moving with stamina left.

## Stamina as a fraction of a full bar; spent while running, regained otherwise.
var stamina := 1.0
## Ran dry: walks until stamina refills to `CharacterConfig.run_resume_fraction`.
var _exhausted := false
var _running := false  ## Running this frame.

## Inventory (slot id -> Item) and the currently held slot.
var _items := {}
var _current_slot := 1  ## Held inventory slot.

## Knockback velocity from objects shoved into the character; decays each frame. Added on
## top of controller-driven movement.
var _knockback := Vector2.ZERO
## Speed multiplier from pushing objects last frame (1.0 = unencumbered).
var _push_slow := 1.0

## Damage dents/chunks recorded when the character is shot; read by the visuals and the
## collider rebuild. The character is flesh — a hittable surface like furniture.
var _deformable: Deformable
## Splatter and dripping from this character's wounds (Physics domain component).
var _wound: BloodWound
## Bloody footprints from blood the feet walk through (Physics domain component), fed by `_footsteps`.
var _footprints: BloodFootprints
var _footsteps := CharacterFootsteps.new()  ## Detects footfalls and feeds `_footprints`.

## Emitted when a held item lands a hit on a body. `hand` is 0/1 for a melee punch, -1 for a
## shot; `damage` is the amount dealt (a punch scales it by its range of motion). Melee vs shot
## is told apart by `hand`, not by the damage value.
signal hit_landed(body: Node, damage: float, hand: int)

## Interaction component (Interaction domain): finds and runs object interactions. Composed in
## code like the other components; the character only forwards `try_interact()` and reads
## `is_busy()` / `interaction_label()`.
const CharacterInteraction = preload("res://scenes/interaction/character_interaction.gd")
const CharacterPose = preload("res://scenes/character/character_pose.gd")
const CharacterRig = preload("res://scenes/character/character_rig.gd")
const CharacterRagdoll = preload("res://scenes/character/character_ragdoll.gd")
const CharacterFootsteps = preload("res://scenes/character/character_footsteps.gd")

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _hands := $Hands
@onready var _controller := _find_controller()
var _interaction: Node  ## The CharacterInteraction child, built in _ready().


func _ready() -> void:
	# Top-down: no floor/ceiling, so a moving body it touches is never ridden as a platform.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Build the body's collision circle to match `radius`.
	var circle := CircleShape2D.new()
	circle.radius = radius
	_shape.shape = circle

	health = max_health

	_items = ItemRegistry.default_inventory()
	_current_slot = start_slot
	# Re-emit the hands' punch as a unified hit_landed (melee → hand 0/1, with its dealt damage).
	_hands.punched.connect(_on_punched)

	# Compose the flesh deformation component; its impacts dent the drawn silhouette (visual
	# only — the body keeps its circular hitbox). No carved chunks, since a chunk's reach
	# would span this small body and fold it.
	_deformable = Deformable.new()
	_deformable.max_depth = CharacterConfig.flesh_deform_max_depth
	_deformable.allow_chunks = CharacterConfig.flesh_allow_chunks
	_deformable.max_impacts = CharacterConfig.flesh_deform_max_impacts
	add_child(_deformable)

	_wound = BloodWound.new()
	add_child(_wound)

	_footprints = BloodFootprints.new()
	add_child(_footprints)

	_interaction = CharacterInteraction.new()
	add_child(_interaction)


func _physics_process(delta: float) -> void:
	if is_dead:
		ragdoll.step(delta, get_world_2d().direct_space_state, global_position)
		if ragdoll.is_settled() and not _bled_out:
			_bled_out = true
			Physics.bleed_out(get_parent(), self, [get_rid()])
		return

	# Pull intent from the controller first, so facing/movement use this frame's input.
	if _controller:
		_controller.control(self, delta)

	# While in an interaction the character is fully frozen: it holds the exact spot the
	# interaction placed it (possibly overlapping the object, via a collision exception the
	# interaction sets) and runs no movement, aim, knockback or push. Skipping move_and_slide /
	# _apply_pushes is what keeps a seated body from being ejected or shoving its neighbours.
	if _interaction.is_busy():
		move_input = Vector2.ZERO
		velocity = Vector2.ZERO
		_update_stamina(false, delta)
		_knockback = Vector2.ZERO  # Drop any pending shove so standing back up doesn't lurch.
		_hands.facing = facing
		pose.update(delta, facing, Vector2.ZERO, speed, _stances(), _hands.punch_amounts())
		return

	# Aim toward the aim point. Guard the degenerate zero-length case.
	var to_aim := aim_point - global_position
	if to_aim.length() > 0.001:
		facing = to_aim.normalized()
	# A parent's _physics_process runs before its children's, so the hands see this fresh
	# facing on the same frame.
	_hands.facing = facing

	_update_stamina(run_input and move_input.length() > CharacterConfig.run_min_input, delta)
	velocity = move_input * _move_speed() * _push_slow + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector2.ZERO, CharacterConfig.push_knockback_friction * delta)
	_push_slow = _ease_push_slow(_apply_pushes(), delta)
	# Before the children's _physics_process, so the hands build on this frame's pose.
	pose.update(delta, facing, get_real_velocity(), speed, _stances(), _hands.punch_amounts())
	_footsteps.update(self, _footprints)


# --- Controller-facing API -------------------------------------------------------------

## Melee with the held item (F): runs its primary action. Ignored while locked in an interaction.
func melee() -> void:
	var item := current_item()
	if is_busy() or item == null:
		return
	item.primary(self)


## Shoot the held item (left-click): runs its secondary action. Ignored while locked in an interaction
## or running (the arms are down at the sides).
func shoot() -> void:
	var item := current_item()
	if is_busy() or item == null or _running:
		return
	item.secondary(self)


## Switch to inventory slot `slot`. Ignored while locked. Observers read the held item with
## current_item() (the debug HUD polls it).
func select_slot(slot: int) -> void:
	if is_busy():
		return
	if slot in _items and slot != _current_slot:
		_current_slot = slot


## Toggle an object interaction: start the best one in reach, or end the active one.
func try_interact() -> void:
	_interaction.try_interact()


## The reachable objects and their valid actions, for a controller that wants to choose
## deliberately (an AI). Each entry is `{ object, specs }`; empty when nothing is in reach.
func interactions_in_reach() -> Array:
	return _interaction.interactions_in_reach()


## Begin the action `id` on `object` if it is reachable and valid; true on success. Lets a
## controller pick both the object and the action, unlike the random `try_interact()`.
func interact_with(object: Node, id: String) -> bool:
	return _interaction.interact_with(object, id)


## End the active interaction, if any (explicit stop, vs the `try_interact()` toggle).
func end_interaction() -> void:
	_interaction.end_interaction()


## True while locked in an object interaction (sitting, lying, …).
func is_busy() -> bool:
	return _interaction.is_busy()


## The active interaction's HUD label, or "" when idle.
func interaction_label() -> String:
	return _interaction.active_label()


## True while moving at run speed (asked to run, moving, and not out of stamina).
func is_running() -> bool:
	return _running


## Stamina left, 0..1 of a full bar.
func stamina_fraction() -> float:
	return stamina


## Walking speed, or run speed while running.
func _move_speed() -> float:
	return speed * (CharacterConfig.run_speed_mult if _running else 1.0)


## Settle this frame's running and spend or regain stamina. Running dry latches `_exhausted`,
## which holds until stamina refills to `run_resume_fraction`.
func _update_stamina(wants_run: bool, delta: float) -> void:
	_running = wants_run and not _exhausted and stamina > 0.0
	if _running:
		stamina = maxf(stamina - delta / CharacterConfig.run_stamina_seconds, 0.0)
		if stamina <= 0.0:
			_exhausted = true
			_running = false
	else:
		stamina = minf(stamina + delta * CharacterConfig.stamina_regen_per_sec, 1.0)
		if _exhausted and stamina >= CharacterConfig.run_resume_fraction:
			_exhausted = false


## A punch landed: surface it as hit_landed and post a world `&"hit"` event (like a projectile's)
## so listeners such as the AI learn who struck whom.
func _on_punched(hand: int, body: Node, damage: float) -> void:
	hit_landed.emit(body, damage, hand)
	var pos: Vector2 = body.global_position if body is Node2D else global_position
	EventBus.post(&"hit", {
		"position": pos, "victim": body, "source": self, "attacker": self,
		"direction": facing, "damage": damage,
	})


# --- Item-facing API (what an Item may call on its user) --------------------------------

## The held item.
func current_item() -> Item:
	return _items.get(_current_slot)


## The held slot id (1–9).
func current_slot() -> int:
	return _current_slot


## The held item's display name, or "Unknown" with none held. For UI observers, so they
## never need to read Item's fields directly.
func item_name() -> String:
	var item := current_item()
	return item.display_name if item else "Unknown"


## The held item's reach, or 0.0 with none held. For UI observers.
func item_reach() -> float:
	var item := current_item()
	return item.reach if item else 0.0


## Whether inventory slot `id` is present (carried, not necessarily held). Gates interactions
## that require an item.
func has_item(id: int) -> bool:
	return _items.has(id)


## True while a punch swing is in progress.
func is_attacking() -> bool:
	return _hands.is_attacking()


## Recoil: throw `hand` back and twist the shoulders, as a fired weapon does (the item calls it).
func kick(hand: int) -> void:
	pose.kick(hand)


## The drawn direction of a held weapon: it trails the aim a little as the character turns. Visual
## only — shots still leave along `facing`.
func weapon_facing() -> Vector2:
	return Vector2.from_angle(pose.weapon_angle)


## How each hand is held (CharacterConfig.stances names), as the held item asks: arms hang with
## nothing held. Running puts both arms down at the sides whatever is held.
func _stances() -> Array:
	if _running:
		return [&"run", &"run"]
	var item: Item = current_item()
	if item == null:
		return [&"relaxed", &"relaxed"]
	return [item.hand_stance(0), item.hand_stance(1)]


## Throw a punch with the given hand (the item decides which).
func punch(hand: int) -> void:
	_hands.punch(hand)


## Local-space center of a hand (0 left, 1 right).
func hand_position(hand: int) -> Vector2:
	return _hands.hand_position(hand)


## World-space center of a hand (the character is never rotated, so world = origin + local).
func hand_world(hand: int) -> Vector2:
	return global_position + _hands.hand_position(hand)


## World muzzle point for a weapon in `hand` (CharacterConfig.muzzle_ahead past it, along the aim).
func muzzle_origin(hand: int) -> Vector2:
	return hand_world(hand) + facing * CharacterConfig.muzzle_ahead


## The standing skeleton as it is held right now (see character_rig.gd), for the visuals and anything
## that wants the arms' and legs' joints.
func rig() -> CharacterRig:
	return CharacterRig.new(self)


## The scene node transient projectiles/casings/debris spawn into (world space, not under us).
func world_root() -> Node:
	return get_parent()


## An item forwards a projectile hit here so the character can surface it (HUD).
func report_shot(body: Node, damage: float) -> void:
	hit_landed.emit(body, damage, -1)


# --- Hittable contract (struck by projectiles: flesh surface + deformation) -------------

## The character's ballistic surface: partial cover, low penetration, flesh material and a
## base color for debris styling. Read by the Projectile System.
func get_surface() -> Dictionary:
	return {
		"coverage": CharacterConfig.flesh_coverage,
		"penetration": CharacterConfig.flesh_penetration,
		"material": CharacterConfig.flesh_material,
		"color": CharacterConfig.flesh_color,
	}


## Take a hit: shove along the impact (folded into locomotion via the pushable path),
## record the deformation relative to the shoulders (it dents the drawn body and hands and turns
## with them), spray blood debris, and start bleeding: a splatter spray now, then drips every few
## seconds (BloodWound). The striker fills in a HitInfo.
func take_hit(hit: HitInfo) -> void:
	apply_impulse(Physics.impact_impulse(hit))
	_deformable.record(hit, pose.torso_angle)
	Physics.spawn_debris(get_parent(), hit, get_surface())
	_wound.record(hit)
	_apply_damage(hit.damage, hit.direction)


## Reduce health by `amount`; called by the punch path (projectile path goes through take_hit).
func take_damage(amount: float) -> void:
	_apply_damage(amount)


## Apply `amount` of damage to health (shared by the punch and projectile paths), dying at zero;
## `direction` is the blow's (zero when unknown), which the body falls along.
func _apply_damage(amount: float, direction := Vector2.ZERO) -> void:
	if is_dead:
		return
	health = maxf(health - amount, 0.0)
	if health == 0.0:
		_die(direction)


## Mark the character dead and let the body fall: the ragdoll takes over from the live pose with the
## momentum it had (walk + any shove, including the killing blow's), toppling along `direction`, and
## the hand lets go of what it held. Emits `died` for observers.
func _die(direction: Vector2) -> void:
	is_dead = true
	_wound.stop()
	# A corpse is just a body on the floor: clear its collision layer so the living (and bullets,
	# punches, sight lines and the dropped item, all on layer 1) pass right over it instead of being
	# blocked, and draw it beneath them.
	collision_layer = 0
	z_index = CharacterConfig.ragdoll_z_index
	end_interaction()
	var momentum := move_input * _move_speed() * _push_slow + _knockback
	ragdoll = CharacterRagdoll.new(self, momentum, direction)
	_drop_item(momentum)
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	died.emit()


## Let go of the held item: it flies off with the body's `momentum` plus a toss, and leaves the
## inventory if it left something behind in the world.
func _drop_item(momentum: Vector2) -> void:
	var item := current_item()
	if item == null:
		return
	var toss := Vector2.from_angle(randf() * TAU) * CharacterConfig.ragdoll_drop_toss * randf_range(0.5, 1.0)
	if item.drop(self, momentum + toss):
		_items.erase(_current_slot)


## Where this body's blood leaves it (world): its position while alive; once fallen, the middle of
## the trunk where it lies. Blood pools sample it, so they spill from the body, not where it stood.
func blood_origin() -> Vector2:
	if ragdoll == null:
		return global_position
	var mid: Vector3 = (ragdoll.point(CharacterRagdoll.CHEST) + ragdoll.point(CharacterRagdoll.PELVIS)) * 0.5
	return global_position + Vector2(mid.x, mid.y)


## Total accumulated hit damage this character has taken, read from its deformation record. Lets a
## controller sense how hurt the character is (0 when unscathed).
func damage_taken() -> float:
	return _deformable.damage_total if _deformable else 0.0


# --- Pushable contract (shoved by Knockback transfers and other walking characters) -----

## Take a shove; divided by mass and folded into locomotion.
func apply_impulse(impulse: Vector2) -> void:
	_knockback += impulse / maxf(CharacterConfig.player_mass, 0.5)


## The character's mass, used by pushers to scale their shove.
func get_mass() -> float:
	return maxf(CharacterConfig.player_mass, 0.5)


# --- Walking-push (shove furniture the body slid against; be slowed by it) --------------

## Shove every pushable body the character slid into this frame; return the resulting speed
## multiplier (heavier furniture slows the character more, floored so it never fully locks).
func _apply_pushes() -> float:
	var input_strength := move_input.length()
	if input_strength <= 0.0:
		return 1.0

	var heaviest := 0.0
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null or not collider.has_method("apply_impulse"):
			continue
		# The normal points back toward the character, so "into the object" is -normal.
		var dir := -collision.get_normal()
		var impulse := CharacterConfig.push_impulse * input_strength * get_physics_process_delta_time()
		# Carry the object along rather than launch it: never drive it faster than we walk.
		if collider.has_method("get_mass") and "linear_velocity" in collider:
			var along: float = collider.linear_velocity.dot(dir)
			var gap := maxf(move_input.dot(dir) * _move_speed() * CharacterConfig.push_carry_factor - along, 0.0)
			impulse = minf(impulse, gap * collider.get_mass())
		collider.apply_impulse(dir * impulse)
		if collider.has_method("get_mass"):
			heaviest = maxf(heaviest, collider.get_mass())

	if heaviest <= 0.0:
		return 1.0
	return clampf(1.0 - heaviest * CharacterConfig.push_slow_per_weight, CharacterConfig.push_slow_min, 1.0)


## Slow down at once on contact, but recover toward full speed gradually so losing contact for a
## frame doesn't snap the speed back.
func _ease_push_slow(target: float, delta: float) -> float:
	if target <= _push_slow:
		return target
	return minf(target, _push_slow + CharacterConfig.push_slow_release * delta)


## First child that can drive this character (has a `control` method).
func _find_controller() -> Node:
	for child in get_children():
		if child.has_method("control"):
			return child
	return null
