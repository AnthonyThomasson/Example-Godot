# Tactical entry

How an invader gets through an opening into a building, alone or as a team, and the real-world tactics
that rule is modelled on. Behaviours E1 to E9 are enforced; each has its tests
in `tests/ai/entry_*_test.gd` (`tools/run_tests.sh entry`), named under the behaviour, following the convention of
`docs/flanking-behavior.md`. They are scripted-Von
tests on the Terrace house of `tests/_ai/flank_maps.gd`, read through `tests/_ai/entry_probe.gd`.

An *opening* is a doorway in a wall (`WorldGen.get_openings`: `pos`, `width`, `front`/`exit`, the rooms it
joins). Doorways are open archways; there are no door objects yet (issue #21), so forced breaching is not
modelled (see *Not modelled*). The AI's side lives in `scenes/ai/`: `perception/` (what it knows of the
opening, `visible_points`), `decision/` (the ENTER tactic) and `behavior/` (the entry phases, `look_at` aim,
`search_coverage.gd` for clearing). See `domain-ai-perception`, `domain-ai-decision`, `domain-ai-behavior`
and `domain-ai-coverage`.

## The real-world tactics being simulated

**The fatal funnel.** The doorway and the strip just inside it is where an entrant is most exposed: a
shooter inside sees only that narrow gap and everyone passing through it, silhouetted. The overriding rule is
never to stop in it. Time spent in the threshold is the cost of every technique below.

**The stack.** The team lines up in single file beside the opening, against the wall, out of the line of sight
through the door. Position fixes the job: the first two enter and take opposite corners, the third follows and
covers what the first two have not, and the last man faces back and holds the hallway behind (and carries any
breaching charge). Three can clear a room; a fourth adds flexibility; two should enter alone only when there is
no choice.

**Three ways to enter.**
- *Dynamic entry*: speed, surprise and violence of action. The point man goes through without stopping.
  Sources give 5 to 6 seconds to clear an average room as a training target. Fast, but every operator is
  committed the instant they cross.
- *Limited penetration, "slicing the pie"*: before anyone crosses, an operator sweeps the opening in
  small angle steps from the side, exposing only the weapon and one eye, so most of the room (75% or more in
  one account) is seen from outside, and what is visible is engaged from outside. Only then does the team
  enter, and only to clear the corners that could not be seen. Slower, farther from any threat, and more time
  to decide.
- *Deliberate*: stage, gather information, then choose one of the above.

**Buttonhook and cross.** Entering a room, the first operator turns round the door jamb to the near
corner and clears the large part of the room as they enter; the second crosses the doorway to the far corner.
Together they take the two *points of domination* with interlocking sectors of fire so each covers the other's
back. Once started, the move is committed.

**Hard and soft corners.** A *soft* corner can be seen from the entry point; a *hard* corner cannot. A box room
fed at its centre has two hard corners, one fed at a corner has one. Entry is planned around the hard corners
because they are where an unseen threat can be. A room too small for the team is called short: only two enter,
the rest hold security outside.

**Moving through a building.** Stop, look and listen before a hallway junction and slice it before exposing
yourself. Two officers move by bounding: one covers from behind cover while the other advances to the next
position, then covers in turn; about 5 to 10 feet apart, offset so fields of fire stay clear, and 8 to 12 inches
off walls (a wall hug gives false cover, invites ricochet and carries sound). Every doorway passed is searched or
secured first, so nothing is left behind the team.

**Alone.** The training sources agree on the same principles for a single officer: stand off the frame, show
as little as possible, clear what you can from outside before crossing, never linger in the funnel, and prefer to
wait for backup when the risk is high. None gives a public step-by-step solo procedure. The solo behaviour
below (E7) is this game's adaptation of the team principles, not doctrine.

## Behaviours

