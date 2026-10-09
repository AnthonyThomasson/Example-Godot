extends CanvasLayer

## UI domain, spectator inspector: the debug lens for the 2-AI spectator match. SPACE pauses/resumes.
## A LEFT-CLICK on an NPC selects it — revealing ONLY that NPC's debug overlays (the enabled ones) and
## hiding every other NPC's; clicking it again, or empty ground, clears the selection. With an NPC
## selected, a LEFT-CLICK on one of its tactical points (a zone marker) highlights that point and opens
## a detail panel with its kind, label and the reasoning text Von read (cover, route, range). No NPC
## shows any overlay until it is clicked — the debug view is always focused on one NPC at a time.
##
## It runs PROCESS_MODE_ALWAYS so Space and clicks work while the tree is paused (freeze the match, then
## inspect). A decoupled observer like the other spectator UI: it reads only published surfaces — the
## combatants' public `global_position`, the framing camera for the cursor's world point, and each NPC's
## `debug_zones()` (duck-typed) for the point details — and flips the debug-overlay toggles by the same
## duck-typed property names `main.gd`'s `_configure_debug` uses (`show_actions` / `show_path` /
## `show_vision` / `show_tactics` / `show_room_zones`). Main builds it in spectator mode. Player-mode
## input is untouched: Space stays the player's INTERACT there (this node exists only in the match).

## World-space pick radius (px) around the cursor within which a click selects an NPC.
const PICK_RADIUS := 48.0
## World-space pick radius (px) within which a click on the selected NPC's zone opens its details.
const ZONE_PICK_RADIUS := 20.0
## The match HUD goal readout's left edge, width and bottom (it occupies x 24, y 76..356) — the detail
## panel mirrors these so a clicked point's details stack directly under the goal text.
const GOAL_LEFT := 24.0
const GOAL_WIDTH := 560.0
const GOAL_BOTTOM := 356.0

const ContactMarkers := preload("res://scenes/ui/contact_markers.gd")

var _combatants: Array = []  ## The NPCs to pick from (public nodes), handed in by Main.
var _flags: Dictionary = {}  ## Which overlay toggles to enable on the selected NPC (from the setup menu).
var _selected: Node = null   ## The NPC whose overlays are shown, or null.
var _selected_ctrl: Node = null ## The selected NPC's controller, cached for live marker refreshes.
var _detail: Label           ## The clicked tactical point's detail text (hidden when none).
var _contact_markers: Node2D ## World-space overlay that draws the selected NPC's contact knowledge.


## Keep running while paused and build the hint + detail UI. `flags` is the set of overlay toggles the
## setup menu enabled (property name -> bool); a selected NPC shows exactly those. Called by Main.
func setup(combatants: Array, flags: Dictionary) -> void:
	_combatants = combatants
	_flags = flags
	process_mode = Node.PROCESS_MODE_ALWAYS
	# World-space contact-indicator overlay added as a sibling so it draws in world coordinates.
	_contact_markers = ContactMarkers.new()
	_contact_markers.name = "ContactMarkers"
	get_parent().add_child(_contact_markers)
	# The clicked point's details sit top-left, directly beneath the match HUD's goal readout.
	_detail = _make_label(HORIZONTAL_ALIGNMENT_LEFT, 22)
	_detail.offset_left = GOAL_LEFT
	_detail.offset_right = GOAL_LEFT + GOAL_WIDTH
	_detail.offset_top = GOAL_BOTTOM + 8.0
	_detail.offset_bottom = GOAL_BOTTOM + 8.0 + 240.0
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.visible = false
	_select(null)  # start with every NPC's overlays hidden — nothing is shown until clicked


