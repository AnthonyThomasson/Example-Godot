extends RefCounted

## Testing domain: a hand-laid building — walled, floored rooms joined by doorways — made through the
## Objects factories (interface 2) in the house's own wall style. Returns a Node2D annotated through
## `WorldGen.annotate_layout`, so NavBuilder and WorldGen.get_rooms / get_openings work on it like on a house.


## Build the layout described by `world` (`{ rooms, doors, thickness }`, world-space) under `parent` and
## return its root. Each room gets its own walls with every door that lies on one of its edges cut in.
static func build(world: Dictionary, parent: Node) -> Node2D:
	var root := Node2D.new()
	root.name = "Layout"
	parent.add_child(root)
	var thickness := float(world.get("thickness", 12.0))
	var doors: Array = world.get("doors", [])
	var rooms: Array = []
	for room in world["rooms"]:
		var rect: Rect2 = room["rect"]
		var key := String(room["key"])
		var floor_def := WorldGen.floor_definition(String(room.get("floor", "oak_planks")))
		if not floor_def.is_empty():
			FloorFactory.spawn(rect, floor_def, key.capitalize() + " Floor", root)
		WallFactory.spawn(rect, thickness, WallFactory.openings_for(rect, doors), key.capitalize(), root, WorldGen.wall_style())
		rooms.append({ "key": room["key"], "type": room.get("type", room["key"]), "rect": rect })
	WorldGen.annotate_layout(root, rooms, doors)
	return root
