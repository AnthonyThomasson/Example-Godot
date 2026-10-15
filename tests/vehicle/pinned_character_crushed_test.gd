extends GameTest

## V6 / F6 (ticket #54, feedback round 2): a character with something solid at it is still hurt, and the car slows
## naturally: it is never stopped dead by a character. Four empty cars are let roll at the same 200 px/s (between
## harm_min_speed 90 and harm_kill_speed 300: hurt, not killed, in the open) at a standing character:
##  (a) pinned: the character stands just in front of a heavy armchair (the chair right behind it, along the car's path);
##  (b) pinned: the character stands just in front of the arena wall;
##  (c) in the open, nothing behind it (the yardstick, as in `vehicle/hits_character_damage_by_speed`);
##  (d) shielded: the armchair stands between the car and the character, which stands right behind it.
## (a) and (b) take at least the open hit's harm; (d) at least half of it (the piece carries the blow on, some of it
## absorbed). Against the armchair (a, d) the car shoves the piece on and keeps a natural share of its speed; in the open
## it keeps most of it; against the wall (b) it stops as a wall crash does, and posts a crash.
##
## The thresholds, from the physics (masses: car 400, character 40, armchair made heavy: 80):
##  - Harm: the open hit's closing speed is the car's 200 px/s (the character stands still), and so is the first touch in
##    (a) and (b), so equal harm is the floor; DAMAGE_SLACK only absorbs a frame's sampling of the closing speed (2% of
##    the damage, under 1 px/s of it). In (d) the chair, shoved at nearly the car's speed, strikes the character; half the
##    open harm leaves room for what the piece absorbs and is far from none.
##  - Speed kept 0.1 s after the first touch. Open (c): the character takes its momentum share (40 / 440) with a bounce
##    (harm_bounce 0.4), so the car keeps 1 - 1.4 x 40 / 440 = 87%, less rolling resistance (25 px/s², about 1%): 70%
##    leaves room for a frame's contact and is far from a stop. Armchair (a, d): car, character and chair shoved as one
##    plastic pile keep 400 / 520 = 77% by momentum; the character's bounce takes about 6% more and the chair's damping
##    (4 /s on 80 of 520) under 1% in 0.1 s, so about 70% is natural; (a) asks for 30% (the plan's floor: the pinned
##    character is squeezed and the chair turns), (d) for 50% (the chair alone takes the first blow).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## Lane -> [the car's start, the character].
const LANES := {
	&"chair": [Vector2(400, 110), &"pinned_chair"],
	&"wall": [Vector2(1320, 330), &"pinned_wall"],
	&"open": [Vector2(400, 550), &"open"],
	&"shield": [Vector2(400, 770), &"shielded"],
}
const SPEED := 200.0
const ARENA := Rect2(0, 0, 1600, 900)
## The armchair's weight: twice the character's mass (40), a heavy piece (the catalogue armchair weighs 22).
const CHAIR_WEIGHT := 80.0
## How far (px) the pinning armchair's near face stands ahead of the car's nose as placed (the car is then moved up to it).
const CHAIR_AHEAD := 60.0
## The gap (px) between each car's nose and the first thing it strikes (its character, or in (d) the armchair).
const GAP := 20.0
## Harm in (a) / (b) may fall short of the open hit's by this share at most; (d) must take this share of it.
const DAMAGE_SLACK := 0.02
const SHIELDED_HARM := 0.5
## The share of the approach speed each car keeps AFTER_TOUCH s after its first touch (see above).
const KEEP := { &"chair": 0.3, &"open": 0.7, &"shield": 0.5 }
const AFTER_TOUCH := 0.1


