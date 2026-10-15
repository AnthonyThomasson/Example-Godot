extends RefCounted

## What the gun and grenade painters share (Items domain, private): the looks they draw by handle, the guns' two silhouettes
## (held seen from above, and lying on the side) and the grenades' shell, cap and lever, on a PixelCanvas. A weapon style's
## painter (police_gun_painter.gd, scrap_gun_painter.gd, pipe_gun_painter.gd and the three grenade ones) lays its silhouette
## through here and adds its own marks.
##
## A painter's options carry the look (a `looks` row of `GunConfig` / `GrenadeConfig`: its colours) as an int handle
## (`opts.look`, from `register`), never the row itself: PixelArt keys its caches by the options (`render_turned` hashes them on
## every call). The handle is the row's hash, so the same colours always have the same one and a cached texture keyed by it is
## always that look's.
##
## Held, a gun is drawn in the game's top-down frame (muzzle toward +y, butt at y = 0) and scales its parts from `c.w` / `c.h`, so
## the raised barrel's shorter canvas is the same drawing foreshortened. Lying, it is its side profile along y: the receiver along
## the top edge, the grip, magazine and stock hanging off toward the far edge, `flip` mirroring it. A `crude` silhouette (the
## pipe guns) is a short box action with a pipe for the barrel and no guard.

## Heights for cast shadows.
const STOCK_HEIGHT := 3
const BODY_HEIGHT := 5
const GUARD_HEIGHT := 4
const BARREL_HEIGHT := 3
const FLAT_HEIGHT := 3
const FUZE_HEIGHT := 6
const LEVER_HEIGHT := 6
## The muzzle's bore.
const MUZZLE := Color(0.05, 0.05, 0.06)
## The order the held parts are drawn in, and each one's height.
const HELD_PARTS := { "grip": STOCK_HEIGHT, "stock": STOCK_HEIGHT, "body": BODY_HEIGHT, "guard": GUARD_HEIGHT,
	"barrel": BARREL_HEIGHT }

## The looks by handle.
static var _looks := {}


## The handle of `look`, registered for `look_of`.
static func register(look: Dictionary) -> int:
	var id := hash(look)
	_looks[id] = look
	return id


## The look a painter's `opts` name (`opts.look`), or {} for none.
static func look_of(opts: Dictionary) -> Dictionary:
	return _looks.get(opts.get("look", 0), {})


# --- Guns held, seen from above -----------------------------------------------------------------

## The parts of `gun` as held (part -> its rect, butt to muzzle): a pistol's `grip` and `body` (the slide); a long gun's `stock`,
## `body` (the receiver), `guard` and `barrel`. `crude`: a box action and a pipe for the barrel (a zip pistol, a pipe gun).
static func held_parts(c: PixelCanvas, gun: StringName, crude: bool) -> Dictionary:
	var w := c.w
	var h := c.h
	var cx := int(w / 2.0)
	var parts := {}
	match gun:
		&"pistol":
			var g := maxi(3, int(h / 4.0))
			parts["grip"] = Rect2i(1, 0, w - 2, g + 1)
			if crude:
				var box_end := maxi(g + 3, int(h * 0.55))
				parts["body"] = Rect2i(0, g - 1, w, box_end - g + 1)
				parts["barrel"] = Rect2i(cx - 1, box_end - 1, 3, h - box_end + 1)
			else:
				parts["body"] = Rect2i(0, g - 1, w, h - g + 1)
		&"smg":
			var s := maxi(2, int(h * 24 / 100.0))
			var b := maxi(s + 3, int(h * 62 / 100.0))
			parts["stock"] = Rect2i(0, 0, w, s + 1) if crude else Rect2i(1, 0, w - 2, s + 1)
			parts["body"] = Rect2i(0, s - 1, w, b - s + 2)
			if crude:
				parts["barrel"] = Rect2i(cx - 1, b - 1, 3, h - b + 1)
			else:
				var r := maxi(b, int(h * 86 / 100.0))
				parts["guard"] = Rect2i(1, b - 1, w - 2, r - b + 2)
				parts["barrel"] = Rect2i(cx - 1, r, 2, h - r)
		_:
			var s := maxi(3, int(h * 26 / 100.0))
			var b := maxi(s + 3, int(h * 50 / 100.0))
			parts["stock"] = Rect2i(0, 0, w, s + 1)
			parts["body"] = Rect2i(0, s - 1, w, b - s + 2)
			if crude:
				parts["barrel"] = Rect2i(cx - 1, b - 1, 3, h - b + 1)
			else:
				var r := maxi(b + 3, int(h * 80 / 100.0))
				parts["guard"] = Rect2i(1, b - 1, w - 2, r - b + 2)
				parts["barrel"] = Rect2i(cx - 1, r, 2, h - r)
	return parts


