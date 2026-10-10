extends RefCounted

## Top-down pixel-art open SHELF painter (Objects domain, private). Painted in the canonical frame
## (front toward +y): a material frame around a shadowed well, filled with what the shelf holds as
## seen from above — rows of book tops, cardboard boxes and paint tins, or pairs of shoes. Metal
## frames show corner uprights. Options (`art_opts`, defaulting to ObjectArtConfig.shelf_*):
## `contents` ("books" | "boxes" | "shoes").

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _FRAME_HEIGHT := 5    ## Heights for cast shadows: the frame stands over its contents.
const _CONTENT_HEIGHT := 3


## Paint a shelf onto `c` in `base` with a `material` frame, front toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var frame := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 1)
	c.fill(frame, base, _FRAME_HEIGHT)
	c.surface(frame, material, base)
	var border := maxi(2, roundi(mini(c.w, c.h) * 0.08))
	var well := Rect2i(0, 0, c.w, c.h).grow(-border)
	c.fill(PixelCanvas.rounded(well, 0), t.shadow.darkened(0.3), 1)
	match String(opts.get("contents", ObjectArtConfig.shelf_contents)):
		"books":
			_books(c, well)
		"boxes":
			_boxes(c, well)
		"shoes":
			_shoes(c, well)
	c.bevel(frame, 2, 2, t.light, t.dark)
	c.outline(frame, t.outline)
	if material == "metal":
		for p in [Vector2i(0, 0), Vector2i(c.w - 3, 0), Vector2i(0, c.h - 3), Vector2i(c.w - 3, c.h - 3)]:
			var post := PixelCanvas.rounded(Rect2i(p, Vector2i(3, 3)), 0)
			c.fill(post, t.dark, _FRAME_HEIGHT + 1)
			c.outline(post, t.outline)
	c.cast_shadows()


## Book tops standing against the back: covers in assorted colors around a pale page block, the
## odd gap, and every so often a small vase on the shelf.
static func _books(c: PixelCanvas, well: Rect2i) -> void:
	var paper: Color = ObjectArtConfig.prop_colors["paper"]
	var x := well.position.x
	while x < well.end.x - 1:
		var roll := c.rng.randf()
		if roll < 0.08:
			x += c.rng.randi_range(1, 3)
			continue
		if roll < 0.12 and well.end.x - x > 8:
			var o := Vector2i(x + 3, well.position.y + mini(4, well.size.y / 3))
			c.fill(PixelCanvas.disc(o, 2), ObjectArtConfig.prop_colors["glaze"], _CONTENT_HEIGHT + 1)
			x += 7
			continue
		var bw := mini(c.rng.randi_range(2, 4), well.end.x - x)
		var bh := maxi(2, roundi(well.size.y * c.rng.randf_range(0.6, 0.95)))
		var cover := _pick(c, "books")
		var r := Rect2i(x, well.position.y, bw, bh)
		c.fill(PixelCanvas.rounded(r, 0), cover, _CONTENT_HEIGHT)
		if bw >= 3:
			c.fill(PixelCanvas.rounded(Rect2i(x + 1, r.position.y + 1, bw - 2, bh - 2), 0), paper)
		else:
			c.line(Vector2i(x + bw - 1, r.position.y), Vector2i(x + bw - 1, r.end.y - 1), cover.darkened(0.3))
		c.px(x, r.end.y - 1, cover.darkened(0.35))
		x += bw


## Cardboard boxes of assorted sizes with tape and flap seams, and the odd paint tin.
static func _boxes(c: PixelCanvas, well: Rect2i) -> void:
	var card := ObjectArtConfig.shelf_box_color
	var x := well.position.x + 1
	while x < well.end.x - 4:
		var depth := maxi(4, roundi(well.size.y * c.rng.randf_range(0.6, 0.95)))
		if c.rng.randf() < 0.3:
			var rad := mini(depth / 2, 5)
			var o := Vector2i(x + rad, well.position.y + rad + 1)
			var tin := PixelCanvas.disc(o, rad)
			var label := _pick(c, "books")
			c.fill(tin, ObjectArtConfig.prop_colors["metal"], _CONTENT_HEIGHT)
			c.outline(tin, ObjectArtConfig.prop_colors["metal"].darkened(0.4))
			c.outline(PixelCanvas.disc(o, maxi(1, rad - 2)), label)
			x += rad * 2 + 2
			continue
		var bw := mini(c.rng.randi_range(10, 22), well.end.x - x - 1)
		var r := Rect2i(x, well.position.y + 1, bw, depth)
		var tone := card.darkened(c.rng.randf_range(0.0, 0.15))
		var box := PixelCanvas.rounded(r, 0)
		c.fill(box, tone, _CONTENT_HEIGHT)
		c.bevel(box, 1, 1, tone.lightened(0.12), tone.darkened(0.25))
		c.line(Vector2i(r.position.x + 1, r.position.y + r.size.y / 2), Vector2i(r.end.x - 2, r.position.y + r.size.y / 2), tone.darkened(0.3))
		var tape := r.position.x + r.size.x / 2
		c.line(Vector2i(tape, r.position.y + 1), Vector2i(tape, r.end.y - 2), tone.lightened(0.25))
		x += bw + 1


## Pairs of shoes, toes toward the front: two soles with a dark opening near the heel.
static func _shoes(c: PixelCanvas, well: Rect2i) -> void:
	var sw := maxi(3, well.size.y / 4)
	var x := well.position.x + 1
	while x + sw * 2 + 1 <= well.end.x:
		var col := _pick(c, "shoes")
		var length := maxi(sw + 2, roundi(well.size.y * c.rng.randf_range(0.75, 0.95)))
		for i in 2:
			var r := Rect2i(x + i * (sw + 1), well.end.y - length, sw, length)
			var shoe := PixelCanvas.ellipse(r)
			c.fill(shoe, col, _CONTENT_HEIGHT)
			c.outline(shoe, col.darkened(0.45))
			c.fill(PixelCanvas.ellipse(Rect2i(r.position.x + 1, r.position.y + 1, maxi(1, sw - 2), maxi(2, length * 2 / 5))), col.darkened(0.55))
		x += sw * 2 + 3


## A random entry of the prop palette list `name`.
static func _pick(c: PixelCanvas, name: String) -> Color:
	var list: Array = ObjectArtConfig.prop_colors.get(name, [Color.MAGENTA])
	return list[c.rng.randi_range(0, list.size() - 1)]
