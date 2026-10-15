extends Node2D

## Vehicles domain: the draw layer of a vehicle, on its own child Node2D (the layered control / animate / draw
## convention). A vehicle has two, which sandwich its occupants:
##  - `Chassis` (`layer` "chassis", under them): the drop shadow, the wheels (the front pair turned by `wheel_angle()`),
##    the body with its open cabin (floor, seats, dashboard, the sills in the door gaps), and each door where it is: a
##    swing or rear door turned about its hinge, a sliding door rolled back along the body.
##  - `Roof` (`layer` "roof", over them): the windscreen, roof and rear window, each door's side glass (fading as the door
##    opens, the window going with it), the wing mirrors on the front doors, the lamps (the tail lights lit while
##    braking, `brake_lights()`) and the dents bullets left. The glass is tinted and see-through, so the part of a seated
##    occupant under it shows.
## All of it is pixel art through the Art domain (interface 12) by this domain's painters (art/): each texture is painted
## once, lit for the nearest `ArtConfig.turn_steps` step of the angle it is drawn at, cached by `PixelArt`, and drawn
## rotated to the exact angle. A layer repaints only when what it shows changes (`_key`): a lighting step, the wheels'
## angle, a door's swing, the brake lights, a dent, or (the shadow and the doors' light) the body's turn.

const CarPainter = preload("res://scenes/vehicle/art/car_painter.gd")
const VanPainter = preload("res://scenes/vehicle/art/van_painter.gd")
const DoorPainter = preload("res://scenes/vehicle/art/door_painter.gd")
const WheelPainter = preload("res://scenes/vehicle/art/wheel_painter.gd")
const LampPainter = preload("res://scenes/vehicle/art/lamp_painter.gd")
const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")

## The body painter of each kind.
const PAINTERS := { &"car": CarPainter, &"van": VanPainter }
## The art's canonical frame (front toward +y) turned onto the vehicle's (front toward +x).
const BODY_TURN := -PI * 0.5
## A wing mirror's size (across, along) and how far from the hinge along the door it stands.
const MIRROR := Vector2(5, 8)
const MIRROR_AT := 9.0

## "chassis" (under the occupants) or "roof" (over them).
@export_enum("chassis", "roof") var layer: String = "chassis"

@onready var _vehicle := get_parent()  ## The vehicle this layer draws (`vehicle.gd`).
var _redraw_key := PackedInt32Array()  ## The `_key()` the layer was last drawn for.
## The next lighting step (counted out from the current one: 1, -1, 2, -2 ...) to paint ahead of time.
var _warm := 1
## Per door id: { def (its kinds-row entry), frame (`vehicle_art.door_frame`) }.
var _doors: Dictionary = {}


func _ready() -> void:
	# Under the occupants (and the living beside it) but over what lies on the floor, or over them.
	z_index = DrawLayers.UNDER_VEHICLE if layer == "chassis" else DrawLayers.ABOVE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for def: Dictionary in VehicleConfig.kinds[_vehicle.kind]["doors"]:  # (the vehicle reads its row after its children are ready)
		_doors[def["id"]] = { "def": def, "frame": Art.door_frame(def) }


func _process(_delta: float) -> void:
	_warm_ahead()
	var key := _key()
	if key != _redraw_key:
		_redraw_key = key
		queue_redraw()


## Once the engine runs (it may now turn through every lighting step), paint the body's other steps ahead of time, one a
## frame and the nearest first, so turning never waits on a paint.
func _warm_ahead() -> void:
	var steps := maxi(1, ArtConfig.turn_steps)
	if _warm >= steps or not _vehicle.engine_state().get("running", false):
		return
	var offset := ceili(_warm / 2.0) * (1 if _warm % 2 == 1 else -1)
	_body_texture(BODY_TURN + offset * TAU / steps)
	_warm += 1


