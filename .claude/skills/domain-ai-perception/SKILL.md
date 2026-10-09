---
name: domain-ai-perception
description: Deep implementation detail for the AI PERCEPTION sub-domain (scenes/ai/perception/) — what an NPC knows and how it is worded for Von. The sight sense, hostility rules, the generic event memory (with keyed supersede), movement tracks/facing/visible wounds, gunfire heard, allies' radio callouts, leads, searched rooms, the tactics geometry (flank sides, fire/advance/retreat spots, route length + exposure, cover) and the decision SNAPSHOT (state sections, facts, option groups) — plus the measured wording rules Von needs (situation phrases, bands, no negations). Use when editing scenes/ai/perception/ or working on vision, memory/eviction, what Von is told, option groups, flanking geometry, callouts, or combat line-of-sight. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Perception sub-domain (`scenes/ai/perception/`)

The SENSE half of the NPC brain: it turns the world into what the NPC *knows*, and turns that into the
snapshot the decision planner walks. It holds no policy — it never decides, picks or gates by goal. It
owns four internal modules and presents one public face, `agent_perception.gd` (a `Node`).

Files:
- `agent_perception.gd` — the public face: SEE (observe), the contacts view, event intake, BUILD (sense).
- `agent_vision.gd` — the sight sense and the single owner of the ray query (`blocked` / `raycast`).
- `agent_hostility.gd` — the hostility rules (categorization).
- `agent_memory.gd` — a generic, behaviour-agnostic event log.
- `agent_tactics.gd` — combat geometry: flank sides, fire/advance/retreat spots, routes, cover.

The controller (`ai/goal_controller.gd`) sets `agent_perception.gd`'s config fields from its exports,
calls `setup()` once to BUILD the internal modules, then `apply_config()` to configure them — and
re-calls `apply_config()` each decision, so a tunable retuned at runtime reaches the modules without a
rebuild that would wipe the event memory. Nothing outside this folder holds a reference to them.

## Public interface (what the orchestrator / behaviour call)

- `setup()` (build the modules), `apply_config()` (push the config fields into them; re-callable each
  decision), `set_faction(f)`.
- `observe(character, rooms)` — the SEE pass, every tick: one `saw_character` sighting per visible
  character (keyed, superseded while visible) carrying `pos`, a smoothed velocity track (`vel`),
  `facing`, a visible wound band, `ally`, inside/room, held item; the room the NPC stands in is
  remembered as searched (`visited_room`); an unfamiliar NPC learns rooms/objects by sight.
- `contacts(self_pos)` — characters seen within `contact_memory_ttl` (hostiles first, then nearest),
  with `hostile`/`reason`/`visible`/`age`. `lost_hostiles()` — hostiles last seen longer ago, within
  `lead_memory_ttl` (investigation leads).
