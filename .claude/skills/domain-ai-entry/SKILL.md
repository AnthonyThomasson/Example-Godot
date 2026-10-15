---
name: domain-ai-entry
description: Deep implementation detail for the AI TACTICAL ENTRY module (scenes/ai/behavior/entry.gd + the entry guard in behavior.gd) — how an NPC gets through a doorway into a room as police and soldiers do, alone or as one of a team over the radio: the phase machine (approach / stack / pie / bang / cross / corner / clear / cover / rear), the team radio steps (claim, ready, bang, going_in, in, clear, cover, rear, done, abort) and their heartbeat, the barrier and follow order, slicing the pie, crossing the fatal funnel without stopping, the corners (buttonhook, hard corner), clearing the room and holding it (covering the doorways on, rear security), the bang (a stun thrown in first), topping off at the stack, the last man facing back, a short room taking two, no crossing with a hostile in view, bodies on the way, commitment, the entry guard's detours and the pass-by securing of a doorway walked past, and the read-outs for the entry overlays. Use when editing entry.gd or Behavior's _entry_guard / _apply_entry / _finish_entry, or working on stacking, the pie, crossing, corners, room clearing, rear security, a stun entry, the entry guard or an NPC walking into an uncleared room; the spec and its tests are docs/tactical-entry.md (E1 to E17) and tests/ai/entry/. Complements `domain-ai-behavior`, `domain-ai-perception` (the doorway geometry, agent_entry.gd), `domain-ai-watch` and the `architecture` skill.
---

# AI · Tactical entry (`scenes/ai/behavior/entry.gd`, the entry guard in `behavior.gd`)

The spec and the tests are `docs/tactical-entry.md` (E1 to E17; the bang is also `docs/grenades.md` G18) and `tests/ai/entry/`
(the bang's fallbacks in `tests/ai/grenade/bang_fallback_*`). Von only chooses the doorway (the ENTER or STUN ENTRY tactic,
`domain-ai-decision`); the choreography is this phase machine, so it runs with the server down. The doorway geometry (stack slots,
pie arc, corners, capacity) and the team's claims off the radio are the perception's (`agent_entry.gd`, "Entry geometry" in
`domain-ai-perception`), read through the `AgentPerception` wrappers; the room is cleared by sight with `search_coverage.gd`
(`domain-ai-coverage`). The human's side of the same radio is `PlayerStack` (`domain-ai`).

## The module

