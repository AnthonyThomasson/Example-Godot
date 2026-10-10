extends RefCounted

## Top-down pixel-art COAT RACK painter (Objects domain, private), kept within the inscribed circle
## of its round footprint: three coats hanging from the hooks, splayed outward with a pale collar,
## a hat on top and the wooden post cap with its hook arms. No options.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _COAT_HEIGHT := 5  ## Heights for cast shadows, floor-up.
const _HAT_HEIGHT := 8
const _POST_HEIGHT := 9


## Paint a coat rack onto `c` with a `base` wooden post.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	var o := Vector2i(c.w / 2, c.h / 2)
	var radius := mini(c.w, c.h) / 2 - 1
	var spin := c.rng.randf() * TAU
	for i in 3:
		var a := spin + TAU * i / 3.0
		var d := Vector2(cos(a), sin(a))
		var col := _pick(c)
		var body := PixelCanvas.disc(o + Vector2i((d * radius * 0.5).round()), maxi(2, roundi(radius * 0.4)))
		c.fill(body, col, _COAT_HEIGHT)
		c.bevel(body, 1, 1, col.lightened(0.15), col.darkened(0.25))
		c.outline(body, col.darkened(0.45))
		c.line(o + Vector2i((d * radius * 0.25).round()), o + Vector2i((d * radius * 0.7).round()), col.darkened(0.3), _COAT_HEIGHT)
		c.px(o.x + roundi(d.x * radius * 0.3), o.y + roundi(d.y * radius * 0.3), col.lightened(0.35), _COAT_HEIGHT)
	var hat := _pick(c)
	var brim := PixelCanvas.disc(o, maxi(2, roundi(radius * 0.42)))
	c.fill(brim, hat.darkened(0.2), _HAT_HEIGHT)
	c.outline(brim, hat.darkened(0.5))
	c.fill(PixelCanvas.disc(o, maxi(1, roundi(radius * 0.27))), hat, _HAT_HEIGHT)
	var t := PixelCanvas.tones(base)
	for i in 4:
		var a := spin + PI * 0.25 + TAU * i / 4.0
		c.line(o, o + Vector2i((Vector2(cos(a), sin(a)) * radius * 0.35).round()), t.dark, _POST_HEIGHT)
	c.fill(PixelCanvas.disc(o, 1), t.light, _POST_HEIGHT)
	c.cast_shadows()


## A random coat color.
static func _pick(c: PixelCanvas) -> Color:
	var list: Array = ObjectArtConfig.prop_colors["coats"]
	return list[c.rng.randi_range(0, list.size() - 1)]
