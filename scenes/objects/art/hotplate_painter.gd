extends RefCounted

## Top-down pixel-art HOTPLATE painter (Objects domain, private): the kitchenette's two-ring hotplate on a crate, one ring
## glowing hot, a pan on the other. Canonical frame: the front toward +y. The catalogue colour is the plate's. Run down
## (decay.gd): grease, grime and rust. The hot ring gives light: drawn glowing in ObjectArtConfig.hotplate_ring_color.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")

const _CRATE_HEIGHT := 3  ## Heights for cast shadows.
const _PLATE_HEIGHT := 5
const _PAN_HEIGHT := 7


## Paint the hotplate on its crate onto `c`, `base` the plate, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	var crate := ObjectArtConfig.hotplate_crate_color
	Tech.box(c, Rect2i(0, 0, c.w, c.h), crate, _CRATE_HEIGHT, 1)
	for x in range(0, c.w, 6):  # The crate's slats.
		c.line(Vector2i(x, 1), Vector2i(x, c.h - 2), crate.darkened(0.3), _CRATE_HEIGHT)
	var plate := Rect2i(3, 4, c.w - 6, c.h - 8)
	Tech.box(c, plate, base, _PLATE_HEIGHT, 2)
	var r := maxi(3, int(plate.size.y / 2.0) - 2)
	var left := Vector2i(plate.position.x + r + 2, plate.position.y + int(plate.size.y / 2.0))
	var right := Vector2i(plate.end.x - r - 3, left.y)
	var hot := ObjectArtConfig.hotplate_ring_color
	c.glowing(func() -> void:
		c.outline(PixelCanvas.disc(left, r), hot)
		c.outline(PixelCanvas.disc(left, maxi(1, r - 2)), hot.darkened(0.3)))
	var pan := PixelCanvas.disc(right, r + 1)
	var pan_col := ObjectArtConfig.hotplate_pan_color
	c.fill(pan, pan_col, _PAN_HEIGHT)
	c.outline(pan, PixelCanvas.tones(pan_col).outline)
	c.line(right + Vector2i(r + 1, 0), right + Vector2i(r + 6, 1), pan_col.darkened(0.2), _PAN_HEIGHT)
	c.cast_shadows()
	Decay.stain(c, Decay.GREASE, 3)
	Decay.grime(c)
	Decay.rust(c, 3)
