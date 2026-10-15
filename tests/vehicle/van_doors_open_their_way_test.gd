extends GameTest

## V3 (ticket #54): the van's doors move as their kind does. It has two front swing doors, a sliding side door on the
## right and rear double doors. Boarding by the side door, the door rolls back along the body (it slides, it never turns)
## and the character takes a cargo seat; boarding by a rear door, the door swings out behind the van about its hinge at
## the back corner (it turns, it never slides) and the character takes the other cargo seat.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The van's doors open their own way",
		"description": "The van's door table; the side door slides back along the body without turning; a rear door swings out behind the van without sliding; each leads to a cargo seat.",
		"tags": ["vehicle", "van", "board", "door", "animation"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"van", &"van", Vector2(450, 300))
	s.actor(&"side", &"puppet", Vector2(150, 540))
	s.actor(&"back", &"puppet", Vector2(150, 60))


## Board puppet `id` by door `door_id`, sampling that door every frame until it is seated and the door has shut again.
## Returns `{ seated, angle (largest |angle|), offset (the largest offset), handle (the handle at the most open) }`.
func _board_watching(t: TestContext, van: Node2D, id: StringName, door_id: StringName) -> Dictionary:
	await Probe.place(t, id, Probe.stand_point(van, door_id))
	var who := t.actor(id)
	t.puppet(id).use_vehicle()
	var out := { "seated": false, "angle": 0.0, "offset": Vector2.ZERO, "handle": Vector2.ZERO, "open": 0.0 }
	var deadline := t.time + 8.0
	while t.time < deadline:
		await t.frames(1)
		var d := Probe.door(van, door_id)
		out["angle"] = maxf(out["angle"], absf(float(d.get("angle", 0.0))))
		var offset: Vector2 = d.get("offset", Vector2.ZERO)
		if offset.length() > (out["offset"] as Vector2).length():
			out["offset"] = offset
		if float(d.get("open", 0.0)) > out["open"]:
			out["open"] = float(d.get("open", 0.0))
			out["handle"] = d.get("handle", Vector2.ZERO)
		if who.is_in_vehicle():
			out["seated"] = true
		if out["seated"] and float(d.get("open", 0.0)) < 0.02:
			break
	return out


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"van", [&"side", &"back"]):
		return
	var van := t.vehicle(&"van") as Node2D
	var doors := {}
	for d: Dictionary in van.doors():
		doors[d.get("id")] = [d.get("kind"), d.get("seat")]
	t.expect_eq(doors, Probe.VAN_DOORS, "the van has two front swing doors, a sliding side door and rear double doors")
	t.expect_eq(Probe.sorted(van.seats().map(func(s): return s.get("id"))), Probe.sorted(Probe.VAN_SEATS), "the van's seats")
	if not t.require(Probe.door(van, &"side").has("handle") and Probe.door(van, &"rear_left").has("handle"), "the van reports its side and rear handles"):
		return
	var tail := Probe.edge(van, -Probe.forward(van))

	# --- The side door slides back along the body.
	var side: Dictionary = await _board_watching(t, van, &"side", &"side")
	if not t.require(side["seated"], "the character gets in by the side door"):
		return
	var slid: Vector2 = side["offset"]
	t.check(slid.length() >= 15.0, "the side door rolls open along the body (%.0f px)" % slid.length())
	t.check(slid.length() > 0.0 and slid.normalized().dot(-Probe.forward(van)) > 0.9, "backward, along the body (direction %s)" % slid.normalized())
	t.check(side["angle"] <= 0.05, "it never turns (most %.3f rad)" % side["angle"])
	t.expect_eq(Probe.seat_of(van, t.actor(&"side")), &"cargo_right", "the side door leads to the right cargo seat")

	# --- A rear door swings out behind the van.
	var back: Dictionary = await _board_watching(t, van, &"back", &"rear_left")
	if not t.require(back["seated"], "the character gets in by the rear-left door"):
		return
	t.check(back["angle"] >= 1.0, "the rear door swings open (most %.2f rad)" % back["angle"])
	t.check((back["offset"] as Vector2).length() <= 2.0, "it never slides (%.1f px)" % (back["offset"] as Vector2).length())
	var behind := ((back["handle"] as Vector2) - tail).dot(-Probe.forward(van))
	t.check(behind > 5.0, "it swings out behind the van (its handle %.0f px past the tail at the most open)" % behind)
	t.expect_eq(Probe.seat_of(van, t.actor(&"back")), &"cargo_left", "the rear-left door leads to the left cargo seat")