- `process_hit(character, data) -> bool` — a hit on/near the NPC → `under_fire` (direction + whether it
  hit), `engaged`, hostility; a hit farther off within `hearing_radius` → `heard_gunfire` (a lead), but
  ONLY from a shooter not already known hostile — gunfire from a character it is fighting (or any other
  known hostile) is no mystery (COMBAT / that contact's last-seen lead already covers it), so it is not a
  lead; only an UNKNOWN shooter is.
- `process_callout(character, data)` — an ally's radio `&"callout"` within `callout_range` →
  `heard_callout` (keyed per speaker, ttl `callout_ttl`).
- `check_lead(lead_id)` — the NPC reached an investigation lead: remember it as checked
  (`checked_lead`), so it is not offered again until something newer happens there.
- `quick_facts(character)` — cheap facts (under fire, engaged, hostile known) between decisions.
- `sense(character, rooms, goal, activity) -> { facts, sections, sections_per_target, options }` — the
  BUILD pass (below). `activity` is the behaviour's current-activity line.
- Combat geometry for the behaviour: `has_line_to`, `combat_spots`,
  `note_engaged` / `engaged_fresh` / `under_fire` / `hit_recently`; `memory_size()` and
  `room_status(rooms, self_pos)` (each room tagged current / searched / unsearched / unknown) for debug.

## The snapshot (what the planner walks)

- **facts** — named booleans the tree gates on: `threat_known`, `hostile_known`, `hostile_visible`,
  `has_pistol`, `under_fire`, `hit_recently`, `engaged`, `leads`, `hurt`, `critical`, `inside`,
  `exposed`, `in_cover`.
- **sections** — named state-text blocks; each tree level shows the ones it lists: `goal`,
  `situation` (place, item, own health as its own sentence), `current` (activity line), `odds`
  (hostiles vs allies; "All quiet so far." only when there are no leads), `contacts`, `exposure`
  (clear shot / exposed to their fire / behind cover / line blocked, plus other hostiles that can see
  you), `allies` (each ally's side of the target + their radio callouts), `flanks` (one-line digest),
  `awareness` (being hit / under fire; gunfire heard only while no hostile is known; noted events).
  `sections_per_target[id]` re-frames exposure/flanks/allies around each known hostile.
- **options** — named groups `{ summary, summary_inside?, options: [{ id, label, desc, params, tags }] }`:
  `threat` (summary only), `hostiles` (bind: one per hostile, only DISTINGUISHING facts), per target
  `fire_positions` (where you stand, firing spots around the target named by place and cover — "behind
  the sofa in the kitchen", "the hallway, north of them" — with their route, and an ambush),
  `flank_sides` (tagged `held` when an ally — seen or radioed — holds it, `crosses` when the route
  there passes a known hostile; described as "route passes X"), `advance_positions` (halfway / close /
  rush), `melee` (one `punch` option, only while the target is point-blank); globally
  `retreat_positions`, `shooter`, `leads`
  (last seen, where they were heading, gunfire heard, unseen shooter, support an ally), `search_rooms`
  (+ front entrance / approach the house while outside), `explore` (unknown rooms by direction only),
  `interactions` (deduped by label, uncapped), `rooms`. Groups are capped at `max_options_per_level`.
  Options are places and things, never verbs; `tags.inside` drives the territorial filter.

## Wording rules for Von (measured with `tools/von_probe.py`)

Von is a CLASSIFIER: it picks the option whose text best matches the state. It can't do arithmetic or
compare numbers, and an encoder reads "no cover" as "cover". So:
1. **Bands, not numbers** — distance from `punch_range`/`shoot_range` ("point-blank", "close, in pistol
   range", "too far to shoot"), route length (`route_buckets`: short/medium/long, plus hidden/exposed),
   recency (`recency_bands`: just now / recently / a while ago).
2. **Canonical phrases** — the state uses the exact phrases the tree's situation descriptions are
   written in ("You have a clear shot at X from where you stand.", "You are exposed to their fire.",
   "You are badly wounded.", "looks badly wounded", "moving away from you"), so a fact lights up the
   option it argues for.
3. **No negated attributes** — "in the open", "line blocked", "free", "taken by X", "unsearched",
   "neutral", "too far to shoot".
4. **Only distinguishing facts in options** — common facts (every hostile is hostile and has a pistol)
   and the contacts section on a bind level blur the match.
5. **Only perceived facts** — facing, aim and wounds only while visible; unknown rooms by direction.
Room types are humanized ("kitchen_living" → "kitchen living").

## Contacts and hostility

The NPC perceives characters, not "the player". The hostility rules categorize each sighting: allies
(same faction or `allied_factions`) are never hostile; `on_sight` / `trespass` (seen inside the house)
/ `retaliate` (attacked it, via `process_hit`). A verdict is remembered as `&"hostile"` with ttl
`hostility_ttl` (≤ 0 = permanent grudge).

## Vision & knowledge

`agent_vision.gd.can_see` is true within `view_distance`, AND within the `awareness_radius` bubble or
the forward cone (`fov_degrees`), AND with a clear line on `QUERY_MASK = 1` (walls + solid furniture).
`enabled = false` = omniscient. `familiar_with_house` seeds every room/object as permanently known on
the first observe; otherwise each must be seen. People are never pre-known.

## Memory (`agent_memory.gd`)

A generic event log: `remember(topic, data, ttl, key := "")`; `is_fresh` / `recall` / `recall_all` /
`recall_aged` / `age_of` / `fresh` read back. A write with a `key` (the event's subject) SUPERSEDES the
live event with the same topic + key — something re-observed every tick stays one entry instead of
flooding the log and volume-evicting every other expirable event. Cleanup on every write: age-expired
first, then, while over `capacity`, the oldest expirable. Permanent events (ttl ≤ 0) never age out
and are never volume-evicted. Topics: `saw_character` / `saw_room` / `saw_object` / `visited_room` /
`hostile` / `under_fire` / `engaged` / `heard_gunfire` / `heard_callout` / `checked_lead`. An event whose `data`
carries a `note` string is surfaced to Von.

## Tactics (`agent_tactics.gd`)

Pure queries over known contacts, the physics space (via the vision rays) and the nav map
(`NavigationServer2D` closest point + path). A target's flanks are measured in its own frame (its
last-seen facing, else the side facing this NPC): left / right / rear candidates at `flank_distance`,
sampled across `flank_arc`, snapped to the navmesh, preferring a clear shot. Each spot is annotated
with clear shot, cover within a step (`cover_min`), route length + exposure (share of route samples
the target can see), `crosses` (a known hostile the route passes), `held_by` (ally within
`flank_ally_radius` on that side, or a callout point there), `exposed_to` (other hostiles),
`heading_toward` and `ally_lane`. Hostile fronts (`ctx.fronts`, built once per `sense()`) serve both
the flank frames and the watch test below.

Route safety: `route_crosses(path, hostiles)` names a hostile whose last-known position lies within
`route_clearance` of the route AND nearer than the route's start (walking away from someone close by
is not passing them). `watched_in_open(ctx, p, path)` names a hostile that would catch the NPC in the
open: looking toward `p` (within `watch_arc` of its front; an unknown facing counts as facing the NPC)
with a clear line and no cover within a step of `p`, or — while the NPC is now hidden or covered from it
— looking along a mostly exposed route there.

Fire spots are sampled on rings around the NPC (`combat_ring_radius`, ×2) and around the target (each of
`fire_spot_distances`); a spot needs a clear shot in range and must pass both route-safety tests, and
the best per 8-way sector around the target is kept (cover close by, then the shortest step). `here`
is never screened; the ambush spot passes the same tests. Advance spots lie along the route; retreat
spots come from known rooms, nearby cover and allies, kept only if hidden from every threat or farther
away (rays toward a threat exclude hostile bodies). A character is never cover; a blocking object is
named by its `object_name`, a character by its name, anything else as "wall".
`combat_spots` (ring around the NPC: fire vs cover) also serves the behaviour's peek-and-cover.
