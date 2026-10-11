extends Node2D

## Character DRAW layer. Renders the whole character as top-down pixel art (painted through the Art
## domain's PixelArt), each part at its own angle from the character's pose and each limb from the
## joints of its rig: a drop shadow, the legs and shoes, the arms (sleeve, then forearm), the
## shoulders at the pose's lunge, the head (with its shadow on the shoulders) shifted by the pose's
## lean and breath, then the item's own weapon, the fists gripping it, and last the wound marks.
## Shots dent and darken the shoulders and any part they passed through. Each part is lit for the
## nearest lighting step and drawn rotated to its exact angle. Reads the body radius, pose, rig, held
## item and wounds from the character and hand positions/size from the hands sibling. Appearance
## only — no item-specific weapon logic lives here (that's each Item's draw_weapon()). Once dead it
## draws the fallen ragdoll instead.

const BodyPainter = preload("res://scenes/character/body_painter.gd")
const HeadPainter = preload("res://scenes/character/head_painter.gd")
const HandPainter = preload("res://scenes/character/hand_painter.gd")
const LimbPainter = preload("res://scenes/character/limb_painter.gd")
const TorsoPainter = preload("res://scenes/character/torso_painter.gd")
const Rig = preload("res://scenes/character/character_rig.gd")  # The joint indices, shared with the ragdoll.

@export var body_color: Color = Color(0.32549, 0.65098, 1.0)  ## Shirt color.
@export var hand_color: Color = Color(0.93, 0.76, 0.6)        ## Hands: skin, or a glove color.
@export var skin_color: Color = Color(0.93, 0.76, 0.6)        ## Face, ears and forearms.
@export var hair_color: Color = Color(0.36, 0.24, 0.14)       ## Hair, or the headwear's color.
## "short", "long", "buzz", "beanie" or "cap".
@export_enum("short", "long", "buzz", "beanie", "cap") var hair_style: String = "short"
@export var backpack: bool = false                            ## Wear a backpack.
@export var pack_color: Color = Color(0.3, 0.32, 0.26)        ## Backpack color.
@export var pants_color: Color = Color(0.22, 0.27, 0.4)       ## Pants.
@export var shoe_color: Color = Color(0.16, 0.13, 0.12)       ## Shoes.

@onready var _character := get_parent()   ## Character — body radius, pose, rig, held item.
@onready var _hands := $"../Hands"        ## Sibling — hand positions / size.

## Draws the body's floor shadow; inside a CanvasGroup (which carries the shadow's alpha) so
## overlapping parts don't darken twice.
var _shadow: Node2D
var _settled_drawn := false  ## The fallen body has been drawn at rest: nothing left to redraw.

## A standing body is repainted only when what it draws has changed: its joints, the angles its parts are
## turned by, what is held and its wounds, each rounded to a step below a visible pixel at the body's size
## (positions in px, angles in rad). A character standing still drifts by less than a step most frames
## (breath, glance), and repainting an identical body is most of an idle crowd's frame cost.
const REDRAW_POS_STEP := 0.1
const REDRAW_ANGLE_STEP := 0.02
var _rig  ## The standing skeleton solved this frame, shared by the body's and the shadow's draw.
var _redraw_key := PackedInt32Array()  ## The rounded inputs the standing body was last repainted for.
var redraws := 0  ## How many times the standing body has been drawn (tests read it).


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_shadow()


func _process(_delta: float) -> void:
	var ragdoll = _character.ragdoll
	if ragdoll == null:
		_rig = _character.rig()
		var key := _redraw_key_of(_rig)
		if key != _redraw_key:
			_redraw_key = key
			queue_redraw()
			_shadow.queue_redraw()
		return
	if _settled_drawn:
		return
	_settled_drawn = ragdoll.is_settled()
	queue_redraw()
	_shadow.queue_redraw()


