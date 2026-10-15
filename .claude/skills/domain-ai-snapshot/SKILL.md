---
name: domain-ai-snapshot
description: Deep implementation detail for the AI SNAPSHOT sub-domain (scenes/ai/perception/snapshot/ + agent_snapshot.gd) — the decision snapshot the planner walks and Von reads: the named facts, the state-text sections (situation, loadout, odds, contacts, exposure, allies, flanks, awareness), the option groups (hostiles, fire/flank/advance/melee per target, reload, retreat, leads, shooter, entries, search, explore, interactions, rooms), the shared vocabulary and tuning (SnapshotVocab) and the measured wording rules Von needs (bands, canonical phrases, no negations). Use when editing scenes/ai/perception/snapshot/ or agent_snapshot.gd, or adding a fact, a state section, an option group, or changing what Von is told. Complements the `domain-ai-perception` overview, `domain-ai-decision` and the `architecture` skill.
---

# AI · Snapshot sub-domain (`scenes/ai/perception/agent_snapshot.gd` + `snapshot/`)

The BUILD half of perception: given what the NPC currently knows (contacts, memory, learned house knowledge) and the combat
geometry, it writes the decision SNAPSHOT the planner walks. A pure transform: it reads the event memory and the tactics module,
holds no state between calls, and never writes memory, decides or picks. `agent_perception.gd` (see `domain-ai-perception`) owns it
and calls `build()` once per decision; it sets the tunables on `snapshot.vocab` from `apply_config()`.

Files:
- `agent_snapshot.gd` — `build(character, rooms, goal, activity, known, callouts, knowledge) -> { facts, sections, sections_per_target,
  options, gun }`: the **facts** literal, the per-hostile loop (`_analyze`), and the assembly of the dict; `fill_goal(goal, character)`.
- `snapshot/snapshot_vocab.gd` — the shared vocabulary and tuning: `COMPASS`, `SIDE_WORDS`, every tunable the perception copies in
  (`shoot_range`, `punch_range`, `recency_bands`, `route_buckets`, `aim_cone`, `still_speed`, `flank_ally_radius`,
  `investigate_distance`, `extrapolate_cap`, `max_options_per_level`, `hurt_threshold`, `critical_threshold`, `low_ammo_fraction`,
  `max_contacts_in_state`, `search_memory_ttl`), the house `rooms` of the decision being built, and the band / wording helpers
  (`dist_band, recency, route_band, route_text, move_text, coming_text, aim_text, where, room_suffix, room_name, health_band,
  wound_band, compass, place, own_posture_text, contact_posture_text, gun_noun, side_status, is_inside, house_centre`, static `room_at`).
  The snapshot reads its tuning here only; the same fields are declared on the controller (the exports) and on the perception
  (which copies them in), so adding a tunable is three declarations and one line in `agent_perception.apply_config()`.
- `snapshot/snapshot_sections.gd` — the state text: `situation_text, loadout_text, odds_text, contacts_text, exposure_text,
  unseen_fire_text, allies_text, flanks_text, awareness_text, threat_summary`.
- `snapshot/snapshot_options.gd` — the option groups: `hostile_group, reload_group, fire_group, flank_group, grenade_group, melee_group,
  advance_group, retreat_group, lead_group, shooter_group, entry_group` (with the static `entry_rooms`)`, search_group, explore_group,
  interaction_group, room_group` and their
  helpers. Reads the per-decision knowledge from `know` (set by `build()`).

Add a **fact** in the `facts` literal of `build()`; a **section** as a `*_text` function in `snapshot_sections.gd` plus a key in
`build()`'s `sections` dict (and list it in the tree level that shows it); an **option group** as a `*_group` function in
`snapshot_options.gd` plus a key in the `options` dict. A fact the tree does not gate on is available vocabulary for new rules
(`tools/audit_scan.py facts` lists those).

## The snapshot (what the planner walks) — built by `agent_snapshot.gd`

The face's `sense(character, rooms, goal, activity)` gathers the knowledge (contacts, callouts,
learned rooms/objects, lost hostiles) and hands it to `agent_snapshot.gd`'s
`build(character, rooms, goal, activity, known, callouts, knowledge)`, which assembles the snapshot
below from that knowledge + the tactics geometry. The author reads the memory and tactics modules
only; it writes no memory and holds no policy. Everything in this section and the wording rules below
lives in `agent_snapshot.gd`.

