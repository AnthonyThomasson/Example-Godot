extends GameTest

## A bleed-out pool blurs its fill field twice a redraw (blood_pool_visuals.gd `_box_blur`), every physics frame while it
## spreads. The blur adds each cell's three-cell row sums (kept in doubles) where it once added the nine cells one by one;
## a sum of float32 fills is exact in a double, so the field is the same. This pins it to the plain nine-cell loop, value for
## value, over random fields of pool-like shapes: mostly empty, a blob of fills from 0 to 1, a few very faint cells.

const PoolVisuals := preload("res://scenes/physics/blood/blood_pool_visuals.gd")
const SEED := 2024
const FIELDS := 60


func describe() -> Dictionary:
	return {
		"name": "A bleed-out pool's blur is the same as the plain sum",
		"description": "BloodPoolVisuals._box_blur gives the very values of the plain nine-cell loop, over random pool fields, both passes.",
		"tags": ["blood", "draw"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var cells := 0
	var differing := 0
	for n in FIELDS:
		var w := rng.randi_range(7, 48)
		var h := rng.randi_range(7, 48)
		var field := PackedFloat32Array()
		field.resize(w * h)
		var centre := Vector2(rng.randf_range(0.3, 0.7) * w, rng.randf_range(0.3, 0.7) * h)
		var reach := rng.randf_range(2.0, minf(w, h) * 0.4)
		for y in range(3, h - 3):
			for x in range(3, w - 3):
				var d := Vector2(x, y).distance_to(centre)
				if d < reach:
					field[y * w + x] = clampf(1.0 - d / reach + rng.randf_range(-0.2, 0.2), 0.0, 1.0)
				elif rng.randf() < 0.05:
					field[y * w + x] = rng.randf() * 1e-6  # a faint fringe
		var fast := field
		var plain := field
		for pass_i in 2:
			fast = PoolVisuals._box_blur(fast, w, h)
			plain = _plain_blur(plain, w, h)
			cells += w * h
			for i in fast.size():
				if fast[i] != plain[i]:
					differing += 1
	t.check(cells > 50000, "cells compared (%d)" % cells)
	t.check(differing == 0, "%d of %d blurred cells differ from the plain sum" % [differing, cells])


## `_box_blur` as it was: the nine cells added one by one.
func _plain_blur(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var sum := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					sum += src[(y + dy) * w + x + dx]
			out[y * w + x] = sum / 9.0
	return out
