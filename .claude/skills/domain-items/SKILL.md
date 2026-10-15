---
name: domain-items
description: Deep implementation detail for the Items domain (scenes/items/) — the things the character holds and the actions they perform (fists, the guns — pistol, SMG, assault rifle —, key, unarmed). Use when editing scenes/items/ or working on item slots, the Item contract, adding a new item or gun, GunConfig (damage, fire rate, penetration, spread, recoil), how a long gun is held and raised against a wall, magazines, an item dropped on death (DroppedItem), outfits (OutfitConfig garments and armour plates, Outfit: armour layers, plate wear, weight, look), loadouts, or a gun's link into the projectile system. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Items domain

Owns the things the character holds and the actions they perform. Fire-rate and alternation state
lives in the item; the reload clock and the aim are the character's.

## Slots

Number keys 1–9 select a slot (`ItemRegistry`):
- **1** unarmed — no hands, F/LMB do nothing (both hands `relaxed`, the `Item.hand_stance` default).
- **2** fists — both hands, F alternates (alternation state lives in the item); both held in `guard`.
- **3** pistol — right hand + pistol art; F jabs, LMB fires (one round per click), R reloads.
- **4** key — inert carryable; it exists so a `requires_item: 4` interaction has something to
  gate on (gates the wardrobe's "Rummage" interaction).
- **5** SMG, **6** assault rifle — automatic guns held two-handed (hold LMB to keep firing).

A gun's slot is the `slot` of its `GunConfig` row; `ItemRegistry.default_inventory()` has everything,
`inventory_for(slots)` just some, and `loadout_for(gun_slot)` / `spares_for(gun_slot)` / `random_gun_slot(rng)` are what Main uses to
arm a spawn (see `LoadoutConfig` below and `domain-character`, `set_loadout`).

## Guns (`gun.gd`, `gun_config.gd`)

Every firearm is a `GunItem` (`class_name GunItem extends Item`) whose numbers come live from its row in `GunConfig`
(`GunConfig.guns`, a static-var holder like `MagazineConfig`, so a test or tool can retune it — tests use `set_static`):

| Key | Meaning |
|---|---|
| `name`, `slot` | display name (HUD, and how the AI words it); inventory slot / number key |
| `damage` | added to the bullet's base damage (`Projectile.damage`, 10) at full speed head-on |
| `fire_interval` | seconds between rounds (at most one round per physics frame) |
| `automatic` | holding the trigger keeps firing (a controller re-presses `shoot()` every frame); false = one round per click |
| `penetration` | power multiplier for punching through what it hits (1 = a pistol round); see `domain-projectile` |
| `muzzle_speed`, `spread_deg`, `recoil` | speed a round leaves at; random cone half-angle; scale of the kick (`user.kick(hand, recoil)`) |
| `magazine`, `spare_magazines` | the `MagazineConfig.types` id it is built loaded with; how many spares a character carrying it carries |
| `raises_at_contact` | the barrel is too long to use against a wall (below) |

First-pass numbers: pistol 15 dmg / 0.10 s / semi / ×1.0 / 12 rounds; SMG 5 dmg / 0.07 s / auto / ×0.8 / 2.5° / 32 rounds;
rifle 22 dmg / 0.11 s / auto / ×2.2 / 4400 px/s / 24 rounds. They are one table, for tuning.

`GunItem` holds everything a gun does: the magazine, `rounds_loaded` / `ammo_capacity` / `can_reload` / `finish_reload`, `reload_time()`
(the loaded magazine type's, `MagazineConfig.reload_time_of`), `secondary(user) -> bool` (refuses while reloading, empty or still cycling;
else spends a round, rotates the aim by the spread, calls `ProjectileSpawner.spawn(muzzle_origin, dir, world, user, damage, muzzle_speed,
penetration)`, ejects a casing, kicks the hand and posts a `&"shot"` event on `EventBus`
(`{ position` (muzzle)`, gun, attacker, power }`, which the Audio domain voices)) and `primary` (a melee jab with the weapon hand; a long gun, the SMG or rifle, **strikes with its butt**, swung in **both hands**: `strike_direction(aim, amount)` turns the barrel about the weapon hand, outward from the body, by `strike_turn()` (`STRIKE_TURN`, 105 degrees) x `strike_swing(amount)`, so it ends nearly across the body with the butt centred on the aim and a little ahead of the muzzle (`draw_weapon` draws it so; `strike_end(aim, amount)` is the butt relative to the hand); the other hand grips `strike_support_gap()` (`SUPPORT_GAP`, negative: toward the butt) along the barrel; the blow is thrown `strike_tempo()` (2x) slower than a fist and lands `strike_short()` px short of one; the hands layer shortens the hand's extension by `strike_forward()` (the butt's forward reach at the end of the turn) and queries the hit at `strike_end` once it is ahead of the hand, so the blow lands about as far out as before; a pistol just jabs). **Fire rate** is a cooldown: `tick(delta)`
counts it down (the character ticks every item it carries, before its controller runs, so it is deterministic and independent of the
wall clock); firing does `cooldown += fire_interval`, carrying an overshoot so 0.07 s is not rounded to 5 frames, with the idle credit
capped at one frame so a gun never bursts to catch up.

