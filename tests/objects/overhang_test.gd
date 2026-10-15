extends GameTest

## R9 (ticket #61): a piece may draw an overhead part beyond its footprint, above the characters, with no collider. The
## streetlight is that piece: its arm and lamp head reach out over the street. A streetlight (the catalogue row, spawned
## through ObjectFactory) stands in an arena and a puppet is stood under the far end of its overhang: the overhang draws
## over every part of the puppet, nothing solid is there, the puppet stays where it was put (nothing pushes it out), and
## the post itself is still solid.
##
## The reads it takes the build to publish:
## - the catalogue row `WorldGen.object_definition("streetlight")`, carrying an `overhang` (the Objects field the plan names);
## - under the spawned piece, a CanvasItem named `Overhang` that draws the overhead part (found by name, like a vehicle's
##   `Roof`), with `get_rect() -> Rect2`, the area it draws in its own frame (a Sprite2D's own `get_rect`, or the same
##   read on a node that draws it by hand).

const LAMP_AT := Vector2(500, 350)
const KEY := "streetlight"
const UNDER_INSET := 6.0  ## How far (px) in from the end of the overhang the puppet is stood.
const STAY := 1.0  ## How far (px) the puppet may be moved while it stands there.


func describe() -> Dictionary:
	return {
		"name": "A streetlight's overhang draws above characters, with no collider",
		"description": "A puppet stood under the far end of a streetlight's overhang is drawn under it, nothing solid is there and nothing pushes it out; the post is still solid.",
		"tags": ["objects", "overhang", "streetlight", "draw-order"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	if not WorldGen.object_definition(KEY).is_empty():  # placed only once the catalogue has it; run() names the gap
		s.object(&"lamp", KEY, LAMP_AT)
	s.actor(&"walker", &"puppet", Vector2(120, 120))


## A canvas item's z after its parents' relative z_index.
func _absolute_z(item: CanvasItem) -> int:
	var z := item.z_index
	var node: Node = item
	while (node as CanvasItem).z_as_relative:
		node = node.get_parent()
		if not node is CanvasItem:
			break
		z += (node as CanvasItem).z_index
	return z


## Whether `a` is drawn over `b`: a higher absolute z, or the same z and later in the tree.
func _draws_above(a: CanvasItem, b: CanvasItem) -> bool:
	var za := _absolute_z(a)
	var zb := _absolute_z(b)
	return za > zb if za != zb else a.is_greater_than(b)


## The colliders found at world point `p` on the solid layer, the actors left out.
func _solid_at(t: TestContext, p: Vector2, skip: Array) -> Array:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = p
	query.collision_mask = PhysicsLayers.SOLID
	query.exclude = skip
	return t.world.get_world_2d().direct_space_state.intersect_point(query)


func run(t: TestContext) -> void:
	var def := WorldGen.object_definition(KEY)
	if not t.require(not def.is_empty(), "the catalogue has a streetlight (WorldGen.object_definition(\"%s\"))" % KEY):
		return
	t.check(def.has("overhang"), "the streetlight's definition carries an overhang")
	var lamp: Node2D = t.object(&"lamp")
	var overhang := lamp.find_child("Overhang", true, false) as CanvasItem
	if not t.require(overhang != null, "the streetlight has a CanvasItem named Overhang drawing its overhead part"):
		return
	var drawn: Rect2 = overhang.get_rect()
	var area: Rect2 = overhang.get_global_transform() * drawn

	# Stand the puppet under the far end of the overhang, along the line from the post out through it.
	var walker: Node2D = t.actor(&"walker")
	var radius: float = walker.radius
	var post_radius: float = maxf(def["size"].x, def["size"].y) * 0.5
	var out := (area.get_center() - LAMP_AT).normalized()
	var reach := 0.0  # the farthest point of the overhang along that line (it need not start at the post's centre)
	for step in 2000:
		if area.has_point(LAMP_AT + out * step):
			reach = step
	var stand := LAMP_AT + out * (reach - UNDER_INSET)
	if not t.require(area.has_point(stand) and reach - UNDER_INSET >= post_radius + radius + 2.0,
			"the overhang reaches beyond the footprint, far enough for a body to stand under it (it reaches %.0f px from the post's centre)" % reach):
		return
	walker.global_position = stand
	await t.seconds(0.5)

	var moved := walker.global_position.distance_to(stand)
	t.check(moved < STAY, "nothing pushes the puppet out from under the overhang (moved %.1f px)" % moved)
	var bodies := _solid_at(t, stand, [walker.get_rid()])
	t.check(bodies.is_empty(), "nothing solid stands under the overhang (%d colliders at %s)" % [bodies.size(), stand])
	var colliders := overhang.find_children("*", "CollisionObject2D", true, false) + overhang.find_children("*", "CollisionShape2D", true, false) \
		+ overhang.find_children("*", "CollisionPolygon2D", true, false)
	t.check(colliders.is_empty(), "the overhang has no collider (%d found)" % colliders.size())
	t.check(_solid_at(t, LAMP_AT, [walker.get_rid()]).any(func(hit: Dictionary) -> bool: return hit["collider"] == lamp), "the post itself is solid")

	var items: Array = [walker]
	items.append_array(walker.find_children("*", "CanvasItem", true, false))
	for item: CanvasItem in items:
		if item.is_visible_in_tree():
			t.check(_draws_above(overhang, item), "the overhang draws over the puppet's %s (z %d over %d)" % [
				walker.get_path_to(item), _absolute_z(overhang), _absolute_z(item)])
