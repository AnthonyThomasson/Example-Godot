---
name: domain-ai-perception
description: Deep implementation detail for the AI PERCEPTION sub-domain (scenes/ai/perception/) — what an NPC knows and how it is worded for Von. The sight sense, hostility rules, the generic event memory (with keyed supersede), movement tracks/facing/visible wounds, gunfire heard, allies' radio callouts, leads, searched rooms, the tactics geometry (flank sides, fire/advance/retreat spots, route length + exposure, cover), the doorway geometry for tactical entry (agent_entry.gd: stack slots, pie arc, hard/soft corners, the team's slot claims) and its hand-off to the decision SNAPSHOT (the snapshot itself, its wording rules and option groups are the sub-domain `domain-ai-snapshot`). Use when editing scenes/ai/perception/ (except the snapshot) or working on vision, memory/eviction, hostility, flanking geometry, entry geometry, callouts, or combat line-of-sight. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Perception sub-domain (`scenes/ai/perception/`)

The SENSE half of the NPC brain: it turns the world into what the NPC *knows*, and turns that into the
snapshot the decision planner walks. It holds no policy — it never decides, picks or gates by goal. It
owns five internal modules and presents one public face, `agent_perception.gd` (a `Node`).

Files:
- `agent_perception.gd` — the public face: SEE (observe), the contacts view, event intake, and the
  BUILD entry (`sense`) that gathers knowledge and delegates to the snapshot author.
- `agent_vision.gd` — the sight sense and the single owner of the ray query (`blocked` / `raycast`).
- `agent_hostility.gd` — the hostility rules (categorization).
- `agent_memory.gd` — a generic, behaviour-agnostic event log.
- `agent_tactics.gd` — combat geometry: flank sides, fire/advance/retreat spots, routes, cover.
- `agent_entry.gd` — doorway geometry for a tactical entry (`docs/tactical-entry.md`) and the team's claims on a doorway
  off the radio (see "Entry geometry" below).
- `agent_snapshot.gd` + `snapshot/` — the BUILD half (`domain-ai-snapshot`): turns the gathered knowledge + the tactics geometry
  into the decision SNAPSHOT (facts / sections / option groups) and owns the measured wording Von reads. Pure transform.

The controller (`ai/goal_controller.gd`) sets `agent_perception.gd`'s config fields from its exports,
calls `setup()` once to BUILD the internal modules, then `apply_config()` to configure them — and
re-calls `apply_config()` each decision, so a tunable retuned at runtime reaches the modules without a
rebuild that would wipe the event memory. Nothing outside this folder holds a reference to them.

## Public interface (what the orchestrator / behaviour call)

- `setup()` (build the modules), `apply_config()` (push the config fields into them; re-callable each
  decision), `set_faction(f)`.
- `observe(character, rooms)` — the SEE pass, every tick: one `saw_character` sighting per visible
  character (keyed, superseded while visible; renewed every `SIGHT_EVERY_FRAMES` (3) physics frames, offset per NPC and target,
  for a character that stays in the view cone: the range/cone test runs every frame, so one that enters the cone is tested at once
  and one that leaves it is dropped at once, and what the NPC holds of a character it sees is at most 3 frames old;
  `tests/ai/sight_follows_a_moving_target_test.gd`) carrying `pos`, a smoothed velocity track (`vel`; `track_smoothing` is the share taken per physics frame, so a sighting several frames after the last takes the share they add up to),
  `facing`, a visible wound band, `posture`, `ally`, inside/room, held item; the room the NPC stands in is
  remembered as searched (`visited_room`); an unfamiliar NPC learns rooms/objects by sight (it skips what it already knows
  before testing sight, and reads each known set once per pass). That look runs every `LEARN_EVERY_FRAMES` (6) physics frames,
  offset per NPC by instance id so a squad does not look on the same frame, and again at the start of every `sense()`, so what
  it knows at a decision is what it sees at that moment. The characters it tests are found by scanning the world
  root once and keeping the list (`_other_characters`: rescanned only when a node with `current_item` enters or leaves the
  tree, via `node_added` / `node_removed`; the scan walks ~1000 nodes).
- `contacts(self_pos)` — characters seen within `contact_memory_ttl` (hostiles first, then nearest),
  with `hostile`/`reason`/`visible`/`age`. `lost_hostiles()` — hostiles last seen longer ago, within
  `lead_memory_ttl` (investigation leads).