A subclass supplies only its look and its hold: the gun id (`GUN`, also the `Magazine.gun` key), `painter()` / `flat_painter()` and
`art_size()` / `flat_size()`, `grip_back()` (px the butt sits behind the weapon hand), and the stance names (`grip_stance()` /
`fore_stance()`, and `raised_grip_stance()` / `raised_fore_stance()`). `muzzle_ahead()` = `art_size().y − grip_back()` (the pistol's is 11), which `Character.muzzle_origin` uses, so a long gun's muzzle is further out.

- **Pistol** (`pistol.gd`): 5×13 art, held at arm's length (`aim`) with the other fist beside it on the grip (`support`: same forward point, both hands together).
- **SMG** (`smg.gd`): 6×28 art, `GRIP_BACK` 10; shouldered (butt on the right shoulder; `smg_grip` / `smg_fore`), the other hand out on the shroud.
- **Zeroing:** `GunItem.secondary` aims the round from the muzzle at the point `GunConfig.zero_range` (300 px) ahead on the aim line, not parallel to `facing`, so a
  shouldered gun (muzzle 9 px off the line) still hits where the character points; the spread is applied around that direction.
- **Rifle** (`rifle.gd`): 7×36 art, `GRIP_BACK` 13; shouldered, butt on the right shoulder (`rifle_grip` at the grip, `rifle_fore` out along the
  handguard), both hands on the barrel's line.

## Raised against a wall (`raises_at_contact`)

A long gun (SMG, rifle) cannot be used against a wall or object: `Item.raises_at_contact()` makes the character test the barrel each frame
(see `domain-character`). While it touches, `raised_stance(hand)` (`ready_grip` / `ready_fore`: hands drawn in to the chest) is held, and
`draw_weapon` reads `user.weapon_raise()` (0..1) to foreshorten the barrel — "pointed up" seen from above — rendering the painter at
`RAISE_STEPS` lengths down to `RAISED_LENGTH` (crisp and cached, not a stretched texture), scaled about the weapon hand. `shoot()` does
nothing while it is raised. The pistol does not raise.

## Ammo, magazines and reloading

`Magazine` (`magazine.gd`, an `Item` subclass; `Magazine.create(type, loaded := -1)`) holds `rounds` of a `capacity`
for a `gun`. Types, capacities, optional per-type `reload_time` and the shared fallback `reload_time` live in `MagazineConfig` (a static-var
holder; add a row to `types` for a new magazine): standard / extended for each gun — pistol 12 / 20, SMG 32 / 50, rifle 24 / 40, rifle and SMG
reloads slower. A magazine only fits its own `gun` (`Character.best_magazine(gun)` filters on it). Magazines are **carried by the character, never
held**: they are not in any slot, so nothing can switch to them, and several can be carried (`ItemRegistry.create_magazines(type_ids)`).
A gun (`magazine: Magazine`) spends one round per shot (`secondary` does nothing when empty or reloading, with no
casing and no recoil) and reports `rounds_loaded()` / `ammo_capacity()`. `can_reload(user)` is true when a carried magazine
holds more rounds than the loaded one; `finish_reload(user)` seats the fullest compatible spare (`user.take_magazine`) and
stows the old one with its remaining rounds (`user.stow_magazine`), dropping it only if empty. `ItemRegistry.create(slot, rounds)`
builds a gun loaded with its `GunConfig.magazine` type (`rounds` < 0 = full). The base `Item` keeps all of this inert
(`rounds_loaded()` = -1). The reload timer and R binding are the Character's, see `domain-character`.

## Adding an item

Write an `Item` subclass in `items/` and add a case in `ItemRegistry.create`. To add a **gun**: a row in `GunConfig.guns` (with a free
`slot`), a `GunItem` subclass (painters, sizes, `grip_back`, stances — add any new stance rows to `CharacterConfig.stances`), a case in
`ItemRegistry._new_gun`, and magazine rows in `MagazineConfig.types` for its `gun` id.

## Loadouts

`LoadoutConfig` (static holder) is what a match hands a character: `options()` is the plain-data list a UI shows — **Random**
first, then every gun in `GunConfig.guns` by slot, each with its `MagazineConfig` types (its own `magazine` first) — so a gun
added to `GunConfig` is offered automatically; `grenade_options()` and `outfit_options()` (below) are the grenade and outfit rows.
`normalize(loadout)` makes a `{ weapon, magazine, spares, stuns, frags, outfit }` dict valid (the outfit through `outfit_of`, which clears both plates
unless the vest holds plates),
`apply(character, loadout, rng)` calls `Character.set_loadout` (bare hands, fists, key and the one gun, loaded with the chosen
magazine and carrying `spares` of it; `random` draws a gun from `rng`) and `Character.set_outfit` (the whole outfit, replacing what it
wore) and returns the gun id, `random(rng)` draws a valid loadout, its outfit (`random_outfit(rng)`: each slot any of its choices, None
included, then made valid by `outfit_of`, so a plate drawn without a carrier is cleared) drawn after the gun, so a seed's gun does not depend on it. `ItemRegistry.create` / `inventory_for` take an optional loaded-`magazine` override.

## Outfits (`outfit_config.gd`, `outfit.gd`; spec `docs/outfits.md` O1 to O14)

What a character wears. `OutfitConfig` (static holder; tests retune it with `set_static`) has the slots — `GARMENT_SLOTS` `head body vest pants feet`
and `PLATE_SLOTS` `front_plate back_plate`, String keys like a loadout's; `PLATE_SIDE` (the torso side each plate covers),
`optional_slots` (head, vest; the plate slots may always be empty) — and two tables of rows by StringName id
(`&""` = nothing worn):

- `garments`: `name`, `slot`, `weight` (kg), `plates` (true = holds a front and back plate: the plate carrier only), `look` (`kind`, the painter's style name:
  `cap`, `helmet`, `short_sleeves`, `long_sleeves`, `vest`, `carrier`, `jeans`, `tactical`, `shoes`, `boots`; and `color`, absent for the t-shirt and shirt, which
  take the team colour) and, for the helmet, the tactical vest and the plate carrier, `armour`: `zones` (of `feet legs torso head`), optional `sides` (of `front flank back`; absent = all round) and the
  protection numbers.
- `plates` (soft IIIA insert, steel III, ceramic IV): the protection numbers plus `name`, `weight` and `durability`.

The protection numbers: `stop_power` (round-power units: a round whose power × speed factor is below it is stopped), `penetration` (P, what a round that
gets through loses speed against; P ≥ `BallisticsConfig.penetration_bounce_min` ricochets a glancing one: the steel plate), `material` / `color` (what a
stopped round strikes: debris, the hit event, the impact sound), `blunt` (share of a stopped round still dealt), `reduction` (share cut from one that gets
through) and `blast` (share cut from a frag's blast). Helpers: `garment(id)`, `plate(id)`, `slots()`, `may_be_empty(slot)`, `choices(slot)`, `fits(slot, id)`,
`name_of(slot, id)`.

`Outfit` (`RefCounted`) is one character's worn set; the Character owns one (`Character.set_outfit` / `outfit()`). `Outfit.new(ids)` / `set_ids(ids)` replace
everything worn (an unfitting id = nothing; a plate is kept only while the vest `holds_plates()`; a plate left in its slot keeps its condition, a new one
starts at 1). Reads: `ids()`, `worn(slot)`, `condition(slot)` (1 new .. 0 spent). `layer(zone, side)` is the armour a round meets there — `{}`, or the
strongest covering garment's numbers, or over them the plate on that side: its numbers, its stop power `lerp(panel's, max(plate's, panel's), condition)`,
`reduction` and `blast` the larger of the two — as `{ stop_power, penetration, material, color, blunt, reduction, blast, plate }`. `wear(zone, side, damage)`
wears the plate there by `damage / durability` (floored at 0; only plates wear; a hit that changes nothing is skipped). `weight()` is the kg worn.
`look()` (the art: each garment slot worn -> `{ id, kind, color? }`, each plate -> `{ id, condition, color }`), `view()` (the UI: each garment slot -> its
name, "" for none; each plate slot -> `{ type, name, condition }`) and `revision` (bumped by `set_ids` and by a `wear` that lowered a condition: the art
checks it once a frame). `LoadoutConfig.outfit_options()` is the setup window's rows (`[{ slot, label, choices: [{ id, label }] }]`, `OUTFIT_LABELS`, a
"None" choice first where a slot may be empty; a garment choice whose row `plates` is marked `plates: true`, the plate carrier's, and each plate slot's
row `plate: true`, so the window can offer the plates only with a vest that holds them, `docs/outfits.md` O11b); `outfit_of(loadout)` makes a loadout's
`outfit` valid (every slot; a missing, unknown or misplaced id — String ids accepted — takes `default_outfit`'s: a t-shirt, jeans and shoes; both plates
`&""` unless the vest holds plates). What a layer does to a hit is the Character's `take_hit` (`domain-character`),
and the stop itself the projectile's (`domain-projectile`).

## Gun art

A gun's `draw_weapon` draws its painter (`items/art/pistol_painter.gd`, `smg_painter.gd`, `rifle_painter.gd`; Items-private, the gun art folder) through the Art domain:
`PixelArt.render_turned(painter, size, color, PixelArt.snap_angle(angle), "metal")`, drawn rotated to the exact angle of the character's
`weapon_facing()` (which trails the aim a touch as it turns) with its butt `grip_back()` px behind the weapon hand. Painters draw in the
canonical frame — muzzle toward +y, butt at y = 0 — and scale their parts from `c.w` / `c.h`, so the same painter renders the shortened raised
barrel. The weapon hand's stance is steady (arm reaching out, steady while walking) and the other hand's holds the gun forward: a two-handed hold.
The character visuals draw the weapon under the torso and before the fists, so its butt tucks behind the shoulder and the fists grip it. The weapon hand is hand 0 (the character's right as drawn). Firing calls `user.kick(weapon_hand(), recoil)`, so the weapon hand
(and the gun in it) recoils, and the supporting hand with it by its stance's `recoil_share`.

## Dropping on death

When its user dies the character calls `item.drop(user, velocity)`. The base `Item` leaves nothing
(returns null); a gun spawns a `DroppedItem` (`dropped_item.gd`, `class_name DroppedItem`, a
`Node2D` in the world root) where its art was drawn, pulled back toward the hand (`held_from`) if
that spot is inside a wall. The dropped item falls from about hand height on a pseudo-height,
bounces, skids to a stop with a fading spin and glances off walls and solid furniture (circle
`cast_motion` on layer 1); it picks which side lands up once (`flip`) and draws through
`item.draw_dropped(canvas, at, angle, modulate, opts)` over
a shadow that closes in as it lands, at `DrawLayers.LYING` (−2: over the blood, under the living and a vehicle's chassis), and stops processing once at rest. Tuning is
its exports. Visual only: nothing picks it up and the Despawner never frees it. A gun's
`draw_dropped` paints its flat painter (`items/art/pistol_flat_painter.gd`, `smg_flat_painter.gd`, `rifle_flat_painter.gd`): the gun's
side profile lying on the floor — receiver with sights and muzzle, grip (and, on the long guns, magazine and stock) raked off one side
(`flip` mirrors it) — at `flat_size()`.

## Grenades (`grenade.gd`, `thrown_grenade.gd`, `grenade_config.gd`; spec `docs/grenades.md` G1 to G6, G10)

Two throwables, slots `ItemRegistry.STUN_SLOT` 7 and `FRAG_SLOT` 8, each a *count* (`uses_left()`; every other item answers -1, `is_throwable()` false).
`GrenadeConfig` (static holder, a row per kind: `fuse`, `windup`, `max_range` (550 px for both: issue #51 R14), `throw_speed`, `arc_height`, `restitution`, `friction` and the effect numbers
`Explosion` reads, a stun's including `flash_cover_reach`: furniture shields from the flash only within that many px of the body); the stun's effect on the body (`stun_speed`, `stun_sway`, `recover_tail`, `stun_drift`) is `CharacterConfig`'s. `GrenadeItem` (`StunGrenadeItem` / `FragGrenadeItem` supply look and kind) tells what it is through `throw_stats()` (`Item` default {}): `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, made by `GrenadeConfig.stats_of(kind, row)` (`flash_cover_reach` INF for a frag), which `Character.throw_stats(slot)` forwards and a live `ThrownGrenade.throw_stats()` answers from the row it was thrown with: the one read the AI throws by (interface 6/7), tested by `items/grenade_throw_stats` and `ai/grenade/grenade_range_follows_the_item`:
`secondary` starts a throw (`throw` stance for `windup` s, counted in `tick`; a death or a switch of slot during it throws nothing), `_release` spends one, hands a `ThrownGrenade` the hand's
position and `user.aim_target()`, pops a `GrenadeSpoon` (a tracked `DroppedItem`) and posts `&"throw"`. `Character` empties a slot whose count reached 0 and takes up the gun (else the fists).
`ThrownGrenade` (a world `Node2D`, group `live_grenades`) flies a lob **planned** at the throw (`plan`: flight time and gravity solved so it comes to *rest* at the aim, simulated with the
very `Motion` integrator the node then runs; first touchdown capped at `max_range`, then the skid), then **fitted to the floor** (`_fit`): that lob is flown over the world as it is
(`_rest_in`, through the node's own sweep `_sweep` / `_first_strike`, the same walls, furniture and bodies it strikes) and, when it comes to rest more than `FIT_NEAR` (24 px) from the
aim (a sofa on the skid's way kicked it back), longer lobs (touchdown `FIT_STEP` 12 px further out at a time, up to `max_range`) are tried and the one resting nearest the aim is
thrown, so a grenade aimed behind low cover is lobbed over it (test `items/grenade_lobbed_over_cover`; about one simulated flight per throw in the open, up to ~30 behind cover).
In flight it skips furniture whose `coverage` is below its height and bounces off the rest (and the living) with `restitution`; its thrower's own body is passed for the
first `THROWER_CLEAR` (40 px) of flight, in the node's sweep and in the plan alike (`_sweep(..., passed)`: it leaves the hand ~16 px from the body centre and its first px pass
within body + grenade radius of it, so a pixel decided whether a throw struck its own thrower; test `items/grenade_passes_its_thrower`); posts `&"grenade"` (`bounce` / `rest`) and on the fuse's end calls `Explosion.frag` / `Explosion.stun`. A grenade is never dropped on death.
`LoadoutConfig` carries `stuns` / `frags` (0..3, `grenade_options()`, `grenade_counts()`); `ItemRegistry.create(slot, count)` (negative = one) and `inventory_for(..., grenades)` build them.
Art: `art/stun_grenade_painter.gd`, `frag_grenade_painter.gd` (option `spoon`: the lever held down, in the hand) and `spoon_painter.gd`, through `PixelArt.render_turned`.

## Link into the Projectile System

Items reach the Projectile System in two places. A gun calls `ProjectileSpawner.spawn(...) -> Node` (the bullet node), connects that
node's `hit(body, damage)` signal to `user.report_shot` (for the HUD), and ejects a casing with `CasingSpawner.spawn(at, facing, parent)`.
A `ThrownGrenade` calls `Explosion.frag` / `Explosion.stun` (`(at, world, source, row)`) when its fuse ends. No other item crosses that boundary.

**Interfaces:** 6 (Items ↔ Character, incl. `Outfit` / `OutfitConfig`), 10 (EventBus `&"shot"`, `&"throw"`, `&"grenade"`), 11 (`DrawLayers`: a dropped item and a grenade at rest `LYING`, a grenade in flight `ABOVE`), 12 (Items → Art) — signatures in `architecture`.
