extends Node2D

## Character INTERACTION layer. Owns object interactions end to end: on a request it finds the
## reachable objects that advertise interactions (their `get_interactions()`), keeps only the
## actions whose item gate passes, targets the object nearest the mouse, and starts a random one
## of that object's valid actions — freezing the character in place until the next request ends
## it and returns the character to where it started. A `move_to` action additionally snaps the
## character onto the object and lets the two bodies overlap (a temporary collision exception, so
## sitting/lying puts the character ON the object without either ejecting or shoving the other);
## actions without `move_to` act in place. The character forwards `try_interact()` (the player's
## random toggle) plus `interactions_in_reach()` / `interact_with(object, id)` / `end_interaction()`
## (a controller picking a specific object + action), and reads `is_busy()` / `active_label()`;
## it never learns what an interaction means, so this system can be iterated on its own.

## How far from the body center (px) an object may be and still be reachable.
@export var reach: float = 46.0
## Bias the reach circle this far ahead of the character along its facing (0 = centered on body).
@export var front_offset: float = 0.0

## Physics layer the reach query tests (General's `PhysicsLayers.SOLID` — walls + solid furniture).
const QUERY_MASK := PhysicsLayers.SOLID
## Extra gap (px) required around the body before an object's collision is re-enabled on exit.
const CLEAR_MARGIN := 3.0

## Emitted when an interaction starts (true + its label) or ends (false + ""), for the HUD.
signal interaction_changed(active: bool, label: String)

var _active: Dictionary = {}     ## The active interaction spec, or empty when idle.
var _active_object: Node = null  ## The object the active interaction belongs to.
## Where the character stood when the interaction began; it returns here on exit.
var _return_position := Vector2.ZERO
## Object whose collision exception is pending removal once the body has cleared it (see below).
var _clearing_object: Node = null

@onready var _character := get_parent()  ## Character (CharacterBody2D) — position, aim, inventory.


func _physics_process(_delta: float) -> void:
	# Re-enable collision with a just-left object only once the body has fully separated from it,
	# so restoring collision never finds an overlap for the solver to eject the object out of.
	if _clearing_object == null:
		return
	if not _overlaps(_clearing_object):
		_character.remove_collision_exception_with(_clearing_object)
		_clearing_object = null


## Toggle interaction: end the current one (moving back), or start the best one in range.
func try_interact() -> void:
	if is_busy():
		_end()
	else:
		_begin_best()


## True while an interaction is in progress (the character is locked).
func is_busy() -> bool:
	return not _active.is_empty()


## The active interaction's HUD label, or "" when idle.
func active_label() -> String:
	return _active.get("label", "")


## The reachable objects and their valid actions, as `[{ object, specs }]` (empty when none in
## range). Lets a controller (an AI) see its options and choose deliberately via `interact_with`.
func interactions_in_reach() -> Array:
	return _query_reachable()


## Begin action `id` on `object` if it is reachable, valid and we are idle; true on success.
## Unlike `try_interact()`, the caller picks both the object and the action (no nearest/random).
func interact_with(object: Node, id: String) -> bool:
	if is_busy():
		return false
	for entry in _query_reachable():
		if entry["object"] != object:
			continue
		for spec in entry["specs"]:
			if spec.get("id", "") == id:
				_begin(spec, object)
				return true
	return false


## End the active interaction, if any (explicit stop for a controller, vs try_interact's toggle).
func end_interaction() -> void:
	if is_busy():
		_end()


## Find every reachable object advertising a valid action, target the one nearest the mouse, and
## begin a random one of its valid actions. Does nothing if nothing valid is in range.
func _begin_best() -> void:
	var target: Node = null
	var target_specs: Array = []
	var best_dist := INF
	for entry in _query_reachable():
		# Prefer whichever reachable object sits closest to the mouse cursor.
		var dist: float = entry["object"].global_position.distance_squared_to(_character.aim_point)
		if dist < best_dist:
			best_dist = dist
			target = entry["object"]
			target_specs = entry["specs"]

	if target:
		_begin(target_specs.pick_random(), target)


## Every object within reach that advertises at least one valid action, as `[{ object, specs }]`
## (specs already item-gated). Shared by the player's `_begin_best` and the AI-facing queries.
func _query_reachable() -> Array:
	var center: Vector2 = _character.global_position + _character.facing * front_offset
	var shape := CircleShape2D.new()
	shape.radius = reach
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = QUERY_MASK
	params.exclude = [_character.get_rid()]
	params.transform = Transform2D(0.0, center)

	var out: Array = []
	for result in get_world_2d().direct_space_state.intersect_shape(params, 32):
		var obj: Node = result.collider
		if obj == null or not obj.has_method("get_interactions"):
			continue
		var valid := _valid_specs(obj.get_interactions())
		if not valid.is_empty():
			out.append({ "object": obj, "specs": valid })
	return out


## Keep only the actions whose item gate passes (no `requires_item`, or the character has it).
func _valid_specs(specs: Array) -> Array:
	var out: Array = []
	for spec in specs:
		var needed: int = spec.get("requires_item", 0)
		if needed <= 0 or _character.has_item(needed):
			out.append(spec)
	return out


## Start an interaction: remember the return spot; for a `move_to` action let the body share
## space with the object (a collision exception, so neither ejects nor shoves the other) and snap
## onto its center; then announce. Actions without `move_to` leave the character where it stands.
func _begin(spec: Dictionary, object: Node) -> void:
	_return_position = _character.global_position
	_active = spec
	_active_object = object
	if spec.get("move_to", false):
		if _clearing_object == object:
			_clearing_object = null  # Re-entering the same object: keep its existing exception.
		else:
			_character.add_collision_exception_with(object)
		_character.global_position = object.global_position
	interaction_changed.emit(true, active_label())


## End the active interaction. try_interact() runs inside the character's physics step, so the
## actual teardown is deferred to after the step: moving the body and re-enabling its collision
## mid-solve — then having move_and_slide() run the same frame — is what made the physics lurch.
## The character stays frozen (still busy) for this frame; _teardown runs before the next one.
func _end() -> void:
	call_deferred("_teardown")


## Restore the character to its start spot and hand the object off to the clearing check, which
## re-enables collision only once the body has separated from it (so no separation kick). Runs
## outside the physics step (deferred from _end), then clears the busy state.
func _teardown() -> void:
	_character.global_position = _return_position
	if _active_object != null and _active.get("move_to", false):
		_clearing_object = _active_object
	_active = {}
	_active_object = null
	interaction_changed.emit(false, "")


## Whether the body (its circle plus a clearance margin) currently overlaps `object`'s collider.
func _overlaps(object: Node) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = _character.radius + CLEAR_MARGIN
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = QUERY_MASK
	params.exclude = [_character.get_rid()]
	params.transform = Transform2D(0.0, _character.global_position)
	for result in get_world_2d().direct_space_state.intersect_shape(params, 32):
		if result.collider == object:
			return true
	return false
