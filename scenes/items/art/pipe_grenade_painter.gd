extends RefCounted

## Top-down pixel-art painter for a grenade in the PIPE GUN weapon style (Items domain, private; rendered through the Art
## domain's PixelArt), the fuze toward +y: a capped pipe bomb with a red fuse out of its end cap, or a soda can with a white band
## for a stun, each wrapped twice in copper wire. Options: `kind` (&"frag" / &"stun"), `look` (the `GrenadeConfig` look's handle,
## weapon_art.gd) and `spoon` (the lever still held down: in the hand; thrown, it is gone).

const WeaponArt = preload("res://scenes/items/art/weapon_art.gd")


## Paint the grenade onto `c`, the fuze toward +y.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var look := WeaponArt.look_of(opts)
	if look.is_empty():
		return
	var frag: bool = opts.get("kind", &"frag") == &"frag"
	var cap_len := maxi(2, int(c.h * (22 if frag else 24) / 100.0))
	var top := c.h - cap_len
	var mid := int(top * 0.45)
	# A pipe a pixel narrower than an egg; a can as wide as a stun.
	var t := WeaponArt.shell(c, look, cap_len, false, 1 if frag else 0)
	if not frag:
		for x in c.w:
			WeaponArt.over(c, x, mid - 1, look["band"], WeaponArt.BODY_HEIGHT)
	var wire: Color = look["wire"]
	for y in [mid + 1, mid + 3]:
		for x in c.w:
			WeaponArt.over(c, x, y, wire if x % 2 == 0 else wire.darkened(0.3), WeaponArt.BODY_HEIGHT + 1)
	WeaponArt.over(c, 1, 1, t.highlight, WeaponArt.BODY_HEIGHT)
	if frag:  # The pipe's end cap, the fuse out of it.
		WeaponArt.cap(c, look, Rect2i(0, top, c.w, cap_len))
		c.px(int(c.w / 2.0), c.h - 1, look["fuse"], WeaponArt.FUZE_HEIGHT + 1)
	else:
		WeaponArt.cap(c, look, Rect2i(1, top, c.w - 2, cap_len))
	if opts.get("spoon", false):
		WeaponArt.lever(c, look, frag)
	c.cast_shadows()
