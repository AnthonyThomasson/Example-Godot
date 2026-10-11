extends GameTest

## A hit on a sturdy character sprays splatters at once, then the wound drips: each BloodSplat after
## the spray lands 3..10 s after the one before (BloodConfig.drip_interval_min/max), and the drips stop
## once the hit's budget (damage * drips_per_damage) is spent.

const HIT_DAMAGE := 10.0  # 2 spray splatters, 2 drips


func describe() -> Dictionary:
	return {
		"name": "A wound sprays, then drips every 3 to 10 seconds",
		"description": "A hit throws an immediate splatter spray, then drops of blood land 3 to 10 s apart until the wound's drip budget is spent.",
		"tags": ["blood", "wound", "drip", "splat"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"physics.blood", true)
	s.actor(&"victim", &"puppet", Vector2(350, 200), { "max_health": 1000.0 })


func run(t: TestContext) -> void:
	var victim := t.actor(&"victim")
	await t.frames(2)
	var hit := HitInfo.new()
	hit.position = victim.global_position + Vector2(10, 0)
	hit.normal = Vector2.RIGHT
	hit.direction = Vector2.LEFT
	hit.damage = HIT_DAMAGE
	var hit_time := t.time
	victim.take_hit(hit)
	await t.frames(1)

	var spray: int = t.spawned("BloodSplat").size()
	t.check(spray >= 1, "the hit sprays splatter at once (%d)" % spray)

	# Note the sim time of each splatter that lands after the spray.
	var drips_wanted := ceili(HIT_DAMAGE * BloodConfig.drips_per_damage)
	var times: Array = []
	var seen := spray
	var deadline := t.time + BloodConfig.drip_interval_max * drips_wanted + 2.0
	while times.size() < drips_wanted and t.time < deadline:
		await t.frames(1)
		var now: int = t.spawned("BloodSplat").size()
		while seen < now:
			times.append(t.time)
			seen += 1
	if not t.require(times.size() == drips_wanted, "the wound drips %d times (saw %d)" % [drips_wanted, times.size()]):
		return
	var previous := hit_time
	for i in times.size():
		var gap: float = times[i] - previous
		t.check(gap >= BloodConfig.drip_interval_min - 0.1 and gap <= BloodConfig.drip_interval_max + 0.1,
			"drip %d lands %.1fs after the last (3..10 s)" % [i + 1, gap])
		previous = times[i]

	var count: int = t.spawned("BloodSplat").size()
	await t.seconds(BloodConfig.drip_interval_max + 1.0)
	t.expect_eq(t.spawned("BloodSplat").size(), count, "no more drips once the budget is spent")
