extends GameTest

## Reloading is heard in two beats: the magazine coming out when the reload starts and going in (and the action
## racked) when it finishes, a reload-time later. Each gun has its own sounds, a reload that is interrupted never
## finishes (so is never heard to), and a gun that cannot reload makes none.

const Probe := preload("res://tests/_audio/sound_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Reloading sounds out when it starts and in when it finishes",
		"description": "Pistol, SMG and rifle reloads make reload/<gun>/out at once and reload/<gun>/in after their reload time; switching weapons mid-reload leaves only the first; an empty gun with no spare magazine makes none.",
		"tags": ["sound", "reload", "gun"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	s.actor(&"pistol_man", &"puppet", Vector2(100, 80), { "start_slot": 3, "start_rounds": 2 })
	s.actor(&"smg_man", &"puppet", Vector2(100, 190), { "start_slot": 5, "start_rounds": 2 })
	s.actor(&"rifle_man", &"puppet", Vector2(100, 300), { "start_slot": 6, "start_rounds": 2 })
	s.actor(&"fickle_man", &"puppet", Vector2(100, 410), { "start_slot": 3, "start_rounds": 2 })
	s.actor(&"dry_man", &"puppet", Vector2(100, 520), { "start_slot": 3, "start_rounds": 0, "spare_magazine_types": [] })


func run(t: TestContext) -> void:
	await t.seconds(0.3)
	var started := t.time
	for who in [&"pistol_man", &"smg_man", &"rifle_man", &"fickle_man", &"dry_man"]:
		t.puppet(who).reload()
	await t.frames(3)

	# --- The first beat is immediate.
	var heard := Probe.sounds(t, &"reload")
	var profiles := Probe.profiles(heard)
	for profile in [&"reload/pistol/out", &"reload/smg/out", &"reload/rifle/out"]:
		t.check(profiles.has(profile), "%s sounded as the reload began" % profile)
	t.expect_eq(heard.filter(func(d): return d["profile"] == &"reload/pistol/out").size(), 2, "the pistol is reloaded by two men (the plain one and the fickle one)")
	t.check(not heard.any(func(d): return String(d["profile"]).ends_with("/in")), "nobody has finished yet")
	t.check(not heard.any(func(d): return d["position"].distance_to(Vector2(100, 520)) < 80.0), "the man with no magazine to load made no sound")

	# --- One changes his mind: switching to fists cancels the reload.
	await t.seconds(0.5)
	t.puppet(&"fickle_man").select_slot(2)

	# --- The second beat arrives when the reload is done, in each gun's own time.
	var times := {}
	for pair in [[&"reload/pistol/in", 1.5], [&"reload/smg/in", 1.8], [&"reload/rifle/in", 2.4]]:
		var profile: StringName = pair[0]
		if t.require(await t.until(func(): return Probe.profiles(Probe.sounds(t, &"reload")).has(profile), 4.0), "%s sounded" % profile):
			var at: float = 0.0
			for e in t.events:
				if e["topic"] == &"sound" and e["data"]["profile"] == profile:
					at = e["time"]
					break
			times[profile] = at - started
			t.check(absf(at - started - pair[1]) < 0.3, "%s came a reload-time later (%.2f s, expected %.1f)" % [profile, at - started, pair[1]])
	t.check(times.get(&"reload/pistol/in", 9.0) < times.get(&"reload/smg/in", 0.0) and times.get(&"reload/smg/in", 9.0) < times.get(&"reload/rifle/in", 0.0),
		"the longer the gun's reload, the later its second beat")

	await t.seconds(0.8)
	var finished := Probe.sounds(t, &"reload").filter(func(d): return String(d["profile"]).ends_with("/in"))
	t.expect_eq(finished.size(), 3, "three reloads finished (the pistol, SMG and rifle), the cancelled one did not")
	t.check(not t.events_of(&"reload", func(d): return d["stage"] == &"done" and d["character"] == t.actor(&"fickle_man")).size() > 0,
		"the cancelled reload never posted a finish")
	# The event names the gun.
	t.check(t.happened(&"reload", func(d): return d["stage"] == &"start" and d["gun"] == &"rifle" and d["power"] > 2.0), "the start event names the rifle and its power")
