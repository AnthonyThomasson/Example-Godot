extends Node2D

## Lighting domain (private, draw-only): a room's ceiling fixture seen from below, a bare bulb on its flex, drawn unshaded at
## `DrawLayers.OVERHEAD` (it hangs over whoever walks under it), dimming with its light's rhythm (WorldLighting sets its
## `modulate`). Built by WorldLighting at the room's centre beside the fixture's light.

const FLEX := Color(0.08, 0.08, 0.08)
const CORE := Color(1.0, 1.0, 0.9)

var _color := Color.WHITE  ## The light's colour, the bulb glowing in it.


## A fixture glowing in `color`, drawn through the unshaded `material`.
func setup(color: Color, unshaded: Material) -> Node2D:
	name = "Fixture"
	_color = color
	material = unshaded
	z_as_relative = false
	z_index = DrawLayers.OVERHEAD
	return self


func _draw() -> void:
	draw_line(Vector2(-1, -7), Vector2(0, -2), FLEX, 1.0)
	draw_circle(Vector2.ZERO, 3.0, _color.lightened(0.45))
	draw_circle(Vector2.ZERO, 1.5, CORE)