**E1. Approach off the line of sight.** Heading for an opening, an invader does not walk down the line
that looks straight through it. It goes to a staging point beside the opening, on the outside of the wall and
clear of the doorway's view into the room, and arrives along the wall side, not across the door. Why: the
funnel is exposed to anyone inside; staging out of sight keeps surprise.
Tests: `entry_stages_beside_opening`, `entry_approach_off_door_axis`.

**E2. Stack beside the opening.** Several invaders heading for the same opening queue in single file on
the wall beside it, one slot each, ordered by arrival, each a body's width behind the one in front, none in the
doorway's line of sight. Slots are claimed over the radio (the same claim pattern as a flank side), so two
invaders never take the same one. Why: a stack is the formation every technique starts from; crowding the door
makes a target and blocks the point man.
Tests: `entry_stack_orders_slots`, `entry_stack_no_double_claim`.

**E3. Slice the pie.** The first in the stack walks a short arc outside the opening (`entry_pie_steps` points, 100 px from
the threshold, from 55° to 25° off the door's axis), turning its gaze through the doorway at each, before it crosses. What it sees from outside it engages from
outside, and it notes the share of the room seen and which corners are still hidden. Why: it is the cheapest way
to learn the room, and the farthest the entrant ever is from a threat. Built on `visible_points` and the
search-coverage sweep.
It fires in every phase, the approach and the stack as much as the pie (`docs/gaze-and-fire.md` W2); a threat in sight holds the
entrant's eyes there, and a pie step the gaze cannot settle on because of it counts as settled, so the entry still goes in.
Tests: `entry_pie_sees_room_from_outside`, `entry_pie_engages_from_outside`, `entry_guard_fires_from_outside`.

**E4. Never stop in the funnel.** Once an invader commits to crossing, it keeps moving until it is
through the threshold and off the door axis. It does not stop to aim, reload or re-decide in the threshold unless
it is hit. A hit while crossing finishes the crossing, then fights from the first position inside. Why: the one
thing every source forbids.
Nor does it run, there or on the way to the door: running lowers the gun.
Tests: `entry_no_pause_in_threshold`, `entry_hit_in_threshold_clears_it`, `entry_never_runs`.

**E5. Take opposite corners, hard corner first.** Entering as a team, the point turns to the near
corner on its own side and the second crosses to the door-wall corner on the other side, the hard corner. They do not
take the same corner, and each turns its gaze across the room as it goes so the sectors interlock. Why: two
interlocking sectors cover the whole room and each other.
Tests: `entry_pair_take_opposite_corners`, `entry_pair_hard_corner_first`.

**E6. Ready barrier and "going in".** The point does not cross until every invader in range holds its
slot (or a ready timeout runs out), and it radios that it is going in. Followers cross after it, one at a
time, not together. A member killed is dropped from the barrier at once; one that never arrives is dropped by the ready timeout (or gives
its own approach up after `entry_approach_time`). Why: a team that
trickles through the funnel is a series of solo entries; the radio is the team's only signal. The barrier is a
hold-until-ready, not a fixed delay.
Tests: `entry_waits_for_stack`, `entry_ready_timeout`, `entry_going_in_callout`.

**E7. Solo entry.** An invader with no ally in radio range runs the same sequence without a barrier (it still
claims slot 1 on the radio, so an ally that turns up joins its stack): stage (E1), slice the pie from one side then the other (E3), and, if nothing is hostile in
view, one committed entry (E4) that goes directly to the hard corner (E5, alone) and clears the rest by sight.
It is slower than a team and takes more of the doorway's angle, but is never in the funnel longer than a team
member. Why: the same principles with nobody to cover it. An ally that comes into range mid-sequence is joined
at the next slot, not mid-crossing.
Tests: `entry_solo_pies_both_sides`, `entry_solo_commits_once`, `entry_ally_joins_stack`,
`entry_solo_even_wall_goes_in` (a door with the same wall either side: crossing to the second side must not
send it back to the start).

**E8. Clear, mark, cover, move on.** When the corners and the room's points are seen, the room is marked cleared
(the `cleared_room` memory; the room's `visited_room` entry comes from standing in it). Then the team holds the room it has taken, guns on what it
has not: each member covers a different one of the room's doorways on into a room nobody has cleared (doors to outside
and the one they came in by do not count), standing back inside the cleared room off that doorway's axis with its gun
through it. A member left over, when there are more of them than such doorways, holds the doorway they came in by as rear
security, facing back the way it came; a room with no doorway on leaves only the last one in on the rear. The team holds
until one of them moves on (its next entry, or `entry_cover_time` without one), and then the rest go too. Alone, the
invader looks through each doorway on in turn before it moves on. Then they take the next opening or unsearched room. A
room whose door is past is never passed without being searched or secured first. Why: a cleared room that is not marked
is searched again; the doorways on are where the next threat comes from, and a doorway left unwatched is a hole in the
team's rear.
Tests: `entry_marks_room_cleared`, `entry_pair_covers_remaining_doors`, `entry_solo_covers_remaining_doors`,
`entry_cover_holds_until_team_moves`, `entry_rear_security`.

**E9. No unguarded thresholds.** A walk that would cross into a room that is not cleared goes in by tactical
entry, whatever order sent the NPC there: a search or explore, an investigation lead, closing in on or flanking a
hostile, the way to an object, the front entrance. And at every such doorway on the way, not only the last: sent two
doors deep, it enters by each. Within `entry_guard_range` (300 px of walking) of the doorway the walk is paused, the
entry runs (E1 to E8) and the walk then carries on from where the entry left the NPC. A room is cleared when an entry
into it ran to the end, when an ally radioed it clear, or when a search covered it by sight; walking through a room does
not clear it. Exempt: a retreat; an NPC under fire (one that began an entry gives it up and radios `abort`); and a
crossing already under way (E4). A decision made while the entry runs, such as a fight that began, replaces the walk
paused behind it and does not tear the entry down (the entrant fires at what it sees meanwhile, `docs/gaze-and-fire.md` W2). Why: E8's last sentence, "a room whose door is past is never passed
without being searched or secured first", and the plain walk through the funnel that skipping the entry is.
Tests: `entry_guard_explore`, `entry_guard_search_room`, `entry_guard_advance`, `entry_guard_cleared_room_free`,
`entry_guard_under_fire_exempt`, `entry_guard_retreat_exempt`; with `entry_fallback_aborts` (an entry is given up when
Von cannot be reached) and `entry_decision_in_flight_during_cross` (a decision already in flight waits for the crossing).

## Situations

The two common room shapes, `#` wall, `D` opening, `S` stack slots outside (1 is the point), `p` the pie
arc, `H` hard corner, `c` soft corner.

```
 Centre-fed room                             Corner-fed room

   c ############## c                          c ############## c
   #                #                          #                #
   #                #                          #                #
   # H            H #                          # H            H #
   #######   D   #####                         ###  D  ###########
              S1 S2 S3                                S1 S2 S3
            p                                       p
```

Hard and soft are judged as the definition above says, by sight from just outside the threshold: the far
corners are seen through the door and the two on the door's own wall are not, so both shapes have two hard
corners (the sources count one for a corner-fed room, whose short-side corner is a step from the jamb). The
stack forms on the side of the door with more wall to stand against (an even
wall: the side the point comes from), single file, slot 1 nearest the door. The pie arc runs from beside
the stack toward the door's axis, clear of the slots.

## How the rules are enforced

- **What the AI knows.** Main hands every NPC the house's openings (`WorldGen.get_openings`, through
  `MatchSpawner.bind_npc`; the test world does the same). Perception's `agent_entry.gd` turns each one,
  entered into one of the rooms it joins, into geometry: the door's outward normal and the axis along its
  wall (taken from the room edge it lies on; the data has none), the stack slots in single file on both
  sides, the pie arc, and the four corners of the room behind tagged hard or soft by a sight ray. Built
  once per opening and kept, since walls do not move.
