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
const LimbPainter = preload("res://scenes/character/limb_painter.gd")
const TorsoPainter = preload("res://scenes/character/torso_painter.gd")
const Rag = preload("res://scenes/character/character_ragdoll.gd")

@export var body_color: Color = Color(0.32549, 0.65098, 1.0)  ## Shirt color.
@export var hand_color: Color = Color(0.93, 0.76, 0.6)        ## Hands: skin, or a glove color.
@export var skin_color: Color = Color(0.93, 0.76, 0.6)        ## Face and ears.
@export var hair_color: Color = Color(0.36, 0.24, 0.14)       ## Hair, or the headwear's color.
## "short", "long", "buzz", "beanie" or "cap".
@export_enum("short", "long", "buzz", "beanie", "cap") var hair_style: String = "short"
@export var backpack: bool = false                            ## Wear a backpack.
@export var pack_color: Color = Color(0.3, 0.32, 0.26)        ## Backpack color.
@export var pants_color: Color = Color(0.22, 0.27, 0.4)       ## Pants (seen once fallen).
@export var shoe_color: Color = Color(0.16, 0.13, 0.12)       ## Shoes (seen once fallen).

@onready var _character := get_parent()   ## Character — body radius, pose, held item.
@onready var _hands := $"../Hands"        ## Sibling — hand positions / size.

## Draws a fallen body's floor shadow; inside a CanvasGroup (which carries the shadow's alpha) so
## overlapping parts don't darken twice. Built once the body falls.
var _shadow: Node2D
var _settled_drawn := false  ## The fallen body has been drawn at rest: nothing left to redraw.


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	var ragdoll = _character.ragdoll
	if ragdoll == null:
		queue_redraw()  # facing / items change continuously.
		return
	if _settled_drawn:
		return
	if _shadow == null:
		_build_shadow()
	_settled_drawn = ragdoll.is_settled()
	queue_redraw()
	_shadow.queue_redraw()


func _draw() -> void:
	if _character.ragdoll:
		_draw_fallen(_character.ragdoll)
		return
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


# --- The fallen body ---------------------------------------------------------------------
# Once dead the body is the ragdoll's: each part is drawn from its 3D points seen from above, the
# lowest first, so a standing body hides its legs under the shoulders and a toppling one reveals
# them. Lengths foreshorten as the parts tip toward or away from the camera.

## A trunk face is drawn once its outward side turns at least this far (its normal's z) to the camera.
const FACE_MIN := 0.02


## The shadow layer: a CanvasGroup behind the body carrying the shadow's alpha, around the node
## the fallen body's shadow draws on (opaque, so overlapping parts merge into one shade).
func _build_shadow() -> void:
	var group := CanvasGroup.new()
	group.show_behind_parent = true
	group.self_modulate = Color(1.0, 1.0, 1.0, ArtConfig.drop_shadow_alpha)
	add_child(group)
	_shadow = Node2D.new()
	group.add_child(_shadow)
	_shadow.draw.connect(_draw_fallen_shadow)


## Every part of the fallen body, lowest first.
func _draw_fallen(rd) -> void:
	var deformable = _character._deformable
	# The wounds sit on the shoulders' top: recorded facing +x, turned to the art's +y front.
	var impacts := _turned(deformable.impacts if deformable else [], PI * 0.5)
	var damage_total: float = deformable.damage_total if deformable else 0.0
	var parts := _fallen_parts(rd)
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["height"] < b["height"])
	for part in parts:
		match part["kind"]:
			"limb":
				_draw_limb(part)
			"hand":
				_draw_fallen_hand(part)
			"head":
				_draw_fallen_head(part)
			_:
				_draw_face(part, impacts, damage_total)


## The fallen body's floor shadow: each part's silhouette with every point shifted away from the
## light by its height, so the shadow closes in under the body as it lands.
func _draw_fallen_shadow() -> void:
	var rd = _character.ragdoll
	if rd == null:
		return
	var shift := global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized() \
		* CharacterConfig.ragdoll_shadow_per_height
	var cast := func(p: Vector3) -> Vector2: return Vector2(p.x, p.y) + shift * p.z
	for part in _fallen_parts(rd):
		match part["kind"]:
			"limb":
				var w: float = part["width"]
				var a: Vector2 = cast.call(part["a"])
				var b: Vector2 = cast.call(part["b"])
				_shadow.draw_line(a, b, Color.BLACK, w)
				_shadow.draw_circle(a, w * 0.5, Color.BLACK)
				_shadow.draw_circle(b, w * 0.5, Color.BLACK)
			"hand":
				_shadow.draw_circle(cast.call(part["at"]), _hands.hand_radius, Color.BLACK)
			"head":
				_shadow.draw_circle(cast.call(part["at"]), CharacterConfig.ragdoll_head_radius * _character.radius,
					Color.BLACK)
	var corners := PackedVector2Array()
	for corner in _torso_corners(rd):
		corners.append(cast.call(corner))
	var hull := Geometry2D.convex_hull(corners)
	if hull.size() >= 3:
		_shadow.draw_colored_polygon(hull, Color.BLACK)


