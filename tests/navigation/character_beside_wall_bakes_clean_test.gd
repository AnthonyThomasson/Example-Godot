extends GameTest

## A character standing near a wall cuts the baked navmesh with its round hole, and the cut used to leave vertices
## a fraction of a pixel apart: the NavigationServer merges edges by 1 px cell, rejects an edge whose ends share
## one and logs "navigation map synchronization error" (any logged engine error fails a test). The bake welds the
## vertices that share a cell, so every spot below bakes clean. They are spots next to the terrace house's walls and
## furniture that the unwelded bake got wrong.

const Maps := preload("res://tests/_ai/flank_maps.gd")

const SPOTS := [
	Vector2(739.3569, 174.8348), Vector2(684.2812, 365.3985), Vector2(443.7598, 404.0789),
	Vector2(153.6895, 6.187025), Vector2(82.46811, 160.5835), Vector2(161.5776, 354.6605),
	Vector2(648.2258, 404.0137), Vector2(854.5775, 392.4496), Vector2(413.3746, 5.394064),
]


func describe() -> Dictionary:
	return {
		"name": "A character beside a wall bakes a clean navmesh",
		"description": "A puppet is placed at spots beside the terrace house's walls and the steering region is re-baked each time: no polygon edge collapses into one cell, no edge is shared by three polygons, and the map syncs without an engine error.",
		"tags": ["navigation", "rebake", "character", "weld"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, true)
	s.switch(&"nav.rebake", false)
	s.actor(&"p", &"puppet", Vector2(300, 200))


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region: NavigationRegion2D = t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	var steering := NavBuilder.steering_region(region)
	var map := NavBuilder.steering_map(t.world.get_world_2d().navigation_map)
	var problems := []
	for spot in SPOTS:
		t.actor(&"p").global_position = spot
		NavBuilder.rebake_steering(region, t.world.house, t.rooms)
		var why := _problem(steering)
		if why != "":
			problems.append("%s: %s" % [spot, why])
		NavigationServer2D.map_force_update(map)
		await t.frames(2)
	t.check(problems.is_empty(), "every baked navmesh has edges the server can merge: %s" % str(problems))


## What is wrong with `region`'s baked polygon, as the NavigationServer would see it ("" = nothing): a polygon edge whose
## ends fall in one 1 px cell, or that more than two polygons share.
func _problem(region: NavigationRegion2D) -> String:
	var poly := region.navigation_polygon
	var verts := poly.get_vertices()
	var offset := region.global_position
	var shared := {}
	for i in poly.get_polygon_count():
		var indices := poly.get_polygon(i)
		for k in indices.size():
			var a := verts[indices[k]] + offset
			var b := verts[indices[(k + 1) % indices.size()]] + offset
			var cell_a := Vector2i(a.floor())
			var cell_b := Vector2i(b.floor())
			if cell_a == cell_b:
				return "an edge collapses at %s" % a
			var key := [cell_a, cell_b] if (cell_a.x < cell_b.x or (cell_a.x == cell_b.x and cell_a.y < cell_b.y)) else [cell_b, cell_a]
			shared[key] = int(shared.get(key, 0)) + 1
			if shared[key] > 2:
				return "an edge at %s is shared by three polygons" % a
	return ""
