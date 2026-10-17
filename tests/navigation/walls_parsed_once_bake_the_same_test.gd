extends GameTest

## A re-bake tick bakes the planning and the steering region from one parse of the house's walls (`NavBuilder._walls_of`,
## handed to both by nav_updater.gd) where each bake once parsed them itself. This checks a bake's source made from the shared
## parse is the one a bake parsing on its own makes (its walkable outlines, its obstructions and projected obstructions, the
## same values in the same order), on a generated house as it stands and after a wall is shot up (its collider rebuilt).

const SEED := 7
const PLAN := "garage_home"
const RADIUS := 14.0


func describe() -> Dictionary:
	return {
		"name": "A bake from the shared wall parse is the same",
		"description": "A nav bake source built from NavBuilder._walls_of equals one built by parsing the walls itself, before and after a wall is dented.",
		"tags": ["bake", "walls"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var house: Node2D = t.world.get("house")
	await t.frames(2)
	_compare(t, house, "as the house stands")
	var wall: Node = null
	for node in house.find_children("*", "StaticBody2D", true, false):
		if node.has_method("wall_segments"):
			wall = node
			break
	if not t.require(wall != null, "the house has a wall"):
		return
	var seg: PackedVector2Array = wall.wall_segments()[0]
	for k in 4:
		var hit := HitInfo.new()
		hit.position = wall.to_global(seg[0].lerp(seg[1], 0.2 + 0.15 * k))
		hit.normal = (seg[1] - seg[0]).normalized().orthogonal()
		hit.direction = -hit.normal
		hit.damage = 40.0
		hit.speed_factor = 1.0
		wall.take_hit(hit)
	await t.frames(3)  # the wall's collider is rebuilt from the dents
	_compare(t, house, "after a wall is shot up")


## Check the bake source made with the walls parsed once matches the one that parses them itself, `when` naming the moment.
func _compare(t: TestContext, house: Node2D, when: String) -> void:
	var rooms: Array = t.rooms
	var furniture := NavBuilder.furniture_holes(house)
	var own: Dictionary = NavBuilder._source_for(house, rooms, RADIUS, [], furniture)
	var shared: Dictionary = NavBuilder._source_for(house, rooms, RADIUS, [], furniture, NavBuilder._walls_of(house, RADIUS))
	var a: NavigationMeshSourceGeometryData2D = own["source"]
	var b: NavigationMeshSourceGeometryData2D = shared["source"]
	t.check(a.get_obstruction_outlines().size() > 10, "%s: the walls are parsed (%d obstructions)" % [when, a.get_obstruction_outlines().size()])
	t.check(a.get_traversable_outlines() == b.get_traversable_outlines(), "%s: the same walkable outlines" % when)
	t.check(a.get_obstruction_outlines() == b.get_obstruction_outlines(), "%s: the same obstructions" % when)
	t.check(a.get_projected_obstructions() == b.get_projected_obstructions(), "%s: the same projected obstructions" % when)
