extends Node2D

## Character DRAW layer. Renders the character as top-down pixel art (painted through the Art
## domain's PixelArt) in separate parts, each at its own angle from the character's pose: a drop
## shadow, the shoulders, the head (with its shadow on the shoulders) shifted by the pose's lean
## and breath, then the item's own weapon, then the fists the held item wants shown, gripping it,
## and last the wound marks. Shots dent and darken the shoulders and any part they passed through.
## Each part is lit for the nearest lighting step and drawn rotated to its exact angle. Reads the
## body radius, pose, held item and wounds from the character and hand positions/size from the
## hands sibling. Appearance only — no item-specific weapon logic lives here (that's each Item's
## draw_weapon()).

const BodyPainter = preload("res://scenes/character/body_painter.gd")
const HeadPainter = preload("res://scenes/character/head_painter.gd")
const HandPainter = preload("res://scenes/character/hand_painter.gd")

@export var body_color: Color = Color(0.32549, 0.65098, 1.0)  ## Shirt color.
@export var hand_color: Color = Color(0.93, 0.76, 0.6)        ## Hands: skin, or a glove color.
@export var skin_color: Color = Color(0.93, 0.76, 0.6)        ## Face and ears.
@export var hair_color: Color = Color(0.36, 0.24, 0.14)       ## Hair, or the headwear's color.
## "short", "long", "buzz", "beanie" or "cap".
@export_enum("short", "long", "buzz", "beanie", "cap") var hair_style: String = "short"
@export var backpack: bool = false                            ## Wear a backpack.
@export var pack_color: Color = Color(0.3, 0.32, 0.26)        ## Backpack color.

@onready var _character := get_parent()   ## Character — body radius, pose, held item.
@onready var _hands := $"../Hands"        ## Sibling — hand positions / size.


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	queue_redraw()  # facing / items change continuously.


func _draw() -> void:
	var r: float = _character.radius
	var size := Vector2(r * 2.0, r * 2.0)
	var pose = _character.pose
	var torso: float = pose.torso_angle - PI * 0.5  # Canonical art faces +y.
	var body := PixelArt.render_turned(BodyPainter, size, body_color, PixelArt.snap_angle(torso), "fabric",
		{ "backpack": backpack, "pack": pack_color })
	var deformable = _character._deformable
	# Impacts are recorded relative to the shoulders (character.take_hit), so they turn with them.
	var impacts := _turned(deformable.impacts if deformable else [], pose.torso_angle)
	var damage_total: float = deformable.damage_total if deformable else 0.0
	var item: Item = _character.current_item()
	var hands: Array = item.visible_hands() if item else []

	_draw_shadow(body, size, impacts, torso)
	# Shoulders: the art through the flesh silhouette deformed by any shots (dents + darkening).
	Deformation.draw_shape(self, "circle", size, body_color, CharacterConfig.flesh_crack_color,
		impacts, damage_total, Deformation.NO_COLOR, Deformation.NO_COLOR, Deformation.NO_COLOR,
		body, torso, false)
	_draw_head(pose, impacts, damage_total)
	if item:
		item.draw_weapon(self, _character)
	for hand in hands:
		_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, impacts, damage_total)
	# Wound marks over everything, so a hit hand shows its wound: dark-red holes and cracks that
	# read as bloody gashes (config-driven).
	Deformation.draw_marks(self, impacts, CharacterConfig.flesh_crack_color,
		CharacterConfig.flesh_hole_color, CharacterConfig.flesh_scorch_color)


## The body's drop shadow: the art's own silhouette through the deformed outline, offset away from
## the light in world space by its height proxy (flesh `coverage`), like furniture.
func _draw_shadow(body: Texture2D, size: Vector2, impacts: Array, angle: float) -> void:
	var offset := minf(CharacterConfig.flesh_coverage * ArtConfig.drop_shadow_per_coverage, ArtConfig.drop_shadow_max)
	if offset <= 0.0 or ArtConfig.drop_shadow_alpha <= 0.0:
		return
	var poly := Deformation.shape_polygon("circle", size, impacts)
	if not Deformation.is_valid_polygon(poly):
		poly = Deformation.base_ring("circle", size)
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(p.rotated(-angle) / size + Vector2(0.5, 0.5))
	var shift := global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized() * offset
	draw_colored_polygon(Transform2D(0.0, shift) * poly, Color(0.0, 0.0, 0.0, ArtConfig.drop_shadow_alpha), uvs, body)


