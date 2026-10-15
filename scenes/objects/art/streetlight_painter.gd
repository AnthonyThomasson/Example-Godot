extends RefCounted

## Top-down pixel-art STREETLIGHT painter (Objects domain, private): a street lamp seen from above, in two parts (`part` in
## the options). The default, `pole`, is the piece's own art inside its round footprint: a base plate bolted to the sidewalk
## (four bolts) and the round top of the rusted steel post, a flyer taped round it. `overhang` is its overhead part (drawn
## by the piece's `Overhang`, overhang_visuals.gd, above whoever walks under it): the arm from the post's top (the canvas'
## top centre) out over the road and, at its end, the head, `head` `cobra` (a dented cobra head, its lens facing the road)
## or `sign` (a dark board, a neon tube round its edge and two bars of letters). Canonical frame: the front (+y) is out
## over the road. Run down (decay.gd): grime and rust. What gives light (the lens, the sign's tube and letters) is drawn
## glowing: the lens in ObjectArtConfig.streetlight_lens_color, the sign in its `neon` (cyan or magenta). The catalogue
## colour is the post's paint (and its debris'). Knobs: ObjectArtConfig.streetlight_*.

const Decay = preload("res://scenes/objects/art/decay.gd")

const _PLATE_HEIGHT := 1  ## Heights for cast shadows.
const _POST_HEIGHT := 12
const _ARM_HEIGHT := 20
const _HEAD_HEIGHT := 22


## Paint the streetlight's `opts.part` onto `c`: the post in `base` paint, or its arm and head out over the road (+y).
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	if String(opts.get("part", "pole")) == "overhang":
		var head_at := c.h - int(opts.get("head_px", ObjectArtConfig.streetlight_head_px) / 2.0) - 1
		_arm(c, head_at)
		if String(opts.get("head", ObjectArtConfig.streetlight_head)) == "sign":
			_sign(c, head_at, Decay.neon(opts) if Decay.neon(opts).a > 0.0 else ObjectArtConfig.neon_magenta)
		else:
			_cobra(c, head_at)
	else:
		_pole(c, base)
	Decay.grime(c, -1.0, 2)
	Decay.rust(c, maxi(1, int(c.w * c.h / 120.0)))
	c.cast_shadows()


## The base plate (four bolts at its corners, inside the round footprint) and the post's round top, raised over it, a
## scrap of flyer taped round it.
static func _pole(c: PixelCanvas, base: Color) -> void:
	var mid := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var half := int(mini(c.w, c.h) / 2.0) - 1
	var plate_col := ObjectArtConfig.streetlight_plate_color
	var pt := PixelCanvas.tones(plate_col)
	var plate := PixelCanvas.disc(mid, half)
	c.fill(plate, plate_col, _PLATE_HEIGHT)
	c.bevel(plate, 1, 1, pt.light, pt.dark)
	c.outline(plate, pt.outline)
	for d in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		var bolt: Vector2i = mid + d * int(half * 0.62)
		c.px(bolt.x, bolt.y, pt.highlight, _PLATE_HEIGHT + 1)
	var r := maxi(2, int(half * 0.55))
	var post := PixelCanvas.disc(mid, r)
	var t := PixelCanvas.tones(base)
	c.fill(post, base, _POST_HEIGHT)
	c.bevel(post, 1, 1, t.highlight, t.shadow)
	c.outline(post, t.outline)
	c.px(mid.x + 1, mid.y - r + 1, ObjectArtConfig.streetlight_flyer_color, _POST_HEIGHT)
	c.px(mid.x + 2, mid.y - r + 1, Decay.STICKERS[0], _POST_HEIGHT)
	c.px(mid.x - 1, mid.y + 1, Decay.RUST_DARK, _POST_HEIGHT)


## The arm from the post's top (the canvas' top centre) out to just short of the head at `head_at`.
static func _arm(c: PixelCanvas, head_at: int) -> void:
	var x := int(c.w / 2.0)
	var t := PixelCanvas.tones(ObjectArtConfig.streetlight_head_color)
	c.fill(PixelCanvas.disc(Vector2i(x, 1), 2), t.dark, _ARM_HEIGHT)  # The cap the arm leaves the post by.
	for y in range(1, head_at - 4):
		c.px(x - 1, y, t.light, _ARM_HEIGHT)
		c.px(x, y, t.dark, _ARM_HEIGHT)


## A dented cobra head at the arm's end, its lens facing down at the road, glowing.
static func _cobra(c: PixelCanvas, head_at: int) -> void:
	var x := int(c.w / 2.0)
	var col := ObjectArtConfig.streetlight_head_color
	var t := PixelCanvas.tones(col)
	var rx := maxi(3, int(c.w / 2.0) - 2)
	var head := PixelCanvas.ellipse(Rect2i(x - rx, head_at - 7, rx * 2, 15))
	c.fill(head, col, _HEAD_HEIGHT)
	c.bevel(head, 1, 1, t.light, t.dark)
	c.outline(head, t.outline)
	c.px(x + 3, head_at - 3, t.shadow, _HEAD_HEIGHT)  # A dent.
	c.px(x + 4, head_at - 2, t.shadow, _HEAD_HEIGHT)
	var lens := ObjectArtConfig.streetlight_lens_color
	c.glowing(func() -> void: c.fill(PixelCanvas.ellipse(Rect2i(x - 3, head_at - 2, 6, 7)), lens, _HEAD_HEIGHT))


## A neon sign at the arm's end: a dark board, its tube run round the edge and two bars of letters, glowing in `neon`.
static func _sign(c: PixelCanvas, head_at: int, neon: Color) -> void:
	var board_col := ObjectArtConfig.streetlight_sign_color
	var board := PixelCanvas.rounded(Rect2i(1, head_at - 6, c.w - 2, 12), 1)
	c.fill(board, board_col, _HEAD_HEIGHT)
	c.outline(board, PixelCanvas.tones(board_col).outline)
	var tube := neon.lightened(0.15)
	var letters := neon.lightened(0.45)
	c.glowing(func() -> void:
		c.outline(PixelCanvas.rounded(Rect2i(2, head_at - 5, c.w - 4, 10), 1), tube)
		c.line(Vector2i(5, head_at - 1), Vector2i(int(c.w * 0.42), head_at - 1), letters, _HEAD_HEIGHT)
		c.line(Vector2i(int(c.w * 0.54), head_at - 1), Vector2i(c.w - 6, head_at - 1), letters, _HEAD_HEIGHT)
		c.line(Vector2i(7, head_at + 2), Vector2i(c.w - 8, head_at + 2), letters, _HEAD_HEIGHT))
