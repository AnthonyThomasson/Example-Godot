extends RefCounted

## Top-down pixel-art APPLIANCE painter (white goods and electronics; Objects domain, private).
## Painted in the canonical frame (front toward +y): a rounded enamel or brushed-metal box whose top
## shows what the appliance is — a stove's burners and knob strip, a fridge's vent grille and door
## handles, a microwave's vents, window and keypad, a washer's glass lid full of laundry or a
## dryer's solid lid and vents — or a TV's slim screen on its stand. Options (`art_opts`,
## defaulting to ObjectArtConfig.appliance_*): `panel` ("plain" | "burners" | "fridge" |
## "microwave" | "washer" | "dryer" | "tv").

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _BODY_HEIGHT := 4  ## Heights for cast shadows.
const _KNOB_HEIGHT := 6


## Paint an appliance onto `c` in `base` with a `material` finish, front toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var panel := String(opts.get("panel", ObjectArtConfig.appliance_panel))
	if panel == "tv":
		_tv(c, base, t)
		c.cast_shadows()
		return
	var body := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 3)
	c.fill(body, base, _BODY_HEIGHT)
	c.surface(body, material, base)
	c.bevel(body, 2, 2, t.highlight, t.dark)
	match panel:
		"burners":
			_burners(c, t)
		"fridge":
			_fridge(c, t)
		"microwave":
			_microwave(c, t)
		"washer":
			_drum(c, base, t, true)
		"dryer":
			_drum(c, base, t, false)
	c.outline(body, t.outline)
	c.cast_shadows()


## Four burners (ring, cap, cross grate) in a 2×2 grid over a knob strip along the front.
static func _burners(c: PixelCanvas, t: Dictionary) -> void:
	var strip := maxi(4, roundi(c.h * 0.16))
	c.paint_over(Rect2i(2, c.h - strip - 1, c.w - 4, strip), t.shadow)
	var metal := ObjectArtConfig.appliance_metal_color
	for i in 4:
		var kx := roundi((i + 0.5) * c.w / 4.0)
		c.fill(PixelCanvas.disc(Vector2i(kx, c.h - strip / 2 - 1), maxi(1, strip / 3)), metal, _KNOB_HEIGHT)
	var area := Rect2i(3, 3, c.w - 6, c.h - strip - 6)
	var rad := maxi(3, mini(area.size.x, area.size.y) / 4 - 1)
	for gy in 2:
		for gx in 2:
			var o := area.position + Vector2i(roundi((gx + 0.5) * area.size.x / 2.0), roundi((gy + 0.5) * area.size.y / 2.0))
			var ring := PixelCanvas.disc(o, rad)
			c.outline(ring, metal.darkened(0.2))
			c.fill(PixelCanvas.disc(o, maxi(1, rad / 3)), metal.darkened(0.45))
			c.line(o - Vector2i(rad, 0), o + Vector2i(rad, 0), metal.darkened(0.3), _BODY_HEIGHT + 1)
			c.line(o - Vector2i(0, rad), o + Vector2i(0, rad), metal.darkened(0.3), _BODY_HEIGHT + 1)


## A fridge top: a vent grille toward the back, a door seam down the front lip, and two handles.
static func _fridge(c: PixelCanvas, t: Dictionary) -> void:
	for row in 3:
		var y := 3 + row * 2
		var x := roundi(c.w * 0.25)
		while x < roundi(c.w * 0.75):
			c.line(Vector2i(x, y), Vector2i(x + 2, y), t.shadow)
			x += 4
	var lip := maxi(3, roundi(c.h * 0.08))
	c.paint_over(Rect2i(2, c.h - lip - 1, c.w - 4, lip), t.dark)
	c.line(Vector2i(c.w / 2, c.h - lip - 1), Vector2i(c.w / 2, c.h - 2), t.outline)
	var metal := ObjectArtConfig.appliance_metal_color
	for x in [c.w / 2 - 3, c.w / 2 + 2]:
		c.fill(PixelCanvas.rounded(Rect2i(x, c.h - lip - 3, 1, lip + 3), 0), metal, _KNOB_HEIGHT)