## The head at the pose's offset and angle, casting its shadow onto the shoulders first (the head
## sits above them, so its silhouette darkens them a few px away from the light).
func _draw_head(pose, impacts: Array, damage_total: float) -> void:
	var px := ArtConfig.pixel_size
	var side := float(HeadPainter.canvas_for(HeadPainter.radius_for(roundi(_character.radius * 2.0 / px)))) * px
	var size := Vector2(side, side)
	var angle: float = pose.head_angle - PI * 0.5
	var tex := PixelArt.render_turned(HeadPainter, size, skin_color, PixelArt.snap_angle(angle), "",
		{ "skin": skin_color, "hair": hair_color, "hair_style": hair_style })
	var at: Vector2 = pose.head_offset
	var drop := global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized() \
		* ArtConfig.cast_shadow_px * px
	draw_set_transform(at + drop, angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(0.0, 0.0, 0.0, ArtConfig.cast_shadow_darken))
	_draw_part(tex, size, at, angle, impacts, damage_total, skin_color)


## A fist at the given hand (0 = left, 1 = right), turned to `angle`, dented by the shots that
## passed through where it is and darkened like the body.
func _draw_hand(hand: int, angle: float, impacts: Array, damage_total: float) -> void:
	var diameter: float = _hands.hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var tex := PixelArt.render_turned(HandPainter, size, hand_color, PixelArt.snap_angle(angle), "",
		{ "side": -1 if hand == 0 else 1 })
	_draw_part(tex, size, _hands.hand_position(hand), angle, impacts, damage_total, hand_color)


## One round part's art (`tex` spanning `size`) at `at`, turned to `angle`: through its silhouette
## dented by the shots that passed through it, darkened by the body's damage.
func _draw_part(tex: Texture2D, size: Vector2, at: Vector2, angle: float, impacts: Array,
		damage_total: float, color: Color) -> void:
	draw_set_transform(at, 0.0, Vector2.ONE)
	Deformation.draw_shape(self, "circle", size, color, color, _through(impacts, at, size.x * 0.5),
		damage_total, Deformation.NO_COLOR, Deformation.NO_COLOR, Deformation.NO_COLOR, tex, angle, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## `impacts` turned by `angle`: from the shoulder-relative frame they're recorded in to the drawn one.
static func _turned(impacts: Array, angle: float) -> Array:
	var out := []
	for impact in impacts:
		var moved: Dictionary = impact.duplicate()
		moved["pos"] = (impact["pos"] as Vector2).rotated(angle)
		moved["inward"] = (impact["inward"] as Vector2).rotated(angle)
		out.append(moved)
	return out


## The body `impacts` whose shot passed through a part — a circle of `radius` at `center` on the
## shot's path before it struck the body — re-seated where the shot entered the part, in its
## frame, with the dent scaled down to the part's size.
func _through(impacts: Array, center: Vector2, radius: float) -> Array:
	var out := []
	var shrink := radius / float(_character.radius)
	for impact in impacts:
		var p: Vector2 = impact["pos"] - center
		var d: Vector2 = impact["inward"]
		var b := p.dot(d)
		var disc := b * b - (p.length_squared() - radius * radius)
		if disc < 0.0:
			continue  # The shot's line misses the part.
		var t := -b - sqrt(disc)  # Entry along the shot, relative to where it struck the body.
		if t > 0.0:
			continue  # The part lies past the body contact: the body stopped the shot first.
		var seated: Dictionary = impact.duplicate()
		seated["pos"] = p + d * t
		seated["depth"] = float(impact["depth"]) * shrink
		out.append(seated)
	return out
