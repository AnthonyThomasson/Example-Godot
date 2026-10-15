extends GameTest

## V7 (ticket #54): the vehicles are heard, every sound synthesized like the rest. A driver sitting down cranks the ignition
## and starts one looping engine voice per running vehicle, whose pitch follows the revs (higher at speed than idling) and
## which is cut when the driver leaves; the door clicks open and slams shut (the van's slide door rolls and thunks); the
## tyres squeal while the car slides; a crash crunches louder the faster it is, and a car striking a character thuds. The
## van's engine is deeper than the car's. All of it as `vehicle` / `engine` / `skid` bus events and `sound` events.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const SoundProbe := preload("res://tests/_audio/sound_probe.gd")
## The profiles the vehicles add (V7): every one must be in the sound bank (and so is rendered by audio/bank).
const PROFILES := [&"engine/car", &"engine/van", &"ignition/car", &"ignition/van", &"door/car/open", &"door/car/close",
	&"door/van/open", &"door/van/close", &"door/van/slide_open", &"door/van/slide_close", &"skid/tyre"]


func describe() -> Dictionary:
	return {
		"name": "Vehicles sound: ignition, engine, doors, skid, crash",
		"description": "Boarding the car: door open and close, ignition, the engine loop (pitch up with speed, cut on exit); a handbrake slide squeals; the van's slide door rolls; a slow and a fast crash (the fast louder); a car striking a character thuds; the new profiles are in the bank and the van's engine is the deeper.",
		"tags": ["sound", "vehicle", "engine", "door", "skid", "crash"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2600, 1200), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.set_static(SoundConfig, &"category_range", Probe.everywhere())
	s.set_static(SoundConfig, &"pitch_jitter", 0.0)
	s.set_static(SoundConfig, &"volume_jitter_db", 0.0)
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.vehicle(&"van", &"van", Vector2(300, 800))
	s.vehicle(&"slow", &"car", Vector2(2200, 150))
	s.vehicle(&"fast", &"car", Vector2(2200, 450))
	s.vehicle(&"bump", &"car", Vector2(1500, 1050))
	s.actor(&"me", &"puppet", Vector2(100, 100))
	s.actor(&"side", &"puppet", Vector2(100, 1100))
	s.actor(&"dummy", &"puppet", Vector2(1900, 1150), { "max_health": 100000.0 })


## The bus events (with their sim time) logged since index `mark` of `t.events`, of `topic`, passing `filter`.
func _since(t: TestContext, mark: int, topic: StringName, filter := Callable()) -> Array:
	return t.events.slice(mark).filter(func(e): return e["topic"] == topic and (not filter.is_valid() or filter.call(e["data"])))


## The `sound` events since `mark` whose profile is `profile` (or starts with it, when `prefix`).
func _sounds(t: TestContext, mark: int, profile: String, prefix := false) -> Array:
	return _since(t, mark, &"sound", func(d): return String(d["profile"]) == profile or (prefix and String(d["profile"]).begins_with(profile)))


## The vehicle events since `mark` at `stage`.
func _stage(t: TestContext, mark: int, stage: StringName) -> Array:
	return _since(t, mark, &"vehicle", func(d): return d.get("stage") == stage)


## Roll the empty `id` car into the east wall at `speed`, its nose first parked 10 px off it. Returns the crash sound's
## `volume_db` (or -INF when none was heard).
func _crash(t: TestContext, id: StringName, speed: float) -> float:
	var car := t.vehicle(id) as Node2D
	var gap := Probe.gap_to_solid(car, Probe.forward(car))
	await Probe.move_vehicle(t, car, car.global_position + Probe.forward(car) * (gap - 10.0), 0.0)
	var mark := t.events.size()
	car.set("linear_velocity", Probe.forward(car) * speed)
	await t.seconds(1.0)
	t.check(not _stage(t, mark, &"crash").is_empty(), "the %s's crash into the wall at %.0f px/s posts a crash event" % [id, speed])
	var heard := _sounds(t, mark, "crash/", true)
	if not t.check(not heard.is_empty(), "and a crash/ sound at %.0f px/s" % speed):
		return -INF
	return float(heard[0]["data"]["volume_db"])


func run(t: TestContext) -> void:
	for id in [&"car", &"van", &"slow", &"fast", &"bump"]:
		if not Probe.ready(t, id, [&"me", &"side"] if id == &"car" else []):
			return
	var service: Node = Sound
	if not t.require(service.has_method("loop_of"), "Sound.loop_of(vehicle, kind) exists"):
		return
	var car := t.vehicle(&"car") as Node2D
	var van := t.vehicle(&"van") as Node2D

	# --- The library.
	var bank := SoundBank.profiles()
	for profile in PROFILES:
		t.check(bank.has(profile), "the sound bank has %s" % profile)
	t.check(bank.any(func(p): return String(p).begins_with("crash/")), "and crash/ profiles")
	if bank.has(&"engine/car") and bank.has(&"engine/van"):
		var car_engine := SoundProbe.samples(&"engine/car")
		var van_engine := SoundProbe.samples(&"engine/van")
		t.check(SoundProbe.low_share(van_engine) > SoundProbe.low_share(car_engine), "the van's engine is deeper than the car's (low share %.2f against %.2f)" % [SoundProbe.low_share(van_engine), SoundProbe.low_share(car_engine)])

	# --- Getting in: the door, the ignition, the engine.
	var mark := t.events.size()
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets into the car"):
		return
	await t.until(func(): return Probe.open_of(car, &"front_left") < 0.02, 2.0)
	await t.seconds(0.3)
	t.check(not _stage(t, mark, &"door_open").is_empty() and not _sounds(t, mark, "door/car/open").is_empty(), "the door clicks open (door_open, door/car/open)")
	t.check(not _stage(t, mark, &"door_close").is_empty() and not _sounds(t, mark, "door/car/close").is_empty(), "and slams shut (door_close, door/car/close)")
	t.check(not _stage(t, mark, &"ignition").is_empty() and not _sounds(t, mark, "ignition/car").is_empty(), "the ignition cranks as the driver sits (ignition, ignition/car)")
	t.check(not _since(t, mark, &"engine", func(d): return d.get("vehicle") == car and d.get("stage") == &"start").is_empty(), "the engine starts (an engine start event for the car)")
	t.check(not _sounds(t, mark, "engine/car").is_empty(), "with an engine/car sound")
	var idle: Dictionary = service.loop_of(car, &"engine")
	if not t.require(not idle.is_empty(), "one looping engine voice plays for the running car"):
		return

	# --- The engine's pitch follows the revs.
	await t.seconds(1.0)
	var idle_pitch := float(service.loop_of(car, &"engine").get("pitch", 0.0))
	var idle_rpm := float(car.engine_state().get("rpm", 0.0))
	if not t.require(await Probe.reach_speed(t, &"me", car, 150.0, 6.0), "the car reaches 150 px/s"):
		return
	t.puppet(&"me").drive(1.0, 0.0, false)
	await t.frames(2)
	var fast_pitch := float(service.loop_of(car, &"engine").get("pitch", 0.0))
	t.check(fast_pitch > idle_pitch * 1.1, "the engine's pitch rises with speed (%.2f idling, %.2f at 150 px/s)" % [idle_pitch, fast_pitch])
	t.check(float(car.engine_state().get("rpm", 0.0)) > idle_rpm, "with the revs")

	# --- A handbrake slide squeals.
	mark = t.events.size()
	var squealed := false
	t.puppet(&"me").drive(0.0, 1.0, true)
	var deadline := t.time + 1.0
	while t.time < deadline:
		await t.frames(1)
		squealed = squealed or not service.loop_of(car, &"skid").is_empty()
	t.check(not _since(t, mark, &"skid", func(d): return d.get("vehicle") == car and d.get("stage") == &"start").is_empty(), "the slide starts a skid (a skid start event)")
	t.check(not _sounds(t, mark, "skid/tyre").is_empty() and squealed, "and a looping skid/tyre squeal plays")
	t.puppet(&"me").drive(-1.0, 0.0, false)
	await t.until(func(): return car.speed() < 3.0, 6.0)
	t.puppet(&"me").drive(0.0, 0.0, false)
	await t.seconds(1.0)
	t.check(not _since(t, mark, &"skid", func(d): return d.get("vehicle") == car and d.get("stage") == &"stop").is_empty(), "the squeal stops with the slide (a skid stop event)")
	t.check(service.loop_of(car, &"skid").is_empty(), "and its voice is gone")

	# --- Getting out cuts the engine.
	mark = t.events.size()
	if not t.require(await Probe.exit(t, &"me"), "the driver gets out"):
		return
	await t.until(func(): return Probe.open_of(car, &"front_left") < 0.02, 2.0, "the car door shuts")
	t.check(not _since(t, mark, &"engine", func(d): return d.get("vehicle") == car and d.get("stage") == &"stop").is_empty(), "the engine is cut (an engine stop event)")
	t.check(service.loop_of(car, &"engine").is_empty(), "and its voice is gone")

	# --- The van's slide door rolls and thunks.
	mark = t.events.size()
	if not t.require(await Probe.board_by(t, &"side", van, &"side"), "a character gets into the van by the side door"):
		return
	await t.until(func(): return Probe.open_of(van, &"side") < 0.02, 2.0)
	await t.seconds(0.3)
	t.check(not _stage(t, mark, &"slide_open").is_empty() and not _sounds(t, mark, "door/van/slide_open").is_empty(), "the side door rolls open (slide_open, door/van/slide_open)")
	t.check(not _stage(t, mark, &"slide_close").is_empty() and not _sounds(t, mark, "door/van/slide_close").is_empty(), "and thunks shut (slide_close, door/van/slide_close)")
	t.check(_since(t, mark, &"vehicle", func(d): return d.get("kind") != &"van").is_empty(), "the van's events name it a van")

	# --- Crashes: louder the faster.
	var crash_min: Variant = Probe.config_value(&"crash_min_speed")
	if not t.require(crash_min != null, "VehicleConfig.crash_min_speed exists"):
		return
	var soft := await _crash(t, &"slow", float(crash_min) * 1.5)
	var hard := await _crash(t, &"fast", float(crash_min) * 4.0)
	t.check(hard > soft + 1.0, "the faster crash is the louder (%.1f against %.1f dB)" % [hard, soft])

	# --- A car striking a character thuds.
	var bump := t.vehicle(&"bump") as Node2D
	var radius: float = t.actor(&"dummy").radius
	await Probe.place(t, &"dummy", Probe.edge(bump, Probe.forward(bump)) + Probe.forward(bump) * (radius + 8.0))
	mark = t.events.size()
	bump.set("linear_velocity", Probe.forward(bump) * maxf(float(crash_min) * 2.0, 150.0))
	await t.seconds(1.0)
	var bumps := _stage(t, mark, &"bump_character")
	if t.check(not bumps.is_empty(), "striking a character posts bump_character"):
		var at: Vector2 = bumps[0]["data"].get("position", Vector2.INF)
		var thuds := _since(t, mark, &"sound", func(d): return d["kind"] == &"vehicle" and (d["position"] as Vector2).distance_to(at) < 60.0)
		t.check(not thuds.is_empty() and absf(float(thuds[0]["time"]) - float(bumps[0]["time"])) < 0.2, "and a vehicle sound is heard there at once")
