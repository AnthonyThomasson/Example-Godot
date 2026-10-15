extends RefCounted

## The Objects domain's painter registry (private; read by the object, wall and floor visuals, the wear layer and the
## factory): maps an `art` id to its painter and renders it through the Art domain's PixelArt — at a cardinal facing for a
## piece, or at the painter's own tile size for a floor or wall tile — in the run-down look: every colour handed to a painter
## is graded first (decay.gd). Each texture has an EMISSIVE twin (`emissive` / `tile_emissive`): only the pixels its painter
## drew `glowing` (a screen's face, a tube, a bulb), for the visuals to draw as their light-source overlay.

const Decay = preload("res://scenes/objects/art/decay.gd")

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
	"decor": preload("res://scenes/objects/art/decor_painter.gd"),
	"floor": preload("res://scenes/objects/art/floor_painter.gd"),
	"street": preload("res://scenes/objects/art/street_painter.gd"),
	"wall": preload("res://scenes/objects/art/wall_painter.gd"),
	"wear": preload("res://scenes/objects/art/wear_painter.gd"),
	"streetlight": preload("res://scenes/objects/art/streetlight_painter.gd"),
	"tech": preload("res://scenes/objects/art/tech_painter.gd"),
	"recliner": preload("res://scenes/objects/art/recliner_painter.gd"),
	"clinic": preload("res://scenes/objects/art/clinic_painter.gd"),
	"security": preload("res://scenes/objects/art/security_painter.gd"),
	"hotplate": preload("res://scenes/objects/art/hotplate_painter.gd"),
}

## The painters that draw several kinds of piece (`kind` in the options): their neon share is the kind's
## (ObjectArtConfig.neon_share), not the painter's.
const BY_KIND := ["tech", "recliner", "clinic"]

## The painters whose colour inputs are already the colours they draw in (the wear marks are tinted from a floor's drawn
## tone, the street and the decor draw ObjectArtConfig's own): not graded again.
const AS_GIVEN := ["wear", "street", "decor"]

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
	return PixelArt.render(PAINTERS[art], size, _color(art, color), facing, material, _graded(art, opts))


## The emissive twin of `texture` for the same inputs: only what its painter drew glowing (a screen's face, a tube, a
## bulb), in its own colours, transparent elsewhere; null when nothing in it gives light (or for an unknown art id).
static func emissive(art: String, size: Vector2, color: Color, facing: Vector2, material: String = "",
		opts: Dictionary = {}) -> Texture2D:
	if not PAINTERS.has(art):
		return null
	return PixelArt.emissive(PAINTERS[art], size, _color(art, color), facing, material, _graded(art, opts))


## The emissive twin of `tile` (null when the tile has nothing that gives light).
static func tile_emissive(art: String, color: Color, material: String = "", opts: Dictionary = {}) -> Texture2D:
	var painter = PAINTERS.get(art)
	if painter == null:
		return null
	return emissive(art, painter.tile_size(opts), color, Vector2.DOWN, material, opts)


## The colour the run-down look draws `color` in: what a piece's debris and a wall's chips take, so they match its art.
static func drawn_color(color: Color) -> Color:
	return Decay.grade(color)


## 0..1, where `local` (px from a floor's origin) lies on a groove of the tiling `art` (its grout, seams, joints) within
## `half_width`: what blood flows along. 0 for a painter that models none.
static func groove(art: String, local: Vector2, opts: Dictionary, half_width: float) -> float:
	var painter = PAINTERS.get(art)
	return painter.groove(local, opts, half_width) if painter != null and painter.has_method(&"groove") else 0.0


## Whether the tiling `art` with `opts` soaks liquid up (carpet).
static func porous(art: String, opts: Dictionary) -> bool:
	var painter = PAINTERS.get(art)
	return painter != null and painter.has_method(&"porous") and painter.porous(opts)


## The neon a piece drawn by `art` with `opts` takes, picked per piece from `piece_seed` (deterministic: the same piece in
## the same house always gets the same): `"cyan"`, `"magenta"`, or `""` for none. Only the light-giving kinds in
## ObjectArtConfig.neon_share ever do, that share of them.
static func neon_for(art: String, opts: Dictionary, piece_seed: int) -> String:
	var kind := art
	if BY_KIND.has(art):
		kind = String(opts.get("kind", ""))
	elif art == "appliance" and String(opts.get("panel", "")) == "tv":
		kind = "tv"
	elif art == "table":
		if not (opts.get("props", []) as Array).any(func(p: Dictionary) -> bool: return p.get("kind", "") == "monitor"):
			return ""
		kind = "desk"
	var share: float = ObjectArtConfig.neon_share.get(kind, 0.0)
	var roll := absi(hash([kind, piece_seed]))
	if share <= 0.0 or float(roll % 1000) / 1000.0 >= share:
		return ""
	return "cyan" if int(roll / 1000.0) % 2 == 0 else "magenta"


## The colour `art`'s painter is handed for `color`: graded, unless it takes its colours as given.
static func _color(art: String, color: Color) -> Color:
	return color if AS_GIVEN.has(art) else Decay.grade(color)


## `opts` with its colour options (a checker's `alt`) graded like the base colour.
static func _graded(art: String, opts: Dictionary) -> Dictionary:
	if not opts.has("alt") or AS_GIVEN.has(art):
		return opts
	var out := opts.duplicate()
	out["alt"] = Decay.grade(opts["alt"])
	return out
