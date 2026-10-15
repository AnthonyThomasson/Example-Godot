extends RefCounted

## Top-down pixel-art painter for a gun in the POLICE ISSUE weapon style (Items domain, private; rendered through the Art
## domain's PixelArt): the line both police units carry, in gunmetal with a red and blue light bar across the receiver's top
## and a white serial stencil at its back. Options: `gun` (&"pistol" / &"smg" / &"rifle"), `look` (the `GunConfig` look's
## handle, weapon_art.gd), and `flat`: held, in the game's top-down frame; flat, lying on its side (`flip` the side up).

const WeaponArt = preload("res://scenes/items/art/weapon_art.gd")


## Paint the gun onto `c`, muzzle toward +y.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var look := WeaponArt.look_of(opts)
	if look.is_empty():
		return
	var gun: StringName = opts.get("gun", &"pistol")
	if opts.get("flat", false):
		var mx := WeaponArt.mirror(c, bool(opts.get("flip", false)))
		var p := WeaponArt.flat_profile(c, gun, false)
		WeaponArt.draw_flat(c, look, gun, p, mx, false, false, false)
		_flat_marks(c, look, p, mx)
	else:
		var parts := WeaponArt.held_parts(c, gun, false)
		WeaponArt.draw_held(c, look, parts, false)
		_held_marks(c, look, parts)
		WeaponArt.held_muzzle(c)
	c.cast_shadows()


## The light bar across the receiver just behind the guard (red left, blue right, a dark divider) and the serial stencil
## dashed across its back.
static func _held_marks(c: PixelCanvas, look: Dictionary, parts: Dictionary) -> void:
	var body: Rect2i = parts["body"]
	var cx := int(c.w / 2.0)
	var y := body.end.y - 3
	c.px(maxi(cx - 1, 1), y, look["light"], WeaponArt.BODY_HEIGHT + 1)
	c.px(mini(cx + 1, c.w - 2), y, look["light2"], WeaponArt.BODY_HEIGHT + 1)
	c.px(cx, y, (look["body"] as Color).darkened(0.5), WeaponArt.BODY_HEIGHT + 1)
	for x in range(1, c.w - 1, 2):
		c.px(x, body.position.y + 2, look["trim"], WeaponArt.BODY_HEIGHT)


## Lying: the light bar on the receiver's top edge and the stencil dashed along its side.
static func _flat_marks(c: PixelCanvas, look: Dictionary, p: Dictionary, mx: Callable) -> void:
	var body_end: int = p["body_end"]
	var from := maxi(int(p["stock_end"]), 0) + 1
	c.px(mx.call(1), body_end - 3, look["light"], WeaponArt.FLAT_HEIGHT + 2)
	c.px(mx.call(1), body_end - 2, look["light2"], WeaponArt.FLAT_HEIGHT + 2)
	for y in range(from + 1, mini(body_end - 4, from + 6)):
		if y % 2 == 0:
			c.px(mx.call(2), y, look["trim"], WeaponArt.FLAT_HEIGHT + 2)
