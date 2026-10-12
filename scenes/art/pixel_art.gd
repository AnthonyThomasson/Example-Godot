class_name PixelArt

## Renders painters into cached pixel-art textures (Art domain: the entry point the Objects,
## Character and Items domains paint through). A PAINTER is any script with
## `static func paint(canvas: PixelCanvas, base: Color, material: String, opts: Dictionary)` that
## draws in a canonical frame — front toward +y, width across the front — under `canvas.light`,
## the world light already turned into that frame. Two ways to orient the result:
##   • render(): `facing` is a cardinal direction and the image itself is turned to it (furniture).
##   • render_turned(): the image stays canonical but is lit as if turned by `angle`; the caller
##     draws it rotated by that angle (freely turning things: characters, held items).
## Either way the lighting stays consistent in the world. Textures are cached by their inputs
## (static, so they survive scene reloads); a piece's random detail is seeded by its inputs minus
## its orientation, so it doesn't change as the piece turns.

## Painted textures by their inputs; identical pieces share one texture.
static var _cache: Dictionary = {}

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
	var img := _paint(painter, canon, color, -turns * PI * 0.5, material, opts, base_key)
	match turns:
		1:
			img.rotate_90(CLOCKWISE)
		2:
			img.rotate_180()
		3:
			img.rotate_90(COUNTERCLOCKWISE)
	return _store(key, img)


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
		tex = _store(key, _paint(painter, _resolution(size), color, -angle, material, opts, base_key))
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


## Paint `painter` onto a fresh canvas of `res` with the world light turned by `light_turn`.
static func _paint(painter: Script, res: Vector2i, color: Color, light_turn: float, material: String,
		opts: Dictionary, seed_key: String) -> Image:
	var canvas := PixelCanvas.new(res.x, res.y, hash(seed_key), ArtConfig.light_from.rotated(light_turn))
	painter.paint(canvas, color, material, opts)
	return canvas.img


## Cache `img` as a texture under `key` and return it.
static func _store(key: String, img: Image) -> Texture2D:
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
