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
- `agent_snapshot.gd` — `build(rooms, goal, activity, known, callouts, knowledge) -> { facts, sections, sections_per_target,
  options, gun }`: the **facts** literal, the per-hostile loop (`_analyze`), and the assembly of the dict; `fill_goal(goal)`;
  `bind(character)` (from the perception's own `bind`) hands the NPC's body to it and to the vocabulary, the sections and the option
  groups, each holding it as `_character`, so none of their functions takes the character.
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

The face's `sense(rooms, goal, activity)` gathers the knowledge (contacts, callouts,
learned rooms/objects, lost hostiles) and hands it to `agent_snapshot.gd`'s
`build(rooms, goal, activity, known, callouts, knowledge)`, which assembles the snapshot
below from that knowledge + the tactics geometry. The author reads the memory and tactics modules
only; it writes no memory and holds no policy. Everything in this section and the wording rules below
lives in `agent_snapshot.gd`.

- **facts** — named booleans a `requires` or an entry rule can gate on: `threat_known`, `hostile_known`,
  `gun_loaded` (the gun it fights with, `Character.gun_slot()`, has rounds and is not mid-reload),
  `weapon_low` (at or below `low_ammo_fraction` of its magazine, empty included), `can_reload` (a carried magazine would add
  rounds), `under_fire`, `engaged`, `leads`, `lead_outside` (the NPC is inside the house and an offered lead lies outside it:
  gates the `stay` child of INVESTIGATE), `hurt`, `inside`, `exposed`, and the grenade ones: `grenade_ready` (some known hostile has a `grenade_throws` option),
  `stack_has_stun` (it carries a stun, or a teammate's entry callout says `stuns` > 0: gates STUN ENTRY), `ordered` (it holds a live order from its
  leader, `docs/leadership.md` LD5: gates the ORDER node and its entry rule). The brain overlay shows the ones that hold.
