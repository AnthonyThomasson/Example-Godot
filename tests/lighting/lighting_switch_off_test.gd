extends GameTest

## R10 (ticket #61): the behaviour switch `lighting.enabled` (default on) turned off builds none of the lighting. In a room with
## a lamp, a neon tube, an armchair and a puppet that fires a shot: no WorldLighting, no ambient CanvasModulate, no sky
## DirectionalLight2D, no PointLight2D (none lit by the shot either) and no LightOccluder2D (not on the walls, the pieces nor
## the character) anywhere under the world.
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` (group `world_lighting`); the switch is the `lighting.enabled` row
## of the Testing domain's switch table (`LightingConfig.enabled` and `LightMasks.shadows`).

const Probe := preload("res://tests/_lighting/lighting_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "lighting.enabled off builds no lighting",
		"description": "With the switch off, no WorldLighting, ambient, sky light, point light or occluder is under the world, even after a shot.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"lighting.enabled", false)
	s.object(&"lamp", "lamp", Vector2(450, 150), { "neon": "" })
	s.object(&"tube", "neon_tube", Vector2(450, 400))
	s.object(&"armchair", "armchair", Vector2(650, 300), { "neon": "" })
	s.actor(&"gunner", &"puppet", Vector2(200, 300), { "start_slot": 3 })


func run(t: TestContext) -> void:
	var gunner := t.puppet(&"gunner")
	gunner.aim_at(Vector2(880, 300))
	await t.seconds(0.4)
	gunner.shoot()
	if not t.require(await t.until(func() -> bool: return t.happened(&"shot"), 1.0), "the pistol fires (a shot event)"):
		return
	await t.frames(1)
	t.check(Probe.lighting(t) == null, "no WorldLighting is built")
	for type in ["CanvasModulate", "DirectionalLight2D", "PointLight2D", "LightOccluder2D"]:
		var found := Probe.under(t.world, type)
		t.check(found.is_empty(), "no %s is built (%s)" % [type, found.map(func(n: Node) -> String: return String(t.world.get_path_to(n)))])
