class_name BloodSpawner

## Physics System: builds blood in the world — one splatter (BloodSplat) per call to `splat`, and a dead
## body's flowing pool (BloodPool) per call to `bleed`. `BloodWound` and `Physics` call it.

const BloodPool = preload("res://scenes/physics/blood/blood_pool.gd")
const BloodPoolVisuals = preload("res://scenes/physics/blood/blood_pool_visuals.gd")
const BloodSplat = preload("res://scenes/physics/blood/blood_splat.gd")


## Add one splatter (BloodSplat) of core radius `size` at world `position` under `parent`, thrown toward
## `direction` with `energy` 0..1; `exclude` is the bleeding body's RID(s), ignored by its wall clipping.
## Returns the splat (Despawner-tracked).
static func splat(parent: Node, position: Vector2, size: float, direction: Vector2, energy: float, exclude: Array) -> Node:
	var node := Node2D.new()
	node.name = "BloodSplat"
	node.script = BloodSplat
	parent.add_child(node, true)  # readable names (BloodSplat, BloodSplat2, …)
	node.global_position = position
	Despawner.track(node)
	node.call(&"setup", size, direction, energy, exclude)
	return node


## Start `source`'s bleed-out pool where its blood leaves it (`blood_origin()`, else its position):
## a flood-fill (BloodConfig.bleed_out_*, flow_*) flowing slowly around obstacles into one pool. Returns the pool.
static func bleed(parent: Node, source: Node2D, exclude: Array) -> Node:
	var at: Vector2 = source.blood_origin() if source.has_method("blood_origin") else source.global_position
	var pool := _new_pool(at, parent)
	pool.seed_bleed_out(BloodConfig.bleed_out_cells, BloodConfig.bleed_out_duration, exclude)
	return pool


## A fresh, empty, Despawner-tracked pool (with its draw layer) at world `position` under `parent`.
static func _new_pool(position: Vector2, parent: Node) -> Node:
	var pool := Node2D.new()
	pool.name = "BloodPool"
	pool.script = BloodPool
	pool.z_index = BloodConfig.z_index  # the whole pool lies at blood's rung; its draw layer inherits it

	var visuals := Node2D.new()
	visuals.name = "BloodPoolVisuals"
	visuals.script = BloodPoolVisuals
	pool.add_child(visuals)

	parent.add_child(pool, true)  # readable names (BloodPool, BloodPool2, …) so observers can tell pools apart
	# `position` is a world point; place the pool there regardless of the parent's transform (a
	# world-root parent may be offset from the origin).
	pool.global_position = position
	Despawner.track(pool)
	return pool
