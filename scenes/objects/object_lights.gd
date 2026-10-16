extends RefCounted

## Objects domain (private): the lights a piece gives, its `get_lights()` declaration (read duck-typed by the Lighting
## domain, which gives each one a PointLight2D under the piece). What gives light is what the piece's painter draws
## glowing: a lamp's bulb, a screen's face (a TV, a desk's monitor, the den's monitor wall, the rig's halo, a cart's
## display), a neon tube, a server rack's LEDs, the scanner's beam, the hot ring, the surgeon's lamp, a street lamp's lens or
## sign, and a piece's neon trim. Each light is plain data, in the piece's own frame:
##   `offset` (Vector2) and `turn` (rad, the pool's long axis from +x), `colour`, `energy`, `radius` (px, out along the long
##   axis), `shape` (`round` / `wide` / `tube`), `rhythm` (`[[mode, weight], ...]`, the rhythms it may be drawn with),
##   `room_light` (it lights its room), `street` (it lights the street too: a street lamp), `height` (`overhead`: it hangs
##   or stands above the heads, a lamp's bulb, a street lamp's head; `low`: a screen, a tube, LEDs; which shadows it, and
##   whether it pools downward, is the Lighting domain's) and `glow` (the piece's `Emissive` overlay that shows the source,
##   dimming with the light; null when it has none).
## Tuning: ObjectArtConfig.light_specs (the per-kind numbers) and the painters' colours.

const Decay = preload("res://scenes/objects/art/decay.gd")


## The lights `piece` (an EnvironmentObject in the tree, its visuals ready) gives; [] for a piece that gives none.
static func of(piece: Node2D) -> Array:
	var kind := _kind(piece)
	if kind == "":
		return []
	var spec: Dictionary = ObjectArtConfig.light_specs.get(kind, {})
	if spec.is_empty():
		return []
	var opts: Dictionary = piece.art_opts
	var size: Vector2 = piece.size
	var ahead: Vector2 = (piece.facing as Vector2).normalized()
	if ahead == Vector2.ZERO:
		ahead = Vector2.DOWN
	var depth := absf(size.dot(ahead))
	var across := absf(size.dot(ahead.orthogonal()))
	var neon := Decay.neon(opts)
	var screen := neon if neon.a > 0.0 else ObjectArtConfig.decay_screen_color
	var spill := ahead.angle() + PI * 0.5  # A screen's pool lies across its front.
	var offset := ahead * (depth * 0.5 + float(spec["ahead"])) if spec.has("ahead") else Vector2.ZERO
	var turn := 0.0
	var radius := float(spec.get("radius", 0.0))
	var colour := screen
	var glow: CanvasItem = _overlay(piece.get_node_or_null("EnvironmentObjectVisuals"))
	var street := false
	match kind:
		"lamp":
			colour = neon if neon.a > 0.0 else ObjectArtConfig.lamp_glow_color
		"tv", "desk":
			turn = spill
		"monitor_wall":
			turn = spill
			radius = maxf(across * 0.85, radius)
		"server_rack":
			colour = neon if neon.a > 0.0 else ObjectArtConfig.tech_led_colors[-1]
		"surgical":
			colour = ObjectArtConfig.recliner_lamp_color
		"scanner":
			turn = ahead.angle()  # The beam runs out along the post's face.
			colour = ObjectArtConfig.security_beam_color
		"hotplate":
			colour = ObjectArtConfig.hotplate_ring_color
		"neon_tube":
			colour = Decay.neon({ "neon": opts.get("tone", "cyan") })
			turn = 0.0 if size.x >= size.y else PI * 0.5  # Along the tube.
			radius = maxf(size.x, size.y) * float(spec["tube_reach"])
		"cobra", "sign":
			var overhang := piece.get_node_or_null("Overhang")
			if overhang != null:
				offset = (overhang.get_rect() as Rect2).get_center()
				glow = _overlay(overhang)
			colour = ObjectArtConfig.streetlight_lens_color if kind == "cobra" \
				else (neon if neon.a > 0.0 else ObjectArtConfig.neon_magenta)
			street = true
		"trim":
			colour = neon
			radius += maxf(size.x, size.y) * 0.5
	return [{
		"offset": offset, "turn": turn, "colour": colour, "energy": float(spec["energy"]), "radius": radius,
		"shape": spec.get("shape", &"round"), "rhythm": spec.get("rhythm", []), "room_light": spec.get("room_light", false),
		"street": street, "height": spec.get("height", &"low"), "glow": glow,
	}]


## Which row of ObjectArtConfig.light_specs `piece` gives light by ("" for none): by its painter and options, or, for a piece
## with a neon option and no light of its own, its trim.
static func _kind(piece: Node2D) -> String:
	var art: String = piece.art
	var opts: Dictionary = piece.art_opts
	var neon := Decay.neon(opts).a > 0.0
	match art:
		"lamp":
			return "lamp"
		"appliance":
			if String(opts.get("panel", "")) == "tv":
				return "tv"
		"table":
			if (opts.get("props", []) as Array).any(func(p: Variant) -> bool: return p is Dictionary and p.get("kind", "") == "monitor"):
				return "desk"
		"tech":
			return String(opts.get("kind", "monitor_wall"))
		"recliner":
			return String(opts.get("kind", "rig"))
		"clinic":
			if String(opts.get("kind", "")) == "tool_cart":
				return "tool_cart"
		"security":
			if String(opts.get("kind", "")) == "scanner":
				return "scanner"
		"hotplate":
			return "hotplate"
		"decor":
			if String(opts.get("kind", "")) == "neon_tube":
				return "neon_tube"
			return ""
		"streetlight":
			return String(opts.get("head", ObjectArtConfig.streetlight_head))
	return "trim" if neon else ""


## The `Emissive` overlay of visuals node `visuals` (null without one).
static func _overlay(visuals: Node) -> CanvasItem:
	if visuals == null or not visuals.has_method(&"emissive_layer"):
		return null
	return visuals.call(&"emissive_layer") as CanvasItem
