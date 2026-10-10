extends Node2D

## Draw layer for a blood pool. A wound pool is one lumpy filled blob per particle, in the shared
## blood color: each blob is a polygon built from the drop's stored per-vertex shape, so it reads as an
## organic splat rather than a circle and no two blobs match; overlapping blobs merge into a single,
## ragged puddle. A bleed-out pool draws its flow's cells through a threshold shader instead (see
## `_draw_flow`). Sits at a negative z_index so the pool draws beneath the player and furniture (like
## spent casings). Reads the particles or the flow from its parent control node (blood_pool.gd).

## The threshold runs per screen pixel on the bilinearly magnified field (edge width ~1 px via
## fwidth), so the outline is crisp yet smooth rather than a blurred alpha ramp.
const FLOW_SHADER := """
shader_type canvas_item;
uniform vec4 blood_color : source_color;
uniform vec4 rim_color : source_color;
uniform float opacity = 0.85;
uniform float threshold = 0.3;
void fragment() {
	float v = texture(TEXTURE, UV).r;
	float w = max(fwidth(v) * 0.75, 0.002);
	float a = smoothstep(threshold - w, threshold + w, v);
	vec3 c = mix(rim_color.rgb, blood_color.rgb, smoothstep(threshold, 0.9, v));
	COLOR = vec4(c, a * opacity);
}
"""
## Box-blur passes over the fill field, melting single frontier cells into their neighbours.
const BLUR_PASSES := 2
## Empty cells around the claimed ones, so the blur and the outline have room at the edge.
const PAD := 3

@onready var _pool := get_parent()  ## The blood pool (control node).

## The fill field as a texture; held in a member because one freed at the end of `_draw` renders white.
var _flow_texture: ImageTexture
## The threshold shader's material, created on the first flow draw.
var _flow_material: ShaderMaterial


func _ready() -> void:
	z_index = BloodConfig.z_index


func _draw() -> void:
	if _pool.flow:
		_draw_flow()
		return
	var color: Color = BloodConfig.color
	for p in _pool.particles:
		var center: Vector2 = p["pos"]
		var radius: float = p["radius"]
		var shape: PackedFloat32Array = p["shape"]
		var verts := shape.size()
		var points := PackedVector2Array()
		for i in verts:
			var angle := TAU * i / verts
			points.append(center + Vector2(cos(angle), sin(angle)) * radius * shape[i])
		draw_colored_polygon(points, color)


## A flowing pool: the claimed cells' fill levels are written to a small field, box-blurred so single
## cells at the frontier melt into their neighbours, drawn magnified with linear
## filtering through a threshold shader. The contour is one smooth outline that creeps outward, never
## separate dots.
func _draw_flow() -> void:
	var flow: BloodFlow = _pool.flow
	if flow.cells.is_empty():
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _flow_material == null:
		var shader := Shader.new()
		shader.code = FLOW_SHADER
		_flow_material = ShaderMaterial.new()
		_flow_material.shader = shader
		material = _flow_material
	var base := Color(BloodConfig.color.r, BloodConfig.color.g, BloodConfig.color.b, 1.0)
	_flow_material.set_shader_parameter("blood_color", base)
	_flow_material.set_shader_parameter("rim_color", base.darkened(BloodConfig.flow_edge_darken))
	_flow_material.set_shader_parameter("opacity", BloodConfig.color.a)

	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in flow.cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i(PAD, PAD)
	hi += Vector2i(PAD, PAD)
	var w := hi.x - lo.x + 1
	var h := hi.y - lo.y + 1

	var field := PackedFloat32Array()
	field.resize(w * h)
	for c in flow.cells:
		field[(c.y - lo.y) * w + (c.x - lo.x)] = flow.fill(c)
	for pass_i in BLUR_PASSES:
		field = _box_blur(field, w, h)

	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in field.size():
		bytes[i] = int(clampf(field[i], 0.0, 1.0) * 255.0)
	var image := Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes)
	var size := BloodConfig.flow_cell_size
	# Held in a member: a texture freed at the end of _draw would render white.
	_flow_texture = ImageTexture.create_from_image(image)
	draw_texture_rect(_flow_texture, Rect2(Vector2(lo) * size, Vector2(w, h) * size), false)


## One 3x3 box-blur pass (edges read as empty).
func _box_blur(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var sum := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					sum += src[(y + dy) * w + x + dx]
			out[y * w + x] = sum / 9.0
	return out
