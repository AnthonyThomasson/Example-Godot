extends GameTest

## P2 (`docs/grenades.md`, Performance): a frag and a stun going off together in a crowded, furnished room keep the frame
## smooth. Twelve pieces of furniture and eight characters stand round the middle of an arena, blood, debris, hit particles and
## sound on; a puppet throws a frag into the middle and then a stun timed to go off with it (through the controller contract:
## select the slot, aim, click). The blast and its fragments, the flash and bang, the FX, scorch, blood, debris, ragdolls and
## sounds all land in one frame and the two seconds after it, and those frames meet the smooth standard (`Perf.SMOOTH_*`).
## The runner's camera frames every actor on a player's screen, so every body is drawn. Headless measures the CPU only (the drawing
## calls included, not the GPU); `tools/run_tests.sh --windowed` measures the render too.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")

const CENTRE := Vector2(600, 400)
const THROWER_AT := Vector2(200, 400)  ## 400 px off, inside the throw range, outside the blast; the lane along y = 400 is kept clear
## The burst frames and the 2 s after them: the stun goes off a few frames after the frag (its release lands on a frame), so the
## window has a few frames to spare, checked below against the bursts' real times.
const MEASURE_FRAMES := 130
const AFTER_S := 2.0
## The furniture round the middle (catalogue key, offset from the centre): a sitting room's worth, none on the thrower's lane.
const PIECES := [
	["sofa", Vector2(0, -150)], ["coffee_table", Vector2(0, -80)], ["armchair", Vector2(-140, -110)], ["armchair", Vector2(140, -110)],
	["bookshelf", Vector2(-60, -230)], ["bookshelf", Vector2(60, -230)], ["chair", Vector2(-120, 90)], ["chair", Vector2(120, 90)],
	["desk", Vector2(0, 160)], ["chair", Vector2(0, 110)], ["wardrobe", Vector2(230, 150)], ["side_table", Vector2(-230, 140)],
]
## The eight characters, from 60 to 230 px off the burst, some in the open, some behind the furniture.
const PEOPLE := [
	Vector2(60, 30), Vector2(-70, -30), Vector2(150, 30), Vector2(-160, 40), Vector2(90, -190), Vector2(-200, -170),
	Vector2(220, -40), Vector2(-60, 220),
]


func describe() -> Dictionary:
	return {
		"name": "A frag and a stun going off in a crowded room keep it smooth",
		"description": "A frag and a stun burst together among 8 characters and 12 pieces of furniture (blood, debris and sound on); the burst frame and the 2 s after it average under 16.7 ms, p95 under 20 and no frame over 33.4.",
		"tags": ["grenade", "frag", "stun", "blood", "debris", "crowd"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 800))
	s.switch(&"physics.blood", true)
	s.switch(&"physics.debris", true)
	s.switch(&"physics.hit_particles", true)
	s.switch(&"audio.sound", true)
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would change what is drawn, so what is measured
	s.switch(&"nav.rebake", false)  # the blast shoves the pieces into overlaps; re-baking is costed in perf/grenade_match_stress
	for i in PIECES.size():
		s.object(StringName("piece%d" % i), PIECES[i][0], CENTRE + PIECES[i][1])
	for i in PEOPLE.size():
		var at: Vector2 = CENTRE + PEOPLE[i]
		s.actor(StringName("person%d" % i), &"puppet", at, { "start_slot": Probe.PISTOL, "aim_point": at + Vector2.from_angle(i * 0.8) * 100.0 })
	s.actor(&"thrower", &"puppet", THROWER_AT, { "max_health": 1000000.0, "aim_point": CENTRE })


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	_player_screen(t)
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1 and Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a frag and a stun"):
		return

	# The frag first, then the stun once the frag has as long left as the stun's fuse and wind-up: they go off together.
	await Probe.throw_at(t, &"thrower", Probe.FRAG, CENTRE)
	if not t.require(await t.until(func() -> bool: return not Probe.live(t).is_empty(), 1.0), "the frag left the hand"):
		return
	var frag: Node = Probe.live(t)[0]
	await Probe.ready(t, &"thrower", Probe.STUN, CENTRE)
	await t.until(func() -> bool: return not is_instance_valid(frag) or frag.fuse_left() <= Probe.FUSE_STUN + Probe.WINDUP, 4.0)
	t.puppet(&"thrower").shoot()
	if not t.require(await t.until(func() -> bool: return Probe.live(t).size() == 2, 1.0), "the stun left the hand while the frag was live"):
		return

	await t.until(func() -> bool: return not is_instance_valid(frag) or frag.fuse_left() <= 2.0 / 60.0, 4.0)
	var start := t.time
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	var booms := Probe.booms(t)
	if not t.require(booms.size() == 2, "both grenades went off (%d bursts)" % booms.size()):
		return
	var first := minf(float(booms[0]["time"]), float(booms[1]["time"]))
	var last := maxf(float(booms[0]["time"]), float(booms[1]["time"]))
	if not t.require(first >= start and t.time - last >= AFTER_S - 0.05, "the window holds both bursts (at +%.2f and +%.2f s) and the %.0f s after them (it ran %.2f s)" % [first - start, last - start, AFTER_S, t.time - start]):
		return
	Perf.within_frames(t, "frag and stun burst", stats, Perf.SMOOTH_AVG_MS, Perf.SMOOTH_P95_MS, Perf.SMOOTH_MAX_MS)
	var hits := Probe.raw(t, &"hit", func(d: Dictionary) -> bool: return d.get("outcome") == &"blast").size()
	var stunned := Probe.raw(t, &"stun").size()
	var dead := 0
	for i in PEOPLE.size():
		dead += 1 if t.actor(StringName("person%d" % i)).is_dead else 0
	GameLog.say("PERF frag and stun burst: %d blast hits, %d stuns, %d dead, node growth %d" % [hits, stunned, dead, Perf.nodes() - nodes_before])
	t.check(hits >= 4 and stunned >= 4, "the burst struck the crowd (%d blast hits, %d stuns)" % [hits, stunned])


## Headless, the runner's viewport is 64 px square (the camera sees ~160 px of the world), so every body a player would see is
## culled and never drawn. For this test give it the screen a player has (the project's window size, 1152x648), put back as the
## world goes. A windowed run already has that window.
func _player_screen(t: TestContext) -> void:
	if DisplayServer.get_name() != "headless":
		return
	var root := t.world.get_tree().root
	var was := root.size
	root.size = Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	t.world.tree_exiting.connect(func() -> void: root.size = was)
