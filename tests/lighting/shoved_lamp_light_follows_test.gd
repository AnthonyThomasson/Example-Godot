extends GameTest

## R10 (ticket #61): a shoved lamp's light moves with it. A lamp is shoved across the room (the pushable contract's
## `apply_impulse`): while it slides and once it rests, each of its lights stays where it was in the lamp's own frame, and is
## still one of the lighting's lights.
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting`
## with `lights()`; the lamp's `get_lights()`.

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const LAMP_AT := Vector2(250, 300)
const SHOVE := Vector2(900, 120)
const MOVED := 40.0  ## px the shove must carry the lamp, so the light has somewhere to follow it to.
const KEEP := 0.5  ## px a light may stray from its place on the lamp.


func describe() -> Dictionary:
	return {
		"name": "A shoved lamp's light moves with it",
		"description": "A lamp shoved across the room keeps each of its lights at the same place in its own frame, while it slides and at rest.",
		"tags": ["lighting"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.object(&"lamp", "lamp", LAMP_AT, { "neon": "" })


func run(t: TestContext) -> void:
	var lamp: RigidBody2D = t.object(&"lamp")
	t.check(not Probe.declared(lamp).is_empty(), "the lamp declares its light (get_lights())")
	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	var lights := Probe.lights_of(lighting, lamp)
	if not t.require(not lights.is_empty(), "the lamp has its light (a PointLight2D under it)"):
		return
	var offsets := {}
	for l: PointLight2D in lights:
		offsets[l] = lamp.global_transform.affine_inverse() * l.global_position

	lamp.apply_impulse(SHOVE)
	for _i in 30:
		await t.frames(2)
		_check_follow(t, lamp, offsets, "while it slides")
	await t.seconds(1.0)
	var moved := lamp.global_position.distance_to(LAMP_AT)
	t.trace("lamp moved", moved)
	if not t.require(moved >= MOVED, "the shove carries the lamp at least %.0f px (%.1f)" % [MOVED, moved]):
		return
	_check_follow(t, lamp, offsets, "at rest")
	var now: Array = lighting.lights()
	for l: PointLight2D in offsets:
		t.check(now.has(l), "%s is still one of the lighting's lights" % l.name)


## Check that each light in `offsets` (light -> its point in the lamp's frame) is still there.
func _check_follow(t: TestContext, lamp: Node2D, offsets: Dictionary, when: String) -> void:
	for l: PointLight2D in offsets:
		var want: Vector2 = lamp.global_transform * (offsets[l] as Vector2)
		var off := l.global_position.distance_to(want)
		if off > KEEP:
			t.check(false, "the lamp's light %s follows it %s (%.1f px off, lamp at %s)" % [l.name, when, off, lamp.global_position.round()])
			return
