extends RefCounted

## Top-down pixel-art CLINIC painter (Objects domain, private): the ripperdoc's steel furniture, `kind` in the options.
##   `tool_cart`: an instrument cart, a rimmed tray of scalpels and clamps, a syringe and a small diagnostic screen (glowing,
##     in its `neon` or the cheap screens' green);
##   `cyberware_shelf`: an open steel shelf of cyberware, chrome arms with joints, eyes, chips with pins and jars.
## Canonical frame: the front toward +y. The catalogue colour is the steel's. Run down (decay.gd): grime, rust, scratches.
## Knobs: ObjectArtConfig.clinic_*.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")

const _BODY_HEIGHT := 4  ## Heights for cast shadows.
const _TOOL_HEIGHT := 5
const _SHELF_HEIGHT := 7


## Paint the clinic piece `opts.kind` onto `c` in `base` steel, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "tool_cart")):
		"cyberware_shelf":
			_shelf(c, base)
		_:
			_cart(c, base, Decay.screen_color(opts))
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, maxi(2, int(c.w * c.h / 400.0)))
	Decay.scratches(c, 3)


## The cart: its tray of instruments, the syringe and the screen.
static func _cart(c: PixelCanvas, base: Color, screen: Color) -> void:
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, _BODY_HEIGHT, 2)
	var tray := Rect2i(3, 3, c.w - 6, c.h - 6)
	c.fill(PixelCanvas.rounded(tray, 1), ObjectArtConfig.clinic_tray_color, _BODY_HEIGHT)
	var steel := ObjectArtConfig.clinic_chrome_color
	for i in 4:
		var x := tray.position.x + 3 + i * 4
		c.line(Vector2i(x, tray.position.y + 2), Vector2i(x, mini(tray.end.y - 3, tray.position.y + 9)), steel, _TOOL_HEIGHT)
		c.px(x, tray.position.y + 2, ObjectArtConfig.tech_dark_color, _TOOL_HEIGHT)
	var sy := tray.end.y - 3
	c.line(Vector2i(tray.position.x + 2, sy), Vector2i(tray.position.x + 12, sy), steel.lightened(0.3), _TOOL_HEIGHT)
	c.px(tray.position.x + 6, sy, Decay.STICKERS[0], _TOOL_HEIGHT)
	Decay.screen(c, Rect2i(tray.end.x - 12, tray.position.y + 2, 9, 6), screen)


## The shelf: its dark well, filled along its length with arms, eyes, chips and jars.
static func _shelf(c: PixelCanvas, base: Color) -> void:
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, _SHELF_HEIGHT, 1)
	var well := Rect2i(3, 3, c.w - 6, c.h - 6)
	c.fill(PixelCanvas.rounded(well, 0), ObjectArtConfig.tech_dark_color, 1)
	var chrome := ObjectArtConfig.clinic_chrome_color
	var x := well.position.x + 2
	while x < well.end.x - 6:
		match c.rng.randi_range(0, 3):
			0:  # An arm along the depth: upper, elbow, forearm.
				c.line(Vector2i(x, well.position.y + 1), Vector2i(x, well.end.y - 3), chrome, _TOOL_HEIGHT)
				c.line(Vector2i(x + 1, well.position.y + 1), Vector2i(x + 1, well.end.y - 3), chrome.darkened(0.25), _TOOL_HEIGHT)
				c.fill(PixelCanvas.disc(Vector2i(x, well.position.y + int(well.size.y / 2.0)), 1), ObjectArtConfig.clinic_joint_color, _TOOL_HEIGHT)
				x += 5
			1:  # An eye.
				var o := Vector2i(x + 3, well.position.y + c.rng.randi_range(4, maxi(4, well.size.y - 5)))
				c.fill(PixelCanvas.disc(o, 3), ObjectArtConfig.clinic_eye_color, _TOOL_HEIGHT)
				c.fill(PixelCanvas.disc(o, 1), ObjectArtConfig.clinic_joint_color, _TOOL_HEIGHT)
				x += 8
			2:  # A chip with its pins.
				var r := Rect2i(x, well.position.y + c.rng.randi_range(2, maxi(2, well.size.y - 8)), 6, 5)
				c.fill(PixelCanvas.rounded(r, 0), ObjectArtConfig.clinic_chip_color, _TOOL_HEIGHT)
				for k in range(r.position.x, r.end.x, 2):
					c.px(k, r.position.y - 1, ObjectArtConfig.clinic_pin_color, _TOOL_HEIGHT)
					c.px(k, r.end.y, ObjectArtConfig.clinic_pin_color, _TOOL_HEIGHT)
				x += 8
			_:  # A jar.
				var o := Vector2i(x + 3, well.position.y + 5)
				c.fill(PixelCanvas.disc(o, 3), ObjectArtConfig.clinic_jar_color, _TOOL_HEIGHT)
				c.outline(PixelCanvas.disc(o, 3), chrome)
				x += 8
