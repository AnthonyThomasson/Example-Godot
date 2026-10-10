extends RefCounted

## Top-down pixel-art wall FIXTURE painter (thin wall-mounted pieces; Objects domain, private).
## Painted in the canonical frame (room side toward +y). A `mirror`: a framed glass strip with glare
## streaks. A `towels` rack: a chrome bar on end brackets with folded towels draped over it.
## Options (`art_opts`): `kind` ("mirror" | "towels").

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _BAR_HEIGHT := 4  ## Heights for cast shadows.
const _TOWEL_HEIGHT := 6


## Paint a fixture onto `c` in `base` (glass tint or bar metal).
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	if String(opts.get("kind", "mirror")) == "towels":
		_towels(c, base)
	else:
		_mirror(c, base)
	c.cast_shadows()


## A frame around glass with two glare streaks.
static func _mirror(c: PixelCanvas, glass: Color) -> void:
	var frame_col := ObjectArtConfig.fixture_frame_color
	var ft := PixelCanvas.tones(frame_col)
	var frame := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 1)
	c.fill(frame, frame_col, _BAR_HEIGHT)
	c.bevel(frame, 1, 1, ft.highlight, ft.dark)
	var pane := PixelCanvas.rounded(Rect2i(2, 2, c.w - 4, c.h - 4), 0)
	c.fill(pane, glass, _BAR_HEIGHT)
	c.glare(pane, glass.lightened(0.5), 2)
	c.outline(frame, ft.outline)


## A chrome bar on two brackets with towels folded over it.
static func _towels(c: PixelCanvas, metal: Color) -> void:
	var cy := c.h / 2
	c.fill(PixelCanvas.rounded(Rect2i(1, cy - 1, c.w - 2, 2), 0), metal, _BAR_HEIGHT)
	c.line(Vector2i(1, cy - 1), Vector2i(c.w - 2, cy - 1), metal.lightened(0.3))
	for x in [2, c.w - 3]:
		c.fill(PixelCanvas.disc(Vector2i(x, cy), 2), metal.darkened(0.2), _BAR_HEIGHT)
	var list: Array = ObjectArtConfig.prop_colors["towels"]
	var n := clampi(c.w / 18, 1, 3)
	var tw := (c.w - 10) / n - 2
	for i in n:
		var col: Color = list[c.rng.randi_range(0, list.size() - 1)]
		var r := Rect2i(5 + i * (tw + 2), 1, tw, c.h - 2)
		var towel := PixelCanvas.rounded(r, 1)
		c.fill(towel, col, _TOWEL_HEIGHT)
		c.surface(towel, "fabric", col)
		c.line(Vector2i(r.position.x, cy), Vector2i(r.end.x - 1, cy), col.lightened(0.2))
		c.line(Vector2i(r.position.x, cy + 1), Vector2i(r.end.x - 1, cy + 1), col.darkened(0.2))
		c.line(Vector2i(r.position.x + 1, r.end.y - 2), Vector2i(r.end.x - 2, r.end.y - 2), col.darkened(0.15))
		c.outline(towel, col.darkened(0.35))
