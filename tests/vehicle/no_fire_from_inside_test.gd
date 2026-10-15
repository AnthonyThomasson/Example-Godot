extends GameTest

## V5 (ticket #54): mouse aim and firing do nothing from inside a vehicle. A driver and a front passenger, each with a
## loaded pistol, both fire once on foot (a shot leaves the barrel: the control), then get into the car; seated, each
## aims at a point outside and clicks the trigger again and again: no round leaves the barrel (no `shot` event, no `hit`,
## no `sound` of kind `shot`) and no ammo is spent.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## The slot both hold (the pistol).
const SLOT := 3
const RIDERS := { &"d": &"front_left", &"p": &"front_right" }


func describe() -> Dictionary:
	return {
		"name": "No firing from inside a vehicle",
		"description": "A seated driver and passenger click the trigger of a loaded pistol: no shot, hit or shot sound, no ammo spent (on foot the same click fires).",
		"tags": ["vehicle", "car", "drive", "shoot", "pistol"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.switch(&"audio.sound", true)
	s.set_static(SoundConfig, &"category_range", Probe.everywhere())
	s.vehicle(&"car", &"car", Vector2(500, 350))
	s.actor(&"d", &"puppet", Vector2(150, 100), { "start_slot": SLOT })
	s.actor(&"p", &"puppet", Vector2(850, 600), { "start_slot": SLOT })


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", RIDERS.keys()):
		return
	var car := t.vehicle(&"car") as Node2D

	# The control: on foot, the same click fires.
	for id in RIDERS:
		var who := t.actor(id) as Node2D
		var before := t.events.size()
		t.puppet(id).aim_at(who.global_position + Vector2(0, -1 if who.global_position.y < 350 else 1) * 100.0)
		await t.seconds(0.4)
		t.puppet(id).shoot()
		if not t.require(await t.until(func(): return not _since(t, before, &"shot", id).is_empty(), 1.0), "on foot, %s's click fires a shot" % id):
			return
	await t.seconds(0.6)

	# Driver first (a passenger with an empty driver's seat slides across to it).
	for id in RIDERS:
		if not t.require(await Probe.board_by(t, id, car, RIDERS[id]), "%s gets in by the %s door" % [id, RIDERS[id]]):
			return
	await t.seconds(0.6)
	t.check(Probe.seat_of(car, t.actor(&"d")) == &"driver" and Probe.seat_of(car, t.actor(&"p")) == &"passenger", "one drives, one rides (%s, %s)" % [Probe.seat_of(car, t.actor(&"d")), Probe.seat_of(car, t.actor(&"p"))])

	# Seated: aim out of each side and click, ten times over two seconds.
	var mark := t.events.size()
	var ammo := {}
	for id in RIDERS:
		ammo[id] = t.actor(id).ammo(SLOT)
		t.puppet(id).aim_at(car.global_position + Probe.right(car) * (-400.0 if id == &"d" else 400.0))
	for i in 10:
		await t.seconds(0.2)
		for id in RIDERS:
			t.puppet(id).shoot()
	await t.seconds(0.5)

	for id in RIDERS:
		var who := t.actor(id)
		t.check(who.is_in_vehicle(), "%s is still seated" % id)
		t.check(_since(t, mark, &"shot", id).is_empty(), "no round leaves %s's barrel (%d shot events)" % [id, _since(t, mark, &"shot", id).size()])
		t.check(who.ammo(SLOT) == ammo[id], "%s spends no ammo (%d rounds, had %d)" % [id, who.ammo(SLOT), ammo[id]])
	var hits := t.events.slice(mark).filter(func(e): return e["topic"] == &"hit")
	t.check(hits.is_empty(), "nothing is hit (%d hit events)" % hits.size())
	var bangs := t.events.slice(mark).filter(func(e): return e["topic"] == &"sound" and e["data"]["kind"] == &"shot")
	t.check(bangs.is_empty(), "no gunshot is heard (%d shot sounds)" % bangs.size())


## The `topic` events since index `mark` of the event log posted by actor `id` (their `attacker`).
func _since(t: TestContext, mark: int, topic: StringName, id: StringName) -> Array:
	var who := t.actor(id)
	return t.events.slice(mark).filter(func(e): return e["topic"] == topic and e["data"].get("attacker") == who)