- **What Von decides.** Whether to enter, and by which doorway. SEARCH offers a child **ENTER**
  (`decision_tree.gd`) beside its rooms and unexplored areas; its options are the `entries` group
  (`snapshot_options.gd`): the doorways out of the NPC's area into a room it has not seen or not searched
  lately, nearest first ("the doorway into the kitchen — unsearched — short route"). A room a doorway leads
  into is not also offered as a plain walk in. The wording was checked with `tools/von_probe.py`
  (`tools/von_scenarios/search_enter_*.json`, `enter_*.json`). Only invaders enter this way
  (`GoalController.entry_enabled`, on in `npc_invader.tscn`; test switch `ai.entry`).
- **The choreography.** The ENTER leaf runs the `entry` primitive, a phase machine in the behaviour
  sub-domain (`behavior/entry.gd`): approach (E1), stack (E2), pie (E3), cross (E4, E5), corner, clear
  (E8), cover (E8), rear (E8). It does not ask Von again on the cadence until the entry is over, so it runs with the server down (a forced decision
  still replaces it, or aborts it when Von is down).
  While crossing, the controller holds every decision (`Behavior.committed()`); a hit or a hostile seen
  in the doorway is acted on once the NPC is through. The room is cleared by sight with
  `search_coverage.gd`. Posture and running stay code-owned: it stands throughout and never runs, not even
  under fire, because a running character cannot shoot (test `entry_never_runs`).
