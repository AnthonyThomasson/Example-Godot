extends RefCounted

## Vehicles domain: a vehicle's door, top-down pixel art (rendered through Art, `PixelArt.render_turned`). `opts.kind` and
## `opts.door` name it (its `VehicleConfig.kinds` row entry); `opts.part` is which piece:
##  - `panel`: the door seen from above as it swings, in its own canonical frame (front, +y, toward the hinge along it;
##    across it its thickness, the outside on the `vehicle_art.door_frame` `outer` side): the painted skin with its handle,
##    the black belt moulding, the top of the frame, and the trim on the inside (an armrest along it), which shows once
##    it is open; shut lines at both ends. A sliding door carries its rail groove, a rear door a hinge strap.
##  - `glass`: its side window, a strip of tinted glass between the belt line and the roof, in the vehicle's canonical frame
##    (as the body is), so it stays put and fades as the door opens.
##  - `mirror`: the wing mirror on a front door, standing out from it near the hinge.

const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")

const _HEIGHT := 5  ## Heights (for cast shadows).
const _GLASS := 8


## Paint the `opts.part` (`panel` / `glass` / `mirror`) of the door `opts.door` of an `opts.kind` vehicle onto `c` in `base` paint.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var kind: StringName = opts.get("kind", &"car")
	var def := door_def(kind, opts.get("door", &""))
	if def.is_empty():
		return
	match opts.get("part", "panel"):
		"glass":
			_glass(c, kind, def)
		"mirror":
			_mirror(c, base)
		_:
			_panel(c, base, def, Art.door_frame(def)["outer"])


## Door `id` of `kind` (its kinds-row entry), or {}.
static func door_def(kind: StringName, id: StringName) -> Dictionary:
	for def: Dictionary in VehicleConfig.kinds[kind]["doors"]:
		if def["id"] == id:
			return def
	return {}


## The door from above: skin, moulding, frame, trim, handle and shut lines.
static func _panel(c: PixelCanvas, base: Color, def: Dictionary, outer: float) -> void:
	var t := PixelCanvas.tones(base)
	var trim := VehicleConfig.trim_color
	var inside := VehicleConfig.interior_color.lightened(0.08)
	# Column `i` px in from the outside face.
	var col := func(i: int) -> int: return c.w - 1 - i if outer > 0.0 else i
	var band := func(from: int, to: int) -> Rect2i:
		var a: int = col.call(from)
		var b: int = col.call(to - 1)
		return Rect2i(mini(a, b), 0, absi(b - a) + 1, c.h)
	var slab := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 1)
	c.fill(slab, t["dark"], _HEIGHT)
	var skin := PixelCanvas.rounded(band.call(0, 2), 0)
	c.fill(skin, base, _HEIGHT + 1)
	c.bevel(skin, 1, 1, t["highlight"], t["shadow"])
	c.fill(PixelCanvas.rounded(band.call(2, 3), 0), trim, _HEIGHT + 1)
	var lining := PixelCanvas.rounded(band.call(c.w - 2, c.w), 0)
	c.fill(lining, inside, _HEIGHT)
	# An armrest along the middle of the lining.
	var rest_col: int = col.call(c.w - 2)
	var rest := Rect2i(mini(rest_col, col.call(c.w - 1)), roundi(c.h * 0.35), 2, maxi(roundi(c.h * 0.3), 2))
	c.fill(PixelCanvas.rounded(rest, 0), inside.lightened(0.15), _HEIGHT + 1)
	# The handle, on the skin where it is pulled (a sliding door's near its front edge).
	var from_hinge := (def["handle"] as Vector2).distance_to(def["hinge"])
	var row := clampi(c.h - 1 - roundi(from_hinge) + (4 if from_hinge < c.h * 0.5 else 2), 2, c.h - 6)
	if def["kind"] == &"rear":
		row = clampi(roundi(c.h * 0.12), 2, c.h - 6)
	c.line(Vector2i(col.call(0), row), Vector2i(col.call(0), row + 3), trim)
	c.px(col.call(1), row + 1, t["highlight"])
	# Shut lines at both ends.
	c.line(Vector2i(0, 0), Vector2i(c.w - 1, 0), t["outline"])
	c.line(Vector2i(0, c.h - 1), Vector2i(c.w - 1, c.h - 1), t["outline"])
	match def["kind"]:
		&"slide":
			c.line(Vector2i(col.call(3), 2), Vector2i(col.call(3), c.h - 3), t["shadow"])  # the rail groove
		&"rear":
			for r in [c.h - 7, roundi(c.h * 0.55)]:  # hinge straps
				c.line(Vector2i(col.call(0), r), Vector2i(col.call(2), r), trim)
	c.cast_shadows()


## The side window: tinted glass with a glint and a black rubber round it, the shape of the door's glass (its front cut
## by the windscreen's pillar) in the strip from the roof out to the belt line (`glass_rect`).
static func _glass(c: PixelCanvas, kind: StringName, def: Dictionary) -> void:
	var row: Dictionary = VehicleConfig.kinds[kind]
	var look: Dictionary = VehicleConfig.looks[kind]
	var rect := glass_rect(kind, def["id"])
	var gaps := Art.door_glass(row, look, def["id"])
	var k := c.h / maxf(rect.size.x, 1.0)
	var centre := rect.get_center()
	var pane := Art.cached("door_glass/%s/%s|%d|%d" % [kind, def["id"], c.w, c.h], func() -> PixelCanvas.Shape:
		return Art.convex(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
			var p := Vector2(rect.position.x + (y + 0.5) / k, centre.y - (x + 0.5 - c.w * 0.5) / k)
			return Art.in_door_glass(gaps, look, p)))
	var glass := VehicleConfig.glass_color
	c.fill(pane, glass, _GLASS)
	c.glare(pane, Color(glass.lightened(0.55), 0.6), 1)
	c.outline(pane, VehicleConfig.trim_color)


## Where door `id`'s side glass lies (vehicle frame): its span along the body, from the roof out to the belt line on its
## side.
static func glass_rect(kind: StringName, id: StringName) -> Rect2:
	var look: Dictionary = VehicleConfig.looks[kind]
	var span: Vector2 = look["glass"][id]
	var side := signf((door_def(kind, id)["handle"] as Vector2).y)
	var inner: float = look["roof_half"]
	var outer: float = look["belt"]
	var y0 := inner if side > 0.0 else -outer
	return Rect2(span.x, y0, span.y - span.x, outer - inner)


## A wing mirror: a painted housing with the dark glass facing back.
static func _mirror(c: PixelCanvas, base: Color) -> void:
	var t := PixelCanvas.tones(base)
	var housing := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 2)
	c.fill(housing, base, _GLASS)
	c.bevel(housing, 1, 1, t["highlight"], t["shadow"])
	c.fill(PixelCanvas.rounded(Rect2i(1, 0, c.w - 2, 2), 0), VehicleConfig.glass_color.darkened(0.3), _GLASS)
	c.outline(housing, t["outline"])
