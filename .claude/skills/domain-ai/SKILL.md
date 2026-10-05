---
name: domain-ai
description: Deep implementation detail for the AI domain (scenes/ai/) — non-player brains: the generic goal-driven controller, its perception helper, its tunable vision/sight sense, its event-memory helper, and the dev-only Von decision-server launcher. Use when editing scenes/ai/ or working on the NPC's goal/behaviour, its vision (field of view/range/line-of-sight) and what it knows vs. remembers, per-NPC house familiarity, agent perception/state, the agent memory, the act-centric decision menu, the derived movement, the commitment/engagement memory, the Von choice requests, or the decision server. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# AI domain

Non-player brains: controllers that drive a character (with a world-sensing/perception helper for
their decision context, a tunable **sight** sense that gates what they perceive, and an event-memory
helper for what they have seen and what has happened), plus the dev-only decision-server launcher. A
controller writes the character's intent and calls its public action API — it never reaches into
character internals.

**The NPC is not omniscient.** Each tick a SEE pass runs the world through a configurable vision
sense (field of view, range, line of sight) and deposits what is currently visible into the agent's
memory; the decision is then built from what the NPC *currently sees AND remembers*, never from
ground truth. It engages only a player it can locate, acts on a last-KNOWN position once sight is
lost, and forgets as the memory decays. See **Vision & knowledge** below.

## The goal-driven agent

`character/npc.tscn` is a **generic goal-driven agent** driven by `ai/goal_controller.gd`. Its
behaviour is pure data: an exported `goal` string in plain language ("watch tv", "make some food",
"hunt down the player", or the default house-guard goal), **authored on the NPC itself** — the
`goal` (and `engage_only_inside`) export on `npc.tscn`'s `GoalController` node, editable per NPC in
the Inspector. Main injects only world wiring (`target`, `rooms`), never the goal. **There is no
per-goal code** — the same machinery serves any behaviour; adding one means typing a string.

**The decision is act-centric.** Von ranks distinct, verb-like options sharply but ranks many
near-identical spatial points almost at random, so the NPC asks it **WHAT TO DO**, not where to
step, and derives the movement itself. Each decision `ai/agent_perception.gd`'s `sense()` builds a
compact text state **from what the NPC sees and remembers** (the goal verbatim, then where the NPC
is, what it holds, whether it is mid-interaction, and what it knows of the player — currently seen
with a live bearing, last seen with a bearing + age, or not known at all), followed by any
**combat-awareness** lines (under fire from a direction / gunfire struck nearby / its own injury
level) and **what each KNOWN character around it is holding** (threat context, from sightings), and
POSTs **two `choice` questions in one request** to a local Jev-style `/v1/systemone` server (Von):

- `act` — the real decision: `hold`; `shoot` / `punch` **offered only while the player is KNOWN**
  (a fresh sighting — you cannot choose to attack someone you can't locate); plus one **interact**
  option per *distinct* action offered by a **KNOWN** object (deduped by label, each pointing at the
  nearest known object that offers it; item-gated). A *familiar* NPC knows the whole house, so
  "Watch TV" / "Cook" / … are choosable from the start; an *unfamiliar* NPC only gains them as it
  sees the objects. Being distinct and verb-like, Von picks the goal's match sharply.
- `move` — named destinations only (each **known** room, where the player was last seen, the post),
  consulted **only** when the act is `hold` and the NPC is otherwise idle. No local step-ring and no
  distance annotations — those are what made Von wander.

It adopts Von's TOP pick (argmax `choice`) for each (steady-stance fallback when the server is down).

**Movement and aim are derived from the chosen act** (there is no aim question):
- `interact` → walk to that object, face it, and run the interaction once in reach (`interact_with`).
- `shoot` → **peek-and-cover** (`_apply_peek_cover`): aim at the player's **last-known** position and
  fire when the perception's `has_line_to(known_pos)` confirms a clear line (so it never shoots
  through walls), paced by `fire_cooldown`. **Vision gates whether it KNOWS the player; a clear line
  gates whether it can HIT them** — once a target is known, it shoots at where it knows they are,
  independent of its view cone (otherwise peeking around cover would starve it of shots). In the PEEK
  phase it moves to the nearest **fire spot** (clear line to the known position) and fires; after a
  shot it drops to COVER and ducks to the nearest **cover spot** for `cover_time`, then peeks again.
  The fire/cover position is committed for `reposition_interval` so the NPC steers smoothly. If the
  sighting decays while peeking (lost sight for `player_memory_ttl`), combat drops out and it
  reconsiders.
- `punch` → close to the last-known position to `punch_range` and swing on the cooldown (no cover
  cycle for fists).
- `hold` → watch the player if its position is known; a hunting NPC that can't locate it **patrols**
  instead (see below). Otherwise it holds and repositions to the `move` destination if one was chosen.

