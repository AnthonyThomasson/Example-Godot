extends RefCounted

## Top-down pixel-art painter for a gun in the TAPED SCRAP weapon style (Items domain, private; rendered through the Art domain's
## PixelArt): a defender's patched-up gun in rusted steel with a mismatched wooden stock, grey duct tape round the guard, grip
## and stock and a rust-coloured magazine. Options: `gun` (&"pistol" / &"smg" / &"rifle"), `look` (the `GunConfig` look's
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
		WeaponArt.draw_flat(c, look, gun, p, mx, false, true, false)
		_flat_marks(c, look, p)
	else:
		var parts := WeaponArt.held_parts(c, gun, false)
		WeaponArt.draw_held(c, look, parts, true)
		_held_marks(c, look, parts)
		WeaponArt.held_muzzle(c)
	c.cast_shadows()


## Rust on the receiver and the guard (a pistol's slide), a strip of tape round the guard, the grip and the stock's neck.
static func _held_marks(c: PixelCanvas, look: Dictionary, parts: Dictionary) -> void:
	var body: Rect2i = parts["body"]
	var front: Rect2i = parts.get("guard", body)
	WeaponArt.specks(c, body, look["rust"], 5)
	WeaponArt.specks(c, front, look["rust"], 3)
	WeaponArt.band(c, front.position.y + int(front.size.y / 3.0), look["tape"], WeaponArt.GUARD_HEIGHT, 2)
	if parts.has("grip"):
		WeaponArt.band(c, (parts["grip"] as Rect2i).position.y + 1, look["tape"], WeaponArt.STOCK_HEIGHT)
	if parts.has("stock"):
		WeaponArt.band(c, (parts["stock"] as Rect2i).end.y - 3, look["tape"], WeaponArt.STOCK_HEIGHT)


## Lying: rust along the receiver and two rows of tape round the guard (round a pistol's slide).
static func _flat_marks(c: PixelCanvas, look: Dictionary, p: Dictionary) -> void:
	var body_end: int = p["body_end"]
	var guard_end: int = p["guard_end"]
	var from := maxi(int(p["stock_end"]), 0) + 1
	WeaponArt.specks(c, Rect2i(0, from, c.w, body_end - from), look["rust"], 6)
	var tape_y := body_end + maxi(1, int((guard_end - body_end) / 3.0)) if guard_end > body_end + 2 else from + 2
	for y in range(tape_y, tape_y + 2):
		for x in c.w:
			WeaponArt.over(c, x, y, look["tape"], WeaponArt.FLAT_HEIGHT + 2)