## The rounded inputs the layer was last painted for.
func _key() -> PackedInt32Array:
	var step := VehicleConfig.redraw_step
	var key := PackedInt32Array([_light_step(global_rotation + BODY_TURN), roundi(global_rotation / VehicleConfig.redraw_turn_step)])
	for d in _vehicle.door_list():
		key.append(roundi(d.amount() / step))
	if layer == "chassis":
		key.append(roundi(_vehicle.wheel_angle() / step))
	else:
		key.append(int(_vehicle.brake_lights()))
		var marks: Array = _vehicle.hit_marks()
		key.append(marks.size())
		key.append(int(marks.back().get("seed", 0)) if not marks.is_empty() else 0)  # the oldest dents drop off past the cap
	return key


func _draw() -> void:
	if layer == "chassis":
		_draw_shadow()
		_draw_wheels()
		_draw_body()
		_draw_doors()
	else:
		_draw_body()
		_draw_door_glass()
		_draw_mirrors()
		_draw_brake_lights()
		_draw_dents()
	draw_set_transform(Vector2.ZERO)


## The body's shadow on the ground: its outline, pushed away from the light (by its height, `coverage`) in world space.
func _draw_shadow() -> void:
	var offset := minf(float(_vehicle.row()["coverage"]) * ArtConfig.drop_shadow_per_coverage, ArtConfig.drop_shadow_max)
	var away := global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized() * offset
	draw_colored_polygon(Transform2D(0.0, away) * (_vehicle.outline() as PackedVector2Array),
			Color(0.0, 0.0, 0.0, ArtConfig.drop_shadow_alpha))


## The four wheels at the axles, the front pair turned by the steering angle (only what the body leaves shows).
func _draw_wheels() -> void:
	var row: Dictionary = _vehicle.row()
	var half: Vector2 = _vehicle.half_size()
	var wheel: Vector2 = row["wheel_size"]
	var size := Vector2(wheel.y, wheel.x)
	for x: float in [row["axle_front"], row["axle_rear"]]:
		var angle: float = BODY_TURN + (_vehicle.wheel_angle() if x == row["axle_front"] else 0.0)
		var tex := PixelArt.render_turned(WheelPainter, size, VehicleConfig.tyre_color, _lit(angle), "rubber")
		for side in [-1.0, 1.0]:
			draw_set_transform(Vector2(x, side * (half.y - wheel.y * 0.35)), angle)
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false)


## The body's art for this layer (its kind's painter), drawn turned onto the vehicle's frame.
func _draw_body() -> void:
	var size := _body_size()
	draw_set_transform(Vector2.ZERO, BODY_TURN)
	draw_texture_rect(_body_texture(BODY_TURN), Rect2(-size * 0.5, size), false)


## The body's art for this layer, lit for drawing at `angle` in the vehicle's frame.
func _body_texture(angle: float) -> Texture2D:
	return PixelArt.render_turned(PAINTERS.get(_vehicle.kind, CarPainter), _body_size(), _vehicle.color, _lit(angle), "metal",
			{ "kind": _vehicle.kind, "part": layer })


## The body's art size: its width across, its length along (the canonical frame).
func _body_size() -> Vector2:
	var length_width: Vector2 = VehicleConfig.kinds[_vehicle.kind]["size"]
	return Vector2(length_width.y, length_width.x)


## Each door where it is now: turned about its hinge by its angle, or rolled back along the body by its offset. Its
## thickness lies inside the body's edge when shut.
func _draw_doors() -> void:
	var depth: float = VehicleConfig.looks[_vehicle.kind]["door_depth"]
	for d in _vehicle.door_list():
		var frame: Dictionary = _doors[d.id]["frame"]
		var size := Vector2(depth, frame["length"])
		var angle: float = frame["turn"] + d.angle()
		var tex := PixelArt.render_turned(DoorPainter, size, _vehicle.color, _lit(angle), "metal",
				{ "kind": _vehicle.kind, "door": d.id, "part": "panel" })
		draw_set_transform(d.hinge + d.offset(), angle)
		draw_texture_rect(tex, Rect2(Vector2(-depth if frame["outer"] > 0.0 else 0.0, -size.y), size), false)