**Pursuing the player (`pursue_player`).** A hunting NPC must not get distracted by the house's
chores. The view cone follows the NPC's facing (its aim) and the character is frozen facing one way
while *in* an interaction, so settling into a passive interaction also blinds it. So when
`pursue_player` is true the controller overrides a chosen `interact` (and, when the player is known,
a `hold`) in `_set_act`:
- player **unknown** → a holding **"search"** (logged `act=search`), whose derived movement is a
  **house patrol** (`_apply_idle` → `_patrol`): it walks room to room facing its direction of travel,
  so the cone leads the way and sweeps naturally — no in-place spin. Right after losing sight it heads
  to the **last-known position** first (`_investigate_last_seen`), then cycles the rooms, picking the
  nearest it isn't in and didn't just leave (`_next_patrol_point`), re-choosing on arrival. While
  patrolling it doesn't re-ask Von (`_should_decide` returns false for this case); spotting the player
  fires a salient event that re-decides and engages at once. This is also how it "waits for the player
  to enter" — it just keeps patrolling and catches them when they come into view.
- player **known** → **engage** (shoot/punch): the ~20-option interaction menu otherwise dilutes
  Von's ranking so it picks e.g. "sit" with the player in plain view. The inside-gate still turns
  this back into a hold when engagement isn't allowed (intruder outside and not under fire).

Turn `pursue_player` off for an NPC whose goal is unrelated to the player (e.g. "watch tv"): it then
does its task and Von chooses freely, and only a backstop keeps a *non-pursuing* NPC that has been
dragged into a fight (self-defense, `&"engaged"` fresh) from peeling off to sit mid-combat. Like the
inside-gate, these are controller policies Von (a single-shot ranker) can't apply itself.

**Pathing avoids furniture, shoving through only as a last resort.** All derived movement flows
through `_path_move` on a `NavigationAgent2D`. The Navigation domain bakes furniture in as navmesh
holes, so the path already routes **around** furniture and reroutes through another doorway when the
near one is blocked. On top of that the controller enables the agent's RVO **avoidance**: each frame
`_path_move` feeds `_agent.velocity` the desired direction and applies the previous frame's
avoidance-safe velocity (from the `velocity_computed` callback, stored in `_safe_velocity`) to
`move_input`, so it steers around a piece shoved off its hole. When no route exists at all — a piece
seals the only way so `_agent.is_target_reachable()` is false, or the NPC stays wedged (advancing less
than `stuck_speed`) for `push_through_delay` seconds — it enters `_push_through`: it drives straight at
the blocker at full strength, letting the character's own push physics shove it aside, then resumes
normal pathing once it progresses or the target is reachable again. Tuning exports: `push_through_delay`,
`stuck_speed`.

**The inside-gate (`engage_only_inside`).** Von is a single-shot ranker and can't reliably apply an
"only if …" condition itself (e.g. "engage only once the player is inside"); asked to defend a
house it drifts to hiding/holding instead of shooting. So the controller enforces the one spatial
condition that matters here: when `engage_only_inside` is true, a `shoot`/`punch` pick made while
the player is **known to be outside** the house becomes `hold` (`hold(outside)` in the log), using
the KNOWN inside/outside fact from the latest sighting. Interactions and idle pass
through. Turn it off for a goal that should engage the player anywhere (e.g. hunt). The default goal
is therefore phrased unconditionally ("shoot the intruder on sight"), and the gate supplies the
"only inside" part. Otherwise there is no per-goal gating — the full act menu is offered every tick.
**Self-defense suspends the gate:** while the NPC is under fire (`under_fire_time` window after it
is hit) the gate no longer downgrades a `shoot`/`punch` pick, so it may defend itself against an
attacker even one still outside — the gate's job is to not *pre-emptively* attack someone merely
standing outside, not to forbid self-defense. But when combat is only running because of this
suspension (the attacker is still outside), the controller **holds its ground inside**
(`_hold_ground`): the peek-and-cover destinations are restricted to points inside the house and the
peek fallback stops advancing, so the NPC returns fire from inside (through a doorway/window when it
has a line) rather than chasing the attacker out. Once the attacker steps inside, normal aggressive
engagement resumes.

