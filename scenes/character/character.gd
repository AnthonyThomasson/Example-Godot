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
## Rounds the starting gun is loaded with (negative = a full magazine).
@export var start_rounds: int = -1
## The spare magazines carried, as `MagazineConfig.types` ids (several of a kind are fine): two for each gun.
@export var spare_magazine_types: Array = [&"standard", &"standard", &"smg_standard", &"smg_standard",
	&"rifle_standard", &"rifle_standard"]
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
var _rig_cache: CharacterRig = null  ## The standing rig solved for `_rig_frame` (see `rig()`).
var _rig_frame := -1  ## The physics frame `_rig_cache` was solved in.
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

## The body's height: a `CharacterConfig.postures` key (`stand` or `crouch`). A crouch is a
## smaller target and slower; only a standing character can run. Set through `set_posture()`.
var _posture: StringName = &"stand"
## Seconds until the posture may change again (`CharacterConfig.posture_change_time` after each change).
var _posture_cooldown := 0.0
## What the body is drawn at, easing toward the posture: its height as a share of a standing one (1 = standing,
## down to the crouch row's).
var _posture_height := 1.0

## Inventory (slot id -> Item) and the currently held slot.
var _items := {}
var _current_slot := 1  ## Held inventory slot.
## Spare magazines carried (Magazine). They are not inventory slots: none can be held or selected.
var _magazines: Array = []
## The item being reloaded (null = not reloading) and the seconds left until it is done.
var _reloading_item: Item
var _reload_left := 0.0
## The held weapon's barrel is against a wall or object (only a weapon that `raises_at_contact`): it is held
## pointing up and cannot shoot. Set at once; `_raise` eases toward it (0 = held to the aim .. 1 = fully up).
var _blocked := false
var _raise := 0.0  ## How far the held weapon is raised off the aim, 0..1, easing toward `_blocked`.

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
var _legs := CharacterLegs.new()  ## Rests the legs against walls and furniture and shoves light pieces (see character_legs.gd).

## Emitted when a held item lands a hit on a body. `hand` is 0/1 for a melee punch, -1 for a
## shot; `damage` is the amount dealt (a punch scales it by its range of motion). Melee vs shot
## is told apart by `hand`, not by the damage value.
signal hit_landed(body: Node, damage: float, hand: int)

## Interaction component (Interaction domain): finds and runs object interactions. Composed in
## code like the other components; the character only forwards `try_interact()` and reads
## `is_busy()` / `interaction_label()`.
const CharacterInteraction = preload("res://scenes/interaction/character_interaction.gd")
const CharacterPose = preload("res://scenes/character/body/character_pose.gd")
const CharacterRig = preload("res://scenes/character/body/character_rig.gd")
const CharacterRagdoll = preload("res://scenes/character/body/character_ragdoll.gd")
const CharacterFootsteps = preload("res://scenes/character/character_footsteps.gd")
const CharacterLegs = preload("res://scenes/character/body/character_legs.gd")

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

	_items = ItemRegistry.default_inventory(start_rounds)
	_magazines = ItemRegistry.create_magazines(spare_magazine_types)
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

	_posture_cooldown = maxf(_posture_cooldown - delta, 0.0)
	_ease_posture(delta)
	# Items keep their own clocks (a gun's time between rounds); tick them before the controller pulls the
	# trigger, so a round that is due this frame can leave this frame.
	for item: Item in _items.values():
		item.tick(delta)
	# Pull intent from the controller first, so facing/movement use this frame's input.
	if _controller:
		_controller.control(self, delta)
	_update_reload(delta)

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
		_legs.clear()
		pose.update(delta, facing, Vector2.ZERO, speed, _stances(), _hands.punch_amounts())
		return

	# Aim toward the aim point. Guard the degenerate zero-length case.
	var to_aim := aim_point - global_position
	if to_aim.length() > 0.001:
		facing = _turned_toward(to_aim.normalized(), delta)
	# A parent's _physics_process runs before its children's, so the hands see this fresh
	# facing on the same frame.
	_hands.facing = facing
	_update_weapon_raise(delta)

	_update_stamina(run_input and _posture == &"stand" and move_input.length() > CharacterConfig.run_min_input, delta)
	velocity = move_input * _move_speed() * _push_slow + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector2.ZERO, CharacterConfig.push_knockback_friction * delta)
	_push_slow = _ease_push_slow(_apply_pushes(), delta)
	# Before the children's _physics_process, so the hands build on this frame's pose.
	pose.update(delta, facing, get_real_velocity(), speed, _stances(), _hands.punch_amounts())
	_legs.update(self, delta)
	_footsteps.update(self, _footprints)


