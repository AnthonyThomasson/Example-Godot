extends GameTest

## A wounded character that dies stops dripping: its BloodWound is stopped on death and the bleed-out
## pool (not further drops) takes over.


func describe() -> Dictionary:
	return {
		"name": "Death stops a wound's dripping",
		"description": "A wounded character is killed; no BloodSplat lands after the death, while the bleed-out BloodPool still spreads.",
		"tags": ["blood", "wound", "drip", "death"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"physics.blood", true)
	s.actor(&"victim", &"puppet", Vector2(350, 200), { "max_health": 100.0 })


func _hit(victim: Node, damage: float) -> void:
	var hit := HitInfo.new()
	hit.position = victim.global_position + Vector2(10, 0)
	hit.normal = Vector2.RIGHT
	hit.direction = Vector2.LEFT
	hit.damage = damage
	victim.take_hit(hit)


func run(t: TestContext) -> void:
	var victim := t.actor(&"victim")
	await t.frames(2)
	_hit(victim, 20.0)  # leaves a drip budget of 4
	await t.frames(1)
	_hit(victim, 100.0)  # kills it
	if not t.require(victim.is_dead, "the victim dies"):
		return
	var after_death: int = t.spawned("BloodSplat").size()
	await t.seconds(BloodConfig.drip_interval_max + 2.0)
	t.expect_eq(t.spawned("BloodSplat").size(), after_death, "no drips land after death")
	t.check(not t.spawned("BloodPool").is_empty(), "the bleed-out pool spreads instead")
