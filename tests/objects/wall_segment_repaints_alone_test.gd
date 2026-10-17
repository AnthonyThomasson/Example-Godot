extends GameTest

## Each segment of a wall is drawn by its own child of the wall's visuals (wall_visuals.gd), in segment order, so a hit
## repaints the struck segment alone (its dent and marks) while the rest keep their drawing. This shoots one segment of an
## arena's walls and counts each segment's draws: the struck one draws again, no other does, and every segment has its
## drawing child in order.

func describe() -> Dictionary:
	return {
		"name": "A struck wall segment repaints alone",
		"description": "A hit on one wall segment repaints that segment's drawing child and none of the others.",
		"tags": ["wall", "draw", "deformation"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var wall: Node = null
	for node in t.world.find_children("*", "StaticBody2D", true, false):
		if node.has_method("wall_segments"):
			wall = node
			break
	if not t.require(wall != null and wall.get_node_or_null("WallVisuals") != null, "the arena has a drawn wall"):
		return
	var visuals: Node = wall.get_node("WallVisuals")
	var segs: Array = wall.wall_segments()
	var pieces: Array = []
	for i in segs.size():
		pieces.append(visuals.get_node_or_null("Segment%d" % i))
	if not t.require(not pieces.has(null), "every segment has its drawing child (%d segments)" % segs.size()):
		return
	t.check(pieces.all(func(p: Node) -> bool: return p.get_index() == pieces[0].get_index() + pieces.find(p)), "in segment order")
	await t.frames(2)
	var draws: Array = []
	for i in pieces.size():
		draws.append([0])
		(pieces[i] as Node2D).draw.connect(func() -> void: draws[i][0] += 1)
	var struck := 0  # the top wall, along y = 0
	for i in segs.size():
		if (segs[i][0] as Vector2).y == 0.0 and (segs[i][1] as Vector2).y == 0.0:
			struck = i
			break
	var hit := HitInfo.new()
	var mid: Vector2 = (segs[struck][0] + segs[struck][1]) * 0.5
	hit.position = wall.to_global(mid)
	hit.normal = Vector2.DOWN
	hit.direction = Vector2.UP
	hit.damage = 30.0
	hit.speed_factor = 1.0
	wall.take_hit(hit)
	await t.frames(2)
	t.check(draws[struck][0] >= 1, "the struck segment repainted (%d draws)" % draws[struck][0])
	var others := 0
	for i in pieces.size():
		if i != struck:
			others += draws[i][0]
	t.check(others == 0, "no other segment repainted (%d draws)" % others)
