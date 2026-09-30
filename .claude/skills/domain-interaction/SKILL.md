---
name: domain-interaction
description: Deep implementation detail for the Interaction domain (scenes/interaction/) — finding a reachable object and running one of its actions (sit, lie, …). Use when editing scenes/interaction/ or working on object interactions, the Space toggle, move_to snapping, or the interactable contract. Complements AGENTS.md, which holds the cross-domain interfaces.
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
ejected), moving it back on exit. **Space** again stops and steps back.

The component reads the character's existing `facing`, `global_position`, `aim_point` and
`has_item(id)`, and moves it. It discovers objects through the **interactable contract** — every
world object implements `get_interactions() -> Array` (plain data dicts: `id`, `label`, optional
`move_to` / `requires_item`), advertised via the optional `interactions` object field.

A non-player controller uses `interactions_in_reach()` + `interact_with(object, id)` to pick a
specific object and action instead of the random toggle.

## Interface recap (authoritative in AGENTS.md)

- **Interaction ↔ Character & Objects** (interface 8): the character exposes only opaque
  forwards — `try_interact()` (the player's Space toggle), `interactions_in_reach()` and
  `interact_with(object, id)` / `end_interaction()` (for a controller/AI), `is_busy()`
  (movement/actions lock) and `interaction_label()` (HUD). Objects advertise actions via
  `get_interactions()`.