## Each door's side window, between its belt line and the roof, fading out as the door opens (the window goes with it).
func _draw_door_glass() -> void:
	var glazed: Dictionary = VehicleConfig.looks[_vehicle.kind]["glass"]
	for d in _vehicle.door_list():
		if not glazed.has(d.id):
			continue
		var alpha := 1.0 - clampf(d.amount() / maxf(VehicleConfig.glass_fade, 0.01), 0.0, 1.0)
		if alpha <= 0.0:
			continue
		var rect: Rect2 = DoorPainter.glass_rect(_vehicle.kind, d.id)
		var size := Vector2(rect.size.y, rect.size.x)
		var tex := PixelArt.render_turned(DoorPainter, size, _vehicle.color, _lit(BODY_TURN), "glass",
				{ "kind": _vehicle.kind, "door": d.id, "part": "glass" })
		draw_set_transform(rect.get_center(), BODY_TURN)
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(1.0, 1.0, 1.0, alpha))


## The wing mirrors, standing out from their doors near the hinge and swinging with them.
func _draw_mirrors() -> void:
	for id in VehicleConfig.looks[_vehicle.kind]["mirror"]:
		var d = _door(id)
		if d == null:
			continue
		var frame: Dictionary = _doors[id]["frame"]
		var angle: float = frame["turn"] + d.angle()
		var tex := PixelArt.render_turned(DoorPainter, MIRROR, _vehicle.color, _lit(angle), "metal",
				{ "kind": _vehicle.kind, "door": id, "part": "mirror" })
		draw_set_transform(d.hinge + d.offset(), angle)
		draw_texture_rect(tex, Rect2(Vector2(0.0 if frame["outer"] > 0.0 else -MIRROR.x, -MIRROR_AT), MIRROR), false)


## While braking, the tail lights light up and throw a red glow on the ground behind.
func _draw_brake_lights() -> void:
	if not _vehicle.brake_lights():
		return
	draw_set_transform(Vector2.ZERO)
	var glow := VehicleConfig.brake_glow
	for rect: Rect2 in Art.tail_lamps(_vehicle.row(), VehicleConfig.looks[_vehicle.kind]):
		draw_rect(Rect2(rect.position + Vector2(-5.0, -2.0), rect.size + Vector2(5.0, 4.0)), Color(glow, glow.a * 0.5))
		draw_rect(Rect2(rect.position + Vector2(-2.5, -1.0), rect.size + Vector2(2.5, 2.0)), glow)
	for rect: Rect2 in Art.tail_lamps(_vehicle.row(), VehicleConfig.looks[_vehicle.kind]):
		var size := Vector2(rect.size.y, rect.size.x)
		var tex := PixelArt.render_turned(LampPainter, size, VehicleConfig.tail_on_color, _lit(BODY_TURN), "glass")
		draw_set_transform(rect.get_center(), BODY_TURN)
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false)


## The dents bullets have left (Physics' marks, drawn over the paint).
func _draw_dents() -> void:
	draw_set_transform(Vector2.ZERO)
	Deformation.draw_marks(self, _vehicle.hit_marks(), Color(0.15, 0.15, 0.16), Color(0.06, 0.06, 0.07),
			Color(0.2, 0.18, 0.16))


## The lighting step for art drawn at `angle` in the vehicle's frame (its turn on screen added).
func _lit(angle: float) -> float:
	return PixelArt.snap_angle(global_rotation + angle)


## Which lighting step an on-screen angle falls in.
static func _light_step(angle: float) -> int:
	var steps := maxi(1, ArtConfig.turn_steps)
	return roundi(PixelArt.snap_angle(angle) / (TAU / steps)) % steps


## The door object `id`, or null.
func _door(id: StringName):
	for d in _vehicle.door_list():
		if d.id == id:
			return d
	return null
