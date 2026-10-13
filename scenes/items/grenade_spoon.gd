class_name GrenadeSpoon extends Item

## A grenade's spoon (the safety lever), the tiny prop that pops off as it is thrown and lies on the floor. It is a
## `DroppedItem` carrying this item, so it falls, bounces and skids like one; visual only, and the Despawner keeps their
## number in check. Never held.

const SpoonPainter = preload("res://scenes/items/art/spoon_painter.gd")
## The spoon's footprint lying flat (px): across, along.
const SIZE := Vector2(3.0, 8.0)
## Speed (px/s) it is flung off at, to the side of the throw.
const TOSS := 90.0


func _init() -> void:
	display_name = "Spoon"
	reach = 0.0


## Let a spoon go from `at` as a grenade is thrown along `throw_angle`: it spins off to one side into `parent`.
static func pop(at: Vector2, throw_angle: float, parent: Node) -> Node:
	var side := 1.0 if randf() < 0.5 else -1.0
	var velocity := Vector2.from_angle(throw_angle + side * randf_range(1.0, 2.0)) * TOSS * randf_range(0.6, 1.0)
	var node := DroppedItem.spawn(GrenadeSpoon.new(), at, randf() * TAU, velocity, parent, at)
	Despawner.track(node)
	return node


## The spoon lying on the floor, centered at `at` along `angle`, tinted by `modulate`.
func draw_dropped(canvas: CanvasItem, at: Vector2, angle: float, modulate: Color = Color.WHITE,
		_opts: Dictionary = {}) -> void:
	var turn := angle - PI * 0.5
	var tex := PixelArt.render_turned(SpoonPainter, SIZE, Color(0.62, 0.64, 0.68), PixelArt.snap_angle(turn), "metal")
	canvas.draw_set_transform(at, turn, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-SIZE * 0.5, SIZE), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
