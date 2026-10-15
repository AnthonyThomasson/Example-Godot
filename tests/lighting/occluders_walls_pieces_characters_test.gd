extends GameTest

## R10 (ticket #61): shadows. Occluders stand on the walls, on solid pieces and on living characters, and a character's goes
## when it dies. In one room with a lamp, an armchair, a rug and two puppets:
## - every wall run is covered by a casting LightOccluder2D (sampled along each `wall_segments()` run);
## - each solid piece (the armchair, the lamp) carries its own occluder over its footprint, so it follows a shove; the rug,
##   walk-over decor, carries none;
## - a living puppet stands in a casting occluder, and still does after walking a stretch (it follows the body);
## - once the other puppet is dead, no casting occluder is under it or over where it lies;
## - the lamp's light casts shadows that the walls', the armchair's and the living character's occluders take part in (its
##   shadow mask meets each one's occluder mask).
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting`
## with `lights()`; the lamp's light a PointLight2D under it. The occluders are plain LightOccluder2Ds anywhere under the world
## (a solid piece's under the piece).

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const ROOM := Rect2(0, 0, 900, 600)
const WALKER_AT := Vector2(200, 450)
const WALK_TO := Vector2(330, 450)
const VICTIM_AT := Vector2(650, 450)


func describe() -> Dictionary:
	return {
		"name": "Walls, solid pieces and living characters cast shadows; the dead do not",
		"description": "Casting occluders cover every wall run, sit on each solid piece (not on a rug) and on a living character as it walks; a dead character has none; the lamp's light is shadowed by them.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ROOM)
	s.switch(&"nav.rebake", false)
	s.object(&"lamp", "lamp", Vector2(450, 120), { "neon": "" })
	s.object(&"armchair", "armchair", Vector2(450, 300), { "neon": "" })
	s.object(&"rug", "rug", Vector2(700, 200))
	s.actor(&"walker", &"puppet", WALKER_AT)
	s.actor(&"victim", &"puppet", VICTIM_AT)


func run(t: TestContext) -> void:
	var world: Node = t.world

	# Walls: every run covered.
	var wall_occluder: LightOccluder2D = null
	for wall in world.find_children("*", "Node2D", true, false).filter(func(n: Node) -> bool: return n.has_method(&"wall_segments")):
		for seg: PackedVector2Array in wall.wall_segments():
			if seg[0].distance_to(seg[1]) < 1.0:
				continue
			for f in [0.25, 0.5, 0.75]:
				var p: Vector2 = (wall as Node2D).global_transform * seg[0].lerp(seg[1], f)
				var over := Probe.occluders_at(world, p)
				t.check(not over.is_empty(), "the wall %s is covered by an occluder at %s" % [wall.name, p.round()])
				if not over.is_empty() and wall_occluder == null:
					wall_occluder = over[0]

	# Solid pieces: their own occluder over their footprint; walk-over decor none.
	var piece_occluders := {}
	for id in [&"armchair", &"lamp"]:
		var piece: Node2D = t.object(id)
		var own := Probe.own_occluders(piece).filter(func(o: LightOccluder2D) -> bool: return Probe.holds(o, piece.global_position))
		t.check(not own.is_empty(), "the solid %s carries an occluder over its footprint" % id)
		if not own.is_empty():
			piece_occluders[id] = own[0]
	t.check(Probe.own_occluders(t.object(&"rug")).is_empty(), "the rug (walk-over decor) carries no occluder")

	# Living characters: an occluder over the body that follows it.
	var walker: Node2D = t.actor(&"walker")
	var body_occluder: LightOccluder2D = null
	var at_start := Probe.occluders_at(world, walker.global_position)
	t.check(not at_start.is_empty(), "the living walker stands in an occluder")
	if not at_start.is_empty():
		body_occluder = at_start[0]
	t.puppet(&"walker").walk_to(WALK_TO)
	if not t.require(await t.until(func() -> bool: return t.puppet(&"walker").has_arrived(), 4.0), "the walker gets to %s" % WALK_TO):
		return
	await t.frames(2)
	t.check(not Probe.occluders_at(world, walker.global_position).is_empty(), "the walker's occluder follows it (at %s)" % walker.global_position.round())

	# The dead: no occluder.
	var victim: Node2D = t.actor(&"victim")
	t.check(not Probe.occluders_at(world, victim.global_position).is_empty(), "the victim, alive, stands in an occluder")
	victim.take_damage(100000.0)
	if not t.require(await t.until(func() -> bool: return victim.is_dead, 1.0), "the victim dies"):
		return
	await t.seconds(1.5)
	t.check(Probe.own_occluders(victim).is_empty(), "the dead victim carries no casting occluder")
	var lies: Array = [victim.global_position, victim.blood_origin()]
	for p: Vector2 in lies:
		t.check(Probe.occluders_at(world, p).is_empty(), "no occluder over where the dead victim lies (%s)" % p.round())

	# The lamp's light is shadowed by them.
	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	var lamp_lights := Probe.lights_of(lighting, t.object(&"lamp"))
	if not t.require(not lamp_lights.is_empty(), "the lamp has its light"):
		return
	var light: PointLight2D = lamp_lights[0]
	t.check(light.shadow_enabled, "the lamp's light casts shadows")
	var casters := { "wall": wall_occluder, "armchair": piece_occluders.get(&"armchair"), "walker": body_occluder }
	for what: String in casters:
		var occ: LightOccluder2D = casters[what]
		if occ != null:
			t.check(light.shadow_item_cull_mask & occ.occluder_light_mask != 0, "the %s shadows the lamp's light (mask %d, occluder %d)" % [
				what, light.shadow_item_cull_mask, occ.occluder_light_mask])