## The inputs of the standing draw for `rig`, each rounded to its redraw step: the joints and feet (which
## carry the lunge, the head's offset and the hands' places), the angles the shoulders, head, fists and
## weapon are turned by, the held slot, and the wounds that dent and darken the parts.
func _redraw_key_of(rig) -> PackedInt32Array:
	var pose = _character.pose
	var key := PackedInt32Array()
	for i in 17:
		var p: Vector3 = rig.point(i)
		key.append(roundi(p.x / REDRAW_POS_STEP))
		key.append(roundi(p.y / REDRAW_POS_STEP))
		key.append(roundi(p.z / REDRAW_POS_STEP))
	for i in 2:
		var toes: Vector3 = rig.toes(i)
		key.append(roundi(toes.x / REDRAW_ANGLE_STEP))
		key.append(roundi(toes.y / REDRAW_ANGLE_STEP))
	for angle in [pose.torso_angle, pose.head_angle, pose.hand_angles[0], pose.hand_angles[1], pose.weapon_angle]:
		key.append(roundi(angle / REDRAW_ANGLE_STEP))
	key.append(_character.current_slot())
	var deformable = _character._deformable
	if deformable:
		key.append(deformable.impacts.size())
		key.append(roundi(deformable.damage_total * 100.0))
	return key


func _draw() -> void:
	if _character.ragdoll:
		_draw_fallen(_character.ragdoll)
		return
	redraws += 1
	var pose = _character.pose
	var rig = _rig if _rig != null else _character.rig()
	var lunge: Vector2 = pose.torso_offset
	var torso: float = pose.torso_angle - PI * 0.5  # Canonical art faces +y.
	var size := _shoulder_size()
	var body := _shoulder_art(torso)
	var deformable = _character._deformable
	# Impacts are recorded relative to the shoulders (character.take_hit), so they turn with them.
	var impacts := _turned(deformable.impacts if deformable else [], pose.torso_angle)
	var placed := _shifted(impacts, lunge)  # The same wounds in the character's frame, for the parts.
	var damage_total: float = deformable.damage_total if deformable else 0.0
	var item: Item = _character.current_item()

	for i in 2:
		_draw_chain(_leg_chain(rig, i))
	for i in 2:
		_draw_chain(_arm_chain(rig, i))
	# Shoulders: the art through the flesh silhouette deformed by any shots (dents + darkening).
	draw_set_transform(lunge, 0.0, Vector2.ONE)
	Deformation.draw_shape(self, "circle", size, body_color, CharacterConfig.flesh_crack_color,
		impacts, damage_total, Deformation.NO_COLOR, Deformation.NO_COLOR, Deformation.NO_COLOR,
		body, torso, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_head(pose, placed, damage_total)
	if item:
		item.draw_weapon(self, _character)
	for hand in 2:
		_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, placed, damage_total)
	# Wound marks over everything, so a hit hand shows its wound: dark-red holes and cracks that
	# read as bloody gashes (config-driven).
	Deformation.draw_marks(self, placed, CharacterConfig.flesh_crack_color,
		CharacterConfig.flesh_hole_color, CharacterConfig.flesh_scorch_color)


## The shoulders' art canvas: the body's round footprint.
func _shoulder_size() -> Vector2:
	var r: float = _character.radius
	return Vector2(r * 2.0, r * 2.0)


## The shoulders' pixel art, lit for the nearest lighting step to `angle` (the art's turn).
func _shoulder_art(angle: float) -> Texture2D:
	return PixelArt.render_turned(BodyPainter, _shoulder_size(), body_color, PixelArt.snap_angle(angle),
		"fabric", { "backpack": backpack, "pack": pack_color })


## The standing body's floor shadow, drawn into the shadow group: the shoulders' own silhouette
## through the deformed outline, then each limb, fist and the head, every point shifted away from
## the light by its height.
func _draw_standing_shadow() -> void:
	var pose = _character.pose
	var rig = _rig if _rig != null else _character.rig()
	var cast := _shadow_caster()
	var deformable = _character._deformable
	var impacts := _turned(deformable.impacts if deformable else [], pose.torso_angle)
	var size := _shoulder_size()
	var angle: float = pose.torso_angle - PI * 0.5
	var poly := Deformation.shape_polygon("circle", size, impacts)
	if not Deformation.is_valid_polygon(poly):
		poly = Deformation.base_ring("circle", size)
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(p.rotated(-angle) / size + Vector2(0.5, 0.5))
	var lift: Vector2 = cast.call(rig.point(Rig.CHEST))  # The shoulders' lunge, shifted from the light.
	_shadow.draw_colored_polygon(Transform2D(0.0, lift) * poly, Color.BLACK, uvs, _shoulder_art(angle))
	for i in 2:
		for chain in [_leg_chain(rig, i), _arm_chain(rig, i)]:
			_draw_limb_shadow(chain, cast)
		_shadow.draw_circle(cast.call(rig.point(Rig.HAND[i])), _hands.hand_radius, Color.BLACK)
	_shadow.draw_circle(cast.call(rig.point(Rig.HEAD)), CharacterConfig.ragdoll_head_radius * _character.radius,
		Color.BLACK)


