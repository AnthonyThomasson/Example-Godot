---
name: domain-ai
description: Light overview of the AI domain (scenes/ai/) — non-player brains, split into four isolated sub-domains under scenes/ai/ around a thin orchestrator. Start here to see the shape of the AI (sense → decision-tree walk → primitive, the sub-domain map, the two NPC presets, the cross-domain interfaces), then load the matching `domain-ai-<name>` skill for deep detail: `domain-ai-perception` (what the NPC knows: vision, hostility, memory, tracks, callouts, tactics geometry, the decision snapshot Von reads), `domain-ai-decision` (the decision tree, its planner walk, the Von round-trip + server), `domain-ai-behavior` (the primitives: move/engage/melee/interact/hold + pathing + commitment), `domain-ai-debug` (the overlays). Use when editing scenes/ai/ or working on NPC goals/behaviour, or to find which sub-domain owns a concern. Complements the `architecture` skill (cross-domain interfaces).
---

# AI domain (`scenes/ai/`) — overview

Non-player brains. **One** generic, data-driven controller drives every NPC (house defender and
invader alike) — there is no per-NPC-type or per-goal code. An NPC's behaviour is pure DATA authored
on its scene: a plain-language `goal` string plus a handful of generic primitives (hostility rules,
pursuit, territory) and decision-tree config. A controller writes the character's intent and calls
its public action API — it never reaches into character internals.

The domain is split into **four isolated sub-domains** around a thin orchestrator, each a module
folder under `scenes/ai/` that talks to the others only through a small published interface — the same
isolation the game applies between top-level domains. This skill is the map; load the per-sub-domain
skill for detail.

## The orchestrator + four sub-domains

`ai/goal_controller.gd` is the **orchestrator** — the AI's own composition root (the `main.gd` of the
AI domain). It is the single **authoring surface** (every tunable is an export here, so a defender or
invader preset is all data on this one node), it wires the sub-domains and pushes its exports into
them — building them once, then re-pushing the config each decision so a tunable retuned at runtime
(a behaviour test, the dev command server) takes effect without a rebuild — and it runs the
**SENSE → THINK → ACT** loop plus the decide cadence, salient-event detection, interrupting a decision
walk the situation has overtaken, and the EventBus intake (hits, allies' callouts) and its own callouts.

| Sub-domain | Folder | Skill | Owns (role) |
|---|---|---|---|
| **Perception** | `ai/perception/` | `domain-ai-perception` | SENSE — what the NPC knows (sight, hostility, event memory, movement tracks, gunfire heard, allies' callouts) and the combat geometry (`agent_tactics.gd`: flanks, fire/advance/retreat spots); builds the decision SNAPSHOT — state sections, facts, option groups — worded for Von. |
| **Decision** | `ai/decision/` | `domain-ai-decision` | THINK — the decision TREE (data), the planner that walks it with Von one `choice` request per level, and the Von transport + dev-only server launcher. |
| **Behaviour** | `ai/behavior/` | `domain-ai-behavior` | ACT — runs the chosen leaf's primitive (move / engage / melee / interact / hold) and the commitment state Von lacks; owns a locomotion layer for pathing. |
| **Debug** | `ai/debug/` | `domain-ai-debug` | Draw-only overlays: the vision cone/bubble, and the decision-path label + movement path. |

Data flow each tick: the orchestrator folds queued hits and callouts into **Perception**, has it
`observe()` and return `contacts()`; hands those to **Behaviour** to resolve + honour commitments;
when free (or forced), asks **Perception** for a snapshot and starts a **Decision** walk over it;
adopts the returned leaf into **Behaviour** (and radios it to allies); then has **Behaviour** `apply()`
the running primitive.

## The decision tree

```
root ─┬─ COMBAT (pick the hostile) ─┬─ ENGAGE  → a firing spot / ambush        (engage)
      │                             ├─ FLANK   → a side of the target           (move)
      │                             ├─ PUSH    → advance / rush, or MELEE       (move / melee)
      │                             ├─ RETREAT → a hidden / farther spot        (move)
      │                             └─ LOCATE  → toward an unseen shooter       (move)
      ├─ INVESTIGATE → a lead (last seen, heading, gunfire, ally's call)        (move)
      ├─ SEARCH      → a room / unexplored area / the entrance                  (move)
      └─ IDLE ─┬─ USE → an object · GO → a room · WAIT                           (interact / move / hold)
```

Entry rules skip the broad levels when the situation is clear (under fire / engaged / — when
pursuing — a hostile known → straight to COMBAT). A level with one option is taken without asking.

## The two presets

Spawned by Main (`defender_count` / `invader_count`, default 1 each):
- **Defender** — `character/npc_defender.tscn` (faction `household`): `hostile_on_trespass` +
  `hostile_on_attack`, `defend_territory` (combat options stay inside the house), familiar with the
  house. Dropped into a random room.
- **Invader** — `character/npc_invader.tscn`, an inherited scene overriding only data (faction
  `invader`): `hostile_on_sight`, not territorial, unfamiliar with the house (it learns rooms by
  sight and is offered unexplored areas by direction), a red body. Dropped just outside the house;
  several start spread around the perimeter and coordinate flanks over the callout radio.

Both pursue hostiles (`pursue_hostiles`, default on): IDLE is never offered and a known hostile sends
every decision straight to COMBAT.

## Key idea: Von picks, perceptions inform, behaviour executes

Von ranks distinct, verb-like options well but cannot do arithmetic or compare near-identical spatial
points, so every level offers a few DISTINCT options whose text carries the deciding facts as bands
("short hidden route", "in pistol range", "held by Invader2"). The NPC acts only on what it has
PERCEIVED: it fights a hostile's last-KNOWN position, loses a contact once its sighting decays (it
becomes an investigation lead), and (unless `familiar_with_house`) must see rooms/objects before it can
use them. The detail lives in `domain-ai-perception`, `domain-ai-decision` and `domain-ai-behavior`.

## Cross-domain interfaces (authoritative in the `architecture` skill)

The AI's external surface is all the orchestrator's:
- **Character ↔ Controller** (interface 7): the controller is any node with `control(character,
  delta)`; it writes `move_input` / `aim_point` and calls `melee()`, `shoot()`, `select_slot(id)`,
  `interact_with(object, id)` / `end_interaction()`; reads `damage_taken()`, `faction`,
  `current_item()`, `has_item()` — and, for a character it can SEE, `facing` and `damage_taken()`.
  Main injects only `rooms` (and `entry_point`). For observers the controller exposes
  `current_act()` (the decision path as ids), `debug_status()` (the full path as labels, every level —
  `COMBAT - Intruder - FLANK - their left side (kitchen)` — plus progress) and `debug_state() ->
  Dictionary` — the deep snapshot (every level of the last walk: the state and question Von saw, the
  options, its probabilities and pick; the facts; the contacts; the running primitive; pathing). The
  dev command server's `ai` verb dumps it; `tools/von_probe.py` replays captured levels against Von.
- **AI → Navigation** (interface 9): the behaviour's locomotion sets a `NavigationAgent2D`'s
  `target_position` and reads `get_next_path_position()`; perception's tactics query the nav map
  (closest point, path) to judge routes.
- **EventBus** (interface 10): the orchestrator consumes `&"hit"` and `&"callout"` and hands each to
  perception; it posts `&"callout"` when it adopts a combat or investigation decision.
