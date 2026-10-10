extends RefCounted

## Procedural pixel art for world objects (Objects domain, private; read by the object visuals).
## Turns an object's `art` id, footprint, color and facing into a cached nearest-filtered texture
## sized to its footprint. Painters draw in a canonical frame — front toward +y, width across the
## front — under a light already turned into that frame; the image is then rotated to the facing,
## so lighting stays consistent in the world whichever way a piece faces.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

## Painter per `art` id: each has `static func paint(canvas, base: Color, opts: Dictionary)`.
const PAINTERS := {
	"sofa": preload("res://scenes/objects/art/sofa_painter.gd"),
	"table": preload("res://scenes/objects/art/table_painter.gd"),
	"chair": preload("res://scenes/objects/art/chair_painter.gd"),
}

## Painted textures by their inputs; identical pieces share one texture.
static var _cache: Dictionary = {}


## The texture for an `art` piece with local footprint `size` whose front faces `facing`
## (a cardinal direction in the piece's local frame), or null for an unknown art id.
static func texture(art: String, size: Vector2, color: Color, facing: Vector2, opts: Dictionary = {}) -> Texture2D:
	if not PAINTERS.has(art):
		push_error("ObjectArt: unknown art '%s'" % art)
		return null
	var key := "%s|%v|%s|%v|%s|%s" % [art, size, color.to_html(), facing, opts, ObjectArtConfig.pixel_size]
	if _cache.has(key):
		return _cache[key]

	# Clockwise quarter turns taking the canonical front (+y) onto `facing`.
	var turns := posmod(roundi(Vector2.DOWN.angle_to(facing) / (PI * 0.5)), 4)
	var res := (size / maxf(ObjectArtConfig.pixel_size, 0.01)).round()
	var canon := Vector2i(int(res.y), int(res.x)) if turns % 2 == 1 else Vector2i(res)
	var light := ObjectArtConfig.light_from.rotated(-turns * PI * 0.5)
	var canvas := PixelCanvas.new(canon.x, canon.y, hash(key), light)
	PAINTERS[art].paint(canvas, color, opts)

	var img := canvas.img
	match turns:
		1:
			img.rotate_90(CLOCKWISE)
		2:
			img.rotate_180()
		3:
			img.rotate_90(COUNTERCLOCKWISE)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
