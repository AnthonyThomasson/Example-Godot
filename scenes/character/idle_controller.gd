extends Node

## Placeholder controller for a non-player character. It satisfies the character's
## controller contract (a child with `control(character, delta)`) but issues no intent, so
## the character stands still and does nothing. Swap in an AI brain with the same contract
## to drive the NPC — no other changes to the character are needed.

## Called each physics frame by the character. Does nothing (the NPC is idle for now).
func control(_character, _delta: float) -> void:
	pass
