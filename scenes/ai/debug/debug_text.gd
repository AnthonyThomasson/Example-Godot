extends RefCounted

## AI domain, debug: the one place overlay text is drawn, so every label reads clearly over the busy
## world — a dark outline behind the glyphs and a floor on the colour's opacity (a fading marker's label
## stays legible). Same argument order as `CanvasItem.draw_string`, plus the canvas to draw on.

## Least opacity a label's colour may have.
const MIN_ALPHA := 0.9
## Outline thickness as a fraction of the font size (never under `MIN_OUTLINE` px).
const OUTLINE_RATIO := 0.28
const MIN_OUTLINE := 3
const OUTLINE_COLOR := Color(0, 0, 0, 0.95)


## Draw `text` on `canvas` at `pos` with a dark outline, in `color` (brightened to at least MIN_ALPHA).
static func string(canvas: CanvasItem, font: Font, pos: Vector2, text: String, align: HorizontalAlignment,
		width: float, size: int, color: Color) -> void:
	var outline := maxi(MIN_OUTLINE, int(size * OUTLINE_RATIO))
	canvas.draw_string_outline(font, pos, text, align, width, size, outline, OUTLINE_COLOR)
	canvas.draw_string(font, pos, text, align, width, size, Color(color, maxf(color.a, MIN_ALPHA)))
