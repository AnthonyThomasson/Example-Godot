extends GameTest

## G12: the bang is reduced (x0.4) through a wall only. A piece of furniture between the burst and a character, right against it, stops the flash
## (G11) but not the sound: a crouched character against a couch and a standing one against a wardrobe, both out of the flash, are deafened for the
## full fall-off of their distance. The victims are stood round the grenade once it lies still, so the distance is known.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(60, 350)
const AIM := Vector2(450, 350)
const COUCH := Vector2(450, 220)    ## spans y 195 to 245 (coverage 45)
const WARDROBE := Vector2(450, 480)  ## 90 x 45, spans y 457 to 503 (coverage 95)
## Against the far face of each, 20 px off it.
const BEHIND_COUCH := Vector2(450, 175)
const BEHIND_WARDROBE := Vector2(450, 523)
## Seconds of slack on a deaf time.
const SLACK := 0.35


func describe() -> Dictionary:
	return {
		"name": "Furniture stops the flash but not the bang",
		"description": "A stun grenade lies still between a couch and a wardrobe; a character crouched against the couch and one standing against the wardrobe are not flashed but are deafened for the whole fall-off of their distance.",
		"tags": ["grenade", "stun", "bang", "deaf", "cover", "character"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.object(&"couch", "sofa", COUCH)
	s.object(&"wardrobe", "wardrobe", WARDROBE)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	# Out of the way until the grenade has landed, then stood in place.
	s.actor(&"couched", &"puppet", Vector2(940, 60), { "max_health": 100000.0 })
	s.actor(&"cabinet", &"puppet", Vector2(940, 100), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(thrower, Probe.STUN)):
		return
	t.puppet(&"couched").set_posture(&"crouch")
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await Probe.wait_rest(t, 1.4), "the grenade comes to rest before it goes off"):
		return
	var burst := Probe.rest_point(t)
	Probe.place(t, &"couched", BEHIND_COUCH, burst)
	Probe.place(t, &"cabinet", BEHIND_WARDROBE, burst)
	if not t.require(await Probe.wait_boom(t, &"stun", 1.2), "the stun grenade goes off"):
		return
	var at: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
	await t.frames(2)
	for id in [&"couched", &"cabinet"]:
		var c := t.actor(id)
		t.check(Probe.shielded(t, at, c), "set-up: %s has a piece of furniture over its height on the line from the burst" % id)
		var events := Probe.stuns(t, c)
		if not t.check(not events.is_empty(), "%s is stunned" % id):
			continue
		var d: float = c.global_position.distance_to(at)
		var got := float(events[0]["data"].get("deaf", 0.0))
		var want := Probe.expected_deaf(d)
		t.check(float(events[0]["data"].get("blind", -1.0)) == 0.0, "%s is not flashed: the furniture at its face is between it and the burst" % id)
		t.check(want > 1.0 and absf(got - want) <= SLACK, "%s (%.0f px) is deaf for the whole fall-off: %.2f s, expected %.2f (not x0.4 = %.2f)" % [id, d, got, want, want * Probe.WALL_FACTOR])