# --- Controller-facing API -------------------------------------------------------------

## Melee with the held item (F): runs its primary action. Ignored while locked in an interaction.
func melee() -> void:
	var item := current_item()
	if is_busy() or item == null:
		return
	item.primary(self)


## Shoot the held item (left-click): runs its secondary action; true when a round left the barrel. Ignored
## while locked in an interaction, running (the arms are down at the sides), reloading, or with the weapon's
## barrel against a wall or object (`weapon_blocked()`). A gun also holds back between rounds, per its fire rate.
func shoot() -> bool:
	var item := current_item()
	if is_busy() or item == null or _running or is_reloading():
		return false
	# Judge the barrel now rather than trusting the last frame's verdict: a controller acts before this frame's
	# check runs, and on a character's very first frame none has run at all, so a long gun fired point-blank
	# into a wall would leave through it.
	_update_weapon_raise(0.0)
	if _blocked:
		return false
	return item.secondary(self)


## Reload the held item (R): start swapping in the fullest carried magazine, which takes
## the item's `reload_time()`. Ignored when dead, locked in an interaction, running, already
## reloading, or when no carried magazine would add rounds. Switching items, running or an interaction
## cancels it.
func reload() -> void:
	var item := current_item()
	if is_dead or is_busy() or _running or is_reloading() or item == null or not item.can_reload(self):
		return
	_reloading_item = item
	_reload_left = item.reload_time()
	item.reloading = true
	_post_reload(item, &"start")


## Switch to inventory slot `slot`. Ignored while locked. Observers read the held item with
## current_item() (the debug HUD polls it).
func select_slot(slot: int) -> void:
	if is_busy():
		return
	if slot in _items and slot != _current_slot:
		_cancel_reload()
		_current_slot = slot
		_rig_cache = null  # The weapon hand may change: the rig is solved afresh on the next read.
		_update_weapon_raise(0.0)  # Judged for the new item now, so a shot in this same frame can't slip past a wall.


## Toggle an object interaction: start the best one in reach, or end the active one. Starting one stands
## the character up (sitting or lying is its own posture).
func try_interact() -> void:
	_interaction.try_interact()
	_stand_if_busy()


## The reachable objects and their valid actions, for a controller that wants to choose
## deliberately (an AI). Each entry is `{ object, specs }`; empty when nothing is in reach.
func interactions_in_reach() -> Array:
	return _interaction.interactions_in_reach()


## Begin the action `id` on `object` if it is reachable and valid; true on success. Lets a
## controller pick both the object and the action, unlike the random `try_interact()`.
func interact_with(object: Node, id: String) -> bool:
	var began: bool = _interaction.interact_with(object, id)
	_stand_if_busy()
	return began


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


## Take a posture: `stand` or `crouch` (`CharacterConfig.postures`). True when the character is in it
## afterwards, so asking for the posture it already holds is a harmless `true`: a controller can write its wanted
## posture every frame. Refused (false) while dead, locked in an interaction, or within
## `CharacterConfig.posture_change_time` of the last change. A crouch is slower, a smaller target and cannot
## run.
func set_posture(wanted: StringName) -> bool:
	if wanted == _posture:
		return true
	if is_dead or is_busy() or _posture_cooldown > 0.0 or not CharacterConfig.postures.has(wanted):
		return false
	_posture = wanted
	_posture_cooldown = CharacterConfig.posture_change_time
	_rig_cache = null
	return true


## C: crouch, or stand back up from a crouch.
func toggle_crouch() -> void:
	set_posture(&"stand" if _posture == &"crouch" else &"crouch")


## The current posture: `stand` or `crouch`.
func posture() -> StringName:
	return _posture


## Whether the body is crouching.
func is_crouching() -> bool:
	return _posture == &"crouch"


## Where side `i`'s ankle rests (local x/y px) against a wall or piece of furniture its leg has met, or null when
## nothing is in its way. The rig draws the leg there (see character_legs.gd).
func foot_clamp(i: int) -> Variant:
	return _legs.ankle(i)