## A 3D point's place on the floor shadow: its flat position shifted away from the light by its
## height. Used as `cast.call(Vector3) -> Vector2`.
func _shadow_caster() -> Callable:
	var shift := global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized() \
		* CharacterConfig.body_shadow_per_height
	return func(p: Vector3) -> Vector2: return Vector2(p.x, p.y) + shift * p.z


## One limb chain's floor shadow: each segment's capsule through `cast`.
func _draw_limb_shadow(chain: Dictionary, cast: Callable) -> void:
	for seg in chain["segs"]:
		_shadow.draw_colored_polygon(_capsule(cast.call(seg["a"]), cast.call(seg["b"]), seg["ra"], seg["rb"]),
			Color.BLACK)


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


## `impacts` moved by `by`: from the shoulders' frame to the character's, once the shoulders lunge.
static func _shifted(impacts: Array, by: Vector2) -> Array:
	if by == Vector2.ZERO:
		return impacts
	var out := []
	for impact in impacts:
		var moved: Dictionary = impact.duplicate()
		moved["pos"] = (impact["pos"] as Vector2) + by
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


# --- Limbs, shadow and the fallen body --------------------------------------------------
# Limbs are tapered capsules between 3D joints, drawn the same from the standing rig or the fallen
# ragdoll. Once dead the body is the ragdoll's: each part is drawn from its 3D points seen from
# above, the lowest first, so a standing body hides its legs under the shoulders and a toppling one
# reveals them, with the trunk a loft of cross-sections, so every part foreshortens and rounds off
# naturally as it tips toward or away from the camera.

## Points sampled around each trunk cross-section and each limb end.
const SECTION_POINTS := 16
const CAP_POINTS := 6
## Cross-sections the trunk's outline is lofted through between its ends, and in each end's dome.
const TRUNK_STEPS := 10
const DOME_STEPS := 3
## How far past the end sections the domes reach (spine fractions): over the shoulders, under the hips.
const DOME_TOP := 0.12
const DOME_BOTTOM := 0.1
## A wound shows once its patch of skin turns at least this far (its normal's z) to the camera.
const WOUND_MIN_FACING := 0.3


## The shadow layer: a CanvasGroup behind the body carrying the shadow's alpha, around the node
## the body's shadow draws on (opaque, so overlapping parts merge into one shade).
func _build_shadow() -> void:
	var group := CanvasGroup.new()
	group.show_behind_parent = true
	group.self_modulate = Color(1.0, 1.0, 1.0, ArtConfig.drop_shadow_alpha)
	add_child(group)
	_shadow = Node2D.new()
	group.add_child(_shadow)
	_shadow.draw.connect(_draw_body_shadow)


## The body's floor shadow, standing or fallen.
func _draw_body_shadow() -> void:
	var rd = _character.ragdoll
	if rd == null:
		_draw_standing_shadow()
	else:
		_draw_fallen_shadow(rd)


## Every part of the fallen body, lowest first.
func _draw_fallen(rd) -> void:
	var parts := _fallen_parts(rd)
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["height"] < b["height"])
	for part in parts:
		match part["kind"]:
			"chain":
				_draw_chain(part)
			"hand":
				_draw_fallen_hand(part)
			"head":
				_draw_fallen_head(part)
			"trunk":
				_draw_trunk(rd)


## The fallen body's floor shadow: each part's silhouette with every point shifted away from the
## light by its height, so the shadow closes in under the body as it lands.
func _draw_fallen_shadow(rd) -> void:
	var cast := _shadow_caster()
	for part in _fallen_parts(rd):
		match part["kind"]:
			"chain":
				_draw_limb_shadow(part, cast)
			"hand":
				_shadow.draw_circle(cast.call(part["at"]), _hands.hand_radius, Color.BLACK)
			"head":
				_shadow.draw_circle(cast.call(part["at"]), CharacterConfig.ragdoll_head_radius * _character.radius,
					Color.BLACK)
	var outline := _trunk_outline(rd, cast)
	if outline.size() >= 3:
		_shadow.draw_colored_polygon(outline, Color.BLACK)