- **The guard (E9).** `Behavior._entry_guard` (`behavior.gd`) runs after the running primitive has steered and reads the
  walk the nav agent was just given (`Locomotion.path_ahead()`), not the order's destination, so it sees every walk: a
  move, an engage or its repositions, the way to an object. Perception's `AgentEntry.threshold_ahead` finds the first
  doorway on it that leads into a room that is not cleared (`cleared_room` memory, written when an entry finishes, when an
  ally radios `cleared_room`, and when a search covers its room). The guard then stashes the order, runs an `entry`
  primitive for that doorway (the same one ENTER runs) and puts the order back when it ends. Exempt are the nodes that
  carry `entry_guard: false` (RETREAT) and an NPC under fire. `GoalController` exports `entry_guard`, `entry_guard_range`
  and `entry_guard_rearm` (test switch `ai.entry_guard`). It acts only where entry does, on invaders (`entry_enabled`).
- **The team.** Roles, readiness and progress travel on the callout radio: each step is a `callout` with
  `opening`, `slot`, `side` and `entry_step` (`claim`, `ready`, `going_in`, `in`, `clear` with
  `cleared_room`, `cover` with `covering` (the doorway on it watches), `rear`, `done`, `abort`), repeated whole every
  2 s so a claim stays live. A doorway on is claimed like a slot: the nearest one no teammate covers, and of two who
  claim one, the lower instance id keeps it. `done` ends a hold; a teammate still holding takes it as the team moving on. A slot is the lowest the radio
  leaves free; two members who claim the same slot on the same frame settle it by instance id (the flank
  side claim pattern). A single invader is a team of one: nobody else claims the doorway, so there is no
  barrier and the pie is sliced from both sides (E7).

Interpretations and the game's own rules, where the sources leave a choice:

- "Ordered by arrival" (E2) is the order of claims on the radio, not of bodies at the wall.
- The point is the lowest slot still waiting; a member that claimed a slot and never reached it is dropped
  once the member behind it has waited `entry_ready_timeout`. The wait restarts when someone new claims a
  slot (E6, E7).
- The point buttonhooks to the door-wall corner on its own side; the second crosses to the hard corner on
  the other side; a lone entrant goes to the door-wall corner on the side away from where it stands, so it
  crosses the room's front (E5, E7). Later members take a spot inside, off the axis.
