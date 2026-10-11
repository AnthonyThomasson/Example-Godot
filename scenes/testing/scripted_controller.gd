extends Node

## Testing domain: a puppet controller — a character's `control(character, delta)` child (interface 7)
## driven by a test instead of a human or an AI. Commands are queued here and carried out on the
## character's own frame, through only the published controller API (`move_input`, `aim_point`,
## `run_input`, `melee`, `shoot`, `select_slot`, `interact_with`, `end_interaction`).
##
## Commands return at once; wait on their effect through the TestContext, e.g.
## `p.walk_to(spot)` then `await t.until(p.has_arrived, 3.0, "never arrived")`.

## How close (px) to a `walk_to` target counts as arrived.
@export var arrive_distance := 6.0

var _character: Node = null
## What to face: a Node2D (followed live), a Vector2 world point, or null (keep the last aim).
var _aim: Variant = null
## Walking target (world), or null.
var _walk_target: Variant = null
## Steady move direction (used when no walk target), 0–1 length.
var _move_dir := Vector2.ZERO
## Whether the puppet holds run.
var _run := false
## Whether the puppet holds the trigger: an automatic gun keeps firing, a semi-auto one fires once per `shoot()`.
var _firing := false
## Actions waiting for the character's next frame: Callables taking the character.
var _pending: Array[Callable] = []
## Interactions started on the character's frame that reported failure (object, id) — for tests to read.
var failed_interactions: Array = []


## Called by the character at the top of its physics frame.
func control(character, _delta: float) -> void:
	_character = character
	if _aim is Node2D and is_instance_valid(_aim):
		character.aim_point = (_aim as Node2D).global_position
	elif _aim is Vector2:
		character.aim_point = _aim
	if _walk_target is Vector2:
		var to: Vector2 = _walk_target - character.global_position
		if to.length() <= arrive_distance:
			_walk_target = null
			character.move_input = Vector2.ZERO
		else:
			character.move_input = to.normalized()
	else:
		character.move_input = _move_dir
	character.run_input = _run
	if _firing and character.is_automatic():
		character.shoot()
	var actions := _pending.duplicate()
	_pending.clear()
	for action in actions:
		action.call(character)


## Face a Node2D (tracked) or a world point.
func aim_at(target: Variant) -> void:
	_aim = target


## Walk straight to a world point (no pathfinding); `has_arrived()` turns true there.
func walk_to(point: Vector2) -> void:
	_walk_target = point


## Walk steadily along `direction` (normalized; zero stops).
func walk(direction: Vector2) -> void:
	_walk_target = null
	_move_dir = direction.limit_length(1.0)


## Hold (or release) run; it takes effect while the puppet moves.
func set_run(on: bool) -> void:
	_run = on


## Stop walking.
func stop() -> void:
	_walk_target = null
	_move_dir = Vector2.ZERO


## True once a `walk_to` target has been reached (or none is set).
func has_arrived() -> bool:
	return _walk_target == null


## Switch to inventory slot `slot` (1 unarmed, 2 fists, 3 pistol, 4 key, 5 SMG, 6 assault rifle).
func select_slot(slot: int) -> void:
	_pending.append(func(c): c.select_slot(slot))


## Use the held item's primary action (F: punch / jab).
func punch() -> void:
	_pending.append(func(c): c.melee())


## Use the held item's secondary action once (a click of LMB: fire a round).
func shoot() -> void:
	_pending.append(func(c): c.shoot())


## Hold (or release) the trigger: while held, an automatic gun fires every frame its fire rate allows. A
## semi-automatic gun is unaffected (it needs a `shoot()` per round).
func hold_fire(on: bool) -> void:
	_firing = on


## Reload the held item (R): swap in the fullest carried magazine.
func reload() -> void:
	_pending.append(func(c): c.reload())


## Start interaction `id` on `object`; a refusal is recorded in `failed_interactions`.
func interact(object: Node, id: String) -> void:
	_pending.append(func(c):
		if not c.interact_with(object, id):
			failed_interactions.append([object, id]))


## End the active interaction.
func end_interaction() -> void:
	_pending.append(func(c): c.end_interaction())
