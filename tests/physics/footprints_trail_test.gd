extends GameTest

## A walker crossing a big splatter picks blood up on its soles: it prints in the splatter, and
## keeps printing on the clean floor beyond it with the prints fading, left and right feet alternating,
## until the blood runs out. Nothing is printed before the splatter.

const SPLAT_AT := Vector2(300, 200)
const SPLAT_SIZE := 30.0


func describe() -> Dictionary:
	return {
		"name": "Walking through blood leaves a fading trail of footprints",
		"description": "A puppet walks across a splatter: prints start in it, fade along the clean floor, alternate feet and then stop.",
		"tags": ["blood", "footprints", "walk"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.switch(&"physics.blood", true)
	s.actor(&"walker", &"puppet", Vector2(100, 200))


func run(t: TestContext) -> void:
	BloodSpawner.splat(t.world, SPLAT_AT, SPLAT_SIZE, Vector2.RIGHT, 0.0, [])
	await t.frames(2)
	var walker := t.puppet(&"walker")
	walker.walk(Vector2.RIGHT)
	await t.until(func(): return t.actor(&"walker").global_position.x > 800.0, 10.0, "the walker crosses the arena")
	walker.stop()
	await t.frames(2)
	t.screenshot("footprint_trail")

	var layer := BloodDecals.find(t.world)
	if not t.require(layer != null, "the walker left prints"):
		return
	var trail: Array = layer.items().filter(func(m): return m["kind"] == "print")
	t.check(trail.size() >= 5, "a trail of prints (%d)" % trail.size())
	t.check(trail.size() <= 30, "the trail ends instead of running forever (%d)" % trail.size())

	var first_x: float = trail[0]["poly"][0].x
	# A satellite droplet lands up to `splat_satellite_reach_max` (3.4) core radii out, so a foot may print that far short.
	t.check(first_x > SPLAT_AT.x - SPLAT_SIZE * 4.0, "no prints before the splatter (first at x=%.0f)" % first_x)
	# Past the splatter and its satellites no foot can pick blood up again, so each only ever fades.
	var clear: Array = trail.filter(func(m): return m["poly"][0].x > SPLAT_AT.x + SPLAT_SIZE * 4.0)
	var tapering := clear.size() >= 4
	for i in range(2, clear.size()):  # two back = the same foot
		if clear[i]["alpha"] > clear[i - 2]["alpha"] + 0.001:
			tapering = false
	t.check(tapering, "each foot's prints only ever fade along the clean floor (%d prints)" % clear.size())
	t.check(trail[trail.size() - 1]["alpha"] < trail[0]["alpha"], "the last print is fainter than the first")

	var centres: Array = trail.map(func(m): return _centre(m["poly"]))
	var mean_y := 0.0
	for c in centres:
		mean_y += c.y
	mean_y /= centres.size()
	var alternating := 0
	for i in range(1, centres.size()):
		if (centres[i].y - mean_y) * (centres[i - 1].y - mean_y) < 0.0:
			alternating += 1
	t.check(alternating >= (centres.size() - 1) * 0.7, "left and right feet alternate (%d of %d)" % [alternating, centres.size() - 1])


## Mean of a polygon's points.
func _centre(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / poly.size()