## The fallen body's parts as dicts with their `kind`, mean `height` and 3D geometry: limb segments
## (sleeves, forearms, legs, shoes, the neck), fists, the head and the trunk faces turned to the camera.
func _fallen_parts(rd) -> Array:
	var r: float = _character.radius
	var parts := []
	for i in 2:
		var shoulder: Vector3 = rd.point(Rag.SHOULDER[i])
		var elbow: Vector3 = rd.point(Rag.ELBOW[i])
		var hand: Vector3 = rd.point(Rag.HAND[i])
		var hip: Vector3 = rd.point(Rag.HIP[i])
		var knee: Vector3 = rd.point(Rag.KNEE[i])
		var ankle: Vector3 = rd.point(Rag.ANKLE[i])
		var toes: Vector3 = rd.toes(i)
		var foot := CharacterConfig.ragdoll_foot * r
		parts.append(_limb(shoulder, elbow, CharacterConfig.ragdoll_upper_arm_width, CharacterConfig.ragdoll_upper_arm,
			body_color, "fabric"))
		parts.append(_limb(elbow, hand, CharacterConfig.ragdoll_forearm_width, CharacterConfig.ragdoll_forearm,
			skin_color, ""))
		parts.append(_limb(hip, knee, CharacterConfig.ragdoll_thigh_width, CharacterConfig.ragdoll_thigh,
			pants_color, "fabric"))
		parts.append(_limb(knee, ankle, CharacterConfig.ragdoll_shin_width, CharacterConfig.ragdoll_shin,
			pants_color, "fabric"))
		parts.append(_limb(ankle - toes * foot * 0.25, ankle + toes * foot * 0.75, CharacterConfig.ragdoll_foot_width,
			CharacterConfig.ragdoll_foot, shoe_color, ""))
		parts.append({ "kind": "hand", "at": hand, "height": hand.z + 0.5, "along": hand - elbow, "side": i })
	var head: Vector3 = rd.point(Rag.HEAD)
	var chest: Vector3 = rd.point(Rag.CHEST)
	parts.append(_limb(chest, head, CharacterConfig.ragdoll_neck_width,
		(CharacterConfig.ragdoll_head_height - CharacterConfig.ragdoll_shoulder_height), skin_color, ""))
	parts.append({ "kind": "head", "at": head, "height": head.z, "face": rd.face(),
		"neck": chest - head })
	parts.append_array(_torso_faces(rd))
	return parts


## A limb segment from `a` to `b`: `width` and true `length` in body radii, its color and material.
func _limb(a: Vector3, b: Vector3, width: float, length: float, color: Color, material: String) -> Dictionary:
	var r: float = _character.radius
	return { "kind": "limb", "a": a, "b": b, "height": (a.z + b.z) * 0.5, "width": width * r,
		"length": length * r, "color": color, "material": material }


## The trunk as a box in its own frame: across the shoulders, from below the hips to over the
## shoulders, and front to back as deep as the shoulder art. Returns its frame, `center`,
## `half` extents (x across, y along the spine, z front to back).
func _torso_box(rd) -> Dictionary:
	var r: float = _character.radius
	var pelvis: Vector3 = rd.point(Rag.PELVIS)
	var basis: Basis = rd.torso()
	var bottom := -CharacterConfig.ragdoll_torso_below_hips * r
	var top: float = (rd.point(Rag.CHEST) - pelvis).length() + CharacterConfig.ragdoll_torso_above_shoulders * r
	return { "basis": basis, "center": pelvis + basis.y * (bottom + top) * 0.5,
		"half": Vector3(r, (top - bottom) * 0.5, CharacterConfig.art_shoulder_depth * r) }


## The trunk box's eight corners.
func _torso_corners(rd) -> Array:
	var box := _torso_box(rd)
	var basis: Basis = box["basis"]
	var half: Vector3 = box["half"]
	var out := []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(box["center"] + basis.x * half.x * sx + basis.y * half.y * sy + basis.z * half.z * sz)
	return out


