extends Node2D

## AI domain: an optional debug overlay that draws the NPC's *actual* visible area — the portions
## of the forward FOV cone and the 360° near-awareness bubble that have a direct, unobstructed line
## of sight back to the NPC. A ray fan asks the controller each frame where the NPC's sight ends
## (`debug_sight_end`, the perception's own rule: walls and TALL furniture block, low pieces are seen
## over) and builds a visibility polygon from the answers, so the shadows are exactly the sense's and
## show only the area that would trigger a detection. Toggle with `show_vision`. Draw-only —
## it senses nothing and feeds nothing back (follows the "draw on its own child Node2D" convention).

## Rays cast across the forward FOV arc (higher = smoother wall edges, more cost).
const CONE_RAYS := 64
## Rays cast for the 360° awareness-bubble sweep.
const BUBBLE_RAYS := 48

## Whether to draw the vision overlay at all.
@export var show_vision: bool = true
## The GoalController to read vision tunables from (a sibling under the NPC).
@export var controller_path: NodePath = NodePath("../GoalController")
## Fill colour for the forward view cone's line-of-sight area.
@export var cone_color: Color = Color(0.3, 0.8, 1.0, 0.12)
## Fill colour for the near-awareness bubble's line-of-sight area.
@export var bubble_color: Color = Color(1.0, 0.9, 0.3, 0.5)

var _controller: Node
var _character: Node2D
var _cone_poly: PackedVector2Array = PackedVector2Array()
var _bubble_poly: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_character = get_parent() as Node2D
	# Keep rebuilding/drawing while the tree is paused, so the spectator inspector can reveal a clicked
	# NPC's vision during a Space-pause (otherwise the visibility polygons wouldn't be built).
	process_mode = Node.PROCESS_MODE_ALWAYS


## Rebuild the visibility polygons every frame so they track the NPC's movement and facing.
func _process(_delta: float) -> void:
	if show_vision:
		_rebuild_visibility()
		queue_redraw()


## Draw the cached visibility polygons built in _process.
func _draw() -> void:
	if not show_vision or _controller == null or _character == null:
		return
	if _bubble_poly.size() >= 3:
		draw_polygon(_bubble_poly, [bubble_color])
	if _cone_poly.size() >= 3:
		draw_polygon(_cone_poly, [cone_color])


## Where the NPC's sight from `from` in `dir` ends: the first sight-blocking hit within `max_dist`, or the
## full-distance endpoint when the path is clear (the controller's `debug_sight_end`).
func _cast(from: Vector2, dir: Vector2, max_dist: float) -> Vector2:
	return _controller.debug_sight_end(from + dir * max_dist)


## Rebuild the LoS-masked visibility polygons for both the cone and the bubble.
## When vision is disabled (omniscient fallback) the bubble is drawn as a plain circle; the cone
## is skipped because the NPC sees everything regardless of facing.
func _rebuild_visibility() -> void:
	_cone_poly.clear()
	_bubble_poly.clear()
	if _controller == null or _character == null:
		return

	var facing: Vector2 = _character.facing
	var awareness: float = _controller.awareness_radius

	# Omniscient fallback: no raycasts, just plain geometry to mark the awareness bubble.
	if not _controller.vision_enabled:
		for i in range(BUBBLE_RAYS):
			_bubble_poly.append(Vector2.from_angle((float(i) / float(BUBBLE_RAYS)) * TAU) * awareness)
		return

	if not _controller.has_method("debug_sight_end"):
		return
	var from_pos: Vector2 = _character.global_position

	# Awareness bubble: 360° ray sweep clipped by LoS — walls reduce the radius in each direction.
	for i in range(BUBBLE_RAYS):
		var angle := (float(i) / float(BUBBLE_RAYS)) * TAU
		_bubble_poly.append(to_local(_cast(from_pos, Vector2.from_angle(angle), awareness)))

	# FOV cone: ray fan from left edge to right edge, each ray clipped at the first wall it hits.
	if facing == Vector2.ZERO:
		return
	var dist: float = _controller.view_distance
	var half_fov := deg_to_rad(_controller.fov_degrees) * 0.5
	var base := facing.angle()
	_cone_poly.append(Vector2.ZERO)
	for i in range(CONE_RAYS + 1):
		var t := float(i) / float(CONE_RAYS)
		var ray_angle := base - half_fov + t * deg_to_rad(_controller.fov_degrees)
		_cone_poly.append(to_local(_cast(from_pos, Vector2.from_angle(ray_angle), dist)))
