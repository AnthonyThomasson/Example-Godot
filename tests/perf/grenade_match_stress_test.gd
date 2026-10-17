extends GameTest

## P1 (`docs/grenades.md`, Performance): grenades going off in a running match keep it smooth. The 5v5 match of
## `perf/match_5v5_stress` (a generated house, its largest plan, Main's placement and loadouts, nav re-baker, blood, debris, sound and radio on,
## scripted Von), and once the sides are in contact a puppet on the invaders' side (the human's place) throws three frags and
## three stuns among the fighters over about 3 s, through the controller contract (select the slot, aim, click). So the
## burst's whole cost is in the window: the blast and its fragments, the flash and bang, the FX, scorch, blood and debris,
## the sounds, and every NPC's grenade perception, evade planning and re-decision. From the first throw to 3 s after the
## last burst the frames meet the smooth standard (`Perf.SMOOTH_*`). The camera frames the fighters as Main's spectator view does, on a
## player's screen, so every body a player would see is drawn. Headless measures the CPU only (the drawing calls included, not the GPU);
## `tools/run_tests.sh --windowed` measures the render too.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const MatchSpawner := preload("res://scenes/match_spawner.gd")
const OverlayRegistry := preload("res://scenes/ui/overlays/overlay_registry.gd")

const SEED := 7
## The house `perf/match_5v5_stress` measures its match in: the largest plan, pinned (see its comment).
const PLAN := "garage_home"
const PER_SIDE := 5
const WARMUP_S := 6.0
## Frag, stun, frag, stun, frag, stun: one throw every `THROW_EVERY` frames (0.6 s), the click `CLICK_AFTER` frames after the
## slot is picked and the aim set (the facing settles in a frame or two standing; the 0.3 s wind-up is over before the next pick).
const THROWS := [Probe.FRAG, Probe.STUN, Probe.FRAG, Probe.STUN, Probe.FRAG, Probe.STUN]
const THROW_EVERY := 36
const CLICK_AFTER := 15
## How far from the fighter it throws at the thrower stands: inside the throw range, outside the kill radius.
const THROW_DISTANCE := 200.0
## The last click is at frame 195 (3.25 s); the last frag leaves the hand at about 2.95 s and goes off 3 s later, so the last
## burst is near 6 s and the window runs to 3 s after it: 560 frames (9.3 s), checked below against the bursts' real times.
const MEASURE_FRAMES := 560
const AFTER_LAST_S := 3.0
const NODE_GROWTH := 2500


func describe() -> Dictionary:
	return {
		"name": "Grenades in a 5v5 match keep it smooth",
		"description": "In the 5v5 match of perf/match_5v5_stress a puppet throws 3 frags and 3 stuns among the fighters over ~3 s; from the first throw to 3 s after the last burst the average frame stays under 16.7 ms, p95 under 20 and no frame over 33.4.",
		"tags": ["match", "ai", "scripted", "crowd", "grenade", "frag", "stun"],
		"timeout": 60.0,
		# As perf/match_5v5_stress: the match re-bakes the navmesh while furniture is shoved around (a blast shoves a lot of
		# it), and the bake of overlapping footprints is now and then rejected by the engine. A nav bug this test is not about.
		"allowed_logs": ["Navigation map synchronization error", "NavigationPolygon polygon convex partition failed"],
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.vision", true)
	s.switch(&"ai.pursuit", true)
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would change what is drawn, so what is measured
	# Far off the house until its first throw: it plays no part in the warm-up.
	s.actor(&"thrower", &"puppet", Vector2(-3000, -3000), { "faction": &"invader", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters := _spawn_match(t)
	if not t.require(characters.size() == PER_SIDE * 2, "ten combatants spawned (%d)" % characters.size()):
		return
	_player_screen(t)
	var camera := t.world.get_viewport().get_camera_2d()
	if not t.require(camera != null and camera.has_method("frame"), "the runner's camera can frame the fight"):
		return
	camera.frame(characters)
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 3, 3)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 3 and Probe.count(thrower, Probe.STUN) == 3, "the thrower carries 3 frags and 3 stuns"):
		return
	await t.seconds(WARMUP_S)

	var nodes_before := Perf.nodes()
	var start := t.time
	var targets: Array = []
	var throw := func(i: int) -> void:
		var k := int(i / float(THROW_EVERY))
		if k >= THROWS.size():
			return
		var step := i % THROW_EVERY
		if step == 0:
			targets.append(_throw_from(t, characters))
			t.puppet(&"thrower").select_slot(THROWS[k])
		elif step == CLICK_AFTER:
			t.puppet(&"thrower").shoot()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES, throw)
	var end := t.time

	var booms := Probe.booms(t)
	var last := -INF
	for b: Dictionary in booms:
		last = maxf(last, float(b["time"]))
	if not t.require(booms.size() == THROWS.size(), "all six grenades went off inside the window (%d bursts; thrown at %s)" % [booms.size(), str(targets)]):
		return
	if not t.require(end - last >= AFTER_LAST_S - 0.05, "the window runs %.1f s past the last burst (%.2f s after the first throw)" % [end - last, last - start]):
		return
	Perf.within_frames(t, "grenades in a 5v5 match", stats, Perf.SMOOTH_AVG_MS, Perf.SMOOTH_P95_MS, Perf.SMOOTH_MAX_MS)
	var hits := Probe.raw(t, &"hit", func(d: Dictionary) -> bool: return d.get("outcome") == &"blast").size()
	var stunned := Probe.raw(t, &"stun").size()
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF grenades in a 5v5 match: %d blast hits, %d stuns, node growth %d" % [hits, stunned, grown])
	t.check(hits + stunned > 0, "the grenades went off among the fighters (%d blast hits, %d stuns)" % [hits, stunned])
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])