## Fill, shade and outline the held `parts` in the look's colours (each part its own: `grip`, `stock`, `body`, `guard`,
## `barrel`), the receiver in the look's `finish`, the stock in wood grain when `wood_stock`; the receiver's lit top rail and its
## ejection port.
static func draw_held(c: PixelCanvas, look: Dictionary, parts: Dictionary, wood_stock: bool) -> void:
	var cx := int(c.w / 2.0)
	for part: String in HELD_PARTS:
		if not parts.has(part):
			continue
		var rect: Rect2i = parts[part]
		var col: Color = look[part]
		var shape := PixelCanvas.rounded(rect, 0 if part == "barrel" and rect.size.x < 3 else 1)
		var t := PixelCanvas.tones(col)
		c.fill(shape, col, HELD_PARTS[part])
		if part == "body":
			c.surface(shape, look.get("finish", "metal"), col, false)
		elif part == "stock" and wood_stock:
			c.surface(shape, "wood", col, false)
		if rect.size.x >= 3:
			c.bevel(shape, 1, 1, t.light, t.dark)
		c.outline(shape, t.outline)
		if part == "body":
			c.line(Vector2i(cx, rect.position.y + 2), Vector2i(cx, rect.end.y - 2), t.highlight)
			var port := rect.position.y + int(rect.size.y / 3.0)
			c.line(Vector2i(mini(cx + 1, c.w - 2), port), Vector2i(mini(cx + 1, c.w - 2), port + 1), t.outline)


## The muzzle's bore at the held gun's front end.
static func held_muzzle(c: PixelCanvas) -> void:
	var cx := int(c.w / 2.0)
	for x in range(cx - 1, cx + 1):
		if c.covered(x, c.h - 1):
			c.px(x, c.h - 1, MUZZLE)


# --- Guns lying on the side ---------------------------------------------------------------------

## The side profile of `gun` on a `c` canvas (px along y): `bw` the receiver's thickness, `stock_end` where the stock ends (-1:
## none), `body_end` the receiver's end, `guard_end` the guard's, `grip_top` / `grip_len` the grip, `mag_top` / `mag_len` /
## `mag_curve` the magazine (none for a pistol). `crude`: a short box action, the pipe from there to the muzzle.
static func flat_profile(c: PixelCanvas, gun: StringName, crude: bool) -> Dictionary:
	var h := c.h
	var p := { "bw": 3, "stock_end": -1, "body_end": h - 1, "guard_end": h - 1, "grip_top": 1, "grip_len": int(h * 2 / 5.0),
		"mag_top": -1, "mag_len": 0, "mag_curve": 0.0 }
	match gun:
		&"smg":
			p["bw"] = 4
			p["stock_end"] = maxi(3, int(h * 22 / 100.0))
			p["body_end"] = maxi(p["stock_end"] + 4, int(h * 60 / 100.0))
			p["guard_end"] = maxi(p["body_end"] + 2, int(h * 84 / 100.0))
			p["grip_top"] = p["stock_end"]
			p["grip_len"] = maxi(3, int(h / 6.0))
			p["mag_top"] = p["stock_end"] + p["grip_len"] + 1
			p["mag_len"] = int(h * 27 / 100.0)
		&"rifle":
			p["bw"] = maxi(3, int(c.w * 3 / 8.0))
			p["stock_end"] = maxi(4, int(h * 26 / 100.0))
			p["body_end"] = maxi(p["stock_end"] + 4, int(h * 54 / 100.0))
			p["guard_end"] = maxi(p["body_end"] + 3, int(h * 82 / 100.0))
			p["grip_top"] = p["stock_end"] - 3
			p["grip_len"] = maxi(3, int(h / 8.0))
			p["mag_top"] = p["stock_end"] + int((p["body_end"] - p["stock_end"]) / 2.0)
			p["mag_len"] = maxi(4, int(h / 5.0))
			p["mag_curve"] = 0.9
	if crude:
		p["body_end"] = mini(p["body_end"], maxi(p["stock_end"] + 4, int(h * (0.5 if gun == &"pistol" else 0.42))))
		p["guard_end"] = p["body_end"]
	return p