## What the body is drawn at right now, easing toward the posture: a standing body's height as a share (1 =
## standing .. the crouch row's). For the rig.
func posture_height() -> float:
	return _posture_height


## How folded the drawn body is, 0 (standing) .. 1 (crouched): the share the rig pitches the spine by.
func posture_folded() -> float:
	var crouch_height: float = CharacterConfig.postures[&"crouch"]["height"]
	return clampf((1.0 - _posture_height) / maxf(1.0 - crouch_height, 0.01), 0.0, 1.0)


## How far further ahead (px) the hands are held at this posture: a crouch holds them out past its forward-leaning
## chest.
func posture_hand_ahead() -> float:
	return CharacterConfig.body_crouch_hand_ahead * posture_folded()


## True while a reload is in progress.
func is_reloading() -> bool:
	return _reloading_item != null


## True while the held item keeps firing as long as the trigger is held (an automatic gun): a controller
## re-presses `shoot()` every frame instead of once per click.
func is_automatic() -> bool:
	var item := current_item()
	return item != null and item.is_automatic()


## True while the held weapon's barrel is against a wall or object: it is held pointing up and `shoot()` does
## nothing until the character backs off. Only a weapon that `raises_at_contact()` is ever blocked.
func weapon_blocked() -> bool:
	return _blocked


## How far the held weapon is raised off the aim, 0 (held to the aim) .. 1 (fully up), easing toward the
## blocked state. For the weapon's art.
func weapon_raise() -> float:
	return _raise


## The inventory slot of the gun this character fights with: the held item when it takes ammo, else the lowest
## slot holding something that does; -1 with none.
func gun_slot() -> int:
	var held := current_item()
	if held != null and held.ammo_capacity() >= 0:
		return _current_slot
	var best := -1
	for slot: int in _items:
		if _items[slot].ammo_capacity() >= 0 and (best < 0 or slot < best):
			best = slot
	return best


## Carry only the items in `slots` (see `ItemRegistry`), holding `hold_slot`, with the spare magazines named by
## `spare_types` (`MagazineConfig.types` ids): how a spawner arms a character with its gun. Starts every gun
## loaded as `start_rounds` says (in `loaded_magazine` when that type fits the gun, else the gun's own); a reload
## in progress is dropped. Safe after `add_child`, so a spawner can re-arm a scene-placed character.
func set_loadout(slots: Array, hold_slot: int, spare_types: Array, loaded_magazine: StringName = &"") -> void:
	_cancel_reload()
	_items = ItemRegistry.inventory_for(slots, start_rounds, loaded_magazine)
	_magazines = ItemRegistry.create_magazines(spare_types)
	_current_slot = hold_slot if hold_slot in _items else (_items.keys()[0] if not _items.is_empty() else hold_slot)
	_raise = 0.0
	_update_weapon_raise(0.0)


## Rounds loaded in the item in `slot` (the held one by default), or -1 if it has no ammo.
func ammo(slot := -1) -> int:
	var item := _item_in(slot)
	return item.rounds_loaded() if item else -1


## Rounds a full load of the item in `slot` (the held one by default) holds, or -1 if it has no ammo.
func ammo_capacity(slot := -1) -> int:
	var item := _item_in(slot)
	return item.ammo_capacity() if item else -1


## Whether a reload of the item in `slot` (the held one by default) would add rounds right now.
func can_reload(slot := -1) -> bool:
	var item := _item_in(slot)
	return item != null and not is_reloading() and item.can_reload(self)


## How many spare magazines are carried.
func spare_magazines() -> int:
	return _magazines.size()


## The carried magazine for `gun` holding the most rounds (null with none); it stays carried.
func best_magazine(gun: StringName) -> Magazine:
	var best: Magazine = null
	for mag: Magazine in _magazines:
		if mag.gun == gun and (best == null or mag.rounds > best.rounds):
			best = mag
	return best


## Take `best_magazine(gun)` out of the carried store (null with none): an item loading it.
func take_magazine(gun: StringName) -> Magazine:
	var mag := best_magazine(gun)
	if mag != null:
		_magazines.erase(mag)
	return mag


## Carry `mag` (a magazine an item has taken out of a gun).
func stow_magazine(mag: Magazine) -> void:
	_magazines.append(mag)


