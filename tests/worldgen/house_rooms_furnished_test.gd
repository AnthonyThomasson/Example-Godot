extends GameTest

## Generated rooms are not left bare: every room's solid furniture covers at least a floor share of its
## floor (lower for corridors), the fill pass puts more in than the recipe's zones alone, and the
## WorldGenConfig knobs really switch it off.

const SEEDS := [11, 12, 13]
const FAR_AWAY := Vector2(5000, 5000)
const MIN_COVER := 0.08  ## Fraction of a room's interior its solid pieces must cover.
const MIN_COVER_CORRIDOR := 0.03  ## Hallways and entry halls are mostly walking space.
const CORRIDORS := ["hallway", "entry_hall"]


func describe() -> Dictionary:
	return {
		"name": "Generated rooms are furnished, not bare",
		"description": "Every room of every floorplan has a minimum share of its floor covered by solid furniture; the fill pass adds pieces over a zones-only house and WorldGenConfig.fill_scale = 0 turns it off.",
		"tags": ["worldgen", "house", "furniture", "fill"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	# run() flips these; registering them has the harness put them back whatever way the test ends.
	s.set_static(WorldGenConfig, &"fill_scale", WorldGenConfig.fill_scale)
	s.set_static(WorldGenConfig, &"fill_enabled", WorldGenConfig.fill_enabled)


## The solid pieces and their combined footprint area in each room of `house`: key -> { count, area }.
func _furniture(house: Node2D) -> Dictionary:
	var result := {}
	for room in WorldGen.get_rooms(house):
		var node := house.get_node_or_null(String(room["key"]).capitalize() + " Furniture")
		var count := 0
		var area := 0.0
		if node:
			for piece in node.get_children():
				if piece.solid:
					count += 1
					area += piece.size.x * piece.size.y
		result[room["key"]] = { "count": count, "area": area }
	return result


## Total solid pieces across every plan and seed, and (when `check_cover`) the per-room cover assertions. The
## houses are built under a node that is never in the tree: only their pieces' fields and metas are read, so
## there is no need to paint, collide or register anything.
func _survey(t: TestContext, check_cover: bool) -> int:
	var pieces := 0
	var holder := Node2D.new()
	for plan in HouseDefinitions.get_all():
		for house_seed in SEEDS:
			var house := WorldGen.generate(house_seed, plan, FAR_AWAY, holder)
			var furniture := _furniture(house)
			for room in WorldGen.get_rooms(house):
				var f: Dictionary = furniture[room["key"]]
				pieces += f["count"]
				if check_cover:
					var floor_area := (room["rect"] as Rect2).grow(-12.0).get_area()
					var floor_min: float = MIN_COVER_CORRIDOR if room["type"] in CORRIDORS else MIN_COVER
					t.check(f["area"] / floor_area >= floor_min, "%s seed %d: the %s (%s) is %.0f%% furnished, at least %.0f%% expected" % [
						plan, house_seed, room["key"], room["type"], 100.0 * f["area"] / floor_area, 100.0 * floor_min])
			house.free()
	holder.free()
	return pieces


func run(t: TestContext) -> void:
	var filled := _survey(t, true)

	WorldGenConfig.fill_scale = 0.0
	var zones_only := _survey(t, false)
	WorldGenConfig.fill_scale = 1.0
	t.check(filled > zones_only, "the fill pass adds pieces (%d with, %d without)" % [filled, zones_only])

	WorldGenConfig.fill_enabled = false
	var disabled := _survey(t, false)
	WorldGenConfig.fill_enabled = true
	t.expect_eq(disabled, zones_only, "fill_enabled = false matches fill_scale = 0")
	await t.frames(1)
