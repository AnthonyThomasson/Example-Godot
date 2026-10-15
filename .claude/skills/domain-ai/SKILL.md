---
name: domain-ai
description: Light overview of the AI domain (scenes/ai/) — non-player brains, split into four isolated sub-domains under scenes/ai/ around a thin orchestrator. Start here to see the shape of the AI (sense → decision-tree walk → primitive, the sub-domain map, the two NPC presets, which cross-domain interfaces it uses), then load the matching `domain-ai-<name>` skill for deep detail: `domain-ai-perception` (what the NPC knows: vision, hostility, memory, tracks, callouts, tactics geometry, the decision snapshot Von reads), `domain-ai-decision` (the decision tree, its planner walk, the Von round-trip + server), `domain-ai-behavior` (the primitives: move/engage/melee/interact/hold/entry + pathing + commitment + tactical entry; its `combat.gd` is `domain-ai-combat`, `search_coverage.gd` is `domain-ai-coverage` and `watch.gd`, where it looks and when it shoots, is `domain-ai-watch`), `domain-ai-debug` (the overlays); the decision snapshot inside perception is `domain-ai-snapshot`. Use when editing scenes/ai/ or working on NPC goals/behaviour, or to find which sub-domain owns a concern. Complements the `architecture` skill (cross-domain interfaces).
---

# AI domain (`scenes/ai/`) — overview