## The item in inventory slot `slot`; the held item for a negative slot.
func _item_in(slot: int) -> Item:
	return current_item() if slot < 0 else _items.get(slot)


## Count a reload down; it is dropped if its item is no longer held, the character is locked in an
## interaction or runs. Done: the item swaps its magazine.
func _update_reload(delta: float) -> void:
	if _reloading_item == null:
		return
	if is_busy() or _running or current_item() != _reloading_item:
		_cancel_reload()
		return
	_reload_left -= delta
	if _reload_left > 0.0:
		return
	var item := _reloading_item
	_cancel_reload()
	item.finish_reload(self)
	_post_reload(item, &"done")


## Tell the world a reload began (`stage` &"start": the magazine comes out) or finished (&"done": the new one is seated)
## by `item`, from the weapon hand (the Audio domain voices it; a cancelled reload never posts "done").
func _post_reload(item: Item, stage: StringName) -> void:
	EventBus.post(&"reload", {
		"position": hand_world(item.weapon_hand()), "gun": item.gun_id(), "stage": stage, "power": item.round_power(),
		"character": self,
	})


## Stop any reload in progress and clear the item's `reloading` flag.
func _cancel_reload() -> void:
	if _reloading_item != null:
		_reloading_item.reloading = false
	_reloading_item = null


## Judge whether the held weapon's barrel touches a wall or object, and ease the raise toward it. Only a weapon
## that `raises_at_contact()` is ever blocked. The barrel is a ray from beside the body centre along the aim, as
## far as the weapon reaches held normally (never as raised, or pulling it up would clear it and drop it again);
## it blocks when something solid is within that reach, and stays blocked until there is
## `CharacterConfig.weapon_contact_margin` of clearance, so the weapon does not flicker at the edge.
func _update_weapon_raise(delta: float) -> void:
	var item := current_item()
	if item == null or not item.raises_at_contact():
		_blocked = false
	else:
		var hand := item.weapon_hand()
		var stance: Dictionary = CharacterConfig.stances.get(item.hand_stance(hand), CharacterConfig.stances[&"relaxed"])
		var reach: float = float(stance["forward"]) + posture_hand_ahead() + _muzzle_ahead(item)
		var lateral: float = float(stance["lateral"]) * (-1.0 if hand == 0 else 1.0)
		var from := global_position + facing.orthogonal() * lateral
		var margin := 0.0 if not _blocked else CharacterConfig.weapon_contact_margin
		_blocked = _hands.solid_distance(from, facing, reach + margin + 1.0) < reach + margin
	_raise = move_toward(_raise, 1.0 if _blocked else 0.0, CharacterConfig.weapon_raise_speed * delta)


## Walking speed (slower in a lower posture), or run speed while running (only possible standing).
func _move_speed() -> float:
	return speed * float(CharacterConfig.postures[_posture]["speed"]) * (CharacterConfig.run_speed_mult if _running else 1.0)


## `facing` turned toward the unit vector `want`: at once standing, but no faster than the posture's `turn` rate
## (rad/s) crouched, so a low body takes longer to come round. The aim point itself is never held back.
func _turned_toward(want: Vector2, delta: float) -> Vector2:
	var rate: float = CharacterConfig.postures[_posture]["turn"]
	if rate <= 0.0:
		return want
	var step := rate * delta
	return facing.rotated(clampf(facing.angle_to(want), -step, step)).normalized()


## Ease the drawn body toward the posture (it snaps the last hair, so a settled body stops changing).
func _ease_posture(delta: float) -> void:
	var k := 1.0 - exp(-CharacterConfig.posture_ease * delta)
	_posture_height = _eased_to(_posture_height, float(CharacterConfig.postures[_posture]["height"]), k)


## `now` moved a fraction `k` of the way to `target`, snapped onto it once within a hair of it.
static func _eased_to(now: float, target: float, k: float) -> float:
	var next := lerpf(now, target, k)
	return target if absf(next - target) < 0.002 else next


## An interaction began: stand up for it, whatever the posture was (no cooldown, it is not a controller's choice).
func _stand_if_busy() -> void:
	if is_busy():
		_posture = &"stand"


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
## so listeners such as the AI learn who struck whom. The event is a `punch` outcome on the struck `material`
## (what its surface reports; "" for a wall or anything without one).
func _on_punched(hand: int, body: Node, damage: float) -> void:
	hit_landed.emit(body, damage, hand)
	var pos: Vector2 = body.global_position if body is Node2D else global_position
	var surface_material := ""
	if body.has_method("get_surface"):
		surface_material = String(body.get_surface().get("material", ""))
	EventBus.post(&"hit", {
		"position": pos, "victim": body, "source": self, "attacker": self,
		"direction": facing, "damage": damage, "outcome": &"punch", "material": surface_material,
	})


