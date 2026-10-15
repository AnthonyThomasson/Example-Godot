# Outfits

What a character wears, for the player and for NPCs: a garment in each of five slots, two armour plates in a plate carrier, and what
that does to a round that strikes the body. Behaviours O1 to O15 are the spec; each has the tests named under it, following the
convention of `docs/grenades.md` and `docs/tactical-entry.md`. The tests are in `tests/character/`, `tests/projectile/`, `tests/items/` and
`tests/ui/` (`tools/run_tests.sh outfit`: every one is tagged `outfit`) and reach the game through `tests/_outfit/outfit_probe.gd`, which
also fires real gun and fragment rounds down shooting lanes, each with a witness standing behind the target to show whether a round came out.

**Verification (14 October 2026, on the finished branch).** `tools/lint.sh` and the headless load check: clean. The 14 outfit tests (the 13
tagged `outfit` and `ai/entry/entry_guard_fires_from_outside`, whose bullet height is pinned to the torso) with `--repeat=10 --jobs=auto`:
140 runs, 140 passed (load average 4.4 before, 5.5 after). The whole suite with `--summary --jobs=auto`: 298 passed, 0 failed, 24 skipped
(the Von tests), 0 `gap`. `--domain=perf` alone: 9 of 9 passed (load average 4.4 before and after); `perf/hit_overload_stress`
with `--repeat=5`: 12.28 to 12.68 ms average a frame, against 12.14 to 12.70 ms on `main` measured the same way (load average 4.1).

## Behaviours

Round power is the gun's `GunConfig` `penetration`: pistol **1.0**, SMG **0.8**, rifle **2.2**, a frag's fragment **0.4**. A round's damage
is its `dealt` damage (`damage x squareness x speed_factor`, the pistol's 25 and the rifle's 32 head-on at full speed into a torso).

### What is worn

**O1. Slots.** Five garment slots and two plate slots, String keys: `head` (cap, helmet), `body` (t-shirt, shirt), `vest` (tactical vest,
plate carrier), `pants` (jeans, tactical pants), `feet` (shoes, boots), `front_plate` and `back_plate` (soft IIIA insert, steel III plate,
ceramic IV plate). Ids are StringNames, `&""` = nothing worn. Head, vest and both plates may be left empty; once an outfit is chosen the
body, pants and feet are always worn. A plate is worn only in a garment that holds plates (the plate carrier): one put in any other vest,
or with no vest, is dropped. `Character.set_outfit(ids)` replaces the whole outfit; `outfit_view()` reads it (O13). A character never
dressed (the scene defaults, tests) wears nothing: no protection, no weight and its style's own clothes (O15); only O2 and O3 apply to it.
Tests: `items/loadout_outfit`, `character/hit_zone_by_bullet_height` (nobody dressed), `character/outfit_weight_slows` (the bare body).

### Where a round strikes

**O2. Hit zones.** A bullet's height (0..100, `docs/cover-and-stance.md` H1) over the body's posture coverage picks the zone, feet up:
**feet** up to 0.08, **legs** up to 0.45, **torso** up to 0.85, **head** above. The same fractions standing (coverage 60: feet up to 4.8, legs to
27, torso to 51, head 51 to 60) and crouched (coverage 35: feet to 2.8, legs to 15.75, torso to 29.75, head above). So the same height can
be a standing body's legs and a crouched one's torso. (`CharacterConfig.hit_zones`, `Character.hit_zone(height)`.)
Test: `character/hit_zone_by_bullet_height`.

**O3. Zone damage.** A round's damage is scaled by its zone: head **x2**, torso **x1**, legs and feet **x0.6**
(`CharacterConfig.zone_damage`). A pistol round deals 50 to a head, 25 to a torso and 15 to a leg. Melee (a punch or a kick, through
`take_damage`) is not zoned and a blast has no zone (O9).
Test: `character/hit_zone_by_bullet_height`.

**O4. Sides.** The side a round strikes is the angle between the way back along its direction (toward the shooter) and the
shoulders' facing (`pose.torso_angle`): **front** up to **60 degrees**, **back** from **120 degrees**, the **flank** between
(`CharacterConfig.side_front_deg` / `side_back_deg`, `Character.hit_side(direction)`).
Test: `projectile/plate_covers_front_back_not_flank` (rounds 0, 45, 90, 135 and 180 degrees off the front).

### Armour

