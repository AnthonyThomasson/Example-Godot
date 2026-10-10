extends Node2D

## Draws an EnvironmentObject: its pixel art (when it has an `art` painter) or its flat shape
## and name label, either way through the damage-deformed silhouette.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

@onready var _obj := get_parent()
var _art: Texture2D  ## The piece's pixel-art texture, or null for the flat shape + label.

func _ready() -> void:
	if _obj.art != "":
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_art = ObjectArt.texture(_obj.art, _obj.size, _obj.color, _obj.facing, _obj.object_material, _obj.art_opts)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var shape: String = _obj.shape_type
	var size: Vector2 = _obj.size
	var color: Color = _obj.color
	var text_color: Color = _obj.text_color

	# Damage-deformed silhouette (dents, missing pieces) + crack/hole marks. Impact
	# state lives on the Deformable physics component the object composes.
	var deformable = _obj._deformable
	var impacts: Array = deformable.impacts if deformable else []
	var damage_total: float = deformable.damage_total if deformable else 0.0

	if _art:
		_draw_drop_shadow(shape, size, impacts)
		var marks := color.darkened(ObjectArtConfig.tone_outline)
		Deformation.draw_shape(self, shape, size, color, marks, impacts, damage_total,
				Deformation.NO_COLOR, Deformation.NO_COLOR, Deformation.NO_COLOR, _art)
		return

	Deformation.draw_shape(self, shape, size, color, text_color, impacts, damage_total)

	# Draw the object's name centered on it.
	var name_text: String = _obj.object_name
	var font: Font = ThemeDB.fallback_font
	var font_size := 14
	var text_size := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := Vector2(-text_size.x / 2.0, font_size / 2.0)
	draw_string(font, pos, name_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)


## The art's silhouette (its alpha, through the deformed outline) cast on the floor away from the
## light, longer for taller pieces (`coverage`); flat decor casts none. The offset is fixed in
## world space, so the shadow stays put relative to the light as a shoved piece spins.
func _draw_drop_shadow(shape: String, size: Vector2, impacts: Array) -> void:
	var offset := minf(_obj.coverage * ObjectArtConfig.drop_shadow_per_coverage, ObjectArtConfig.drop_shadow_max)
	if not _obj.solid or offset <= 0.0 or ObjectArtConfig.drop_shadow_alpha <= 0.0:
		return
	var poly := Deformation.shape_polygon(shape, size, impacts)
	if not Deformation.is_valid_polygon(poly):
		poly = Deformation.base_ring(shape, size)
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(p / size + Vector2(0.5, 0.5))
	var away := -ObjectArtConfig.light_from.normalized()
	var shift := global_transform.basis_xform_inv(away).normalized() * offset
	draw_colored_polygon(Transform2D(0.0, shift) * poly, Color(0.0, 0.0, 0.0, ObjectArtConfig.drop_shadow_alpha), uvs, _art)
