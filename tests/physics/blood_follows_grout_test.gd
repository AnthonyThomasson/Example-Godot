extends GameTest

## A one-hit target is shot dead on a glazed-tile floor: it dies, the wound leaves a splatter, and once its body
## rests the bleed-out pool it spreads lies along the grout lines far more than chance (grout covers ~1/6 of the
## floor), because the flow follows the floor texture (BloodSurface). Pair: death_without_blood (the same kill with
## blood off).


func describe() -> Dictionary:
	return {
		"name": "Dead body's blood follows grout",
		"description": "A 1 hp target is shot dead on a tiled floor; its bleed-out pool claims mostly grout cells.",
		"tags": ["death", "blood", "bleed out", "floor", "surface"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.blood", true)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(560, 250), { "max_health": 1.0 })


func run(t: TestContext) -> void:
	var target := t.actor(&"target")
	var floor_node := FloorFactory.spawn(Rect2(100, 50, 696, 408), {
		"art": "floor", "color": Color(0.8, 0.8, 0.8), "material": "ceramic", "art_opts": { "pattern": "tiles" },
	}, "TestTiles", target.get_parent())
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(target)
	await t.seconds(0.4)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"died", func(d): return d["actor"] == &"target"), 2.0), "the target dies"):
		return
	t.check(target.is_dead, "is_dead is set")
	t.check(not t.spawned("BloodSplat").is_empty(), "the lethal wound left a splatter")
	# The bleed-out pool (the one BloodPool, with a flow) comes once the body rests.
	await t.until(func(): return _bleed_out_pool(t) != null, 8.0, "a bleed-out pool starts")
	var pool := _bleed_out_pool(t)
	if not t.require(pool != null, "the body bled out a flowing pool"):
		return
	await t.until(func(): return pool.flow.cells.size() >= BloodConfig.bleed_out_cells, 6.0, "the flow claims all its cells")
	var on := 0
	for c in pool.flow.cells:
		var p: Vector2 = pool.global_position + (Vector2(c) + Vector2(0.5, 0.5)) * BloodConfig.flow_cell_size
		if floor_node.flow_groove(p, BloodConfig.groove_half_width) > 0.5:
			on += 1
	var share := float(on) / maxf(pool.flow.cells.size(), 1)
	t.trace("grout share of bleed-out cells", share)
	t.check(share > 0.4, "most of the pool lies on grout (%.2f of %d cells)" % [share, pool.flow.cells.size()])


## The bleed-out pool (the BloodPool that has a flow), or null before the body rests.
func _bleed_out_pool(t: TestContext) -> Node:
	for p in t.spawned("BloodPool"):
		if p.flow:
			return p
	return null
