# Leadership

Each side has a squad and a leader, and the leader can order members to defend a room or to stack on a door. A member with no order
acts on its own, exactly as it would without any of this. The human can choose to lead its side from the setup window; a right-click
then pauses the game and opens a menu to order the selected teammates. The tests named under each behaviour assert this document.

The pieces: `general/game_clock.gd` (the pausable clock every AI timer reads), `ai/team/squad.gd` (the squad: roster, leader, succession,
`issue` and `view`), `goal_controller.gd` (the order intake, the `ordered → order` entry rule, the progress radio), `agent_perception.gd`
(`process_order`, the live order, its end), `agent_entry.gd` (`defend_spot`), the snapshot (`snapshot_options.gd` `order_group` and
`tag_rooms`, `snapshot_sections.gd` `order_text`), the decision tree's `order` node and the planner's `confine_room`, the behaviour's
`defend` primitive (`behavior.gd`, `combat.gd`) and its ordered stack (`entry.gd`, the entry guard in `behavior.gd`, and the perception's
`ordered_walk` and `seen_empty`). Main builds the squads (`main.gd` `_build_squads`, `match_spawner.gd` `bind_squad`) and, when the
human leads, the command menu and the order markers (`main.gd` `_build_command_menu`; `ui/hud/command_menu.gd`, `ui/hud/order_markers.gd`;
the setup window's "Lead the team", `ui/menus/setup_menu.gd`; `Keybinds.COMMAND`). See the `architecture` skill (interfaces 7, 10, 11
and 21), the `domain-ai-*` skills, `domain-main`, `domain-general`, `domain-ui-menus` and `domain-ui-hud`.

## Behaviours

**LD1. Pausable AI clock.** Every AI ttl and timer runs on `GameClock` (General, interface 11), which counts physics frames and so stands
still while the tree is paused: the memory's ages (a contact's 4 s, a callout's 6 s, leads, under fire), the controller's stamps and force
age, the leaf age, the burst ages, the grenade replan and the debug overlays' ages and blink. A pause of any length expires nothing. Two
things stay on the wall clock because they measure real time: the Von launcher's boot timeout and the planner's per-level `ms` (Von's
latency).

On this clock a headless `--fixed-fps` run ages the memory in sim time, as a played game does in real time, so a contact lapses
after 4 s of play. Two consequences (D9): a GRENADE order keeps the hostile it was offered on while the throw runs, so the contact
lapsing on the way forces no new decision, while its death does (`docs/grenades.md` G17, tests `ai/grenade/grenade_throw_spot_round_wall`,
`ai/grenade/grenade_throw_target_killed_redecides`); and
`ai/decision/von_down_holds_steady` keeps its hostile alive through the check (its premise: a dead hostile leaves no threat, and the
quiet reload, which needs no Von, would be taken).

Tests: `ai/perception/clock_pauses` (the tree paused for 10 s of wall time: a known contact and a callout are still known on resume),
`ai/perception/memory_matches_reference` (the memory against a plain log, on the game clock).

**LD2. A Von request across a pause.** The `HTTPRequest` asking Von pauses with its NPC, and its timeout timer with it: an answer that
arrives during the pause is read on resume and adopted then, with no failure.

Tests: `ai/decision/von_request_across_pause` (real Von: paused mid-request for 10 s, the answer adopted after resume).

**LD3. Squad.** One squad per side. Its leader is the member of the highest `rank`, the first in spawn order among equals: for the invaders
that is the unit's lead (rank 2, then its sergeant, rank 1), and a defenders' crew, which carries no rank, is led by its first spawned. A
squad the human leads is led by the human. Main builds one per side under `World` after arming the characters, and hands each NPC its own
(`MatchSpawner.bind_squad`). An AI leader gives no orders: nothing in a match changes unless a leader orders.

Tests: `general/squad_leader_rule` (invaders by rank, then spawn order; defenders by the first spawned; the human when leading).

**LD4. Succession.** When the leader dies, the next in line by the same rule leads within the frame, and the squad says so on the bus:
`&"leader"` `{ faction, leader, previous }`. The orders already given stand; a later order, from the new leader, replaces them.

