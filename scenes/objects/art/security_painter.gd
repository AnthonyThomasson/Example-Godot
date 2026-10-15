extends RefCounted

## Top-down pixel-art SECURITY painter (Objects domain, private): the security vestibule's steel, `kind` in the options.
##   `barricade`: a heavy slab across the room, hazard-striped, propped with sandbags at both ends;
##   `scanner`: one post of the scanner arch, its emitter along the face toward the other post (+y), glowing;
##   `lockers`: a row of steel lockers seen from above, each top with a vent slot along its front and a number.
## Canonical frame: the front toward +y. The catalogue colour is the steel's. Run down (decay.gd): grime, rust, scratches
## and stickers. Knobs: ObjectArtConfig.security_*.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")

const _BAG_HEIGHT := 4  ## Heights for cast shadows.
const _SLAB_HEIGHT := 6
const _LOCKER_HEIGHT := 9
const _POST_HEIGHT := 12


## Paint the security piece `opts.kind` onto `c` in `base` steel, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "barricade")):
		"scanner":
			_scanner(c, base)
		"lockers":
			_lockers(c, base)
		_:
			_barricade(c, base)
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, maxi(2, int(c.w * c.h / 400.0)))
	Decay.scratches(c, 4)
	Decay.stickers(c, 1)


## The slab between two stacks of sandbags, its back edge striped.
static func _barricade(c: PixelCanvas, base: Color) -> void:
	var end := int(c.w * 0.14)
	var slab := Rect2i(int(c.w * 0.12), 2, c.w - int(c.w * 0.24), c.h - 4)
	Tech.box(c, slab, base, _SLAB_HEIGHT, 2)
	var stripe := ObjectArtConfig.security_hazard_color
	var dark := ObjectArtConfig.tech_dark_color
	for x in range(slab.position.x + 2, slab.end.x - 2):
		for y in range(slab.position.y + 2, mini(slab.end.y - 1, slab.position.y + 5)):
			c.px(x, y, stripe if int((x + y) / 4.0) % 2 == 0 else dark)
	for at in [0, c.w - end]:
		for k in 3:
			var h := int((c.h - 2) / 3.0)
			Tech.box(c, Rect2i(at + (k % 2) * 3, 1 + k * h, int(c.w * 0.13), h), ObjectArtConfig.security_sandbag_color, _BAG_HEIGHT, 3)


## A scanner post: a tall rounded box, its emitter strip along the front face and a lens on top.
static func _scanner(c: PixelCanvas, base: Color) -> void:
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, _POST_HEIGHT, 3)
	Decay.screen(c, Rect2i(3, c.h - 4, c.w - 6, 2), ObjectArtConfig.security_beam_color)
	c.fill(PixelCanvas.disc(Vector2i(int(c.w / 2.0), int(c.h / 2.0) - 2), 2), ObjectArtConfig.tech_dark_color, _POST_HEIGHT)


## The lockers, every other one a shade darker, each with its vent slots along the front and its number.
static func _lockers(c: PixelCanvas, base: Color) -> void:
	var n := maxi(2, int(c.w / 24.0))
	var lw := int(c.w / float(n))
	for i in n:
		var r := Rect2i(i * lw, 0, lw - 1, c.h)
		var steel := base if i % 2 == 0 else base.darkened(0.12)
		Tech.box(c, r, steel, _LOCKER_HEIGHT, 1)
		for y in range(c.h - 6, c.h - 2, 2):
			c.line(Vector2i(r.position.x + 3, y), Vector2i(r.end.x - 4, y), steel.darkened(0.4))
		c.px(r.position.x + int(lw / 2.0), 4, ObjectArtConfig.security_number_color)