**Commitment memory (the System-Two layer Von lacks).** Von is stateless and cannot sequence, so
the controller holds the thread: once it heads for a chosen object it commits to reaching it (a
`max_commit_time` safety cap aside); once an interaction starts it stays in it for
`interaction_dwell` seconds; once it enters a fight it **commits to combat** while the `&"engaged"`
memory is fresh (`engage_dwell`, refreshed by each shot it fires or takes) rather than re-rolling
Von's flat `shoot`/`hold` ranking every cadence — which is what made it flip combat↔hold every
second (peek-and-cover keeps tracking the player while committed). It re-decides when the task
resolves, the dwell/cap elapses, or a **salient event** fires — a change in what it *believes* about
the player (first spotted, lost from sight, or crossing the house boundary per the last sighting),
or a **hit while not already in combat** (the NPC itself shot, or anything struck within
`hit_awareness_radius`, which kicks off a fight; a hit *during* a fight only refreshes the
engagement, so a firefight doesn't re-ask Von every frame). As a backstop, while the `&"engaged"`
memory is fresh any re-decision that returns an `interact` is overridden back to combat — so a
stray pick can't make the NPC break off to sit in a chair mid-fight. This lets multi-step goals
advance and firefights persist instead of oscillating every tick.

**Agent memory (`ai/agent_memory.gd`).** A generic, behaviour-agnostic event log the controller
owns: `remember(topic, data, ttl)` appends an event; `is_fresh`/`recall`/`recall_all`/`age`/`fresh`
read it back. It is **not** capped per topic — many events (and many of one topic) coexist. Cleanup
is a configurable policy run on every write: age-expired events (per-entry `ttl`, or the
`memory_default_ttl` fallback) are dropped first, then, while over `memory_capacity`, the oldest
**expirable** (positive-ttl) events. **Permanent events (ttl ≤ 0) never age out and are never
volume-evicted** — they are long-term facts (e.g. learned house knowledge), so they survive the
flood of short-lived sightings. The controller records `&"under_fire"` (incoming direction, ttl
`under_fire_time`) and `&"engaged"` (ttl `engage_dwell`); the perception records its sightings here
too (see below). `_under_attack()` is just `memory.is_fresh(&"under_fire")`. Adding a new remembered
event is one `remember()` call — give its `data` a `note` string and the perception surfaces it to
Von automatically. This replaces the old ad-hoc under-fire timers.

`agent_perception.gd` has two halves and holds no policy (reads only published contracts: character
API, objects' `get_interactions()` / `get_surface()`, the injected room rects):

- **`observe(...)` — the SEE pass, every tick.** Runs each thing through the vision sense and
  deposits what is currently visible into memory: the player (`&"saw_player"` with position, inside,
  room, held item; ttl `player_memory_ttl`), each visible other character (`&"saw_character"` with
  held item; ttl `character_memory_ttl`), and — for an *unfamiliar* NPC — rooms and objects it sees
  (`&"saw_room"` / `&"saw_object"`, permanent). A *familiar* NPC gets its rooms+objects seeded as
  permanent on the first observe (`_seed_house`). People are never seeded.
- **`sense(...)` — the BUILD pass, each decision.** Composes the state + menu from what the NPC
  currently sees and remembers (see the act-centric section): the player line from the freshest
  `saw_player` (live vs. "last saw … Ns ago"), known characters' items from `saw_character`, the
  injury line from `damage_taken()`, the under-fire/`note` lines from memory, and the act/move menus
  restricted to the player-if-known and to known rooms/objects.

It also answers the controller's combat-geometry queries — `player_visible()` (was the player in
view on the last observe tick; gates acquisition), `has_line_to(point)` (clear line to a world
point; the fire gate) and `combat_spots(character, known_pos, …)` (nearby fire/cover points vs. the
last-known position, classified by raycast) — which feed peek-and-cover directly, not Von.

## Vision & knowledge

`ai/agent_vision.gd` is the **sight sense** — pure, stateless geometry owned by the controller
(created like the memory). `can_see(from, facing, point, space, exclude)` is true when `point` is
within `view_distance`, AND either within a 360° `awareness_radius` near-bubble or inside the
forward cone of half-angle `fov_degrees/2` around the NPC's facing (its aim), AND reachable by a
clear line on the physics query layer (walls/solid furniture block sight). `enabled = false` makes
everything visible (omniscient), restoring the pre-vision behaviour.

**Per-NPC knowledge** is a memory seed, authored on the `GoalController`: `familiar_with_house` (on)
= the NPC starts knowing every room and object (seeded permanent); (off) = it must *see* each room
and object before it can navigate to or use it. People are never pre-known either way — a player or
other character is known only once seen, and that knowledge decays with its sighting's ttl, so the
NPC can be flanked and will lose a target that breaks line of sight for `player_memory_ttl`. The
controller resolves `_target_known` / `_known_target_pos` from `saw_player` each tick and ALL acting
reads those rather than the player's true position; losing the sighting drops combat back to the
goal.

`ai/vision_debug.gd` on `npc.tscn`'s `VisionDebug` child is an optional draw-only overlay (toggle
`show_vision`) that renders the cone, far arc, and awareness bubble from the controller's live vision
params — for tuning them visually. It senses nothing and feeds nothing back.

Tuning exports: `engage_only_inside`, `pursue_player`, `hit_awareness_radius`,
`under_fire_time`, `engage_dwell`, `memory_capacity`, `memory_default_ttl`, `push_through_delay`,
`stuck_speed`, and the **Vision** group (`vision_enabled`, `view_distance`, `fov_degrees`,
`awareness_radius`, `familiar_with_house`, `player_memory_ttl`, `character_memory_ttl`) on the
controller; `hurt_threshold`, `critical_threshold` on the perception (injury wording).

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
