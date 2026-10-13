extends GameTest

## A piece of furniture shoved out of a puddle drags the blood with it: it lays streaks on the clean floor
## beyond the puddle that fade as the blood runs out, and lays nothing while it sits still (the switch is
## object_smear_switch_off).

const SPLAT_AT := Vector2(300, 200)
const SPLAT_SIZE := 30.0


func describe() -> Dictionary:
	return {
		"name": "A pushed object smears blood out of a puddle",
		"description": "A puppet pushes a chair out of a splatter: streaks appear past the splatter, fade, and none appear while the chair is still.",
		"tags": ["blood", "smear", "pushable"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", SPLAT_AT)
	s.actor(&"pusher", &"puppet", Vector2(240, 200))
	s.camera_follow([&"chair"])


func run(t: TestContext) -> void:
	BloodSpawner.splat(t.world, SPLAT_AT, SPLAT_SIZE, Vector2.RIGHT, 0.0, [])
	await t.seconds(0.5)
	var layer := BloodDecals.find(t.object(&"chair").get_parent())
	t.expect_eq(layer.ribbon_count() if layer else 0, 0, "a chair at rest in the blood smears nothing")

	t.puppet(&"pusher").walk(Vector2.RIGHT)
	await t.until(func(): return t.object(&"chair").global_position.x > 460.0, 10.0, "the chair is pushed out of the puddle")
	t.screenshot("chair_smear_mid")
	await t.until(func(): return t.object(&"chair").global_position.x > 700.0, 10.0, "the chair is pushed across")
	t.puppet(&"pusher").stop()
	await t.frames(2)
	t.screenshot("chair_smear")
	layer = BloodDecals.find(t.object(&"chair").get_parent())
	if not t.require(layer != null and layer.ribbon_count() > 0, "the chair left streaks"):
		return
	var ribbons: Array = layer.items().filter(func(m): return m["kind"] == "ribbon")
	var beyond := ribbons.filter(func(m): return (m["points"] as PackedVector2Array)[-1].x > SPLAT_AT.x + SPLAT_SIZE * 2.5)
	t.check(not beyond.is_empty(), "streaks reach past the puddle (%d of %d)" % [beyond.size(), ribbons.size()])
	# No hard edge: a ribbon eases in from nothing, steps smoothly, and stays faint over the puddle itself.
	var longest: Dictionary = ribbons[0]
	for m in ribbons:
		if (m["points"] as PackedVector2Array).size() > (longest["points"] as PackedVector2Array).size():
			longest = m
	var widths: PackedFloat32Array = longest["widths"]
	var alphas: PackedFloat32Array = longest["alphas"]
	t.check(widths.size() >= 6, "a streak runs a good way (%d samples)" % widths.size())
	t.check(alphas[0] < 0.02, "a streak starts from nothing (%.2f)" % alphas[0])
	var jump := 0.0
	var over_puddle := 0.0
	for m in ribbons:
		var a: PackedFloat32Array = m["alphas"]
		var pts: PackedVector2Array = m["points"]
		for i in a.size():
			if i > 0:
				jump = maxf(jump, a[i] - a[i - 1])  # rises only: falling into blood may be quick
			if pts[i].distance_to(SPLAT_AT) < SPLAT_SIZE * 0.8:
				over_puddle = maxf(over_puddle, a[i])
	t.check(jump < 0.2, "a streak swells out gradually, no hard start (%.2f)" % jump)
	t.check(over_puddle < 0.15, "streaks are see-through over the puddle itself (%.2f)" % over_puddle)
	var peak := 0.0
	var widest := 0.0
	for i in alphas.size():
		peak = maxf(peak, alphas[i])
		widest = maxf(widest, widths[i])
	t.check(alphas[alphas.size() - 1] < peak and widths[widths.size() - 1] < widest, "the streak thins and fades")
	# And it is not a ruler line: some ribbon strays from its end-to-end line.
	var stray := 0.0
	for m in ribbons:
		stray = maxf(stray, _stray(m["points"]))
	t.check(stray > 0.6, "streaks wander off a straight line (%.2f px)" % stray)


## The farthest a ribbon's samples lie from the straight line between its ends (px).
func _stray(pts: PackedVector2Array) -> float:
	if pts.size() < 3:
		return 0.0
	var a := pts[0]
	var b := pts[pts.size() - 1]
	if a.distance_to(b) < 0.001:
		return 0.0
	var worst := 0.0
	for p in pts:
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		worst = maxf(worst, p.distance_to(closest))
	return worst
