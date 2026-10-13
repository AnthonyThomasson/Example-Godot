---
name: domain-character
description: Overview and root-body detail for the Character domain (scenes/character/) — the player character (built so other character types can exist): facing, movement, postures and running, the weapon raise against a wall, ammo / reloading and loadout, death, footsteps, walking into furniture and the player/NPC scene wiring. The body itself (skeleton, pose, legs, hands and punch, ragdoll fall, all drawing and pixel art) is the sub-domain `domain-character-body` (scenes/character/body/). Use when editing character.gd, player_controller.gd, character_footsteps.gd, character_config.gd or the character scenes. Complements the `architecture` skill, which holds the cross-domain interfaces.
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
  punch hit detection), `character_pose.gd` (the living motion, each hand's stance), `character_rig.gd` (the standing skeleton),
  `character_legs.gd` (feet against walls), `body_sweep.gd` (the collide-and-slide hands and legs share), `character_ragdoll.gd` (the fall) and `character_visuals.gd` + the painters (appearance).
  Load that skill for anything about how the character moves, holds a weapon, looks or falls.

Ordering: a parent's `_physics_process` runs before its children's, so the hands see the
character's fresh `facing`, and the character pulls its controller's intent at the top of its own
`_physics_process` (lag-free).

## Death

`_apply_damage(amount, direction)` (shared by `take_hit`, which passes the shot's direction, and
`take_damage`, the punch path) calls `_die(direction)` at zero health. `_die` leaves layer 1 and
moves to `CharacterConfig.ragdoll_z_index` (beneath the living, above blood pools), ends any
interaction, builds `ragdoll` from the rig's joints with the body's momentum (walk + knockback,
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
(`_move_speed()`, also used for the death momentum and the push carry cap); `pose.update` still gets the
walk `speed`, so the walk amount stays at 1 while the stride cadence rises with the speed. Being busy in
an interaction counts as not running. `shoot()` does nothing while running (`melee()` still works).
Reads: `is_running()`, `stamina_fraction()`. Test: `tests/character/run_speed_stamina_test.gd`.

The run's legs, arms and shoulders (stride blend, `run` stance, shoulder sway and lean) are drawn from `pose.run_amount()`; see `domain-character-body`. Test: `tests/character/run_pose_test.gd`.

## Ammo and reloading

The character carries spare magazines (`_magazines`, `Magazine` items) beside its inventory: they are never in
`_items`, so no number key or interaction can select them. They come from the exports `spare_magazine_types`
(`MagazineConfig.types` ids, default two standard magazines for each gun) and `start_rounds` (what the starting gun is loaded with;
negative = full), which tests and sandboxes set through `actor(..., props)`. `set_loadout(slots, hold_slot, spare_types, loaded_magazine := &"")` re-arms a character after the fact (a match gives an NPC or the scene-placed player its gun this way; `loaded_magazine` picks the type the gun starts loaded with). `reload()` (R, or the AI's reload
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

**Loadout.** `set_loadout(slots, hold_slot, spare_types, loaded_magazine := &"")` rebuilds the inventory from `ItemRegistry.inventory_for(slots, start_rounds, loaded_magazine)`, the carried
magazines and the held slot (dropping any reload, re-judging the raise). Main uses it (through `LoadoutConfig.apply`) to arm the player and every NPC with its side's loadout — a chosen gun, or one random gun by default
(`ItemRegistry.loadout_for` / `spares_for`); tests that do not call it keep `default_inventory()` — every item.

## Walking into furniture

`_apply_pushes()` shoves each pushable the body slid into with `push_impulse` per *second* of contact
(× `delta`), capped so the object is carried at no more than `speed × push_carry_factor` along the
push (it is never launched ahead of the walker; the cap uses the walker's intent along the contact normal).
The body runs in `MOTION_MODE_FLOATING` (top-down: no floor), otherwise a body it walks "down" into would be ridden as a platform and lend the character its launch velocity. The resulting slow-down (`push_slow_per_weight`,
floored by `push_slow_min`) applies at once but eases back at `push_slow_release`/s, so a lost-contact
frame doesn't snap speed. Test: `tests/character/walk_into_furniture_speed_test.gd`.

## Facing

- **Facing:** `character.gd` points `facing` from itself to `aim_point` (the mouse, set by the
  controller) each frame. The node is never rotated, so hand math stays in local space.

## Runtime shapes (built in `_ready()`)

`character.gd` builds its body `CircleShape2D`; `character_hands.gd` builds the fist query
`CircleShape2D`. The editor shows a "no shape" warning on `Player/CollisionShape2D` — expected.

## Scenes

The NPCs are the AI domain's scenes (`ai/npc.tscn`, a generic goal-driven agent driven by `ai/goal_controller.gd`;
see the `domain-ai` skill; `ai/npc_defender.tscn` and `ai/npc_invader.tscn` inherit it and only override data: faction, goal,
hostility exports, colour). The player uses `player_controller.gd`. `character/character_base.tscn` is the bare
character (body, shape, Hands, Visuals) with **no controller**, and the one place that composition is declared: `npc.tscn`
inherits it and `main.tscn`'s `Player` instances it: a composer adds any `control()` child before it enters the tree
(`_find_controller()` runs at `_ready`) — the Testing domain adds its puppet `ScriptedController` or
`player_controller.gd`.

Every character has an exported `faction` (`&"player"` by default; the NPC presets set
`&"household"` / `&"invader"`), read by AI perception to tell allies from potential hostiles. A
landed punch (or leg kick, `_on_kicked`, hand code `KICK_HAND`) is surfaced as `hit_landed` **and** posted as a `&"hit"` `EventBus` event with
`attacker = self` (like a projectile's), so a punch counts as an attack for AI hostility. The event also carries
`outcome = &"punch"` and the struck `material` (the victim's `get_surface()`, `""` when it has none), for the Audio domain.

## Interface recap (authoritative in the `architecture` skill)

- **Character ↔ Controller** (interface 7): the character reads intent from a controller child
  (any node with `control(character, delta)`) that writes `move_input` / `aim_point` / `run_input` and calls
  the action API: `melee()`, `leg_kick()`, `shoot() -> bool`, `select_slot(id)`, `try_interact()` /
  `interact_with(object, id)` / `end_interaction()`, and may read `damage_taken()` (accumulated hit
  damage, for injury sensing), `gun_slot()`, `weapon_blocked()` and `is_automatic()`. Signals: `hit_landed(body, damage, hand)`
  (hand 0/1 = melee punch, 2 = leg kick, −1 = shot), `died` (`is_dead`).
  Observers (debug HUD, camera) attach by exported node path and read only the public API/signals.
- **Character → Art** (interface 12): the body, head, hand, limb and trunk painters render through
  `PixelArt.render_turned` / `snap_angle`, draw on `PixelCanvas`, and read `ArtConfig`.
- **Character → Physics** (interface 4): `Deformable` / `Deformation` for wounds, a `BloodWound`
  child (splatter spray + timed drips on a hit, stopped on death), a `BloodFootprints` child fed by
  `character_footsteps.gd` on each footfall, and the generic `Ragdoll` the fallen body is built on.
- **Items ↔ Character** (interface 6): the character API an item may call — `facing`,
  `punch(hand)`, `punch_amount(hand)`, `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`,
  `report_shot(body, dmg)`, `kick(hand, strength)`, `weapon_facing()`, `weapon_raise()`, `best_magazine(gun)` / `take_magazine(gun)` /
  `stow_magazine(m)`; and reads the item's `hand_stance(hand)` / `raised_stance(hand)` (how each hand is held), `muzzle_ahead()`,
  `raises_at_contact()`, `is_automatic()` and `tick(delta)`, calling its `drop(user, velocity)` on death.
