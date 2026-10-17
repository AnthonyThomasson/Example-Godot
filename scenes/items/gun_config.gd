class_name GunConfig

## Tuning for the guns (Items domain). Static vars, like the other config holders, so a test or tool can
## change them (tests restore them with `set_static`). One row per gun, by gun id (`GunItem.gun` /
## `Magazine.gun`); add a row, a `GunItem` subclass and a case in `ItemRegistry._new_gun` to add a gun.
##
## Row keys:
##   name              display name (HUD, and how the AI words it: "Your pistol is loaded").
##   slot              the inventory slot / number key it lives in (`ItemRegistry`).
##   damage            added to the bullet's own base damage (`Projectile.damage`) at full speed, head-on.
##   fire_interval     seconds between rounds. One round per physics frame at most.
##   automatic         true = holding the trigger keeps firing; false = one round per press.
##   penetration       power multiplier for punching through what it hits (1 = the pistol): it divides the
##                     speed a bullet loses to a surface and lowers the speed it needs to get through.
##   muzzle_speed      px/s a round leaves at; damage and impact scale with the speed it still has.
##   spread_deg        random cone half-angle each round leaves within (0 = dead straight).
##   one_hand_spread_deg  added to `spread_deg` for a round fired one-handed (its user's other hand over its eyes,
##                     `Character.one_handed()`; docs/grenades.md G13).
##   recoil            scale of the kick the hands take per round (1 = the pistol's).
##   magazine          the `MagazineConfig.types` id it is loaded with when built.
##   spare_magazines   how many of that type a character who carries it also carries spare.
##   raises_at_contact the barrel is too long to fire at a wall: it points up and cannot shoot while it touches
##                     a wall or object (the pistol is short enough to fire point-blank).
##   looks             how it is drawn, per weapon style (`Item.style`: `police` issue, taped `scrap`, `pipe` guns; a style with
##                     no row draws `default_style`'s): `painter` (held and lying, items/art/) and the colours of its parts,
##                     `body` (slide or receiver), `stock`, `guard`, `grip`, `barrel`, `magazine` (seen lying) and the marks the
##                     painter draws (`light` / `light2` a light bar, `trim` a stencil, `rust`, `tape`, `wire`, `weld`), `finish`
##                     the receiver's surface. Looks only: nothing it does depends on them.
const PoliceGunPainter = preload("res://scenes/items/art/police_gun_painter.gd")
const ScrapGunPainter = preload("res://scenes/items/art/scrap_gun_painter.gd")
const PipeGunPainter = preload("res://scenes/items/art/pipe_gun_painter.gd")

## How far ahead (px) of the body, on the aim line, every gun is zeroed: a round leaves the muzzle (a shouldered
## gun's is several px off the line) angled to cross the aim line there, so shots land where the character points
## at a normal range instead of running parallel to it.
static var zero_range: float = 300.0
## The weapon style a gun is drawn in when its `looks` has no row for its `Item.style`.
static var default_style: StringName = &"police"
static var guns: Dictionary = {
	&"pistol": {
		"name": "Pistol", "slot": 3, "damage": 15.0, "fire_interval": 0.10, "automatic": false,
		"penetration": 1.0, "muzzle_speed": 3200.0, "spread_deg": 0.0, "recoil": 1.0, "one_hand_spread_deg": 3.0,
		"magazine": &"standard", "spare_magazines": 2, "raises_at_contact": false,
		"looks": _looks(),
	},
	&"smg": {
		"name": "SMG", "slot": 5, "damage": 5.0, "fire_interval": 0.07, "automatic": true,
		"penetration": 0.8, "muzzle_speed": 2900.0, "spread_deg": 2.5, "recoil": 0.55, "one_hand_spread_deg": 6.0,
		"magazine": &"smg_standard", "spare_magazines": 2, "raises_at_contact": true,
		"looks": _looks(),
	},
	&"rifle": {
		"name": "Assault rifle", "slot": 6, "damage": 22.0, "fire_interval": 0.11, "automatic": true,
		"penetration": 2.2, "muzzle_speed": 4400.0, "spread_deg": 0.8, "recoil": 1.2, "one_hand_spread_deg": 8.0,
		"magazine": &"rifle_standard", "spare_magazines": 2, "raises_at_contact": true,
		"looks": _looks(),
	},
}


## The row for `gun` (empty for an unknown id).
static func row(gun: StringName) -> Dictionary:
	return guns.get(gun, {})


## How `gun` is drawn in weapon `style`: its `looks` row, `default_style`'s for a style it has none for (empty for an unknown gun).
static func look(gun: StringName, style: StringName) -> Dictionary:
	var looks: Dictionary = row(gun).get("looks", {})
	return looks.get(style, looks.get(default_style, {}))


## The three weapon styles' looks, the same for every gun: police issue in gunmetal with a red and blue light bar and a white
## serial; taped scrap in rusted steel with a wooden stock, grey tape and a rust-coloured magazine; pipe guns with a pipe barrel,
## a plank stock, copper wire and welds.
static func _looks() -> Dictionary:
	return {
		&"police": { "painter": PoliceGunPainter, "finish": "metal",
			"body": Color(0.36, 0.38, 0.42), "stock": Color(0.18, 0.19, 0.21), "guard": Color(0.27, 0.29, 0.32),
			"grip": Color(0.15, 0.16, 0.18), "barrel": Color(0.24, 0.25, 0.27), "magazine": Color(0.15, 0.16, 0.18),
			"light": Color(1.0, 0.16, 0.12), "light2": Color(0.22, 0.48, 1.0), "trim": Color(0.88, 0.90, 0.92) },
		&"scrap": { "painter": ScrapGunPainter, "finish": "metal",
			"body": Color(0.44, 0.38, 0.32), "stock": Color(0.47, 0.31, 0.17), "guard": Color(0.33, 0.34, 0.27),
			"grip": Color(0.22, 0.19, 0.16), "barrel": Color(0.30, 0.28, 0.26), "magazine": Color(0.522, 0.261, 0.108),
			"rust": Color(0.58, 0.29, 0.12), "tape": Color(0.68, 0.68, 0.64) },
		&"pipe": { "painter": PipeGunPainter, "finish": "metal",
			"body": Color(0.40, 0.40, 0.38), "stock": Color(0.54, 0.41, 0.24), "guard": Color(0.35, 0.33, 0.30),
			"grip": Color(0.32, 0.23, 0.14), "barrel": Color(0.52, 0.52, 0.50), "magazine": Color(0.32, 0.23, 0.14),
			"wire": Color(0.80, 0.46, 0.20), "weld": Color(0.66, 0.64, 0.58) },
	}


## The gun id living in inventory slot `slot`, or &"" when none does.
static func gun_in_slot(slot: int) -> StringName:
	for gun: StringName in guns:
		if int(guns[gun].get("slot", -1)) == slot:
			return gun
	return &""


## Every gun's inventory slot, lowest first.
static func slots() -> Array:
	var out := []
	for gun: StringName in guns:
		out.append(int(guns[gun].get("slot", -1)))
	out.sort()
	return out
