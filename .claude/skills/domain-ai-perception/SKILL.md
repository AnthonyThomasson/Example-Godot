---
name: domain-ai-perception
description: Deep implementation detail for the AI PERCEPTION sub-domain (scenes/ai/perception/) — what an NPC knows. The sight sense (field of view / range / line of sight), the hostility rules, the generic event memory, the merged known-contacts view, the decision context it builds for Von (state text + act/move menus), per-NPC house familiarity, and the combat-geometry queries (clear line of fire, peek/cover spots). Use when editing scenes/ai/perception/ or working on vision, what an NPC sees vs. remembers, hostility categorization, memory/eviction, the act/move menus, or combat line-of-sight. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Perception sub-domain (`scenes/ai/perception/`)

The SENSE half of the NPC brain: it turns the world into what the NPC *knows*, and knows nothing of
policy — it never decides, picks or gates by goal. It owns three internal modules and presents one
public face, `agent_perception.gd` (a `Node`), to the orchestrator and behaviour sub-domains.

Files:
- `agent_perception.gd` — the sub-domain's public face (the perception/sensor Node).
- `agent_vision.gd` — the sight sense (pure, stateless geometry).
- `agent_hostility.gd` — the hostility rules (categorization).
- `agent_memory.gd` — a generic, behaviour-agnostic event log.

The controller (`ai/goal_controller.gd`) is the single authoring surface: it copies its exports onto
`agent_perception.gd`'s config fields and calls `setup()` once, which builds + configures the three
internal modules. Nothing outside this folder holds a vision/hostility/memory reference — all access
goes through the perception methods below.

## Public interface (what the orchestrator / behaviour call)

- `setup()` — build the owned vision/hostility/memory from the config fields; `set_faction(f)` — tell
  the hostility rules this NPC's own faction (allies are never hostile).
- `observe(character, rooms)` — the SEE pass, run every tick. Tests what is currently visible via the
  vision sense, deposits sightings into memory (`saw_character` for every other character, the player
  included; `saw_room`/`saw_object` for an NPC learning its surroundings), and runs each character
  sighting through the hostility rules. Dead characters are skipped.
- `contacts(self_pos) -> Array` — the merged known-contacts view: the freshest sighting per character
  + `hostile`/`reason` + `visible` (seen this tick), hostiles first then nearest. Dead/freed drop out.
- `sense(character, rooms, goal) -> { state_text, acts, moves }` — the BUILD pass, run each decision:
  the compact text state Von ranks against, plus the act and move menus (below).
- `has_line_to(character, target, point) -> bool`, `combat_spots(character, target, tgt_pos, radius,
  count) -> { fire, cover }`, `contact_visible(id) -> bool` — combat geometry for the behaviour
  (pure sensing, never routed through Von).
- `process_hit(character, data) -> bool` — fold one world `&"hit"` event into memory + hostility
  (`under_fire`, `engaged`, `on_attacked`); true when it was a relevant attack. `note_engaged()`,
  `engaged_fresh() -> bool`, `under_fire() -> bool` — the thin engagement/under-fire memory queries.

## Contacts and hostility

**The NPC perceives characters, not "the player".** Each `saw_character` sighting is
`{ id, node, name, faction, pos, inside, room, item }` (ttl `contact_memory_ttl`). The hostility rules
(`agent_hostility.gd`, configured from the controller's Hostility exports) then categorize it:
- **Allies are never hostile**: same faction as the NPC's character, or listed in `allied_factions`.
- `on_sight` — any other character seen is hostile (`reason "seen"`).
- `trespass` — any other character seen *inside the house* is hostile (`"trespassing"`).
- `retaliate` — a character that attacks the NPC is hostile (`"attacked you"`), fed from
  `process_hit` (a hit on the NPC, or within `hit_awareness_radius`, whose attacker isn't itself).

A verdict is remembered as `&"hostile"` `{ id, reason }` with ttl `hostility_ttl` (≤ 0 = permanent
grudge), so it persists after the trigger ends.

## The decision context (what Von is asked)

`sense()` builds, from what the NPC sees AND remembers:
- **state** — the goal verbatim; where the NPC is / what it holds / whether mid-interaction; one line
  per known contact (up to `max_contacts_in_state`: live or "last saw … Ns ago", HOSTILE(reason) or
  not, inside/outside + room, bearing, held item); then combat-awareness lines (under fire from a
  direction, any remembered event with a `note`, own injury level).
- **act menu** — `hold`; per **known hostile** `shoot_<id>` (if carrying the pistol) and `punch_<id>`;
  `search` when none is known; plus one **interact** option per *distinct* action offered by a
  **known** object (deduped by label → nearest known object offering it; item-gated).
- **move menu** — named destinations only: each **known** room, `last_seen_<id>` per known hostile,
  and the starting position (`post`). Consulted by the behaviour only when the act is `hold`.

## Vision & knowledge

`agent_vision.gd.can_see(from, facing, point, space, exclude)` is true when `point` is within
`view_distance`, AND either within the 360° `awareness_radius` bubble or inside the forward cone of
half-angle `fov_degrees/2` around facing, AND reachable by a clear line on the physics query layer
(`QUERY_MASK = 1` — walls + solid furniture). `enabled = false` = omniscient. `agent_vision.gd` is
the sub-domain's single owner of that ray query: it also exposes `blocked(…)` / `raycast(…)` (pure
geometry, ignoring `enabled`), which the combat-geometry tests below use instead of repeating it.

**Per-NPC knowledge** is a memory seed: `familiar_with_house` (on) seeds every room/object as
permanent on the first observe (`_seed_house`); (off) the NPC must *see* each room/object first.
People are never pre-known — known only once seen, forgotten after `contact_memory_ttl` out of sight.

## Memory (`agent_memory.gd`)

A generic event log: `remember(topic, data, ttl)`; `is_fresh`/`recall`/`recall_all`/`fresh`
read back; not capped per topic. Cleanup runs on every write: age-expired first, then, while over
`capacity`, the oldest **expirable** events. **Permanent events (ttl ≤ 0) never age out and are
never volume-evicted** (learned house knowledge, permanent hostility verdicts). Topics in use:
`saw_character`, `saw_room`, `saw_object`, `hostile`, `under_fire`, `engaged`. An event whose `data`
carries a `note` string is surfaced to Von automatically.

## Combat geometry

Pure physics queries via `agent_vision.gd`'s `blocked()` / `raycast()`, excluding the NPC and the
target body:
- `has_line_to(…, point)` — a clear line to the engaged contact's **last-known** position gates
  FIRING (vision gates whether it KNOWS a contact; a clear line gates whether it can HIT it).
- `combat_spots(…)` — ring of candidate points classified `fire` (clear line to `tgt_pos`) vs
  `cover` (shielded by a ≥ `cover_min` coverage solid), each nearest-first, for the behaviour to pick.
