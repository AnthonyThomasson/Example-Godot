extends GameTest

## With penetration made impossible (a round needs more speed than any gun can give), every impact is a *blocked*
## one: the round embeds where it lands. A chair, a body and a wall are each heard as their material's blocked
## sound, and the same shots do not sound blocked when penetration is normal (the materials test covers that).
## A shot that flies over cover makes no impact sound at all: it never touched anything.

const Probe := preload("res://tests/_audio/sound_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A blocked round sounds embedded, a fly-over is silent",
		"description": "With penetration out of reach, pistol rounds into a chair, a body and a wall make blocked impacts; with fly-over forced on, a shot at a chair makes a shot sound and no impact.",
		"tags": ["sound", "impact", "blocked", "flyover", "projectile"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"projectile.flyover", false)
	s.switch(&"nav.rebake", false)  # shot furniture is shoved into overlaps; re-baking them logs a nav sync error
	s.set_static(BallisticsConfig, &"penetration_min_speed", 1.0e9)
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", straight)
	s.actor(&"at_chair", &"puppet", Vector2(100, 70), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(400, 70))
	s.actor(&"at_body", &"puppet", Vector2(100, 200), { "start_slot": 3 })
	s.actor(&"body", &"puppet", Vector2(400, 200), { "max_health": 500.0 })
	s.actor(&"at_wall", &"puppet", Vector2(100, 330), { "start_slot": 3 })


func run(t: TestContext) -> void:
	t.puppet(&"at_chair").aim_at(Vector2(880, 70))
	t.puppet(&"at_body").aim_at(Vector2(880, 200))
	t.puppet(&"at_wall").aim_at(Vector2(880, 330))
	await t.seconds(0.5)
	for shooter in [&"at_chair", &"at_body", &"at_wall"]:
		t.puppet(shooter).shoot()
	await t.seconds(1.2)

	for case in [[70.0, 400.0, &"impact/wood/blocked/medium", "a chair"], [200.0, 400.0, &"impact/flesh/blocked/medium", "a body"],
			[330.0, 894.0, &"impact/wall/blocked/medium", "the wall"]]:
		var heard := Probe.sounds(t, &"impact").filter(func(d): return absf(d["position"].y - case[0]) < 25.0 and absf(d["position"].x - case[1]) < 45.0)
		if t.check(not heard.is_empty(), "a round stopped by %s was heard" % case[3]):
			t.expect_eq(heard[0]["profile"], case[2], "a blocked round in %s" % case[3])
		t.expect_eq(heard.size(), 1, "and it sounded once (it stopped there)")

	# --- A fly-over: nothing is struck, so only the shot is heard.
	BallisticsConfig.cover_flyover_scale = 1000.0
	Sound.reset()
	var shots_before := Probe.sounds(t, &"shot").size()
	var impacts_before := Probe.sounds(t, &"impact").size()
	t.puppet(&"at_chair").aim_at(Vector2(400, 70))
	await t.seconds(0.4)
	t.puppet(&"at_chair").shoot()
	await t.seconds(0.15)
	# The chair is flown over; the round goes on to the east wall, which is full cover and gets a normal impact.
	await t.seconds(0.6)
	t.expect_eq(Probe.sounds(t, &"shot").size() - shots_before, 1, "the shot was heard")
	var after := Probe.sounds(t, &"impact").slice(impacts_before)
	t.check(after.filter(func(d): return absf(d["position"].x - 400.0) < 45.0).is_empty(), "but the chair it flew over made no impact sound")