## The trunk faces turned toward the camera, each with its `center` and the 3D axes its art's x
## and y run along (unit) over its `size`: the shoulders' top (the standing art, wounds and all),
## the chest or the back, and a side.
func _torso_faces(rd) -> Array:
	var box := _torso_box(rd)
	var basis: Basis = box["basis"]
	var half: Vector3 = box["half"]
	var center: Vector3 = box["center"]
	var length := half.y * 2.0
	var faces := []
	if basis.y.z > FACE_MIN:
		faces.append({ "kind": "top", "center": center + basis.y * half.y, "x": basis.x, "y": basis.z,
			"size": Vector2(half.x, half.x) * 2.0 })
	if absf(basis.z.z) > FACE_MIN:
		var s := signf(basis.z.z)
		faces.append({ "kind": "front" if s > 0.0 else "back", "center": center + basis.z * half.z * s,
			"x": basis.x * s, "y": -basis.y, "size": Vector2(half.x * 2.0, length) })
	if absf(basis.x.z) > FACE_MIN:
		var s := signf(basis.x.z)
		faces.append({ "kind": "side", "center": center + basis.x * half.x * s, "x": basis.z * -s,
			"y": -basis.y, "size": Vector2(half.z * 2.0, length) })
	for face in faces:
		face["height"] = (face["center"] as Vector3).z
	return faces


## A trunk face's art mapped onto its projected axes (squashing as it turns away). The shoulders'
## top is the standing art through the wound-dented silhouette, with the wound marks over it.
func _draw_face(face: Dictionary, impacts: Array, damage_total: float) -> void:
	var x3: Vector3 = face["x"]
	var y3: Vector3 = face["y"]
	var c3: Vector3 = face["center"]
	var ax := Vector2(x3.x, x3.y)
	var ay := Vector2(y3.x, y3.y)
	var size: Vector2 = face["size"]
	var angle := ay.angle() - PI * 0.5 if ay.length() > 0.05 else ax.angle()  # The art's turn.
	draw_set_transform_matrix(Transform2D(ax, ay, Vector2(c3.x, c3.y)))
	if face["kind"] == "top":
		var tex := PixelArt.render_turned(BodyPainter, size, body_color, PixelArt.snap_angle(angle), "fabric",
			{ "backpack": backpack, "pack": pack_color })
		Deformation.draw_shape(self, "circle", size, body_color, CharacterConfig.flesh_crack_color,
			impacts, damage_total, Deformation.NO_COLOR, Deformation.NO_COLOR, Deformation.NO_COLOR,
			tex, 0.0, false)
		Deformation.draw_marks(self, impacts, CharacterConfig.flesh_crack_color,
			CharacterConfig.flesh_hole_color, CharacterConfig.flesh_scorch_color)
	else:
		var tex := PixelArt.render_turned(TorsoPainter, size, body_color, PixelArt.snap_angle(angle), "fabric",
			{ "face": face["kind"], "pants": pants_color, "backpack": backpack, "pack": pack_color })
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A limb segment's capsule art along its projected bone, squashed to the projected length (its
## rounded ends kept).
func _draw_limb(limb: Dictionary) -> void:
	var a3: Vector3 = limb["a"]
	var b3: Vector3 = limb["b"]
	var a := Vector2(a3.x, a3.y)
	var b := Vector2(b3.x, b3.y)
	var span := a.distance_to(b)
	var width: float = limb["width"]
	var angle := (b - a).angle() - PI * 0.5 if span > 0.01 else 0.0
	var size := Vector2(width, float(limb["length"]) + width)
	var tex := PixelArt.render_turned(LimbPainter, size, limb["color"], PixelArt.snap_angle(angle), limb["material"])
	draw_set_transform((a + b) * 0.5, angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-width * 0.5, -(span + width) * 0.5, width, span + width), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A fallen fist, its knuckles along the forearm.
func _draw_fallen_hand(hand: Dictionary) -> void:
	var at: Vector3 = hand["at"]
	var along: Vector3 = hand["along"]
	var flat := Vector2(along.x, along.y)
	var angle := flat.angle() - PI * 0.5 if flat.length() > 0.5 else 0.0
	var diameter: float = _hands.hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var tex := PixelArt.render_turned(HandPainter, size, hand_color, PixelArt.snap_angle(angle), "",
		{ "side": -1 if hand["side"] == 0 else 1 })
	draw_set_transform(Vector2(at.x, at.y), angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The fallen head, its art's front turned the way the face looks; a face turned up or down shows
## its front toward the neck, the crown away from the body.
func _draw_fallen_head(head: Dictionary) -> void:
	var px := ArtConfig.pixel_size
	var side := float(HeadPainter.canvas_for(HeadPainter.radius_for(roundi(_character.radius * 2.0 / px)))) * px
	var size := Vector2(side, side)
	var face: Vector3 = head["face"]
	var neck: Vector3 = head["neck"]
	var look := Vector2(face.x, face.y) + Vector2(neck.x, neck.y).normalized() * absf(face.z)
	var angle := look.angle() - PI * 0.5 if look.length() > 0.01 else 0.0
	var tex := PixelArt.render_turned(HeadPainter, size, skin_color, PixelArt.snap_angle(angle), "",
		{ "skin": skin_color, "hair": hair_color, "hair_style": hair_style })
	var at: Vector3 = head["at"]
	draw_set_transform(Vector2(at.x, at.y), angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
