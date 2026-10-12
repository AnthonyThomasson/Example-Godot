extends GameTest

## Real bullets, real surfaces: a pistol round through a chair is heard as wood, through a lamp as metal, into a
## body as flesh; and the same wall is heard differently depending on the round that goes through it — an SMG's
## light round, a pistol's medium one, an assault rifle's heavy one.

const Probe := preload("res://tests/_audio/sound_probe.gd")

## [lane y, gun slot, what stands at x=400 in that lane (or "" = fire at the east wall), profile expected]
const LANES := [
	[70.0, 3, "chair", &"impact/wood/penetrate/medium"],
	[170.0, 3, "lamp", &"impact/metal/penetrate/medium"],
	[270.0, 3, "body", &"impact/flesh/penetrate/medium"],
	[400.0, 5, "", &"impact/wall/penetrate/light"],
	[500.0, 3, "", &"impact/wall/penetrate/medium"],
	[600.0, 6, "", &"impact/wall/penetrate/heavy"],
]


func describe() -> Dictionary:
	return {
		"name": "Bullet impacts sound like what they hit and what hit it",
		"description": "Pistol rounds through a chair, a lamp and a body, and SMG / pistol / rifle rounds through a wall, make wood, metal, flesh and light / medium / heavy wall impacts.",
		"tags": ["sound", "impact", "projectile", "material"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"projectile.flyover", false)
	s.switch(&"nav.rebake", false)  # shot furniture is shoved into overlaps; re-baking them logs a nav sync error
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", straight)
	for i in LANES.size():
		var lane: Array = LANES[i]
		s.actor(StringName("shooter%d" % i), &"puppet", Vector2(100, lane[0]), { "start_slot": lane[1] })
		match lane[2]:
			"chair":
				s.object(&"chair", "chair", Vector2(400, lane[0]))
			"lamp":
				s.object(&"lamp", "lamp", Vector2(400, lane[0]))
			"body":
				s.actor(&"body", &"puppet", Vector2(400, lane[0]), { "max_health": 500.0 })


func run(t: TestContext) -> void:
	for i in LANES.size():
		var lane: Array = LANES[i]
		t.puppet(StringName("shooter%d" % i)).aim_at(Vector2(880, lane[0]))
	await t.seconds(0.5)
	for i in LANES.size():
		t.puppet(StringName("shooter%d" % i)).shoot()
	await t.seconds(1.5)

	for i in LANES.size():
		var lane: Array = LANES[i]
		# The first impact in this lane: at the object, or at the east wall.
		var x_min := 380.0 if lane[2] != "" else 860.0
		var x_max := 420.0 if lane[2] != "" else 910.0
		var heard := Probe.sounds(t, &"impact").filter(func(d): return absf(d["position"].y - lane[0]) < 25.0 \
			and d["position"].x > x_min and d["position"].x < x_max)
		var what: String = lane[2] if lane[2] != "" else "the wall (slot %d)" % lane[1]
		if t.check(not heard.is_empty(), "a hit on %s was heard" % what):
			t.expect_eq(heard[0]["profile"], lane[3], "the sound of a round hitting %s" % what)
