---
name: domain-ai
description: Deep implementation detail for the AI domain (scenes/ai/) — non-player brains: the house-guard controller, its world-sensing perception helper, and the dev-only Von decision-server launcher. Use when editing scenes/ai/ or working on the NPC guard, guard perception/state, the Von choice requests (move/aim/act), or the decision server. Complements AGENTS.md, which holds the cross-domain interfaces.
---

# AI domain

Non-player brains: controllers that drive a character (with a world-sensing helper for their
decision context), plus the dev-only decision-server launcher. A controller writes the
character's intent and calls its public action API — it never reaches into character internals.

## The house guard

`character/npc.tscn` is a house guard driven by `ai/jev_controller.gd`, whose goal is to defend
the house and not engage the player unless the player is inside it. Every `decide_interval` it
composes an `ai/guard_perception.gd` sensor to build a compact text state (the goal, whether the
intruder is inside the house, room + bearing + held item — from the `rooms` rects Main injects
alongside `target`) and three fixed-shape candidate sets, then POSTs **three `choice` questions in
one request** to a local Jev-style `/v1/systemone` server (Von):

- `move` — a ring of nearby points + each room centre + the intruder + post.
- `aim` — a ring of look-directions + at-intruder.
- `act` — `shoot` / `punch` / `hold`.

It samples one answer each (uniform fallback when the server is down).

**No mode gating:** the full option set is offered every tick and Von applies the "engage only
once inside" rule from the state, so restraint and cover-use emerge rather than being hard-coded.

Each choice executes through the character's public API: `move` paths with a `NavigationAgent2D`
(interface 9; attached by the `nav_agent_path` export), `aim` sets `aim_point`, and `act` equips
via `select_slot` then fires via `shoot()` / swings via `melee()`.

`guard_perception.gd` holds no policy (it only senses and annotates) and reads only published
contracts (character API, objects' `get_surface()`, the injected room rects).

## Decision server launcher

`ai/decision_server_launcher.gd` (a node in `main.tscn`) starts `von serve` when run from the
editor — using its `von_path`, which defaults to the `application/von/server_path` project setting
(blank = don't auto-start) — logs to `user://von_server.log` + `[von]` Output lines, and kills it
on exit.

Note: `mcp__godot__stop_project` hard-kills Godot, so the launcher's `_exit_tree` doesn't run and
the Von server it spawned is orphaned on port 8000 — `pkill -f "von serve"` clears it.

## Interface recap (authoritative in AGENTS.md)

- **Character ↔ Controller** (interface 7): the controller is any node with `control(character,
  delta)`; it writes `move_input` / `aim_point` and calls `melee()`, `shoot()`, `select_slot(id)`,
  `try_interact()` / `interact_with(object, id)` / `end_interaction()`.
- **AI → Navigation** (interface 9): the controller sets a `NavigationAgent2D`'s `target_position`
  and reads `get_next_path_position()`.
