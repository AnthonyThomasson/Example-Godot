extends GameTest

## R10 (ticket #61): the dusk. A generated house is tinted by one ambient CanvasModulate in the configured colour (the plan's
## blue-violet 0.40 / 0.37 / 0.55), and its street lit by the sky: DirectionalLight2Ds in the configured sky colour, shining
## from the south-west (toward +x, -y). Every sky light that reaches the street's floors is unshadowed, and one does; none
## reaches the rooms' floors (the house has a roof: a room is lit by the ambient, its fixture and its pieces).
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting`, `LightingConfig.ambient_color` and
## `LightingConfig.sky_color`. The ambient and the sky are plain Godot nodes under the world.

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const SEED := 4


func describe() -> Dictionary:
	return {
		"name": "Dusk: the ambient and the sky light",
		"description": "One CanvasModulate in the configured blue-violet; a sky light in the configured colour from the south-west, unshadowed on the street; none in the house.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var ambient_color: Color = LightingConfig.ambient_color
	var sky_color: Color = LightingConfig.sky_color
	t.check(ambient_color.is_equal_approx(Probe.AMBIENT), "the configured ambient is the plan's dusk %s (%s)" % [Probe.AMBIENT, ambient_color])
	if Probe.require_lighting(t) == null:
		return

	var ambients := Probe.under(t.world, "CanvasModulate")
	if t.require(ambients.size() == 1, "the world has one ambient CanvasModulate (%d)" % ambients.size()):
		var tint: Color = (ambients[0] as CanvasModulate).color
		t.check(tint.is_equal_approx(ambient_color), "the ambient is the configured colour %s (%s)" % [ambient_color, tint])

	var skies := Probe.under(t.world, "DirectionalLight2D")
	if not t.require(not skies.is_empty(), "the world has its sky light (a DirectionalLight2D)"):
		return
	var house: Node2D = t.world.house
	var street := {}
	for piece: Dictionary in WorldGen.get_street(house):
		street[piece["node"]] = true
	var floors := Probe.floors(house)
	var room_floors := floors.filter(func(f: Node) -> bool: return not street.has(f))
	var street_floors := floors.filter(func(f: Node) -> bool: return street.has(f))
	if not t.require(not room_floors.is_empty() and not street_floors.is_empty(), "the house has room floors and street floors (%d, %d)" % [
			room_floors.size(), street_floors.size()]):
		return
	var lights_rooms := false
	var lights_street := false
	for sky: DirectionalLight2D in skies:
		t.check(sky.color.is_equal_approx(sky_color), "the sky light %s is the configured colour %s (%s)" % [sky.name, sky_color, sky.color])
		var shine := sky.global_transform.y.normalized()  # A directional light shines along its +y.
		t.check(shine.x > 0.0 and shine.y < 0.0, "the sky light %s comes from the south-west (shines toward %s)" % [sky.name, shine])
		var on_rooms := room_floors.any(func(f: Node2D) -> bool: return sky.range_item_cull_mask & Probe.floor_mask(f) != 0)
		var on_street := street_floors.any(func(f: Node2D) -> bool: return sky.range_item_cull_mask & Probe.floor_mask(f) != 0)
		lights_rooms = lights_rooms or on_rooms
		lights_street = lights_street or on_street
		if on_street:
			t.check(not sky.shadow_enabled, "the sky light %s on the street is unshadowed" % sky.name)
		t.check(not on_rooms, "the sky light %s does not reach the rooms' floors (the house has a roof)" % sky.name)
	t.check(not lights_rooms, "no sky light reaches the rooms' floors")
	t.check(lights_street, "a sky light reaches the street's floors")
