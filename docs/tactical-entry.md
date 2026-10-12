# Tactical entry

How an invader should get through an opening into a building, alone or as a team, and the real-world
tactics that rule is modelled on. This is a **specification, not yet implemented**: today an invader walks
the navmesh straight through the front doorway (`entrance` option in `snapshot/snapshot_options.gd`, a
plain `move`). The tests for the behaviours below are written first, left red and tagged `gap`
(`tools/run_tests.sh gap` lists them), following the convention of `docs/flanking-behavior.md`. The test
names under each behaviour are the planned ones. The work is tracked in the implementation ticket that
links this file (spike #18).

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

**E3. Slice the pie.** The first in the stack looks across the opening in angle steps from the stack
point, turning its gaze (not its body) to each, before it crosses. What it sees from outside it engages from
outside, and it notes the share of the room seen and which corners are still hidden. Why: it is the cheapest way
to learn the room, and the farthest the entrant ever is from a threat. Built on `visible_points` and the
search-coverage sweep.
Tests: `entry_pie_sees_room_from_outside`, `entry_pie_engages_from_outside`.

**E4. Never stop in the funnel.** Once an invader commits to crossing, it keeps moving until it is
through the threshold and off the door axis. It does not stop to aim, reload or re-decide in the threshold unless
it is hit. A hit while crossing finishes the crossing, then fights from the first position inside. Why: the one
thing every source forbids.
Tests: `entry_no_pause_in_threshold`, `entry_hit_in_threshold_clears_it`.

**E5. Take opposite corners, hard corner first.** Entering as a team, the point turns to the near
corner and the second crosses to the far corner, the hard corner among those still hidden after E3. They do not
take the same corner, and each turns its gaze across the room as it goes so the sectors interlock. Why: two
interlocking sectors cover the whole room and each other. Rooms where E3 saw every corner skip the hard-corner
step and the pair spreads to the two near ones.
Tests: `entry_pair_take_opposite_corners`, `entry_pair_hard_corner_first`.

**E6. Ready barrier and "going in".** The point does not cross until every invader in range holds its
slot (or a ready timeout runs out), and it radios that it is going in. Followers cross after it, one at a
time, not together. A member killed or without a path is dropped from the barrier at once. Why: a team that
trickles through the funnel is a series of solo entries; the radio is the team's only signal. The barrier is a
hold-until-ready, not a fixed delay.
Tests: `entry_waits_for_stack`, `entry_ready_timeout`, `entry_going_in_callout`.

**E7. Solo entry.** An invader with no ally in radio range runs the same sequence without a barrier or a
claimed slot: stage (E1), slice the pie from one side then the other (E3), and, if nothing is hostile in
view, one committed entry (E4) that goes directly to the hard corner (E5, alone) and clears the rest by sight.
It is slower than a team and takes more of the doorway's angle, but is never in the funnel longer than a team
member. Why: the same principles with nobody to cover it. An ally that comes into range mid-sequence is joined
at the next slot, not mid-crossing.
Tests: `entry_solo_pies_both_sides`, `entry_solo_commits_once`, `entry_ally_joins_stack`.

**E8. Clear, mark, move on.** When the corners and the room's points are seen, the room is marked cleared
(it feeds the existing *searched rooms* memory). One invader stays on the opening as rear security facing back
the way it came; the others take the next opening or unsearched room. A room whose door is past is never
passed without being searched or secured first. Why: a cleared room that is not marked is searched again; a
doorway left unwatched is a hole in the team's rear.
Tests: `entry_marks_room_cleared`, `entry_rear_security`.

## Situations

The two common room shapes, `#` wall, `D` opening, `S` stack slots outside (1 is the point), `p` the pie
stand-off, `H` hard corner, `c` soft corner.

```
 Centre-fed room: two hard corners          Corner-fed room: one hard corner

   H ############## H                          H ############# c
   #                #                         #               #
   #                #                         #               #
   #                #                         #               #
   c#####   D   #####c                        c ####### c######
       S3 S2 S1 p                                       D S1 p S2 S3
```

The stack waits on the wall side, `p` is a step toward the door, off its axis. In the corner-fed room the
stack forms on the wall side of the door so the point's first turn is toward the near corner.

## How the rules are enforced

None of this is enforced yet. The plan, in the order it is built:

- The AI receives the openings (`WorldGen.get_openings`), turned into per-opening geometry: the inward
  and outward normal, the threshold, the stack and pie points on either side and the corner types of the room
  behind it (E1 to E3).
- Von decides *whether and how* to enter (a new SEARCH-level ENTER tactic: stage, pie, enter, hold). The
  choreography is not Von's: stack, pie, cross, corners and clear are a phase machine in the behaviour
  sub-domain, driven by a role slot, so it works with the server down. Posture and run stay code-owned.
- Roles and the ready barrier travel on the callout radio (new statuses for entry steps; a role and an
  opening id in the payload), so a single invader and a team are the same code with a different number of
  members (E2, E6, E7).

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
