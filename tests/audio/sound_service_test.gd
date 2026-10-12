extends GameTest

## How the Sound service plays: a category never has more voices sounding than its cap (the oldest is cut off
## for the newest), voices free themselves when their clip is done, repeated events vary but never repeat a
## variant back to back, the same events after a reset play the same way, and none of it touches the gameplay
## RNG (a seeded `randf()` is unmoved by a burst of sounds). Range is checked on the pure function the service
## uses for it: a view centred somewhere, at some zoom.

const Probe := preload("res://tests/_audio/sound_probe.gd")
const SoundService := preload("res://scenes/audio/sound.gd")  # for its static range function; the autoload is an instance


func describe() -> Dictionary:
	return {
		"name": "The Sound service caps, frees, varies and stays out of the gameplay RNG",
		"description": "Voice caps per category, voices freeing after their clip, variant and pitch variety, reset repeatability, RNG isolation and the zoom-scaled range.",
		"tags": ["sound", "service", "voices"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	s.set_static(SoundConfig, &"category_voices", { &"shot": 6, &"impact": 8, &"footstep": 3 })


func _step(at: Vector2 = Vector2(400, 250), foot: int = 0) -> void:
	EventBus.post(&"footfall", { "position": at, "foot": foot, "speed": 150.0, "running": false })


func run(t: TestContext) -> void:
	# --- Voice caps: ten footsteps at once, three voices.
	Sound.reset()
	for i in 10:
		_step()
	t.expect_eq(Probe.sounds(t, &"footstep").size(), 10, "every step is announced")
	t.expect_eq(Sound.active(&"footstep"), 3, "but only three voices sound (the cap)")
	t.expect_eq(Sound.active(&"shot"), 0, "and no other category is touched")
	# A shot still gets a voice while the steps hold theirs.
	EventBus.post(&"shot", { "position": Vector2(400, 250), "gun": &"pistol" })
	t.expect_eq(Sound.active(&"shot"), 1, "a shot sounds beside the steps")
	t.expect_eq(Sound.active(&"footstep"), 3, "without costing a step its voice")
	t.expect_eq(Sound.active(), 4, "four voices in all")

	# --- Voices free themselves once their clip has played.
	await t.seconds(1.5)
	t.expect_eq(Sound.active(), 0, "after the clips end no voice is sounding")

	# --- Variety: many identical events do not repeat one clip.
	Sound.reset()
	var from := Probe.sounds(t, &"footstep").size()
	for i in 24:
		_step()
		await t.frames(1)
	var steps := Probe.sounds(t, &"footstep").slice(from)
	var variants := {}
	var pitches := {}
	var repeats := 0
	for i in steps.size():
		variants[steps[i]["variant"]] = true
		pitches[snappedf(steps[i]["pitch"], 0.001)] = true
		if i > 0 and steps[i]["variant"] == steps[i - 1]["variant"]:
			repeats += 1
	var wanted := int(SoundConfig.category_variants[&"footstep"])
	t.check(variants.size() >= wanted - 1, "a step draws on its many takes (%d of %d variants used)" % [variants.size(), wanted])
	t.expect_eq(repeats, 0, "the same variant never plays twice in a row")
	t.check(pitches.size() > 12, "pitch varies from step to step (%d distinct pitches)" % pitches.size())
	var swing: float = SoundConfig.pitch_jitter * SoundConfig.category_jitter_scale[&"footstep"]
	var lo := 9.0
	var hi := -9.0
	var quietest := 99.0
	var loudest := -99.0
	for s in steps:  # all left feet, which ring at 0.97 of the base pitch
		var off: float = s["pitch"] / 0.97 - 1.0
		t.check(absf(off) <= swing + 0.001, "the pitch stays within the footstep jitter (%.3f)" % s["pitch"])
		lo = minf(lo, off)
		hi = maxf(hi, off)
		quietest = minf(quietest, s["volume_db"])
		loudest = maxf(loudest, s["volume_db"])
	t.check(hi - lo > swing, "steps use a good part of that pitch range (%.3f wide of %.3f)" % [hi - lo, swing * 2.0])
	t.check(loudest - quietest > SoundConfig.volume_jitter_db, "and differ in loudness (%.1f dB apart)" % (loudest - quietest))

	# --- Reset makes the service start over: the same events play the same way.
	var run_a := _burst(t)
	await t.seconds(0.5)
	var run_b := _burst(t)
	t.check(run_a == run_b, "after a reset the same burst picks the same variants and pitches")
	t.check(run_a.size() == 12, "(a burst of %d)" % run_a.size())

	# --- Sound never draws from the gameplay RNG.
	seed(4321)
	var expected := randf()
	seed(4321)
	for i in 20:
		_step()
		EventBus.post(&"shot", { "position": Vector2(400, 250), "gun": &"rifle" })
		EventBus.post(&"hit", { "position": Vector2(400, 250), "outcome": &"penetrate", "material": "wood" })
	t.expect_eq(randf(), expected, "a burst of sounds leaves the gameplay RNG where it was")

	# --- Range: the pure function the service asks.
	var centre := Vector2(1000, 1000)
	SoundConfig.category_range = { &"footstep": 900.0, &"shot": 2400.0 }
	t.check(SoundService.reach_from(&"footstep", centre + Vector2(800, 0), centre, 1.0) > 0.0, "a step 800 px away is heard at zoom 1")
	t.expect_eq(SoundService.reach_from(&"footstep", centre + Vector2(1000, 0), centre, 1.0), 0.0, "one 1000 px away is not")
	t.check(SoundService.reach_from(&"footstep", centre + Vector2(1000, 0), centre, 0.5) > 0.0, "but is once the camera has zoomed out to 0.5")
	t.expect_eq(SoundService.reach_from(&"footstep", centre + Vector2(500, 0), centre, 2.0), 0.0, "and one 500 px away is lost zoomed in to 2")
	t.check(SoundService.reach_from(&"shot", centre + Vector2(2300, 0), centre, 1.0) > 0.0, "a shot carries much farther than a step")
	SoundConfig.range_follows_zoom = false
	t.check(SoundService.reach_from(&"footstep", centre + Vector2(1000, 0), centre, 0.5) == 0.0, "with zoom-following off the range is fixed")
	SoundConfig.range_follows_zoom = true
	# (the statics changed here are restored by the harness, like any set_static)


## A fixed burst of 12 events from a reset service: the (variant, pitch) of each sound, in order.
func _burst(t: TestContext) -> Array:
	Sound.reset()
	var from := Probe.sounds(t).size()
	for i in 6:
		_step(Vector2(400, 250), i % 2)
		EventBus.post(&"shot", { "position": Vector2(400, 250), "gun": &"smg", "power": 0.8 })
	var out: Array = []
	for s in Probe.sounds(t).slice(from):
		out.append([s["profile"], s["variant"], snappedf(s["pitch"], 0.0001), snappedf(s["volume_db"], 0.0001)])
	return out
