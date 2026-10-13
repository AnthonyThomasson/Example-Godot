# Flanking behaviour

What an NPC should do when it flanks a target, and which tests hold the AI to it. The tests in
`tests/ai/flank/` assert this document, not the current code: where the AI falls short the test
is written first, left red and tagged `gap` (`tools/run_tests.sh gap` lists them; the runner reports such a failure
as GAP, expected and not a failure of the run, and a `gap` test that passes as a FAIL telling you to drop the tag); no
flank test is red now.
Each test's header comment names the behaviour (F, B1 to B9, C) it asserts.

Flanking here means taking one of the sides of a known hostile, measured in the hostile's own frame
(left, right, rear), and fighting it from there. The AI's side of this lives in `agent_tactics.gd`
(candidate points and their annotations), `agent_snapshot.gd` + `snapshot/` (the words Von reads), `decision_tree.gd`
(which options a node offers) and the `engage` primitive (walking there and firing). See the
`domain-ai-perception` and `domain-ai-decision` skills.

## Behaviours

**F. Sides are the target's own.** Left, right and rear are measured in the target's frame (where it was
last seen facing, else the side toward the NPC). The side the NPC already stands on is not offered. A flank
point lies about 220 px from the target on its side.
Tests: `flank_sides_target_facing_npc`, `flank_sides_target_facing_away`, `flank_sides_target_sideways`.

**B1. Approach out of the target's sight.** A flank position is behind the target and out of view of its
other enemies, and the approach is covered or concealed rather than across the target's front. A route
the target cannot see (it looks away, or a wall is between) is described as hidden, not exposed.
Only the samples inside the target's view cone (`watch_arc`) count toward a route being exposed. Why:
surprise is the point of a flank; game AI gives path cost to the target's forward arc.
Tests: `flank_sides_target_facing_npc`, `flank_sides_target_facing_away`.

**B2. Never walk a flank route past a hostile.** A route that passes within `route_clearance` of the target
or another known hostile is dropped as `crosses`. Walking away from someone close by is not passing them.
Why: the NPC would walk into their fire. Tests: `flank_rear_route_crosses_target`,
`flank_route_passes_second_hostile`.

