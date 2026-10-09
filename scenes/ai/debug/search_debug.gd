extends Node2D

## AI domain: an optional debug overlay for how an NPC is searching a room — the line-of-sight COVERAGE
## a `look_around` search move performs. It reads the sibling GoalController's `debug_search_coverage()`
## (all the room's sample points, which are still unseen, and the one being looked at now) and draws,
## while the NPC is covering a room: every sample point dim, the still-UNSEEN ones bright, a line + ring
## to the current target, and a "seen / total" readout. So you can watch the NPC turn and relocate until
## the whole room has been seen. Senses nothing, feeds nothing back (the "draw on its own child Node2D"
## convention, like tactics_debug.gd / vision_debug.gd).

## Whether to draw the coverage overlay. Off by default; in spectator mode the inspector turns it on
## only for the selected NPC (like the tactics overlay).
@export var show_search: bool = false
## The GoalController to read the coverage from (a sibling under the NPC).
@export var controller_path: NodePath = NodePath("../GoalController")

const SEEN_COLOR := Color(0.4, 0.8, 0.5, 0.35)   # dim green — a sampled point already seen
const UNSEEN_COLOR := Color(1.0, 0.85, 0.2)      # bright gold — still to be seen
const TARGET_COLOR := Color(1.0, 0.4, 0.2)       # red — the point being looked at / walked to now
const POINT_RADIUS := 2.5
const UNSEEN_RADIUS := 4.0
const TARGET_RADIUS := 8.0
const FONT_SIZE := 11

var _controller: Node   ## The GoalController read for the coverage state.
var _character: Node2D   ## The NPC body this overlay is a child of.


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_character = get_parent() as Node2D
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep drawing while paused, like the other overlays.


## Redraw every frame so the shrinking unseen set and the moving target track the live search.
func _process(_delta: float) -> void:
	if show_search:
		queue_redraw()


## Draw the sample points (dim = seen, bright = unseen), the current target with a line from the NPC,
## and a seen/total count — but only while the NPC is actively covering a room.
func _draw() -> void:
	if not show_search or _controller == null or _character == null or _character.get("is_dead") == true:
		return
	if not _controller.has_method("debug_search_coverage"):
		return
	var cov: Dictionary = _controller.debug_search_coverage()
	if not cov.get("active", false):
		return
	var points: Array = cov.get("points", [])
	var unseen: Array = cov.get("unseen", [])
	if points.is_empty():
		return
	# Every sampled point dim; those still unseen drawn brighter on top, so coverage fills in as they clear.
	for p in points:
		draw_circle(to_local(p as Vector2), POINT_RADIUS, SEEN_COLOR)
	for p in unseen:
		draw_circle(to_local(p as Vector2), UNSEEN_RADIUS, UNSEEN_COLOR)
	# The point it is looking at / moving to now: a line from the NPC + a ring.
	var target := to_local(cov.get("target", _character.global_position) as Vector2)
	draw_line(Vector2.ZERO, target, Color(TARGET_COLOR, 0.6), 1.5)
	draw_arc(target, TARGET_RADIUS, 0.0, TAU, 16, TARGET_COLOR, 2.0)
	# A seen / total readout beside the NPC.
	var seen: int = points.size() - unseen.size()
	draw_string(ThemeDB.fallback_font, Vector2(TARGET_RADIUS, -TARGET_RADIUS),
		"searched %d/%d" % [seen, points.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, UNSEEN_COLOR)