## Draw `gun` lying on its side in the look's colours along profile `p` (`flat_profile`), mirrored by `mx` (a local column to the
## canvas's): the magazine (`magazine`, curving forward on the rifle), the grip raked back (and a pistol's trigger guard), the
## stock (a wire frame on an SMG unless `crude`, in wood grain when `wood_stock`), the receiver and guard along the top edge, the
## barrel (a thin post, or the pipe as thick as a `crude` action), the sights and the bore. `wood_grip`: the grip in grain.
static func draw_flat(c: PixelCanvas, look: Dictionary, gun: StringName, p: Dictionary, mx: Callable, crude: bool,
		wood_stock: bool, wood_grip: bool) -> void:
	var h := c.h
	var bw: int = p["bw"]
	var stock_end: int = p["stock_end"]
	var body_end: int = p["body_end"]
	var guard_end: int = p["guard_end"]
	var below := bw + 1  # The first column under the receiver.
	var tones := PixelCanvas.tones((look["body"] as Color).lightened(0.1))
	var everywhere := Rect2i(0, 0, c.w, h)
	if p["mag_len"] > 0:
		var mag_col: Color = look.get("magazine", look["grip"])
		var mag_top: int = p["mag_top"]
		var mag_end: int = mag_top + int(p["mag_len"])
		var curve_k: float = p["mag_curve"]
		var mag := PixelCanvas.Shape.new(everywhere, func(x: int, y: int) -> bool:
			var drop: int = mx.call(x) - below
			if drop < -1 or drop > 3:
				return false
			var curve := int(float(maxi(drop, 0)) * curve_k)
			return y >= mag_top + curve and y <= mag_end + curve)
		c.fill(mag, mag_col, FLAT_HEIGHT)
		c.outline(mag, mag_col.darkened(0.6))
	var grip_col: Color = look["grip"]
	var grip_top: int = p["grip_top"]
	var grip_len: int = p["grip_len"]
	var grip_far := c.w - 1 if gun == &"pistol" else below + 1
	var grip := PixelCanvas.Shape.new(everywhere, func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		if lx < below - 1 or lx > grip_far:
			return false
		var rake := float(lx - below) * 0.6
		return y >= grip_top - rake and y <= grip_top + grip_len - rake)
	c.fill(grip, grip_col, FLAT_HEIGHT - 1)
	if wood_grip:
		c.surface(grip, "wood", grip_col, false)
	c.outline(grip, grip_col.darkened(0.6))
	if gun == &"pistol":  # The trigger guard just ahead of the grip.
		var gy := grip_top + grip_len + 1
		for lx in range(below, below + 3):
			c.px(mx.call(lx), gy + 3, tones.outline, FLAT_HEIGHT - 1)
		c.line(Vector2i(mx.call(below + 2), gy), Vector2i(mx.call(below + 2), gy + 3), tones.outline, FLAT_HEIGHT - 1)
	if stock_end > 0:
		var stock_col: Color = look["stock"]
		var thick := bw + (2 if crude else 1)
		var frame: bool = gun == &"smg" and not crude
		var stock := PixelCanvas.Shape.new(everywhere, func(x: int, y: int) -> bool:
			var lx: int = mx.call(x)
			if y < 0 or y > stock_end or lx < 0 or lx >= thick:
				return false
			return not frame or lx <= 1 or lx >= thick - 2 or y <= 1)
		c.fill(stock, stock_col, FLAT_HEIGHT)
		if wood_stock:
			c.surface(stock, "wood", stock_col, false)
		c.outline(stock, stock_col.darkened(0.6))
	var body_col: Color = (look["body"] as Color).lightened(0.1)  # Its broad side faces up, catching more light.
	var from := stock_end - 1 if stock_end > 0 else 0
	var body := PixelCanvas.Shape.new(everywhere, func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		if y >= from and y <= body_end:
			return lx >= 1 and lx <= bw
		if y > body_end and y <= guard_end:
			return lx >= 1 and lx <= bw - 1
		return false)
	c.fill(body, body_col, FLAT_HEIGHT + 1)
	c.surface(body, look.get("finish", "metal"), body_col, false)
	c.bevel(body, 1, 1, tones.light, tones.dark)
	c.outline(body, tones.outline)
	for y in range(body_end + 1, guard_end):  # The guard in its own colour.
		for lx in range(2, bw):
			c.px(mx.call(lx), y, look["guard"], FLAT_HEIGHT + 1)
	var barrel_col: Color = look["barrel"]
	for y in range(guard_end + 1, h):
		if crude:
			for lx in range(1, bw):
				c.px(mx.call(lx), y, barrel_col if lx > 1 else barrel_col.lightened(0.2), FLAT_HEIGHT + 1)
			c.px(mx.call(0), y, barrel_col.darkened(0.5), FLAT_HEIGHT + 1)
			c.px(mx.call(bw), y, barrel_col.darkened(0.5), FLAT_HEIGHT + 1)
		else:
			c.px(mx.call(2), y, barrel_col, FLAT_HEIGHT + 1)
	c.px(mx.call(0), 1, tones.outline, FLAT_HEIGHT + 1)  # Rear sight.
	c.px(mx.call(0), maxi(guard_end - 1, 2), tones.outline, FLAT_HEIGHT + 1)  # Front sight.
	for lx in range(1, bw if crude else 3):  # The bore.
		if c.covered(mx.call(lx), h - 1):
			c.px(mx.call(lx), h - 1, MUZZLE)


