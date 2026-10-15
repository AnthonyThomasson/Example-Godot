extends RefCounted

## Vehicles domain: the car, top-down pixel art (rendered through Art, `PixelArt.render_turned`), in two parts that sandwich
## its occupants (`opts.part`):
##  - `chassis` (under them): the low, rounded body in its paint, the black bumpers and grille, the bonnet with its
##    creases and the boot lid, and inside the cabin the floor, the seats, the dashboard and steering wheel and the sills
##    the doors close over (the doors themselves are door_painter.gd's, drawn where they swing).
##  - `roof` (over them): the raked windscreen and the rear window in tinted, see-through glass, the roof panel on its
##    pillars, and the lamps. The side glass is each door's own (door_painter.gd), so it can go with the door.
## Painted in the vehicle's frame through vehicle_art.gd; geometry from the car's `VehicleConfig.kinds` and `looks` rows.

const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")

const _FLOOR := 1  ## Heights of the parts (the canvas height layer), floor up.
const _BODY := 5
const _PILLAR := 9
const _ROOF := 10


## Paint the car's `opts.part` (`chassis` / `roof`) onto `c` in `base` paint, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var kind: StringName = opts.get("kind", &"car")
	var row: Dictionary = VehicleConfig.kinds[kind]
	var look: Dictionary = VehicleConfig.looks[kind]
	var k := Art.scale(c, (row["size"] as Vector2).x)
	if opts.get("part", "chassis") == "roof":
		_roof(c, base, kind, row, look, k)
	else:
		_chassis(c, base, row, look, k)
	# No cast shadows: a body is repainted for every lighting step it turns through, and on a canvas this size they cost
	# more than the rest of the painting together. Its raised parts are shaded by their bevels instead.


## The body, the bumpers, bonnet and boot, and the open cabin with its seats.
static func _chassis(c: PixelCanvas, base: Color, row: Dictionary, look: Dictionary, k: float) -> void:
	var t := PixelCanvas.tones(base)
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var trim := VehicleConfig.trim_color
	var bumper: float = look["bumper"]
	var bonnet: float = look["bonnet"]
	var boot: float = look["boot"]
	var belt: float = look["belt"]
	# The body: a long rounded box, glossy.
	var body := PixelCanvas.rounded(Art.box(c, -half.x, half.x, -half.y, half.y, k), roundi(float(row["corner"]) * 1.1 * k))
	c.fill(body, base, _BODY)
	c.bevel(body, 1, 2, t["highlight"], t["dark"])
	# The bumpers, black, wrapping the ends.
	for ends: Array in [[half.x - bumper, half.x], [-half.x, -half.x + bumper]]:
		var b := PixelCanvas.rounded(Art.box(c, ends[0], ends[1], -half.y + 4.0, half.y - 4.0, k), roundi(4 * k))
		c.fill(b, trim, _BODY - 1)
		c.bevel(b, 1, 1, trim.lightened(0.18), trim.darkened(0.3))
	# The grille between the headlights.
	var head: Vector2 = look["head"]
	var grille := PixelCanvas.rounded(Art.box(c, half.x - bumper - 5.0, half.x - bumper, -head.x + 6.0, head.x - 6.0, k), roundi(1 * k))
	c.fill(grille, trim, _BODY)
	for i in 3:
		var x := half.x - bumper - 1.5 - i * 1.6
		c.line(Art.at(c, Vector2(x, -head.x + 8.0), k), Art.at(c, Vector2(x, head.x - 8.0), k), trim.lightened(0.15))
	# The bonnet: two creases running back to the windscreen, the shut line before it, a sheen.
	for side in [-1.0, 1.0]:
		c.line(Art.at(c, Vector2(half.x - bumper - 7.0, side * 17.0), k), Art.at(c, Vector2(bonnet + 3.0, side * 21.0), k), t["dark"])
		c.line(Art.at(c, Vector2(half.x - bumper - 7.0, side * 18.0), k), Art.at(c, Vector2(bonnet + 3.0, side * 22.0), k), t["light"])
	c.line(Art.at(c, Vector2(bonnet + 1.0, -belt + 2.0), k), Art.at(c, Vector2(bonnet + 1.0, belt - 2.0), k), t["shadow"])
	var sheen := PixelCanvas.rounded(Art.box(c, bonnet + 4.0, half.x - bumper - 6.0, -half.y + 8.0, half.y - 8.0, k), roundi(6 * k))
	c.glare(sheen, base.lightened(0.38), 2)
	# The boot lid's shut line and its badge.
	c.line(Art.at(c, Vector2(boot - 1.0, -belt + 4.0), k), Art.at(c, Vector2(boot - 1.0, belt - 4.0), k), t["shadow"])
	var badge := Art.at(c, Vector2(-half.x + bumper + 4.0, 0.0), k)
	c.px(badge.x, badge.y, t["highlight"])
	c.px(badge.x + 1, badge.y, t["highlight"])
	# The cabin, open to the sky (the roof part covers it): the floor, the dashboard and wheel, the seats, the console.
	var floor_shape := PixelCanvas.rounded(Art.box(c, boot, bonnet, -belt, belt, k), roundi(4 * k))
	c.fill(floor_shape, VehicleConfig.interior_color, _FLOOR)
	c.surface(floor_shape, "fabric", VehicleConfig.interior_color)
	Art.sills(c, row["doors"], belt, k)
	var seats: Dictionary = row["seats"]
	var driver: Vector2 = seats[&"driver"]
	Art.dashboard(c, look["dash"], belt - 1.0, look["wheel"], driver, k)
	var console := PixelCanvas.rounded(Art.box(c, driver.x - 12.0, (look["dash"] as Vector2).x, -5.0, 5.0, k), roundi(2 * k))
	c.fill(console, VehicleConfig.trim_color.lightened(0.08), 3)
	c.bevel(console, 1, 1, VehicleConfig.trim_color.lightened(0.25), VehicleConfig.trim_color.darkened(0.3))
	var knob := Art.at(c, Vector2(driver.x + 14.0, 0.0), k)
	c.fill(PixelCanvas.disc(knob, maxi(1, roundi(1.5 * k))), VehicleConfig.trim_color.lightened(0.3), 4)
	Art.seats(c, seats, k, driver.x - 20.0)
	# The rear shelf under the back window.
	var shelf := PixelCanvas.rounded(Art.box(c, boot, boot + 14.0, -belt + 2.0, belt - 2.0, k), roundi(2 * k))
	c.fill(shelf, VehicleConfig.interior_color.darkened(0.2), 2)


