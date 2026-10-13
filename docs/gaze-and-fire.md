# Gaze and fire

Where an NPC looks and when it takes the shot (the faults ruled out: an NPC turned its back on a known threat, looked at
a wall, or saw an enemy and did not shoot). The tests named under each behaviour assert this document
(`tools/run_tests.sh gaze`). The code is `scenes/ai/behavior/watch.gd` and the *watch stage* of `behavior.gd`
(`_apply_watch`); see the `domain-ai-watch`, `domain-ai-behavior` and `domain-ai-combat` skills.

The one rule: **an NPC is always either looking at (and, when it can, shooting) a threat, or watching its doors; never a
wall, and never with its back to a known threat.** The character turns to wherever the controller sets `aim_point`
(instantly when standing), so the question is only who sets it. The primitives set it only as they steer (a walk looks down
its path, a room search at the nearest unseen floor), and the watch stage, which runs after them every tick, overrides it with
a threat or, for a resting NPC, the doors. It also does all the shooting of a threat, so no primitive or entry phase needs
its own fire call.

A *threat* is a hostile contact (`Watch.threat`): the one it is fighting if it can see it, else the nearest it can see,
else the one it is fighting as last seen, else the nearest it saw within `watch_lost_gaze` s. A contact it cannot see only
counts while it has a clear line to where it was last seen (it does not stare at a wall because someone is behind it).

## Behaviours

**W1. A threat holds the eyes.** Whatever the primitive is doing (a move, a search covering a room, a hold, a reload, an
engage still walking to its spot, any tactical-entry phase) the NPC faces its threat. Only a melee and an engaged NPC in
position (which aim at their target themselves) and an interaction (its own gaze, and the character is frozen anyway) are
left alone. A fight retargets from a contact it has lost sight of to another hostile it can see.
Tests: `gaze_search_turns_to_threat`, `gaze_travel_watches_threat`, `engaged_retargets_to_visible`.

**W2. A threat in sight is shot, in every state.** The shot is taken as soon as one is available (a loaded gun, the threat in
`shoot_range` with a clear line, the facing settled): in a move, a hold, a reload, while covering a room, and in every phase
of a tactical entry, the approach, the stack and the pie included, so an invader stacking at a door with its target in plain
view fires on it from outside (E3). A gaze step of the entry that cannot settle because the entrant is looking at a threat
counts as settled, so the entry carries on rather than waiting at the pie. Peek-and-cover and the ambush shoot only once the
facing has settled on the contact; a peek ducks only after a shot left the barrel (or on the click of an empty gun, where the
cover phase reloads), not after a refused one.
Tests: `entry_guard_fires_from_outside`, `gaze_search_turns_to_threat`, `combat_waits_for_facing`.

**W3. An empty gun is reloaded.** With a threat in view and a spare magazine, an empty gun is reloaded at once, not carried
on a walk (`auto_reload`; not mid-crossing, E4). A gun with no spare is not reloaded and not fired.
Tests: `fire_dry_gun_on_move_reloads`, `empty_pistol_no_spares`.

**W4. With no threat: look where you are going, or watch the doors.** A walking NPC looks along its path as far as it has a
clear line, up to `watch_look_ahead` px, so it looks through the doorway it is lining up and never at the jamb or the wall
beside it. A resting NPC (a hold, a reload, a move that has arrived, the Von-down fallback) turns among the doorways of its
room, `watch_door_dwell` s at each, outer doors included, skipping any under its feet or without a clear line. Outdoors, or in
a room with no doorway in line, it keeps the gaze it has; an NPC that was never given one looks where its body points.
Tests: `gaze_hold_watches_doors`, `gaze_walk_looks_ahead`, `gaze_fresh_npc_keeps_its_facing`.

**W5. A walk that has arrived stops.** An arrived move zeroes its steering input, so the NPC stands still while the next
decision (a slow Von) is in flight.
Tests: `gaze_arrival_stops`.

**W6. No sprinting with a shot to take.** A running character can neither shoot nor reload, so an NPC that has a shot available
(or an empty gun to reload) drops to a walk and takes it, instead of sprinting on past its range. Retreating is the exception
(`run_through_fire` on the RETREAT node): it is about leaving the line, not trading shots.
Tests: `ai_runs_to_destination`, `retreat_keeps_running`.

## Tuning (`GoalController`, group *Watch*)

`watch_look_ahead` (150 px), `watch_door_dwell` (2.5 s), `watch_lost_gaze` (2 s). The turn between doorways uses
`search_look_rate`.

## Not modelled

Shooting across low furniture an NPC can see over (a table, a counter): the line of fire is fully physical, as it is for
fire spots, flanks and the snapshot's `clear_shot`, so such a shot is not taken (the NPC still faces the enemy).
