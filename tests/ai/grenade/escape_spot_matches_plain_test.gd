extends GameTest

## G16's escape spot (agent_throw.gd `escape`) snaps each candidate, judges each spot it lands on and routes each spot once,
## where the plain loop does all three for every candidate (the standing and the crouching probe often meet the same wall, so many
## candidates are the same point). This pins its answer to the plain loop, over frags and stuns going off all round a furnished
## house with the NPC at many places, so the spot an NPC runs to, whether it crouches and the length of its route are unchanged.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")

const SEED := 1717
const CASES := 60
## How far (px) from the burst the NPC stands in each case: inside the zone of either kind.
const NEAR := 220.0


func describe() -> Dictionary:
	return {
		"name": "The escape spot is the same as the plain search finds",
		"description": "AgentThrow.escape gives the same spot, crouch and route length as the loop that snaps, judges and routes every candidate, for frags and stuns all over a furnished house.",
		"tags": ["ai", "grenade", "evade"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.actor(&"npc", &"puppet", Maps.HALL_MIDDLE)


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	Probe.arm(npc, 1, 1)
	await t.frames(2)
	var geometry = AgentThrow.new()
	geometry.vision = AgentVision.new()
	geometry.bind(npc)
	geometry.learn_carried()
	geometry.learn_body()
	var space: PhysicsDirectSpaceState2D = npc.get_world_2d().direct_space_state
	var map: RID = npc.get_world_2d().navigation_map
	var exclude := Probe.character_rids(t)
	var rooms: Array = t.rooms
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var compared := 0
	var differing: Array = []
	var found := 0
	for n in CASES:
		var room: Dictionary = rooms[n % rooms.size()]
		var rect: Rect2 = room["rect"]
		var burst := NavBuilder.snap(map, rect.position + Vector2(rng.randf(), rng.randf()) * rect.size)
		var from := NavBuilder.snap(map, burst + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, NEAR))
		for kind in [&"frag", &"stun"]:
			var radius: float = geometry.radius_of(kind)
			var fuse := rng.randf_range(0.6, 3.0)
			var speed := rng.randf_range(90.0, 260.0)
			var fast: Dictionary = geometry.escape(space, map, kind, radius, burst, from, fuse, speed, exclude)
			var plain := _plain_escape(geometry, space, map, kind, radius, burst, from, fuse, speed, exclude)
			compared += 1
			found += 1 if fast["spot"] != Vector2.INF else 0
			if fast != plain:
				differing.append("%s at %s from %s: %s, plain %s" % [kind, burst.round(), from.round(), fast, plain])
	t.check(compared == CASES * 2 and found >= CASES / 2.0, "escapes compared (%d, %d with a spot)" % [compared, found])
	t.check(differing.is_empty(), "%d of %d escapes differ from the plain search: %s" % [differing.size(), compared, differing.slice(0, 3)])


## `AgentThrow.escape` as it was: every candidate snapped, judged and routed.
func _plain_escape(g, space, map: RID, kind: StringName, radius: float, burst: Vector2, from: Vector2, fuse_left: float,
		speed: float, exclude: Array) -> Dictionary:
	var out_r: float = g.zone_radius(kind, radius) + AgentThrow.OUTSIDE_SLACK
	var reach: float = g.cover_reach(kind)
	var spots: Array = []
	for p in g._candidates(space, burst, from, out_r, exclude, kind):
		var q := NavBuilder.snap(map, p)
		if q.distance_to(p) > AgentThrow.SNAP_TOLERANCE:
			continue
		var crouch := false
		if q.distance_to(burst) < out_r and not g._covered(space, burst, q, g.stand_height(), exclude, reach):
			if not g._covered(space, burst, q, g.crouch_height(), exclude, reach):
				continue
			crouch = true
		spots.append({ "spot": q, "crouch": crouch })
	var best := { "spot": Vector2.INF, "crouch": false, "route": INF }
	var allowed := maxf(fuse_left - AgentThrow.ARRIVE_MARGIN, 0.0) * speed
	for s: Dictionary in spots:
		var length := NavBuilder.path_length(NavBuilder.route(map, from, s["spot"]))
		if length <= allowed and length < best["route"]:
			best = { "spot": s["spot"], "crouch": s["crouch"], "route": length }
	return best
