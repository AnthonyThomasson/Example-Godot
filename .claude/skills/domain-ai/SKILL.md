---
name: domain-ai
description: Deep implementation detail for the AI domain (scenes/ai/) — non-player brains: the generic goal-driven controller, its world-sensing perception helper, and the dev-only Von decision-server launcher. Use when editing scenes/ai/ or working on the NPC's goal/behaviour, agent perception/state, the act-centric decision menu, the derived movement, the commitment memory, the Von choice requests, or the decision server. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# AI domain

Non-player brains: controllers that drive a character (with a world-sensing helper for their
decision context), plus the dev-only decision-server launcher. A controller writes the
character's intent and calls its public action API — it never reaches into character internals.

## The goal-driven agent

`character/npc.tscn` is a **generic goal-driven agent** driven by `ai/goal_controller.gd`. Its
behaviour is pure data: an exported `goal` string in plain language ("watch tv", "make some food",
"hunt down the player", or the default house-guard goal), **authored on the NPC itself** — the
`goal` (and `engage_only_inside`) export on `npc.tscn`'s `GoalController` node, editable per NPC in
the Inspector. Main injects only world wiring (`target`, `rooms`), never the goal. **There is no
per-goal code** — the same machinery serves any behaviour; adding one means typing a string.

**The decision is act-centric.** Von ranks distinct, verb-like options sharply but ranks many
near-identical spatial points almost at random, so the NPC asks it **WHAT TO DO**, not where to
step, and derives the movement itself. Each decision `ai/agent_perception.gd` builds a compact text
state (the goal verbatim, then where the NPC is, what it holds, whether it is mid-interaction, and
the player's position relative to the house — from the `rooms` rects Main injects alongside
`target`) and POSTs **two `choice` questions in one request** to a local Jev-style `/v1/systemone`
server (Von):

- `act` — the real decision: `shoot` / `punch` / `hold`, plus one **interact** option per *distinct*
  action available **anywhere in the house** (deduped by label, each pointing at the nearest object
  that offers it; item-gated). So "Watch TV" / "Cook" / … are always choosable even across the
  house, and — being distinct and verb-like — Von picks the goal's match sharply and confidently.
- `move` — named destinations only (each room, the player, the post), consulted **only** when the
  act is `hold` and the NPC is otherwise idle. No local step-ring and no distance annotations —
  those are what made Von wander.

It adopts Von's TOP pick (argmax `choice`) for each (steady-stance fallback when the server is down).

**Movement and aim are derived from the chosen act** (there is no aim question):
- `interact` → walk to that object, face it, and run the interaction once in reach (`interact_with`).
- `shoot` → **peek-and-cover** (`_apply_peek_cover`): aim at the player and only ever fire when the
  perception's `has_shot` raycast confirms a clear line (never through walls), paced by
  `fire_cooldown`. In the PEEK phase it moves to the nearest **fire spot** (a sampled point with a
  clear line) and fires; after a shot it drops to the COVER phase and ducks to the nearest
  **cover spot** (shielded by a high-coverage object) for `cover_time`, then peeks again. The
  chosen fire/cover position is committed for `reposition_interval` rather than re-picked every
  frame, so the NPC steers smoothly instead of vibrating.
- `punch` → close to `punch_range` and swing on the cooldown (no cover cycle for fists).
- `hold` → watch the player, and reposition to the `move` destination if one was chosen.

**The inside-gate (`engage_only_inside`).** Von is a single-shot ranker and can't reliably apply an
"only if …" condition itself (e.g. "engage only once the player is inside"); asked to defend a
house it drifts to hiding/holding instead of shooting. So the controller enforces the one spatial
condition that matters here: when `engage_only_inside` is true, a `shoot`/`punch` pick made while
the player is **outside** the house becomes `hold` (`hold(outside)` in the log), using the
inside/outside fact the controller already senses for salient events. Interactions and idle pass
through. Turn it off for a goal that should engage the player anywhere (e.g. hunt). The default goal
is therefore phrased unconditionally ("shoot the intruder on sight"), and the gate supplies the
"only inside" part. Otherwise there is no per-goal gating — the full act menu is offered every tick.

**Commitment memory (the System-Two layer Von lacks).** Von is stateless and cannot sequence, so
the controller holds the thread: once it heads for a chosen object it commits to reaching it (a
`max_commit_time` safety cap aside); once an interaction starts it stays in it for
`interaction_dwell` seconds; combat re-decides every cadence so it keeps tracking the player. It
re-decides when the task resolves, the dwell/cap elapses, or a **salient event** fires (the player
crossing the house boundary). This lets multi-step goals advance instead of oscillating every tick.

`agent_perception.gd` holds no policy (it only senses, nothing goal-specific) and reads only
published contracts (character API, objects' `get_interactions()` / `get_surface()`, the injected
room rects). It caches the house's interactable objects via a one-time scan of
`character.world_root()` on first sense, so a far-off object is still offerable. It also answers the
controller's combat-geometry queries — `has_shot` (clear line to the player) and `combat_spots`
(nearby fire/cover points, classified by raycast) — which feed the peek-and-cover logic directly,
not Von.

## Decision server launcher

`ai/decision_server_launcher.gd` (a node in `main.tscn`) starts `von serve` when run from the
editor — using its `von_path`, which defaults to the `application/von/server_path` project setting
(blank = don't auto-start) — logs to `user://von_server.log` + `[von]` Output lines, and kills it
on exit.

Note: `mcp__godot__stop_project` hard-kills Godot, so the launcher's `_exit_tree` doesn't run and
the Von server it spawned is orphaned on port 8000 — `pkill -f "von serve"` clears it.

## Interface recap (authoritative in the `architecture` skill)

- **Character ↔ Controller** (interface 7): the controller is any node with `control(character,
  delta)`; it writes `move_input` / `aim_point` and calls `melee()`, `shoot()`, `select_slot(id)`,
  `try_interact()` / `interact_with(object, id)` / `end_interaction()`.
- **AI → Navigation** (interface 9): the controller sets a `NavigationAgent2D`'s `target_position`
  and reads `get_next_path_position()`.