**B3. Do not flank across a friend's line of fire.** A side whose point lies in an ally's line of fire to
the target, or whose route crosses that line, is not offered. Only allies the NPC can see count: it
weighs what it perceives, so an ally outside its view cone has no lane (a radioed side is B4's `held`).
Why: blue-on-blue; the assault must land where the base of fire is not shooting. Tests: `flank_ally_lane`,
`flank_two_invaders_split_sides`.

**B4. One flanker per side.** A side an ally holds, standing on it where the NPC can see it or by radio
callout, is not offered; with every side held there is no FLANK tactic and the NPC fights directly. Allies
decide at different moments and each radios its side, so they end on different sides. Without the radio
they can collide (the contrast case).
Why: surround only with surplus force; a stacked side adds no angle.
Tests: `flank_all_sides_held`, `flank_side_held_by_radio`, `flank_side_held_by_seen_ally`,
`flank_two_invaders_split_sides`, `flank_three_invaders_exhaust_sides`, `flank_without_callouts_collide`.

**B5. Terrain that denies a flank means no flank.** At a corridor's dead end, against a wall, or in a
doorway funnel every side lies behind a wall or past the target. The FLANK tactic is absent and the NPC
engages or advances.
Why: anchored flanks cannot be turned; the doorway is the fatal funnel, so no one lingers in it.
Tests: `flank_corridor_dead_end`, `flank_side_behind_wall`, `flank_rear_route_crosses_target`.

**B6. The flank spot is a firing position.** It has a clear shot at the target, and cover beside it is
reported ("cover close by (the pillar)"). A point with the line blocked, such as outside a wall or behind a
shelf, is still weighed (and worded "line blocked from there") but is not offered as a flank.
Why: a flank that cannot shoot only ends the NPC somewhere pointless; F.E.A.R.'s flanks were cover-to-cover
moves to spots with a line on the player.
Tests: `flank_spot_cover_and_clear_shot`, `flank_spot_line_blocked`, `flank_side_behind_wall`,
`flank_corridor_dead_end`.

**B7. Do not step into the side the target is walking toward.** A side the target's smoothed velocity heads
toward reads "they are moving toward that side" and is not offered. The risk of being flanked back is
weighed against the gain.
Tests: `flank_target_moving_toward_side`.

**B8. A territorial defender does not leave its house to flank.** Sides outside the house are weighed and
dropped for a NPC that defends territory, and offered when it does not.
Tests: `flank_territory_confines_sides`, `flank_territory_off_offers_outside` (contrast).

**B9. Commit.** Once a side is chosen the NPC walks the route, reaches the target's side in the target's
frame and fires from there; it does not stall or turn back on the way.
Tests: `flank_walks_to_chosen_side`.

**C. Configuration.** `disabled_nodes = [flank]` removes the FLANK tactic however open the sides are.
Tests: `flank_disabled_node`.

## Situations

The tests run on three hand-laid maps (`tests/_ai/flank_maps.gd`, built with `TestSetup.layout`), so each
scenario reads as a place: "the target in the living room, the NPC in the hall".

- **Terrace house** (840 x 470): living room (sofa, coffee table, bookshelf, armchair), kitchen (island,
  counter, fridge) and a hallway along the south. Doorways: hall to living room, hall to kitchen,
  living room to kitchen, the front door and a back door onto the garden. Used for the doorway standoff,
  in-room flanks, radio claims and territory.
- **Corridor spine** (900 x 300): one 100 px corridor, three rooms off it, a dead end at the east.
  Used for the dead end.
- **Warehouse** (1000 x 700): one room with three shelving rows, a car, a counter, a bench, a tool chest
  and two pillars. Used for open-ground flanks, ally and second-hostile cases, and the NPC groups.

```
Terrace house                     Corridor spine                  Warehouse
+----------+----------+           +------+------+------+          +----------------------+
| LIVING    ) KITCHEN  >          | RM A | RM B | RM C |          | car    ==shelves==   |
|          |          |           +--[ ]-+--[ ]-+--[ ]-+          |   ==shelves==  pillar|
+--[ ]-----+---[ ]----+           [ CORRIDOR (dead end)|          |  pillar  ==shelves== |
[ HALL (front door)   |           +--------------------+          +----------------------+
+---------------------+
```

## How the rules are enforced

A side the AI will not take is still weighed: `debug_zones()` lists it with its words and tags, and the
decision tree's `flank` node drops it through `drop_tags`. The tags, set in `snapshot/snapshot_options.gd`
(`flank_group`), are `held` (B4), `crosses` (B2), `no_shot` (B5/B6), `heading` (B7) and `lane` (B3). The
geometry behind them is in `agent_tactics.gd` (`flank_sides`, `ally_lane`, `route_exposed`, which takes the
target's front for B1). A FLANK tactic whose every side is dropped is not offered at all.

There are no known gaps. A new behaviour that the AI does not show yet is written as a red test tagged
`gap` first, and listed here until it passes.

## Sources

How far each is to be trusted:

- Wikipedia, [Flanking maneuver](https://en.wikipedia.org/wiki/Flanking_maneuver): general reference on
  flank attacks, anchored flanks, a pinning element and friendly-fire coordination (B3, B4, B5). Marked as
  needing citations.
- UNITAF, [attacking theory](https://unitedtaskforce.net/training/sop/field-leadership/attacking-theory)
  and [firefight theory](https://unitedtaskforce.net/handbook/group/236/firefight-theory): a milsim
  group's reproduction of find, fix, flank, finish; flanks are rapid, concealed and decisive (B1, B4).
  Third-party, not doctrine itself.
- US Army CALL 97-20, [battle drill](https://www.globalsecurity.org/military/library/report/call/call_97-20_btldrill.htm):
  the fatal funnel at a doorway (B5). Primary, about room entry rather than flanking.
- Liden, 2001 game-AI paper [Liden.pdf](https://www.qrg.northwestern.edu/Resources/aigames.org/2001/Liden.pdf):
  a flank position is behind an enemy and not visible to its other enemies (B1, B2). The PDF could not be
  read here; the criteria are as summarised by a search result, so check them against the paper.
- gamedev.net, [shooter game flanking algorithm](https://humor.gamedev.net/forums/topic/673823-shooter-game-flanking-algorithm-or-way-of-implementation):
  forum suggestions to add path cost in the target's forward arc (B1). Opinion.
- Jeff Orkin's F.E.A.R. AI, as reported by [Vice](https://creators.vice.com/en/article/xy9nqa/shooters-never-matched-fears-legendary-ai)
  and the [GameSpot designer diary](https://www.gamespot.com/articles/fear-designer-diary-2-a-study-of-smart-ai-part-ii/1100-6134022/):
  the flanking was cover-to-cover moves placed beside the player, backed by radio callouts (B4, B6).
  Secondhand account of a primary talk.
- [Killzone 2 review](https://www.pcworld.com/article/533255/killzone_2_review.html): enemies that flank in
  answer to suppression. Review, not design material.
- Shardpunk devlog, [Tweaking the AI](https://bryqu.itch.io/shardpunk/devlog/56198/tweaking-the-ai): scoring
  flank options against the risk of being flanked (B7). Hobbyist devlog.
- B8 and B9 are this game's own requirements (the territory rule in `domain-ai-decision` / `domain-ai-snapshot` / `domain-ai-behavior`; the commit
  rule in `domain-ai-behavior`), not sourced.
