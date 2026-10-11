extends GameTest

## Every gun has its own penetration (`GunConfig` `penetration`, with its muzzle speed). A wall stops a pistol
## round and an SMG round, but an assault rifle round goes through it and hits the target standing behind.

const GUNS := {
	&"pistol": [&"pistol_man", &"pistol_target", 3],
	&"smg": [&"smg_man", &"smg_target", 5],
	&"rifle": [&"rifle_man", &"rifle_target", 6],
}


func describe() -> Dictionary:
	return {
		"name": "Only the rifle shoots through a wall",
		"description": "Each gun fires at a target standing just outside the arena's wall: the pistol and the SMG are stopped by it, the assault rifle's round goes through and wounds the target.",
		"tags": ["item", "gun", "penetration", "wall", "projectile"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.switch(&"projectile.flyover", false)  # a character is partial cover; make every shot that arrives land
	# Dead straight: it's the wall being tested, not the aim.
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	var y := 100.0
	for gun: StringName in GUNS:
		s.actor(GUNS[gun][0], &"puppet", Vector2(600, y), { "start_slot": GUNS[gun][2] })
		# Just beyond the east wall (it runs along x = 800, 12 px thick).
		s.actor(GUNS[gun][1], &"puppet", Vector2(840, y), { "max_health": 400.0 })
		y += 150.0


func run(t: TestContext) -> void:
	for gun: StringName in GUNS:
		t.puppet(GUNS[gun][0]).aim_at(t.actor(GUNS[gun][1]))
	await t.seconds(0.5)
	for gun: StringName in GUNS:
		t.check(not t.actor(GUNS[gun][0]).weapon_blocked(), "the %s's barrel is clear of the wall" % gun)
	# Three rounds each, so a single unlucky ricochet or deflection can't decide it.
	for i in 3:
		for gun: StringName in GUNS:
			t.puppet(GUNS[gun][0]).shoot()
		await t.seconds(0.4)
	await t.seconds(1.0)

	var rifle_target := t.actor(GUNS[&"rifle"][1])
	t.check(rifle_target.health < rifle_target.max_health,
		"the rifle's round went through the wall and wounded the target (%.0f / %.0f)" % [rifle_target.health, rifle_target.max_health])
	for gun: StringName in [&"pistol", &"smg"]:
		var target := t.actor(GUNS[gun][1])
		t.check(target.health == target.max_health, "the wall stopped the %s's rounds (target at %.0f / %.0f)" % [gun, target.health, target.max_health])
		t.check(t.actor(GUNS[gun][0]).ammo(GUNS[gun][2]) < t.actor(GUNS[gun][0]).ammo_capacity(GUNS[gun][2]),
			"the %s did fire" % gun)
