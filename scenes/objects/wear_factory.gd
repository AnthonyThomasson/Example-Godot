class_name WearFactory

## Objects-domain factory: turns where wear gathers in a room (World-Gen's placement: a few clusters, each by a wall, a
## corner or a piece of furniture, seeded) into the room's wear: a draw-only node (decals/room_wear.gd) that decides and
## draws each cluster's marks on the room's floor and wall. World-Gen never draws, and never touches the node's fields.

const RoomWear = preload("res://scenes/objects/decals/room_wear.gd")


## Build the wear of the room `rect` (in `parent`'s space) under `parent`: its floor is `floor_definition` (a catalogue floor:
## the marks follow its `art_opts.pattern` and colour), its walls `wall_thickness` thick, and `clusters` are
## `{ pos, wall, seed }` (the cluster's centre; the free stretch of wall it is by as `[a, b]`, its centre line between two
## points, or `[]`; the seed of its marks), all in `parent`'s space. Added after the house's floors and walls, so it draws
## over them. Returns the node (one per room: the CanvasItem drawing that room's wear).
static func spawn(rect: Rect2, floor_definition: Dictionary, wall_thickness: float, clusters: Array, wear_name: String,
		parent: Node) -> Node2D:
	var wear: Node2D = RoomWear.new()
	wear.name = wear_name
	wear.setup(rect, floor_definition, wall_thickness, clusters)
	parent.add_child(wear)
	return wear
