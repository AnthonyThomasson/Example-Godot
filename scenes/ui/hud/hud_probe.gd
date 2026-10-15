extends RefCounted

## UI hud: how the hud observers find an NPC's controller, shared by the match HUD and the spectator inspector: the child in
## the group `npc_controllers` (the AI controller, interface 7), which `goal_text()`, `debug_zones()` and
## `known_contacts_for_display()` are read off.


## The AI controller child of `character` (in the group `npc_controllers`), or null (also for the player, a null or a freed
## character).
static func controller_of(character: Node) -> Node:
	if character == null or not is_instance_valid(character):
		return null
	for child in character.get_children():
		if child.is_in_group(&"npc_controllers"):
			return child
	return null