Tests: `general/squad_succession` (a Main-built match: the lead invader killed, the sergeant leads within a frame, one `leader` event, the
trooper keeps its order, a newer order from the sergeant replaces it).

**LD5. Order transport.** A squad posts each order its leader gives as `&"order"` `{ id, leader, faction, to, kind, ... }`, kinds
`defend_room` (`room`), `stack` (`opening`, `into`, `stack_at` or `split`, `bang`) and `cancel`; a `defend_room` or `stack` order also
carries its target point, `pos` (the room's centre, the doorway's), for the order markers (LD12). `Squad.issue` turns a leader's request in
plain terms (`{ kind, to, pos?, room?, bang? }`) into one: a room key or the room under `pos`; for a stack the doorway nearest `pos` within
its width, the room on the far side of the wall plane from `pos` (an exterior door always goes into the house), and the side of the door
`pos` lies on along the wall (`stack_at`) or, for a click on the opening itself, both (`split`). No `to` means every living member but the
leader; an order to a dead member is dropped. Range is unlimited. Only the recipients named in `to`, of the squad's side, take it: each
holds it as its live order (the memory topic `order`, permanent) until it is done, cancelled or replaced, and never on a timer. While it
holds one the snapshot fact `ordered` is true.

Tests: `ai/decision/order_transport` (`ordered` on the recipients only; still held after three times the callout ttl; a newer order
replaces it; a cancel clears it).

**LD6. The ORDER node.** An arriving order forces a decision at once, as a hit does (after a crossing or an evade, which hold every
decision). The entry rules run in the order `under_fire → combat`, `engaged → combat`, `ordered → order`, `hostile_known → combat`: an
ordered member that is shot at or fighting fights, and goes back to its order once the fight lapses; a hostile merely known does not hide
the order. The ORDER node offers one option, the order itself, built by the snapshot with the primitive it runs (`defend` for a room, an
`entry` for a stack) and its params, each carrying the order's `order_id`; it is taken without asking Von. At Von's other levels the state
carries one sentence, after the goal, while the member holds an order: "Your leader ordered you to defend the kitchen." or "Your leader
ordered you to go into the kitchen by its doorway quietly." ("with a stun grenade first"). A member with no order reads exactly what it
read before: the same tree, the same rules, the same state text.

The sentence was measured with `tools/von_probe.py` on the 38 `tools/von_scenarios` levels (all 38 pass as they stand), each with the
sentence inserted after the goal: at the combat levels, the only ones an ordered member is asked (bind, engage, flank, grenade, retreat,
tactic: 18 levels), the top pick is unchanged in 17 of 18 for the defend sentence (the one change is the flank near-tie of
`flank_free_sides`, 0.52 to 0.48, toward a side outside the house that a member defending the kitchen is never offered) and in 18 of 18 for
both stack sentences, the expected pick's probability moving by 0.02 on average (0.09 at most). At the levels an ordered member never
reaches (search, enter, investigate: the order takes the walk first) the sentence naming the kitchen pulls toward kitchen options, which
is why it is shown only while ordered. "defend" and "hold" read alike (17 of 18 either way); "defend" is the menu's word.

