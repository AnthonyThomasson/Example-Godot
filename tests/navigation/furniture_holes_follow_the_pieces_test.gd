extends GameTest

## `NavBuilder.furniture_holes` keeps each piece's footprint hull with what it was made from (each collision shape's global
## transform and its size, radius or points) and makes it again only when that changes, and finds the pieces with
## `find_children` where it once walked every node itself. This pins it to a fresh measurement: the same holes, in the same
## order, over a generated house as it stands, after pieces are moved and turned, and after a piece is shot up (its collider
## rebuilt in convex pieces), and a moved piece's hole moves with it.

const SEED := 7
const PLAN := "garage_home"


func describe() -> Dictionary:
	return {
		"name": "Furniture holes follow the pieces",
		"description": "furniture_holes gives what a fresh measurement of every piece gives (the same holes in the same order) as pieces stand, move, turn and are dented.",
		"tags": ["bake", "furniture", "holes"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var house: Node2D = t.world.get("house")
	await t.frames(2)
	var pieces: Array = house.find_children("*", "RigidBody2D", true, false)
	if not t.require(pieces.size() >= 20, "the house is furnished (%d pieces)" % pieces.size()):
		return
	var before := NavBuilder.furniture_holes(house)
	t.check(before == _fresh(house), "as the house stands, the holes are a fresh measurement's (%d)" % before.size())
	t.check(NavBuilder.furniture_holes(house) == before, "asked again, they are the same")

	var moved: RigidBody2D = null
	for piece: RigidBody2D in pieces:
		if not piece.freeze:
			moved = piece
			break
	if not t.require(moved != null, "a piece that can be moved"):
		return
	var index := pieces.find(moved)
	moved.freeze = true  # a free body is put back by the next physics step
	await t.frames(1)
	moved.global_position += Vector2(23.0, -11.0)
	moved.rotation += 0.4
	await t.frames(1)
	var after := NavBuilder.furniture_holes(house)
	t.check(after == _fresh(house), "after a piece is moved and turned, the holes are a fresh measurement's")
	t.check(after.size() == before.size() and (after[index] as PackedVector2Array) != (before[index] as PackedVector2Array),
		"and the moved piece's hole moved with it")

	var hit := HitInfo.new()
	hit.position = moved.global_position + Vector2(12.0, 0.0)
	hit.normal = Vector2.RIGHT
	hit.direction = Vector2.LEFT
	hit.damage = 60.0
	hit.speed_factor = 1.0
	for k in 4:
		hit.position = moved.global_position + Vector2.from_angle(k * 1.3) * 12.0
		moved.take_hit(hit)
	await t.frames(3)  # the collider is rebuilt from the dents a frame later
	var dented := NavBuilder.furniture_holes(house)
	t.check(dented == _fresh(house), "after a piece is shot up, the holes are a fresh measurement's")


## Every piece's hole measured afresh: nothing kept from an earlier call.
func _fresh(house: Node2D) -> Array:
	NavBuilder._hulls.clear()
	return NavBuilder.furniture_holes(house)