## The fallen body's parts as dicts with their `kind` and mean `height`: limb chains (arms, legs with
## their shoes, the neck), fists, the head and the trunk.
func _fallen_parts(rd) -> Array:
	var r: float = _character.radius
	var parts := []
	for i in 2:
		parts.append(_arm_chain(rd, i))
		parts.append(_leg_chain(rd, i))
		var elbow: Vector3 = rd.point(Rig.ELBOW[i])
		var hand: Vector3 = rd.point(Rig.HAND[i])
		parts.append({ "kind": "hand", "at": hand, "height": hand.z + 0.5, "along": hand - elbow, "side": i })
	var head: Vector3 = rd.point(Rig.HEAD)
	var chest: Vector3 = rd.point(Rig.CHEST)
	var neck := CharacterConfig.body_neck_width
	parts.append(_chain([_seg(chest, head, neck, neck,
		(CharacterConfig.body_head_height - CharacterConfig.body_shoulder_height) * r, skin_color, "")]))
	parts.append({ "kind": "head", "at": head, "height": head.z, "face": rd.face(), "neck": chest - head })
	parts.append({ "kind": "trunk", "height": (chest.z + rd.point(Rig.PELVIS).z) * 0.5 })
	return parts


## Side `i`'s arm as a limb chain from the joints of `j` (the rig or the ragdoll): the sleeve to the
## elbow, the bare forearm to the center of the fist.
func _arm_chain(j, i: int) -> Dictionary:
	var r: float = _character.radius
	var arm: Array = CharacterConfig.body_arm_widths
	var shoulder: Vector3 = j.point(Rig.SHOULDER[i])
	var elbow: Vector3 = j.point(Rig.ELBOW[i])
	var hand: Vector3 = j.point(Rig.HAND[i])
	return _chain([
		_seg(shoulder, elbow, arm[0], arm[1], CharacterConfig.body_upper_arm * r, body_color, "fabric"),
		_seg(elbow, hand, arm[1], arm[2], CharacterConfig.body_forearm * r, skin_color, ""),
	])


## Side `i`'s leg as a limb chain from the joints of `j`: the thigh, the shin in two parts (the
## calf is wider than the ankle) and the shoe along the way the foot points.
func _leg_chain(j, i: int) -> Dictionary:
	var r: float = _character.radius
	var leg: Array = CharacterConfig.body_leg_widths
	var shoe: Array = CharacterConfig.body_shoe_widths
	var hip: Vector3 = j.point(Rig.HIP[i])
	var knee: Vector3 = j.point(Rig.KNEE[i])
	var ankle: Vector3 = j.point(Rig.ANKLE[i])
	var calf := knee.lerp(ankle, 0.35)
	var toes: Vector3 = j.toes(i)
	var foot := CharacterConfig.body_foot * r
	var shin := CharacterConfig.body_shin * r
	return _chain([
		_seg(hip, knee, leg[0], leg[1], CharacterConfig.body_thigh * r, pants_color, "fabric"),
		_seg(knee, calf, leg[1], leg[2], shin * 0.35, pants_color, "fabric"),
		_seg(calf, ankle, leg[2], leg[3], shin * 0.65, pants_color, "fabric"),
		_seg(ankle - toes * foot * 0.25, ankle + toes * foot * 0.75, shoe[0], shoe[1], foot, shoe_color, ""),
	])


## One tapered limb segment from `a` to `b` (3D): its widths at each end in body radii, the true
## `length` (px) its art is painted at, its color and material.
func _seg(a: Vector3, b: Vector3, width_a: float, width_b: float, length: float, color: Color,
		material: String) -> Dictionary:
	var r: float = _character.radius
	return { "a": a, "b": b, "ra": width_a * r * 0.5, "rb": width_b * r * 0.5, "length": length,
		"color": color, "material": material }


## A limb chain: its segments, sorted as one part by their mean height.
func _chain(segs: Array) -> Dictionary:
	var height := 0.0
	for seg in segs:
		height += ((seg["a"] as Vector3).z + (seg["b"] as Vector3).z) * 0.5
	return { "kind": "chain", "segs": segs, "height": height / segs.size() }


## A limb chain: every segment first a pixel wider in its outline tone, then every fill over them
## (lowest first), so the joints run together under one continuous outline.
func _draw_chain(chain: Dictionary) -> void:
	var segs: Array = chain["segs"].duplicate()
	for seg in segs:
		draw_colored_polygon(_capsule(_flat(seg["a"]), _flat(seg["b"]), seg["ra"] + 1.0, seg["rb"] + 1.0),
			PixelCanvas.tones(seg["color"]).outline)
	segs.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return (p["a"] as Vector3).z + (p["b"] as Vector3).z < (q["a"] as Vector3).z + (q["b"] as Vector3).z)
	for seg in segs:
		_draw_segment(seg)


