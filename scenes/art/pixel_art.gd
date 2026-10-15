class_name PixelArt

## Renders painters into cached pixel-art textures (Art domain: the entry point the Objects,
## Character, Items and Vehicles domains paint through). A PAINTER is any script with
## `static func paint(canvas: PixelCanvas, base: Color, material: String, opts: Dictionary)` that
## draws in a canonical frame — front toward +y, width across the front — under `canvas.light`,
## the world light already turned into that frame. Two ways to orient the result:
##   • render(): `facing` is a cardinal direction and the image itself is turned to it (furniture).
##   • render_turned(): the image stays canonical but is lit as if turned by `angle`; the caller
##     draws it rotated by that angle (freely turning things: characters, held items, vehicles).
## Either way the lighting stays consistent in the world. Textures are cached by their inputs
## (static, so they survive scene reloads); a piece's random detail is seeded by its inputs minus
## its orientation, so it doesn't change as the piece turns.
## What a painter draws `glowing` (PixelCanvas: a screen's face, a tube, a bulb) is kept for a `render`ed piece as a second,
## EMISSIVE texture of only those pixels (`emissive()`), from the same paint, for callers that draw light sources unshaded.

## Painted textures by their inputs; identical pieces share one texture.
static var _cache: Dictionary = {}

## A `render`ed texture's emissive pixels by the same key, or null when its painter drew nothing glowing.
static var _emissive: Dictionary = {}

## Most `render_turned` calls remembered by their exact arguments (see `_turned_memo`) before the memo is dropped and refills.
const TURNED_MEMO_MAX := 4096

## `render_turned`'s textures by the arguments of the calls that fetched them, so a repeat call with the same values (a
## character repaints its parts every frame) is one lookup instead of building the key string below. Only a shortcut to
## `_cache`: which texture a call gets is still decided by the string key, so values that key treats as equal still share one
## texture. Bounded, so arguments that never repeat exactly cannot grow it.
static var _turned_memo: Dictionary = {}


## `painter`'s art for a footprint of `size` world px whose front faces the cardinal `facing`.
static func render(painter: Script, size: Vector2, color: Color, facing: Vector2 = Vector2.DOWN,
		material: String = "", opts: Dictionary = {}) -> Texture2D:
	# Clockwise quarter turns taking the canonical front (+y) onto `facing`.
	var turns := posmod(roundi(Vector2.DOWN.angle_to(facing) / (PI * 0.5)), 4)
	var base_key := _key(painter, size, color, material, opts)
	var key := "%s|f%d" % [base_key, turns]
	if _cache.has(key):
		return _cache[key]
	var res := _resolution(size)
	var canon := Vector2i(res.y, res.x) if turns % 2 == 1 else res
	var canvas := _paint(painter, canon, color, -turns * PI * 0.5, material, opts, base_key)
	var glow := canvas.emissive()
	_emissive[key] = null if glow == null else ImageTexture.create_from_image(_turned(glow, turns))
	return _store(key, _turned(canvas.img, turns))


## The emissive pixels of `render`'s texture for the same inputs (painting it if it is not cached yet): what the painter drew
## `glowing`, in the art's own colours, transparent elsewhere, the same size and orientation; null when it drew nothing glowing.
static func emissive(painter: Script, size: Vector2, color: Color, facing: Vector2 = Vector2.DOWN,
		material: String = "", opts: Dictionary = {}) -> Texture2D:
	render(painter, size, color, facing, material, opts)
	var turns := posmod(roundi(Vector2.DOWN.angle_to(facing) / (PI * 0.5)), 4)
	return _emissive.get("%s|f%d" % [_key(painter, size, color, material, opts), turns])


## `img` turned by `turns` clockwise quarter turns.
static func _turned(img: Image, turns: int) -> Image:
	match turns:
		1:
			img.rotate_90(CLOCKWISE)
		2:
			img.rotate_180()
		3:
			img.rotate_90(COUNTERCLOCKWISE)
	return img


## `painter`'s art for a footprint of `size` world px in its canonical frame, lit as it will look
## once drawn rotated by `angle` (radians, clockwise on screen). Callers snap `angle` to a few
## steps so the cache stays small.
static func render_turned(painter: Script, size: Vector2, color: Color, angle: float,
		material: String = "", opts: Dictionary = {}) -> Texture2D:
	var memo_key: Array = [painter, size, color, material, opts, ArtConfig.pixel_size, angle]
	var memo: Variant = _turned_memo.get(memo_key)
	if memo != null:
		return memo
	var base_key := _key(painter, size, color, material, opts)
	var key := "%s|a%.4f" % [base_key, angle]
	var tex: Texture2D
	if _cache.has(key):
		tex = _cache[key]
	else:
		tex = _store(key, _paint(painter, _resolution(size), color, -angle, material, opts, base_key).img)
	if _turned_memo.size() >= TURNED_MEMO_MAX:
		_turned_memo.clear()
	memo_key[4] = opts.duplicate(true)  # The caller may change its dictionary later; the memo keeps the values it was asked with.
	_turned_memo[memo_key] = tex
	return tex


## `angle` snapped to the nearest of ArtConfig.turn_steps lighting steps (pass it to
## render_turned, then draw rotated by the exact angle).
static func snap_angle(angle: float) -> float:
	var step := TAU / maxi(1, ArtConfig.turn_steps)
	return wrapf(roundf(angle / step) * step, 0.0, TAU)


## The art resolution (art px) of a `size` world-px footprint.
static func _resolution(size: Vector2) -> Vector2i:
	return Vector2i((size / maxf(ArtConfig.pixel_size, 0.01)).round())


## The cache key of a painter's inputs, without orientation.
static func _key(painter: Script, size: Vector2, color: Color, material: String, opts: Dictionary) -> String:
	return "%s|%v|%s|%s|%s|%s" % [painter.resource_path, size, color.to_html(), material, opts, ArtConfig.pixel_size]


## Paint `painter` onto a fresh canvas of `res` with the world light turned by `light_turn`; returns the canvas.
static func _paint(painter: Script, res: Vector2i, color: Color, light_turn: float, material: String,
		opts: Dictionary, seed_key: String) -> PixelCanvas:
	var canvas := PixelCanvas.new(res.x, res.y, hash(seed_key), ArtConfig.light_from.rotated(light_turn))
	painter.paint(canvas, color, material, opts)
	return canvas


## Cache `img` as a texture under `key` and return it.
static func _store(key: String, img: Image) -> Texture2D:
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
