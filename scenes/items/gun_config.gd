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
##   recoil            scale of the kick the hands take per round (1 = the pistol's).
##   magazine          the `MagazineConfig.types` id it is loaded with when built.
##   spare_magazines   how many of that type a character who carries it also carries spare.
##   raises_at_contact the barrel is too long to fire at a wall: it points up and cannot shoot while it touches
##                     a wall or object (the pistol is short enough to fire point-blank).
## How far ahead (px) of the body, on the aim line, every gun is zeroed: a round leaves the muzzle (a shouldered
## gun's is several px off the line) angled to cross the aim line there, so shots land where the character points
## at a normal range instead of running parallel to it.
static var zero_range: float = 300.0
static var guns: Dictionary = {
	&"pistol": {
		"name": "Pistol", "slot": 3, "damage": 15.0, "fire_interval": 0.10, "automatic": false,
		"penetration": 1.0, "muzzle_speed": 3200.0, "spread_deg": 0.0, "recoil": 1.0,
		"magazine": &"standard", "spare_magazines": 2, "raises_at_contact": false,
	},
	&"smg": {
		"name": "SMG", "slot": 5, "damage": 5.0, "fire_interval": 0.07, "automatic": true,
		"penetration": 0.8, "muzzle_speed": 2900.0, "spread_deg": 2.5, "recoil": 0.55,
		"magazine": &"smg_standard", "spare_magazines": 2, "raises_at_contact": true,
	},
	&"rifle": {
		"name": "Assault rifle", "slot": 6, "damage": 22.0, "fire_interval": 0.11, "automatic": true,
		"penetration": 2.2, "muzzle_speed": 4400.0, "spread_deg": 0.8, "recoil": 1.2,
		"magazine": &"rifle_standard", "spare_magazines": 2, "raises_at_contact": true,
	},
}


## The row for `gun` (empty for an unknown id).
static func row(gun: StringName) -> Dictionary:
	return guns.get(gun, {})


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
