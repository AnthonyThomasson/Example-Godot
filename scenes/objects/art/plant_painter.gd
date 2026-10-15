extends RefCounted

## Top-down pixel-art POTTED PLANT painter (Objects domain, private), kept within the inscribed
## circle of its round footprint: a terracotta pot with a lit rim around dark soil, and a crown of
## tapering leaves radiating from the middle in two tones, each with a pale midrib. Run down: the leaves wilted toward
## dead brown (ObjectArtConfig.plant_wilt) and the whole grimy (decay.gd). Options (`art_opts`, defaulting to
## ObjectArtConfig.plant_*): `leaves`.

const Decay = preload("res://scenes/objects/art/decay.gd")

const _POT_HEIGHT := 3  ## Heights for cast shadows: leaves arch over the pot.
const _LEAF_HEIGHT := 7


## Paint a plant onto `c` with `base` foliage.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var o := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var radius := int(mini(c.w, c.h) / 2.0) - 1
	var pot_col := ObjectArtConfig.plant_pot_color
	var pt := PixelCanvas.tones(pot_col)
	var pot := PixelCanvas.disc(o, roundi(radius * 0.72))
	c.fill(pot, pot_col, _POT_HEIGHT)
	c.bevel(pot, 1, 2, pt.light, pt.dark)
	c.outline(pot, pt.outline)
	c.fill(PixelCanvas.disc(o, roundi(radius * 0.55)), ObjectArtConfig.plant_soil_color, 1)

	var leaf := base.lerp(ObjectArtConfig.plant_dead_color, ObjectArtConfig.plant_wilt)
	var n := int(opts.get("leaves", ObjectArtConfig.plant_leaves))
	var spin := c.rng.randf() * TAU
	for i in n:
		var a := spin + TAU * i / n + c.rng.randf_range(-0.25, 0.25)
		var length := radius * c.rng.randf_range(0.75, 1.0)
		_leaf(c, o, Vector2(cos(a), sin(a)), length, leaf if i % 2 == 0 else leaf.darkened(0.14))
	c.cast_shadows()
	Decay.grime(c)
	Decay.blotches(c, 2, 0.3, 3)


## One tapering leaf from `o` along `dir`: widest a third of the way out, with a pale midrib and a
## sunlit edge on the side facing the light.
static func _leaf(c: PixelCanvas, o: Vector2i, dir: Vector2, length: float, col: Color) -> void:
	var side := dir.orthogonal()
	var lit_side := 1.0 if side.dot(c.light) > 0.0 else -1.0
	var width := maxf(1.5, length * 0.2)
	for step in roundi(length * 2.0):
		var f := step / (length * 2.0)
		var half := width * sin(PI * minf(1.0, f * 1.15)) * (1.0 - f * 0.4)
		var p := Vector2(o) + dir * f * length
		for s in range(-ceili(half), ceili(half) + 1):
			var q := Vector2i((p + side * s).round())
			var tone := col.lightened(0.18) if signf(s) == lit_side and absf(s) >= half - 1.0 else col
			c.px(q.x, q.y, tone, _LEAF_HEIGHT)
		var mid := Vector2i(p.round())
		if f > 0.15 and f < 0.85:
			c.px(mid.x, mid.y, col.lightened(0.3), _LEAF_HEIGHT)
