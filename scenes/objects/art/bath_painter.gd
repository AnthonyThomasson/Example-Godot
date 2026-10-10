extends RefCounted

## Top-down pixel-art BATH painter (Objects domain, private). Painted in the canonical frame
## (front toward +y). A `tub`: a glazed rim around a sunken basin of rippled water, a drain and a
## mixer tap at one end. A `shower`: a tiled tray with a central drain, a glass screen along the
## front and one side, a shower head on its arm and a soap dish. Options (`art_opts`):
## `style` ("tub" | "shower").

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _TRAY_HEIGHT := 1  ## Heights for cast shadows.
const _RIM_HEIGHT := 5
const _FIXTURE_HEIGHT := 8


## Paint a tub or shower onto `c` in `base` glaze, front toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	if String(opts.get("style", "tub")) == "shower":
		_shower(c, base, material)
	else:
		_tub(c, base, material)
	c.cast_shadows()


## Rim, sunken basin (inverted bevel), water with ripples and glare, drain and tap at the left end.
static func _tub(c: PixelCanvas, base: Color, material: String) -> void:
	var t := PixelCanvas.tones(base)
	var full := Rect2i(0, 0, c.w, c.h)
	var rim := PixelCanvas.rounded(full, mini(10, mini(c.w, c.h) / 4))
	c.fill(rim, base, _RIM_HEIGHT)
	c.surface(rim, material, base)
	c.bevel(rim, 2, 3, t.highlight, t.dark)
	c.outline(rim, t.shadow)
	var lip := maxi(4, mini(c.w, c.h) / 12)
	var basin_rect := full.grow(-lip)
	var basin := PixelCanvas.rounded(basin_rect, mini(14, mini(basin_rect.size.x, basin_rect.size.y) / 3))
	c.fill(basin, base.darkened(0.06), _TRAY_HEIGHT)
	c.bevel(basin, 1, 2, t.shadow, t.light)
	var water_col := ObjectArtConfig.bath_water_color
	var water_rect := basin_rect.grow(-3)
	var water := PixelCanvas.rounded(water_rect, mini(12, mini(water_rect.size.x, water_rect.size.y) / 3))
	c.fill(water, water_col, _TRAY_HEIGHT)
	for _i in maxi(3, water_rect.get_area() / 500):
		var p := water_rect.position + Vector2i(c.rng.randi_range(4, water_rect.size.x - 10), c.rng.randi_range(3, water_rect.size.y - 4))
		c.line(p, p + Vector2i(c.rng.randi_range(3, 6), 0), water_col.lightened(0.18))
	c.glare(water, water_col.lightened(0.45), 2)
	var cy := c.h / 2
	var metal := ObjectArtConfig.counter_tap_color
	var drain := Vector2i(basin_rect.position.x + 7, cy)
	c.fill(PixelCanvas.disc(drain, 2), metal.darkened(0.25))
	c.px(drain.x, drain.y, metal.darkened(0.6))
	c.fill(PixelCanvas.rounded(Rect2i(1, cy - 1, lip + 4, 2), 0), metal, _FIXTURE_HEIGHT)
	for dy in [-5, 5]:
		c.fill(PixelCanvas.disc(Vector2i(lip / 2 + 1, cy + dy), 1), metal, _FIXTURE_HEIGHT)


## Tiled tray, drain grate, a glass screen along the front and right side, the shower head on its
## arm from the back wall, and a soap dish in the back corner.
static func _shower(c: PixelCanvas, base: Color, material: String) -> void:
	var t := PixelCanvas.tones(base)
	var tray := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 2)
	c.fill(tray, base, _TRAY_HEIGHT)
	c.surface(tray, material if material != "glass" else "ceramic", base)
	var cell := maxi(4, ObjectArtConfig.bath_tile_px)
	var grout := base.darkened(0.14)
	for x in range(3, c.w - 3, cell):
		c.line(Vector2i(x, 3), Vector2i(x, c.h - 4), grout)
	for y in range(3, c.h - 3, cell):
		c.line(Vector2i(3, y), Vector2i(c.w - 4, y), grout)
	c.bevel(tray, 1, 2, t.light, t.dark)
	c.outline(tray, t.shadow)

	var metal := ObjectArtConfig.counter_tap_color
	var o := Vector2i(c.w / 2, c.h / 2)
	var drain := PixelCanvas.disc(o, 3)
	c.fill(drain, metal)
	c.outline(drain, metal.darkened(0.4))
	for d in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		c.px(o.x + d.x, o.y + d.y, metal.darkened(0.5))

	var glass := ObjectArtConfig.shower_glass_color
	var band := 2
	c.fill(PixelCanvas.rounded(Rect2i(0, c.h - band, c.w, band), 0), glass, _FIXTURE_HEIGHT)
	c.fill(PixelCanvas.rounded(Rect2i(c.w - band, 0, band, c.h), 0), glass, _FIXTURE_HEIGHT)
	c.line(Vector2i(1, c.h - band), Vector2i(c.w - band - 1, c.h - band), glass.lightened(0.4))
	c.line(Vector2i(c.w - band, 1), Vector2i(c.w - band, c.h - band - 1), glass.lightened(0.4))

	var head := Vector2i(roundi(c.w * 0.22), roundi(c.h * 0.16))
	c.fill(PixelCanvas.rounded(Rect2i(head.x - 1, 0, 2, head.y), 0), metal, _FIXTURE_HEIGHT)
	var rose := PixelCanvas.disc(head, maxi(2, c.w / 18))
	c.fill(rose, metal, _FIXTURE_HEIGHT + 1)
	c.outline(rose, metal.darkened(0.35))
	c.px(head.x, head.y, metal.darkened(0.45))
	var dish := Rect2i(c.w - roundi(c.w * 0.26), 2, roundi(c.w * 0.14), 4)
	c.fill(PixelCanvas.rounded(dish, 1), metal, _FIXTURE_HEIGHT - 2)
	c.fill(PixelCanvas.ellipse(dish.grow(-1)), Color(0.95, 0.88, 0.85), _FIXTURE_HEIGHT - 1)