## A label on this layer that never swallows a click meant for an NPC. The caller anchors/positions it.
func _make_label(align: int, size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label


## SPACE toggles pause; a left-click selects an NPC, or (with one selected) inspects the tactical point
## under the cursor. Handled here so it works in the player-less match and while the tree is paused.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(Keybinds.PAUSE) and not event.is_echo():
		_set_paused(not get_tree().paused)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(_cursor_world())


## Pause or resume the whole tree (this node keeps running — PROCESS_MODE_ALWAYS) and show/hide the hint.
func _set_paused(paused: bool) -> void:
	get_tree().paused = paused


## The cursor's world position via the active (spectator framing) camera; the raw screen point if none.
func _cursor_world() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	return cam.get_global_mouse_position() if cam != null else get_viewport().get_mouse_position()


## Route a click: a tactical point of the selected NPC takes priority (show its details); otherwise pick
## the NPC under the cursor (toggling selection off on a second click or a miss).
func _on_click(world: Vector2) -> void:
	if _selected != null and is_instance_valid(_selected):
		var zone := _zone_at(world)
		if not zone.is_empty():
			_show_zone(zone)
			return
	var npc := _npc_at(world)
	_select(null if npc == _selected else npc)


## The NPC nearest `world` within PICK_RADIUS, or null when the click missed everyone.
func _npc_at(world: Vector2) -> Node:
	var best: Node = null
	var best_d := PICK_RADIUS
	for npc in _combatants:
		if not is_instance_valid(npc):
			continue
		var d: float = (npc.global_position as Vector2).distance_to(world)
		if d <= best_d:
			best_d = d
			best = npc
	return best


## The selected NPC's tactical zone nearest `world` within ZONE_PICK_RADIUS (its `debug_zones()` entry
## `{ point, category, label, desc }`), or an empty dict when the click wasn't on one.
func _zone_at(world: Vector2) -> Dictionary:
	var ctrl := _controller_of(_selected)
	if ctrl == null:
		return {}
	var best := {}
	var best_d := ZONE_PICK_RADIUS
	for zone in ctrl.debug_zones():
		var d: float = (zone["point"] as Vector2).distance_to(world)
		if d <= best_d:
			best_d = d
			best = zone
	return best


## Refresh the contact markers every frame so the rings track characters as they move (and as the
## selected NPC's knowledge of them updates). Runs while paused too, where the knowledge holds steady.
func _process(_delta: float) -> void:
	if _selected != null:
		_refresh_markers()


## Select `npc` (null = none): show only the selected NPC's own overlays and cache its controller for
## the live marker refresh. Clears any tactical-point detail/highlight from the previous selection
## (on the PREVIOUS NPC, not the new one — _clear_zone must run before _selected is reassigned).
func _select(npc: Node) -> void:
	_clear_zone()
	_selected = npc
	_selected_ctrl = _controller_of(npc) if npc != null else null
	# Show only the selected NPC's own overlays; hide every other NPC's.
	for c in _combatants:
		if is_instance_valid(c):
			_set_overlays(c, c == npc)
	_refresh_markers()


## Push the selected NPC's current contact knowledge to the world-space marker overlay (empty when
## nothing is selected), so each ring sits on the position that NPC last knew the contact to be at.
func _refresh_markers() -> void:
	if _contact_markers == null:
		return
	var display: Array = []
	if _selected_ctrl != null and is_instance_valid(_selected_ctrl) and _selected_ctrl.has_method("known_contacts_for_display"):
		for c in _selected_ctrl.known_contacts_for_display():
			display.append({
				"pos": c["pos"],
				"name": c["name"],
				"hostile": c["hostile"],
				"visible": c["visible"],
			})
	_contact_markers.set_contacts(display)


## Reveal (`on`) or hide one NPC's debug overlays by duck-typed property name. When revealing, each
## toggle takes its setup-menu value from `_flags`; when hiding, all go false. Forces a redraw because a
## paused overlay's own _process may not run.
func _set_overlays(npc: Node, on: bool) -> void:
	for child in npc.get_children():
		var touched := false
		for flag in _flags:
			if flag in child:
				child.set(flag, _flags[flag] if on else false)
				touched = true
		if touched and child.has_method("queue_redraw"):
			child.queue_redraw()


## Highlight the clicked tactical point on the selected NPC and fill the detail panel with its kind,
## label and the reasoning text Von read.
func _show_zone(zone: Dictionary) -> void:
	var overlay := _tactics_overlay(_selected)
	if overlay != null:
		overlay.set_focus(zone["point"])
	var label: String = zone.get("label", "")
	var desc: String = zone.get("desc", "")
	_detail.text = "%s%s%s" % [String(zone["category"]).to_upper(),
		"  ·  " + label if label != "" else "", "\n" + desc if desc != "" else ""]
	_detail.visible = true


## Drop any tactical-point detail: clear the highlight on the selected NPC and hide the panel.
func _clear_zone() -> void:
	var overlay := _tactics_overlay(_selected)
	if overlay != null:
		overlay.clear_focus()
	if _detail != null:
		_detail.visible = false


## The NPC's GoalController (the child exposing `debug_zones()`), or null.
func _controller_of(npc: Node) -> Node:
	if npc == null or not is_instance_valid(npc):
		return null
	for child in npc.get_children():
		if child.has_method("debug_zones"):
			return child
	return null


## The NPC's tactics overlay (the child exposing `set_focus()`), or null.
func _tactics_overlay(npc: Node) -> Node:
	if npc == null or not is_instance_valid(npc):
		return null
	for child in npc.get_children():
		if child.has_method("set_focus"):
			return child
	return null
