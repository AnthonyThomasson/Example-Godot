---
name: domain-ai-combat
description: Deep implementation detail for the AI COMBAT module (scenes/ai/behavior/combat.gd) — how an NPC fights with its hands: taking a shot (fire cooldown, dry-gun click, automatic bursts, backing off a gun whose barrel is against a wall), throwing a punch, the peek-and-cover cycle (peek to a clear-shot spot, fire, duck to cover) and its committed destination, the ambush, melee, fire-at-will on the move, the reload reflex, and the no-per-weapon-code rule. Use when editing scenes/ai/behavior/combat.gd or working on how NPCs shoot, reload, take cover or step back. Complements the `domain-ai-behavior` overview and the `architecture` skill.
---

# AI · Combat module (`scenes/ai/behavior/combat.gd`)

A `RefCounted` that `Behavior` owns (built in `setup()`, config copied in by `apply_config()`). It owns the fire cooldown and the
peek-and-cover cycle (`phase` `"peek"`/`"cover"`, `cover_timer`, `fire_timer`, the committed `dest` and `dest_timer`, the burst and
back-off counters) and executes every combat action on the character. `Behavior` decides WHICH fight is on — it holds the engaged
contact (node, last-known position) and the `hold_ground` flag — and passes them in each call, so combat never picks a target. It reads
the world only through the perception (`has_line_to`, `combat_spots`, `note_engaged`) and `Locomotion` (`move_to`, `inside_house`).

API (all take the `character`): `tick(delta)` (cooldown), `begin_fight()` (reset to the peek phase), `can_fire_at(character, target)` (a
loaded gun, the known contact in range on a clear line: a shot is on), `fire_at_will(character, target)`
(shoot it when `can_fire_at`, once facing settles; aims at it; the watch stage calls it for the threat in every primitive, `domain-ai-watch`), `reload_due(character)`, `has_line_of_fire(character, target) -> bool` (in range on a clear line, whatever the gun's state; what `can_fire_at` adds a loaded gun to, and the entry reads for E14), `top_off(character) -> bool` (a tactical reload of a part-spent gun, called by the entry at the stack: starts it, true while it runs or is wanted; `docs/tactical-entry.md` E11), `ambush(character, node, pos)`,
`peek_cover(character, delta, node, pos, hold_ground)`, `melee(character, pos, hold_ground)`, `shoot(character) -> bool`,
`punch(character)`, `continue_burst(character)`, `apply_back_off(character, delta)`, `reload_if_dry(character)`; `signal dry`
(an empty gun was pulled on — `Behavior` flags the task resolved so the controller re-decides). Tunables (copied from the controller
exports): `shoot_range`, `punch_range`, `combat_ring_radius` / `combat_ring_count` (the ring of candidate spots), `cover_time`,
`fire_cooldown`, `fire_burst`, `back_off_time`, `reposition_interval`, `auto_reload`.

**Peek-and-cover** (the `engage` primitive, style `peek_cover`): in the PEEK phase move to the nearest spot with a clear shot and
fire on `fire_cooldown`, then duck; in the COVER phase hold behind a shielding spot for `cover_time` (reloading an empty gun
meanwhile) before peeking again. Positions are committed for `reposition_interval`, not re-picked every frame, so the NPC steers
smoothly. A peek shoots only once the facing has settled on the contact (`AIM_TOLERANCE`) and ducks only after a shot left the barrel (or on the click
of an empty gun, where the cover phase reloads it), not after a refused one. **Ambush** holds the covered spot and fires the moment a line opens (facing settled). **Melee** closes to `punch_range` and strikes on the
cooldown (no cover cycle): `Combat.strike` kicks (`Combat.kick`, `Character.leg_kick()`) while standing with a gun in hand, so the gun stays in hand,
and otherwise (crouched, or no gun held) equips the fists and punches (`Combat.punch`). With `hold_ground` (a territorial NPC fighting a contact outside), spots are restricted to inside
the house, the peek fallback holds instead of advancing, and melee won't chase out of the house.

**No per-weapon code.** The behaviour never knows which gun it has. It fights with `Character.gun_slot()` (the held item if it takes ammo, else the
lowest slot that does) and reacts only to generic conditions the character reports: out of rounds, mid-reload, running, **blocked**, automatic.

**Firing** (`Combat.shoot(character) -> bool`, true = a round left the barrel; the fists are `Combat.punch`). It holds fire at a run or mid-reload (cooldown kept);
a dry gun is a click (below); otherwise it equips the gun and, **if `weapon_blocked()` (the barrel is against a wall or object), sets
`_back_off_timer = back_off_time`, keeps the cooldown and returns false**, else calls `shoot()` and, only on success, notes engagement and starts
the cooldown. `Behavior.apply()` ends each tick with `Combat.apply_back_off`: while the timer runs it overrides `move_input = -facing` (away from where the gun
points) and clears `run_input`, so the NPC steps back until the barrel is clear, then shoots. Callers that advance state on a shot (peek-and-cover
switching to its cover phase) wait for the back-off to finish. A pistol never reports blocked, so a chair against it changes nothing. An
`is_automatic()` gun's trigger pull is a **burst**: `_burst_left = fire_burst − 1` more rounds, fired from `Behavior.apply()` (`Combat.continue_burst`) as the gun's own
fire rate allows, ending early on a run, reload, wall or empty gun. Controller exports: `fire_burst` (3), `back_off_time` (0.45 s).
Tests: `tests/ai/combat/blocked_gun_steps_back_test.gd` (a rifle with a chair against its barrel), `pistol_fires_against_object_test.gd`.
Not modelled: a rifleman cornered with a wall behind it can still stall (bounded by the back-off timer and re-decisions); cover logic treats walls as
bulletproof though a rifle shoots through them.

**Ammo.** An empty gun cannot fire, so the behaviour never "fights" with one: `Combat.fire_at_will` returns early when the gun
is empty or reloading, and `Combat.shoot()` on an empty gun is a dry click that does not note engagement or call `shoot()`; it spends
`fire_cooldown` and emits `dry` (the behaviour flags the task resolved), so the NPC re-decides (the snapshot now says the gun is empty) at most once per
cooldown. `auto_reload` (controller export, default on) is `Combat.reload_if_dry`, a reflex in `hold` (the server-down fallback, and after a
reload), in the cover phase of peek-and-cover and from the watch stage whenever a threat is in view outside a crossing (W3): an EMPTY gun with a spare magazine is reloaded without a decision. A reload
runs only while standing (running cancels it, so the `reload` primitive never sets `run_input`). `debug_state()` / `debug_combat()`
carry `reloading`; the combat overlay shows a RELOADING badge. Tests: `tests/ai/combat/scripted_reload_decision_test.gd`,
`dry_pistol_fallback_test.gd`, `empty_pistol_no_spares_test.gd`.
