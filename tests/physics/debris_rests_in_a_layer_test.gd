extends GameTest

## A chip knocked off a shot chair is a node only while it flies: once it lands it is drawn by the parent's `DebrisLayer`
## (one layer, a few draw calls) and its node is gone, lying where it landed, a short throw from what the round struck (the
## chair, and the wall behind it that the round goes on into). The layer holds at most `Despawner.max_scene_objects` chips,
## dropping the oldest, so a floor is never strewn without end.

const CAP := 4


func describe() -> Dictionary:
	return {
		"name": "Debris rests in a layer, not in nodes",
		"description": "A shot chair's chips fly as nodes, then land into the DebrisLayer and free their nodes; the layer keeps at most the despawner's cap.",
		"tags": ["debris", "chair", "pistol"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.debris", true)
	s.switch(&"physics.hit_particles", false)
	s.switch(&"physics.blood", false)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(500, 250))
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var chair: Node2D = t.object(&"chair")
	shooter.aim_at(chair)
	await t.seconds(0.4)
	shooter.shoot()
	if not t.require(await t.until(func(): return _chip_nodes(t).size() > 0, 2.0), "the shot sprays chips as nodes"):
		return
	var parent: Node = _chip_nodes(t)[0].get_parent()
	var seen := {}  # every chip node that flew, by instance id (chips spawn over a few frames as the round goes on)
	for i in 60:
		for n in _chip_nodes(t):
			seen[n.get_instance_id()] = true
		await t.frames(1)
	var layer := DebrisLayer.find(parent)
	if not t.require(layer != null, "the chips' parent holds a DebrisLayer once they land"):
		return
	t.check(_chip_nodes(t).is_empty(), "the landed chips' nodes are gone (%d left)" % _chip_nodes(t).size())
	t.check(layer.count() == seen.size(), "every chip that flew is now in the layer (%d of %d)" % [layer.count(), seen.size()])
	var struck: Array = t.events_of(&"hit").map(func(d): return d["position"])
	var far := 0
	for chip in layer.items():
		var nearest := INF
		for at in struck:
			nearest = minf(nearest, (chip["at"] as Vector2).distance_to(at))
		if nearest > 80.0:
			far += 1
	t.check(not struck.is_empty() and far == 0, "each rests a short throw from something the round struck (%d farther than 80 px)" % far)

	var cap_before: int = Despawner.max_scene_objects
	Despawner.max_scene_objects = CAP
	var oldest: Dictionary = layer.items()[0]
	for i in CAP + 2:
		layer.rest(Vector2(100 + i * 10, 100), 0.0, Color.WHITE, Vector2(3, 3), "rect")
	t.check(layer.count() == CAP, "past the cap the layer holds exactly the cap (%d)" % layer.count())
	t.check(not layer.items().has(oldest), "and it was the oldest chip that was dropped")
	Despawner.max_scene_objects = cap_before


## The debris chip nodes currently in the world (they sit under the arena, not the world root), told by what a chip is
## rather than by name: sibling chips share a name and the engine renumbers them.
func _chip_nodes(t: TestContext) -> Array:
	return t.world.find_children("*", "Node2D", true, false).filter(func(n): return "chip_shape" in n and n.has_method("start"))
