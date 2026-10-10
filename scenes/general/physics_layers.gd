class_name PhysicsLayers

## General domain: named physics-layer bits, shared read-only infrastructure (same role as
## Objects' `Wall.Side` enum) — a single source so "walls + solid furniture" isn't redefined
## as the same magic number in every file that raycasts against it.

## Walls + solid (non-see-over) furniture: the line-of-sight/line-of-fire query layer used by
## AI perception (agent_vision.gd), its debug mirror (vision_debug.gd), and Interaction
## (character_interaction.gd).
const SOLID := 1