Non-player brains. **One** generic, data-driven controller drives every NPC (house defender and
invader alike) — there is no per-NPC-type or per-goal code. An NPC's behaviour is pure DATA authored
on its scene: a plain-language `goal` string (`{gun}` in it stands for the NPC's own gun; `goal_text()` is the filled-in text)
plus a handful of generic primitives (hostility rules, pursuit, territory) and decision-tree config. A controller writes the character's intent and calls
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
walk the situation has overtaken, and the EventBus intake (`&"hit"`, allies' `&"callout"`s, `&"grenade"` landings and
`&"explosion"`s, queued and handed to perception on the next tick) and its own callouts.

| Sub-domain | Folder | Skill | Owns (role) |
|---|---|---|---|
| **Perception** | `ai/perception/` | `domain-ai-perception` (+ `domain-ai-snapshot` for the snapshot: `agent_snapshot.gd`, `perception/snapshot/`) | SENSE — what the NPC knows (sight, hostility, event memory, movement tracks, gunfire heard, allies' callouts) and the combat geometry (`agent_tactics.gd`: flanks, fire/advance/retreat spots); builds the decision SNAPSHOT — state sections, facts, option groups — worded for Von (`agent_snapshot.gd`). |
| **Decision** | `ai/decision/` | `domain-ai-decision` | THINK — the decision TREE (data), the planner that walks it with Von one `choice` request per level, and the Von transport + dev-only server launcher. |
| **Behaviour** | `ai/behavior/` | `domain-ai-behavior` (+ `domain-ai-combat` for `combat.gd`, `domain-ai-coverage` for `search_coverage.gd`, `domain-ai-watch` for `watch.gd`) | ACT — runs the chosen leaf's primitive (move / engage / melee / interact / hold / reload / entry / throw) and the commitment state Von lacks; owns a locomotion layer for pathing, and the tactical entry phase machine (`entry.gd`). |
| **Debug** | `ai/debug/` | `domain-ai-debug` | Draw-only overlays: the vision cone/bubble, the decision-path label + movement path, the tactical zones it weighed, search coverage, and behaviour overlays (contacts, hearing/radio, combat, territory, move/use targets, Von/brain, routes, stuck, the entry plan, the entry team and guard). |

**The human's stack (`ai/team/player_stack.gd`).** Not a fifth sub-domain: one small module, the human's side of the entry radio
(`docs/tactical-entry.md` E16). A child of the human's character (Main attaches it through `MatchSpawner.bind_player`), it listens to the
`&"callout"` bus like an NPC and, when an allied team is stacking at a doorway the human is near (`reserve_range` 300 px of walking), radios the
human's own claim for the first free slot: the same entry fields, with the human as `speaker`, repeated every 2 s. It reads the human's step
from where it stands (`claim` / `ready` / `going_in` / `in`) and withdraws on leaving, dying, nobody left stacking, or `go_timeout` after the AI
ahead is through. It reuses perception's `AgentEntry` statics (`claims`, `free_slot`, `stack_side`, `slot_point`) and geometry, and never moves the
character. `view()` feeds `StackMarkers` (UI). `entry.gd` has no case for a human: the barrier, the lone entrant's pie and the follow rule just see one more teammate.

Data flow each tick: the orchestrator folds queued hits and callouts into **Perception**, has it
`observe()` and return `contacts()`; hands those to **Behaviour** to resolve + honour commitments;
when free (or forced) and the frame has a snapshot to spare (`DecisionBudget`: `per_frame` snapshots a physics frame, one by
default, so NPCs deciding together spread over frames), asks **Perception** for a snapshot and starts a **Decision** walk
over it;
adopts the returned leaf into **Behaviour** (and radios it to allies); then has **Behaviour** `apply()`
the running primitive.

**Observer reads** (pure reads, never perturbing the loop): `debug_status()` is the decision path as labels plus the running
primitive's progress. `debug_state() -> Dictionary` is the deep snapshot: every level of the last walk (the state and question
Von saw, the options, its probabilities and pick), the facts, the contacts, the running primitive and pathing (`loco`: the walk's
`way` plain / round / held, `held_for`, `giving_way`), and `decisions` (walks started) with `decision_reason` (why the latest started:
the force reason, e.g. "task resolved", "way blocked", "attacked", or "cadence"); the dev command
server's `ai` verb dumps it and `tools/von_probe.py` replays captured levels against Von. `debug_zones() -> Array` flattens the
last snapshot's option groups to world points, each with its `label`, `desc` (for an inspector to explain a clicked point) and
`tags`, tagged by zone kind (fire / flank / advance / retreat / lead / search / entry / room / interaction, plus `waypoint` for
the non-room go-to points: post / entrance / approach). `debug_room_zones() -> Array` gives each room `{ rect, type, status }`
by how the NPC regards it (current / searched / unsearched / unknown). Both feed the tactics overlay (`domain-ai-debug`).

## Grenades (`docs/grenades.md`)

Two decisions Von makes and two reflexes outside it. **GRENADE** (G17) is a COMBAT tactic: offered against a hostile hidden from the NPC's line of fire, in throw range with a clear lob,
when no known ally would be in the blast and the NPC could get safe from it itself; it runs the `throw` primitive (select, aim, throw, radio `frag_out` / `bang_out`, gun back in hand, wait out the fuse, or the evade plan if it is in the
burst's zone). **STUN ENTRY** (G18) is a SEARCH tactic beside ENTER, offered while the NPC or its stack carries a stun: the same doorways, with a stun thrown into the room from beside the door before the point crosses (the `bang` phase of
`entry.gd`, `docs/tactical-entry.md` E17). `perception/snapshot` words both (`domain-ai-snapshot`), the tree has the nodes (`domain-ai-decision`), `combat.gd` throws (`domain-ai-combat`), `entry.gd` runs the bang (`domain-ai-behavior`); the numbers it
knows of a grenade not yet thrown (throw range, radii, fuses, the flash's cover reach) it reads off the grenades it carries (`Character.throw_stats(slot)`, interface 6/7; no copy in exports).

Two reflexes outside Von, in the orchestrator's loop (`_react_to_grenades`, `_process_events`), and the exports **Grenades** group (`grenades_enabled`, `hear_grenade` 300 px, `evade_margin` 120 px):
- **Evade (G16).** Perception knows the live grenades it sees, hears come down, is told of (callout `status` `grenade`, also `frag_out` / `bang_out`) or threw; when it is inside a
  grenade's danger zone it radios an `&"grenade"` callout (`point` = where it landed, `kind`) and the behaviour runs to the nearest safe spot (out of the burst's line, behind furniture that
  shields a crouched body, or outside the zone), holds it facing away and re-decides at the burst. No decision starts or is adopted meanwhile. `perception/agent_grenades.gd`,
  `agent_throw.gd`, `behavior.gd` ("The evade reflex"). `debug_grenades()` reads it; the `show_grenades` overlay draws it.
- **Stunned (G15).** Blind: no new sighting, no new decision (it re-decides the tick sight returns), its contacts kept so it fires blind at the last-known spot of the one it fought (the character's aim
  sway applies); deaf: the orchestrator drops gunfire, hits elsewhere, callouts and grenade landings it would have heard.

## The decision tree

```
root ─┬─ COMBAT (pick the hostile) ─┬─ ENGAGE  → a safe firing spot / ambush   (engage)
      │                             ├─ RELOAD  → swap in a magazine             (reload)
      │                             ├─ FLANK   → a side, route clear of hostiles (engage)
      │                             ├─ GRENADE → frag or stun a hostile hidden behind cover (throw)
      │                             ├─ ADVANCE → halfway / close / rush         (move)
      │                             ├─ MELEE   → punch, only when point-blank   (melee)
      │                             ├─ RETREAT → a hidden / farther spot        (move)
      │                             └─ LOCATE  → toward an unseen shooter       (move)
      ├─ INVESTIGATE ─┬─ a lead (last seen, heading, gunfire, ally's call)      (move)  [always asked of Von]
      │               └─ STAY → hold, when a lead is outside the house          (hold)
      ├─ SEARCH ─┬─ ENTER → a doorway into a room left to search              (entry)
      │          ├─ STUN ENTRY → the same with a stun thrown in first (a stun in the stack) (entry{bang})
      │          └─ a room / unexplored area / the entrance                     (move)
      ├─ RELOAD_QUIET → top up with nobody about                                (reload)
      └─ IDLE ─┬─ USE → an object · GO → a room · WAIT                           (interact / move / hold)
```

Entry rules skip the broad levels when the situation is clear (under fire / engaged / — when
pursuing — a hostile known → straight to COMBAT). A level with one option is taken without asking.

## The two presets

Spawned by Main (`defender_count` / `invader_count`, default 1 each):
- **Defender** — `ai/npc_defender.tscn` (faction `household`): `hostile_on_trespass` +
  `hostile_on_attack`, `defend_territory` (combat options stay inside the house), familiar with the
  house. Dropped at a clear spot in a random room (never inside solid furniture or on another defender).
- **Invader** — `ai/npc_invader.tscn`, an inherited scene overriding only data (faction
  `invader`): `hostile_on_sight`, not territorial, unfamiliar with the house (it learns rooms by
  sight and is offered unexplored areas by direction), a red body. Dropped just outside the house;
  several start spread around the perimeter and coordinate flanks over the callout radio. It enters rooms
  tactically (`entry_enabled`, `docs/tactical-entry.md`): stack beside the door, slice the pie, cross
  without stopping, take the corners, clear, leave rear security — as a team over the radio, or alone.

Both pursue hostiles (`pursue_hostiles`, default on): IDLE is never offered and a known hostile sends
every decision straight to COMBAT.

Both know their ammo: the snapshot's `loadout` section and the `gun_loaded` / `weapon_low` / `can_reload` facts feed a RELOAD
tactic in the decision tree, the `reload` primitive runs it, and the `auto_reload` export (default on) reloads an empty gun
as a reflex. `low_ammo_fraction` sets where "nearly empty" starts.

Nothing in the AI is written per weapon: it fights with `Character.gun_slot()` (whatever gun it carries — the presets hold a pistol, but a match
arms every NPC with a gun from its side's loadout, one random gun by default) and reacts only to generic conditions the character reports. Notably, when its gun cannot fire because the
barrel is against a wall or object (`weapon_blocked()`, a long gun), it steps back until it can; a pistol is never blocked. See `domain-ai-behavior`.

## Key idea: Von picks, perceptions inform, behaviour executes

Von ranks distinct, verb-like options well but cannot do arithmetic or compare near-identical spatial
points, so every level offers a few DISTINCT options whose text carries the deciding facts as bands
("short hidden route", "in pistol range", "held by Invader2"). The NPC acts only on what it has
PERCEIVED: it fights a hostile's last-KNOWN position, loses a contact once its sighting decays (it
becomes an investigation lead), and (unless `familiar_with_house`) must see rooms/objects before it can
use them. The detail lives in `domain-ai-perception`, `domain-ai-decision` and `domain-ai-behavior`.

**Interfaces:** 3 (`Explosion.shields` / `first_stop`, the blast's cover rule perception asks of a grenade), 6 (`ItemRegistry`'s
slot ids, `throw_stats()`, `aim_target()`), 7 (Character ↔ Controller, the observer reads and overlay exports), 9 (AI → Navigation), 10 (EventBus), 11 (`PhysicsLayers`), 13 (`DecisionStub` / `DecisionServerLauncher` for tests), 17 (the human's `PlayerStack`) — signatures in `architecture`.
