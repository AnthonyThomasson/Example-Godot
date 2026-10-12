extends GameTest

## Each gun has its own report: the pistol, SMG and assault rifle each fire with their own shot sound, at the
## muzzle, and the shot event names the gun and the shooter. A held trigger on an automatic gun sounds every round,
## and a gun that cannot fire (empty) makes no shot at all.

const Probe := preload("res://tests/_audio/sound_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Every gun fires with its own report",
		"description": "Pistol, SMG and rifle shots make shot/pistol, shot/smg and shot/rifle sounds at the muzzle; a held SMG sounds each round; an empty gun is silent.",
		"tags": ["sound", "shot", "gun"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	s.actor(&"pistol_man", &"puppet", Vector2(100, 80), { "start_slot": 3 })
	s.actor(&"smg_man", &"puppet", Vector2(100, 200), { "start_slot": 5 })
	s.actor(&"rifle_man", &"puppet", Vector2(100, 320), { "start_slot": 6 })
	s.actor(&"empty_man", &"puppet", Vector2(100, 440), { "start_slot": 3, "start_rounds": 0, "spare_magazine_types": [] })


func run(t: TestContext) -> void:
	for who in [&"pistol_man", &"smg_man", &"rifle_man", &"empty_man"]:
		t.puppet(who).aim_at(t.actor(who).global_position + Vector2(600, 0))
	await t.seconds(0.5)

	t.puppet(&"pistol_man").shoot()
	t.puppet(&"rifle_man").shoot()
	t.puppet(&"empty_man").shoot()
	await t.seconds(0.3)
	var shots := Probe.sounds(t, &"shot")
	t.expect_eq(shots.size(), 2, "the pistol and the rifle each sounded once, the empty gun not at all")
	t.check(Probe.profiles(shots).has(&"shot/pistol"), "a pistol report")
	t.check(Probe.profiles(shots).has(&"shot/rifle"), "a rifle report")

	for pair in [[&"pistol_man", &"pistol"], [&"rifle_man", &"rifle"]]:
		var man: Node2D = t.actor(pair[0])
		var heard := shots.filter(func(d): return d["profile"] == StringName("shot/%s" % pair[1]))
		if t.check(heard.size() == 1, "one %s report" % pair[1]):
			t.check(heard[0]["position"].distance_to(man.global_position) < 80.0, "it came from where the %s stood" % pair[1])
	var event: Dictionary = t.events_of(&"shot", func(d): return d["gun"] == &"rifle")[0]
	t.expect_eq(event["attacker"], t.actor(&"rifle_man"), "the shot event names the shooter")
	t.check(event["automatic"], "and says the rifle is automatic")
	t.check(event["power"] > 2.0, "and how hard-hitting its round is (%.1f)" % event["power"])
	t.check(not t.events_of(&"shot", func(d): return d["gun"] == &"pistol")[0]["automatic"], "while the pistol is not")
	t.check(not t.happened(&"shot", func(d): return d["attacker"] == t.actor(&"empty_man")), "the empty gun posted no shot event")

	# A held trigger: every round sounds.
	var before := Probe.sounds(t, &"shot", "shot/smg").size()
	t.puppet(&"smg_man").hold_fire(true)
	await t.seconds(0.6)
	t.puppet(&"smg_man").hold_fire(false)
	var rounds := Probe.sounds(t, &"shot", "shot/smg").size() - before
	t.check(rounds >= 5, "the held SMG sounded round after round (%d in 0.6 s)" % rounds)
	t.check(rounds <= 10, "but no faster than its fire rate (%d)" % rounds)
	t.check(Sound.active(&"shot") <= SoundConfig.category_voices[&"shot"], "within the shot voice cap (%d sounding)" % Sound.active(&"shot"))
