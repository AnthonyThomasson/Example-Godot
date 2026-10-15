---
name: domain-interaction
description: Deep implementation detail for the Interaction domain (scenes/interaction/) — finding a reachable object and running one of its actions (sit, lie, …). Use when editing scenes/interaction/ or working on object interactions, the Space toggle, move_to snapping, or the interactable contract. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Interaction domain

Kept deliberately isolated so it iterates alone. The character composes a `CharacterInteraction`
component (`interaction/`, built in `_ready()` like the physics components). The character never
learns what an interaction *means* — add/retune actions in the catalogue data alone.

## Behaviour (Space toggle)

`CharacterInteraction` shape-queries for reachable objects, keeps the actions whose
`requires_item` gate passes (`character.has_item`), targets the object nearest the mouse
(`aim_point`), and runs a random one of its valid actions — freezing the character (`is_busy()`).
For a `move_to` action it snaps the character onto the object and lets the two bodies overlap (a
temporary `add_collision_exception_with`, so a seat/bed isn't shoved and the character isn't
ejected), moving it back on exit. **Space** again stops and steps back. On exit (deferred out of the physics step) it hands the
object to the character's `keep_clear_of(body)`, which lifts the exception only once the body has cleared the object by the
character's `CLEAR_MARGIN`, so restoring the collision never finds an overlap to eject from; re-entering the object just left calls
`stop_clearing(body)` first and keeps the exception it still has.

The component reads the character's existing `facing`, `global_position`, `aim_point` and
`has_item(id)`, and moves it. It discovers objects through the **interactable contract** — every
world object implements `get_interactions() -> Array` (plain data dicts: `id`, `label`, optional
`move_to` / `requires_item`), advertised via the optional `interactions` object field.

A non-player controller uses `interactions_in_reach()` + `interact_with(object, id)` to pick a
specific object and action instead of the random toggle.

**Interfaces:** 8 (Interaction ↔ Character & Objects) — signatures in `architecture`.
