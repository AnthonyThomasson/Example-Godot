extends GameTest

## R4 guard (ticket #61): the environment's look never changes how it sounds. Every catalogue object and every floor has
## the `material` in the tables below, which a bullet striking a piece and a foot landing on a floor are voiced by.
## Checked through the catalogue lookups (`WorldGen.object_definition` / `floor_definition`) and through what the built
## nodes report: a spawned piece's `get_surface().material` (what impacts voice), the footstep surface a spawned floor
## registers (`SoundSurface.at`, which also hangs on the floor's pattern), and a wall in the house style reporting no
## material (voiced as `wall`). A restyle that changes a material fails it.

const FAR := Vector2(4000, 4000)  ## Where each piece is spawned on its own, clear of the arena.

## Every catalogue object's material.
const OBJECTS := {
	"armchair": "fabric", "bath_mat": "fabric", "bathtub": "ceramic", "bed": "fabric", "bench": "wood",
	"bookshelf": "wood", "cabinet": "wood", "car": "metal", "chair": "wood", "coat_rack": "wood",
	"coffee_table": "wood", "console_table": "wood", "desk": "wood", "dining_table": "wood", "dresser": "wood",
	"dryer": "metal", "filing_cabinet": "metal", "fridge": "metal", "island": "stone", "kitchen_counter": "stone",
	"lamp": "metal", "laundry_sink": "ceramic", "linen_shelf": "wood", "microwave": "metal", "mirror": "glass",
	"nightstand": "wood", "office_chair": "plastic", "plant": "foliage", "rug": "fabric", "rug_large": "fabric",
	"runner": "fabric", "shelving": "metal", "shoe_rack": "wood", "shower": "glass", "side_table": "wood",
	"sink": "ceramic", "sofa": "fabric", "stove": "metal", "table": "wood", "toilet": "ceramic",
	"tool_chest": "metal", "towel_rack": "metal", "tv": "electronics", "wardrobe": "wood",
	"washing_machine": "metal", "workbench": "wood",
}

## Every floor's material and the footstep surface it registers.
const FLOORS := {
	"oak_planks": ["wood", &"wood"], "walnut_planks": ["wood", &"wood"], "ash_planks": ["wood", &"wood"],
	"grey_planks": ["wood", &"wood"], "parquet": ["wood", &"wood"], "white_tile": ["ceramic", &"tile"],
	"terracotta_tile": ["ceramic", &"tile"], "slate_tile": ["stone", &"stone"], "checker": ["ceramic", &"tile"],
	"mosaic": ["ceramic", &"tile"], "beige_carpet": ["fabric", &"carpet"], "blue_carpet": ["fabric", &"carpet"],
	"green_carpet": ["fabric", &"carpet"], "concrete": ["stone", &"concrete"],
}


func describe() -> Dictionary:
	return {
		"name": "The restyle keeps every object's and floor's material",
		"description": "Every catalogue object and floor keeps its material through the cyberpunk restyle (catalogue and spawned node), each floor registers the same footstep surface, and a house-style wall still reports no material.",
		"tags": ["objects", "material", "floor", "sound", "restyle"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	for key: String in OBJECTS:
		var def := WorldGen.object_definition(key)
		if not t.check(not def.is_empty(), "the catalogue still has the %s" % key):
			continue
		t.expect_eq(def.get("material", ""), OBJECTS[key], "the %s's catalogue material" % key)
		var piece := ObjectFactory.spawn(def, FAR, t.world)
		t.expect_eq(piece.get_surface()["material"], OBJECTS[key], "a spawned %s strikes as %s" % [key, OBJECTS[key]])
		piece.free()

	for key: String in FLOORS:
		var def := WorldGen.floor_definition(key)
		if not t.check(not def.is_empty(), "the catalogue still has the %s floor" % key):
			continue
		t.expect_eq(def.get("material", ""), FLOORS[key][0], "the %s floor's catalogue material" % key)
		var rect := Rect2(FAR, Vector2(200, 200))
		var floor_node := FloorFactory.spawn(rect, def, "Probe " + key, t.world)
		t.expect_eq(SoundSurface.at(rect.get_center()), FLOORS[key][1], "footsteps on the %s floor sound like %s" % [key, FLOORS[key][1]])
		floor_node.free()

	var wall := WallFactory.spawn(Rect2(FAR, Vector2(200, 200)), 12.0, [], "Probe wall", t.world, WorldGen.wall_style())
	t.expect_eq(wall.get_surface()["material"], "", "a house-style wall reports no material (voiced as a wall)")
	wall.free()
	await t.frames(1)
