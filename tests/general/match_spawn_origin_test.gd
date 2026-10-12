extends GameTest

## Main drops an NPC without launching the furniture it lands beside. The spawner used to add the NPC to the
## tree at the world origin and only then move it, so for that moment its collider overlapped any piece
## standing near (0, 0); the physics ejected the piece at thousands of px/s, and it flew across the map into
## whatever character was in its way (a "character spawns or is pushed way far away from the level").
## House seed 18 with the front entrance at the game's (440, 350) puts a kitchen counter against the origin.
## Runs the match spawner (the placement helper `main.gd` uses) on the test's own world.

const MatchSpawner := preload("res://scenes/match_spawner.gd")
const SEED := 18
## Where `main.gd` puts the front entrance (its scene anchor, `entrance_distance` above it).
const FRONT_ENTRANCE := Vector2(440, 350)
## The character's body radius: a piece closer to the origin than this overlaps a character added there.
const BODY_RADIUS := 14.0
## How far a piece of furniture or a held NPC may settle (a nudge, not a launch).
const MAX_DRIFT := 40.0


func describe() -> Dictionary:
	return {
		"name": "Spawned NPCs do not launch furniture at the origin",
		"description": "A defender and an invader dropped into a house with a counter against the world origin leave every piece of furniture where it stood and stay where they were put.",
		"tags": ["setup", "match", "spawn"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, "", FRONT_ENTRANCE)
	s.von_down()   # the NPCs hold steady, so any movement is physics alone
	s.switch(&"ai.hostile_on_trespass", false)


func run(t: TestContext) -> void:
	var near_origin := false
	for hole: PackedVector2Array in NavBuilder.furniture_holes(t.world):
		for i in hole.size():
			if Geometry2D.get_closest_point_to_segment(Vector2.ZERO, hole[i], hole[(i + 1) % hole.size()]).length() < BODY_RADIUS:
				near_origin = true
	if not t.require(near_origin,
			"precondition: a solid piece stands against the world origin (pick another SEED if world-gen changed)"):
		return

	var pieces: Array = []
	_collect_bodies(t.world, pieces)
	var piece_starts: Array = pieces.map(func(p): return (p as Node2D).global_position)

	var spawner = MatchSpawner.new()
	spawner.world = t.world
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	spawner.spawn_defender(t.rooms, rng, 0)
	spawner.spawn_invader(t.rooms, rng, 0, 1, FRONT_ENTRANCE)
	var npcs: Array = spawner.combatants.duplicate()
	if not t.require(npcs.size() == 2, "a defender and an invader spawned"):
		return
	for npc: Node2D in npcs:
		npc.set("speed", 0.0)   # the AI cannot walk them, so only physics can move one
	var npc_starts: Array = npcs.map(func(n): return (n as Node2D).global_position)

	var worst := 0.0
	var elapsed := 0.0
	while elapsed < 1.5:
		await t.seconds(0.1)
		elapsed += 0.1
		for i in pieces.size():
			worst = maxf(worst, (pieces[i] as Node2D).global_position.distance_to(piece_starts[i]))
		t.trace("furniture_drift", worst)
	for i in pieces.size():
		var drift: float = (pieces[i] as Node2D).global_position.distance_to(piece_starts[i])
		t.check(drift <= MAX_DRIFT, "%s stays where it stood (moved %.0f px)" % [(pieces[i] as Node).name, drift])
	for i in npcs.size():
		var drift: float = (npcs[i] as Node2D).global_position.distance_to(npc_starts[i])
		t.check(drift <= MAX_DRIFT, "%s stays where it was dropped (moved %.0f px)" % [(npcs[i] as Node).name, drift])


## Every furniture body (RigidBody2D) under `node`, appended to `out`.
func _collect_bodies(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is RigidBody2D:
			out.append(child)
		_collect_bodies(child, out)