# --- Item-facing API (what an Item may call on its user) --------------------------------

## The held item.
func current_item() -> Item:
	return _items.get(_current_slot)


## The held slot id (1–9).
func current_slot() -> int:
	return _current_slot


## The display name of the item in `slot` (the held item by default), or "Unknown" with none there. For UI
## observers and the AI's wording, so they never need to read Item's fields directly.
func item_name(slot := -1) -> String:
	var item := _item_in(slot)
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


## Recoil: throw `hand` back and twist the shoulders, as a fired weapon does (the item calls it);
## `strength` scales it (1 = a pistol's), so a light automatic's stream of rounds does not pile up.
func kick(hand: int, strength := 1.0) -> void:
	pose.kick(hand, strength)


## The drawn direction of a held weapon: it trails the aim a little as the character turns. Visual
## only — shots still leave along `facing`.
func weapon_facing() -> Vector2:
	return Vector2.from_angle(pose.weapon_angle)


## How each hand is held (CharacterConfig.stances names), as the held item asks: arms hang with
## nothing held. Running puts both arms down at the sides whatever is held; a weapon whose barrel is against
## a wall or object is held raised, as the item says.
func _stances() -> Array:
	if _running:
		return [&"run", &"run"]
	var item: Item = current_item()
	if item == null:
		return [&"relaxed", &"relaxed"]
	if _blocked:
		return [item.raised_stance(0), item.raised_stance(1)]
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


## World muzzle point for a weapon in `hand`: the held item's `muzzle_ahead()` past it (a long gun reaches
## further than a pistol), along the aim.
func muzzle_origin(hand: int) -> Vector2:
	return hand_world(hand) + facing * _muzzle_ahead(current_item())


## How far past the weapon hand `item`'s muzzle is: its own `muzzle_ahead()`, or `CharacterConfig.muzzle_ahead`
## for an item that gives none (or no item).
func _muzzle_ahead(item: Item) -> float:
	var ahead := item.muzzle_ahead() if item != null else -1.0
	return ahead if ahead >= 0.0 else CharacterConfig.muzzle_ahead


## The standing skeleton as it is held right now (see character_rig.gd), for the visuals and anything
## that wants the arms' and legs' joints. Solved once per physics frame and shared: the pose, the hands and the feet's
## rests change only in `_physics_process`, so every caller in the same frame (the draw, a footfall, a test) gets the one solve.
func rig() -> CharacterRig:
	var frame := Engine.get_physics_frames()
	if _rig_cache == null or _rig_frame != frame:
		_rig_cache = CharacterRig.new(self)
		_rig_frame = frame
	return _rig_cache


## The scene node transient projectiles/casings/debris spawn into (world space, not under us).
func world_root() -> Node:
	return get_parent()


## An item forwards a projectile hit here so the character can surface it (HUD).
func report_shot(body: Node, damage: float) -> void:
	hit_landed.emit(body, damage, -1)


# --- Hittable contract (struck by projectiles: flesh surface + deformation) -------------

## The character's ballistic surface: partial cover (the body's height, so a lower posture is struck by fewer
## shots and hides behind lower cover), low penetration, flesh material and a base color for debris styling.
## Read by the Projectile System.
func get_surface() -> Dictionary:
	return {
		"coverage": CharacterConfig.postures[_posture]["coverage"],
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
	_rig_cache = null
	_cancel_reload()
	_wound.stop()
	# A corpse is just a body on the floor: clear its collision layer so the living (and bullets,
	# punches, sight lines and the dropped item, all on layer 1) pass right over it instead of being
	# blocked, and draw it beneath them.
	collision_layer = 0
	z_index = CharacterConfig.ragdoll_z_index
	end_interaction()
	var momentum := move_input * _move_speed() * _push_slow + _knockback
	# The body falls from the standing skeleton, whatever it was doing.
	_posture = &"stand"
	_posture_height = 1.0
	_legs.clear()
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
