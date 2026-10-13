---
name: domain-ai-coverage
description: Deep implementation detail for the AI SEARCH COVERAGE module (scenes/ai/behavior/search_coverage.gd) — how a searcher covers a room by sight: grid-sampling the room into points (inset from the walls, off furniture), dropping the points now in its view cone with a clear line, turning its gaze to the nearest unseen one, walking to a new vantage when it is far or occluded, and finishing once enough is seen or the time budget runs out. Use when editing scenes/ai/behavior/search_coverage.gd or working on search/explore behaviour, the search-coverage overlay data or the search_coverage_* tunables. Complements the `domain-ai-behavior` overview and `domain-ai-debug`.
---

# AI · Search coverage module (`scenes/ai/behavior/search_coverage.gd`)

A `RefCounted` that `Behavior` owns. A `look_around` move (search / explore) ignores the `arrive_room` early-out and walks all the way INTO the
room (its interior `point`); on arrival `Behavior` calls `begin(character)` and from then on `step(character, delta)` every tick until it
returns true, then flags the task resolved so the controller re-decides. `max_commit_time` still caps the walk INTO the room before
coverage starts.

- **Sample:** `begin` locks the room (`Locomotion.room_key_at`) and grid-samples it (`spacing`, inset `margin` off the walls, dropping any point off the
  navmesh via `Locomotion.on_navmesh` so none lands on furniture) into `points`, with `unseen` a copy. An unknown room (an explore point in no
  room) samples nothing, so coverage ends at once — a single look. `sample_room(key)` is public: a tactical entry
  (`behavior/entry.gd`) measures the share of a room it saw from outside against the same grid, and reuses
  `begin`/`step` to clear the room once inside.
- **Step:** each tick it drops from `unseen` every point now in view (perception's `visible_points`: view cone + line of sight), spends
  `budget`, turns the gaze (`look_rate` rad/s, eased from where the NPC actually faces, so a threat that held its eyes meanwhile is not snapped back from) toward the nearest still-unseen point (`target`) and — when that point is farther than `approach` or
  its line is blocked by furniture — walks toward it (`Locomotion.move_to`) so a new vantage reveals it; otherwise it stands and turns.
  It is done when `unseen` has shrunk to `1 − target_fraction` of the points or the budget (`budget_max`) is spent. So a searcher actively looks
  throughout the room until it has SEEN all of it, rather than looking from one spot.
- **Debug:** `debug()` → `{ points, unseen, target, budget }`; `Behavior.debug_coverage()` adds `active` (a look-around move that has arrived and is not
  resolved, or an entry in its `clear` phase), which the search overlay (`domain-ai-debug`) draws.
- **Tunables** (controller exports copied in by `Behavior.apply_config()`): `search_coverage_spacing`, `_margin`, `_target`, `_budget`, `_approach`,
  `search_look_rate`.
