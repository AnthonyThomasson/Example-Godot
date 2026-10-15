# Hearing

What an NPC hears and what it makes of it. The tests named under each behaviour assert this document.

Gunfire heard, a grenade coming down and the team radio are older senses with their own homes (`docs/grenades.md` G15, G16 and the
`domain-ai-perception` skill); this document holds footsteps. The pieces: `character_footsteps.gd` (the `footfall` event),
`goal_controller.gd` (the intake and the **Hearing** exports), `agent_perception.gd` (`process_footfall`, the `heard_footsteps` memory) and
`snapshot_options.gd` / `snapshot_sections.gd` (how it is worded for Von). See the `domain-character`, `domain-ai-perception` and
`domain-ai-snapshot` skills.

## Behaviours

**H1. Footsteps heard.** Every time a character's foot lands it posts a `footfall` event that says whose step it is (`character`) and
its gait (`running`, `crouched`). An NPC hears the steps of a character not of its own faction, through walls, out to a range set by
the gait:

| gait | heard within | export |
|---|---|---|
| walking | 250 px | `hear_walk` |
| running | 450 px | `hear_run` |
| crouched | 100 px | `hear_crouch` |

(Running wins over walking; a crouched body cannot run.) Its own side's steps it never takes for anyone's: the walker's `faction` is how
it knows its own team, as a person knows the sound of the squad around them. A character it can see right now is no news. A deafened
NPC (`docs/grenades.md` G15) hears none.

A heard step is remembered as `heard_footsteps` (`{ pos }`, one per walker, the latest step standing for it, kept `lead_memory_ttl`, 20 s;
`debug_memory()["footsteps"]`, `[{ pos, age }]` like `gunfire`). It is used three ways:
- an **INVESTIGATE lead**, like gunfire: "footsteps heard to the west, in the kitchen — just now — short route";
- a line of the awareness section while no hostile is known: "Footsteps heard to the west, in the kitchen, just now.";
- a reason to **suspect the room** it came from (`docs/grenades.md` G18): a doorway into it reads "footsteps heard there", and a stack
  that carries a stun takes STUN ENTRY into it; while a stun is in the stack, footsteps in a room a doorway leads into are not a lead.

Tests: `ai/perception/footsteps_heard_by_gait` (scripted: walk, run and crouch in and out of range through a wall, an ally unheard),
`ai/investigate/footsteps_lead` (real Von: a defender hears an invader in the next room and investigates),
`ai/grenade/stun_entry_footsteps_heard` (real Von: the stack bangs the room the steps came from).

## Numbers

The ranges are this game's own, set for scale: a walk is heard about a room away, a run farther, a crouched step only by someone right
beside the wall. Nothing here is drawn from a published source.

## Not modelled

The floor under the step (carpet as loud as tile), a step heard louder or softer by distance within the range, which way a walker is
going, a defender reacting to a stack at its door beyond investigating the steps (issue #51, out of scope), and the human's own
hearing (the Audio domain plays every step to the player).