func describe() -> Dictionary:
	return {
		"name": "A pinned or shielded character is still hurt",
		"description": "Empty cars at 200 px/s strike a character in front of a heavy armchair, one in front of the wall, one in the open and one behind the armchair: the pinned ones take at least the open hit's harm and the shielded one half of it; the car keeps 30% / 70% / 50% of its speed 0.1 s after the touch (pinned / open / shielded) and shoves the armchair; against the wall it posts a crash.",
		"tags": ["vehicle", "car", "collision", "character", "damage", "furniture", "wall"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA, { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	for lane in LANES:
		s.vehicle(lane, &"car", LANES[lane][0])
	# The car is 220 long: its nose is 110 ahead of its centre.
	var chair := _heavy_chair()
	var half := _chair_half()
	s.object(&"chair", chair, LANES[&"chair"][0] + Vector2(110.0 + CHAIR_AHEAD + half, 0.0))
	s.object(&"shield", chair, LANES[&"shield"][0] + Vector2(110.0 + GAP + half, 0.0))
	var x := 200.0
	for lane in LANES:
		s.actor(LANES[lane][1], &"puppet", Vector2(x, 880))
		x += 100.0


## The armchair's catalogue definition, made `CHAIR_WEIGHT` heavy.
static func _heavy_chair() -> Dictionary:
	var chair := WorldGen.object_definition("armchair").duplicate(true)
	chair["weight"] = CHAIR_WEIGHT
	return chair


## Half the armchair's depth along the car's path (it is placed unturned).
static func _chair_half() -> float:
	return float((_heavy_chair()["size"] as Vector2).x) / 2.0


func run(t: TestContext) -> void:
	for lane in LANES:
		if not Probe.ready(t, lane, [LANES[lane][1]]):
			return
	var chairs := { &"chair": t.object(&"chair") as Node2D, &"shield": t.object(&"shield") as Node2D }
	for id in chairs:
		if not t.require(chairs[id] != null, "the armchair %s is placed" % id):
			return

	# Each character GAP ahead of its car's nose, so every car strikes at the same closing speed (a longer roll would lose
	# speed to rolling resistance and so harm). In (a) and (b) the car is first moved so that what stands ahead of it is
	# just a character's width past that: the character then touches it. In (d) the character stands touching the far
	# face of the armchair, which is GAP ahead of the nose.
	var placed := {}
	for lane in LANES:
		var car := t.vehicle(lane) as Node2D
		var who: StringName = LANES[lane][1]
		var radius: float = t.actor(who).radius
		var front := Probe.forward(car)
		if lane == &"chair" or lane == &"wall":
			var behind := Probe.gap_to_solid(car, front)
			if not t.require(behind < 300.0, "in the %s lane something solid stands ahead of the nose (%.0f px)" % [lane, behind]):
				return
			await Probe.move_vehicle(t, car, car.global_position + front * (behind - (GAP + 2.0 * radius + 1.0)), car.global_rotation)
			t.check(absf(Probe.gap_to_solid(car, front) - (GAP + 2.0 * radius + 1.0)) < 1.5, "the %s lane's car stands a character's width and GAP short of it (%.1f px)" % [lane, Probe.gap_to_solid(car, front)])
		if lane == &"shield":
			t.check(absf(Probe.gap_to_solid(car, front) - GAP) < 1.5, "the shielding armchair stands GAP ahead of the nose (%.1f px)" % Probe.gap_to_solid(car, front))
			placed[lane] = chairs[&"shield"].global_position + front * (_chair_half() + radius + 1.0)
		else:
			placed[lane] = Probe.edge(car, front) + front * (GAP + radius)
		await Probe.place(t, who, placed[lane])
	for lane in LANES:
		var who: StringName = LANES[lane][1]
		t.check(t.actor(who).global_position.distance_to(placed[lane]) < 2.0, "the %s character stands where it was put" % lane)

	var chair_start := {}
	for id in chairs:
		chair_start[id] = chairs[id].global_position
	for lane in LANES:
		var car := t.vehicle(lane) as Node2D
		car.set("linear_velocity", Probe.forward(car) * SPEED)

	# Each lane's first touch: the first frame its car slows, its character is hurt or shoved, or (d) its chair moves;
	# and the car's speed AFTER_TOUCH s later.
	var touched := {}
	var kept := {}
	var deadline := t.time + 1.5
	while t.time < deadline:
		await t.frames(1)
		for lane in LANES:
			var car := t.vehicle(lane) as Node2D
			var who := t.actor(LANES[lane][1])
			t.trace("%s car speed" % lane, car.speed())
			t.trace("%s health" % lane, who.health)
			var moved: bool = who.global_position.distance_to(placed[lane]) > 1.0
			if lane == &"shield":
				moved = moved or chairs[lane].global_position.distance_to(chair_start[lane]) > 1.0
			if not touched.has(lane) and (moved or who.health < who.max_health or car.speed() < 0.97 * SPEED):
				touched[lane] = t.time
			if touched.has(lane) and not kept.has(lane) and t.time >= touched[lane] + AFTER_TOUCH:
				kept[lane] = car.speed()
	for lane in LANES:
		if not t.require(touched.has(lane), "the %s lane's car reaches what stands ahead of it" % lane):
			return

	var harm := {}
	for lane in LANES:
		var who := t.actor(LANES[lane][1])
		harm[lane] = who.max_health - who.health
	var open: float = harm[&"open"]
	t.check(open > 0.0 and not t.actor(&"open").is_dead, "in the open %.0f px/s hurts the character and it lives (harm %.1f)" % [SPEED, open])
	for lane in [&"chair", &"wall"]:
		t.check(harm[lane] >= open * (1.0 - DAMAGE_SLACK), "pinned against the %s it takes at least the open hit's harm (%.1f against %.1f)" % [lane, harm[lane], open])
	t.check(harm[&"shield"] >= SHIELDED_HARM * open, "behind the armchair it takes at least half the open hit's harm (%.1f against %.1f)" % [harm[&"shield"], open])

	for lane in KEEP:
		var share: float = KEEP[lane]
		t.check(float(kept.get(lane, 0.0)) >= share * SPEED, "in the %s lane the car keeps going: %.0f px/s %.1f s after the first touch (at least %.0f of %.0f)" % [lane, float(kept.get(lane, 0.0)), AFTER_TOUCH, share * SPEED, SPEED])
	for id in chairs:
		var shoved: float = (chairs[id].global_position - chair_start[id]).dot(Probe.forward(t.vehicle(id) as Node2D))
		t.check(shoved > 20.0, "in the %s lane the car shoves the armchair on (%.0f px)" % [id, shoved])

	var wall_car := t.vehicle(&"wall") as Node2D
	var crashed := t.events_of(&"vehicle", func(d): return d.get("stage") == &"crash" and (d.get("position", Vector2.ZERO) as Vector2).distance_to(wall_car.global_position) < 300.0)
	t.check(not crashed.is_empty(), "against the wall the car crashes as into a wall (a crash event; it is at %.0f px/s)" % wall_car.speed())