`entry.gd` is a `RefCounted` built in `Behavior.setup`: `setup(loco, perception, coverage, eyes, combat)` captures the locomotion, the
perception, the room coverage, the watch module (where a walker looks) and the combat module (the tactical reload and the bang's throw);
`bind(character)` (from `Behavior.bind`) hands in the NPC's body once. `Behavior.apply_config()` copies the tunables in (below).
- `begin(params) -> bool` — start from an ENTER leaf's `opening`, `into`, `slot` and `bang`, or the guard's pass-by `secure`; false
  when the doorway is unknown (the leaf is dropped and the NPC re-decides). `step(delta) -> bool` — one tick; true once it is over.
- `abandon()` (radio `abort`), `reset()`, `committed()`, `take_calls()`, `way_blocked() -> bool`, `expects_burst(kind)` (all below).
- State read by `Behavior` and the overlays: `phase`, `opening`, `into`, `slot`, `side`, `solo`, `secure`, `secured`, `covering`, `bang`,
  `seen_fraction`, `pie_sides`, `corner`; `debug()` / `debug_view()` (the read-outs, below).
- Set by `Behavior` every tick from the watch stage (`_apply_entry`): `gaze_held` and `hostile_in_view` (below).

## The phases and the team

`Behavior` adopts an ENTER or STUN ENTRY leaf, starts the entry on the next tick (`_entry_pending`, then `begin(params)`: it reads
the doorway's geometry and the team off the perception, `entry_geometry` / `entry_team`) and then calls `step(delta)` each tick until it
reports done. Phases:
`approach` (to its stack slot: if on the wrong side of the door, out from the wall and across far out first; then to a
point past the slot and along the wall into it, so it never walks the door's axis close in), `stack` (in the slot facing
the door; radios `ready`), `pie` (the point — the lowest slot still waiting — walks the pie arc, at each step turning its
gaze through the door until it settles plus `entry_pie_dwell`, dropping room sample points (`SearchCoverage.sample_room`)
and corners it sees: `seen_fraction`, hidden corners; alone it then crosses in front, far out, and slices the other
side), `cross` (radios `going_in`; walks to its corner without stopping; `in` once past the wall plane and off the axis),
`corner` (holds it `entry_corner_dwell` looking across the room), `clear` (`SearchCoverage.begin/step`; radios `clear`
with `cleared_room` once the rest of the stack is in), `cover` (the room is held, guns on the doorways on, below), `rear`
(a member left over holds just inside the door it came by, facing out).

- **Holding the cleared room (E8).** `_finish` marks the room cleared, then reads the doorways on out of it into rooms not
  cleared (`entry_watch_doors(into, opening)`, outside doors and the door it came by left out) with a cover spot each:
  `COVER_DEPTH` back inside the cleared room, off the doorway's axis on the NPC's side, the gun aimed through it. With a
  team, each member claims the nearest doorway no teammate's `cover` call names (kept once its own; a tie goes to the lower
  instance id) and radios `cover` with `covering`; one left over (or, with no doorway on, the last one in) goes to `rear`,
  anyone else is done. Each member on the rear has a spot of its own (`_hold_rear_or_done`: by slot, the members take turns either
  side of the doorway just inside it, each pair `SPOT_SPACING` (44 px) further along the wall), so two never share one. The hold ends when a teammate seen holding (`cover` / `rear`) is no longer (it radioed `done`,
  `abort`, or claims another doorway), or after `entry_cover_time` (cover) / `rear_security_time` (rear); a member that
  held radios `done`. Alone, it turns its gaze through each doorway on in turn, `entry_watch_dwell` once settled, then is
  done. The heartbeat repeats the latest call whole, so `covering` and `cleared_room` stay on the radio.

- **The bang (E17, `docs/grenades.md` G18).** An ENTER or STUN ENTRY leaf with `bang: true` (and a stack that follows the first claimer's mode: every claim carries `bang` and the `stuns` the member carries; one
  `bang: false` makes the whole stack quiet) adds the `bang` phase between `stack` and `cross`. `_thrower(team)` picks the second of the stack if it carries a stun, else the lowest slot that does, from the claims, the same on every member;
  `_bang_due` (in `stack`, or in `approach` once the rest are ready) has the thrower plan the throw (`_plan_bang`: a target `BANG_DEPTHS` of the way into the room, on the doorway's axis first, and a spot, its own slot or
  `BANG_STEP_ALONG` in front of the door, `BANG_STEP_OUT` out from the wall, from which the lob is clear of the jamb with its hand `BANG_HAND_REACH` to its right and `BANG_EDGE_MARGIN` to spare: none = the bang is given up and the stack
  goes in quietly), radio `bang`, and every member that sees the call enters `bang`. In `bang`, the thrower walks out from its slot (clear of the member ahead of it) to the spot, throws through `Combat.begin_throw` / `throw_step` /
  `throw_released`, and walks back; everyone holds its slot turned away from the door (`_look_toward` away along the door's normal; the watch stage does not turn it to a threat in `bang`). On the stun's burst in the room (`AgentPerception.last_burst`)
  the stack is over the bang (`_bang_over`): the point crosses at once, no pie, and E14's hold on a hostile in view does not apply for `BANG_WINDOW` s; no top-off is waited for. A call not answered by a burst within `BANG_BURST_CAP`
  or never made within `BANG_CALL_CAP` gives the bang up, and so does a teammate's claim that says quiet (`bang` false: its thrower had no lob or lost its stun): a member in `stack` or in `bang`
  follows it at once, its own claims saying quiet too. Tests: `tests/ai/grenade/bang_fallback_*`. `Entry.expects_burst(kind)` makes `Behavior.set_evade` leave the stack to this hold while a stun is in the air; `committed()` is also true during the thrower's wind-up.
- **Top off at the stack (E11).** A member short of a full magazine with a spare swaps it in while `stack`ed, the one lull:
  `_topping_off` (entry.gd) calls `Combat.top_off` (a tactical reload: `select_slot(gun_slot())`, `reload()`) from `_tick_stack`
  before the point starts the pie or a follower crosses, and from `_tick_pie` before the point crosses (a pie that fired),
  standing still and waiting for the reload to end. Skipped while a hostile holds the entrant's eyes (`gaze_held`: it fires) and
  past `TOP_OFF_CAP` (8 s) per entry; never in `cross` (the watch stage's empty-gun reflex is off while committed too).
- **The last man faces back (E12).** In `stack` a member that is the last slot of a stack of three or more (`_covers_rear`:
  two or more others on the radio, every one with a lower slot) looks along the wall away from the door (`spot + along * side * 300`,
  at 3x `look_rate`) instead of at it, until the member ahead of it is through (`_turn_at`); then it looks at the door as every
  follower does. A threat in sight takes the eyes first (the watch stage).
- **A short room takes two (E13).** The doorway geometry's `capacity` (perception, `domain-ai-perception`) is 2 for a room with a side under
  `entry_short_room` (150 px). A member with that many claiming lower slots ahead of it (`_holds_outside`) stays in `stack` running `_tick_security`: still,
  facing back (E12), until the room is called clear by the team and a teammate that held it moves on (`_team_moved`) or
  `rear_time` has run out since, then radios `done`. It never crosses. Not held back once nobody ahead of it is on the radio and
  the room is not called clear (it takes the lead); gives up (`abort`) after `SECURITY_CAP` (30 s) with no clear call.
- **No crossing on a hostile in view (E14).** `Behavior._apply_entry` hands the entry `hostile_in_view` (`_hostile_in_view`: the watch
  stage's threat is seen now, or was within `watch_lost_gaze`, and `Combat.has_line_of_fire` holds: in range on a clear line, so it
  can be engaged from outside; a hostile seen over low cover with no line of fire holds nothing). While it is set the pie holds where it stands
  (no next step, no crossing; the watch stage fires), a follower does not cross after the member ahead, and nothing else changes: it
  crosses once the hostile is out of view. Whatever order brought the NPC to the doorway (ENTER, or a COMBAT advance / engage the
  entry guard sent through an entry) meets the same rule, because it is the entry's, not the order's. An NPC under fire still drops
  a detour and walks in (the guard's exemption).
- **Barrier and order.** The point crosses when every other claimant has radioed past `claim`, or `entry_ready_timeout`
  after it was ready (restarted when the stack grows). A follower crosses `entry_follow_gap` after the member ahead of
  it radioed `in`. A member still at `claim` once the one behind has waited the timeout is dropped from the order.
- **Corners.** Point: the door-wall corner on its own side (buttonhook); alone, the door-wall corner on the side away
  from where it ended the pie. Second: the hard corner on the other side. Later members: a spot inside off the axis, `SPOT_SPACING`
  apart.
- **Bodies on the way.** Every phase walks through `Locomotion.move_to`, so a member goes round a teammate at rest, stops short of
  one on its slot or spot and takes a free spot beside it (an approach waypoint counts as reached there too, `_loco.reached`), and gives
  way to a walking one. The crossing never stands in the funnel except while `Locomotion.holding()` (a body in its way). A walk a body
  seals and stays in re-plans (`Entry.way_blocked`, called by `Behavior._way_blocked` on `Locomotion.take_blocked`): the approach goes
  on to its next waypoint; with none left a member the stack keeps from its slot takes the back of the stack (`_to_back`: the slot
  behind the last claimed, radioed as a new claim; E2 goes by arrival), and with no slot to take gives the claim up (`abort`; `Behavior`
  re-decides with `resolve_reason()` "way blocked", or a detour hands the walk back to its order); a pie step is skipped; the thrower
  gives the bang up; a crossing waits out the first signal (the one ahead moves on into the room), then gives the entry up if still
  outside the wall plane, or takes its corner where it stands once through; a corner, cover or rear spot is held where it stands and
  the room is covered from there. An entrant walks all the way into its corner (`CORNER_REACH` 6 px): in a small room a corner
  a stride short sits in the doorway of the one crossing behind it. E13's capacity counts a member's place in the stack (how many
  claim a lower slot), not its slot's number, since a member that took the back leaves its old slot empty. A member back in `stack` stands where it was held (its place). Tests: `entry_held_walk_replans`,
  `stack_ai_goes_round_player_in_slot`.
- **Commitment.** `committed()` is true while crossing; the controller starts no decision then (a forced one waits),
  so a hit or a hostile seen in the doorway is fought once the NPC is through. Posture stands throughout, and it never
  runs, not even under fire: a running character cannot shoot, so a sprint to the stack or through the doorway would
  be a lowered gun at the worst moment (test `entry_never_runs`).
- **The radio.** Steps are queued (`take_calls()`, via `Behavior.take_entry_calls()`, which adds `opening`, `into`, `slot` and `side`) and the controller posts them;
  a human invader's `PlayerStack` (`ai/team/`, `domain-ai`) posts the same steps for the human, so the team counts it like an ally;
  the latest is repeated every 2 s so the claim stays live. Choosing anything else `abandon()`s the entry (radios
  `abort`). Each phase change is a `GameLog` line (`--verbose` in tests).
- **The entry guard (E9).** Entry is not only for an ENTER order: `Behavior._entry_guard()` runs every tick after the
  running primitive steered (a `move` not yet arrived, an `engage` and its repositions, an `interact` walk) and reads the walk the
  nav agent was just given (`Locomotion.path_ahead()`), not the order's destination. When the perception's `threshold_ahead()`
  finds a doorway on that walk into a room that is not cleared, within `entry_guard_range` (300 px of walking), it starts a
  **detour**: the order is stashed whole in `_resume`, `_primitive` becomes `entry` for that doorway (`_params` = opening +
  room; slot and side come from the radio as usual), and when the entry ends `_finish_entry()` puts the order back and refills
  its commit timer; the walk carries on from where the entry left the NPC, and meets the next uncleared doorway the same way.
  The labels and path of the order stay, so the status line still says what the NPC is after, with the entry's phase as progress.
  Exempt: `entry_guard` off, no `entry_enabled`, an NPC under fire, a leaf whose params say `entry_guard: false` (RETREAT), a
  `move` that has arrived, and a doorway whose entry was given up less than `entry_guard_rearm` s ago (`_guard_off`, on the
  guard's own clock). A new decision while a detour runs (`set_leaf`) replaces the paused order and leaves the entry
  running, unless it is one the guard does not apply to (`_guards(leaf)`: not a walk, a retreat, or under fire): then the
  detour is dropped and the entry abandoned (`abort` on the radio). Coming under fire before the crossing cancels the detour
  the same way (`_cancel_detour`); a crossing already under way is finished. A decision that was in flight when the NPC became
  committed to its own ENTER crossing is ignored (`set_leaf` returns) and the entry's end re-decides. `fallback()` (no decision to
  be had) abandons any entry. Tests: `tests/ai/entry/entry_guard_*_test.gd`, `entry_fallback_aborts`,
  `entry_decision_in_flight_during_cross`.
- **Doorways passed in a corridor (E15).** The same guard also looks for a doorway the walk goes **past** (`Perception.passing_ahead`:
  between two rooms of the house, into a room not cleared, the walk crosses its axis within 150 px of the wall and never enters it)
  nearer than any doorway it crosses, via `_passing_gate`, skipping one a teammate is working or that was just secured or given up.
  The detour is an `entry` with `secure: true`: `entry.gd` takes no team and radios nothing, stacks beside the jamb, slices one side of
  the pie (the watch stage fires at what it sees, E14 holds it on a hostile in view) and ends `secured` without crossing; `_finish_entry`
  then leaves the doorway alone for `entry_secure_time` (30 s, controller export). An ENTER order's own approach walk is guarded the same way
  (`_guard_approach`: the entry is abandoned, the doorway secured, the order restarts from `approach`), but not for a member heading for a
  stack others have claimed (`entry_team(opening)` is not empty): the team goes to its door as one. `_stash_order` keeps `entry_pending`
  so a paused ENTER starts afresh. Tests: `entry_guard_secures_passed_doorway` (scripted), `entry_corridor_doors_not_passed` (real Von).
- **Read-outs.** `Behavior.debug_entry()` (opening, into, slot, side, solo, secure, phase, seen_fraction, pie_sides, covering, watch_doors,
  hidden_corners, corner, stack_point, team, bang, bang_stage), also under `entry` in `debug_state()`;
  `Behavior.debug_entry_view()` (world-space: entry.gd `debug_view` — doorway frame, slots, pie arc and queue,
  corners with what the pie saw, role, waypoints, gaze, timers, the team off the radio, the doorways covered — plus the
  entry guard's detour, rearm list, look-ahead and the cleared rooms) for the entry debug overlays; the status line says the phase
  ("stacked at the door", "slicing the pie", "going in" ...).

## With the watch stage (`domain-ai-watch`)

Where the entrant looks is the entry's own (`_look_toward`, eased through the static `Watch.ease_gaze`; a walk looks down its path,
`_aim_travel` via `Watch.travel_point`), but the watch stage still runs after it every tick and has the last word: a threat in sight takes
the eyes and the gun in every phase but `bang` (the stack holds its slots turned away from the door for the stun, and the watch stage does
not turn it back). While the entry is `committed()` (the crossing, and the thrower's wind-up) the watch stage's empty-gun reflex
(`Combat.reload_if_dry`) is off. Two flags carry the stage's verdict back into the entry: `gaze_held` (a threat holds the eyes: a gaze step
the threat will not let settle counts as settled, so the pie does not wait on it) and `hostile_in_view` (`Behavior._hostile_in_view`: E14,
above).

## Exports (`GoalController`, group *Entry*)

`entry_ready_timeout`, `entry_follow_gap`, `entry_pie_dwell`, `entry_corner_dwell`, `rear_security_time`, `entry_cover_time`,
`entry_watch_dwell`, `entry_approach_time` → `Behavior` fields → `apply_config()` → `Entry` (`ready_timeout`, `follow_gap`, `pie_dwell`,
`corner_dwell`, `rear_time`, `cover_time`, `watch_dwell`, `approach_time`; `look_rate` is `search_look_rate`). `entry_enabled` (ENTER
offered, and the guard on) and the geometry's `entry_stack_spacing`, `entry_wall_standoff`, `entry_pie_radius`, `entry_pie_steps`,
`entry_corner_inset` and `entry_short_room` go to the perception. The guard's `entry_guard`, `entry_guard_range`, `entry_guard_rearm` and
`entry_secure_time` stay on `Behavior`.
