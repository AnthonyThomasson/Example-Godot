---
name: domain-ai
description: Light overview of the AI domain (scenes/ai/) — non-player brains, split into four isolated sub-domains under scenes/ai/ around a thin orchestrator. Start here to see the shape of the AI (the sense → think → act model, the sub-domain map, the two NPC presets, the cross-domain interfaces), then load the matching `domain-ai-<name>` skill for deep detail: `domain-ai-perception` (what the NPC knows: vision, hostility, memory, menus, combat geometry), `domain-ai-decision` (the Von round-trip + server), `domain-ai-behavior` (combat/patrol/interact + pathing + commitment), `domain-ai-debug` (the overlays). Use when editing scenes/ai/ or working on NPC goals/behaviour, or to find which sub-domain owns a concern. Complements the `architecture` skill (cross-domain interfaces).
---

# AI domain (`scenes/ai/`) — overview

Non-player brains. **One** generic, data-driven controller drives every NPC (house defender and
invader alike) — there is no per-NPC-type or per-goal code. An NPC's behaviour is pure DATA authored
on its scene: a plain-language `goal` string plus a handful of generic primitives (hostility rules,
pursuit, territory, flanking). A controller writes the character's intent and calls its public action
API — it never reaches into character internals.

The domain is split into **four isolated sub-domains** around a thin orchestrator, each a module
folder under `scenes/ai/` that talks to the others only through a small published interface — the same
isolation the game applies between top-level domains. This skill is the map; load the per-sub-domain
skill for detail.

## The orchestrator + four sub-domains

`ai/goal_controller.gd` is the **orchestrator** — the AI's own composition root (the `main.gd` of the
AI domain). It is the single **authoring surface** (every tunable is an export here, so a defender or
invader preset is all data on this one node), it wires + configures the sub-domains, and it runs the
**SENSE → THINK → ACT** loop plus the decide cadence, salient-event detection and EventBus hit intake.
It holds almost no behaviour itself.

| Sub-domain | Folder | Skill | Owns (role) |
|---|---|---|---|
| **Perception** | `ai/perception/` | `domain-ai-perception` | SENSE — what the NPC knows: sight sense, hostility rules, event memory, the known-contacts view, the decision context (state + act/move menus), combat geometry. |
| **Decision** | `ai/decision/` | `domain-ai-decision` | THINK — the round-trip to the local Von "System One" server (two `choice` questions, top-pick), plus the dev-only server launcher. |
| **Behaviour** | `ai/behavior/` | `domain-ai-behavior` | ACT — turning the chosen act into movement + actions, the generic primitives (pursuit/territory/flanking), and the commitment state Von lacks; owns a locomotion layer for pathing. |
| **Debug** | `ai/debug/` | `domain-ai-debug` | Draw-only overlays: the vision cone/bubble, and the action label + movement path. |

Data flow each tick: the orchestrator folds queued hits into **Perception**, has it `observe()` and
return `contacts()`; hands those to **Behaviour** to resolve + honour commitments; when free, asks
**Perception** for the decision context and sends it through **Decision**; adopts the returned pick
into **Behaviour**; then has **Behaviour** `apply()` the act (movement + actions, via locomotion).

## The two presets

Spawned by Main (`defender_count` / `invader_count`, default 1 each):
- **Defender** — `character/npc_defender.tscn` (faction `household`): `hostile_on_trespass` +
  `hostile_on_attack`, `defend_territory`, familiar with the house. Dropped into a random room.
- **Invader** — `character/npc_invader.tscn`, an inherited scene overriding only data (faction
  `invader`): `hostile_on_sight`, not territorial, unfamiliar with the house, a red body. Dropped
  just outside the house; several start spread around the perimeter so they flank a shared target.

## Key idea: act-centric, and the NPC is not omniscient

Von ranks distinct, verb-like options reliably but ranks near-identical spatial points almost at
random, so the AI asks it **WHAT TO DO** (engage a known hostile, search, hold, or use a known object)
and DERIVES the movement itself. And the NPC acts only on what it has PERCEIVED: it engages a hostile's
last-KNOWN position, loses a contact once its sighting decays, and (unless `familiar_with_house`) must
see rooms/objects before it can use them. The detail of both lives in `domain-ai-perception` and
`domain-ai-behavior`.

## Cross-domain interfaces (authoritative in the `architecture` skill)

The AI's external surface is unchanged by the sub-domain split — all of it is the orchestrator's:
- **Character ↔ Controller** (interface 7): the controller is any node with `control(character,
  delta)`; it writes `move_input` / `aim_point` and calls `melee()`, `shoot()`, `select_slot(id)`,
  `interact_with(object, id)` / `end_interaction()`; reads `damage_taken()`, `faction`,
  `current_item()`, `has_item()`. Main injects only `rooms` (and `entry_point`). For observers (the
  match HUD / command server) the controller exposes `current_act()` — its live decision id — and
  `debug_status()`, both read-only (forwarded from the behaviour sub-domain).
- **AI → Navigation** (interface 9): the behaviour's locomotion sets a `NavigationAgent2D`'s
  `target_position` and reads `get_next_path_position()`.
- **EventBus** (interface 10): the orchestrator consumes `&"hit"` (`victim`, `position`, `direction`,
  `attacker`) and hands each event to perception.