## The mirror a lying gun is drawn through: a local column to the canvas's, across when `flip`.
static func mirror(c: PixelCanvas, flip: bool) -> Callable:
	var w := c.w
	return func(x: int) -> int: return w - 1 - x if flip else x


# --- Grenades -----------------------------------------------------------------------------------

## A grenade's shell in the look's `shell` colour and `finish`, the fuze end toward +y, leaving `cap_len` px for the fuze or cap:
## an egg (`egg`) or a cylinder inset `inset` px each side. Returns the shell's tones.
static func shell(c: PixelCanvas, look: Dictionary, cap_len: int, egg: bool, inset := 0) -> Dictionary:
	var col: Color = look["shell"]
	var t := PixelCanvas.tones(col)
	var body := PixelCanvas.ellipse(Rect2i(0, 0, c.w, c.h - cap_len + 2)) if egg \
		else PixelCanvas.rounded(Rect2i(inset, 0, c.w - inset * 2, c.h - cap_len + 1), 1)
	c.fill(body, col, BODY_HEIGHT)
	c.surface(body, look.get("finish", "metal"), col, false)
	c.bevel(body, 1, 1, t.light, t.dark)
	c.outline(body, t.outline)
	return t


## The fuze or cap in the look's `cap` colour over `rect`.
static func cap(c: PixelCanvas, look: Dictionary, rect: Rect2i) -> void:
	var col: Color = look["cap"]
	var shape := PixelCanvas.rounded(rect, 1)
	c.fill(shape, col, FUZE_HEIGHT)
	c.bevel(shape, 1, 1, col.lightened(0.2), col.darkened(0.3))
	c.outline(shape, col.darkened(0.6))


## The safety lever held down along the shell (a grenade in the hand) in the look's `lever` colour: down a stun's right edge,
## or a frag's (`frag`), bending in to its fuze.
static func lever(c: PixelCanvas, look: Dictionary, frag: bool) -> void:
	var col: Color = look["lever"]
	for y in range(3 if frag else 2, c.h - 1):
		c.px((c.w - 2 if y < c.h - 3 else c.w - 3) if frag else c.w - 1, y, col, LEVER_HEIGHT)
	c.px(c.w - 3 if frag else c.w - 1, c.h - 1, col.darkened(0.5), LEVER_HEIGHT)


# --- Marks --------------------------------------------------------------------------------------

## Set (x, y) to `col` only where something is drawn.
static func over(c: PixelCanvas, x: int, y: int, col: Color, height := -1) -> void:
	if c.covered(x, y):
		c.px(x, y, col, height)


## `rows` rows across the whole width from `y`, only over what is drawn, every third pixel a shade darker (a band, tape).
static func band(c: PixelCanvas, y: int, col: Color, height: int, rows := 1) -> void:
	for yy in range(y, y + rows):
		for x in c.w:
			over(c, x, yy, col if x % 3 != 2 else col.darkened(0.15), height)


## `count` specks over what is drawn in `r` (rust, seeded by the canvas), every other one darker.
static func specks(c: PixelCanvas, r: Rect2i, col: Color, count: int) -> void:
	for k in count:
		var p := Vector2i(c.rng.randi_range(r.position.x, maxi(r.end.x - 1, r.position.x)),
			c.rng.randi_range(r.position.y, maxi(r.end.y - 1, r.position.y)))
		over(c, p.x, p.y, col if k % 2 == 0 else col.darkened(0.25))