## One limb segment's art (a shaded strip from limb_painter.gd) mapped onto its tapered capsule:
## across the strip runs across the limb, along it from end to end.
func _draw_segment(seg: Dictionary) -> void:
	var a := _flat(seg["a"])
	var b := _flat(seg["b"])
	var ra: float = seg["ra"]
	var rb: float = seg["rb"]
	var span := a.distance_to(b)
	var dir := (b - a) / span if span > 0.01 else Vector2.DOWN
	var widest := maxf(ra, rb)
	var angle := dir.angle() - PI * 0.5
	var size := Vector2(roundf(widest * 2.0), roundf(float(seg["length"]) + ra + rb))
	var tex := PixelArt.render_turned(LimbPainter, size, seg["color"], PixelArt.snap_angle(angle), seg["material"])
	var poly := _capsule(a, b, ra, rb)
	var uvs := PackedVector2Array()
	for p in poly:
		var rel := p - a
		uvs.append(Vector2(rel.dot(dir.orthogonal()) / (widest * 2.0) + 0.5, (rel.dot(dir) + ra) / (span + ra + rb)))
	draw_colored_polygon(poly, Color.WHITE, uvs, tex)


## A tapered capsule outline from `a` (radius `ra`) to `b` (radius `rb`): a round cap behind each
## end joined by straight sides; a circle when the ends meet (a limb pointing at the camera).
static func _capsule(a: Vector2, b: Vector2, ra: float, rb: float) -> PackedVector2Array:
	var span := a.distance_to(b)
	var out := PackedVector2Array()
	if span < 0.5:
		var rad := maxf(ra, rb)
		for k in CAP_POINTS * 2:
			out.append(a + Vector2.from_angle(TAU * k / (CAP_POINTS * 2)) * rad)
		return out
	var base := (b - a).angle()
	for k in CAP_POINTS + 1:  # Behind `a`, from one side round to the other.
		out.append(a + Vector2.from_angle(base + PI * 0.5 + PI * k / CAP_POINTS) * ra)
	for k in CAP_POINTS + 1:  # Ahead of `b`.
		out.append(b + Vector2.from_angle(base - PI * 0.5 + PI * k / CAP_POINTS) * rb)
	return out


## A 3D point's place on the floor plane, seen from above.
static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y)


## The trunk's cross-section at spine fraction `t` (0 = hip joints, 1 = shoulder joints) as
## Vector2(half-width, half-depth) in body radii, eased between the configured sections so the
## outline curves; past either end it rounds off in a dome.
static func _section_at(t: float) -> Vector2:
	var sections: Array = CharacterConfig.ragdoll_trunk_sections
	var first: Vector3 = sections[0]
	var last: Vector3 = sections[sections.size() - 1]
	if t < first.x:
		return Vector2(first.y, first.z) * _dome((first.x - t) / DOME_BOTTOM)
	if t > last.x:
		return Vector2(last.y, last.z) * _dome((t - last.x) / DOME_TOP)
	for k in range(1, sections.size()):
		var hi: Vector3 = sections[k]
		if t <= hi.x:
			var lo: Vector3 = sections[k - 1]
			var w := smoothstep(0.0, 1.0, (t - lo.x) / maxf(hi.x - lo.x, 0.001))
			return Vector2(lerpf(lo.y, hi.y, w), lerpf(lo.z, hi.z, w))
	return Vector2(last.y, last.z)


## A dome's width `s` of the way (0..1) from its base to its tip.
static func _dome(s: float) -> float:
	return sqrt(maxf(1.0 - 0.85 * s * s, 0.0))


## The spine fractions the trunk's outline is lofted through: the domes under the hips and over the
## shoulders, and evenly between them.
static func _trunk_steps() -> PackedFloat32Array:
	var sections: Array = CharacterConfig.ragdoll_trunk_sections
	var t0: float = (sections[0] as Vector3).x
	var t1: float = (sections[sections.size() - 1] as Vector3).x
	var out := PackedFloat32Array()
	for k in range(DOME_STEPS, 0, -1):
		out.append(t0 - DOME_BOTTOM * k / DOME_STEPS)
	for k in TRUNK_STEPS + 1:
		out.append(lerpf(t0, t1, float(k) / TRUNK_STEPS))
	for k in range(1, DOME_STEPS + 1):
		out.append(t1 + DOME_TOP * k / DOME_STEPS)
	return out


