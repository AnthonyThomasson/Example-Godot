extends RefCounted

## Top-down pixel-art painter for a gun in the PIPE GUN weapon style (Items domain, private; rendered through the Art domain's
## PixelArt): a defender's crude home build, a box action with a plumbing pipe for the barrel held by clamp bands, copper wire
## where the pipe meets the action, weld beads along the box and a scrap plank for a stock. Options: `gun` (&"pistol" / &"smg" /
## &"rifle"), `look` (the `GunConfig` look's handle, weapon_art.gd), and `flat`: held, in the game's top-down frame; flat, lying
## on its side (`flip` the side up).

const WeaponArt = preload("res://scenes/items/art/weapon_art.gd")


## Paint the gun onto `c`, muzzle toward +y.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var look := WeaponArt.look_of(opts)
	if look.is_empty():
		return
	var gun: StringName = opts.get("gun", &"pistol")
	if opts.get("flat", false):
		var mx := WeaponArt.mirror(c, bool(opts.get("flip", false)))
		var p := WeaponArt.flat_profile(c, gun, true)
		WeaponArt.draw_flat(c, look, gun, p, mx, true, true, true)
		_flat_marks(c, look, p, mx)
	else:
		var parts := WeaponArt.held_parts(c, gun, true)
		WeaponArt.draw_held(c, look, parts, true)
		_held_marks(c, look, parts)
		WeaponArt.held_muzzle(c)
	c.cast_shadows()


## Clamp bands down the pipe, copper wire where it leaves the action, weld beads down the box's left edge; the plank's ragged
## sawn end and a twist of wire round its neck.
static func _held_marks(c: PixelCanvas, look: Dictionary, parts: Dictionary) -> void:
	var pipe: Rect2i = parts["barrel"]
	var body: Rect2i = parts["body"]
	var clamp_col := (look["barrel"] as Color).darkened(0.45)
	for y in range(pipe.position.y + 2, pipe.end.y - 1, 4):
		for x in range(pipe.position.x, pipe.end.x):
			c.px(x, y, clamp_col, WeaponArt.BARREL_HEIGHT)
	for x in range(pipe.position.x, pipe.end.x):
		c.px(x, pipe.position.y + 1, look["wire"], WeaponArt.BARREL_HEIGHT + 1)
	for y in range(body.position.y + 1, body.end.y - 1, 2):
		c.px(0, y, look["weld"], WeaponArt.BODY_HEIGHT)
	if parts.has("stock"):
		c.px(0, 0, Color.TRANSPARENT, 0)
		c.px(c.w - 2, 0, Color.TRANSPARENT, 0)
		WeaponArt.band(c, (parts["stock"] as Rect2i).end.y - 2, look["wire"], WeaponArt.STOCK_HEIGHT)


## Lying: clamp bands round the pipe, the copper wire where it meets the action and weld beads along the box.
static func _flat_marks(c: PixelCanvas, look: Dictionary, p: Dictionary, mx: Callable) -> void:
	var bw: int = p["bw"]
	var body_end: int = p["body_end"]
	var from := maxi(int(p["stock_end"]), 0) + 1
	var clamp_col := (look["barrel"] as Color).darkened(0.45)
	for y in range(body_end + 2, c.h - 1, 4):
		for lx in range(0, bw + 1):
			WeaponArt.over(c, mx.call(lx), y, clamp_col, WeaponArt.FLAT_HEIGHT + 2)
	for lx in range(0, bw + 1):
		WeaponArt.over(c, mx.call(lx), body_end + 1, look["wire"], WeaponArt.FLAT_HEIGHT + 2)
	for y in range(from, body_end, 2):
		c.px(mx.call(bw), y, look["weld"], WeaponArt.FLAT_HEIGHT + 2)
