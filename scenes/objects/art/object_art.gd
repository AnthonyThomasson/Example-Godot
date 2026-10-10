extends RefCounted

## Procedural pixel art for world objects, walls and floors (Objects domain, private; read by the
## object, wall and floor visuals). Turns an `art` painter id, a size, a color, a facing and a
## material into a cached nearest-filtered texture. Painters draw in a canonical frame — front
## toward +y, width across the front — under a light already turned into that frame; the image is
## then rotated to the facing, so lighting stays consistent in the world whichever way a piece
## faces. Wall and floor tiles are the same call at tile size, facing DOWN.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

## Painter per `art` id: each has `static func paint(canvas, base: Color, material: String,
## opts: Dictionary)`.
const PAINTERS := {
	"sofa": preload("res://scenes/objects/art/sofa_painter.gd"),
	"table": preload("res://scenes/objects/art/table_painter.gd"),
	"chair": preload("res://scenes/objects/art/chair_painter.gd"),
	"cabinet": preload("res://scenes/objects/art/cabinet_painter.gd"),
	"shelf": preload("res://scenes/objects/art/shelf_painter.gd"),
	"counter": preload("res://scenes/objects/art/counter_painter.gd"),
	"appliance": preload("res://scenes/objects/art/appliance_painter.gd"),
	"bed": preload("res://scenes/objects/art/bed_painter.gd"),
	"office_chair": preload("res://scenes/objects/art/office_chair_painter.gd"),
	"toilet": preload("res://scenes/objects/art/toilet_painter.gd"),
	"bath": preload("res://scenes/objects/art/bath_painter.gd"),
	"rug": preload("res://scenes/objects/art/rug_painter.gd"),
	"plant": preload("res://scenes/objects/art/plant_painter.gd"),
	"lamp": preload("res://scenes/objects/art/lamp_painter.gd"),
	"coat_rack": preload("res://scenes/objects/art/coat_rack_painter.gd"),
	"car": preload("res://scenes/objects/art/car_painter.gd"),
	"fixture": preload("res://scenes/objects/art/fixture_painter.gd"),
	"floor": preload("res://scenes/objects/art/floor_painter.gd"),
	"wall": preload("res://scenes/objects/art/wall_painter.gd"),
}

## Painted textures by their inputs; identical pieces share one texture.
static var _cache: Dictionary = {}


## One repeating tile of a tiling painter (one with `static func tile_size(opts) -> Vector2`, e.g.
## `floor`), or null for an unknown art id.
static func tile(art: String, color: Color, material: String = "", opts: Dictionary = {}) -> Texture2D:
	var painter = PAINTERS.get(art)
	if painter == null:
		push_error("ObjectArt: unknown art '%s'" % art)
		return null
	return texture(art, painter.tile_size(opts), color, Vector2.DOWN, material, opts)


## The texture for an `art` piece with local footprint `size` whose front faces `facing`
## (a cardinal direction in the piece's local frame), or null for an unknown art id.
static func texture(art: String, size: Vector2, color: Color, facing: Vector2, material: String = "",
		opts: Dictionary = {}) -> Texture2D:
	if not PAINTERS.has(art):
		push_error("ObjectArt: unknown art '%s'" % art)
		return null
	var key := "%s|%v|%s|%v|%s|%s|%s" % [art, size, color.to_html(), facing, material, opts, ObjectArtConfig.pixel_size]
	if _cache.has(key):
		return _cache[key]

	# Clockwise quarter turns taking the canonical front (+y) onto `facing`.
	var turns := posmod(roundi(Vector2.DOWN.angle_to(facing) / (PI * 0.5)), 4)
	var res := (size / maxf(ObjectArtConfig.pixel_size, 0.01)).round()
	var canon := Vector2i(int(res.y), int(res.x)) if turns % 2 == 1 else Vector2i(res)
	var light := ObjectArtConfig.light_from.rotated(-turns * PI * 0.5)
	var canvas := PixelCanvas.new(canon.x, canon.y, hash(key), light)
	PAINTERS[art].paint(canvas, color, material, opts)

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
