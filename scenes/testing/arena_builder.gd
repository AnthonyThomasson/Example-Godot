extends RefCounted

## Testing domain: a hand-built arena — one walled, floored room — made through the Objects factories
## (interface 2) in the house's own wall style. Returns a Node2D carrying the same `rooms` meta a
## generated house has, so NavBuilder and WorldGen.get_rooms work on it unchanged.


## Build the arena described by `world` (`{ rect, floor, walls, thickness }`, world-space) under
## `parent` and return its root.
static func build(world: Dictionary, parent: Node) -> Node2D:
	var root := Node2D.new()
	root.name = "Arena"
	parent.add_child(root)
	var rect: Rect2 = world["rect"]
	var floor_def := WorldGen.floor_definition(String(world.get("floor", "oak_planks")))
	if not floor_def.is_empty():
		FloorFactory.spawn(rect, floor_def, "Arena Floor", root)
	if world.get("walls", true):
		WallFactory.spawn(rect, float(world.get("thickness", 12.0)), [], "Arena Walls", root, WorldGen.wall_style())
	root.set_meta("rooms", [{ "key": "arena", "type": "arena", "rect": rect }])
	return root