Tests: `ai/decision/order_node_no_von` (an order is adopted by a walk that starts at the ORDER node, every level auto, no question to
Von), `ai/decision/order_fight_then_resume` (real Von: shot at, an ordered defender fights, then goes back to its order),
`ai/decision/unordered_state_unchanged` (an unordered NPC's walk and state text match a capture taken before any of this).

**LD7. Progress radio.** A member radios how its order goes as a callout with `order_id` and `order_step`: `moving` when it takes the order
up, `in_position` once it holds its defend spot, `done` when the order is done (a stack's room cleared, by itself or by a teammate who
radioed it), `refused` when it cannot carry the order out (a room or doorway it does not know: the order is dropped as the decision walk
starts, and that walk is the member's own, not kept to the refused order's room); each step once until the next differs.
The entry steps of a stack go out as they always do. Allies leave a progress call out of what they weigh (it never replaces a member's
entry claim on their radio); the squad keeps each member's latest step for `view()` (`{ leader, members: [{ node, order, step }] }`).
An order radioed `done` is no longer one the member holds: the view shows it with no order and the step `done`, so the order markers drop
it and the command menu offers no "Cancel order" for it. A `refused` order is still held, and drawn red.

Tests: `ai/decision/order_progress_radio` (a defender radios `in_position` in the living room, an invader `done` once it has cleared the
kitchen; each callout names its order; the squads' views show the steps), `general/squad_done_order_not_cancellable` (a member's order
radioed done is held no more and the menu offers no cancel for it; a refused one is still held), `ai/decision/order_refused_unconfined`
(a defender refuses a defend order for a room it does not know and still engages from its own room, no `confine_room` in the leaf).

**LD8. Defend a room.** Ordered to defend a room, the members share out its doorways (D2): member `n` of the order's recipients (in the
order `to` names them) takes doorway `n` (by id) of the room, the extras doubling up on the other side of the doorways in turn. Each walks
to a spot back in the room, off its doorway's axis and out of every doorway's fatal funnel, with a sight line to its doorway and low cover
on that line where there is some (`AgentEntry.defend_spot`): a guarded walk for an invader, as any of its walks, and a plain one for a
defender. There it holds, still, its gun on its doorway; a lone member of a room with several doorways takes the spot from which it sees
the most of them and turns among them. The watch stage turns it to a threat in sight and shoots, as in every primitive. A fight its own
shots begin (a hostile in its sector) is the decision's to weigh, as is one where it is shot at: in a fight Von still picks the tactic, but
only among the options inside that room (every option naming a place is tagged with its room, `tags.room`; the planner's `confine_room`
drops the engage, flank, advance, retreat and locate spots and the throw spots outside it), and `_hold_ground` and `Combat.peek_cover` keep
it inside against a contact outside the room. A live grenade (D8) sets off the evade reflex as it would anywhere, which may take the member
out of the room; once the grenade has burst it decides again, takes its order up and walks back in to its spot. "Never leaves the room" is
a rule on its fight options, not on the reflex. The order lasts until it is cancelled or replaced.

Tests: `ai/combat/defend_room_stays_inside` (real Von: an ordered defender shot at from the hall fights and never leaves the kitchen),
`ai/combat/defend_room_shares_doorways` (two members, two doorways, one each, off-axis and back from the wall, guns on them),
`ai/combat/defend_room_evade_returns` (a frag drives a defender out of the box room; after the burst it walks back in and holds).