- **sections** — named state-text blocks; each tree level shows the ones it lists: `goal` (the controller's goal with `{gun}` filled in by `fill_goal`, the same noun as `loadout`),
  `situation` (place, item, own health as its own sentence), `current` (activity line), `odds`
  (hostiles vs allies; "All quiet so far." only when there are no leads), `contacts`, `exposure`
  (clear shot / exposed to their fire / behind cover / line blocked, plus other hostiles that can see
  you), `allies` (each ally's side of the target + their radio callouts), `flanks` (one-line digest),
  `loadout` (then "You carry a frag grenade and a stun grenade." for the grenades carried; the gun in bands, never round counts: "Your pistol is loaded." / "…nearly empty." / "…empty.", then
  once it runs low "You carry spare magazines." or "You are out of spare magazines."; "You are reloading your pistol.";
  empty without a gun; the noun is the gun's display name lower-cased, `gun_noun` ("pistol", "assault rifle", an acronym like "SMG" kept), so a
  pistol user's text is unchanged and the Von scenario fixtures stay valid; listed in the contexts of root, combat, engage, flank, advance), `awareness` (being hit / under fire; gunfire and footsteps heard only while no hostile is known; noted events).
  `order` (`order_text`, LD6): one sentence while the NPC holds an order, "Your leader ordered you to defend the kitchen." / "... to go into the
  kitchen by its doorway quietly." ("with a stun grenade first"), "" otherwise; the planner shows it after the goal at every level, so an NPC
  with no order reads exactly what it read before. Measured with `tools/von_probe.py` (`docs/leadership.md` LD6: at the combat levels the top
  pick unchanged in 17/18 levels for the defend sentence, 18/18 for the stack ones).
  `sections_per_target[id]` re-frames exposure/flanks/allies around each known hostile. The snapshot also carries `gun` (that noun), which the planner
  fills into `{gun}` in the tree's templates. `shoot_range` and the "in pistol range" distance band are deliberately left gun-agnostic (pinned wording).
- **options** — named groups `{ summary, summary_inside?, options: [{ id, label, desc, params, tags }] }`:
  `threat` (summary only), `hostiles` (bind: one per hostile, only DISTINGUISHING facts), per target
  `fire_positions` (where you stand, firing spots around the target named by place and cover — "behind
  the sofa in the kitchen", "the hallway, north of them" — with their route, and an ambush),
  `flank_sides` (tagged `held` when an ally — seen or radioed — holds it, `crosses` when the route
  there passes a known hostile; described as "route passes X"), `advance_positions` (halfway / close /
  rush), `melee` (one `punch` option, only while the target is point-blank); globally
  `reload` (one option, only while `can_reload`, so the planner takes it unasked), `retreat_positions`, `shooter` (LOCATE's `toward_shots`, under
  fire with no hostile known; empty when the line back from the newest shot, `shot_from`, runs into a room the NPC is not in: it does not walk into a
  barricaded shooter, issue #51 R10, and GRENADE at the shots' origin or RETREAT stand instead), `leads`
  (last seen, where they were heading, gunfire heard, footsteps heard, unseen shooter, support an ally; each says WHERE it is in the canonical
  `SnapshotVocab.place`/`where` words, "in the kitchen" / "outside the house", and the awareness section says it of heard gunfire too, so the
  NPC's goal can be weighed against it). LOCATE (the walk to where the shots came from) and a RETREAT spot are not offered when their walk
  would end where the NPC already stands or on a character it knows of (issue #51 R12, `docs/tactical-entry.md` E9): `shooter` is empty, and
  the `lead_shooter` lead left out, when the point toward the shots is where the NPC stands (`AgentTactics.where_it_stands`: the walk to its
  navmesh point is under a `STRIDE`, 32 px; shots from beyond the walkable ground), and the retreat spots are screened in `agent_tactics.gd`
  (`domain-ai-perception`, Tactics). Other leads lie at fixed points and reaching one spends it (`check_lead`). `entries` (the doorways
  ENTER offers, `entry_enabled` only: out of the NPC's area into a room unseen — named by direction — or unsearched,
  nearest first; the place is the NPC's free stack slot on the side it would stack on (the team's, or its own when the way there crosses the doorway's view, E19), `params` carry `opening`, `into`, `slot`,
  `side`; the summary is the nearest one's desc), `search_rooms` (+ front entrance / approach the house while outside;
  with entries, the rooms they lead into and the entrance are left to ENTER), `explore` (unknown rooms by direction
  only, minus those an entry leads into),
  `interactions` (deduped by label, uncapped), `rooms` (uncapped). The other groups are capped at `max_options_per_level`
  (`explore` at two).
  `order` (`order_group`, LD6): the ORDER node's one option, the live order, carrying its own `primitive` and params with `order_id`:
  `defend_<room>` runs `defend` (`room`, `spot`, `door`, `door_pos` from `AgentEntry.defend_spot`, the member's place being its index in
  the order's `to`), `stack_<opening>` runs `entry` (`opening`, `into`, `bang`, `split`, `stack_at`); empty with no order or one it cannot
  carry out (a room or doorway it does not know: the controller ends it `refused`).
  Options are places and things, never verbs; `tags.inside` drives the territorial filter. After the groups are built `tag_rooms` tags every
  option that names a place with the room it lies in (`tags.room`: the room key of its `from`, else its `point`; "" outside): the planner's
  `confine_room` keeps a member ordered to defend a room to the options in it (LD8). Tags are not text.


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
(`line.clear` false: "frag X behind their cover", group `situation` "Your line to X is blocked") or lies in a room the NPC is outside of (`_held_room`, issue #51 R7: "frag X in the kitchen",
`situation` "X holds a room you are outside of", `held_room` the room, and the exposure section adds "X holds the kitchen, a room you are outside of." before the throw sentence), within that kind's throw range (`AgentThrow.range_of`, off the grenade carried) with a clear lob from the thrower's hand (`AgentThrow.can_lob`), judged per kind, from where the NPC stands or else
from a **throw spot** a short walk away (`_throw_option(ctx, kind, spot, target_id, keep_out, walk)` asks `AgentTactics.throw_spot` within `AgentThrow.reach_of`, never inside `keep_out`, the room the
hostile holds, with `_throw_walk` as its route: the walked route (`AgentEntry.walk_route`, E18) and `detour`, whether the entry guard would stop it, a threshold into an uncleared room or a
doorway view with no way round, so a spot whose walk needs none is preferred; issue #51 R13); `params` `point` (the spot), `kind`, `radius`, `slot`, `target_id`, `from` (where it throws from: the throw spot, or where it stands) and `walk` (`from` is a throw
spot); the option keeps `route_len` (the walk), its desc adds " — from the hallway to the east, short route" (`_throw_from_text`) and the group's summary says "within throwing range from a spot
nearby" when every option needs the walk, "within throwing range" otherwise (`_throw_reach_text`; measured: the walk's words change nothing, `docs/grenades.md` G17); `tags` `ally_in_blast` (a known ally, seen or on the radio, in the
grenade's danger zone at the spot: `AgentThrow.in_zone`), `no_safe_spot` (the NPC itself is in the zone standing **at `from`** and `AgentThrow.escape` from there finds no spot or cover within the fuse) which the tree's `grenade` node drops by, and `inside` (`_throw_option`, shared).
`debug_zones()` (`ZoneList`) lists every throw weighed, dropped ones too, as zones of category `grenade` with `from`. A throw spot is worked out once per decision for a burst spot,
reach and room kept out of (`_throw_spots`, cleared by `SnapshotOptions.begin()`, which `build()` calls): a frag and a stun of the same reach share it.
Globally, `grenade_throws` is also `shots_grenade_group` (R10): with no hostile known and under fire, a throw per kind onto the stretch, inside the first room along it the NPC is
outside of, of a `shot_from` line (`AgentSuspicion.shot_line`: from where it leaves the room the shot landed in; `_shots_aim`: the point nearest its middle, `SHOT_AIM_SHARES`, it can lob onto from where it stands, else, issue #51 R15, from a throw spot outside that room), `situation` "The shots came from a room you
are outside of"; the unseen-fire exposure then adds "The shots came from the kitchen, a room you are outside of. You can throw a stun grenade where the shots came from." The fact
`grenade_ready` holds for either. A group's `situation` fills the tree's `{situation}` (`domain-ai-decision`).
The exposure section says "You can throw a frag grenade onto their spot." for the options not dropped, and "X is blinded by a flash and cannot see you." for a hostile it caught in a stun's flash (`blind` on the contact, from
`AgentPerception.process_explosion`); the contact line, the `hostiles` option and the ADVANCE summary say "blinded by a flash", a blinded hostile has no `aim_text`, and the `hostiles` bind carries `blinded` (the clause
the ADVANCE desc's `{blinded}` is filled with). The `entries` options say what makes a room suspect instead of "unexplored"/"unsearched" (the perception's `AgentSuspicion.rooms_suspected`, room key ->
reason ids, worded by `SnapshotOptions.SUSPECT_PHRASES`, each fact its own phrase, in this order, docs/grenades.md G18; the entry reads the same reasons through `AgentPerception.room_suspicion`
to make any entry into a suspect room a bang one, E17): "gunfire heard there" (a `heard_gunfire` position inside the room), "footsteps heard there" (`heard_footsteps`, docs/hearing.md H1),
"shots at you came from there" (the `shot_from` line runs through the room), "an ally radioed a fight there" (a combat callout's `target_pos` in it), "a hostile seen going in" (a lost hostile last seen in it),
"a hostile lost by its doorway" (lost outside it within `AgentSuspicion.LOST_NEAR_DOOR` 150 px of one of its doorways) and "a hostile seen heading in" (lost moving, where it was heading inside it); such a doorway is listed first.
With a stun in the stack (`stack_has_stun`) none of those facts about a room an entry doorway leads into is a `leads` option: the lost hostile's last-seen and heading leads, gunfire and footsteps there, the
unseen-shooter lead whose `shot_from` line runs into it, an ally's support call whose `target_pos` is in it (the way into that room is an entry, ENTER / STUN ENTRY, whose option says why, and any entry into a suspect room is a bang
one, E17). Without one the leads are as before. The `leads` group also offers **footsteps heard** (`lead_footsteps_<cell>`: "footsteps heard to the west, in the kitchen — just now — short route"),
and the awareness section says "Footsteps heard to the west, in the kitchen, just now." beside gunfire, while no hostile is known.

**Route bands are the route walked (E18).** Every "short / medium / long route" in an option (`SnapshotOptions._route_len`) is the length of the route the NPC
will walk from where it stands, `AgentEntry.walk_route(...)["len"]`: the one that keeps out of the doorway views when it would take it (within
`door_avoid_ratio` x the plain route + `door_avoid_slack`), else the plain one. The controller starts no decision before the avoid map of the room the NPC
stands in is baked (`AgentPerception.routes_ready`). Test: `tests/ai/entry/entry_route_band_as_walked_test.gd`. The combat spots' `route_len` (`agent_tactics.gd`)
stay on the plain route.

**Posture** words appear only when someone is not standing, so a standing body's text is byte-identical (the `tools/von_scenarios` fixtures pin it): the
NPC's own in its situation line (" You are crouching.") and a *visible* contact's in its contact line ("crouched low"; a last-seen posture may be stale, so it is never shown for a remembered one). Test: `tests/ai/posture/posture_in_von_state_test.gd`.
`low_ammo_fraction` is a controller export pushed through `apply_config`. Room types are humanized ("kitchen_living" → "kitchen living").
