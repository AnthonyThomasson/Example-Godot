extends RefCounted

## Top-down pixel-art CABINET painter (storage casegoods; Objects domain, private). Painted in the
## canonical frame (front toward +y): a material-finished top, optionally framed by crown moulding,
## glazed (showing stacked plates) or a hinged lid with straps, and along the front a lip strip
## showing the doors or drawers with their handles. Options (`art_opts`, defaulting to
## ObjectArtConfig.cabinet_*): `front` ("doors" | "drawers" | "lid" | "none"), `count`,
## `front_depth`, `crown`, `top` ("solid" | "glass" | "lid"), `labels`, `handle` (a Color), `props`.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")
const Props = preload("res://scenes/objects/art/props.gd")

const _BODY_HEIGHT := 4  ## Cast-shadow height of the carcass (props stand above it).


## Paint a cabinet onto `c` in `base` with a `material` finish, front toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var lip := clampi(roundi(c.h * float(opts.get("front_depth", ObjectArtConfig.cabinet_front_depth))), 2, c.h / 3)
	var body := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 2)
	var top_rect := Rect2i(0, 0, c.w, c.h - lip)
	var top := PixelCanvas.rounded(top_rect, 2)

	c.fill(body, base, _BODY_HEIGHT)
	c.surface(top, material, base)
	if opts.get("crown", ObjectArtConfig.cabinet_crown):
		c.bevel(top, 2, 3, t.highlight, t.dark)
		c.outline(PixelCanvas.rounded(top_rect.grow(-4), 1), t.dark)
	else:
		c.bevel(top, 2, 2, t.light, t.dark)
	match String(opts.get("top", "solid")):
		"glass":
			_glass_top(c, top_rect, t)
		"lid":
			_lid(c, top_rect, base, t)

	var handle: Color = opts.get("handle", ObjectArtConfig.cabinet_handle_color)
	_front(c, Rect2i(0, c.h - lip, c.w, lip), String(opts.get("front", ObjectArtConfig.cabinet_front)),
			int(opts.get("count", ObjectArtConfig.cabinet_count)), bool(opts.get("labels", false)), base, t, handle)
	c.outline(body, t.outline)
	Props.draw_all(c, opts.get("props", []), top_rect.grow(-3))
	c.cast_shadows()


## The front lip: a face shaded by how it meets the light, split into `count` doors or drawers.
static func _front(c: PixelCanvas, strip: Rect2i, kind: String, count: int, labels: bool, base: Color,
		t: Dictionary, handle: Color) -> void:
	var facing_light := Vector2.DOWN.dot(c.light)
	var face := base.lightened(0.08) if facing_light > 0.3 else (base.darkened(0.14) if facing_light < -0.3 else base.darkened(0.05))
	c.paint_over(strip, face)
	c.line(Vector2i(1, strip.position.y), Vector2i(c.w - 2, strip.position.y), t.shadow)
	if kind == "none" or strip.size.y < 2:
		return
	var n := maxi(1, count)
	var mid_y := strip.position.y + strip.size.y / 2
	var seams: Array[int] = []
	for i in range(1, n):
		var x := roundi(float(i) * c.w / n)
		seams.append(x)
		c.line(Vector2i(x, strip.position.y + 1), Vector2i(x, strip.end.y - 2), t.shadow)
	match kind:
		"doors":
			if n == 1:
				_vbar(c, c.w - 4, strip, handle)
			for x in seams:
				_vbar(c, x - 2, strip, handle)
				_vbar(c, x + 2, strip, handle)
		"drawers":
			for i in n:
				var cx := roundi((i + 0.5) * c.w / n)
				var half := clampi(c.w / n / 6, 1, 4)
				c.line(Vector2i(cx - half, mid_y), Vector2i(cx + half, mid_y), handle, _BODY_HEIGHT + 1)
				if labels and strip.size.y >= 4:
					c.line(Vector2i(cx - 1, mid_y - 2), Vector2i(cx + 1, mid_y - 2), Color(0.92, 0.9, 0.84))
		"lid":
			c.fill(PixelCanvas.rounded(Rect2i(c.w / 2 - 2, strip.position.y, 4, mini(3, strip.size.y)), 0), handle, _BODY_HEIGHT + 1)


## A short vertical handle bar at column `x` of the front strip.
static func _vbar(c: PixelCanvas, x: int, strip: Rect2i, handle: Color) -> void:
	c.line(Vector2i(x, strip.position.y + 1), Vector2i(x, maxi(strip.position.y + 1, strip.end.y - 3)), handle, _BODY_HEIGHT + 1)


## A glazed top: a sunken pale glass panel over stacked plates, framed, with a glare streak.
static func _glass_top(c: PixelCanvas, top_rect: Rect2i, t: Dictionary) -> void:
	var pane := top_rect.grow(-3)
	if pane.size.x < 6 or pane.size.y < 6:
		return
	var glass := PixelCanvas.rounded(pane, 1)
	c.fill(glass, ObjectArtConfig.cabinet_glass_color)
	var r := mini(pane.size.y / 2 - 1, 6)
	var x := pane.position.x + r + 1
	while x + r < pane.end.x:
		Props.draw(c, "plate", Vector2i(x, pane.position.y + pane.size.y / 2))
		x += r * 2 + 3
	c.glare(glass, ObjectArtConfig.cabinet_glass_color.lightened(0.5), 2)
	c.outline(glass, t.shadow)


## A chest lid: a raised panel crossed by two darker straps, with metal corner brackets.
static func _lid(c: PixelCanvas, top_rect: Rect2i, base: Color, t: Dictionary) -> void:
	var panel := PixelCanvas.rounded(top_rect.grow(-2), 2)
	c.fill(panel, base.lightened(0.04))
	c.bevel(panel, 1, 1, t.light, t.dark)
	for f in [0.25, 0.75]:
		var x := roundi(top_rect.size.x * f)
		c.fill(PixelCanvas.rounded(Rect2i(x - 2, top_rect.position.y, 4, top_rect.size.y), 0), t.dark, _BODY_HEIGHT)
		c.line(Vector2i(x - 2, top_rect.position.y), Vector2i(x - 2, top_rect.end.y - 1), t.shadow)
	var metal := ObjectArtConfig.cabinet_handle_color
	for p in [Vector2i(1, 1), Vector2i(top_rect.size.x - 3, 1)]:
		c.fill(PixelCanvas.rounded(Rect2i(p, Vector2i(2, 2)), 0), metal)
