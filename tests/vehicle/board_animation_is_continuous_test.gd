extends GameTest

## V3 (ticket #54): boarding is one fluid movement, never a jump. Sampled every frame from the E press until the door has
## shut behind the seated character: the character's position never steps further in a frame than its own walk does, its
## facing turns smoothly (toward the door, then forward), the door eases open before the character folds in and eases shut
## after, the fold eases from standing to seated, and the seated character ends drawn over the chassis and under the roof.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## The most the facing may turn in one frame (rad): 15 rad/s, a half turn in no less than 0.2 s.
const MAX_TURN_PER_FRAME := 0.25
## The most the fold may change in one frame: a 0.5 s eased fold peaks near 0.05.
const MAX_FOLD_PER_FRAME := 0.1
## The most a door's open amount may change in one frame: a 0.35 s eased swing peaks near 0.08.
const MAX_DOOR_PER_FRAME := 0.15
## A measured ease (the door from 5 % to 90 % open, the fold from 10 % to 90 %) takes between these shares of the spec's
## full time (`Probe.DOOR_OPEN_TIME`, `Probe.FOLD_TIME`).
const EASE_SHARE_MIN := 0.4
const EASE_SHARE_MAX := 2.0


func describe() -> Dictionary:
	return {
		"name": "The boarding animation is continuous",
		"description": "Every frame of a boarding: per-frame steps under a walking step, a smooth turn to the door and then forward, the door easing open before the fold and shut after it, an eased fold, and the seated character between the Chassis and Roof layers.",
		"tags": ["vehicle", "car", "board", "animation", "door"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	if not Probe.has_reads(t, me, [&"posture_folded"], "character me"):
		return
	if not t.require(Probe.door(car, &"front_left").has("handle"), "the car reports its front-left handle"):
		return
	var chassis := Probe.layer(car, "Chassis")
	var roof := Probe.layer(car, "Roof")
	if not t.require(chassis != null and roof != null, "the car has its Chassis and Roof draw layers"):
		return

	# In reach of the front-left handle but not at it (ahead of it and out from the side), facing away from the car, so
	# the boarding has a walk and a turn to make.
	var d := Probe.door(car, &"front_left")
	var handle: Vector2 = d["handle"]
	var start := handle + Probe.outward(car, d) * 35.0 + Probe.forward(car) * 25.0
	if not t.require(start.distance_to(handle) < Probe.DOOR_REACH, "the start is in reach of the front-left handle"):
		return
	await Probe.place(t, &"me", start)
	var puppet := t.puppet(&"me")
	puppet.aim_at(start + (start - car.global_position))
	await t.seconds(0.4)
	puppet.aim_at(null)

	# Every frame from the press until the door is shut behind the seated character (or 6 s).
	var pos: Array[Vector2] = []
	var face: Array[Vector2] = []
	var fold: Array[float] = []
	var door: Array[float] = []
	var seated_at := -1
	puppet.use_vehicle()
	var deadline := t.time + 6.0
	while t.time < deadline:
		await t.frames(1)
		pos.append(me.global_position)
		face.append(me.facing)
		fold.append(float(me.posture_folded()))
		door.append(Probe.open_of(car, &"front_left"))
		if seated_at < 0 and me.is_in_vehicle():
			seated_at = pos.size() - 1
		if seated_at >= 0 and door[-1] < 0.02 and pos.size() > seated_at + 5:
			break
	if not t.require(seated_at >= 0, "the character gets in"):
		return

	# Position: no frame steps further than the character's own walk does in a frame.
	var walk_step: float = me.speed / Engine.physics_ticks_per_second * 1.2
	var worst_step := 0.0
	for i in range(1, pos.size()):
		worst_step = maxf(worst_step, pos[i].distance_to(pos[i - 1]))
	t.trace("step", worst_step)
	t.check(worst_step <= walk_step, "no frame moves the character further than a walking step (worst %.2f px, a step %.2f px)" % [worst_step, walk_step])

	# Facing: smooth, toward the door at some point before the fold, forward at the end.
	var worst_turn := 0.0
	for i in range(1, face.size()):
		worst_turn = maxf(worst_turn, absf(face[i - 1].angle_to(face[i])))
	t.check(worst_turn <= MAX_TURN_PER_FRAME, "the facing turns smoothly (worst %.3f rad in a frame)" % worst_turn)
	var fold_starts := _first(fold, func(x): return x > 0.1)
	var faced_door := false
	for i in range(0, fold_starts if fold_starts >= 0 else face.size()):
		var to_door := handle - pos[i]
		if to_door.length() > 1.0 and face[i].dot(to_door.normalized()) > 0.7:
			faced_door = true
	t.check(faced_door, "it turns to face the door before folding in")
	t.check(face[-1].dot(Probe.forward(car)) > 0.9, "it ends facing forward (dot %.2f)" % face[-1].dot(Probe.forward(car)))

	# The door: eases open, is open before the fold starts, eases shut after the fold is done.
	var peak: float = door.max()
	t.check(peak >= 0.9, "the door opens (most %.2f)" % peak)
	t.check(door[-1] <= 0.05, "the door is shut at the end (%.2f)" % door[-1])
	var worst_door := 0.0
	for i in range(1, door.size()):
		worst_door = maxf(worst_door, absf(door[i] - door[i - 1]))
	t.check(worst_door <= MAX_DOOR_PER_FRAME, "the door eases, never snaps (worst %.3f in a frame)" % worst_door)
	var opening := _first(door, func(x): return x > 0.05)
	var open := _first(door, func(x): return x >= 0.9)
	if opening >= 0 and open >= 0:
		var took := float(open - opening) / Engine.physics_ticks_per_second
		t.check(_about(took, Probe.DOOR_OPEN_TIME), "the door takes about %.2f s to open (%.2f s)" % [Probe.DOOR_OPEN_TIME, took])
	var door_open_by := _first(door, func(x): return x >= 0.8)
	t.check(door_open_by >= 0 and fold_starts >= 0 and door_open_by <= fold_starts, "the door is open before the character folds in (open frame %d, fold frame %d)" % [door_open_by, fold_starts])
	var peak_at := door.find(peak)
	var closing := -1
	for i in range(peak_at, door.size()):
		if door[i] < 0.8:
			closing = i
			break
	t.check(closing >= 0 and fold[closing] >= 0.8, "the door shuts only once the character is folded in (fold %.2f as it closes)" % (fold[closing] if closing >= 0 else -1.0))

	# The fold: from standing to seated, eased.
	t.check(fold[0] < 0.1, "the character starts standing (fold %.2f)" % fold[0])
	t.check(fold[seated_at] >= 0.9, "it is folded into the seat once seated (fold %.2f)" % fold[seated_at])
	var worst_fold := 0.0
	for i in range(1, fold.size()):
		worst_fold = maxf(worst_fold, absf(fold[i] - fold[i - 1]))
	t.check(worst_fold <= MAX_FOLD_PER_FRAME, "the fold eases (worst %.3f in a frame)" % worst_fold)
	var folded := _first(fold, func(x): return x >= 0.9)
	if fold_starts >= 0 and folded >= 0:
		var fold_time := float(folded - fold_starts) / Engine.physics_ticks_per_second
		t.check(_about(fold_time, Probe.FOLD_TIME), "the fold takes about %.2f s (%.2f s)" % [Probe.FOLD_TIME, fold_time])

	# Seated: inside the body, over the chassis and under the roof.
	var reach_in := car.global_position.distance_to(Probe.edge(car, -Probe.forward(car)))
	t.check(me.global_position.distance_to(car.global_position) < reach_in, "the character ends inside the car's body")
	t.check(Probe.draws_above(me, chassis), "the seated character is drawn over the chassis")
	t.check(Probe.draws_above(roof, me), "and under the roof")


## Whether a measured ease of `took` s fits a full time of `full` s.
func _about(took: float, full: float) -> bool:
	return took >= full * EASE_SHARE_MIN and took <= full * EASE_SHARE_MAX


## The first index of `values` where `test` holds, or -1.
func _first(values: Array, test: Callable) -> int:
	for i in values.size():
		if test.call(values[i]):
			return i
	return -1
