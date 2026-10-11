extends GameTest

## Harness self-test, first of an ordered pair: overrides a static var for this test only.
## static_restore_b_test then checks it came back.


func describe() -> Dictionary:
	return { "name": "Static override applies (1/2)", "tags": ["harness", "statics"], "internal": true, "timeout": 3.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(BloodConfig, &"enabled", false)
	s.switch(&"physics.debris", false)


func run(t: TestContext) -> void:
	await t.frames(2)
	t.check(not BloodConfig.enabled, "BloodConfig.enabled is overridden off")
	t.check(not PhysicsConfig.debris_enabled, "the debris switch turned its static off")
