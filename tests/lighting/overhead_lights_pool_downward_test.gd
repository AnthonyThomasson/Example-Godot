extends GameTest

## `docs/lighting.md` L2 and L3: every light has a height, and an overhead light shines down. In two rooms, one with a
## standing lamp, a TV, a street lamp and a neon street sign, the other bare (it gets a ceiling fixture):
## - each piece's declared light carries its `height`: `overhead` for the lamp, the street lamp and the sign, `low` for the TV;
## - every overhead light's pool (the fixture's too) is flat in the middle: still 0.9 of its centre's brightness at half its
##   radius; the low TV's glow falls off: under 0.7 there;
## - every light's pool (each piece's, the fixture's) falls off smoothly, without rings: no jump between 64 samples from its
##   centre to its rim of more than 0.08 of its centre's brightness;
## - a street lamp's and a sign's pool is tight under its head: at most 140 px in radius, centred within 4 px of the middle of
##   its `Overhang` (the head); the standing lamp's is 160 px in radius (within 10).
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting` with `lights()` and `fixtures()`,
## the pieces' `get_lights()` (`height`) and each light's texture (a radial GradientTexture2D).

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const LIT := Rect2(0, 0, 900, 600)
const BARE := Rect2(900, 0, 500, 600)


func describe() -> Dictionary:
	return {
		"name": "Overhead lights pool downward, low lights glow, both smooth",
		"description": "Lamps, street lamps, signs and fixtures declare or are overhead and light a flat pool (a street lamp's tight under its head); a TV is low and its glow falls off; every pool fades smoothly, without rings.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "lit", "type": "living_room", "rect": LIT },
		{ "key": "bare", "type": "kitchen", "rect": BARE },
	], [{ "pos": Vector2(900, 300), "width": 80.0 }])
	s.switch(&"nav.rebake", false)
	s.object(&"lamp", "lamp", Vector2(150, 150), { "neon": "" })
	s.object(&"tv", "tv", Vector2(450, 120), { "neon": "" })
	s.object(&"street_lamp", "streetlight", Vector2(200, 450), { "neon": "" })
	s.object(&"sign", "street_sign", Vector2(650, 450))


func run(t: TestContext) -> void:
	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	var heights := { &"lamp": "overhead", &"tv": "low", &"street_lamp": "overhead", &"sign": "overhead" }
	var overhead: Array = []  ## `[what, light]`
	for id: StringName in heights:
		var piece: Node2D = t.object(id)
		var declared := Probe.declared(piece)
		if not t.require(not declared.is_empty(), "the %s declares its light" % id):
			return
		var height := String((declared[0] as Dictionary).get("height", ""))
		t.check(height == heights[id], "the %s's light is %s (declares %s)" % [id, heights[id], "no height" if height == "" else height])
		var own := Probe.lights_of(lighting, piece)
		if not t.require(not own.is_empty(), "the %s has its light" % id):
			return
		var light: PointLight2D = own[0]
		var half := Probe.profile(light, 0.5)
		if heights[id] == "overhead":
			overhead.append([String(id), light])
		else:
			t.check(half >= 0.0 and half < Probe.LOW_HALF_MAX, "the %s's low glow falls off: %.2f of its centre at half its radius (under %.2f)" % [
				id, half, Probe.LOW_HALF_MAX])
	var fixtures: Array = lighting.fixtures()
	var bare := fixtures.filter(func(f: Dictionary) -> bool: return String(f["room"]) == "bare")
	if t.require(not bare.is_empty(), "the bare room has its ceiling fixture"):
		overhead.append(["fixture", bare[0]["light"]])

	var every: Array = overhead.duplicate()
	every.append(["tv", Probe.lights_of(lighting, t.object(&"tv"))[0]])
	for entry: Array in every:
		var step := Probe.largest_step(entry[1])
		t.check(step >= 0.0 and step <= Probe.SMOOTH_STEP_MAX, "the %s's pool fades smoothly: its largest step is %.2f of its centre (at most %.2f)" % [
			entry[0], step, Probe.SMOOTH_STEP_MAX])

	for entry: Array in overhead:
		var half := Probe.profile(entry[1], 0.5)
		t.check(half >= Probe.OVERHEAD_HALF_MIN, "the %s's overhead pool is flat: %.2f of its centre at half its radius (at least %.2f)" % [
			entry[0], half, Probe.OVERHEAD_HALF_MIN])

	var lamp_box := Probe.light_box(Probe.lights_of(lighting, t.object(&"lamp"))[0])
	var lamp_radius := maxf(lamp_box.size.x, lamp_box.size.y) * 0.5
	t.check(absf(lamp_radius - Probe.LAMP_POOL) <= Probe.LAMP_POOL_SLACK, "the lamp's pool is %.0f px in radius (%.0f)" % [
		Probe.LAMP_POOL, lamp_radius])

	for id: StringName in [&"street_lamp", &"sign"]:
		var piece: Node2D = t.object(id)
		var head := piece.find_child("Overhang", true, false) as CanvasItem
		if not t.require(head != null, "the %s has its head (Overhang)" % id):
			return
		var light: PointLight2D = Probe.lights_of(lighting, piece)[0]
		var box := Probe.light_box(light)
		var radius := maxf(box.size.x, box.size.y) * 0.5
		t.check(radius <= Probe.STREET_POOL_MAX, "the %s's pool is tight: %.0f px in radius (at most %.0f)" % [id, radius, Probe.STREET_POOL_MAX])
		var head_at: Vector2 = head.get_global_transform() * (head.get_rect() as Rect2).get_center()
		var off := light.global_position.distance_to(head_at)
		t.check(off <= Probe.STREET_POOL_CENTRE, "the %s's pool is under its head (%.1f px off)" % [id, off])
