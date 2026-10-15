extends RefCounted

## Top-down pixel-art TECH painter (Objects domain, private): the netrunner den's hardware, `kind` in the options.
##   `monitor_wall`: a rail along the wall carrying a row of screens, the outer ones angled in, their faces glowing to the
##     room, cables off the back, and a keyboard ledge in front (a keyboard, a mug, papers);
##   `server_rack`: a steel top with rows of vents, a cable bundle off the back and a row of LEDs along the front edge.
## Canonical frame: the front toward +y, the back against the wall. Run down (decay.gd): grime, rust, stickers. What gives
## light (the screens, the LEDs) is drawn glowing, in the piece's `neon` or the cheap screens' green (Decay.screen_color).
## The catalogue colour is the casing's. Knobs: ObjectArtConfig.tech_*.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Props = preload("res://scenes/objects/art/props.gd")

const _RAIL_HEIGHT := 6  ## Heights for cast shadows.
const _SCREEN_HEIGHT := 8
const _LEDGE_HEIGHT := 3
const _RACK_HEIGHT := 9


## Paint the tech piece `opts.kind` onto `c` in a `base` casing, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var screen := Decay.screen_color(opts)
	match String(opts.get("kind", "monitor_wall")):
		"server_rack":
			_server_rack(c, base, screen)
		_:
			_monitor_wall(c, base, screen)
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, maxi(2, int(c.w * c.h / 400.0)))
	Decay.stickers(c, 1)


## A filled, bevelled, outlined box of `col`, `height` tall.
static func box(c: PixelCanvas, r: Rect2i, col: Color, height: int, radius := 2) -> PixelCanvas.Shape:
	var t := PixelCanvas.tones(col)
	var s := PixelCanvas.rounded(r, radius)
	c.fill(s, col, height)
	c.bevel(s, 1, 1, t.light, t.dark)
	c.outline(s, t.outline)
	return s


## The rail, the screens (every third a dimmer one), the cables off the back and the keyboard ledge.
static func _monitor_wall(c: PixelCanvas, base: Color, screen: Color) -> void:
	var dark := ObjectArtConfig.tech_dark_color
	box(c, Rect2i(0, 0, c.w, 4), dark, _RAIL_HEIGHT, 1)
	var n := maxi(3, int(c.w / 30.0))
	var mw := int((c.w - 4) / float(n)) - 2
	var depth := maxi(6, int(c.h * 0.2))
	for i in n:
		var edge := i == 0 or i == n - 1
		var r := Rect2i(3 + i * (mw + 2), 5 + (2 if edge else 0), mw, depth)
		box(c, r, base, _SCREEN_HEIGHT, 1)
		var glow := screen if i % 3 != 1 else screen.darkened(0.25)
		Decay.screen(c, Rect2i(r.position.x + 1, r.end.y - 3, r.size.x - 2, 2), glow)
	for i in 3:  # Cables off the back, drooping to the floor behind the ledge.
		var x := c.rng.randi_range(4, c.w - 5)
		c.line(Vector2i(x, 3), Vector2i(x + c.rng.randi_range(-3, 3), 5 + depth + 3), dark.lightened(0.15), _RAIL_HEIGHT - 1)
	var ledge := Rect2i(2, 8 + depth, c.w - 4, maxi(4, c.h - 10 - depth))
	box(c, ledge, ObjectArtConfig.tech_ledge_color, _LEDGE_HEIGHT, 1)
	var mid_y := ledge.position.y + int(ledge.size.y / 2.0)
	Props.draw(c, "keyboard", Vector2i(int(c.w / 2.0), mid_y))
	Props.draw(c, "mug", Vector2i(c.w - 14, mid_y))
	Props.draw(c, "papers", Vector2i(14, mid_y))


## The rack's top: vent rows, the LEDs along the front edge (most lit, glowing) and the cable bundle off the back.
static func _server_rack(c: PixelCanvas, base: Color, screen: Color) -> void:
	box(c, Rect2i(0, 0, c.w, c.h), base, _RACK_HEIGHT, 1)
	var t := PixelCanvas.tones(base)
	for y in range(4, c.h - 8, 3):
		for x in range(4, c.w - 4, 3):
			c.px(x, y, t.shadow)
			c.px(x + 1, y, t.shadow)
	var leds: Array[Color] = [screen, ObjectArtConfig.tech_led_colors[0], ObjectArtConfig.tech_led_colors[1]]
	for x in range(3, c.w - 3, 2):
		if c.rng.randf() < 0.7:
			var lit: Color = leds[c.rng.randi_range(0, leds.size() - 1)]
			c.glowing(func() -> void: c.px(x, c.h - 3, lit, _RACK_HEIGHT))
		else:
			c.px(x, c.h - 3, t.dark, _RACK_HEIGHT)
	c.line(Vector2i(int(c.w / 2.0) - 3, 0), Vector2i(int(c.w / 2.0) + 3, 0), ObjectArtConfig.tech_dark_color, _RACK_HEIGHT)