- `process_hit(character, data) -> bool` — a hit on/near the NPC → `under_fire` (direction + whether it
  hit), `engaged`, hostility; a hit farther off within `hearing_radius` → `heard_gunfire` (a lead), but
  ONLY from a shooter not already known hostile — gunfire from a character it is fighting (or any other
  known hostile) is no mystery (COMBAT / that contact's last-seen lead already covers it), so it is not a
  lead; only an UNKNOWN shooter is.
- `process_callout(character, data)` — an ally's radio `&"callout"` within `callout_range` →
  `heard_callout` (keyed per speaker, ttl `callout_ttl`). One carrying `cleared_room` (an ally cleared a room in a
  tactical entry) also teaches the room, marks it `visited_room` and `cleared_room`, so the team does not clear it twice.
- `check_lead(lead_id)` — the NPC reached an investigation lead: remember it as checked
  (`checked_lead`), so it is not offered again until something newer happens there.
- `quick_facts(character)` — cheap facts (under fire, engaged, hostile known) between decisions.
- `sense(character, rooms, goal, activity) -> { facts, sections, sections_per_target, options }` — the
  BUILD pass (below). `activity` is the behaviour's current-activity line.
- Combat geometry for the behaviour: `has_line_to`, `combat_spots`,
  `note_engaged` / `engaged_fresh` / `under_fire`; `memory_size()` and
  `room_status(rooms, self_pos)` (each room tagged current / searched / unsearched / unknown) for debug.
- Entry geometry for the behaviour: `entry_geometry(character, opening_id, into)`, `entry_team(opening_id)` and the shared
  stack rules `entry_free_slot(team, self_id, current)`, `entry_stack_side(geometry, team, self_pos)` and
  `entry_slot_point(geometry, side, slot)` (wrappers on `AgentEntry`'s statics, which the snapshot's `entries` group also uses; the
  behaviour never reaches into `agent_entry.gd` itself) (below). `openings` (the house's doorways, set by the controller each tick from Main's inject) and `entry_enabled`.
- `visible_points(character, points) -> Array` — of `points`, the subset in sight right now (view
  cone + clear line of sight, via `can_see`); the searcher's room-coverage test (behaviour samples a
  room and asks each tick which sampled points it has now seen).

## The snapshot and the wording rules — `domain-ai-snapshot`

`sense(character, rooms, goal, activity)` gathers the knowledge (contacts, callouts, learned rooms/objects, lost hostiles) and hands it to
`agent_snapshot.gd`'s `build(...)`, which assembles the snapshot the planner walks (facts, state sections, option groups) and owns the
measured wording Von reads. That whole sub-domain — `agent_snapshot.gd` and `snapshot/` (vocabulary + tuning, sections, option groups), the
fact / section / option reference and the Von wording rules — is the **`domain-ai-snapshot`** skill.


## Contacts and hostility

The NPC perceives characters, not "the player". The hostility rules categorize each sighting: allies
(the same faction) are never hostile; `on_sight` / `trespass` (seen inside the house)
/ `retaliate` (attacked it, via `process_hit`). A verdict is remembered as `&"hostile"` with ttl
`hostility_ttl` (≤ 0 = permanent grudge).

## Vision & knowledge

`agent_vision.gd` reuses one `PhysicsRayQueryParameters2D` for every cast, and `can_see_node` tests the cone before building
the ray's exclude list. `agent_vision.gd.can_see` is true within `view_distance`, AND within the `awareness_radius` bubble or
the forward cone (`fov_degrees`), AND with a clear SIGHT line on `QUERY_MASK = 1` (walls + solid
furniture). The sight line looks OVER low cover: it walks the ray, skipping any collider whose
`coverage` (the Objects height proxy) is at or below `see_over_coverage` (default 60 — tables, beds,
islands, counters) and continuing past it, so only walls (coverage 100) and tall furniture (cabinets,
wardrobes, fridges) break the line. This is sight-only — `blocked()` / `raycast()` stay fully physical
(every solid collider counts) for line-of-fire and cover, so a bullet is still stopped by a table.
`enabled = false` = omniscient. `familiar_with_house` seeds every room/object as permanently known on
the first observe; otherwise each must be seen. People are never pre-known.

## Memory (`agent_memory.gd`)

