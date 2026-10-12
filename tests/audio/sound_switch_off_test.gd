extends GameTest

## The twin of the sound tests with the `audio.sound` switch off: a real gun is fired, a punch lands and a
## walker steps, yet the Sound service synthesizes, plays and announces nothing. The events themselves still
## happen (the shot, the hit, the footfall are posted regardless: the AI listens to some of them).

const Probe := preload("res://tests/_audio/sound_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "No sound with the sound switch off",
		"description": "audio.sound off: shots, hits and footsteps still happen and are posted on the bus, but make no `sound` and no voice.",
		"tags": ["sound", "switch"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"audio.sound", false)
	s.switch(&"projectile.flyover", false)
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	s.actor(&"shooter", &"puppet", Vector2(120, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(620, 250), { "max_health": 400.0 })
	s.actor(&"walker", &"puppet", Vector2(150, 400))


func run(t: TestContext) -> void:
	Sound.reset()
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"hit", func(d): return d["victim"] == t.actor(&"target")), 2.0), "the shot lands"):
		return
	await t.until(func(): return t.happened(&"footfall"), 2.0, "the walker steps")
	await t.seconds(0.5)

	t.check(t.happened(&"shot"), "the shot was posted")
	t.check(t.happened(&"footfall"), "the footfall was posted")
	t.expect_eq(Probe.sounds(t).size(), 0, "yet nothing made a sound")
	t.expect_eq(Sound.active(), 0, "and no voice is sounding")