## Stand the thrower `THROW_DISTANCE` from the fighter in the thick of the fight (the living one with the most others near it), on
## the navmesh with a clear line to it, and aim at it. Returns the fighter's position.
func _throw_from(t: TestContext, characters: Array) -> Vector2:
	var target: Node2D = null
	var crowd := -1
	for c: Node2D in characters:
		if c.is_dead:
			continue
		var near := 0
		for o: Node2D in characters:
			if o != c and not o.is_dead and o.global_position.distance_to(c.global_position) < 300.0:
				near += 1
		if near > crowd:
			crowd = near
			target = c
	if target == null:
		return Vector2.ZERO
	var map := t.world.get_world_2d().navigation_map
	var spot := target.global_position + Vector2.RIGHT * THROW_DISTANCE
	for a in 16:
		var want := target.global_position + Vector2.from_angle(TAU * a / 16.0) * THROW_DISTANCE
		var on := NavBuilder.snap(map, want)
		if on.distance_to(want) < 30.0 and Probe.line_clear(t, on, target.global_position):
			spot = on
			break
	var thrower := t.actor(&"thrower")
	thrower.global_position = spot
	thrower.velocity = Vector2.ZERO
	t.puppet(&"thrower").aim_at(target.global_position)
	return target.global_position.round()


## Place the match as Main does (as perf/match_5v5_stress): defenders in random rooms, invaders around the house heading for its
## front entrance, each side armed from the default (random gun) loadout drawn from the same seeded rng.
func _spawn_match(t: TestContext) -> Array:
	var spawner = MatchSpawner.new()
	spawner.world = t.world
	spawner.openings = t.world.openings
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var entrance := _front_entrance(t)
	for i in PER_SIDE:
		spawner.spawn_defender(t.rooms, rng, i)
	for i in PER_SIDE:
		spawner.spawn_invader(t.rooms, rng, i, PER_SIDE, entrance)
	var loadout_rng := RandomNumberGenerator.new()
	loadout_rng.seed = SEED
	for c in spawner.combatants:
		LoadoutConfig.apply(c, {}, loadout_rng)
		_overlays_off(c)
	return spawner.combatants


## Main's `_configure_debug` with every overlay at its default (off), as perf/match_5v5_stress.
func _overlays_off(npc: Node) -> void:
	for child in npc.get_children():
		for flag in OverlayRegistry.defaults():
			if not OverlayRegistry.is_global(flag) and flag in child:
				child.set(flag, false)


## The generated house's front entrance (world px), or the origin when it has none.
func _front_entrance(t: TestContext) -> Vector2:
	for o in WorldGen.get_openings(t.world.get("house")):
		if o["front"]:
			return o["pos"]
	return Vector2.ZERO


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