A generic event log: `remember(topic, data, ttl, key := "")`; `is_fresh` / `recall` / `recall_all` /
`recall_aged` / `age_of` / `fresh` read back. A write with a `key` (the event's subject) SUPERSEDES the
live event with the same topic + key — something re-observed every tick stays one entry instead of
flooding the log and volume-evicting every other expirable event. Cleanup on every write: age-expired
first, then, while over `capacity`, the oldest expirable. Permanent events (ttl ≤ 0) never age out
and are never volume-evicted. Events are stored as one list per topic, each in write order, every event carrying its write order across topics (`seq`): a keyed write
supersedes in place within its own topic's list and every reader walks only the topic it names, so the cost of a call follows the number
of events of that topic, not of everything remembered (a familiar NPC holds a permanent `saw_room` / `saw_object` per room and
furniture piece). `seq` keeps the promised order: newest first for readers and `fresh()`, oldest expirable first for volume eviction.
`_prune` skips its scan until the earliest deadline among the stored events (`_earliest_expiry`), and every reader takes the clock
once. `tests/ai/memory_matches_reference_test.gd` runs random writes through the memory and a plain ordered log and compares every reader. Topics: `saw_character` / `saw_room` / `saw_object` / `visited_room` /
`cleared_room` / `hostile` / `under_fire` / `engaged` / `heard_gunfire` / `heard_callout` / `checked_lead`.

## Tactics (`agent_tactics.gd`)

The flank behaviour these queries should deliver, and the tests that assert it, are in
`docs/flanking-behavior.md`.

Whether the NPC is hidden from a hostile where it stands is worked out once per snapshot (`ctx.covered_from`), not per candidate
spot. Pure queries over known contacts, the physics space (via the vision rays) and the nav map
(`NavigationServer2D` closest point + path). A target's flanks are measured in its own frame (its
last-seen facing, else the side facing this NPC): left / right / rear candidates at `flank_distance`,
sampled across `flank_arc`, snapped to the navmesh, preferring a clear shot. Each spot is annotated
with clear shot, cover within a step (`cover_min`), route length + exposure (share of route samples
the target can see; for a flank, only samples inside the target's view cone, `watch_arc` around its
front, so a route behind its back is hidden — `route_exposed`'s optional `front`), `crosses` (a known
hostile the route passes), `held_by` (ally within `flank_ally_radius` on that side, or a callout point
there), `exposed_to` (other hostiles), `heading_toward` and `ally_lane` (a seen ally whose line of fire
on the target passes within 40 px of the spot, or that the route there crosses). Hostile fronts
(`ctx.fronts`, built once per `sense()`) serve both the flank frames and the watch test below. The
snapshot turns these into boolean tags on each `flank_sides` option — `held`, `crosses`, `no_shot` (no
clear shot), `heading`, `lane` — which the `flank` node's `drop_tags` drop; the side stays in
`debug_zones()` with its words ("line blocked from there", "they are moving toward that side", "in X's
line of fire").

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

## Entry geometry (`agent_entry.gd`)

The behaviour asked of it is `docs/tactical-entry.md`. Given the house's openings (Main's `WorldGen.get_openings`, handed
in by `set_house` on each observe) and rooms, `entries_from(room_key)` lists the doorways out of the NPC's area (outer
doors from outside, a room's doors into the next room), `watch_doors(room_key, exclude_id, is_cleared)` those of a cleared
room on into rooms not cleared (what the team covers after clearing it, E8; the perception's `entry_watch_doors(into, opening_id)`) and `geometry(id, into, map, space)` lays one out, built once on a
baked nav map and cached (walls do not move): `out` (unit normal away from the room, from the room edge the door lies on)
and `along` (the wall's axis), `wall` (wall length either side), `side` (the side with more wall, 0 when even), `slots`
(single file against the wall on each side: `wall_standoff` off it, the first a body clear of the jamb, then every
`stack_spacing`, snapped), `pie` (`pie_steps` points `pie_radius` from the threshold, from 55° to 25° off the axis), and the
room's four corners inset `corner_inset`, each `near` (on the door's wall), `side` and `hard` (no sight line from 24 px
outside the threshold). The statics `claims(id, callouts)` (allies' live entry claims: slot, side, step, covering; `abort` and `done` drop one), `free_slot(team,
self_id, current)` (the lowest free slot; a tie goes to the lower instance id), `stack_side(g, team, self_pos)` and
`slot_point(g, side, slot)` are shared with the snapshot's `entries` group and, through the `AgentPerception` wrappers, with the behaviour's `entry.gd`. Tunables: the controller's `entry_*` exports.

**Cleared rooms and the entry guard (E9).** `cleared_room` (keyed per room, ttl `search_memory_ttl`) is not `visited_room`:
standing in a room visits it, but a room is *cleared* only by `mark_cleared(key)`: the behaviour calls it when an entry
finishes (`entry.gd` `_finish`, own clear or an ally's) and when a search covers its room by sight, and `process_callout`
when an ally radios `cleared_room`. `is_cleared(key)` reads it; the snapshot's `entries` group skips only cleared rooms
(search ranking still uses `visited_room`). `threshold_ahead(character, path, from_idx, max_dist)` (a thin wrapper on
`AgentEntry.threshold_ahead`) walks a nav path and returns the first doorway whose wall plane a step crosses, within the
doorway's width and heading into a room that is not the one the NPC is in and is not cleared: `{ opening, into, dist }`, or
{}. The last step is extended by `THRESHOLD_EXTEND` (30 px) so a destination that is the doorway counts. The behaviour's
entry guard calls it every tick. `room_doorways(room_key)` (over `AgentEntry.room_doorways`) lists every doorway of a room, outer doors
included, as `{ id, pos, width }`: the places a resting NPC watches (`Watch.idle_gaze`, `domain-ai-watch`).