- The room is radioed clear once the member that covered it sees the rest of the stack through; a member
  still taking its corner holds it before it accepts the call. The doorways on come before the rear: a pair in a
  room with two of them covers both and leaves the way it came unwatched (E8). A hold lasts until a teammate who was
  holding moves on, or at most `entry_cover_time` (8 s) on a doorway and `rear_security_time` (10 s) on the rear; a
  lone entrant looks through each doorway on for `entry_watch_dwell` (0.8 s) and has nobody to leave behind.
- A room crossed in a retreat or under fire is visited, not cleared: ENTER offers it again once the NPC is outside, and an
  entry the guard began there and gave up is not started again for `entry_guard_rearm` s. Search ranking still goes by
  `visited_room` (stood in it lately); the guard and ENTER go by `cleared_room`.

## Sources

How far each is to be trusted. Mixed quality; none is current doctrine, and no source found describes a solo
procedure.

- US Army CALL 97-20, [battle drill](https://www.globalsecurity.org/military/library/report/call/call_97-20_btldrill.htm):
  room-clearing roles for a four-man team, two men only in extreme circumstances (the stack, E2, E5). Primary,
  but read here through a search summary, not the page (the fetch failed), so check the wording.
- Police1, [Slicing the pie vs. button hook for room entry](https://www.police1.com/swat/slicing-the-pie-vs-button-hook-for-room-entry):
  the exposure and speed tradeoffs, 75% of the room seen from outside, the three-officer cell (E3, E5). Trade
  press by instructors.
- Police Magazine, [Down the corridors](https://www.policemag.com/articles/down-the-corridors): hallway
  bounding, 5 to 10 ft spacing, 8 to 12 in off walls, securing every doorway passed (E8, Not modelled). Trade
  press.
- Search results quoting a SWAT training deck and a milsim podcast, e.g.
  [Tactical Tuesday, dynamic room entry](https://tacticaltuesdaywithmodernmilsim.buzzsprout.com/1674331/13696651-tactical-tuesday-episode-twenty-six-dynamic-room-entry-surprise-speed-and-violence-of-action-part-one)
  and [SOFREP, room anatomy](https://sofrep.com/news/become-close-quarters-combat-master-room-anatomy-part-3/):
  the fatal funnel, buttonhook and cross, hard and soft corners, the 5 to 6 s benchmark, short rooms (E4,
  E5). Third-party; the benchmark is a training target, not a standard.
- Texas CTE, [Building Search exam](https://www.txcte.org/sites/default/files/resources/documents/Building%20Search%20Exam.docx):
  show only the weapon, one eye and a small part of the side, and do not enter a room that can be cleared
  without entering (E3). Course material, seen only as a search summary. The advice that a building search
  take at least two officers comes from a
  [PA police study guide](https://open-exam-prep.com/study-guides/pa-police-civil-service/patrol-operations-and-incident-response/crimes-in-progress-and-building-searches)
  (E7), a study aid and the weakest source here.
- [ALERRT Solo Officer Rapid Deployment](https://oklahoma.gov/cleet/training/cleet-training/2024-ne-region-classroom-courses/pryor/alerrt-solo-officer-rapid-deployment.html):
  confirms single-officer movement, threshold evaluation and room entry are taught; the public listing has
  titles only, no technique (E7).
- E4's "finish the crossing when hit", E6's ready timeout and E7's ally joining are this game's own rules,
  not sourced.

## Not modelled

Closed or locked doors, breaching, flashbangs and the dynamic-entry "shock" they give (blocked on doors, issue
#21). Stairs (bottom-up clearing, no leapfrogging). Mirrors and cameras under a door. Hallway bounding overwatch
and corner clearing outside a room. Verbal commands to non-combatants. A defender reacting to a stack at its door.
Entry speed is not tuned against the 5 to 6 second benchmark.
