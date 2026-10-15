extends Node2D

## Physics System, blood: draw layer for a bleed-out pool: its flow's cells drawn through a threshold shader (see
## `_draw_flow`). Draws at its pool's z_index (`BloodConfig.z_index`, set on the pool by the spawner): beneath what lies
## on the floor, the player and furniture. Reads the flow from its parent control node (blood_pool.gd).

## The threshold runs per screen pixel on the bilinearly magnified field (edge width ~1 px via
## fwidth), so the outline is crisp yet smooth rather than a blurred alpha ramp.
const FLOW_SHADER := """
shader_type canvas_item;
uniform vec4 blood_color : source_color;
uniform vec4 rim_color : source_color;
uniform float opacity = 0.85;
uniform float threshold = 0.3;
uniform vec2 field_px = vec2(1.0);
uniform float tuft_spread = 0.8;
uniform float tuft_px = 2.5;
uniform float tuft_contrast = 0.2;
uniform float soak_opacity = 0.65;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	// Carpet and rug blood soaks in tuft by tuft: the pool is cut into irregular tufts (the nearest of a jittered
	// point per cell, fixed to the pool in world pixels), each with its own soak rate and shade of red. Only the
	// colour changes: the blood stays opaque over its whole outline, so no fibre shows through.
	vec2 p = UV * field_px / tuft_px;
	vec2 base = floor(p);
	float f1 = 9.0;
	float f2 = 9.0;
	vec2 tuft = base;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = base + vec2(float(i), float(j));
			float d = distance(p, c + vec2(hash(c), hash(c + vec2(19.7, 3.1))));
			if (d < f1) {
				f2 = f1;
				f1 = d;
				tuft = c;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float rate = hash(tuft + vec2(3.3, 8.9));
	float shade = hash(tuft + vec2(37.1, 11.7));
	float spread = tuft_spread * 0.7;
	float s = clamp((t.g - rate * spread) / max(1.0 - spread, 0.001), 0.0, 1.0);
	float v = t.r;
	float w = max(fwidth(v) * 0.75, 0.002);
	float a = smoothstep(threshold - w, threshold + w, v);
	vec3 fresh = mix(rim_color.rgb, blood_color.rgb, smoothstep(threshold, 0.9, v));
	vec3 soaked = mix(blood_color.rgb * (1.0 - tuft_contrast), min(blood_color.rgb * (1.0 + 0.6 * tuft_contrast), vec3(1.0)), shade);
	vec3 col = mix(fresh, soaked, s);
	// A faint darker crease where two tufts meet, so the texture reads as tufts without opening a gap.
	col *= 1.0 - 0.5 * tuft_contrast * s * (1.0 - smoothstep(0.0, 0.18, f2 - f1));
	// Soaked blood is thinner: the pattern of the carpet or rug shows through it (never a hole).
	a *= mix(1.0, soak_opacity * (0.9 + 0.1 * shade), s);
	COLOR = vec4(col, a * opacity);
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


func _draw() -> void:
	_draw_flow()


## The claimed cells' fill levels are written to a small field, box-blurred so single
## cells at the frontier melt into their neighbours, drawn magnified with linear
## filtering through a threshold shader. The contour is one smooth outline that creeps outward, never
## separate dots.
func _draw_flow() -> void:
	var flow: BloodFlow = _pool.flow
	if flow.cells.is_empty():
		return
	var covered: Array = flow.cells.keys() + flow.trail.keys()
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
	for c in covered:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i(PAD, PAD)
	hi += Vector2i(PAD, PAD)
	var w := hi.x - lo.x + 1
	var h := hi.y - lo.y + 1

	var field := PackedFloat32Array()
	field.resize(w * h)
	for c in covered:
		field[(c.y - lo.y) * w + (c.x - lo.x)] = flow.fill(c)
	for pass_i in BLUR_PASSES:
		field = _box_blur(field, w, h)

	# Red = fill, green = how far the blood has sunk in (left at cell resolution;
	# the texture filtering smooths it, and the shader soaks it in tuft by tuft).
	var bytes := PackedByteArray()
	bytes.resize(w * h * 2)
	for i in field.size():
		bytes[i * 2] = int(clampf(field[i], 0.0, 1.0) * 255.0)
	if flow.has_porous():
		for c in flow.cells:
			bytes[((c.y - lo.y) * w + (c.x - lo.x)) * 2 + 1] = int(clampf(flow.soak_level(c), 0.0, 1.0) * 255.0)
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RG8, bytes)
	var size := BloodConfig.flow_cell_size
	_flow_material.set_shader_parameter("field_px", Vector2(w, h) * size)
	_flow_material.set_shader_parameter("tuft_spread", BloodConfig.soak_tuft_spread)
	_flow_material.set_shader_parameter("tuft_px", BloodConfig.soak_tuft_size)
	_flow_material.set_shader_parameter("tuft_contrast", BloodConfig.soak_tuft_contrast)
	_flow_material.set_shader_parameter("soak_opacity", BloodConfig.soak_opacity)
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
