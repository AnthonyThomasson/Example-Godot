# Tactical entry

How an invader gets through an opening into a building, alone or as a team, and the real-world tactics
that rule is modelled on. Behaviours E1 to E9, E11 to E19 are enforced; each has its tests
in `tests/ai/entry/` (`tools/run_tests.sh entry`; E16's in `tests/ai/stack/`), named under the behaviour, following the convention of
`docs/flanking-behavior.md`. They are tests on the Terrace house of
`tests/_ai/flank_maps.gd`, read through `tests/_ai/entry_probe.gd`.
E10 (the clear-time benchmark) is met and its test is green. E1 to E9 are scripted-Von tests. E10 to E16 are tests that run
the whole pipeline with the real Von server (`requires_von`, `--include-von --require-von`), as are E18's and E19's: the world gives the AI the situation
and the test judges what the shipped AI does with it; E15 and E18 also have scripted tests of their mechanism. A rule the AI does not
follow yet is written the same way before it is built: the behaviour here, and a test that is red on purpose and tagged `gap`
(`tools/run_tests.sh --include-von --require-von gap` lists them; none is open).

An *opening* is a doorway in a wall (`WorldGen.get_openings`: `pos`, `width`, `front`/`exit`, the rooms it
joins). Doorways are open archways; there are no door objects yet (issue #21), so forced breaching is not
modelled (see *Not modelled*). The AI's side lives in `scenes/ai/`: `perception/` (what it knows of the
opening, `visible_points`), `decision/` (the ENTER tactic) and `behavior/` (the entry phases and their aim in `entry.gd`,
`search_coverage.gd` for clearing). See `domain-ai-perception`, `domain-ai-decision`, `domain-ai-entry` (the entry phases),
`domain-ai-behavior` and `domain-ai-coverage`.

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
back. Once started, the move is committed. A team stacked on both sides of a door enters by the *criss-cross*: the
first man from each side crosses to the corner on the far side, one after the other, their paths crossing in the
doorway; who goes first and the order of the rest are this game's rules (E19).

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
the wall beside it, one slot each, ordered by arrival (the order of the claims on the radio: a member takes the lowest slot the claims it
has heard leave free), each clear of the one in front (`entry_stack_spacing`, 44 px: outside
the footprint a body on the next slot keeps clear around it, so no slot is a spot inside a teammate), none in the doorway's line of
sight. The file forms on one side of the door, unless a member would have to cross the doorway's view to get there (E19). A member walks round the teammates already in the stack (the human among them), stops short of one on its own slot and takes a
free spot beside it, and gives way to one walking (`domain-ai-behavior`, Locomotion). When a body seals the only way to where a phase
walks and stays, the member re-plans within a few seconds rather than waiting on it: on to its next point; one the stack itself keeps
from its slot takes the back of the stack (the slots go by arrival), and with no slot left gives the claim up (`abort`) and re-decides;
a pie step is skipped; a corner, cover or rear spot is held from where it stands. Slots are claimed over the radio (the same claim pattern as a flank side), so two
invaders never take the same one. Why: a stack is the formation every technique starts from; crowding the door
makes a target and blocks the point man.
Tests: `entry_stack_orders_slots`, `entry_stack_no_double_claim`, `entry_spots_clear_of_each_other`, `entry_team_no_bumping` (four invaders
placed as in a match, real Von: nobody walks into a teammate, standing or walking), `entry_held_walk_replans`, `stack_ai_goes_round_player_in_slot`
(a match built as `main.gd` builds one: the AI goes round the human standing in its slot).

**E3. Slice the pie.** The first in the stack walks a short arc outside the opening (`entry_pie_steps` points, 100 px from
the threshold, from 55° to 25° off the door's axis), turning its gaze through the doorway at each, before it crosses. What it sees from outside it engages from
outside, and it notes the share of the room seen and which corners are still hidden. Why: it is the cheapest way
to learn the room, and the farthest the entrant ever is from a threat. Built on `visible_points` and the
search-coverage sweep.
It fires in every phase, the approach and the stack as much as the pie (`docs/gaze-and-fire.md` W2); a threat in sight holds the
entrant's eyes there, and a pie step the gaze cannot settle on because of it counts as settled; with a line of fire to the hostile the pie then holds and nobody crosses (E14), and without one the entry goes on.
Tests: `entry_pie_sees_room_from_outside`, `entry_pie_engages_from_outside`, `entry_guard_fires_from_outside`.

**E4. Never stop in the funnel.** Once an invader commits to crossing, it keeps moving until it is
through the threshold and off the door axis. It does not stop to aim, reload or re-decide in the threshold unless
it is hit. A hit while crossing finishes the crossing, then fights from the first position inside. Why: the one
thing every source forbids.
Nor does it run, there or on the way to the door: running lowers the gun.
Tests: `entry_no_pause_in_threshold`, `entry_hit_in_threshold_clears_it`, `entry_never_runs`.

**E5. Take opposite corners, hard corner first.** Entering as a team, the point turns to the near
corner on its own side and the second crosses to the door-wall corner on the other side, the hard corner (a stack split across
the door criss-crosses instead: E19). They do not
take the same corner, and each turns its gaze across the room as it goes so the sectors interlock. Each walks all the way into its
corner: in a small room a corner a stride short stands in the doorway the next one crosses. Why: two
interlocking sectors cover the whole room and each other.
Tests: `entry_pair_take_opposite_corners`, `entry_pair_hard_corner_first`.

**E6. Ready barrier and "going in".** The point does not cross until every invader in range holds its
slot (or a ready timeout runs out), on either side of the door (the other side's front man of a split stack is ready once it has
sliced its half of the pie, E19), and it radios that it is going in. Followers cross after it, one at a
time, not together, each after the member ahead of it in the crossing order (on a split stack the sides take turns, E19). A member killed is dropped from the barrier at once; one that never arrives is dropped by the ready timeout (or gives
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
security, facing back the way it came, each at a spot of its own just inside it (taking turns either side of the doorway); a room with no doorway on leaves only the last one in on the rear. The team holds
until one of them moves on (its next entry, or `entry_cover_time` without one), and then the rest go too. Alone, the
invader looks through each doorway on in turn before it moves on. Then they take the next opening or unsearched room. A
room whose door is past is never passed without being searched or secured first. Why: a cleared room that is not marked
is searched again; the doorways on are where the next threat comes from, and a doorway left unwatched is a hole in the
team's rear.
Tests: `entry_marks_room_cleared`, `entry_pair_covers_remaining_doors`, `entry_solo_covers_remaining_doors`,
`entry_cover_holds_until_team_moves`, `entry_rear_security`, `entry_spots_clear_of_each_other`.

**E9. No unguarded thresholds.** A walk that would cross into a room that is not cleared goes in by tactical
entry, whatever order sent the NPC there: a search or explore, an investigation lead, closing in on or flanking a
hostile, the way to an object or to a throw spot (`docs/grenades.md` G17), the front entrance. And at every such doorway on the way, not only the last: sent two
doors deep, it enters by each. Within `entry_guard_range` (300 px of walking) of the doorway the walk is paused, the
entry runs (E1 to E8) and the walk then carries on from where the entry left the NPC. A room is cleared when an entry
into it ran to the end, when an ally radioed it clear, or when a search covered it by sight; walking through a room does
not clear it. Exempt: a retreat; an NPC under fire (one that began an entry gives it up and radios `abort`); and a
crossing already under way (E4). *(issue #51, R10.)* The under-fire exemption does not cover a walk into the room the shots came
from: shot at from a room it is outside of (the line back from the shot, `shot_from`, runs into it, counted from where it leaves the room the shot
landed in: that room is only where the NPC stood), whether it sees the shooter or not, the NPC
does not walk in through that doorway unguarded. It fights from outside (E14), GRENADE is offered (G17: at the hostile it sees there, or, unseen,
where the shots came from), LOCATE is not offered toward that room (GRENADE at the shots' origin, or RETREAT, instead; LOCATE stays for shots from the
open or from the room the NPC is in), and any walk in (a rush, an advance) stops at the doorway as an entry, a bang one when the stack carries a stun
(E17: the room is suspect); an entry into that room is not given up for the shots, and a decision made under fire leaves it running. The room
counts as suspect (`docs/grenades.md` G18: "shots at you came from there"). The exemption stays for shots from anywhere else. Why: the shooter is
a barricaded hostile, and walking through its doorway under its fire is the funnel at its worst. A decision made while the entry runs, such as a fight that began, replaces the walk
paused behind it and does not tear the entry down (the entrant fires at what it sees meanwhile, `docs/gaze-and-fire.md` W2). Why: E8's last sentence, "a room whose door is past is never passed
without being searched or secured first", and the plain walk through the funnel that skipping the entry is. *(Issue #51, R12.)* Whatever the room, LOCATE (the walk
to where the shots came from, also offered as the "where the shots came from" lead) and a RETREAT spot are not offered when their walk would end where
the NPC already stands (within a stride, 32 px of walking) or on a character it knows of: shots from beyond the walkable ground give no LOCATE (the
navmesh pulls the point back to the NPC), a cover spot off the navmesh is judged where its walk ends, and falling back to an ally is to a spot beside
it, behind it from the threat, not onto its body. A RETREAT takes the NPC out of sight of every threat when it stands in sight of one, else at least a
stride farther from them. Other leads need no such rule: they lie at fixed points, and reaching one spends it. Why: a move that ends the tick it
begins leaves the situation as it was, so the same order is offered and taken again, every other frame. Nor is adopting an order news: the
NPC re-decides at once when what it believes of hostiles changes (one spotted, lost or newly hostile, or the one it fights crossing the house's
boundary), and the order it has just adopted, setting or clearing the hostile it fights, is not such a change, so it starts no decision of its own.
Tests: `entry_guard_explore`, `entry_guard_search_room`, `entry_guard_advance`, `entry_guard_cleared_room_free`,
`entry_guard_under_fire_exempt` (shot at from behind, in the garden: straight through), `entry_guard_shot_from_room_ahead` (shot at from the
kitchen it is ordered to rush: fights from outside, in only by entry), `entry_guard_landing_room_not_the_shots` (shot at in the kitchen from the
living room, then in the hall: straight back into the kitchen; scripted), `entry_guard_retreat_exempt`, `ai/grenade/stun_entry_shot_from_room`
(R10, unseen shooter, real Von), `ai/combat/locate_not_into_shots_room` / `locate_toward_shots_from_open` (no LOCATE toward the shots' room, LOCATE
toward shots from the open; scripted), `entry_guard_bang_suspect_room` / `entry_guard_quiet_unsuspected_room` (a guard's entry into a suspect room
goes in with a bang, into an unsuspected one quietly; scripted), `ai/combat/retreat_never_where_it_stands` (falling back to an ally it stands
beside: a spot behind the ally, once), `ai/combat/locate_never_where_it_stands` (shot at from beyond the garden's walkable edge: no LOCATE onto
its own spot), `ai/combat/retreat_out_of_sight_goes_farther` (out of sight of the shots: no retreat nearer them) and
`ai/decision/adopt_target_no_redecide` (an order on a hostile in sight is adopted: no decision forced in the second after) (R12; scripted); with `entry_fallback_aborts` (an entry is given up when
Von cannot be reached) and `entry_decision_in_flight_during_cross` (a decision already in flight waits for the crossing).

**E10. Clear an average room within the benchmark.** From the point's `going_in` to the `clear` call a team takes 6 s
at most, the 5 to 6 second training target for an average room. Why: speed is the dynamic entry's protection; a team
that lingers in a half-cleared room is a team in the open.
Test: `entry_clear_within_benchmark` (a pair, the furnished kitchen; real Von, `requires_von`).

**E11. Reload at the stack, never in the funnel.** An entrant crosses with a topped-off gun: a magazine part spent is
swapped for a full one while it is stacked, the one lull before the crossing, and never in the threshold or the room
just taken. Why: doctrine starts an entry with a full magazine, and a reload in the fatal funnel is a stopped, unarmed
body in the one place it must not stop (E4). In the code, a stack member short of a full magazine with a spare to swap in
(`Combat.top_off`, a tactical reload) stands still and reloads from `stack`, before the point starts the pie or a follower
crosses, and again after the pie before the point crosses (a pie that fired); it waits for the reload to end. Not while a
hostile holds its eyes (it fires instead, E14), and not for more than `TOP_OFF_CAP` (8 s) in one entry. Nothing reloads in
`cross`. A gun that is already full costs no time.
Test: `entry_reloads_before_crossing` (7 of 12 rounds, above the band Von calls low, so only the entry has a reason to
reload; real Von, `requires_von`).

**E12. The last man covers the rear of the stack.** While the stack waits at the door, the last slot faces back the way
the team came and holds the approach; the point and the second face the door. Why: the stack's rear is its blind side
(the "The stack" paragraph above: the last man faces back and holds the hallway behind). In the code, the last slot of a
stack of three or more (`Entry._covers_rear`: the last of its side's file, with two or more crossing ahead of it) turns its gaze
along the wall away from the door, the line the team came by, from `stack` until the member ahead of it is through; then
it turns to cross in its turn (a threat in sight still takes its eyes first, `docs/gaze-and-fire.md`). A stack of two has no
rear guard, and the last man in the room still takes the rear watch there (E8). A stack split across the door (E19) has a rear guard
per side: the last of each side's file that is not one of the two front men.
Test: `entry_stack_last_covers_rear` (three invaders in the garden; real Von, `requires_von`).

**E13. Short room: two go in, the rest hold outside.** A room too small for the team is entered by two, who take its
corners; the later slots hold the stack side as security and never step into the doorway. The game's rule for "too
small": a room under 150 px on either side (three bodies), whose door wall cannot hold a third corner. Why: a third
body in a box room has no point of domination to take and blocks the two who do. In the code, the doorway's geometry
carries a `capacity` (`AgentEntry.geometry`: 2 for a room with a side under `short_room`, the controller's
`entry_short_room`; else every slot). A member with that many ahead of it in the crossing order (both sides of a split stack, E19) stays in `stack` (`Entry._holds_outside`,
`_tick_security`), facing back along the line (E12), while the two ahead are still on the radio and after the room is
called clear, and radios `done` once a teammate that held the room has moved on (or `rear_security_time` after the call).
It does not stand in for the two: with nobody ahead and the room not called clear (they died or gave up) it takes the lead,
and it gives up after 30 s with the room never called clear.
Test: `entry_short_room_two_go_in` (the box room of `flank_maps.gd`; three invaders in its corridor, real Von,
`requires_von`).

**E14. Engage from outside; no crossing on a hostile in view.** A hostile seen through the door is fought from outside,
and nobody crosses while it stands in view, whatever tactic is chosen for the fight. Why: what is visible is engaged
from outside, a room that can be cleared without entering is not entered, and a known gun on the door is the funnel at
its worst (E3, E7's "if nothing is hostile in view"). In the code, `Behavior` tells the entry when a hostile is in view (the
threat holding the NPC's eyes is seen now, or was within `watch_lost_gaze`, 2 s, and there is a line of fire to it, within
range and with a clear line, so it can be engaged from outside: `Entry.hostile_in_view`; a hostile seen over low cover with no
line of fire gives nothing to engage from outside, and does not hold the entry). The pie then stops where it is (the point neither walks on to the next step nor crosses), a follower
does not cross after the member ahead, and the watch stage fires; the entry goes on, and crosses, once the hostile is out
of view. This holds whatever order brought the NPC to the door: the ENTER tactic, or a COMBAT advance or engage whose walk the
entry guard (E9) turns into an entry. Under fire from the room it is about to enter, it holds outside like any other time (E9);
under fire from anywhere else it still gives a detour up and walks straight in (E9's exemption). For `BANG_WINDOW` (3 s) after a stun or frag its own team threw went off in the
room, the hold does not apply (E17).
Tests: `entry_hostile_in_view_holds_outside` (a defender that cannot be killed, in view from the pie arc; real Von,
`requires_von`), `entry_guard_shot_from_room_ahead` (the same under its fire, scripted).

**E15. A doorway view a walk has to cross is secured first.** When the only way (E18) crosses the view of an open doorway into a
room not clear for passing, the NPC covers the doorway with its gun from beside the jamb before it is in the view, then crosses
the view in one go without stopping, and never goes in. Why: a door left open behind or beside the team is a threat on its
side (E8's last sentence), and a view crossed at a run is crossed once. In the code the entry guard looks for the doorway views a
walk goes **into** without entering the room behind them (`AgentEntry.passing_ahead`, `Behavior._passing_gate`): the walk comes
from outside the view of a doorway (E18) into it within `entry_guard_range`, however far out from the wall, inside the house or
out, at an exterior door too. The view of a doorway of a room the walk goes into (by any of the room's doors) is left to E9, whose entry clears that room and
covers its doorways (E8), and so is the room the NPC stands in. The NPC then secures it: an `entry` run in `secure` mode stacks beside the jamb on the side it comes from,
slices one side of the pie with its gun on the doorway (so it fires at what it sees, E3, and holds on a hostile in view, E14),
and walks on across the view, the doorway left alone for `entry_secure_time` (30 s). It never crosses the doorway and says
nothing on the radio (no claim, no going in), and it is not started for a doorway a teammate is working. A walk to a doorway's own
stack (an ENTER order, `_guard_approach`) secures the doors it passes the same way; a member heading for a stack that others have
claimed does not (the team goes to its door as one, so the point is not left to go in alone). Exempt, as in E9: a retreat, an NPC
under fire, and the doorway it is entering itself. Left open: a team passing a door on the way to its own is not made to secure it.
Tests: `entry_secure_exterior_door_then_cross` (no way round the front door's view: it covers the door from the jamb, crosses
without stopping, never goes in; real Von), `entry_pass_far_out_secured` (the view crossed 300 px out from its wall; real Von),
`entry_corridor_doors_not_passed` (gunfire heard in the far room of the corridor spine draws the invader past two open
doors; real Von, `requires_von`), `entry_guard_secures_passed_doorway` (the same walk as a plain investigation, scripted Von: both
doors covered from beside the jamb, neither entered, nothing claimed on the radio), `entry_guard_enter_walk_secures_passed_doorway`
(an ENTER order for room C: each door secured once, then C stacked and entered) and
`entry_guard_enter_walk_with_team_keeps_together` (an ally has claimed C's stack: nothing secured on the way).

**E16. The human stacks up with the team.** A human invader near the doorway an AI team is stacking at is one of the
team. Its place is reserved over the radio like an NPC's claim: the first free slot, on the side the team stacks on (on the side the human
stands on when its way to the team's side would cross the doorway's view: a split stack, E19), kept
for as long as the human stays near (`PlayerStack.reserve_range`, 300 px of walking, as the entry guard; dropped beyond 1.5 times
that); an AI that claims the doorway later takes a slot behind it. The human is never ordered: its radio step is read from
where it stands (`claim` away from the slot, `ready` in it, `going_in` in the doorway, `in` once through). The AI's own
rules then do the rest: the point waits for the human at the ready barrier (E6, up to `entry_ready_timeout`), a lone AI
with a human near is a team of two and slices only its own side (E7), and an AI behind the human crosses after the human's
`in` (the follow gap). A human who does not follow is not waited for for ever: once the AI ahead is through and the human
has not crossed within `PlayerStack.go_timeout` (6 s), its claim is withdrawn (`abort`), the marker goes and the AI behind goes
in. After the entry the AI's corner, clear and cover roles ignore the human. The floor shows it: every slot of the doorway
numbered in the order they were claimed, each where it stands (on both sides of the door when the stack is split), the human's own
highlighted, the AI's dimmer (`scenes/ui/hud/stack_markers.gd`). Only invaders enter, so only a
human invader is ever offered a slot. Why: a stack is a formation the human can only join if it can see where it forms and the
team can count on it to be there; the number says how many go in ahead.
Tests: `stack_ai_goes_round_player_in_slot`, `stack_player_reserved_slot`, `stack_player_keeps_slot_late_ai_behind`, `stack_far_player_ignored`,
`stack_point_waits_for_player`, `stack_point_goes_when_player_ready`, `stack_follower_waits_for_player`,
`stack_player_idle_withdrawn`, `stack_player_leaving_withdraws`, `stack_defender_player_none`, `stack_player_slot_von` (the real
Von server; `tools/run_tests.sh stack --include-von`), `ui/stack_markers_draw`, `general/stack_player_wiring`.

**E17. A stun before the crossing (the bang entry, `docs/grenades.md` G18).** A stack that carries a stun grenade and has a reason to
think a hostile is in the room (gunfire or footsteps heard there, shot at from it, an ally's fight in it, a hostile seen going in, lost
by its doorway or heading in: G18's suspect room) goes in with a bang, whatever brought it to the doorway: STUN ENTRY, an ENTER (run, and named, as
the STUN ENTRY it is) or a walk the entry guard turned into an entry (E9); the
mode is the first claimer's and every claim on the radio repeats it (`bang`, with the stuns the member carries), so the stack goes in
all one way (one member giving the bang up makes it quiet for all: its claims say `bang_off`, and nothing turns that stack back).
**A late reason turns a quiet entry** *(issue #51, R11)*. While nobody has crossed (approach, stack, the pie) and the stack carries a stun, a
reason to suspect the room (one that comes up after the entry began, or one a member knows when it joins a quiet stack, or a stun that joins the
stack; read every `SUSPECT_EVERY` 0.25 s) turns the quiet entry into a bang: the member's
claims say bang, and a teammate whose claims said quiet follows as soon as it hears that (the whole stack goes in one way, as above); a
point slicing the pie goes back to its slot to hold for the bang. Then the thrower throws as below, with the same fallbacks. Not once anyone
is crossing (`going_in` or through): a member that turned waits for the rest to follow (it holds for the bang, no pie, until their claims say
so too) and gives the bang up if one goes in quietly first.
**A quiet stack listens first** *(issue #51, R17)*. A quiet entry whose stack carries a stun holds at the stack `entry_listen_time` (3 s, a
`GoalController` export) from the point getting to its slot before the point slices the pie, so a late reason (above) has time to arrive; a hostile
in view (E14) or coming under fire ends the hold early, and it is not taken up again in that entry. A stack without a stun, one that gave the bang
up or one already over a burst does not hold. Why: a team about to open a door listens at it first, and a reason heard then is a stun put in
rather than a room walked into.
**The thrower is committed to the bang** *(issue #51, R16)*. From its `bang` call until the stun leaves its hand (the walk out to its spot, the
stun taken in hand, the wind-up) the thrower starts and adopts no new decision, as a member crossing does (E4): a hostile seen on the walk out or in
the wind-up does not make it leave. It throws, then decides again from where it stands (a decision that came back meanwhile is taken again the
moment the stun is away). `BANG_BURST_CAP`, the stun lost, a walk to its spot with no way through and the thrower killed still end it. A member that
leaves the stack for a fight does not cancel the bang (its `abort` takes it off the stack), and in the `bang` phase any stun its own team threw that
goes off in the room counts as the bang (one thrown by GRENADE included): the members still at the door go in on it (R8, below). Why: a stun
half-thrown is the worst of both, a lowered gun with nothing gained, and the team in the stack is waiting on it.
**Go in on the burst** *(issue #51, R8)*. Not only the bang's own stun: once a stun or frag its own team threw (the NPC or an ally) goes off in the
room, an entry into it that nobody of it has crossed yet (approach, stack, the pie), or one that begins within `BANG_WINDOW` (3 s) of the burst (a
GRENADE thrown into the room, then the walk in), goes in on it: the point does not slice the pie (or stops slicing it) and crosses from where it
stands as soon as the stack is ready (E6), without waiting on a top-off (E11), the rest follow as in E6, and for `BANG_WINDOW` after the burst the
E14 hold on a hostile in view does not apply. A quiet entry that went in on a burst does not turn into a bang. Why: whoever is in the room is blind
and deaf, or down, for a moment, and that moment is the entry's.
Why: a stack hears the room as it lines up, and a team that hears someone behind the door it is about to open puts a stun in first. The stack forms as in E1 and E2 (split across the door when it must
be, E19: neither front man then slices the pie). Once it is ready, the **thrower**
(the second of the stack, by slot on either side, if it carries a stun, else the lowest slot that does; alone, itself) radios `bang`, steps out in front of the
door's edge, throws the stun to the room's far side through the doorway (in a room deeper than a stun reaches, as far in as it reaches) and comes back to its slot; every member holds its slot
turned away from the door (phase `bang`, nobody looks at a threat in the doorway) until the stun goes off. The point does not slice
the pie (E3): on the burst it crosses at once (E4), and the rest follow as in E6; for `BANG_WINDOW` (3 s) after it the E14 hold on a
hostile in view does not apply, as whoever is in the doorway is blind and deaf. With no stun left, no clear lob into the room (from
the thrower's hand, clear of the jamb), a thrower that is not ready within `BANG_CALL_CAP` (8 s) or a stun that does not go off within
`BANG_BURST_CAP` (5 s) of the call, the stack goes in quietly. Why: a stun grenade is how real teams take a room they think is
occupied, and the entrants go in the moment it goes off; the stack stays beside the wall, out of the burst's line, turned away from the
flash. Tests: `ai/grenade/stun_entry_suspect_room`, `quiet_entry_unsuspected_room`, `stun_entry_ally_radioed`, `stun_entry_hostile_lost_near_door`,
`stun_entry_footsteps_heard` (the steps heard after the stack's first decision: R11) (the real Von server, `--include-von --require-von`) and, scripted, one fallback each:
`ai/grenade/bang_fallback_no_clear_lob`, `bang_fallback_stun_lost`, `bang_fallback_never_called`, `bang_fallback_never_goes_off`, the aim into a room deeper than a
stun reaches: `ai/grenade/bang_into_long_room` (scripted), and the late reason:
`ai/grenade/quiet_entry_turns_bang` (gunfire heard while the quiet stack lines up: a bang before anyone goes in), `quiet_entry_crossing_stays_quiet`
(the same as the point crosses: it stays quiet); the listen hold (scripted): `ai/grenade/quiet_entry_listens_at_stack` (about 3 s in the slot before
the pie; a lone entrant without a stun does not hold), `quiet_entry_listen_turns_bang` (steps heard during the hold: a bang before anyone goes in),
`quiet_entry_listen_ends_on_hit`, `quiet_entry_listen_ends_on_hostile_in_view`; the committed thrower: `ai/grenade/bang_kept_through_fight` (a householder
shows itself in the doorway at the call: the point leaves for the fight, the thrower throws the planned stun, then fights, and a member at the door
goes in on the burst; real Von); going in on the burst: `ai/grenade/burst_then_cross` (its own stun thrown by GRENADE at a householder
holding the kitchen's back doorway from inside, in its line of fire, then the walk in: no pie, across from its slot at once; real Von); a guard's entry: `ai/entry/entry_guard_bang_suspect_room` (a search
walk through the back door into a kitchen gunfire was heard in: a bang), `entry_guard_quiet_unsuspected_room` (the same walk, nothing heard: quiet), scripted.

**E18. Keep out of a doorway's view; a cleared room is safe to pass for a minute.** Any walk the entry guard covers (a search or
explore, an investigation, an advance or flank, the way to an object or to a throw spot, the approach to a stack) stays out of the **view** of every
open doorway into a room that is not clear for passing, inside the house or out. The view of a doorway is the area outside it that
someone inside the room sees through it: bounded by the rays from the room's two far corners through the opposite jambs, `door_view_depth`
(450 px) long, and stopped at walls (a doorway between two rooms: cut at the edge of the room in front of it, so a view does not run on through
the next doorway into another room). When the plain route goes into such a view and a route that keeps out of all of them reaches the
destination no longer than `door_avoid_ratio` (2.0) x the plain route + `door_avoid_slack` (300 px), the NPC walks that one: round the
far side of the house, or round the end of a view in a hall. Otherwise it walks the plain route, and E15 secures each view it crosses.
A room is **clear for passing** for `entry_pass_clear_time` (60 s) after it was cleared (E8, an ally's `cleared_room`, or a search
that covered it): a doorway into it is then walked past freely; after that its views are avoided or secured again. E9 and ENTER keep
a cleared room cleared (nobody clears it twice) for the memory's own span. The route bands Von reads in the options ("short / medium /
long route") are the length of the route the NPC will walk, the door-avoiding one when it would take it (the planner is not offered
a short route it would not walk). Exempt, as in E9: a retreat, an NPC under fire, and the doorway it is entering itself (the approach to its
stack leaves that doorway's own view alone). Why: a threshold crossed in the open is how a team is shot from a room it has not cleared
(E4, E9); the real answer is to give an open door a wide berth, and cover it only when the way leads past it. In the code
`AgentEntry` lays out each view once per doorway (`door_view`, a ray fan on `PhysicsLayers.SOLID` that looks through furniture and
characters) and the route (`walk_route`); the Navigation domain bakes the house's planning bake with those views as extra holes
(`NavBuilder.avoid_map`, on the worker thread, cached per set of views), and `Locomotion` walks that map (its third way, beside the
plain and steering ones; a body at rest in the way still takes the walk to the steering map or holds it, and E15 secures the views that
route crosses; once the route on the avoid map passes no body it knows of, the walk goes back to it). A decision waits the few frames the avoid map takes to bake (`routes_ready`; a forced one does not) so its route bands are the
walked ones.
Exports on `GoalController`: `door_view_depth`, `door_avoid_ratio`, `door_avoid_slack`, `entry_pass_clear_time`. The entry plan overlay
(`show_entry`) draws the views the NPC keeps out of.
Tests: `entry_route_round_door_view_outside` (a one-room house, gunfire on its far side: the invader goes round the north side, never in
the front door's view; real Von), `entry_route_round_door_view_inside` (a hall with a store room's view across it: it goes round the
far end; real Von), `entry_cleared_room_pass_expires` (scripted: the cleared room is passed freely, a minute later its door is avoided or
covered), `entry_route_band_as_walked` (scripted: the lead's route band is the medium walked one, not the short plain one);
`navigation/avoid_map_carves_the_views` (the map); `ai/movement/npc_doors_walk_round_body` / `npc_doors_walk_body_on_goal` (scripted: a teammate at
rest on the way round a view, or on its end: gone round or stood short of, never pressed against); `ai/grenade/grenade_throw_walk_secures_doorway` (scripted: every throw spot in reach is past a
study's doorway, whose view fills the corridor: the walk to the spot secures the doorway from beside its jamb, then the throw).

**E19. A split stack and the criss-cross.** A member that would have to cross the doorway's view to reach the side the team stacks on
stacks on its own side of the door instead, so a team that comes at a door from both sides stacks on both, and nobody walks through the
view before the entry. Each side has its own file of slots against the wall; the slots are still numbered across both sides in the order
they were claimed, and every claim carries its side. Each side's front man slices its own half of the pie (E3). Then they **criss-cross**: the
point (the first claimer) crosses to the door-wall corner on the far side, hard corner first, and after its `in` the other side's front man
crosses to the opposite corner, the one on the point's side; the rest follow with the sides taking turns, each after the `in` of the member
ahead of it (the crossing order: the point, the other side's front man, then the second of the point's side, the second of the other side,
and so on; a side that runs out leaves the rest to the other). The ready barrier (E6), the bang thrower (E17) and the short room's count (E13)
take both sides together, the other side's front man counting as ready once its half of the pie is sliced; E12's rear guard is per side;
the human is given a slot on the side it stands on when the way to the team's side would cross the view (E16). A stack whose members all
arrive from one side is one-sided and behaves as E1 to E17 say. Why: walking across the door to reach the stack is the funnel crossed
outside it (E15, E18); the criss-cross is how real teams enter from both sides of a door, each man covering the half of the room the other
cannot see, and the crossing paths keep each entrant's sector clear of the other's. In the code, `AgentEntry.stack_side_from` takes the
team's side (`stack_side`: the point's, else the side with more wall, else its own) unless `cuts_view` says the member's plain route there
starts outside the doorway's view (E18) and crosses the door's axis inside it (a walk that starts in the view, or goes round it, does not
split the stack); `AgentEntry.place` is a member's place in its side's file (its slot less the claims ahead of it on the other side), and
`AgentEntry.crossing_order` the order the stack crosses in. `entry.gd` reads both through the perception (`_before`, `_slices_own_half`,
`_follow`, `_corner_for`); `PlayerStack` uses them for the human.
Test: `entry_split_stack_criss_cross` (two invaders at the Terrace house's back door from its north and south; real Von, `requires_von`).

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

The two maps of E13 and E15 (`#` wall, `D` opening): the box room (E13), 140 px square off a corridor, and the
corridor spine (E15), three rooms off one hallway.

```
        ########                          ##########################
        # BOX  #                          # A      # B      # C    #
   ######  D  ####################        ####  D  ####  D  ####  D #
   D   CORRIDOR                  #        D   CORRIDOR              #
   ###############################        ###########################
```

Hard and soft are judged as the definition above says, by sight from just outside the threshold: the far
corners are seen through the door and the two on the door's own wall are not, so both shapes have two hard
corners (the sources count one for a corner-fed room, whose short-side corner is a step from the jamb). The
stack forms on the side the point stacks on: for the point, the side of the door with more wall to stand against (an even
wall: the side it comes from), single file, slot 1 nearest the door; a member whose way there crosses the door's view stacks on
its own side (E19). The pie arc runs from beside
the stack toward the door's axis, clear of the slots.

## How the rules are enforced

- **What the AI knows.** Main hands every NPC the house's openings (`WorldGen.get_openings`, through
  `MatchSpawner.bind_npc`; the test world does the same). Perception's `agent_entry.gd` turns each one,
  entered into one of the rooms it joins, into geometry: the door's outward normal and the axis along its
  wall (taken from the room edge it lies on; the data has none), the stack slots in single file on both
  sides, the pie arc, and the four corners of the room behind tagged hard or soft by a sight ray. Built
  once per opening and kept, since walls do not move.
- **What Von decides.** Whether to enter, and by which doorway. (With a stun grenade in the stack SEARCH offers **STUN ENTRY** beside
  ENTER: the same doorways, a bang before the crossing, E17.) SEARCH offers a child **ENTER**
  (`decision_tree.gd`) beside its rooms and unexplored areas; its options are the `entries` group
  (`snapshot_options.gd`): the doorways out of the NPC's area into a room it has not seen or not searched
  lately, nearest first ("the doorway into the kitchen — unsearched — short route"). A room a doorway leads
  into is not also offered as a plain walk in. The wording was checked with `tools/von_probe.py`
  (`tools/von_scenarios/search_enter_*.json`, `enter_*.json`). Only invaders enter this way
  (`GoalController.entry_enabled`, on in `npc_invader.tscn`; test switch `ai.entry`).
- **The choreography.** The ENTER leaf runs the `entry` primitive, a phase machine in the behaviour
  sub-domain (`behavior/entry.gd`): approach (E1), stack (E2), bang (E17, a bang entry only), pie (E3), cross (E4, E5), corner, clear
  (E8), cover (E8), rear (E8). It does not ask Von again on the cadence until the entry is over, so it runs with the server down (a forced decision
  still replaces it, or aborts it when Von is down).
  While crossing, the controller holds every decision (`Behavior.committed()`); a hit or a hostile seen
  in the doorway is acted on once the NPC is through. So it does while the bang's thrower is between its call and the stun leaving its
  hand (`Entry.throwing()`, E17), and a decision that came back meanwhile is taken again once the stun is away (`Behavior._held`). The room is cleared by sight with
  `search_coverage.gd`. Posture and running stay code-owned: it stands throughout and never runs, not even
  under fire, because a running character cannot shoot (test `entry_never_runs`).
- **The guard (E9).** `Behavior._entry_guard` (`behavior.gd`) runs after the running primitive has steered and reads the
  walk the nav agent was just given (`Locomotion.path_ahead()`), not the order's destination, so it sees every walk: a
  move, an engage or its repositions, the way to an object, a throw's walk to its throw spot (which starts afresh from the walk when the
  entry hands it back, `_resume_order`). Perception's `AgentEntry.threshold_ahead` finds the first
  doorway on it that leads into a room that is not cleared (`cleared_room` memory, written when an entry finishes, when an
  ally radios `cleared_room`, and when a search covers its room). The guard then stashes the order, runs an `entry`
  primitive for that doorway (the same one ENTER runs) and puts the order back when it ends. Exempt are the nodes that
  carry `entry_guard: false` (RETREAT) and an NPC under fire, but for a doorway into the room the shots came from
  (`Behavior._into_the_shots`, over `AgentPerception.shots_from_room`). Any entry into a room the NPC suspects (`AgentPerception.room_suspicion`,
  the shots' room among them) is a bang one when the stack carries a stun (`Entry.begin`, E17). `GoalController` exports `entry_guard`, `entry_guard_range`
  and `entry_guard_rearm` (test switch `ai.entry_guard`). It acts only where entry does, on invaders (`entry_enabled`).
- **The views (E18).** `AgentEntry.door_view(opening, into)` lays out a doorway's view once (walls do not move); `avoided(here)` is
  the set of views of the doorways into rooms not clear for passing (`AgentPerception.is_pass_clear`, from the `cleared_room`
  memory's age against `entry_pass_clear_time`), less the room the NPC stands in; `walk_route(from, to)` weighs the plain route
  against the one on `NavBuilder.avoid_map` (planning bake plus the views as holes, async, cached by the set) with
  `door_avoid_ratio` and `door_avoid_slack`. `Locomotion._update_doors` puts a guarded walk on that map (`Behavior._keeps_out_of_views`:
  a move, engage or interact that is not a retreat, and an entry's approach); `Behavior._passing_gate` (E15) secures what the plain
  walk still goes into. `SnapshotOptions._route_len` measures the same route for the bands Von reads.
- **The team.** Roles, readiness and progress travel on the callout radio: each step is a `callout` with
  `opening`, `into` (the room it leads into), `slot`, `side` (the side of the door the member stacks on: on a split stack, E19,
  not the same for all) and `entry_step` (`claim`, `ready`, `going_in`, `in`, `clear` with
  `cleared_room`, `cover` with `covering` (the doorway on it watches), `rear`, `done`, `abort`), repeated whole every
  2 s so a claim stays live. A doorway on is claimed like a slot: the nearest one no teammate covers, and of two who
  claim one, the lower instance id keeps it. `done` ends a hold; a teammate still holding takes it as the team moving on. A slot is the lowest the radio
  leaves free; two members who claim the same slot on the same frame settle it by instance id (the flank
  side claim pattern). A single invader is a team of one: nobody else claims the doorway, so there is no
  barrier and the pie is sliced from both sides (E7).

Interpretations and the game's own rules, where the sources leave a choice:

- "Ordered by arrival" (E2) is the order of claims on the radio, not of bodies at the wall. A member claims the lowest slot the
  claims it has heard leave free; two that claim before either hears the other settle it by instance id.
- The point is the lowest slot still waiting; a member that claimed a slot and never reached it is dropped
  once the member behind it has waited `entry_ready_timeout`. The wait restarts when someone new claims a
  slot (E6, E7).
- The point buttonhooks to the door-wall corner on its own side; the second crosses to the hard corner on
  the other side; a lone entrant goes to the door-wall corner on the side away from where it stands, so it
  crosses the room's front (E5, E7). On a split stack the point crosses to the far side's corner and the other
  side's front man to the point's side (E19). Later members take a spot inside, off the axis.
- The room is radioed clear once the member that covered it sees the rest of the stack through; a member
  still taking its corner holds it before it accepts the call. The doorways on come before the rear: a pair in a
  room with two of them covers both and leaves the way it came unwatched (E8). A hold lasts until a teammate who was
  holding moves on, or at most `entry_cover_time` (8 s) on a doorway and `rear_security_time` (10 s) on the rear; a
  lone entrant looks through each doorway on for `entry_watch_dwell` (0.8 s) and has nobody to leave behind.
- E14 applies whatever tactic the fight takes: a rush, an advance or a flank into a room whose hostile is in view with a line of
  fire first clears the gun on the door from outside (kills it, or loses sight of it), and goes in after. The rush tests (`entry_guard_advance`,
  `entry_guard_fires_from_outside`) give the target normal health and assert it was shot dead from outside before the invader
  went in, and `flank_walks_to_chosen_side` has a low coffee table across the lines from the hall (sight looks over it, a bullet
  does not), so the flank is the only way to a shot.
- A room crossed in a retreat or under fire (not the shots' own room) is visited, not cleared: ENTER offers it again once the NPC is outside, and an
  entry the guard began there and gave up is not started again for `entry_guard_rearm` s. Search ranking still goes by
  `visited_room` (stood in it lately); the guard and ENTER go by `cleared_room`.

- **The human (E16).** `PlayerStack` (`scenes/ai/team/player_stack.gd`) is a child of the human's character, attached by Main
  (`MatchSpawner.bind_player`). It hears the same callouts the NPCs do, and when an allied claim on a doorway is live and the
  human is within range it radios the human's own claim as a `callout` with the human as speaker, repeated every 2 s. The AI's
  entry code (`claims`, `free_slot`, the barrier, the follow rule) reads it like any teammate's, so `entry.gd` has no case for a
  human. Its side comes from the same `AgentEntry.stack_side_from` (E19). `view()` gives the markers the doorway, the slots (each
  where it stands, on either side) and which is the human's.

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
- [Wikipedia, Tactical reload](https://en.wikipedia.org/wiki/Tactical_reload): a partly spent magazine is swapped
  for a full one and kept; doctrine starts an entry into a building with a full magazine (E11). Tertiary; the
  [NRA Women piece on when to reload](https://nrawomen.com/content/when-to-reload) names room clearing as a
  situation for a tactical reload. A game-tactics wiki adds that reloading in the fatal funnel is dangerous; not
  relied on.
- E4's "finish the crossing when hit", E6's ready timeout, E7's ally joining and E13's size rule for a short room are
  this game's own rules, not sourced.

## Not modelled

Closed or locked doors and breaching (blocked on doors, issue #21); a stun grenade thrown in is modelled (E17), a frag at
entry is not. The dynamic-entry "shock" of breaching. Stairs (bottom-up clearing, no leapfrogging). Mirrors and cameras under a door. Hallway bounding overwatch
and corner clearing outside a room (a doorway passed in a corridor is E15). Verbal commands to non-combatants. A
defender reacting to a stack at its door. Entry speed against the 5 to 6 second benchmark is E10.
