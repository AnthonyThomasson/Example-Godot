extends GameTest

## V6 (ticket #54): a character struck by a vehicle is knocked back, and hurt by the closing speed above harm_min_speed
## (90 px/s), up to lethal at harm_kill_speed. Three empty cars are let roll into three standing characters: at 60 px/s
## the character is shoved and unhurt, between the two speeds it is hurt and lives, above harm_kill_speed it dies.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const LANES := { &"slow": 150.0, &"mid": 400.0, &"fast": 650.0 }
## The gap (px) between a car's nose and the character it rolls into.
const GAP := 8.0


func describe() -> Dictionary:
	return {
		"name": "A vehicle hurts a character by its speed",
		"description": "Empty cars rolling at 60 px/s, midway between harm_min_speed and harm_kill_speed, and past harm_kill_speed strike standing characters: shoved only, hurt and alive, dead.",
		"tags": ["vehicle", "car", "collision", "character", "damage"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 800), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	var x := 100.0
	for lane in LANES:
		s.vehicle(lane, &"car", Vector2(400, LANES[lane]))
		s.actor(StringName("hit_" + lane), &"puppet", Vector2(x, 760))
		x += 100.0


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"slow") or not Probe.ready(t, &"mid") or not Probe.ready(t, &"fast"):
		return
	var kill: Variant = Probe.config_value(&"harm_kill_speed")
	if not t.require(kill != null, "VehicleConfig.harm_kill_speed exists"):
		return
	var mid := (Probe.HARM_MIN_SPEED + float(kill)) / 2.0
	if not t.require(mid > Probe.HARM_MIN_SPEED * 1.1 and mid < float(kill) * 0.9, "the middle speed %.0f px/s sits well between harm_min_speed (%.0f) and harm_kill_speed (%.0f)" % [mid, Probe.HARM_MIN_SPEED, float(kill)]):
		return
	var speeds := { &"slow": 60.0, &"mid": mid, &"fast": float(kill) + 40.0 }

	# Each character stands just ahead of its car's nose.
	var placed := {}
	for lane in LANES:
		var car := t.vehicle(lane) as Node2D
		var who := StringName("hit_" + lane)
		var radius: float = t.actor(who).radius
		placed[lane] = Probe.edge(car, Probe.forward(car)) + Probe.forward(car) * (radius + GAP)
		await Probe.place(t, who, placed[lane])
	for lane in LANES:
		var car := t.vehicle(lane) as Node2D
		car.set("linear_velocity", Probe.forward(car) * float(speeds[lane]))
	await t.seconds(1.5)

	var slow := t.actor(&"hit_slow")
	var front := Probe.forward(t.vehicle(&"slow") as Node2D)
	t.check(not slow.is_dead and is_equal_approx(slow.health, slow.max_health), "at 60 px/s the character is unhurt (health %.1f)" % slow.health)
	t.check((slow.global_position - placed[&"slow"]).dot(front) > 3.0, "but knocked back (%.1f px)" % (slow.global_position - placed[&"slow"]).dot(front))
	var hurt := t.actor(&"hit_mid")
	t.check(not hurt.is_dead and hurt.health < hurt.max_health, "at %.0f px/s it is hurt and lives (health %.1f)" % [mid, hurt.health])
	var killed := t.actor(&"hit_fast")
	t.check(killed.is_dead, "at %.0f px/s it is killed (health %.1f)" % [float(speeds[&"fast"]), killed.health])