**O5. The protection layer.** Where armour covers the zone and side a round strikes (`Outfit.layer(zone, side)`), the body offers the round
the armour's surface instead of its own (`Character.get_surface_at(height, direction)`): its `stop_power` (in round-power units), its
`penetration` (P), its `material` and `color`, and `inner_material` (the flesh under it). The armour row also has `blunt` (the share of a
stopped round's damage still dealt), `reduction` (the share cut from a round that gets through), `blast` (the share cut from a frag's blast)
and the garment's `weight`. A plate on its side lies over the carrier's soft panel and replaces its numbers (O8). Where nothing covers the
zone and side the body is bare flesh. The numbers are the table below (`OutfitConfig`).
Tests: the projectile tests of O6 to O9.

**O6. Stopped or through.** The projectile weighs the armour after the ricochet check: a round whose power x speed factor is below the
`stop_power` is **stopped** (outcome `blocked`, it embeds). A glancing round (squareness below `bounce_square_max` 0.5) off armour of P 80 or more
(`penetration_bounce_min`: only the steel plate, P 95) **ricochets** by the usual rule before that. A stopped or ricocheted round deals the armour's
`blunt` share of its zoned damage and does nothing else to the body: no wound, no dent (`damage_taken()` stays where it was), no blood and no exit;
its debris is the armour's material and colour, and its `&"hit"` event carries the armour's `material`, which is how the impact is heard: the
steel plate as `metal`, the ceramic plate as `ceramic`, the helmet as `composite`, the soft panels as `fabric`. A round that beats the stop
power is **through**: it loses speed against the armour's P as any penetration does, always goes on (never embeds as too slow), its event
and sound are `inner_material` (flesh) and outcome `penetrate`, and the body takes its zoned damage less the armour's `reduction`, with the
wound, the blood and the blood carried on as for a bare body.
Tests: `projectile/armour_stop_feedback` (steel, ceramic, helmet, soft vest and a bare body: no dent, blood or exit; heard as metal, ceramic,
composite, the vest's material, flesh), `projectile/helmet_stops_pistol_not_rifle`, `projectile/soft_vest_stops_pistol_smg_not_rifle`.

**O7. Garments that protect.** The **helmet** (composite, stop power 1.2) covers the head, all round: it stops a pistol and an SMG round,
not a rifle round. The **tactical vest** (a soft IIIA panel, fabric, 1.2) covers the torso all round: it stops a pistol round, an SMG round and
a fragment, from any side, and not a rifle round. The **plate carrier** has the same soft panel, plus a front plate on the front side and a back
plate on the back side (O8); its flank is the soft panel only. The cap, t-shirt, shirt, jeans, tactical pants, shoes and boots give no
protection (weight and looks only). Nothing covers the legs and feet.
Tests: `projectile/helmet_stops_pistol_not_rifle` (and a pistol round in a helmeted torso goes through), `projectile/soft_vest_stops_pistol_smg_not_rifle`
(front and back; the head and legs of a vested body stay bare), `projectile/plate_covers_front_back_not_flank`.

**O8. Plates.** A plate covers its own side of the torso, in a plate carrier. The **steel III** (stop power 2.6) and **ceramic IV** (3.0)
plates stop a rifle round until they are worn; the **soft IIIA insert** (1.2) adds nothing against a rifle round to the panel it lies on. A
plate's condition runs from **1** (new) to **0** (spent): every hit on it, stopped or through, wears it by the hit's damage (before the zone
and armour scaling) divided by its `durability` (ceramic **100**, soft insert **400**, steel **2000**), and the condition never recovers. Its
stop power falls linearly with its condition toward the soft panel's under it: `lerp(1.2, plate's, condition)`. Against rifle rounds at
32 damage head-on: the ceramic plate goes 1, 0.68, 0.36, so it stops the first two and the third gets through (stop power 1.85 below the
rifle's 2.2); the steel plate loses 0.016 a hit, so it stops 18 of them and the 19th gets through. A plate left in its slot when the outfit
is set again keeps its condition; a new one starts at 1.
Tests: `projectile/plate_wears_out` (eight rifle rounds: the ceramic stops the first and lets one through within the eight, the steel stops all; both
conditions fall in `outfit_view()`, the ceramic's further), `projectile/plate_covers_front_back_not_flank` (no plates, or soft inserts, let a rifle round
through the front; the soft panel still stops a pistol in the flank).

**O9. Grenades.** A frag's fragments are bullets (O2 to O8: the soft panel and the plates stop them, the legs and head take them bare). A
frag's blast strikes the whole body with no height (`HitInfo.height` -1) and no zone; its damage is cut by the `blast` share of the torso
armour on the side facing the burst: **0.35** for the soft panels, **0.5** for the steel and ceramic plates. A helmet does not cut it. Stun grenades
are unchanged.
Tests: `projectile/frag_blast_cut_by_vest` (a bare and a helmeted body take the blast's full damage, a vested one under 0.85 of it),
`projectile/soft_vest_stops_pistol_smg_not_rifle` (the fragment).

### Weight

**O10. Weight.** The outfit's total weight above `outfit_free_weight` **2 kg** (plain clothes, 1.7 kg, weigh nothing extra) slows every
pace by **0.0067** a kg, floored at 0.6 of the speed, and multiplies the stamina a run spends by 1 + **0.025** a kg. The invaders' plated kit
(helmet, shirt, plate carrier, two steel plates, tactical pants, boots) is 14.0 kg, 12 over: **8%** slower and **1.3x** the stamina spent
running (so it runs dry sooner). `run_speed()` reads the slowed speed.
Test: `character/outfit_weight_slows` (the kit walks at 85 to 97% of a bare body's speed and spends over 1.05x its stamina running; plain clothes are
faster than the kit and no faster than bare).

### Choosing

**O11. Choosing.** `LoadoutConfig.outfit_options()` is the plain data a UI shows: a row per slot, `{ slot, label, choices: [{ id, label }] }`,
offering that slot's garments or plates, with a "None" choice (`id` `&""`) first for head, vest and the plates. A loadout carries an `outfit`
(`{ <slot>: id }`): `normalize` fills every slot (a missing, unknown or misplaced id takes `LoadoutConfig.default_outfit`'s, and String ids are
read), `apply` dresses the character in the whole outfit, and `random` draws one (each slot any of its choices, drawn after the gun). The
setup window has an `Outfit_<slot>` pick per slot in each side's column, reported as the side's `outfit` with String ids (`""` for none) and saved
with the setup.

**O11b. Plates need a carrier, and the menu says so.** In `outfit_options()` the vest choice that holds plates (its garment row's `plates`:
the plate carrier) is marked `plates: true`, and each plate slot's row `plate: true`. `normalize` (through `outfit_of`) clears both plates
(`&""`) unless the vest holds plates, so neither a saved setup nor `random` carries a plate that does nothing (the plates are still drawn from the
rng, so every outfit takes the same number of draws). In the setup window a side's plate picks are disabled and show "None" unless its vest pick is a `plates` choice,
are enabled again when one is picked, and a disabled plate is reported as `""` by `current_config()` and `start_requested`. The window reads only
those marks (plain data), never the ids. Defaults: **defenders** wear plain clothes (t-shirt, jeans, shoes: `default_outfit`); **invaders** a helmet, a shirt, a plate
carrier with a steel III plate front and back, tactical pants and boots (`Main.invader_loadout`). Endless draws each side's outfit with its gun.
How each garment looks depends on the wearer's style (O15), never on the side's loadout.
Tests: `items/loadout_outfit` (the options and their `plates` mark, normalize and its clearing of plates without a carrier, apply, and varied
`random` outfits), `ui/setup_menu_config` (the picks, reported and restored; the plate picks off and on with the vest, reported as none while off).
The side defaults, the saving and Endless are wired in Main, which no test reaches.

To try the armour by hand, the **Gun range** sandbox (`sandboxes/player_gun_range_sandbox.gd`) has a firing line of nine lanes, each ending at a
dummy (1000 health) in one outfit: plain clothes; helmet + t-shirt; tactical vest; plate carrier with no plates; carrier + soft IIIA; + steel III;
+ ceramic IV; the invaders' kit turned away (the back plate); a ceramic carrier side on (the flank). A floor label under each shows its outfit (the
debug panel's lines), plate condition and health as they change.

### Display

**O12. Art.** Every garment is drawn, standing, crouched and fallen. The cap or the helmet (a shell over the hair and ears, the nose showing in
front); short sleeves (bare forearms) and a round neckband, or long sleeves with a cuff, a collar and buttons; the tactical vest (a padded panel
with a velcro patch, the shoulder caps bare) or the plate carrier (front and back panels past the shoulders, straps, three magazine pouches in
front, a drag handle on the back, a raised panel over each plate, the cummerbund on the flank); jeans (orange-stitched seams, a faded thigh) or
tactical pants (a cargo pocket, knee pads); shoes or taller laced boots, each drawn in the wearer's style (O15). Plate wear shows in **4**
steps of 2 marks each (cracks and scuffs torn through to the plate's colour), each step adding to the last. A slot nothing is worn in (the body,
pants or feet of a body never dressed) is drawn in the style's own bare clothes. For every body, dressed or not, the crouched and falling trunk
map the most visible of its chest, back and flank under the shoulders' art. A change of outfit, of style or of a plate's wear step repaints the
body, a settled fallen one included.
Test: `character/outfit_art` (each garment paints something plain clothes never do, standing and crouched; a worn ceramic plate repaints; a
crouched carrier shows on the back; a fallen body's carrier taken off changes its drawing, put back restores it exactly).

**O13. Display.** The player debug panel (bottom left, `=== OUTFIT ===`) and the spectator inspector (bottom right while an NPC is selected,
`<name> — OUTFIT`) list what the character wears, one line per slot: `Head: Helmet`, a plate as `Front plate: Ceramic IV plate 68%`
(its condition, `roundi(condition x 100)`), `—` for nothing worn. Both read only `outfit_view()`; the inspector refreshes every frame, so wear shows live.
Tests: `ui/debug_panel_outfit`, `ui/inspector_outfit` (nothing listed before a click on the NPC, nor after a click on empty ground).

**O14. The AI is unaware.** NPCs do not know what anyone wears: nothing worn enters their decisions, the snapshot Von reads or their aim. A
stopped round still posts its `&"hit"` (an NPC hears it and is "attacked"), but it raises no `damage_taken()`, so it is not a visible wound.
No test: there is nothing new to assert.

**O15. Styles.** Every character is drawn in a style, `Character.style`: the invaders are cyberpunk police, one unit a
match, **Zenitex** (`zenitex`: cool charcoal with light grey edges on every garment, two white stripes across each shoulder cap, segmented
shoulder plates on a shirt, a white stencil along the vest's front and back edges with a red lamp, white forearm stripes and knee-pad bars, a
faceless helmet with a light rim and a white glint on its visor, gloves, a pack) or **Trauma Team** (`trauma`: a white helmet red over the
crown with a blue lamp, a green suit, a white vest with red crosses, red gloves and forearm guards, red soles, a white medic pack); the
defenders are a crew of cybernetic criminals, each a **scavenger merc** (`merc`: mismatched drab scraps, a patched sleeve, goggles or
multi-lens optics, a headset, a webbed chest rig with flank pouches, muddy boots) or a **heavy borg** (`borg`: chrome arms, a chrome shin,
glowing optics, a chrome face plate, a spine rig and cables, torn sleeves, welded steel and rivets, steel toe caps). What a garment looks like
in a style is its `OutfitConfig` row's `looks` (the same garment kind in every style; a police unit's livery colour, or the name of the palette
a crew member draws its colour from); the rest of the look and each character's own variety (skin, hair and hair style, gloves, a pack, eyes and
face, tattoos, inlays, a headset, a spine rig, cables, chrome arms and shin, the colours a crew member found its clothes in) is the style's row
in `CharacterConfig.styles`, drawn from the character's `look_seed`. A police unit's rank shows: the lead's stripe across the helmet
(`Character.rank` 2), the sergeant's chevrons (1). `Character.set_style(style, seed, rank := 0)` sets them (or the exported `style` and
`look_seed` before `_ready`); a character never given a style is a `zenitex` (a test's puppet, a dummy, the gun range), the defender NPC scene a
`merc`. A style is looks only: the armour layers, the weight, the surfaces a round meets, the setup window's choices and the garment names are
the same in every style. A match styles its crews as it arms them (`Main._arm_characters`, from the house seed through its own salted RNG,
so the styles never shift the guns or the placement): one unit drawn for every invader, the human invader too, its first the lead and its
second the sergeant; each defender, the human defender too, drawn merc or borg with a look seed of its own. `LoadoutConfig.apply(character,
loadout, rng, style)` passes the style on (`{ look, seed, rank, weapon }`), and `weapon` is the weapon style every item the character carries
is drawn in (`Item.style`: `police` for the invaders, `scrap` or `pipe` drawn per defender; an item never given one is `police`).
A gun or grenade is drawn in it held, dropped (either side up) and, a grenade, in flight and at rest: **police issue** (gunmetal, a red and
blue light bar, a white serial; gunmetal grenades with red and blue marks), **taped scrap** (rusted steel, a wooden stock, grey tape, a rust
magazine; a taped rusty olive frag, a taped tin-can stun) or **pipe guns** (a pipe barrel with clamp bands, a plank stock, copper wire, welds;
a capped pipe bomb with a red fuse, a wired soda-can stun). A dropped gun and a thrown grenade keep it; what an item does never changes with it.
Tests: `character/style_look` (one outfit drawn differently in each style with the same armour, weight and surfaces; no style draws as a
zenitex), `general/match_styles` (one unit per match drawn from the seed, defenders mixed merc and borg with seeds of their own, every item
in its wielder's weapon style), `items/weapon_style_look` (each gun and grenade drawn differently in each weapon style, held and lying; no style
draws as police), `items/weapon_style_kept` (a dropped scrap gun and a thrown pipe frag keep their style) and `items/weapon_style_function`
(the same shots, damage, sounds, throws and bursts in every style).

## Numbers

| Armour | Covers | Stop power | P | Material | Blunt | Reduction | Blast cut | Weight (kg) | Durability |
|---|---|---|---|---|---|---|---|---|---|
| Helmet | head, all round | 1.2 | 60 | composite | 0.2 | 0.2 | 0 | 1.5 | |
| Tactical vest (soft IIIA) | torso, all round | 1.2 | 30 | fabric | 0.2 | 0.25 | 0.35 | 2.0 | |
| Plate carrier (its soft panel) | torso, all round | 1.2 | 30 | fabric | 0.2 | 0.25 | 0.35 | 2.5 | |
| Soft IIIA insert | torso, its side | 1.2 | 30 | fabric | 0.2 | 0.25 | 0.35 | 0.5 | 400 |
| Steel III plate | torso, its side | 2.6 | 95 | metal | 0.12 | 0.35 | 0.5 | 3.6 | 2000 |
| Ceramic IV plate | torso, its side | 3.0 | 70 | ceramic | 0.1 | 0.4 | 0.5 | 2.6 | 100 |

Weight and looks only: cap 0.1, t-shirt 0.2, shirt 0.4, jeans 0.7, tactical pants 0.8, shoes 0.8, boots 1.6 kg.

Which round each layer stops (at full speed): every layer stops the pistol (1.0), the SMG (0.8) and a fragment (0.4); only an unworn steel
or ceramic plate stops the rifle (2.2). A round slowed by what it went through has less power (a rifle round at half speed, 1.1, is stopped by
a soft panel).

## How the rules are enforced

- **Items** (`scenes/items/`): `OutfitConfig` (the rows above, the slots, zones and sides), `Outfit` (the worn set, `layer`, `wear`, `weight`,
  `look(style)`, `view`), `LoadoutConfig` (`outfit_options`, `outfit_of`, `random_outfit`, `default_outfit`, the outfit in `normalize` / `apply` /
  `random`, and the style `apply` passes on), `Item.style` (stamped by `ItemRegistry.inventory_for`).
- **Character**: `set_outfit`, `outfit()`, `outfit_view()`, `get_surface_at`, `hit_zone`, `hit_side`, and `take_hit`'s zone, armour, wear and
  blast steps; the weight in `_speed_in` and the run's stamina; the zone and weight numbers in `CharacterConfig`. The style: `style`,
  `look_seed`, `rank`, `set_style`, `CharacterConfig.styles`. The art (`character/body/`: `character_visuals.gd`, `character_style.gd` which
  resolves the style's look, and the painters, `vest_painter.gd` among them) draws from `outfit().look(style)`.
- **Projectile**: `_surface_for` asks `get_surface_at`, the armour step in `_resolve`, `HitInfo.height` filled; `Explosion`'s blast hits carry
  height -1. **Physics**: `HitInfo.height`. **Audio**: the `composite` impact material.
- **UI** (the setup window's picks, `outfit_lines.gd` for the debug panel and the inspector) and **Main** (the side defaults, the outfit through
  the setup window and the settings file, the crews' styles in `_arm_characters`).
- **Damage reported** in the `&"hit"` event, `hit_landed` and `report_shot` is the striker's, before the body's zone, blunt and reduction scaling.

## This game's own rules

Every number in the tables is the game's, tuned for 50 HP characters; the armour names (NIJ levels IIIA, III, IV) only say which rounds each is
meant to stop. In particular: the zone fractions and multipliers; the side angles; stop power as a single threshold on power x speed factor;
the blunt and reduction shares; the linear fall of a plate's stop power with its condition, and wear by damage over durability; the plate
carrier as the only garment that holds plates; no armour on the legs and feet; the blast cut by the torso armour alone; the free weight of
plain clothes and the linear slowing; the default outfits of each side.

## Not modelled

AI awareness of armour (aiming for the head or the flank, preferring a rifle against plates); looting armour or plates from the dead; a
helmet's hearing protection against a stun; armour on the arms, neck or groin; gloves as a garment (a style's gloves are looks only); spall
and backface wounds; plates that crack apart or are swapped mid-match; a HUD widget for the player's own armour beyond the debug panel.
