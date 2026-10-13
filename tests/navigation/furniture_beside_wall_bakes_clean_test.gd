extends GameTest

## A turned chair beside a wall cuts the planning navmesh with its hole, and the cut used to leave vertices a fraction of a pixel apart:
## the NavigationServer merges edges by 1 px cell, rejects an edge whose ends share one and logs "navigation map synchronization error"
## (any logged engine error fails a test). Only the steering bake welded those vertices (`character_beside_wall_bakes_clean`); the planning
## re-bake, run by the NavUpdater whenever furniture is shoved, did not, and tripped once in a while (seen in a run of
## `ai/grenade/stun_entry_suspect_room`, a chair moved by a body beside it). Now every bake welds. These are the chair spots a random
## search of 600 placements found the unwelded planning bake wrong at, baked both ways (in place and on the server's worker thread).

const Maps := preload("res://tests/_ai/flank_maps.gd")

const SPOTS := [
	[Vector2(885.1079, 149.3317), 3.55461406707764],
	[Vector2(811.0822, 205.5673), 5.71764612197876],
]


func describe() -> Dictionary:
	return {
		"name": "Furniture beside a wall bakes a clean navmesh",
		"description": "A chair turned at spots beside the terrace house's walls and the planning region is re-baked each time, in place and off the main thread: no polygon edge collapses into one cell, no edge is shared by three polygons, and the map syncs without an engine error.",
		"tags": ["navigation", "rebake", "furniture", "weld"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(740, 60), { "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region: NavigationRegion2D = t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	var map: RID = t.world.get_world_2d().navigation_map
	var chair: Node2D = t.object(&"chair")
	var problems := []
	for spot: Array in SPOTS:
		chair.global_position = spot[0]
		chair.rotation = spot[1]
		for off_thread in [false, true]:
			if off_thread:
				var done := [false]
				NavBuilder.rebake_async(region, t.world.house, t.rooms, 14.0, func(): done[0] = true)
				await t.until(func(): return done[0], 5.0, "the off-thread bake lands")
			else:
				NavBuilder.rebake(region, t.world.house, t.rooms)
			var why := _problem(region)
			if why != "":
				problems.append("%s turned %.2f (%s): %s" % [spot[0], spot[1], "off the main thread" if off_thread else "in place", why])
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
