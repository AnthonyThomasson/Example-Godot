extends Node

## Vehicles domain: a character's use of vehicles (interface 19), composed by the character like its
## CharacterInteraction, which only forwards opaque calls to it: `try_use_vehicle()` (E: board by the nearest usable
## door, or get out), `vehicle()`, `is_in_vehicle()`, and once a physics frame `control(delta)` (after its controller,
## so the ride overrides that frame's intent) and `abandon()` on death. It finds vehicles through the group `vehicles`
## and steps the character's ride (vehicle_boarding.gd), which moves the character through its own walk and its ride API
## (`set_ride_pose`, `end_ride`). While the ride lasts the character keeps a collision exception with the vehicle; once
## it is out, it hands the vehicle to the character's `keep_clear_of`, which drops the exception as soon as the body has
## cleared the vehicle, so getting out never shoves it.

var _ride: RefCounted  ## The ride under way (VehicleBoarding), from the E press to the last step out; null on foot.

@onready var _character: Node2D = get_parent()


## E: seated, get out (braking or waiting for the vehicle to slow first); on foot, board by the door whose handle is
## nearest, among those within `VehicleConfig.door_reach` of a vehicle moving slower than `board_max_speed`, skipping a
## door that cannot open for the next nearest. Nothing happens on the way in or out, or with no usable door.
func try_use_vehicle() -> void:
	if _ride != null:
		if _ride.is_seated():
			_ride.vehicle.exit(_character)
		return
	var candidates := []
	for near in _character.get_tree().get_nodes_in_group(&"vehicles"):
		if not near is Node2D or near.speed() >= VehicleConfig.board_max_speed:
			continue
		for door: Dictionary in near.doors():
			var distance: float = _character.global_position.distance_to(door["handle"])
			if distance <= VehicleConfig.door_reach:
				candidates.append({ "vehicle": near, "door": door["id"], "distance": distance })
	candidates.sort_custom(func(a, b): return a["distance"] < b["distance"])
	for c: Dictionary in candidates:
		var ride: RefCounted = c["vehicle"].board(_character, c["door"])
		if ride != null:
			_ride = ride
			_character.stop_clearing(c["vehicle"])  # Back into the vehicle just left: its exception stays.
			return


## The vehicle the character is boarding, riding in or getting out of; null on foot.
func vehicle() -> Node2D:
	return _ride.vehicle if _ride != null and is_instance_valid(_ride.vehicle) else null


## True only while seated (not on the way in or out).
func is_in_vehicle() -> bool:
	return vehicle() != null and _ride.is_seated()


## True from the E press to the last step out: the character is busy.
func is_active() -> bool:
	return _ride != null


## Step the ride one physics frame (the character calls it after its controller). Once the character is out, the
## vehicle goes to the character's `keep_clear_of`, which restores their collision as soon as it has cleared the body.
func control(delta: float) -> void:
	if _ride == null:
		return
	if not is_instance_valid(_ride.vehicle):
		_ride = null
		_character.end_ride()
		return
	_ride.step(delta)
	if _ride.is_done():
		_character.keep_clear_of(_ride.vehicle)
		_ride = null


## The character died: its ride ends where its body is (the seat is given up, the door left as it is).
func abandon() -> void:
	if _ride == null:
		return
	if is_instance_valid(_ride.vehicle):
		_ride.abandon()
		_character.keep_clear_of(_ride.vehicle)
	_ride = null
	_character.end_ride()
