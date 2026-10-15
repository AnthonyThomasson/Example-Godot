extends RefCounted

## Vehicles domain: the van, top-down pixel art (rendered through Art, `PixelArt.render_turned`), in the same two parts as
## the car (`opts.part`), but boxy:
##  - `chassis` (under the occupants): a long square-cornered body, a short snub nose with a wide grille, black bumpers
##    (a step plate at the back), the cab (floor, dashboard and wheel, two seats either side of the engine cover), a
##    bulkhead behind it, and the bare cargo bay (plywood floor, tie-down rails, benches) seen when the slide or rear doors
##    open; the slide door's rail runs along the right flank.
##  - `roof` (over them): the upright windscreen in tinted glass, then one tall, flat roof over cab and cargo alike,
##    stiffened by ribs across it with a vent on top: no side or back windows behind the cab. And the lamps.
## Painted in the vehicle's frame through vehicle_art.gd; geometry from the van's `VehicleConfig.kinds` and `looks` rows.

const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")

const _FLOOR := 1  ## Heights of the parts (the canvas height layer), floor up.
const _BODY := 5
const _PILLAR := 10
const _ROOF := 12
const _RIB_GAP := 17.0  ## px between the roof's ribs.


## Paint the van's `opts.part` (`chassis` / `roof`) onto `c` in `base` paint, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var kind: StringName = opts.get("kind", &"van")
	var row: Dictionary = VehicleConfig.kinds[kind]
	var look: Dictionary = VehicleConfig.looks[kind]
	var k := Art.scale(c, (row["size"] as Vector2).x)
	if opts.get("part", "chassis") == "roof":
		_roof(c, base, kind, row, look, k)
	else:
		_chassis(c, base, row, look, k)
	# No cast shadows: a body is repainted for every lighting step it turns through, and on a canvas this size they cost
	# more than the rest of the painting together. Its raised parts are shaded by their bevels instead.


## The body, the nose and bumpers, the cab and the cargo bay.
static func _chassis(c: PixelCanvas, base: Color, row: Dictionary, look: Dictionary, k: float) -> void:
	var t := PixelCanvas.tones(base)
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var trim := VehicleConfig.trim_color
	var bumper: float = look["bumper"]
	var bonnet: float = look["bonnet"]
	var belt: float = look["belt"]
	var body := PixelCanvas.rounded(Art.box(c, -half.x, half.x, -half.y, half.y, k), roundi(float(row["corner"]) * k))
	c.fill(body, base, _BODY)
	c.bevel(body, 1, 2, t["highlight"], t["dark"])
	# Bumpers: a deep one at the nose, one at the tail with a step plate in its middle.
	var nose := PixelCanvas.rounded(Art.box(c, half.x - bumper, half.x, -half.y + 3.0, half.y - 3.0, k), roundi(3 * k))
	c.fill(nose, trim, _BODY - 1)
	c.bevel(nose, 1, 1, trim.lightened(0.18), trim.darkened(0.3))
	var tail := PixelCanvas.rounded(Art.box(c, -half.x, -half.x + bumper - 2.0, -half.y + 3.0, half.y - 3.0, k), roundi(2 * k))
	c.fill(tail, trim, _BODY - 1)
	var step := PixelCanvas.rounded(Art.box(c, -half.x - 0.5, -half.x + bumper, -20.0, 20.0, k), roundi(1 * k))
	c.fill(step, trim.lightened(0.22), _BODY)
	for i in 4:
		var y := -15.0 + i * 10.0
		c.line(Art.at(c, Vector2(-half.x + 1.0, y), k), Art.at(c, Vector2(-half.x + bumper - 1.0, y), k), trim)
	# The snub nose: a wide grille of slats between the headlights, the bonnet's shut line, a sheen.
	var head: Vector2 = look["head"]
	var grille := PixelCanvas.rounded(Art.box(c, half.x - bumper - 9.0, half.x - bumper, -head.x + 4.0, head.x - 4.0, k), roundi(1 * k))
	c.fill(grille, trim, _BODY)
	for i in 4:
		var x := half.x - bumper - 1.5 - i * 2.0
		c.line(Art.at(c, Vector2(x, -head.x + 6.0), k), Art.at(c, Vector2(x, head.x - 6.0), k), trim.lightened(0.18))
	c.line(Art.at(c, Vector2(bonnet + 1.0, -belt + 2.0), k), Art.at(c, Vector2(bonnet + 1.0, belt - 2.0), k), t["shadow"])
	c.glare(PixelCanvas.rounded(Art.box(c, bonnet + 2.0, half.x - bumper - 10.0, -half.y + 6.0, half.y - 6.0, k), roundi(3 * k)),
		base.lightened(0.3), 1)
	# The cab: floor, dashboard and wheel, the engine cover between the seats, the seats; the bulkhead behind them.
	var seats: Dictionary = row["seats"]
	var driver: Vector2 = seats[&"driver"]
	var bulkhead: float = (look["pillars"][0] as Vector2).y
	var cab := PixelCanvas.rounded(Art.box(c, bulkhead, bonnet, -belt, belt, k), roundi(3 * k))
	c.fill(cab, VehicleConfig.interior_color, _FLOOR)
	c.surface(cab, "fabric", VehicleConfig.interior_color)
	Art.dashboard(c, look["dash"], belt - 1.0, look["wheel"], driver, k)
	var cover := PixelCanvas.rounded(Art.box(c, driver.x - 14.0, (look["dash"] as Vector2).x, -9.0, 9.0, k), roundi(3 * k))
	c.fill(cover, trim.lightened(0.1), 3)
	c.bevel(cover, 1, 1, trim.lightened(0.28), trim.darkened(0.3))
	var wall := PixelCanvas.rounded(Art.box(c, bulkhead - 4.0, bulkhead, -belt, belt, k), 0)
	c.fill(wall, base.darkened(0.25), 6)
	# The cargo bay: a plywood floor with tie-down rails along it.
	var wood := VehicleConfig.cargo_floor_color
	var bay := PixelCanvas.rounded(Art.box(c, -half.x + bumper - 2.0, bulkhead - 4.0, -belt, belt, k), roundi(2 * k))
	c.fill(bay, wood, _FLOOR)
	c.speckle(bay.bounds, wood, 0.06, 0.06)
	# Plywood sheets laid across, and the tie-down rails along.
	var sheet := -half.x + bumper + 30.0
	while sheet < bulkhead - 8.0:
		c.line(Art.at(c, Vector2(sheet, -belt + 1.0), k), Art.at(c, Vector2(sheet, belt - 1.0), k), wood.darkened(0.18))
		sheet += 30.0
	for y in [-belt + 4.0, -14.0, 14.0, belt - 4.0]:
		c.line(Art.at(c, Vector2(-half.x + bumper, y), k), Art.at(c, Vector2(bulkhead - 6.0, y), k), wood.darkened(0.35))
	Art.sills(c, row["doors"], belt, k)
	Art.seats(c, seats, k, driver.x - 20.0)
	# The slide door's rail along the right flank, behind its opening.
	for def: Dictionary in row["doors"]:
		if def["kind"] == &"slide":
			var rail_y := signf((def["hinge"] as Vector2).y) * (half.y - 1.5)
			var front: float = (def["hinge"] as Vector2).x - float(def["length"])
			c.line(Art.at(c, Vector2(front - float(def["length"]) + 2.0, rail_y), k), Art.at(c, Vector2(front, rail_y), k), t["outline"])


