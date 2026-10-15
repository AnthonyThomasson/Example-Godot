extends RefCounted

## UI hud: how the hud observers find a character's controller, shared by the match HUD and the spectator inspector. The
## controller is the child with `control` (the controller contract, interface 7): the AI controller, or the player's.


## The controller child of `character` (the node with `control`), or null (also for a null or freed character).
static func controller_of(character: Node) -> Node:
	if character == null or not is_instance_valid(character):
		return null
	for child in character.get_children():
		if child.has_method("control"):
			return child
	return null
