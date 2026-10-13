class_name GrenadeConfig

## Tuning for the grenades (Items domain). Static vars, like the other config holders, so a test or tool can
## change them (tests restore them with `set_static`). One row per kind, by kind id (`GrenadeItem.kind`); the spec
## behind every number is `docs/grenades.md` (G1 to G19). The thrown grenade carries its row to the burst
## (`Explosion.frag` / `Explosion.stun`, Projectile System), which reads the effect numbers.
##
## Row keys, both kinds:
##   name           display name (HUD, and how the AI words it).
##   slot           the inventory slot / number key it lives in (`ItemRegistry`).
##   fuse           seconds from release to the burst (there is no cooking).
##   windup         seconds of drawn-back arm between the click and the grenade leaving the hand.
##   max_range      farthest (px) a throw first touches down; aimed past it, it comes down here and rolls on a little.
##   throw_speed    px/s it flies across the floor at full range (a shorter throw is a slower, floatier lob).
##   release_height height (px, the `coverage` scale) it leaves the hand at.
##   arc_height     height (px) the lob peaks at: furniture whose `coverage` is below the arc's height at that point is
##                  flown over, anything taller is struck.
##   restitution    share of its speed a bounce keeps (the floor's and a wall's).
##   friction       px/s² the floor skids it to a stop with.
## Frag only:
##   blast_radius, kill_radius, blast_damage   full damage out to `kill_radius`, falling linearly to 0 at `blast_radius`.
##   blast_impulse  shove at the blast point (`apply_impulse` units), falling off with distance like the damage (furniture, living
##                  characters, ragdolls); `blast_max_speed` (px/s) caps the speed it gives a light body (a chair), mass x speed.
##   fragments, fragment_damage, fragment_speed, fragment_range, fragment_penetration   the real projectiles it throws.
## Stun only:
##   flash_radius, flash_full, max_blind   blinded by sight within `flash_radius` (full inside `flash_full`) for up to `max_blind` s.
##   flash_cover_reach   a wall always stops the flash; a piece of furniture taller than the character only when the character is within this many
##                  px of it (hunched right against it): light comes round and over one that is not at its face.
##   bang_radius, max_deaf, wall_factor   deafened and disoriented by range for up to `max_deaf` s (x`wall_factor` through a wall).
##   point_blank, point_blank_damage   the only damage a stun does.
static var grenades: Dictionary = {
	&"stun": {
		"name": "Stun grenade", "slot": 7, "fuse": 1.5, "windup": 0.3, "max_range": 450.0, "throw_speed": 720.0,
		"release_height": 50.0, "arc_height": 82.0, "restitution": 0.35, "friction": 700.0,
		"flash_radius": 400.0, "flash_full": 100.0, "max_blind": 5.0, "flash_cover_reach": 30.0,
		"bang_radius": 350.0, "max_deaf": 6.0, "wall_factor": 0.4,
		"point_blank": 30.0, "point_blank_damage": 5.0,
	},
	&"frag": {
		"name": "Frag grenade", "slot": 8, "fuse": 3.0, "windup": 0.3, "max_range": 450.0, "throw_speed": 720.0,
		"release_height": 50.0, "arc_height": 82.0, "restitution": 0.35, "friction": 700.0,
		"blast_radius": 250.0, "kill_radius": 120.0, "blast_damage": 60.0, "blast_impulse": 12000.0, "blast_max_speed": 700.0,
		"fragments": 40, "fragment_damage": 12.0, "fragment_speed": 3600.0, "fragment_range": 500.0,
		"fragment_penetration": 0.4,
	},
}

## A landing slower than this vertical speed (px/s) is not a bounce but the grenade rolling to a stop.
static var min_hop_speed: float = 40.0
## Shortest a lob's flight is held to (s), so a throw at the thrower's feet is a drop, not an instant arrival.
static var min_flight_time: float = 0.3


## The row for `kind` (empty for an unknown id).
static func row(kind: StringName) -> Dictionary:
	return grenades.get(kind, {})


## The kind living in inventory slot `slot`, or &"" when none does.
static func kind_in_slot(slot: int) -> StringName:
	for kind: StringName in grenades:
		if int(grenades[kind].get("slot", -1)) == slot:
			return kind
	return &""


## Every grenade's inventory slot, lowest first.
static func slots() -> Array:
	var out := []
	for kind: StringName in grenades:
		out.append(int(grenades[kind].get("slot", -1)))
	out.sort()
	return out


## How far (px) from a live grenade of `kind` it is dangerous to stand in sight of: the frag's blast radius, the stun's flash radius.
static func danger_radius(kind: StringName) -> float:
	var r := row(kind)
	return float(r.get("blast_radius", r.get("flash_radius", 0.0)))


## What a grenade of `kind` tells whoever holds it or watches it fly, from `source` (its row; a thrown grenade passes the row it was thrown
## with): `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`. `flash_cover_reach` is INF for a frag (furniture shields from its
## blast at any distance); `max_blind` (s) is the longest a stun blinds anyone, 0 for a frag. The one place this dictionary is made: `GrenadeItem.throw_stats()` and `ThrownGrenade.throw_stats()` both return it, and
## the AI reads it (through `Character.throw_stats`) instead of keeping a copy of the numbers.
static func stats_of(kind: StringName, source: Dictionary) -> Dictionary:
	return {
		"kind": kind,
		"max_range": float(source.get("max_range", 0.0)),
		"danger_radius": float(source.get("blast_radius", source.get("flash_radius", 0.0))),
		"fuse": float(source.get("fuse", 0.0)),
		"flash_cover_reach": float(source.get("flash_cover_reach", INF)),
		"max_blind": float(source.get("max_blind", 0.0)),
	}