## The upright windscreen, the one tall roof with its ribs and vent, and the lamps.
static func _roof(c: PixelCanvas, base: Color, kind: StringName, row: Dictionary, look: Dictionary, k: float) -> void:
	var t := PixelCanvas.tones(base)
	var roof: Vector2 = look["roof"]
	var roof_half: float = look["roof_half"]
	var belt: float = look["belt"]
	var bonnet: float = look["bonnet"]
	var boot: float = look["boot"]
	var screen_half: float = look["screen_half"]
	var frame := PixelCanvas.rounded(Art.box(c, boot - 3.0, bonnet, -belt, belt, k), roundi(3 * k))
	c.fill(frame, base, _PILLAR)
	c.bevel(frame, 1, 1, t["light"], t["shadow"])
	Art.clear_door_glass(c, kind, row, look, k)
	var windscreen := Art.region(c, roof.x, bonnet, -screen_half, screen_half, k, "van_screen/%s" % kind, func(p: Vector2) -> bool:
		return absf(p.y) <= Art.screen_edge(look, p.x) - 1.0 and p.x <= bonnet - 1.0)
	c.fill(windscreen, VehicleConfig.glass_color, _PILLAR - 1)
	c.glare(windscreen, Color(VehicleConfig.glass_color.lightened(0.55), 0.6), 3)
	c.outline(windscreen, VehicleConfig.trim_color)
	# The roof, square-edged and flat, a little paler than the body, ribbed across.
	var panel := PixelCanvas.rounded(Art.box(c, boot - 2.0, roof.x, -roof_half, roof_half, k), roundi(4 * k))
	c.fill(panel, t["light"], _ROOF)
	c.bevel(panel, 1, 2, t["highlight"], t["dark"])
	var x := roof.x - 10.0
	while x > boot + 6.0:
		c.line(Art.at(c, Vector2(x, -roof_half + 4.0), k), Art.at(c, Vector2(x, roof_half - 4.0), k), t["highlight"])
		c.line(Art.at(c, Vector2(x - 1.0, -roof_half + 4.0), k), Art.at(c, Vector2(x - 1.0, roof_half - 4.0), k), t["dark"])
		x -= _RIB_GAP
	var vent := PixelCanvas.rounded(Art.box(c, -78.0, -60.0, -9.0, 9.0, k), roundi(2 * k))
	c.fill(vent, t["base"].darkened(0.08), _ROOF + 2)
	c.bevel(vent, 1, 1, t["highlight"], t["shadow"])
	c.outline(vent, t["outline"])
	for i in 3:
		var vx := -74.0 + i * 5.0
		c.line(Art.at(c, Vector2(vx, -6.0), k), Art.at(c, Vector2(vx, 6.0), k), t["shadow"])
	c.outline(panel, t["shadow"])
	_lamps(c, row, look, k)


## Headlights at the nose's corners; tail lights standing up the back corners (dark until lit by the visuals).
static func _lamps(c: PixelCanvas, row: Dictionary, look: Dictionary, k: float) -> void:
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var length: float = look["lamp"]
	var head: Vector2 = look["head"]
	for r in Art.both(c, half.x - length - 2.0, half.x - 1.0, head.x, head.y, k):
		var lamp := PixelCanvas.rounded(r, roundi(1 * k))
		c.fill(lamp, VehicleConfig.headlight_color, _BODY + 1)
		c.bevel(lamp, 1, 1, Color.WHITE, VehicleConfig.headlight_color.darkened(0.3))
		c.outline(lamp, VehicleConfig.trim_color)
	for rect: Rect2 in Art.tail_lamps(row, look):
		var lamp := PixelCanvas.rounded(Art.box(c, rect.position.x, rect.end.x, rect.position.y, rect.end.y, k), roundi(1 * k))
		c.fill(lamp, VehicleConfig.tail_off_color, _ROOF)
		c.outline(lamp, VehicleConfig.trim_color)
