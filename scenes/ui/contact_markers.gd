extends Node2D

## UI domain: world-space contact-indicator overlay for the spectator inspector. When an NPC is
## selected, this node draws a coloured ring + name label at EACH CHARACTER THE SELECTED NPC HAS
## IN MEMORY — showing the selected NPC's own knowledge of the world, not the contacts' state.
##
## Drawn in the main scene (world space), not under the CanvasLayer, so positions map directly to
## world coordinates. The SpectatorInspector pushes fresh contacts every frame (set_contacts), which
## queues the redraw — so the rings redraw live, and hold steady while the match is Space-paused.

const RING_RADIUS := 28.0
const FONT_SIZE := 14
## Opacity for a currently-visible contact vs a stale (remembered but not in sight) one.
const ALPHA_VISIBLE := 0.9
const ALPHA_STALE := 0.45

## Hostile ring colour (red).
const COLOR_HOSTILE := Color(1.0, 0.25, 0.25)
## Neutral / ally ring colour (amber).
const COLOR_NEUTRAL := Color(1.0, 0.75, 0.2)

var _contacts: Array = []  ## Array of { pos, name, hostile, visible }


## Replace the contacts list and queue a redraw. Called by SpectatorInspector every frame while an NPC
## is selected, so the rings track the characters as they move and as the NPC's knowledge updates.
func set_contacts(contacts: Array) -> void:
	_contacts = contacts
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for c in _contacts:
		var world_pos: Vector2 = c["pos"]
		var hostile: bool = c["hostile"]
		var visible: bool = c["visible"]
		var base := COLOR_HOSTILE if hostile else COLOR_NEUTRAL
		base.a = ALPHA_VISIBLE if visible else ALPHA_STALE
		draw_arc(world_pos, RING_RADIUS, 0.0, TAU, 24, base, 2.5)
		var label: String = c["name"] + (" ●" if visible else " ?")
		var str_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, world_pos + Vector2(-str_w * 0.5, -RING_RADIUS - 5.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, base)