## A microwave top: vent slots at the back corner; the front lip holds the dark door window and a
## keypad with a small lit display.
static func _microwave(c: PixelCanvas, t: Dictionary) -> void:
	for row in 3:
		var y := 3 + row * 2
		for x in range(roundi(c.w * 0.55), c.w - 4, 3):
			c.line(Vector2i(x, y), Vector2i(x + 1, y), t.shadow)
	var lip := maxi(5, roundi(c.h * 0.22))
	var strip := Rect2i(2, c.h - lip - 1, c.w - 4, lip)
	c.paint_over(strip, t.dark)
	var window := PixelCanvas.rounded(Rect2i(strip.position.x + 1, strip.position.y + 1, roundi(strip.size.x * 0.62), strip.size.y - 2), 1)
	c.fill(window, ObjectArtConfig.appliance_glass_color)
	c.glare(window, ObjectArtConfig.appliance_glass_color.lightened(0.35), 1)
	var pad_x := strip.position.x + roundi(strip.size.x * 0.7)
	c.line(Vector2i(pad_x, strip.position.y + 1), Vector2i(pad_x + 3, strip.position.y + 1), ObjectArtConfig.prop_colors["glow"])
	for y in range(strip.position.y + 3, strip.end.y - 1, 2):
		for x in range(pad_x, strip.end.x - 1, 2):
			c.px(x, y, t.light)


## A washer or dryer top: a control panel along the back (dial, display, buttons) and a round
## lid — glass over tumbling laundry for a washer, solid with lint vents for a dryer.
static func _drum(c: PixelCanvas, base: Color, t: Dictionary, washer: bool) -> void:
	var panel_h := maxi(4, roundi(c.h * 0.16))
	c.paint_over(Rect2i(2, 2, c.w - 4, panel_h), t.dark)
	var metal := ObjectArtConfig.appliance_metal_color
	var dial := Vector2i(c.w - 4 - panel_h / 2, 2 + panel_h / 2)
	c.fill(PixelCanvas.disc(dial, maxi(1, panel_h / 2 - 1)), metal, _KNOB_HEIGHT)
	c.px(dial.x, dial.y - 1, t.outline)
	c.line(Vector2i(c.w / 2 - 3, 2 + panel_h / 2), Vector2i(c.w / 2 + 3, 2 + panel_h / 2), ObjectArtConfig.prop_colors["glow"])
	for i in 3:
		c.px(5 + i * 3, 2 + panel_h / 2, t.light)
	var o := Vector2i(c.w / 2, panel_h + 2 + (c.h - panel_h - 2) / 2)
	var rad := maxi(3, mini(c.w, c.h - panel_h) * 3 / 10)
	var ring := PixelCanvas.disc(o, rad)
	c.fill(ring, t.light)
	c.outline(ring, t.shadow)
	if washer:
		var glass := PixelCanvas.disc(o, rad - 2)
		c.fill(glass, ObjectArtConfig.appliance_glass_color.lerp(Color(0.4, 0.6, 0.8), 0.4))
		for i in 4:
			var a := c.rng.randf() * TAU
			var p := o + Vector2i((Vector2(cos(a), sin(a)) * c.rng.randf_range(0.0, rad - 4)).round())
			c.fill(PixelCanvas.disc(p, maxi(1, rad / 4)), _pick(c, "books").lightened(0.15))
		c.glare(glass, Color(0.85, 0.92, 1.0), 2)
	else:
		c.fill(PixelCanvas.disc(o, rad - 2), base.darkened(0.04))
		c.bevel(PixelCanvas.disc(o, rad - 2), 1, 1, t.dark, t.highlight)
		for i in 3:
			var y := c.h - 5 - i * 2
			c.line(Vector2i(4, y), Vector2i(maxi(5, rad), y), t.shadow)


## A TV from above: a slim screen bar across the back on a low stand, a lit edge toward the room
## and a standby LED. Everything else stays floor.
static func _tv(c: PixelCanvas, base: Color, _t: Dictionary) -> void:
	var stand := PixelCanvas.rounded(Rect2i(roundi(c.w * 0.32), roundi(c.h * 0.42), roundi(c.w * 0.36), roundi(c.h * 0.42)), 3)
	var metal := ObjectArtConfig.appliance_metal_color.darkened(0.45)
	c.fill(stand, metal, 2)
	c.bevel(stand, 1, 1, metal.lightened(0.25), metal.darkened(0.3))
	var depth := maxi(3, roundi(c.h * 0.18))
	var bar_rect := Rect2i(1, roundi(c.h * 0.22), c.w - 2, depth)
	var bar := PixelCanvas.rounded(bar_rect, 1)
	c.fill(bar, base, _BODY_HEIGHT + 2)
	c.bevel(bar, 1, 1, base.lightened(0.3), base.darkened(0.2))
	c.line(Vector2i(bar_rect.position.x + 1, bar_rect.end.y - 1), Vector2i(bar_rect.end.x - 2, bar_rect.end.y - 1),
			ObjectArtConfig.prop_colors["glow"])
	c.px(c.w / 2, bar_rect.end.y, Color(0.9, 0.25, 0.2))


## A random entry of the prop palette list `name`.
static func _pick(c: PixelCanvas, name: String) -> Color:
	var list: Array = ObjectArtConfig.prop_colors.get(name, [Color.MAGENTA])
	return list[c.rng.randi_range(0, list.size() - 1)]