## The trunk's outline seen through `project` (3D → 2D): the union of the hulls of each pair of
## neighbouring cross-sections (ellipses across the spine, eased between
## CharacterConfig.ragdoll_trunk_sections and domed at both ends), so it is waisted and rounded from
## any side and shrinks to the shoulders seen from above.
func _trunk_outline(rd, project: Callable) -> PackedVector2Array:
	var r: float = _character.radius
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var rings := []
	for t in _trunk_steps():
		var centre: Vector3 = pelvis + basis.y * t * spine
		var half := _section_at(t) * r
		var ring := PackedVector2Array()
		for k in SECTION_POINTS:
			var around := Vector2.from_angle(TAU * k / SECTION_POINTS)
			ring.append(project.call(centre + basis.x * around.x * half.x + basis.z * around.y * half.y))
		rings.append(ring)
	var outline := PackedVector2Array()
	for k in range(1, rings.size()):
		var hull := _open(Geometry2D.convex_hull(rings[k - 1] + rings[k]))
		if outline.is_empty():
			outline = hull
			continue
		# The union's outer boundary is its largest piece (any others would be holes).
		var best := PackedVector2Array()
		for poly in Geometry2D.merge_polygons(outline, hull):
			if _area(poly) > _area(best):
				best = poly
		outline = best if best.size() >= 3 else outline
	if Geometry2D.triangulate_polygon(outline).is_empty():
		var everything := PackedVector2Array()
		for ring in rings:
			everything.append_array(ring)
		outline = _open(Geometry2D.convex_hull(everything))
	return outline


## The area enclosed by `poly`, whichever way it winds.
static func _area(poly: PackedVector2Array) -> float:
	var twice := 0.0
	for k in poly.size():
		twice += poly[k].cross(poly[(k + 1) % poly.size()])
	return absf(twice) * 0.5


## `poly` without a closing point that repeats its first.
static func _open(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
		poly.remove_at(poly.size() - 1)
	return poly


## The trunk: a shirt-colored underfill of its outline, the art of the side most turned to the
## camera mapped across it (the shoulders' top, the chest, the back or a flank), a 1 px outline, then
## the wounds on whatever skin faces up.
func _draw_trunk(rd) -> void:
	var outline := _trunk_outline(rd, func(p: Vector3) -> Vector2: return _flat(p))
	if outline.size() < 3:
		return
	var face := _trunk_face(rd)
	draw_colored_polygon(outline, body_color)
	var ax: Vector2 = face["x"]
	var ay: Vector2 = face["y"]
	var size: Vector2 = face["size"]
	var det := ax.x * ay.y - ax.y * ay.x
	if absf(det) > 0.0001:
		var uvs := PackedVector2Array()
		for p in outline:
			var rel: Vector2 = p - face["center"]
			var u := (rel.x * ay.y - rel.y * ay.x) / det
			var v := (ax.x * rel.y - ax.y * rel.x) / det
			uvs.append(Vector2(u / size.x + 0.5, v / size.y + 0.5))
		draw_colored_polygon(outline, Color.WHITE, uvs, face["texture"])
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, PixelCanvas.tones(body_color).outline, 1.0)
	_draw_wounds(rd)


