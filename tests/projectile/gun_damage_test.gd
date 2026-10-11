extends GameTest

## Every gun deals its own damage (`GunConfig` `damage`, on top of the bullet's base). Each puppet fires one
## round, straight (the spread is switched off), at a target in the open; the hit event carries what it dealt.

const GUNS := {
	&"pistol": [&"pistol_man", &"pistol_target", 3],
	&"smg": [&"smg_man", &"smg_target", 5],
	&"rifle": [&"rifle_man", &"rifle_target", 6],
}

## The bullet's own base damage before the gun adds its own (`Projectile.damage`).
const BASE_DAMAGE := 10.0


func describe() -> Dictionary:
	return {
		"name": "Each gun hits for its own damage",
		"description": "One round from each gun at a target in the open; the damage dealt is the bullet's base plus the gun's, the rifle highest and the SMG lowest.",
		"tags": ["item", "gun", "damage", "hit event"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.switch(&"projectile.flyover", false)  # a character is partial cover; make every shot land
	# Dead straight, so each round meets its target squarely and the damage is the gun's alone.
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	var y := 100.0
	for gun: StringName in GUNS:
		s.actor(GUNS[gun][0], &"puppet", Vector2(100, y), { "start_slot": GUNS[gun][2] })
		s.actor(GUNS[gun][1], &"puppet", Vector2(450, y), { "max_health": 400.0 })
		y += 150.0


func run(t: TestContext) -> void:
	for gun: StringName in GUNS:
		t.puppet(GUNS[gun][0]).aim_at(t.actor(GUNS[gun][1]))
	await t.seconds(0.5)
	for gun: StringName in GUNS:
		t.puppet(GUNS[gun][0]).shoot()
	var landed := func() -> bool:
		for gun: StringName in GUNS:
			if t.events_of(&"hit", func(d): return d["victim"] == t.actor(GUNS[gun][1])).is_empty():
				return false
		return true
	if not t.require(await t.until(landed, 2.0), "each gun's round lands on its target"):
		return

	var dealt := {}
	for gun: StringName in GUNS:
		var victim := t.actor(GUNS[gun][1])
		var hit: Dictionary = t.events_of(&"hit", func(d): return d["victim"] == victim)[0]
		dealt[gun] = float(hit["damage"])
		var nominal := BASE_DAMAGE + float(GunConfig.row(gun)["damage"])
		# The muzzle is a few px off the aim line, so the round meets the round body a little off square.
		t.check(dealt[gun] <= nominal + 0.01 and dealt[gun] >= nominal * 0.8,
			"the %s deals about %.0f (dealt %.1f)" % [gun, nominal, dealt[gun]])
	t.check(dealt[&"rifle"] > dealt[&"pistol"] and dealt[&"pistol"] > dealt[&"smg"],
		"the rifle hits hardest, the SMG lightest (rifle %.1f, pistol %.1f, SMG %.1f)" % [dealt[&"rifle"], dealt[&"pistol"], dealt[&"smg"]])
