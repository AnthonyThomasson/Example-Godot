extends GameTest

## Performance guard for the thing a player watches: a 5v5 match in a generated house, set up the way Main sets
## one up (the match spawner's placement, every NPC armed from the default random loadout, nav re-baker, blood,
## debris, sound and team radio all on) with Von scripted so no server is needed. After a warm-up that brings the
## sides into contact, 300 frames are measured: the average frame must fit in one 60 fps frame, with no spike over
## two. Headless measures CPU only; rendering is not in these numbers.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const MatchSpawner := preload("res://scenes/match_spawner.gd")
const OverlayRegistry := preload("res://scenes/ui/overlays/overlay_registry.gd")

const SEED := 7
const PER_SIDE := 5
const WARMUP_S := 6.0
const MEASURE_FRAMES := 300
const NODE_GROWTH := 2500


func describe() -> Dictionary:
	return {
		"name": "A 5v5 match runs without frame loss",
		"description": "Five defenders and five invaders fight in a generated house, set up as Main does; the average frame stays under 16.7 ms and no frame takes over two.",
		"tags": ["match", "ai", "scripted", "crowd"],
		"timeout": 40.0,
		# A real match re-bakes the navmesh while furniture is shoved around, and now and then the bake of overlapping
		# footprints is rejected by the engine (about one run in five). That is a nav bug this test is not about; the
		# bake's cost is part of what it measures, so the two lines are allowed rather than the re-bake switched off.
		"allowed_logs": ["Navigation map synchronization error", "NavigationPolygon polygon convex partition failed"],
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.vision", true)
	s.switch(&"ai.pursuit", true)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters := _spawn_match(t)
	if not t.require(characters.size() == PER_SIDE * 2, "ten combatants spawned (%d)" % characters.size()):
		return
	await t.seconds(WARMUP_S)
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	Perf.within_frames(t, "5v5 match", stats, Perf.SMOOTH_AVG_MS, Perf.SMOOTH_P95_MS, Perf.SMOOTH_MAX_MS)
	t.check(not t.von_requests().is_empty(), "the NPCs asked for decisions (%d asks)" % t.von_requests().size())
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF 5v5 match node growth %d, %d decisions asked" % [grown, t.von_requests().size()])
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])


## Place the match as Main does: defenders in random rooms, invaders around the house heading for its front
## entrance, each side armed from the default (random gun) loadout drawn from the same seeded rng.
func _spawn_match(t: TestContext) -> Array:
	var spawner = MatchSpawner.new()
	spawner.world = t.world
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


## Main's `_configure_debug` with every overlay at its default (off): a debug overlay that is left on (the vision cone's
## export defaults to on) would be costed as if a player were watching it.
func _overlays_off(npc: Node) -> void:
	for child in npc.get_children():
		for flag in OverlayRegistry.defaults():
			if not OverlayRegistry.is_global(flag) and flag in child:
				child.set(flag, false)


func _front_entrance(t: TestContext) -> Vector2:
	for o in WorldGen.get_openings(t.world.get("house")):
		if o["front"]:
			return o["pos"]
	return Vector2.ZERO
