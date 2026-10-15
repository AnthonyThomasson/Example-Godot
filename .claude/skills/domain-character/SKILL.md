---
name: domain-character
description: Overview and root-body detail for the Character domain (scenes/character/) — the player character (built so other character types can exist): facing, movement, postures and running, the weapon raise against a wall, ammo / reloading and loadout, the outfit (hit zones, sides, armour in take_hit, its weight), death, footsteps, walking into furniture, riding a vehicle (the forwards to the Vehicles domain's CharacterVehicleUse and the ride pose) and the player/NPC scene wiring. The body itself (skeleton, pose, legs, hands and punch, ragdoll fall, all drawing and pixel art) is the sub-domain `domain-character-body` (scenes/character/body/). Use when editing character.gd, player_controller.gd, character_footsteps.gd, character_push.gd, character_config.gd or the character scenes. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Character domain

Owns the player character, built so other character types can exist. Reads intent from a
pluggable controller child and integrates knockback into locomotion (it is the one "pushable"
that isn't a RigidBody2D — it integrates knockback into its own walk).

## Layering (control / animate / draw)

The three verbs live in separate files, wired via the scene tree (no `class_name` on scene
scripts; cross-file calls resolve through `$` / `get_parent()`). A "draw" file is attached to
its own child `Node2D`.

- **Control** (`character.gd`, root body) owns state + physics: computes `facing`, moves, and
  forwards intent from its controller. Never draws.
- **Animate and draw** live in `scenes/character/body/` — **`domain-character-body`**: `character_hands.gd` (hand geometry, punch,
  punch hit detection), `character_kick.gd` (the leg kick and its hit detection), `character_pose.gd` (the living motion, each hand's stance), `character_rig.gd` (the standing skeleton),
  `character_legs.gd` (feet against walls), `body_sweep.gd` (the collide-and-slide hands and legs share), `character_ragdoll.gd` (the fall) and `character_visuals.gd` + the painters in `body/art/` (appearance).
  Load that skill for anything about how the character moves, holds a weapon, looks or falls.

Ordering: a parent's `_physics_process` runs before its children's, so the hands see the
character's fresh `facing`, and the character pulls its controller's intent at the top of its own
`_physics_process` (lag-free).

## Death

`_apply_damage(amount, direction)` (shared by `take_hit`, which passes the shot's direction, and
`take_damage`, the punch path) calls `_die(direction)` at zero health. `_die` leaves layer 1 and
moves to `CharacterConfig.ragdoll_z_index` (`DrawLayers.LYING`, −2: beneath the living and a vehicle's chassis and roof, above blood
pools; `vehicle/fallen_body_under_vehicle`), ends any
interaction, abandons any vehicle ride (`CharacterVehicleUse.abandon()`: the body falls where it is, the door left as it is), builds `ragdoll` from the rig's joints with the body's momentum (walk + knockback,
including the killing blow's shove), lets go of the held item (`Item.drop(self, momentum + toss)`;
a returned node removes the slot, so `current_item()` may be null on a corpse), then emits `died`.
While dead `_physics_process` only steps the ragdoll (`step(delta, space, global_position)`); the
pose and hands stop. How the ragdoll is built and drawn is in `domain-character-body`.


**Bleeding out:** `blood_origin()` is the character's position while alive and its trunk's middle
once fallen (blood drips and pools sample it). When the ragdoll first settles the character calls
`Physics.bleed_out(get_parent(), self, [get_rid()])`, so a pool spreads out from under the body.


## Footsteps (bloody footprints)

`character_footsteps.gd` (a `RefCounted`, stepped by `character.gd` after the pose) spots each foot's landing:
the foot is planted while `cos(stride_phase + (0|PI))` is >= 0, so a landing is cos rising through 0
(only above `MIN_WALK` walk amount; none while an interaction holds the character or once dead). On a landing it
solves the rig once, reports the sole (middle, toes, `body_foot` x radius long, `body_shoe_widths[0]` wide) to the
`BloodFootprints` child (Physics), which decides whether it prints, and posts a `&"footfall"` `EventBus` event
(`{ position` (the sole)`, foot` (0 left / 1 right)`, speed, running }`) which the Audio domain turns into a step on the floor
under it. Tests: `tests/physics/footprints_trail_test.gd`, `tests/audio/footstep_surface_sound_test.gd`.

A reload posts `&"reload"` on `EventBus` twice: `stage = &"start"` from `reload()` and `&"done"` once the timer ends and the
magazine is swapped (`_post_reload`; `{ position` (weapon hand)`, gun, stage, power, character }`). A reload cancelled by
running, switching items, an interaction or death never posts `done`. Test: `tests/audio/reload_sound_test.gd`.

## A long gun against a wall (the raise)

An item whose `raises_at_contact()` is true (SMG, rifle) is judged every physics frame by `_update_weapon_raise(delta)` (after `facing` is
set, before `pose.update`; skipped in an interaction). The barrel is a ray from beside the body centre (the weapon hand's lateral) along the
aim, as far as the gun reaches **held normally** — the item's *un-raised* stance forward plus `muzzle_ahead()`, never the raised one, or pulling
it up would clear the ray and drop it again. `CharacterHands.solid_distance(from, dir, max)` does the cast (it owns the physics-space query and
`HAND_MASK`) and **ignores other characters**: a gun against a person is not against a wall, and a dead body is on no layer. It blocks when something is within
the reach, and stays blocked until `CharacterConfig.weapon_contact_margin` of clearance, so it does not flicker at the edge. `_blocked` is
set at once (`weapon_blocked()`: `shoot()` returns false, a gun cannot fire), while `weapon_raise()` (0..1) eases toward it at
`CharacterConfig.weapon_raise_speed` for the art. While blocked, `_stances()` asks the item for `raised_stance(hand)` (hands drawn in to the chest), and
`GunItem.draw_weapon` shortens the barrel by `weapon_raise()`: "pointed up" seen from above. The raise joins `_redraw_key_of` in
`character_visuals.gd` (rounded to `REDRAW_RAISE_STEP`), or an idle body would not repaint. `select_slot`, `set_loadout` and **`shoot()` itself** re-judge it
at once: a controller acts before the frame's own check runs (and on a character's very first frame none has run), so trusting last frame's `_blocked`
let a long gun fired point-blank into a wall leave through it. Test: `tests/character/long_gun_wall_raise_test.gd` (incl. a shot on the first frame);
holds: `tests/character/long_gun_hold_test.gd`.

## Postures (crouch)

A character is **standing or crouching** (`_posture`, a `CharacterConfig.postures` key: `stand` / `crouch`). Spec and
numbers: `docs/cover-and-stance.md`. (`CharacterConfig.stances` is how a *hand* is held; the body is a *posture*.)
- **API** (interface 7): `set_posture(p) -> bool` (idempotent, so a controller may write it every frame; refused while dead, in an interaction or
  within `posture_change_time` of the last change), `toggle_crouch()` (C: stand<->crouch); reads `posture()`. The player's key comes from `Keybinds.CROUCH` through `player_controller.gd`; the puppet has `set_posture` / `toggle_crouch`.
- **Reads for a controller:** `posture_coverage(posture)` (the body's height on the coverage scale in `stand` / `crouch`: what furniture must stand above to shield it) and
  `run_speed()` / `walk_speed()` (px/s standing, running / walking, as it is now, slower while stunned or weighed down by the outfit): the AI's grenade geometry judges a spot by them and keeps no copy of the numbers
  (`tests/character/posture_and_run_reads_test.gd`).
- **Effects:** `_move_speed()` multiplies the posture's `speed` row (1.0 / 0.6); running (`_update_stamina`) needs `_posture == stand`, so a
  refused run costs no stamina; shooting, reloading and `melee()` work in every posture (`leg_kick()` only standing); `get_surface().coverage` is the
  posture's row (60 / 35: a bullet strikes what stands above its one height, see the Projectile skill); starting an interaction stands the
  character up and locks the posture; `_die` stands it (and resets the drawn body) before the ragdoll is built, so a body falls from the standing skeleton.
  The collision circle (and `radius`) never change.
- **Turning:** `facing` is turned toward the aim at no more than the posture's `turn` rate (`_turned_toward`; stand 0 = at once, crouch 5 rad/s),
  so a low body takes longer to come round; `aim_point` is never held back, and the hands, weapon and shots follow `facing`.

- **Look and legs:** the drawn body eases into the posture (`_posture_height`, `posture_ease`; read through `posture_height()` / `posture_folded()` / `posture_hand_ahead()`); the rig fold, the arms and the legs are in `domain-character-body`.
Tests: `tests/character/posture_speed_test.gd`, `posture_player_input_test.gd`, `posture_interaction_test.gd`, `posture_turn_speed_test.gd`, `crouch_rig_test.gd`, `crouch_arms_attached_test.gd`, `legs_rest_on_walls_test.gd`.

## Running and stamina

A controller sets `run_input` (the player: `Keybinds.RUN`, Shift; an NPC: its behaviour layer). Each frame
`_update_stamina(wants_run, delta)` decides `_running` (asked, moving above `run_min_input`, not
exhausted) and spends or regains `stamina` (a 0..1 bar): a full bar lasts `run_stamina_seconds`, it refills
at `stamina_regen_per_sec`. Running dry latches `_exhausted` — the character walks, run still held, until
the bar refills to `run_resume_fraction`. Only a standing character runs (a crouched one's run request is ignored). Running multiplies the walk speed by `run_speed_mult`
(`_move_speed()`, also used for the death momentum and the push carry cap); a heavy outfit spends the bar faster (below); `pose.update` still gets the
walk `speed`, so the walk amount stays at 1 while the stride cadence rises with the speed. Being busy in
an interaction counts as not running. `shoot()` does nothing while running (`melee()` still works).
Reads: `is_running()`, `stamina_fraction()`. Test: `tests/character/run_speed_stamina_test.gd`.

The run's legs, arms and shoulders (stride blend, `run` stance, shoulder sway and lean) are drawn from `pose.run_amount()`; see `domain-character-body`. Test: `tests/character/run_pose_test.gd`.

## Ammo and reloading

The character carries spare magazines (`_magazines`, `Magazine` items) beside its inventory: they are never in
`_items`, so no number key or interaction can select them. They come from the exports `spare_magazine_types`
(`MagazineConfig.types` ids, default two standard magazines for each gun) and `start_rounds` (what the starting gun is loaded with;
negative = full), which tests and sandboxes set through `actor(..., props)`. `set_loadout(slots, hold_slot, spare_types, loaded_magazine := &"", grenades := {})` re-arms a character after the fact (a match gives an NPC or the scene-placed player its gun this way; `loaded_magazine` picks the type the gun starts loaded with). `reload()` (R, or the AI's reload
primitive) starts a timer of the held item's `reload_time()` on it if its `can_reload(self)` says a carried
magazine would add rounds, and sets the item's `reloading` flag (a gun's support hand eases to the `reload`
stance while it is up). `_update_reload` runs right after the controller: it cancels the reload when the character
is busy, running or no longer holds that item, else counts down and calls `item.finish_reload(self)`. `shoot()` is
ignored mid-reload; switching slot or dying cancels it; magazines are lost with the body. Reads: `is_reloading()`,
`ammo(slot)`, `ammo_capacity(slot)`, `can_reload(slot)`, `spare_magazines()`, `item_name(slot)`, `is_automatic()`,
the held-item reads `current_item()` / `current_slot()` / `item_reach()` and `has_item(id)` (is a slot carried), `is_attacking()` (a punch swing),
`gun_slot()` (the gun it fights with: the held item if it takes ammo, else the lowest slot that does, else −1: how the AI finds
its weapon without knowing which). Tests: `tests/items/reload_swaps_magazine_test.gd`, `tests/character/reload_blocked_test.gd`.

**Firing.** `shoot() -> bool` runs the held item's `secondary`; it returns false when busy, running, reloading, `weapon_blocked()` or the gun
is still cycling between rounds. `_physics_process` ticks every carried item (`Item.tick(delta)`) *before* the controller runs, so a gun's fire-rate
cooldown is in step with the frame that pulls the trigger. A controller re-presses `shoot()` every frame while the trigger is held when
`is_automatic()` (`player_controller.gd` reads `Keybinds.is_fire_pressed()`; the test puppet has `hold_fire(on)`).

**Loadout.** `set_loadout(slots, hold_slot, spare_types, loaded_magazine := &"", grenades := {})` rebuilds the inventory from `ItemRegistry.inventory_for(slots, start_rounds, loaded_magazine, grenades)`, the carried
magazines and the held slot (dropping any reload, re-judging the raise). Main uses it (through `LoadoutConfig.apply`) to arm the player and every NPC with its side's loadout — a chosen gun, or one random gun by default
(`ItemRegistry.loadout_for` / `spares_for`); tests that do not call it keep `default_inventory()` — every item.

## The outfit: hit zones, sides, armour, weight (`docs/outfits.md` O1 to O10)

The character owns an `Outfit` (Items, `_outfit`; a new one wears nothing). `set_outfit(ids)` replaces the whole worn set (Main dresses every spawn
through `LoadoutConfig.apply`; tests through it or `set_outfit`); `outfit()` hands the art the `Outfit` (its `look()` and `revision`, `domain-character-body`),
`outfit_view()` the UI its `view()`. A character never dressed has no armour, no weight and its own look.
- **Where a round strikes.** `hit_zone(height)`: the bullet's `HitInfo.height` over `posture_coverage(_posture)` against `CharacterConfig.hit_zones`
  (`feet` up to 0.08, `legs` 0.45, `torso` 0.85, `head` above; the same fractions standing and crouched), `&""` for a height below 0 (a blast).
  `hit_side(direction)`: the angle between `-direction` and `pose.torso_angle` (the shoulders), `front` up to `side_front_deg` 60, `back` from
  `side_back_deg` 120, `flank` between.
- **`get_surface_at(height, direction)`** (interface 3, which the projectile asks first): `get_surface()` where `Outfit.layer(zone, side)` is empty or the
  height is below 0; over armour, that surface with the layer's `penetration`, `material`, `color`, `stop_power` and `inner_material` (the body's own
  material, flesh).
- **`take_hit`.** The shove is always applied. A hit with height below 0 (a frag's blast) is not zoned: its damage less the torso layer's `blast` share for
  that side wounds (`_wound_by`). Otherwise the damage is scaled by `CharacterConfig.zone_damage` (head 2, torso 1, legs and feet 0.6). No layer there:
  it wounds for the zoned damage (`_wound_by`). Over a layer it first wears the plate (`Outfit.wear(zone, side, hit.damage)`: the unscaled damage); then a hit that got through
  (`hit.penetrated`) wounds for `(1 − reduction)` of the zoned damage, and one that did not (stopped or glanced off, `penetrated` false: the projectile
  guarantees a round that beats `stop_power` penetrates) deals only `blunt` of it through `_apply_damage`, with debris of the armour's material and colour
  and no `Deformable` record (so `damage_taken()` does not rise), no `BloodWound`. `_wound_by(hit, damage)` is the wounding path: the dent, the blood
  debris, the bleeding and the damage. Melee (`take_damage`) is not zoned and meets no armour.
- **Weight.** `_speed_in` multiplies every pace by `_weight_speed()` = `max(1 − extra × outfit_speed_per_kg, outfit_speed_min)` (0.0067, 0.6), `extra` the kg worn above
  `outfit_free_weight` (2: plain clothes weigh nothing extra), so `_move_speed()` and `run_speed()` slow with it; `_update_stamina` spends the run's stamina
  `1 + extra × outfit_stamina_per_kg` (0.025) times as fast. The invaders' plated kit (14 kg) is about 8% slower and spends 1.3x.
Tests: `tests/character/hit_zone_by_bullet_height_test.gd`, `outfit_weight_slows_test.gd`, `outfit_art_test.gd`, and the armour ones in `tests/projectile/`
(`helmet_stops_pistol_not_rifle`, `soft_vest_stops_pistol_smg_not_rifle`, `plate_covers_front_back_not_flank`, `plate_wears_out`, `armour_stop_feedback`,
`frag_blast_cut_by_vest`). A test that counts gun damage pins `BallisticsConfig.bullet_height` (a random height picks a zone).

## Grenades and the stun (`docs/grenades.md` G1, G13)

`item_count(slot := -1)` reads a grenade slot's count; `throw_stats(slot := -1)` forwards the item's `throw_stats()` (a grenade's `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, `{}` for any other item or an empty slot), which the AI throws by. `_empty_spent_slots` (after the items tick) erases a grenade slot whose last grenade is thrown and, if it was held,
selects `gun_slot()` (else the fists). `aim_target()` is the aim point swayed by `aim_sway()`; `GunItem.secondary` turns each shot by `aim_sway()` (0 unless stunned).
`take_stun(blind, deaf, from)` takes the longer of the old and new timers (blind and deaf each) and posts `&"stun"`; `stun_level()` (0..1) is the longer remaining timer over
`CharacterConfig.recover_tail` (the four stun numbers, `stun_speed`, `stun_sway`, `recover_tail` and `stun_drift`, are the body's tuning and live in `CharacterConfig`: the
Character reads nothing of `GrenadeConfig`), and while it is above 0 `_move_speed()` scales to `stun_speed`, running is refused, the walk drifts (`_stun_drift`) and the aim sways (`aim_sway`: two
out-of-step sines, up to `stun_sway` degrees x the level). `stun_view()` feeds the UI (`StunScreen`). `blast_push(from, impulse)` is an explosion's hook: a living body is knocked
back (`apply_impulse`), a dead one's ragdoll is woken and thrown (`CharacterRagdoll.blast`). The `throw` stance (`CharacterConfig.stances`) is the wind-up's drawn-back arm.
`set_loadout(..., grenades := {})` takes a slot -> count dict. Tests: `tests/items/grenade_*`, `tests/character/stunned_slow_and_sway_test.gd`.

## Riding a vehicle (interface 19, `docs/vehicles.md`)

The character composes the Vehicles domain's `CharacterVehicleUse` (`scenes/vehicle/character_vehicle_use.gd`, preloaded and
added in `_ready` beside the interaction) and only forwards: `try_use_vehicle()` (E from `player_controller.gd` on
`Keybinds.is_use_vehicle_just_pressed()`, the puppet's `use_vehicle()`; refused while dead or in an object interaction, and
stands a crouched character up through `_stand_if_busy`), `vehicle()` and `is_in_vehicle()`. `_physics_process` calls
`_vehicle_use.control(delta)` right after the controller, so the ride overrides that frame's intent (it walks the character to the
door with `move_input` / `aim_point`, and from the driver's seat hands the keys on to the vehicle). While the ride lasts (`is_active()`)
`is_busy()` is true and `try_interact()` / `interact_with` are refused.

The Vehicles domain poses the body with `set_ride_pose(at, toward, fold, step)`: the first pose sets `_riding`, cancels a reload and
disables the collision shape (`set_deferred`); each pose sets `global_position`, `facing`, `aim_point`, the posture to `stand` and
`_posture_height` between standing and the crouch height by `fold` (so `posture_folded()` and the body art read the seated fold), keeps
`_ride_step` and drops `_rig_cache`. While `_riding`, `_ease_posture` is skipped, `current_item()` returns null (the item put away: no
firing, nothing drawn in the hands) and `_ride_frame` replaces the rest of the frame: no movement, knockback or push, stamina refilling,
legs and kick cleared, and `pose.update` with `_ride_step` as the motion (the legs step with the pose through the vehicle's frame, not
with the vehicle). `end_ride()` clears `_riding`, re-enables the shape, zeroes the step and points the aim along the facing. The collision
exception with the vehicle is added at boarding; after the ride the component hands the vehicle to `keep_clear_of(body)`, below.

**Clearing a body just left** (interfaces 8 and 19). `keep_clear_of(body)` keeps the collision exception with an object an interaction's
`move_to` put the character on, or a vehicle it rode, until the character's circle (+`CLEAR_MARGIN` 3 px, on `PhysicsLayers.SOLID`) no
longer overlaps it, checked once a physics frame after the move (`_restore_cleared`), then drops it; a freed body is forgotten. Going
straight back onto that object or into that vehicle calls `stop_clearing(body) -> bool`, so the exception stays.
Tests: `tests/vehicle/` (`domain-vehicle`), `tests/general/use_vehicle_key_test.gd`.

## Walking into furniture

`_apply_pushes()` shoves each pushable the body slid into with `push_impulse` per *second* of contact
(× `delta`) at the **contact point** (`collision.get_position()`), through `CharacterPush.shove(piece, dir, impulse, at_world, speed)`
(`character_push.gd`, shared with the leg press in `domain-character-body`): the impulse lands off-centre, so a piece pushed near one
end slides and turns about a point near the far end, one pushed in the middle of a side just slides. The shove is capped so the
*contact point* (linear velocity plus spin) is carried at no more than `speed × push_carry_factor` along the push, worked out with the
piece's effective mass at that point (mass and the physics server's inverse inertia), so a turning end is never flung ahead of the
walker (the cap uses the walker's intent along the contact normal). Another character (no `linear_velocity`) takes the shove uncapped and
ignores the point.
The body runs in `MOTION_MODE_FLOATING` (top-down: no floor), otherwise a body it walks "down" into would be ridden as a platform and lend the character its launch velocity. The resulting slow-down (`push_slow_per_weight`,
floored by `push_slow_min`) applies at once but eases back at `push_slow_release`/s, so a lost-contact
frame doesn't snap speed. Tests: `tests/character/walk_into_furniture_speed_test.gd`, `walk_into_sofa_turns_test.gd`.

## Facing

- **Facing:** `character.gd` points `facing` from itself to `aim_point` (the mouse, set by the
  controller) each frame. The node is never rotated, so hand math stays in local space.

## Runtime shapes (built in `_ready()`)

`character.gd` builds its body `CircleShape2D`; `body_strike.gd` builds each strike's query circle (a fist's or a foot's). The editor shows a "no shape" warning on `Player/CollisionShape2D` — expected.

## Scenes

The NPCs are the AI domain's scenes (`ai/npc.tscn`, a generic goal-driven agent driven by `ai/goal_controller.gd`;
see the `domain-ai` skill; `ai/npc_defender.tscn` and `ai/npc_invader.tscn` inherit it and only override data: faction, goal,
hostility exports, colour). The player uses `player_controller.gd`. `character/character_base.tscn` is the bare
character (body, shape, Hands, Visuals) with **no controller**, and the one place that composition is declared: `npc.tscn`
inherits it and `main.tscn`'s `Player` instances it: a composer adds any `control()` child before it enters the tree
(`_find_controller()` runs at `_ready`) — the Testing domain adds its puppet `ScriptedController` or
`player_controller.gd`.

Every character joins the group `characters` in its `_ready` (interface 7): it is how the AI's perception and tactics, the Projectile
System's `Explosion` and a vehicle tell a character in the world. Every character has an exported `faction` (`&"player"` by default; the NPC presets set
`&"household"` / `&"invader"`), read by AI perception to tell allies from potential hostiles. A
landed punch (or leg kick, `_on_kicked`, hand code `KICK_HAND`) is surfaced as `hit_landed` **and** posted as a `&"hit"` `EventBus` event with
`attacker = self` (like a projectile's), so a punch counts as an attack for AI hostility. The event also carries
`outcome = &"punch"` and the struck `material` (the victim's `get_surface()`, `""` when it has none), for the Audio domain.

**Interfaces:** 3 (hittable), 4 (Character → Physics), 5 (pushable), 6 (Items ↔ Character), 7 (Character ↔ Controller), 8 (Interaction), 10 (EventBus), 11 (`DrawLayers.LYING` for the fallen body), 12 (Character → Art), 19 (Character ↔ Vehicle) — signatures in `architecture`.