- **facts** — named booleans a `requires` or an entry rule can gate on: `threat_known`, `hostile_known`,
  `gun_loaded` (the gun it fights with, `Character.gun_slot()`, has rounds and is not mid-reload),
  `weapon_low` (at or below `low_ammo_fraction` of its magazine, empty included), `can_reload` (a carried magazine would add
  rounds), `under_fire`, `engaged`, `leads`, `lead_outside` (the NPC is inside the house and an offered lead lies outside it:
  gates the `stay` child of INVESTIGATE), `hurt`, `inside`, `exposed`, and the grenade ones: `has_frag`, `has_stun` (carried, `Character.item_count`), `grenade_ready` (some known hostile has a `grenade_throws` option),
  `stack_has_stun` (it carries a stun, or a teammate's entry callout says `stuns` > 0: gates STUN ENTRY). The brain overlay shows the ones that hold.
- **sections** — named state-text blocks; each tree level shows the ones it lists: `goal` (the controller's goal with `{gun}` filled in by `fill_goal`, the same noun as `loadout`),
  `situation` (place, item, own health as its own sentence), `current` (activity line), `odds`
  (hostiles vs allies; "All quiet so far." only when there are no leads), `contacts`, `exposure`
  (clear shot / exposed to their fire / behind cover / line blocked, plus other hostiles that can see
  you), `allies` (each ally's side of the target + their radio callouts), `flanks` (one-line digest),
  `loadout` (then "You carry a frag grenade and a stun grenade." for the grenades carried; the gun in bands, never round counts: "Your pistol is loaded." / "…nearly empty." / "…empty.", then
  once it runs low "You carry spare magazines." or "You are out of spare magazines."; "You are reloading your pistol.";
  empty without a gun; the noun is the gun's display name lower-cased, `gun_noun` ("pistol", "assault rifle", an acronym like "SMG" kept), so a
  pistol user's text is unchanged and the Von scenario fixtures stay valid; listed in the contexts of root, combat, engage, flank, advance), `awareness` (being hit / under fire; gunfire heard only while no hostile is known; noted events).
  `sections_per_target[id]` re-frames exposure/flanks/allies around each known hostile. The snapshot also carries `gun` (that noun), which the planner
  fills into `{gun}` in the tree's templates. `shoot_range` and the "in pistol range" distance band are deliberately left gun-agnostic (pinned wording).
- **options** — named groups `{ summary, summary_inside?, options: [{ id, label, desc, params, tags }] }`:
  `threat` (summary only), `hostiles` (bind: one per hostile, only DISTINGUISHING facts), per target
  `fire_positions` (where you stand, firing spots around the target named by place and cover — "behind
  the sofa in the kitchen", "the hallway, north of them" — with their route, and an ambush),
  `flank_sides` (tagged `held` when an ally — seen or radioed — holds it, `crosses` when the route
  there passes a known hostile; described as "route passes X"), `advance_positions` (halfway / close /
  rush), `melee` (one `punch` option, only while the target is point-blank); globally
  `reload` (one option, only while `can_reload`, so the planner takes it unasked), `retreat_positions`, `shooter`, `leads`
  (last seen, where they were heading, gunfire heard, unseen shooter, support an ally; each says WHERE it is in the canonical
  `SnapshotVocab.place`/`where` words, "in the kitchen" / "outside the house", and the awareness section says it of heard gunfire too, so the
  NPC's goal can be weighed against it), `entries` (the doorways
  ENTER offers, `entry_enabled` only: out of the NPC's area into a room unseen — named by direction — or unsearched,
  nearest first; the place is the NPC's free stack slot on the team's side, `params` carry `opening`, `into`, `slot`,
  `side`; the summary is the nearest one's desc), `search_rooms` (+ front entrance / approach the house while outside;
  with entries, the rooms they lead into and the entrance are left to ENTER), `explore` (unknown rooms by direction
  only, minus those an entry leads into),
  `interactions` (deduped by label, uncapped), `rooms` (uncapped). The other groups are capped at `max_options_per_level`
  (`explore` at two).
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
A seen character's `reloading` flag (read via `is_reloading()` only while visible) joins its contact line ("…, reloading").
**Grenades** (`docs/grenades.md`): per target the group `grenade_throws` (`grenade_group`): one option `frag` / `stun` per kind carried, only against a hostile whose last-known spot is hidden from the NPC's line of fire
(`line.clear` false), within that kind's throw range (`AgentThrow.range_of`, off the grenade carried) with a clear lob (`AgentThrow.can_lob`), judged per kind; `params` `point` (the spot), `kind`, `radius`, `slot`, `target_id`; `tags` `ally_in_blast` (a known ally, seen or on the radio, in the
grenade's danger zone at the spot: `AgentThrow.in_zone`), `no_safe_spot` (the NPC itself is in the zone standing and `AgentThrow.escape` finds no spot or cover within the fuse) which the tree's `grenade` node drops by, and `inside`.
The exposure section says "You can throw a frag grenade onto their spot." for the options not dropped, and "X is blinded by a flash and cannot see you." for a hostile it caught in a stun's flash (`blind` on the contact, from
`AgentPerception.process_explosion`); the contact line, the `hostiles` option and the ADVANCE summary say "blinded by a flash", a blinded hostile has no `aim_text`, and the `hostiles` bind carries `blinded` (the clause
the ADVANCE desc's `{blinded}` is filled with). The `entries` options say what makes a room suspect instead of "unexplored"/"unsearched": "gunfire heard there" (a `heard_gunfire` position inside the room), "a hostile seen going in"
(a lost hostile last seen in it), listed first. With a stun in the stack (`stack_has_stun`) a gunfire or lost-hostile lead inside a room an entry doorway leads into is no longer a `leads` option (INVESTIGATE would move there and the entry
guard would turn it into a quiet entry: the bang is the entry's to weigh). Without one the leads are as before.

**Posture** words appear only when someone is not standing, so a standing body's text is byte-identical (the `tools/von_scenarios` fixtures pin it): the
NPC's own in its situation line (" You are crouching.") and a *visible* contact's in its contact line ("crouched low"; a last-seen posture may be stale, so it is never shown for a remembered one). Test: `tests/ai/posture/posture_in_von_state_test.gd`.
`low_ammo_fraction` is a controller export pushed through `apply_config`. Room types are humanized ("kitchen_living" → "kitchen living").