**LD9. Stack on a door.** Ordered to stack on a doorway, the members go in by it as one stack (`docs/tactical-entry.md` E1 to E19), from
wherever in the house they are, invaders and defenders alike, whatever `entry_enabled` says (D4). The ORDER node's option is an `entry`
whose params carry the order: `opening`, `into`, `bang`, `stack_at` or `split`, `order_id`. Its claims carry it on the radio (`order_id`,
`order_bang`, the order's mode, and `order_side`, the side it names, 0 for a split stack), and the order's rules hold for any stack that
has a claim carrying an `order_id`; a stack nobody was ordered to keeps its own (D10).
- **The side (D3, D6).** With `stack_at` (the leader's click beside the opening) every member stacks on the side of the door the click lies
  on along the wall, whichever side it comes from. On a split stack (a click on the opening) each member takes the side it begins on (it
  reaches it without crossing the doorway's view, E19), but when that side would hold two more of the stack than the other, the last to
  claim it takes the other side: the sides differ by one at most, and once they do nobody moves again.
- **The mode wins.** The stack goes in quietly or with a stun as ordered: no suspect-room bang (E17, `entry.gd` `begin`), no first claimer's
  mode, no late upgrade (`_maybe_upgrade`) nor the listen at the stack that waits for one, and no veto from anyone outside the order (a
  teammate's `bang_off`). An unordered member that joins an ordered stack follows the order's mode and side (D10). **D1:** ordered with a
  stun when, the stack in place, nobody in it carries one, it goes in quietly and radios `bang_off` (the order's members follow it), and
  the order is still done at `cleared_room`; the throw's own failures give the bang up as they always do.
- **Go when ready (D7).** The point crosses (or the thrower calls the bang) once every living recipient of the order (the order's `to`,
  `Squad.alive` through the controller's `squad`) has radioed past `claim` at the doorway, or `order_ready_cap` (60 s, Entry export) after
  the first ordered `ready` it heard or said; a member the order does not name is waited for `entry_ready_timeout` as ever. A member does
  not go in alone (no second side of the pie) while another recipient is coming, and an ordered bang holds the point in its slot until
  the stack is in.
- **The way there is guarded (D4).** The ordered entry's walk to its slot meets the entry guard as any walk does: a threshold into a room
  that is not cleared is entered first, as a detour, and the ordered entry starts afresh after it (E9); a doorway view on the way is kept out
  of or secured (E15, E18; not when others already claim the ordered doorway, as for any stack). **D11:** on that walk an NPC that does not
  clear rooms by entry (`entry_enabled` off: a defender) counts a room it has stood in within `entry_pass_clear_time` (60 s) and seen no
  hostile in (`AgentPerception.seen_empty`) as clear for passing, for thresholds and views alike; any other room still gets an entry. A
  room only glimpsed through a doorway was not stood in. An invader's way is unchanged: it clears rooms by entry.
- **The end.** The order is done when its room is cleared (`cleared_room`, by the member or radioed by a teammate): the member radios
  `order_step` `done` and acts on its own from then (the rest of the entry, covering the doorways on, runs to its end first). The same
  order decided again (a decision forced meanwhile) leaves the running entry, or the detour in front of it, running.
- **The human.** A human leader near the ordered doorway is given a slot by its `PlayerStack` as for any stack (E16); it is a member the
  order does not name.

Tests (all scripted, on the Terrace house's back door unless said; `tests/ai/entry/`): `order_stack_quiet_suspect_room` (ordered quiet
into a suspect kitchen: no bang mode, no bang, no stun thrown), `order_stack_stun_despite_bang_off` (a teammate radioing `bang_off`
throughout: the bang is called and a stun goes off before the crossing), `order_stack_no_stun_goes_quiet` (D1: the stuns gone, in quietly
with `bang_off`, done at the cleared kitchen), `order_stack_far_guards_thresholds` (from the living room to the kitchen's hall doorway: the
hall entered first, then the ordered entry), `order_stack_side_from_click` (D3: a click south, then north, of the opening stacks the member
there; the squad's resolution of the room, an exterior door and a split stack), `order_stack_split_even` (D6: three from the north and one
from the south stack two and two, the southerner south), `order_stack_waits_for_all` (D7: the point waits for the far recipient past the 6 s
timeout), `order_stack_defender` (D4, D11: a defender passes a corridor it has seen empty and enters a room it has not),
`order_stack_unordered_joiner_follows` (D10: a quiet claimer north follows a later stun order south), `order_stack_ends_at_cleared` (the
order done at the cleared kitchen, then Von asked again with no `ordered` fact).

**LD10. Lead the team.** The setup window has a "Lead the team" checkbox, off by default, which applies to Start only (a played match;
Watch and Endless ignore it). It is reported as the window's `lead` and saved with the rest of its choices (`Settings.set_setup`), so the
window reopens with it as it was left. With it on, the human leads its side's squad (`Squad.setup`'s `human`), and a human invader is the
unit's lead (`rank` 2): the first NPC invader is its sergeant (1) and the rest troopers (0). The style draws are the same either way: each
character gets the style, look seed and weapon style it would get with it off. With it off, nothing changes: the human invader is ranked
last of the unit as before, the squads are led by their own rule, and neither the command menu nor the order markers are built.

Tests: `ui/setup_menu_config` (the checkbox: off by default, reported as `lead` by `current_config()` and Start, ticked again from a
remembered config), `general/lead_rank` (on: the human invader rank 2, the first NPC 1, the next 0, the same styles and look seeds; off:
the human last; `Settings.set_setup` keeps and saves `lead`).

**LD11. Command menu.** Built only when the human leads (`ui/hud/command_menu.gd`). `Keybinds.COMMAND` ("Command teammates", right
mouse by default; nothing reads the right button otherwise) pauses the whole tree and opens the menu on what is under the cursor, a
panel docked at the left of the screen (so it never covers the teammates or the doorway it is about) and a ring on the clicked point:
- a teammate's body within 28 px of the click: "Select <name>" or "Deselect <name>" (the menu stays open);
- else a doorway, the one nearest the click within its width: "Stack into the <room> (quiet)" and "Stack into the <room> with stun",
  `<room>` the room the stack goes into as the squad resolves the click (`Squad.resolve`, D3: the far side of the wall plane from the
  click, an exterior door's one room), so the label and the order name the same room; the stun item is greyed while no
  recipient carries a stun (D1);
- else a room: "Defend the <room>";
- and "Cancel order" while a recipient holds an order (one radioed done is held no more, LD7);
- below, the teammates, each a box to tick.
The recipients are the selection, or every living teammate when nothing is selected, never the human. A left-click on a teammate's body
while the menu is open selects or deselects it too. The selection lasts until it is changed, and a dead teammate leaves it. Choosing an
order closes the menu and asks the squad for it (`order_requested` → Main → `Squad.issue`, interface 21): `{ kind: "stack", to, pos, bang
}` with `pos` the click itself (the squad works out the doorway, its side and the room, D3), `{ kind: "defend_room", to, room }` or `{ kind:
"cancel", to }` (the recipients holding an order). Escape closes the menu without an order and never reaches the "back to setup" key;
closing unpauses the tree. Space stays the player's Interact. The menu opens only while the human leads: once it is dead and someone else
leads, it stays shut. It holds no AI reference and works out no AI id: it reads its teammates through the Character API and the squad
through its `view()`.

Tests: `ui/command_menu_items` (plain dicts, a fake squad's view and a real squad's `resolve`: the items for a doorway, a room and a teammate, the stun item greyed with no
stun and offered with one, the requests for the whole squad, a selection and a ticked teammate, "Cancel order" for a selected member that
holds an order, Escape, a right-click opening it on the doorway and a left-click on a body while paused; it pauses the tree and unpauses on
close), `ui/command_menu_label_matches_order` (a real squad: by an interior doorway, on either side of the wall and on its plane, the
room the stack item names is the room of the order the squad posts), `general/command_menu_wiring` (a Main-built match with "Lead the team" on: two ticked teammates ordered to stack on the back door
with a stun claim slots there in bang mode once the menu closes), the keybind coverage test (`general/keybinds_overrides`:
every action, `COMMAND` among them, has a settings label and group).

**LD12. Order markers and the squad leaders.** Built with the command menu, only when the human leads (D5; Watch and Endless draw none),
`ui/hud/order_markers.gd`, under `World` at `DrawLayers.ABOVE`. It draws each living member's order target (a dashed line from the member to its target, the doorway's centre for a stack or the room's
centre for a defend, as the order's `pos`; the target ringed and named with the member's latest progress, red when it refused; an order
that is done is no longer drawn), and a ring round each teammate selected in the open menu. It watches the squad's `view()` and the menu's
selection (`selection_changed`, empty once the menu closes), and reads the members through the Character API.

Who leads is a debug overlay, not a marker: the overlay bar's "Squad leaders" (`show_leaders`, a global row of `OverlayRegistry`, off by
default; `ui/overlays/leader_overlay.gd`, under `World` at `DrawLayers.ABOVE`), which Main builds in every match, played, Watch or Endless,
over every squad's `view()`. While it is on it draws a crown over each side's living leader, moving to the next in line when one falls.

Tests: `ui/order_markers_draw` (a fake view: one target per member with an order and none without, no marker on the leader, the selected
teammate ringed where it stands and cleared with the selection, drawn at `DrawLayers.ABOVE`), `ui/leader_overlay_draw` (the `show_leaders`
row, global and off by default; with fake views nothing while off, then a crown over each squad's leader, moved to a new leader and gone
with none; Main's `_build_leader_overlay` over two real squads, shown and hidden by the bar's toggle).

## Decisions

The cases the behaviours above cite as D1 to D11.

| # | Case | Decision | Where |
|---|---|---|---|
| D1 | Ordered with a stun, no stun in the stack | The menu greys "with stun" while no recipient carries one; a stack whose stun is gone by the time it is in goes in quietly and radios `bang_off`, and the order is still done at `cleared_room`. | LD9, LD11 |
| D2 | Where the defenders of a room stand | They share out its doorways, each on a spot back in the room, off its doorway's axis, cover preferred, gun on that doorway; extras double up in turn; a lone member takes the spot that sees the most doorways and turns among them. | LD8 |
| D3 | What a click on a doorway decides | The side of the wall plane clicked is where the stack forms (it goes into the other room); left or right of the opening along the wall is the stack's side of the door; a click on the opening is a split stack; an exterior door always goes into the house. | LD5, LD9 |
| D4 | Defenders and stack orders | An ordered stack runs whatever `entry_enabled` says, its approach guarded like any walk (thresholds and views). | LD9 |
| D5 | Markers | Only when the human leads, for its own squad: each member's target, the selection while paused; the leader's crown is a debug overlay ("Squad leaders") for every squad in any match. | LD12 |
| D6 | A split stack's members | Each takes the side it reaches without crossing the view, balanced so the sides differ by one at most. | LD9 |
| D7 | Go when ready | The point waits for every living recipient's `ready`, at most `order_ready_cap`; an unordered joiner is waited for `entry_ready_timeout`. | LD9 |
| D8 | A defender and a live grenade | The evade reflex may leave the room; after the burst the member walks back in and holds. | LD8 |
| D9 | The clock and the tests | Moving to the game clock may change a test's timing; `memory_matches_reference` takes its reference "now" from the new clock (the clock source only), and any other test turned red is reported with its cause before it is changed. | LD1 |
| D10 | Unordered entries | Unchanged: Von's ENTER and STUN ENTRY, the first claimer's mode, the suspect-room bang, the `bang_off` veto, the late upgrade, the listen and the ready timeout; the order's rules apply only to a stack with a claim carrying an `order_id`, and an unordered joiner follows the order's mode and side. | LD9 |
| D11 | A defender's ordered walk across its own house | A room it has stood in and seen empty within `entry_pass_clear_time` counts as clear for passing, for thresholds and views; any other room gets an entry. | LD9 |

## Numbers

| What | Value | Where |
|---|---|---|
| A defend spot: back from its doorway's wall | 60 to 150 px, best 100 | `AgentEntry.DEFEND_DEPTHS`, `DEFEND_DEPTH` |
| ... along the wall past the jamb | 30 to 100 px, best 50 | `DEFEND_LATERALS`, `DEFEND_LATERAL` |
| ... inside the room's walls by | 22 px | `DEFEND_INSET` |
| The fatal funnel: within a body of a doorway's width, nearer its wall than | 14 px, 200 px | `DEFEND_BODY`, `DEFEND_FUNNEL_DEPTH` |
| A defender walks into its spot to within, and back to it when pushed off by more than | 8 px, 24 px | `Behavior.DEFEND_REACH`, `DEFEND_DRIFT` |
| An ordered stack waits for its recipients at most (from the first ordered `ready`) | 60 s | `GoalController.order_ready_cap` |
| A room seen empty counts as clear for a defender's ordered walk for | 60 s | `GoalController.entry_pass_clear_time` |
| The command menu picks a teammate's body within | 28 px | `CommandMenu.PICK_RADIUS` |

## Performance

The perf guards (`tools/run_tests.sh --domain=perf`, nine tests) passed 9/9 on the finished change, measured 2026-10-16 09:10 to 09:11
under a 1-min load average of 3.9 to 4.3 on 12 cores (other sessions on the machine; not a quiet machine). The numbers before the
change were measured under a load of 4.2 to 5.1. Frame times in ms, avg / p95 / max (decisions made):

| Guard | Before (load 4.2-5.1) | After (load 3.9-4.3) |
|---|---|---|
| 10v10 match | 11.01 / 15.01 / 19.99 (172) | 10.63 / 14.47 / 21.19 (221) |
| 5v5 match | 7.42 / 11.63 / 19.42 (82) | 6.72 / 11.33 / 17.19 (101) |
| NPC crowd | 4.97 / 12.94 / 17.80 (123) | 4.36 / 9.62 / 17.20 (108) |
| hit overload | 13.66 / 16.10 / 21.71 | 11.59 / 14.05 / 18.51 |
| crowd fall | 9.86 / 14.17 / 19.45 | 9.25 / 12.80 / 16.72 |

The matches ask more decisions on the game clock: contacts lapse after 4 s of game time, as in a real-time match, where a headless run on
the wall clock kept them about 30 s of sim time (LD1).
