extends CharacterBody2D

## A generic top-down character. It owns the body, movement, aim-based "facing", the item
## inventory, and the knockback it takes from shoves. It reads its intent from a pluggable
## controller child (any node with a `control(character, delta)` method): the controller
## writes `move_input` / `aim_point` and calls `melee/shoot/select_slot`. Drawing
## is in character_visuals.gd, the hand/punch/fist geometry in character_hands.gd.

## Radius of the placeholder circle. Matches chair size (28x28 → 14 radius).
@export var radius: float = 14.0  ## Body circle radius (px).
@export var speed: float = 300.0  ## Move speed (px/s).
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

## Intent, written each frame by the controller.
var move_input := Vector2.ZERO   ## Desired move direction (already 0–1 length).
var aim_point := Vector2.ZERO    ## World point to face.

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
## The blood pool this character is currently bleeding into; hits accumulate here while it stands on
## the pool, and a new one starts once it moves off. Goes invalid when the pool is despawned.
var _blood_pool: Node

## Emitted when a held item lands a hit on a body. `hand` is 0/1 for a melee punch, -1 for a
## shot; `damage` is the amount dealt (a punch scales it by its range of motion). Melee vs shot
## is told apart by `hand`, not by the damage value.
signal hit_landed(body: Node, damage: float, hand: int)
## Re-emitted from the interaction component: true + label when an interaction starts, false + ""
## when it ends. For the HUD; the character itself stays unaware of what an interaction means.
signal interaction_changed(active: bool, label: String)

## Interaction component (Interaction domain): finds and runs object interactions. Composed in
## code like the other components; the character only forwards `try_interact()` and reads
## `is_busy()` / `interaction_label()`.
const CharacterInteraction = preload("res://scenes/interaction/character_interaction.gd")

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _hands := $Hands
@onready var _controller := _find_controller()
var _interaction: Node  ## The CharacterInteraction child, built in _ready().


func _ready() -> void:
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

	# Compose the interaction component and surface its state change as our own signal.
	_interaction = CharacterInteraction.new()
	add_child(_interaction)
	_interaction.interaction_changed.connect(func(active: bool, label: String) -> void: interaction_changed.emit(active, label))


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
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
		_knockback = Vector2.ZERO  # Drop any pending shove so standing back up doesn't lurch.
		_hands.facing = facing
		return

	# Aim toward the aim point. Guard the degenerate zero-length case.
	var to_aim := aim_point - global_position
	if to_aim.length() > 0.001:
		facing = to_aim.normalized()
	# A parent's _physics_process runs before its children's, so the hands see this fresh
	# facing on the same frame.
	_hands.facing = facing

	velocity = move_input * speed * _push_slow + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector2.ZERO, CharacterConfig.push_knockback_friction * delta)
	_push_slow = _apply_pushes()


# --- Controller-facing API -------------------------------------------------------------

## Melee with the held item (F): runs its primary action. Ignored while locked in an interaction.
func melee() -> void:
	if is_busy():
		return
	current_item().primary(self)


## Shoot the held item (left-click): runs its secondary action. Ignored while locked in an interaction.
func shoot() -> void:
	if is_busy():
		return
	current_item().secondary(self)


## Switch to inventory slot `slot`. Ignored while locked. The held item is read on demand via
## current_item() (the debug HUD polls it), so no change signal is emitted.
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


## Whether inventory slot `id` is present (carried, not necessarily held). Gates interactions
## that require an item.
func has_item(id: int) -> bool:
	return _items.has(id)


## True while a punch swing is in progress.
func is_attacking() -> bool:
	return _hands.is_attacking()


## Throw a punch with the given hand (the item decides which).
func punch(hand: int) -> void:
	_hands.punch(hand)


## Local-space center of a hand (0 left, 1 right).
func hand_position(hand: int) -> Vector2:
	return _hands.hand_position(hand)


## World-space center of a hand (the character is never rotated, so world = origin + local).
func hand_world(hand: int) -> Vector2:
	return global_position + _hands.hand_position(hand)


## World muzzle point for a weapon in `hand` (the drawn barrel tip, +clearance).
func muzzle_origin(hand: int) -> Vector2:
	return hand_world(hand) + facing * 26.0


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
## record the deformation (dents the drawn silhouette), spray blood debris, and feed a blood
## pool on the floor. The striker fills in a HitInfo. Each hit accumulates into `_blood_pool` while
## this body stands on it (pooling out wider), starting a new pool once it moves off. The pool
## excludes this body's collider so the blood spreading out of the wound is not trapped inside it.
func take_hit(hit: HitInfo) -> void:
	apply_impulse(Physics.impact_impulse(hit))
	_deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())
	_blood_pool = Physics.spawn_blood(get_parent(), hit, [get_rid()], self, _blood_pool)
	_apply_damage(hit.damage)


## Reduce health by `amount`; called by the punch path (projectile path goes through take_hit).
func take_damage(amount: float) -> void:
	_apply_damage(amount)


## Apply `amount` of damage to health (shared by the punch and projectile paths), dying at zero.
func _apply_damage(amount: float) -> void:
	if is_dead:
		return
	health = maxf(health - amount, 0.0)
	if health == 0.0:
		_die()


## Mark the character dead and halt its motion, emitting `died` for observers.
func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	# A corpse is just a body on the floor: clear its collision layer so the living (and bullets,
	# punches and sight lines, all on layer 1) pass right over it instead of being blocked.
	collision_layer = 0
	died.emit()


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
		collider.apply_impulse(-collision.get_normal() * CharacterConfig.push_impulse * input_strength)
		if collider.has_method("get_mass"):
			heaviest = maxf(heaviest, collider.get_mass())

	if heaviest <= 0.0:
		return 1.0
	return clampf(1.0 - heaviest * CharacterConfig.push_slow_per_weight, CharacterConfig.push_slow_min, 1.0)


## First child that can drive this character (has a `control` method).
func _find_controller() -> Node:
	for child in get_children():
		if child.has_method("control"):
			return child
	return null
