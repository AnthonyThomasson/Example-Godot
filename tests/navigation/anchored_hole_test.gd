extends GameTest

## R8 (ticket #61): an anchored solid piece (a definition with `anchored: true`, spawned through ObjectFactory) never
## moves, and it is still an obstacle: `NavBuilder.furniture_holes` (interface 9) includes its footprint and the baked
## map has a hole there, like any solid furniture. A plain chair beside it is carved as before, and a walk-over rug
## (non-solid decor, frozen too) is still not carved: the build carves the anchored pieces, not every frozen body.

const POST_AT := Vector2(300, 200)
const CHAIR_AT := Vector2(150, 200)
const RUG_AT := Vector2(450, 200)
## The test post: a solid metal circle that never moves (the streetlight's kind of piece).
const POST := {
	"name": "Post", "shape": "circle", "size": Vector2(28, 28), "color": Color(0.32, 0.33, 0.36), "material": "metal",
	"weight": 6, "coverage": 100, "penetration": 85, "anchored": true,
}
## The shove the premise check gives the post (pushable contract, interface 5): it moves a 6-weight piece plainly.
const SHOVE := Vector2(3000, 0)


func describe() -> Dictionary:
	return {
		"name": "An anchored piece is carved into the nav map",
		"description": "NavBuilder.furniture_holes includes an anchored solid post (which a shove does not move) and the baked map has a hole there; a chair is carved, a rug is not.",
		"tags": ["navigation", "anchored", "furniture", "streetlight"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.object(&"post", POST, POST_AT)
	s.object(&"chair", "chair", CHAIR_AT)
	s.object(&"rug", "rug", RUG_AT)


## Whether some hole of `holes` holds every point of `points`.
func _carved(holes: Array, points: Array) -> bool:
	for hole: PackedVector2Array in holes:
		if points.all(func(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p, hole)):
			return true
	return false


## The centre of a piece and four points just inside its footprint's edge.
func _footprint(at: Vector2, half: float) -> Array:
	var inset := half - 1.0
	return [at, at + Vector2(inset, 0), at - Vector2(inset, 0), at + Vector2(0, inset), at - Vector2(0, inset)]


func run(t: TestContext) -> void:
	var post: RigidBody2D = t.object(&"post")
	# The premise: the post is anchored (a shove through the pushable contract leaves it where it stands).
	post.apply_impulse(SHOVE)
	await t.frames(10)
	var drift := post.global_position.distance_to(POST_AT)
	if not t.require(drift < 0.1, "the post is anchored: a shove leaves it in place (it moved %.1f px)" % drift):
		return

	var holes := NavBuilder.furniture_holes(t.world.house)
	var half: float = POST["size"].x * 0.5
	t.check(_carved(holes, _footprint(POST_AT, half)), "furniture_holes has a hole over the anchored post's footprint (%d holes)" % holes.size())
	t.check(_carved(holes, _footprint(CHAIR_AT, 13.0)), "furniture_holes has a hole over the chair")
	t.check(not _carved(holes, [RUG_AT]), "the rug (walk-over decor) is not carved")

	var map := t.world.get_world_2d().navigation_map
	if t.require(NavBuilder.ready(map), "the nav map is baked"):
		var off := NavBuilder.snap(map, POST_AT).distance_to(POST_AT)
		t.check(off >= half, "the baked map has no floor under the anchored post (nearest walkable point %.1f px from its centre, its radius %.1f)" % [off, half])
