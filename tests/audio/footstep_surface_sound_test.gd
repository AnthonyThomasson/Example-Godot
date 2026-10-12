extends GameTest

## A walker's steps sound like the floor under them. A puppet crosses an arena whose west half is oak planks and
## whose east half has carpet laid over it: its steps are wood while it is on the planks and carpet once it is on
## the carpet, each foot lands in turn at a walking cadence, and the same walker running steps with the run sound.

const Probe := preload("res://tests/_audio/sound_probe.gd")
const CARPET := Rect2(450, 50, 330, 400)


func describe() -> Dictionary:
	return {
		"name": "Footsteps follow the floor and the gait",
		"description": "A puppet walks from planks onto carpet and then runs back: wood then carpet footsteps while walking, run footsteps when running, feet alternating at a walking cadence.",
		"tags": ["sound", "footstep", "surface", "walk"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	s.actor(&"walker", &"puppet", Vector2(80, 250))


func run(t: TestContext) -> void:
	FloorFactory.spawn(CARPET, {
		"art": "floor", "color": Color(0.7, 0.7, 0.7), "material": "fabric", "art_opts": { "pattern": "carpet" },
	}, "TestCarpet", t.world)
	await t.frames(2)
	var walker := t.puppet(&"walker")
	var body := t.actor(&"walker")

	walker.walk(Vector2.RIGHT)
	if not t.require(await t.until(func(): return body.global_position.x > 720.0, 10.0, "the walker crosses the room"), "it got across"):
		return
	walker.stop()
	var steps := Probe.sounds(t, &"footstep")
	t.check(steps.size() >= 12, "it took a good number of steps (%d)" % steps.size())
	# 150 px/s over 640 px is ~4.3 s; a stride of 48 px per step pair means ~6 steps/s.
	t.check(steps.size() <= 40, "at a walking cadence, not a stampede (%d)" % steps.size())

	var on_wood := steps.filter(func(d): return d["position"].x < CARPET.position.x - 25.0)
	var on_carpet := steps.filter(func(d): return d["position"].x > CARPET.position.x + 25.0)
	t.check(on_wood.size() >= 4 and on_carpet.size() >= 4, "steps on both floors (%d wood, %d carpet)" % [on_wood.size(), on_carpet.size()])
	t.expect_eq(Probe.profiles(on_wood), [&"footstep/wood/walk"], "every step on the planks sounded like wood")
	t.expect_eq(Probe.profiles(on_carpet), [&"footstep/carpet/walk"], "every step on the carpet sounded like carpet")

	var feet := t.events_of(&"footfall").map(func(d): return d["foot"])
	var alternating := true
	for i in range(1, feet.size()):
		if feet[i] == feet[i - 1]:
			alternating = false
	t.check(alternating and feet.size() >= 12, "the feet landed in turn (%d steps)" % feet.size())

	# Running back across the whole room: run steps, and fewer of them per distance than walking.
	var before := steps.size()
	var start_x: float = body.global_position.x
	walker.set_run(true)
	walker.walk(Vector2.LEFT)
	await t.until(func(): return body.global_position.x < 150.0, 8.0, "the walker runs back")
	walker.stop()
	var ran := Probe.sounds(t, &"footstep").slice(before)
	t.check(ran.size() >= 6, "it took steps running (%d)" % ran.size())
	t.check(ran.filter(func(d): return d["position"].x > CARPET.position.x + 25.0).all(func(d): return d["profile"] == &"footstep/carpet/run"),
		"on the carpet they sounded like running on carpet")
	t.check(ran.filter(func(d): return d["position"].x < CARPET.position.x - 25.0).all(func(d): return d["profile"] == &"footstep/wood/run"),
		"and on the planks like running on wood")
	t.check(not Probe.profiles(ran).has(&"footstep/carpet/walk"), "none of them like walking")
	var walk_per_px := float(steps.size()) / (720.0 - 80.0)
	var run_per_px: float = float(ran.size()) / (start_x - body.global_position.x)
	t.check(run_per_px < walk_per_px, "a runner's strides are longer (%.3f vs %.3f steps/px)" % [run_per_px, walk_per_px])
