extends RefCounted

## The Objects domain's painter registry (private; read by the object, wall and floor visuals):
## maps an `art` id to its painter and renders it through the Art domain's PixelArt — at a
## cardinal facing for a piece, or at the painter's own tile size for a floor or wall tile.

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
	return PixelArt.render(PAINTERS[art], size, color, facing, material, opts)