## The glasshouse over the cabin: windscreen, roof on its pillars, rear window; and the lamps.
static func _roof(c: PixelCanvas, base: Color, kind: StringName, row: Dictionary, look: Dictionary, k: float) -> void:
	var t := PixelCanvas.tones(base)
	var glass := VehicleConfig.glass_color
	var rubber := VehicleConfig.trim_color
	var roof: Vector2 = look["roof"]
	var roof_half: float = look["roof_half"]
	var belt: float = look["belt"]
	var bonnet: float = look["bonnet"]
	var boot: float = look["boot"]
	var screen_half: float = look["screen_half"]
	var rear_half: float = look["rear_half"]
	# How wide the windscreen is at x (it narrows toward the roof), and the rear window.
	var rear := func(x: float) -> float: return lerpf(rear_half, roof_half + 1.0, clampf((x - boot) / (roof.y - boot), 0.0, 1.0))
	# The pillars and the frame round the glass: everything from the belt line in, between the windscreen's base and the
	# rear window's, except the door glass (each door's own).
	var frame := PixelCanvas.rounded(Art.box(c, boot, bonnet, -belt, belt, k), roundi(3 * k))
	c.fill(frame, base, _PILLAR)
	c.bevel(frame, 1, 1, t["light"], t["shadow"])
	Art.clear_door_glass(c, kind, row, look, k)
	# The windscreen and the rear window, tinted glass in black rubbers.
	var windscreen := Art.region(c, roof.x, bonnet, -screen_half, screen_half, k, "car_screen/%s" % kind, func(p: Vector2) -> bool:
		return absf(p.y) <= Art.screen_edge(look, p.x) - 1.0 and p.x <= bonnet - 1.0)
	_glass(c, windscreen, glass, rubber)
	var back := Art.region(c, boot, roof.y, -roof_half, roof_half, k, "car_rear/%s" % kind, func(p: Vector2) -> bool:
		return absf(p.y) <= rear.call(p.x) - 1.0 and p.x >= boot + 1.0)
	_glass(c, back, glass, rubber)
	# The roof: a lighter, raised panel with a sheen.
	var panel := PixelCanvas.rounded(Art.box(c, roof.y, roof.x, -roof_half, roof_half, k), roundi(7 * k))
	c.fill(panel, t["light"], _ROOF)
	c.bevel(panel, 1, 2, t["highlight"], t["dark"])
	c.glare(panel, base.lightened(0.42), 2)
	c.outline(panel, t["shadow"])
	_lamps(c, row, look, k)


## Glass in `shape`: the tint, a glint, a rubber seal round it.
static func _glass(c: PixelCanvas, shape: PixelCanvas.Shape, glass: Color, rubber: Color) -> void:
	c.fill(shape, glass, _PILLAR - 1)
	c.glare(shape, Color(glass.lightened(0.55), 0.6), 2)
	c.outline(shape, rubber)


## Headlights at the nose's corners and tail lights at the tail's (dark until lit by the visuals).
static func _lamps(c: PixelCanvas, row: Dictionary, look: Dictionary, k: float) -> void:
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var length: float = look["lamp"]
	var head: Vector2 = look["head"]
	for r in Art.both(c, half.x - length, half.x - 1.0, head.x, head.y, k):
		var lamp := PixelCanvas.rounded(r, roundi(2 * k))
		c.fill(lamp, VehicleConfig.headlight_color, _BODY + 1)
		c.bevel(lamp, 1, 1, Color.WHITE, VehicleConfig.headlight_color.darkened(0.3))
		c.outline(lamp, VehicleConfig.trim_color)
	for rect: Rect2 in Art.tail_lamps(row, look):
		var lamp := PixelCanvas.rounded(Art.box(c, rect.position.x, rect.end.x, rect.position.y, rect.end.y, k), roundi(1 * k))
		c.fill(lamp, VehicleConfig.tail_off_color, _BODY + 1)
		c.outline(lamp, VehicleConfig.trim_color)

