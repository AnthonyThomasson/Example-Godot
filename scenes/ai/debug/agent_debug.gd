extends Node2D

## AI domain: an optional debug overlay that draws, in the world next to the NPC, what its brain is
## doing — a floating ACTION LABEL (the controller's live decision, from `debug_status()`) and its
## current MOVEMENT PATH (the NavigationAgent2D's path, polyline + waypoints + target marker). Two
## independent toggles (`show_actions`, `show_path`). Draw-only — it reads the sibling GoalController
## and NavigationAgent2D through their public API, senses nothing and feeds nothing back (follows the
## "draw on its own child Node2D" convention, like vision_debug.gd).

## Whether to draw the floating action label above the NPC.
@export var show_actions: bool = true
## Whether to draw the NPC's current navigation path.
@export var show_path: bool = true
## The GoalController to read the action status from (a sibling under the NPC).
@export var controller_path: NodePath = NodePath("../GoalController")
## The NavigationAgent2D to read the current path from (a sibling under the NPC).
@export var agent_path: NodePath = NodePath("../NavigationAgent2D")
## Colour of the action label text.
@export var label_color: Color = Color(1, 1, 1, 0.9)
## Colour of the movement-path line and markers.
@export var path_color: Color = Color(0.4, 0.9, 1.0, 0.8)
## Pixels below the NPC's origin to anchor the label (keeps it clear of the match HUD panel above).
@export var label_offset: float = 28.0

## Point size of the label font.
const FONT_SIZE := 16
## Radius (px) of a waypoint dot on the path.
const WAYPOINT_RADIUS := 2.5
## Radius (px) of the ring drawn at the path's final target.
const TARGET_RADIUS := 6.0

var _controller: Node             ## The GoalController read for the action label.
var _agent: NavigationAgent2D     ## The nav agent read for the movement path.
var _character: Node2D            ## The NPC body this overlay is a child of.


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_agent = get_node_or_null(agent_path) as NavigationAgent2D
	_character = get_parent() as Node2D
	# Keep drawing while the tree is paused, so the spectator inspector can reveal a clicked NPC's label
	# and path during a Space-pause.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Redraw every frame so the label and path track the NPC's live decision and movement.
func _process(_delta: float) -> void:
	if show_actions or show_path:
		queue_redraw()


## Draw the current path (remaining waypoints + target) and the action label.
func _draw() -> void:
	if _character == null or _character.get("is_dead") == true:
		return
	if show_path and _agent != null:
		_draw_path()
	if show_actions and _controller != null and _controller.has_method("debug_status"):
		_draw_label(_controller.debug_status())


## Draw the agent's remaining navigation path as a polyline, a dot at each waypoint, and a ring at the
## final target. Nothing is drawn when the path has no remaining segment (an idle/arrived NPC).
func _draw_path() -> void:
	var path: PackedVector2Array = _agent.get_current_navigation_path()
	if path.size() < 2:
		return
	var from: int = min(_agent.get_current_navigation_path_index(), path.size() - 1)
	var local: PackedVector2Array = PackedVector2Array()
	local.append(to_local(_character.global_position))  # start the line at the NPC itself
	for i in range(from, path.size()):
		local.append(to_local(path[i]))
	if local.size() >= 2:
		draw_polyline(local, path_color, 2.0)
	for i in range(from, path.size()):
		draw_circle(to_local(path[i]), WAYPOINT_RADIUS, path_color)
	draw_arc(to_local(path[path.size() - 1]), TARGET_RADIUS, 0.0, TAU, 16, path_color, 1.5)


## Draw the action-status text centred above the NPC's body.
func _draw_label(text: String) -> void:
	if text == "":
		return
	var font: Font = ThemeDB.fallback_font
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE).x
	var pos := Vector2(-width / 2.0, label_offset)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, label_color)