## The trunk side most turned to the camera, as the art to map across the outline: its `texture`,
## its `center` and the screen vectors its art's x and y run along (per px) over its `size`.
func _trunk_face(rd) -> Dictionary:
	var r: float = _character.radius
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var sections: Array = CharacterConfig.ragdoll_trunk_sections
	var bottom: float = ((sections[0] as Vector3).x - DOME_BOTTOM) * spine
	var top: float = ((sections[sections.size() - 1] as Vector3).x + DOME_TOP) * spine
	var mid: Vector3 = pelvis + basis.y * (bottom + top) * 0.5
	var length := top - bottom
	var depth := CharacterConfig.art_shoulder_depth * r
	var side := signf(basis.x.z) if basis.x.z != 0.0 else 1.0
	var facing := signf(basis.z.z) if basis.z.z != 0.0 else 1.0
	var faces := [
		{ "kind": "top", "score": basis.y.z, "centre": pelvis + basis.y * top, "x": basis.x, "y": basis.z,
			"size": Vector2(2.0 * r, 2.0 * r) },
		{ "kind": "front" if facing > 0.0 else "back", "score": absf(basis.z.z), "centre": mid + basis.z * depth * facing,
			"x": basis.x * facing, "y": -basis.y, "size": Vector2(2.0 * r, length) },
		{ "kind": "side", "score": absf(basis.x.z), "centre": mid + basis.x * r * side, "x": basis.z * -side,
			"y": -basis.y, "size": Vector2(2.0 * depth, length) },
	]
	var best: Dictionary = faces[0]
	for f in faces:
		if f["score"] > best["score"]:
			best = f
	var x3: Vector3 = best["x"]
	var y3: Vector3 = best["y"]
	var ax := _flat(x3)
	var ay := _flat(y3)
	var size: Vector2 = best["size"]
	var angle := ay.angle() - PI * 0.5 if ay.length() > 0.05 else ax.angle()  # The art's turn.
	var tex: Texture2D
	if best["kind"] == "top":
		tex = PixelArt.render_turned(BodyPainter, size, body_color, PixelArt.snap_angle(angle), "fabric",
			{ "backpack": backpack, "pack": pack_color })
	else:
		tex = PixelArt.render_turned(TorsoPainter, size, body_color, PixelArt.snap_angle(angle), "fabric",
			{ "face": best["kind"], "pants": pants_color, "backpack": backpack, "pack": pack_color })
	return { "texture": tex, "center": _flat(best["centre"]), "x": ax, "y": ay, "size": size }


## The shots the body took while alive, as wounds on its fallen trunk: each sits around the body
## where it struck (its angle in the shoulders' frame) at a height seeded per wound between waist and
## chest, and shows only while that patch of skin faces the camera — the chest's wounds on a body
## lying on its back, the back's on one lying face down.
func _draw_wounds(rd) -> void:
	var deformable = _character._deformable
	if deformable == null:
		return
	var r: float = _character.radius
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var wounds := []
	for impact in deformable.impacts:
		var pos: Vector2 = impact["pos"]
		if pos.length() < 0.001:
			continue
		# Recorded with the body facing +x: its right is −y, its front +x.
		var around := Vector2(-pos.y, pos.x).normalized()
		var rng := RandomNumberGenerator.new()
		rng.seed = int(impact["seed"])
		var t := rng.randf_range(0.35, 0.9)
		var half := _section_at(t) * r
		var reach := 1.0 / sqrt(pow(around.x / half.x, 2.0) + pow(around.y / half.y, 2.0))
		var on := around * reach
		var skin: Vector3 = pelvis + basis.y * t * spine + basis.x * on.x + basis.z * on.y
		var normal: Vector3 = (basis.x * on.x / (half.x * half.x) + basis.z * on.y / (half.y * half.y)).normalized()
		if normal.z < WOUND_MIN_FACING:
			continue
		var wound: Dictionary = impact.duplicate()
		wound["pos"] = _flat(skin)
		wound["inward"] = Vector2.ZERO
		wound["depth"] = float(impact["depth"]) * normal.z
		wounds.append(wound)
	Deformation.draw_marks(self, wounds, CharacterConfig.flesh_crack_color, CharacterConfig.flesh_hole_color,
		CharacterConfig.flesh_scorch_color)


## A fallen fist, its knuckles along the forearm.
func _draw_fallen_hand(hand: Dictionary) -> void:
	var at: Vector3 = hand["at"]
	var along: Vector3 = hand["along"]
	var flat := _flat(along)
	var angle := flat.angle() - PI * 0.5 if flat.length() > 0.5 else 0.0
	var diameter: float = _hands.hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var tex := PixelArt.render_turned(HandPainter, size, hand_color, PixelArt.snap_angle(angle), "",
		{ "side": -1 if hand["side"] == 0 else 1 })
	draw_set_transform(_flat(at), angle, Vector2.ONE)
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
	var look := _flat(face) + _flat(neck).normalized() * absf(face.z)
	var angle := look.angle() - PI * 0.5 if look.length() > 0.01 else 0.0
	var tex := PixelArt.render_turned(HeadPainter, size, skin_color, PixelArt.snap_angle(angle), "",
		{ "skin": skin_color, "hair": hair_color, "hair_style": hair_style })
	draw_set_transform(_flat(head["at"]), angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
